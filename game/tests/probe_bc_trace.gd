extends SceneTree
## Frame by frame: BodyClear's turn of each upper arm (deg) and the hand's step (mm) — Director 06.11, 19:27: «руки
## дергаются как сумасшедшие, меняя положение туда и назад».
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_bc_trace.gd -- id state [seconds] [off=k]

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


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var state: String = a[1]
	var secs := float(a[2]) if a.size() > 2 else 6.0
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	for k in range(3, a.size()):
		var s := String(a[k])
		if s.begins_with("ab="):   # ab=no_back:false
			var kv := s.substr(3).split(":")
			spec["rt3d"]["arm_body"][kv[0]] = JSON.parse_string(kv[1])
		elif s.begins_with("off="):
			(spec["rt3d"] as Dictionary).erase(s.substr(4))
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
	var unit := float(live.arm_body.get("_unit")) if live.arm_body != null else 1.0
	if a.has("bcoff") and live.arm_body != null:   # BodyClear on the figure but not turning: the clip alone, same units
		live.arm_body.set("enabled", false)
	var hb := [sk.find_bone("LeftHand"), sk.find_bone("RightHand")]
	live.set_state("idle")
	for i in 60:
		live.process(DT)
		await process_frame
	live.set_state(state)
	var prev := [Vector3.ZERO, Vector3.ZERO]
	var pv := [Vector3.ZERO, Vector3.ZERO]
	var t := 0.0
	var acc_max := [0.0, 0.0]
	var flips := [0, 0]
	var jolts := [0, 0]
	var prev_d := [Vector3.ZERO, Vector3.ZERO]
	var line := ""
	var f := 0
	while t < secs:
		live.process(DT)
		await process_frame
		t += DT
		f += 1
		if g.out.is_empty():
			continue
		var rl: Array = live.arm_body.get("_rot") if live.arm_body != null else [Vector3.ZERO, Vector3.ZERO]
		for s in 2:
			var p: Vector3 = (g.out[hb[s]] as Transform3D).origin / unit
			var d: Vector3 = p - (prev[s] as Vector3)
			if f > 30:   # the first half second: the switch of state itself
				var acc: float = (d - (prev_d[s] as Vector3)).length() * 1000.0
				acc_max[s] = maxf(acc_max[s], acc)
				if acc > 2.0:
					jolts[s] += 1
				if d.length() > 0.0005 and (prev_d[s] as Vector3).length() > 0.0005 and d.dot(prev_d[s] as Vector3) < 0.0:
					flips[s] += 1
			prev_d[s] = d
			prev[s] = p
		if f % 3 == 0:
			line += " %.0f/%.0f" % [rad_to_deg((rl[0] as Vector3).length()), rad_to_deg((rl[1] as Vector3).length())]
	print("%s %s: hand jerk (mm/frame²) L %.1f R %.1f, frames over 2 L %d R %d, back-and-forth reversals L %d R %d" % [
			id, state, acc_max[0], acc_max[1], jolts[0], jolts[1], flips[0], flips[1]])
	print("  turn L/R deg every 0.05 s:" + line)
	quit(0)
