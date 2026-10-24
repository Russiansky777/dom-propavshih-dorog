extends MechanicPanel
## Q06 «Второй верстак», переделан по H48 (Director 24.10: «ничего не понятно, ни как, зачем и куда нажимать… предметы
## сделаны ужасно, полностью переработать»). Ilya's cramped workshop (the shed in his yard, O4) as a close-up: a second
## bench is put together — a third working place, for Ulya (`texts.label_goal`, always on screen under the title).
## One step at a time, one line of hint for it, and every action is the same: take a part with the mouse and drag it
## onto the lit place.
##   0 "fitted"     — a fastening into the groove: the key (`fits`) sits; the wedge sits, wobbles and slides back home
##                    with Ilya's word why (`text`) — the «compare two fastenings» of the scenario;
##   1 "stopped"    — the stop block into the groove, up against the key;
##   2 "screw_set"  — the wooden screw onto its place behind the stop block;
##   3 "tightened"  — the screw is turned: press on the lit ring round its handle and drive the mouse round
##                    (`turn.turns` turns, either way); the screw creeps in as it goes, letting go keeps what is done;
##   4 "checked"    — the board onto the bench, its end against the stop block — Ilya leans on it: it holds.
## Each step is a story flag (`steps`): put away midway, the close-up opens on the same step, a load replays nothing.
## While a part is dragged its target glows brighter when the part is over it; let go there — it settles with a
## click; let go anywhere else — it glides back to where it lay. Nothing is lost on a wrong try.
## Art (партия 10б): `art.bg` — the bench with an empty groove and no screw (closeup_second_bench_clean, 1672×941);
## `parts.<id>.image` — each part painted on its own full-canvas layer where it sits when done (`rect` — its box on
## that layer); the engine lays it aside at `rest` ({offset, rot} from the painted place) and brings it to `seat`
## ({offset, rot, scale}); the cast shadow is the engine's (the same cut-out, dark, offset — higher while lifted).
## `zones[i]` — the lit place of step i (canvas px polygon). Coordinates — canvas px; `step_pos`, `hint_pos` — screen.

const CANVAS := Vector2(1672, 941)
const EVENTS := ["fitted", "stopped", "screw_set", "tightened", "checked"]

var k: float = 1.0
var art_root: Control = null
var layer: Node2D = null            # canvas px, scaled by k: zones, ghosts, parts, the turning ring
var parts: Dictionary = {}          # id -> {node, img, shadow, image (Image of the cut-out), rect, cfg}
var zone_fill: Polygon2D = null
var zone_line: Line2D = null
var zone_halo: Line2D = null       # a dark rim under the bright edge: the place reads on pale pine
var ghost: Sprite2D = null          # the lit place of steps 1, 2, 4: the part's own outline, faint
var ring: Line2D = null             # step 3: the ring to drive round
var ring_done: Line2D = null
var ring_arrow: Polygon2D = null
var goal: Label = null
var hint: Label = null
var step_label: Label = null
var name_tip: Label = null
var tries_wrong: int = 0            # the wedge tried in the groove
var returns: int = 0                # parts let go away from their place (glided back)
var turn_progress: float = 0.0      # 0..1 of the screw turning
var drag_id: String = ""
var over_target: bool = false
var hover_id: String = ""
var _grab_off: Vector2 = Vector2.ZERO
var _turning: bool = false
var _turn_last: float = 0.0
var _turn_ticks: int = 0
var _anim: Dictionary = {}          # id -> {from: xf, to: xf, t, dur, then}
var _wobble_t: float = -1.0
var _check_t: float = -1.0          # the board pressed by Ilya
var _pulse: float = 0.0
var _screw_turned: bool = false     # the "tightened" event sent (waits for the line)


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	k = 1920.0 / CANVAS.x
	art_root = Control.new()
	art_root.name = "Art"
	art_root.size = CANVAS
	art_root.scale = Vector2(k, k)
	art_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art_root)
	var bg := String(art.get("bg", ""))
	if bg != "" and ResourceLoader.exists(bg):
		crop(bg, [0, 0, CANVAS.x, CANVAS.y], Vector2.ZERO, 1.0, art_root).name = "Bench"
	else:
		var st := PlaceholderArt.stand_in(spec.get("stub", {}))
		st.name = "BenchStandIn"
		art_root.add_child(st)
	layer = Node2D.new()
	layer.name = "Layer"
	layer.scale = Vector2(k, k)
	add_child(layer)
	# The lit place: a soft warm fill with a bright edge (pulses; brighter when a part is over it).
	zone_fill = Polygon2D.new()
	zone_fill.name = "ZoneFill"
	layer.add_child(zone_fill)
	zone_halo = Line2D.new()
	zone_halo.name = "ZoneHalo"
	zone_halo.width = 9.0
	zone_halo.joint_mode = Line2D.LINE_JOINT_ROUND
	zone_halo.default_color = Color(0.28, 0.13, 0.03, 0.5)
	layer.add_child(zone_halo)
	zone_line = Line2D.new()
	zone_line.name = "ZoneLine"
	zone_line.width = 3.0
	zone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	layer.add_child(zone_line)
	ghost = Sprite2D.new()
	ghost.name = "Ghost"
	ghost.centered = true
	layer.add_child(ghost)
	var order: Array = spec.get("draw_order", ["wedge", "key", "stop", "screw", "board"])
	var pc: Dictionary = spec.get("parts", {})
	for id in order:
		if pc.has(id):
			_make_part(String(id), pc[id])
	_make_ring()
	name_tip = label("", Vector2.ZERO, 260)
	name_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_tip.visible = false
	goal = label(text("label_goal"), v2(spec.get("goal_pos", [40, 150])), 900)
	goal.name = "Goal"
	step_label = label("", v2(spec.get("step_pos", [1000, 96])), 900, &"CloseupTitle")
	step_label.name = "Step"
	hint = label("", v2(spec.get("hint_pos", [1000, 150])), 900)
	hint.name = "Hint"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_place_all()
	_refresh()


func opened() -> void:
	sound("knock")


# --- Parts ---------------------------------------------------------------------------------------

func _make_part(id: String, cfg: Dictionary) -> void:
	var r := _rect(cfg.get("rect", [0, 0, 10, 10]))
	var node := Node2D.new()
	node.name = "Part_" + id
	var tex: Texture2D = null
	var img: Image = null
	var path := String(cfg.get("image", ""))
	if path != "" and ResourceLoader.exists(path):
		var full: Texture2D = load(path)
		var at := AtlasTexture.new()
		at.atlas = full
		at.region = r
		tex = at
		var fi := full.get_image()
		if fi != null:
			if fi.is_compressed():
				fi.decompress()
			img = fi.get_region(Rect2i(r))
	# Cast shadow: the cut-out itself, dark and soft (two copies), under the part; offset grows while it is lifted.
	var shadows: Array[Sprite2D] = []
	for i in 2:
		var sh := Sprite2D.new()
		sh.name = "Shadow%d" % i
		sh.texture = tex
		sh.centered = true
		sh.modulate = Color(0.16, 0.08, 0.02, 0.26 if i == 0 else 0.14)
		node.add_child(sh)
		shadows.append(sh)
	var spr := Sprite2D.new()
	spr.name = "Image"
	spr.texture = tex
	spr.centered = true
	node.add_child(spr)
	if tex == null:
		# no art: a plain wooden block of the part's size (honest stand-in)
		var poly := Polygon2D.new()
		poly.name = "StandIn"
		var h := r.size / 2.0
		poly.polygon = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
		poly.color = Color(0.85, 0.68, 0.45)
		node.add_child(poly)
	layer.add_child(node)
	parts[id] = {"node": node, "img": spr, "shadows": shadows, "image": img, "rect": r, "cfg": cfg, "tex": tex}


## A placement of a part: {pos (canvas px of its centre), rot (deg), scale}.
func _xf(id: String, which: String) -> Dictionary:
	var p: Dictionary = parts[id]
	var cfg: Dictionary = p["cfg"]
	var r: Rect2 = p["rect"]
	var t: Dictionary = cfg.get(which, {}) if which != "painted" else {}
	return {"pos": r.get_center() + v2(t.get("offset", [0, 0])), "rot": float(t.get("rot", 0.0)), "scale": float(t.get("scale", 1.0))}


func _apply(id: String, xf: Dictionary, lift: float = 0.0) -> void:
	var p: Dictionary = parts[id]
	var n: Node2D = p["node"]
	n.position = xf["pos"]
	n.rotation_degrees = float(xf["rot"])
	var s := float(xf["scale"]) * (1.0 + 0.04 * lift)
	n.scale = Vector2(s, s)
	# the shadow lies on the top: offset in canvas px whatever the part's turn
	var off := Vector2(5, 7).lerp(Vector2(16, 24), lift)
	var sh: Array = p["shadows"]
	for i in sh.size():
		var o: Vector2 = off * (1.0 if i == 0 else 1.35)
		(sh[i] as Sprite2D).position = o.rotated(-n.rotation) / s
		(sh[i] as Sprite2D).scale = Vector2.ONE * (1.0 if i == 0 else 1.03)


func _xf_lerp(a: Dictionary, b: Dictionary, x: float) -> Dictionary:
	return {"pos": (a["pos"] as Vector2).lerp(b["pos"], x), "rot": lerpf(float(a["rot"]), float(b["rot"]), x),
		"scale": lerpf(float(a["scale"]), float(b["scale"]), x)}


func _current_xf(id: String) -> Dictionary:
	var n: Node2D = parts[id]["node"]
	var base := float(_xf(id, "rest")["scale"])
	return {"pos": n.position, "rot": n.rotation_degrees, "scale": n.scale.x if n.scale.x > 0 else base}


## Where a part lies now by the story (opened again midway, a load): at rest, in its seat or at the painted place.
func _home(id: String) -> Dictionary:
	var s := step()
	match id:
		"key":
			return _xf(id, "seat") if s >= 1 else _xf(id, "rest")
		"stop":
			return _xf(id, "painted") if s >= 2 else _xf(id, "rest")
		"screw":
			if s >= 4:
				return _xf(id, "painted")
			return _xf(id, "seat") if s >= 3 else _xf(id, "rest")
		"board":
			return _xf(id, "seat") if s >= 5 else _xf(id, "rest")
	return _xf(id, "rest")


func _place_all() -> void:
	for id in parts:
		if _anim.has(id) or id == drag_id:
			continue
		_apply(id, _home(id))
	if step() == 3 and not _turning and drag_id == "":
		_apply_turn()


# --- Steps ---------------------------------------------------------------------------------------

## 0..5: how many steps are done (`steps` — the flags of the five events).
func step() -> int:
	var n := 0
	for f in spec.get("steps", []):
		if not flag(String(f)):
			return n
		n += 1
	return n


## The parts that can be taken on this step.
func movable(s: int) -> Array:
	match s:
		0:
			return ["wedge", "key"]
		1:
			return ["stop"]
		2:
			return ["screw"]
		4:
			return ["board"]
	return []


## The part that belongs to this step's place.
func step_part(s: int) -> String:
	return ["key", "stop", "screw", "", "board"][s] if s < 5 else ""


func flags_changed() -> void:
	if layer != null:
		_place_all()
		_refresh()


func _busy() -> bool:
	return not _anim.is_empty() or _wobble_t >= 0.0 or _check_t >= 0.0 or dialogue_up() or step() >= 5


func _refresh() -> void:
	var s := step()
	var n := mini(s, 4)
	step_label.text = text("label_step%d" % (n + 1)) if s < 5 else text("label_done")
	hint.text = text("label_hint%d" % (n + 1)) if s < 5 else ""
	var zones: Array = spec.get("zones", [])
	var show_zone: bool = s < 5 and s != 3 and s < zones.size() and not zones[s].is_empty()
	zone_fill.visible = show_zone
	zone_line.visible = show_zone
	zone_halo.visible = show_zone
	if show_zone:
		var pts := _points(zones[s])
		zone_fill.polygon = pts
		var closed := PackedVector2Array(pts)
		closed.append(pts[0])
		zone_line.points = closed
		zone_halo.points = closed
	# the ghost: the part's own outline faint on its place (not on step 1 — which fastening fits is the question)
	var gp := step_part(s)
	ghost.visible = gp != "" and s != 0 and parts.has(gp) and parts[gp]["tex"] != null
	if ghost.visible:
		var xf := _xf(gp, "seat" if gp != "stop" else "painted")
		ghost.texture = parts[gp]["tex"]
		ghost.position = xf["pos"]
		ghost.rotation_degrees = float(xf["rot"])
		ghost.scale = Vector2.ONE * float(xf["scale"])
	var turning := s == 3
	ring.visible = turning
	ring_done.visible = turning
	ring_arrow.visible = turning
	_draw_ring()


# --- Input ---------------------------------------------------------------------------------------

func _to_canvas(p: Vector2) -> Vector2:
	return p / k


## The topmost movable part under the point (its painted pixels, not its box).
func part_at(cp: Vector2) -> String:
	var ids := movable(step())
	var best := ""
	var best_i := -1
	for id in ids:
		if not parts.has(id) or _anim.has(id):
			continue
		var n: Node2D = parts[id]["node"]
		if not _hit(id, cp):
			continue
		if n.get_index() > best_i:
			best_i = n.get_index()
			best = id
	return best


func _hit(id: String, cp: Vector2) -> bool:
	var p: Dictionary = parts[id]
	var n: Node2D = p["node"]
	var r: Rect2 = p["rect"]
	var local: Vector2 = n.transform.affine_inverse() * cp + r.size / 2.0
	var grow := float(spec.get("grab_margin", 10.0))
	if local.x < -grow or local.y < -grow or local.x > r.size.x + grow or local.y > r.size.y + grow:
		return false
	var img: Image = p["image"]
	if img == null:
		return true
	# a few pixels round the point: thin parts (the board, the wedge) are easy to catch
	for d in [Vector2.ZERO, Vector2(grow, 0), Vector2(-grow, 0), Vector2(0, grow), Vector2(0, -grow)]:
		var q: Vector2 = local + d
		if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixelv(Vector2i(q)).a > 0.3:
			return true
	return false


## Is the part (dragged, the pointer at `cp`) over the lit place of this step?
func _over_place(id: String, cp: Vector2) -> bool:
	var s := step()
	var zones: Array = spec.get("zones", [])
	if s < zones.size() and not zones[s].is_empty():
		if Geometry2D.is_point_in_polygon(cp, _points(zones[s])) or Geometry2D.is_point_in_polygon(parts[id]["node"].position, _points(zones[s])):
			return true
	var target := _seat_of_step(id)
	return (parts[id]["node"] as Node2D).position.distance_to(target["pos"]) < float(spec.get("snap_r", 90.0))


## Where the dragged part goes on this step (the wedge is tried where the key goes).
func _seat_of_step(id: String) -> Dictionary:
	match id:
		"stop":
			return _xf(id, "painted")
		"wedge":
			return _xf(id, "seat")
	return _xf(id, "seat")


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var cp := _to_canvas(ev.position)
		if ev.pressed:
			if _busy():
				accept_event()
				return
			if step() == 3 and _on_ring(cp):
				accept_event()
				_turning = true
				_turn_last = (cp - _pivot()).angle()
				return
			var id := part_at(cp)
			if id != "":
				accept_event()
				drag_id = id
				_grab_off = (parts[id]["node"] as Node2D).position - cp
				name_tip.visible = false
				_set_lift(id, 1.0)
		else:
			if _turning:
				accept_event()
				_turning = false
			elif drag_id != "":
				accept_event()
				_drop(drag_id, cp)
	elif ev is InputEventMouseMotion:
		var cp2 := _to_canvas(ev.position)
		if drag_id != "":
			accept_event()
			var n: Node2D = parts[drag_id]["node"]
			n.position = cp2 + _grab_off
			_set_lift(drag_id, 1.0)
			over_target = _over_place(drag_id, cp2)
		elif _turning:
			accept_event()
			_turn_by(cp2)
		else:
			_hover(cp2, ev.position)


func _hover(cp: Vector2, screen: Vector2) -> void:
	var id := "" if _busy() else part_at(cp)
	if id != hover_id:
		if hover_id != "" and parts.has(hover_id):
			(parts[hover_id]["img"] as Sprite2D).modulate = Color.WHITE
		hover_id = id
		if id != "":
			(parts[id]["img"] as Sprite2D).modulate = Color(1.12, 1.08, 1.0)
	var on_ring := not _busy() and step() == 3 and _on_ring(cp)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (id != "" or on_ring) else Control.CURSOR_ARROW
	if id != "":
		name_tip.text = StoryData.text(String(parts[id]["cfg"].get("label", id)))
		name_tip.position = Vector2(clampf(screen.x - 130.0, 10.0, 1650.0), clampf(screen.y - 70.0, 120.0, 1000.0))
		name_tip.visible = true
	else:
		name_tip.visible = false


func _set_lift(id: String, lift: float) -> void:
	var n: Node2D = parts[id]["node"]
	var cur := _current_xf(id)
	var base := float(_home(id)["scale"])
	cur["scale"] = base
	_apply(id, cur, lift)
	n.z_index = 10 if lift > 0.0 else 0


func _drop(id: String, cp: Vector2) -> void:
	drag_id = ""
	over_target = false
	var n: Node2D = parts[id]["node"]
	n.z_index = 0
	var from := _current_xf(id)
	from["scale"] = float(_home(id)["scale"])
	if _over_place(id, cp):
		var fits := id == step_part(step())
		var to := _seat_of_step(id)
		if fits:
			_anim[id] = {"from": from, "to": to, "t": 0.0, "dur": 0.16, "then": "seated"}
		else:
			tries_wrong += 1
			_anim[id] = {"from": from, "to": to, "t": 0.0, "dur": 0.16, "then": "wobble"}
	else:
		returns += 1
		_anim[id] = {"from": from, "to": _home(id), "t": 0.0, "dur": 0.38, "then": "back"}


# --- The screw turned by the mouse --------------------------------------------------------------

func _pivot() -> Vector2:
	return v2(spec.get("turn", {}).get("pivot", [1268, 386]))


func _ring_r() -> float:
	return float(spec.get("turn", {}).get("radius", 96.0))


func _on_ring(cp: Vector2) -> bool:
	var d := cp.distance_to(_pivot())
	return d < _ring_r() + 70.0


func _turn_by(cp: Vector2) -> void:
	var a := (cp - _pivot()).angle()
	if cp.distance_to(_pivot()) < 12.0:
		return
	var d := wrapf(a - _turn_last, -PI, PI)
	_turn_last = a
	var turns := float(spec.get("turn", {}).get("turns", 2.0))
	turn_progress = clampf(turn_progress + absf(d) / (TAU * turns), 0.0, 1.0)
	var ticks := int(turn_progress * turns * 4.0)
	if ticks > _turn_ticks:
		_turn_ticks = ticks
		sound("ring_creak")
	_apply_turn()
	_draw_ring()
	if turn_progress >= 1.0 and not _screw_turned:
		_screw_turned = true
		_turning = false
		sound("knock")
		event("tightened")
		_refresh()


## The screw creeps from its seat (set, not yet turned) to the painted place as it is turned; the handle end shakes a
## little with each quarter so the turning reads.
func _apply_turn() -> void:
	if not parts.has("screw"):
		return
	var xf := _xf_lerp(_xf("screw", "seat"), _xf("screw", "painted"), turn_progress)
	xf["rot"] = float(xf["rot"]) + 0.8 * sin(turn_progress * float(spec.get("turn", {}).get("turns", 2.0)) * TAU * 2.0)
	_apply("screw", xf)


func _make_ring() -> void:
	ring = Line2D.new()
	ring.name = "TurnRing"
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.9, 0.6, 0.55)
	ring.texture = _dash_texture()
	ring.texture_mode = Line2D.LINE_TEXTURE_TILE
	ring.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	layer.add_child(ring)
	ring_done = Line2D.new()
	ring_done.name = "TurnDone"
	ring_done.width = 9.0
	ring_done.default_color = Color(1.0, 0.82, 0.38, 0.95)
	ring_done.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ring_done.end_cap_mode = Line2D.LINE_CAP_ROUND
	layer.add_child(ring_done)
	ring_arrow = Polygon2D.new()
	ring_arrow.name = "TurnArrow"
	ring_arrow.color = Color(1.0, 0.86, 0.5, 0.95)
	layer.add_child(ring_arrow)


func _draw_ring() -> void:
	if ring == null:
		return
	var c := _pivot()
	var r := _ring_r()
	var ry := r * 0.78   # the ring lies round the screw's axis, seen a little from above
	var pts := PackedVector2Array()
	for i in 65:
		var a := TAU * i / 64.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * ry))
	ring.points = pts
	var done := PackedVector2Array()
	var span := TAU * turn_progress * float(spec.get("turn", {}).get("turns", 2.0))
	var full := minf(span, TAU)
	var nseg := maxi(2, int(full / TAU * 64.0))
	if turn_progress > 0.0:
		for i in nseg + 1:
			var a2 := -PI / 2.0 + full * i / nseg
			done.append(c + Vector2(cos(a2) * r, sin(a2) * ry))
	ring_done.points = done
	# the arrow at the head of the ring (where to drive next), going round
	var ah := -PI / 2.0 + fmod(span, TAU) + 0.25
	var tip := c + Vector2(cos(ah) * r, sin(ah) * ry)
	var dir := Vector2(-sin(ah) * r, cos(ah) * ry).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	ring_arrow.polygon = PackedVector2Array([tip + dir * 20.0, tip - dir * 10.0 + nrm * 13.0, tip - dir * 10.0 - nrm * 13.0])


# --- Time ----------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_pulse += delta
	var glow := 0.5 + 0.5 * sin(_pulse * 3.4)
	if zone_fill.visible:
		var hot := over_target and drag_id != ""
		zone_fill.color = Color(1.0, 0.88, 0.45, 0.45 if hot else 0.16 + 0.12 * glow)
		zone_line.default_color = Color(1.0, 0.98, 0.85, 1.0) if hot else Color(1.0, 0.92, 0.6, 0.7 + 0.3 * glow)
		zone_line.width = 5.0 if hot else 3.5
		zone_halo.default_color = Color(0.28, 0.13, 0.03, 0.6 if hot else 0.3 + 0.2 * glow)
	if ghost.visible:
		ghost.modulate = Color(1.0, 0.95, 0.8, (0.42 if over_target and drag_id != "" else 0.16 + 0.14 * glow))
	if ring != null and ring.visible:
		ring.modulate.a = 0.6 + 0.4 * glow if not _turning else 1.0
	for id in _anim.keys():
		var a: Dictionary = _anim[id]
		a["t"] = float(a["t"]) + delta
		var x := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var e := 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)   # ease out: quick, then settles
		_apply(id, _xf_lerp(a["from"], a["to"], e), 1.0 - e if String(a["then"]) != "back" else (1.0 - e) * 0.8)
		if x >= 1.0:
			_anim.erase(id)
			_arrived(id, String(a["then"]))
	if _wobble_t >= 0.0:
		_wobble_t += delta
		var w: Node2D = parts["wedge"]["node"]
		var seat := _xf("wedge", "seat")
		w.rotation_degrees = float(seat["rot"]) + 6.0 * sin(_wobble_t * 26.0) * maxf(0.0, 1.0 - _wobble_t / 0.7)
		if _wobble_t >= 0.7:
			_wobble_t = -1.0
			_anim["wedge"] = {"from": _current_xf("wedge"), "to": _home("wedge"), "t": 0.0, "dur": 0.45, "then": "back_quiet"}
	if _check_t >= 0.0:
		# Ilya leans on the board: a short tremble, no give
		_check_t += delta
		var b: Node2D = parts["board"]["node"]
		var seat_b := _xf("board", "seat")
		b.position = (seat_b["pos"] as Vector2) + Vector2(0, 2.5 * sin(_check_t * 40.0) * maxf(0.0, 1.0 - _check_t / 0.5))
		if _check_t >= 0.55:
			_check_t = -1.0
			_apply("board", seat_b)
			sound("knock")
			event("checked")
			_refresh()


func _arrived(id: String, then: String) -> void:
	match then:
		"seated":
			sound("knock")
			var s := step()
			if id == "board":
				_check_t = 0.0
				return
			if s < EVENTS.size():
				event(EVENTS[s])
			if id == "screw":
				turn_progress = 0.0
				_turn_ticks = 0
		"wobble":
			sound("clank")
			_wobble_t = 0.0
			var t := String(parts[id]["cfg"].get("text", ""))
			if t != "":
				say(t)
		"back":
			pass
	_place_all()
	_refresh()


# --- Helpers -------------------------------------------------------------------------------------

static func _points(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


static func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static var _dash: ImageTexture = null


static func _dash_texture() -> ImageTexture:
	if _dash == null:
		var img := Image.create(14, 4, false, Image.FORMAT_RGBA8)
		for x in 14:
			for y in 4:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if x < 8 else 0.0))
		_dash = ImageTexture.create_from_image(img)
	return _dash


func _screen_of(cp: Vector2) -> Dictionary:
	return {"x": cp.x * k, "y": cp.y * k}


## Click targets for tests and the web probe: where each part is now (a point on its painted pixels), where this
## step's part goes, the turning ring.
func probe() -> Dictionary:
	var s := step()
	var ps := {}
	for id in parts:
		var n: Node2D = parts[id]["node"]
		ps[id] = _screen_of(_grab_point(id))
		ps[id]["movable"] = movable(s).has(id)
		ps[id]["home"] = _screen_of(_home(id)["pos"])
		ps[id]["at"] = _screen_of(n.position)
	var target := {}
	var gp := step_part(s)
	if gp != "":
		target = _screen_of(_seat_of_step(gp)["pos"])
	var out := {"step": s, "parts": ps, "target": target, "tries_wrong": tries_wrong, "returns": returns,
		"busy": _busy(), "dragging": drag_id, "over_target": over_target,
		"zone_visible": zone_fill.visible, "ghost_visible": ghost.visible,
		"hint": hint.text, "step_text": step_label.text, "goal": goal.text,
		"stand_in": art_root.get_node_or_null("BenchStandIn") != null,
		"art_parts": parts.values().all(func(p): return p["tex"] != null)}
	if s == 3:
		var c := _pivot()
		out["turn"] = {"pivot": _screen_of(c), "radius": _ring_r() * k, "radius_y": _ring_r() * 0.78 * k,
			"progress": turn_progress, "turning": _turning}
	return out


## A point on the part's painted pixels near its centre (the centre of a thin board may be the edge of the cut-out).
func _grab_point(id: String) -> Vector2:
	var n: Node2D = parts[id]["node"]
	return n.position
