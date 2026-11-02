extends SceneTree
## The skirt's cloth between the hem and the boots, as skinned (Director 01.11, line 3: «при шагании ноги выпирают будто
## штаны из-под юбки»): the triangles of the mesh between `lo` and `hi` metres up, skinned on the CPU per sampled frame of a
## walk on the spot and a stop — how far their edges stretch against the rest pose. A strip bound to the shins pulled
## out between the hem (on the skirt's bones) and the boot is a run of long thin triangles: stretched ×1.5 and more.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_skirt_stretch.gd [-- res://scene.glb] [nodrive]

var v: Actor3D
var _want := false
var _bd: Dictionary = {}
var _rest: Dictionary = {}
var _got: Array = []


func _on_upd() -> void:
	if _want:
		_want = false
		if _rest.is_empty():
			_rest = skinned(v, _bd, false)   # the reference: standing (the bind pose's skirt and legs stand otherwise)
			_got = [0, 0, 1.0]
		else:
			_got = stretch(_bd, _rest, skinned(v, _bd, false))


func _initialize() -> void:
	_run()


## The band's triangles (vertex index triples) and the per-vertex skinning data, from the biggest mesh of the figure.
static func band(av: Actor3D, lo: float, hi: float) -> Dictionary:
	var mi: MeshInstance3D = null
	for m in av.meshes:
		if mi == null or (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			mi = m
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones = arr[Mesh.ARRAY_BONES]
	var wts = arr[Mesh.ARRAY_WEIGHTS]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := int(bones.size() / verts.size())
	var sk := av.skeleton
	var bind_bone: Array = []
	for j in mi.skin.get_bind_count():
		var b := mi.skin.get_bind_bone(j)
		if b < 0:
			b = sk.find_bone(mi.skin.get_bind_name(j))
		bind_bone.append(b)
	var used := {}
	var tris := PackedInt32Array()
	for t in range(0, ind.size(), 3):
		var a := ind[t]
		var b := ind[t + 1]
		var c := ind[t + 2]
		var ya := verts[a].y
		if ya < lo or ya > hi or verts[b].y < lo or verts[b].y > hi or verts[c].y < lo or verts[c].y > hi:
			continue
		tris.append_array([a, b, c])
		used[a] = true
		used[b] = true
		used[c] = true
	var vid := PackedInt32Array(used.keys())
	var vb: Array = []
	var vw: Array = []
	for i in vid:
		var bb := PackedInt32Array()
		var ww := PackedFloat32Array()
		for k in per:
			var w := float(wts[i * per + k])
			if w > 0.0:
				bb.append(int(bones[i * per + k]))
				ww.append(w)
		vb.append(bb)
		vw.append(ww)
	# edges shorter than 2 mm (in skeleton units) are left out: a sliver's ratio means nothing
	var u := 1.0 / maxf(av._skel_to_model().basis.get_scale().x, 1e-6)
	return {"min_edge": 0.002 * u, "mi": mi, "verts": verts, "tris": tris, "vid": vid, "vb": vb, "vw": vw, "bind_bone": bind_bone}


static func skinned(av: Actor3D, bd: Dictionary, rest: bool) -> Dictionary:
	var sk := av.skeleton
	var mi: MeshInstance3D = bd["mi"]
	var mats: Array = []
	for j in mi.skin.get_bind_count():
		var b: int = bd["bind_bone"][j]
		var g: Transform3D = sk.get_bone_global_rest(b) if rest else sk.get_bone_global_pose(b)
		mats.append(g * mi.skin.get_bind_pose(j))
	var out := {}
	var verts: PackedVector3Array = bd["verts"]
	var vid: PackedInt32Array = bd["vid"]
	for n in vid.size():
		var i := vid[n]
		var p := Vector3.ZERO
		var bb: PackedInt32Array = bd["vb"][n]
		var ww: PackedFloat32Array = bd["vw"][n]
		for k in bb.size():
			p += ww[k] * ((mats[bb[k]] as Transform3D) * verts[i])
		out[i] = p
	return out


## [triangles stretched over ×1.5, over ×2, the largest stretch] of the band in this pose against `rest` (standing).
static func stretch(bd: Dictionary, rest: Dictionary, now: Dictionary) -> Array:
	var tris: PackedInt32Array = bd["tris"]
	var min_edge: float = bd.get("min_edge", 0.0)
	var n15 := 0
	var n2 := 0
	var mx := 1.0
	for t in range(0, tris.size(), 3):
		var r := 0.0
		for e in 3:
			var a := tris[t + e]
			var b := tris[t + (e + 1) % 3]
			var l0 := (rest[a] as Vector3).distance_to(rest[b])
			if l0 > min_edge:
				r = maxf(r, (now[a] as Vector3).distance_to(now[b]) / l0)
		if r > 1.5:
			n15 += 1
		if r > 2.0:
			n2 += 1
		mx = maxf(mx, r)
	return [n15, n2, mx]


func _run() -> void:
	await process_frame
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var nodrive := false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("res://"):
			spec["rt3d"]["scene"] = a
		elif a == "nodrive":
			nodrive = true
	v = Actor3D.new()
	root.add_child(v)
	if not v.setup(spec):
		push_error(v.load_error)
		quit(1)
		return
	if v.skirt_drive != null and nodrive:
		v.skirt_drive.on = false
	var bd := band(v, 0.15, 0.5)
	_bd = bd
	_rest = {}
	v.skeleton.skeleton_updated.connect(_on_upd)
	print("band 0.15–0.50 m: %d triangles, %d vertices" % [(bd["tris"] as PackedInt32Array).size() / 3, (bd["vid"] as PackedInt32Array).size()])
	var ph := 0.0
	var d := 1.0 / 60.0
	var walk := [0, 0, 1.0]
	var stop := [0, 0, 1.0]
	var sums := [0.0, 0.0, 0]
	var walk_frames := 0
	for i in 300:
		var w := 0.0
		if i >= 20 and i < 200:
			w = clampf((i - 20) / 20.0, 0.0, 1.0)
		elif i >= 200 and i < 224:
			w = 1.0 - (i - 200) / 24.0
		if w > 0.0:
			ph += d * (0.55 + 0.45 * w) / maxf(v.walk_len, 0.01)
		v.pose(d, fposmod(ph, 1.0), w, 0.0)
		_got = []
		_want = (i % 4 == 0 and (i >= 60 or OS.get_environment("SDEBUG") != "")) or i == 12
		await process_frame
		if _got.is_empty() or i <= 12:
			continue
		var s := _got
		if OS.get_environment("SDEBUG") != "":
			print("  f%d w %.2f: %s" % [i, w, str(s)])
		var acc: Array = walk if i < 200 else stop
		if i < 200:
			sums[0] += float(s[0])
			sums[1] += float(s[1])
			sums[2] += 1
		acc[0] = maxi(int(acc[0]), int(s[0]))
		acc[1] = maxi(int(acc[1]), int(s[1]))
		acc[2] = maxf(float(acc[2]), float(s[2]))
	print("walking: on average %.0f triangles stretched ×1.5+ (%.0f ×2+)" % [sums[0] / maxf(sums[2], 1), sums[1] / maxf(sums[2], 1)])
	print("walking: at most %d triangles stretched ×1.5+ (%d ×2+), the largest ×%.2f; stopping and after: %d (%d), ×%.2f" % [walk[0], walk[1], walk[2], stop[0], stop[1], stop[2]])
	quit(0)
