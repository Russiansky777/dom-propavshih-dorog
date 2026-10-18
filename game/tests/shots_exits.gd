extends SceneTree
## Frames of the exit hints in the real game (not a test; needs a display — tools/shots_exits.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_exits.gd \
##     -- <out_dir> [ROOM ...]
## For every room (default: rooms/_index.json in_scope) the game enters it as after M01 (exits open),
## lets the marks fade in and saves:
##   exits_<ROOM>.png         — the room as the player sees it: exit marks idle, pointer on nothing;
##   exits_<ROOM>_hover.png   — the pointer on the first exit with a mark (or the first drawn door):
##                              the mark lit, the caption (the OS cursor itself is not in a frame);
##   exits_<ROOM>_reveal.png  — 0.5 s after Space: every hotspot and exit named.
## A line per exit goes to stdout (direction, mark position) for the log.


func _initialize() -> void:
	_run()


func _wait_s(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	img.save_png(path)


## A point where the pointer hovers nothing (no caption, no lit mark in the frame).
func _park(room) -> Vector2:
	for p in [Vector2(960, 150), Vector2(700, 300), Vector2(1300, 300), Vector2(960, 760), Vector2(500, 760), Vector2(1400, 800)]:
		if room.pick(p) == null:
			return p
	return Vector2(960, 150)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var sd = root.get_node("StoryData")
	var rooms: Array = args.slice(1) if args.size() > 1 else sd.rooms_index.get("in_scope", [])
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	var ui = main_node.get_node("GameUi")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var made := 0
	for rid in rooms:
		gs.set_flag("done_M01", true)
		gs.set_flag("has_key_house", true)
		gs.set_flag("house_unlocked", true)   # the front door is open once the key was applied (18.10)
		sr.call("_on_state_reset")
		rm.change_room(String(rid), "default")
		for i in 10:
			await physics_frame
		sr.call("_on_state_reset")   # no enter-scene text over the frame
		var room = rm.current_room
		var park := _park(room)
		root.warp_mouse(park)
		await _wait_s(2.0)           # marks fade in (0.4 s), drizzle and sway settle
		var first_mark: Node = null
		var first_door: Node = null
		for e in room.get_exits():
			if not e.has_method("cursor_kind"):
				continue
			var line := "%s→%s: %s (%s)" % [rid, e.target_room, e.cue_dir, e.cue_source]
			if e.cue != null:
				line += " mark at (%.0f, %.0f)" % [e.cue.global_position.x, e.cue.global_position.y]
				if first_mark == null:
					first_mark = e
			elif first_door == null:
				first_door = e
			print("exit " + line)
		var base := out_dir.path_join("exits_%s" % rid)
		await _save(base + ".png")
		var target = first_mark if first_mark != null else first_door
		if target != null:
			var at: Vector2 = target.cue.global_position if target.cue != null else target.global_position
			root.warp_mouse(at)
			await _wait_s(0.6)
			await _save(base + "_hover.png")
			print("hover %s→%s: cursor %s, caption «%s»" % [rid, target.target_room, ui.get("_cursor_kind"), ui.get("hover_label").text])
		root.warp_mouse(park)
		await _wait_s(0.4)
		ui.call("reveal_hotspots")
		await _wait_s(0.5)
		await _save(base + "_reveal.png")
		made += 1
		print("room frame %s → %s{,_hover,_reveal}.png" % [rid, base])
		await _wait_s(1.2)
	gs.reset()
	quit(0 if made > 0 else 1)
