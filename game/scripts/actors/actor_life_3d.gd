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
var head_drift_deg: float = 2.0
var glance_deg: float = 9.0
var glance_every_s: Vector2 = Vector2(7.0, 13.0)
var glance_hold_s: Vector2 = Vector2(1.2, 2.4)
var glance_move_s: float = 0.7

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
	_g_start = _rng.randf_range(glance_every_s.x * 0.5, glance_every_s.y * 0.5)
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
	out[_chest] = Vector3(-b * 0.6 * br, 0, 0)
	out[_spine] = Vector3(-b * 0.4 * br, 0, 0)
	var drift_y := deg_to_rad(head_drift_deg) * (0.6 * sin(TAU * t / 9.7) + 0.4 * sin(TAU * t / 5.3 + 1.3))
	var drift_x := deg_to_rad(head_drift_deg) * 0.5 * (0.7 * sin(TAU * t / 7.9 + 0.4) + 0.3 * sin(TAU * t / 3.7))
	var g := glance_amount(t)
	var gy := deg_to_rad(glance_deg) * _g_dir * g
	var gx := deg_to_rad(glance_deg) * _g_pitch * g
	# the head turn is shared by the neck (40 %) and the head (60 %), breath counter-nods the head
	out[_neck] = Vector3((drift_x + gx) * 0.4, (drift_y + gy) * 0.4, 0) * w
	out[_head] = Vector3((drift_x + gx) * 0.6 + b * 0.5 * br, (drift_y + gy) * 0.6, 0) * w
	return out


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or idle_weight <= 0.0001:
		return
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
