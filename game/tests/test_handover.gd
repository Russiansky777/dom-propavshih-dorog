extends SceneTree
## Director 09.11 (11:34; 12:35; 12:40): things in hands and turns of the figures, as played (x11 — live 3D figures).
##   HO-1 M01, the key: Tamara comes along the counter to Agata's end and holds the key out; it is IN her fingers (a
##        picture inside her 3D render, not laid over the palm in 2D); Agata takes it from her hand where she stands
##        (no walk round the counter); the key is never gone between the hands (one of them shows it every frame
##        until Agata's hand goes down); the two grips are close when it changes hands; Tamara's empty hand goes
##        down at once (her clip goes on from its way back, not held out further); at the scene's end she is back at
##        her place behind the counter.
##   HO-2 M17, the line: Pelageya walks to the water by the pier plate and pulls with her back to us; a line runs
##        from her hands to the plate while she pulls; in the black after it she is back on the path.
##   HO-3 the epilogue frames: the figures turned as the accepted painted frames had them (face_dir — the v2 sheet's
##        dir), not as a point picked by eye.
##   HO-4 the small actions taken out (12:40): Tamara's bag strap and bag picture, Pelageya's tarring, the lamp of
##        Ilya's wife (staging and the lamp in hand).
## Each check has a self-check that shows it catches the defect.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --fixed-fps 30 -s res://tests/test_handover.gd

var fails := 0
var passes := 0
var gs; var rm; var sr; var sd


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL  " + what)


## Frames where neither hand shows the thing, between the first and the last frame that shows it.
static func gap_frames(seq: Array) -> int:
	var first := seq.find(true)
	var last := seq.rfind(true)
	if first < 0:
		return 0
	var n := 0
	for i in range(first, last + 1):
		if not seq[i]:
			n += 1
	return n


func _flags_before(upto: String) -> void:
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)


func _to_line(scene: String, at: int) -> int:
	var idx := 0
	var g := 0
	while g < 6000 and String(sr.active_scene) == scene:
		g += 1
		await process_frame
		if sr.is_staging() or sr.current_beat.is_empty():
			continue
		if idx >= at:
			break
		if sr.current_beat.get("type") == "options":
			sr.choose(String(sr.current_beat["options"][0]["id"]))
		else:
			sr.advance()
		idx += 1
	return idx


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState"); rm = root.get_node("RoomManager"); sr = root.get_node("StoryRunner"); sd = root.get_node("StoryData")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	# self-check of the gap count
	_check(gap_frames([false, true, true, false, false, true, true]) == 2 and gap_frames([true, true, true]) == 0, "self-check: gap_frames")
	var only := OS.get_environment("HO_ONLY")
	if only == "" or only == "1":
		await _ho1()
	if only == "" or only == "2":
		await _ho2()
	if only == "" or only == "3":
		await _ho3()
	if only == "" or only == "5":
		await _ho5()
	_ho4()
	print("==== handover: %d tests, %d passed, %d failed ====" % [passes + fails, passes, fails])
	quit(1 if fails > 0 else 0)


func _ho1() -> void:
	print("  -- HO-1 the key (M01)")
	gs.reset()
	_flags_before("M01")
	rm.change_room("Z1", "default")
	for i in 30:
		await process_frame
	sr.call("_on_state_reset")
	var pl: Node2D = rm.player
	pl.call("click_at", Vector2(1070, 350))   # as the player does: Agata walks to the talk point, the scene starts
	var w := 0
	while w < 1500 and String(sr.active_scene) != "M01":
		w += 1
		await process_frame
	await _to_line("M01", 8)
	for i in 50:   # Tamara's hand goes out (hold at 0,25 of give_small)
		await process_frame
	var tam: Node2D = rm.current_room.get_node("npc_tamara")
	_check(tam.global_position.distance_to(Vector2(1215, 700)) < 4.0, "HO-1 Tamara came along the counter to Agata (at %s)" % tam.global_position)
	var key = null
	for hp in tam.get("action_props"):
		if String(hp.data.get("during", "")) == "give_small":
			key = hp
	_check(key != null and key.shown(), "HO-1 the key is not shown in Tamara's hand while she holds it out")
	_check(key != null and key.hand3d != null and key.hand3d.visible and not key.visible,
		"HO-1 the key is not in her fingers (3D %s, 2D over the palm %s)" % [key.hand3d.visible if key and key.hand3d else null, key.visible if key else null])
	var ag0: Vector2 = pl.global_position
	# the hand-over, frame by frame
	sr.advance()
	var seq: Array = []
	var moved := 0.0
	var t := 0.0
	var tam_hand_max := -INF
	var released_t := -1.0
	var tam_hold_x := -INF
	while t < 6.0:
		await process_frame
		t += 1.0 / 30.0
		var mine := false
		for n in pl.get_children():
			if n.has_method("give_away") and n.call("shown"):
				mine = true
		var st: Dictionary = pl.call("held_act_state")
		var share := float(st.get("t", 0.0)) / maxf(float(st.get("len", 1.0)), 0.01)
		var ks: bool = key != null and key.shown()
		if bool(pl.call("is_acting")) and share < 0.8 or ks:
			seq.append(ks or mine)
		moved = maxf(moved, pl.global_position.distance_to(ag0))
		var g: Vector2 = key.grip_screen() if key != null else Vector2.INF
		if not sr.last_handover.is_empty():
			if released_t < 0.0:
				released_t = t
			elif t > released_t + 0.4 and g != Vector2.INF:
				tam_hand_max = maxf(tam_hand_max, g.x)
		elif g != Vector2.INF:
			tam_hold_x = maxf(tam_hold_x, g.x)
		if String(sr.current_beat.get("speaker", "")) == "agata" and not bool(pl.call("is_acting")) and t > 1.0:
			break
	_check(moved < 6.0, "HO-1 Agata walked during the hand-over (%.0f px) — she takes it where she stands" % moved)
	_check(not sr.last_handover.is_empty(), "HO-1 the key never changed hands")
	_check(float(sr.last_handover.get("px", INF)) <= 40.0, "HO-1 the hands were %.0f px apart when it changed hands (≤ 40)" % float(sr.last_handover.get("px", INF)))
	_check(seq.size() > 10 and gap_frames(seq) <= 1, "HO-1 the key was gone %d frames between the hands (of %d)" % [gap_frames(seq), seq.size()])
	_check(tam_hand_max < tam_hold_x + 15.0, "HO-1 Tamara's empty hand went further out after the hand-over (%.0f > %.0f)" % [tam_hand_max, tam_hold_x])
	# the scene's end: back to her place
	var g2 := 0
	while g2 < 3000 and String(sr.active_scene) == "M01":
		g2 += 1
		await process_frame
		if not sr.is_staging() and not sr.current_beat.is_empty():
			sr.advance()
	for i in 60:
		await process_frame
	_check(tam.global_position.distance_to(Vector2(1070, 700)) < 4.0, "HO-1 Tamara is not back at her place after the scene (%s)" % tam.global_position)


func _ho2() -> void:
	print("  -- HO-2 the line (M17)")
	gs.reset()
	rm.start_at("boat_turn")
	for i in 30:
		await process_frame
	sr.call("_on_state_reset")
	rm.player.call("click_at", Vector2(965, 650))
	var w := 0
	while w < 600 and String(sr.active_scene) != "M17":
		w += 1
		await process_frame
	_check(String(sr.active_scene) == "M17", "HO-2 a click on Pelageya did not start M17 (active %s, busy %s, player at %s)" % [sr.active_scene, sr.is_busy(), rm.player.global_position])
	if String(sr.active_scene) != "M17":
		return
	await _to_line("M17", 3)
	var pel: Node2D = rm.current_room.get_node("npc_pelageya")
	var live = pel.get("live")
	var yaw_before := absf(rad_to_deg(wrapf(float(live.get("yaw")), -PI, PI)))
	sr.advance()
	var seen_line := false
	var line_end := Vector2.INF
	var away := false
	var at_water := false
	var t := 0.0
	while t < 12.0:
		await process_frame
		t += 1.0 / 30.0
		var hl := pel.get_node_or_null("HandLine") as Line2D
		if hl != null and hl.visible and hl.get_point_count() > 1:
			seen_line = true
			line_end = hl.get_point_position(hl.get_point_count() - 1)
			away = away or absf(rad_to_deg(wrapf(float(live.get("yaw")), -PI, PI))) > 110.0
			at_water = at_water or pel.global_position.distance_to(Vector2(1165, 725)) < 4.0
		if String(sr.current_beat.get("speaker", "")) == "narrator" and not sr.is_staging():
			break
	_check(yaw_before < 110.0, "HO-2 self-check: before the walk she faces Agata, not away (%.0f°)" % yaw_before)
	_check(at_water, "HO-2 Pelageya did not pull at the water's edge by the plate")
	_check(away, "HO-2 she does not pull with her back to us")
	_check(seen_line and line_end.distance_to(Vector2(1262, 548)) < 2.0, "HO-2 no line from her hands to the plate while she pulls (end %s)" % line_end)
	for i in 10:
		await process_frame
	_check(pel.global_position.distance_to(Vector2(965, 800)) < 4.0, "HO-2 after the black she is not back on the path (%s)" % pel.global_position)
	sr.call("_on_state_reset")


func _ho3() -> void:
	print("  -- HO-3 the epilogue frames' turns")
	gs.reset()
	rm.start_at("epilogue")
	for i in 20:
		await process_frame
	var fv = root.find_child("FrameView", true, false)
	for c in [["EP_tamara", "tamara", 3], ["EP_pavel", "pavel", 6], ["EP_boat", "pelageya", 6], ["EP_boat", "mitya", 6]]:
		sr.set_frame(String(c[0]), false)
		for i in 40:
			await process_frame
		var npc = fv.room.get_node_or_null("npc_" + String(c[1])) if fv.room != null else null
		var live = npc.get("live") if npc != null else null
		if live == null:
			_check(false, "HO-3 %s %s: no live figure" % [c[0], c[1]])
			continue
		var want := wrapf(-45.0 * float(c[2]), -180.0, 180.0)
		var got := wrapf(rad_to_deg(float(live.get("yaw"))), -180.0, 180.0)
		_check(absf(wrapf(got - want, -180.0, 180.0)) < 4.0, "HO-3 %s %s turned %.0f°, the accepted frame %.0f° (dir %d)" % [c[0], c[1], got, want, c[2]])
		# self-check: the face point the frame had before (a point picked by eye) gives another turn
		if String(c[1]) == "pavel":
			npc.call("face_towards", Vector2(1420, 600))
			for i in 30:
				await process_frame
			var old := wrapf(rad_to_deg(float(live.get("yaw"))), -180.0, 180.0)
			_check(absf(wrapf(old - want, -180.0, 180.0)) > 20.0, "HO-3 self-check: the old face point turns Pavel like dir 6 too (%.0f°)" % old)
		sr.set_frame("", false)
		await process_frame


func _ho4() -> void:
	print("  -- HO-4 small actions taken out")
	var tam: Dictionary = {}
	for h in sd.room("EP_tamara").get("hotspots", []):
		if h.get("id") == "tamara":
			tam = h
	_check(not tam.has("act") and not tam.has("held"), "HO-4 Tamara on the bridge still adjusts the bag strap / has the bag picture")
	for h in sd.room("EP_boat").get("hotspots", []):
		if h.get("id") == "pelageya":
			_check(not h.has("act"), "HO-4 Pelageya still tars the boat")
	for h in sd.room("O3").get("hotspots", []):
		if h.get("id") == "ilya_wife":
			_check(not h.has("held"), "HO-4 Ilya's wife still holds the lamp")
	var lamp := false
	for id in sd.scene_order:
		for st in sd.scene(id).get("stage", []):
			for g in st.get("npc_act", []):
				if String(g.get("action", "")) == "hold_lamp":
					lamp = true
	_check(not lamp, "HO-4 a staging still lifts the lamp")
	# the narration says no lamp any more (Director 13:36 «давай уберём „лампу несёт“») and its voice still plays: the
	# game's voice manifest has the trimmed line's text (tools/voice_trim.py; voice_director plays a line only while the
	# sha1 of its text matches)
	var m20: Dictionary = sd.scene("M20")
	var t7 := String(m20.get("mandatory_lines", [])[7].get("text", ""))
	_check(not t7.contains("ламп"), "HO-4 M20 line 7 still mentions the lamp: %s" % t7)
	for lang in ["ru"]:
		var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voice/%s/manifest.json" % lang))
		var e: Dictionary = man.get("lines", {}).get("M20_7", {}) if man is Dictionary else {}
		_check(String(e.get("text_sha1", "")) == t7.sha1_text(), "HO-4 the voice of M20_7 (%s) is silenced: the game's manifest has «%s»" % [lang, e.get("text", "")])
		var st = load("res://assets/voice/%s/M20_7.ogg" % lang)
		_check(st != null and st.get_length() < 2.7, "HO-4 the voice of M20_7 (%s) still runs %.2f s (the lamp words)" % [lang, st.get_length() if st else -1.0])



## HO-5 (Director 12:35 «сумка висит в воздухе, вокруг неё белый кантик»; 13:36 «повесь на бедро, как-то красиво»):
## Tamara's mail bag on the bridge is worn at her hip with a strap to the shoulder, inside her 3D render; the picture
## has no light fringe at its edge.
func _ho5() -> void:
	print("  -- HO-5 the mail bag on the bridge")
	gs.reset()
	rm.start_at("epilogue")
	for i in 20:
		await process_frame
	var fv = root.find_child("FrameView", true, false)
	sr.set_frame("EP_tamara", false)
	for i in 40:
		await process_frame
	var tam = fv.room.get_node_or_null("npc_tamara") if fv.room != null else null
	var worn: Array = tam.get("worn_props") if tam != null else []
	var bag = worn[0] if worn.size() > 0 else null
	_check(bag != null and bag.hand3d != null and bag.hand3d.visible and not bag.visible, "HO-5 the bag is not worn inside her 3D figure")
	var strap = tam.get_node_or_null("Strap") if tam != null else null
	_check(strap != null and strap.visible and strap.get_point_count() >= 2, "HO-5 no strap from the bag to her shoulder")
	if strap != null and bag != null:
		var top: Vector2 = strap.get_point_position(0)
		var sh: Vector2 = strap.get_point_position(strap.get_point_count() - 1)
		_check(sh.y < top.y - 40.0, "HO-5 the strap does not go up to the shoulder (%s → %s)" % [top, sh])
	# the picture's edge: no light pixels along its outline (the Meshy cut-out's white rim)
	var img: Image = load("res://assets/props/hip_mail_bag.png").get_image()
	var light := 0
	var edge := 0
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			var c := img.get_pixel(x, y)
			if c.a < 0.3:
				continue
			if img.get_pixel(x - 1, y).a < 0.3 or img.get_pixel(x + 1, y).a < 0.3 or img.get_pixel(x, y - 1).a < 0.3 or img.get_pixel(x, y + 1).a < 0.3:
				edge += 1
				if c.get_luminance() > 0.72:
					light += 1
	_check(edge > 100 and float(light) / float(edge) < 0.03, "HO-5 the bag picture has a light rim (%d of %d edge px)" % [light, edge])
	# self-check: the old picture had it
	var old: Image = load("res://assets/props/held_mail_bag.png").get_image()
	var l2 := 0
	var e2 := 0
	for y in range(1, old.get_height() - 1):
		for x in range(1, old.get_width() - 1):
			var c := old.get_pixel(x, y)
			if c.a < 0.3:
				continue
			if old.get_pixel(x - 1, y).a < 0.3 or old.get_pixel(x + 1, y).a < 0.3 or old.get_pixel(x, y - 1).a < 0.3 or old.get_pixel(x, y + 1).a < 0.3:
				e2 += 1
				if c.get_luminance() > 0.72:
					l2 += 1
	_check(e2 > 0 and float(l2) / float(e2) >= 0.03, "HO-5 self-check: the old bag picture's rim is not found (%d of %d)" % [l2, e2])
	sr.set_frame("", false)
	await process_frame
