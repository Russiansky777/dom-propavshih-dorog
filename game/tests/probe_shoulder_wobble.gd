extends SceneTree
## Shoulders frame by frame (Director 06.11, 22:02: «у них плечи ходят как желейные, хотя по идее они вообще почти
## не двигаются», a still of Ilya standing): standing for `secs`, after every modifier — per side the shoulder
## (clavicle) and the upper arm, their turn in the hips' frame: how far they go (deg, max − min), how fast (deg/s, the
## largest) and how often the turn reverses (wobble). Variants switch rt3d parts off to find who moves them.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_shoulder_wobble.gd -- id [state] [secs] [off=a,b]

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


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var state: String = a[1] if a.size() > 1 else "idle"
	var secs := float(a[2]) if a.size() > 2 else 8.0
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var off := ""
	for k in range(3, a.size()):
		if String(a[k]).begins_with("off="):
			off = String(a[k]).substr(4)
			for key in off.split(","):
				var kp := key.split(".")
				if kp.size() == 2:
					(spec["rt3d"][kp[0]] as Dictionary).erase(kp[1])
				else:
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
	var g := Grab.new()
	sk.add_child(g)
	var hips := sk.find_bone("Hips")
	var bones := ["LeftShoulder", "LeftArm", "RightShoulder", "RightArm", "Spine02", "neck"]
	var ids: Array = []
	for b in bones:
		ids.append(sk.find_bone(b))
	live.set_state(state)
	var prev: Array = []
	var prev_w: Array = []
	var mx: Array = []
	var flips: Array = []
	var lo: Array = []
	var hi: Array = []
	for b in bones:
		prev.append(null)
		prev_w.append(Vector3.ZERO)
		mx.append(0.0)
		flips.append(0)
		lo.append(Vector3(INF, INF, INF))
		hi.append(Vector3(-INF, -INF, -INF))
	var t := 0.0
	while t < secs:
		live.process(DT)
		await process_frame
		t += DT
		if t < 1.0 or g.out.is_empty():
			continue
		var hq: Quaternion = (g.out[hips] as Transform3D).basis.get_rotation_quaternion()
		for i in bones.size():
			var q: Quaternion = hq.inverse() * (g.out[ids[i]] as Transform3D).basis.get_rotation_quaternion()
			var e := q.get_euler() * (180.0 / PI)
			lo[i] = Vector3(minf(lo[i].x, e.x), minf(lo[i].y, e.y), minf(lo[i].z, e.z))
			hi[i] = Vector3(maxf(hi[i].x, e.x), maxf(hi[i].y, e.y), maxf(hi[i].z, e.z))
			if prev[i] != null:
				var dq: Quaternion = ((prev[i] as Quaternion).inverse() * q).normalized()
				if dq.w < 0.0:
					dq = -dq
				var ang := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
				var ax := Vector3(dq.x, dq.y, dq.z)
				var w: Vector3 = ax.normalized() * ang * (180.0 / PI) / DT if ax.length() > 1e-9 else Vector3.ZERO
				mx[i] = maxf(mx[i], w.length())
				if w.length() > 2.0 and (prev_w[i] as Vector3).length() > 2.0 and w.dot(prev_w[i]) < 0.0:
					flips[i] += 1
				prev_w[i] = w
			prev[i] = q
	var line := "%s %s off=[%s]:" % [id, state, off]
	for i in bones.size():
		var rng: Vector3 = hi[i] - lo[i]
		line += "  %s range %.1f° speed≤%.0f°/s rev %d" % [bones[i], maxf(rng.x, maxf(rng.y, rng.z)), mx[i], flips[i]]
	print(line)
	quit(0)
