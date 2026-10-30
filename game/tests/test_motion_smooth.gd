extends SceneTree
## Smooth motion of the live figures (Director 30.10, 17:36: «движения всё ещё не достаточно естественные и иногда
## странные или рваные у некоторых персонажей»). Every bone's acceleration is measured frame by frame (second
## difference of its position, with the body's yaw, scaled to 1/60 s frames) through what the figures do in play;
## a pop or a kink is a frame far above the motion around it. Defects this guards (found by tests/probe_motion.gd):
##   - walk loops: Agata's Walking_Woman jumped 6 cm once a cycle (no closing step), the long villager walks
##     11–12 cm once in 4 s, the one-second walks hitched (two closing keys) → baked loops (rt3d.walk_loop);
##   - linear fades (talk/listen, walk, actions, gesture) and the first-order turn started and stopped with a jolt
##     → weights through critically damped followers, turns with a limited angular acceleration;
##   - listen/talk played to and fro reversed every motion mid-air → forward loop with a crossfade;
##   - «open» squeezed 5.2 s of motion capture into 2.2 s (the hand at 2.4× its speed) → a cut, natural rate;
##   - Director 30.10, 19:16 «крутится на 360, прежде чем повернуться в нужную сторону»: in the last stretch of a walk
##     she kept walking while turning to the point and circled round it (331° one way for a path needing 44°) →
##     facing first in the last stretch too; the turn's way is chosen once per target, with the body's momentum.
## Thresholds — how much a bone may change its step per 1/60 s frame, above what the clips themselves do:
##   standing (idle, listen, talk, their fades, the gesture, turning): 14 mm (clips ≤ 9; the to-and-fro reversal
##   of a talking hand was ≈ 45, a fade's linear end ≈ 20, the old turn's start ≈ 20);
##   walking and stopping: 26 mm (heel strikes of the clips ≈ 20; the old walk seams 60–150);
##   actions: 22 mm (the grab of «pick» ≈ 16; «open» at 2.4× its pace ≈ 75) and the pace within 0.8–1.25×.
## The walk seam itself: no sharper than the cycle's own steps.
##   godot --headless --path game -s res://tests/test_motion_smooth.gd

const DT := 1.0 / 60.0
const BONES := ["Hips", "Spine", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
const NPCS := ["nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana", "tamara"]
const STAND_MM := 14.0
const WALK_MM := 26.0
const ACT_MM := 22.0

var _results: Array = []
var _cur_ok := true
var _cur_msgs: Array = []
var _sr: Node = null


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_cur_ok = false
		_cur_msgs.append(msg)


func _report(name: String, t0: int) -> void:
	print(("PASS  " if _cur_ok else "FAIL  ") + name + "  (%d ms)" % (Time.get_ticks_msec() - t0))
	for m in _cur_msgs:
		print("        - " + str(m))
	_results.append([name, _cur_ok])
	_cur_ok = true
	_cur_msgs = []


func _sample(v: Actor3D) -> Dictionary:
	var out := {}
	for b in BONES:
		if v.skeleton.find_bone(b) >= 0:
			out[b] = v.turn.transform * v.bone_model(b)   # with the body yaw: a jolt in a turn counts too
	return out


## Worst acceleration over a run as a change of step per 1/60 s (mm): [mm, bone, frame].
func _worst(frames: Array, dts: Array) -> Array:
	var best := [0.0, "", -1]
	for i in range(2, frames.size()):
		var d1: float = maxf(float(dts[i - 1]), 1e-4)
		var d2: float = maxf(float(dts[i]), 1e-4)
		for b in BONES:
			if not frames[i].has(b):
				continue
			var v1: Vector3 = (frames[i - 1][b] - frames[i - 2][b]) / d1
			var v2: Vector3 = (frames[i][b] - frames[i - 1][b]) / d2
			var acc := (v2 - v1) / ((d1 + d2) * 0.5)
			var mm := acc.length() * DT * DT * 1000.0
			if mm > best[0]:
				best = [mm, b, i]
	return best


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	_test_walk_seams()
	_report("Walk loops: the seam of every walk cycle is no sharper than the cycle's own steps (no pop, no hitch)", t0)
	t0 = Time.get_ticks_msec()
	await _test_villagers()
	_report("Villagers: idle, listen, talk (forward loop), their fades, a 150° turn, walking off and stopping — no jolt", t0)
	t0 = Time.get_ticks_msec()
	_test_turn_way()
	_report("Turn way: a turn takes the short way, or goes on the way it already turns when coming back would take longer — never round the circle", t0)
	t0 = Time.get_ticks_msec()
	await _test_agata()
	_report("Agata: idle, the talk gesture, a 150° turn, walk and stop, open/pick/reach at the clip's own pace — no jolt; no circling on 60 walks", t0)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== motion smoothness: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


## A walk set up at its end: walking towards a point 100 px off, then on its last leg 9 px past the end with the
## nearest so far 7 px. Returns whether she has arrived two frames later.
func _pass_by(gs: Node, rm: Node, player: Node2D, on: bool) -> bool:
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
		gs.set_flag(f, true)
	rm.change_room("M1", "default", Vector2(900, 800))
	for i in 10:
		await process_frame
	var walk_rt: Dictionary = player._rt.get("walk", {})
	var keep = walk_rt.get("pass_m", null)
	if not on:
		walk_rt["pass_m"] = 0.0
	var goal: Vector2 = player.global_position + Vector2(-100, 0)
	player.click_at(goal)
	var guard := 0
	while (player.nav_agent.get_current_navigation_path().size() < 2 or not player.is_walking()) and guard < 120:
		await process_frame
		guard += 1
	var path: PackedVector2Array = player.nav_agent.get_current_navigation_path()
	var end: Vector2 = path[path.size() - 1]
	var leg: Vector2 = (end - path[path.size() - 2]).normalized()
	player.global_position = end + leg * 6.0 + leg.orthogonal() * 7.0   # 9.2 px off the end, past it
	player._closest_px = 7.0
	player._path_seg = path.size() - 2
	await process_frame
	await process_frame
	var arrived: bool = not player.is_walking()
	if keep == null:
		walk_rt.erase("pass_m")
	else:
		walk_rt["pass_m"] = keep
	return arrived


## The turning a walk's path asks for (rad): from the yaw she stands at to its first leg, then every bend, all of it
## added up one way (an upper bound for one-way turning when she follows it). The path as seen on the screen floor
## is turned into yaws the way the player heads (Player._yaw_for_screen).
func _path_turn(p, yaw0: float) -> float:
	var path: PackedVector2Array = p.nav_agent.get_current_navigation_path()
	if path.size() < 2:
		return -1.0
	var total := 0.0
	var prev := yaw0
	var at: Vector2 = p.global_position
	for q in path:
		var d: Vector2 = q - at
		if d.length() < 4.0:
			continue
		var y: float = p._yaw_for_screen(d)
		total += absf(angle_difference(prev, y))
		prev = y
		at = q
	return total


# --- Walk seams ------------------------------------------------------------------------------------

func _test_walk_seams() -> void:
	for id in ["agata"] + NPCS + ["agata:raw"]:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % String(id).get_slice(":", 0)))
		var raw := String(id).ends_with(":raw")
		if raw:
			# self-check of the metric: Agata's clip as recorded (no baked loop) must show its seam
			(spec["rt3d"] as Dictionary).erase("walk_loop")
		var v := Actor3D.new()
		root.add_child(v)
		if not v.setup(spec):
			_check(false, "%s: live model not loaded (%s)" % [id, v.load_error])
			v.queue_free()
			continue
		if v.life != null:
			v.life.active = false
		if not v.clips.has("walk"):
			v.queue_free()
			continue
		_check(raw or String(v.clips["walk"]).begins_with("rt_loop/"), "%s: the walk is not a baked loop (rt3d.walk_loop)" % id)
		var frames: Array = []
		var dts: Array = []
		var phases: Array = []
		var n := int(round(v.walk_len * 60.0 * 2.2))
		for i in n:
			var ph := fposmod(float(i) * DT / v.walk_len, 1.0)
			v._apply(ph, 1.0, 0.0, "", 0.0)
			frames.append(_sample(v))
			dts.append(DT)
			phases.append(ph)
		# worst inside the cycle vs worst within ±4 frames of the seam
		var inner := 0.0
		var seam := 0.0
		for i in range(2, frames.size()):
			var w := _worst([frames[i - 2], frames[i - 1], frames[i]], [DT, DT, DT])
			var near := minf(float(phases[i]), 1.0 - float(phases[i])) * v.walk_len < 4.5 * DT
			if near:
				seam = maxf(seam, w[0])
			else:
				inner = maxf(inner, w[0])
		print("        %s walk %.3f s: seam %.1f mm, inside the cycle up to %.1f mm per 1/60 s" % [id, v.walk_len, seam, inner])
		if raw:
			_check(seam > inner * 1.5, "self-check: the recorded clip's seam (%.1f mm) did not stand out of its cycle (%.1f) — the metric would not catch a pop" % [seam, inner])
		else:
			_check(seam <= maxf(inner * 1.05, 4.0), "%s: walk seam %.1f mm per 1/60 s — sharper than the cycle's own steps (%.1f)" % [id, seam, inner])
		v.queue_free()


# --- Turn way ------------------------------------------------------------------------------------

## Actor3D.turn_step from 3000 random states (yaw, speed up to the cap) to random targets: it settles on the target
## having turned at most the short way plus what braking takes, never 270°+ one way; and the case that went round the
## circle: turning one way, a new target just behind on the other side.
func _test_turn_way() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cap := deg_to_rad(400.0)
	var accel := deg_to_rad(1500.0)
	var worst := 0.0
	for c in 3000:
		var st := Vector4(rng.randf_range(-PI, PI), rng.randf_range(-cap, cap), 0.0, 0.0)
		st.z = signf(st.y)
		st.w = st.x + st.y * 0.3
		var tgt := rng.randf_range(-PI, PI)
		var total := 0.0
		for f in 600:
			var y0 := st.x
			st = Actor3D.turn_step(st, tgt, DT, cap, 9.0, accel)
			total += absf(angle_difference(y0, st.x))
		var err := absf(angle_difference(st.x, tgt))
		worst = maxf(worst, total)
		if err > deg_to_rad(1.0) or total > deg_to_rad(270.0):
			_check(false, "turn from yaw %.0f° at %.0f°/s to %.0f°: turned %.0f°, %.1f° off at the end" % [rad_to_deg(st.x), rad_to_deg(st.y), rad_to_deg(tgt), rad_to_deg(total), rad_to_deg(err)])
			break
	print("        turn_step: 3000 random turns, the longest %.0f°" % rad_to_deg(worst))


# --- Villagers ---------------------------------------------------------------------------------

func _test_villagers() -> void:
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in NPCS:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			_check(false, "%s: live model not loaded" % id)
			n.queue_free()
			continue
		live.view.seed_idle(7)
		var scen := [
			["idle", 6.0, func(_t): pass, STAND_MM],
			["listen", 7.0, func(t): if t == 0.0: live.set_state("listen"), STAND_MM],
			["listen→idle", 1.5, func(t): if t == 0.0: live.set_state("idle"), STAND_MM],
			["talk (loop seam at %.1f s)" % (live.view.action_length("talk") - 0.8), 9.0, func(t): if t == 0.0: live.set_state("talk"), STAND_MM],
			["talk→idle", 1.5, func(t): if t == 0.0: live.set_state("idle"), STAND_MM],
			["idle→talk", 1.5, func(t): if t == 0.0: live.set_state("talk"), STAND_MM],
			["turn 150°", 2.0, func(t): if t == 0.0: live.face(Vector2(-60, -100), 0.55), STAND_MM],
			["walk off", 2.5, func(t): if t == 0.0: live.set_state("idle"); live.walk(true, 110.0, 1.0), WALK_MM],
			["stop", 1.5, func(t): if t == 0.0: live.walk(false), WALK_MM],
		]
		var line := "        %-9s" % id
		for sc in scen:
			var frames: Array = []
			var dts: Array = []
			var t := 0.0
			while t < float(sc[1]):
				(sc[2] as Callable).call(t)
				live.process(DT)
				frames.append(_sample(live.view))
				dts.append(DT)
				t += DT
			var w := _worst(frames, dts)
			line += " %s %.0f" % [String(sc[0]).get_slice(" ", 0), w[0]]
			_check(w[0] <= float(sc[3]), "%s %s: %s jolted %.1f mm per 1/60 s at %.2f s (≤ %.0f)" % [id, sc[0], w[1], w[0], w[2] * DT, float(sc[3])])
		print(line)
		n.queue_free()
		await process_frame


# --- Agata ---------------------------------------------------------------------------------------

func _gesture_beat(t: float) -> void:
	if t == 0.0:
		_sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_1", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
	elif t > 4.0 and not _sr.current_beat.is_empty():
		_sr.current_beat = {}


func _rec(player: Node2D, secs: float, frames: Array, dts: Array, every: Callable = Callable()) -> void:
	var t := 0.0
	var guard := 0
	while t < secs and guard < 4000:
		if every.is_valid():
			every.call(t)
		await process_frame
		guard += 1
		var d: float = player.get_process_delta_time()
		t += d
		frames.append(_sample(player.view3d))
		dts.append(d)


func _test_agata() -> void:
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	_sr = root.get_node("StoryRunner")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	Engine.max_fps = 60
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
	_check(player.is_3d(), "Agata is not drawn in 3D (forced): %s" % (player.view3d.load_error if player.view3d else "no view"))
	if not player.is_3d():
		PS.forced_render = ""
		Engine.max_fps = 0
		return
	var k: float = player.floor_foreshortening()
	var runs := [
		["idle", 8.0, Callable(), STAND_MM],
		["gesture", 6.0, _gesture_beat, STAND_MM],
		["turn 150°", 2.0, func(t): if t == 0.0: player.face_towards(player.global_position + Vector2(-0.5, -0.9 * k) * 200.0), STAND_MM],
		["walk+stop", 4.0, func(t): if t == 0.0: player.click_at(player.global_position + Vector2(-380, -40)), WALK_MM],
	]
	for act in ["open", "pick", "reach"]:
		runs.append(["act " + act, 4.5, func(t): if t == 0.0: player._start_action(act, null), ACT_MM])
	var line := "        agata    "
	for r in runs:
		var frames: Array = []
		var dts: Array = []
		await _rec(player, float(r[1]), frames, dts, r[2])
		var w := _worst(frames, dts)
		line += " %s %.0f" % [String(r[0]).get_slice(" ", 0) + (String(r[0]).get_slice(" ", 1) if String(r[0]).begins_with("act") else ""), w[0]]
		_check(w[0] <= float(r[3]), "agata %s: %s jolted %.1f mm per 1/60 s at %.2f s (≤ %.0f)" % [r[0], w[1], w[0], float(w[2]) * DT, float(r[3])])
		if w[0] > float(r[3]) and w[2] >= 2:
			var at: int = w[2]
			for i in range(maxi(2, at - 4), mini(frames.size(), at + 3)):
				print("          f%d dt %.4f step %.1f mm" % [i, dts[i], (frames[i][w[1]] - frames[i - 1][w[1]]).length() * 1000.0])
		if String(r[0]).begins_with("act "):
			# the clip at (about) its own pace: motion capture hands do not move 2.4× faster than recorded
			_check(player._act_speed >= 0.8 and player._act_speed <= 1.25, "agata %s: played at %.2f× the clip's pace (0.8–1.25)" % [r[0], player._act_speed])
	print(line)
	# circling (Director 19:16): 60 walks to random points in four rooms — the longest one-way turn is no more than the
	# path itself asks for (turning to its first leg, then its bends) plus what braking takes (≤ 120°); circling
	# round the point was 331° for a path needing 44°, round a corner of the path 228–386° for 44° (M1 walk 2, when
	# the navigation timing let her pass the corner wide). A walk that ends in another room (a door) counts until the
	# room changes — the new room's start yaw is not a turn.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 11
	var walks := 0
	var longest := 0.0
	var worst_excess := -INF
	for room in [["Z2", Vector2(960, 900)], ["H1", Vector2(1200, 960)], ["R1", Vector2(900, 900)], ["M1", Vector2(900, 900)]]:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
			gs.set_flag(f, true)
		rm.change_room(room[0], "default", room[1])
		for i in 10:
			await process_frame
		for wk in 15:
			var yaw0: float = player.yaw3d
			player.click_at(player.global_position + Vector2(wrng.randf_range(-600, 600), wrng.randf_range(-250, 250)))
			await process_frame
			if not player.is_walking():
				continue
			walks += 1
			var in_room = rm.current_room
			var run := 0.0
			var run_sign := 0.0
			var max_run := 0.0
			var last: float = player.yaw3d
			var guard := 0
			var need := -1.0
			while (player.is_walking() or absf(player._yaw_v) > 0.05) and guard < 900 and rm.current_room == in_room:
				if need < 0.0:
					need = _path_turn(player, yaw0)
				await process_frame
				guard += 1
				if rm.current_room != in_room:
					break
				var stp := angle_difference(last, player.yaw3d)
				last = player.yaw3d
				if absf(stp) > 1e-4:
					run = run + absf(stp) if signf(stp) == run_sign else absf(stp)
					run_sign = signf(stp)
					max_run = maxf(max_run, run)
			longest = maxf(longest, max_run)
			need = maxf(need, 0.0)
			worst_excess = maxf(worst_excess, max_run - need)
			_check(max_run <= need + deg_to_rad(120.0), "agata %s walk %d: turned %.0f° one way for a path asking %.0f° (circling)" % [room[0], wk, rad_to_deg(max_run), rad_to_deg(need)])
	print("        agata: %d walks, the longest one-way turn %.0f°, at most %.0f° beyond what its path asks" % [walks, rad_to_deg(longest), rad_to_deg(worst_excess)])
	_check(walks >= 30, "only %d of 60 clicks became walks" % walks)
	# following the path (corners): the point she heads for is ahead of her along the path even when she has gone a
	# little wide of a corner — the agent's corner was then behind her and she turned back to it (M1: 228–386°)
	var corner := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var wide := Vector2(112, 14)    # past the corner, 12 px wide of it: the agent never came within its 10 px
	var pf: Array = PS.path_follow(corner, wide, 0, 30.0)
	var ahead: Vector2 = (pf[0] as Vector2) - wide
	_check(int(pf[1]) == 1 and ahead.dot(Vector2(0, 1)) > 0.0, "past a corner, wide of it, the path point she heads for is not ahead along the next leg (%s, segment %d)" % [str(pf[0]), int(pf[1])])
	_check((Vector2(100, 0) - wide).dot(Vector2(0, 1)) < 0.0, "self-check: the corner itself is behind her there (what she used to turn back to)")
	var back: Array = PS.path_follow(corner, Vector2(50, 3), 1, 30.0)
	_check(int(back[1]) == 1, "a segment reached is never left for an earlier one (%d)" % int(back[1]))
	var r_prev := INF
	var decreasing := true
	for x in [0.0, 30.0, 60.0, 90.0]:
		var r: float = PS.path_follow(corner, Vector2(x, 4), 0, 30.0)[2]
		decreasing = decreasing and r < r_prev
		r_prev = r
	_check(decreasing and absf(float(PS.path_follow(corner, Vector2(100, 100), 1, 30.0)[2])) < 0.01, "the path left shrinks as she goes and is 0 at its end")
	# passing by the end: on the last leg, once within pass_m and moving away again, she has arrived (M1 walk 6:
	# she went on past, turned round and came back — 223° one way). Set up exactly: walking, nearest so far 7 px, now
	# 9 px off the end (the agent's own tolerance is 6 px). Self-check: with pass_m 0 she walks on.
	var passed_on := await _pass_by(gs, rm, player, true)
	var passed_off := await _pass_by(gs, rm, player, false)
	print("        passing by the end of a walk: arrived %s; with passing-by off %s" % [str(passed_on), str(passed_off)])
	_check(passed_on, "on the last leg, 9 px past her nearest 7 px to the end, she still walks (goes on past, turns round, comes back)")
	_check(not passed_off, "self-check: with passing-by off she stops there anyway — the case is not set up")
	PS.forced_render = ""
	Engine.max_fps = 0
