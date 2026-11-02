extends SceneTree
## Frames of the skirt and the legs walking on the spot (Director 01.11, line 3: «ноги… будто 2 не связанных с юбкой
## ботинка сами шагают, а при шагании ноги выпирают будто штаны из-под юбки, а сама юбка не двигается»; «низ юбки до колен
## её колбасит при окончании движения»): the live figure alone (Actor3D, no room), walking at full weight, then stopping;
## the lower half every 3rd frame from the side, 3/4 and front. Needs a display.
##   godot --path game -s res://tests/probe_skirt_frames.gd -- <out dir> [scene res path] [key=value rt3d.skirt overrides]

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	for a in args.slice(1):
		if String(a).begins_with("res://"):
			spec["rt3d"]["scene"] = a
		elif String(a).contains("="):
			var kv := String(a).split("=")
			spec["rt3d"]["skirt"][kv[0]] = float(kv[1])
	var views := [["side", 90.0], ["q34", 45.0], ["front", 0.0]]
	if OS.get_environment("VIEWS") != "":
		views = views.slice(0, int(OS.get_environment("VIEWS")))
	for view in views:
		var v := Actor3D.new()
		root.add_child(v)
		if not v.setup(spec):
			push_error("setup: " + v.load_error)
			quit(1)
			return
		v.set_render_scale(2.0)
		v.set_yaw(deg_to_rad(float(view[1])))
		var ph := 0.0
		var n := 0
		var d := 1.0 / 60.0
		# stand, walk 2.5 s, stop (weight down over 0.4 s), stand 1 s
		for i in 270:
			var w := 0.0
			if i >= 20 and i < 170:
				w = clampf((i - 20) / 20.0, 0.0, 1.0)
			elif i >= 170 and i < 194:
				w = 1.0 - (i - 170) / 24.0
			if w > 0.0:
				ph += d * (0.55 + 0.45 * w) / maxf(v.walk_len, 0.01)
			v.pose(d, fposmod(ph, 1.0), w, 0.0)
			await process_frame
			if (i >= 125 and i < 170 and i % 3 == 0) or (i >= 170 and i < 260 and i % 6 == 0):
				await RenderingServer.frame_post_draw
				var img := v.get_texture().get_image()
				var sz := img.get_size()
				img.get_region(Rect2i(0, int(sz.y * 0.45), sz.x, int(sz.y * 0.55))).save_png("%s/%s_%03d.png" % [out, view[0], n])
				n += 1
		v.queue_free()
		await process_frame
	quit(0)
