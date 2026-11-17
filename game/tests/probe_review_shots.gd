extends SceneTree
## Review 17.11: pictures of two fixes for the Director — the photo in the mill passage with the lines over it (its
## caption above the line box) and M21b «Как было» after the village list (the talk in Mama's room, not over the paper).
##   SHOTS_DIR=<dir> xvfb-run -a -s "-screen 0 1920x1080x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1920x1080 --path game -s res://tests/probe_review_shots.gd

var gs
var rm
var sr
var sd
var _n := 0
var _dir := ""


func _initialize() -> void:
	var wd := float(OS.get_environment("WATCHDOG")) if OS.get_environment("WATCHDOG") != "" else 1500.0
	create_timer(wd).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _shot(tag: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_n += 1
	print("%02d %-12s room %s scene %s view %s mech %s beat «%s»" % [_n, tag, String(rm.current_room.room_id) if rm.current_room != null else "-",
		String(sr.active_scene), str(sr.view_open), str(sr.mechanic_open), String(sr.current_beat.get("text", "")).left(50)])
	if _dir != "" and DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_jpg("%s/r%02d_%s.jpg" % [_dir, _n, tag], 0.85)


func _hotspot(id: String) -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id:
			return h
	return null


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _play(tag: String, until_flag: String) -> void:
	var last := ""
	for g in 6000:
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if gs.has_flag(until_flag):
				break
			continue
		if sr.is_staging():
			continue
		var key := String(b.get("text", ""))
		if key != last:
			last = key
			await _settle(40)
			await _shot(tag)
		await _settle(8)
		sr.advance()


func _start(point: String) -> Node:
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _settle(4)
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get(point, {}) as Dictionary).duplicate(true))
	for i in 900:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	return main_node


func _stop(main_node: Node) -> void:
	if sr.mechanic_open:
		sr.close_mechanic()
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await _settle(4)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	_dir = OS.get_environment("SHOTS_DIR")
	# the photo in the mill passage, day two: the door and the board looked at — the photo is the last look (M09s)
	var m: Node = await _start("day2")
	for f in ["done_M09", "seen_office_door", "seen_shift_schedule"]:
		gs.set_flag(f, true)
	rm.change_room("M2", "from_M1")
	await _settle(60)
	var ph := _hotspot("photo")
	if ph != null:
		sr.interact(ph)
		await _play("photo", "done_M09s")
		await _settle(30)
		await _shot("photo_after")
	await _stop(m)
	# M21b: the morning of day three, M21 talked, the notebooks read — the village list
	m = await _start("day3")
	for f in ["started_M21", "done_M21", "o3_read_notebooks"]:
		gs.set_flag(f, true)
	await _settle(30)
	var vl := _hotspot("village_list")
	if vl != null:
		sr.interact(vl)
		await _play("m21b", "done_M21b")
	await _stop(m)
	quit(0)
