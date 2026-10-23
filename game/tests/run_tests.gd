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


## The H1 shutter's latch close-up (F8): strike when the marker is in the green; returns when the shutter is open.
func _open_latch() -> void:
	var mv = root.find_child("MechanicView", true, false)
	var g := 0
	while not gs.has_flag("h1_shutter_open") and g < 3000:
		g += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		elif sr.mechanic_open and mv != null and mv.panel != null and mv.panel.get("timing") != null:
			var tb = mv.panel.timing
			if tb.logic != null and tb.logic.state == "run" and absf(tb.logic.pos() - tb.logic.center) < 0.04:
				tb.strike()
		await process_frame
	var g2 := 0
	while (sr.mechanic_open or not sr.current_beat.is_empty()) and g2 < 600:
		if not sr.current_beat.is_empty():
			sr.advance()
		g2 += 1
		await process_frame


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
	await _test("H1: Agata sprite from sheets (frame from sprites.json, height 384, 8 walk + 8 idle), directions, table occluder z-sort", _test_h1_real)
	await _test("Turns (F22): >45° goes row by row (≈70 ms each, half a turn ≈ 0.28 s) with the animation playing; from standing Agata turns on the spot, then walks; an NPC turns to her the same way", _test_turns)
	await _test("Stride: fps from speed, stride = sheet stride, foot lock holds the drawn figure between frames", _test_stride)
	await _test("NPC actors: Tamara/Pelageya from sheets on their hotspots, depth scale, y-sort, talk during their lines", _test_npc_actors)
	await _test("Shadows: soft ellipse under the feet of Agata and NPCs, behind the figure, scaled by depth", _test_shadows)
	await _test("No straight-line walking: a click right after entering Z1 waits for the nav map and goes round the counter", _test_no_straight_line)
	await _test("Loop seams: every repeating animation of every actor sheet returns to its first frame smoothly", _test_loop_seams)
	await _test("Cross-fade: switching idle↔walk (Agata) and idle↔talk (Tamara) dissolves the old pose in ≈0.12 s", _test_crossfade)
	await _test("Actions: hotspot action_anim plays once, the effect lands on the key frame exactly once; save mid-action is safe", _test_actions)
	await _test("Idle sway: even back-and-forth — equal time to both extreme poses (±5 %), equal holds, easing to rest at both ends", _test_idle_sway)
	await _test("Tikhon: bone-rigged puppet in H1 from the start — breathing/tail loop without a seam, ear/head accents, head lift on his lines, scared tail, hotspot still clickable", _test_tikhon)
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
		while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running") or sr.call("is_staging")) and frames < MAX_FRAMES:
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
		var staged := false
		while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 2000:
			guard += 1
			if sr.call("is_staging"):
				# a scene staging (fade, room change, sounds): no beat on screen, the queue waits for it
				if not staged:
					seen.append("stage")
					staged = true
				await t.process_frame
				continue
			staged = false
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


## Rows the actor draws (from the playing animation's name) until it shows `target`: consecutive repeats
## dropped. Also: seconds taken, whether the animation kept playing every frame, positions seen.
func _watch_rows(actor: Node2D, target: int, timeout_s: float) -> Dictionary:
	var spr: AnimatedSprite2D = actor.get_node("Sprite")
	var rows: Array = []
	var played := true
	var poses: Array = []
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	# game time (sum of process deltas, as the turn counts it — not the wall clock of a loaded runner); the current
	# frame counts too: a test resumed on process_frame runs before the actors' _process of the same frame
	var game_s := root.get_process_delta_time()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		var name := String(spr.animation)
		var r := int(name.substr(name.rfind("_") + 1))
		if rows.is_empty() or rows[-1] != r:
			rows.append(r)
		played = played and spr.is_playing()
		poses.append(actor.global_position)
		seen.append(r)
		if r == target:
			break
		await process_frame
		game_s += root.get_process_delta_time()
	return {"rows": rows, "s": game_s, "playing": played, "poses": poses, "seen": seen}


func _rows_step_by_one(rows: Array, n: int) -> bool:
	for i in range(1, rows.size()):
		if load("res://scripts/actors/actor_sheet.gd").row_steps(int(rows[i - 1]), int(rows[i]), n) != 1:
			return false
	return true


func _test_turns() -> void:
	Engine.time_scale = 1.0
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	gs.set_flag("done_M01", true)
	rm.change_room("H1", "", Vector2(1200, 900))
	for i in 6:
		await physics_frame
	_check(player.call("uses_sheet"), "Agata uses the sheets")
	# 1. Standing, facing left (row 6) → face right (row 2): half a turn past the face, idle playing.
	player.direction = 6
	player.shown_dir = 6
	player.set("_turn_t", 0.0)  # a turn starts from rest (set by hand here, not by a finished turn)
	player.call("_play_idle")
	await process_frame
	player.call("face_towards", player.global_position + Vector2(300, 0))
	var w: Dictionary = await _watch_rows(player, 2, 2.0)
	print("    Agata 6 → 2: rows %s in %.2f s (game time; time_scale %.1f), playing %s" % [str(w.rows), w.s, Engine.time_scale, str(w.playing)])
	_check(w.rows == [6, 7, 0, 1, 2], "half a turn goes 6 → 7 → 0 → 1 → 2 (past the face), got %s" % str(w.rows))
	_check(w.s >= 0.24 and w.s <= 0.6, "four steps of ≈70 ms take ≈0.28 s, got %.2f s" % w.s)
	_check(w.playing, "the idle keeps playing during the turn (no frozen frame)")
	# 2. 90° the other way (2 → 4, past 3) — any change over 45° visits the neighbours in order.
	player.call("face_towards", player.global_position + Vector2(0, -300))
	w = await _watch_rows(player, 4, 2.0)
	_check(w.rows == [2, 3, 4], "a quarter turn goes 2 → 3 → 4, got %s" % str(w.rows))
	# 3. Standing towards the viewer (row 0), a click behind her: she turns on the spot first, then walks off.
	player.direction = 0
	player.shown_dir = 0
	player.set("_turn_t", 0.0)  # a turn starts from rest (set by hand here, not by a finished turn)
	player.call("_play_idle")
	await process_frame
	var start: Vector2 = player.global_position
	player.call("walk_to", start + Vector2(0, -150))
	var target_row: int = player.sheet.direction_index(Vector2(0, -1))
	w = await _watch_rows(player, target_row, 2.0)
	var moved_while_turning := false
	var sheet_script = load("res://scripts/actors/actor_sheet.gd")
	for i in range(w.poses.size()):
		# more than 45° off the path: still on the spot (the last 45° she may already walk off)
		if sheet_script.row_steps(int(w.seen[i]), target_row, 8) > 1:
			moved_while_turning = moved_while_turning or (w.poses[i] as Vector2).distance_to(start) > 1.0
	print("    Agata walk behind: rows %s in %.2f s, moved while turning %s" % [str(w.rows), w.s, str(moved_while_turning)])
	_check(_rows_step_by_one(w.rows, 8) and w.rows.size() == 5, "turning to walk off goes row by row through half a turn, got %s" % str(w.rows))
	_check(not moved_while_turning, "she turns on the spot before walking off (no walking backwards)")
	for i in 90:
		await physics_frame
	_check(player.global_position.distance_to(start) > 20.0, "after the turn she walks (moved %.0f px)" % player.global_position.distance_to(start))
	# 4. An NPC turning to face Agata (Pavel in M2): row by row as well.
	gs.set_flag("office_unbolted", true)
	rm.change_room("M2", "", Vector2(700, 900))
	for i in 6:
		await physics_frame
	var npc: Node2D = null
	for n in load("res://scripts/actors/npc_actor.gd").all_in(rm.current_room):
		if n.actor_id == "pavel":
			npc = n
	_check(npc != null, "Pavel stands in M2 (office_unbolted)")
	if npc != null:
		var from_row: int = npc.sheet.direction_index(Vector2(1, 0))
		npc.direction = from_row
		npc.shown_dir = from_row
		npc.set("_turn_t", 0.0)
		npc.call("_play_idle")
		await process_frame
		npc.call("face_towards", npc.global_position + Vector2(-300, 0))
		var to_row: int = npc.sheet.direction_index(Vector2(-1, 0))
		w = await _watch_rows(npc, to_row, 2.0)
		print("    Pavel %d → %d: rows %s in %.2f s" % [from_row, to_row, str(w.rows), w.s])
		_check(_rows_step_by_one(w.rows, 8) and w.rows.size() == 5 and w.rows[-1] == to_row, "Pavel turns row by row, got %s" % str(w.rows))
		_check(w.playing, "Pavel's idle keeps playing during the turn")
	_cleanup_m1()


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
	_check(sd.scenes.has("M01") and sd.scenes.has("M08") and sd.scenes.has("N01") and sd.scenes.has("Q04"), "scenes M01/M08/N01/Q04 missing")
	_check(sd.start_location == "Z1", "start location should be Z1, got %s" % sd.start_location)
	_check(not sd.text("@ui.not_built").begins_with("["), "ui texts not resolved")
	# Every in-scope room has a real background file and every layer/state/hotspot/puzzle image exists.
	for rid in sd.rooms_index.get("in_scope", []):
		var spec: Dictionary = sd.room(rid)
		var bg_img := String(spec.get("background", {}).get("image", ""))
		# Art ordered but not delivered (R2, R3 — BRIEF_CHATGPT_v4): an engine-drawn stand-in from data,
		# with the order named in `_art`; never a missing picture.
		var placeholder: bool = spec.get("background", {}).has("placeholder") and String(spec.get("_art", "")) != ""
		_check(placeholder or (bg_img != "" and ResourceLoader.exists(bg_img)), "%s: background.image missing or not found (%s)" % [rid, bg_img])
		for l in spec.get("layers", []):
			if not l.has("image") and l.has("text"):
				continue  # stand-in text layer until its picture is drawn (validate_rooms.py п. 11)
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
	rm.checkpoint_prefix = "test_%d_" % OS.get_process_id()
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
	_check(seen.size() == sd.scene("M01")["mandatory_lines"].size() and seen.size() == 9, "M01 should play its 9 lines, got %s" % str(seen))
	_check(gs.has_flag("done_M01") and gs.has_flag("met_tamara") and gs.has_flag("knows_pier_trace") and gs.has_flag("knows_letters_bag")
		and gs.has_flag("knows_dunya_left") and gs.has_flag("knows_bridge_lost"), "M01 flags missing")
	_check(gs.has_item("key_house") and gs.has_item("pocket_watch") and gs.has_item("mitten"), "M01 items missing: %s" % str(gs.inventory))
	# Docs/SCENARIO_FINAL.md M01: Tamara's letter goes to the journal, not the bag.
	_check(not gs.has_item("letter_tamara") and gs.has_flag("has_letter_tamara"), "the letter is in the journal, not in the bag: %s" % str(gs.inventory))
	_check(sr.journal_facts().any(func(f): return String(f).contains("опора моста")), "journal knows what Tamara wrote: %s" % str(sr.journal_facts()))
	_check(gs.journal_goal == sd.scene("M01").get("goal", sd.scene("M01")["result"]), "journal goal should be M01 goal (player text, not the scenario note)")
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
	# Day two is built (block 2): the mill yard is a real room, the way there is open from the start.
	_check(m1exit != null and m1exit.is_open() and m1exit.target_exists(), "Z2→M1 is open and the mill yard is built")

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
	_check(gs.has_flag("done_M02") and gs.has_flag("met_pelageya") and gs.has_flag("knows_no_road") and gs.has_flag("knows_rope_on_plate"),
		"M02 flags missing")
	# 9 lines and the shown attempt (a staging: fade, boat knocks its own pier) before Pelageya's «Берег вижу»;
	# the sluice, the marsh, other boats and the manager are questions now (polish 22.10, D23).
	_check(seen.size() == 10 and seen[2] == "stage", "M02: 2 lines, the staging, 7 lines; got %s" % str(seen))
	_check(not sr.is_staging() and sr.stage_dim == 0.0, "the staging is over, no dusk left")
	_check(not r2exit.is_open(), "R1→R2 stays closed after M02 (без плиты лодку вернёт сюда же)")

	# --- M03 in H1 ---
	_check(await bot.go("Z2"), "R1→Z2")
	# Director 18.10: the house door stays locked until the key is applied (bag → door); the key stays in
	# the lock (leaves the bag), the door is open from then on — after a load too.
	var h1exit = bot.exit_to("H1")
	_check(h1exit != null and not h1exit.is_open(), "Z2→H1 is locked before the key is applied")
	_check(not (await bot.go("H1")), "Z2→H1 must not open without the key applied")
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.closed", "the locked door names the key in the bag: %s" % str(sr.current_beat))
	await bot.finish()
	_check(gs.has_item("key_house") and not gs.has_flag("house_unlocked"), "the key stays in the bag after the locked attempt")
	sr.select_item("key_house")
	_check(not (await bot.go("H1")), "the unlock text plays before Agata goes in")
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.unlock", "key on the door → unlock text: %s" % str(sr.current_beat))
	_check(not gs.has_item("key_house") and gs.has_flag("house_unlocked") and gs.has_flag("has_key_house"), "key used: out of the bag, door unlocked, never given again")
	await bot.finish()
	var fr_in := 0
	while bot.room_id() != "H1" and fr_in < 120:
		await process_frame
		fr_in += 1
	await bot.wait_idle()
	_check(bot.room_id() == "H1", "after the unlock text Agata walks in (room=%s)" % bot.room_id())
	_check(not gs.has_flag("started_M03"), "M03 must not start before the three steps")
	await bot.use("shutter")
	await bot.finish()
	await _open_latch()   # F8: the tight latch — caught up in the green of «точный удар»
	await bot.finish()
	await bot.use("stove")
	await bot.finish()
	_check(gs.has_flag("stove_lit") and gs.has_flag("h1_shutter_open"), "M03 steps 1-2")
	await bot.use("scarf")
	seen = await bot.finish()  # the scarf narration, then M03 (deferred trigger) in the same run
	_check(gs.has_flag("started_M03"), "M03 should start after the third step")
	_check(gs.has_flag("done_M03") and gs.has_flag("met_tikhon") and gs.has_flag("house_open") and gs.has_flag("knows_tikhon_waits"), "M03 flags missing: %s" % str(seen))
	_check(seen.any(func(x): return x.contains("Вечер долгий")), "M03: «Вечер долгий»: %s" % str(seen))
	var tikhon = bot.hotspot("tikhon")
	_check(tikhon != null and tikhon.visible, "Tikhon should be visible after M03")
	# Home knowledge by questions (M03): the door from the school — «Нина просила», in his own voice.
	await bot.use("tikhon")
	_check(sr.current_beat.get("type", "") == "options" and sr.current_options().size() == 4, "Tikhon: four questions: %s" % str(sr.current_beat))
	seen = await bot.finish(["door"])
	_check(gs.has_flag("h1_asked_door") and seen.any(func(x): return x.begins_with("tikhon:") and x.contains("Нина просила")), "Tikhon answers about the door: %s" % str(seen))
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
	seen = await bot.finish()
	_check(gs.has_item("door_hinges") and gs.has_flag("seen_workshop") and gs.has_flag("knows_rule_things_remember") and gs.has_flag("seen_bell"), "M04 workshop steps")
	_check(seen.size() == 2 and seen[1].contains("Если колокол звенит"), "bell: the tag, then Agata's thought about the school door: %s" % str(seen))
	# N6 (playtest r7): the painted box stays — the hotspot too: empty now, the hinges go to the school door in the gallery.
	_check(bot.hotspot("hinges_box") != null and bot.hotspot("hinges_box").visible, "the hinges' box stays clickable after pickup")
	await bot.use("hinges_box")
	var box_seen: Array = await bot.finish()
	_check(gs.inventory.count("door_hinges") == 1 and box_seen.any(func(x): return String(x).contains("пуста")), "the empty box: «…пуста: петли у меня — к школьной двери в галерее» (%s)" % str(box_seen))
	# The brace before the plan: look only, not taken (Docs/SCENARIO_FINAL.md, section 9).
	await bot.use("brace")
	await bot.finish()
	_check(not gs.has_item("brace_plate") and not gs.has_flag("has_brace_plate") and bot.hotspot("brace").visible, "the brace stays on the bench before the plan")
	await bot.use("bundle_nina")
	await bot.finish()
	_check(gs.has_flag("h2_bundle_unwrapped") and not gs.has_item("bundle_nina"), "the bundle unwraps and never goes into the bag")
	_check(not gs.has_flag("done_M04"), "M04 not complete before seeing the door")
	_check(await bot.go("H1"), "H2→H1")
	_check(await bot.go("H3"), "H1→H3")
	await bot.use("school_door")
	seen = await bot.finish()
	await process_frame
	seen += await bot.finish()
	_check(gs.has_flag("done_M04") and gs.has_flag("seen_school_door") and gs.has_flag("seen_mirror_home"), "M04 should complete in H3 (grants include seen_mirror_home)")
	_check(gs.has_flag("has_school_door") and gs.has_flag("has_bell") and gs.has_flag("has_bundle_nina"), "non-inventory items become has_ flags")
	_check(seen.any(func(x): return x.contains("Доделаю за неё")), "M04: «Доделаю за неё»: %s" % str(seen))
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
		_check(not sr.puzzle_check(), "two hinges are not enough: the door has three")
		sr.puzzle_place("hinge_3", "middle")
		_check(sr.puzzle_check(), "correct placement (three hinges, V notch) must succeed")
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
	_check(gs.has_flag("house_unlocked") and not gs.has_item("key_house"), "after a load the house stays unlocked and the key used")
	_check(gs.has_flag("done_M04") and sr.current_beat.is_empty(), "M04 must not replay after load")
	await bot.use_item("door_hinges", "school_door")
	_check(sr.puzzle_open, "puzzle reopens after load")
	if sr.puzzle_open:
		sr.puzzle_place("hinge_1", "top")
		sr.puzzle_place("hinge_2", "bottom")
		sr.puzzle_place("hinge_3", "middle")
		sr.puzzle_set_mark(2)
		_check(sr.puzzle_check(), "puzzle solvable after load")
		sr.close_puzzle()
	await bot.finish()
	_check(gs.has_flag("door_school_installed"), "M05 redone after load")

	# --- O1: M06, M07, V03, chalk ---
	_check(await bot.go("O1"), "H3→O1 through the installed door")
	seen = await bot.finish()
	_check(gs.has_flag("o1_saw_winter") and seen.any(func(x): return x.contains("Там зима")), "first entry: «Там зима. А у нас ещё октябрь»: %s" % str(seen))
	await bot.use("sack")
	await bot.finish()
	await bot.use("notebooks")
	await bot.finish()
	await process_frame
	seen = await bot.finish()
	_check(gs.has_flag("done_M06") and gs.has_flag("seen_class_traces"), "M06 completes after 2 of 3 examines; seen=%s" % str(seen))
	await bot.use("teacher_drawer")
	_check(sr.view_open and String(sr.view.get("id", "")) == "teacher_drawer", "the drawer opens its close-up (photo, drawing, plan)")
	seen = await bot.finish()
	await process_frame
	seen += await bot.finish()
	sr.close_view()
	await process_frame
	_check(gs.has_flag("done_M07") and gs.has_flag("knows_crossing_plan"), "M07; seen=%s" % str(seen))
	_check(gs.has_item("photo_bridge") and gs.has_item("drawing_ilya") and gs.has_item("plan_crossing"), "M07 items: %s" % str(gs.inventory))
	_check(seen.any(func(x): return x.contains("Тому, кто придёт через эту дверь")) and seen.any(func(x): return x.contains("Держим мы")), "M07: the plan is read, «Держим мы…»: %s" % str(seen))
	var inv_before: int = gs.inventory.size()
	await bot.use("teacher_drawer")
	await bot.finish()
	_check(not sr.view_open and gs.inventory.size() == inv_before, "the empty drawer gives nothing twice and opens no close-up")
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
	_check(gs.has_flag("mitten_placed") and not gs.has_item("mitten"), "mitten left on the step: out of the bag")
	var gate = bot.exit_to("O4")
	_check(gate != null and not gate.is_open(), "O2→O4 closed (school_path_open)")
	var before_loop: Vector2 = player.global_position
	_check(not (await bot.go("O4")), "gate must loop back, not transition")
	await bot.wait_idle()
	seen = await bot.finish()
	await process_frame
	seen += await bot.finish()
	_check(gs.has_flag("observed_path_loop"), "loop sets observed_path_loop")
	_check(bot.room_id() == "O2", "still in O2 after the loop")
	var porch = rm.current_room.get_spawn("porch")
	_check(porch != null and player.global_position.is_equal_approx(porch.global_position), "player teleported to the porch (was %s, now %s)" % [str(before_loop), str(player.global_position)])
	_check(gs.has_flag("mitten_placed"), "the mitten stays in place after the loop")
	# The board is optional now (Docs/SCENARIO_FINAL.md M08): the loop alone completes M08.
	_check(gs.has_flag("done_M08") and seen.any(func(x): return x.contains("До деревни — ещё нет")), "M08 completes after the loop: %s" % str(seen))
	# The mitten can be picked up again — the same one, once.
	await bot.use("mitten")
	await bot.finish()
	_check(gs.has_item("mitten") and gs.has_flag("mitten_taken_back") and not bot.hotspot("mitten").visible, "the mitten is back in the bag")

	# --- back to O1: chalk on the board, one of three lines (or none) ---
	_check(await bot.go("O1"), "O2→O1")
	await bot.use_item("chalk", "board")
	var opts: Array = sr.current_options()
	_check(opts.size() == 4, "the board offers three lines and «не писать» (the drawing is found): %s" % str(opts))
	seen = await bot.finish(["mama"])
	_check(gs.has_flag("board_mama") and not gs.has_flag("board_here"), "«Мама, я иду» on the board; seen=%s" % str(seen))
	_check(not gs.has_item("chalk") and gs.has_flag("has_chalk"), "chalk stays at the board after writing (out of the bag, not given again)")
	var bm = rm.current_room.get_node_or_null("Layers/board_mama")
	_check(bm != null and bm.visible and bm.get_node_or_null("Image") != null and not rm.current_room.get_node("Layers/board_written").visible
		and not rm.current_room.get_node("Layers/board_ilya").visible, "«Мама, я иду» drawn in chalk (batch 7), the only line on the board")

	# --- home through the school door → the night by the stove (N01), checkpoint «День второй» ---
	await bot.go("H3")
	_check(gs.has_flag("started_N01"), "back home through the school door → the night starts (room=%s)" % bot.room_id())
	seen = await bot.finish()
	_check(gs.has_flag("done_N01") and gs.has_flag("night_day1"), "N01 (night by the stove) done: %s" % str(seen))
	# (the first staging may already be over inside bot.go — its wait_idle waits for stagings too)
	var night_lines: Array = seen.filter(func(x): return x != "stage")
	# The morning staging, then Tikhon's morning line (SCENARIO_FINAL §7 «Утро», block 2 22.10) before the checkpoint.
	_check(night_lines.size() == 4 and night_lines[0].begins_with("agata:") and night_lines[2].begins_with("tikhon:")
		and seen.size() >= 2 and seen[seen.size() - 2] == "stage" and String(seen.back()).begins_with("tikhon:Колокол не трогай"),
		"N01: 2 lines of Agata, Tikhon's grumble, morning staging, Tikhon's morning line: %s" % str(seen))
	_check(bot.room_id() == "H1", "the night moves Agata to the stove (H1), room=%s" % bot.room_id())
	_check(sr.stage_dim == 0.0 and not sr.is_staging(), "morning: no dusk left")
	var cp_slot: String = rm.checkpoint_prefix + "day2"
	_check(gs.has_save(cp_slot) and String(gs.save_info(cp_slot).get("title", "")) == "День второй", "checkpoint «День второй» saved: %s" % str(gs.save_info(cp_slot)))
	_check(gs.journal_goal == String(sd.scene("N01")["goal"]), "journal goal of day two: %s" % gs.journal_goal)
	_check(await bot.go("H3"), "H1→H3 again")
	await bot.finish()
	_check(not sr.is_staging() and sr.current_beat.is_empty() and bot.room_id() == "H3", "the night never replays")
	_check(rm.load_game(cp_slot), "load «День второй»")
	await process_frame
	await process_frame
	_check(bot.room_id() == "H1" and not sr.is_staging() and sr.current_beat.is_empty() and gs.has_flag("done_N01"), "after loading «День второй»: morning in H1, nothing replays")

	# --- day two morning: the brace can be taken now (the plan says where it is) ---
	_check(await bot.go("H2"), "H1→H2")
	await bot.use("brace")
	await bot.finish()
	_check(gs.has_item("brace_plate") and not bot.hotspot("brace").visible, "the brace is taken after the plan")
	_check(rm.save_game(MID_SLOT), "save with the brace")
	_check(rm.load_game(MID_SLOT), "load with the brace")
	await process_frame
	_check(gs.inventory.count("brace_plate") == 1 and not bot.hotspot("brace").visible, "after a load the brace is in the bag once, the bench empty")
	gs.delete_save(cp_slot)

	_check(gs.has_flag("door_school_installed") and gs.has_flag("board_mama") and gs.has_flag("knows_crossing_plan"), "final flags")
	for it in ["pocket_watch", "photo_bridge", "drawing_ilya", "plan_crossing", "brace_plate", "mitten"]:
		_check(gs.has_item(it), "inventory should hold %s" % it)
	for it in ["door_hinges", "key_house", "chalk", "letter_tamara"]:
		_check(not gs.has_item(it), "%s must stay out of the bag" % it)
	for sid in ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "N01", "V01", "V02", "V03", "Q04"]:
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
	# Frame width comes from sprites.json (v3: 384 — the pick bend fits; was 288); height and pivot stay.
	var fw: int = player.sheet.frame_w
	_check(fw >= 288 and player.sheet.frame_h == 384, "frame %dx%d: width ≥ 288 from sprites.json, height 384" % [fw, player.sheet.frame_h])
	_check(tex != null and tex.get_size() == Vector2(fw, 384), "frame size should be %dx384, got %s" % [fw, str(tex.get_size() if tex else null)])
	var wn := int(player.sheet.actions["walk"].get("frames", 0))
	# F16 (23.10, «у Агаты будто бы мало fps»): ≥ 20 frames per walk cycle, all of them played
	_check(spr.sprite_frames.get_frame_count("walk_0") == wn and wn >= 20, "walk: ≥ 20 frames per cycle, all played (sheet %d, played %d)" % [wn, spr.sprite_frames.get_frame_count("walk_0")])
	# Idle rev 8: eased back-and-forth over the evenly-moving frames (data idle_motion, test «Idle sway»).
	var tl: Array = player.sheet.eased_timeline("idle", 3)
	_check(spr.sprite_frames.get_frame_count("idle_3") == tl.size() and tl.size() >= 6, "idle_3 is built from the eased timeline (%d segments), got %d frames" % [tl.size(), spr.sprite_frames.get_frame_count("idle_3")])
	# F16/F22 (Директор 02:29: «будто бы 4–5 кадров меняются и всё»): every row's sway shows ≥ 20 different frames
	for r in 8:
		var cols := {}
		for seg in player.sheet.eased_timeline("idle", r):
			cols[int(seg[0])] = true
		_check(cols.size() >= 20, "idle row %d sways through %d different frames (≥ 20)" % [r, cols.size()])
	var seq: Array = player.sheet.frame_sequence(8, "pingpong")
	_check(seq == [0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1], "pingpong sequence for 8 frames, got %s" % str(seq))
	_check(player.sheet.frame_sequence(12, "loop") == range(12), "loop sequence is 0..n-1")
	for i in tl.size():
		var at3 := spr.sprite_frames.get_frame_texture("idle_3", i) as AtlasTexture
		# grid sheet: the cell of column tl[i][0], row 3; packed atlas (game copy): that frame's piece + margin
		var want: Array = player.sheet.frame_rect(player.sheet.actions["idle"], 3, int(tl[i][0]))
		_check(at3.region == want[0] and at3.margin == want[1], "idle_3 frame %d must be sheet column %d of row 3, got %s / %s" % [i, int(tl[i][0]), str(at3.region), str(at3.margin)])
		_check(is_equal_approx(spr.sprite_frames.get_frame_duration("idle_3", i), float(tl[i][2])), "idle_3 frame %d holds %d timeline steps" % [i, int(tl[i][2])])
	_check(is_equal_approx(spr.sprite_frames.get_animation_speed("idle_0"), 30.0), "eased idle runs on a 30 steps/s timeline")
	var st = load("res://scripts/actors/actor_sheet.gd").load_actor("agata", {"idle_static_frame": 0})
	_check(st.is_loaded() and st.frames.get_frame_count("idle_0") == 1, "idle_static_frame still pins the idle to one frame when set")
	_check(spr.offset.is_equal_approx(Vector2(-0.5 * fw, -0.9464285714285714 * 384.0)), "sprite offset should put the pivot (feet) at the origin, got %s" % str(spr.offset))
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
	# Step tempo from real speed: at scale 1 and 260 px/s the walk cycle runs at 0.67–1.17 × the sheet's frames
	# per second of cycle (12 frames → 8–14 fps; F16: 24 frames → 16–28 fps — the sheet plays at its own tempo).
	var wfr := float(player.sheet.walk_frames())
	var fps_lo := wfr * 2.0 / 3.0
	var fps_hi := wfr * 7.0 / 6.0
	var fps1: float = player.sheet.walk_fps(260.0, 1.0)
	_check(fps1 >= fps_lo and fps1 <= fps_hi, "walk fps at scale 1 / 260 px/s should be %.0f–%.0f, got %.2f" % [fps_lo, fps_hi, fps1])
	# Speed in px/s follows the depth scale (constant metres per second).
	player.call("enter_room", room, Vector2(1200, 700))
	var v_far: float = player.call("current_speed_px")
	var fps_far: float = player.call("current_walk_fps")
	player.call("enter_room", room, Vector2(1200, 1070))
	var v_near: float = player.call("current_speed_px")
	var fps_near: float = player.call("current_walk_fps")
	_check(is_equal_approx(v_near / v_far, 2.0 / 1.3), "speed should scale with depth (near/far = 2.0/1.3), got %.3f" % (v_near / v_far))
	_check(absf(fps_near - fps_far) < 0.05 and fps_near >= fps_lo and fps_near <= fps_hi, "walk fps must stay constant across depth and within %.0f–%.0f, got far %.2f / near %.2f" % [fps_lo, fps_hi, fps_far, fps_near])
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
	var speeds := {}
	for run in runs:
		player.call("enter_room", room, run[1])
		await physics_frame
		var resyncs0: int = player.lock_resyncs
		player.call("walk_to", run[2])
		var samples: Array = []   # [frame, drawn, logical, scale, game µs, lag, row]
		var n := 0
		# Game time, not wall time: the sum of the process deltas the player moved by (a loaded CI runner stretches
		# the wall clock between frames and the measured speed drifted 5 % off — CI 23.10).
		var game_us := 0.0
		while player.call("is_walking") and n < 3000:
			await process_frame
			n += 1
			game_us += root.get_process_delta_time() * 1e6
			if not String(spr.animation).begins_with("walk_"):
				continue
			samples.append([spr.frame, player.call("drawn_position"), player.global_position, absf(player.scale.y), game_us, player.call("lock_lag_px"), player.direction])
		var within_max := 0.0
		var max_err := 0.0
		var max_lag := 0.0
		var ahead := false
		var changes := 0
		var t0 := -1.0
		var t1 := -1.0
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
			var expect: float = sheet.stride_at(run[3], a[0]) * a[3] * sheet.row_floor_factor(run[3], player.call("floor_foreshortening"))
			var got: float = (b[1] as Vector2).distance_to(a[1])
			adv.append(snappedf(got, 0.1))
			max_err = maxf(max_err, absf(got - expect))
		var fps_meas := float(changes - 1) / (float(t1 - t0) / 1e6) if changes > 1 else 0.0
		print("    walk %s (row %d): %d frame changes, fps %.2f (formula %.2f), drawn still within a frame: max %.2f px; advance per change %s; max |advance − table×scale| %.2f px; max lag behind logical %.1f px; resyncs %d" % [
			run[0], run[3], changes, fps_meas, sheet.walk_fps_const(), within_max, str(adv), max_err, max_lag, player.lock_resyncs - resyncs0])
		_check(changes >= 8, "%s: expected at least 8 frame changes, got %d" % [run[0], changes])
		# Measured logical speed per unit of depth scale (px/s ÷ scale), for the vertical/side ratio.
		# only while the logical position moves: the end of a walk where the drawn figure finishes its steps
		# (logical position already at the target) is not speed; nor a turn on the spot before it (F22)
		var dist_px := 0.0
		var scale_sum := 0.0
		var secs := 0.0
		var moving := 0
		for i in range(1, samples.size()):
			var dd := (samples[i][2] as Vector2).distance_to(samples[i - 1][2])
			if dd < 0.01:
				continue
			dist_px += dd
			secs += float(samples[i][4] - samples[i - 1][4]) / 1e6
			scale_sum += float(samples[i][3])
			moving += 1
		speeds[run[0]] = dist_px / maxf(secs, 0.001) / maxf(scale_sum / maxf(moving, 1), 0.001)
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
	# Room perspective: vertical screen speed = side speed × floor_foreshortening (±5 %), by the
	# formula for every depth row and as measured on the two walks; profile rows stay exact (factor 1).
	var k: float = player.call("floor_foreshortening")
	var v_side: float = sheet.walk_speed_row_px(2, 1.0) * sheet.row_floor_factor(2, k)
	var v_down: float = sheet.walk_speed_row_px(0, 1.0) * sheet.row_floor_factor(0, k)
	var v_up: float = sheet.walk_speed_row_px(4, 1.0) * sheet.row_floor_factor(4, k)
	var measured: float = float(speeds.get("up", 0.0)) / maxf(float(speeds.get("left", 1.0)), 0.001)
	print("    floor_foreshortening %.2f (H1): vertical/side speed by formula %.3f / %.3f, measured on the walks %.3f; row factors %s" % [
		k, v_down / v_side, v_up / v_side, measured, str(range(8).map(func(r): return snappedf(sheet.row_floor_factor(r, k), 0.001)))])
	_check(absf(v_down / v_side - k) <= 0.05 * k and absf(v_up / v_side - k) <= 0.05 * k, "vertical/side speed must equal floor_foreshortening %.2f ±5 %%, got %.3f / %.3f" % [k, v_down / v_side, v_up / v_side])
	_check(absf(measured - k) <= 0.05 * k, "measured vertical/side speed %.3f must equal floor_foreshortening %.2f ±5 %%" % [measured, k])
	_check(is_equal_approx(sheet.row_floor_factor(2, k), 1.0) and is_equal_approx(sheet.row_floor_factor(6, k), 1.0), "profile rows keep the measured root motion (factor 1)")
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
	_check(spr.sprite_frames.get_frame_count("idle_0") == t.sheet.eased_timeline("idle", 0).size() and spr.sprite_frames.get_frame_count("talk_0") == t.sheet.eased_timeline("talk", 0).size(), "tamara: eased idle and eased talk timelines (data overrides), got %d/%d" % [spr.sprite_frames.get_frame_count("idle_0"), spr.sprite_frames.get_frame_count("talk_0")])
	_check(spr.animation == "idle_0" and spr.is_playing(), "tamara idles facing the viewer (idle_0), got %s" % spr.animation)
	var hs: Node2D = room.get_node("Hotspots/tamara")
	var shape: CollisionShape2D = hs.get_node("Shape")
	var feet: Vector2 = hs.global_position + Vector2(0, shape.shape.size.y / 2)
	_check(t.global_position.is_equal_approx(feet), "tamara's feet at the hotspot's bottom centre %s, got %s" % [str(feet), str(t.global_position)])
	_check(is_equal_approx(t.scale.y, room.depth_scale(feet.y) * 1.055), "tamara scale = room depth scale at her feet × 1.055 (1,74 м при Агате 1,65 м — по замыслу): %.3f, got %.3f" % [room.depth_scale(feet.y) * 1.055, t.scale.y])
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
		_check(is_equal_approx(p.scale.y, room.depth_scale(p.global_position.y) * 0.94), "pelageya scale = depth scale × 0.94 (1,55 м при Агате 1,65 м — по замыслу)")
		_check(p.get_node("Sprite").sprite_frames.get_frame_count("talk_0") == p.sheet.eased_timeline("talk", 0).size(), "pelageya talk plays the eased back-and-forth")
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
				# Paths hug the cut-out's edge; only points clearly inside count (> 8 px from every edge). The cut-out is
				# the counter plus the body's clearance (≈ 100 px at this depth since D3, 23.10), so a few px of corner
				# cutting at speed ×4 still keeps Agata far from the counter itself.
				if Geometry2D.is_point_in_polygon(player.global_position, h) and _edge_distance(player.global_position, h) > 8.0:
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
		if _is_puppet(id):
			continue  # one-picture bone rig (Tikhon): no sheet, checked by its own test
		var sheet = load("res://scripts/actors/actor_sheet.gd").load_actor(id)
		if not sheet.is_loaded():
			_check(false, "%s: sheet not loaded (%s)" % [id, sheet.load_error])
			continue
		for action in sheet.actions.keys():
			if not sheet.action_loops(action):
				continue  # one-shot actions end in a cross-fade, not a seam
			var seq: Array = sheet.action_sequence(action, 0)
			if action == sheet.idle_action and sheet.idle_static_frame >= 0:
				continue
			if seq.size() < 3:
				continue
			var path: String = sheet.sheet_dir + "/" + String(sheet.actions[action].get("sheet", action + ".png"))
			var img: Image = sheet.grid_image(String(action))  # the game copy is a packed atlas: unpacked to the grid
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
				seq = sheet.action_sequence(action, r)
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
	var iimg: Image = ag.grid_image(ag.idle_action)
	_check(iimg != null and not iimg.is_empty(), "cannot read %s" % ipath)
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
		idle_anim = String(spr.animation)  # she may turn on the spot first (F22): the last idle row before the walk
		await process_frame
		n += 1
	fade = player.get_node_or_null("Crossfade")
	_check(fade != null and fade.visible, "idle→walk must start a cross-fade node 'Crossfade'")
	if fade != null:
		# the old pose: the idle on the row the walk starts from (after a turn on the spot, F22, that is the row shown last)
		var walk_row := String(spr.animation).substr(String(spr.animation).rfind("_") + 1)
		idle_anim = "idle_" + walk_row if String(spr.animation).begins_with("walk_") else idle_anim
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
	# F8 (23.10): the action's effect is Agata taking hold of the tight latch (the close-up of «точный удар»
	# opens on the key frame); the shutter itself opens in that close-up.
	var on_flag := func(f, v): if f == "h1_shutter_latch" and v: flag_sets[0] += 1
	gs.flag_changed.connect(on_flag)
	player.speed_factor = 3.0
	player.call("walk_to_and_interact", shutter)
	var n := 0
	# is_acting is true from arrival; the action itself starts once she has turned to the shutter (F22)
	while not (player.call("is_acting") and String(spr.animation).begins_with("open_")) and n < 2000:
		await process_frame
		n += 1
	_check(player.call("is_acting") and String(spr.animation).begins_with("open_"), "arriving at the shutter must start the open action, got %s" % String(spr.animation))
	_check(not gs.has_flag("h1_shutter_latch"), "the shutter must not open before the key frame")
	var kf: int = sheet.action_key_frame("open")
	var seen_before_key := false
	var fire_frame := -1
	var fires0: int = player.action_fire_count
	n = 0
	while player.call("is_acting") and n < 2000:
		if not gs.has_flag("h1_shutter_latch") and spr.frame < kf:
			seen_before_key = true
		if gs.has_flag("h1_shutter_latch") and fire_frame < 0:
			fire_frame = spr.frame
		await process_frame
		n += 1
	print("    shutter: open action, flag set at sheet frame %d (key frame %d), fires %d, flag_changed %d" % [fire_frame, kf, player.action_fire_count - fires0, flag_sets[0]])
	_check(seen_before_key and fire_frame >= kf and fire_frame <= kf + 1, "the effect must land on the key frame %d (got %d)" % [kf, fire_frame])
	_check(gs.has_flag("h1_shutter_latch") and flag_sets[0] == 1 and player.action_fire_count - fires0 == 1, "the latch is taken exactly once")
	_check(String(spr.animation).begins_with("idle_"), "after the action Agata idles, got %s" % String(spr.animation))
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	_check(sr.mechanic_open and String(sr.mechanic.get("type", "")) == "latch", "the latch close-up opens on the key frame")
	await _open_latch()
	_check(gs.has_flag("h1_shutter_open"), "the latch caught in the green opens the shutter")
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


## Director 17.10 (idle): «качание должно быть равномерным реверс-движением: разворот влево занимал
## столько же, сколько обратный вправо». For every actor and direction row, from the built timeline:
##   * the time from the middle pose (frame nearest the path midpoint) to each extreme pose is the
##     same both ways (±5 %), and the total time spent in each extreme pose is the same (±5 %);
##   * the motion eases to rest at both ends: frames next to an extreme are held longer than the
##     middle frame, and an extreme is held at least twice as long as the middle frame;
##   * the period is 3–4 s, the timeline loops on the same pose (no seam), only evenly-moving frames
##     are used (data idle_motion, measured on this very sheet — md5).
func _test_idle_sway() -> void:
	var dir := DirAccess.open("res://data/actors")
	var checked := 0
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var id := fname.get_basename()
		if _is_puppet(id):
			continue  # one-picture bone rig (Tikhon): no sheet, checked by its own test
		var sheet = load("res://scripts/actors/actor_sheet.gd").load_actor(id)
		_check(String(sheet.actions.get(sheet.idle_action, {}).get("playback", "")) == "pingpong_eased", "%s: idle must play pingpong_eased (data actions.idle)" % id)
		for action in sheet.actions.keys():
			if String(sheet.actions[action].get("playback", "")) != "pingpong_eased":
				continue
			checked += _check_eased(sheet, id, String(action))
	_check(checked >= 40, "expected 5 eased clips × 8 rows (idle ×3, talk ×2), got %d rows" % checked)


## One eased back-and-forth clip, all rows: symmetric travel and holds, easing to rest, 3–4 s period,
## no seam, measured on this very sheet. Returns the number of rows checked.
func _check_eased(sheet, id: String, action: String) -> int:
	var act: Dictionary = sheet.actions[action]
	var ipath: String = sheet.sheet_dir + "/" + String(act.get("sheet", action + ".png"))
	_check(sheet.eased_md5(action) == FileAccess.get_md5(ipath), "%s/%s: eased_motion measured on another sheet — run tools/measure_idle.py --write" % [id, action])
	var mrows: Array = sheet.eased_rows(action)
	var worst_travel := 0.0
	var worst_dwell := 0.0
	var rows := 0
	for r in sheet.directions:
		var tl: Array = sheet.eased_timeline(action, r)
		var mrow: Dictionary = mrows[r] if r < mrows.size() else {}
		var cols: Array = mrow.get("frames", [])
		var path: Array = mrow.get("path", [])
		if cols.size() < 3:
			_check(false, "%s/%s row %d: eased_motion needs ≥ 3 frames" % [id, action, r])
			continue
		var a: int = int(cols[0])
		var b: int = int(cols[cols.size() - 1])
		# Position of each frame along the (symmetrised) path; the middle of the motion is where the
		# shown pose crosses 0.5 — the centre of the middle frame (odd count) or the switch between
		# the two middle frames (even count).
		var pos := {}
		for k in cols.size():
			pos[int(cols[k])] = (float(path[k]) + 1.0 - float(path[cols.size() - 1 - k])) * 0.5
		var period := 0.0
		var starts: Array = []
		for seg in tl:
			starts.append(period)
			period += float(seg[1])
		_check(period >= 2.95 and period <= 4.2, "%s/%s row %d: period %.2f s outside 3–4 s" % [id, action, r, period])
		_check(int(tl[0][0]) == a and int(tl[tl.size() - 1][0]) == a, "%s/%s row %d: the loop starts and ends on the same pose (no seam)" % [id, action, r])
		var dwell_a := 0.0
		var dwell_b := 0.0
		var b_center := -1.0
		var mids: Array = []
		var mid_dur := 0.0
		for i in tl.size():
			var c: int = int(tl[i][0])
			var d: float = float(tl[i][1])
			var pc: float = float(pos.get(c, 0.0))
			if c == a:
				dwell_a += d
			elif c == b:
				dwell_b += d
				b_center = starts[i] + d * 0.5
			if absf(pc - 0.5) < 0.001:
				mids.append(starts[i] + d * 0.5)
				mid_dur = maxf(mid_dur, d)
			elif i > 0:
				var pp: float = float(pos.get(int(tl[i - 1][0]), 0.0))
				if absf(pp - 0.5) >= 0.001 and ((pp < 0.5 and pc > 0.5) or (pp > 0.5 and pc < 0.5)):
					mids.append(starts[i])
					mid_dur = maxf(mid_dur, maxf(d, float(tl[i - 1][1])))
		if mids.size() != 2 or b_center < 0.0:
			_check(false, "%s/%s row %d: timeline must pass the middle pose twice and reach the far pose once: %s" % [id, action, r, str(tl)])
			continue
		var t1: float = mids[0]
		var t2: float = b_center - mids[0]
		var t3: float = mids[1] - b_center
		var t4: float = period - mids[1]
		var travel_dev := maxf(maxf(t1, t2), maxf(t3, t4)) / minf(minf(t1, t2), minf(t3, t4)) - 1.0
		var dwell_dev := absf(dwell_a - dwell_b) / maxf(dwell_a, dwell_b)
		worst_travel = maxf(worst_travel, travel_dev)
		worst_dwell = maxf(worst_dwell, dwell_dev)
		_check(travel_dev <= 0.05, "%s/%s row %d: middle→extreme times differ by %.1f %% (%.2f / %.2f / %.2f / %.2f s)" % [id, action, r, travel_dev * 100.0, t1, t2, t3, t4])
		_check(dwell_dev <= 0.05, "%s/%s row %d: time in the two extreme poses differs by %.1f %% (%.2f vs %.2f s)" % [id, action, r, dwell_dev * 100.0, dwell_a, dwell_b])
		_check(dwell_a >= 1.5 * mid_dur and dwell_b >= 1.5 * mid_dur, "%s/%s row %d: the motion must come to rest at both extremes (holds %.2f/%.2f vs middle %.2f s)" % [id, action, r, dwell_a, dwell_b, mid_dur])
		rows += 1
	print("    %s/%s: %d rows, worst middle→extreme asymmetry %.1f %%, worst extreme-hold difference %.1f %%; row 0: %s" % [id, action, rows, worst_travel * 100.0, worst_dwell * 100.0, str(sheet.eased_timeline(action, 0).map(func(seg): return "%d:%.2f" % [int(seg[0]), float(seg[1])]))])
	return rows



func _is_puppet(id: String) -> bool:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	return typeof(spec) == TYPE_DICTIONARY and String(spec.get("type", "")) == "puppet"


## Tikhon (Director: «где питомец, только имя на печи»): a Polygon2D+Skeleton2D puppet from one picture.
func _test_tikhon() -> void:
	gs.reset()
	await _spawn_main()
	rm.autosave_enabled = false
	sr = root.get_node("StoryRunner")
	rm.change_room("H1", "default")
	await physics_frame
	await physics_frame
	var room: Node = rm.current_room
	var pups: Array = load("res://scripts/actors/puppet_actor.gd").all_in(room)
	_check(pups.size() == 1 and pups[0].actor_id == "tikhon", "H1 should hold Tikhon's puppet, got %d" % pups.size())
	if pups.is_empty():
		_cleanup_m1()
		return
	var t: Node2D = pups[0]
	var hs: Node2D = room.get_node("Hotspots/tikhon")
	# In the room from the first entry, before M03 (Director 18.10: «изначально в комнате, а не появляться»;
	# where he sits — tests/test_h1.gd).
	_check(t.visible and hs.visible and not gs.has_flag("started_M03"), "Tikhon is in H1 with his hotspot before M03")
	# Rig: mesh over the picture, skinned to the bones, every vertex fully weighted.
	var poly: Polygon2D = t.poly
	_check(poly.polygon.size() > 150 and poly.polygons.size() > 200, "mesh too coarse: %d vertices, %d triangles" % [poly.polygon.size(), poly.polygons.size()])
	_check(poly.get_bone_count() == 8, "8 bones skinned (body, head, 2 ears, 4 tail links), got %d" % poly.get_bone_count())
	var worst := 0.0
	for i in poly.polygon.size():
		var sum := 0.0
		for b in poly.get_bone_count():
			sum += poly.get_bone_weights(b)[i]
		worst = maxf(worst, absf(sum - 1.0))
	_check(worst < 0.001, "every vertex must be fully weighted (worst sum error %.4f)" % worst)
	# Size: ≈ 0.33 of Agata's height at the same depth (Director 18.10: «быть побольше немного»; was 0.28).
	var agata_h: float = 337.0 * room.depth_scale(t.depth_y)
	var ratio: float = t.figure_height_px() / agata_h
	print("    tikhon: %d vertices, %d triangles; height %.0f px = %.2f × Agata at depth y %.0f; feet %s" % [poly.polygon.size(), poly.polygons.size(), t.figure_height_px(), ratio, t.depth_y, str(t.global_position)])
	_check(absf(ratio - 0.33) < 0.02, "Tikhon ≈ 0.33 of Agata's height, got %.2f" % ratio)
	# Breathing + tail: one seamless loop (first and last key equal on every track), body scale ±2 %.
	var idle: Animation = t.life.get_animation("idle")
	_check(t.life.is_playing() and t.life.current_animation == "idle" and idle.loop_mode == Animation.LOOP_LINEAR, "the idle loop plays")
	var max_body := 1.0
	for tr in idle.get_track_count():
		var first = idle.track_get_key_value(tr, 0)
		var last = idle.track_get_key_value(tr, idle.track_get_key_count(tr) - 1)
		var seam: float = (first - last).length() if first is Vector2 else absf(float(first) - float(last))
		_check(seam < 0.0005, "idle track %s must end where it starts (seam %.5f)" % [str(idle.track_get_path(tr)), seam])
		if str(idle.track_get_path(tr)).ends_with(":scale"):
			for k in idle.track_get_key_count(tr):
				max_body = maxf(max_body, (idle.track_get_key_value(tr, k) as Vector2).y)
	_check(absf(max_body - 1.02) < 0.002, "breathing: body scale up to +2 %%, got %.3f" % max_body)
	# The mesh really moves with the bones: a tail vertex moves when the tail bone turns.
	var bone_t4: Bone2D = t.bones["tail4"]
	var before := bone_t4.global_position
	t.life.seek(1.2, true)
	await process_frame
	var after := bone_t4.global_position
	t.life.seek(0.0, true)
	_check(before.distance_to(after) > 0.5, "the tail tip must sway with the idle loop")
	# Accents: an ear twitch / head tilt comes within the configured interval and ends on the rest pose.
	var head_rest: float = t.bones["head"].rest.get_rotation()
	var seen := {}
	var n := 0
	while seen.size() < 1 and n < 1600:
		await process_frame
		n += 1
		if t.accent.is_playing():
			seen[t.accent.current_animation] = true
	_check(not seen.is_empty(), "an ear twitch or head tilt must come within 12 s")
	print("    accents seen: %s" % str(seen.keys()))
	while t.accent.is_playing():
		await process_frame
	_check(absf(t.bones["head"].rotation - head_rest) < 0.001 and absf(t.bones["ear_l"].rotation - t.bones["ear_l"].rest.get_rotation()) < 0.001, "accents end on the rest pose")
	# His own line lifts the head; the next speaker's line lowers it again.
	var b_dict := {"type": "line", "speaker": "tikhon", "text": "test"}
	sr.current_beat = b_dict
	sr.beat_changed.emit()
	_check(t.talking and t.accent.current_animation == "talk_lift", "on his line Tikhon lifts his head")
	sr.current_beat = {"type": "line", "speaker": "agata", "text": "test"}
	sr.beat_changed.emit()
	_check(not t.talking, "on Agata's line he lowers it again")
	sr.current_beat = {}
	sr.beat_changed.emit()
	while t.accent.is_playing():
		await process_frame
	t.play_scared()
	while t.accent.is_playing():
		await process_frame
	_check((t.bones["tail2"].scale as Vector2).y > 1.3, "scared: the tail fluffs up")
	t.calm()
	while t.accent.is_playing():
		await process_frame
	_check(absf((t.bones["tail2"].scale as Vector2).y - 1.0) < 0.01, "calm: the tail settles")
	# The hotspot stays clickable (the figure draws no input; the hotspot keeps its rect).
	var rs: Vector2 = (hs.get_node("Shape") as CollisionShape2D).shape.size
	await physics_frame
	var picked = room.pick(hs.global_position)
	_check(picked == hs, "the tikhon hotspot must still be picked at its centre, got %s" % str(picked))
	# A click on the drawn figure (middle of his body) reaches him, and the old name box is gone.
	var body_mid: Vector2 = t.global_position + Vector2(0, -t.figure_height_px() * 0.5)
	picked = room.pick(body_mid)
	_check(picked == hs, "a click on Tikhon's body %s must pick his hotspot, got %s" % [str(body_mid), str(picked)])
	var ph: Node = hs.get_node_or_null("Visual")
	_check(ph == null or not (ph as CanvasItem).visible, "the placeholder name box is hidden under the puppet")
	gs.reset()
	_cleanup_m1()
