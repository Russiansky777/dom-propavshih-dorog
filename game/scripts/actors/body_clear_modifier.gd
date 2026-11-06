extends SkeletonModifier3D
## Hands kept out of the body (Director 01.11, line 10: «руки Пелагеи чуть проваливаются в тело»; line 52: «у Ульяны
## руки заходят в тело»): the Meshy clips were captured on another body, and the villagers' coats, aprons and skirts are
## wider than it — standing, a hanging hand sinks 2–7 cm into Pelageya's hip, Ulyana's listening hands 2 cm into her
## coat (tests/probe_villager_motion.gd). After the clips: per arm, the forearm's middle, the wrist and the middle of
## the hand are looked up in the body's hull (from the mesh's own bind pose: the vertices of the hips, the spine and
## the thighs, the farthest one per 6° around the middle of each centimetre of height, followed with the body bone
## that carries most of that height; a profile per bone was tried 06.11 and pushed the arms the wrong way); one inside
## (with its own thickness) turns the upper arm about the shoulder away from the body just enough, at most `max_deg`.
## The turn follows softly (critically damped, `omega` /s): it never pops. Data rt3d.arm_body {max_deg, omega, hand_r_m,
## fore_r_m, hand_len, tip_r_m, shell, shell_r_m}; NpcLive3D adds it after the other modifiers.

const SECTORS := 60
const BODY := ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "RightUpLeg"]

static var _hull_cache: Dictionary = {}   # model path → [bins, unit]

var enabled: bool = true           # off — the tests' self-check (the clip's hands as they were)
var max_deg: float = 15.0
var omega: float = 12.0
var omega_back: float = 3.0
var catch_m: float = 0.005         # deeper than this after the follower — straight to the needed turn
var hand_r: float = 0.02           # metres
var fore_r: float = 0.03
var hand_len: float = 0.45         # the hand's middle: this share of the forearm's length past the wrist
## Block 3 (Director 02.11, line 12: «пальцы Павла в теле»): the fingertips are checked too — the hand's farthest
## vertex from the wrist at rest (vertices whose strongest bone is the hand), carried by the hand bone; `tip_r_m` its
## thickness (data rt3d.arm_body.tip_r_m; 0 — off, as before).
var tip_r: float = 0.0
var _tip: Array = [Vector3.ZERO, Vector3.ZERO]   # per side: the fingertip in the hand bone's rest frame (skeleton units)
static var _tip_cache: Dictionary = {}
## Director 06.11, 15:56 («Павел слушает… руки въезжают в тело»): the centre line and the fingertip are not the
## whole hand — a hanging hand turns its palm and thumb to the thigh, and they went 5 cm into Pavel's apron while every
## checked point was outside (tests/probe_hand_penetration.gd). `shell` points spread over the hand's own surface
## (farthest-point sampled from its vertices at rest, carried by the hand bone; data rt3d.arm_body.shell, 0 — off), each
## with `shell_r_m` thickness.
var shell_n: int = 0
var no_back: bool = false
var forward_only: bool = false     # data arm_body.forward_only: out of the clothes forward only (see _want)
## How much of the turn is shown (NpcLive3D: data arm_body.stance_free — the turn only as much as talk or an action is
## shown; standing, the arms hang as the clip has them — Director 06.11, 23:0x, «Г: руки как в клипе»: pushed out of
## the apron the arms stood off the body like a wrestler's)
var strength: float = 1.0
var legacy_zero_dt: bool = false   # tests only: the follower skipped on passes with no time step, as before 19:27          # data arm_body.no_back: never take the arm out backwards (see _want)
var _hips: int = -1
var shell_r: float = 0.015
var _shell: Array = [[], []]       # per side: [[2 (the hand), point in the hand bone's rest frame], …]
static var _shell_cache: Dictionary = {}   # model → per side the hand's vertices in the hand bone's rest frame
var _surf: Array = [[], []]
var tip_m: Array = [0.0, 0.0]      # this frame, after the turn: how deep each fingertip is (m, < 0 outside; tests)
var depth_m: Array = [0.0, 0.0]    # this frame, before the turn: how deep (with thickness) each arm went in (m; tests)
var shown_m: Array = [0.0, 0.0]    # after the turn (m; tests)

var _bins: Dictionary = {}         # int bin → [[centre Vector2 (x, z), PackedFloat32Array radii, carrying bone]]
var _unit: float = 100.0           # skeleton units per metre
var _arm: Array = []               # per side [upper arm, forearm, hand]
var _rot: Array = [Vector3.ZERO, Vector3.ZERO]   # rotation vector shown (skeleton space) and its speed
var _rot_v: Array = [Vector3.ZERO, Vector3.ZERO]
var snap: bool = true


func setup(d: Dictionary, sk: Skeleton3D, meshes: Array, unit_per_m: float, cache_key: String) -> bool:
	max_deg = float(d.get("max_deg", max_deg))
	omega = float(d.get("omega", omega))
	omega_back = float(d.get("omega_back", omega_back))
	hand_r = float(d.get("hand_r_m", hand_r))
	fore_r = float(d.get("fore_r_m", fore_r))
	hand_len = float(d.get("hand_len", hand_len))
	tip_r = float(d.get("tip_r_m", 0.0))
	shell_n = int(d.get("shell", 0))
	no_back = bool(d.get("no_back", false))
	forward_only = bool(d.get("forward_only", false))
	_bake_cfg = d.get("bake", null)
	shell_r = float(d.get("shell_r_m", shell_r))
	_unit = unit_per_m
	_hips = sk.find_bone("Hips")
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
		_shell_cache[cache_key] = _surf
	if _tip_cache.has(cache_key):
		_tip = (_tip_cache[cache_key] as Array).duplicate()
	# the hand's points are spread per figure (its own data `shell`: a test may switch them off), from the model's cached
	# hand vertices
	_shell = [[], []]
	var surf: Array = _shell_cache.get(cache_key, [[], []])
	var sk_n := "%s#%d" % [cache_key, shell_n]
	if _shell_cache.has(sk_n):
		_shell = (_shell_cache[sk_n] as Array).duplicate(true)
	elif shell_n > 0:
		for side in 2:
			# the hand only: points on the sleeve (tried) found the elbow against the back of the waistcoat and swung the
			# whole arm backwards
			for q in _farthest(surf[side], shell_n):
				_shell[side].append([2, q])
		_shell_cache[sk_n] = _shell.duplicate(true)
	return not _bins.is_empty()


## The hull per centimetre of height, skeleton space at rest: vertices whose strongest bone is a body bone.
func _build_hull(sk: Skeleton3D, meshes: Array) -> Dictionary:
	var body := {}
	for nm in BODY:
		var b := sk.find_bone(nm)
		if b >= 0:
			body[b] = true
	var hands := {sk.find_bone("LeftHand"): 0, sk.find_bone("RightHand"): 1}
	var surf := [[[], []], [[], []]]   # side → [unused, hand points in the hand bone's rest frame]
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
					surf[side][1].append(hr.affine_inverse() * hp)
					continue
				if not body.has(bone):
					continue
				var p: Vector3 = (binds[best][1] as Transform3D) * vs[k]
				var key := int(floor(p.y / step))
				if not acc.has(key):
					acc[key] = [[], {}]
				(acc[key][0] as Array).append(Vector2(p.x, p.z))
				acc[key][1][bone] = int(acc[key][1].get(bone, 0)) + 1
	_surf = [surf[0][1], surf[1][1]]
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
		out[key] = [[c, r, top]]
	return out


## The clearing baked into the stance clips (Director 06.11, 20:21, a second look at the video: «кисть Павла сначала
## опускается к фартуку, затем уходит обратно наружу и вверх»): done live, the turn always came after the clip had
## taken the hand in — 0.3 s later, 6 cm out again (tests/probe_hand_path.gd). Now every key of the upper arm in these
## clips already holds the turn it needs: the need reckoned on the clip's own pose every `every` keys, held for ±`hold`
## s and smoothed (σ `sigma` s) so it comes before the hand reaches the clothes and leaves after; the live turn is left
## only what the blending of clips adds. Data rt3d.arm_body.bake {every, hold, sigma}; each clip of the figure's own copy once.
func bake(anim: AnimationPlayer, names: Array) -> void:
	var cfg = _bake_cfg
	if cfg == null or anim == null:
		return
	var sk := get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	if sk == null or _arm.size() < 2:
		return
	var every := maxi(1, int(cfg.get("every", 2)))
	var hold := float(cfg.get("hold", 0.25))
	var sigma := float(cfg.get("sigma", 0.12))
	var keep_poses: Array = []
	for b in sk.get_bone_count():
		keep_poses.append([sk.get_bone_pose_position(b), sk.get_bone_pose_rotation(b)])
	var was := enabled
	enabled = true
	for nm in names:
		var a := anim.get_animation(nm)
		# the figure's own copy of the clip (Actor3D copies the model's libraries per figure): changed in place, once
		if a == null or a.has_meta("arms_cleared"):
			continue
		a.set_meta("arms_cleared", true)
		var tr := {}
		for i in a.get_track_count():
			var bn := String(a.track_get_path(i).get_concatenated_subnames())
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				tr[bn] = i
		for side in 2:
			var ids: Array = _arm[side]
			var arm_name := sk.get_bone_name(ids[0])
			if not tr.has(arm_name):
				continue
			var ti: int = tr[arm_name]
			var n := a.track_get_key_count(ti)
			if n < 2:
				continue
			var times := PackedFloat32Array()
			times.resize(n)
			for k in n:
				times[k] = a.track_get_key_time(ti, k)
			# the need (rotation vector at the shoulder, skeleton space) on the clip's own pose
			var need: Array = []
			need.resize(n)
			var last := Vector3.ZERO
			for k in n:
				if k % every != 0 and k != n - 1:
					need[k] = null
					continue
				_pose_clip(sk, a, tr, times[k])
				var g := sk.get_bone_global_pose(ids[0])
				var r0 := _want(sk, side, g)
				var want: Vector3 = r0[0]
				for it in 2:
					if want.length() < 1e-6:
						break
					sk.set_bone_global_pose(ids[0], Transform3D(Basis(want.normalized(), want.length()) * g.basis, g.origin))
					want += _want(sk, side, g)[0] as Vector3
					sk.set_bone_global_pose(ids[0], g)
				if want.length() > deg_to_rad(max_deg):
					want = want.normalized() * deg_to_rad(max_deg)
				need[k] = want
				last = want
			# the keys between: interpolated
			var prev_k := 0
			for k in n:
				if need[k] != null:
					if k - prev_k > 1:
						for j in range(prev_k + 1, k):
							need[j] = (need[prev_k] as Vector3).lerp(need[k], float(j - prev_k) / float(k - prev_k))
					prev_k = k
			# held (the largest size within ±hold, its own direction), then smoothed: the turn starts before the
			# hand would reach the clothes and stays a little after
			var held: Array = []
			held.resize(n)
			for k in n:
				var best: Vector3 = need[k]
				var j := k
				while j > 0 and times[k] - times[j - 1] <= hold:
					j -= 1
				while j < n and times[j] - times[k] <= hold:
					if (need[j] as Vector3).length() > best.length():
						best = need[j]
					j += 1
				held[k] = best
			for k in n:
				var acc := Vector3.ZERO
				var wsum := 0.0
				var j := k
				while j > 0 and times[k] - times[j - 1] <= 3.0 * sigma:
					j -= 1
				while j < n and times[j] - times[k] <= 3.0 * sigma:
					var w := exp(-0.5 * pow((times[j] - times[k]) / maxf(sigma, 1e-4), 2.0))
					acc += (held[j] as Vector3) * w
					wsum += w
					j += 1
				var rv: Vector3 = acc / maxf(wsum, 1e-6)
				if rv.length() < 1e-5:
					continue
				# into the key: the arm's parent at that time, the turn in skeleton space → the local rotation
				_pose_clip(sk, a, tr, times[k])
				var par := sk.get_bone_parent(ids[0])
				var pq: Quaternion = sk.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
				var turn := Quaternion(rv.normalized(), rv.length())
				var ql: Quaternion = a.track_get_key_value(ti, k)
				a.track_set_key_value(ti, k, (pq.inverse() * turn * pq * ql).normalized())
	enabled = was
	for b in sk.get_bone_count():
		sk.set_bone_pose_position(b, keep_poses[b][0])
		sk.set_bone_pose_rotation(b, keep_poses[b][1])


var _bake_cfg = null
## The skeleton put in the clip's own pose at time t (its tracks; the bones it has none for at rest).
static func _pose_clip(sk: Skeleton3D, a: Animation, tr: Dictionary, t: float) -> void:
	for b in sk.get_bone_count():
		var bn := sk.get_bone_name(b)
		if tr.has(bn):
			sk.set_bone_pose_rotation(b, a.rotation_track_interpolate(tr[bn], t))
		else:
			sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion())


## n points spread over pts (farthest-point sampling, from the first).
static func _farthest(pts: Array, n: int) -> Array:
	var out: Array = []
	if pts.is_empty() or n <= 0:
		return out
	var dist := PackedFloat32Array()
	dist.resize(pts.size())
	dist.fill(INF)
	var cur := 0
	for i in mini(n, pts.size()):
		out.append(pts[cur])
		var far := -1.0
		var nxt := 0
		for k in pts.size():
			var d: float = (pts[k] as Vector3).distance_squared_to(pts[cur])
			if d < dist[k]:
				dist[k] = d
			if dist[k] > far:
				far = dist[k]
				nxt = k
		cur = nxt
	return out


## How deep a skeleton-space point is inside the hull (skeleton units, < 0 outside, -INF off the body's heights) and the
## way out of it (skeleton space, unit, horizontal of the carrying bone).
func depth_at(sk: Skeleton3D, p: Vector3) -> Array:
	# Director 06.11, 19:27 («руки дергаются как сумасшедшие, меняя положение туда и назад»): the depth was a step
	# function — the radius of a 6° sector (the most of three), the deepest of three 1-cm slices — and the turn jumped
	# with it, back and forth, 20–40 times in 6 s (tests/probe_bc_trace.gd). Now it is continuous: the radius
	# interpolated between sectors, the slices blended by height.
	var step := 0.01 * _unit
	var hips := sk.find_bone("Hips")
	var q0: Vector3 = sk.get_bone_global_rest(hips) * (sk.get_bone_global_pose(hips).affine_inverse() * p)
	var fy := q0.y / step - 0.5
	var key := int(floor(fy))
	var fr := fy - float(key)   # 0 at the middle of slice `key`, 1 at the middle of slice key + 1
	var dk := {}
	for kk in [key - 1, key, key + 1, key + 2]:
		dk[kk] = _slice_depth(sk, p, kk)
	var lo: Array = _deeper(dk[key - 1], dk[key])
	var mid: Array = _deeper(dk[key], dk[key + 1])
	var hi: Array = _deeper(dk[key + 1], dk[key + 2])
	# the deeper of each slice with its neighbour, blended between the two nearest slices
	var aa: Array = _deeper(lo, mid)
	var bb: Array = _deeper(mid, hi)
	if float(aa[0]) == -INF or float(bb[0]) == -INF:
		return aa if float(bb[0]) == -INF else bb
	var w: Vector3 = (aa[1] as Vector3).lerp(bb[1] as Vector3, fr)
	return [lerpf(float(aa[0]), float(bb[0]), fr), w.normalized() if w.length() > 1e-6 else aa[1]]


static func _deeper(x: Array, y: Array) -> Array:
	return x if float(x[0]) >= float(y[0]) else y


## Depth in one slice, the radius interpolated between the sectors (each sector the most of itself and its neighbours).
func _slice_depth(sk: Skeleton3D, p: Vector3, kk: int) -> Array:
	if not _bins.has(kk):
		return [-INF, Vector3.ZERO]
	var best := -INF
	var way := Vector3.ZERO
	for e in _bins[kk]:
		var bone: int = e[2]
		var rest := sk.get_bone_global_rest(bone)
		var pose := sk.get_bone_global_pose(bone)
		var q: Vector3 = rest * (pose.affine_inverse() * p)
		var c: Vector2 = e[0]
		var r: PackedFloat32Array = e[1]
		var d := Vector2(q.x, q.z) - c
		var u := fposmod(atan2(d.y, d.x), TAU) / TAU * SECTORS - 0.5
		var s0 := int(floor(u))
		var f := u - float(s0)
		var r_a := _rad3(r, s0)
		var r_b := _rad3(r, s0 + 1)
		if r_a <= 0.0 and r_b <= 0.0:
			continue
		var dep := lerpf(r_a, r_b, f) - d.length()
		if dep > best:
			best = dep
			var out_rest := Vector3(d.x, 0.0, d.y).normalized() if d.length() > 1e-4 else Vector3(1, 0, 0)
			way = (pose.basis * (rest.basis.inverse() * out_rest)).normalized()
	return [best, way]


static func _rad3(r: PackedFloat32Array, s: int) -> float:
	var i := posmod(s, SECTORS)
	return maxf(maxf(r[i], r[(i + 1) % SECTORS]), r[(i + SECTORS - 1) % SECTORS])


## The points of an arm checked: [position, thickness (skeleton units)].
func _points(sk: Skeleton3D, i: int) -> Array:
	var ids: Array = _arm[i]
	var el: Vector3 = sk.get_bone_global_pose(ids[1]).origin
	var wr: Vector3 = sk.get_bone_global_pose(ids[2]).origin
	var hm := wr + (wr - el) * hand_len
	var pts := [[el.lerp(wr, 0.5), fore_r * _unit], [wr, hand_r * _unit], [hm, hand_r * _unit]]
	if tip_r > 0.0 and (_tip[i] as Vector3) != Vector3.ZERO:
		pts.append([sk.get_bone_global_pose(ids[2]) * (_tip[i] as Vector3), tip_r * _unit])
	if not (_shell[i] as Array).is_empty():
		var gf := sk.get_bone_global_pose(ids[1])
		var gh := sk.get_bone_global_pose(ids[2])
		for e in _shell[i]:
			pts.append([(gh if int(e[0]) == 2 else gf) * (e[1] as Vector3), shell_r * _unit])
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
		# Director 06.11, 19:27 («руки дергаются как сумасшедшие, меняя положение туда и назад»): the skeleton is
		# updated more than once a frame (the stance's own passes with no time step) and every such pass set the turn
		# straight to the frame's raw target — the follower was skipped half the time and the arm jumped to and fro
		# (tests/probe_bc_trace.gd). A pass with no time step now keeps the turn as it is; only a placing snaps it.
		if not enabled:
			_rot[i] = Vector3.ZERO
			_rot_v[i] = Vector3.ZERO
		elif snap or (legacy_zero_dt and delta <= 0.0):
			_rot[i] = want
			_rot_v[i] = Vector3.ZERO
		elif delta > 0.0:
			var cur: Vector3 = _rot[i]
			var vel: Vector3 = _rot_v[i]
			# (19:27) out of the clothes at `omega`, back toward the clip's own pose slowly (`omega_back`): a turn that
			# was needed a moment ago is not dropped and taken again — no back and forth
			# (a hand still in — last frame's `shown_m` — is taken out fast whatever the turn's size does)
			var om := omega if want.length() >= cur.length() or float(shown_m[i]) > 0.0 else omega_back
			for c in 3:
				var s := _spring(cur[c], vel[c], want[c], om, delta)
				cur[c] = s.x
				vel[c] = s.y
			_rot[i] = cur
			_rot_v[i] = vel
		var rot: Vector3 = (_rot[i] as Vector3) * clampf(strength, 0.0, 1.0)
		if rot.length() > 1e-5:
			var nb := Basis(rot.normalized(), rot.length()) * g.basis
			sk.set_bone_global_pose(ids[0], Transform3D(nb, g.origin))
		var after := -INF
		for pt in _points(sk, i):
			after = maxf(after, float(depth_at(sk, pt[0])[0]) + float(pt[1]))
		# the follower lagging while the clip brings the hand into the clothes (a state's switch, a gesture coming down):
		# more than `catch_m` in — catch up on a timed pass. An extra zero-time pass must preserve the follower.
		if delta > 0.0 and after > catch_m * _unit and want.length() > rot.length() and enabled:
			_rot[i] = want
			_rot_v[i] = Vector3.ZERO
			rot = want * clampf(strength, 0.0, 1.0)
			if rot.length() > 1e-5:
				sk.set_bone_global_pose(ids[0], Transform3D(Basis(rot.normalized(), rot.length()) * g.basis, g.origin))
			after = -INF
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
	var dir_sum := Vector3.ZERO
	var size := 0.0
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
		var way: Vector3 = da[1]
		if no_back and _hips >= 0:
			# Director 06.11, 18:48 («Пелагея… плечи прячут куда-то в тело»): a hand at the front of the quilted jacket was
			# taken out backwards — the whole arm swung behind her, the hand 18 cm behind the shoulder. Out sideways or
			# forward only; the hips' +z is forward on these rigs (toes)
			var hb := sk.get_bone_global_pose(_hips).basis
			var fwd: Vector3 = hb.z.normalized()
			var back := way.dot(fwd)
			if back < 0.0:
				way -= fwd * back
				# what is left sideways, and as much more of the arm's own side as was taken (smoothly: no jump)
				way += hb.x.normalized() * (1.0 if i == 0 else -1.0) * (-back) * 0.5
				way = way.normalized()
		if forward_only and _hips >= 0:
			# Director 06.11, 23:0x («Г: руки как в клипе»; then the talk took the arms out sideways like a wrestler's
			# again): a hand at the side behind the apron's edge stays as the clip has it; only a hand in front, in the
			# apron or the coat, is taken out — forward
			var fw: Vector3 = sk.get_bone_global_pose(_hips).basis.z.normalized()
			var ahead := way.dot(fw)
			if ahead <= 0.2:
				continue
			way = fw
		var axis := arm_v.cross(way)
		if axis.length() < 1e-6 or arm_v.length() < 1e-4:
			continue
		var rv := axis.normalized() * minf(dep / arm_v.length(), deg_to_rad(max_deg))
		# (19:27) the deepest point alone set the direction, and it hopped between the hand's points — the turn's
		# direction is now every point in, weighted by how deep, its size the largest needed
		dir_sum += rv * dep
		size = maxf(size, rv.length())
	if dir_sum.length() > 1e-9:
		want = dir_sum.normalized() * size
	return [want, deepest]


static func _spring(x: float, v: float, target: float, om: float, dt: float) -> Vector2:
	var y := x - target
	var j := v + om * y
	var e := exp(-om * dt)
	return Vector2(target + (y + j * dt) * e, (v - om * j * dt) * e)
