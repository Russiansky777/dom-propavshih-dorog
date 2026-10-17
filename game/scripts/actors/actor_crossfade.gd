class_name ActorCrossfade
extends AnimatedSprite2D
## Short dissolve between two animations of an actor (idle↔walk↔talk↔action, or a direction row
## change): the outgoing pose is frozen on a copy of the sprite, left in place in the world
## (top_level, so the logical position moving on does not drag it) and faded out over
## ActorSheet.crossfade_s (≈ 0.12 s) on top of the incoming animation. No pose ever jumps.
##
## Usage: `ActorCrossfade.begin(sprite, sheet.crossfade_s)` BEFORE `sprite.play(new_anim)`.

var _t: float = 0.0
var _duration: float = 0.12


## Starts (or restarts) the fade of `sprite`'s current pose. Returns the fade node, or null when there
## is nothing to fade (no animation yet, sprite hidden, zero duration).
static func begin(sprite: AnimatedSprite2D, duration: float) -> ActorCrossfade:
	if sprite == null or duration <= 0.0 or not sprite.is_visible_in_tree() or sprite.sprite_frames == null:
		return null
	if String(sprite.animation) == "" or not sprite.sprite_frames.has_animation(sprite.animation):
		return null
	var parent := sprite.get_parent()
	if parent == null:
		return null
	var fade: ActorCrossfade = parent.get_node_or_null("Crossfade") as ActorCrossfade
	if fade == null:
		fade = ActorCrossfade.new()
		fade.name = "Crossfade"
		parent.add_child(fade)
		parent.move_child(fade, sprite.get_index() + 1)  # drawn right after the sprite: on top of it
	fade.sprite_frames = sprite.sprite_frames
	fade.centered = sprite.centered
	fade.offset = sprite.offset
	fade.texture_filter = sprite.texture_filter
	fade.top_level = true
	fade.global_transform = sprite.global_transform
	fade.z_index = sprite.z_index
	fade.z_as_relative = sprite.z_as_relative
	fade.animation = sprite.animation
	fade.frame = sprite.frame
	fade.stop()  # frozen pose
	fade._duration = duration
	fade._t = 0.0
	fade.modulate = Color(1, 1, 1, 1)
	fade.visible = true
	fade.set_process(true)
	return fade


func _process(delta: float) -> void:
	_t += delta
	var a := 1.0 - clampf(_t / maxf(_duration, 0.001), 0.0, 1.0)
	modulate.a = a
	if a <= 0.0:
		visible = false
		set_process(false)


## True while the old pose is still visible.
func is_fading() -> bool:
	return visible and modulate.a > 0.0
