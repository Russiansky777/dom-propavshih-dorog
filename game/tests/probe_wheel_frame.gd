extends SceneTree
## The mill yard as the game draws it by day, for the trial of live water at the wheel (Director 16.11, 14:40: «давай
## пока тестово попробуем… короткое видео просто пришлёшь, как оно смотрится»; Docs/PLAN_WHEEL_WATER.md): the room M1
## at the second day, nobody in it, no interface, the wheel stopped at a given angle — the picture a video model starts
## from, and the same room filmed as it is now (the code's water) for a «было». Needs a display:
##   godot --path game --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
##       -s res://tests/probe_wheel_frame.gd -- <out_dir> [angle_deg] [film_seconds] [fps]
## Writes <out_dir>/start_water.png (the wheel at angle_deg, the code's water as drawn at that moment; no drizzle, no
## exit arrow), <out_dir>/start_clean.png (the same without the code's streams, spray and foam — the painting and the
## wheel only)
## and, with film_seconds > 0, <out_dir>/now_NNN.png — the room as it is now, wheel turning, `fps` frames a second.


func _initialize() -> void:
	_run()


func _frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("frame ", path)


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var angle := float(a[1]) if a.size() > 1 else 0.0
	var film_s := float(a[2]) if a.size() > 2 else 0.0
	var fps := int(a[3]) if a.size() > 3 else 15
	var rm = root.get_node("RoomManager")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var p: Dictionary = (root.get_node("StoryData").start_points.get("day2", {}) as Dictionary).duplicate(true)
	p["room"] = "M1"
	rm.start_with(p)
	for i in 20:
		await process_frame
	# nobody and nothing of the interface in the picture
	for n in root.find_children("*", "CanvasLayer", true, false):
		if n.name in ["GameUi", "MechanicView", "FrameView", "Hud", "Cursor"] or String(n.name).begins_with("Ui"):
			(n as CanvasLayer).visible = false
	var ui = main_node.get_node_or_null("GameUi")
	if ui != null:
		ui.set("visible", false)
	if rm.player != null:
		(rm.player as Node2D).visible = false
	for n in root.find_children("*", "Node2D", true, false):
		if n.get("actor_id") != null and n != rm.player:
			(n as Node2D).visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	# the room as it is now, wheel turning
	if film_s > 0.0:
		Engine.max_fps = fps
		var n_frames := int(film_s * fps)
		for k in n_frames:
			await process_frame
			await _frame("%s/now_%03d.png" % [out, k])
	else:
		for i in 60:
			await process_frame
	# the wheel stopped at the angle
	var wheel: Node = null
	for n in root.find_children("*", "Node2D", true, false):
		if n.has_method("is_spinning") and n.get("data") is Dictionary and String((n.get("data") as Dictionary).get("id", "")) == "wheel":
			wheel = n
	if wheel == null:
		push_error("no wheel layer in M1")
		quit(1)
		return
	wheel.set_process(false)
	(wheel.get_node("Image") as Node2D).rotation_degrees = angle
	# the start pictures: no drizzle streaks and no exit arrow baked into what the model animates
	for n in root.find_children("Rain", "", true, false):
		n.set("visible", false)
	for n in root.find_children("*", "ExitCue", true, false):
		n.set("visible", false)
	for i in 3:
		await process_frame
	await _frame(out + "/start_water.png")
	for w in root.find_children("*", "AmbientWheel", true, false):
		(w as Node2D).visible = false
	for i in 3:
		await process_frame
	await _frame(out + "/start_clean.png")
	quit(0)
