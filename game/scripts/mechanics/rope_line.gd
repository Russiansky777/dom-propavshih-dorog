class_name RopeLine
extends RefCounted
## A rope drawn by the engine looks like the painted one (Director 23.10, F5: «однородного цвета» — no more
## flat lines): a Line2D in tile mode with the strip cut from the painting (tools/make_rope_texture.py →
## rope_tile.png — the strands, highlights and fibres of closeup_plate_rope), and a soft shadow under it.
## `scroll(line, px)` slides the strands along the line (a rope hauled through a ring).

const TEXTURE := "res://assets/closeups/rope_tile.png"


## A textured rope `width` px thick (the texture's height maps onto the width; the strands tile along it).
static func make(width: float, node_name: String = "Rope") -> Line2D:
	var l := Line2D.new()
	l.name = node_name
	l.width = width
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.antialiased = false
	if ResourceLoader.exists(TEXTURE):
		l.texture = load(TEXTURE)
		l.texture_mode = Line2D.LINE_TEXTURE_TILE
		l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		l.default_color = Color.WHITE
	else:
		l.default_color = Color(0.55, 0.42, 0.27)
	return l


## The rope's shadow on the stone or the water: the same line, dark and offset.
static func shadow(width: float, node_name: String = "RopeShadow") -> Line2D:
	var l := Line2D.new()
	l.name = node_name
	l.width = width * 0.9
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.default_color = Color(0, 0, 0, 0.38)
	return l


## Points of a sagging rope from `a` to `b` (a catenary-like curve, `sag` px down at the middle).
static func sag_points(a: Vector2, b: Vector2, sag: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	return out


## Slides the strands along the rope by `px` (a rope hauled through a ring): a tiny canvas shader shifts the
## tile phase.
static func set_phase(l: Line2D, px: float) -> void:
	if l.texture == null:
		return
	var tw := float(l.texture.get_width()) * l.width / maxf(float(l.texture.get_height()), 1.0)
	var mat := l.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = _scroll_shader()
		l.material = mat
	mat.set_shader_parameter("phase", fposmod(px / maxf(tw, 1.0), 1.0))


static var _shader: Shader = null


static func _scroll_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type canvas_item;\nuniform float phase = 0.0;\nvarying vec4 vcol;\nvoid vertex() {\n\tvcol = COLOR;\n}\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, vec2(UV.x + phase, UV.y)) * vcol;\n}\n"
	return _shader
