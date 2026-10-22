extends MechanicPanel
## M10–M12, the workshop (H2): the office mirror clamped in Dunya's stand «ЗМ» and the mill bell beside it.
##   1. Two wedges (clicks) clamp the frame — the glass clears and shows the office now (OfficeView in a
##      SubViewport; UPDATE_ALWAYS, so a change at the mill is in the glass the same frame). Event "clamped".
##   2. With the clapper hung (`bell_clapper_hung`), one strike: Pavel's lantern lights the gap at once —
##      the same frame as the strike (canon: the mirror shows now; test_day2 checks the frame numbers).
##      Event "lantern".
##   3. The hook (HookPuzzle): the bell's presses become the mill signals (BellSignal): one — go on, two —
##      stop, long — lift. Director 23.10 (F8): after «пускай» Pavel feels for the bar — the hook sways up and
##      down along the gap; «стой» must catch it in the bolt zone (a «Точный удар» sweep: the upright bar beside
##      the glass shows the zone in green and the hook as its marker). Caught — «подымай» lifts the bar.
##      Stopped elsewhere — the hook slips off and falls, Pavel brings it up again; no penalty. Event "unbolted".
## The bell is pressed with the mouse: a click is a strike, two quick clicks — «стой», a press held ~0.6 s — the
## long ring; the legend is on screen under the shift schedule (logic review M2, item 2).
## Art: the stand «ЗМ» is the tall carved frame in the middle of Dunya's workshop (Director 23.10); the close-up
## is the workshop painting with the glass layer in the frame's opening (tools/make_h2_frame_glass.py) over it,
## cropped round the frame; glass_polygon is the opening — a quad textured with the office view; OfficeView
## draws «Контора — вид на дверь» (партия 3).

var office: OfficeView = null
var office_vp: SubViewport = null
var glass: Control = null          # the click area over the glass (bounding box of its contour)
var glass_poly: Polygon2D = null   # the office now, mapped onto the glass contour
var glass_rect: Rect2 = Rect2()
var glass_points: PackedVector2Array = PackedVector2Array()
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
var hook_bar: TimingBar = null    # upright «точный удар» bar beside the glass: the bolt zone, the hook as marker
var _press_phases: Array[float] = []   # the sway phase at the last bell presses («стой» is judged at its first)
var _bell_swing: float = 0.0
var _status: String = ""


func build() -> void:
	var fr: Dictionary = spec.get("frame", {})
	var reg: Array = fr.get("region", [370, 140, 280, 320])
	var fpos := v2(fr.get("pos", [300, 110]))
	var fk := float(fr.get("scale", 2.8))
	# The frame and the stand: the workshop painting and the layer with the mirror in Dunya's stand, one crop.
	var images: Array = fr.get("images", [fr.get("image", "")])
	for i in images.size():
		crop(String(images[i]), reg, fpos, fk).name = "Frame" if i == 0 else "Frame%d" % i
	# The glass: its contour on the canvas → the screen.
	var pts := PackedVector2Array()
	for q in fr.get("glass_polygon", [[454, 187], [560, 180], [565, 361], [460, 373]]):
		pts.append(fpos + (v2(q) - Vector2(float(reg[0]), float(reg[1]))) * fk)
	glass_points = pts
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	glass_rect = Rect2(lo, hi - lo)
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
	office.hook_bar = float(spec.get("hook", {}).get("bar", 0.5))
	office_vp.add_child(office)
	glass_poly = Polygon2D.new()
	glass_poly.name = "GlassView"
	glass_poly.texture = office_vp.get_texture()
	glass_poly.polygon = pts
	# The view's corners on the contour's corners (top-left, top-right, bottom-right, bottom-left).
	var vs := Vector2(office_vp.size)
	glass_poly.uv = PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)])
	add_child(glass_poly)
	var sheen := Polygon2D.new()
	sheen.name = "Sheen"
	sheen.color = Color(0.85, 0.9, 1.0, 0.07)
	sheen.polygon = pts
	add_child(sheen)
	glass = hit_area(glass_rect, _on_glass_input, "Glass")
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
	var legend := label(text("label_bell"), v2(spec.get("legend_pos", [1120, 878])), float(spec.get("legend_w", 760)))
	legend.name = "BellLegend"
	status_label = label("", v2(spec.get("status_pos", [1120, 950])), float(spec.get("status_w", 540)))
	hook = HookPuzzle.new(spec.get("hook", {}))
	hook.event.connect(_on_hook_event)
	_build_hook_bar()
	_sync_from_flags()


## The upright bar beside the glass, level with the gap: its green is the bolt zone, its marker the hook.
func _build_hook_bar() -> void:
	var oa: Dictionary = spec.get("office", {}).get("art", {})
	var reg: Array = oa.get("region", [520, 80, 380, 660])
	var gap: Array = oa.get("gap", [95, 705])
	var g0 := float(gap[0]) + (float(gap[1]) - float(gap[0])) * hook.sway.x
	var g1 := float(gap[0]) + (float(gap[1]) - float(gap[0])) * hook.sway.y
	var y0 := glass_rect.position.y + (g0 - float(reg[1])) / float(reg[3]) * glass_rect.size.y
	var y1 := glass_rect.position.y + (g1 - float(reg[1])) / float(reg[3]) * glass_rect.size.y
	hook_bar = TimingBar.new()
	hook_bar.name = "HookBar"
	var bx := float(spec.get("hook_bar_x", glass_rect.end.x + 120.0))
	hook_bar.position = Vector2(bx, y0 - 6.0)
	hook_bar.size = Vector2(46, y1 - y0 + 12.0)
	hook_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hook_bar.space_key = false
	hook_bar.drive = false
	add_child(hook_bar)
	hook_bar.setup({"hint": ""}, true)
	hook_bar.logic = hook.timing
	hook_bar.logic.slow_k = TimingBar.SLOW_K if TimingBar.slow else 1.0


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
	_press_phases.append(hook.timing.phase)
	if _press_phases.size() > 2:
		_press_phases.pop_front()
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
		# «стой» is judged where the hook was when its first strike rang.
		hook.apply(s, _press_phases[0] if s == "two" and _press_phases.size() == 2 else -1.0)
	if not sigs.is_empty():
		_set_status()


func tick(delta: float) -> void:
	if hook_active():
		_handle_signals(signal_parser.tick(clock))
		hook.step(delta)
		office.hook_frac = hook.pos
		office.bar_lift = hook.lift_amount if hook.state == "lift_bar" else 0.0
		office.refresh()
	if hook_bar != null:
		hook_bar.visible = hook_active() or (hook != null and hook.state in ["lift_bar", "solved"] and not flag("office_unbolted"))
		hook_bar.modulate.a = 1.0 if hook.state in ["sway", "stopped", "lift_bar"] else 0.45
	if _bell_swing > 0.0:
		_bell_swing = maxf(_bell_swing - delta * 1.6, 0.0)
		bell.rotation_degrees = sin(clock * 14.0) * 6.0 * _bell_swing
	if not clamped() and glass_poly != null:
		glass_poly.modulate = Color(1, 1, 1, 0.22)
		glass_poly.position = Vector2(sin(clock * 9.0) * 3.0, cos(clock * 7.0) * 2.0)
	elif glass_poly != null and glass_poly.modulate.a < 1.0:
		glass_poly.modulate = Color(1, 1, 1, 1)
		glass_poly.position = Vector2.ZERO


func _on_hook_event(name: String) -> void:
	match name:
		"missed":
			sound("clank")
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
		var bc := center_of(bell_hit)
		# How to ring each signal (bots: tools/ai_playtest): «стой» is judged at its FIRST click.
		out["signals_how"] = {"one": {"x": bc.get("x", 0), "y": bc.get("y", 0), "how": "click"},
			"two": {"x": bc.get("x", 0), "y": bc.get("y", 0), "how": "double_click", "gap_ms": 150},
			"long": {"x": bc.get("x", 0), "y": bc.get("y", 0), "how": "hold", "hold_ms": 800}}
		out["strike"] = {"x": bc.get("x", 0), "y": bc.get("y", 0), "how": "double_click (= «стой»), when timing.in_green"}
		out["hook"] = {"pos": hook.pos, "state": hook.state, "bar": hook.bar, "tolerance": hook.tolerance, "misses": hook.misses,
			"sway": [hook.sway.x, hook.sway.y], "in_zone": hook.state == "sway" and hook.timing.in_green(hook.timing.pos()),
			"timing": hook_bar.probe() if hook_bar != null else {}}
	return out
