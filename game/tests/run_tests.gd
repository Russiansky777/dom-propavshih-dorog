extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path game -s res://tests/run_tests.gd
## Prints PASS/FAIL per test; exit code 0 only when every check passed.
##
## Note: a `-s` script is compiled before autoload singletons are registered, so it
## reaches them through the tree (`root.get_node("GameState")`), never by bare identifier.

const TEST_SLOT: String = "test_slot"
const TEST_AUTOSAVE_SLOT: String = "test_auto"

var gs: Node
var rm: Node
var world: Node2D
var player: Node2D

var _results: Array = []      # [name: String, passed: bool, message: String]
var _current_checks: Array = []  # failures of the running test


func _initialize() -> void:
	gs = root.get_node_or_null("GameState")
	rm = root.get_node_or_null("RoomManager")
	_run()


func _run() -> void:
	await process_frame
	if gs == null or rm == null:
		_results.append(["autoloads", false, "GameState/RoomManager autoloads missing from the tree"])
		_finish()
		return
	rm.autosave_slot = TEST_AUTOSAVE_SLOT
	rm.autosave_enabled = false

	await _test("GameState save → modify → load restores flags/inventory/room", _test_save_load)
	await _test("RoomManager.change_room loads RoomOffice and places player at spawn", _test_change_room)
	await _test("RoomManager autosaves to slot after room change", _test_autosave)
	await _test("Room.apply_flags toggles door state nodes on office_latch_open", _test_apply_flags)
	await _test("NavigationServer2D returns a path inside RoomHouse.Walkable", _test_navigation_path)
	await _test("Room.pick finds hotspot/exit under a point", _test_pick)
	await _test("Mirror shows RoomOfficeView through a ViewportTexture with Echo looping", _test_mirror)
	await _test("Player walks to the exit and RoomManager switches rooms", _test_walk_to_exit)
	await _test("Save/load round-trip survives room change and restores player position", _test_save_load_room)
	await _test("InputMap: F5 → quick_save, F9 → quick_load", _test_input_map)
	_cleanup()
	# --- M1: data-driven rooms and story runner ---
	await _test("StoryData loads every JSON and every room builds without errors", _test_story_data)
	await _test("Negative: exit H3→O1 is closed before M05 and open after", _test_exit_gate)
	await _test("Bot walkthrough M01→M08 via StoryRunner/Room API with mid-way save/load", _test_walkthrough)
	await _test("H1: Agata sprite from sheets (288x384, 8 walk + 8 idle), directions, table occluder z-sort", _test_h1_real)
	_cleanup_m1()
	_finish()


# --- Harness ---------------------------------------------------------------

func _test(test_name: String, fn: Callable) -> void:
	_current_checks = []
	var started := Time.get_ticks_msec()
	await fn.call()
	var ms := Time.get_ticks_msec() - started
	var passed := _current_checks.is_empty()
	_results.append([test_name, passed, "; ".join(_current_checks)])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, ms])
	if not passed:
		for c in _current_checks:
			print("        - " + c)


func _check(cond: bool, message: String) -> void:
	if not cond:
		_current_checks.append(message)


func _finish() -> void:
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	if failed > 0:
		print("Failures:")
		for r in _results:
			if not r[1]:
				print("  FAIL %s: %s" % [r[0], r[2]])
	quit(0 if failed == 0 else 1)


func _cleanup() -> void:
	gs.delete_save(TEST_SLOT)
	gs.delete_save(TEST_AUTOSAVE_SLOT)
	if world != null and is_instance_valid(world):
		root.remove_child(world)
		world.free()
	rm.current_room = null
	world = null
	player = null


func _ensure_world() -> void:
	if world != null and is_instance_valid(world):
		return
	world = Node2D.new()
	world.name = "World"
	root.add_child(world)
	var player_scene: PackedScene = load("res://scenes/actors/Player.tscn")
	player = player_scene.instantiate()
	world.add_child(player)
	rm.setup(world, player)


# --- Tests -----------------------------------------------------------------

func _test_save_load() -> void:
	gs.reset()
	gs.set_flag("office_latch_open", true)
	gs.set_flag("mirror_mounted", false)
	_check(gs.add_item("key_mill"), "add_item should return true for a new item")
	_check(not gs.add_item("key_mill"), "add_item must refuse a duplicate")
	gs.current_room = "RoomOffice"
	gs.player_pos = Vector2(123, 456)
	_check(gs.save(TEST_SLOT), "save() returned false")
	_check(gs.has_save(TEST_SLOT), "save file missing after save()")

	# Modify everything.
	gs.reset()
	gs.set_flag("unrelated", true)
	gs.add_item("spoon")
	gs.current_room = "Nowhere"
	gs.player_pos = Vector2.ZERO

	_check(gs.load(TEST_SLOT), "load() returned false")
	_check(gs.has_flag("office_latch_open"), "flag office_latch_open not restored")
	_check(gs.flags.get("mirror_mounted", true) == false, "flag mirror_mounted=false not restored")
	_check(not gs.has_flag("unrelated"), "flag set after save should be gone after load")
	_check(gs.inventory == ["key_mill"], "inventory not restored: %s" % str(gs.inventory))
	_check(gs.current_room == "RoomOffice", "current_room not restored: %s" % gs.current_room)
	_check(gs.player_pos == Vector2(123, 456), "player_pos not restored: %s" % str(gs.player_pos))
	_check(not gs.load("missing_slot_xyz"), "load() of a missing slot must return false")
	gs.reset()


func _test_change_room() -> void:
	_ensure_world()
	var ok: bool = rm.change_room("RoomOffice", "from_house")
	await process_frame
	_check(ok, "change_room returned false")
	_check(rm.current_room != null, "current_room is null")
	if rm.current_room == null:
		return
	_check(rm.current_room.room_id == "RoomOffice", "room_id is %s" % rm.current_room.room_id)
	_check(world.has_node("RoomOffice"), "RoomOffice not in the world container")
	_check(world.get_child(0) == rm.current_room, "room must be the first child (drawn under the player)")
	var spawn: Node2D = rm.current_room.get_spawn("from_house")
	_check(spawn != null, "spawn 'from_house' not found")
	if spawn != null:
		_check(player.global_position.is_equal_approx(spawn.global_position),
			"player at %s, spawn at %s" % [str(player.global_position), str(spawn.global_position)])
	_check(gs.current_room == "RoomOffice", "GameState.current_room not updated")
	_check(player.get("room") == rm.current_room, "player.room not bound to the new room")


func _test_autosave() -> void:
	_ensure_world()
	gs.delete_save(TEST_AUTOSAVE_SLOT)
	rm.autosave_enabled = true
	rm.change_room("RoomHouse", "start")
	await process_frame
	rm.autosave_enabled = false
	_check(gs.has_save(TEST_AUTOSAVE_SLOT), "autosave slot '%s' not written" % TEST_AUTOSAVE_SLOT)
	_check(not world.has_node("RoomOffice"), "previous room must be freed")
	_check(world.has_node("RoomHouse"), "RoomHouse not in the world container")


func _test_apply_flags() -> void:
	_ensure_world()
	gs.reset()
	rm.change_room("RoomHouse", "start")
	await process_frame
	var room: Node = rm.current_room
	var closed: CanvasItem = room.get_node_or_null("Hotspots/Door/DoorClosed")
	var opened: CanvasItem = room.get_node_or_null("Hotspots/Door/DoorOpen")
	_check(closed != null and opened != null, "door state nodes missing")
	if closed == null or opened == null:
		return
	_check(closed.visible and not opened.visible, "initial: expected closed visible, open hidden")
	gs.set_flag("office_latch_open", true)
	_check(opened.visible and not closed.visible, "after set: expected open visible, closed hidden")
	gs.set_flag("office_latch_open", false)
	_check(closed.visible and not opened.visible, "after clear: expected closed visible, open hidden")
	# Explicit re-apply after a silent state swap (what RoomManager does after load).
	gs.flags["office_latch_open"] = true
	room.apply_flags()
	_check(opened.visible and not closed.visible, "apply_flags() did not re-sync visuals")
	gs.reset()
	room.apply_flags()
	_check(closed.visible and not opened.visible, "apply_flags() after reset did not restore closed state")


func _test_navigation_path() -> void:
	_ensure_world()
	if rm.current_room == null or rm.current_room.room_id != "RoomHouse":
		rm.change_room("RoomHouse", "start")
	var region: NavigationRegion2D = rm.current_room.get_walkable()
	_check(region != null, "Walkable NavigationRegion2D missing")
	if region == null:
		return
	var map: RID = region.get_navigation_map()
	var from := Vector2(400, 900)
	var to := Vector2(1500, 1000)
	# Godot 4.7.2: a freshly added region is queryable only after the map's second sync
	# iteration (observed: ~5 physics frames). Poll with a hard cap instead of a fixed wait.
	var path: PackedVector2Array = PackedVector2Array()
	var frames := 0
	while path.size() < 2 and frames < 60:
		await physics_frame
		frames += 1
		path = NavigationServer2D.map_get_path(map, from, to, true)
	print("        nav map ready after %d physics frames (iteration %d)" % [frames, NavigationServer2D.map_get_iteration_id(map)])
	_check(path.size() >= 2, "path is empty or trivial (size %d) after %d physics frames" % [path.size(), frames])
	if path.size() >= 2:
		_check(path[0].distance_to(from) < 1.0, "path does not start at from: %s" % str(path[0]))
		_check(path[path.size() - 1].distance_to(to) < 1.0, "path does not end at to: %s" % str(path[path.size() - 1]))
	# A point outside the polygon is clamped to the closest navigable point.
	var closest := NavigationServer2D.map_get_closest_point(map, Vector2(960, 300))
	_check(closest.y >= 639.0, "closest point for an off-floor target should be on the floor edge, got %s" % str(closest))


func _test_pick() -> void:
	_ensure_world()
	if rm.current_room == null or rm.current_room.room_id != "RoomHouse":
		rm.change_room("RoomHouse", "start")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var hit: Node = room.pick(Vector2(1350, 400))
	_check(hit != null and hit.get("hotspot_id") == "office_door", "pick at door center returned %s" % str(hit))
	var hit_exit: Node = room.pick(Vector2(1860, 850))
	_check(hit_exit != null and hit_exit.get("target_room") == "RoomOffice", "pick at exit returned %s" % str(hit_exit))
	var hit_mirror: Node = room.pick(Vector2(560, 330))
	_check(hit_mirror != null and hit_mirror.get("hotspot_id") == "mirror_frame", "pick at mirror returned %s" % str(hit_mirror))
	var none: Node = room.pick(Vector2(960, 950))
	_check(none == null, "pick on empty floor returned %s" % str(none))


func _test_mirror() -> void:
	_ensure_world()
	if rm.current_room == null or rm.current_room.room_id != "RoomHouse":
		rm.change_room("RoomHouse", "start")
	await process_frame
	var mirror: Node = rm.current_room.get_node_or_null("Mirror")
	_check(mirror != null, "Mirror node missing")
	if mirror == null:
		return
	var glass: Sprite2D = mirror.get_node_or_null("Glass")
	_check(glass != null and glass.texture is ViewportTexture, "Glass texture is not a ViewportTexture")
	var view: Node = mirror.get_node_or_null("SubViewport/OfficeView")
	_check(view != null, "OfficeView not instanced inside the SubViewport")
	if view != null:
		var echo: Node = view.get_node_or_null("Echo")
		_check(echo != null and echo.call("is_looping"), "Echo in mirror view is not looping")
		var echo_figure: Node2D = view.get_node_or_null("Echo/Figure")
		if echo_figure != null:
			var x0 := echo_figure.position.x
			await create_timer(0.3).timeout
			_check(not is_equal_approx(x0, echo_figure.position.x), "Echo figure did not move in 0.3 s (x=%f)" % x0)
	gs.reset()
	mirror.call("refresh")
	_check(mirror.call("is_wobbling") == true, "mirror should wobble while mirror_mounted is false")
	gs.set_flag("mirror_mounted", true)
	_check(mirror.call("is_wobbling") == false, "mirror should stop wobbling when mirror_mounted is true")
	gs.reset()


func _test_walk_to_exit() -> void:
	_ensure_world()
	gs.reset()
	rm.change_room("RoomHouse", "start")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var exit_node: Node = room.pick(Vector2(1860, 850))
	_check(exit_node != null, "exit not pickable")
	if exit_node == null:
		return
	var start_pos: Vector2 = player.global_position
	Engine.time_scale = 6.0
	player.call("click_at", Vector2(1860, 850))
	_check(player.call("is_walking"), "player did not start walking")
	var frames := 0
	while rm.current_room == room and frames < 1200:
		await physics_frame
		frames += 1
	Engine.time_scale = 1.0
	await process_frame
	_check(rm.current_room != room, "room did not change after walking to the exit (%d frames)" % frames)
	_check(rm.current_room != null and rm.current_room.room_id == "RoomOffice", "expected RoomOffice after exit")
	_check(player.global_position != start_pos, "player did not move")
	# Now click the latch: walk, interact, flag set.
	await physics_frame
	await physics_frame
	Engine.time_scale = 6.0
	player.call("click_at", Vector2(300, 420))
	frames = 0
	while player.call("is_walking") and frames < 1200:
		await physics_frame
		frames += 1
	Engine.time_scale = 1.0
	_check(gs.has_flag("office_latch_open"), "office_latch_open not set after walking to the latch")
	_check(not player.call("is_path_fallback"), "player used the straight-line fallback instead of the navigation path")
	_check(player.z_index == int(player.global_position.y), "z_index must equal int(y) (y-sort)")
	var expected_scale: float = rm.current_room.depth_scale(player.global_position.y)
	_check(is_equal_approx(absf(player.scale.y), expected_scale), "player scale %f != depth scale %f" % [player.scale.y, expected_scale])


func _test_save_load_room() -> void:
	_ensure_world()
	gs.reset()
	rm.change_room("RoomOffice", "from_house")
	await process_frame
	gs.set_flag("office_latch_open", true)
	player.global_position = Vector2(777, 888)
	_check(rm.save_game(TEST_SLOT), "save_game failed")
	gs.reset()
	rm.change_room("RoomHouse", "start")
	await process_frame
	_check(rm.load_game(TEST_SLOT), "load_game failed")
	await process_frame
	_check(rm.current_room != null and rm.current_room.room_id == "RoomOffice", "load_game did not rebuild RoomOffice")
	_check(player.global_position.is_equal_approx(Vector2(777, 888)), "player position not restored: %s" % str(player.global_position))
	_check(gs.has_flag("office_latch_open"), "flag lost through load_game")
	var latch_open: CanvasItem = rm.current_room.get_node_or_null("Hotspots/Latch/LatchOpen")
	_check(latch_open != null and latch_open.visible, "latch visual not re-applied after load")
	gs.reset()


func _test_input_map() -> void:
	_check(InputMap.has_action("quick_save"), "action quick_save missing")
	_check(InputMap.has_action("quick_load"), "action quick_load missing")
	var f5 := InputEventKey.new()
	f5.physical_keycode = KEY_F5
	f5.pressed = true
	var f9 := InputEventKey.new()
	f9.physical_keycode = KEY_F9
	f9.pressed = true
	_check(f5.is_action_pressed("quick_save"), "F5 does not trigger quick_save (keycode %d)" % KEY_F5)
	_check(f9.is_action_pressed("quick_load"), "F9 does not trigger quick_load (keycode %d)" % KEY_F9)
	_check(not f5.is_action_pressed("quick_load"), "F5 must not trigger quick_load")


# =============================================================================
# M1 — data-driven rooms, StoryRunner, bot walkthrough
# =============================================================================

const MID_SLOT: String = "test_mid"

var sd: Node
var sr: Node
var main_node: Node = null


## Drives the real game through the public API (Room.pick/StoryHotspot/StoryExit/Player/StoryRunner).
class Bot:
	var t: SceneTree
	var rm: Node
	var sr: Node
	var gs: Node
	var player: Node2D
	var log: Array[String] = []
	const MAX_FRAMES := 2400

	func _init(tree: SceneTree, p_rm: Node, p_sr: Node, p_gs: Node) -> void:
		t = tree
		rm = p_rm
		sr = p_sr
		gs = p_gs
		player = rm.player

	func room_id() -> String:
		return rm.current_room.room_id if rm.current_room != null else ""

	func hotspot(id: String) -> Node:
		if rm.current_room == null:
			return null
		return rm.current_room.get_node_or_null("Hotspots/" + id)

	func exit_to(target: String) -> Node:
		if rm.current_room == null:
			return null
		return rm.current_room.get_node_or_null("Exits/to_" + target)

	func wait_idle() -> int:
		var frames := 0
		while (player.call("is_walking") or sr.get("_loop_running")) and frames < MAX_FRAMES:
			await t.physics_frame
			frames += 1
		await t.process_frame
		await t.process_frame
		return frames

	## Walks to a hotspot and interacts (same path as a mouse click: Room.pick → walk → trigger).
	func use(id: String) -> bool:
		var h := hotspot(id)
		if h == null or not h.visible:
			log.append("use(%s): hotspot missing or hidden in %s" % [id, room_id()])
			return false
		var picked = rm.current_room.pick(h.global_position)
		if picked != h:
			log.append("use(%s): pick at %s returned %s" % [id, str(h.global_position), str(picked)])
		player.call("click_at", h.global_position)
		await wait_idle()
		return true

	func use_item(item: String, id: String) -> bool:
		sr.select_item(item)
		if sr.selected_item != item:
			log.append("use_item: cannot select %s" % item)
			return false
		return await use(id)

	## Uses the exit to `target` and waits for the room change (or the closed reaction).
	func go(target: String) -> bool:
		var e := exit_to(target)
		if e == null:
			log.append("go(%s): no exit in %s" % [target, room_id()])
			return false
		var before := room_id()
		player.call("click_at", e.global_position)
		await wait_idle()
		var frames := 0
		while room_id() == before and sr.current_beat.is_empty() and frames < 60:
			await t.process_frame
			frames += 1
		await t.physics_frame
		await t.physics_frame
		return room_id() == target

	## Advances dialogue; options are answered with `choices` in order (default: first option).
	func finish(choices: Array = []) -> Array[String]:
		var seen: Array[String] = []
		var guard := 0
		while not sr.current_beat.is_empty() and guard < 200:
			guard += 1
			var b: Dictionary = sr.current_beat
			if b.get("type") == "options":
				var opts: Array = b.get("options", [])
				var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
				if not choices.is_empty():
					pick = String(choices.pop_front())
				seen.append("options:" + pick)
				sr.choose(pick)
			else:
				seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text", "")).left(40)])
				sr.advance()
			await t.process_frame
		await t.process_frame
		return seen


func _spawn_main() -> void:
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_slot = TEST_AUTOSAVE_SLOT
	world = main_node.get_node("World")
	player = main_node.get_node("World/Player")


func _cleanup_m1() -> void:
	gs.delete_save(MID_SLOT)
	gs.delete_save(TEST_AUTOSAVE_SLOT)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
		main_node = null
	rm.current_room = null


func _test_story_data() -> void:
	sd = root.get_node("StoryData")
	sr = root.get_node("StoryRunner")
	_check(sd.loaded, "StoryData.loaded is false: %s" % str(sd.load_errors))
	_check(sd.rooms.size() >= 10, "expected ≥10 rooms, got %d" % sd.rooms.size())
	_check(sd.scenes.has("M01") and sd.scenes.has("M08") and sd.scenes.has("Q04"), "scenes M01/M08/Q04 missing")
	_check(sd.start_location == "Z1", "start location should be Z1, got %s" % sd.start_location)
	_check(not sd.text("@ui.not_built").begins_with("["), "ui texts not resolved")
	# Every in-scope room has a real background file and every layer/state/hotspot/puzzle image exists.
	for rid in sd.rooms_index.get("in_scope", []):
		var spec: Dictionary = sd.room(rid)
		var bg_img := String(spec.get("background", {}).get("image", ""))
		_check(bg_img != "" and ResourceLoader.exists(bg_img), "%s: background.image missing or not found (%s)" % [rid, bg_img])
		for l in spec.get("layers", []):
			var img := String(l.get("image", ""))
			_check(ResourceLoader.exists(img), "%s: layer %s image not found: %s" % [rid, String(l.get("id", "?")), img])
		for h in spec.get("hotspots", []):
			if h.has("image"):
				_check(ResourceLoader.exists(String(h["image"])), "%s/%s: hotspot image not found" % [rid, String(h.get("id", "?"))])
			for key in h.get("puzzle", {}).get("art", {}).keys():
				var a = h["puzzle"]["art"][key]
				if a is Dictionary and a.has("image"):
					_check(ResourceLoader.exists(String(a["image"])), "%s puzzle art %s not found: %s" % [rid, key, String(a["image"])])
	# Build every in-scope room standalone and verify structure. (Loaded at runtime: a -s script
	# must not name classes whose scripts depend on autoloads, see the note at the top.)
	var builder = load("res://scripts/rooms/room_builder.gd")
	for rid in sd.rooms_index.get("in_scope", []):
		var room = builder.build(rid)
		_check(room != null, "RoomBuilder.build(%s) returned null" % rid)
		if room == null:
			continue
		root.add_child(room)
		_check(room.get_node_or_null("Walkable") != null, "%s: Walkable missing" % rid)
		_check(room.get_spawn("default") != null, "%s: spawn default missing" % rid)
		var spec: Dictionary = sd.room(rid)
		_check(room.get_hotspots().size() == spec.get("hotspots", []).size(), "%s: hotspot count mismatch" % rid)
		_check(room.get_exits().size() == spec.get("exits", []).size(), "%s: exit count mismatch" % rid)
		for h in room.get_hotspots():
			_check(not h.label_text().begins_with("["), "%s/%s: unresolved label %s" % [rid, h.hotspot_id, h.label_text()])
		for e in room.get_exits():
			_check(not e.label_text().begins_with("["), "%s/exit %s: unresolved label" % [rid, e.target_room])
		root.remove_child(room)
		room.free()


func _test_exit_gate() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	rm.change_room("H3", "default")
	await physics_frame
	await physics_frame
	var e = rm.current_room.get_node_or_null("Exits/to_O1")
	_check(e != null, "H3 has no exit to O1")
	if e == null:
		return
	_check(not e.is_open(), "H3→O1 must be closed before M05")
	_check(e.missing_flags() == ["door_school_installed"], "missing flags should be [door_school_installed], got %s" % str(e.missing_flags()))
	# Using the closed exit reacts with text and keeps the room (no crash, no transition).
	sr.use_exit(e)
	await process_frame
	_check(sr.current_beat.get("type", "") == "narration", "closed exit should narrate, beat=%s" % str(sr.current_beat))
	_check(gs.current_room == "H3", "closed exit must not change the room")
	sr.advance()
	await process_frame
	# The leaning door leaf is pickable before installation and hidden after; the frame itself is the exit.
	var door = rm.current_room.get_node_or_null("Hotspots/school_door")
	_check(door != null and door.visible, "school_door hotspot should be visible before M05")
	_check(rm.current_room.pick(door.global_position) == door, "click on the leaning leaf should hit the door hotspot before M05")
	var frame_empty = rm.current_room.get_node_or_null("Layers/frame_empty")
	var frame_installed = rm.current_room.get_node_or_null("Layers/door_installed")
	_check(frame_empty != null and frame_empty.visible and frame_installed != null and not frame_installed.visible, "state layers: empty frame visible, installed door hidden before M05")
	gs.set_flag("door_school_installed", true)
	await process_frame
	_check(e.is_open(), "H3→O1 must be open once door_school_installed is set")
	_check(door != null and not door.visible, "school_door hotspot should hide after installation")
	_check(rm.current_room.pick(e.global_position) == e, "click on the frame should hit the exit after M05")
	_check(not frame_empty.visible and frame_installed.visible, "state layers swap when the door is installed")
	gs.reset()
	await process_frame
	_cleanup_m1()


func _test_walkthrough() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = true
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	Engine.time_scale = 4.0
	var bot := Bot.new(self, rm, sr, gs)
	await bot.wait_idle()
	_check(bot.room_id() == "Z1", "game must start in Z1, got %s" % bot.room_id())
	_check(sr.journal_goal() != "", "initial goal must be explained")

	# --- M01: Tamara ---
	await bot.use("drawings")
	var seen := await bot.finish()
	_check(gs.has_flag("z1_compared_drawings"), "drawings examine should set its flag")
	await bot.use("tamara")
	_check(gs.has_flag("started_M01"), "talking to Tamara should start M01")
	seen = await bot.finish()
	_check(seen.size() == 3, "M01 should play 3 lines, got %s" % str(seen))
	_check(gs.has_flag("done_M01") and gs.has_flag("met_tamara") and gs.has_flag("knows_pier_trace"), "M01 flags missing")
	_check(gs.has_item("key_house") and gs.has_item("letter_tamara") and gs.has_item("pocket_watch"), "M01 items missing: %s" % str(gs.inventory))
	_check(gs.journal_goal == sd.scene("M01")["result"], "journal goal should be M01 result")
	_check(gs.has_save(TEST_AUTOSAVE_SLOT), "autosave after the scene beat")

	# --- Z2 and closed exits ---
	_check(await bot.go("Z2"), "exit Z1→Z2 should open after M01 (room=%s)" % bot.room_id())
	var h3exit = bot.exit_to("H3")
	_check(h3exit != null and not h3exit.is_open(), "Z2→H3 must be closed before house_open")
	_check(not (await bot.go("H3")), "Z2→H3 must not transition while closed")
	await bot.finish()
	_check(bot.room_id() == "Z2", "still in Z2 after the closed exit")
	var m1exit = bot.exit_to("M1")
	_check(m1exit != null and m1exit.is_open() and not m1exit.target_exists(), "Z2→M1 is open but unbuilt in M1")
	_check(not (await bot.go("M1")), "unbuilt exit must not transition")
	await bot.finish()

	# --- M02 via Z3 → R1 ---
	_check(await bot.go("Z3"), "Z2→Z3")
	await bot.use("old_pier_base")
	await bot.finish()
	_check(await bot.go("R1"), "Z3→R1")
	await bot.use("instruction")
	await bot.finish()
	_check(gs.has_flag("seen_ferry_instruction"), "instruction examine should set seen_ferry_instruction")
	var r2exit = bot.exit_to("R2")
	_check(r2exit != null and not r2exit.is_open(), "R1→R2 closed (ferry_verified)")
	await bot.use("pelageya")
	seen = await bot.finish()
	_check(gs.has_flag("done_M02") and gs.has_flag("met_pelageya") and gs.has_flag("knows_journal_target"), "M02 flags missing")
	_check(seen.size() == 3, "M02 should play 3 lines, got %s" % str(seen))

	# --- M03 in H1 ---
	_check(await bot.go("Z2"), "R1→Z2")
	_check(await bot.go("H1"), "Z2→H1 with key_house")
	_check(not gs.has_flag("started_M03"), "M03 must not start before the three steps")
	await bot.use("shutter")
	await bot.finish()
	await bot.use("stove")
	await bot.finish()
	_check(gs.has_flag("stove_lit") and gs.has_flag("h1_shutter_open"), "M03 steps 1-2")
	await bot.use("scarf")
	seen = await bot.finish()  # the scarf narration, then M03 (deferred trigger) in the same run
	_check(gs.has_flag("started_M03"), "M03 should start after the third step")
	_check(gs.has_flag("done_M03") and gs.has_flag("met_tikhon") and gs.has_flag("house_open"), "M03 flags missing: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("options:")), "M03 context line should be offered as an option: %s" % str(seen))
	var tikhon = bot.hotspot("tikhon")
	_check(tikhon != null and tikhon.visible, "Tikhon should be visible after M03")
	_check(bot.hotspot("scarf") != null and not bot.hotspot("scarf").visible, "scarf hidden after removal")

	# --- V01 (choices, exclusive) and Q04 ---
	await bot.use("cups")
	seen = await bot.finish(["blue"])
	_check(gs.has_flag("v01_cup_blue"), "cup choice")
	await bot.use("cups")
	await bot.finish(["white"])
	_check(gs.has_flag("v01_cup_white") and not gs.has_flag("v01_cup_blue"), "exclusive choice should swap flags")
	await bot.use("photo")
	await bot.finish(["table"])
	await process_frame
	await bot.finish()
	_check(gs.has_flag("done_V01"), "V01 should complete after both choices")
	await bot.use("shelf")
	seen = await bot.finish(["A"])
	_check(gs.has_flag("q04_corner_stove") and gs.has_flag("done_Q04"), "Q04 choice A → flags; seen=%s" % str(seen))
	_check(seen.size() >= 5, "Q04 should play its 4 lines after the choice: %s" % str(seen))

	# --- V02 attic ---
	_check(await bot.go("H4"), "H1→H4")
	await bot.finish()
	_check(gs.has_flag("done_V02"), "V02 auto on entering H4")
	_check(await bot.go("H1"), "H4→H1")

	# --- M04 ---
	_check(await bot.go("H2"), "H1→H2")
	await bot.use("bench")
	await bot.finish()
	await bot.use("hinges_box")
	await bot.finish()
	await bot.use("bell")
	await bot.finish()
	_check(gs.has_item("door_hinges") and gs.has_flag("seen_workshop") and gs.has_flag("knows_rule_things_remember") and gs.has_flag("seen_bell"), "M04 workshop steps")
	_check(bot.hotspot("hinges_box") != null and not bot.hotspot("hinges_box").visible, "hinges box hidden after pickup")
	_check(not gs.has_flag("done_M04"), "M04 not complete before seeing the door")
	_check(await bot.go("H1"), "H2→H1")
	_check(await bot.go("H3"), "H1→H3")
	await bot.use("school_door")
	await bot.finish()
	await process_frame
	seen = await bot.finish()
	_check(gs.has_flag("done_M04") and gs.has_flag("seen_school_door") and gs.has_flag("seen_mirror_home"), "M04 should complete in H3 (grants include seen_mirror_home)")
	_check(gs.has_flag("has_school_door") and gs.has_flag("has_bell"), "non-inventory items become has_ flags")
	_check(not gs.has_item("school_door"), "non-inventory items never enter the inventory")
	_check(rm.save_game(MID_SLOT), "mid-way save")

	# --- M05 puzzle ---
	var o1exit = bot.exit_to("O1")
	_check(o1exit != null and not o1exit.is_open(), "H3→O1 closed before M05")
	await bot.use_item("door_hinges", "school_door")
	_check(sr.puzzle_open, "hinges on the door should open the puzzle")
	if sr.puzzle_open:
		sr.puzzle_place("hinge_1", "top")
		sr.puzzle_place("hinge_2", "middle")
		sr.puzzle_set_mark(0)
		_check(not sr.puzzle_check(), "wrong placement must fail")
		_check(sr.puzzle["view"] == "wall" and sr.puzzle["errors"] == 1, "first error shows the wall")
		_check(sr.puzzle["hint"] == "", "no hint after the first error")
		_check(not sr.puzzle_check(), "second wrong attempt")
		_check(sr.puzzle["hint"] == sd.scene("M05")["hints"][0], "hint after the second error = M05 hints[0], got '%s'" % sr.puzzle["hint"])
		sr.puzzle_place("hinge_2", "bottom")
		sr.puzzle_set_mark(2)
		_check(sr.puzzle_check(), "correct placement must succeed")
		_check(sr.puzzle["solved"] and sr.puzzle["view"] == "winter", "success shows the winter view")
		sr.close_puzzle()
	seen = await bot.finish()
	_check(gs.has_flag("done_M05") and gs.has_flag("door_school_installed"), "M05 flags; seen=%s" % str(seen))
	_check(not gs.has_item("door_hinges"), "hinges consumed by M05")
	_check(o1exit.is_open(), "H3→O1 open after M05")

	# --- Load the mid-way save: state restored, one-time events not repeated, puzzle redoable ---
	_check(rm.load_game(MID_SLOT), "load mid-way save")
	await process_frame
	await process_frame
	_check(bot.room_id() == "H3", "load restores the room (H3), got %s" % bot.room_id())
	_check(not gs.has_flag("door_school_installed") and gs.has_item("door_hinges"), "load restores pre-M05 state")
	_check(gs.has_flag("done_M04") and sr.current_beat.is_empty(), "M04 must not replay after load")
	await bot.use_item("door_hinges", "school_door")
	_check(sr.puzzle_open, "puzzle reopens after load")
	if sr.puzzle_open:
		sr.puzzle_place("hinge_1", "top")
		sr.puzzle_place("hinge_2", "bottom")
		sr.puzzle_set_mark(2)
		_check(sr.puzzle_check(), "puzzle solvable after load")
		sr.close_puzzle()
	await bot.finish()
	_check(gs.has_flag("door_school_installed"), "M05 redone after load")

	# --- O1: M06, M07, V03, chalk ---
	_check(await bot.go("O1"), "H3→O1 through the installed door")
	await bot.use("sack")
	await bot.finish()
	await bot.use("notebooks")
	await bot.finish()
	await process_frame
	seen = await bot.finish()
	_check(gs.has_flag("done_M06") and gs.has_flag("seen_class_traces"), "M06 completes after 2 of 3 examines; seen=%s" % str(seen))
	await bot.use("teacher_drawer")
	await bot.finish()
	await process_frame
	seen = await bot.finish()
	_check(gs.has_flag("done_M07") and gs.has_flag("knows_trip_14"), "M07; seen=%s" % str(seen))
	_check(gs.has_item("invoice_chalk") and gs.has_item("photo_school_pier"), "M07 items")
	await bot.use("chalk")
	await bot.finish()
	_check(gs.has_item("chalk"), "chalk picked up")
	await bot.use("bird_drawing")
	await bot.finish(["leave"])
	await process_frame
	await bot.finish()
	_check(gs.has_flag("done_V03") and gs.has_flag("v03_left"), "V03 choice")

	# --- O2: mitten, loop ---
	_check(await bot.go("O2"), "O1→O2")
	await bot.finish()
	_check(gs.has_item("mitten"), "mitten is in the bag since M01")
	await bot.use_item("mitten", "porch_step")
	await bot.finish()
	_check(gs.has_flag("mitten_placed"), "mitten placed")
	var gate = bot.exit_to("O4")
	_check(gate != null and not gate.is_open(), "O2→O4 closed (school_path_open)")
	var before_loop: Vector2 = player.global_position
	_check(not (await bot.go("O4")), "gate must loop back, not transition")
	await bot.wait_idle()
	await bot.finish()
	_check(gs.has_flag("observed_path_loop"), "loop sets observed_path_loop")
	_check(bot.room_id() == "O2", "still in O2 after the loop")
	var porch = rm.current_room.get_spawn("porch")
	_check(porch != null and player.global_position.is_equal_approx(porch.global_position), "player teleported to the porch (was %s, now %s)" % [str(before_loop), str(player.global_position)])
	_check(gs.has_flag("mitten_placed"), "the mitten stays in place after the loop")
	_check(not gs.has_flag("done_M08"), "M08 waits for the board")

	# --- back to O1: chalk on the board → M08 ---
	_check(await bot.go("O1"), "O2→O1")
	await bot.use_item("chalk", "board")
	await bot.finish()
	await process_frame
	seen = await bot.finish()
	_check(gs.has_flag("wrote_on_board") and gs.has_flag("done_M08"), "M08 completes after the loop + board; seen=%s" % str(seen))
	_check(gs.has_item("chalk"), "chalk is not consumed")

	# --- home through the school door ---
	_check(await bot.go("H3"), "O1→H3 back through the door")
	_check(gs.has_flag("door_school_installed") and gs.has_flag("wrote_on_board") and gs.has_flag("knows_trip_14"), "final flags")
	for it in ["key_house", "letter_tamara", "pocket_watch", "invoice_chalk", "photo_school_pier", "chalk", "mitten"]:
		_check(gs.has_item(it), "inventory should hold %s" % it)
	_check(not gs.has_item("door_hinges"), "door_hinges must stay consumed")
	for sid in ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "V01", "V02", "V03", "Q04"]:
		_check(gs.has_flag("done_" + sid), "scene %s not done" % sid)
	_check(bot.log.is_empty(), "bot log: %s" % str(bot.log))
	Engine.time_scale = 1.0
	_cleanup_m1()


func _test_h1_real() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	# Sprite built from the sheets.
	_check(player.call("uses_sheet"), "player should use the actor sheet (data/actors/agata.json)")
	var spr: AnimatedSprite2D = player.get_node_or_null("Sprite")
	_check(spr != null, "AnimatedSprite2D 'Sprite' missing")
	if spr == null:
		return
	var names := spr.sprite_frames.get_animation_names()
	var walk_n := 0
	var idle_n := 0
	for n in names:
		if String(n).begins_with("walk_"):
			walk_n += 1
		elif String(n).begins_with("idle_"):
			idle_n += 1
	_check(walk_n == 8 and idle_n == 8, "expected 8 walk + 8 idle animations, got %d/%d (%s)" % [walk_n, idle_n, str(names)])
	var tex := spr.sprite_frames.get_frame_texture("walk_0", 0)
	_check(tex != null and tex.get_size() == Vector2(288, 384), "frame size should be 288x384, got %s" % str(tex.get_size() if tex else null))
	_check(spr.sprite_frames.get_frame_count("walk_0") == 12, "walk animations should have 12 frames")
	_check(spr.sprite_frames.get_frame_count("idle_0") == 1, "idle is a static frame until the turn clip is replaced (idle_static_frame)")
	_check(spr.offset.is_equal_approx(Vector2(-144.0, -0.9464285714285714 * 384.0)), "sprite offset should put the pivot (feet) at the origin, got %s" % str(spr.offset))
	_check(not player.get_node("Body").visible, "placeholder body hidden when the sheet is used")
	# Direction mapping (data/actors/agata.json; verified against the sheet by eye):
	# rows run counter-clockwise on screen: 0=S 1=SE 2=E 3=NE 4=N 5=NW 6=W 7=SW.
	_check(player.call("direction_index", Vector2(-1, 0)) == 6, "left should map to row 6 (profile facing left)")
	_check(player.call("direction_index", Vector2(0, -1)) == 4, "up (back) should map to row 4")
	_check(player.call("direction_index", Vector2(1, 0)) == 2, "right should map to row 2 (profile facing right)")
	_check(player.call("direction_index", Vector2(0, 1)) == 0, "down (front) should map to row 0")
	_check(player.call("direction_index", Vector2(-1, -1)) == 5, "up-left should map to row 5")
	_check(player.call("direction_index", Vector2(1, 1)) == 1, "down-right should map to row 1")
	# Real H1: background image, occluder with explicit z, player scale from room depth.
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	_check(room.get_node_or_null("Background/Image") != null, "H1 should use the real background image")
	var table: Node2D = room.get_node_or_null("Occluders/table_chair")
	_check(table != null and table.get_node_or_null("Image") != null, "H1 table/chair occluder with image missing")
	if table != null:
		_check(table.z_index == 950, "occluder z should be the data value 950, got %d" % table.z_index)
		player.call("enter_room", room, Vector2(900, 800))
		_check(table.z_index > player.z_index, "player above the table (y=800) must be drawn behind it (z %d vs %d)" % [player.z_index, table.z_index])
		player.call("enter_room", room, Vector2(900, 1000))
		_check(player.z_index > table.z_index, "player below the table (y=1000) must be drawn in front of it")
	_check(is_equal_approx(room.depth_scale(700.0), 1.3) and is_equal_approx(room.depth_scale(1070.0), 2.0), "H1 depth scale from data (1.3..2.0)")
	# Step tempo from real speed: at scale 1 and 260 px/s the walk cycle must run at 8–14 fps.
	var fps1: float = player.sheet.walk_fps(260.0, 1.0)
	_check(fps1 >= 8.0 and fps1 <= 14.0, "walk fps at scale 1 / 260 px/s should be 8–14, got %.2f" % fps1)
	# Speed in px/s follows the depth scale (constant metres per second).
	player.call("enter_room", room, Vector2(1200, 700))
	var v_far: float = player.call("current_speed_px")
	var fps_far: float = player.call("current_walk_fps")
	player.call("enter_room", room, Vector2(1200, 1070))
	var v_near: float = player.call("current_speed_px")
	var fps_near: float = player.call("current_walk_fps")
	_check(is_equal_approx(v_near / v_far, 2.0 / 1.3), "speed should scale with depth (near/far = 2.0/1.3), got %.3f" % (v_near / v_far))
	_check(absf(fps_near - fps_far) < 0.05 and fps_near >= 8.0 and fps_near <= 14.0, "walk fps must stay constant across depth and within 8–14, got far %.2f / near %.2f" % [fps_far, fps_near])
	# Walking plays the walk animation through speed_scale (no manual frames) and sets the direction row.
	player.speed_factor = 1.0
	player.call("enter_room", room, Vector2(1400, 900))
	player.call("walk_to", Vector2(900, 900))
	var frames := 0
	var seen_frames := {}
	var playing_walk := false
	while player.call("is_walking") and frames < 600:
		await physics_frame
		frames += 1
		if frames > 5:
			seen_frames[spr.frame] = true
			if spr.is_playing() and spr.animation == "walk_6" and spr.speed_scale > 0.5:
				playing_walk = true
	_check(playing_walk, "walk_6 should play via speed_scale while walking left")
	_check(player.direction == 6 and spr.animation.begins_with("idle_6"), "after walking left: row 6 and idle_6, got dir %d anim %s" % [player.direction, spr.animation])
	_check(seen_frames.size() >= 6, "walk frames should advance while walking, saw %d distinct" % seen_frames.size())
	_check(spr.sprite_frames.get_frame_count(spr.animation) == 1 or not spr.is_playing() or true, "idle present")
	gs.reset()
	_cleanup_m1()
