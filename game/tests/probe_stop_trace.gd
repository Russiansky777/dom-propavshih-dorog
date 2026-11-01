extends SceneTree
## Frame trace of one stop (Director 01.11, morning page: «при остановке — семенит, доступает»): per frame the commanded
## and shown walk weights, the stop plan, the stride hold / closing state, both feet's height and whether a lock or a
## lock-step holds them, and the figure's ground speed. Walk k as in probe_stop_steps.gd.
##   godot --path game --fixed-fps 60 -s res://tests/probe_stop_trace.gd -- <k>

var _drawn: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var k := int(args[0]) if args.size() > 0 else 0
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
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("Z2", "default", Vector2(500 + (k % 3) * 150, 860 + (k % 2) * 80))
	for i in 20:
		await process_frame
	var v: Actor3D = player.view3d
	v.seed_idle(60 + k)
	seed(60 + k)
	v.skeleton.skeleton_updated.connect(_on_upd.bind(v))
	var ang := PI * 0.5 + (k - 2.5) * 0.25
	player.yaw3d = ang
	player.yaw3d_target = ang
	for i in 30:
		await process_frame
	var kf: float = player.floor_foreshortening()
	var dist := float(args[1]) if args.size() > 1 else 500.0 + k * 40.0
	player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * kf) * dist)
	var t := 0.0
	var tracing := false
	var after := 0.0
	var prev := player.global_position
	var ppm_s: float = v.ppm * absf(player.scale.y)
	print("t walk_w shown_w plan hold keep closing | L_h L_state R_h R_state | speed_mps pos")
	while after < 1.2 and t < 8.0:
		await process_frame
		var d: float = player.get_process_delta_time()
		t += d
		if not tracing and player.is_walking() and (player.walk_w < 0.99 or not player._stop_plan.is_empty()) and player.walk_time > 0.3:
			tracing = true
		if not tracing:
			prev = player.global_position
			continue
		if not player.is_walking():
			after += d
		var f: Array = _drawn if not _drawn.is_empty() else v.feet_model()
		var hs: Array = []
		for i in 2:
			var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
			var st := "step%.2f" % float(v._foot_step[i][1]) if v._foot_step[i] != null else ("lock" if v._foot_lock[i] != null else ("st%.1f" % float(v._st_w[i]) if v._st_t[i] != null else "-"))
			hs.append("%.3f %s" % [h, st])
		var sp := (player.global_position - prev).length() / ppm_s / maxf(d, 1e-4)
		prev = player.global_position
		var pl: Dictionary = player._stop_plan
		var u := "-"
		if not pl.is_empty():
			u = "%.2f" % clampf((player.walk_phase - float(pl["ph0"])) / maxf(float(pl["dph"]), 0.01), 0.0, 1.0)
			var dbg: Array = pl.get("dbg", [0.0, 0.0])
			u += " rem%.3f/%.3f" % [float(dbg[0]), float(dbg[1])]
		var errs := "-"
		if v.dbg_errs.size() == 2:
			errs = "e%.3f/%.3f" % [float(v.dbg_errs[0]), float(v.dbg_errs[1])]
		var fm: Array = v.feet_model()
		print("%.3f %.2f %.2f %s %s %s %d | %s | %s | %.2f %s side%d drift%.3f %s rm%.2f z%.3f/%.3f off%.3f/%.3f reach%.3f/%.3f" % [t, player.walk_w, v.shown_w(), u, str(v.stride_hold)[0], str(v.stride_hold_keep)[0], v._closing, hs[0], hs[1], sp, str(player.global_position.round()), player._rm_side, float(pl.get("drift", -1.0)), errs, player.rm_last_px.length(), fm[0].z, fm[2].z, (v.stride_off[0] as Vector3).length(), (v.stride_off[1] as Vector3).length(), float(v.dbg_reach[0]), float(v.dbg_reach[1])])
	PS.forced_render = ""
	quit(0)


func _on_upd(v: Actor3D) -> void:
	_drawn = v.feet_model()
