extends Node
## Autoload `RoomManager`: owns the lifecycle of room scenes and the player's placement.
##
## `Main` registers the world container and the player with `setup()`. A room is built from
## data (`data/story/rooms/<id>.json` via RoomBuilder) when it exists there, otherwise loaded from
## `res://scenes/rooms/<id>.tscn` or the probe fixtures in `res://scenes/probe/`. After every room
## change the state is autosaved to `autosave_slot` and flag-driven visuals are re-applied; every
## `autosave_interval_s` of play too (G5) — always between things, never inside a line, a staging or a close-up.

signal room_changed(room_id: String)
signal room_change_failed(room_id: String, reason: String)

const SCENE_DIRS: Array[String] = ["res://scenes/rooms", "res://scenes/probe"]

var autosave_slot: String = "auto"
var autosave_enabled: bool = true
## G5 (Director 23.10: «автосохранение раз в 5 минут»): play time between timed autosaves (data/story/meta.json
## autosave.interval_s, 300). Counted while a room is on screen and the tree is not paused.
var autosave_interval_s: float = 300.0
var play_since_autosave: float = 0.0
var autosave_pending: bool = false     # an autosave asked for in the middle of a line / staging / close-up waits
var autosaves_done: int = 0            # tests
## Prefix of scene checkpoint slots (scenes data `checkpoint.slot`, «day2»): tests set their own so a run never
## overwrites the player's «День второй» in the shared user://saves.
var checkpoint_prefix: String = ""

var room_container: Node = null
var player: Node2D = null
var current_room: Room = null


func setup(container: Node, the_player: Node2D) -> void:
	room_container = container
	player = the_player
	if StoryData.autosave_cfg.has("interval_s"):
		autosave_interval_s = maxf(float(StoryData.autosave_cfg["interval_s"]), 5.0)


func _process(delta: float) -> void:
	if current_room == null or not is_instance_valid(current_room) or not autosave_enabled:
		return
	play_since_autosave += delta
	if play_since_autosave >= autosave_interval_s:
		autosave_pending = true
	if autosave_pending and can_autosave():
		_write_autosave()


## G5: an autosave is written only between things — never while a line or a choice is on screen, a staging or a
## frame of a scene plays, a close-up (mechanic, puzzle, view, item) is open, or the boat loops; asked for then, it
## waits for the first free moment. A load then never lands in the middle of a scene.
func can_autosave() -> bool:
	if current_room == null or not is_instance_valid(current_room):
		return false
	if StoryRunner.is_busy() or StoryRunner.examined_item != "" or StoryRunner.current_frame != "" or StoryRunner.stage_dim > 0.0:
		return false
	if player != null and player.has_method("is_acting") and bool(player.call("is_acting")):
		return false
	return true


func _write_autosave() -> bool:
	autosave_pending = false
	play_since_autosave = 0.0
	if not save_game(autosave_slot):
		return false
	autosaves_done += 1
	return true


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
	# A room seen through Agata's eyes (R2, the crossing from the boat: rooms/<id>.json "player_hidden")
	# has no figure of her; every other room shows her again.
	player.visible = not (StoryData.has_room(room_id) and bool(StoryData.room(room_id).get("player_hidden", false)))

	GameState.current_room = room_id
	GameState.player_pos = pos
	current_room.apply_flags()
	room_changed.emit(room_id)

	StoryRunner.on_room_entered(room_id)
	if autosave_enabled:
		autosave()   # after the room's first-entry lines are queued: a load never lands before them
	return true


## Autosave after a room change or a story beat (scene completion, a close-up's event): written now if nothing is
## going on (can_autosave), else as soon as it is over (G5). No-op while autosave is disabled. Returns true when
## written now.
func autosave() -> bool:
	if not autosave_enabled:
		return false
	autosave_pending = true
	if can_autosave():
		return _write_autosave()
	return false


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
	autosave_pending = false
	play_since_autosave = 0.0
	return ok


## Start point (data/story/start_points.json; web `?start=<id>`, desktop `-- --start=<id>`): the state after the
## story up to `done_through` — every main scene up to it (in story order) done with its grants and the flags its
## room needed to complete (`complete_when`), the items it gave in the bag unless used up (items.json consumed),
## plus the point's own `flags` (the player's choices, room states) — then `room`/`spawn`. For the Director to
## check a later block without replaying the earlier ones; a normal new game never goes through here.
func start_at(point_id: String) -> bool:
	var p: Dictionary = StoryData.start_points.get(point_id, {})
	if p.is_empty():
		push_warning("RoomManager: no start point '%s'" % point_id)
		return false
	return start_with(p)


## The same from a start point given as data (TR1: a trailer shot's `state` — data/trailer/<id>.json).
func start_with(p: Dictionary) -> bool:
	GameState.reset()
	var upto := String(p.get("done_through", ""))
	var last_goal := ""
	var last_scene := ""
	for id in StoryData.scene_order:
		var sc: Dictionary = StoryData.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		GameState.set_flag("started_" + id, true)
		GameState.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			GameState.set_flag(String(f), true)
		for it in sc.get("grants", {}).get("items", []):
			var iid := String(it)
			GameState.set_flag("has_" + iid, true)
			var meta: Dictionary = StoryData.item(iid)
			if bool(meta.get("inventory", false)) and not bool(meta.get("consumed", false)) and not GameState.has_item(iid):
				GameState.add_item(iid)
		for rid in StoryData.scene_trigger_rooms(id):
			var cw = StoryData.room(rid).get("scenes", {}).get(id, {}).get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []):
					GameState.set_flag(String(f), true)
				if not c.get("any", []).is_empty():
					GameState.set_flag(String(c["any"][0]), true)
		if sc.has("goal"):
			last_goal = StoryData.scene_goal(sc)
			last_scene = id
		if id == upto:
			break
	# Optional scenes of the days before (V01–V03 of day one): done, so they do not play on arrival; first-entry
	# texts of every room (on_enter once_flag) count as seen.
	var upto_ep := int(StoryData.scene(upto).get("episode", 0))
	for id in StoryData.scene_order:
		var sc: Dictionary = StoryData.scene(id)
		if String(sc.get("type", "")) == "minor" and int(sc.get("episode", 0)) <= upto_ep:
			GameState.set_flag("done_" + id, true)
	for rid in StoryData.rooms.keys():
		for oe in StoryData.room(String(rid)).get("on_enter", []):
			if String(oe.get("once_flag", "")) != "":
				GameState.set_flag(String(oe["once_flag"]), true)
	for f in p.get("flags", []):
		GameState.set_flag(String(f), true)
	for f in p.get("unset", []):
		GameState.set_flag(String(f), false)
	for it in p.get("remove_items", []):
		GameState.remove_item(String(it))
	for it in p.get("add_items", []):
		if not GameState.has_item(String(it)):
			GameState.add_item(String(it))
	if last_goal != "":
		GameState.set_goal(last_goal, last_scene)
	return change_room(String(p.get("room", StoryData.start_location)), String(p.get("spawn", "default")))


## Clears story state and starts from `room_id`/`spawn_id` (defaults: locations.json `start`).
func new_game(room_id: String = "", spawn_id: String = "default") -> bool:
	GameState.reset()
	if room_id == "":
		room_id = StoryData.start_location
	return change_room(room_id, spawn_id)
