extends SceneTree
## 13.11: the evening with the family in Nina's room (after M20) — where a click on the floor sends Agata and how long
## she walks: per click the place she stops at, the seconds it took, whether she is still «walking» at the cap.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_family_walk.gd [-- x,y x,y …]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var sd = root.get_node("StoryData")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	sr.call("_on_state_reset")
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		if id == "M20":
			break
	rm.change_room("O3", "from_O4")
	for i in 30:
		await physics_frame
	sr.call("_cancel_stage")
	sr.current_beat = {}
	var player: Node2D = main_node.get_node("World/Player")
	var clicks: Array = []
	for a in OS.get_cmdline_user_args():
		var p := String(a).split(",")
		if p.size() == 2:
			clicks.append(Vector2(float(p[0]), float(p[1])))
	if clicks.is_empty():
		clicks = [Vector2(1610, 950), Vector2(1300, 900), Vector2(1150, 800), Vector2(1500, 1040), Vector2(1090, 840), Vector2(1850, 900)]
	for c in clicks:
		var from := player.global_position
		player.call("walk_to", c)
		var t := 0.0
		var path := 0.0
		var last := from
		while t < 0.2 or (bool(player.call("is_walking")) and t < 20.0):
			await physics_frame
			t += 1.0 / 60.0
			path += player.global_position.distance_to(last)
			last = player.global_position
		print("click %s: from %s → stops at %s after %.2f s (walked %.0f px)%s" % [str(c), str(from.round()), str(player.global_position.round()), t, path, "  STILL WALKING" if bool(player.call("is_walking")) else ""])
	# a click on a thing or a villager: she walks to its stand and acts
	for id in ["nina", "window", "icon", "bed"]:
		var hs: Node = rm.current_room.get_node_or_null("Hotspots/" + id)
		if hs == null:
			continue
		player.global_position = rm.current_room.get_spawn("from_O4").global_position
		for i in 4:
			await physics_frame
		var stand: Vector2 = hs.call("get_stand_position")
		player.call("walk_to_and_interact", hs)
		var t := 0.0
		var said_at := -1.0
		while t < 0.2 or ((bool(player.call("is_walking")) or (sr.current_beat.is_empty() and t < 3.0)) and t < 20.0):
			await physics_frame
			t += 1.0 / 60.0
			if said_at < 0.0 and not sr.current_beat.is_empty():
				said_at = t
		print("click on %s: stand %s → stops at %s after %.2f s; a line came at %.2f s: %s" % [id, str(stand), str(player.global_position.round()), t, said_at, String(sr.current_beat.get("text", "—")).substr(0, 40)])
		sr.current_beat = {}
		sr.call("_cancel_stage")
		for i in 20:
			await physics_frame
	quit(0)
