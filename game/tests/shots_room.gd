extends SceneTree
## A clean frame of a room in the real game (not a test; needs a display — tools/shots_room.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_room.gd \
##     -- <out_dir> Z4:1300,860
## For every ROOM[:x,y] the game (Main.tscn, with the room's lights and ambient layer) enters the room,
## Agata walks from the default spawn to (x, y), the scene runs a couple of seconds (drizzle, sway,
## lantern flicker) and the frame is saved as <out_dir>/real_<ROOM>.png (1920x1080).


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
	var specs: Array = args.slice(1) if args.size() > 1 else ["Z4:1300,860"]
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
	var made := 0
	for spec in specs:
		var parts := String(spec).split(":")
		var rid := parts[0]
		gs.set_flag("done_M01", true)
		rm.change_room(rid, "default")
		for i in 10:
			await physics_frame
		if parts.size() > 1:
			var xy := parts[1].split(",")
			player.call("walk_to", Vector2(float(xy[0]), float(xy[1])))
			var frames := 0
			while player.call("is_walking") and frames < 1500:
				await physics_frame
				frames += 1
		for i in 150:
			await process_frame
		# The X cursor sits mid-screen (over the far exit in Z4): move it to a bare corner so no hover
		# caption is in the frame.
		root.warp_mouse(Vector2(4, 1076))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		var path := out_dir.path_join("real_%s.png" % rid)
		img.save_png(path)
		made += 1
		print("room frame %s: Agata at %s → %s" % [rid, str(player.global_position.round()), path])
	gs.reset()
	quit(0 if made > 0 else 1)
