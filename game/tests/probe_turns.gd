extends SceneTree
## Turning while walking: for many clicks in a few rooms, the body's total turning during the walk vs the turning
## the path itself needs (start heading → each segment → arrival). A loop round a point shows as a surplus ≥ 300°.
##   godot --headless --path game -s res://tests/probe_turns.gd [-- accel_deg_s2]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		player._rt["turn"]["accel_deg_s2"] = float(args[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var loops := 0
	var n := 0
	for room in [["Z2", Vector2(960, 900)], ["H1", Vector2(1200, 960)], ["R1", Vector2(900, 900)], ["M1", Vector2(900, 900)]]:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
			gs.set_flag(f, true)
		rm.change_room(room[0], "default", room[1])
		for i in 10:
			await process_frame
		for k in 14:
			var tgt: Vector2 = player.global_position + Vector2(rng.randf_range(-600, 600), rng.randf_range(-250, 250))
			player.click_at(tgt)
			for i in 3:
				await process_frame
			if not player.is_walking():
				continue
			var path: PackedVector2Array = player.nav_agent.get_current_navigation_path()
			var need := 0.0
			var prev_yaw: float = player.yaw3d
			for j in range(1, path.size()):
				var d := path[j] - path[j - 1]
				if d.length() < 4.0:
					continue
				var y: float = player._yaw_for_screen(d)
				need += absf(angle_difference(prev_yaw, y))
				prev_yaw = y
			var turned := 0.0
			var run := 0.0
			var run_sign := 0.0
			var max_run := 0.0
			var last: float = player.yaw3d
			var guard := 0
			while (player.is_walking() or absf(player._yaw_v) > 0.05) and guard < 900:
				await process_frame
				guard += 1
				var stp := angle_difference(last, player.yaw3d)
				turned += absf(stp)
				if absf(stp) > 1e-4:
					if signf(stp) == run_sign:
						run += absf(stp)
					else:
						run_sign = signf(stp)
						run = absf(stp)
					max_run = maxf(max_run, run)
				last = player.yaw3d
				if OS.get_environment("TRACE") == room[0] + str(k):
					print("    f%d pos %s yaw %.0f tgt %.0f v %.1f dir %.0f walk %.2f shown %.2f dist %.0f rem %.0f walking %s" % [guard, str(player.global_position.round()), rad_to_deg(player.yaw3d), rad_to_deg(player.yaw3d_target), rad_to_deg(player._yaw_v), player._yaw_dir, player.walk_w, player.view3d.shown_w(), player.global_position.distance_to(tgt), player._remaining_px(), player.is_walking()])
			n += 1
			var surplus := rad_to_deg(max_run)
			worst = maxf(worst, surplus)
			if surplus > 230.0:
				loops += 1
				print("  %s walk %d: one way %.0f° (turned %.0f°, path needs %.0f°; %d points, %d frames)" % [room[0], k, rad_to_deg(max_run), rad_to_deg(turned), rad_to_deg(need), path.size(), guard])
	print("walks %d, loops (one way > 230°) %d, longest one-way turn %.0f°" % [n, loops, worst])
	PS.forced_render = ""
	quit(0)
