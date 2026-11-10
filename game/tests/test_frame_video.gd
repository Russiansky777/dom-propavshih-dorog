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
##   FV-8 (Director 10.11, 19:04, the hugs: «ок, давай второй вариант») the frame names an intro beside the loop
##        (background.video_intro): the intro plays once, from the painting, over the loop that waits paused at its
##        start; at the intro's end the loop goes on and no drawn frame through the join differs from the one before
##        it by more than the clip's own motion; self-check — with the intro off the first picture on screen is the
##        loop's own beginning, far from the painting.
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
	for fid in ["F_hug_pelageya", "F_hug_nina"]:
		await _intro_join(fid, sd, sr, main_node)
	# FV-5: the dinner (09.11) — the clip follows the player's choices; the people and the cup are inside it, so their
	# layers go; a variant without a clip yet falls back to the painting with its layers
	var fv = main_node.find_child("FrameView", true, false)
	var cases := [
		# 09.11 evening: two Kling Pro clips per variant (a, b), each starts and ends in the painting — they take turns
		[["v01_cup_blue"], ["closed_blue_a", "closed_blue_b"], ["agata", "family_closed", "cup_blue", "tikhon"]],
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
		if v != null and v.files.size() == 1:
			_check(v.loop and v.is_playing(), "FV-5 one clip %s but it does not loop" % names)
		var out5 := OS.get_environment("FV_OUT")
		if out5 != "" and want[0] == "open_blue_a":
			for i in 150:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png(out5.path_join("frame_video_ingame_EP_dinner.png"))
		sr.set_frame("", false)
		await process_frame
	# FV-6 (Director 09.11, 12:35 «Уля вообще не приходит при этом на видео»): the dinner opens without Ulyana and her
	# flag is set later, at the door's line (E5 M26) — the clip must change to the family with her at once.
	# Self-check first: with the re-pick switched off (as built before) the clip stays — the check sees the defect.
	for old_way in [true, false]:
		gs.reset()
		gs.set_flag("v01_cup_blue", true)
		sr.set_frame("EP_dinner", false)
		for i in 3:
			await process_frame
		var v6 = fv.room.get_node_or_null("Background/Video") if fv.room != null else null
		if old_way and v6 != null and gs.flag_changed.is_connected(Callable(v6, "_on_flag")):
			gs.flag_changed.disconnect(Callable(v6, "_on_flag"))
		var before6 := String(v6.stream.resource_path).get_file() if v6 != null and v6.stream != null else ""
		gs.set_flag("ep_ulyana_came", true)
		await process_frame
		var after6 := String(v6.stream.resource_path).get_file() if v6 != null and v6.stream != null else ""
		var switched: bool = before6.begins_with("closed_blue") and after6.begins_with("open_blue") and v6.is_playing()
		if old_way:
			_check(not switched, "FV-6 self-check: without the re-pick the clip still changed (%s → %s)" % [before6, after6])
		else:
			_check(switched, "FV-6 Ulyana came mid-frame: clip %s → %s" % [before6, after6])
		sr.set_frame("", false)
		await process_frame
	# FV-7 (Director 09.11, 21:58 / 22:32: «экран „моргает“ постоянно в последней сцене… целиком»): when one clip of the
	# dinner ends and the next begins, no drawn frame may show the empty room under the player (a new stream starts
	# with an empty texture). The clip is taken close to its end and every frame through the change is compared with
	# the one before it, over the family's part of the picture. Self-check first: the change without the held picture
	# (as built before) does show the empty room.
	for old_way7 in [true, false]:
		gs.reset()
		gs.set_flag("v01_cup_blue", true)
		sr.set_frame("EP_dinner", false)
		for i in 6:
			await process_frame
		var v7 = fv.room.get_node_or_null("Background/Video") if fv.room != null else null
		if v7 == null:
			_check(false, "FV-7 no player on the dinner frame")
			continue
		v7.set("hold_enabled", not old_way7)
		v7.stream_position = 9.4
		var clip7 := String(v7.stream.resource_path)
		var ref7: Image = null
		var worst := 0.0
		var changed_at := -1
		var n7 := 0
		while n7 < 200 and (changed_at < 0 or n7 - changed_at < 6):
			n7 += 1
			await RenderingServer.frame_post_draw
			var shot: Image = root.get_viewport().get_texture().get_image()
			shot.resize(96, 54, Image.INTERPOLATE_BILINEAR)
			if changed_at < 0 and String(v7.stream.resource_path) != clip7:
				changed_at = n7
			if changed_at < 0:
				ref7 = shot
				continue
			if ref7 == null:
				continue
			# the family's part of the picture (design px 640..1840 × 300..800 → 96×54)
			var sum := 0.0
			var cnt := 0
			for y in range(15, 40):
				for x in range(32, 92):
					sum += absf(shot.get_pixel(x, y).get_luminance() - ref7.get_pixel(x, y).get_luminance())
					cnt += 1
			worst = maxf(worst, sum / cnt * 255.0)
		print("    FV-7 %s: the clip changed at frame %d, the family's part differs from the frame before by at most %.1f/255" % ["without the held picture" if old_way7 else "as built", changed_at, worst])
		if changed_at < 0:
			_check(false, "FV-7 the clip never changed in 200 frames")
		elif old_way7:
			_check(worst > 6.0, "FV-7 self-check: without the held picture the change shows no empty frame (%.1f) — the test sees nothing" % worst)
		else:
			_check(worst <= 3.0, "FV-7 a frame at the clip change differs by %.1f/255 (> 3) — the empty room shows" % worst)
			var hold7 = v7.get_node_or_null("Hold")
			_check(hold7 != null and not (hold7 as CanvasItem).visible, "FV-7 the held picture stays over the new clip")
		sr.set_frame("", false)
		await process_frame
	var m26: Dictionary = sd.scene("M26")
	var sets_at_line := false
	for st in m26.get("stage", []):
		if (st.get("sets", []) as Array).has("ep_ulyana_came") and typeof(st.get("at")) != TYPE_STRING:
			sets_at_line = true
	_check(sets_at_line, "FV-6 M26 no longer sets ep_ulyana_came at a line — the test's premise changed")
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
	_check(spec.get("effects", []).filter(func(e): return e.get("type") == "snow" and not bool(e.get("unless_video", false))).is_empty(), "FV-3 the frame's snow effect is not unless_video (it would fall over the video's snow)")
	var fx: Node = room.get_node_or_null("Effects")
	var snow_built := false
	if fx != null:
		for n in fx.get_children():
			if String(n.name).contains("snow"):
				snow_built = true
	_check(not snow_built, "FV-3 the snow effect is built over the video")
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


## FV-8: the intro, then the loop (see the header).
func _intro_join(fid: String, sd, sr, main_node) -> void:
	print("  -- %s: intro → loop" % fid)
	var spec: Dictionary = sd.room(fid)
	var intro_path := String(spec.get("background", {}).get("video_intro", ""))
	_check(intro_path != "" and ResourceLoader.exists(intro_path), "FV-8 %s names no intro (%s)" % [fid, intro_path])
	if intro_path == "" or not ResourceLoader.exists(intro_path):
		return
	var starts: Dictionary = {}
	var fv_script: GDScript = load("res://scripts/rooms/frame_video.gd")
	for with_intro in [false, true]:
		fv_script.set("intro_enabled", with_intro)
		sr.set_frame(fid, false)
		for i in 3:
			await process_frame
		fv_script.set("intro_enabled", true)
		var fv = main_node.find_child("FrameView", true, false)
		var v: VideoStreamPlayer = fv.room.get_node_or_null("Background/Video") if fv != null and fv.room != null else null
		if v == null:
			_check(false, "FV-8 %s: no player on the frame" % fid)
			continue
		var intro: VideoStreamPlayer = v.get_node_or_null("Intro")
		if with_intro:
			_check(intro != null and intro.is_playing() and intro.volume_db <= -60.0 and intro.size == v.size, "FV-8 %s: no intro playing over the loop (%s)" % [fid, intro])
			_check(v.paused and v.stream_position <= 0.001 and v.loop and v.stream != null, "FV-8 %s: the loop does not wait at its start under the intro (paused %s, position %.2f, loop %s)" % [fid, v.paused, v.stream_position, v.loop])
			if intro == null:
				continue
		else:
			_check(intro == null and not v.paused, "FV-8 self-check: with the intro off there is still an intro (%s) or the loop waits (%s)" % [intro, v.paused])
		# the painting as the game draws it: the player hidden for one drawn frame
		v.visible = false
		await RenderingServer.frame_post_draw
		var painting := _small()
		v.visible = true
		# a quarter of a second in: what is on screen against the painting
		var lead: VideoStreamPlayer = intro if with_intro else v
		var n := 0
		while lead.stream_position < 0.25 and n < 300:
			n += 1
			await process_frame
		await RenderingServer.frame_post_draw
		starts[with_intro] = _part_diff(_small(), painting)
		if with_intro:
			# the join: every drawn frame from 0.7 s before the intro's end till the loop is well on
			intro.stream_position = maxf(intro.get_stream_length() - 0.7, 0.3)
			var prev: Image = null
			var worst := 0.0
			var worst_at := -1
			var gone_at := -1
			var k := 0
			while k < 300 and (gone_at < 0 or k - gone_at < 12):
				k += 1
				await RenderingServer.frame_post_draw
				var shot := _small()
				if prev != null:
					var d := _part_diff(shot, prev)
					if d > worst:
						worst = d
						worst_at = k
				prev = shot
				if gone_at < 0 and v.get_node_or_null("Intro") == null:
					gone_at = k
			print("    FV-8 %s: the intro went at frame %d of the watch; frame-to-frame difference through the join at most %.2f/255 (at frame %d); the loop at %.2f s" % [fid, gone_at, worst, worst_at, v.stream_position])
			_check(gone_at > 0, "FV-8 %s: the intro never gave way to the loop" % fid)
			_check(worst <= JOIN_MAX, "FV-8 %s: a frame at the join differs from the one before by %.2f/255 (> %.1f) — a jump or an empty frame" % [fid, worst, JOIN_MAX])
			_check(not v.paused and v.is_playing() and v.loop and v.stream_position > 0.0, "FV-8 %s: after the intro the loop does not play (paused %s, playing %s, position %.2f)" % [fid, v.paused, v.is_playing(), v.stream_position])
		sr.set_frame("", false)
		await process_frame
	if starts.has(true) and starts.has(false):
		print("    FV-8 %s: a quarter of a second in, the screen against the painting — with the intro %.2f/255, without %.2f/255" % [fid, float(starts[true]), float(starts[false])])
		_check(float(starts[true]) <= START_MAX, "FV-8 %s: the intro does not begin in the painting (%.2f/255 > %.1f)" % [fid, float(starts[true]), START_MAX])
		_check(float(starts[false]) > START_MAX * 1.5, "FV-8 self-check: without the intro the frame also begins in the painting (%.2f/255) — the measure tells nothing" % float(starts[false]))


const JOIN_MAX := 3.0
const START_MAX := 3.0


func _small() -> Image:
	var shot: Image = root.get_viewport().get_texture().get_image()
	shot.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	return shot


## Mean difference of the middle of the picture (design px 600..1320 × 200..880 — the people), 0..255.
func _part_diff(a: Image, b: Image) -> float:
	var sum := 0.0
	var cnt := 0
	for y in range(10, 44):
		for x in range(30, 66):
			sum += absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			cnt += 1
	return sum / maxf(1.0, cnt) * 255.0


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
