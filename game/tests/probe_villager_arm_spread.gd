extends SceneTree
## How far the villagers' arms stand out from the body (Director 06.11, 15:56: «остальных тоже коробит»): the talk clip
## on Mitya's rig holds the arms out at 30–40° like a scarecrow even with BodyClear off. Per state: the upper arm's
## sideways angle from straight down (in the body's frontal plane; mean and max over 6 s), before (clip) and after the
## modifiers, and how far the wrist is from the body's hull (BodyClear) — mean.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_villager_arm_spread.gd -- id[,id] [state,state]

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


static func spread(sk: Skeleton3D, poses: Array, side: String) -> float:
	var hips: Transform3D = poses[sk.find_bone("Hips")]
	var a: Vector3 = (poses[sk.find_bone(side + "Arm")] as Transform3D).origin
	var f: Vector3 = (poses[sk.find_bone(side + "ForeArm")] as Transform3D).origin
	var d := hips.basis.inverse() * (f - a)   # in the hips' frame: x sideways, y up, z forward
	var out := d.x if side == "Left" else -d.x
	return rad_to_deg(atan2(out, -d.y))


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = String(a[0]).split(",")
	var states: Array = String(a[1]).split(",") if a.size() > 1 else ["idle", "talk", "listen"]
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for k in OS.get_environment("SPREAD_OFF").split(",", false):   # e.g. act_body.upper,arm_hang — a try without
			var kp := k.split(".")
			if kp.size() == 2:
				(spec["rt3d"][kp[0]] as Dictionary).erase(kp[1])
			else:
				(spec["rt3d"] as Dictionary).erase(k)
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var sk: Skeleton3D = live.view.skeleton
		var g0 := Grab.new()   # before BodyClear: added before it
		sk.add_child(g0)
		sk.move_child(g0, live.arm_body.get_index())
		var g1 := Grab.new()
		sk.add_child(g1)
		var line := "%-9s" % id
		for st in states:
			live.set_state(String(st))
			var t := 0.0
			var sums := [0.0, 0.0, 0.0, 0.0]
			var mx := [-99.0, -99.0, -99.0, -99.0]
			var k := 0
			while t < 6.0:
				live.process(DT)
				await process_frame
				t += DT
				if t < 1.0 or g0.out.is_empty():
					continue
				k += 1
				var v := [spread(sk, g0.out, "Left"), spread(sk, g0.out, "Right"), spread(sk, g1.out, "Left"),
						spread(sk, g1.out, "Right")]
				for i in 4:
					sums[i] += v[i]
					mx[i] = maxf(mx[i], v[i])
			line += " | %s clip L%.0f/%.0f R%.0f/%.0f → L%.0f/%.0f R%.0f/%.0f" % [st, sums[0] / k, mx[0], sums[1] / k, mx[1],
					sums[2] / k, mx[2], sums[3] / k, mx[3]]
		print(line)
		n.queue_free()
		await process_frame
	quit(0)
