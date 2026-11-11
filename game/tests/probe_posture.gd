extends SceneTree
## How a villager stands (Director 10.11, 16:15: «Пелагея какая-то скукоженная», «руки … не вытянуты вперёд»): numbers of
## the standing pose after every modifier, against the model's own bind pose —
##   shoulders up/forward (cm, the arm joint against the hips), the chest's and the head's lean forward (deg),
##   elbows bent (deg), forearms off the vertical forward (deg), hands forward of the hips (cm) and out from them (cm).
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_posture.gd -- id[,id|all] [state] [seconds]

const DT := 1.0 / 60.0
const ALL := ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]


class Grab extends SkeletonModifier3D:
	var out: Array = []
	func _process_modification_with_delta(_d: float) -> void:
		var sk := get_skeleton()
		out.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			out[b] = sk.get_bone_global_pose(b)


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
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


## The pose's numbers in the hips' frame (x — her left, y — up, z — forward).
static func numbers(sk: Skeleton3D, poses: Array) -> Dictionary:
	var hips: Transform3D = poses[sk.find_bone("Hips")]
	var inv := hips.basis.inverse()
	var o := {}
	var loc := func(bone: String) -> Vector3:
		return inv * ((poses[sk.find_bone(bone)] as Transform3D).origin - hips.origin)
	for side in ["Left", "Right"]:
		var k := "L" if side == "Left" else "R"
		var arm: Vector3 = loc.call(side + "Arm")
		var fore: Vector3 = loc.call(side + "ForeArm")
		var hand: Vector3 = loc.call(side + "Hand")
		o["sh_up_" + k] = arm.y * 100.0
		o["sh_fwd_" + k] = arm.z * 100.0
		var ua := (fore - arm).normalized()
		var fa := (hand - fore).normalized()
		o["elbow_" + k] = rad_to_deg(ua.angle_to(fa))
		o["fore_fwd_" + k] = rad_to_deg(atan2(fa.z, -fa.y))
		o["upper_fwd_" + k] = rad_to_deg(atan2(ua.z, -ua.y))
		o["hand_fwd_" + k] = hand.z * 100.0
		o["hand_out_" + k] = (hand.x if side == "Left" else -hand.x) * 100.0
	var head: Transform3D = poses[sk.find_bone("Head")]
	var hf := inv * head.basis.z   # the head's forward axis in the hips' frame
	o["head_pitch"] = rad_to_deg(atan2(-hf.y, hf.z))   # + looks down
	var neck_name := "Neck" if sk.find_bone("Neck") >= 0 else "neck"
	var neck: Vector3 = loc.call(neck_name)
	var hd: Vector3 = loc.call("Head")
	# the upper back's lean (Spine → neck) forward of straight up, deg (Director 10.11, 22:15: «Павел… чуть сутулый»)
	var sp: Vector3 = loc.call("Spine")
	o["chest_fwd"] = rad_to_deg(atan2((neck - sp).z, (neck - sp).y))
	# the same lean of the whole trunk (hips → neck) against the bind pose's upright frame (not the hips', which tilt
	# themselves): + forward
	var rh: Transform3D = sk.get_bone_global_rest(sk.find_bone("Hips"))
	var tr: Vector3 = rh.basis.inverse() * ((poses[sk.find_bone(neck_name)] as Transform3D).origin - hips.origin)
	o["trunk_fwd"] = rad_to_deg(atan2(tr.z, tr.y))
	o["head_fwd"] = hd.z * 100.0
	o["neck_fwd"] = neck.z * 100.0
	o["neck_up"] = neck.y * 100.0
	return o


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = ALL if (a.is_empty() or String(a[0]) == "all") else Array(String(a[0]).split(","))
	var state := String(a[1]) if a.size() > 1 else "idle"
	var secs := float(a[2]) if a.size() > 2 else 2.0
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	print("%-10s %7s %7s %7s %7s | %6s %6s | %6s %6s | %6s %6s | %6s %6s | %6s %6s | %6s %6s %6s %6s" % ["id", "shUpL", "shUpR", "shFwL", "shFwR", "elbL", "elbR", "foreL", "foreR", "uppL", "uppR", "hFwL", "hFwR", "hOutL", "hOutR", "headP", "headFw", "chestF", "trunk"])
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var n := _fake_npc()
		n.set("actor_id", String(id))
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			print(id, ": not loaded")
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var sk: Skeleton3D = live.view.skeleton
		var g := Grab.new()
		sk.add_child(g)
		# the bind pose's numbers: the rest transforms, composed
		var rest: Array = []
		rest.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			rest[b] = sk.get_bone_global_rest(b)
		var r := numbers(sk, rest)
		live.set_state(state)
		var t := 0.0
		var acc := {}
		var cnt := 0
		while t < secs + 1.0:
			await process_frame
			t += DT
			if t >= secs and g.out.size() == sk.get_bone_count():
				var p := numbers(sk, g.out)
				for k in p:
					acc[k] = float(acc.get(k, 0.0)) + float(p[k])
				cnt += 1
		if cnt == 0:
			print(id, ": no pose")
			continue
		for k in acc:
			acc[k] = float(acc[k]) / float(cnt)
		print("%-10s %+7.1f %+7.1f %+7.1f %+7.1f | %6.1f %6.1f | %+6.1f %+6.1f | %+6.1f %+6.1f | %+6.1f %+6.1f | %6.1f %6.1f | %+6.1f %+6.1f %+6.1f %+6.1f" % [id,
			acc["sh_up_L"] - r["sh_up_L"], acc["sh_up_R"] - r["sh_up_R"], acc["sh_fwd_L"] - r["sh_fwd_L"], acc["sh_fwd_R"] - r["sh_fwd_R"],
			acc["elbow_L"], acc["elbow_R"], acc["fore_fwd_L"], acc["fore_fwd_R"], acc["upper_fwd_L"], acc["upper_fwd_R"],
			acc["hand_fwd_L"], acc["hand_fwd_R"], acc["hand_out_L"], acc["hand_out_R"], acc["head_pitch"] - r["head_pitch"], acc["head_fwd"] - r["head_fwd"], acc["chest_fwd"], acc["trunk_fwd"] - r["trunk_fwd"]])
		n.queue_free()
		await process_frame
	quit(0)
