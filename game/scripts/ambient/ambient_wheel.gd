class_name AmbientWheel
extends Node2D
## Water at a mill wheel (Директор 25.10 стр. 15: «мельница не реалистично воду скидывает да и входит»; 29.10 стр. 96:
## «анимации мельницы и воды — ничего не сделано»; 30.10, 14:30: «колесо стало лучше, но воду — до реалистичной»).
## Built from an ambient entry `wheel_water` (AmbientRoot), drawn in code over the painted wheel and water.
##   POUR    — on the rising side the buckets come up full and pour. Water leaves a bucket lip as a continuous clear
##             STREAM (`pour.stream`): a chain of water parcels emitted at the lip with the lip's own velocity (ω·r
##             along the rim), each falling under gravity; the chain is drawn as one ribbon (shader: the background
##             seen through it, bent a little; brighter rims, a sky highlight, striations travelling down). A stream
##             thins as it speeds up, necks and breaks into drops after `break_s` (fuller buckets hold together
##             longer); the drops fall on. A bucket pours most right after it leaves the water and runs dry by
##             `span_deg`, dribbling a few last drops. The lips follow the real angle of the spinning room layer
##             (`layer`), so the streams turn with the paddles; while the wheel stands (pond let down) nothing pours.
##   ENTRY   — each time a paddle cuts into the water on the descending side: a burst of spray thrown up and back
##             (fine mist-drops and a few heavy ones), white churn and foam where it went in.
##   FOAM    — churned water under the wheel, carried with the current (`foam.drift_px_s`) and fading downstream;
##             `foam.style: "lace"` — lacy froth (noise shader) instead of soft ellipses (the bank lap at R3 keeps those).
##   SOURCES — fixed spouts (a painted wheel that does not turn — the epilogue cascade): each source segment pours as
##             a curtain of `streams` side-by-side ribbons with a given velocity.
##   LANDING — where water meets the water line: white churn, a small crown of spray, now and then a breath of mist.
## Units: screen px, s; gravity `gravity_px_s2`. All randomness from a seeded RNG (stable in tests).

const RIBBON_SHADER := preload("res://shaders/wheel_water_ribbon.gdshader")
const FOAM_SHADER := preload("res://shaders/wheel_water_foam.gdshader")

var cfg: Dictionary = {}
var room: Node = null
var on: bool = true

var _rng := RandomNumberGenerator.new()
var _drops: Array = []      # [pos: Vector2, vel: Vector2, life: float, kind: int, w: float, a: float]
var _foam: Array = []       # [pos: Vector2, vel: Vector2, age: float, life: float, size: Vector2, a: float, seed: float, churn: bool]
var _mist: Array = []       # [pos: Vector2, vel: Vector2, age: float, life: float, r: float, a: float]
## Streams: key ("b<bucket>" / "s<source>_<k>") → {pts: [[pos, vel, age, brk, w, a, alive]], emit, wob, seed, live, r, land}
var _streams: Dictionary = {}
var _layer_img: Node2D = null
var _last_rot: float = NAN
var _own_rot: float = 0.0
var _pour_acc: Dictionary = {}   # bucket index → fractional dribble drops owed
var _foam_acc: float = 0.0
var _g: float = 1100.0
var _col := Color(0.86, 0.92, 0.96, 0.78)
var _foam_col := Color(0.93, 0.95, 0.96, 0.55)
var _seg := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _segc := PackedColorArray([Color.WHITE, Color.WHITE])
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _quadc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _quaduv := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _k: float = 1.0

# Drawing layers (children, in order): lacy foam and churn under the streams, the streams, the drops and mist on top.
var _foam_item: Node2D = null
var _ribbon_item: Node2D = null
var _top_item: Node2D = null

# Counters for tests and the probe.
var poured: int = 0      # water parcels that left a lip or a spout (stream points + loose drops)
var entries: int = 0
var landed: int = 0

enum { POUR, SPRAY, CROWN, SPOUT }
const MAX_DROPS: int = 700
const MAX_FOAM: int = 140
const MAX_MIST: int = 40
const MAX_STREAM_PTS: int = 90


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
	_make_items()
	var lid := String(cfg.get("layer", ""))
	if lid != "" and room != null:
		var ln := room.get_node_or_null("Layers/" + lid)
		if ln != null:
			_layer_img = ln.get_node_or_null("Image") as Node2D
	# Start mid-flow: a room entered shows the streams already running, not their first drops (the wheel is wound
	# back by the warm-up and turned to where its layer stands now).
	var warm := float(cfg.get("warm_s", 1.2))
	_own_rot = wheel_rot() - deg_per_s() * warm
	var steps := int(warm / 0.025)
	for i in steps:
		_step(0.025, true)


func _make_items() -> void:
	for n in ["Foam", "Streams", "Drops"]:
		var old := get_node_or_null(n)
		if old != null:
			old.free()
	_foam_item = Node2D.new()
	_foam_item.name = "Foam"
	if _lace():
		var fm := ShaderMaterial.new()
		fm.shader = FOAM_SHADER
		_foam_item.material = fm
	add_child(_foam_item)
	_foam_item.draw.connect(_draw_foam)
	_ribbon_item = Node2D.new()
	_ribbon_item.name = "Streams"
	var rm := ShaderMaterial.new()
	rm.shader = RIBBON_SHADER
	var tint := _col
	rm.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	var st: Dictionary = cfg.get("stream", {})
	rm.set_shader_parameter("refract_px", float(st.get("refract_px", 3.0)))
	rm.set_shader_parameter("highlight", float(st.get("highlight", 0.42)))
	rm.set_shader_parameter("body_mix", float(st.get("body_mix", 0.2)))
	rm.set_shader_parameter("aeration", float(st.get("aeration", 0.8)))
	rm.set_shader_parameter("aer_lip", float(st.get("aer_lip", 0.25)))
	_ribbon_item.material = rm
	add_child(_ribbon_item)
	_ribbon_item.draw.connect(_draw_streams)
	_top_item = Node2D.new()
	_top_item.name = "Drops"
	add_child(_top_item)
	_top_item.draw.connect(_draw_top)


func _lace() -> bool:
	return String(cfg.get("foam", {}).get("style", "")) == "lace"


func set_on(v: bool) -> void:
	on = v
	visible = v
	if not v:
		_drops.clear()
		_foam.clear()
		_mist.clear()
		_streams.clear()
	_redraw()


func _redraw() -> void:
	queue_redraw()
	for it in [_foam_item, _ribbon_item, _top_item]:
		if it != null:
			it.queue_redraw()


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


## Water surface y at x: `water_line` — points [[x, y], …] left to right, straight between them (a wheel's water is
## one segment; a bank's edge under stones bends).
func water_y(x: float) -> float:
	var wl: Array = cfg.get("water_line", [[0, 1080], [1920, 1080]])
	if wl.size() < 2:
		return 1080.0
	for i in range(wl.size() - 1):
		var a := Vector2(float(wl[i][0]), float(wl[i][1]))
		var b := Vector2(float(wl[i + 1][0]), float(wl[i + 1][1]))
		if x <= b.x or i == wl.size() - 2:
			if absf(b.x - a.x) < 0.01:
				return a.y
			return a.y + (x - a.x) * (b.y - a.y) / (b.x - a.x)
	return float(wl[0][1])


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
	_step(minf(delta, 0.05), false)
	_redraw()


func _step(dt: float, warm: bool) -> void:
	var rot: float
	if warm or _layer_img == null:
		_own_rot = fmod(_own_rot + deg_per_s() * dt, 360.0)
		rot = _own_rot
	else:
		rot = wheel_rot()
	var turn_now := turning()
	# Move what is in the air first, then let new water out (with its head start within this step).
	_move(dt)
	for key in _streams:
		_streams[key]["live"] = false
	if turn_now and cfg.has("pour"):
		_pour(dt, rot)
	if turn_now and cfg.has("entry"):
		_entry(rot)
	if cfg.has("sources"):
		_sources(dt)
	if cfg.has("foam") and (turn_now or not cfg.has("hub")):
		_foam_spawn(dt)
	var gone: Array = []
	for key in _streams:
		if (_streams[key]["pts"] as Array).is_empty() and not bool(_streams[key]["live"]):
			gone.append(key)
	for key in gone:
		_streams.erase(key)


# --- Streams -----------------------------------------------------------------------------------

func _stream(key: String) -> Dictionary:
	if not _streams.has(key):
		_streams[key] = {"pts": [], "emit": _rng.randf(), "wob": _rng.randf() * TAU, "seed": _rng.randf() * 50.0,
			"live": true, "r": _rng.randf(), "land": 0}
	var s: Dictionary = _streams[key]
	s["live"] = true
	return s


## One water parcel leaves `pos` with `vel` into stream `s`: `w` — the stream's width there, `brk` — how long it
## holds together before breaking into drops, `a` — opacity.
## `ago` — how long before the end of this step the parcel left (several leave in one long frame: each is moved on by
## its own head start, so they never pile up on one spot and the ribbon stays smooth at any frame rate).
func _emit(s: Dictionary, pos: Vector2, vel: Vector2, w: float, brk: float, a: float, ago: float = 0.0) -> void:
	var pts: Array = s["pts"]
	if pts.size() >= MAX_STREAM_PTS:
		pts.pop_front()
	var v := vel + Vector2(0.0, _g * ago)
	var p := pos + vel * ago + Vector2(0.0, 0.5 * _g * ago * ago)
	pts.append([p, v, ago, brk, w, a, true])
	poured += 1


func _pour(dt: float, rot: float) -> void:
	var p: Dictionary = cfg["pour"]
	var st: Dictionary = cfg.get("stream", {})
	var n := int(cfg.get("paddles", 16))
	var phase := float(cfg.get("bucket_phase_deg", 0.0))
	var cut := cut_angles()
	var turn := 1.0 if deg_per_s() >= 0.0 else -1.0
	var span := float(p.get("span_deg", 80.0))
	var w := deg_to_rad(absf(deg_per_s()))
	var r_k: Array = p.get("r_k", [0.84, 1.0])
	var hz := float(st.get("emit_hz", 50.0))
	var brk_r: Array = st.get("break_s", [0.16, 0.42])
	var width := float(st.get("width_px", 7.0))
	var c := hub()
	var R := radius()
	for i in n:
		var ang := fposmod(rot + phase + 360.0 * float(i) / float(n), 360.0)
		# Degrees travelled since this bucket left the water (along the turn).
		var since := fposmod((ang - cut.y) * turn, 360.0)
		if since > span * 1.35:
			continue
		var full := pow(maxf(0.0, 1.0 - since / span), float(p.get("falloff", 1.6)))
		var a := deg_to_rad(ang)
		if since <= span and full > 0.04:
			# A bucket pours over its whole lip: `per_bucket` streams side by side along the paddle (radially), each
			# its own wobble and break — one sheet that tears into strands, not a single thread.
			var nb := int(st.get("per_bucket", 1))
			for sb in nb:
				var s := _stream("b%d_%d" % [i, sb])
				var rr := R * lerpf(float(r_k[0]), float(r_k[1]), (float(sb) + float(s["r"])) / float(nb))
				var lip := c + Vector2(cos(a), sin(a)) * rr
				var tang := Vector2(-sin(a), cos(a)) * turn * w * rr
				s["emit"] = float(s["emit"]) + hz * dt
				s["wob"] = float(s["wob"]) + dt * float(st.get("wobble_hz", 2.3)) * TAU
				# The lip wobbles the stream a little (the water sloshes in the bucket): a slow sway, not per-drop noise.
				var sway := Vector2(sin(float(s["wob"])), 0.35 * cos(float(s["wob"]) * 0.7)) * float(p.get("jitter_px_s", 9.0))
				while float(s["emit"]) >= 1.0:
					s["emit"] = float(s["emit"]) - 1.0
					var vel := tang * float(p.get("carry", 1.0)) + sway + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0))
					var brk := lerpf(float(brk_r[0]), float(brk_r[1]), full) * _rng.randf_range(0.8, 1.2)
					_emit(s, lip, vel, width * (0.3 + 0.7 * sqrt(full)), brk, _col.a * (0.55 + 0.45 * full), float(s["emit"]) / hz)
			# Where the bucket has just come up out of the race, the water it drags out boils white at the surface.
			if since < float(st.get("exit_churn_deg", 14.0)) and _rng.randf() < dt * 9.0:
				var lx := c.x + cos(a) * R
				_add_churn(Vector2(lx + _rng.randf_range(-10.0, 10.0), water_y(lx) + 3.0), _rng.randf_range(40.0, 70.0), 0.85)
				if _rng.randf() < 0.25:
					_add_mist(Vector2(lx, water_y(lx) - 8.0), 30.0, 0.12)
		# Loose drops: some break off the lip at once; a bucket running dry dribbles its last.
		var dribble := float(p.get("rate", 70.0)) * float(p.get("stray", 0.15)) * (full if since <= span else 0.25) * _k
		var owed: float = float(_pour_acc.get(i, 0.0)) + dribble * dt
		while owed >= 1.0 and _drops.size() < MAX_DROPS:
			owed -= 1.0
			var aa := a + deg_to_rad(_rng.randf_range(-3.0, 3.0))
			var rr2 := R * _rng.randf_range(float(r_k[0]), float(r_k[1]))
			var pos := c + Vector2(cos(aa), sin(aa)) * rr2
			var vel2 := Vector2(-sin(aa), cos(aa)) * turn * w * rr2 + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.6)) * float(p.get("stray_px_s", 45.0))
			_drops.append([pos, vel2, 0.0, POUR, _rng.randf_range(1.4, 2.6), _col.a * _rng.randf_range(0.55, 0.9)])
			poured += 1
		_pour_acc[i] = owed


func _sources(dt: float) -> void:
	var srcs: Array = cfg["sources"]
	var st: Dictionary = cfg.get("stream", {})
	var hz := float(st.get("emit_hz", 50.0))
	var brk_r: Array = st.get("break_s", [0.16, 0.42])
	for si in srcs.size():
		var src: Dictionary = srcs[si]
		var a0: Array = src.get("from", [0, 0])
		var a1: Array = src.get("to", a0)
		var p0 := Vector2(float(a0[0]), float(a0[1]))
		var p1 := Vector2(float(a1[0]), float(a1[1]))
		var v: Array = src.get("v", [0, 0])
		var k_n := int(src.get("streams", clampi(int(round(p0.distance_to(p1) / 34.0)), 2, 6)))
		var wid := float(src.get("stream_px", p0.distance_to(p1) / float(k_n) * 0.85))
		for k in k_n:
			var s := _stream("s%d_%d" % [si, k])
			s["emit"] = float(s["emit"]) + hz * dt
			s["wob"] = float(s["wob"]) + dt * float(st.get("wobble_hz", 2.3)) * TAU
			var t := (float(k) + 0.5) / float(k_n) + 0.12 / float(k_n) * sin(float(s["wob"]) * 0.37)
			var at := p0.lerp(p1, t)
			var sway := Vector2(sin(float(s["wob"])), 0.3 * cos(float(s["wob"]) * 0.6)) * float(src.get("jitter_px_s", 12.0))
			while float(s["emit"]) >= 1.0:
				s["emit"] = float(s["emit"]) - 1.0
				var vel := Vector2(float(v[0]), float(v[1])) + sway + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.0, 1.5))
				var brk := lerpf(float(brk_r[0]), float(brk_r[1]), float(s["r"])) * _rng.randf_range(0.8, 1.2)
				_emit(s, at, vel, wid * _rng.randf_range(0.9, 1.1), brk, _col.a * _rng.randf_range(0.75, 0.95), float(s["emit"]) / hz)


# --- Entry, foam, mist -----------------------------------------------------------------------

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
		# Mostly fine spray (small, quick, faint), a few heavy drops thrown higher.
		var heavy := _rng.randf() < 0.22
		var sp := _rng.randf_range(float(spd[0]), float(spd[1])) * (1.0 if heavy else _rng.randf_range(0.55, 0.95))
		_drops.append([pos, d * sp, 0.0, SPRAY, _rng.randf_range(2.0, 3.0) if heavy else _rng.randf_range(1.0, 1.8), _col.a * (_rng.randf_range(0.75, 1.0) if heavy else _rng.randf_range(0.35, 0.7))])
	# White churn where the paddle went in, foam behind it, a breath of mist.
	_add_churn(at + Vector2(_rng.randf_range(-6.0, 6.0), 1.0), float(e.get("width_px", 26.0)) * 2.4, 0.55)
	for k in int(e.get("foam", 5)):
		_add_foam(at + Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-3.0, 4.0)), 1.15)
	_add_mist(at + Vector2(0, -10), 34.0, 0.16)


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
	# `aspect` [min, max] — height / width of a patch: churned water under a wheel is lumpy (≈0.3), the lap at a bank
	# is a thin line of froth (≈0.07).
	var asp: Array = f.get("aspect", [0.22, 0.38])
	_foam.append([p, Vector2(float(dr[0]), float(dr[1])) * _rng.randf_range(0.75, 1.25), 0.0, _rng.randf_range(0.9, float(f.get("life_s", 2.2))), Vector2(w, w * _rng.randf_range(float(asp[0]), float(asp[1]))), _foam_col.a * _rng.randf_range(0.6, 1.0), _rng.randf(), false])


## White aerated water where a stream or a paddle hits: a churning patch (lace foam only), short-lived, drifting.
func _add_churn(p: Vector2, w: float, a: float) -> void:
	if not _lace() or _foam.size() >= MAX_FOAM:
		return
	var dr: Array = cfg.get("foam", {}).get("drift_px_s", [-70, 0])
	_foam.append([p, Vector2(float(dr[0]), float(dr[1])) * 0.4, 0.0, _rng.randf_range(0.45, 0.8), Vector2(w, w * _rng.randf_range(0.32, 0.45)), a * _rng.randf_range(0.8, 1.0), _rng.randf(), true])


func _add_mist(p: Vector2, r: float, a: float) -> void:
	if _mist.size() >= MAX_MIST or not _lace():
		return
	_mist.append([p, Vector2(_rng.randf_range(-12.0, 12.0), -_rng.randf_range(8.0, 22.0)), 0.0, _rng.randf_range(0.9, 1.6), r * _rng.randf_range(0.8, 1.3), a])


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
			if kind != SPRAY and _rng.randf() < 0.3 * _k:
				_crown(Vector2(pos.x, water_y(pos.x)))
			if kind != SPRAY and _rng.randf() < 0.06:
				_add_foam(Vector2(pos.x, water_y(pos.x) + 2.0), 0.6)
			continue
		if float(d[2]) < 3.0:
			keep.append(d)
	_drops = keep
	# Streams: every parcel falls; one that has held long enough breaks into drops; one that reaches the water lands.
	for key in _streams:
		var s: Dictionary = _streams[key]
		var pts: Array = s["pts"]
		var kp: Array = []
		for q in pts:
			var pos: Vector2 = q[0]
			var vel: Vector2 = q[1]
			vel.y += _g * dt
			pos += vel * dt
			q[0] = pos
			q[1] = vel
			q[2] = float(q[2]) + dt
			var wy := water_y(pos.x)
			if vel.y > 0.0 and pos.y >= wy:
				if bool(q[6]):
					landed += 1
					s["land"] = int(s["land"]) + 1
					# white water where the stream lands (not for every parcel — a churn patch lives a while)
					if int(s["land"]) % 4 == 0:
						_add_churn(Vector2(pos.x + _rng.randf_range(-4.0, 4.0), wy + 2.0), float(q[4]) * 3.4 + 24.0, 0.95)
					if _rng.randf() < 0.12 * _k:
						_crown(Vector2(pos.x, wy))
					if _rng.randf() < 0.012:
						_add_mist(Vector2(pos.x, wy - 6.0), 26.0, 0.1)
				continue
			if bool(q[6]) and float(q[2]) >= float(q[3]):
				q[6] = false
				# The stream necks and parts: the parcel goes on as a drop or two.
				var nd := 0 if _rng.randf() < 0.3 else (1 if _rng.randf() < 0.75 else 2)
				for j in nd:
					if _drops.size() < MAX_DROPS:
						var sc := Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-10.0, 14.0))
						_drops.append([pos + Vector2(_rng.randf_range(-1.0, 1.0) * float(q[4]) * 0.3, 0.0), vel + sc, 0.0, POUR, clampf(float(q[4]) * 0.2, 1.0, 2.2) * _rng.randf_range(0.8, 1.15), float(q[5]) * _rng.randf_range(0.45, 0.75)])
			# a broken parcel stays in the list (not drawn) as a gap: the ribbon is never bridged across it
			if float(q[2]) < 3.0:
				kp.append(q)
		# trim leading gap markers
		while kp.size() > 0 and not bool(kp[0][6]):
			kp.pop_front()
		s["pts"] = kp
	var fk: Array = []
	for f in _foam:
		f[2] = float(f[2]) + dt
		f[0] = (f[0] as Vector2) + (f[1] as Vector2) * dt
		if float(f[2]) < float(f[3]):
			fk.append(f)
	_foam = fk
	var mk: Array = []
	for m in _mist:
		m[2] = float(m[2]) + dt
		m[0] = (m[0] as Vector2) + (m[1] as Vector2) * dt
		if float(m[2]) < float(m[3]):
			mk.append(m)
	_mist = mk


func _crown(at: Vector2) -> void:
	for k in 2:
		if _drops.size() >= MAX_DROPS:
			return
		var v := Vector2(_rng.randf_range(-60.0, 60.0), -_rng.randf_range(70.0, 150.0))
		_drops.append([at, v, 0.0, CROWN, 1.3, _col.a * 0.6])


# --- Drawing ---------------------------------------------------------------------------------

func _draw_foam() -> void:
	if _lace():
		for f in _foam:
			var t: float = float(f[2]) / float(f[3])
			var a: float = float(f[5]) * (1.0 - t * t) * minf(1.0, float(f[2]) * 5.0)
			var sz: Vector2 = (f[4] as Vector2) * (1.0 + 0.6 * t)
			var p: Vector2 = f[0]
			var col := Color(float(f[6]), t, 1.0 if bool(f[7]) else 0.0, a)
			_quad[0] = p + Vector2(-sz.x, -sz.y) * 0.5
			_quad[1] = p + Vector2(sz.x, -sz.y) * 0.5
			_quad[2] = p + Vector2(sz.x, sz.y) * 0.5
			_quad[3] = p + Vector2(-sz.x, sz.y) * 0.5
			for i in 4:
				_quadc[i] = col
			_quaduv[0] = Vector2(0, 0)
			_quaduv[1] = Vector2(1, 0)
			_quaduv[2] = Vector2(1, 1)
			_quaduv[3] = Vector2(0, 1)
			_foam_item.draw_primitive(_quad, _quadc, _quaduv)
		return
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
		_ellipse(_foam_item, f[0], s2 * 1.45, ch)
		_ellipse(_foam_item, f[0], s2, c)
		var cc := c
		cc.a = minf(a * 1.3, 0.9)
		_ellipse(_foam_item, f[0] + Vector2(0, -s2.y * 0.08), s2 * 0.5, cc)


func _draw_streams() -> void:
	var u_k := float(cfg.get("stream", {}).get("u_per_s", 2.4))
	for key in _streams:
		var s: Dictionary = _streams[key]
		var pts: Array = s["pts"]
		var n := pts.size()
		if n < 2:
			continue
		var seed := float(s["seed"])
		# left / right edge of every live parcel (normals from its neighbours)
		var L := PackedVector2Array()
		var Rr := PackedVector2Array()
		L.resize(n)
		Rr.resize(n)
		for j in n:
			var q: Array = pts[j]
			if not bool(q[6]):
				continue
			var pa: Vector2 = q[0]
			var dir := Vector2.ZERO
			if j + 1 < n and bool(pts[j + 1][6]):
				dir += (pts[j + 1][0] as Vector2) - pa
			if j > 0 and bool(pts[j - 1][6]):
				dir += pa - (pts[j - 1][0] as Vector2)
			if dir.length() < 0.01:
				dir = q[1]
			# older parcels come first in the list: the stream runs from the lip (last) down to the oldest (first)
			var nrm := Vector2(-dir.y, dir.x).normalized()
			var vel: Vector2 = q[1]
			var age: float = q[2]
			var thin := clampf(sqrt(90.0 / maxf(vel.length(), 90.0)), 0.55, 1.0)
			var neck := 1.0 - 0.55 * pow(clampf(age / float(q[3]), 0.0, 1.0), 3.0)
			# at the lip the water is just tipping over the edge: the stream opens out over its first few cm
			var lip_k := 0.45 + 0.55 * clampf(age / 0.06, 0.0, 1.0)
			# the sheet is never a ruler-straight band: its width breathes along the fall
			var breathe := 0.82 + 0.3 * sin(age * 23.0 + seed * 3.1) * sin(age * 9.0 + seed)
			var hw := float(q[4]) * 0.5 * thin * neck * lip_k * breathe
			L[j] = pa + nrm * hw
			Rr[j] = pa - nrm * hw
		# length of the live run each parcel belongs to: a torn-off scrap of two or three parcels is not drawn as a
		# ribbon (it would read as a glass shard) — its parcels fall on as drops when they break
		var run := PackedInt32Array()
		run.resize(n)
		var j0 := 0
		while j0 < n:
			if not bool(pts[j0][6]):
				run[j0] = 0
				j0 += 1
				continue
			var j1 := j0
			while j1 < n and bool(pts[j1][6]):
				j1 += 1
			for jj in range(j0, j1):
				run[jj] = j1 - j0
			j0 = j1
		for j in n - 1:
			var q0: Array = pts[j]
			var q1: Array = pts[j + 1]
			if not (bool(q0[6]) and bool(q1[6])) or run[j] < 4:
				continue
			var a0 := _stream_alpha(q0)
			var a1 := _stream_alpha(q1)
			if a0 <= 0.003 and a1 <= 0.003:
				continue
			_quad[0] = L[j]
			_quad[1] = L[j + 1]
			_quad[2] = Rr[j + 1]
			_quad[3] = Rr[j]
			# r — aeration (0 clear at the lip → 1 white as it falls and tears apart), read by the shader
			var e0 := clampf(float(q0[2]) / float(q0[3]), 0.0, 1.0)
			var e1 := clampf(float(q1[2]) / float(q1[3]), 0.0, 1.0)
			_quadc[0] = Color(e0, 1, 1, a0)
			_quadc[1] = Color(e1, 1, 1, a1)
			_quadc[2] = Color(e1, 1, 1, a1)
			_quadc[3] = Color(e0, 1, 1, a0)
			var u0 := float(q0[2]) * u_k + seed
			var u1 := float(q1[2]) * u_k + seed
			_quaduv[0] = Vector2(u0, 0.0)
			_quaduv[1] = Vector2(u1, 0.0)
			_quaduv[2] = Vector2(u1, 1.0)
			_quaduv[3] = Vector2(u0, 1.0)
			_ribbon_item.draw_primitive(_quad, _quadc, _quaduv)


## A parcel's opacity in its stream: fades in just off the lip, out as it necks before breaking, and into the water
## surface just above it (the stream goes in, it does not end on a cut).
func _stream_alpha(q: Array) -> float:
	var age: float = q[2]
	var t := clampf(age / float(q[3]), 0.0, 1.0)
	var pos: Vector2 = q[0]
	var above := clampf((water_y(pos.x) - pos.y) / 16.0, 0.0, 1.0)
	return float(q[5]) * minf(1.0, 0.35 + age * 30.0) * (1.0 - smoothstep(0.7, 1.0, t) * 0.7) * above


func _draw_top() -> void:
	for m in _mist:
		var t: float = float(m[2]) / float(m[3])
		var a: float = float(m[5]) * sin(PI * t)
		_soft_disc(_top_item, m[0], float(m[4]) * (1.0 + 0.8 * t), Color(0.95, 0.97, 0.98, a))
	for d in _drops:
		var pos: Vector2 = d[0]
		var vel: Vector2 = d[1]
		var tail := vel * float(cfg.get("streak_s", 0.03)) * (0.6 if int(d[3]) == POUR else 1.0)
		if tail.length() < 2.0:
			tail = vel.normalized() * 2.0 if vel.length() > 0.01 else Vector2(0, 2)
		# A drop and the trace behind it: bright at the drop, clear at the tail (no hard bars).
		var c := _col
		var age: float = d[2]
		c.a = float(d[5]) * (1.0 - smoothstep(0.35, 0.6, age) * 0.6 if int(d[3]) == SPRAY else 1.0)
		var c0 := c
		c0.a = 0.0
		_seg[0] = pos - tail
		_seg[1] = pos
		_segc[0] = c0
		_segc[1] = c
		_top_item.draw_polyline_colors(_seg, _segc, float(d[4]), true)


## A round patch soft all the way out: full colour in the middle, clear at the rim (a fan with per-vertex alpha).
func _soft_disc(item: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array([p])
	var cols := PackedColorArray([c])
	var c0 := c
	c0.a = 0.0
	for i in 15:
		var a := TAU * float(i) / 14.0
		pts.append(p + Vector2(cos(a) * r, sin(a) * r * 0.7))
		cols.append(c0)
	item.draw_polygon(pts, cols)


func _ellipse(item: CanvasItem, p: Vector2, sz: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(p + Vector2(cos(a) * sz.x * 0.5, sin(a) * sz.y * 0.5))
	item.draw_colored_polygon(pts, c)


func probe() -> Dictionary:
	var sp := 0
	var live := 0
	for key in _streams:
		for q in _streams[key]["pts"]:
			if bool(q[6]):
				sp += 1
		if bool(_streams[key]["live"]):
			live += 1
	return {"drops": _drops.size(), "foam": _foam.size(), "poured": poured, "entries": entries, "landed": landed,
		"streams": live, "stream_pts": sp, "turning": turning(), "rot": wheel_rot(), "cut": [cut_angles().x, cut_angles().y], "on": on}
