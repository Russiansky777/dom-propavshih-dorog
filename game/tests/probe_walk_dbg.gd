extends SceneTree
## One walk with its navigation path and the figure's state every 0.25 s (debugging a stall).
##   godot --path game -s res://tests/probe_walk_dbg.gd -- <room> <x0> <y0> <x1> <y1>

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
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room(a[0], "default", Vector2(float(a[1]), float(a[2])))
	for i in 40:
		await process_frame
	# first walk to the start point the way a player would (a click), then the logged walk
	player.walk_to(Vector2(float(a[1]), float(a[2])))
	var w0 := 0.0
	while w0 < 8.0:
		await process_frame
		w0 += player.get_process_delta_time()
		if w0 > 0.5 and not player.is_walking():
			break
	for i in 30:
		await process_frame
	var to := Vector2(float(a[3]), float(a[4]))
	print("DBG start %s → %s" % [str(player.global_position), str(to)])
	player.walk_to(to)
	var t := 0.0
	var next := 0.0
	while t < 6.0:
		await process_frame
		t += player.get_process_delta_time()
		if t >= next:
			next += 0.25
			var path: PackedVector2Array = player.nav_agent.get_current_navigation_path()
			print("DBG t %.2f pos %s walking %s w %.2f seg %d/%d path %s target_reached %s fin %s next %s" % [t, str(player.global_position.round()), player.is_walking(), player.walk_w, player._path_seg, path.size(), str(Array(path).map(func(p): return p.round())), player.nav_agent.is_target_reached(), player.nav_agent.is_navigation_finished(), str(player.nav_agent.get_next_path_position().round())])
	quit(0)
