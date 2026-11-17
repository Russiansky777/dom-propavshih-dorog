extends SceneTree
## Review 17.11: what happens beat by beat when the photo in the mill passage is clicked on day two with M09 done.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_photo_lines.gd

var gs
var rm
var sr
var sd


func _initialize() -> void:
	create_timer(200.0).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("day2", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	gs.set_flag("done_M09", true)
	rm.change_room("M2", "from_M1")
	var last := ""
	for i in 30:
		await process_frame
		var k := "%s|%s|%s|mech %s" % [String(sr.active_scene), String(sr.current_beat.get("type", "")), String(sr.current_beat.get("text", "")).left(40), str(sr.mechanic_open)]
		if k != last:
			last = k
			print("enter f%d: %s" % [i, k])
	var ph: Node = null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == "photo":
			ph = h
	print("photo hotspot: ", ph, " visible ", (ph as CanvasItem).visible if ph != null else false)
	sr.interact(ph)
	for i in 900:
		await process_frame
		var k := "%s|%s|%s|mech %s|busy %s" % [String(sr.active_scene), String(sr.current_beat.get("type", "")), String(sr.current_beat.get("text", "")).left(40), str(sr.mechanic_open), str(sr.is_busy())]
		if k != last:
			last = k
			print("f%d: %s" % [i, k])
		if not sr.current_beat.is_empty() and not sr.is_staging() and i % 20 == 19:
			sr.advance()
	quit(0)
