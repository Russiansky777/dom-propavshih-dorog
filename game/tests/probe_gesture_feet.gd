extends SceneTree
## Review 12.11 (the first full CI run since 11.11, 43267144034): test_motion_smooth «agata gesture: LeftFoot jolted
## 14.2 mm per 1/60 s at 1.57 s (≤ 14)». The sequence of that test (seed 2027: 8 s of standing, then her line), per
## frame: which gesture plays and how strongly, each foot's step per frame, its lock, its step state and lock error.
## Two readings of every bone: as the clips give it (read after the frame — what test_motion_smooth measures) and as it
## is drawn (read in skeleton_updated, after the foot locks and the other modifiers) — «shown».
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_gesture_feet.gd [-- role=<clip role>] [lines=N] [loop]
## role=… forces the gesture of every line (talk, talk_chest, talk_calm); lines=N plays N lines in turn (default 1);
## loop — the borrowed gestures as before 12.11 (the stance inside them from its start again, with its seam).

const DT := 1.0 / 60.0
const FEET := ["LeftFoot", "RightFoot"]

var _v: Actor3D = null
var _shown := {}


func _on_updated() -> void:
	for b in ["LeftFoot", "RightFoot", "Hips", "Head", "RightHand"]:
		_shown[b] = _v.turn.transform * _v.bone_model(b)


func _initialize() -> void:
	_run()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with(key + "="):
			return String(a).get_slice("=", 1)
	return def


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	Engine.max_fps = 60
	if OS.get_cmdline_user_args().has("loop"):
		Actor3D.fill_pingpong = false   # as before 12.11: the stance copied into a borrowed gesture from its start again
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "default", Vector2(1200, 960))
	for i in 8:
		await process_frame
	player.seed_motion(2027)
	var v: Actor3D = player.view3d
	_v = v
	v.skeleton.skeleton_updated.connect(_on_updated)
	var force := _arg("role", "")
	var n_lines := int(_arg("lines", "1"))
	var rows: Array = []
	var t := 0.0
	# 8 s of standing, as the test's «idle» run before the gesture
	while t < 8.0:
		await process_frame
		t += player.get_process_delta_time()
	for ln in n_lines:
		t = 0.0
		var said := false
		while t < 6.0:
			if not said:
				sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_%d" % (ln + 1), "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
				said = true
			elif t > 4.0 and not sr.current_beat.is_empty():
				sr.current_beat = {}
			if force != "":
				player.gest_role = force
			await process_frame
			t += player.get_process_delta_time()
			var row := {"ln": ln, "t": t, "role": String(player.gest_role), "gw": float(player._gest_w)}
			for i in 2:
				row[FEET[i]] = v.turn.transform * v.bone_model(FEET[i])
				row["lock%d" % i] = v._foot_lock[i]
				row["step%d" % i] = null if v._foot_step[i] == null else float(v._foot_step[i][1])
				row["w%d" % i] = float(v._foot_w[i])
				row["err%d" % i] = float(v.dbg_errs[i]) if v.dbg_errs.size() > i else -1.0
			row["hips"] = v.turn.transform * v.bone_model("Hips")
			row["shown"] = _shown.duplicate()
			rows.append(row)
	sr.current_beat = {}
	# per line: the gesture, the worst change of a foot's step per frame, the frames around it
	for ln in n_lines:
		var mine: Array = rows.filter(func(r): return int(r["ln"]) == ln)
		var worst := [0.0, "", -1]
		var moved := [0.0, 0.0]
		for i in range(2, mine.size()):
			for f in 2:
				var s1: Vector3 = mine[i - 1][FEET[f]] - mine[i - 2][FEET[f]]
				var s2: Vector3 = mine[i][FEET[f]] - mine[i - 1][FEET[f]]
				moved[f] += s2.length() * 1000.0
				var mm := (s2 - s1).length() * 1000.0
				if mm > float(worst[0]):
					worst = [mm, FEET[f], i]
		print("line %d: gesture %s — worst %s %.1f mm per 1/60 s at %.2f s; path of the feet over the line: left %.0f mm, right %.0f mm" % [ln + 1, mine[mine.size() / 2]["role"], worst[1], worst[0], float(mine[int(worst[2])]["t"]), moved[0], moved[1]])
		# as drawn: the worst change of step and the largest step of each bone
		var sline := "    shown:"
		for b in ["LeftFoot", "RightFoot", "Hips", "Head", "RightHand"]:
			var wj := 0.0
			var ws := 0.0
			var wt := 0.0
			for i in range(2, mine.size()):
				if not (mine[i]["shown"] as Dictionary).has(b) or not (mine[i - 2]["shown"] as Dictionary).has(b):
					continue
				var p1: Vector3 = mine[i - 1]["shown"][b] - mine[i - 2]["shown"][b]
				var p2: Vector3 = mine[i]["shown"][b] - mine[i - 1]["shown"][b]
				ws = maxf(ws, p2.length() * 1000.0)
				if (p2 - p1).length() * 1000.0 > wj:
					wj = (p2 - p1).length() * 1000.0
					wt = float(mine[i]["t"])
			sline += " %s jolt %.1f (at %.2f s) step %.1f;" % [b, wj, wt, ws]
		print(sline)
		var at := int(worst[2])
		var f := FEET.find(String(worst[1]))
		for i in range(maxi(1, at - 8), mini(mine.size(), at + 6)):
			var r: Dictionary = mine[i]
			var d: Vector3 = (r[FEET[f]] - mine[i - 1][FEET[f]]) * 1000.0
			var hd: Vector3 = (r["hips"] - mine[i - 1]["hips"]) * 1000.0
			print("    t %.2f gw %.2f %s step (%.1f, %.1f, %.1f) mm = %.1f | lock %s stepping %s w %.2f err %.0f mm | hips step %.1f mm" % [float(r["t"]), float(r["gw"]), FEET[f], d.x, d.y, d.z, d.length(),
				"yes" if r["lock%d" % f] != null else "no", ("%.2f" % float(r["step%d" % f])) if r["step%d" % f] != null else "no", float(r["w%d" % f]), float(r["err%d" % f]) * 1000.0, hd.length()])
	PS.forced_render = ""
	Engine.max_fps = 0
	quit(0)
