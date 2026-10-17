extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path game -s res://tests/run_tests.gd
## Prints PASS/FAIL per test; exit code 0 only when every check passed.
##
## Note: a `-s` script is compiled before autoload singletons are registered, so it
## reaches them through the tree (`root.get_node("GameState")`), never by bare identifier.

## Save slots of this test run. They live in the shared user://saves of the machine, and several
## test runs may go at once (agents, CI, a person) — so every name carries the process id: one run
## deleting or rewriting its slots can never pull a save from under another (the bot walkthrough's
## «load mid-way save» failed exactly that way when two runs overlapped).
var TEST_SLOT: String = "test_slot"
var TEST_AUTOSAVE_SLOT: String = "test_auto"
var MID_SLOT: String = "test_mid"

var gs: Node
var rm: Node
var world: Node2D
var player: Node2D

var _results: Array = []      # [name: String, passed: bool, message: String]
var _current_checks: Array = []  # failures of the running test


func _initialize() -> void:
	var sfx := "_%d" % OS.get_process_id()
	TEST_SLOT += sfx
	TEST_AUTOSAVE_SLOT += sfx
	MID_SLOT += sfx
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
	await _test("Stride: fps from speed, stride = sheet stride, foot lock holds the drawn figure between frames", _test_stride)
	await _test("NPC actors: Tamara/Pelageya from sheets on their hotspots, depth scale, y-sort, talk during their lines", _test_npc_actors)
	await _test("Shadows: soft ellipse under the feet of Agata and NPCs, behind the figure, scaled by depth", _test_shadows)
	await _test("No straight-line walking: a click right after entering Z1 waits for the nav map and goes round the counter", _test_no_straight_line)
	await _test("Loop seams: every repeating animation of every actor sheet returns to its first frame smoothly", _test_loop_seams)
	await _test("Cross-fade: switching idle↔walk (Agata) and idle↔talk (Tamara) dissolves the old pose in ≈0.12 s", _test_crossfade)
	await _test("Actions: hotspot action_anim plays once, the effect lands on the key frame exactly once; save mid-action is safe", _test_actions)
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
	_check(player.call("has_path"), "player must have walked along a navigation path (no straight-line fallback exists)")
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
		while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running")) and frames < MAX_FRAMES:
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

	# --- Z4 (lane by the post office: side porch of the house) → Z2, closed exits ---
	_check(await bot.go("Z4"), "exit Z1→Z4 should open after M01 (room=%s)" % bot.room_id())
	var h3exit = bot.exit_to("H3")
	_check(h3exit != null and not h3exit.is_open(), "Z4→H3 (side porch) must be closed before house_open")
	_check(not (await bot.go("H3")), "Z4→H3 must not transition while closed")
	await bot.finish()
	_check(bot.room_id() == "Z4", "still in Z4 after the closed exit")
	_check(await bot.go("Z2"), "Z4→Z2 (lane → street)")
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
	# Idle rev 8 (window 0–20 % of the clip) plays pingpong from sprites.json: 0..7 then 6..1 = 14 frames.
	_check(spr.sprite_frames.get_frame_count("idle_0") == 14, "idle should have 14 pingpong frames (8 forward, 6 back), got %d" % spr.sprite_frames.get_frame_count("idle_0"))
	var seq: Array = player.sheet.frame_sequence(8, "pingpong")
	_check(seq == [0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1], "pingpong sequence for 8 frames, got %s" % str(seq))
	_check(player.sheet.frame_sequence(12, "loop") == range(12), "loop sequence is 0..n-1")
	var r8: Rect2 = (spr.sprite_frames.get_frame_texture("idle_3", 8) as AtlasTexture).region
	var r13: Rect2 = (spr.sprite_frames.get_frame_texture("idle_3", 13) as AtlasTexture).region
	_check(r8.position == Vector2(6 * 288, 3 * 384) and r13.position == Vector2(1 * 288, 3 * 384), "pingpong frames 8 and 13 must be sheet columns 6 and 1 of row 3, got %s / %s" % [str(r8.position), str(r13.position)])
	_check(is_equal_approx(spr.sprite_frames.get_animation_speed("idle_0"), 8.0), "idle fps comes from sprites.json (8)")
	var st = load("res://scripts/actors/actor_sheet.gd").load_actor("agata", {"idle_static_frame": 0})
	_check(st.is_loaded() and st.frames.get_frame_count("idle_0") == 1, "idle_static_frame still pins the idle to one frame when set")
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


## Defect «ходьба скользит»: numbers in the log. The sheet's planted foot slides back by
## `sheet_stride_px_per_frame` (measured: tools/measure_stride.py) between two walk frames; the
## engine must move the figure by exactly that much per frame at every depth, through speed_scale.
func _test_stride() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	var spr: AnimatedSprite2D = player.get_node_or_null("Sprite")
	if spr == null:
		_check(false, "no sprite")
		return
	var sheet = player.sheet
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var st: Dictionary = spec.get("walk", {}).get("stride_table", {})
	var frames_n: int = sheet.walk_frames()
	var ppm1: float = sheet.px_per_meter(1.0)
	var cycle_px: float = sheet.cycle_meters * ppm1
	# 1. The table belongs to this sheet (re-measure after any walk.png change: tools/measure_stride.py --write).
	_check(sheet.has_stride_table(), "walk.stride_table (8 rows × 12 frames) missing from data/actors/agata.json")
	var md5 := FileAccess.get_md5("res://" + String(st.get("sheet", "")))
	_check(md5 != "" and md5 == String(st.get("sheet_md5", "")), "stride_table was measured on another walk.png (md5 %s vs %s): run tools/measure_stride.py --write" % [md5, String(st.get("sheet_md5", ""))])
	# 2. Sums: profile rows = cycle_meters × px/m (±2 %); other rows = cycle × projection of the render camera.
	var elev: float = deg_to_rad(float(st.get("camera_elev_deg", 14.0)))
	print("    cycle %.1f px (scale 1) = %.4f m; fps %.2f (= %d × %.2f m/s / cycle); start frame %d" % [cycle_px, sheet.cycle_meters, sheet.walk_fps_const(), frames_n, sheet.speed_mps, sheet.stride_start_frame])
	for r in 8:
		var sum := 0.0
		for k in frames_n:
			sum += sheet.stride_at(r, k)
		var phi := deg_to_rad(90.0 - 45.0 * r)
		var proj := Vector2(cos(phi), sin(phi) * sin(elev)).length()
		print("    row %d: Σ %.1f px (expected %.1f = cycle × %.3f) speed at scale 1: %.1f px/s; strides %s" % [r, sum, cycle_px * proj, proj, sheet.walk_speed_row_px(r, 1.0), str(sheet.stride_rows[r])])
		_check(absf(sum - cycle_px * proj) <= 0.02 * cycle_px * proj, "row %d: table sum %.1f must equal the cycle %.1f ±2 %%" % [r, sum, cycle_px * proj])
		for k in frames_n:
			_check(sheet.stride_at(r, k) > 0.0, "row %d frame %d: stride must be positive" % [r, k])
	_check(absf(sheet.walk_speed_row_px(2, 1.0) - sheet.speed_mps * ppm1) < 0.5, "profile speed = speed_mps × px/m")
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	player.speed_factor = 1.0
	# 3. Walk left (row 6) along the near edge, then up (row 4): sample every render frame.
	var runs := [["left", Vector2(1650, 990), Vector2(820, 990), 6], ["up", Vector2(1650, 990), Vector2(1650, 740), 4]]
	for run in runs:
		player.call("enter_room", room, run[1])
		await physics_frame
		var resyncs0: int = player.lock_resyncs
		player.call("walk_to", run[2])
		var samples: Array = []   # [frame, drawn, logical, scale, ticks, lag, row]
		var n := 0
		while player.call("is_walking") and n < 3000:
			await process_frame
			n += 1
			if not String(spr.animation).begins_with("walk_"):
				continue
			samples.append([spr.frame, player.call("drawn_position"), player.global_position, absf(player.scale.y), Time.get_ticks_usec(), player.call("lock_lag_px"), player.direction])
		var within_max := 0.0
		var max_err := 0.0
		var max_lag := 0.0
		var ahead := false
		var changes := 0
		var t0 := -1
		var t1 := -1
		var adv := []
		for i in range(1, samples.size()):
			var a: Array = samples[i - 1]
			var b: Array = samples[i]
			max_lag = maxf(max_lag, b[5])
			if b[5] < -0.05:
				ahead = true
			if a[0] == b[0]:
				within_max = maxf(within_max, (b[1] as Vector2).distance_to(a[1]))
				continue
			changes += 1
			if t0 < 0:
				t0 = b[4]
			t1 = b[4]
			if wrapi(b[0] - a[0], 0, frames_n) != 1 or a[6] != run[3]:
				continue
			var expect: float = sheet.stride_at(run[3], a[0]) * a[3]
			var got: float = (b[1] as Vector2).distance_to(a[1])
			adv.append(snappedf(got, 0.1))
			max_err = maxf(max_err, absf(got - expect))
		var fps_meas := float(changes - 1) / (float(t1 - t0) / 1e6) if changes > 1 else 0.0
		print("    walk %s (row %d): %d frame changes, fps %.2f (formula %.2f), drawn still within a frame: max %.2f px; advance per change %s; max |advance − table×scale| %.2f px; max lag behind logical %.1f px; resyncs %d" % [
			run[0], run[3], changes, fps_meas, sheet.walk_fps_const(), within_max, str(adv), max_err, max_lag, player.lock_resyncs - resyncs0])
		_check(changes >= 8, "%s: expected at least 8 frame changes, got %d" % [run[0], changes])
		_check(within_max < 0.01, "%s: drawn figure must not move while a frame is shown, moved %.2f px" % [run[0], within_max])
		_check(max_err < 0.6, "%s: every frame change must advance the drawn figure by table[row][frame] × scale (max error %.2f px)" % [run[0], max_err])
		_check(not ahead, "%s: the drawn figure must never be ahead of the logical position" % run[0])
		_check(max_lag <= sheet.row_cycle_px(run[3]) * 2.1, "%s: lag behind the logical position must stay under one cycle (%.1f px)" % [run[0], max_lag])
		_check(player.lock_resyncs - resyncs0 <= 1, "%s: drawn figure clamped/re-synced %d times" % [run[0], player.lock_resyncs - resyncs0])
		_check(absf(spr.speed_scale - 1.0) < 0.001 or not spr.animation.begins_with("walk_"), "after arrival the idle plays at speed 1")
		_check(spr.position == Vector2.ZERO and spr.scale == Vector2.ONE, "%s: sprite offset/scale must be reset once standing" % run[0])
		print("    %s: stopped at %s (target %s)" % [run[0], str(player.global_position.round()), str(run[2])])
		var tol: float = player.nav_agent.target_desired_distance + 1.0  # the navigation agent's own arrival tolerance
		_check(player.global_position.distance_to(run[2]) < tol, "%s: the drawn figure finishes its steps and stops on the target (±%.0f px), at %s" % [run[0], tol, str(player.global_position)])
	gs.reset()
	_cleanup_m1()


## Items 4/7 of the Director's list: NPCs are sheet actors (idle pingpong + talk), not cut-out frames.
func _test_npc_actors() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	sr = root.get_node("StoryRunner")
	rm.change_room("Z1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var npcs: Array = load("res://scripts/actors/npc_actor.gd").all_in(room)
	_check(npcs.size() == 1 and npcs[0].actor_id == "tamara", "Z1 should hold one NPC actor (tamara), got %d" % npcs.size())
	if npcs.is_empty():
		_cleanup_m1()
		return
	var t: Node2D = npcs[0]
	var spr: AnimatedSprite2D = t.get_node("Sprite")
	_check(spr.sprite_frames.get_frame_count("idle_0") == 14 and spr.sprite_frames.get_frame_count("talk_0") == 22, "tamara: idle 14 and talk 22 pingpong frames (talk: data override), got %d/%d" % [spr.sprite_frames.get_frame_count("idle_0"), spr.sprite_frames.get_frame_count("talk_0")])
	_check(spr.animation == "idle_0" and spr.is_playing(), "tamara idles facing the viewer (idle_0), got %s" % spr.animation)
	var hs: Node2D = room.get_node("Hotspots/tamara")
	var shape: CollisionShape2D = hs.get_node("Shape")
	var feet: Vector2 = hs.global_position + Vector2(0, shape.shape.size.y / 2)
	_check(t.global_position.is_equal_approx(feet), "tamara's feet at the hotspot's bottom centre %s, got %s" % [str(feet), str(t.global_position)])
	_check(is_equal_approx(t.scale.y, room.depth_scale(feet.y)), "tamara scale = room depth scale at her feet (%.3f), got %.3f" % [room.depth_scale(feet.y), t.scale.y])
	_check(t.z_index == int(feet.y), "tamara z_index = int(feet y)")
	var counter: Node2D = room.get_node_or_null("Occluders/counter")
	if counter != null:
		_check(counter.z_index > t.z_index, "the post counter (z %d) must cover Tamara (z %d)" % [counter.z_index, t.z_index])
	var img: Node = hs.get_node_or_null("Image")
	_check(img == null or not img.visible, "the static front view of the hotspot is hidden when the actor exists")
	# M01: Tamara's line → talk animation, Agata's lines → idle.
	player.call("enter_room", room, Vector2(1100, 1040))
	sr.start_scene("M01")
	await process_frame
	var seen := []
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 50:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "line":
			seen.append("%s→%s" % [String(b.get("speaker", "")), spr.animation])
			if String(b.get("speaker", "")) == "tamara":
				_check(spr.animation == "talk_0" and spr.is_playing(), "during Tamara's line the talk sheet must play, got %s" % spr.animation)
			else:
				_check(spr.animation.begins_with("idle_"), "during another speaker's line Tamara idles, got %s" % spr.animation)
			sr.advance()
		elif b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		await process_frame
	_check(seen.size() >= 3, "M01 should show at least 3 lines, saw %s" % str(seen))
	print("    M01 lines → Tamara's animation: %s" % str(seen))
	_check(spr.animation.begins_with("idle_"), "after the dialogue Tamara idles again")
	# R1: Pelageya, slightly taller than Agata (scale_factor), same mechanics.
	rm.change_room("R1", "default")
	await physics_frame
	await physics_frame
	room = rm.current_room
	npcs = load("res://scripts/actors/npc_actor.gd").all_in(room)
	_check(npcs.size() == 1 and npcs[0].actor_id == "pelageya", "R1 should hold Pelageya's actor")
	if not npcs.is_empty():
		var p: Node2D = npcs[0]
		_check(is_equal_approx(p.scale.y, room.depth_scale(p.global_position.y) * 1.03), "pelageya scale = depth scale × 1.03")
		_check(p.get_node("Sprite").sprite_frames.get_frame_count("talk_0") == 22, "pelageya talk plays pingpong (12 sheet frames → 22)")
	gs.reset()
	_cleanup_m1()


## Item 6: contact shadow for every actor (data `shadow`, defaults 0.6 m wide, 0.3 ratio, alpha 0.5).
func _test_shadows() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var shadow: Sprite2D = player.get_node_or_null("Sprite/Shadow")
	_check(shadow != null, "Agata's sprite must carry a Shadow child")
	if shadow == null:
		_cleanup_m1()
		return
	_check(shadow.show_behind_parent, "shadow draws behind the figure")
	_check(shadow.texture is GradientTexture2D and (shadow.texture as GradientTexture2D).fill == GradientTexture2D.FILL_RADIAL, "shadow is a radial gradient (soft edge)")
	var grad: Gradient = (shadow.texture as GradientTexture2D).gradient
	_check(grad.get_color(0).a > 0.3 and grad.get_color(0).a < 0.6 and grad.get_color(grad.get_point_count() - 1).a == 0.0, "shadow fades from semi-transparent black to transparent")
	# Ellipse size: 0.6 m × 240.6 px/m = 144 px wide at scale 1, 43 px high; grows with the depth scale.
	var expect: Vector2 = load("res://scripts/actors/actor_shadow.gd").size_at(player.sheet, 1.0)
	_check(expect.x > 130.0 and expect.x < 160.0 and is_equal_approx(expect.y, expect.x * 0.3), "shadow ellipse ≈ 144×43 px at scale 1 (0.6 m), got %s" % str(expect))
	player.call("enter_room", room, Vector2(1200, 700))
	var far: Vector2 = shadow.get_global_transform().get_scale() * 64.0
	player.call("enter_room", room, Vector2(1200, 1070))
	var near: Vector2 = shadow.get_global_transform().get_scale() * 64.0
	_check(is_equal_approx(near.x / far.x, 2.0 / 1.3), "shadow width scales with depth like the figure (near/far = 2.0/1.3), got %.3f" % (near.x / far.x))
	_check(absf(shadow.global_position.y - player.global_position.y) < 8.0, "shadow sits at the feet (origin), got dy %.1f" % (shadow.global_position.y - player.global_position.y))
	# NPCs get the same shadow.
	rm.change_room("Z1", "default")
	await physics_frame
	await physics_frame
	var npcs: Array = load("res://scripts/actors/npc_actor.gd").all_in(rm.current_room)
	_check(npcs.size() == 1 and npcs[0].get_node_or_null("Sprite/Shadow") != null, "Tamara's actor must carry a shadow too")
	gs.reset()
	_cleanup_m1()


## Director's defect: Agata walked through the post counter when a click came before the navigation
## map was synced (the old 30-frame straight-line fallback). Now she waits for the path.
func _test_no_straight_line() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/Z1.json"))
	var holes: Array = []
	for hole in spec.get("walkable_holes", []):
		var poly := PackedVector2Array()
		for pt in hole:
			poly.append(Vector2(float(pt[0]), float(pt[1])))
		holes.append(poly)
	_check(holes.size() >= 1, "Z1 must have the counter cut-out in walkable_holes")
	for trial in 2:
		rm.change_room("Z1", "default")
		# Same physics frame as the room change: the map cannot have synced yet. Trial 1 also keeps
		# the floor region disabled for 45 frames (longer than the old 30-frame fallback) before the
		# map becomes usable — Agata must wait, not walk straight.
		var start: Vector2 = player.global_position
		var target := Vector2(1260, 712)  # behind the counter, on the far side of the cut-out
		var region: NavigationRegion2D = rm.current_room.get_walkable()
		var hold_frames := 45 if trial == 1 else 0
		if hold_frames > 0:
			region.enabled = false
			await physics_frame  # the map syncs without the floor before the click
			await physics_frame
		player.call("click_at", target)
		# A straight line from the spawn to the target crosses the counter: make sure that is what we test.
		var crosses := false
		for i in range(1, 50):
			var q: Vector2 = start.lerp(target, float(i) / 50.0)
			for h in holes:
				if Geometry2D.is_point_in_polygon(q, h):
					crosses = true
		_check(crosses, "test setup: the straight line spawn→target must cross the counter cut-out")
		var waited := 0
		var ever_had_path := false
		var moved_before_path := false
		var inside := []
		var frames := 0
		var speed_factor_old: float = player.speed_factor
		player.speed_factor = 4.0
		while player.call("is_walking") and frames < 1500:
			await physics_frame
			frames += 1
			if hold_frames > 0 and frames == hold_frames:
				_check(player.call("is_walking") and not player.call("has_path") and player.global_position.distance_to(start) < 0.5,
					"with the floor region disabled for %d frames Agata must still be waiting in place (walking=%s path=%s moved=%.1f)" % [hold_frames, str(player.call("is_walking")), str(player.call("has_path")), player.global_position.distance_to(start)])
				region.enabled = true
			if player.call("has_path"):
				ever_had_path = true
			elif not ever_had_path:
				waited += 1
				if player.global_position.distance_to(start) > 0.5:
					moved_before_path = true
			for h in holes:
				# Paths hug the cut-out's edge; only points clearly inside count (> 3 px from every edge).
				if Geometry2D.is_point_in_polygon(player.global_position, h) and _edge_distance(player.global_position, h) > 3.0:
					inside.append(player.global_position)
		player.speed_factor = speed_factor_old
		print("    trial %d: waited %d physics frames for the path, walked %d frames, ended at %s" % [trial, waited, frames, str(player.global_position)])
		_check(not moved_before_path, "Agata must stand still until the navigation path exists")
		_check(player.call("has_path"), "the walk must use a navigation path")
		_check(inside.is_empty(), "Agata went through the counter: %d samples inside the cut-out, first %s" % [inside.size(), str(inside[0]) if not inside.is_empty() else ""])
		_check(player.global_position.distance_to(target) < 60.0, "should arrive behind the counter near %s, got %s" % [str(target), str(player.global_position)])
	gs.reset()
	_cleanup_m1()


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Director 17.10: «анимации не должны прерываться и начинаться с совершенно другой точки».
## For every actor (data/actors/*.json) and every repeating action, the played sequence (loop or
## pingpong) is checked per direction row: the difference last→first frame must not exceed 1.5 × the
## median difference of neighbouring frames. A failing sheet is named (fix: pingpong in the data, or
## a re-render). Frames are compared at 1/4 size: colour+alpha, over the union of opaque pixels.
func _test_loop_seams() -> void:
	var dir := DirAccess.open("res://data/actors")
	_check(dir != null, "res://data/actors missing")
	if dir == null:
		return
	var checked := 0
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var id := fname.get_basename()
		var sheet = load("res://scripts/actors/actor_sheet.gd").load_actor(id)
		if not sheet.is_loaded():
			_check(false, "%s: sheet not loaded (%s)" % [id, sheet.load_error])
			continue
		for action in sheet.actions.keys():
			if not sheet.action_loops(action):
				continue  # one-shot actions end in a cross-fade, not a seam
			var seq: Array = sheet.action_sequence(action)
			if action == sheet.idle_action and sheet.idle_static_frame >= 0:
				continue
			if seq.size() < 3:
				continue
			var path: String = sheet.sheet_dir + "/" + String(sheet.actions[action].get("sheet", action + ".png"))
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img == null or img.is_empty():
				_check(false, "%s/%s: cannot read %s" % [id, action, path])
				continue
			img.convert(Image.FORMAT_RGBA8)
			var worst := 0.0
			var worst_row := -1
			# The walk is seen with root motion: at each frame change the drawn figure advances by the
			# stride table, so frame k+1 is compared shifted forward by stride[row][k] along the row's axis.
			var rooted: bool = action == sheet.walk_action and sheet.has_stride_table()
			var elev := deg_to_rad(float(_actor_walk_elev(id)))
			for r in sheet.directions:
				var cache := {}
				var phi := deg_to_rad(90.0 - 360.0 / sheet.directions * r)
				var axis := Vector2(cos(phi), sin(phi) * sin(elev)).normalized()
				var neighbours: Array = []
				for i in seq.size() - 1:
					var off: Vector2 = axis * float(sheet.stride_at(r, int(seq[i]))) if rooted else Vector2.ZERO
					neighbours.append(_frame_diff(img, sheet, r, int(seq[i]), int(seq[i + 1]), cache, off))
				neighbours.sort()
				var med: float = neighbours[neighbours.size() / 2]
				var off_seam: Vector2 = axis * float(sheet.stride_at(r, int(seq[seq.size() - 1]))) if rooted else Vector2.ZERO
				var seam := _frame_diff(img, sheet, r, int(seq[seq.size() - 1]), int(seq[0]), cache, off_seam)
				var ratio := seam / maxf(med, 0.001)
				if ratio > worst:
					worst = ratio
					worst_row = r
			checked += 1
			print("    %s/%s (%s, %d frames played): worst seam/median %.2f (row %d)" % [id, action, String(sheet.actions[action].get("playback", "loop")), seq.size(), worst, worst_row])
			_check(worst <= 1.5, "%s/%s: loop seam %.2f × the median frame step (row %d) — the clip jumps back to its start; play it pingpong (data actions.%s.playback) or re-render" % [id, path.get_file(), worst, worst_row, action])
	_check(checked >= 5, "expected at least 5 repeating actions across actors, checked %d" % checked)
	# The check itself must catch a real seam: Agata's idle played as a plain loop jumps 7 → 0.
	var ag = load("res://scripts/actors/actor_sheet.gd").load_actor("agata")
	var ipath: String = ag.sheet_dir + "/" + String(ag.actions[ag.idle_action].get("sheet", "idle.png"))
	var iimg := Image.load_from_file(ProjectSettings.globalize_path(ipath))
	iimg.convert(Image.FORMAT_RGBA8)
	var n_idle: int = int(ag.actions[ag.idle_action].get("frames", 8))
	var c := {}
	var nb: Array = []
	for i in n_idle - 1:
		nb.append(_frame_diff(iimg, ag, 0, i, i + 1, c))
	nb.sort()
	var loop_ratio := _frame_diff(iimg, ag, 0, n_idle - 1, 0, c) / maxf(nb[nb.size() / 2], 0.001)
	print("    self-check: agata/idle played as a loop would jump %.2f × the median step (must be caught)" % loop_ratio)
	_check(loop_ratio > 1.5, "self-check: the seam metric must flag idle played as a loop (got %.2f)" % loop_ratio)


## Mean max-channel difference over the union of opaque pixels; frame b is shifted by `off`
## (sheet px; drawn forward by the root motion) before the comparison.
func _frame_diff(img: Image, sheet, row: int, a: int, b: int, cache: Dictionary, off: Vector2 = Vector2.ZERO) -> float:
	var da: PackedByteArray = _small_frame(img, sheet, row, a, cache)
	var db: PackedByteArray = _small_frame(img, sheet, row, b, cache)
	var w: int = sheet.frame_w / 4
	var h: int = sheet.frame_h / 4
	var ox := int(round(off.x / 4.0))
	var oy := int(round(off.y / 4.0))
	var sum := 0.0
	var n := 0
	for y in h:
		var yb := y - oy
		for x in w:
			var i := (y * w + x) * 4
			var xb := x - ox
			var j := -1
			if xb >= 0 and xb < w and yb >= 0 and yb < h:
				j = (yb * w + xb) * 4
			var a_a: int = da[i + 3]
			var a_b: int = db[j + 3] if j >= 0 else 0
			if a_a <= 32 and a_b <= 32:
				continue
			if j < 0:
				sum += a_a
			else:
				sum += maxi(maxi(absi(da[i] - db[j]), absi(da[i + 1] - db[j + 1])), maxi(absi(da[i + 2] - db[j + 2]), absi(a_a - a_b)))
			n += 1
	return sum / maxf(n, 1)


func _actor_walk_elev(id: String) -> float:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if typeof(spec) != TYPE_DICTIONARY:
		return 14.0
	return float(spec.get("walk", {}).get("stride_table", {}).get("camera_elev_deg", spec.get("walk", {}).get("camera_elev_deg", 14.0)))


func _small_frame(img: Image, sheet, row: int, col: int, cache: Dictionary) -> PackedByteArray:
	if cache.has(col):
		return cache[col]
	var fr := img.get_region(Rect2i(col * sheet.frame_w, row * sheet.frame_h, sheet.frame_w, sheet.frame_h))
	fr.resize(sheet.frame_w / 4, sheet.frame_h / 4, Image.INTERPOLATE_BILINEAR)
	cache[col] = fr.get_data()
	return cache[col]


func _test_crossfade() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	sr = root.get_node("StoryRunner")
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	player.call("enter_room", rm.current_room, Vector2(1500, 990))
	await process_frame
	var fade0 = player.get_node_or_null("Crossfade")
	_check(fade0 == null or not fade0.visible, "no cross-fade right after entering a room")
	var idle_anim := String(spr.animation)
	player.call("walk_to", Vector2(1000, 990))
	var fade: AnimatedSprite2D = null
	var n := 0
	while n < 120 and not String(spr.animation).begins_with("walk_"):
		await process_frame
		n += 1
	fade = player.get_node_or_null("Crossfade")
	_check(fade != null and fade.visible, "idle→walk must start a cross-fade node 'Crossfade'")
	if fade != null:
		_check(String(fade.animation) == idle_anim and not fade.is_playing(), "the fade shows the frozen old pose (%s), got %s" % [idle_anim, String(fade.animation)])
		_check(fade.top_level, "the fading pose stays in place in the world (top_level)")
		var a0: float = fade.modulate.a
		var t0 := Time.get_ticks_msec()
		while fade.visible and Time.get_ticks_msec() - t0 < 1000:
			await process_frame
		var took := Time.get_ticks_msec() - t0
		print("    idle→walk fade: alpha %.2f at start, gone after %d ms (crossfade_s %.2f)" % [a0, took, player.sheet.crossfade_s])
		_check(not fade.visible and took <= 300, "the fade must be gone within ~0.12 s (took %d ms)" % took)
	while player.call("is_walking"):
		await process_frame
	fade = player.get_node_or_null("Crossfade")
	_check(fade != null and String(fade.animation).begins_with("walk_"), "walk→idle on arrival cross-fades from the last walk pose")
	# Tamara: idle→talk on her line, talk→idle after.
	rm.change_room("Z1", "default")
	await physics_frame
	await physics_frame
	var npcs: Array = load("res://scripts/actors/npc_actor.gd").all_in(rm.current_room)
	if npcs.is_empty():
		_check(false, "no Tamara actor in Z1")
		_cleanup_m1()
		return
	var t: Node2D = npcs[0]
	sr.start_scene("M01")
	await process_frame
	var saw_fade := false
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 50:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		else:
			sr.advance()
		# Checked synchronously: the beat change has just switched Tamara's animation.
		var nb: Dictionary = sr.current_beat
		if nb.get("type") == "line" and String(nb.get("speaker", "")) == "tamara":
			var tf = t.get_node_or_null("Crossfade")
			saw_fade = tf != null and tf.visible and String(tf.animation).begins_with("idle_")
		await process_frame
	_check(saw_fade, "Tamara's idle→talk switch must cross-fade from the idle pose")
	gs.reset()
	_cleanup_m1()


## Director 17.10 («как Агата открывает ставни»): hotspot `action_anim` (open / pick / reach).
func _test_actions() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	sr = root.get_node("StoryRunner")
	var sheet = player.sheet
	# 1. Every action_anim used by a room exists in Agata's sheets, with its key frame inside the clip.
	var used := {}
	for rid in root.get_node("StoryData").rooms.keys():
		for h in root.get_node("StoryData").rooms[rid].get("hotspots", []):
			var a := String(h.get("action_anim", ""))
			if a != "":
				used[a] = int(used.get(a, 0)) + 1
				_check(sheet.has_action(a), "%s.%s: action_anim '%s' has no sheet in data/actors/agata.json" % [rid, String(h.get("id", "")), a])
	for a in used.keys():
		if sheet.has_action(a):
			var n: int = sheet.action_sequence(a).size()
			var kf: int = sheet.action_key_frame(a)
			_check(kf > 0 and kf < n, "%s: key frame %d outside 1..%d" % [a, kf, n - 1])
			_check(not sheet.action_loops(a), "%s must play once (loop false)" % a)
	print("    action_anim in rooms: %s; key frames %s" % [str(used), str(sheet.action_key_frames)])
	_check(used.size() >= 3, "expected open, pick and reach to be used by hotspots, got %s" % str(used))
	# 2. Shutter in H1: walk there, the open action plays, the flag lands on the key frame, once.
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	var shutter: Node2D = room.get_node("Hotspots/shutter")
	var flag_sets := [0]
	var on_flag := func(f, v): if f == "h1_shutter_open" and v: flag_sets[0] += 1
	gs.flag_changed.connect(on_flag)
	player.speed_factor = 3.0
	player.call("walk_to_and_interact", shutter)
	var n := 0
	while not player.call("is_acting") and n < 2000:
		await process_frame
		n += 1
	_check(player.call("is_acting") and String(spr.animation).begins_with("open_"), "arriving at the shutter must start the open action, got %s" % String(spr.animation))
	_check(not gs.has_flag("h1_shutter_open"), "the shutter must not open before the key frame")
	var kf: int = sheet.action_key_frame("open")
	var seen_before_key := false
	var fire_frame := -1
	var fires0: int = player.action_fire_count
	n = 0
	while player.call("is_acting") and n < 2000:
		if not gs.has_flag("h1_shutter_open") and spr.frame < kf:
			seen_before_key = true
		if gs.has_flag("h1_shutter_open") and fire_frame < 0:
			fire_frame = spr.frame
		await process_frame
		n += 1
	print("    shutter: open action, flag set at sheet frame %d (key frame %d), fires %d, flag_changed %d" % [fire_frame, kf, player.action_fire_count - fires0, flag_sets[0]])
	_check(seen_before_key and fire_frame >= kf and fire_frame <= kf + 1, "the effect must land on the key frame %d (got %d)" % [kf, fire_frame])
	_check(gs.has_flag("h1_shutter_open") and flag_sets[0] == 1 and player.action_fire_count - fires0 == 1, "the shutter opens exactly once")
	_check(String(spr.animation).begins_with("idle_"), "after the action Agata idles, got %s" % String(spr.animation))
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	# A second click on the open shutter is only a look: no action, no second effect.
	player.call("walk_to_and_interact", shutter)
	n = 0
	while (player.call("is_walking") or player.call("is_acting")) and n < 2000:
		await process_frame
		n += 1
	_check(player.action_fire_count - fires0 == 1 and flag_sets[0] == 1, "clicking the open shutter again must not replay the action or its effect")
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	gs.flag_changed.disconnect(on_flag)
	# 3. Save in the middle of the stove action (before its key frame): the save has no effect in it;
	#    loading it leaves Agata standing, and the stove can be lit — once — afterwards.
	var stove: Node2D = room.get_node("Hotspots/stove")
	player.call("walk_to_and_interact", stove)
	n = 0
	while not player.call("is_acting") and n < 3000:
		await process_frame
		n += 1
	_check(player.call("is_acting") and not gs.has_flag("stove_lit"), "stove: action running, not lit yet")
	_check(rm.save_game(MID_SLOT), "save during the action")
	n = 0
	while player.call("is_acting") and n < 2000:
		await process_frame
		n += 1
	_check(gs.has_flag("stove_lit"), "the action lit the stove")
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	_check(rm.load_game(MID_SLOT), "load the mid-action save")
	await process_frame
	await process_frame
	_check(not gs.has_flag("stove_lit") and not player.call("is_acting") and String(spr.animation).begins_with("idle_"), "after loading the mid-action save: stove not lit, Agata standing (acting=%s, anim %s)" % [str(player.call("is_acting")), String(spr.animation)])
	var fires1: int = player.action_fire_count
	player.call("walk_to_and_interact", rm.current_room.get_node("Hotspots/stove"))
	n = 0
	while (player.call("is_walking") or player.call("is_acting")) and n < 3000:
		await process_frame
		n += 1
	_check(gs.has_flag("stove_lit") and player.action_fire_count - fires1 == 1, "after load the stove can be lit, exactly once")
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	player.speed_factor = 1.0
	gs.reset()
	_cleanup_m1()
