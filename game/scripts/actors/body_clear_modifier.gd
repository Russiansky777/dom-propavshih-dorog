extends SkeletonModifier3D
## Hands kept out of the body (Director 01.11, line 10: «руки Пелагеи чуть проваливаются в тело»; line 52: «у Ульяны
## руки заходят в тело»): the Meshy clips were captured on another body, and the villagers' coats, aprons and skirts are
## wider than it — standing, a hanging hand sinks 2–7 cm into Pelageya's hip, Ulyana's listening hands 2 cm into her
## coat (tests/probe_villager_motion.gd). After the clips: per arm, the forearm's middle, the wrist and the middle of
## the hand are looked up in the body's hull (from the mesh's own bind pose: the vertices of the hips, the spine and
## the thighs, the farthest one per 6° around the middle of each centimetre of height, followed with the body bone that
## carries that height); one inside (with its own thickness) turns the upper arm about the shoulder away from the body
## just enough, at most `max_deg`. The turn follows softly (critically damped, `omega` /s): it never pops. Data
## rt3d.arm_body {max_deg, omega, hand_r_m, fore_r_m, hand_len}; NpcLive3D adds it after the other modifiers.

const SECTORS := 60
const BODY := ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "RightUpLeg"]

static var _hull_cache: Dictionary = {}   # model path → [bins, unit]

var enabled: bool = true           # off — the tests' self-check (the clip's hands as they were)
var max_deg: float = 15.0
var omega: float = 12.0
var hand_r: float = 0.02           # metres
var fore_r: float = 0.03
var hand_len: float = 0.45         # the hand's middle: this share of the forearm's length past the wrist
## Block 3 (Director 02.11, line 12: «пальцы Павла в теле»): the fingertips are checked too — the hand's farthest
## vertex from the wrist at rest (vertices whose strongest bone is the hand), carried by the hand bone; `tip_r_m` its
## thickness (data rt3d.arm_body.tip_r_m; 0 — off, as before).
var tip_r: float = 0.0
var _tip: Array = [Vector3.ZERO, Vector3.ZERO]   # per side: the fingertip in the hand bone's rest frame (skeleton units)
static var _tip_cache: Dictionary = {}
var tip_m: Array = [0.0, 0.0]      # this frame, after the turn: how deep each fingertip is (m, < 0 outside; tests)
var depth_m: Array = [0.0, 0.0]    # this frame, before the turn: how deep (with thickness) each arm went in (m; tests)
var shown_m: Array = [0.0, 0.0]    # after the turn (m; tests)

var _bins: Dictionary = {}         # int bin → [centre Vector2 (x, z), PackedFloat32Array radii, bone]
var _unit: float = 100.0           # skeleton units per metre
var _arm: Array = []               # per side [upper arm, forearm, hand]
var _rot: Array = [Vector3.ZERO, Vector3.ZERO]   # rotation vector shown (skeleton space) and its speed
var _rot_v: Array = [Vector3.ZERO, Vector3.ZERO]
var snap: bool = true


func setup(d: Dictionary, sk: Skeleton3D, meshes: Array, unit_per_m: float, cache_key: String) -> bool:
	max_deg = float(d.get("max_deg", max_deg))
	omega = float(d.get("omega", omega))
	hand_r = float(d.get("hand_r_m", hand_r))
	fore_r = float(d.get("fore_r_m", fore_r))
	hand_len = float(d.get("hand_len", hand_len))
	tip_r = float(d.get("tip_r_m", 0.0))
	_unit = unit_per_m
	for side in ["Left", "Right"]:
		var ids := [sk.find_bone(side + "Arm"), sk.find_bone(side + "ForeArm"), sk.find_bone(side + "Hand")]
		if ids.has(-1):
			return false
		_arm.append(ids)
	if _hull_cache.has(cache_key):
		_bins = _hull_cache[cache_key]
	else:
		_bins = _build_hull(sk, meshes)
		_hull_cache[cache_key] = _bins
		_tip_cache[cache_key] = _tip.duplicate()
	if _tip_cache.has(cache_key):
		_tip = (_tip_cache[cache_key] as Array).duplicate()
	return not _bins.is_empty()


## The hull per centimetre of height, skeleton space at rest: vertices whose strongest bone is a body bone.
func _build_hull(sk: Skeleton3D, meshes: Array) -> Dictionary:
	var body := {}
	for nm in BODY:
		var b := sk.find_bone(nm)
		if b >= 0:
			body[b] = true
	var hands := {sk.find_bone("LeftHand"): 0, sk.find_bone("RightHand"): 1}
	var tip_d := [0.0, 0.0]
	var acc := {}       # bin → [Array of Vector2, {bone: count}]
	var step := 0.01 * _unit
	for mi in meshes:
		var skin: Skin = (mi as MeshInstance3D).skin
		if skin == null:
			continue
		var binds: Array = []
		for j in skin.get_bind_count():
			var b := skin.get_bind_bone(j)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(j))
			binds.append([b, sk.get_bone_global_rest(b) * skin.get_bind_pose(j)])
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bi = arr[Mesh.ARRAY_BONES]
			var bw = arr[Mesh.ARRAY_WEIGHTS]
			if bi == null or bw == null or vs.is_empty():
				continue
			var per: int = bi.size() / vs.size()
			for k in vs.size():
				var best := -1
				var wb := 0.0
				for c in per:
					var w: float = bw[k * per + c]
					if w > wb:
						wb = w
						best = int(bi[k * per + c])
				if best < 0:
					continue
				var bone: int = binds[best][0]
				if hands.has(bone):
					var hp: Vector3 = (binds[best][1] as Transform3D) * vs[k]
					var hr := sk.get_bone_global_rest(bone)
					var side: int = hands[bone]
					var dist := hp.distance_to(hr.origin)
					if dist > float(tip_d[side]):
						tip_d[side] = dist
						_tip[side] = hr.affine_inverse() * hp
					continue
				if not body.has(bone):
					continue
				var p: Vector3 = (binds[best][1] as Transform3D) * vs[k]
				var key := int(floor(p.y / step))
				if not acc.has(key):
					acc[key] = [[], {}]
				(acc[key][0] as Array).append(Vector2(p.x, p.z))
				acc[key][1][bone] = int(acc[key][1].get(bone, 0)) + 1
	var out := {}
	for key in acc.keys():
		var pts: Array = acc[key][0]
		var c := Vector2.ZERO
		for q in pts:
			c += q
		c /= float(pts.size())
		var r := PackedFloat32Array()
		r.resize(SECTORS)
		for q in pts:
			var dd: Vector2 = q - c
			var s := int(fposmod(atan2(dd.y, dd.x), TAU) / TAU * SECTORS) % SECTORS
			r[s] = maxf(r[s], dd.length())
		var top := -1
		var n := -1
		for b in (acc[key][1] as Dictionary).keys():
			if int(acc[key][1][b]) > n:
				n = int(acc[key][1][b])
				top = int(b)
		out[key] = [c, r, top]
	return out


## How deep a skeleton-space point is inside the hull (skeleton units, < 0 outside, -INF off the body's heights) and the
## way out of it (skeleton space, unit, horizontal of the carrying bone).
func depth_at(sk: Skeleton3D, p: Vector3) -> Array:
	var step := 0.01 * _unit
	var hips := sk.find_bone("Hips")
	var q0: Vector3 = sk.get_bone_global_rest(hips) * (sk.get_bone_global_pose(hips).affine_inverse() * p)
	var key := int(floor(q0.y / step))
	var best := -INF
	var way := Vector3.ZERO
	for kk in [key - 1, key, key + 1]:
		if not _bins.has(kk):
			continue
		var e: Array = _bins[kk]
		var bone: int = e[2]
		var rest := sk.get_bone_global_rest(bone)
		var pose := sk.get_bone_global_pose(bone)
		var q: Vector3 = rest * (pose.affine_inverse() * p)
		var c: Vector2 = e[0]
		var r: PackedFloat32Array = e[1]
		var d := Vector2(q.x, q.z) - c
		var s := int(fposmod(atan2(d.y, d.x), TAU) / TAU * SECTORS) % SECTORS
		var rr := maxf(maxf(r[s], r[(s + 1) % SECTORS]), r[(s + SECTORS - 1) % SECTORS])
		if rr <= 0.0:
			continue
		var dep := rr - d.length()
		if dep > best:
			best = dep
			var out_rest := Vector3(d.x, 0.0, d.y).normalized() if d.length() > 1e-4 else Vector3(1, 0, 0)
			way = (pose.basis * (rest.basis.inverse() * out_rest)).normalized()
	return [best, way]


## The points of an arm checked: [position, thickness (skeleton units)].
func _points(sk: Skeleton3D, i: int) -> Array:
	var ids: Array = _arm[i]
	var el: Vector3 = sk.get_bone_global_pose(ids[1]).origin
	var wr: Vector3 = sk.get_bone_global_pose(ids[2]).origin
	var hm := wr + (wr - el) * hand_len
	var pts := [[el.lerp(wr, 0.5), fore_r * _unit], [wr, hand_r * _unit], [hm, hand_r * _unit]]
	if tip_r > 0.0 and (_tip[i] as Vector3) != Vector3.ZERO:
		pts.append([sk.get_bone_global_pose(ids[2]) * (_tip[i] as Vector3), tip_r * _unit])
	return pts


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _arm.size() < 2:
		return
	for i in 2:
		var ids: Array = _arm[i]
		var g: Transform3D = sk.get_bone_global_pose(ids[0])
		var r0 := _want(sk, i, g)
		var deepest: float = r0[1]
		var want: Vector3 = r0[0]
		# the turn is reckoned for the pose as it is; a hand in front of a thick coat (Mitya) is left 1–2 cm in after one
		# such turn — twice more from the turned arm, the turns added (then the arm is put back for the soft follower)
		for it in 2:
			if want.length() < 1e-6 or not enabled:
				break
			sk.set_bone_global_pose(ids[0], Transform3D(Basis(want.normalized(), want.length()) * g.basis, g.origin))
			var r1 := _want(sk, i, g)
			want += r1[0] as Vector3
			sk.set_bone_global_pose(ids[0], g)
		if want.length() > deg_to_rad(max_deg):
			want = want.normalized() * deg_to_rad(max_deg)
		depth_m[i] = maxf(deepest, 0.0) / _unit
		if snap or delta <= 0.0:
			_rot[i] = want
			_rot_v[i] = Vector3.ZERO
		else:
			var cur: Vector3 = _rot[i]
			var vel: Vector3 = _rot_v[i]
			for c in 3:
				var s := _spring(cur[c], vel[c], want[c], omega, delta)
				cur[c] = s.x
				vel[c] = s.y
			_rot[i] = cur
			_rot_v[i] = vel
		var rot: Vector3 = _rot[i]
		if rot.length() > 1e-5:
			var nb := Basis(rot.normalized(), rot.length()) * g.basis
			sk.set_bone_global_pose(ids[0], Transform3D(nb, g.origin))
		var after := -INF
		for pt in _points(sk, i):
			after = maxf(after, float(depth_at(sk, pt[0])[0]) + float(pt[1]))
		shown_m[i] = maxf(after, 0.0) / _unit
		if (_tip[i] as Vector3) != Vector3.ZERO:
			tip_m[i] = float(depth_at(sk, sk.get_bone_global_pose(ids[2]) * (_tip[i] as Vector3))[0]) / _unit
	snap = false


## The turn (rotation vector, skeleton space) that takes this arm's deepest point out of the body, and how deep the
## deepest point is (with its thickness, skeleton units).
func _want(sk: Skeleton3D, i: int, g: Transform3D) -> Array:
	var want := Vector3.ZERO
	var deepest := -INF
	var sh: Vector3 = sk.get_bone_global_pose(int(_arm[i][0])).origin
	for pt in _points(sk, i):
		var p: Vector3 = pt[0]
		var da := depth_at(sk, p)
		var dep: float = float(da[0]) + float(pt[1])
		deepest = maxf(deepest, dep)
		if dep <= 0.0 or not enabled:
			continue
		var arm_v := p - sh
		var axis := arm_v.cross(da[1] as Vector3)
		if axis.length() < 1e-6 or arm_v.length() < 1e-4:
			continue
		var rv := axis.normalized() * minf(dep / arm_v.length(), deg_to_rad(max_deg))
		if rv.length() > want.length():
			want = rv
	return [want, deepest]


static func _spring(x: float, v: float, target: float, om: float, dt: float) -> Vector2:
	var y := x - target
	var j := v + om * y
	var e := exp(-om * dt)
	return Vector2(target + (y + j * dt) * e, (v - om * j * dt) * e)
