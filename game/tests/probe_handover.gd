extends SceneTree
## Frames of a scene's hand-over in play (Director 09.11 11:34: «ключ приклеен на руку… Агата не забирает его в тот
## момент… обходит Тамару»): the scene runs to line `at`, then frames every `step` s for `secs` s; then the line is
## advanced and frames go on (the staging before the next line) — what the player sees.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/probe_handover.gd -- \
##       <out_dir> <scene> <room> <at_line> [secs=7] [step=0.25] [crop x,y,w,h] [after_s=6] [click x,y]
## Writes <out>/<scene>_<n>.jpg (cropped) and prints per frame: t, line, Agata pos, the prop shown and where.

var gs; var rm; var sr; var sd


func _initialize() -> void:
	_run()


func _flags_before(upto: String) -> void:
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for st in sc.get("stage", []):
			for f in st.get("sets", []):
				gs.set_flag(String(f), true)


func _props() -> String:
	var s := ""
	for n in root.find_children("Held", "", true, false):
		if n is CanvasItem and (n as CanvasItem).visible:
			s += " %s@%s a%.2f" % [String(n.get_parent().name), (n as Node2D).global_position.round(), (n as CanvasItem).modulate.a]
	for n in root.find_children("HeldKey*", "", true, false):
		s += " %s vis %s" % [n.name, n.visible]
	return s


func _gripR(pl) -> Vector2:
	var v = pl.get("view3d")
	var b: Sprite2D = pl.get("body3d")
	if v == null or b == null:
		return Vector2.INF
	return (b.global_transform * (v.hand_grip_frame_px("Right") + b.offset)).round()


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState"); rm = root.get_node("RoomManager"); sr = root.get_node("StoryRunner"); sd = root.get_node("StoryData")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]; var scene: String = a[1]; var room: String = a[2]; var at := int(a[3])
	var secs := float(a[4]) if a.size() > 4 else 7.0
	var step := float(a[5]) if a.size() > 5 else 0.25
	var crop := Rect2i(0, 0, 1920, 1080)
	if a.size() > 6 and a[6] != "-":
		var c := a[6].split(",")
		crop = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	var after_s := float(a[7]) if a.size() > 7 else 6.0
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	if OS.get_environment("HO_START") != "":
		rm.start_at(OS.get_environment("HO_START"))
	else:
		_flags_before(scene)
		rm.change_room(room, "default")
	for i in 30:
		await process_frame
	sr.call("_on_state_reset")
	if a.size() > 8 and a[8] != "-":
		# as the player does it: a click on the villager — Agata walks to the talk point, the scene starts there
		var c8 := a[8].split(",")
		rm.player.call("click_at", Vector2(float(c8[0]), float(c8[1])))
		var w := 0
		while w < 1200 and String(sr.active_scene) != scene:
			w += 1
			await process_frame
	else:
		sr.start_scene(scene)
	var idx := 0
	var g := 0
	# run the lines up to `at` (each staging plays out as in the game)
	while g < 20000:
		g += 1
		await process_frame
		if sr.is_staging():
			continue
		if sr.current_beat.is_empty():
			continue
		if idx >= at:
			break
		if sr.current_beat.get("type") == "options":
			sr.choose(String(sr.current_beat["options"][0]["id"]))
		else:
			sr.advance()
		idx += 1
	# the line `at` is on screen once its staging is done; film from the staging before it — so go back: we film from
	# the moment the previous line was advanced. Simpler: the staging at `at` ran already; film what goes on now.
	var n := 0
	var t := 0.0
	var pl: Node2D = rm.player
	var phases := [[secs, "line %d" % at], [after_s, "advance → line %d" % (at + 1)]]
	for ph in phases:
		if String(ph[1]).begins_with("advance"):
			sr.advance()
		var t0 := 0.0
		while t0 < float(ph[0]):
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image().get_region(crop)
			if img.get_width() > 1400:
				img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
			img.save_jpg("%s/%s_%03d.jpg" % [out, scene, n], 0.85)
			print("%03d t %.2f %s agata %s walking %s acting %s%s" % [n, t, ph[1], pl.global_position.round() if pl else "-", pl.call("is_walking") if pl else "-", pl.call("is_acting") if pl else "-", _props() + " act %s t %.2f/%.2f aw %.2f w %.2f yaw %.0f→%.0f gripR %s" % [pl.call("current_action"), float(pl.get("_act_t")), float(pl.get("_act_len")), float(pl.get("_act_w")), pl.get("view3d").shown_act_w(), rad_to_deg(float(pl.get("yaw3d"))), rad_to_deg(float(pl.get("yaw3d_target"))), _gripR(pl)] + " ho " + str(sr.get("last_handover"))])
			n += 1
			await create_timer(step).timeout
			t0 += step
			t += step
	quit(0)
