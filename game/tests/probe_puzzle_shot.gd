extends SceneTree
## The school door close-up (M05) as the player sees it, the beam moved so that notch `n` is near the door's mark
## (rendered): godot --path game -s res://tests/probe_puzzle_shot.gd -- <out.png> [notch] [offset_px]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "done_M04"]:
		gs.set_flag(f, true)
	gs.add_item("door_hinges")
	rm.change_room("H3", "default")
	for i in 10:
		await process_frame
	var h = null
	for x in rm.current_room.get_hotspots():
		if x.hotspot_id == "school_door":
			h = x
	sr.open_puzzle(h)
	for i in 20:
		await process_frame
	var cp: Node = null
	for n in main_node.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("closeup_puzzle.gd"):
			cp = n
	if cp != null and a.size() > 1:
		var k := int(a[1])
		var off := float(a[2]) if a.size() > 2 else 0.0
		var nb: Array = cp.get("notch_base")
		var dx: float = float(cp.get("anchor").x) - float(nb[k].x) + off
		cp.set("_beam_dx", dx)
		cp.set("_beam_shown_dx", dx)
		cp.call("_update_beam_visuals")
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	print("SHOT ", a[0], " panel ", cp != null)
	quit(0)
