extends MechanicPanel
## M14, the sluice (M4): the key is in the winch; the lever goes notch by notch along the dial (drag it, or
## click past it), and after each notch the gauge shows the water falling. The next notch only once the
## fall has settled — before that Pavel holds the winch («Разом нельзя»); a drag past the next notch stops
## at it. The opened notches are saved (GameState counter `mech.sluice.notch`), so a load or a reopened
## close-up keeps them; the last notch settled → event "opened".
## Stand-in art: a crop of the delivered M4 painting round the gate and the delivered lever (M4_lever_up)
## turned by the engine about its hub; the gauge is drawn (no gauge at the gate in the art yet).

const COUNTER := "mech.sluice.notch"

var logic: SluiceLogic = null
var lever: Sprite2D = null
var socket: Vector2 = Vector2.ZERO
var angles: Array = [-29.0, 0.0, 30.0, 57.0]
var lever_angle: float = -29.0
var dial_hit: Control = null
var gauge: Control = null
var gauge_water: ColorRect = null
var status_label: Label = null
var refused: int = 0           # how many times Pavel held the winch (tests)
var opened_sent: bool = false
var _dragging: bool = false
var _spring: float = 0.0       # lever springing back to the current notch after a refused try
var _gauge_rect: Rect2 = Rect2()


func build() -> void:
	var g: Dictionary = spec.get("gate", {})
	var k := float(g.get("scale", 2.1))
	var pos := v2(g.get("pos", [260, 130]))
	var reg: Array = g.get("region", [512, 234, 386, 394])
	crop(String(g.get("image", "")), reg, pos, k).name = "Gate"
	var sock := v2(g.get("socket", [697, 523]))
	socket = pos + (sock - Vector2(float(reg[0]), float(reg[1]))) * k
	angles = spec.get("notch_angles", angles)
	logic = SluiceLogic.new(spec.get("water", {}), GameState.get_counter(COUNTER))
	if flag(String(spec.get("done_flag", "sluice_opened"))):
		logic = SluiceLogic.new(spec.get("water", {}), logic.last_notch())
		opened_sent = true
	lever_angle = float(angles[logic.notch])
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
	add_child(lever)
	dial_hit = hit_area(Rect2(socket - Vector2(380, 420), Vector2(760, 520)), _on_dial_input, "Dial")
	# The gauge (рейка уровня): water band, ticks, the working mark of the journal.
	var gr: Array = spec.get("gauge_rect", [1300, 170, 110, 760])
	_gauge_rect = Rect2(float(gr[0]), float(gr[1]), float(gr[2]), float(gr[3]))
	gauge = Control.new()
	gauge.name = "Gauge"
	gauge.position = _gauge_rect.position
	gauge.size = _gauge_rect.size
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gauge)
	var board := ColorRect.new()
	board.color = Color(0.78, 0.72, 0.6)
	board.size = gauge.size
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(board)
	gauge_water = ColorRect.new()
	gauge_water.name = "Water"
	gauge_water.color = Color(0.22, 0.34, 0.42, 0.85)
	gauge_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(gauge_water)
	for i in 11:
		var t := ColorRect.new()
		t.color = Color(0.15, 0.1, 0.06)
		t.position = Vector2(0, gauge.size.y * float(i) / 10.0 - 1.5)
		t.size = Vector2(gauge.size.x * (0.6 if i % 5 == 0 else 0.35), 3)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gauge.add_child(t)
	var mark := ColorRect.new()
	mark.name = "WorkMark"
	mark.color = Color(0.7, 0.12, 0.08)
	mark.position = Vector2(0, gauge.size.y * (1.0 - float(spec.get("work_mark", 0.9))) - 2)
	mark.size = Vector2(gauge.size.x, 5)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(mark)
	label(text("label_gauge"), _gauge_rect.position + Vector2(-40, _gauge_rect.size.y + 8), 220, &"CloseupLabel")
	status_label = label("", v2(spec.get("status_pos", [260, 980])), 1100)
	_refresh()


func next_angle() -> float:
	return float(angles[mini(logic.notch + 1, angles.size() - 1)])


## Try to open one more notch (the lever brought to it). Returns the logic's answer.
func try_open() -> String:
	var r := logic.open_next()
	match r:
		"ok":
			GameState.set_counter(COUNTER, logic.notch)
			lever_angle = float(angles[logic.notch])
			sound("hammer")
			RoomManager.autosave()
		"wait":
			refused += 1
			_spring = 1.0
			say("wait")
	_refresh()
	return r


func _on_dial_input(ev: InputEvent) -> void:
	if opened_sent:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if ev.pressed:
			_dragging = true
		elif _dragging:
			_dragging = false
			var want := _angle_at(dial_hit.position + ev.position)
			if want >= next_angle() - 8.0 and logic.notch < logic.last_notch():
				try_open()
			else:
				lever_angle = float(angles[logic.notch])
				_refresh()
	elif ev is InputEventMouseMotion and _dragging:
		accept_event()
		# The lever follows the hand, but never past the next notch (one notch at a time).
		lever_angle = clampf(_angle_at(dial_hit.position + ev.position), float(angles[logic.notch]), next_angle())
		_refresh()


func _angle_at(p: Vector2) -> float:
	var d := p - socket
	return rad_to_deg(atan2(d.x, -d.y))


func tick(delta: float) -> void:
	logic.step(delta)
	if _spring > 0.0:
		_spring = maxf(_spring - delta * 3.0, 0.0)
		lever_angle = lerpf(float(angles[logic.notch]), float(angles[logic.notch]) + 6.0, _spring)
	_refresh()
	if not opened_sent and logic.finished():
		opened_sent = true
		event("opened")


func _refresh() -> void:
	if lever != null:
		lever.rotation_degrees = lever_angle
	if gauge_water != null:
		var h := gauge.size.y * clampf(logic.level, 0.0, 1.0)
		gauge_water.position = Vector2(0, gauge.size.y - h)
		gauge_water.size = Vector2(gauge.size.x, h)
	if status_label != null:
		var key := "label_status_settled"
		if logic.finished():
			key = "label_status_open"
		elif not logic.settled():
			key = "label_status_falling"
		status_label.text = text(key)


func probe() -> Dictionary:
	var tip := socket + Vector2(sin(deg_to_rad(lever_angle)), -cos(deg_to_rad(lever_angle))) * 200.0
	var nxt := socket + Vector2(sin(deg_to_rad(next_angle())), -cos(deg_to_rad(next_angle()))) * 200.0
	var far := socket + Vector2(sin(deg_to_rad(float(angles[angles.size() - 1]))), -cos(deg_to_rad(float(angles[angles.size() - 1])))) * 200.0
	return {"notch": logic.notch, "last": logic.last_notch(), "level": logic.level, "settled": logic.settled(),
		"finished": logic.finished(), "refused": refused, "lever_deg": lever_angle,
		"lever_tip": {"x": tip.x, "y": tip.y}, "next_notch": {"x": nxt.x, "y": nxt.y}, "last_notch_point": {"x": far.x, "y": far.y}}
