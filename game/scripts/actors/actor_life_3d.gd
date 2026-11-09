class_name ActorLife3D
extends SkeletonModifier3D
## Small living motion on top of Agata's idle clip (3D mode): breath in the chest, a slow drift of the
## head and, now and then, a glance aside that eases out and back. Everything is a smooth function of
## time (sums of sines, cosine-eased glances) — no step, no jump; amplitudes in degrees from data
## (`rt3d.life`). Weighted by how much she is standing still (`idle_weight`: 0 while walking or acting),
## so it never fights the walk or an action.

var idle_weight: float = 1.0
var t: float = 0.0
var breath_deg: float = 0.8
var breath_period_s: float = 4.2
## the breath's share on the chest bone (Spine01); the rest on the spine bone above it (Spine02)
var breath_chest_k: float = 0.6
var head_drift_deg: float = 2.0
var glance_deg: float = 9.0
var glance_every_s: Vector2 = Vector2(7.0, 13.0)
var glance_hold_s: Vector2 = Vector2(1.2, 2.4)
var glance_move_s: float = 0.7

## The weight going from foot to foot (Director 09.11, 22:18: «они слишком статичные, будто солдаты стоят, Агата у нас
## более живая, потому что покачивается»): Agata's idle clip carries her hips 7.9 cm side to side and 5.7 cm fore and
## aft, turns them 3–6° and her arms 3–4° (tests/probe_clip_ranges.gd); the villagers' stance clips — 0.6–1.4 cm and
## nothing else. Here, on top of the clip: the hips drift side to side (± sway_cm) and a little fore and aft, roll
## towards the loaded leg and turn a little about the vertical, the spine rolls back so the shoulders stay level, the
## arms swing a degree or two after the body. All sums of slow sines with the figure's own phase — no step, no beat
## shared between two villagers. The feet stay where they are (Actor3D's foot locks come after this modifier).
var sway_cm: float = 0.0
var sway_fore_cm: float = 0.0
var sway_roll_deg: float = 0.0
var sway_yaw_deg: float = 0.0
var sway_period_s: float = 7.3
var arm_swing_deg: float = 0.0
var unit: float = 1.0           # skeleton units per metre (Actor3D)
var _hips: int = -1
var _arms: Array = [-1, -1]
var _sway_ph: float = 0.0
var _lat_parent := Vector3.RIGHT     # the body's side-to-side axis in the hips' parent space (for the position)
var _fwd_parent := Vector3.BACK
var _ax_local: Dictionary = {}       # bone → [forward axis, up axis, lateral axis] in the bone's own rest frame

var _skel: Skeleton3D = null
var _chest: int = -1
var _spine: int = -1
var _neck: int = -1
var _head: int = -1
var _rng := RandomNumberGenerator.new()
var _g_start: float = 4.0     # next glance starts at this time
var _g_hold: float = 1.6
var _g_dir: float = 1.0
var _g_pitch: float = 0.0


func setup(d: Dictionary, skel: Skeleton3D) -> void:
	_skel = skel
	breath_deg = float(d.get("breath_deg", breath_deg))
	breath_period_s = float(d.get("breath_period_s", breath_period_s))
	breath_chest_k = clampf(float(d.get("breath_chest_k", breath_chest_k)), 0.0, 1.0)
	head_drift_deg = float(d.get("head_drift_deg", head_drift_deg))
	glance_deg = float(d.get("glance_deg", glance_deg))
	var ge: Array = d.get("glance_every_s", [glance_every_s.x, glance_every_s.y])
	glance_every_s = Vector2(float(ge[0]), float(ge[1]))
	var gh: Array = d.get("glance_hold_s", [glance_hold_s.x, glance_hold_s.y])
	glance_hold_s = Vector2(float(gh[0]), float(gh[1]))
	glance_move_s = float(d.get("glance_move_s", glance_move_s))
	_rng.seed = int(d.get("seed", 7))
	_chest = skel.find_bone(String(d.get("chest_bone", "Spine01")))
	_spine = skel.find_bone(String(d.get("spine_bone", "Spine02")))
	_neck = skel.find_bone(String(d.get("neck_bone", "neck")))
	_head = skel.find_bone(String(d.get("head_bone", "Head")))
	sway_cm = float(d.get("sway_cm", 0.0))
	sway_fore_cm = float(d.get("sway_fore_cm", 0.0))
	sway_roll_deg = float(d.get("sway_roll_deg", 0.0))
	sway_yaw_deg = float(d.get("sway_yaw_deg", 0.0))
	sway_period_s = maxf(1.0, float(d.get("sway_period_s", sway_period_s)))
	arm_swing_deg = float(d.get("arm_swing_deg", 0.0))
	_hips = skel.find_bone("Hips")
	_arms = [skel.find_bone("LeftArm"), skel.find_bone("RightArm")]
	if _hips >= 0 and _head >= 0 and int(_arms[0]) >= 0 and int(_arms[1]) >= 0:
		# the body's axes in skeleton space, from the rest pose: up to the head, lateral to the left arm, forward
		var up: Vector3 = (skel.get_bone_global_rest(_head).origin - skel.get_bone_global_rest(_hips).origin).normalized()
		var lat: Vector3 = skel.get_bone_global_rest(int(_arms[0])).origin - skel.get_bone_global_rest(int(_arms[1])).origin
		lat = (lat - up * lat.dot(up)).normalized()
		var fwd := lat.cross(up).normalized()
		var par := skel.get_bone_parent(_hips)
		var pb := skel.get_bone_global_rest(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
		_lat_parent = pb.inverse() * lat
		_fwd_parent = pb.inverse() * fwd
		for b in [_hips, _chest, _spine, int(_arms[0]), int(_arms[1])]:
			if b >= 0:
				var rb := skel.get_bone_global_rest(b).basis.orthonormalized()
				_ax_local[b] = [rb.inverse() * fwd, rb.inverse() * up, rb.inverse() * lat]
	_g_start = _rng.randf_range(glance_every_s.x * 0.5, glance_every_s.y * 0.5)
	_new_glance()


## A figure of its own (Actor3D._desync_idle): `u` 0..1 sets the breath period (±8 %) and phase, `seed`
## the glance timing — villagers sharing one data block do not breathe or glance together.
func desync(u: float, seed_v: int) -> void:
	breath_period_s *= 1.0 + 0.08 * (2.0 * u - 1.0)
	t = u * breath_period_s
	_rng.seed = seed_v
	_sway_ph = fposmod(u * 37.0 + float(seed_v % 1000) * 0.017, 1.0) * TAU
	sway_period_s *= 1.0 + 0.15 * (2.0 * fposmod(u * 7.0, 1.0) - 1.0)
	_g_start = t + _rng.randf_range(glance_every_s.x * 0.3, glance_every_s.y * 0.8)
	_new_glance()


func _new_glance() -> void:
	_g_hold = _rng.randf_range(glance_hold_s.x, glance_hold_s.y)
	_g_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	_g_pitch = _rng.randf_range(-0.25, 0.35)


func advance(delta: float) -> void:
	t += delta
	var g_end := _g_start + 2.0 * glance_move_s + _g_hold
	if t > g_end:
		_g_start = g_end + _rng.randf_range(glance_every_s.x, glance_every_s.y)
		_new_glance()


## Glance amount 0..1 at time `at`: cosine ease out, hold, cosine ease back.
func glance_amount(at: float) -> float:
	var x := at - _g_start
	if x <= 0.0:
		return 0.0
	if x < glance_move_s:
		return 0.5 - 0.5 * cos(PI * x / glance_move_s)
	x -= glance_move_s
	if x < _g_hold:
		return 1.0
	x -= _g_hold
	if x < glance_move_s:
		return 0.5 + 0.5 * cos(PI * x / glance_move_s)
	return 0.0


## Additive rotations (radians) this frame: {bone: Vector3(pitch, yaw, roll)} — also used by tests.
func offsets() -> Dictionary:
	var w := clampf(idle_weight, 0.0, 1.0)
	var out := {}
	var br := sin(TAU * t / breath_period_s)
	var b := deg_to_rad(breath_deg) * w
	out[_chest] = Vector3(-b * breath_chest_k * br, 0, 0)
	out[_spine] = Vector3(-b * (1.0 - breath_chest_k) * br, 0, 0)
	var drift_y := deg_to_rad(head_drift_deg) * (0.6 * sin(TAU * t / 9.7) + 0.4 * sin(TAU * t / 5.3 + 1.3))
	var drift_x := deg_to_rad(head_drift_deg) * 0.5 * (0.7 * sin(TAU * t / 7.9 + 0.4) + 0.3 * sin(TAU * t / 3.7))
	var g := glance_amount(t)
	var gy := deg_to_rad(glance_deg) * _g_dir * g
	var gx := deg_to_rad(glance_deg) * _g_pitch * g
	# the head turn is shared by the neck (40 %) and the head (60 %), breath counter-nods the head
	out[_neck] = Vector3((drift_x + gx) * 0.4, (drift_y + gy) * 0.4, 0) * w
	out[_head] = Vector3((drift_x + gx) * 0.6 + b * 0.5 * br, (drift_y + gy) * 0.6, 0) * w
	return out


## The sway now: [side to side −1..1, fore and aft −1..1, turn −1..1, arms −1..1] (tests read it).
func sway() -> Array:
	var p := TAU / sway_period_s
	var side := 0.65 * sin(p * t + _sway_ph) + 0.35 * sin(p * t / 1.618 + 2.0 * _sway_ph)
	var fore := 0.6 * sin(p * t / 1.37 + 1.7 + _sway_ph) + 0.4 * sin(p * t / 2.3 + 0.4)
	var turn := 0.7 * sin(p * t / 1.21 + 2.9 + 1.3 * _sway_ph) + 0.3 * sin(p * t / 0.83 + 0.9)
	# the arms follow the body a little late
	var arms := 0.65 * sin(p * (t - 0.35) + _sway_ph) + 0.35 * sin(p * (t - 0.35) / 1.618 + 2.0 * _sway_ph)
	return [side, fore, turn, arms]


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or idle_weight <= 0.0001:
		return
	if _hips >= 0 and _ax_local.has(_hips) and (sway_cm != 0.0 or sway_roll_deg != 0.0 or sway_yaw_deg != 0.0 or arm_swing_deg != 0.0):
		var w := clampf(idle_weight, 0.0, 1.0)
		var sw := sway()
		var side: float = sw[0]
		var k := 0.01 * unit * w
		# the pelvis sinks a little as the weight goes onto one leg (a straight leg cannot grow longer)
		var pos := skel.get_bone_pose_position(_hips) + _lat_parent * (sway_cm * side * k) + _fwd_parent * (sway_fore_cm * float(sw[1]) * k)
		skel.set_bone_pose_position(_hips, pos)
		var ah: Array = _ax_local[_hips]
		var roll := deg_to_rad(sway_roll_deg) * side * w
		var yaw := deg_to_rad(sway_yaw_deg) * float(sw[2]) * w
		skel.set_bone_pose_rotation(_hips, skel.get_bone_pose_rotation(_hips) * Quaternion(ah[0], roll) * Quaternion(ah[1], yaw))
		# the spine takes most of the roll and half of the turn back: the shoulders stay level, the head looks where it did
		for sb in [_spine, _chest]:
			if sb >= 0 and _ax_local.has(sb):
				var asb: Array = _ax_local[sb]
				skel.set_bone_pose_rotation(sb, skel.get_bone_pose_rotation(sb) * Quaternion(asb[0], -roll * 0.4) * Quaternion(asb[1], -yaw * 0.25))
		if arm_swing_deg != 0.0:
			for i in 2:
				var ab: int = _arms[i]
				if ab >= 0 and _ax_local.has(ab):
					var aa: Array = _ax_local[ab]
					var sgn := 1.0 if i == 0 else -1.0
					# forward of where the clip has it and back to it, never behind: the clip's own place is as near the
					# clothes as the arm can hang (arm_rest) — swinging back from it put the hand into the coat. About the
					# body's lateral axis (− is forward), the two arms a little apart in time
					var fw := clampf(0.5 + 0.5 * (float(sw[3]) * 0.7 + 0.3 * sgn * float(sw[2])), 0.0, 1.0)
					skel.set_bone_pose_rotation(ab, skel.get_bone_pose_rotation(ab) * Quaternion(aa[2], -deg_to_rad(arm_swing_deg) * 2.0 * fw * w))
	var off := offsets()
	for bone in off.keys():
		if int(bone) < 0:
			continue
		var v: Vector3 = off[bone]
		if v.length_squared() < 1e-12:
			continue
		var q := skel.get_bone_pose_rotation(bone)
		var add := Quaternion.from_euler(Vector3(v.x, v.y, v.z))
		skel.set_bone_pose_rotation(bone, q * add)
