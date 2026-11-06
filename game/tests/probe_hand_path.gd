extends SceneTree
## The hand's path frame by frame through a state switch (Director 06.11, 20:21, a second look at the video: «кисть
## Павла 5,2–5,6 с сначала опускается к фартуку, затем уходит обратно наружу и вверх»): talk for `talk_s`, then
## listen; from `from` s to `to` s each frame the hands' sideways (out from the body) and up positions, cm, in the hips'
## frame in three modes: unbaked with runtime off, baked with runtime off, baked with runtime on.
## All modes retain Actor3D smoothing, arm_hang and pose blending. "Unbaked" is not the raw Meshy clip.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_hand_path.gd -- id [talk_s=5] [from=4.9] [to=6.2]

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


func _one(id: String, bake_clearing: bool, runtime_clearing: bool, talk_s: float, from: float, to: float) -> Array:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if not bake_clearing:
		(spec["rt3d"]["arm_body"] as Dictionary).erase("bake")
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
	var unit := float(live.arm_body.get("_unit"))
	live.arm_body.set("enabled", runtime_clearing)
	var hb := [sk.find_bone("LeftHand"), sk.find_bone("RightHand")]
	var hips := sk.find_bone("Hips")
	var rows: Array = []
	live.set_state("talk")
	var t := 0.0
	var switched := false
	while t < to:
		if t >= talk_s and not switched:
			live.set_state("listen")
			switched = true
		live.process(DT)
		await process_frame
		t += DT
		if t < from or g.out.is_empty():
			continue
		var inv: Transform3D = (g.out[hips] as Transform3D).affine_inverse()
		var r := [t]
		for s in 2:
			var p: Vector3 = inv * (g.out[hb[s]] as Transform3D).origin / unit
			r.append(absf(p.x) * 100.0)
			r.append(p.y * 100.0)
			r.append(p.z * 100.0)
		var rl: Array = live.arm_body.get("_rot")
		r.append(rad_to_deg((rl[0] as Vector3).length()))
		r.append(rad_to_deg((rl[1] as Vector3).length()))
		r.append(float(live.arm_body.get("shown_m")[0]) * 100.0)
		r.append(float(live.arm_body.get("shown_m")[1]) * 100.0)
		rows.append(r)
	n.queue_free()
	await process_frame
	return rows


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var talk_s := float(a[1]) if a.size() > 1 else 5.0
	var from := float(a[2]) if a.size() > 2 else 4.9
	var to := float(a[3]) if a.size() > 3 else 6.2
	var modes := [["unbaked_runtime_off", false, false], ["baked_runtime_off", true, false], ["baked_runtime_on", true, true]]
	print("All modes retain Actor3D smoothing, arm_hang and blending; unbaked is not raw Meshy.")
	print("mode,t_s,L_out_cm,L_up_cm,L_fwd_cm,R_out_cm,R_up_cm,R_fwd_cm,L_turn_deg,R_turn_deg,L_in_cm,R_in_cm")
	for mode in modes:
		var rows: Array = await _one(id, mode[1], mode[2], talk_s, from, to)
		for r in rows:
			print("%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [
					mode[0], r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]])
	quit(0)
