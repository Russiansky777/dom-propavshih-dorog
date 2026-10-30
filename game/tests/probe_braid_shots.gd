extends SceneTree
## Frames of Agata's back walking away, stopping and turning (rendered; needs a display): the braid on its spring.
##   godot --path game -s res://tests/probe_braid_shots.gd -- <out dir>

func _initialize() -> void:
	_run()


func _grab(player: Node2D, out: String, n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var at: Vector2 = root.get_canvas_transform() * player.global_position
	var ppm_s: float = player.view3d.ppm * absf(player.scale.y) * root.get_canvas_transform().get_scale().y
	var r := Rect2i(int(at.x - 0.45 * ppm_s), int(at.y - 1.75 * ppm_s), int(0.9 * ppm_s), int(0.95 * ppm_s))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png("%s/b_%03d.png" % [out, n])


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
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
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("Z2", "default", Vector2(900, 1000))
	for i in 40:
		await process_frame
	player.yaw3d = PI
	player.yaw3d_target = PI
	for i in 30:
		await process_frame
	var n := 0
	player.click_at(player.global_position + Vector2(-60, -200))
	for i in 150:
		if i % 3 == 0:
			await _grab(player, out, n)
			n += 1
		else:
			await process_frame
		if i == 110:
			player.face_towards(player.global_position + Vector2(300, -60))
	PS.forced_render = ""
	quit(0)
