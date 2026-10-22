extends MechanicPanel
## M10–M12, the workshop (H2): the office mirror clamped in Dunya's stand «ЗМ» and the mill bell beside it.
##   1. Two wedges (clicks) clamp the frame — the glass clears and shows the office now (OfficeView in a
##      SubViewport; UPDATE_ALWAYS, so a change at the mill is in the glass the same frame). Event "clamped".
##   2. With the clapper hung (`bell_clapper_hung`), one strike: Pavel's lantern lights the gap at once —
##      the same frame as the strike (canon: the mirror shows now; test_day2 checks the frame numbers).
##      Event "lantern".
##   3. The hook (HookPuzzle): the bell's presses become the mill signals (BellSignal): one — go on, two —
##      stop, long — lift. Wrong — the hook slips and comes back to the top, no penalty. Event "unbolted".
## The bell is pressed with the mouse: a click is a strike, a press held ~0.6 s is the long ring.

var office: OfficeView = null
var office_vp: SubViewport = null
var glass: TextureRect = null
var glass_rect: Rect2 = Rect2()
var bell: TextureRect = null
var bell_hit: Control = null
var wedges: Array[Control] = []
var wedge_in: Array[bool] = [false, false]
var status_label: Label = null
var signal_parser: BellSignal = null
var hook: HookPuzzle = null
var strike_frame: int = -1      # process frame of the last strike (press on the bell)
var light_frame: int = -1       # process frame the lantern light came on in the glass
var signals_seen: Array[String] = []
var _bell_swing: float = 0.0
var _status: String = ""


func build() -> void:
	var fr: Dictionary = spec.get("frame", {})
	var gl: Array = fr.get("glass", [513, 308, 297, 582])
	glass_rect = Rect2(float(gl[0]), float(gl[1]), float(gl[2]), float(gl[3]))
	# The frame and the stand: Dunya's workshop painting round the empty stand; the glass covers its opening.
	var frame_tr := crop(String(fr.get("image", "")), fr.get("region", [960, 92, 262, 512]), v2(fr.get("pos", [420, 130])), float(fr.get("scale", 1.758)))
	frame_tr.name = "Frame"
	# The office now, behind the glass.
	office_vp = SubViewport.new()
	office_vp.name = "OfficeNow"
	office_vp.size = Vector2i(int(glass_rect.size.x), int(glass_rect.size.y))
	office_vp.disable_3d = true
	office_vp.transparent_bg = false
	office_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(office_vp)
	office = OfficeView.new()
	office.name = "Office"
	var os: Dictionary = spec.get("office", {}).duplicate()
	os["size"] = [glass_rect.size.x, glass_rect.size.y]
	office.setup(os)
	office_vp.add_child(office)
	glass = TextureRect.new()
	glass.name = "Glass"
	glass.texture = office_vp.get_texture()
	glass.position = glass_rect.position
	glass.size = glass_rect.size
	glass.mouse_filter = Control.MOUSE_FILTER_STOP
	glass.gui_input.connect(_on_glass_input)
	add_child(glass)
	var sheen := ColorRect.new()
	sheen.name = "Sheen"
	sheen.color = Color(0.85, 0.9, 1.0, 0.07)
	sheen.position = glass_rect.position
	sheen.size = glass_rect.size
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheen)
	# Wedges at the foot of the frame.
	var wp: Array = spec.get("wedges", [[492, 900], [830, 900]])
	for i in wp.size():
		var c := hit_area(Rect2(v2(wp[i]) - Vector2(30, 26), Vector2(60, 52)), _on_wedge_input.bind(i), "Wedge%d" % i)
		var tri := Polygon2D.new()
		tri.name = "Shape"
		tri.color = Color(0.55, 0.38, 0.2)
		var dir := 1.0 if i == 0 else -1.0
		tri.polygon = PackedVector2Array([Vector2(30 - 26 * dir, 8), Vector2(30 + 26 * dir, 18), Vector2(30 - 26 * dir, 30)])
		c.add_child(tri)
		wedges.append(c)
	# The bell.
	var bs: Dictionary = spec.get("bell", {})
	bell = crop(String(bs.get("image", "")), bs.get("region", [1376, 252, 192, 236]), v2(bs.get("pos", [1150, 250])), float(bs.get("scale", 1.7)))
	bell.name = "Bell"
	bell.pivot_offset = Vector2(bell.size.x * 0.5, 0)
	bell_hit = hit_area(Rect2(bell.position, bell.size), _on_bell_input, "BellHit")
	signal_parser = BellSignal.new(bs.get("signal", {}))
	var card := PanelContainer.new()
	card.name = "Schedule"
	card.position = v2(spec.get("schedule_pos", [1120, 690]))
	card.size = Vector2(560, 150)
	card.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.86, 0.80, 0.66, 0.96), Color(0.4, 0.3, 0.18), 18, 12))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var cl := Label.new()
	cl.text = text("label_schedule")
	cl.add_theme_color_override("font_color", Color(0.22, 0.15, 0.08))
	cl.add_theme_font_override("font", UiTheme.font("body"))
	cl.add_theme_font_size_override("font_size", 26)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(cl)
	status_label = label("", v2(spec.get("status_pos", [1120, 870])), 640)
	hook = HookPuzzle.new(spec.get("hook", {}))
	hook.event.connect(_on_hook_event)
	_sync_from_flags()


func opened() -> void:
	if clamped():
		say("view_first" if not flag("lantern_check_seen") else "view_again")


func clamped() -> bool:
	return flag(String(spec.get("clamped_flag", "office_mirror_clamped")))


func _sync_from_flags() -> void:
	for i in wedges.size():
		wedge_in[i] = clamped()
		_place_wedge(i)
	office.light_on = flag("lantern_check_seen") and not flag("office_unbolted")
	office.hook_visible = flag("lantern_check_seen") and not flag("office_unbolted")
	office.door_given = flag("office_unbolted")
	office.bar_lift = 1.0 if flag("office_unbolted") else 0.0
	office.shelf_down = not flag("office_shelf_lifted")
	office.refresh()
	_set_status()


func _place_wedge(i: int) -> void:
	var tri: Polygon2D = wedges[i].get_node("Shape")
	tri.position = Vector2((14.0 if i == 0 else -14.0) if wedge_in[i] else 0.0, 0)


# --- Input ----------------------------------------------------------------------------------

func _on_wedge_input(ev: InputEvent, i: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if wedge_in[i]:
		return
	wedge_in[i] = true
	_place_wedge(i)
	sound("hammer")
	if wedge_in.all(func(x): return x) and not clamped():
		event("clamped")
		office.refresh()


func _on_glass_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		say("glass_touch" if clamped() else "glass_loose")


func _on_bell_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if ev.pressed:
		bell_press()
	else:
		bell_release()


## Mouse down on the bell: the strike. In the lantern stage Pavel's light is in the glass in this very frame.
func bell_press() -> void:
	if not flag("bell_clapper_hung"):
		say("bell_mute")
		return
	if not clamped():
		say("bell_unclamped")
		return
	strike_frame = Engine.get_process_frames()
	sound("bell")
	_bell_swing = 1.0
	if not flag("lantern_check_seen"):
		office.light_on = true
		office.refresh()
		light_frame = Engine.get_process_frames()
		event("lantern")
		office.hook_visible = true
		office.refresh()
		_set_status()
		return
	if hook_active():
		_handle_signals(signal_parser.press(clock))


func bell_release() -> void:
	if hook_active():
		_handle_signals(signal_parser.release(clock))


func hook_active() -> bool:
	return clamped() and flag("lantern_check_seen") and not flag("office_unbolted") and not hook.solved()


func _handle_signals(sigs: Array[String]) -> void:
	for s in sigs:
		signals_seen.append(s)
		if s == "long":
			sound("bell_long")
		hook.apply(s)
	if not sigs.is_empty():
		_set_status()


func tick(delta: float) -> void:
	if hook_active():
		_handle_signals(signal_parser.tick(clock))
		hook.step(delta)
		office.hook_frac = hook.pos
		office.bar_lift = hook.lift_amount if hook.state == "lift_bar" else 0.0
		office.refresh()
	if _bell_swing > 0.0:
		_bell_swing = maxf(_bell_swing - delta * 1.6, 0.0)
		bell.rotation_degrees = sin(clock * 14.0) * 6.0 * _bell_swing
	if not clamped() and glass != null:
		glass.modulate = Color(1, 1, 1, 0.22)
		glass.position = glass_rect.position + Vector2(sin(clock * 9.0) * 3.0, cos(clock * 7.0) * 2.0)
	elif glass != null and glass.modulate.a < 1.0:
		glass.modulate = Color(1, 1, 1, 1)
		glass.position = glass_rect.position


func _on_hook_event(name: String) -> void:
	match name:
		"slipped":
			say("hook_slipped")
		"solved":
			office.door_given = true
			office.hook_visible = false
			office.light_on = false
			office.bar_lift = 1.0
			office.refresh()
			event("unbolted")
	_set_status()


func _set_status() -> void:
	var key := "label_status_wait"
	if not clamped():
		key = "label_status_loose"
	elif not flag("lantern_check_seen"):
		key = "label_status_ring_once"
	elif flag("office_unbolted") or (hook != null and hook.solved()):
		key = "label_status_open"
	elif hook != null:
		key = "label_status_" + hook.state
	_status = key
	if status_label != null:
		status_label.text = text(key)


# --- Probe ----------------------------------------------------------------------------------

func probe() -> Dictionary:
	var out := {"clamped": clamped(), "bell": center_of(bell_hit), "glass": center_of(glass),
		"light": office.light_on if office != null else false, "status": _status,
		"strike_frame": strike_frame, "light_frame": light_frame, "signals": signals_seen.duplicate()}
	var ws: Array = []
	for w in wedges:
		ws.append(center_of(w))
	out["wedges"] = ws
	if hook != null:
		out["hook"] = {"pos": hook.pos, "state": hook.state, "bar": hook.bar, "tolerance": hook.tolerance}
	return out
