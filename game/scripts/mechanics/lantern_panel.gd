extends MechanicPanel
## M16, three lights from the pier (R1): Pelageya's signal lantern; each click opens the shutter for a
## moment — a flash. Three flashes and a pause: from the far bank, dark for a year, three lights answer and
## snow shows through (it is winter there already) — event "answered" (`far_lights_answered`,
## `road_held_both_ends`: the road is held from both ends, time is common). Any other count — Pelageya
## says how it is done, the count starts again, no penalty.
## Stand-in art until «R1_lantern_closed/open, R1_far_dark/snow/lights» (BRIEF_CHATGPT_v4 §C6): crops of the
## delivered R1 painting (the lantern; the far bank), darkness, snow and lights drawn by the engine.

var shutter: ColorRect = null
var lamp_glow: Sprite2D = null
var lantern_hit: Control = null
var far: Control = null
var far_dark: ColorRect = null
var far_snow: ColorRect = null
var far_lights: Array[Sprite2D] = []
var flashes: int = 0
var answered_sent: bool = false
var sequence: Array[int] = []    # counts that were judged (tests)
var _open_t: float = -1.0
var _last_flash_t: float = -100.0
var _answer_t: float = -1.0
var _glass: Rect2 = Rect2()


func build() -> void:
	var ln: Dictionary = spec.get("lantern", {})
	var lpos := v2(ln.get("pos", [260, 200]))
	var lk := float(ln.get("scale", 4.5))
	var lreg: Array = ln.get("region", [286, 95, 98, 158])
	crop(String(ln.get("image", "")), lreg, lpos, lk).name = "Lantern"
	var g: Array = ln.get("glass", [404, 438, 156, 333])
	_glass = Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3]))
	lamp_glow = PlaceholderArt.glow(_glass.get_center(), _glass.size.y * 0.9, Color(1.0, 0.75, 0.35, 0.85))
	lamp_glow.name = "Flame"
	add_child(lamp_glow)
	shutter = ColorRect.new()
	shutter.name = "Shutter"
	shutter.color = Color(0.13, 0.11, 0.1)
	shutter.position = _glass.position
	shutter.size = _glass.size
	shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shutter)
	lantern_hit = hit_area(Rect2(lpos, Vector2(float(lreg[2]), float(lreg[3])) * lk), _on_lantern_input, "LanternHit")
	# The far bank (the delivered R1 painting), dark for a year.
	var fb: Dictionary = spec.get("far", {})
	var fpos := v2(fb.get("pos", [860, 300]))
	var fk := float(fb.get("scale", 1.1))
	var freg: Array = fb.get("region", [783, 243, 871, 148])
	far = Control.new()
	far.name = "FarBank"
	far.position = fpos
	far.size = Vector2(float(freg[2]), float(freg[3])) * fk
	far.clip_contents = true
	far.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(far)
	crop(String(fb.get("image", "")), freg, Vector2.ZERO, fk, far)
	far_dark = ColorRect.new()
	far_dark.color = Color(0.04, 0.05, 0.08, 0.82)
	far_dark.size = far.size
	far_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	far.add_child(far_dark)
	far_snow = ColorRect.new()
	far_snow.color = Color(0.92, 0.94, 1.0, 0.0)
	far_snow.size = far.size
	far_snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	far.add_child(far_snow)
	for p in fb.get("lights", [[260, 70], [420, 60], [600, 78]]):
		var gl := PlaceholderArt.glow(v2(p), 34, Color(1.0, 0.8, 0.4, 0.95))
		gl.visible = false
		far.add_child(gl)
		far_lights.append(gl)
	label(text("label_far"), fpos + Vector2(0, far.size.y + 10), far.size.x)
	label(text("label_count"), v2(spec.get("hint_pos", [860, 640])), 900)
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


## The far bank answers: three lights one after another, the darkness lifts and the snow shows.
func _show_answer(k: float) -> void:
	for i in far_lights.size():
		far_lights[i].visible = k >= 0.25 + 0.2 * i
	far_dark.color.a = lerpf(0.82, 0.25, k)
	far_snow.color.a = lerpf(0.0, 0.35, k)


func probe() -> Dictionary:
	var lights := 0
	for l in far_lights:
		if l.visible:
			lights += 1
	return {"lantern": center_of(lantern_hit), "flashes": flashes, "answered": answered_sent, "lights": lights,
		"shutter_open": not shutter.visible, "sequence": sequence.duplicate()}
