extends SceneTree
## CI 43319182713 (13.11): test_feedback_0511 «0511-4 … the real walk from the pocket round Nina: no stepping on the
## spot ({pos (1489, 786), worst 1.0, t 1.61, stops 1})» — green in the two runs before. The same walk N times, per
## run: how long the legs walked with the body held (the test's measure: walk_w > 0.5, under 25 px/s frame to frame),
## where it ended, how many times the guard's own count was set back to zero while she stood, the largest speed a
## single frame showed while the body moved under 2 px in all, the frame times.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_o3_stall.gd [-- runs=N]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var runs := 10
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("runs="):
			runs = int(String(a).get_slice("=", 1))
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("O3", "default", Vector2(-1, -1))
	for i in 30:
		await process_frame
	for r in runs:
		for p in [Vector2(1640, 900), Vector2(1510, 770)]:
			player.walk_to(p)
			var g := 0
			while bool(player.call("is_walking")) and g < 900:
				await process_frame
				g += 1
		player.global_position = Vector2(1489, 785)
		for i in 20:
			await process_frame
		var stops0 := int(player.get("stall_stops"))
		player.walk_to(Vector2(210, 840))
		var t := 0.0
		var stall := 0.0
		var worst := 0.0
		var last: Vector2 = player.global_position
		var start: Vector2 = last
		var resets := 0
		var prev_guard := 0.0
		var vmax_held := 0.0
		var dmin := 1.0
		var dmax := 0.0
		var frames := 0
		var trace: Array = []
		var na: NavigationAgent2D = player.get("nav_agent")
		while t < 8.0:
			await process_frame
			var d: float = player.get_process_delta_time()
			t += d
			frames += 1
			if frames == 12 or frames == 40:
				trace.append("f%d path %s seg %d" % [frames, str(Array(na.get_current_navigation_path()).map(func(q): return (q as Vector2).round())), int(player.get("_path_seg"))])
			if frames % 20 == 0 and frames <= 200:
				trace.append("f%d pos %s yaw %.0f° → %.0f° step %s w %.2f" % [frames, str(player.global_position.snapped(Vector2(0.1, 0.1))), rad_to_deg(float(player.get("yaw3d"))), rad_to_deg(float(player.get("yaw3d_target"))), str((player.get("rm_last_px") as Vector2).snapped(Vector2(0.01, 0.01))), float(player.get("walk_w"))])
			dmin = minf(dmin, d)
			dmax = maxf(dmax, d)
			var v: float = player.global_position.distance_to(last) / maxf(d, 0.001) / maxf(absf(player.scale.y), 0.05)
			last = player.global_position
			if not bool(player.call("is_walking")):
				break
			var gt := float(player.get("_stall_t"))
			if gt < prev_guard and player.global_position.distance_to(start) < 4.0:
				resets += 1
			prev_guard = gt
			if player.global_position.distance_to(start) < 4.0:
				vmax_held = maxf(vmax_held, v)
			if float(player.get("walk_w")) > 0.5 and v < 25.0:
				stall += d
				worst = maxf(worst, stall)
			else:
				stall = 0.0
		print("run %d: worst %.2f s, ended at %s after %.2f s (%d frames, frame %.1f–%.1f ms), guard stops %d, guard set back while held %d, top frame speed while held %.0f px/s%s" % [r + 1, worst, str(player.global_position.round()), t, frames, dmin * 1000.0, dmax * 1000.0, int(player.get("stall_stops")) - stops0, resets, vmax_held, "  STILL WALKING" if bool(player.call("is_walking")) else ""])
		if OS.get_cmdline_user_args().has("trace") and (worst > 0.4 or r == 0):
			for line in trace:
				print("      ", line)
		if bool(player.call("is_walking")):
			player.call("_cancel_walk")
		for i in 10:
			await process_frame
	PS.forced_render = ""
	quit(0)
