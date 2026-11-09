extends SkeletonModifier3D
## The villager's mouth follows the voice of their own line (Director 09.11, 21:19–21:21: «добавить, чтобы была…
## открытие рта при разговорах… давай делать»). The models have had a jaw since v2 (pipeline/3d/npc_v2/build_npc.py
## "jaw": the chin and the lower lip on a bone Jaw, a dark mouth cavity behind), but the second AI's stance and talk
## clips (accepted 08.11) keep it shut — 0° in every frame (the old v2 talk clip swung it 4.5°). Here, after the clip,
## the jaw opens about its own axis by the loudness of the voice while this villager's line sounds — louder, wider;
## a pause — shut. Where the bus has no meter (the web: samples bypass it) — a steady chatter, as Tikhon's mouth.
## Data rt3d.jaw: {bone, axis (bone-local, from the v2 talk clip: +X), max_deg, db_closed, db_open, attack_s,
## release_s}. Tests: tests/test_jaw.gd.

const NO_METER_DB := -150.0
## the chatter where there is no meter: open share per step
const CHATTER := [0.55, 0.15, 0.8, 0.3, 0.65, 0.1]

var bone: int = -1
var axis := Vector3.RIGHT
var max_deg: float = 6.0
var db_closed: float = -42.0     # at or below — shut
var db_open: float = -12.0       # at or above — fully open
var attack_s: float = 0.03       # opening follows the voice this fast
var release_s: float = 0.08      # closing a little slower: no flutter between syllables
var chatter_step_s: float = 0.11
var speaker_id: String = ""
## shown opening 0..1 (tests read it)
var open: float = 0.0
## tests: the level in dB instead of the Voice bus (NAN — the bus); speaking 1 / 0 instead of VoiceDirector (-1)
var level_override: float = NAN
var speaking_override: int = -1

var _chatter_t: float = 0.0
var _chatter_i: int = 0
## the inside of the mouth (shader mouth_center / mouth_r): the mouth's point in the head bone's space, from the cavity
## mesh behind the lips (pipeline/3d/npc_v2/build_npc.py "cavity"); no cavity (Mitya, under the beard) — off
var mouth_r_m: float = 0.035
var _head: int = -1
var _mouth_local := Vector3.INF
var _mat: ShaderMaterial = null


func setup(d: Dictionary, skel: Skeleton3D, id: String) -> bool:
	bone = skel.find_bone(String(d.get("bone", "Jaw")))
	if bone < 0:
		return false
	var a: Array = d.get("axis", [1.0, 0.0, 0.0])
	axis = Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()
	max_deg = float(d.get("max_deg", max_deg))
	db_closed = float(d.get("db_closed", db_closed))
	db_open = float(d.get("db_open", db_open))
	attack_s = maxf(0.001, float(d.get("attack_s", attack_s)))
	release_s = maxf(0.001, float(d.get("release_s", release_s)))
	chatter_step_s = maxf(0.02, float(d.get("chatter_step_s", chatter_step_s)))
	speaker_id = id
	mouth_r_m = float(d.get("mouth_r_m", mouth_r_m))
	return true


## The mouth's point for the shader: the centre of the cavity mesh at rest, kept in the head bone's space.
func setup_mouth(meshes: Array, mat: ShaderMaterial, skel: Skeleton3D) -> bool:
	_head = skel.find_bone("Head")
	if _head < 0 or mat == null:
		return false
	for mi in meshes:
		if not String((mi as MeshInstance3D).name).contains("cavity"):
			continue
		var c: Vector3 = (mi as MeshInstance3D).get_aabb().get_center()
		var to_skel: Transform3D = skel.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		_mouth_local = skel.get_bone_global_rest(_head).affine_inverse() * (to_skel * c)
		_mat = mat
		return true
	return false


func mouth_world() -> Vector3:
	var skel := get_skeleton()
	if skel == null or _mouth_local == Vector3.INF:
		return Vector3.INF
	return skel.global_transform * (skel.get_bone_global_pose(_head) * _mouth_local)


func speaking() -> bool:
	if speaking_override >= 0:
		return speaking_override == 1
	if speaker_id == "":
		return false
	var vd: Node = get_node_or_null("/root/VoiceDirector")
	return vd != null and bool(vd.call("is_playing")) and String(vd.get("current_speaker")) == speaker_id


func level_db() -> float:
	if not is_nan(level_override):
		return level_override
	var bus := AudioServer.get_bus_index("Voice")
	if bus < 0:
		return -200.0
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))


## The opening wanted now (0..1), before smoothing.
func target(delta: float) -> float:
	if not speaking():
		_chatter_t = 0.0
		return 0.0
	var db := level_db()
	if db <= NO_METER_DB:
		_chatter_t -= delta
		if _chatter_t <= 0.0:
			_chatter_t = chatter_step_s
			_chatter_i = (_chatter_i + 1) % CHATTER.size()
		return float(CHATTER[_chatter_i])
	return clampf((db - db_closed) / maxf(0.1, db_open - db_closed), 0.0, 1.0)


func step(delta: float) -> void:
	var want := target(delta)
	var tau := attack_s if want > open else release_s
	open += (want - open) * (1.0 - exp(-delta / tau))
	if open < 0.001 and want <= 0.0:
		open = 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or bone < 0:
		return
	step(delta)
	if _mat != null:
		_mat.set_shader_parameter("mouth_r", mouth_r_m if open > 0.0 else 0.0)
		if open > 0.0:
			_mat.set_shader_parameter("mouth_center", mouth_world())
	if open <= 0.0:
		return
	var q := skel.get_bone_pose_rotation(bone)
	skel.set_bone_pose_rotation(bone, q * Quaternion(axis, deg_to_rad(max_deg * open)))
