extends SceneTree
## Evidence frames of a conversation with an NPC (not a test; needs a display — tools/shots_dialogue.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_dialogue.gd \
##     -- <out_dir> Z1:tamara R1:pelageya
## For every ROOM:HOTSPOT the real game (Main.tscn) enters the room, Agata walks to the hotspot's stand and
## interacts exactly as after a click (walk_to_and_interact), and the frame is saved once the first
## dialogue line is shown: <out_dir>/talk_<ROOM>_<hotspot>.png. Defect behind it (frame ui_10): Agata stood
## right in front of Tamara and covered her; validate_rooms.py item 9 checks the stands from data.

const PRE_FLAGS := {"R1": ["done_M01"]}


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
	var pairs: Array = args.slice(1) if args.size() > 1 else ["Z1:tamara", "R1:pelageya"]
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	player.set("speed_factor", 3.0)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var made := 0
	for pair in pairs:
		var parts := String(pair).split(":")
		var rid := parts[0]
		var hid := parts[1]
		gs.reset()
		for f in PRE_FLAGS.get(rid, []):
			gs.set_flag(f, true)
		rm.change_room(rid, "default")
		for i in 10:
			await physics_frame
		var hs: Node2D = rm.current_room.get_node_or_null("Hotspots/" + hid)
		if hs == null:
			push_error("shots_dialogue: no hotspot %s in %s" % [hid, rid])
			continue
		player.call("walk_to_and_interact", hs)
		var frames := 0
		while sr.current_beat.is_empty() and frames < 1500:
			await physics_frame
			frames += 1
		for i in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		var path := out_dir.path_join("talk_%s_%s.png" % [rid, hid])
		img.save_png(path)
		made += 1
		print("dialogue frame %s/%s: Agata at %s facing row %d, beat %s → %s" % [rid, hid, str(player.global_position.round()),
			int(player.get("direction")), String(sr.current_beat.get("speaker", sr.current_beat.get("type", "?"))), path])
		while not sr.current_beat.is_empty():
			if sr.current_beat.get("type") == "options":
				sr.choose(String(sr.current_beat.get("options", [])[0].get("id", "")))
			else:
				sr.advance()
			await process_frame
	gs.reset()
	quit(0 if made > 0 else 1)
