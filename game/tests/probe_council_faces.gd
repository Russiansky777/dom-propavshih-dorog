extends SceneTree
## Review 17.11: in the bots' screenshots of the council in the mill yard (M23b, frame F_mill_manager) all four turn
## their backs to the camera on Pavel's and Ilya's lines and face it again on the manager's and Agata's. Line by line:
## each frame figure's facing (sheet direction, live yaw), state, partner.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_council_faces.gd

var gs
var rm
var sr
var sd
var _n := 0
var _slow := 0
var _early := 0
var _last_dt := 0.0
var _last_ms := 0


func _initialize() -> void:
	var wd := float(OS.get_environment("WATCHDOG")) if OS.get_environment("WATCHDOG") != "" else 240.0
	create_timer(wd).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _frame_room() -> Node:
	for fv in root.get_tree().get_nodes_in_group("frame_view"):
		var r = fv.get("room")
		if r != null and is_instance_valid(r):
			return r
	return null


func _dump(tag: String) -> void:
	var fr := _frame_room()
	var line := "dt %.3f %-8s %-8s «%s»" % [root.get_process_delta_time() if false else _last_dt, tag, String(sr.current_beat.get("speaker", "")), String(sr.current_beat.get("text", "")).left(30)]
	if fr == null:
		print(line + " | no frame room")
		return
	var parts: Array = []
	for n in fr.get_children():
		if String(n.name).begins_with("npc_"):
			var lv = n.get("live")
			var yawdeg := rad_to_deg(float(lv.get("yaw"))) if lv != null else 0.0
			var tyaw := rad_to_deg(float(lv.get("yaw_target"))) if lv != null else 0.0
			var aw := float(lv.get("act_w")) if lv != null else 0.0
			var an := String(lv.get("act_name")) if lv != null else ""
			parts.append("%s[%s dir %d yaw %.0f→%.0f act %s %.2f%s]" % [String(n.name).substr(4), String(n.get("state")), int(n.get("direction")), yawdeg, tyaw,
				an, aw, " partner" if n.get("partner") != null else ""])
	print(line + " | " + " ".join(parts))
	var shots := OS.get_environment("SHOTS_DIR")
	if shots != "" and DisplayServer.get_name() != "headless":
		_n += 1
		root.get_viewport().get_texture().get_image().save_jpg("%s/c%03d.jpg" % [shots, _n], 0.8)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	if OS.get_environment("FORCE3D") != "":
		NpcLive3D.forced = "3d"   # live figures without a display (no picture, but the yaw logic runs)
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("freewalk", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	# SLOW_MS: from the yard on, every frame that much longer — the delta of a slow display (the bots' 2–3 frames a second)
	_slow = int(OS.get_environment("SLOW_MS")) if OS.get_environment("SLOW_MS") != "" else 0
	if _slow > 0:
		process_frame.connect(func():
			OS.delay_msec(_slow)
			var now := Time.get_ticks_msec()
			_last_dt = (now - _last_ms) / 1000.0
			_last_ms = now)
	rm.change_room("M1", "from_Z2")
	var last := ""
	var g := 0
	while g < 5000:
		g += 1
		await process_frame
		if gs.has_flag("done_M23b"):
			break
		if _slow > 0 and _frame_room() != null and _early < 12:
			_early += 1
			_dump("  e%02d" % _early)
		var key := String(sr.current_beat.get("text", ""))
		if key != last and not sr.current_beat.is_empty():
			last = key
			for i in 30:   # let the turns settle
				await process_frame
				if _slow > 0 and i % 3 == 0:
					_dump("  f%02d" % i)
			_dump(String(sr.active_scene))
		if not sr.current_beat.is_empty() and not sr.is_staging():
			sr.advance()
	quit(0)
