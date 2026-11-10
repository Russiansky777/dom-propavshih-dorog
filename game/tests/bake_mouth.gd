extends SceneTree
## Where each villager's lips part — measured once from the model (Director 09.11, 21:56: «рот сделан плохо»; 22:18:
## «рты открывающиеся и нормальные»). The models are one closed surface: the lower lip and the chin hang on the bone Jaw,
## the upper lip on the head, and the triangles between them (one corner on the jaw, another not) are the lip line —
## turning the jaw tore the surface there into a jagged slit showing whatever lay behind. The mouth is painted instead
## (shaders/actor_3d.gdshader, JawModifier): a dark opening on the face along that line, opening with the voice.
## This tool finds the line (see `measure`): its middle, its width across, its shape, the body's own axes — in the head
## bone's rest frame.
##   godot --headless --path game -s res://tests/bake_mouth.gd -- <id,id|all> [check]
## Writes res://data/actors_rest/mouth_<id>.json {at: [x, y, z] — the middle of the lip line, right, up, fwd (all in
## the head bone's frame, model units), half_w — to a corner of the mouth, sag — how much higher the corners are than
## the middle, back — how far behind it, unit_per_m}. `check` — compares with the files, exit 1 on a difference.

const ALL := ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]
const ArmRest := preload("res://scripts/actors/arm_rest.gd")


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
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


## The lip line of a built figure: {} when the model has no jaw or no parting.
## The lips are cut apart (the lower lip's edge on the jaw, the upper's on the head, lying on each other at rest): the
## pairs «a jaw vertex and a head vertex within 1.2 mm» at the front of the face are the cut; the lip line is the cut
## with the most points in a band 6 mm high, one run across; a parabola through it is its shape.
static func measure(sk: Skeleton3D, meshes: Array) -> Dictionary:
	var jaw := sk.find_bone("Jaw")
	var head := sk.find_bone("Head")
	if jaw < 0 or head < 0:
		return {}
	# the model's own axes in skeleton space: up is Y; the left arm tells which way she faces (left × up = forward)
	var la := sk.find_bone("LeftArm")
	var up := Vector3.UP
	var out_l := Vector3.RIGHT * (1.0 if la < 0 or sk.get_bone_global_rest(la).origin.x >= 0.0 else -1.0)
	var right := -out_l
	var fwd := out_l.cross(up)
	var head_rest := sk.get_bone_global_rest(head)
	var hp: Vector3 = head_rest.origin
	var unit_per_m: float = 1.0 / maxf(sk.global_transform.basis.get_scale().y, 1e-6)
	var mm := 0.001 * unit_per_m
	var jv: Array = []        # vertices near the face front: on the jaw / not
	var nv: Array = []
	var tris := 0
	for mi in meshes:
		var m := mi as MeshInstance3D
		var skin: Skin = m.skin
		if skin == null:
			continue
		var jb := -1
		var mats: Array = []      # bind j → the bone's rest × the bind pose: a vertex of the mesh → skeleton space at rest
		for j in skin.get_bind_count():
			var b := skin.get_bind_bone(j)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(j))
			if b == jaw:
				jb = j
			mats.append((sk.get_bone_global_rest(b) * skin.get_bind_pose(j)) if b >= 0 else Transform3D.IDENTITY)
		if jb < 0:
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bi = arr[Mesh.ARRAY_BONES]
			var bw = arr[Mesh.ARRAY_WEIGHTS]
			var idx = arr[Mesh.ARRAY_INDEX]
			if bi == null or bw == null or vs.is_empty() or idx == null:
				continue
			var per: int = bi.size() / vs.size()
			var jw := PackedFloat32Array()
			jw.resize(vs.size())
			var rest: Array = []
			rest.resize(vs.size())
			for k in vs.size():
				var w := 0.0
				for c in per:
					if int(bi[k * per + c]) == jb:
						w += float(bw[k * per + c])
				jw[k] = w
			var rest_of := func(k2: int) -> Vector3:
				if rest[k2] != null:
					return rest[k2]
				var p := Vector3.ZERO
				for c in per:
					var w2: float = bw[k2 * per + c]
					if w2 > 0.0:
						p += ((mats[int(bi[k2 * per + c])] as Transform3D) * vs[k2]) * w2
				rest[k2] = p
				return p
			# the vertices of the face's front: on the jaw / on the head (within 45 mm of the middle across, no further
			# than 40 mm behind the foremost jaw vertex — the chin and the lips, not the ears or a scarf's knot)
			var f_max := -INF
			var cand: Array = []
			for k in vs.size():
				if jw[k] <= 0.0 and not _on_head(bi, bw, per, k, skin, sk, head):
					continue
				var p: Vector3 = rest_of.call(k) - hp
				var v := Vector3(p.dot(right), p.dot(up), p.dot(fwd))
				if absf(v.x) > 45.0 * mm:
					continue
				cand.append([v, jw[k] >= 0.5])
				if jw[k] >= 0.5:
					f_max = maxf(f_max, v.z)
			for c3 in cand:
				if (c3[0] as Vector3).z < f_max - 40.0 * mm:
					continue
				if c3[1]:
					jv.append(c3[0])
				else:
					nv.append(c3[0])
			# a jaw vertex with a head vertex lying on it (≤ 1.2 mm): a point of a cut between the two
			var pairs: Array = []
			var lim := pow(1.2 * mm, 2.0)
			for a3 in jv:
				var best := INF
				var bv := Vector3.ZERO
				for b3 in nv:
					var d2 := (a3 as Vector3).distance_squared_to(b3)
					if d2 < best:
						best = d2
						bv = b3
				if best < lim:
					pairs.append(((a3 as Vector3) + bv) * 0.5)
			if pairs.size() < 6:
				# no cut in the model (Mitya: one surface under the beard): the top of what hangs on the jaw at the
				# middle of the face's front is the lower lip's upper edge — a first guess, set right by hand in the
				# actor's data (rt3d.jaw.shift_mm) against the picture of the lips
				var top := Vector3(0, -INF, 0)
				for a3 in jv:
					if absf((a3 as Vector3).x) < 4.0 * mm and (a3 as Vector3).z > f_max - 12.0 * mm and (a3 as Vector3).y > top.y:
						top = a3
				if top.y == -INF:
					continue
				var mid0: Vector3 = hp + up * top.y + fwd * top.z
				var inv0 := head_rest.affine_inverse()
				var r30 := func(v: Vector3) -> Array: return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
				return {"at": r30.call(inv0 * mid0), "right": r30.call(inv0.basis * right), "up": r30.call(inv0.basis * up), "fwd": r30.call(inv0.basis * fwd),
					"half_w": snappedf(17.5 * mm, 0.0001), "sag": 0.0, "back": snappedf(7.0 * mm, 0.0001), "unit_per_m": snappedf(unit_per_m, 0.01),
					"tris": 0, "line_pts": 0, "from": "jaw_top"}
			# the lip line is the cut with the most points in a band 6 mm high
			var best_n := 0
			var band_u := 0.0
			for q3 in pairs:
				var n2 := 0
				for q4 in pairs:
					if absf((q4 as Vector3).y - (q3 as Vector3).y) <= 3.0 * mm:
						n2 += 1
				if n2 > best_n:
					best_n = n2
					band_u = (q3 as Vector3).y
			var line: Array = []
			for q3 in pairs:
				if absf((q3 as Vector3).y - band_u) <= 3.0 * mm:
					line.append(q3)
			line.sort_custom(func(p1, p2): return (p1 as Vector3).x < (p2 as Vector3).x)
			# one run across: from the point nearest the middle outwards, until a gap wider than 9 mm
			var mid_i := 0
			for i2 in line.size():
				if absf((line[i2] as Vector3).x) < absf((line[mid_i] as Vector3).x):
					mid_i = i2
			var i_lo := mid_i
			var i_hi := mid_i
			while i_lo > 0 and (line[i_lo] as Vector3).x - (line[i_lo - 1] as Vector3).x <= 9.0 * mm:
				i_lo -= 1
			while i_hi < line.size() - 1 and (line[i_hi + 1] as Vector3).x - (line[i_hi] as Vector3).x <= 9.0 * mm:
				i_hi += 1
			line = line.slice(i_lo, i_hi + 1)
			if line.size() < 6:
				continue
			var cl: Vector3 = line[0]
			var cr: Vector3 = line[line.size() - 1]
			tris = pairs.size()
			# its shape: up = a + c·x² about the middle between the corners (least squares), forward the same
			var xc := (cl.x + cr.x) * 0.5
			var hw := (cr.x - cl.x) * 0.5
			var s0 := 0.0; var s2 := 0.0; var s4 := 0.0; var y0 := 0.0; var y2 := 0.0; var z0 := 0.0; var z2 := 0.0
			for q3 in line:
				var x := ((q3 as Vector3).x - xc) / hw
				s0 += 1.0; s2 += x * x; s4 += pow(x, 4.0)
				y0 += (q3 as Vector3).y; y2 += (q3 as Vector3).y * x * x
				z0 += (q3 as Vector3).z; z2 += (q3 as Vector3).z * x * x
			var det := s0 * s4 - s2 * s2
			var ya := (y0 * s4 - y2 * s2) / det if absf(det) > 1e-9 else y0 / s0
			var yc2 := (s0 * y2 - s2 * y0) / det if absf(det) > 1e-9 else 0.0
			var za := (z0 * s4 - z2 * s2) / det if absf(det) > 1e-9 else z0 / s0
			var zc2 := (s0 * z2 - s2 * z0) / det if absf(det) > 1e-9 else 0.0
			if OS.get_environment("MOUTH_DUMP") != "":
				var txt := ""
				for q3 in line:
					txt += " (%.1f %.1f %.1f)" % [(q3 as Vector3).x / mm, (q3 as Vector3).y / mm, (q3 as Vector3).z / mm]
				print("  line right/up/fwd mm:", txt)
			var mid: Vector3 = hp + right * xc + up * ya + fwd * za
			var inv := head_rest.affine_inverse()
			var r3 := func(v: Vector3) -> Array: return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
			return {"at": r3.call(inv * mid), "right": r3.call(inv.basis * right), "up": r3.call(inv.basis * up), "fwd": r3.call(inv.basis * fwd),
				"half_w": snappedf(hw, 0.0001), "sag": snappedf(yc2, 0.0001), "back": snappedf(-zc2, 0.0001), "unit_per_m": snappedf(unit_per_m, 0.01),
				"tris": tris, "line_pts": line.size()}
	return {}


static func _on_head(bi, bw, per: int, k: int, skin: Skin, sk: Skeleton3D, head: int) -> bool:
	for c in per:
		if float(bw[k * per + c]) > 0.3:
			var b := skin.get_bind_bone(int(bi[k * per + c]))
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(int(bi[k * per + c])))
			if b == head:
				return true
	return false


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = ALL if a.is_empty() or a[0] == "all" else Array(String(a[0]).split(","))
	var check := a.has("check")
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var bad := 0
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			print("%s: not loaded" % id)
			bad += 1
			n.queue_free()
			continue
		await process_frame
		var d := measure(live.view.skeleton, live.view.meshes)
		var path := "res://data/actors_rest/mouth_%s.json" % id
		if d.is_empty():
			d = {"none": true}   # no parting in the model (Mitya: the beard covers it) — no painted mouth
		if check:
			var have = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			var same: bool = have is Dictionary and JSON.stringify(have) == JSON.stringify(JSON.parse_string(JSON.stringify(d)))
			print("%s: %s" % [id, "matches" if same else "DIFFERS from %s" % path])
			bad += 0 if same else 1
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify(d, "  ") + "\n")
			f.close()
			if d.has("none"):
				print("%s: no parting in the model — no painted mouth" % id)
				n.queue_free()
				await process_frame
				continue
			var k := 1000.0 / float(d["unit_per_m"])
			print("%s: half width %.1f mm, corners %.1f mm %s the middle and %.1f mm behind it, %d points on the line, at %s" % [id, float(d["half_w"]) * k, absf(float(d["sag"])) * k, "above" if float(d["sag"]) > 0.0 else "below", float(d["back"]) * k, d["line_pts"], str(d["at"])])
		n.queue_free()
		await process_frame
	quit(1 if bad > 0 else 0)
