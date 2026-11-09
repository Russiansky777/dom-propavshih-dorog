extends SceneTree
## Frames as the player sees them (Director 09.11, 12:35: «Тамара развернута к нам… Павел на финале тоже развернут
## непонятно как, Пелагея тоже»): each frame shown in FrameView from a start point's state (data/story/start_points.json),
## a shot after `wait` s (live figures settled, clips playing). One JPG per frame + their sheet for the Director.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_frames.gd -- \
##       <out_dir> <start_point> <frame,frame,…> [wait_s=2.5] [flags,…]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var rm = root.get_node("RoomManager"); var sr = root.get_node("StoryRunner"); var gs = root.get_node("GameState")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var sp: String = a[1]
	var frames: PackedStringArray = a[2].split(",")
	var wait := float(a[3]) if a.size() > 3 else 2.5
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_at(sp)
	if a.size() > 4 and a[4] != "":
		for f in a[4].split(","):
			gs.set_flag(f, true)
	for i in 20:
		await process_frame
	for fid in frames:
		sr.set_frame(fid, false)
		await create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [out, fid], 0.88)
		print("shot ", fid)
		sr.set_frame("", false)
		await create_timer(0.3).timeout
	quit(0)
