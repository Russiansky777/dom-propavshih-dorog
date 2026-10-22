extends MechanicPanel
## M16, three lights from the pier (R1): Pelageya's signal lantern; each click opens the shutter for a
## moment — a flash. Three flashes and a pause: from the far bank, dark for a year, three lights answer —
## event "answered" (`far_lights_answered`). The snow over there (it is winter there already) shows since the
## knot (`road_held_both_ends`, polish 22.10 A1: the road comes back at the knot, the lights only answer). Any other count — Pelageya
## says how it is done, the count starts again, no penalty.
## Art (партия 3): closeup_lantern_closed / closeup_lantern_open — two full-screen states of the one signal
## lantern on the wet jetty, the far bank dark behind it; a flash shows the open state for a moment. The
## answer from the far bank — three lights and the snow coming through — is drawn by the engine over the
## painting's far bank (soft glows); in the room R1 the delivered layers R1_far_lights / R1_far_snow show it.
## Coordinates: `lantern_box`, `far_lights`, `far_snow` in canvas px (1672×941, shown full screen).

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


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	var k := 1920.0 / 1672.0
	lit = crop(String(art.get("open", "")), full, Vector2.ZERO, k)
	lit.name = "LanternOpen"
	shutter = crop(String(art.get("closed", "")), full, Vector2.ZERO, k)
	shutter.name = "Shutter"
	far_snow = Node2D.new()
	far_snow.name = "FarSnow"
	far_snow.modulate.a = 0.0
	add_child(far_snow)
	for sh in spec.get("far_snow", [[1320, 330, 420, 34], [180, 330, 260, 30]]):
		far_snow.add_child(PlaceholderArt.shape_node({"type": "glow", "center": [float(sh[0]) * k, float(sh[1]) * k],
			"r": float(sh[2]) * k, "ry": float(sh[3]) * k, "color": "#dfe6f2c0"}))
	for q in spec.get("far_lights", [[1090, 338], [1290, 326], [1480, 342]]):
		var gl := PlaceholderArt.glow(v2(q) * k, 30.0, Color(1.0, 0.8, 0.42, 0.95))
		gl.visible = false
		add_child(gl)
		far_lights.append(gl)
	var lb: Array = spec.get("lantern_box", [560, 60, 420, 820])
	lantern_hit = hit_area(Rect2(Vector2(float(lb[0]), float(lb[1])) * k, Vector2(float(lb[2]), float(lb[3])) * k), _on_lantern_input, "LanternHit")
	var fp := v2(spec.get("far_label_pos", [1250, 300]))
	label(text("label_far"), fp, 420)
	label(text("label_count"), v2(spec.get("hint_pos", [1180, 860])), 640)
	far_snow.modulate.a = 0.55 if flag("road_held_both_ends") else 0.0
	if flag("far_lights_answered"):
		answered_sent = true
		_show_answer(1.0)


func _on_lantern_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		flash()


## One flash: the shutter opens for a moment and closes by itself.
func flash() -> void:
	if _open_t >= 0.0:
		return
	_open_t = clock
	shutter.visible = false
	sound("shutter")
	if answered_sent or _answer_t >= 0.0:
		return
	flashes += 1
	_last_flash_t = clock


func tick(_delta: float) -> void:
	if _open_t >= 0.0 and clock - _open_t >= float(spec.get("open_s", 0.45)):
		_open_t = -1.0
		shutter.visible = true
		sound("shutter")
	if not answered_sent and _answer_t < 0.0 and flashes > 0 and _open_t < 0.0 \
			and clock - _last_flash_t >= float(spec.get("pause_s", 1.3)) and not dialogue_up():
		sequence.append(flashes)
		if flashes == int(spec.get("count", 3)):
			_answer_t = clock
		else:
			say("count_wrong")
		flashes = 0
	if _answer_t >= 0.0 and not answered_sent:
		var k := clampf((clock - _answer_t) / float(spec.get("answer_s", 2.4)), 0.0, 1.0)
		_show_answer(k)
		if k >= 1.0:
			answered_sent = true
			event("answered")


## The far bank answers: three lights one after another (the snow is there since the knot).
func _show_answer(k: float) -> void:
	for i in far_lights.size():
		far_lights[i].visible = k >= 0.25 + 0.2 * i


func probe() -> Dictionary:
	var lights := 0
	for l in far_lights:
		if l.visible:
			lights += 1
	return {"lantern": center_of(lantern_hit), "flashes": flashes, "answered": answered_sent, "lights": lights,
		"shutter_open": not shutter.visible, "sequence": sequence.duplicate()}
