extends MechanicPanel
## Q02 «На карте вырос сад», мини-игра по H47 (Director 24.10: «нужно дать выбрать верно один за одним три объекта в
## нужном порядке, кликами на них, и после этого чтобы они раскрашивались; при неверном выборе обнулять результат»).
## The old school map of Olkhovka in the class (O1), a tracing sheet laid over it. Ulyana, standing by the map, has told
## the way to her home (village_map.use): from the school — down the road to their house, the last one — and the garden
## behind it, where the map has an empty plot. The way is shown on the sheet by clicks, in order (`places[].order`):
##   - the right next place is coloured in watercolour by its own outline (`poly`, `color`) and gets its number;
##   - a click on another place of the map (a house, the mill, the bridge — places without `order`, or one out of turn)
##     is a wrong choice: Ulyana's short word (`texts.wrong`, then `wrong_again`), and every coloured place fades — from
##     the start again; a click where there is no place does nothing;
##   - after the third, the drawing of the tracing comes up over the plot (the garden: currant rows, the apple tree, the
##     path, the shed — `art.tracing`) and event "traced" (data: «Там теперь смородина», then the choice at once).
## The hint (`texts.label_hint`) and the row of three names at the bottom say the order. Art (партия 8б): `art.map` —
## the old map (1672×941), `art.tracing` — the tracing on the same canvas (its sheet ≈18 % white over x100–1580). Until
## the tracing comes up the engine draws the same sheet (`sheet`). Places — canvas px polygons.

const CANVAS := Vector2(1672, 941)

var k: float = 1.0
var canvas: Control = null            # the map and everything on it, canvas px, scaled to the screen
var tracing_art: TextureRect = null
var sheet: Polygon2D = null
var places: Array = []                # [{id, order, label, poly, color, node, fill: [Polygon2D], line, badge}]
var route: Array = []                 # place ids in order
var found: int = 0                    # how many of the way are coloured now
var wrong: int = 0                    # wrong choices so far
var hover_id: String = ""
var hover_line: Line2D = null
var hint: Label = null
var progress: Array[Label] = []
var done_t: float = -1.0
var _fade: Dictionary = {}            # place id -> t: colouring in (+) or fading out (-)
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
	# The tracing sheet over the map (the same as on the tracing art).
	var sh: Dictionary = spec.get("sheet", {})
	var g := _rect(sh.get("rect", [100, 45, 1480, 840]))
	sheet = Polygon2D.new()
	sheet.name = "Sheet"
	sheet.polygon = PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)])
	sheet.color = Color.html(String(sh.get("color", "#ffffff2e")))
	canvas.add_child(sheet)
	# The places; the way — by `order`.
	var ordered: Array = []
	for p in spec.get("places", []):
		var d := {"id": String(p.get("id", "")), "order": int(p.get("order", 0)), "label": String(p.get("label", "")),
			"poly": _points(p.get("poly", [])), "color": Color.html(String(p.get("color", "#c8553d")))}
		_make_place(d)
		places.append(d)
		if d["order"] > 0:
			ordered.append(d)
	ordered.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	for d in ordered:
		route.append(d["id"])
	hover_line = Line2D.new()
	hover_line.name = "Hover"
	hover_line.width = 3.0
	hover_line.default_color = Color(1.0, 0.95, 0.75, 0.9)
	hover_line.joint_mode = Line2D.LINE_JOINT_ROUND
	hover_line.texture = _dash_texture()
	hover_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	hover_line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	canvas.add_child(hover_line)
	var tr_img := String(art.get("tracing", ""))
	if tr_img != "" and ResourceLoader.exists(tr_img):
		tracing_art = crop(tr_img, [0, 0, CANVAS.x, CANVAS.y], Vector2.ZERO, 1.0, canvas)
		tracing_art.name = "TracingArt"
		tracing_art.visible = false
	hint = label(text("label_hint"), v2(spec.get("hint_pos", [1150, 96])), 740)
	hint.name = "Hint"
	# The way at the bottom: «1 Школа — 2 Дом Ули — 3 Сад», each lit when found.
	var at := v2(spec.get("progress_pos", [560, 984]))
	for i in route.size():
		var pd := _place(route[i])
		var l := label("%d · %s" % [i + 1, StoryData.text(String(pd["label"]))], at + Vector2(i * 270.0, 0), 250)
		l.name = "Way%d" % (i + 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress.append(l)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if done():
		found = route.size()
		for id in route:
			_set_colour(id, 1.0)
		if tracing_art != null:
			tracing_art.visible = true
			sheet.visible = false
	_refresh()


func opened() -> void:
	sound("paper")


func done() -> bool:
	return flag(String(spec.get("done_flag", "")))


func _make_place(d: Dictionary) -> void:
	var node := Node2D.new()
	node.name = "Place_" + String(d["id"])
	canvas.add_child(node)
	d["node"] = node
	var poly: PackedVector2Array = d["poly"]
	if poly.size() < 3:
		d["fill"] = []
		return
	# Watercolour by the outline: a soft wider wash, the body, a denser core, a pencil edge.
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(poly.size())
	var fills: Array = []
	for layer_i in 3:
		var grow: float = [1.06, 1.0, 0.86][layer_i]
		var pts := PackedVector2Array()
		for i in poly.size():
			# a little unevenness of the brush (fixed per vertex, no flicker)
			var wob := 1.0 + 0.018 * sin(float(i) * 2.3 + layer_i)
			pts.append(c + (poly[i] - c) * grow * wob)
		var f := Polygon2D.new()
		f.polygon = pts
		f.antialiased = true
		var col: Color = d["color"]
		f.color = Color(col.r, col.g, col.b, [0.16, 0.30, 0.18][layer_i])
		node.add_child(f)
		fills.append(f)
	var edge := Line2D.new()
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	edge.points = closed
	edge.width = 2.6
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.default_color = (d["color"] as Color).darkened(0.45)
	node.add_child(edge)
	d["fill"] = fills
	d["edge"] = edge
	# the number of the step, in a small round mark at the top of the outline
	var top := poly[0]
	for q in poly:
		if q.y < top.y:
			top = q
	var badge := Node2D.new()
	badge.position = Vector2(c.x, top.y - 18.0)
	var disc := Polygon2D.new()
	disc.polygon = PlaceholderArt.circle_points(Vector2.ZERO, 17.0)
	disc.color = (d["color"] as Color).darkened(0.2)
	badge.add_child(disc)
	if int(d["order"]) > 0:
		var num := Label.new()
		num.text = str(d["order"])
		num.position = Vector2(-17, -19)
		num.size = Vector2(34, 36)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 24)
		num.add_theme_color_override("font_color", Color(1, 0.98, 0.92))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(num)
	node.add_child(badge)
	d["badge"] = badge
	node.modulate.a = 0.0
	node.visible = false


func _place(id: String) -> Dictionary:
	for d in places:
		if d["id"] == id:
			return d
	return {}


func _set_colour(id: String, x: float) -> void:
	var d := _place(id)
	if d.is_empty():
		return
	var n: Node2D = d["node"]
	n.visible = x > 0.001
	n.modulate.a = clampf(x, 0.0, 1.0)


func place_at(cp: Vector2) -> String:
	# the smallest outline under the point wins (a house inside a bigger area)
	var best := ""
	var best_area := INF
	for d in places:
		var poly: PackedVector2Array = d["poly"]
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(cp, poly):
			var r := _bounds(poly)
			if r.get_area() < best_area:
				best_area = r.get_area()
				best = d["id"]
	return best


func _busy() -> bool:
	return done_t >= 0.0 or done() or dialogue_up()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var id := "" if _busy() else place_at(ev.position / k)
		if id != hover_id:
			hover_id = id
			_draw_hover()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if id != "" else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _busy():
			return
		var id := place_at(ev.position / k)
		if id == "":
			return
		choose(id)


## A place chosen (clicked): the next of the way — coloured; already coloured — nothing; any other — all again.
func choose(id: String) -> void:
	if found >= route.size():
		return
	if found > 0 and route.slice(0, found).has(id):
		return
	if id == route[found]:
		found += 1
		_fade[id] = 0.0
		sound("pencil")
		if found >= route.size():
			done_t = 0.0
	else:
		wrong += 1
		sound("rope_slip")
		for i in found:
			_fade[route[i]] = -1.0
		found = 0
		say("wrong" if wrong == 1 else "wrong_again")
	hover_id = ""
	_draw_hover()
	_refresh()


func _draw_hover() -> void:
	var d := _place(hover_id)
	if d.is_empty() or (found > 0 and route.slice(0, found).has(hover_id)):
		hover_line.points = PackedVector2Array()
		return
	var poly: PackedVector2Array = d["poly"]
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	hover_line.points = closed


func _refresh() -> void:
	for i in progress.size():
		var l: Label = progress[i]
		var lit := i < found or done()
		l.modulate = Color(1, 1, 1, 1.0) if lit else Color(1, 1, 1, 0.55)
		var col: Color = _place(route[i]).get("color", Color.WHITE)
		l.add_theme_color_override("font_color", col.lightened(0.35) if lit else Color(0.95, 0.9, 0.8))
	hint.visible = not done() and done_t < 0.0


func tick(delta: float) -> void:
	_pulse += delta
	if hover_line.points.size() > 0:
		hover_line.modulate.a = 0.6 + 0.4 * sin(_pulse * 5.0)
	for id in _fade.keys():
		var t := float(_fade[id])
		if t >= 0.0:
			t += delta
			_set_colour(id, clampf(t / 0.45, 0.0, 1.0))
			if t >= 0.45:
				_fade.erase(id)
				continue
		else:
			# fading out: -1 → 0 over 0.5 s
			t += delta * 2.0
			_set_colour(id, clampf(-t, 0.0, 1.0))
			if t >= 0.0:
				_set_colour(id, 0.0)
				_fade.erase(id)
				continue
		_fade[id] = t
	if done_t >= 0.0:
		done_t += delta
		# the garden comes up on the sheet: the drawing of the tracing fades in over the engine's sheet
		var x := clampf((done_t - 0.5) / 0.8, 0.0, 1.0)
		if tracing_art != null:
			tracing_art.visible = x > 0.0
			tracing_art.modulate.a = x
			sheet.modulate.a = 1.0 - x
		if done_t >= 1.4 and not done():
			event("traced")
			_refresh()


# --- Helpers -------------------------------------------------------------------------------------

static func _points(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


static func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r


static var _dash: ImageTexture = null


static func _dash_texture() -> ImageTexture:
	if _dash == null:
		var img := Image.create(14, 4, false, Image.FORMAT_RGBA8)
		for x in 14:
			for y in 4:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if x < 8 else 0.0))
		_dash = ImageTexture.create_from_image(img)
	return _dash


## A point well inside a place (screen px): the centre of its outline, nudged inside if the centre falls out.
func _inside_point(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(poly.size())
	if Geometry2D.is_point_in_polygon(c, poly):
		return c
	for q in poly:
		var m := c.lerp(q, 0.5)
		if Geometry2D.is_point_in_polygon(m, poly):
			return m
	return poly[0]


## Click targets for tests and the web probe: every place (screen point inside it), the way in order, what is coloured.
func probe() -> Dictionary:
	var ps := {}
	for d in places:
		var cp := _inside_point(d["poly"])
		ps[d["id"]] = {"x": cp.x * k, "y": cp.y * k, "order": d["order"], "coloured": (d["node"] as Node2D).visible and (d["node"] as Node2D).modulate.a > 0.5}
	var coloured: Array = []
	for d in places:
		if (d["node"] as Node2D).visible and (d["node"] as Node2D).modulate.a > 0.05:
			coloured.append(d["id"])
	return {"phase": "done" if done() else ("revealing" if done_t >= 0.0 else "route"), "places": ps, "route": route,
		"found": found, "wrong": wrong, "coloured": coloured, "hint": hint.text if hint.visible else "",
		"tracing_visible": tracing_art != null and tracing_art.visible and tracing_art.modulate.a > 0.5,
		"sheet_visible": sheet.visible, "art": canvas.get_node_or_null("Map") != null,
		"stand_in": canvas.get_node_or_null("MapStandIn") != null, "busy": _busy()}
