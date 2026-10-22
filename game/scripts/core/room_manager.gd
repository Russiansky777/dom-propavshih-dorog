extends Node
## Autoload `RoomManager`: owns the lifecycle of room scenes and the player's placement.
##
## `Main` registers the world container and the player with `setup()`. A room is built from
## data (`data/story/rooms/<id>.json` via RoomBuilder) when it exists there, otherwise loaded from
## `res://scenes/rooms/<id>.tscn` or the probe fixtures in `res://scenes/probe/`. After every room
## change the state is autosaved to `autosave_slot` and flag-driven visuals are re-applied.

signal room_changed(room_id: String)
signal room_change_failed(room_id: String, reason: String)

const SCENE_DIRS: Array[String] = ["res://scenes/rooms", "res://scenes/probe"]

var autosave_slot: String = "auto"
var autosave_enabled: bool = true
## Prefix of scene checkpoint slots (scenes data `checkpoint.slot`, «day2»): tests set their own so a run never
## overwrites the player's «День второй» in the shared user://saves.
var checkpoint_prefix: String = ""

var room_container: Node = null
var player: Node2D = null
var current_room: Room = null


func setup(container: Node, the_player: Node2D) -> void:
	room_container = container
	player = the_player


func room_scene_path(room_id: String) -> String:
	for d in SCENE_DIRS:
		var p := "%s/%s.tscn" % [d, room_id]
		if ResourceLoader.exists(p):
			return p
	return ""


func has_room(room_id: String) -> bool:
	return StoryData.has_room(room_id) or room_scene_path(room_id) != ""


func _instantiate_room(room_id: String) -> Node:
	if StoryData.has_room(room_id):
		return RoomBuilder.build(room_id)
	var path := room_scene_path(room_id)
	if path == "":
		return null
	var packed: PackedScene = load(path)
	return packed.instantiate() if packed != null else null


## Frees the current room, instantiates `room_id`, places the player at spawn `spawn_id`
## (or at `override_pos` when `spawn_id` is empty), re-applies flags and autosaves.
func change_room(room_id: String, spawn_id: String, override_pos: Vector2 = Vector2.INF) -> bool:
	if room_container == null or player == null:
		push_error("RoomManager.change_room: call setup() first")
		room_change_failed.emit(room_id, "not_setup")
		return false
	if not has_room(room_id):
		push_error("RoomManager.change_room: no data or scene for room '%s'" % room_id)
		room_change_failed.emit(room_id, "missing_scene")
		return false

	if current_room != null and is_instance_valid(current_room):
		room_container.remove_child(current_room)
		current_room.free()  # synchronous: next room must not coexist with the old one
	current_room = null

	var inst := _instantiate_room(room_id)
	if inst == null:
		room_change_failed.emit(room_id, "load_failed")
		return false
	if not (inst is Room):
		push_error("RoomManager.change_room: room %s root is not a Room" % room_id)
		inst.free()
		room_change_failed.emit(room_id, "not_a_room")
		return false
	current_room = inst
	if current_room.room_id == "":
		current_room.room_id = room_id
	room_container.add_child(current_room)
	# Rooms draw under the player; keep the room first among the container's children.
	room_container.move_child(current_room, 0)
	# Animated NPCs on `npc` hotspots that have actor data (sheets like Agata's).
	NpcActor.attach_all(current_room, player)

	# Place the player.
	var pos: Vector2 = override_pos
	if spawn_id != "":
		var spawn := current_room.get_spawn(spawn_id)
		if spawn != null:
			pos = spawn.global_position
		else:
			push_warning("RoomManager: room '%s' has no spawn '%s'" % [room_id, spawn_id])
	if pos == Vector2.INF:
		var fallback := current_room.get_default_spawn()
		pos = fallback.global_position if fallback != null else Vector2(960, 900)
	if player.has_method("enter_room"):
		player.call("enter_room", current_room, pos)
	else:
		player.global_position = pos

	GameState.current_room = room_id
	GameState.player_pos = pos
	current_room.apply_flags()
	room_changed.emit(room_id)

	if autosave_enabled:
		GameState.save(autosave_slot)
	StoryRunner.on_room_entered(room_id)
	return true


## Autosave after a story beat (scene completion); no-op while autosave is disabled.
func autosave() -> bool:
	if not autosave_enabled:
		return false
	return save_game(autosave_slot)


## Saves the running game (player position is captured live). `title` names a checkpoint save in the menu.
func save_game(slot: String, title: String = "") -> bool:
	if player != null:
		GameState.player_pos = player.global_position
	if current_room != null:
		GameState.current_room = current_room.room_id
	return GameState.save(slot, title)


## Loads a slot and rebuilds the scene from it. Returns false when the slot is missing.
func load_game(slot: String) -> bool:
	if not GameState.load(slot):
		return false
	var room_id := GameState.current_room
	if room_id == "" or not has_room(room_id):
		push_error("RoomManager.load_game: save points to unknown room '%s'" % room_id)
		return false
	var saved_autosave := autosave_enabled
	autosave_enabled = false  # loading must not overwrite the autosave with itself
	var ok := change_room(room_id, "", GameState.player_pos)
	autosave_enabled = saved_autosave
	return ok


## Clears story state and starts from `room_id`/`spawn_id` (defaults: locations.json `start`).
func new_game(room_id: String = "", spawn_id: String = "default") -> bool:
	GameState.reset()
	if room_id == "":
		room_id = StoryData.start_location
	return change_room(room_id, spawn_id)
