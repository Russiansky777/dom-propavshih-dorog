extends "res://tests/probe_stance_sheet.gd"
## How much a standing villager moves (after every modifier): ranges over `secs` of the hips' and the head's place
## (cm, skeleton space), the hands' and the feet's. For the sway's amplitudes and the foot locks holding.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_sway.gd -- <id,id|all> [secs=16] [state=idle]

class Grab extends SkeletonModifier3D:
	var out: Array = []
	func _process_modification_with_delta(_d: float) -> void:
		var sk := get_skeleton()
		out.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			out[b] = sk.get_bone_global_pose(b)


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = ALL if a.is_empty() or a[0] == "all" else Array(String(a[0]).split(","))
	var secs := float(a[1]) if a.size() > 1 else 16.0
	var st := String(a[2]) if a.size() > 2 else "idle"
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var sk: Skeleton3D = live.view.skeleton
		var g := Grab.new()
		sk.add_child(g)
		var unit: float = live.view.life.unit
		live.set_state(st)
		var names := ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
		var lo := {}
		var hi := {}
		var t := 0.0
		var max_step := 0.0
		var prev = null
		while t < secs:
			live.process(DT)
			await process_frame
			t += DT
			if t < 1.5 or g.out.is_empty():
				continue
			for nm in names:
				var p: Vector3 = (g.out[sk.find_bone(nm)] as Transform3D).origin / unit * 100.0
				lo[nm] = (lo[nm] as Vector3).min(p) if lo.has(nm) else p
				hi[nm] = (hi[nm] as Vector3).max(p) if hi.has(nm) else p
			var hp: Vector3 = (g.out[sk.find_bone("Hips")] as Transform3D).origin / unit * 100.0
			if prev != null:
				max_step = maxf(max_step, (hp - (prev as Vector3)).length() * 60.0)
			prev = hp
		var line := "%-9s %s:" % [id, st]
		for nm in names:
			var r: Vector3 = (hi[nm] as Vector3) - (lo[nm] as Vector3)
			line += " %s x %.1f y %.1f z %.1f |" % [nm.replace("Left", "L").replace("Right", "R"), r.x, r.y, r.z]
		print(line + " hips' top speed %.1f cm/s" % max_step)
		n.queue_free()
		await process_frame
	quit(0)
