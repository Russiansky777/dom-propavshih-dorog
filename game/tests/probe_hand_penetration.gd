extends SceneTree
## How deep the hands really go into the clothes (Director 06.11, 15:56: «Павел слушает… руки въезжают в тело»): the
## figure is posed as NpcLive3D poses it (every modifier, BodyClear last), then skinned on the CPU — every hand vertex is
## checked against the nearest vertex of the body and clothes (not arms, not head): behind its surface (along its normal)
## by how much. BodyClear's own hull (rest pose, one bone per centimetre of height) said 0 cm where the hand was hidden
## in the apron. Prints per state the deepest hand vertex per side (cm) and the share of hand vertices hidden.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_hand_penetration.gd -- id[,id] [state,state] [off=k]

const DT := 1.0 / 60.0
const CELL := 0.03   # metres

var _poses: Array = []


class Grab extends SkeletonModifier3D:
	var out: Array = []
	func _process_modification_with_delta(_d: float) -> void:
		var sk := get_skeleton()
		out.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			out[b] = sk.get_bone_global_pose(b)


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


## Per mesh: [verts, normals, per-vertex [bind idx×4], [w×4], bind bones, bind poses, class per vertex (0 skip, 1 body,
## 2 left hand, 3 right hand)]
static func prep(sk: Skeleton3D, meshes: Array) -> Array:
	var cls_of := {}
	for b in sk.get_bone_count():
		var nm := sk.get_bone_name(b)
		var c := 1
		if nm.contains("Arm") or nm.contains("Shoulder") or nm.contains("Head") or nm.to_lower().contains("neck") \
				or nm.contains("Eye") or nm.contains("Jaw"):
			c = 0
		if nm.begins_with("LeftHand") or (nm.begins_with("Left") and (nm.contains("Thumb") or nm.contains("Index") \
				or nm.contains("Middle") or nm.contains("Ring") or nm.contains("Pinky"))):
			c = 2
		if nm.begins_with("RightHand") or (nm.begins_with("Right") and (nm.contains("Thumb") or nm.contains("Index") \
				or nm.contains("Middle") or nm.contains("Ring") or nm.contains("Pinky"))):
			c = 3
		if OS.get_environment("PEN_BODYONLY") != "" and c == 1 and not nm in ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "RightUpLeg"]:
			c = 0
		cls_of[b] = c
	var out := []
	for mi in meshes:
		var skin: Skin = (mi as MeshInstance3D).skin
		if skin == null:
			continue
		var bb := PackedInt32Array()
		var bp: Array = []
		for j in skin.get_bind_count():
			var b := skin.get_bind_bone(j)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(j))
			bb.append(b)
			bp.append(skin.get_bind_pose(j))
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bi = arr[Mesh.ARRAY_BONES]
			var bw = arr[Mesh.ARRAY_WEIGHTS]
			if bi == null or bw == null or vs.is_empty():
				continue
			var per: int = bi.size() / vs.size()
			var cls := PackedByteArray()
			cls.resize(vs.size())
			for k in vs.size():
				var best := -1
				var wb := 0.0
				for c in per:
					if float(bw[k * per + c]) > wb:
						wb = bw[k * per + c]
						best = int(bi[k * per + c])
				cls[k] = cls_of.get(bb[best], 0) if best >= 0 else 0
			out.append([vs, ns, bi, bw, per, bb, bp, cls])
	return out


static func skin_pt(e: Array, k: int, poses: Array, mats: Dictionary) -> Array:
	var per: int = e[4]
	var p := Vector3.ZERO
	var n := Vector3.ZERO
	for c in per:
		var w: float = e[3][k * per + c]
		if w <= 0.0:
			continue
		var j: int = e[2][k * per + c]
		var m: Transform3D
		if mats.has(j):
			m = mats[j]
		else:
			m = (poses[e[5][j]] as Transform3D) * (e[6][j] as Transform3D)
			mats[j] = m
		p += (m * (e[0] as PackedVector3Array)[k]) * w
		n += (m.basis * (e[1] as PackedVector3Array)[k]) * w
	return [p, n.normalized()]


## [deepest hand vertex behind the body/clothes surface per side (m), share of hand vertices behind it per side]
static func measure(prepped: Array, poses: Array, unit: float) -> Array:
	var cell := CELL * unit
	var grid := {}
	var hands := [[], []]
	for e in prepped:
		var mats := {}
		var cls: PackedByteArray = e[7]
		for k in cls.size():
			var c := cls[k]
			if c == 0:
				continue
			var r := skin_pt(e, k, poses, mats)
			if c == 1:
				var key := Vector3i((r[0] as Vector3) / cell)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(r)
			else:
				hands[c - 2].append(r[0])
	var deep := [0.0, 0.0]
	var share := [0.0, 0.0]
	for side in 2:
		var hid := 0
		for h in hands[side]:
			var key := Vector3i((h as Vector3) / cell)
			var bd := INF
			var bn := Vector3.ZERO
			var bpp := Vector3.ZERO
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var kk := key + Vector3i(dx, dy, dz)
						if not grid.has(kk):
							continue
						for r in grid[kk]:
							var d: float = (h as Vector3).distance_squared_to(r[0])
							if d < bd:
								bd = d
								bpp = r[0]
								bn = r[1]
			if bd == INF:
				continue
			var dep: float = -((h as Vector3) - bpp).dot(bn) / unit
			if dep > 0.002:
				hid += 1
				deep[side] = maxf(deep[side], dep)
		share[side] = float(hid) / maxf(1.0, float((hands[side] as Array).size()))
	# the silhouette: per centimetre of height, the farthest body/clothes vertex per 6° around the slice's middle (as
	# BodyClear, but from the posed mesh) — a hand between the apron and the thigh is inside it
	var step := 0.01 * unit
	var acc := {}
	for cellv in grid.values():
		for r in cellv:
			var p: Vector3 = r[0]
			var key := int(floor(p.y / step))
			if not acc.has(key):
				acc[key] = []
			(acc[key] as Array).append(Vector2(p.x, p.z))
	var hull := {}
	for key in acc.keys():
		var pts: Array = acc[key]
		var c := Vector2.ZERO
		for q in pts:
			c += q
		c /= float(pts.size())
		var rr := PackedFloat32Array()
		rr.resize(60)
		for q in pts:
			var dd: Vector2 = q - c
			var s := int(fposmod(atan2(dd.y, dd.x), TAU) / TAU * 60) % 60
			rr[s] = maxf(rr[s], dd.length())
		hull[key] = [c, rr]
	var hd := [-1.0, -1.0]
	for side in 2:
		for h in hands[side]:
			var key := int(floor((h as Vector3).y / step))
			if not hull.has(key):
				continue
			var c: Vector2 = hull[key][0]
			var rr: PackedFloat32Array = hull[key][1]
			var d := Vector2((h as Vector3).x, (h as Vector3).z) - c
			var s := int(fposmod(atan2(d.y, d.x), TAU) / TAU * 60) % 60
			var r0 := maxf(maxf(rr[s], rr[(s + 1) % 60]), rr[(s + 59) % 60])
			hd[side] = maxf(hd[side], (r0 - d.length()) / unit)
	return [deep, share, hd, hands]


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = String(a[0]).split(",")
	var states: Array = ["idle", "talk", "listen"]
	var off: Array = []
	for k in range(1, a.size()):
		var s := String(a[k])
		if s.begins_with("off="):
			off = s.substr(4).split(",")
		else:
			states = s.split(",")
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for k in off:
			(spec["rt3d"] as Dictionary).erase(k)
		if OS.get_environment("PEN_NOSHELL") != "":   # the hand's axis and fingertip only (as before 06.11, 15:56)
			(spec["rt3d"]["arm_body"] as Dictionary).erase("shell")
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			print("%s: not loaded" % id)
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		live.face(Vector2(0.4, 0.5), 0.55, true)
		var sk: Skeleton3D = live.view.skeleton
		var g := Grab.new()
		sk.add_child(g)
		var unit: float = 1.0
		if live.arm_body != null:
			unit = float(live.arm_body.get("_unit"))
		var prepped := prep(sk, live.view.meshes)
		for st in states:
			if String(st).begins_with("clip:"):
				live.set_state("idle")
				for i in 30:
					live.process(DT)
					await process_frame
				live.play_once(String(st).substr(5), true)
			else:
				live.set_state(String(st))
			var t := 0.0
			var worst := [0.0, 0.0]
			var wshare := [0.0, 0.0]
			var wt := [0.0, 0.0]
			var whull := [-1.0, -1.0]
			var bcw := [0.0, 0.0]
			var line := ""
			while t < 6.0:
				live.process(DT)
				await process_frame
				t += DT
				if int(round(t / DT)) % 15 == 0 and t > 0.3:
					var m := measure(prepped, g.out, unit)
					for side in 2:
						whull[side] = maxf(whull[side], m[2][side])
						if float(m[0][side]) > float(worst[side]):
							worst[side] = m[0][side]
							wt[side] = t
						wshare[side] = maxf(wshare[side], m[1][side])
					if live.arm_body != null and OS.get_environment("PEN_BC") != "":
						# BodyClear's own hull at every hand vertex (the skeleton put in the measured pose)
						for b in sk.get_bone_count():
							sk.set_bone_global_pose(b, g.out[b])
						var bcd := [-1.0, -1.0]
						for side in 2:
							for h in m[3][side]:
								bcd[side] = maxf(bcd[side], float(live.arm_body.depth_at(sk, h)[0]) / unit)
						var rl: Array = live.arm_body.get("_rot")
						line += " BC%.1f/%.1f sh%.1f/%.1f rot%.0f/%.0f" % [bcd[0] * 100.0, bcd[1] * 100.0,
								float(live.arm_body.get("shown_m")[0]) * 100.0, float(live.arm_body.get("shown_m")[1]) * 100.0,
								rad_to_deg((rl[0] as Vector3).length()), rad_to_deg((rl[1] as Vector3).length())]
					if live.arm_body != null:
						for side in 2:
							bcw[side] = maxf(bcw[side], float(live.arm_body.get("tip_m")[side]))
					line += " %.1f/%.1f|%.1f/%.1f" % [float(m[0][0]) * 100.0, float(m[0][1]) * 100.0, float(m[2][0]) * 100.0,
							float(m[2][1]) * 100.0]
			print("%s %s: hand behind clothes L %.1f cm (t %.2f, share %d%%)  R %.1f cm (t %.2f, share %d%%)" % [id, st,
					float(worst[0]) * 100.0, wt[0], int(wshare[0] * 100), float(worst[1]) * 100.0, wt[1],
					int(wshare[1] * 100)])
			print("   inside the posed silhouette (hull) L %.1f R %.1f cm; BodyClear's own fingertip L %.1f R %.1f cm" % [
					float(whull[0]) * 100.0, float(whull[1]) * 100.0, float(bcw[0]) * 100.0, float(bcw[1]) * 100.0])
			print("   per 0.25 s behind L/R | hull L/R cm:" + line)
		n.queue_free()
		await process_frame
	quit(0)
