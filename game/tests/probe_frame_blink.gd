extends SceneTree
## A frame as the player sees it, measured every rendered frame (Director 09.11, 21:58: «по эпилогу — почему экран
## „моргает“ постоянно в последней сцене? такого быть не должно»): the start point's state, the frame shown, for `secs`
## seconds — the mean brightness of the screen (64×36) per frame and the biggest jumps between neighbours, with the
## clip playing and its position. Shots of the frames around the biggest jump go to <out>.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 30 \
##       -s res://tests/probe_frame_blink.gd -- <out_dir> <start_point> <frame> [secs=24] [flags,…]


func _initialize() -> void:
	_run()


func _mean(img: Image) -> float:
	img.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	for y in 36:
		for x in 64:
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return s / (64.0 * 36.0) * 255.0


func _video() -> Node:
	for n in root.find_children("*", "VideoStreamPlayer", true, false):
		return n
	return null


func _run() -> void:
	await process_frame
	var rm = root.get_node("RoomManager"); var sr = root.get_node("StoryRunner"); var gs = root.get_node("GameState")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var sp: String = a[1]
	var fid: String = a[2]
	var secs := float(a[3]) if a.size() > 3 else 24.0
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
	sr.set_frame(fid, false)
	var nf := 0
	var means: Array = []
	var info: Array = []
	var imgs: Array = []
	while nf < int(secs * 30.0):
		nf += 1
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		var v = _video()
		var clip := ""
		var pos := -1.0
		if v != null and v is VideoStreamPlayer:
			clip = String((v as VideoStreamPlayer).stream.resource_path).get_file() if (v as VideoStreamPlayer).stream else "-"
			pos = (v as VideoStreamPlayer).stream_position
		var small := img.duplicate()
		imgs.append(small)
		if imgs.size() > 6:
			imgs.pop_front()
		means.append(_mean(img))
		info.append("%.2f %s %.2f" % [nf / 30.0, clip, pos])
		if nf > 150 and means.size() >= 2 and absf(float(means[-1]) - float(means[-2])) > 0.8:
			print("JUMP %.2f → %.2f at %s (prev %s)" % [means[-2], means[-1], info[-1], info[-2]])
			for k in imgs.size():
				(imgs[k] as Image).save_jpg("%s/jump_%d_%d.jpg" % [out, means.size(), k], 0.8)
	var steps: Array = []
	for i in range(151, means.size()):
		steps.append(absf(float(means[i]) - float(means[i - 1])))
	steps.sort()
	print("frames %d, mean %.1f, step p50 %.3f p95 %.3f max %.3f" % [means.size(), means.reduce(func(x, y): return x + y, 0.0) / means.size(), steps[steps.size() / 2], steps[int(steps.size() * 0.95)], steps[-1]])
	quit(0)
