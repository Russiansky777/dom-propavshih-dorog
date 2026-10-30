extends SceneTree
## Frames of Agata's feet stopping and turning on the spot (rendered; needs a display): rows of crops around the feet
## every 3rd frame, with the foot locks on and off, into `out` (PNG per frame + list).
##   godot --path game -s res://tests/probe_feet_shots.gd -- <out dir> <0|1 locks> [k]

func _initialize() -> void:
	_run()


var anchor := Vector2.ZERO   # the crop stays on one spot of the floor: a sliding foot is seen against it


func _grab(player: Node2D, out: String, tag: String, n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var vp := root.get_canvas_transform()
	var at: Vector2 = vp * anchor
	var r := Rect2i(int(at.x) - 160, int(at.y) - 230, 320, 280)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png("%s/%s_%03d.png" % [out, tag, n])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	player.foot_lock_3d = args[1] == "1"
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	var k: int = int(args[2]) if args.size() > 2 else 2
	rm.change_room("Z2", "default", Vector2(700 + (k % 3) * 200, 850 + (k % 2) * 100))
	for i in 30:
		await process_frame
	var ang: float = k * 0.6
	player.yaw3d = ang
	player.yaw3d_target = ang
	for i in 30:
		await process_frame
	var goal: Vector2 = player.global_position + Vector2(sin(ang), cos(ang) * player.floor_foreshortening()) * 380.0
	player.click_at(goal)
	anchor = goal
	var n := 0
	var after := 0
	while player.is_walking() or after < 40:
		if not player.is_walking():
			after += 1
		if player.walk_w < 0.99 or not player.is_walking():
			if Engine.get_process_frames() % 3 == 0:
				await _grab(player, out, "stop", n)
				n += 1
				continue
		await process_frame
	player.face_towards(player.global_position + Vector2(sin(ang + 2.6), cos(ang + 2.6) * player.floor_foreshortening()) * 200.0)
	n = 0
	anchor = player.global_position
	for i in 72:
		if i % 3 == 0:
			await _grab(player, out, "turn", n)
			n += 1
		else:
			await process_frame
	PS.forced_render = ""
	quit(0)
