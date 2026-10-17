extends SceneTree
## Evidence frames of the ambient layer («Живой мир»): not a test, needs a display (OpenGL under Xvfb):
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --display-driver x11 \
##     --rendering-driver opengl3 --resolution 1920x1080 -s res://tests/shots_ambient.gd -- <plan.json> <out_dir>
## plan.json: [{"name": "z2_rain", "room": "Z2", "spawn": "default", "pos": [x, y] (optional),
##              "walk": [x, y] (optional, Agata walks there while frames are taken),
##              "wait": s before the first frame, "frames": N, "dt": s between frames,
##              "flags": [flags to set first], "ambient": true|false,
##              "step_frames": k (capture every k-th frame; run with --fixed-fps F for even steps)}]
## Frames: <out_dir>/<name>_NN.png (1920x1080). GIFs are assembled outside (Python/PIL).
## Prints a line per frame with the ambient stats (splashes, prints) for the log.

var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <plan.json> <out_dir>")
		quit(2)
		return
	_out = args[1]
	var f := FileAccess.open(args[0], FileAccess.READ)
	var plan = JSON.parse_string(f.get_as_text())
	_run(plan)


func _run(plan: Array) -> void:
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
	DirAccess.make_dir_recursive_absolute(_out)
	var builder = load("res://scripts/ambient/ambient_builder.gd")
	for shot in plan:
		builder.enabled = bool(shot.get("ambient", true))
		for fl in shot.get("flags", []):
			gs.set_flag(String(fl), true)
		rm.change_room(String(shot["room"]), String(shot.get("spawn", "default")))
		if shot.has("pos"):
			player.call("enter_room", rm.current_room, Vector2(float(shot["pos"][0]), float(shot["pos"][1])))
		root.get_viewport().warp_mouse(Vector2(1919, 100))  # no hover caption in the frames
		var hover: Node = main_node.find_child("Hover", true, false)
		if hover is CanvasItem:
			(hover as CanvasItem).visible = false
		for i in 6:
			await physics_frame
		if shot.has("walk"):
			player.call("walk_to", Vector2(float(shot["walk"][0]), float(shot["walk"][1])))
		await create_timer(float(shot.get("wait", 0.5))).timeout
		var n := int(shot.get("frames", 1))
		var dt := float(shot.get("dt", 0.1))
		for k in n:
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			if img.get_width() != 1920:
				img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
			var path := _out.path_join("%s_%02d.png" % [String(shot["name"]), k])
			img.save_png(path)
			var amb = builder.of(rm.current_room)
			var last := ""
			if amb != null and amb.footfall != null and not amb.footfall.events.is_empty():
				var e: Dictionary = amb.footfall.events[-1]
				last = " last step: frame %d at %s on '%s' scale %.2f" % [e["frame"], str(e["pos"].round()), e["surface"], e["scale"]]
			print("ambient frame %s: %s%s" % [path, str(amb.stats()) if amb != null else "no ambient", last])
			if k < n - 1:
				if shot.has("step_frames"):
					# With --fixed-fps F every rendered frame is 1/F s of game and shader time.
					for j in int(shot["step_frames"]) - 1:
						await process_frame
				else:
					await create_timer(dt).timeout
	gs.reset()
	quit(0)
