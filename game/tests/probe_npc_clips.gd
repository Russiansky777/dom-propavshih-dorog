extends SceneTree
## The villagers' standing clips as drawn (no foot locks): per clip the hips' sway across and along (cm, range), how
## far each foot travels on the floor while it is down (cm) and how often a foot leaves the floor — a figure that
## «floats left and right» with feet that «walk by themselves» (Director 31.10, 15:04).
##   godot --headless --path game -s res://tests/probe_npc_clips.gd [-- id ...]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["pelageya", "nina", "pavel", "mitya", "ilya", "ilya_wife", "ulyana", "tamara", "agata"]
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		if OS.get_environment("RT3D_DIR") != "" and id != "agata":
			spec["rt3d"]["scene"] = "%s/%s/%s_rt.glb" % [OS.get_environment("RT3D_DIR"), id, id]   # a local copy of the models
		var v := Actor3D.new()
		root.add_child(v)
		if not v.setup(spec):
			print("%s: not loaded (%s)" % [id, v.load_error])
			continue
		if v.life != null:
			v.life.active = false
		var bt := v.tree.tree_root as AnimationNodeBlendTree
		var names: Array = []
		for r in ["idle", "listen", "talk"]:
			if v.clips.has(r):
				names.append([r, v.clips[r]])
		for e in v.idle_pool:
			if not names.any(func(x): return x[1] == e["name"]):
				names.append(["idle*", e["name"]])
		for pair in names:
			var nm: String = pair[1]
			(bt.get_node("idle_a") as AnimationNodeAnimation).animation = nm
			var L := v.anim.get_animation(nm).length
			var hx := [INF, -INF]
			var hz := [INF, -INF]
			var travel := [0.0, 0.0]
			var lifts := [0, 0]
			var prev: Array = []
			var low := [INF, INF]
			var rows: Array = []
			var N := int(L * 30.0)
			for i in N:
				v.tree.set("parameters/idle_a_seek/seek_request", L * i / N)
				v.tree.set("parameters/idle_mix/blend_amount", 0.0)
				v.tree.set("parameters/loco/blend_amount", 0.0)
				v.tree.set("parameters/actb/blend_amount", 0.0)
				v.model.position = Vector3.ZERO
				v.tree.advance(0.0)
				var h := v.bone_model("Hips")
				hx = [minf(hx[0], h.x), maxf(hx[1], h.x)]
				hz = [minf(hz[0], h.z), maxf(hz[1], h.z)]
				var f := v.feet_model()
				rows.append(f)
				for k in 2:
					low[k] = minf(low[k], minf(f[k * 2].y, f[k * 2 + 1].y))
			var up := [false, false]
			for i in range(1, rows.size()):
				for k in 2:
					var f: Array = rows[i]
					var hgt: float = minf(f[k * 2].y, f[k * 2 + 1].y) - float(low[k])
					var now_up := hgt > 0.02
					if now_up and not up[k]:
						lifts[k] += 1
					up[k] = now_up
					if not now_up:
						var a: Vector3 = f[k * 2]
						var b: Vector3 = rows[i - 1][k * 2]
						travel[k] += Vector2(a.x - b.x, a.z - b.z).length()
			print("%-9s %-6s %-34s %5.1fs  hips across %4.1f cm, along %4.1f cm; feet down travel L %4.1f R %4.1f cm (%.1f / %.1f cm/s); lifts L %d R %d" % [id, pair[0], nm, L, (hx[1] - hx[0]) * 100, (hz[1] - hz[0]) * 100, travel[0] * 100, travel[1] * 100, travel[0] * 100 / L, travel[1] * 100 / L, lifts[0], lifts[1]])
		v.queue_free()
		await process_frame
	quit(0)
