class_name Hotspot
extends Area2D
## Clickable object in a room. Content is data: which flag it sets and what it says.
##
## Children: a CollisionShape2D/CollisionPolygon2D (click area) and an optional
## `StandPoint` Marker2D where the player walks before interacting.

signal interact(hotspot_id: String)

@export var hotspot_id: String = ""
## Flag set to true when the player interacts (empty = none).
@export var sets_flag: String = ""
## Hint shown on interaction.
@export_multiline var hint: String = ""
## If non-empty and this flag is true, `hint_when_flag` is shown instead of `hint`.
@export var hint_flag: String = ""
@export_multiline var hint_when_flag: String = ""
## Higher wins when several areas overlap under the cursor.
@export var pick_priority: int = 0


func _ready() -> void:
	monitoring = false       # we only need the shape for point picking
	monitorable = true
	input_pickable = false   # picking is done by Room.pick(); keep the engine out of it
	if hotspot_id == "":
		hotspot_id = name.to_snake_case()


func get_stand_position() -> Vector2:
	var sp := get_node_or_null("StandPoint")
	if sp is Node2D:
		return sp.global_position
	return global_position


## Called by the player on arrival. Applies the data-driven effect and emits `interact`.
func trigger() -> void:
	# Pick the hint from the state *before* this interaction changes it.
	var text := hint
	if hint_flag != "" and GameState.has_flag(hint_flag) and hint_when_flag != "":
		text = hint_when_flag
	if sets_flag != "":
		GameState.set_flag(sets_flag, true)
	if text != "":
		GameState.show_hint(text)
	interact.emit(hotspot_id)
