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
