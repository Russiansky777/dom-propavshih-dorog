extends SceneTree
## T8 frames from the real game (needs a display — tools/shots_t8.sh): a start point, extra flags, a room.
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_t8.gd \
##     -- <out_dir> "name|start|ROOM[:x,y]|flag1,flag2"
## For every spec: RoomManager.start_at(start) (the state after its block), the extra flags, the room;
## Agata walks to (x, y) if given; the frame is saved as <out_dir>/<name>.png (1920x1080).


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var specs: Array = args.slice(1)
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spec in specs:
		var parts := String(spec).split("|")
		var room_xy := parts[2].split(":")
		rm.start_at(parts[1])
		for i in 4:
			await physics_frame
		for f in (parts[3] if parts.size() > 3 else "").split(",", false):
			if f.begins_with("-"):
				gs.set_flag(f.substr(1), false)
			else:
				gs.set_flag(f, true)
		rm.change_room(room_xy[0], "default")
		for i in 10:
			await physics_frame
		if room_xy.size() > 1:
			var xy := room_xy[1].split(",")
			player.call("walk_to", Vector2(float(xy[0]), float(xy[1])))
			var frames := 0
			while player.call("is_walking") and frames < 1500:
				await physics_frame
				frames += 1
		for i in 120:
			await process_frame
		root.warp_mouse(Vector2(4, 1076))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		var path := out_dir.path_join("%s.png" % parts[0])
		img.save_png(path)
		print("t8 frame %s → %s" % [parts[0], path])
	quit(0)
