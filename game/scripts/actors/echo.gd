extends Node2D
## The Echo: a repeat of an unfinished action, not a person. Looped by AnimationPlayer.
## Only responsibility here: y-sort against the player (z_index = int(y)).

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	z_index = clampi(int(global_position.y), -4096, 4096)
	if anim != null and not anim.is_playing():
		anim.play("loop")


func is_looping() -> bool:
	return anim != null and anim.is_playing() and anim.current_animation == "loop"
