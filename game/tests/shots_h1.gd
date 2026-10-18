extends SceneTree
## Frames of H1 states in the real game (not a test; needs a display — tools/shots_h1.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_h1.gd \
##     -- <out_dir> "start||1200,900|" "shelf_a|done_M03,met_tikhon,q04_corner_stove,done_Q04|1200,900|450,500"
## Spec: name|flags (comma)|Agata x,y (placed, not walked)|pointer x,y (hover caption; empty — bare corner).
## Flags are set before entering, so no scene starts on entry (pass done_* for finished scenes). The frame
## is <out_dir>/H1_v2_<name>.png (1920x1080) and the hovered hotspot is printed.


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M1")
	var specs: Array = args.slice(1)
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(out_dir)
	var made := 0
	for spec in specs:
		var p := String(spec).split("|")
		var name := p[0]
		gs.reset()
		gs.set_flag("done_M01", true)
		gs.set_flag("done_M02", true)
		gs.add_item("key_house")
		if p.size() > 1 and p[1] != "":
			for f in p[1].split(","):
				gs.set_flag(f, true)
		var pos := Vector2.INF
		if p.size() > 2 and p[2] != "":
			var xy := p[2].split(",")
			pos = Vector2(float(xy[0]), float(xy[1]))
		rm.change_room("H1", "default", pos)
		for i in 150:
			await process_frame
		var hover := Vector2(4, 1076)
		if p.size() > 3 and p[3] != "":
			var hxy := p[3].split(",")
			hover = Vector2(float(hxy[0]), float(hxy[1]))
		root.warp_mouse(hover)
		var ev := InputEventMouseMotion.new()
		ev.position = hover
		ev.global_position = hover
		root.push_input(ev)
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		var path := out_dir.path_join("H1_v2_%s.png" % name)
		img.save_png(path)
		made += 1
		var room = rm.current_room
		var hit = room.pick(hover) if room != null else null
		var pups: Array = load("res://scripts/actors/puppet_actor.gd").all_in(room)   # not the class name: compiled after the autoloads
		var pup_s := ""
		if not pups.is_empty():
			var t = pups[0]
			pup_s = "tikhon place %d feet %s h %.0f z %d mirror %s" % [t.place_index, str(t.global_position.round()), t.figure_height_px(), t.z_index, str(t.scale.x < 0)]
		print("H1 frame %s: flags %s; under pointer %s: %s; %s → %s" % [name, p[1] if p.size() > 1 else "", str(hover), str(hit.name) if hit else "nothing", pup_s, path])
	gs.reset()
	quit(0 if made > 0 else 1)
