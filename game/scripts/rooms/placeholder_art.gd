class_name PlaceholderArt
extends RefCounted
## Engine-drawn stand-ins for art that is ordered but not delivered yet (Docs/BRIEF_CHATGPT_v4.md):
## rooms R2/R3 without a background, Pavel and Mitya without sheets, glows on the far shore. Everything is
## described in data (rooms/<LOC>.json → background.placeholder.shapes, effects[] of type "shapes",
## hotspot `placeholder`), nothing here is painted "to look like the art" — flat shapes, gradients, glows.
##
## Shape entries ({type, ...}, screen coordinates 1920x1080):
##   {"type": "gradient", "rect": [x,y,w,h], "top": "#rrggbb[aa]", "bottom": "#..."}  — vertical gradient
##   {"type": "poly", "points": [[x,y]...], "color": "#..."}                           — filled polygon
##   {"type": "line", "points": [[x,y]...], "width": 4, "color": "#..."}               — polyline
##   {"type": "circle", "center": [x,y], "r": 20, "color": "#..."}                      — filled disc
##   {"type": "glow", "center": [x,y], "r": 40, "ry": 20, "blend": "add|mix", "color": "#..."} — soft light / haze
##   {"type": "text", "at": [x,y], "text": "@key", "size": 32, "color": "#..."}        — a word painted on
##   {"type": "rect", "rect": [x,y,w,h], "color": "#...", "angle_deg": 0}               — filled rectangle (turned)
##   {"type": "dashes", "points": [[x,y]...], "dash": 10, "gap": 7, "width": 3, "color": "#..."} — dashed polyline
##
## A whole stand-in (`stand_in`, layers' and close-ups' `stub` — art ordered and not delivered yet, partия 8б):
##   {"crops": [{"image": "res://…", "region": [x,y,w,h] in its pixels, "rect": [x,y,w,h], "modulate": "#…"}],
##    "shapes": [...], "texts": [{"text": "@key", "rect": [x,y,w,h], "font_size", "color", "alpha", "angle_deg", "font"}]}
## — a part of a delivered painting stretched to `rect`, the shapes above, then the words.

const SEGMENTS := 28


## The stand-in of an ordered picture (data `stub`, see above), in the coordinates of whoever draws it (a room
## layer — screen px; a close-up — its canvas px, scaled by the panel).
static func stand_in(stub: Dictionary) -> Node2D:
	var root := Node2D.new()
	root.name = "StandIn"
	for i in stub.get("crops", []).size():
		var c: Dictionary = stub["crops"][i]
		var image := String(c.get("image", ""))
		if image == "" or not ResourceLoader.exists(image):
			continue
		var reg: Array = c.get("region", [0, 0, 64, 64])
		var at := AtlasTexture.new()
		at.atlas = load(image)
		at.region = Rect2(float(reg[0]), float(reg[1]), float(reg[2]), float(reg[3]))
		var r: Array = c.get("rect", reg)
		var spr := Sprite2D.new()
		spr.name = "Crop%d" % i
		spr.texture = at
		spr.centered = false
		spr.position = Vector2(float(r[0]), float(r[1]))
		spr.scale = Vector2(float(r[2]) / maxf(float(reg[2]), 1.0), float(r[3]) / maxf(float(reg[3]), 1.0))
		if c.has("modulate"):
			spr.modulate = _col(c["modulate"])
		root.add_child(spr)
	if not stub.get("shapes", []).is_empty():
		root.add_child(build(stub["shapes"]))
	for i in stub.get("texts", []).size():
		var lb := text_label(stub["texts"][i])
		lb.name = "Text%d" % i
		root.add_child(lb)
	return root


## Words in the game's font inside `rect` [x, y, w, h] (a chalk answer on the board, a caption on a stand-in):
## `font` (body_italic by default; "italic" = body_italic), `font_size`, `color` with `alpha`, tilted by `angle_deg`.
static func text_label(l: Dictionary) -> Label:
	var r: Array = l.get("rect", [0, 0, 400, 100])
	var lbl := Label.new()
	lbl.name = "Text"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # before text and size (an unwrapped Label keeps its text width)
	lbl.text = StoryData.text(String(l.get("text", "")))
	lbl.position = Vector2(float(r[0]), float(r[1]))
	lbl.size = Vector2(float(r[2]), float(r[3]))
	lbl.pivot_offset = lbl.size / 2.0
	lbl.rotation = deg_to_rad(float(l.get("angle_deg", 0.0)))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var role := String(l.get("font", "body_italic"))
	if role == "italic":
		role = "body_italic"
	lbl.add_theme_font_override("font", UiTheme.font(role))
	lbl.add_theme_font_size_override("font_size", int(l.get("font_size", 40)))
	var c := Color.html(String(l.get("color", "#ecebe4")))
	c.a = float(l.get("alpha", 0.75))
	lbl.add_theme_color_override("font_color", c)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


static func build(shapes: Array) -> Node2D:
	var root := Node2D.new()
	root.name = "Placeholder"
	for i in shapes.size():
		var s: Dictionary = shapes[i]
		var n := shape_node(s)
		if n != null:
			n.name = String(s.get("id", "%s_%d" % [String(s.get("type", "shape")), i]))
			root.add_child(n)
	return root


static func shape_node(s: Dictionary) -> CanvasItem:
	match String(s.get("type", "")):
		"gradient":
			return _gradient(s)
		"poly":
			var p := Polygon2D.new()
			p.polygon = _points(s.get("points", []))
			p.color = _col(s.get("color", "#808080"))
			return p
		"line":
			var l := Line2D.new()
			l.points = _points(s.get("points", []))
			l.width = float(s.get("width", 4.0))
			l.default_color = _col(s.get("color", "#404040"))
			l.joint_mode = Line2D.LINE_JOINT_ROUND
			l.begin_cap_mode = Line2D.LINE_CAP_ROUND
			l.end_cap_mode = Line2D.LINE_CAP_ROUND
			return l
		"rect":
			var rr: Array = s.get("rect", [0, 0, 10, 10])
			var p2 := Polygon2D.new()
			var sz := Vector2(float(rr[2]), float(rr[3]))
			p2.polygon = PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)])
			p2.position = Vector2(float(rr[0]), float(rr[1])) + sz / 2.0
			p2.offset = -sz / 2.0
			p2.rotation = deg_to_rad(float(s.get("angle_deg", 0.0)))
			p2.color = _col(s.get("color", "#808080"))
			return p2
		"dashes":
			var root := Node2D.new()
			var pts := _points(s.get("points", []))
			var dash := float(s.get("dash", 10.0))
			var gap := float(s.get("gap", 7.0))
			for i in range(1, pts.size()):
				var a := pts[i - 1]
				var seg := a.distance_to(pts[i])
				var d := (pts[i] - a) / maxf(seg, 0.001)
				var t := 0.0
				while t < seg:
					var dl := Line2D.new()
					dl.points = PackedVector2Array([a + d * t, a + d * minf(t + dash, seg)])
					dl.width = float(s.get("width", 3.0))
					dl.default_color = _col(s.get("color", "#404040"))
					root.add_child(dl)
					t += dash + gap
			return root
		"circle":
			var c := Polygon2D.new()
			c.polygon = circle_points(_v(s.get("center", [0, 0])), float(s.get("r", 10.0)))
			c.color = _col(s.get("color", "#808080"))
			return c
		"glow":
			var g := glow(_v(s.get("center", [0, 0])), float(s.get("r", 40.0)), _col(s.get("color", "#ffd080")))
			# `ry` — a soft ellipse (a haze along the far bank); `blend` "mix" — darkening instead of light.
			if s.has("ry"):
				g.scale.y = float(s["ry"]) * 2.0 / 64.0
			if String(s.get("blend", "add")) == "mix":
				g.material = null
			return g
		"text":
			var lb := Label.new()
			lb.text = StoryData.text(String(s.get("text", "")))
			lb.position = _v(s.get("at", [0, 0]))
			lb.add_theme_font_size_override("font_size", int(s.get("size", 28)))
			lb.add_theme_color_override("font_color", _col(s.get("color", "#d8d0c0")))
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var f := UiTheme.font(String(s.get("font", "head_bold")))
			if f != null:
				lb.add_theme_font_override("font", f)
			return lb
	push_warning("PlaceholderArt: unknown shape type %s" % String(s.get("type", "")))
	return null


## A soft round light: a radial gradient texture drawn additively (the far-shore lights, Mitya's lantern).
static func glow(center: Vector2, r: float, color: Color) -> Sprite2D:
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, color.a))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.25, Color(color.r, color.g, color.b, color.a * 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = center
	spr.scale = Vector2(r * 2.0 / 64.0, r * 2.0 / 64.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	return spr


static func _gradient(s: Dictionary) -> TextureRect:
	var r: Array = s.get("rect", [0, 0, 1920, 1080])
	var g := Gradient.new()
	g.set_color(0, _col(s.get("top", "#202830")))
	g.set_color(1, _col(s.get("bottom", "#101418")))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 128
	var tr := TextureRect.new()
	tr.texture = tex
	tr.position = Vector2(float(r[0]), float(r[1]))
	tr.size = Vector2(float(r[2]), float(r[3]))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## A standing figure seen from the front, filling `rect` (feet at its bottom): head, shoulders, coat, legs —
## a flat dark shape with a lighter rim, so the NPC reads as a person, not a box (Pavel, Mitya until their
## sheets come, BRIEF_CHATGPT_v4 §A). `beard` widens the lower face, `lantern` hangs a lit lantern in the hand.
static func silhouette(rect: Rect2, color: Color, opts: Dictionary = {}) -> Node2D:
	var root := Node2D.new()
	root.name = "Silhouette"
	var w := rect.size.x
	var h := rect.size.y
	var x0 := rect.position.x
	var y0 := rect.position.y
	var cx := x0 + w * 0.5
	var head_r := h * 0.068
	var head_c := Vector2(cx, y0 + head_r * 1.05)
	var neck := y0 + head_r * 2.1
	var shoulder := neck + h * 0.03
	var hip := y0 + h * 0.56
	var hem := y0 + h * 0.80
	var body := PackedVector2Array([
		Vector2(cx - w * 0.10, neck), Vector2(cx + w * 0.10, neck),
		Vector2(cx + w * 0.42, shoulder + h * 0.035), Vector2(cx + w * 0.46, hip),
		Vector2(cx + w * 0.47, hem), Vector2(cx - w * 0.47, hem),
		Vector2(cx - w * 0.46, hip), Vector2(cx - w * 0.42, shoulder + h * 0.035)])
	var legs := PackedVector2Array([
		Vector2(cx - w * 0.30, hem - 2), Vector2(cx - w * 0.04, hem - 2), Vector2(cx - w * 0.05, y0 + h),
		Vector2(cx - w * 0.30, y0 + h), Vector2(cx + w * 0.04, hem - 2), Vector2(cx + w * 0.30, hem - 2),
		Vector2(cx + w * 0.30, y0 + h), Vector2(cx + w * 0.05, y0 + h)])
	var rim := Polygon2D.new()
	rim.name = "Rim"
	rim.color = color.lightened(0.35)
	rim.polygon = _grow(body, 3.0)
	root.add_child(rim)
	var b := Polygon2D.new()
	b.name = "Body"
	b.color = color
	b.polygon = body
	root.add_child(b)
	var l1 := Polygon2D.new()
	l1.name = "LegL"
	l1.color = color.darkened(0.15)
	l1.polygon = legs.slice(0, 4)
	root.add_child(l1)
	var l2 := Polygon2D.new()
	l2.name = "LegR"
	l2.color = color.darkened(0.15)
	l2.polygon = legs.slice(4, 8)
	root.add_child(l2)
	var head := Polygon2D.new()
	head.name = "Head"
	head.color = color.lightened(0.08)
	head.polygon = circle_points(head_c, head_r)
	root.add_child(head)
	if bool(opts.get("cap", false)):
		var cap := Polygon2D.new()
		cap.name = "Cap"
		cap.color = color.darkened(0.3)
		cap.polygon = PackedVector2Array([head_c + Vector2(-head_r * 1.15, -head_r * 0.15), head_c + Vector2(head_r * 1.35, -head_r * 0.15),
			head_c + Vector2(head_r * 0.9, -head_r * 0.95), head_c + Vector2(-head_r * 0.9, -head_r * 0.95)])
		root.add_child(cap)
	if bool(opts.get("beard", false)):
		var beard := Polygon2D.new()
		beard.name = "Beard"
		beard.color = Color.html(String(opts.get("beard_color", "#8a8378")))
		beard.polygon = PackedVector2Array([head_c + Vector2(-head_r * 0.8, head_r * 0.2), head_c + Vector2(head_r * 0.8, head_r * 0.2),
			head_c + Vector2(head_r * 0.5, head_r * 1.5), head_c + Vector2(0, head_r * 1.85), head_c + Vector2(-head_r * 0.5, head_r * 1.5)])
		root.add_child(beard)
	if bool(opts.get("lantern", false)):
		var hand := Vector2(cx + w * 0.50, hip + h * 0.02)
		var handle := Line2D.new()
		handle.name = "LanternHandle"
		handle.points = PackedVector2Array([Vector2(cx + w * 0.44, hip - h * 0.08), hand])
		handle.width = maxf(2.0, w * 0.04)
		handle.default_color = color.darkened(0.2)
		root.add_child(handle)
		var box := Polygon2D.new()
		box.name = "Lantern"
		box.color = Color(1.0, 0.82, 0.45)
		var lw := w * 0.16
		box.polygon = PackedVector2Array([hand + Vector2(-lw / 2, 0), hand + Vector2(lw / 2, 0), hand + Vector2(lw / 2, lw * 1.3), hand + Vector2(-lw / 2, lw * 1.3)])
		root.add_child(box)
		var gl := glow(hand + Vector2(0, lw * 0.65), w * 1.1, Color(1.0, 0.75, 0.35, 0.75))
		gl.name = "LanternGlow"
		root.add_child(gl)
	return root


static func circle_points(c: Vector2, r: float, n: int = SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(poly, by)
	return grown[0] if not grown.is_empty() else poly


static func _points(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(_v(p))
	return out


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _col(c) -> Color:
	return Color.html(String(c))
