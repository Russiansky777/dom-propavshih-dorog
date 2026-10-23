extends MechanicPanel
## Q02 «На карте вырос сад» (Director 23.10 11:51): the old school map of Olkhovka in the class (O1), drawn by the
## pupils more than twenty years ago — by the house that is Ilya's now, an empty plot with only a fence.
##   - look (the first opening and until Ulyana has shown her garden — flags `trace_when`): the map, the empty plot
##     ringed and breathing; the hint says what Agata noticed and who knows what is there now.
##   - trace (`trace_when` hold, `done_flag` not yet): the view rides in onto the plot, a tracing sheet is laid over
##     it and the new garden is drawn with a pencil along dotted guides, line by line — «протянуть по контуру»
##     (KnotPath, the same rule as the knot on the plate, F6): currant rows, the path, the shed. Off the guide, or let
##     go in the middle of a line, the pencil slips back to where that line began — no penalty. Event "traced".
## Art (партия 8б): `art.map` — the old map (full canvas 1672×941), `art.tracing` — the drawn tracing on the same
## canvas, faded in when the last line is done. Until they are delivered (`pending` — the request in
## assets/manifest.json) the engine draws the map from `stub` (PlaceholderArt.stand_in, canvas px) and the pencil
## lines stay as drawn: the import of the ordered files is the whole swap.
## `plot` [x, y, w, h] (canvas px) — the empty plot of the stand-in; the lines (`lines.strokes`) are given in the
## plot's own frame (0..1), so they land on the plot wherever a drawing puts it: with `art.tracing` delivered the
## plot is the box of its strong strokes (alpha ≥ `fit_alpha`), unless `fit` is false.

const CANVAS := Vector2(1672, 941)

var k: float = 1.0                    # canvas → screen in the look view
var canvas: Control = null            # the map (art or stand-in) and everything drawn on it, in canvas px
var tracing_art: TextureRect = null
var ring: Line2D = null
var sheet: Node2D = null
var plot: Rect2 = Rect2()             # canvas px
var plot_fitted: bool = false
var zoom: float = 1.0                 # canvas → screen once ridden in
var zoom_at: Vector2 = Vector2.ZERO   # the canvas origin on screen once ridden in
var ride_t: float = -1.0              # the ride onto the plot (s), -1 — not riding
var path: KnotPath = null
var pencil_done: Array[Line2D] = []   # finished lines (screen)
var pencil_now: Line2D = null         # the line being drawn
var guide: Line2D = null
var guide_arrow: Polygon2D = null
var tip: Control = null               # full-screen catcher of the pencil drag (trace phase only)
var stroke_label: Label = null
var hint: Label = null
var slips: int = 0
var done_t: float = -1.0
var _slip_t: float = -1.0
var _slip_from: Vector2 = Vector2.ZERO
var _drag_pos: Vector2 = Vector2.ZERO
var _pulse: float = 0.0


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	k = 1920.0 / CANVAS.x
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.size = CANVAS
	canvas.scale = Vector2(k, k)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var map_img := String(art.get("map", ""))
	if map_img != "" and ResourceLoader.exists(map_img):
		crop(map_img, [0, 0, CANVAS.x, CANVAS.y], Vector2.ZERO, 1.0, canvas).name = "Map"
	else:
		var st := PlaceholderArt.stand_in(spec.get("stub", {}))
		st.name = "MapStandIn"
		canvas.add_child(st)
	var tr_img := String(art.get("tracing", ""))
	plot = _rect(spec.get("plot", [1180, 330, 230, 190]))
	if tr_img != "" and ResourceLoader.exists(tr_img):
		tracing_art = crop(tr_img, [0, 0, CANVAS.x, CANVAS.y], Vector2.ZERO, 1.0, canvas)
		tracing_art.name = "TracingArt"
		if bool(spec.get("fit", true)):
			var fitted := _fit_plot(load(tr_img), float(spec.get("fit_alpha", 0.55)))
			if fitted.size.x > 8.0 and fitted.size.y > 8.0:
				plot = fitted
				plot_fitted = true
	# The plot Agata noticed: a ring that breathes (look view).
	ring = Line2D.new()
	ring.name = "PlotRing"
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.86, 0.5, 0.9)
	var c := plot.get_center()
	var rx := plot.size.x * 0.62
	var ry := plot.size.y * 0.62
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ring.points = pts
	canvas.add_child(ring)
	# The tracing sheet laid over the map (the trace view): `sheet` {rect (canvas px; default — the plot with a margin),
	# color, pins, angle_deg} — with the tracing art delivered, the same sheet as on it (no pins, straight), and at the
	# last line the drawing of the tracing comes up in its place.
	var sh: Dictionary = spec.get("sheet", {})
	sheet = Node2D.new()
	sheet.name = "Sheet"
	var g := _rect(sh["rect"]) if sh.has("rect") else plot.grow_individual(plot.size.x * 0.16, plot.size.y * 0.2, plot.size.x * 0.16, plot.size.y * 0.16)
	var paper := Polygon2D.new()
	paper.polygon = PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)])
	paper.color = Color.html(String(sh.get("color", spec.get("sheet_color", "#f3eedfa0"))))
	sheet.add_child(paper)
	if bool(sh.get("pins", true)):
		for px in [g.position.x + 10.0, g.end.x - 10.0]:
			var pin := Polygon2D.new()
			pin.polygon = PlaceholderArt.circle_points(Vector2(px, g.position.y + 9.0), 5.0)
			pin.color = Color(0.55, 0.16, 0.12)
			sheet.add_child(pin)
	sheet.rotation_degrees = float(sh.get("angle_deg", spec.get("sheet_angle_deg", -1.2 if not sh.has("rect") else 0.0)))
	sheet.position = c - c.rotated(deg_to_rad(sheet.rotation_degrees))
	canvas.add_child(sheet)
	# The ride onto the plot: the plot fills `zoom_box` (screen), no more than `zoom_max`.
	var zb := _rect(spec.get("zoom_box", [330, 250, 1260, 640]))
	zoom = clampf(minf(zb.size.x / plot.size.x, zb.size.y / plot.size.y), k, float(spec.get("zoom_max", 3.2)))
	zoom_at = zb.get_center() - c * zoom
	# The pencil (screen space, over the canvas).
	var pts_cfg: Dictionary = (spec.get("lines", {}) as Dictionary).duplicate(true)
	var strokes: Array = []
	for s in pts_cfg.get("strokes", []):
		var st2: Array = []
		for q in s:
			st2.append([plot.position.x + float(q[0]) * plot.size.x, plot.position.y + float(q[1]) * plot.size.y])
		strokes.append(st2)
	pts_cfg["strokes"] = strokes
	path = KnotPath.new(pts_cfg, zoom_at, zoom)
	guide = Line2D.new()
	guide.name = "Guide"
	guide.width = 6.0
	guide.default_color = Color(0.85, 0.25, 0.15, 0.85)
	guide.texture = _dash_texture()
	guide.texture_mode = Line2D.LINE_TEXTURE_TILE
	guide.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(guide)
	guide_arrow = Polygon2D.new()
	guide_arrow.name = "GuideArrow"
	guide_arrow.color = Color(0.85, 0.25, 0.15, 0.95)
	add_child(guide_arrow)
	pencil_now = _pencil_line("PencilNow")
	tip = Control.new()
	tip.name = "Pencil"
	tip.size = Vector2(1920, 1080)
	tip.mouse_filter = Control.MOUSE_FILTER_STOP
	tip.gui_input.connect(_on_pencil_input)
	add_child(tip)
	stroke_label = label("", Vector2.ZERO, 360)
	hint = label("", v2(spec.get("hint_pos", [1240, 96])), 640)
	if trace_phase():
		_set_view(1.0)   # opened straight onto the tracing (the second time): already ridden in
	else:
		_set_view(0.0)
	_refresh()


func opened() -> void:
	if trace_phase():
		sound("paper")


## Is it the tracing now: Ulyana has shown the garden, the lines are not drawn yet.
func trace_phase() -> bool:
	for f in spec.get("trace_when", []):
		if not flag(String(f)):
			return false
	return not traced()


func traced() -> bool:
	return flag(String(spec.get("done_flag", "")))


func flags_changed() -> void:
	if canvas != null:
		_refresh()


func _refresh() -> void:
	var tracing := trace_phase()
	ring.visible = not tracing and done_t < 0.0 and not traced()
	sheet.visible = tracing or done_t >= 0.0 or traced()
	tip.visible = tracing and done_t < 0.0
	guide.visible = tip.visible
	guide_arrow.visible = tip.visible
	stroke_label.visible = tip.visible
	if tracing_art != null:
		tracing_art.visible = traced() or done_t >= 0.0
	if done_t >= 0.0 or traced():
		hint.text = ""
	elif tracing:
		hint.text = text("label_hint_trace")
	else:
		hint.text = text("label_hint_look")
	_draw_pencil()


## 0 — the whole map, 1 — ridden in onto the plot.
func _set_view(x: float) -> void:
	var e := x * x * (3.0 - 2.0 * x)
	var z := lerpf(k, zoom, e)
	canvas.scale = Vector2(z, z)
	canvas.position = Vector2.ZERO.lerp(zoom_at, e)


# --- The pencil --------------------------------------------------------------------------------

func _pencil_line(n: String) -> Line2D:
	var l := Line2D.new()
	l.name = n
	l.width = float(spec.get("pencil_width", 5.0))
	l.default_color = Color.html(String(spec.get("pencil_color", "#3b342ce6")))
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(l)
	return l


func _on_pencil_input(ev: InputEvent) -> void:
	if not trace_phase() or ride_t >= 0.0:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if path.grab(ev.position):
				accept_event()
				_drag_pos = ev.position
				tip.mouse_default_cursor_shape = Control.CURSOR_DRAG
		elif path.grabbed:
			accept_event()
			_after(path.release())
	elif ev is InputEventMouseMotion and path.grabbed:
		accept_event()
		_drag_pos = ev.position
		# Long moves in small steps: a fast line along the guide counts, a jump across does not.
		var r := ""
		var from := path.end_point()
		var n := maxi(1, int(from.distance_to(ev.position) / 20.0))
		for i in n:
			r = path.drag(from.lerp(ev.position, float(i + 1) / n))
			if r != "move":
				break
		_after(r)


func _after(r: String) -> void:
	match r:
		"slip":
			slips += 1
			_slip_from = _drag_pos
			_slip_t = 0.0
			sound("rope_slip")
			if slips == 1:
				say("slipped")
		"stroke":
			sound("pencil")
			_finish_line()
			# The next line starts elsewhere (rows → path → shed): the pencil is lifted, the next press is at its start.
			var nx := path.strokes[path.stroke]
			var pv := path.strokes[path.stroke - 1]
			if nx[0].distance_to(pv[pv.size() - 1]) > 12.0:
				path.grabbed = false
		"done":
			sound("pencil")
			_finish_line()
			done_t = 0.0
	if r != "move":
		tip.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh()


## The line just drawn stays on the sheet.
func _finish_line() -> void:
	var k0 := path.stroke - 1
	if k0 < 0 or k0 >= path.strokes.size():
		return
	var l := _pencil_line("Pencil%d" % k0)
	l.points = path.strokes[k0]
	pencil_done.append(l)
	move_child(l, tip.get_index())


func _draw_pencil() -> void:
	if path == null:
		return
	var drawing := trace_phase() and done_t < 0.0 and ride_t < 0.0
	pencil_now.visible = drawing
	if not drawing:
		guide.points = PackedVector2Array()
		guide_arrow.polygon = PackedVector2Array()
		return
	# The part of the current line drawn so far (the pencil's end; slipping back after a miss).
	var pts := PackedVector2Array()
	if path.stroke < path.strokes.size():
		var s := path.strokes[path.stroke]
		var acc := 0.0
		pts.append(s[0])
		for i in range(1, s.size()):
			var seg := s[i - 1].distance_to(s[i])
			if acc + seg <= path.progress:
				pts.append(s[i])
				acc += seg
			else:
				if path.progress > acc:
					pts.append(s[i - 1].lerp(s[i], (path.progress - acc) / maxf(seg, 0.001)))
				break
		if _slip_t >= 0.0:
			var x := clampf(_slip_t / 0.3, 0.0, 1.0)
			pts = PackedVector2Array([s[0], _slip_from.lerp(s[0], x * x)])
	pencil_now.points = pts
	var g := path.guide_points()
	guide.points = g
	guide_arrow.polygon = PackedVector2Array()
	if g.size() >= 2:
		var tp := g[g.size() - 1]
		var d := (tp - g[g.size() - 2]).normalized()
		var nrm := Vector2(-d.y, d.x)
		guide_arrow.polygon = PackedVector2Array([tp + d * 16.0, tp - d * 10.0 + nrm * 12.0, tp - d * 10.0 - nrm * 12.0])
		var labels: Array = spec.get("lines", {}).get("labels", [])
		if path.stroke < labels.size():
			stroke_label.text = StoryData.text(String(labels[path.stroke]))
			var e := path.end_point()
			stroke_label.position = Vector2(clampf(e.x - 180.0, 20.0, 1540.0), clampf(e.y - 90.0, 140.0, 980.0))


func tick(delta: float) -> void:
	_pulse += delta
	if ring != null and ring.visible:
		ring.modulate.a = 0.55 + 0.45 * sin(_pulse * 3.2)
		ring.width = 4.0 + 2.0 * (0.5 + 0.5 * sin(_pulse * 3.2))
	if trace_phase() and ride_t < 0.0 and canvas.scale.x < zoom - 0.001 and done_t < 0.0:
		ride_t = 0.0    # the tracing begins (Ulyana's flags came while the map was open): ride onto the plot
	if ride_t >= 0.0:
		ride_t += delta
		_set_view(clampf(ride_t / 0.8, 0.0, 1.0))
		if ride_t >= 0.8:
			ride_t = -1.0
			_refresh()
	if _slip_t >= 0.0:
		_slip_t += delta
		if _slip_t >= 0.3:
			_slip_t = -1.0
		_draw_pencil()
	elif path != null and path.grabbed:
		_draw_pencil()
	if done_t >= 0.0:
		done_t += delta
		if tracing_art != null:
			# the drawn tracing comes up in place of the engine's sheet and the pencil lines
			var x := clampf(done_t / 0.6, 0.0, 1.0)
			tracing_art.visible = true
			tracing_art.modulate.a = x
			sheet.modulate.a = 1.0 - x
			for l in pencil_done:
				l.modulate.a = 1.0 - x
		if done_t >= 0.6 and not traced():
			event("traced")
			_refresh()


# --- Helpers -----------------------------------------------------------------------------------

static func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## The box (canvas px) of a drawing's strong strokes: a small copy is scanned (fast on the web too).
static func _fit_plot(tex: Texture2D, alpha_min: float) -> Rect2:
	if tex == null:
		return Rect2()
	var img := tex.get_image()
	if img == null:
		return Rect2()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var step := 8
	var small := img.duplicate() as Image
	small.resize(maxi(w / step, 1), maxi(h / step, 1), Image.INTERPOLATE_BILINEAR)
	var lo := Vector2i(small.get_width(), small.get_height())
	var hi := Vector2i(-1, -1)
	for y in small.get_height():
		for x in small.get_width():
			if small.get_pixel(x, y).a >= alpha_min:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2()
	var sx := CANVAS.x / float(small.get_width())
	var sy := CANVAS.y / float(small.get_height())
	return Rect2(lo.x * sx, lo.y * sy, (hi.x - lo.x + 1) * sx, (hi.y - lo.y + 1) * sy)


static var _dash: ImageTexture = null


static func _dash_texture() -> ImageTexture:
	if _dash == null:
		var img := Image.create(14, 4, false, Image.FORMAT_RGBA8)
		for x in 14:
			for y in 4:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if x < 8 else 0.0))
		_dash = ImageTexture.create_from_image(img)
	return _dash


func probe() -> Dictionary:
	var strokes: Array = []
	for s in path.strokes:
		var pts: Array = []
		for q in s:
			pts.append({"x": q.x, "y": q.y})
		strokes.append(pts)
	var e := path.end_point()
	var nxt: Array = []
	for q in path.guide_points():
		nxt.append({"x": q.x, "y": q.y})
	var pr := Rect2(canvas.position + plot.position * canvas.scale.x, plot.size * canvas.scale.x)
	var state := "done" if (path.done() or traced()) else ("grabbed" if path.grabbed else ("slipping" if _slip_t >= 0.0 else "free"))
	return {"phase": "done" if traced() else ("trace" if trace_phase() else "look"), "riding": ride_t >= 0.0,
		"plot": {"x": pr.get_center().x, "y": pr.get_center().y, "w": pr.size.x, "h": pr.size.y, "fitted": plot_fitted},
		"ring_visible": ring.visible, "sheet_visible": sheet.visible, "art": tracing_art != null or canvas.get_node_or_null("Map") != null,
		"stand_in": canvas.get_node_or_null("MapStandIn") != null,
		"trace": {"open": tip.visible and ride_t < 0.0, "loops_done": path.stroke, "loops_total": path.strokes.size(), "state": state,
			"end": {"x": e.x, "y": e.y}, "next": nxt, "strokes": strokes, "tolerance": path.tolerance, "grab_r": path.grab_r,
			"how": "press on end, drag through next (then the following strokes) without releasing"},
		"lines_drawn": pencil_done.size(), "slips": slips}
