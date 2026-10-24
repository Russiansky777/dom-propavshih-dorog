class_name SoftWindow
extends Control
## A round window cut into the close-up (Director 24.10, H32: «вырезать и вписать… а не прямоугольники»): the
## picture inside is masked by an ellipse (a circle when the control is square) with a soft edge, a brass rim over
## it and a soft shadow under it. Add the content to `content` (it clips its children by the mask's alpha).
## Data (any of): {"feather": 0.12, "vignette": 0.45, "rim": [r, g, b, a], "rim_width": 3, "shadow": 0.5, "bg": [r, g, b, a]}.

var feather: float = 0.12        # the soft edge, fraction of the radius
var rim_color: Color = Color(0.72, 0.58, 0.34, 0.9)
var rim_width: float = 3.0
var shadow: float = 0.5          # the shadow's opacity under the window
var bg: Color = Color(0.07, 0.05, 0.035, 1.0)
var vignette: float = 0.45       # darkening towards the edge inside the window
var content: TextureRect = null  # the mask: children are clipped by its alpha
var _vig: TextureRect = null
var _rim: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	content = TextureRect.new()
	content.name = "Mask"
	content.stretch_mode = TextureRect.STRETCH_SCALE
	content.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	_vig = TextureRect.new()
	_vig.name = "Vignette"
	_vig.stretch_mode = TextureRect.STRETCH_SCALE
	_vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vig)
	_rim = Control.new()
	_rim.name = "Rim"
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.draw.connect(_draw_rim)
	add_child(_rim)
	resized.connect(_layout)


func configure(cfg: Dictionary) -> void:
	feather = float(cfg.get("feather", feather))
	rim_width = float(cfg.get("rim_width", rim_width))
	shadow = float(cfg.get("shadow", shadow))
	vignette = float(cfg.get("vignette", vignette))
	if cfg.get("rim", null) is Array:
		rim_color = _col(cfg["rim"])
	if cfg.get("bg", null) is Array:
		bg = _col(cfg["bg"])
	_layout()


static func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)


## The mask: a radial gradient, opaque inside, fading over `feather` to nothing at the ellipse's edge; the bg
## colour under the picture (seen where the picture is transparent) is the gradient's own colour.
func _layout() -> void:
	content.size = size
	_rim.size = size
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, clampf(1.0 - feather, 0.0, 0.999), 1.0])
	g.colors = PackedColorArray([bg, bg, Color(bg, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	content.texture = gt
	_vig.size = size
	var vg := Gradient.new()
	var e := clampf(1.0 - feather, 0.05, 0.999)
	vg.offsets = PackedFloat32Array([0.0, e * 0.55, e, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.03, 0.02, 0.01, vignette), Color(0.03, 0.02, 0.01, 0)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 0.5)
	vt.width = 256
	vt.height = 256
	_vig.texture = vt
	queue_redraw()
	_rim.queue_redraw()


## True when `p` (local) is inside the ellipse.
func has_point_inside(p: Vector2) -> bool:
	var r := size * 0.5
	if r.x <= 0.0 or r.y <= 0.0:
		return false
	var d := (p - r) / r
	return d.length_squared() <= 1.0


func _ellipse(scale_r: float, n: int = 72) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := size * 0.5
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * c.x, sin(a) * c.y) * scale_r)
	return pts


## The shadow under the window: a few soft ellipses, offset down.
func _draw() -> void:
	if shadow <= 0.0:
		return
	for i in 6:
		var k := 1.0 + 0.02 * (6 - i)
		var pts := _ellipse(k)
		for j in pts.size():
			pts[j] += Vector2(3, 7)
		draw_colored_polygon(pts, Color(0, 0, 0, shadow / 6.0))


## The rim: a thin brass line where the soft edge begins, a darker line outside it.
func _draw_rim() -> void:
	if rim_width <= 0.0:
		return
	var inner := 1.0 - feather * 0.5
	_rim.draw_polyline(_ellipse(inner), Color(0, 0, 0, 0.35), rim_width + 2.0, true)
	_rim.draw_polyline(_ellipse(inner), rim_color, rim_width, true)
	_rim.draw_polyline(_ellipse(inner - 0.012), Color(1, 0.92, 0.7, 0.18), 1.0, true)
