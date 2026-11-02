extends SceneTree
## Walking (the test «Walk rhythm» walk in Z2): each arm's largest spread out of the side plane and elbow bend, with the
## bag clearance on and off — what the clearance adds to the walking arm.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_arm_spread.gd

var _v: Actor3D
var _mx: Array = []


func _initialize() -> void:
	_run()


func _on_upd() -> void:
	var xf := _v._skel_to_turn()
	var sk := _v.skeleton
	for s in 2:
		var side: String = ["Left", "Right"][s]
		var a: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "Arm")).origin
		var e: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).origin
		var h: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
		var up := e - a
		_mx[s * 2] = maxf(_mx[s * 2], rad_to_deg(atan2(absf(up.x), -up.y)))
		_mx[s * 2 + 1] = maxf(_mx[s * 2 + 1], rad_to_deg(up.angle_to(h - e)))


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
	for on in [true, false]:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
			gs.set_flag(f, true)
		rm.change_room("Z2", "default", Vector2(400, 900))
		for i in 6:
			await process_frame
		_v = player.view3d
		_v.arm_clear_on = on
		player.yaw3d = PI * 0.5
		player.yaw3d_target = PI * 0.5
		for i in 30:
			await process_frame
		player.click_at(player.global_position + Vector2(900, 0))
		for i in 50:
			await process_frame
		_mx = [0.0, 0.0, 0.0, 0.0]
		_v.skeleton.skeleton_updated.connect(_on_upd)
		for i in 100:
			await process_frame
		_v.skeleton.skeleton_updated.disconnect(_on_upd)
		_v.arm_clear_on = true
		print("clearance %s: left arm spread %.1f° elbow %.1f°; right arm spread %.1f° elbow %.1f°" % [str(on), _mx[0], _mx[1], _mx[2], _mx[3]])
	PS.forced_render = ""
	quit(0)
