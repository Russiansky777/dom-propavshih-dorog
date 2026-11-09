extends SceneTree
## How much a clip moves the body (the sway of a stance): per bone, the range of its position (cm, by the model's
## scale) and of its rotation (deg, about its mean) over the clip. For matching the villagers' life to Agata's idle.
##   godot --headless --path game -s res://tests/probe_clip_ranges.gd -- <actor id> <clip role or name> [bones=Hips,Spine,…]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % a[0]))
	var rt: Dictionary = spec["rt3d"]
	var scene: Node = (load(String(rt["scene"])) as PackedScene).instantiate()
	root.add_child(scene)
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var want := String(rt.get("clips", {}).get(a[1], a[1]))
	var bones := ["Hips", "Spine", "Spine01", "Spine02", "neck", "Head", "LeftArm", "RightArm", "LeftForeArm", "LeftUpLeg"]
	if a.size() > 2:
		bones = Array(String(a[2]).trim_prefix("bones=").split(","))
	var unit := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y / 1.5   # ~ skeleton units per metre (head at ~1.5 m)
	for nm in ap.get_animation_list():
		var bare := String(nm).get_slice("/", String(nm).get_slice_count("/") - 1)
		if bare != want:
			continue
		var an := ap.get_animation(nm)
		print("%s %s: %.1f s, head at %.1f units" % [a[0], bare, an.length, sk.get_bone_global_rest(sk.find_bone("Head")).origin.y])
		for i in an.get_track_count():
			var bn := String(an.track_get_path(i).get_concatenated_subnames())
			if not bones.has(bn):
				continue
			var n := an.track_get_key_count(i)
			if an.track_get_type(i) == Animation.TYPE_POSITION_3D:
				var lo := Vector3(INF, INF, INF)
				var hi := -lo
				for k in n:
					var v: Vector3 = an.track_get_key_value(i, k)
					lo = lo.min(v)
					hi = hi.max(v)
				print("  %-12s position range (cm): x %.1f y %.1f z %.1f" % [bn, (hi.x - lo.x) / unit * 100, (hi.y - lo.y) / unit * 100, (hi.z - lo.z) / unit * 100])
			elif an.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				var q0: Quaternion = an.track_get_key_value(i, 0)
				var mx := Vector3.ZERO
				var mn := Vector3.ZERO
				for k in n:
					var q: Quaternion = an.track_get_key_value(i, k)
					var d := (q0.inverse() * q)
					if d.w < 0:
						d = -d
					var rv := Vector3(d.x, d.y, d.z) * 2.0
					mx = mx.max(rv)
					mn = mn.min(rv)
				print("  %-12s rotation range (deg): x %.1f y %.1f z %.1f" % [bn, rad_to_deg(mx.x - mn.x), rad_to_deg(mx.y - mn.y), rad_to_deg(mx.z - mn.z)])
	quit(0)
