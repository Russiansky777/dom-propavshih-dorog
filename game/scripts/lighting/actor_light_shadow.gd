class_name ActorLightShadow
extends Sprite2D
## Cast shadow of an actor (Agata, Tamara, Pelageya) from one room light with `casts_actor_shadow`
## (data/story/lights/<LOC>.json). Mechanism `actor_light_shadow`:
##   - the CURRENT frame of the actor's AnimatedSprite2D is the silhouette (synced on frame_changed /
##     animation_changed and checked every frame, so it never lags behind or flashes on a switch);
##   - child of that sprite (like the contact ellipse ActorShadow, which stays as it is): follows the
##     foot-lock offset and the depth scale, drawn behind the figure (`show_behind_parent`);
##   - squashed vertically and skewed AWAY from the source: the floor vector source→feet is measured
##     in floor units (screen y ÷ room foreshortening `c`); its angle θ (0 = straight towards the
##     viewer, ±90° = sideways) puts the head of the silhouette at
##     (sin θ · length, max(c · cos θ · length, min_squash)) × figure height — the figure keeps its
##     width, lies down towards the viewer and leans away from the light. θ is clamped to ±max_theta
##     (88°): the shadow never flips over the feet, and never collapses to a line (min_squash);
##   - length and opacity by distance to the source (near_px → far_px), opacity × source level ×
##     flicker; fades to 0 right at the source and beyond `far_px`;
##   - every parameter is eased (time constant ~0.08 s): no jump when a walk frame moves the drawn
##     figure by a stride, no blink when the light fades in or out.
## The shader (shaders/light_actor_shadow.gdshader) draws black, blurred, fading towards the head.

const SHADER := preload("res://shaders/light_actor_shadow.gdshader")
const SMOOTH_RATE := 12.0

var sprite: AnimatedSprite2D = null
var source: LightSource = null
var foreshortening: float = 0.42
var _theta: float = 0.0
var _len: float = 0.0
var _alpha: float = 0.0
var _primed: bool = false
var _anim: StringName = &""
var _frame: int = -1


static func attach(actor_sprite: AnimatedSprite2D, src: LightSource, c: float) -> ActorLightShadow:
	var sh := ActorLightShadow.new()
	sh.name = "LightShadow_" + src.source_id
	sh.sprite = actor_sprite
	sh.source = src
	sh.foreshortening = clampf(c, 0.1, 1.0)
	sh.show_behind_parent = true
	sh.centered = false
	sh.offset = actor_sprite.offset
	sh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sh.process_priority = 20  # after the player's foot lock (priority 10)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("figure_h", -actor_sprite.offset.y)
	mat.set_shader_parameter("blur_px", float(src.shadow.get("blur_px", 2.5)))
	mat.set_shader_parameter("head_fade", float(src.shadow.get("head_fade", 0.6)))
	mat.set_shader_parameter("alpha", 0.0)
	sh.material = mat
	sh.visible = false
	actor_sprite.add_child(sh)
	actor_sprite.move_child(sh, 0)  # under the contact ellipse (both behind the figure)
	actor_sprite.frame_changed.connect(sh.sync_frame)
	actor_sprite.animation_changed.connect(sh.sync_frame)
	sh.sync_frame()
	return sh


## Shows the actor's current frame (same texture as the sprite this instant).
func sync_frame() -> void:
	if sprite == null or not is_instance_valid(sprite) or sprite.sprite_frames == null:
		return
	var anim := sprite.animation
	if not sprite.sprite_frames.has_animation(anim):
		return
	var n := sprite.sprite_frames.get_frame_count(anim)
	if n <= 0:
		return
	var f := clampi(sprite.frame, 0, n - 1)
	_anim = anim
	_frame = f
	var tex := sprite.sprite_frames.get_frame_texture(anim, f)
	if tex != texture:
		texture = tex
	if offset != sprite.offset:
		offset = sprite.offset


## Target shadow parameters for the drawn feet `feet` (screen px): [theta, length, alpha].
func target_params(feet: Vector2) -> Array:
	var sp: Dictionary = source.shadow
	var c := foreshortening
	var fl_pt := source.shadow_floor()
	var v := feet - fl_pt
	var fl := Vector2(v.x, v.y / c)
	var dist := fl.length()
	var near := float(sp.get("near_px", 90.0))
	var far := float(sp.get("far_px", 1200.0))
	var k := clampf((dist - near) / maxf(far - near, 1.0), 0.0, 1.0)
	var a := lerpf(float(sp.get("alpha", 0.35)), float(sp.get("alpha_far", 0.08)), k)
	a *= smoothstep(0.0, near, dist)                            # right at the source: none
	a *= 1.0 - smoothstep(far, far * 1.25, dist)                # out of reach: none
	a *= source.shadow_strength()
	var max_theta := deg_to_rad(float(sp.get("max_theta_deg", 88.0)))
	var theta := clampf(atan2(fl.x, fl.y), -max_theta, max_theta) if dist > 0.001 else 0.0
	var length := lerpf(float(sp.get("len", 0.55)), float(sp.get("len_far", 1.2)), k)
	return [theta, length, clampf(a, 0.0, 1.0)]


## Transform of the silhouette for angle `theta` and relative `length` (local = sheet px):
## the figure's width stays horizontal, its height maps to the head vector (lean, squash).
func shadow_transform(theta: float, length: float) -> Transform2D:
	var c := foreshortening
	var width := float(source.shadow.get("width", 1.0))
	var min_squash := float(source.shadow.get("min_squash", 0.16))
	var head := Vector2(sin(theta) * length, maxf(c * cos(theta) * length, min_squash))
	return Transform2D(Vector2(width, 0.0), -head, Vector2.ZERO)


func _process(delta: float) -> void:
	if sprite == null or not is_instance_valid(sprite) or source == null or not is_instance_valid(source):
		visible = false
		return
	if sprite.animation != _anim or sprite.frame != _frame:
		sync_frame()
	var tgt := target_params(sprite.global_position)
	if not _primed:
		_theta = tgt[0]
		_len = tgt[1]
		_alpha = tgt[2]
		_primed = true
	else:
		var w := 1.0 - exp(-delta * SMOOTH_RATE)
		_theta = lerp_angle(_theta, float(tgt[0]), w)
		_len = lerpf(_len, float(tgt[1]), w)
		_alpha = lerpf(_alpha, float(tgt[2]), w)
	transform = shadow_transform(_theta, _len)
	var on := _alpha > 0.004 and texture != null
	if visible != on:
		visible = on
	if on:
		(material as ShaderMaterial).set_shader_parameter("alpha", _alpha)


## Current eased values (tests): {theta, length, alpha}.
func current() -> Dictionary:
	return {"theta": _theta, "length": _len, "alpha": _alpha}
