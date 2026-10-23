class_name ActorShadow
extends Sprite2D
## Soft elliptical contact shadow under an actor's feet: a radial-gradient texture stretched to an
## ellipse, drawn behind the parent sprite (`show_behind_parent`). Sits at the sprite's origin (the
## feet) so it follows the foot-lock offset, and inherits the actor's depth scale, so it shrinks with
## distance like the figure. Size comes from the actor data (`shadow`), in model metres.

const TEX_SIZE := 64


static func make(sheet: ActorSheet) -> ActorShadow:
	var sh := ActorShadow.new()
	sh.name = "Shadow"
	sh.show_behind_parent = true
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, sheet.shadow_alpha), Color(0, 0, 0, sheet.shadow_alpha * 0.55), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	sh.texture = tex
	sh.centered = true
	# Ellipse in the sprite's own pixels (the parent actor applies the depth scale, the sprite 1/texture_scale).
	var w: float = sheet.shadow_width_m * sheet.px_per_meter(1.0) * sheet.texture_scale
	var h: float = w * sheet.shadow_height_ratio
	sh.scale = Vector2(w / TEX_SIZE, h / TEX_SIZE)
	sh.position = Vector2(0, -h * 0.08)  # a touch above the contact line so boots sit "in" it
	return sh


## A shadow of a given ellipse width (in the parent's px), height ratio and peak alpha — for actors
## without a sheet (puppets).
static func make_size(width_px: float, height_ratio: float, alpha: float) -> ActorShadow:
	var sh := ActorShadow.new()
	sh.name = "Shadow"
	sh.show_behind_parent = true
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, alpha), Color(0, 0, 0, alpha * 0.55), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	sh.texture = tex
	sh.centered = true
	var h := width_px * height_ratio
	sh.scale = Vector2(width_px / TEX_SIZE, h / TEX_SIZE)
	sh.position = Vector2(0, -h * 0.08)
	return sh


## Ellipse size on screen (px) for a given actor scale.
static func size_at(sheet: ActorSheet, actor_scale: float) -> Vector2:
	var w: float = sheet.shadow_width_m * sheet.px_per_meter(1.0) * actor_scale
	return Vector2(w, w * sheet.shadow_height_ratio)
