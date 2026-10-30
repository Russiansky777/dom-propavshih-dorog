extends SceneTree
## Loop seams of the live figures' clips: the pose at the clip's end vs its start (walk loops; talk / listen /
## gesture restart) and the per-sample velocity next to the seam, mm. Also the key spacing of the tracks.
##   godot --headless --path game -s res://tests/probe_clips.gd [-- id ...]

const BONES := ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]


func _initialize() -> void:
	_run()


func _pose_at(v: Actor3D, nm: String, t: float) -> Dictionary:
	var bt := v.tree.tree_root as AnimationNodeBlendTree
	(bt.get_node("idle_a") as AnimationNodeAnimation).animation = nm
	v.tree.set("parameters/idle_a_seek/seek_request", t)
	v.tree.set("parameters/idle_mix/blend_amount", 0.0)
	v.tree.set("parameters/loco/blend_amount", 0.0)
	v.tree.set("parameters/actb/blend_amount", 0.0)
	v.model.position = Vector3.ZERO
	v.tree.advance(0.0)
	var out := {}
	for b in BONES:
		out[b] = v.bone_model(b)
	return out


func _dist(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var wb := ""
	for k in a.keys():
		var d: float = (a[k] - b[k]).length()
		if d > worst:
			worst = d
			wb = k
	return [worst * 1000.0, wb]


func _run() -> void:
	await process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["agata", "nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana", "tamara"]
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var v := Actor3D.new()
		root.add_child(v)
		if not v.setup(spec):
			print(id, " not loaded ", v.load_error)
			continue
		if v.life != null:
			v.life.active = false
		for role in v.clips.keys():
			var nm: String = v.clips[role]
			var a := v.anim.get_animation(nm)
			var L := a.length
			var p0 := _pose_at(v, nm, 0.0)
			var p1 := _pose_at(v, nm, L - 0.0005)
			var pe := _pose_at(v, nm, L - 1.0 / 30.0)
			var pn := _pose_at(v, nm, 1.0 / 30.0)
			var seam := _dist(p0, p1)
			var vel_end := _dist(p1, pe)
			var vel_start := _dist(pn, p0)
			# key spacing of the busiest track
			var keys := 0
			for i in a.get_track_count():
				keys = maxi(keys, a.track_get_key_count(i))
			print("%-9s %-6s %-28s len %.2fs keys %d (%.1f/s)  seam %.1f mm (%s)  v_end %.1f v_start %.1f mm/30fps" % [id, role, nm.get_file(), L, keys, keys / L, seam[0], seam[1], vel_end[0], vel_start[0]])
		v.queue_free()
		await process_frame
	quit(0)
