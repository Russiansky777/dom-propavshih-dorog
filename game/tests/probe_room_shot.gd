extends SceneTree
## A room as the player sees it, with given flags (rendered; needs a display).
##   godot --path game -s res://tests/probe_room_shot.gd -- <out.png> <room> [flag,flag,...] [x,y] [seconds]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = OS.get_environment("RENDER") if OS.get_environment("RENDER") != "" else "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	gs.reset()
	if a.size() > 2 and a[2] != "":
		for f in a[2].split(","):
			gs.set_flag(f, true)
	var pos := Vector2.INF
	if a.size() > 3 and a[3] != "":
		var xy := a[3].split(",")
		pos = Vector2(float(xy[0]), float(xy[1]))
	rm.change_room(a[1], "default", pos)
	var wait := float(a[4]) if a.size() > 4 else 1.5
	var t := 0.0
	while t < wait:
		await process_frame
		t += 1.0 / 60.0
	# no lines over the picture
	var sr = root.get_node("StoryRunner")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(a[0])
	print("SHOT %s %s" % [a[0], str(rm.current_room.get("room_id"))])
	quit(0)
