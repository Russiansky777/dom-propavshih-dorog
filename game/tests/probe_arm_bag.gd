extends SceneTree
## The right hand in the bag (as drawn): idle, walking, the talk gesture, «open» — frames with the hand inside the
## bag's box and the deepest, with the clearance on and off.   -- <0|1>

var _v: Actor3D = null
var _rows: Array = []


func _initialize() -> void:
	_run()


func _on_updated() -> void:
	var sk := _v.skeleton
	var tm := _v._skel_to_model()
	var hips: Transform3D = tm * sk.get_bone_global_pose(sk.find_bone("Hips"))
	var hand: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	var fore: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightForeArm")).origin
	_rows.append([_v.bag_depth(hand, hips), _v.bag_depth(hand.lerp(fore, 0.5), hips)])


func _run() -> void:
	await process_frame
	var on := OS.get_cmdline_user_args().size() == 0 or OS.get_cmdline_user_args()[0] != "0"
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
	for i in 10:
		await process_frame
	_v = player.view3d
	_v.arm_clear_on = on
	_v.skeleton.skeleton_updated.connect(_on_updated)
	var scen := [
		["idle", 300, func(_i): pass],
		["walk", 200, func(i): if i == 0: player.click_at(player.global_position + Vector2(-420, 0))],
		["talk", 300, func(i):
			if i == 0: sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_1", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
			if i == 280: sr.current_beat = {}],
		["open", 260, func(i): if i == 0: player._start_action("open", null)],
		["pick", 200, func(i): if i == 0: player._start_action("pick", null)],
		["reach", 200, func(i): if i == 0: player._start_action("reach", null)],
	]
	for sc in scen:
		_rows = []
		for i in int(sc[1]):
			(sc[2] as Callable).call(i)
			await process_frame
		var n := 0
		var worst := 0.0
		var nf := 0
		var worst_f := 0.0
		for r in _rows:
			if float(r[0]) > 0.0:
				n += 1
			worst = maxf(worst, float(r[0]))
			if float(r[1]) > 0.0:
				nf += 1
			worst_f = maxf(worst_f, float(r[1]))
		print("%-6s hand in the bag %3d of %3d frames, deepest %.0f mm; forearm %3d, deepest %.0f mm" % [sc[0], n, _rows.size(), worst * 1000.0, nf, worst_f * 1000.0])
	PS.forced_render = ""
	quit(0)
