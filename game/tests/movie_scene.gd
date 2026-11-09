extends SceneTree
## A scene as played, for the Director to look at (09.11, 16:16 «давай» — the villagers' «more life» trial on one scene):
## the state before the scene (start point or the story before it), Agata clicks the villager, each line stays `line_s`
## seconds (stagings play out), for `secs` seconds in all. Run with Movie Maker:
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 --fixed-fps 30 --resolution 1280x720 \
##       --write-movie out.avi -s res://tests/movie_scene.gd -- <scene> <room> <click x,y> [secs=30] [line_s=4] [start_point]

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


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState"); rm = root.get_node("RoomManager"); sr = root.get_node("StoryRunner"); sd = root.get_node("StoryData")
	var a := OS.get_cmdline_user_args()
	var scene: String = a[0]; var room: String = a[1]
	var c := a[2].split(",")
	var secs := float(a[3]) if a.size() > 3 else 30.0
	var line_s := float(a[4]) if a.size() > 4 else 4.0
	var sp := a[5] if a.size() > 5 else ""
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	if sp != "":
		rm.start_at(sp)
	else:
		gs.reset()
		_flags_before(scene)
		rm.change_room(room, "default")
	for i in 20:
		await process_frame
	sr.call("_on_state_reset")
	rm.player.call("click_at", Vector2(float(c[0]), float(c[1])))
	var f := 0
	var on_line := 0
	var total := int(secs * 30.0)
	while f < total:
		await process_frame
		f += 1
		if sr.is_staging() or sr.current_beat.is_empty():
			on_line = 0
			continue
		on_line += 1
		if on_line >= int(line_s * 30.0):
			on_line = 0
			if sr.current_beat.get("type") == "options":
				sr.choose(String(sr.current_beat["options"][0]["id"]))
			else:
				sr.advance()
	quit(0)
