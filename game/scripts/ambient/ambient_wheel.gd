class_name AmbientWheel
extends Node2D
## Water at a mill wheel (Директор 25.10 стр. 15: «мельница не реалистично воду скидывает да и входит»; 29.10 стр. 96:
## «анимации мельницы и воды — ничего не сделано»). Built from an ambient entry `wheel_water` (AmbientRoot), drawn in
## code over the painted wheel and water, every drop a short streak along its motion:
##   POUR    — on the rising side the buckets come up full and pour: drops leave each bucket lip with the lip's own
##             velocity (ω·r along the rim) and fall under gravity to the water line; a bucket pours most right after
##             it leaves the water and runs dry by `pour.to_deg`. The lips follow the real angle of the spinning room
##             layer (`layer`), so the streams turn with the paddles; while the wheel stands (pond let down) nothing pours.
##   ENTRY   — each time a paddle cuts into the water on the descending side: a burst of spray thrown up and back
##             (against the paddle's way) and a foam patch on the surface.
##   FOAM    — churned water under the wheel, carried with the current (`foam.drift_px_s`, the way the bottom paddles
##             go) and fading downstream.
##   SOURCES — fixed spouts (a painted wheel that does not turn — the epilogue picture): drops from points along a
##             segment with a given velocity.
##   LANDING — where a drop meets the water line: a small crown of spray.
## Units: screen px, s; gravity `gravity_px_s2`. All randomness from a seeded RNG (stable in tests).

var cfg: Dictionary = {}
var room: Node = null
var on: bool = true

var _rng := RandomNumberGenerator.new()
var _drops: Array = []      # [pos: Vector2, vel: Vector2, life: float, kind: int, w: float, a: float]
var _foam: Array = []       # [pos: Vector2, vel: Vector2, age: float, life: float, size: Vector2, a: float]
var _layer_img: Node2D = null
var _last_rot: float = NAN
var _own_rot: float = 0.0
var _pour_acc: Dictionary = {}   # bucket index → fractional drops owed
var _src_acc: Array = []
var _foam_acc: float = 0.0
var _g: float = 1100.0
var _col := Color(0.86, 0.92, 0.96, 0.78)
var _foam_col := Color(0.93, 0.95, 0.96, 0.55)
var _seg := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _segc := PackedColorArray([Color.WHITE, Color.WHITE])

# Counters for tests and the probe.
var poured: int = 0
var entries: int = 0
var landed: int = 0

enum { POUR, SPRAY, CROWN, SPOUT }
const MAX_DROPS: int = 700
const MAX_FOAM: int = 140


func setup(p_cfg: Dictionary, p_room: Node, particles_k: float = 1.0) -> void:
	cfg = p_cfg
	room = p_room
	_rng.seed = String(cfg.get("id", "wheel_water")).hash()
	_g = float(cfg.get("gravity_px_s2", 1100.0))
	if cfg.has("color"):
		_col = Color(String(cfg["color"]))
		_col.a = float(cfg.get("alpha", 0.78))
	_foam_col.a = float(cfg.get("foam", {}).get("alpha", 0.55))
	_k = clampf(particles_k, 0.2, 1.0)
	var lid := String(cfg.get("layer", ""))
	if lid != "" and room != null:
		var ln := room.get_node_or_null("Layers/" + lid)
		if ln != null:
			_layer_img = ln.get_node_or_null("Image") as Node2D
	for s in cfg.get("sources", []):
		_src_acc.append(0.0)
	# Start mid-flow: a room entered shows the streams already running, not their first drops (the wheel is wound
	# back by the warm-up and turned to where its layer stands now).
	var warm := float(cfg.get("warm_s", 1.2))
	_own_rot = wheel_rot() - deg_per_s() * warm
	var steps := int(warm / 0.05)
	for i in steps:
		_step(0.05, true)


var _k: float = 1.0


func set_on(v: bool) -> void:
	on = v
	visible = v
	if not v:
		_drops.clear()
		_foam.clear()
	queue_redraw()


# --- The wheel -------------------------------------------------------------------------------

func hub() -> Vector2:
	var h: Array = cfg.get("hub", [0, 0])
	return Vector2(float(h[0]), float(h[1]))


func radius() -> float:
	return float(cfg.get("radius_px", 100.0))


## Clockwise degrees of the wheel now (the room layer's rotation; own clock without a layer).
func wheel_rot() -> float:
	if _layer_img != null and is_instance_valid(_layer_img):
		return _layer_img.rotation_degrees
	return _own_rot


## Is the wheel turning (its layer shown and spinning)?
func turning() -> bool:
	if cfg.get("hub", null) == null:
		return false
	if _layer_img != null and is_instance_valid(_layer_img):
		var ln := _layer_img.get_parent()
		return ln != null and ln.has_method("is_spinning") and bool(ln.call("is_spinning"))
	return float(cfg.get("deg_per_s", 0.0)) != 0.0


func deg_per_s() -> float:
	if _layer_img != null and is_instance_valid(_layer_img):
		var ln := _layer_img.get_parent()
		if ln != null and ln.get("data") is Dictionary:
			return float(ln.data.get("spin", {}).get("deg_per_s", 0.0))
	return float(cfg.get("deg_per_s", 0.0))


## Water surface y at x (a straight line through `water_line` [[x0, y0], [x1, y1]]).
func water_y(x: float) -> float:
	var wl: Array = cfg.get("water_line", [[0, 1080], [1920, 1080]])
	var a := Vector2(float(wl[0][0]), float(wl[0][1]))
	var b := Vector2(float(wl[1][0]), float(wl[1][1]))
	if absf(b.x - a.x) < 0.01:
		return a.y
	return a.y + (x - a.x) * (b.y - a.y) / (b.x - a.x)


## Angles (deg, clockwise from +x) where the rim meets the water: [entry on the descending side, exit on the rising one].
func cut_angles() -> Vector2:
	var c := hub()
	var dy := water_y(c.x) - c.y
	var s := clampf(dy / radius(), -1.0, 1.0)
	var a := rad_to_deg(asin(s))
	var turn := signf(deg_per_s()) if deg_per_s() != 0.0 else 1.0
	# Clockwise (turn > 0): the right side goes down into the water at a, the left comes up at 180 − a.
	return Vector2(a, 180.0 - a) if turn > 0.0 else Vector2(180.0 - a, a)


func _process(delta: float) -> void:
	if not on or not is_visible_in_tree():
		return
	_step(delta, false)
	queue_redraw()


func _step(dt: float, warm: bool) -> void:
	var rot: float
	if warm or _layer_img == null:
		_own_rot = fmod(_own_rot + deg_per_s() * dt, 360.0)
		rot = _own_rot
	else:
		rot = wheel_rot()
	var turn_now := turning()
	if turn_now and cfg.has("pour"):
		_pour(dt, rot)
	if turn_now and cfg.has("entry"):
		_entry(rot)
	if cfg.has("sources"):
		_sources(dt)
	if cfg.has("foam") and (turn_now or not cfg.has("hub")):
		_foam_spawn(dt)
	_move(dt)


func _pour(dt: float, rot: float) -> void:
	var p: Dictionary = cfg["pour"]
	var n := int(cfg.get("paddles", 16))
	var phase := float(cfg.get("bucket_phase_deg", 0.0))
	var cut := cut_angles()
	var turn := 1.0 if deg_per_s() >= 0.0 else -1.0
	var span := float(p.get("span_deg", 80.0))
	var rate0 := float(p.get("rate", 70.0)) * _k
	var w := deg_to_rad(absf(deg_per_s()))
	var r_k: Array = p.get("r_k", [0.84, 1.0])
	var c := hub()
	var R := radius()
	for i in n:
		var ang := fposmod(rot + phase + 360.0 * float(i) / float(n), 360.0)
		# Degrees travelled since this bucket left the water (along the turn).
		var since := fposmod((ang - cut.y) * turn, 360.0)
		if since > span:
			continue
		var full := pow(1.0 - since / span, float(p.get("falloff", 1.6)))
		var owed: float = float(_pour_acc.get(i, 0.0)) + rate0 * full * dt
		while owed >= 1.0 and _drops.size() < MAX_DROPS:
			owed -= 1.0
			var a := deg_to_rad(ang + _rng.randf_range(-3.0, 3.0))
			var rr := R * _rng.randf_range(float(r_k[0]), float(r_k[1]))
			var pos := c + Vector2(cos(a), sin(a)) * rr
			var tang := Vector2(-sin(a), cos(a)) * turn * w * rr
			# Most of the water leaves the lip together (a string that holds), some breaks off as loose drops.
			var jit := float(p.get("stray_px_s", 45.0)) if _rng.randf() < float(p.get("stray", 0.15)) else float(p.get("jitter_px_s", 9.0))
			var vel := tang * float(p.get("carry", 1.0)) + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.6)) * jit
			_drops.append([pos, vel, 0.0, POUR, float(p.get("width_px", 2.6)) * _rng.randf_range(0.7, 1.25), _col.a * (0.6 + 0.4 * full)])
			poured += 1
		_pour_acc[i] = owed


func _entry(rot: float) -> void:
	var e: Dictionary = cfg["entry"]
	var n := int(cfg.get("paddles", 16))
	var phase := float(cfg.get("paddle_phase_deg", 0.0))
	var cut := cut_angles().x
	if is_nan(_last_rot):
		_last_rot = rot
		return
	var turn := 1.0 if deg_per_s() >= 0.0 else -1.0
	var moved := fposmod((rot - _last_rot) * turn, 360.0)
	if moved > 90.0:
		moved = 0.0
	for i in n:
		var now := fposmod(rot + phase + 360.0 * float(i) / float(n), 360.0)
		var before := now - moved * turn
		# Did this paddle pass the entry angle during the step?
		var d0 := fposmod((cut - before) * turn, 360.0)
		if d0 <= moved and moved > 0.0:
			_burst(e, cut)
	_last_rot = rot


func _burst(e: Dictionary, cut_deg: float) -> void:
	entries += 1
	var c := hub()
	var a := deg_to_rad(cut_deg)
	var at := c + Vector2(cos(a), sin(a)) * radius()
	at.y = water_y(at.x)
	var cnt := int(round(float(e.get("count", 26)) * _k))
	var back: Array = e.get("dir", [0.45, -1.0])
	var dir := Vector2(float(back[0]), float(back[1])).normalized()
	var spd: Array = e.get("speed_px_s", [140, 330])
	for k in cnt:
		if _drops.size() >= MAX_DROPS:
			break
		var d := dir.rotated(deg_to_rad(_rng.randf_range(-1.0, 1.0) * float(e.get("spread_deg", 32.0))))
		var pos := at + Vector2(_rng.randf_range(-1.0, 1.0) * float(e.get("width_px", 26.0)), _rng.randf_range(-2.0, 2.0))
		_drops.append([pos, d * _rng.randf_range(float(spd[0]), float(spd[1])), 0.0, SPRAY, _rng.randf_range(1.8, 3.4), _col.a * _rng.randf_range(0.7, 1.0)])
	# The foam the paddle leaves behind it.
	for k in int(e.get("foam", 5)):
		_add_foam(at + Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-3.0, 4.0)), 1.15)


func _sources(dt: float) -> void:
	var srcs: Array = cfg["sources"]
	for si in srcs.size():
		var s: Dictionary = srcs[si]
		var a0: Array = s.get("from", [0, 0])
		var a1: Array = s.get("to", a0)
		var v: Array = s.get("v", [0, 0])
		var jit := float(s.get("jitter_px_s", 18.0))
		var owed: float = float(_src_acc[si]) + float(s.get("rate", 60.0)) * _k * dt
		while owed >= 1.0 and _drops.size() < MAX_DROPS:
			owed -= 1.0
			var t := _rng.randf()
			var pos := Vector2(float(a0[0]), float(a0[1])).lerp(Vector2(float(a1[0]), float(a1[1])), t)
			var vel := Vector2(float(v[0]), float(v[1])) + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.5, 1.0)) * jit
			_drops.append([pos, vel, 0.0, SPOUT, float(s.get("width_px", 3.0)) * _rng.randf_range(0.7, 1.3), _col.a * _rng.randf_range(0.65, 1.0)])
			poured += 1
		_src_acc[si] = owed


func _foam_spawn(dt: float) -> void:
	var f: Dictionary = cfg["foam"]
	var xr: Array = f.get("x", [0, 0])
	_foam_acc += float(f.get("rate", 14.0)) * _k * dt
	while _foam_acc >= 1.0:
		_foam_acc -= 1.0
		var x := _rng.randf_range(float(xr[0]), float(xr[1]))
		_add_foam(Vector2(x, water_y(x) + _rng.randf_range(-2.0, float(f.get("depth_px", 10.0)))), 1.0)


func _add_foam(p: Vector2, k: float) -> void:
	if _foam.size() >= MAX_FOAM:
		return
	var f: Dictionary = cfg.get("foam", {})
	var dr: Array = f.get("drift_px_s", [-70, 0])
	var sz: Array = f.get("size_px", [10, 30])
	var w := _rng.randf_range(float(sz[0]), float(sz[1])) * k
	_foam.append([p, Vector2(float(dr[0]), float(dr[1])) * _rng.randf_range(0.75, 1.25), 0.0, _rng.randf_range(0.9, float(f.get("life_s", 2.2))), Vector2(w, w * _rng.randf_range(0.22, 0.38)), _foam_col.a * _rng.randf_range(0.6, 1.0)])


func _move(dt: float) -> void:
	var keep: Array = []
	for d in _drops:
		var pos: Vector2 = d[0]
		var vel: Vector2 = d[1]
		vel.y += _g * dt
		pos += vel * dt
		d[2] = float(d[2]) + dt
		d[0] = pos
		d[1] = vel
		var kind: int = d[3]
		if kind == CROWN:
			if float(d[2]) < 0.28 and pos.y < water_y(pos.x) + 2.0:
				keep.append(d)
			continue
		if vel.y > 0.0 and pos.y >= water_y(pos.x):
			landed += 1
			if kind != SPRAY and _rng.randf() < 0.45 * _k:
				_crown(Vector2(pos.x, water_y(pos.x)))
			if kind != SPRAY and _rng.randf() < 0.08:
				_add_foam(Vector2(pos.x, water_y(pos.x) + 2.0), 0.6)
			continue
		if float(d[2]) < 3.0:
			keep.append(d)
	_drops = keep
	var fk: Array = []
	for f in _foam:
		f[2] = float(f[2]) + dt
		f[0] = (f[0] as Vector2) + (f[1] as Vector2) * dt
		if float(f[2]) < float(f[3]):
			fk.append(f)
	_foam = fk


func _crown(at: Vector2) -> void:
	for k in 2:
		if _drops.size() >= MAX_DROPS:
			return
		var v := Vector2(_rng.randf_range(-60.0, 60.0), -_rng.randf_range(70.0, 150.0))
		_drops.append([at, v, 0.0, CROWN, 1.6, _col.a * 0.7])


func _draw() -> void:
	for f in _foam:
		var t: float = float(f[2]) / float(f[3])
		var a: float = float(f[5]) * (1.0 - t) * minf(1.0, float(f[2]) * 6.0)
		var sz: Vector2 = f[4]
		var c := _foam_col
		c.a = a
		# soft edge: a wide faint halo, the body, a brighter core
		var s2: Vector2 = sz * (1.0 + 0.5 * t)
		var ch := c
		ch.a = a * 0.35
		_ellipse(f[0], s2 * 1.45, ch)
		_ellipse(f[0], s2, c)
		var cc := c
		cc.a = minf(a * 1.3, 0.9)
		_ellipse(f[0] + Vector2(0, -s2.y * 0.08), s2 * 0.5, cc)
	for d in _drops:
		var pos: Vector2 = d[0]
		var vel: Vector2 = d[1]
		var tail := vel * float(cfg.get("streak_s", 0.03))
		if tail.length() < 2.0:
			tail = vel.normalized() * 2.0 if vel.length() > 0.01 else Vector2(0, 2)
		# A drop and the trace behind it: bright at the drop, clear at the tail (no hard bars).
		var c := _col
		c.a = float(d[5])
		var c0 := c
		c0.a = 0.0
		_seg[0] = pos - tail
		_seg[1] = pos
		_segc[0] = c0
		_segc[1] = c
		draw_polyline_colors(_seg, _segc, float(d[4]), true)


func _ellipse(p: Vector2, sz: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(p + Vector2(cos(a) * sz.x * 0.5, sin(a) * sz.y * 0.5))
	draw_colored_polygon(pts, c)


func probe() -> Dictionary:
	return {"drops": _drops.size(), "foam": _foam.size(), "poured": poured, "entries": entries, "landed": landed,
		"turning": turning(), "rot": wheel_rot(), "cut": [cut_angles().x, cut_angles().y], "on": on}
