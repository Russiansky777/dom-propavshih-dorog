class_name RoomExit
extends Area2D
## Walk-to exit: when the player reaches `StandPoint`, RoomManager switches rooms.

signal used(target_room: String, target_spawn: String)

@export var target_room: String = ""
@export var target_spawn: String = ""
## Optional flag that must be true for the exit to work (empty = always open).
@export var requires_flag: String = ""
@export_multiline var locked_hint: String = ""
@export var pick_priority: int = 1


func _ready() -> void:
	monitoring = false
	monitorable = true
	input_pickable = false


func get_stand_position() -> Vector2:
	var sp := get_node_or_null("StandPoint")
	if sp is Node2D:
		return sp.global_position
	return global_position


func trigger() -> void:
	if requires_flag != "" and not GameState.has_flag(requires_flag):
		if locked_hint != "":
			GameState.show_hint(locked_hint)
		return
	used.emit(target_room, target_spawn)
	# Deferred: we are called from the player's physics step; freeing the room there is unsafe.
	RoomManager.call_deferred("change_room", target_room, target_spawn)
