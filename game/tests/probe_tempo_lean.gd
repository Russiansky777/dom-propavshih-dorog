extends SceneTree
## Director 08.11, 21:13 («Ульяна вперёд слишком стоит… не стоит ли ускорить анимации?»): per character, in the
## stance (3 s) the body's forward lean — head over the ankles, cm, and the chest's pitch, deg — and in talk (12 s)
## the hands' tempo: mean and 90th-percentile speed, cm/s, in the hips' frame, plus the hands' mean forward offset
## (sign check: gestures go forward).
##   godot --headless --fixed-fps 60 --path <lab> -s res://tests/probe_tempo_lean.gd -- id [id ...]

const DT := 1.0 / 60.0


class Grab extends SkeletonModifier3D:
	var out: Array = []
	func _process_modification_with_delta(_d: float) -> void:
		var sk := get_skeleton()
		out.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			out[b] = sk.get_bone_global_pose(b)


func _initialize() -> void:
	_run()


func _frame(g: Grab, sk: Skeleton3D) -> Dictionary:
	var hips := sk.find_bone("Hips")
	var lu := sk.find_bone("LeftUpLeg")
	var ru := sk.find_bone("RightUpLeg")
	var lf := sk.find_bone("LeftFoot")
	var rf := sk.find_bone("RightFoot")
	var head := sk.find_bone("Head")
	var chest := sk.find_bone("Spine")  # Meshy chain: Hips → Spine02 → Spine01 → Spine → neck → Head
	var spine := sk.find_bone("Spine02")
	if spine < 0:
		spine = sk.find_bone("Spine1")
	var o := func(b: int) -> Vector3: return (g.out[b] as Transform3D).origin
	var right: Vector3 = (o.call(ru) - o.call(lu)).normalized()
	var up := Vector3.UP
	var fwd: Vector3 = up.cross(right).normalized()
	var ankles: Vector3 = (o.call(lf) + o.call(rf)) * 0.5
	var h: Vector3 = o.call(head)
	var c: Vector3 = o.call(chest)
	var s: Vector3 = o.call(spine)
	var v: Vector3 = c - s
	var nk := h - c  # chest top → head: the neck's pitch
	var shoulders: Vector3 = (o.call(sk.find_bone("LeftShoulder")) + o.call(sk.find_bone("RightShoulder"))) * 0.5
	return {
		"neck_pitch": rad_to_deg(atan2(nk.dot(fwd), nk.dot(up))), "head_over_shoulders": (h - shoulders).dot(fwd),
		"torso_pitch": rad_to_deg(atan2((shoulders - o.call(hips)).dot(fwd), (shoulders - o.call(hips)).dot(up))),
		"head_fwd": (h - ankles).dot(fwd), "hips_fwd": (o.call(hips) - ankles).dot(fwd),
		"chest_pitch": rad_to_deg(atan2(v.dot(fwd), v.dot(up))), "fwd": fwd,
	}


func _one(id: String) -> void:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var sc := GDScript.new()
	sc.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	sc.reload()
	var n := Node2D.new()
	n.set_script(sc)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	var live = load("res://scripts/actors/npc_live_3d.gd").new()
	n.add_child(live)
	live.setup(n, spec, 0.55)
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live.face(Vector2(0.4, 0.5), 0.55, true)
	var sk: Skeleton3D = live.view.skeleton
	var g := Grab.new()
	sk.add_child(g)
	var unit := 1.0
	if live.arm_body != null and live.arm_body.get("_unit") != null:
		unit = float(live.arm_body.get("_unit"))
	var hb := [sk.find_bone("LeftHand"), sk.find_bone("RightHand")]
	var hips := sk.find_bone("Hips")
	# stance
	live.set_state("idle")
	var t := 0.0
	var lean: Array = []
	var pitch: Array = []
	var hipsf: Array = []
	var neck: Array = []
	var hos: Array = []
	var torso: Array = []
	var s_hand_fwd: Array = []
	var s_hand_up: Array = []
	while t < 3.0:
		live.process(DT)
		await process_frame
		t += DT
		if t < 1.0 or g.out.is_empty():
			continue
		var f := _frame(g, sk)
		lean.append(float(f["head_fwd"]) / unit * 100.0)
		pitch.append(float(f["chest_pitch"]))
		hipsf.append(float(f["hips_fwd"]) / unit * 100.0)
		neck.append(float(f["neck_pitch"]))
		hos.append(float(f["head_over_shoulders"]) / unit * 100.0)
		torso.append(float(f["torso_pitch"]))
		for s2 in 2:
			var pw: Vector3 = ((g.out[hb[s2]] as Transform3D).origin - (g.out[hips] as Transform3D).origin) / unit
			s_hand_fwd.append(pw.dot(f["fwd"]) * 100.0)
			s_hand_up.append(pw.y * 100.0)
	# talk
	live.set_state("talk")
	t = 0.0
	var prev := [Vector3.ZERO, Vector3.ZERO]
	var speeds: Array = []
	var hand_fwd: Array = []
	var t_lean: Array = []
	var t_torso: Array = []
	var t_neck: Array = []
	var t_torso_max := -99.0
	var k := 0
	while t < 12.0:
		live.process(DT)
		await process_frame
		t += DT
		if g.out.is_empty():
			continue
		var inv: Transform3D = (g.out[hips] as Transform3D).affine_inverse()
		var f := _frame(g, sk)
		t_lean.append(float(f["head_fwd"]) / unit * 100.0)
		t_torso.append(float(f["torso_pitch"]))
		t_neck.append(float(f["neck_pitch"]))
		t_torso_max = maxf(t_torso_max, float(f["torso_pitch"]))
		for s in 2:
			var p: Vector3 = inv * (g.out[hb[s]] as Transform3D).origin / unit
			if k > 0 and t > 0.5:
				speeds.append((p - prev[s]).length() * 100.0 / DT)
			prev[s] = p
			var pw: Vector3 = ((g.out[hb[s]] as Transform3D).origin - (g.out[hips] as Transform3D).origin) / unit
			hand_fwd.append(pw.dot(f["fwd"]) * 100.0)
		k += 1
	speeds.sort()
	var mean := 0.0
	for v in speeds:
		mean += v
	mean /= maxf(1.0, speeds.size())
	var p90: float = speeds[int(speeds.size() * 0.9)] if speeds.size() > 0 else 0.0
	var hf := 0.0
	for v in hand_fwd:
		hf += v
	hf /= maxf(1.0, hand_fwd.size())
	print("TL %-9s stance: hands fwd of hips %5.1f cm, below hips %5.1f cm; head/ankles %4.1f cm torso %5.1f° neck %5.1f° | talk: head/ankles %4.1f cm torso %5.1f° (max %5.1f°) neck %5.1f° | hands mean %5.1f cm/s p90 %5.1f fwd %5.1f cm" % [
		id, _avg(s_hand_fwd), -_avg(s_hand_up), _avg(lean), _avg(torso), _avg(neck), _avg(t_lean), _avg(t_torso), t_torso_max, _avg(t_neck), mean, p90, hf])
	n.queue_free()
	await process_frame


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1.0, a.size())


func _run() -> void:
	await process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["nina", "ilya", "ulyana", "ilya_wife", "mitya", "pelageya", "pavel", "tamara", "manager"]
	for id in ids:
		await _one(String(id))
	quit(0)
