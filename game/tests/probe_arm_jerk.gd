extends SceneTree
## Director 01.11, line 20: «Агатина правая рука иногда резко дёргается, будто конец анимации и начало снова её, но места
## не сходятся». Per drawn frame (skeleton_updated, after every modifier) both hands relative to the chest; the frames
## with the largest second difference (mm per frame², 60 fps) and what was going on then: idle slots, walk, gesture,
## action, the bag clearance IK. Scenes: a long stance, walks, a run of lines (with short gaps), actions.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_arm_jerk.gd [-- noclear]

var _v: Actor3D = null
var _player = null
var _rows: Array = []
var _scene := ""


func _initialize() -> void:
	_run()


func _on_updated() -> void:
	var sk := _v.skeleton
	var tm := _v._skel_to_model()
	var chest: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("Spine02")).origin
	var rh: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin - chest
	var lh: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin - chest
	var rf: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightForeArm")).origin - chest
	_rows.append({"rh": rh, "lh": lh, "rf": rf, "sc": _scene,
		"ik": _v.arm_ik.influence if _v.arm_ik != null else 0.0,
		"tgt": _v._arm_target.position if _v._arm_target != null else Vector3.ZERO,
		"idle": "%s@%.2f/%s@%.2f mix %.2f" % [String(_v._slot_name[0]).get_file(), float(_v._slot_t[0]), String(_v._slot_name[1]).get_file(), float(_v._slot_t[1]), _v._slot_mix],
		"w": _v.shown_w(), "a": _v.shown_act_w(), "act": _v._act_name, "at": _v._shown_t, "at2": _v._shown_t2, "amix": _v._shown_mix,
		"gw": _player._gest_w, "walking": _player.is_walking(), "ph": fposmod(_player.walk_phase, 1.0)})


func _run() -> void:
	await process_frame
	var noclear := OS.get_cmdline_user_args().has("noclear")
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	_player = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "default", Vector2(1200, 960))
	for i in 10:
		await process_frame
	_player.seed_motion(1031)
	_v = _player.view3d
	_v.seed_idle(5)
	_v.arm_clear_on = not noclear
	_v.skeleton.skeleton_updated.connect(_on_updated)
	var lines := ["Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут.",
		"А если дверь на петли вернуть, то и дорога, может, найдётся сама собой.",
		"Нет, я не устала. Просто думаю, с чего начать и куда всё это девать."]
	var scen := [
		["idle", 3600, func(_i): pass],
		["walk", 900, func(i):
			if i == 0: _player.click_at(_player.global_position + Vector2(-420, 0))
			if i == 300: _player.click_at(_player.global_position + Vector2(380, 40))
			if i == 600: _player.click_at(_player.global_position + Vector2(60, 0))
			if i == 700: _player.click_at(_player.global_position + Vector2(-50, 10))],
		["talk", 1500, func(i):
			for k in 3:
				if i == k * 480: sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_%d" % k, "to": "tikhon", "text": lines[k]}
				if i == k * 480 + 300 + k * 40: sr.current_beat = {}],
		["idle2", 1200, func(_i): pass],
		["open", 260, func(i): if i == 0: _player._start_action("open", null)],
		["reach", 200, func(i): if i == 0: _player._start_action("reach", null)],
	]
	if OS.get_environment("TESTSEQ") != "":
		# the sequence of test_agata_3d «Right arm without jerks»
		var tl := "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут, и всё тут."
		scen = [["idle", 1800, func(_i): pass],
			["talk", 702, func(i):
				if i == 0: sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "J_0", "to": "tikhon", "text": tl}
				if i == 300: sr.current_beat = {}
				if i == 360: sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "J_1", "to": "tikhon", "text": tl}
				if i == 660: sr.current_beat = {}]]
	_rows = []
	for sc in scen:
		_scene = String(sc[0])
		for i in int(sc[1]):
			(sc[2] as Callable).call(i)
			await process_frame
	_v.skeleton.skeleton_updated.disconnect(_on_updated)
	# second difference per frame (mm), right hand / right forearm / left hand
	var acc: Array = []
	for i in range(1, _rows.size() - 1):
		var r0: Dictionary = _rows[i - 1]
		var r1: Dictionary = _rows[i]
		var r2: Dictionary = _rows[i + 1]
		var ar := ((r2["rh"] as Vector3) - 2.0 * (r1["rh"] as Vector3) + (r0["rh"] as Vector3)).length() * 1000.0
		var af := ((r2["rf"] as Vector3) - 2.0 * (r1["rf"] as Vector3) + (r0["rf"] as Vector3)).length() * 1000.0
		var al := ((r2["lh"] as Vector3) - 2.0 * (r1["lh"] as Vector3) + (r0["lh"] as Vector3)).length() * 1000.0
		var vr := ((r2["rh"] as Vector3) - (r0["rh"] as Vector3)).length() * 500.0
		acc.append([ar, i, af, al, vr])
	var per_scene := {}
	for e in acc:
		var sc := String(_rows[int(e[1])]["sc"])
		if not per_scene.has(sc):
			per_scene[sc] = [0.0, 0.0, [], 0.0, 0]
		per_scene[sc][0] = maxf(per_scene[sc][0], float(e[0]))
		per_scene[sc][1] = maxf(per_scene[sc][1], float(e[3]))
		if float(e[2]) > per_scene[sc][3]:
			per_scene[sc][3] = float(e[2])
			per_scene[sc][4] = int(e[1])
		(per_scene[sc][2] as Array).append(float(e[0]))
	for sc in per_scene.keys():
		var a: Array = per_scene[sc][2]
		a.sort()
		print("%-6s right hand accel max %.2f mm/f² (p99 %.2f, median %.2f); left hand max %.2f; right elbow max %.2f (f%d)" % [sc, per_scene[sc][0], a[int(a.size() * 0.99)], a[a.size() / 2], per_scene[sc][1], per_scene[sc][3], per_scene[sc][4]])
	acc.sort_custom(func(x, y): return x[0] > y[0])
	var shown := 0
	var last_i := -100
	for e in acc:
		if shown >= 14:
			break
		var i := int(e[1])
		if absi(i - last_i) < 4:
			continue
		last_i = i
		shown += 1
		var r: Dictionary = _rows[i]
		var rp: Dictionary = _rows[i - 1]
		print("f%5d %-6s R acc %.2f (fore %.2f, L %.2f) v %.0f mm/s | ik %.2f→%.2f tgt Δ %.1f mm | w %.2f walking %s ph %.3f | act %s a %.2f t %.2f/%.2f mix %.2f gw %.2f | %s" % [
			i, r["sc"], e[0], e[2], e[3], e[4], rp["ik"], r["ik"], ((r["tgt"] as Vector3) - (rp["tgt"] as Vector3)).length() * 1000.0,
			r["w"], str(r["walking"]), r["ph"], r["act"], r["a"], r["at"], r["at2"], r["amix"], r["gw"], r["idle"]])
	PS.forced_render = ""
	quit(0)
