extends SceneTree
## Motion probe of the live figures (Director 30.10, 17:36: «движения всё ещё не достаточно естественные, иногда
## странные или рваные у некоторых персонажей»): bone positions every 1/60 s through each scenario; a jerk is a frame
## whose second difference of position (mm per frame², the change of the step) is far above its neighbours — a pop
## a viewer sees as a twitch. Prints per character and scenario the worst bones and moments.
##   godot --headless --path game -s res://tests/probe_motion.gd [-- id ...]

const DT := 1.0 / 60.0
const BONES := ["Hips", "Spine", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]

var _rows: Array = []
var _sr: Node = null


func _gesture_beat(t: float) -> void:
	if t == 0.0:
		_sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_1", "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
	elif t > 5.0 and not _sr.current_beat.is_empty():
		_sr.current_beat = {}


func _initialize() -> void:
	_run()


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


func _sample(v: Actor3D) -> Dictionary:
	var out := {}
	for b in BONES:
		if v.skeleton.find_bone(b) >= 0:
			out[b] = v.turn.transform * v.bone_model(b)   # with the body yaw: turning is seen too
	return out


## Second differences (mm) of every bone over a recorded run → worst frames.
func _analyse(who: String, scen: String, frames: Array, labels: Array) -> void:
	var worst := {}
	for b in BONES:
		var best := 0.0
		var at := -1
		for i in range(2, frames.size()):
			if not frames[i].has(b):
				continue
			var p0: Vector3 = frames[i - 2][b]
			var p1: Vector3 = frames[i - 1][b]
			var p2: Vector3 = frames[i][b]
			var d2 := ((p2 - p1) - (p1 - p0)).length() * 1000.0
			if d2 > best:
				best = d2
				at = i
		worst[b] = [best, at]
	if OS.get_environment("PROBE_DUMP") != "":
		var kk := worst.keys()
		kk.sort_custom(func(a, b): return worst[a][0] > worst[b][0])
		var bb: String = kk[0]
		var at0: int = worst[bb][1]
		for i in range(maxi(2, at0 - 8), mini(frames.size(), at0 + 6)):
			var q0: Vector3 = frames[i - 2][bb]
			var q1: Vector3 = frames[i - 1][bb]
			var q2: Vector3 = frames[i][bb]
			print("   %s %s f%d %.2fs d2 %.1f v %.1f  %s" % [scen, bb, i, i * DT, ((q2 - q1) - (q1 - q0)).length() * 1000.0, (q2 - q1).length() * 1000.0, labels[i] if i < labels.size() else ""])
	var line := "%-9s %-14s" % [who, scen]
	var keys := worst.keys()
	keys.sort_custom(func(a, b): return worst[a][0] > worst[b][0])
	for k in keys.slice(0, 3):
		var i: int = worst[k][1]
		line += "  %s %.1f mm @%.2fs%s" % [k, worst[k][0], i * DT, (" [" + str(labels[i]) + "]") if i >= 0 and i < labels.size() and str(labels[i]) != "" else ""]
	print(line)
	_rows.append([who, scen, worst])


func _npc(id: String) -> void:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var n := _fake_npc()
	var live := NpcLive3D.new()
	n.add_child(live)
	if not live.setup(n, spec, 0.55):
		print(id, ": not loaded")
		return
	var scen := [
		["idle 14s", 14.0, func(_t): pass],
		["listen 8s", 8.0, func(t): if t == 0.0: live.set_state("listen")],
		["talk 8s", 8.0, func(t): if t == 0.0: live.set_state("talk")],
		["talk→idle", 3.0, func(t): if t == 0.0: live.set_state("idle")],
		["idle→talk", 3.0, func(t): if t == 0.0: live.set_state("talk")],
		["turn 150°", 3.0, func(t): if t == 0.0: live.face(Vector2(-60, -100), 0.55)],
		["walk start", 3.0, func(t): if t == 0.0: live.set_state("idle"); live.walk(true, 110.0, 1.0)],
		["walk stop", 2.0, func(t): if t == 0.0: live.walk(false)],
	]
	for sc in scen:
		var frames: Array = []
		var labels: Array = []
		var t := 0.0
		while t < float(sc[1]):
			(sc[2] as Callable).call(t)
			live.process(DT)
			frames.append(_sample(live.view))
			labels.append("%s w%.2f %s" % [live.act_name, live.act_w, ("walk%.2f" % live.walk_w) if live.walk_w > 0.0 else ""])
			t += DT
		_analyse(id, sc[0], frames, labels)
	n.queue_free()


func _rec(player: Node2D, secs: float, frames: Array, labels: Array, every: Callable = Callable()) -> void:
	var t := 0.0
	while t < secs:
		if every.is_valid():
			every.call(t)
		await process_frame
		t += player.get_process_delta_time()
		var v: Actor3D = player.view3d
		var smp := _sample(v)
		# root on screen (px → mm at the figure's scale) — a slide shows as a step of the whole figure
		frames.append(smp)
		labels.append("act %s %.2f walk %.2f yaw %.0f gest %.2f | dt %.4f ph %.3f tsw %.2f mp %s idle %s/%s mix %.2f t %.2f/%.2f" % [player._action, player._act_w, player.walk_w, rad_to_deg(player.yaw3d), player._gest_w, player.get_process_delta_time(), fposmod(player.walk_phase, 1.0), player._turn_step_w, str(Vector2(v.model.position.x, v.model.position.z) * 1000.0), String(v._slot_name[0]).get_file(), String(v._slot_name[1]).get_file(), v._slot_mix, v._slot_t[0], v._slot_t[1]])


func _agata() -> void:
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
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "default", Vector2(1200, 960))
	for i in 8:
		await process_frame
	var f: Array = []
	var l: Array = []
	await _rec(player, 20.0, f, l)
	_analyse("agata", "idle 20s", f, l)
	f = []; l = []
	_sr = sr
	await _rec(player, 7.0, f, l, _gesture_beat)
	_analyse("agata", "gesture line", f, l)
	f = []; l = []
	var k: float = player.floor_foreshortening()
	await _rec(player, 2.5, f, l, func(t): if t == 0.0: player.face_towards(player.global_position + Vector2(-0.5, -0.9 * k) * 200.0))
	_analyse("agata", "turn 150°", f, l)
	f = []; l = []
	await _rec(player, 4.0, f, l, func(t): if t == 0.0: player.click_at(player.global_position + Vector2(-380, -40)))
	_analyse("agata", "walk+stop", f, l)
	for act in ["open", "pick", "reach"]:
		f = []; l = []
		await _rec(player, 4.5, f, l, func(t): if t == 0.0: player._start_action(act, null))
		_analyse("agata", "act " + act, f, l)
	PS.forced_render = ""


func _run() -> void:
	Engine.max_fps = 60   # 1/60 s frames, as the probe's numbers are meant
	await process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["agata", "nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana", "tamara"]
	for id in ids:
		if String(id) == "agata":
			await _agata()
		else:
			await _npc(String(id))
		await process_frame
	quit(0)
