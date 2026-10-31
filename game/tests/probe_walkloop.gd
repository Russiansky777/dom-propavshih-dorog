extends SceneTree
## Best loop window of each walk clip: poses sampled at 1/60 s (all bones, model frame, feet-centred), for every
## window [a, b] (b − a ≥ 0.55 s) the seam = position mismatch + velocity mismatch × 1/30 s, mm; prints the best.
##   godot --headless --path game -s res://tests/probe_walkloop.gd [-- id ...]

const BONES := ["Hips", "Spine", "Head", "LeftArm", "RightArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]
const H := 1.0 / 30.0


func _initialize() -> void:
	_run()


func _pose(v: Actor3D, nm: String, t: float) -> Array:
	var bt := v.tree.tree_root as AnimationNodeBlendTree
	(bt.get_node("idle_a") as AnimationNodeAnimation).animation = nm
	v.tree.set("parameters/idle_a_seek/seek_request", t)
	v.tree.set("parameters/idle_mix/blend_amount", 0.0)
	v.tree.set("parameters/loco/blend_amount", 0.0)
	v.tree.set("parameters/actb/blend_amount", 0.0)
	v.model.position = Vector3.ZERO
	v.tree.advance(0.0)
	var out := []
	for b in BONES:
		if v.skeleton.find_bone(b) >= 0:
			out.append(v.bone_model(b))
	return out


func _md(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, (a[i] - b[i]).length())
	return w


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
			continue
		if v.life != null:
			v.life.active = false
		var names: Array = [v.clips["walk"]]
		if OS.get_environment("WALK_CLIPS") != "":
			names = []
			for c in OS.get_environment("WALK_CLIPS").split(","):
				for an in v.anim.get_animation_list():
					if String(an).ends_with(c):
						names.append(String(an))
		for nm in names:
			await _best_loop(v, id, nm)
		v.queue_free()
		await process_frame
	quit(0)


func _best_loop(v: Actor3D, id: String, nm: String) -> void:
		var L := v.anim.get_animation(nm).length
		var n := int(floor(L / H)) + 1
		var P: Array = []
		for i in n:
			P.append(_pose(v, nm, minf(i * H, L - 0.0001)))
		# loop = keys at from + k·H (k < N), then back to `from`: second differences across the seam vs the clip's own
		var interior := 0.0
		var ilist: Array = []
		for i in range(1, n - 1):
			var dd := 0.0
			for k in P[i].size():
				dd = maxf(dd, (P[i + 1][k] - 2.0 * P[i][k] + P[i - 1][k]).length())
			ilist.append(dd)
		ilist.sort()
		var p95: float = ilist[int(ilist.size() * 0.95)]
		interior = ilist[ilist.size() - 1]
		var best := []
		var step := 1  # key grid
		for a in range(0, n - int(0.55 / H), step):
			for b in range(a + int(0.55 / H), n + 1, step):
				# keys a .. b-1 (H grid), wrap: P[b-1] -> P[a]
				if b - 1 >= n or b - 2 < 0:
					continue
				var s1 := 0.0
				var s2 := 0.0
				for k in P[a].size():
					s1 = maxf(s1, (P[a][k] - 2.0 * P[b - 1][k] + P[b - 2][k]).length())
					s2 = maxf(s2, (P[a + 1][k] - 2.0 * P[a][k] + P[b - 1][k]).length())
				best.append([maxf(s1, s2), a * H, b * H, s1 * 1000.0, s2 * 1000.0])
		best.sort_custom(func(x, y): return x[0] < y[0])
		var line := "%-9s walk %.2fs: interior d2 p95 %.1f max %.1f mm (1/30 s);" % [id, L, p95 * 1000.0, interior * 1000.0]
		var shown := 0
		var seen: Array = []
		for e in best:
			var dup := false
			for s0 in seen:
				if absf(s0[0] - e[1]) < 0.08 and absf(s0[1] - e[2]) < 0.08:
					dup = true
			if dup:
				continue
			seen.append([e[1], e[2]])
			line += "  [%.4f, %.4f] T %.4f seam d2 %.1f/%.1f" % [e[1], e[2], e[2] - e[1], e[3], e[4]]
			shown += 1
			if shown >= 4:
				break
		# as the game plays it now: whole clip, end -> start
		var s1n := 0.0
		var s2n := 0.0
		for k in P[0].size():
			s1n = maxf(s1n, (P[0][k] - 2.0 * P[n - 1][k] + P[n - 2][k]).length())
			s2n = maxf(s2n, (P[1][k] - 2.0 * P[0][k] + P[n - 1][k]).length())
		line += "  | now: %.1f/%.1f" % [s1n * 1000.0, s2n * 1000.0]
		print(line.replace("walk %.2fs" % L, "%s %.2fs" % [nm, L]))
