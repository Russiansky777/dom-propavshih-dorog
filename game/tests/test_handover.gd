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
##   HO-5 Tamara's mail bag on the bridge: worn at the hip, a strap to the shoulder, no light rim.
##   HO-6 the other scenes with things in hands: Mitya takes the lantern from the snow with the hand that reaches it
##        (left), when it is there; Nina hangs the coat at the top of her reach, at the hook; no villager walks off the
##        floor of a room and stays there (Nina walked into the table, M19c); Ilya's knife and Nina's chalk are in the
##        fingers, the knife held out until the black.
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
	if only == "" or only == "6":
		await _ho6()
	if only == "" or only == "7":
		await _ho7()
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
	_check(pel.global_position.distance_to(Vector2(885, 800)) < 4.0, "HO-2 after the black she is not back on the path (%s)" % pel.global_position)
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



func _grip_at(npc: Node2D, side: String) -> Vector2:
	var live = npc.get("live")
	var px: Vector2 = live.view.call("hand_grip_frame_px", side)
	var b: Sprite2D = live.get("body")
	return b.global_transform * (px + b.offset)


## The grip of `side` when the npc's one-shot `clip` is at `share` (it plays from the start; real frames, x11).
func _grip_at_share(npc: Node2D, clip: String, share: float, side: String) -> Vector2:
	var secs := float(npc.call("play_action", clip, false, -1.0, false))
	var live = npc.get("live")
	var L: float = live.view.action_length(clip)
	var t := 0.0
	while t < secs + 1.0:
		await process_frame
		t += 1.0 / 30.0
		if bool(live.get("_once_clip")) and float(live.get("act_t")) / maxf(L, 0.01) >= share:
			return _grip_at(npc, side)
	return Vector2.INF


func _ho6() -> void:
	print("  -- HO-6 the other things in hands")
	# the lantern (M18, R3): Mitya at his staging place, turned to Pelageya
	gs.reset()
	_flags_before("M18")
	gs.set_flag("started_M18", true)
	rm.change_room("R3", "default")
	for i in 30:
		await process_frame
	var mit: Node2D = rm.current_room.get_node_or_null("npc_mitya")
	var bail := Vector2((490.0 + 583.0) * 0.5, 537.0) * (1920.0 / 1672.0)   # the lantern on the snow (layer mitya_lantern)
	if mit == null or mit.get("live") == null:
		_check(false, "HO-6 no live Mitya in R3")
	else:
		mit.global_position = Vector2(520, 668)
		mit.call("face_towards", Vector2(690, 668))
		for i in 30:
			await process_frame
		var m18: Dictionary = sd.scene("M18")
		var at := -1.0
		for st in m18.get("stage", []):
			for g in st.get("npc_act", []):
				if String(g.get("action", "")) == "pick_up":
					at = float(g.get("sets_at", -1.0))
		_check(at > 0.0, "HO-6 M18: the lantern goes into the hand by a timer, not when the clip is there (sets_at)")
		var lh: Vector2 = await _grip_at_share(mit, "pick_up", maxf(at, 0.0), "Left")
		_check(lh.distance_to(bail) < 45.0, "HO-6 M18: at the take Mitya's left hand is %.0f px from the lantern (≤ 45)" % lh.distance_to(bail))
		for i in 90:
			await process_frame
		var rh: Vector2 = await _grip_at_share(mit, "pick_up", maxf(at, 0.0), "Right")
		_check(rh.distance_to(bail) > 60.0, "HO-6 self-check: the right hand (where the lantern used to appear) is near it too (%.0f)" % rh.distance_to(bail))
		var hold: Dictionary = {}
		for h in sd.room("R3").get("hotspots", []):
			if h.get("id") == "mitya":
				hold = h.get("held", {})
		_check(String(hold.get("bone", "")) == "LeftHand", "HO-6 M18: the lantern is held in %s, not the hand that picked it up" % hold.get("bone", ""))
	# the coat (M23c, H1): at the top of hang_coat Nina's hand is at the hook
	gs.reset()
	_flags_before("M23c")
	gs.set_flag("started_M23c", true)
	rm.change_room("H1", "default")
	for i in 30:
		await process_frame
	var nin: Node2D = rm.current_room.get_node_or_null("npc_nina")
	var hook := Vector2(1222, 290)
	if nin == null or nin.get("live") == null:
		_check(false, "HO-6 no live Nina in H1")
	else:
		var go: Array = []
		var face: Array = []
		var at2 := -1.0
		for st in sd.scene("M23c").get("stage", []):
			for g in st.get("npc_go", []):
				if String(g.get("id", "")) == "nina" and go.is_empty():
					go = g.get("to", [])
					face = g.get("face", [])
			for g in st.get("npc_act", []):
				if String(g.get("action", "")) == "hang_coat":
					at2 = float(g.get("sets_at", -1.0))
		_check(go.size() == 2 and face.size() == 2 and at2 > 0.0, "HO-6 M23c: no step to the hook / no sets_at")
		if go.size() == 2 and face.size() == 2:
			nin.global_position = Vector2(float(go[0]), float(go[1]))
			nin.call("face_towards", Vector2(float(face[0]), float(face[1])))
			for i in 30:
				await process_frame
			var g2: Vector2 = await _grip_at_share(nin, "hang_coat", at2, "Right")
			_check(g2.distance_to(hook) < 55.0, "HO-6 M23c: at the hanging Nina's hand is %.0f px from the hook (≤ 55)" % g2.distance_to(hook))
			# self-check: where she stood before, turned to the hook
			for i in 120:
				await process_frame
			nin.global_position = Vector2(1404, 756)
			nin.call("face_towards", Vector2(1222, 290))
			for i in 30:
				await process_frame
			var g3: Vector2 = await _grip_at_share(nin, "hang_coat", 0.62, "Right")
			_check(g3.distance_to(hook) > 80.0, "HO-6 self-check: the old staging puts the hand near the hook too (%.0f)" % g3.distance_to(hook))
	# no villager stays off the floor after a walk (M19c: Nina into the table)
	_check(_off_floor().is_empty(), "HO-6 villagers end walks off the floor: %s" % [_off_floor()])
	_check(_inside(Vector2(560, 820), sd.room("O3").get("walkable", [])) == false, "HO-6 self-check: the old M19c point (560, 820) counts as on the floor of O3")
	var m19c_place := false
	for st in sd.scene("M19c").get("stage", []):
		for g in st.get("npc_act", []):
			if String(g.get("action", "")) == "place_table":
				m19c_place = true
	_check(not m19c_place, "HO-6 M19c: Nina still walks to the table that is off the floor")
	# the knife and the chalk: in the fingers; the knife held out until the black
	var ilya = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/ilya.json"))
	var nina = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/nina.json"))
	var kn: Dictionary = ilya["rt3d"]["props"]["give_small"][0]
	var ch: Dictionary = nina["rt3d"]["props"]["write_board"][0]
	_check(String(kn.get("grip", "")) == "fingers" and float(kn.get("until", 0.0)) >= 1.0, "HO-6 Ilya's knife: grip %s until %s" % [kn.get("grip"), kn.get("until")])
	_check(String(ch.get("grip", "")) == "fingers", "HO-6 Nina's chalk: grip %s (on the palm)" % ch.get("grip"))
	var held_out := false
	for st in sd.scene("M25").get("stage", []):
		for g in st.get("npc_act", []):
			if String(g.get("id", "")) == "ilya" and String(g.get("action", "")) == "give_small" and g.has("hold_at"):
				held_out = true
	_check(held_out, "HO-6 M25: Ilya's knife is not held out until the black (it went out mid-reach)")


static func _inside(p: Vector2, poly: Array) -> bool:
	var c := false
	var n := poly.size()
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		if (float(a[1]) > p.y) != (float(b[1]) > p.y) and p.x < (float(b[0]) - float(a[0])) * (p.y - float(a[1])) / (float(b[1]) - float(a[1])) + float(a[0]):
			c = not c
	return c


## HO-7 (Director 09.11, 22:18: «сцена с мамой в классе — она пишет невпопад, и до того, как проигрывается анимация, а
## должна во время анимации написания на доске и в том же месте… Нина выводит число — пусть бы и выводила с мелом в
## руке… а потом возвращалась в ту стойку, где была»): in M22 Nina stands at the board with her back to the room, the
## chalk at the height of the line she writes and by its end, the line comes out while her arm is up; the date too —
## with the chalk raised to the board's corner; after each she steps back to the right, facing Agata.
## Self-check: the arm as the clip has it (no `arm` turn) holds the chalk far above the answer's line.
var _ho7_grip := Vector2.INF


func _ho7_watch(nina: Node2D, layer_id: String, line_y: float, self_check: bool) -> Dictionary:
	var live = nina.get("live")
	var out := {"acted": false, "yaw_off": 999.0, "dy": 999.0, "dx_end": 999.0, "early_w": -1.0, "late_w": -1.0, "raw_dy": 0.0, "end_x": 0.0}
	var spr: Sprite2D = rm.current_room.get_node_or_null("Layers/%s/Image" % layer_id)
	var L: float = live.view.action_length("write_board")
	var g := 0
	var x0 := -1.0
	var w_seen := 0.0
	while g < 900:
		g += 1
		await process_frame
		if OS.get_environment("HO7_DEBUG") != "" and g % 60 == 1:
			print("      [ho7 %d] line %s staging %s nina %s once %s act %s flags here/mama/ilya %s%s%s" % [g, sr.current_beat.get("line_id", "-"), sr.is_staging(), nina.global_position.round(), live.get("_once_clip"), live.get("act_name"), gs.has_flag("board_here"), gs.has_flag("board_mama"), gs.has_flag("board_ilya")])
		if not (bool(live.get("_once_clip")) and String(live.get("act_name")) == "write_board"):
			if out["acted"]:
				break
			continue
		out["acted"] = true
		var share := float(live.get("act_t")) / maxf(L, 0.01)
		# the written part: the layer's region grows from the line's start to its end (StoryRunner._stage_layer_write)
		# and is switched off when the line is whole — the last width seen stays the line's end
		if spr != null and spr.region_enabled:
			w_seen = spr.region_rect.size.x
		var w := w_seen
		if x0 < 0.0 and w > 0.0:
			x0 = w
		if share < 0.15:
			out["early_w"] = (w - x0) if x0 >= 0.0 else 0.0   # nothing written while the arm is still going up
		if share >= 0.45 and share <= 0.6 and _ho7_grip != Vector2.INF:
			out["yaw_off"] = minf(out["yaw_off"], absf(rad_to_deg(angle_difference(float(live.get("yaw")), PI))))
			out["dy"] = minf(out["dy"], absf(_ho7_grip.y - line_y))
			if self_check and live.get("act_arm") != null and out["raw_dy"] == 0.0:
				# the arm as the clip has it, for two frames
				var keep: float = live.act_arm.angle
				live.act_arm.angle = 0.0
				await process_frame
				await process_frame
				out["raw_dy"] = absf(_ho7_grip.y - line_y)
				live.act_arm.angle = keep
				await process_frame
		if share >= 0.7:
			out["late_w"] = maxf(out["late_w"], (w - x0) if x0 >= 0.0 else -1.0)
			if spr != null and _ho7_grip != Vector2.INF:
				var end_x: float = (spr.global_transform * Vector2(w, 0.0)).x
				out["end_x"] = end_x
				out["dx_end"] = minf(out["dx_end"], absf(_ho7_grip.x - end_x))
	return out


func _ho7() -> void:
	# the data: the walk to the board ends facing it, the writing has the arm's turn and writes the line itself
	var m22: Dictionary = sd.scene("M22")
	var acts := 0
	for st in m22.get("stage", []):
		for a in st.get("npc_act", []):
			if String(a.get("action", "")) == "write_board":
				acts += 1
				_check(a.has("arm") and not (a.get("layer_write", []) as Array).is_empty() and float(a["layer_write"][0].get("delay", 0.0)) >= 0.8,
					"HO-7 M22: a write_board without its arm turn or with the line written outside the action (%s)" % str(a).substr(0, 120))
		_check(not st.has("layer_write"), "HO-7 M22: a chalk line written by the staging, not by Nina's action (at %s)" % str(st.get("at")))
	_check(acts == 2, "HO-7 M22: Nina writes twice — the answer and the date (%d)" % acts)
	gs.reset()
	_flags_before("M22")
	gs.set_flag("board_mama", true)
	rm.change_room("O1", "from_O2")
	for i in 40:
		await process_frame
	_check(String(sr.active_scene) == "M22", "HO-7 M22 does not start in the class (%s)" % sr.active_scene)
	var nina: Node2D = rm.current_room.get_node_or_null("npc_nina")
	var live = nina.get("live") if nina != null else null
	if live == null:
		_check(false, "HO-7 no live Nina in the class (x11 needed)")
		return
	var body: Sprite2D = live.get("body")
	var cb := func(): _ho7_grip = body.global_transform * (live.view.hand_grip_frame_px("Right") + body.offset)
	live.view.skeleton.skeleton_updated.connect(cb)
	# the answer: after the line that says she writes it. «Дождалась» on screen: y 387–441 (the layer ×1.5 about its middle)
	var g0 := 0
	while g0 < 600 and (sr.is_staging() or sr.current_beat.is_empty()):   # the first line is up (the room has faded in)
		g0 += 1
		await process_frame
	# on to the line she writes at (M22_3; the first advance of a line may only finish its text)
	var tries := 0
	while tries < 8 and not sr.is_staging() and not String(sr.current_beat.get("line_id", "")).begins_with("M22_3"):
		tries += 1
		sr.advance()
		for i in 8:
			await process_frame
	_check(sr.is_staging() or String(sr.current_beat.get("line_id", "")).begins_with("M22_3"), "HO-7 the line of the answer (M22_3) not reached (%s)" % str(sr.current_beat.get("line_id", "-")))
	var r1: Dictionary = await _ho7_watch(nina, "nina_answer_mama", 414.0, true)
	print("    HO-7 answer: turned %.0f° off the board, chalk %.0f px off the line's height (as the clip has it: %.0f), %.0f px from the line's end; written before the arm is up: %.0f px, by the end: %.0f px" % [r1["yaw_off"], r1["dy"], r1["raw_dy"], r1["dx_end"], r1["early_w"], r1["late_w"]])
	_check(r1["acted"], "HO-7 Nina does not write the answer")
	_check(r1["yaw_off"] <= 25.0, "HO-7 writing the answer Nina is turned %.0f° off the board (≤ 25)" % r1["yaw_off"])
	_check(r1["dy"] <= 45.0, "HO-7 the chalk is %.0f px off the height of the line it writes (≤ 45)" % r1["dy"])
	_check(r1["dx_end"] <= 80.0, "HO-7 the chalk is %.0f px from the end of the written line (≤ 80)" % r1["dx_end"])
	_check(r1["early_w"] == 0.0 and r1["late_w"] > 60.0, "HO-7 the line is not written while the arm is at the board (before: %.0f px, by the end: %.0f)" % [r1["early_w"], r1["late_w"]])
	_check(r1["raw_dy"] > 80.0, "self-check HO-7: with the arm as the clip has it the chalk is only %.0f px off the line — the test sees no miss" % r1["raw_dy"])
	# she steps back to the right of what she wrote, facing Agata
	var g := 0
	while g < 400 and (sr.is_staging() or sr.current_beat.is_empty()):
		g += 1
		await process_frame
	_check(nina.global_position.x > 1280.0, "HO-7 after the answer Nina stays in front of it (x %.0f)" % nina.global_position.x)
	# on to the date (the line «Под своим числом Агатино написала…» is the one before it)
	var guard := 0
	while guard < 12 and not String(sr.current_beat.get("text", "")).begins_with("Нина помедлила"):
		guard += 1
		sr.advance()
		for i in 12:
			await process_frame
		while sr.is_staging():
			await process_frame
	_check(String(sr.current_beat.get("text", "")).begins_with("Нина помедлила"), "HO-7 the date's line not reached (%s)" % String(sr.current_beat.get("text", "")).substr(0, 40))
	sr.advance()
	# «25 октября» on screen: x 1187–1316, y 195–241
	var r2: Dictionary = await _ho7_watch(nina, "nina_answer_date", 218.0, false)
	print("    HO-7 date: turned %.0f° off the board, chalk %.0f px off its height, %.0f px from its end; before the arm is up: %.0f px, by the end: %.0f px" % [r2["yaw_off"], r2["dy"], r2["dx_end"], r2["early_w"], r2["late_w"]])
	_check(r2["acted"] and r2["yaw_off"] <= 25.0, "HO-7 the date: Nina does not write it at the board (acted %s, %.0f° off)" % [r2["acted"], r2["yaw_off"]])
	_check(r2["dy"] <= 60.0, "HO-7 the date: the chalk is %.0f px off its height (≤ 60)" % r2["dy"])
	_check(r2["dx_end"] <= 110.0, "HO-7 the date: the chalk is %.0f px from its end (≤ 110)" % r2["dx_end"])
	_check(r2["early_w"] == 0.0 and r2["late_w"] > 40.0, "HO-7 the date is not written while the arm is up (before: %.0f, by the end: %.0f)" % [r2["early_w"], r2["late_w"]])
	g = 0
	while g < 400 and (sr.is_staging() or sr.current_beat.is_empty()):
		g += 1
		await process_frame
	_check(nina.global_position.x > 1280.0 and not bool(live.get("_once_clip")), "HO-7 after the date Nina is not back in her place (x %.0f, acting %s)" % [nina.global_position.x, live.get("_once_clip")])
	if live.view.skeleton.skeleton_updated.is_connected(cb):
		live.view.skeleton.skeleton_updated.disconnect(cb)
	gs.reset()


func _off_floor() -> Array:
	var out: Array = []
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		for st in sc.get("stage", []):
			for g in st.get("npc_go", []):
				if bool(g.get("fade", true)) or bool(g.get("in_black", false)):
					continue
				for rid in sc.get("locations", []).slice(0, 3):
					var r: Dictionary = sd.room(String(rid))
					if r.is_empty() or bool(r.get("frame", false)):
						continue
					var has := false
					for h in r.get("hotspots", []):
						if h.get("id") == g.get("id"):
							has = true
					var w: Array = r.get("walkable", [])
					var to: Array = g.get("to", [0, 0])
					if has and not w.is_empty() and not _inside(Vector2(float(to[0]), float(to[1])), w):
						out.append("%s %s %s %s" % [id, rid, g.get("id"), to])
	return out
