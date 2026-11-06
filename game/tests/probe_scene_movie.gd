extends SceneTree
## A scene played in the game for a video (block 3, Director 05.11, 23:54: «запиши видео с анимациями»): the story
## state is set as if every earlier scene were done, the room is entered and the scene runs by itself — lines before
## `from` are clicked through at once, from `from` on each line stays while it is being said (voice) plus `hold` s,
## stagings run as in play. Run with a display and Godot's movie writer:
##   xvfb-run godot --path game --write-movie out.avi --fixed-fps 30 --resolution 1920x1080 \
##       -s res://tests/probe_scene_movie.gd -- <scene> <room> [from=0] [to=-1] [flag,flag] [tail_s=2] [max_s=90]
## max_s — the recording stops after that many seconds from line `from` whatever happens (a staging that waits).

var gs
var rm
var sr
var sd


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


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	var a := OS.get_cmdline_user_args()
	var scene: String = a[0]
	var room: String = a[1]
	var from := int(a[2]) if a.size() > 2 else 0
	var to := int(a[3]) if a.size() > 3 else -1
	var tail := float(a[5]) if a.size() > 5 else 2.0
	var max_s := float(a[6]) if a.size() > 6 else 90.0
	var rec_s := 0.0
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	_flags_before(scene)
	if a.size() > 4 and String(a[4]) != "" and String(a[4]) != "-":
		for f in String(a[4]).split(","):
			gs.set_flag(f, true)
	rm.change_room(room, "default")
	for i in 45:
		await process_frame
	sr.call("_on_state_reset")
	sr.start_scene(scene)
	var vd := root.get_node_or_null("VoiceDirector")
	var idx := 0
	var g := 0
	var held := 0.0
	while g < 60000:
		g += 1
		await process_frame
		if idx >= from:
			rec_s += 1.0 / 30.0
			if rec_s > max_s:
				break
		# a close-up mini-game opened by the scene (the windlass at M25): played by itself for the video — «Пускай»,
		# then «Стой» when the log's end is at the mark on the ring
		if bool(sr.get("mechanic_open")):
			await _autoplay_mechanic()
			continue
		if sr.is_staging():
			continue
		if sr.current_beat.is_empty():
			if gs.has_flag("done_" + scene) or (to >= 0 and idx > to):
				break
			continue
		if to >= 0 and idx > to:
			break
		if idx >= from:
			if vd != null and bool(vd.call("line_being_said", sr.current_beat)):
				held = 0.0
				continue
			held += 1.0 / 30.0
			if held < 0.6:
				continue
		held = 0.0
		if sr.current_beat.get("type") == "options":
			sr.choose(String(sr.current_beat["options"][0]["id"]))
		else:
			sr.advance()
		idx += 1
	var t := 0.0
	while t < tail:
		await process_frame
		t += 1.0 / 30.0
	quit(0)


var _mech_done := false


func _autoplay_mechanic() -> void:
	if _mech_done:
		return
	_mech_done = true
	var mv = root.find_child("MechanicView", true, false)
	var p = mv.get("panel") if mv != null else null
	if p == null or not p.has_method("signal_pressed"):
		return
	for i in 45:
		await process_frame
	p.call("signal_pressed", "lower")
	var g := 0
	while g < 900 and not p.logic.at_ring():
		g += 1
		await process_frame
	p.call("signal_pressed", "stop")
	for i in 150:
		await process_frame
