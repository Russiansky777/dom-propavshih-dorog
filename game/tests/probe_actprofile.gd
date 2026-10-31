extends SceneTree
## Profile of Agata's one-shot clips: per 0.1 s the right/left hand height and speed, the hips' travel (does
## the clip walk?), so a window of the clip that holds the gesture itself can be chosen.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var v := Actor3D.new()
	root.add_child(v)
	v.setup(spec)
	v.life.active = false
	# PROFILE_CLIPS=name,name — clips by name (a clip not yet in a role); default — the action roles
	var names: Array = []
	if OS.get_environment("PROFILE_CLIPS") != "":
		names = Array(OS.get_environment("PROFILE_CLIPS").split(","))
	else:
		for role in ["open", "pick", "reach", "talk"]:
			names.append(v.clips[role])
	for nm in names:
		var role := String(nm)
		var L := v.anim.get_animation(nm).length
		var bt := v.tree.tree_root as AnimationNodeBlendTree
		(bt.get_node("idle_a") as AnimationNodeAnimation).animation = nm
		var prev := {}
		var out := "%s %s %.2fs\n" % [role, nm, L]
		var t := 0.0
		while t <= L + 0.001:
			v.tree.set("parameters/idle_a_seek/seek_request", minf(t, L - 0.0005))
			v.tree.set("parameters/idle_mix/blend_amount", 0.0)
			v.tree.set("parameters/loco/blend_amount", 0.0)
			v.tree.set("parameters/actb/blend_amount", 0.0)
			v.model.position = Vector3.ZERO
			v.tree.advance(0.0)
			var rh := v.bone_model("RightHand")
			var lh := v.bone_model("LeftHand")
			var hp := v.bone_model("Hips")
			var lf := v.bone_model("LeftFoot")
			var rf := v.bone_model("RightFoot")
			if not prev.is_empty():
				out += "  %.1f  R y%.2f v%.2f  L y%.2f v%.2f  hips (%.2f,%.2f,%.2f) feet L(%.2f,%.2f) R(%.2f,%.2f)\n" % [t, rh.y, (rh - prev["r"]).length() / 0.1, lh.y, (lh - prev["l"]).length() / 0.1, hp.x, hp.y, hp.z, lf.x, lf.z, rf.x, rf.z]
			prev = {"r": rh, "l": lh}
			t += 0.1
		print(out)
	quit(0)
