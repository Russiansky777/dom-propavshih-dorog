extends SceneTree
## 08.11 (Director, 21:57–23:26: «из статичных кадров с объятиями сделаем видео… луп… фейд 2 секунды»): a painted
## frame alive — data `background.video` (Ogg Theora loop made by tools/video_loop.py from the fal.ai clip).
##   FV-1 the frame F_hug_pelageya builds with a Video player over the picture: the stream loads, loops, is silent,
##        covers the picture exactly (1920 wide, the picture's height and place) and ignores the mouse; the picture
##        stays under it; self-check — a frame without the key has no player;
##   FV-2 it plays: the stream position advances over real frames (x11, not headless) and wraps round (the loop);
##   FV-3 the loop's first and last frames agree (tools/video_loop.py: seam blended into the first frame) — measured
##        on the game's own OGV via the player's texture: the last frame against the first ≤ 8/255 mean; the
##        picture's snow effect is off (the snow falls in the video);
##   FV-4 the scene leaves the hug frame with a 2-second fade (E3 M18 staging), both hug frames' exits ≥ 2 s where
##        a video exists.
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/test_frame_video.gd

var fails := 0
var passes := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL  " + what)


func _run() -> void:
	await process_frame
	var sd = root.get_node("StoryData")
	var gs = root.get_node("GameState")
	var sr = root.get_node("StoryRunner")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 3:
		await process_frame
	for fid in ["F_hug_pelageya", "F_hug_nina"]:
		await _frame(fid, sd, sr, main_node)
	# FV-5: the dinner (09.11) — the clip follows the player's choices; the people and the cup are inside it, so their
	# layers go; a variant without a clip yet falls back to the painting with its layers
	var fv = main_node.find_child("FrameView", true, false)
	var cases := [
		[["v01_cup_blue"], ["closed_blue_a"], ["agata", "family_closed", "cup_blue", "tikhon"]],
		[["v01_cup_white"], ["closed_white_a", "closed_white_b"], ["agata", "family_closed", "cup_white", "tikhon"]],
		[["ep_ulyana_came", "v01_cup_blue"], ["open_blue_a", "open_blue_b"], ["agata", "family", "cup_blue", "tikhon"]],
		[["ep_ulyana_came", "v01_cup_white"], ["open_white_a", "open_white_b"], ["agata", "family", "cup_white", "tikhon"]],
	]
	for c in cases:
		gs.reset()
		for f in c[0]:
			gs.set_flag(String(f), true)
		sr.set_frame("EP_dinner", false)
		for i in 3:
			await process_frame
		var room = fv.room
		var v = room.get_node_or_null("Background/Video") if room != null else null
		var names: Array = []
		if v != null:
			for f in v.files:
				names.append(String(f).get_file().get_basename())
		var want: Array = c[1]
		var same := names.size() == want.size()
		for n in want:
			same = same and names.has(n)
		_check(v != null and same, "FV-5 flags %s → clips %s, got %s" % [c[0], want, names])
		var layers: Node = room.get_node_or_null("Layers") if room != null else null
		for lid in c[2]:
			_check(layers == null or layers.get_node_or_null(NodePath(String(lid))) == null, "FV-5 layer %s drawn over the video (it is inside the clip)" % lid)
		# two clips take turns: the next one is never the one that just played
		if v != null and v.files.size() == 2:
			var first := String(v.stream.resource_path)
			v.call("_next")
			await process_frame
			_check(String(v.stream.resource_path) != first and v.is_playing(), "FV-5 the next clip repeats %s" % first)
			_check(not v.loop, "FV-5 two clips but the player loops one")
		var out5 := OS.get_environment("FV_OUT")
		if out5 != "" and want[0] == "open_blue_a":
			for i in 150:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png(out5.path_join("frame_video_ingame_EP_dinner.png"))
		sr.set_frame("", false)
		await process_frame
	gs.reset()
	# a frame whose variant has no clip falls back to the painting with its layers (FrameVideo.pick → [])
	var empty: Array = load("res://scripts/rooms/frame_video.gd").pick({"videos": [{"if": ["no_such_flag_ever"], "files": ["res://assets/rooms/EP_dinner/open_blue_a.ogv"]}]})
	_check(empty.is_empty(), "FV-5 a variant whose flags do not hold still picks a clip (%s)" % [empty])
	sr.set_frame("", false)
	await process_frame
	gs.reset()
	# FV-4: the staging's exit fade (both hug scenes)
	for sid in ["M18", "M19"]:
		var sc: Dictionary = sd.scene(sid)
		var fade := 0.0
		for st in sc.get("stage", []):
			if st.get("frame", "x") == "":
				fade = float(st.get("fade_out_s", 0.0))
		_check(fade >= 2.0, "FV-4 %s leaves the hug frame with a %.1f s fade (≥ 2)" % [sid, fade])
	print("==== frame video: %d tests, %d passed, %d failed ====" % [passes + fails, passes, fails])
	quit(1 if fails > 0 else 0)


func _frame(fid: String, sd, sr, main_node) -> void:
	print("  -- %s" % fid)
	var spec: Dictionary = sd.room(fid)
	var video := String(spec.get("background", {}).get("video", ""))
	_check(video != "" and ResourceLoader.exists(video), "FV-1 %s has no background.video (%s)" % [fid, video])
	sr.set_frame(fid, false)
	for i in 3:
		await process_frame
	var fv = main_node.find_child("FrameView", true, false)
	var room = fv.room if fv != null else null
	_check(room != null, "FV-1 the frame did not open in FrameView")
	if room == null:
		return
	var v: VideoStreamPlayer = room.get_node_or_null("Background/Video")
	var img: Sprite2D = room.get_node_or_null("Background/Image")
	_check(v != null and img != null, "FV-1 no Video player / Image under the frame's background")
	if v != null and img != null:
		_check(v.stream != null and v.loop and v.is_playing() and v.volume_db <= -60.0, "FV-1 stream %s loop %s playing %s volume %s" % [v.stream, v.loop, v.is_playing(), v.volume_db])
		_check(v.mouse_filter == Control.MOUSE_FILTER_IGNORE, "FV-1 the player takes the mouse")
		var pic_h := roundf(img.texture.get_size().y * room.art_scale)
		_check(v.position == img.position and v.size == Vector2(1920.0, pic_h), "FV-1 player at %s size %s; picture at %s height %.0f" % [v.position, v.size, img.position, pic_h])
		_check(v.get_index() > img.get_index(), "FV-1 the video is under the picture")
		# Director 08.11, 23:47 «фонарь не живой здесь»: the lantern's glow (data/story/lights, a flickering source) draws
		# above the video — the Lighting node comes after the background and keeps its source
		var lighting = room.get_node_or_null("Lighting")
		if fid == "F_hug_pelageya":
			_check(lighting != null and lighting.sources.size() >= 1 and lighting.get_index() > room.get_node("Background").get_index(), "FV-1 no flickering lantern source above the video (Lighting %s)" % lighting)
	_check(spec.get("effects", []).filter(func(e): return e.get("type") == "snow").is_empty(), "FV-3 the frame still has its own snow effect over the video's snow")
	# FV-2: it plays and wraps
	var p0 := -1.0
	var wrapped := false
	var advanced := false
	if v != null:
		var t := 0.0
		var last := -1.0
		while t < 13.0:
			await process_frame
			t += 1.0 / 60.0
			var p: float = v.stream_position
			if p0 < 0.0 and p > 0.0:
				p0 = p
			if last >= 0.0 and p > last + 0.01:
				advanced = true
			if last >= 0.0 and p < last - 1.0:
				wrapped = true
			last = p
			if wrapped and advanced:
				break
		_check(advanced, "FV-2 the stream position never advanced (headless? x11 needed)")
		_check(wrapped, "FV-2 the video did not wrap round in 13 s (loop)")
		# a frame of the game itself for the Director (OUT dir from env), mid-clip
		var out := OS.get_environment("FV_OUT")
		if out != "":
			await process_frame
			var shot: Image = root.get_viewport().get_texture().get_image()
			shot.save_png(out.path_join("frame_video_ingame_%s.png" % fid))
	if v != null and fid == "F_hug_pelageya":
		# the lantern flickers on screen over the video (data lights rect 466,618,100,130, screen px)
		v.paused = true   # the video still: what changes now is the lantern's flicker alone
		await process_frame
		var ra := Rect2i(466, 618, 100, 130)   # the lantern's glow rect (data/story/lights, screen px)
		var shots: Array = []
		for k in 6:
			shots.append(root.get_viewport().get_texture().get_image().get_region(ra))
			for i in 15:
				await process_frame
		v.paused = false
		var d_l := 0.0
		for k in range(1, shots.size()):
			d_l = maxf(d_l, _mean_diff(shots[0], shots[k]))
		var lt = room.get_node_or_null("Lighting")
		var src = lt.sources[0] if lt != null and lt.sources.size() > 0 else null
		print("    lantern region over 1.5 s: max mean |diff| %.2f / 255; source %s level %s energy %s visible %s z %s" % [d_l, src.name if src else "-", src.level if src else "-", src.energy if src else "-", src.visible if src else "-", src.z_index if src else "-"])
		_check(d_l > 0.3, "FV-2 the lantern does not flicker over the video (%.2f)" % d_l)
	await _seam(v)
	sr.set_frame("", false)
	await process_frame


func _seam(v: VideoStreamPlayer) -> void:
	# FV-3: first vs last frame of the game's own OGV
	if v != null and v.stream != null:
		var probe := VideoStreamPlayer.new()
		probe.stream = v.stream
		probe.loop = false
		probe.autoplay = false
		probe.volume_db = -80.0
		root.add_child(probe)
		probe.play()
		var first: Image = null
		var lastimg: Image = null
		var t2 := 0.0
		while t2 < 12.0 and probe.is_playing():
			await process_frame
			t2 += 1.0 / 60.0
			var tex := probe.get_video_texture()
			if tex != null and probe.stream_position > 0.05 and first == null:
				first = tex.get_image()
			if tex != null and probe.stream_position > probe.get_stream_length() - 0.12:
				lastimg = tex.get_image()
		_check(first != null and lastimg != null, "FV-3 could not grab the first/last frames (first %s last %s)" % [first != null, lastimg != null])
		if first != null and lastimg != null:
			var d := _mean_diff(first, lastimg)
			print("    loop seam: first↔last mean |diff| %.1f / 255" % d)
			_check(d <= 8.0, "FV-3 the loop's last frame differs from the first by %.1f (> 8)" % d)
		probe.queue_free()


func _mean_diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			s += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			n += 1
	return s / maxf(1.0, n)
