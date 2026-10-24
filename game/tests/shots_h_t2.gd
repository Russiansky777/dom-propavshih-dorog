extends SceneTree
## Batch H, T2 frames from the real game under Xvfb (not a test; tools/shots_h_t2.sh → Docs/evidence/H/T2_*.jpg):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_h_t2.gd -- <out_dir> [names…]
## Each shot sets the story flags, enters the room, clicks like the mouse (Player.click_at on the hotspot) and saves the
## frame at the moment that shows the point: the bed in the attic (H17), the scarf over the shelf (H12), the cup
## touched on the table (H15), the lever reached (H29), Pavel at the open door (H24), Pavel at the office door (H28).

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var player: Node2D
var out_dir := ""


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _flags_before(upto: String, extra: Array = []) -> void:
	sr._on_state_reset()
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == upto:
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for rid in sd.scene_trigger_rooms(id):
			var cw = sd.room(rid).get("scenes", {}).get(id, {}).get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []):
					gs.set_flag(String(f), true)
	for f in ["house_unlocked", "house_open", "h1_shutter_open", "h1_scarf_removed"]:
		gs.set_flag(f, true)
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(rid: String, spawn: String = "default") -> void:
	rm.change_room(rid, spawn)
	for i in 10:
		await physics_frame
	sr._on_state_reset()
	await _frames(30)


func _hotspot(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("Hotspots/" + id)


func _click(id: String) -> void:
	var h := _hotspot(id)
	if h != null:
		player.call("click_at", h.global_position)


func _wait_walk(limit: int = 1500) -> void:
	var f := 0
	await physics_frame
	while player.call("is_walking") and f < limit:
		await physics_frame
		f += 1


func _shot(name: String) -> void:
	root.warp_mouse(Vector2(4, 1076))
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join("T2_%s.jpg" % name)
	img.save_jpg(path, 0.85)
	print("shot %s → %s" % [name, path])


func _skip_beats(limit: int = 600) -> void:
	var g := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and g < limit:
		g += 1
		if not sr.current_beat.is_empty() and sr.current_beat.get("type") != "options":
			sr.advance()
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/H")
	var only: Array = args.slice(1)
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var all := ["H17_bed_early", "H17_bed_late", "H12_scarf_over_shelf", "H12_shelf_on_bench", "H15_cup_touch", "H29_lever", "H24_door_open", "H28_pavel_door"]
	for n in all:
		if not only.is_empty() and not only.has(n):
			continue
		await call("_shot_" + n)
	gs.reset()
	quit(0)


func _shot_H17_bed_early() -> void:
	_flags_before("M23a", ["done_M23b"])
	await _enter("H4", "from_H1")
	_click("bed")
	await _wait_walk()
	await _frames(40)
	await _shot("H17_bed_early")
	await _skip_beats()


func _shot_H17_bed_late() -> void:
	_flags_before("N01")
	await _enter("H4", "from_H1")
	_click("bed")
	await _wait_walk()
	await _frames(40)
	await _shot("H17_bed_late")
	await _skip_beats(3000)


func _shot_H12_scarf_over_shelf() -> void:
	_flags_before("M03")
	gs.set_flag("h1_scarf_removed", false)
	await _enter("H1", "from_Z2")
	await _shot("H12_scarf_over_shelf")


func _shot_H12_shelf_on_bench() -> void:
	_flags_before("M04", ["met_tikhon", "stove_lit"])
	await _enter("H1", "from_Z2")
	_click("shelf")
	await _wait_walk()
	await _frames(60)
	await _shot("H12_shelf_on_bench")
	if sr.current_beat.get("type") == "options":
		sr.choose("B")
	await _skip_beats()


func _shot_H15_cup_touch() -> void:
	_flags_before("M04", ["met_tikhon", "stove_lit"])
	await _enter("H1", "from_Z2")
	_click("cups")
	await _wait_walk()
	var g := 0
	while sr.current_beat.get("type") != "options" and g < 600:
		g += 1
		await process_frame
	sr.choose("blue")
	await _frames(2)
	if not sr.current_beat.is_empty():
		sr.advance()
	await _wait_walk()
	await _frames(14)
	await _shot("H15_cup_touch")
	await _skip_beats()


func _shot_H29_lever() -> void:
	_flags_before("M13", ["visited_M3"])
	await _enter("M3", "from_M2")
	_click("key_nail")
	await _wait_walk()
	await _frames(16)
	await _shot("H29_lever")
	await _skip_beats()


func _shot_H24_door_open() -> void:
	_flags_before("M09b")
	await _enter("M1", "default")
	sr.start_scene("M09b")
	var g := 0
	while rm.current_room.get_node_or_null("StageDoor") == null and g < 3000:
		g += 1
		if not sr.current_beat.is_empty() and sr.current_beat.get("type") != "options":
			sr.advance()
		elif sr.current_beat.get("type") == "options":
			sr.choose(String(sr.current_beat["options"][0]["id"]))
		await process_frame
	await create_timer(0.95).timeout
	await _shot("H24_door_open")
	await _skip_beats(3000)


func _shot_H28_pavel_door() -> void:
	_flags_before("M10", ["pavel_blessed_mirror", "has_mirror_mill"])
	await _enter("M2", "from_M1")
	await _shot("H28_pavel_door")
