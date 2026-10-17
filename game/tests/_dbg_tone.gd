extends SceneTree
func _initialize() -> void:
	_run()
func _avg(img: Image, r: Rect2i) -> Color:
	var acc := Color(0,0,0,0)
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			acc += img.get_pixel(x, y)
			n += 1
	return acc / n
func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	rm.autosave_enabled = false
	for open in [false, true]:
		gs.reset()
		if open:
			gs.set_flag("h1_shutter_open", true)
		rm.change_room("H1", "", Vector2(1250, 900))
		for i in 30:
			await process_frame
		var player = main_node.get_node("World/Player")
		var spr = player.get("sprite")
		var rl = rm.current_room.get_node("Lighting")
		rl.set_process(false)
		spr.pause()
		for cfg in [[0, Color(1,1,1)], [1, Color(1,1,1)], [0, Color(0.5,0.5,0.5)], [0, Color(0.22,0.22,0.22)]]:
			spr.light_mask = cfg[0]
			spr.self_modulate = cfg[1]
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			print("open=", open, " mask=", cfg[0], " mod=", cfg[1].r, " coat=", _avg(img, Rect2i(1200, 560, 60, 120)), " floor=", _avg(img, Rect2i(1000, 900, 150, 60)))
		rl.set_process(true)
		spr.play()
	quit(0)
