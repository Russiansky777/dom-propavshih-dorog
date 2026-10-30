extends SceneTree
## Skirt springs over a walk: per frame (after the modifiers, skeleton_updated) the hem tips of the front and back
## chains and the shins at hem height — how far the hem moves, and whether a shin ever passes outside the hem.
##   godot --headless --path game -s res://tests/probe_skirt.gd [-- stiffness drag gravity radius]

var v: Actor3D
var rows: Array = []


func _initialize() -> void:
	_run()


func _on_updated() -> void:
	var sk := v.skeleton
	var row := {}
	for c in 8:
		var b := sk.find_bone("Skirt%d_2" % c)
		if b >= 0:
			row["c%d" % c] = v._skel_to_turn() * sk.get_bone_global_pose(b).origin
	for s in ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]:
		row[s] = v.bone_model(s)
	rows.append(row)


func _run() -> void:
	await process_frame
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var a := OS.get_cmdline_user_args()
	if a.size() >= 4:
		spec["rt3d"]["skirt"]["stiffness"] = float(a[0])
		spec["rt3d"]["skirt"]["drag"] = float(a[1])
		spec["rt3d"]["skirt"]["gravity"] = float(a[2])
		spec["rt3d"]["skirt"]["radius_m"] = float(a[3])
	if a.size() >= 5:
		for col in spec["rt3d"]["skirt"]["colliders"]:
			col["radius_m"] = float(col["radius_m"]) * float(a[4])
	v = Actor3D.new()
	root.add_child(v)
	if not v.setup(spec):
		print("not loaded ", v.load_error)
		quit(1)
		return
	print("skirt sim: ", v.skirt != null, " chains ", v.skirt.setting_count if v.skirt else 0)
	for ch in v.skirt.get_children():
		var cap := ch as SpringBoneCollisionCapsule3D
		var b := v.skeleton.find_bone(cap.bone_name)
		var head := v.bone_model(cap.bone_name)
		var child := -1
		for cb in v.skeleton.get_bone_children(b):
			child = cb
		var tip: Vector3 = v._skel_to_turn() * v.skeleton.get_bone_global_pose(child).origin if child >= 0 else head
		var yaxis: Vector3 = (v._skel_to_turn().basis * v.skeleton.get_bone_global_pose(b).basis) * Vector3.UP
		print("  ", cap.bone_name, " head ", head.snapped(Vector3.ONE * 0.01), " child ", tip.snapped(Vector3.ONE * 0.01), " bone +Y ", yaxis.normalized().snapped(Vector3.ONE * 0.01), " along ", (tip - head).normalized().snapped(Vector3.ONE * 0.01))
	v.skeleton.skeleton_updated.connect(_on_updated)
	var ph := 0.0
	for i in 240:
		ph += (1.0 / 60.0) / v.walk_len
		v.pose(1.0 / 60.0, fposmod(ph, 1.0), 1.0 if i > 20 else float(i) / 20.0, 0.0)
		await process_frame
	# hem: range of motion of the tips; shins: how far outside the hem ring they get
	var rng := {}
	var worst_out := 0.0
	for r in rows.slice(60):
		for k in r.keys():
			if String(k).begins_with("c"):
				var p: Vector3 = r[k]
				if not rng.has(k):
					rng[k] = [p, p]
				rng[k][0] = (rng[k][0] as Vector3).min(p)
				rng[k][1] = (rng[k][1] as Vector3).max(p)
	var line := "hem tip travel (m, x/y/z):"
	for k in ["c0", "c2", "c4", "c6"]:
		if rng.has(k):
			var d: Vector3 = rng[k][1] - rng[k][0]
			line += " %s %.3f/%.3f/%.3f" % [k, d.x, d.y, d.z]
	print(line)
	# a foot (ankle) out beyond the hem ring in its direction, while it is high in the swing → boot «floats»
	for r in rows.slice(60):
		for s in ["LeftFoot", "RightFoot"]:
			var f: Vector3 = r[s]
			var dir := Vector2(f.x, f.z).normalized()
			var hem_r := 0.0
			for c in 8:
				var t: Vector3 = r["c%d" % c]
				hem_r = maxf(hem_r, Vector2(t.x, t.z).dot(dir))
			worst_out = maxf(worst_out, Vector2(f.x, f.z).length() - hem_r)
	print("ankle beyond the hem ring: up to %.3f m; frames %d" % [worst_out, rows.size()])
	quit(0)
