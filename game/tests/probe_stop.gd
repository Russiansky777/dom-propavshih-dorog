extends SceneTree
## Stopping: the planted (lower) foot's slide on the floor from 0.7 s before the arrival to 0.6 s after, per walk;
## and turning on the spot (150°): the lower foot's slide.
##   godot --headless --path game -s res://tests/probe_stop.gd

var _feet: Array = []
var _v: Actor3D = null


func _initialize() -> void:
	_run()


## The feet as drawn (after the modifiers: the IK locks).
func _on_updated() -> void:
	_feet = _v.feet_model()


func _m(d: Vector2, ppm_s: float, kf: float) -> float:
	return Vector2(d.x / ppm_s, d.y / (ppm_s * kf)).length()


func _track(player, v: Actor3D, secs: float, until_stop: bool) -> float:
	var kf: float = player.floor_foreshortening()
	var ppm_s: float = v.ppm * absf(player.scale.y)
	var planted := {}
	var worst := 0.0
	var t := 0.0
	var after := 0.0
	while (until_stop and (player.is_walking() or after < 0.6)) or (not until_stop and t < secs):
		await process_frame
		var d: float = player.get_process_delta_time()
		t += d
		if until_stop and not player.is_walking():
			after += d
		var f := _feet if not _feet.is_empty() else v.feet_model()
		ppm_s = v.ppm * absf(player.scale.y)
		var yb := Basis(Vector3.UP, player.yaw3d)
		var counting: bool = (not until_stop) or player.walk_w < 0.97 or not player.is_walking()
		# each foot on the floor (ankle at most 2 cm above its stance height and 1.5 cm above the other): how far its point on the screen floor
		# has gone since it was set down — the skating a viewer sees; a lifted foot (a step) is not counted
		var line := ""
		for i in 2:
			var foot: Vector3 = yb * f[i * 2]
			var wp := Vector2(player.global_position.x + foot.x * ppm_s, player.global_position.y + foot.z * ppm_s * kf)
			var low: float = minf(f[0].y, f[2].y)
			var down: bool = foot.y <= float(v._foot_rest_h[i]) + 0.02 and foot.y <= low + 0.015
			if not down or not counting or not planted.has(i):
				planted[i] = wp
			if down and counting:
				worst = maxf(worst, _m(wp - planted[i], ppm_s, kf))
			if v.foot_ik[i].influence >= 0.999:
				var miss: float = Vector2(v._foot_target[i].position.x - foot.x, v._foot_target[i].position.z - foot.z).length()
				if miss > 0.015:
					var an2 := v.feet_model()
					print("   MISS %s %.0f mm t %.2f walk %.2f shown %.2f step %s tgt %s drawn %s anim %s" % ["L" if i == 0 else "R", miss * 1000.0, t, player.walk_w, v.shown_w(), str(v._foot_step[i] != null), str(v._foot_target[i].position.snapped(Vector3.ONE * 0.01)), str(foot.snapped(Vector3.ONE * 0.01)), str((yb * an2[i * 2]).snapped(Vector3.ONE * 0.01))])
			var an3: Vector3 = yb * v.feet_model()[i * 2]
			line += " | %s %s drawn %s anim %s lock %s st %s" % ["L" if i == 0 else "R", "down" if down else "up  ", str(Vector2(foot.x, foot.z).snapped(Vector2.ONE * 0.01)), str(Vector2(an3.x, an3.z).snapped(Vector2.ONE * 0.01)), str(v._foot_lock[i] != null), ("%.2f" % v._foot_step[i][1]) if v._foot_step[i] != null else "-"]
		if OS.get_environment("TRACE") != "" and Engine.get_process_frames() % 3 == 0:
			print("   t %.2f yaw %.0f yawv %.1f shown %.2f%s" % [t, rad_to_deg(player.yaw3d), v._feet_yaw_v, v.shown_w(), line])
	return worst


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
	player.foot_lock_3d = not (OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "0")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	var stops := []
	var turns := []
	var ks: Array = range(10) if OS.get_environment("TRACE") == "" else [int(OS.get_environment("TRACE"))]
	for k in ks:
		rm.change_room("Z2", "default", Vector2(700 + (k % 3) * 200, 850 + (k % 2) * 100))
		for i in 30:
			await process_frame
		var v: Actor3D = player.view3d
		if _v != v:
			_v = v
			v.skeleton.skeleton_updated.connect(_on_updated)
		var ang: float = (int(k) * 1.05 + 0.3) if OS.get_environment("ANG_TEST") != "" else int(k) * 0.6
		player.yaw3d = ang
		player.yaw3d_target = ang
		for i in 30:
			await process_frame
		player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * player.floor_foreshortening()) * 380.0)
		# skip the start
		for i in 40:
			await process_frame
		stops.append(await _track(player, v, 0.0, true))
		for i in 30:
			await process_frame
		player.face_towards(player.global_position + Vector2(sin(ang + 2.6), cos(ang + 2.6) * player.floor_foreshortening()) * 200.0)
		turns.append(await _track(player, v, 1.2, false))
		print("  k %d: stop %.0f mm, turn %.0f mm" % [k, stops[-1] * 1000.0, turns[-1] * 1000.0])
	var ms := 0.0
	var mt := 0.0
	for x in stops:
		ms += x
	for x in turns:
		mt += x
	print("stop slide: mean %.0f mm, worst %.0f; turn on the spot (150°): mean %.0f mm, worst %.0f" % [ms / stops.size() * 1000.0, stops.max() * 1000.0, mt / turns.size() * 1000.0, turns.max() * 1000.0])
	PS.forced_render = ""
	quit(0)
