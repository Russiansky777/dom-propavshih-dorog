extends SceneTree
## How much the shoulder tops and the upper chest slide on the body (Director 06.11, 22:02: «плечи ходят как
## желейные, хотя по идее почти не двигаются»): the figure skinned on the CPU as posed (every modifier); the vertices
## between the neck and the shoulder joints at shoulder height (±6 cm), followed in the frame of the chest bone
## (Spine02) through `state` for `secs`: how far each goes (mm, max − min of its position), mean and 90th percentile.
## The chest moving as a whole does not count; the skin sliding on it does.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_shoulder_jelly.gd -- id [state] [secs] [off=k]

const DT := 1.0 / 60.0
const Pen := preload("res://tests/probe_hand_penetration.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var state: String = a[1] if a.size() > 1 else "talk"
	var secs := float(a[2]) if a.size() > 2 else 6.0
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var off := ""
	for k in range(3, a.size()):
		if String(a[k]).begins_with("off="):
			off = String(a[k]).substr(4)
			for key in off.split(","):
				(spec["rt3d"] as Dictionary).erase(key)
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
	var g = Pen.Grab.new()
	sk.add_child(g)
	var unit := float(live.arm_body.get("_unit")) if live.arm_body != null else 1.0
	var chest := sk.find_bone("Spine02")
	var pn: Vector3 = sk.get_bone_global_rest(sk.find_bone("neck")).origin
	var la: Vector3 = sk.get_bone_global_rest(sk.find_bone("LeftArm")).origin
	var ra: Vector3 = sk.get_bone_global_rest(sk.find_bone("RightArm")).origin
	var ysh := (la.y + ra.y) * 0.5
	# the chosen vertices: [mesh entry, vertex index]
	var prepped: Array = Pen.prep(sk, live.view.meshes)
	var picks: Array = []
	for ei in prepped.size():
		var e: Array = prepped[ei]
		var vs: PackedVector3Array = e[0]
		var mats := {}
		var rest_poses: Array = []
		for b in sk.get_bone_count():
			rest_poses.append(sk.get_bone_global_rest(b))
		for k in range(0, vs.size(), 3):
			var r: Array = Pen.skin_pt(e, k, rest_poses, mats)
			var p: Vector3 = r[0]
			if absf(p.y - ysh) > 0.06 * unit:
				continue
			var inside: bool = (p.x < la.x and p.x > pn.x + 0.03 * unit) or (p.x > ra.x and p.x < pn.x - 0.03 * unit)
			if inside:
				picks.append([ei, k])
	live.set_state(state)
	var lo: Array = []
	var hi: Array = []
	for i in picks.size():
		lo.append(Vector3(INF, INF, INF))
		hi.append(Vector3(-INF, -INF, -INF))
	var t := 0.0
	var f := 0
	while t < secs:
		live.process(DT)
		await process_frame
		t += DT
		f += 1
		if t < 1.0 or g.out.is_empty() or f % 4 != 0:
			continue
		var inv: Transform3D = (g.out[chest] as Transform3D).affine_inverse()
		var mats_by: Dictionary = {}
		for i in picks.size():
			var ei: int = picks[i][0]
			if not mats_by.has(ei):
				mats_by[ei] = {}
			var r: Array = Pen.skin_pt(prepped[ei], picks[i][1], g.out, mats_by[ei])
			var q: Vector3 = inv * (r[0] as Vector3) / unit
			lo[i] = Vector3(minf(lo[i].x, q.x), minf(lo[i].y, q.y), minf(lo[i].z, q.z))
			hi[i] = Vector3(maxf(hi[i].x, q.x), maxf(hi[i].y, q.y), maxf(hi[i].z, q.z))
	var rngs: Array = []
	for i in picks.size():
		rngs.append(((hi[i] as Vector3) - (lo[i] as Vector3)).length() * 1000.0)
	rngs.sort()
	var mean := 0.0
	for v in rngs:
		mean += v
	mean /= maxf(1.0, rngs.size())
	print("%s %s off=[%s]: %d shoulder/chest vertices slide on the chest — mean %.1f mm, 90%% %.1f mm, max %.1f mm" % [
			id, state, off, rngs.size(), mean, rngs[int(rngs.size() * 0.9)] if rngs.size() > 0 else 0.0,
			rngs[-1] if rngs.size() > 0 else 0.0])
	quit(0)
