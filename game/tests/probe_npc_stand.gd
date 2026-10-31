extends SceneTree
## A villager standing (and talking) as drawn, alone: Actor3D posed as NpcLive3D does, the feet step run as it does —
## how far the drawn feet travel on the floor while down (cm/s) and how far the drawn hips sway across (cm), with the
## feet locks and the calming on, and off (data as before 31.10). RT3D_DIR — a local copy of the models.
##   godot --headless --path game -s res://tests/probe_npc_stand.gd -- <id> [talk]

var _drawn: Array = []
var _hips := Vector3.ZERO


func _initialize() -> void:
	_run()


func _measure(id: String, on: bool, talk: bool) -> String:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if OS.get_environment("RT3D_DIR") != "":
		spec["rt3d"]["scene"] = "%s/%s/%s_rt.glb" % [OS.get_environment("RT3D_DIR"), id, id]
	if not on:
		spec["rt3d"].erase("feet")
		spec["rt3d"].erase("calm")
	var v := Actor3D.new()
	root.add_child(v)
	if not v.setup(spec):
		return "not loaded"
	v.set_floor_k(0.55)
	v.skeleton.skeleton_updated.connect(func():
		_drawn = v.feet_model()
		_hips = v.bone_model("Hips"))
	var dt := 1.0 / 60.0
	var o := Vector2(600, 800)
	var k := Vector2(v.ppm, v.ppm * 0.55)
	var travel := 0.0
	var prev: Array = []
	var hx := [INF, -INF]
	var t := 0.0
	var act_t := 0.0
	var n := 0
	while t < 12.0:
		var act := "talk" if talk else ""
		var lt: Array = [act_t, 0.0, 0.0]
		if talk:
			act_t += dt
			lt = Actor3D.loop_times(act_t, maxf(v.action_length("talk"), 0.1), 0.8)
		v.pose(dt, 0.0, 0.0, 1.0 if talk else 0.0, act, float(lt[0]), float(lt[1]), float(lt[2]))
		if not v.foot_ik.is_empty():
			v.feet_step(dt, o, k)
		await process_frame
		t += dt
		if t < 2.0 or _drawn.is_empty():
			continue
		n += 1
		hx = [minf(hx[0], _hips.x), maxf(hx[1], _hips.x)]
		if not prev.is_empty():
			for i in 2:
				var a: Vector3 = _drawn[i * 2]
				var b: Vector3 = prev[i * 2]
				if a.y < float(v.stride_floor[i * 2]) + 0.03:
					travel += Vector2(a.x - b.x, a.z - b.z).length()
		prev = _drawn.duplicate()
	v.queue_free()
	return "feet travel %.1f cm/s, hips across %.1f cm" % [travel * 100.0 / maxf(t - 2.0, 0.1), (hx[1] - hx[0]) * 100.0]


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "pelageya"
	var talk := args.size() > 1 and args[1] == "talk"
	print("%s %s: now — %s" % [id, "talking" if talk else "standing", await _measure(id, true, talk)])
	print("%s %s: before — %s" % [id, "talking" if talk else "standing", await _measure(id, false, talk)])
	quit(0)
