extends SceneTree
## Evidence frames for items and choices (not a test; needs a display — tools/shots_items.sh runs it under
## Xvfb with the OpenGL renderer): Docs/evidence/M1/items_*.png from the real game (Main.tscn).
##   Z1: Agata walks to a click into the counter's corners and stops beside them (her body clear of it);
##   Z2: the locked front door names the key; the key on the door — unlock text;
##   H1: the photo on the stove ledge and the two cups on the sill before V01; «На столе» + blue cup;
##       «На полке» + white cup;
##   O1: the chalk on a pupil's desk (hover caption), the teacher's desk without chalk; the pencil mark (V03).

var _out := ""
var gs: Node
var rm: Node
var sr: Node
var main_node: Node
var player: Node2D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
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
	var path := _out.path_join("items_%s.png" % name)
	img.save_png(path)
	print("items frame %s → %s" % [name, path])


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
	sr.call("_on_state_reset")
	await _frames(20)


func _walk(to: Vector2) -> void:
	player.call("walk_to", to)
	var n := 0
	while player.call("is_walking") and n < 1500:
		await physics_frame
		n += 1
	await _frames(30)


func _hover_off() -> void:
	var hover: Node = main_node.find_child("Hover", true, false)
	if hover is CanvasItem:
		(hover as CanvasItem).visible = false


func _choose(hotspot: String, option: String) -> void:
	var h: Node = rm.current_room.get_node("Hotspots/" + hotspot)
	sr.interact(h)
	await _frames(3)
	sr.choose(option)
	await _frames(8)


func _drain() -> void:
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 30:
		guard += 1
		sr.advance()
		await _frames(2)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	player.set("speed_factor", 4.0)
	DirAccess.make_dir_recursive_absolute(_out)
	var base := ["done_M01", "met_tamara", "knows_pier_trace"]

	# Z1: corners of the counter.
	_state(base, ["key_house", "pocket_watch", "mitten"])
	await _go("Z1", "default", Vector2(250, 900))
	await _walk(Vector2(600, 880))      # click into the left front corner
	_hover_off()
	await _shot("Z1_corner_left_front")
	await _walk(Vector2(400, 760))
	await _walk(Vector2(600, 732))      # left back corner
	await _shot("Z1_corner_left_back")
	await _go("Z1", "default", Vector2(1700, 820))
	await _walk(Vector2(1430, 880))     # right front corner
	await _shot("Z1_corner_right_front")

	# Z2: locked door, then the key.
	_state(base, ["key_house", "pocket_watch", "mitten"])
	await _go("Z2", "default", Vector2(1000, 700))
	var e: Node = rm.current_room.get_node("Exits/to_H1")
	sr.use_exit(e)
	await _frames(20)
	await _shot("Z2_door_locked")
	await _drain()
	sr.select_item("key_house")
	await _frames(5)
	await _shot("Z2_key_in_hand")
	sr.use_exit(e)
	await _frames(20)
	await _shot("Z2_door_unlocked")
	await _drain()
	await _frames(40)

	# H1: V01 before and after.
	var h1 := base + ["done_M02", "house_unlocked", "done_M03", "started_M03", "met_tikhon", "house_open", "stove_lit",
		"h1_shutter_open", "h1_scarf_removed"]
	_state(h1, ["pocket_watch", "mitten"])
	await _go("H1", "default", Vector2(1250, 960))
	_hover_off()
	await _shot("H1_before_choice")
	await _choose("photo", "table")
	await _shot("H1_photo_table_reaction")
	await _drain()
	await _choose("cups", "blue")
	await _drain()
	await _frames(10)
	await _shot("H1_photo_table_cup_blue")
	await _choose("photo", "shelf")
	await _drain()
	await _choose("cups", "white")
	await _drain()
	await _frames(10)
	await _shot("H1_photo_shelf_cup_white")

	# O1: the chalk on the desk, the mark.
	var o1 := h1 + ["done_M04", "seen_school_door", "done_M05", "door_school_installed", "done_M06", "seen_class_traces"]
	_state(o1, ["pocket_watch", "photo_bridge", "drawing_ilya", "plan_crossing"])
	await _go("O1", "default", Vector2(1100, 790))
	_hover_off()
	await _shot("O1_chalk_on_desk")
	await _choose("bird_drawing", "mark")
	await _drain()
	await _frames(10)
	await _shot("O1_bird_mark")
	gs.reset()
	quit(0)
