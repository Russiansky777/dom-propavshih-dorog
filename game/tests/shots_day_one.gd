extends SceneTree
## Evidence frames for day one by the final scenario (block 1, 22.10) — not a test (needs a display;
## tools/shots_day_one.sh runs it under Xvfb with the OpenGL renderer): Docs/evidence/M1/day1/*.png from the real game.
##   H2: the bundle «Нина. Горница» and the brace with the plate drawing (art batch 2); the unwrapped mirror, the brace taken;
##   O1: the teacher's drawer close-up (photo, Ilya's drawing, the plan with the game's text), the plan read in the
##       dialogue over it; «Мама, я иду» on the board (stand-in text);
##   H1: the night by the stove — dusk, the first line; the bag with the new items.

var _out := ""
var gs: Node
var rm: Node
var sr: Node
var main_node: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1/day1")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	var path := _out.path_join("%s.png" % name)
	img.save_png(path)
	print("day1 frame %s → %s" % [name, path])


func _state(flags: Array, items: Array) -> void:
	sr.call("_on_state_reset")
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	for it in items:
		gs.add_item(String(it))
		gs.set_flag("has_" + String(it), true)


func _go(room: String, spawn: String = "default", pos: Vector2 = Vector2.INF) -> void:
	if pos == Vector2.INF:
		rm.change_room(room, spawn)
	else:
		rm.change_room(room, spawn, pos)
	for i in 10:
		await physics_frame
	await _frames(20)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(5)
	rm.autosave_enabled = false
	rm.checkpoint_prefix = "shots_day1_"
	var base := ["done_M01", "met_tamara", "done_M02", "house_unlocked", "done_M03", "house_open", "met_tikhon", "stove_lit",
		"h1_shutter_open", "h1_scarf_removed"]
	# H2: bundle + brace (art batch 2)
	_state(base, ["pocket_watch", "mitten"])
	await _go("H2", "", Vector2(1250, 705))
	sr.call("_on_state_reset")
	await _frames(10)
	await _shot("day1_H2_bundle_skoba")
	# H2: unwrapped mirror, the brace taken; the bag with the new items
	_state(base + ["h2_bundle_unwrapped", "knows_crossing_plan"], ["pocket_watch", "mitten", "photo_bridge", "drawing_ilya", "plan_crossing", "brace_plate"])
	await _go("H2", "", Vector2(1250, 705))
	sr.call("_on_state_reset")
	await _frames(10)
	await _shot("day1_H2_mirror_bag")
	# O1: the drawer close-up
	var o1 := base + ["done_M04", "seen_school_door", "seen_workshop", "seen_bell", "done_M05", "door_school_installed", "done_M06",
		"seen_class_traces", "o1_saw_winter"]
	_state(o1, ["pocket_watch", "mitten"])
	await _go("O1", "", Vector2(720, 780))
	sr.call("_on_state_reset")
	await _frames(5)
	var drawer: Node = rm.current_room.get_node("Hotspots/teacher_drawer")
	sr.interact(drawer)
	await _frames(30)
	await _shot("day1_O1_drawer_text")
	var guard := 0
	while not sr.current_beat.is_empty() and not String(sr.current_beat.get("text", "")).begins_with("«Тому") and guard < 30:
		guard += 1
		sr.advance()
		await _frames(8)
	await _frames(20)
	await _shot("day1_O1_drawer_plan_line")
	while not sr.current_beat.is_empty() and guard < 60:
		guard += 1
		sr.advance()
		await _frames(4)
	await _frames(20)
	await _shot("day1_O1_drawer_closeup")
	sr.close_view()
	# O1: «Мама, я иду»
	_state(o1 + ["done_M07", "board_mama"], ["pocket_watch"])
	await _go("O1", "", Vector2(1760, 740))
	sr.call("_on_state_reset")
	await _frames(10)
	await _shot("day1_O1_board_mama")
	# H1: the night by the stove — the first line over the dusk
	_state(o1 + ["done_M07", "knows_crossing_plan", "done_M08", "observed_path_loop"], ["pocket_watch", "photo_bridge", "drawing_ilya", "plan_crossing"])
	await _go("O1", "", Vector2(1760, 740))
	sr.call("_on_state_reset")
	rm.change_room("H3", "from_O1")
	guard = 0
	while sr.call("is_staging") and guard < 2000:
		guard += 1
		await process_frame
	await _frames(30)
	await _shot("day1_H1_night")
	for s in ["shots_day1_day2"]:
		gs.delete_save(s)
	quit(0)
