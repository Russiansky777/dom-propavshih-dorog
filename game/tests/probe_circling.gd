extends SceneTree
## The motion test's 60 walks (seed 11) with the foot locks on or off: where each walk ends and its longest
## one-way turn.   -- <0|1> [room filter]

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
	player.foot_lock_3d = OS.get_cmdline_user_args()[0] == "1"
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 11
	for room in [["Z2", Vector2(960, 900)], ["H1", Vector2(1200, 960)], ["R1", Vector2(900, 900)], ["M1", Vector2(900, 900)]]:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
			gs.set_flag(f, true)
		rm.change_room(room[0], "default", room[1])
		for i in 10:
			await process_frame
		for wk in 15:
			var goal: Vector2 = player.global_position + Vector2(wrng.randf_range(-600, 600), wrng.randf_range(-250, 250))
			player.click_at(goal)
			await process_frame
			if not player.is_walking():
				continue
			var run := 0.0
			var run_sign := 0.0
			var max_run := 0.0
			var last: float = player.yaw3d
			var guard := 0
			var trace: Array = ["start yaw %.0f at %s" % [rad_to_deg(player.yaw3d), str(player.global_position.round())]]
			var paths: Array = []
			while (player.is_walking() or absf(player._yaw_v) > 0.05) and guard < 900:
				await process_frame
				guard += 1
				var stp := angle_difference(last, player.yaw3d)
				last = player.yaw3d
				if OS.get_environment("FRAMES") != "" and room[0] == "Z2" and wk == 0:
					print("F %d pos %.4f,%.4f yaw %.5f w %.5f ph %.5f side %d shown %.5f" % [guard, player.global_position.x, player.global_position.y, player.yaw3d, player.walk_w, player.walk_phase, player._rm_side, player.view3d.shown_w()])
				var pth: PackedVector2Array = player.nav_agent.get_current_navigation_path()
				var ps := str(Array(pth).map(func(q): return q.round()))
				if paths.is_empty() or paths[-1] != ps:
					paths.append(ps)
					trace.append("PATH@%d %s" % [guard, ps])
				if guard % 4 == 0:
					trace.append("%.0f,%.0f y%.0f w%.2f" % [player.global_position.x, player.global_position.y, rad_to_deg(player.yaw3d), player.walk_w])
				if absf(stp) > 1e-4:
					run = run + absf(stp) if signf(stp) == run_sign else absf(stp)
					run_sign = signf(stp)
					max_run = maxf(max_run, run)
			print("%s %d: end %s frames %d run %.0f°" % [room[0], wk, str(player.global_position.round()), guard, rad_to_deg(max_run)])
			if rad_to_deg(max_run) > 200.0:
				print("    goal %s  %s" % [str(goal.round()), " | ".join(trace)])
	quit(0)
