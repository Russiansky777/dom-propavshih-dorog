extends MechanicPanel
## M10–M12, the workshop (H2): the office mirror clamped in Dunya's stand «ЗМ» and the mill bell beside it.
##   1. G19 (Director 23.10: «клинья максимально нереалистичные; подбить по 3 раза»): four painted wedges (art pack 9 —
##      H2_state_wedges_loose / half / driven, each wedge cut out by its own box) are driven in on the shared «точный
##      удар» bar, three hits each, one wedge after another (the one in work glows); a miss — that wedge jumps back
##      out loose, the driven ones stay (GameState counter mech.wedges.driven: a reopened close-up or a load keeps
##      them). All four in — the glass clears and shows the office now (OfficeView in a SubViewport; UPDATE_ALWAYS, so
##      a change at the mill is in the glass the same frame). Event "clamped". «Облегчить мини-игры» applies.
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
## is the workshop painting with the glass layer in the frame's opening (state_office_mirror_center.png, batch 8) over it,
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
const WEDGE_COUNTER := "mech.wedges.driven"
var wedges: Array[Control] = []        # one holder per wedge (its three state crops + the glow) — probe/tests
var wedge_hits: Array[int] = []        # hits so far on each wedge (3 — driven)
var wedge_boxes: Array[Rect2] = []     # screen rects of the wedges' boxes
var wedge_timing: TimingBar = null
var wedge_slips: int = 0
var _wedge_jump: float = -1.0          # the wedge in work jumping out after a miss (0..1)
var _wedge_jump_i: int = -1
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
	# H26: glass in a frame, not a cut-out rectangle — bevel, tarnished silver at the edges, a soft glare.
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/glass_bevel.gdshader")
	gm.set_shader_parameter("aspect", Vector2(1.0, glass_rect.size.y / maxf(glass_rect.size.x, 1.0)))
	glass_poly.material = gm
	add_child(glass_poly)
	var sheen := Polygon2D.new()
	sheen.name = "Sheen"
	sheen.color = Color(0.85, 0.9, 1.0, 0.07)
	sheen.polygon = pts
	add_child(sheen)
	glass = hit_area(glass_rect, _on_glass_input, "Glass")
	_build_wedges(reg, fpos, fk)
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
	TimingBar.apply_ease(hook_bar.logic)   # «Облегчить мини-игры» (G3): slower sway, wider bolt zone


## The four wedges of the frame (G19): each a holder at its box with the three painted states cut from their layers
## (`wedges.art` {loose, half, driven}, `wedges.boxes` [[x, y, w, h], …] — canvas px) and a glow round the one in work;
## the «точный удар» bar (`wedges.timing`, `wedges.timing_rect`) drives the one in work, three hits each.
func _build_wedges(reg: Array, fpos: Vector2, fk: float) -> void:
	var ws: Dictionary = spec.get("wedges", {})
	if not (ws is Dictionary):
		ws = {}
	var art: Dictionary = ws.get("art", {})
	var boxes: Array = ws.get("boxes", [])
	var driven := GameState.get_counter(WEDGE_COUNTER) if not clamped() else boxes.size()
	for i in boxes.size():
		var b: Array = boxes[i]
		var box := Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
		var scr := Rect2(fpos + (box.position - Vector2(float(reg[0]), float(reg[1]))) * fk, box.size * fk)
		wedge_boxes.append(scr)
		var holder := Control.new()
		holder.name = "Wedge%d" % i
		holder.position = scr.position
		holder.size = scr.size
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		var glow := Panel.new()
		glow.name = "Glow"
		glow.position = Vector2(-8, -8)
		glow.size = scr.size + Vector2(16, 16)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(1.0, 0.86, 0.5, 0.0)
		gs.border_color = Color(1.0, 0.86, 0.5, 0.9)
		gs.set_border_width_all(3)
		gs.set_corner_radius_all(8)
		gs.shadow_color = Color(1.0, 0.8, 0.4, 0.35)
		gs.shadow_size = 10
		glow.add_theme_stylebox_override("panel", gs)
		holder.add_child(glow)
		for st in ["loose", "half", "driven"]:
			var img := String(art.get(st, ""))
			var tr := crop(img, [box.position.x, box.position.y, box.size.x, box.size.y], Vector2.ZERO, fk, holder)
			tr.name = st.capitalize()
			# H26 (Director 24.10: «клинья инородные»): the pale wedges toned to the stand's wood (data `wedges.tint`).
			tr.modulate = _wedge_tint(ws)
		wedges.append(holder)
		wedge_hits.append(3 if i < driven else 0)
	wedge_timing = TimingBar.new()
	wedge_timing.name = "WedgeTiming"
	var trr: Array = ws.get("timing_rect", [1120, 470, 520, 48])
	wedge_timing.position = Vector2(float(trr[0]), float(trr[1]))
	wedge_timing.size = Vector2(float(trr[2]), float(trr[3]))
	add_child(wedge_timing)
	wedge_timing.setup(ws.get("timing", {"hits": 3, "period_s": 1.9, "green": 0.2}))
	wedge_timing.struck.connect(_on_wedge_struck)
	strike_bar = wedge_timing   # G26: a click anywhere on the close-up strikes the wedge in work
	_refresh_wedges()


## The wedge in work: the first not driven (−1 — all in).
func wedge_in_work() -> int:
	for i in wedge_hits.size():
		if wedge_hits[i] < 3:
			return i
	return -1


func wedges_driven() -> int:
	var n := 0
	for h in wedge_hits:
		if h >= 3:
			n += 1
	return n


## Each wedge shows its state: 0 hits — loose; 1 — half; 2 — between half and driven; 3 — driven.
func _refresh_wedges() -> void:
	var work := wedge_in_work()
	for i in wedges.size():
		var h: int = wedge_hits[i]
		var w: Control = wedges[i]
		var loose: CanvasItem = w.get_node("Loose")
		var half: CanvasItem = w.get_node("Half")
		var drv: CanvasItem = w.get_node("Driven")
		loose.visible = h == 0
		half.visible = h == 1 or h == 2
		drv.visible = h >= 2
		half.modulate.a = 1.0 if h == 1 else 0.5
		drv.modulate.a = 1.0 if h >= 3 else 0.5
		var glow: Control = w.get_node("Glow")
		glow.visible = i == work and not clamped()
		var off := Vector2.ZERO
		if i == _wedge_jump_i and _wedge_jump >= 0.0:
			off = Vector2(0, -26.0 * sin(_wedge_jump * PI))
		for n in [loose, half, drv]:
			(n as Control).position = off
	if wedge_timing != null:
		wedge_timing.visible = work >= 0 and not clamped()
	# While the wedges go in, their bar stands where the bell's schedule and legend are (those are for after).
	for n in ["Schedule", "BellLegend"]:
		var c := get_node_or_null(n) as CanvasItem
		if c != null:
			c.visible = wedge_timing == null or not wedge_timing.visible


func _on_wedge_struck(r: String) -> void:
	var i := wedge_in_work()
	if i < 0:
		return
	match r:
		"hit", "done":
			wedge_hits[i] = 3 if r == "done" else wedge_timing.logic.hits
			sound("hammer")
			if r == "done":
				GameState.set_counter(WEDGE_COUNTER, wedges_driven())
				if wedge_in_work() < 0:
					if not clamped():
						event("clamped")
						office.refresh()
				else:
					wedge_timing.restart()
		"miss":
			wedge_hits[i] = 0
			wedge_slips += 1
			_wedge_jump = 0.0
			_wedge_jump_i = i
			sound("clank")
			if wedge_slips == 1:
				say("wedge_slipped")
	_refresh_wedges()


func opened() -> void:
	if clamped():
		say("view_first" if not flag("lantern_check_seen") else "view_again")


func clamped() -> bool:
	return flag(String(spec.get("clamped_flag", "office_mirror_clamped")))


func _sync_from_flags() -> void:
	if clamped():
		for i in wedge_hits.size():
			wedge_hits[i] = 3
	_refresh_wedges()
	office.light_on = flag("lantern_check_seen") and not flag("office_unbolted")
	office.hook_visible = flag("lantern_check_seen") and not flag("office_unbolted")
	office.door_given = flag("office_unbolted")
	office.bar_lift = 1.0 if flag("office_unbolted") else 0.0
	office.shelf_down = not flag("office_shelf_lifted")
	office.refresh()
	_set_status()


# --- Input ----------------------------------------------------------------------------------


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
	if _wedge_jump >= 0.0:
		_wedge_jump += delta / 0.5
		if _wedge_jump >= 1.0:
			_wedge_jump = -1.0
		_refresh_wedges()
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
	var work := wedge_in_work()
	out["wedge_hits"] = wedge_hits.duplicate()
	out["wedge_work"] = work
	out["wedges_driven"] = wedges_driven()
	out["wedge_slips"] = wedge_slips
	out["wedge_strike"] = center_of(wedges[work]) if work >= 0 and work < wedges.size() else {}
	out["wedge_timing"] = wedge_timing.probe() if wedge_timing != null and wedge_timing.visible else {}
	out["free_click"] = {"x": 1500.0, "y": 180.0}
	out["strikes_by_click"] = strikes_by_click
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


## The wedges' colour fit to the stand «ЗМ» (H26): a multiply tint from data, default the stand's warm brown.
static func _wedge_tint(ws: Dictionary) -> Color:
	var t = ws.get("tint", [0.72, 0.53, 0.36])
	return Color(float(t[0]), float(t[1]), float(t[2]))
