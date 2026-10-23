extends SceneTree
## Frames of rooms at a moment of the story (time of day F17, school door F18, board F19) — real game under Xvfb:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --display-driver x11 --rendering-driver opengl3 \
##     --resolution 1920x1080 -s res://tests/shots_time.gd -- <out_dir> Z2@M16 H1@M06 M1@M09:930,650 …
## ROOM@SCENE — the room as the scene SCENE begins (every main scene before it done with its grants, like
## RoomManager.start_at); :x,y — Agata walks there first. «+flag» adds a flag (Z2@M16+stove_lit).
## Special: «view:ROOM@SCENE:hotspot» — click the hotspot and frame its close-up (M1 board);
## «puzzle:H3@M05» — the school door close-up after the right answer (the view into the class).
## Saved as <out_dir>/time_<ROOM>_<SCENE>.png (1920x1080).

var gs: Node
var rm: Node
var sr: Node
var sd: Node


func _initialize() -> void:
	_run()


func _flags_before(upto: String) -> void:
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == upto:
			break
		gs.flags["done_" + id] = true
		for f in sc.get("grants", {}).get("flags", []):
			gs.flags[String(f)] = true
	gs.flags["house_unlocked"] = true


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var specs: Array = args.slice(1)
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var made := 0
	for spec in specs:
		var s := String(spec)
		var kind := ""
		if s.begins_with("view:") or s.begins_with("puzzle:"):
			kind = s.get_slice(":", 0)
			s = s.substr(kind.length() + 1)
		var parts := s.split(":")
		var head := parts[0].split("+")
		var rs := head[0].split("@")
		var rid := rs[0]
		var scene := rs[1] if rs.size() > 1 else "M01"
		_flags_before(scene)
		for i in range(1, head.size()):
			gs.flags[head[i]] = true
		sr.call("_on_state_reset")
		rm.change_room(rid, "default")
		for i in 10:
			await physics_frame
		sr.call("_on_state_reset")
		if kind == "" and parts.size() > 1:
			var xy := parts[1].split(",")
			player.call("walk_to", Vector2(float(xy[0]), float(xy[1])))
			var frames := 0
			while player.call("is_walking") and frames < 1500:
				await physics_frame
				frames += 1
		if kind == "view" and parts.size() > 1:
			var hid := parts[1]
			for h in rm.current_room.get_hotspots():
				if String(h.get("hotspot_id")) == hid:
					sr.call("interact", h)
					break
			for i in 90:
				await process_frame
		if kind == "puzzle":
			for h in rm.current_room.get_hotspots():
				if h.get("data").has("puzzle"):
					sr.call("open_puzzle", h)
					break
			for i in 10:
				await process_frame
			sr.puzzle["view"] = "winter"   # the door standing open on the classroom (not «solved»: no auto close)
			sr.puzzle_state_changed.emit()
			for i in 40:
				await process_frame
		if kind != "puzzle":
			for i in 150:
				await process_frame
		root.warp_mouse(Vector2(1910, 600))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		var path := out_dir.path_join("time_%s%s_%s.png" % [kind + "_" if kind != "" else "", rid, scene])
		img.save_png(path)
		made += 1
		var tg: Node = rm.current_room.get_node_or_null("TimeOfDay")
		print("frame %s → %s (%s)" % [spec, path, str(tg.call("probe")) if tg != null else "no TimeOfDay"])
		if sr.get("view_open"):
			sr.call("close_view")
	gs.reset()
	quit(0 if made > 0 else 1)
