extends MechanicPanel
## M16, three lights from the pier (R1): Pelageya's signal lantern; each click opens the shutter for a
## moment — a flash. Three flashes and a pause: from the far bank, dark for a year, a lantern answers the same way
## (J, стр. 130: one light flashes three times and stays lit) —
## event "answered" (`far_lights_answered`). The snow over there (it is winter there already) shows since the
## knot (`road_held_both_ends`, polish 22.10 A1: the road comes back at the knot, the lights only answer). Any other count — Pelageya
## says how it is done, the count starts again, no penalty.
## Timing (Director playtest 23.10, AI gate M2 item 16): a player gives the three signals deliberately, a second or
## two apart — so the series is judged only after `pause_s` (3 s) of quiet with fewer than three, right after the
## third flash plus `confirm_s` (0.9 s, room for a fourth) when there are three, and at once on a fourth. A row of
## marks under the hint shows the flashes given so far.
## Art (партия 3): closeup_lantern_closed / closeup_lantern_open — two full-screen states of the one signal
## lantern on the wet jetty, the far bank dark behind it; a flash shows the open state for a moment. The
## answer from the far bank — three lights and the snow coming through — is drawn by the engine over the
## painting's far bank (soft glows); in the room R1 the delivered layers R1_far_lights / R1_far_snow show it.
## Coordinates: `lantern_box`, `far_lights`, `far_snow` in canvas px (1672×941, shown full screen).
## H35 (Director 24.10: «поднятие крышки фонаря сделать мышкой, чтобы он тянулся-открывался, с нормальной анимацией»):
## the shutter plate is lifted by the mouse — press on it and pull up; the plate (`lid.box` of the closed picture)
## follows the pointer up to `lid.lift` px, sliding behind the lantern's top (`lid.housing`) and baring the flame
## (the open picture under it). Let go below `lid.open_at` — it slides back down by itself; pulled up to the end —
## it opens (that is the flash), stays open `open_s` and drops back. A click without pulling opens nothing — the hint
## «потяни вверх» flashes. `flash()` stays for tests and bots (the same as a full pull).

var shutter: TextureRect = null      # the closed state; hidden while the shutter is open
var lit: TextureRect = null          # the open state (flame in the glass)
var lantern_hit: Control = null
var far_snow: Node2D = null
var far_lights: Array[Node2D] = []
var flashes: int = 0
var answered_sent: bool = false
var sequence: Array[int] = []    # counts that were judged (tests)
var _open_t: float = -1.0
var _last_flash_t: float = -100.0
var _answer_t: float = -1.0
var marks: Label = null           # «● ○ ○» — the flashes given in this series
var lid_f: float = 0.0            # how far the shutter plate is up: 0 — closed, 1 — open
var lid: TextureRect = null       # the plate (closed picture's crop), moves up inside LidClip
var lid_open: TextureRect = null  # the open picture over all once the plate is up (its light, the plate seen above)
var housing: TextureRect = null   # the lantern's top (closed picture): the plate slides behind it
var drag_hint: Label = null
var dragging: bool = false
var drag_y0: float = 0.0
var drag_px: float = 260.0        # screen px of pulling for the whole lift
var _lid_target: float = -1.0     # the plate slides on its own toward this (−1 — it follows the mouse / rests)
var _hint_t: float = -100.0
var drag_clicks: int = 0          # presses released without a pull (tests)


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	var k := 1920.0 / 1672.0
	lit = crop(String(art.get("open", "")), full, Vector2.ZERO, k)
	lit.name = "LanternOpen"
	shutter = crop(String(art.get("closed", "")), full, Vector2.ZERO, k)
	shutter.name = "Shutter"
	_build_lid(art, k)
	far_snow = Node2D.new()
	far_snow.name = "FarSnow"
	far_snow.modulate.a = 0.0
	add_child(far_snow)
	for sh in spec.get("far_snow", [[1320, 330, 420, 34], [180, 330, 260, 30]]):
		far_snow.add_child(PlaceholderArt.shape_node({"type": "glow", "center": [float(sh[0]) * k, float(sh[1]) * k],
			"r": float(sh[2]) * k, "ry": float(sh[3]) * k, "color": "#dfe6f2c0"}))
	# J (Director 29.10, стр. 130): the far bank answers like us — one lantern flashes `count` times, then stays lit
	# (it was three separate lights). `far_light` [x, y]; the old `far_lights` list — its middle point.
	var fl: Array = spec.get("far_light", [])
	if fl.is_empty():
		var old: Array = spec.get("far_lights", [[1290, 326]])
		fl = old[old.size() / 2]
	var gl := PlaceholderArt.glow(v2(fl) * k, 30.0, Color(1.0, 0.8, 0.42, 0.95))
	gl.visible = false
	add_child(gl)
	far_lights.append(gl)
	var lb: Array = spec.get("lantern_box", [560, 60, 420, 820])
	lantern_hit = hit_area(Rect2(Vector2(float(lb[0]), float(lb[1])) * k, Vector2(float(lb[2]), float(lb[3])) * k), _on_lantern_input, "LanternHit")
	var fp := v2(spec.get("far_label_pos", [1250, 300]))
	label(text("label_far"), fp, 420)
	var hp := v2(spec.get("hint_pos", [1180, 860]))
	label(text("label_count"), hp, 640)
	marks = label("", hp + Vector2(0, 84), 640)   # under the two lines of the hint
	marks.name = "FlashMarks"
	drag_hint = label(text("label_drag"), hp + Vector2(0, -50), 640)
	drag_hint.name = "DragHint"
	far_snow.modulate.a = 0.55 if flag("road_held_both_ends") else 0.0
	if flag("far_lights_answered"):
		answered_sent = true
		_show_answer(INF)
	_update_marks()


## The plate: the closed picture under everything; over its window the open picture's window (the flame) — bared as
## the plate (a crop of the closed picture) slides up inside its clip, behind the lantern's top (the closed
## picture's housing, over it); the whole open picture fades in at the top of the lift.
func _build_lid(art: Dictionary, k: float) -> void:
	var ld: Dictionary = spec.get("lid", {})
	var box: Array = ld.get("box", [696, 340, 228, 355])
	var win: Array = ld.get("window", [696, 340, 228, 330])
	var clip: Array = ld.get("clip", [690, 180, 240, 520])
	var hs: Array = ld.get("housing", [640, 180, 340, 162])
	drag_px = float(ld.get("drag_px", 260.0))
	crop(String(art.get("open", "")), win, Vector2(float(win[0]), float(win[1])) * k, k).name = "OpenWindow"
	var lc := Control.new()
	lc.name = "LidClip"
	lc.position = Vector2(float(clip[0]), float(clip[1])) * k
	lc.size = Vector2(float(clip[2]), float(clip[3])) * k
	lc.clip_contents = true
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lc)
	lid = crop(String(art.get("closed", "")), box, (Vector2(float(box[0]), float(box[1])) - Vector2(float(clip[0]), float(clip[1]))) * k, k, lc)
	lid.name = "Lid"
	lid.set_meta("rest_y", lid.position.y)
	housing = crop(String(art.get("closed", "")), hs, Vector2(float(hs[0]), float(hs[1])) * k, k)
	housing.name = "Housing"
	lid_open = crop(String(art.get("open", "")), [0, 0, 1672, 941], Vector2.ZERO, k)
	lid_open.name = "OpenFull"
	lid_open.modulate.a = 0.0
	lit.visible = false   # the open picture is now the plate's top state (OpenFull)


func _set_lid(f: float) -> void:
	lid_f = clampf(f, 0.0, 1.0)
	if lid == null:
		return
	var k := 1920.0 / 1672.0
	var lift := float(spec.get("lid", {}).get("lift", 315.0)) * k
	lid.position.y = float(lid.get_meta("rest_y")) - lid_f * lift
	var top := float(spec.get("lid", {}).get("fade_from", 0.8))
	lid_open.modulate.a = smoothstep(top, 1.0, lid_f)


## Mouse on the plate: press — take it; drag up — it follows; let go — it opens (pulled far enough) or slides back.
func _on_lantern_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if ev.pressed:
			if _open_t >= 0.0:
				return
			# Caught while sliding back: it goes on from where it is.
			_lid_target = -1.0
			dragging = true
			drag_y0 = ev.position.y + lid_f * drag_px
		elif dragging:
			dragging = false
			_release_lid()
	elif ev is InputEventMouseMotion and dragging:
		accept_event()
		_set_lid((drag_y0 - ev.position.y) / maxf(drag_px, 1.0))
		if lid_f >= 1.0:
			dragging = false
			flash()


func _release_lid() -> void:
	if lid_f >= float(spec.get("lid", {}).get("open_at", 0.8)):
		flash()
		return
	if lid_f < 0.04:
		drag_clicks += 1
		_hint_t = clock   # a click without a pull: «потяни вверх»
	_lid_target = 0.0     # not far enough: it slides back down


## One flash: the plate goes up to the end (the shutter opens), stays a moment and drops back by itself.
func flash() -> void:
	if _open_t >= 0.0:
		return
	_open_t = clock
	_lid_target = 1.0
	sound("shutter")
	if answered_sent or _answer_t >= 0.0:
		return
	flashes += 1
	_last_flash_t = clock
	_update_marks()
	if flashes > int(spec.get("count", 3)):
		_judge()


func tick(delta: float) -> void:
	# The plate slides on its own: up to the end on a flash, back down when let go or after the flash.
	if _lid_target >= 0.0 and not dragging:
		var sp := 1.0 / maxf(float(spec.get("lid", {}).get("open_anim_s" if _lid_target > lid_f else "fall_s", 0.3)), 0.01)
		_set_lid(move_toward(lid_f, _lid_target, sp * delta))
		if is_equal_approx(lid_f, _lid_target):
			_lid_target = -1.0
	if drag_hint != null:
		var hk := clampf(1.0 - (clock - _hint_t) / 1.2, 0.0, 1.0)
		drag_hint.modulate = Color(1.0, 1.0 - 0.25 * hk, 1.0 - 0.6 * hk, 1.0)
		drag_hint.scale = Vector2.ONE * (1.0 + 0.06 * hk)
	if _open_t >= 0.0 and clock - _open_t >= float(spec.get("open_s", 0.45)) and lid_f >= 1.0:
		_open_t = -1.0
		_lid_target = 0.0
		sound("shutter")
	if not answered_sent and _answer_t < 0.0 and flashes > 0 and _open_t < 0.0 and not dialogue_up():
		var quiet := clock - _last_flash_t
		var need := int(spec.get("count", 3))
		if (flashes == need and quiet >= float(spec.get("confirm_s", 0.9))) \
				or (flashes < need and quiet >= float(spec.get("pause_s", 3.0))):
			_judge()
	if _answer_t >= 0.0 and not answered_sent:
		var t := clock - _answer_t
		_show_answer(t)
		if t >= answer_seconds():
			answered_sent = true
			event("answered")


## The series is over: exactly three — the far bank answers; any other count — Pelageya says how, start again.
func _judge() -> void:
	sequence.append(flashes)
	if flashes == int(spec.get("count", 3)):
		_answer_t = clock
	else:
		say("count_wrong")
	flashes = 0
	_update_marks()


func _update_marks() -> void:
	if marks == null:
		return
	var need := int(spec.get("count", 3))
	if answered_sent or _answer_t >= 0.0:
		marks.text = "● ● ●"
		return
	var parts: Array[String] = []
	for i in need:
		parts.append("●" if i < flashes else "○")
	marks.text = " ".join(parts)


## The far bank answers (стр. 130): after `answer_delay_s` one lantern flashes `count` times — `answer_on_s` lit,
## `answer_off_s` dark — then stays lit (the snow is there since the knot). `t` — seconds since the answer began;
## INF — answered before (the panel reopened): lit.
func _show_answer(t: float) -> void:
	var lit_now := true
	var delay := float(spec.get("answer_delay_s", 0.8))
	var on_s := float(spec.get("answer_on_s", spec.get("open_s", 0.45)))
	var period := on_s + float(spec.get("answer_off_s", 0.55))
	var n := int(spec.get("count", 3))
	if t < delay:
		lit_now = false
	elif t < delay + n * period:
		lit_now = fmod(t - delay, period) < on_s
	for l in far_lights:
		l.visible = lit_now


## Seconds from the right count to the event «answered»: the flashes, then the light held a moment.
func answer_seconds() -> float:
	var on_s := float(spec.get("answer_on_s", spec.get("open_s", 0.45)))
	var period := on_s + float(spec.get("answer_off_s", 0.55))
	return float(spec.get("answer_delay_s", 0.8)) + int(spec.get("count", 3)) * period + float(spec.get("answer_hold_s", 1.0))


func probe() -> Dictionary:
	var lights := 0
	for l in far_lights:
		if l.visible:
			lights += 1
	var lc := center_of(lid) if lid != null else center_of(lantern_hit)
	return {"lantern": center_of(lantern_hit), "flashes": flashes, "answered": answered_sent, "lights": lights,
		"shutter_open": lid_f > 0.02 or _open_t >= 0.0, "sequence": sequence.duplicate(), "lid": lid_f,
		"dragging": dragging, "drag_clicks": drag_clicks,
		# How to give a flash (bots, web checks): press on the plate and pull it up by `pull` px, then let go.
		"lid_drag": {"x": lc.get("x", 0), "y": lc.get("y", 0), "pull": drag_px + 20.0, "how": "drag_up"}}
