extends SceneTree
## The hand's path frame by frame through a state switch (Director 06.11, 20:21, a second look at the video: «кисть
## Павла 5,2–5,6 с сначала опускается к фартуку, затем уходит обратно наружу и вверх»): talk for `talk_s`, then
## listen; from `from` s to `to` s each frame the hands' sideways (out from the body) and up positions, cm, in the hips'
## frame — with BodyClear turning (on) and not (off), side by side, and BodyClear's turn (deg).
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


func _one(id: String, turning: bool, talk_s: float, from: float, to: float) -> Array:
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
	var unit := float(live.arm_body.get("_unit"))
	live.arm_body.set("enabled", turning)
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
	var off: Array = await _one(id, false, talk_s, from, to)
	var on: Array = await _one(id, true, talk_s, from, to)
	print("t     | clip alone: L out/up/fwd   R out/up/fwd | with clearing: L out/up/fwd   R out/up/fwd | turn L/R | in L/R")
	for k in mini(off.size(), on.size()):
		var o: Array = off[k]
		var c: Array = on[k]
		print("%.2f | %5.1f %5.1f %5.1f  %5.1f %5.1f %5.1f | %5.1f %5.1f %5.1f  %5.1f %5.1f %5.1f | %4.1f %4.1f | %.1f %.1f" % [
				o[0], o[1], o[2], o[3], o[4], o[5], o[6], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10]])
	quit(0)
