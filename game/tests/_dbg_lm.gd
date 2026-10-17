extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	rm.autosave_enabled = false
	gs.set_flag("stove_lit", true)
	rm.change_room("H1", "", Vector2(1000, 800))
	for i in 20:
		await process_frame
	var rl = rm.current_room.get_node("Lighting")
	print("param=", rl.receive_material.get_shader_parameter("light_map"), " vp=", rl.light_map, " size=", rl.light_map.size)
	await RenderingServer.frame_post_draw
	var img: Image = rl.light_map.get_texture().get_image()
	print("lm img ", img.get_size(), " px(200,200)=", img.get_pixel(200, 200), " px(50,120)=", img.get_pixel(50, 120), " fmt=", img.get_format())
	img.save_png("/tmp/claude-0/-home-claude/7278ba96-293b-533c-8b27-258ab2726771/scratchpad/lm.png")
	print("bg mat=", rm.current_room.get_node("Background/Image").material)
	quit(0)
