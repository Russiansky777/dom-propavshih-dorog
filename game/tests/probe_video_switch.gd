extends SceneTree
## What the screen shows in the frames right after the dinner's clip changes (Director 09.11, 21:58 / 22:32: «экран
## моргает… микросекунда с полностью чёрным экраном, целиком»): the frame shown, the clip switched by hand
## (FrameVideo._next), every rendered frame after it measured (mean brightness, share of near-black pixels) and saved.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tests/probe_video_switch.gd -- <out_dir> [frames_after=6]


func _initialize() -> void:
	_run()


func _measure(img: Image) -> Array:
	var small: Image = img.duplicate()
	small.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	var dark := 0
	for y in 54:
		for x in 96:
			var c := small.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			s += l
			if l < 0.02:
				dark += 1
	return [s / (96.0 * 54.0) * 255.0, float(dark) / (96.0 * 54.0)]


func _run() -> void:
	await process_frame
	var rm = root.get_node("RoomManager"); var sr = root.get_node("StoryRunner"); var gs = root.get_node("GameState")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var after := int(a[1]) if a.size() > 1 else 6
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_at("epilogue")
	gs.set_flag("v01_cup_blue", true)
	for i in 20:
		await process_frame
	sr.set_frame("EP_dinner", false)
	var v: VideoStreamPlayer = null
	for i in 600:
		await process_frame
		for vn in root.find_children("*", "VideoStreamPlayer", true, false):
			v = vn
		if v != null and i > 120:
			break
	if v == null:
		print("no player")
		quit(1)
		return
	print("player %s files %s playing %s pos %.2f material %s" % [v.get_path(), v.get("files"), v.is_playing(), v.stream_position, v.material])
	await RenderingServer.frame_post_draw
	var before: Image = root.get_viewport().get_texture().get_image()
	print("before: %s" % [_measure(before)])
	before.save_jpg(out + "/sw_before.jpg", 0.85)
	# the natural end of the clip: seek close to it and watch every frame through the change
	v.stream_position = 9.6
	var last_clip := String(v.stream.resource_path).get_file()
	var seen := 0
	var n := 0
	while n < 400 and seen < after:
		n += 1
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		var clip := String(v.stream.resource_path).get_file()
		if clip != last_clip or seen > 0:
			var m := _measure(img)
			var ti: Image = v.get_video_texture().get_image()
			print("frame %d (+%d after change): mean %.2f dark %.3f clip %s pos %.3f tex_alpha %.2f playing %s" % [n, seen, m[0], m[1], clip, v.stream_position, ti.get_pixel(ti.get_width() / 2, ti.get_height() / 2).a, v.is_playing()])
			img.save_jpg("%s/nat_%d.jpg" % [out, seen], 0.85)
			seen += 1
		elif n % 10 == 0:
			var m2 := _measure(img)
			print("frame %d: mean %.2f clip %s pos %.3f" % [n, m2[0], clip, v.stream_position])
		last_clip = clip if seen == 0 else last_clip
	quit(0)
