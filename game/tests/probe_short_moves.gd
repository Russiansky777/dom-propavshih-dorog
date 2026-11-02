extends SceneTree
## Director 01.11, line 3: «АГАТА ТАКЖЕ МЕЛЬТЕШИТ!!! куча перестановок ног ненужных». Short moves from standing (a click a
## little way off — a hotspot next to her, a correction): per move how many times a drawn foot leaves the floor, until
## when (s after the click), where she ends (px from the target), and the turn before it. A person moving 20–60 cm takes
## one step and closes up the other foot: two lifts.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_short_moves.gd [-- noshuffle]

var _drawn: Array = []


func _initialize() -> void:
	_run()


func _on_upd(v: Actor3D) -> void:
	_drawn = v.feet_model()


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
	if OS.get_cmdline_user_args().has("noshuffle"):
		player.set("shuffle_on", false)
	var rows: Array = []
	# [distance on the floor (m), direction relative to her facing (deg)]
	var cases := [[0.1, 0], [0.2, 0], [0.3, 0], [0.45, 0], [0.6, 0], [0.8, 0], [0.2, 45], [0.3, 90], [0.4, -90], [0.25, 180], [0.4, 135], [0.15, -45], [0.5, 60], [1.2, 0]]
	var room_id := "H1" if not OS.get_cmdline_user_args().has("z2") else "Z2"
	var start := Vector2(1100, 960) if room_id == "H1" else Vector2(700, 880)
	for ci in cases.size():
		var c: Array = cases[ci]
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
			gs.set_flag(f, true)
		rm.change_room(room_id, "default", start)
		for i in 6:
			await process_frame
		player.seed_motion(1031)
		var v: Actor3D = player.view3d
		v.seed_idle(60 + ci)
		if not v.skeleton.skeleton_updated.is_connected(_on_upd.bind(v)):
			v.skeleton.skeleton_updated.connect(_on_upd.bind(v))
		var face := PI * 0.5   # facing screen right
		player.yaw3d = face
		player.yaw3d_target = face
		for i in 90:
			await process_frame
		_drawn = []
		var kf: float = player.floor_foreshortening()
		var ang := face + deg_to_rad(float(c[1]))
		# a direction on the floor (yaw: 0 = towards the viewer, +90° = right) → screen
		var dir := Vector2(sin(ang), cos(ang) * kf)
		var target: Vector2 = player.global_position + dir * float(c[0]) * v.ppm * absf(player.scale.y)
		var p0: Vector2 = player.global_position
		player.click_at(target)
		var t := 0.0
		var up: Array = [false, false]
		var lifts := 0
		var last_lift := 0.0
		var still_t := -1.0
		var ev := ""
		var ppm_s: float = v.ppm * absf(player.scale.y)
		var max_w := 0.0
		var min_reach := 9.0
		while t < 4.0:
			await process_frame
			t += player.get_process_delta_time()
			max_w = maxf(max_w, v.shown_w())
			if player.is_walking():
				min_reach = minf(min_reach, minf(float(v.dbg_reach[0]), float(v.dbg_reach[1])))
			if still_t < 0.0 and not player.is_walking():
				still_t = t
			var f: Array = _drawn if not _drawn.is_empty() else v.feet_model()
			for i in 2:
				var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
				var now_up: bool = h > 0.025 or (up[i] and h > 0.015)
				if now_up and not up[i]:
					lifts += 1
					last_lift = t
					ev += " %s%.2f" % ["L" if i == 0 else "R", t]
				up[i] = now_up
		var moved: float = (player.global_position - p0).length()
		rows.append([c[0], c[1], lifts])
		print("%.2f m (%3.0f px) at %4d°: %d lifts, last %.2f s, arrived %.2f s, moved %.0f px, %.1f px off, max walk w %.2f, leg reach spare min %.1f cm |%s" % [
			float(c[0]), p0.distance_to(target), int(c[1]), lifts, last_lift, still_t, moved,
			player.global_position.distance_to(target), max_w, min_reach * 100.0, ev])
	PS.forced_render = ""
	quit(0)
