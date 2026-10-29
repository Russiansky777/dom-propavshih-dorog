extends MechanicPanel
## M14, the sluice (M4): the key is in the winch. G23 (Director 23.10: «мини-игра с зелёным сектором: попал — ступень
## вперёд, промах — с первой ступени»): the water is let down on the shared «точный удар» bar (TimingBar) — a click
## anywhere on the close-up, on the bar, or Space, when the marker is in the green turns the winch one notch on: the
## lever goes to the next notch of the dial and the water on the gauge falls one step. A miss — the winch slips back
## to the first notch and the water rises to the start; no other penalty, no limit. `timing.hits` steps in a row
## (levels − 1, four) → the lever at the last notch, the water on the red mark → event "opened" (data: sluice_opened,
## pond_lowered — the same flags as before). «Облегчить мини-игры» applies (slower, wider green).
## The journal's rule «по зарубке и ждать»: after each hit the marker holds while the water falls (`timing.hit_s`); a
## strike then is not a miss — Pavel says «Погоди. Пусть сойдёт.».
## G24: the gauge beside the gate has a notch for every step and the red mark on the LAST one (where the water has to
## go); the dial painted on the gate (M4 art) still has its red mark on the third notch — art pack 9.
## A reopened close-up starts from the first notch (the series is the game); the opened sluice shows the lever at
## the last notch and the water down.
## Art: a crop of the delivered M4 painting round the gate and the delivered lever (M4_lever_up) turned by the engine
## about its hub; the gauge is drawn (no gauge at the gate in the art yet).

var logic: SluiceLogic = null
var timing: TimingBar = null
var lever: Sprite2D = null
var socket: Vector2 = Vector2.ZERO
var angles: Array = [-29.0, 0.0, 30.0, 57.0, 86.0]
var lever_angle: float = -29.0
var winch_hit: Control = null
var gauge: Control = null
var gauge_water: ColorRect = null
var work_mark: ColorRect = null
var status_label: Label = null
var refused: int = 0           # strikes while the water was still falling (Pavel: «Погоди»)
var slips: int = 0             # misses: the winch slipped back to the first notch
var opened_sent: bool = false
var _said_wait: bool = false
var _slip_t: float = -1.0      # the status says «сорвался» for a moment after a miss
var _gauge_rect: Rect2 = Rect2()
var overlays: Array[String] = []   # room layers laid over the gate (their art delivered)


static func _room_layer_image(room_id: String, layer_id: String) -> String:
	for l in StoryData.room(room_id).get("layers", []):
		if String(l.get("id", "")) == layer_id:
			return String(l.get("image", ""))
	return ""


func build() -> void:
	var g: Dictionary = spec.get("gate", {})
	var k := float(g.get("scale", 2.0))
	var pos := v2(g.get("pos", [230, 120]))
	var reg: Array = g.get("region", [512, 234, 386, 394])
	crop(String(g.get("image", "")), reg, pos, k).name = "Gate"
	# Room layers on the same canvas laid over the crop by id (G24: the red mark on the LAST notch of the dial —
	# art pack 9, M4_state_dial_mark_last); until the picture is there the painting stays as it is.
	for lid in g.get("overlay_layers", []):
		var img := _room_layer_image(String(g.get("layers_room", "M4")), String(lid))
		if img != "" and ResourceLoader.exists(img):
			crop(img, reg, pos, k).name = "Overlay_" + String(lid)
			overlays.append(String(lid))
	var sock := v2(g.get("socket", [697, 523]))
	socket = pos + (sock - Vector2(float(reg[0]), float(reg[1]))) * k
	angles = spec.get("notch_angles", angles)
	logic = SluiceLogic.new(spec.get("water", {}))
	if angles.size() != logic.levels.size():
		push_error("sluice: notch_angles (%d) and water.levels (%d) differ" % [angles.size(), logic.levels.size()])
	var done := flag(String(spec.get("done_flag", "sluice_opened")))
	if done:
		logic = SluiceLogic.new(spec.get("water", {}), logic.last_notch())
		opened_sent = true
	lever_angle = float(angles[mini(logic.notch, angles.size() - 1)])
	var lv: Dictionary = spec.get("lever", {})
	lever = Sprite2D.new()
	lever.name = "Lever"
	if ResourceLoader.exists(String(lv.get("image", ""))):
		lever.texture = load(String(lv["image"]))
	lever.centered = false
	lever.offset = -v2(lv.get("pivot", [738.5, 610]))
	var ls := k * float(lv.get("scale", 0.7))
	lever.scale = Vector2(ls, ls)
	lever.position = socket
	lever.rotation_degrees = lever_angle
	add_child(lever)
	winch_hit = hit_area(Rect2(pos, Vector2(float(reg[2]), float(reg[3])) * k), _on_winch_input, "Winch")
	_build_gauge()
	# The «точный удар» bar under the gate: one hit — one notch.
	timing = TimingBar.new()
	timing.name = "Timing"
	var tr: Array = spec.get("timing_rect", [250, 950, 730, 50])
	timing.position = Vector2(float(tr[0]), float(tr[1]))
	timing.size = Vector2(float(tr[2]), float(tr[3]))
	add_child(timing)
	var tcfg: Dictionary = spec.get("timing", {}).duplicate()
	tcfg["hits"] = logic.steps()
	timing.setup(tcfg)
	timing.struck.connect(_on_struck)
	timing.early.connect(_on_early)
	timing.visible = not done
	winch_hit.visible = not done
	strike_bar = timing
	status_label = label("", v2(spec.get("status_pos", [1460, 230])), float(spec.get("status_w", 420)))
	_refresh()


func _build_gauge() -> void:
	# The gauge (рейка уровня): the water band, a notch for every step, the red mark on the last one (G24).
	var gr: Array = spec.get("gauge_rect", [1300, 170, 110, 760])
	_gauge_rect = Rect2(float(gr[0]), float(gr[1]), float(gr[2]), float(gr[3]))
	gauge = Control.new()
	gauge.name = "Gauge"
	gauge.position = _gauge_rect.position
	gauge.size = _gauge_rect.size
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gauge)
	# H30: the rail is drawn as painted wood with cut divisions in the carved frame (CarvedFrame.draw_rail); the
	# nodes below keep the level, the notches and the red mark for the probe and the tests, unseen.
	var rail := RailDraw.new()
	rail.name = "Rail"
	rail.panel = self
	rail.size = gauge.size
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(rail)
	gauge_water = ColorRect.new()
	gauge_water.name = "Water"
	gauge_water.visible = false
	gauge_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(gauge_water)
	work_mark = ColorRect.new()
	work_mark.name = "WorkMark"
	work_mark.visible = false
	work_mark.position = Vector2(0, gauge_y(work_level()) - 3.0)
	work_mark.size = Vector2(gauge.size.x, 6)
	work_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(work_mark)
	label(text("label_gauge"), _gauge_rect.position + Vector2(-40, _gauge_rect.size.y + 8), 220, &"CloseupLabel")


## The level of the red mark: data `work_mark`, else the last notch's level (G24: «на последней зарубке»).
func work_level() -> float:
	return float(spec.get("work_mark", logic.levels[logic.last_notch()]))


## Gauge level (0 — bottom, 1 — top) → y in the gauge.
func gauge_y(lv: float) -> float:
	return gauge.size.y * (1.0 - clampf(lv, 0.0, 1.0))


func _on_winch_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if timing.visible:
			strikes_by_click += 1
			timing.strike()


func _on_struck(r: String) -> void:
	match r:
		"hit", "done":
			logic.set_notch(timing.logic.hits if r == "hit" else logic.last_notch())
			lever_angle = float(angles[mini(logic.notch, angles.size() - 1)])
			_said_wait = false
			sound("hammer")
			if r == "done":
				timing.visible = false
				winch_hit.visible = false
		"miss":
			logic.set_notch(0)
			lever_angle = float(angles[0])
			slips += 1
			_slip_t = 0.0
			sound("clank")
			if slips == 1:
				say("slipped")
	_refresh()


## A strike while the water is still falling: «по зарубке и ждать» — Pavel holds the winch (once per step).
func _on_early() -> void:
	refused += 1
	if not _said_wait:
		_said_wait = true
		say("wait")


func tick(delta: float) -> void:
	logic.step(delta)
	if _slip_t >= 0.0:
		_slip_t += delta
		if _slip_t >= 2.5:
			_slip_t = -1.0
	if lever != null:
		lever.rotation_degrees = lerpf(lever.rotation_degrees, lever_angle, clampf(delta * 10.0, 0.0, 1.0))
	_refresh()
	if not opened_sent and logic.finished() and timing.logic != null and timing.logic.done():
		opened_sent = true
		event("opened")


func _refresh() -> void:
	if gauge_water != null:
		var h := gauge.size.y * clampf(logic.level, 0.0, 1.0)
		gauge_water.position = Vector2(0, gauge.size.y - h)
		gauge_water.size = Vector2(gauge.size.x, h)
	if status_label != null:
		var key := "label_status_settled"
		if logic.finished():
			# J-A4 (Директор 29.10, стр. 184): после сумерек вода уже сошла — не «к вечеру сойдёт».
			var drained: bool = (spec.get("texts", {}) as Dictionary).has("label_status_drained") and flag("evening_dusk")
			key = "label_status_drained" if drained else "label_status_open"
		elif _slip_t >= 0.0:
			key = "label_status_slipped"
		elif not logic.settled():
			key = "label_status_falling"
		elif logic.notch == 0:
			key = "label_hint"
		status_label.text = text(key)


func probe() -> Dictionary:
	var tip := socket + Vector2(sin(deg_to_rad(lever_angle)), -cos(deg_to_rad(lever_angle))) * 200.0
	var wr := winch_hit.get_global_rect() if winch_hit != null else Rect2()
	return {"notch": logic.notch, "last": logic.last_notch(), "steps": logic.steps(), "level": logic.level,
		"levels": logic.levels, "settled": logic.settled(), "finished": logic.finished(), "refused": refused, "slips": slips,
		"lever_deg": lever_angle, "lever_tip": {"x": tip.x, "y": tip.y},
		"timing": timing.probe() if timing != null and timing.visible else {},
		"strike": {"x": wr.get_center().x, "y": wr.get_center().y}, "free_click": {"x": 1700.0, "y": 600.0},
		"strikes_by_click": strikes_by_click, "work_mark_level": work_level(),
		"work_mark_at_last": is_equal_approx(work_level(), float(logic.levels[logic.last_notch()])),
		"opened": opened_sent, "overlays": overlays, "last_notch_deg": float(angles[angles.size() - 1])}


## The gauge drawn as a painted wooden rail (H30).
class RailDraw extends Control:
	var panel = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if panel == null or panel.logic == null:
			return
		CarvedFrame.draw_rail(self, Rect2(Vector2.ZERO, size), panel.logic.level, panel.logic.levels, panel.work_level(), UiTheme.font("head_bold"))
