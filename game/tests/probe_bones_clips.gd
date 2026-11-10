extends SceneTree
## Which extra bones (skirt, apron, hem…) a villager's skeleton has and which clips move them.
##   godot --path game -s res://tests/probe_bones_clips.gd -- <id>

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var id: String = OS.get_cmdline_user_args()[0]
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var A3 = load("res://scripts/actors/actor_3d.gd")
	var v = A3.new()
	root.add_child(v)
	if not v.setup(spec):
		print("not loaded: ", v.load_error)
		quit(1)
		return
	var sk: Skeleton3D = v.skeleton
	var std := ["Hips", "Spine", "Neck", "Head", "Shoulder", "Arm", "Hand", "Leg", "Foot", "Toe", "Thumb", "Index", "Middle", "Ring", "Pinky", "Eye", "Jaw"]
	var extra: Array = []
	for b in sk.get_bone_count():
		var nm := sk.get_bone_name(b)
		var is_std := false
		for s in std:
			if nm.contains(s):
				is_std = true
		if not is_std:
			extra.append(nm)
	print("bones %d, extra %d: %s" % [sk.get_bone_count(), extra.size(), str(extra)])
	var anim: AnimationPlayer = v.anim
	for nm in anim.get_animation_list():
		var a := anim.get_animation(nm)
		var moved := {}
		for i in a.get_track_count():
			var bn := String(a.track_get_path(i).get_concatenated_subnames())
			if extra.has(bn) and a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				# does it move at all?
				var q0: Quaternion = a.track_get_key_value(i, 0)
				var mx := 0.0
				for k in a.track_get_key_count(i):
					mx = maxf(mx, rad_to_deg(q0.angle_to(a.track_get_key_value(i, k))))
				moved[bn] = snappedf(mx, 0.1)
		print("clip %s: %.2f s, extra-bone tracks %d, moving >1°: %d  %s" % [nm, a.length, moved.size(), moved.values().filter(func(x): return x > 1.0).size(), str(moved).substr(0, 300)])
	quit(0)
