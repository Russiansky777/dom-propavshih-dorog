extends SceneTree
## Frames of short moves from standing (Director 01.11, line 3 «мельтешит… куча перестановок ног»): the whole figure every
## 4th frame for 1.5 s after the click, the «переступ» on or off (needs a display).
##   godot --path game -s res://tests/probe_shuffle_shots.gd -- <out dir> <0|1 shuffle>

var anchor := Vector2.ZERO


func _initialize() -> void:
	_run()


func _grab(out: String, tag: String, n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var at: Vector2 = root.get_canvas_transform() * anchor
	var r := Rect2i(int(at.x) - 200, int(at.y) - 420, 400, 470).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
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
	player.shuffle_on = args[1] == "1"
	var cases := [["side30", 0.3, 90], ["back25", 0.25, 180], ["fwd30", 0.3, 0]]
	if args.size() > 2:
		cases = cases.slice(0, int(args[2]))
	for c in cases:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
			gs.set_flag(f, true)
		rm.change_room("H1", "default", Vector2(1100, 960))
		for i in 6:
			await process_frame
		player.seed_motion(1031)
		player.view3d.seed_idle(61)
		var face := PI * 0.5
		player.yaw3d = face
		player.yaw3d_target = face
		for i in 40:
			await process_frame
		var ang := face + deg_to_rad(float(c[2]))
		var v: Actor3D = player.view3d
		var target: Vector2 = player.global_position + Vector2(sin(ang), cos(ang) * player.floor_foreshortening()) * float(c[1]) * v.ppm * absf(player.scale.y)
		anchor = (player.global_position + target) * 0.5
		player.click_at(target)
		var n := 0
		for i in 84:
			if i % 4 == 0:
				await _grab(out, String(c[0]), n)
				n += 1
			else:
				await process_frame
	PS.forced_render = ""
	quit(0)
