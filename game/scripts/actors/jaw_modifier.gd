extends SkeletonModifier3D
## The villager's mouth follows the voice of their own line (Director 09.11, 21:19–21:21: «добавить, чтобы была…
## открытие рта при разговорах… давай делать»): louder — wider; a pause — shut. Where the bus has no meter (the web:
## samples bypass it) — a steady chatter, as Tikhon's mouth.
## The mouth is PAINTED (Director 21:56 «рот сделан плохо», 22:18 «рты открывающиеся и нормальные»): turning the bone
## Jaw tore the models' closed surface along the lips into a jagged slit with cloth texture showing behind (the first
## try, 6°). Now a dark lens on the face along the lip line opens with the voice (shaders/actor_3d.gdshader mouth_*; the
## line is measured from each model — tests/bake_mouth.gd); the bone is left alone (max_deg 0: at the figures' size on
## screen a chin's 3 mm is a third of a pixel).
## Data rt3d.jaw: {bone, axis, max_deg, db_closed, db_open, attack_s, release_s, open_m, w_share, up_share, shift_mm}.
## Tests: tests/test_jaw.gd.

const NO_METER_DB := -150.0
## the chatter where there is no meter: open share per step
const CHATTER := [0.55, 0.15, 0.8, 0.3, 0.65, 0.1]

var bone: int = -1
var axis := Vector3.RIGHT
var max_deg: float = 0.0
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
## The painted mouth (shader mouth_*): the lip line of this model in the head bone's frame (tests/bake_mouth.gd →
## res://data/actors_rest/mouth_<id>.json); no file or no parting in the model (Mitya, under the beard) — nothing painted.
var open_m: float = 0.0065       # the opening's height when fully open (m)
var w_share: float = 0.85        # the opening's width, a share of the lips' width
var up_share: float = 0.3        # how much of it opens above the lip line (the upper lip lifts a little)
var shift_mm := Vector3.ZERO     # the lip line as painted against the model's cut: [to the villager's right, up, out of the face], mm
var _head: int = -1
var _frame_local := Transform3D.IDENTITY
var _shape := Vector4.ZERO
var _mat: ShaderMaterial = null


func setup(d: Dictionary, skel: Skeleton3D, id: String) -> bool:
	bone = skel.find_bone(String(d.get("bone", "Jaw")))
	# 11.11 (Director 10.11, 22:31: «губы… хотя бы Агаты и Нины нужно сделать как положено»): Agata's model has no jaw bone
	# — the painted mouth needs none (max_deg 0: the bone is never turned)
	if bone < 0 and float(d.get("max_deg", 0.0)) > 0.0:
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
	open_m = float(d.get("open_m", open_m))
	w_share = float(d.get("w_share", w_share))
	up_share = float(d.get("up_share", up_share))
	var sh: Array = d.get("shift_mm", [0.0, 0.0])
	shift_mm = Vector3(float(sh[0]), float(sh[1]), float(sh[2]) if sh.size() > 2 else 0.0)
	return true


## The painted mouth of this model: its lip line (data file) → the frame in the head bone's space and the shape.
func setup_mouth(mat: ShaderMaterial, skel: Skeleton3D, id: String) -> bool:
	_head = skel.find_bone("Head")
	for e in OS.get_environment("MOUTH_SHIFTS").split(",", false):   # probes: MOUTH_SHIFTS=id:dx:dy,… (mm) instead of the data
		if e.get_slice(":", 0) == id:
			shift_mm = Vector3(float(e.get_slice(":", 1)), float(e.get_slice(":", 2)), float(e.get_slice(":", 3)) if e.get_slice_count(":") > 3 else 0.0)
	var path := "res://data/actors_rest/mouth_%s.json" % id
	if _head < 0 or mat == null or not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or d.has("none") or not d.has("at"):
		return false
	var v3 := func(a: Array) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))
	_frame_local = Transform3D(Basis(v3.call(d["right"]), v3.call(d["up"]), v3.call(d["fwd"])), v3.call(d["at"]))
	var u := float(d.get("unit_per_m", 100.0))
	# set right by hand against the picture of the lips (the model's cut is not always on the painted lip line):
	# shift_mm [to the villager's right, up, out of the face]
	_frame_local.origin += (_frame_local.basis.x * shift_mm.x + _frame_local.basis.y * shift_mm.y + _frame_local.basis.z * shift_mm.z) * (0.001 * u)
	# the opening is narrower than the lips: its corners sit on the lip line's own curve at that width
	_shape = Vector4(float(d["half_w"]) * w_share, open_m * u, float(d.get("sag", 0.0)) * w_share * w_share,
		float(d.get("back", 0.0)) * w_share * w_share)
	_mat = mat
	_mat.set_shader_parameter("mouth_shape", _shape)
	_mat.set_shader_parameter("mouth_up_share", up_share)
	_mat.set_shader_parameter("mouth_depth", 0.016 * u)
	_mat.set_shader_parameter("mouth_soft", 0.0005 * u)
	_mat.set_shader_parameter("mouth_open", 0.0)
	return true


## Has a painted mouth (tests).
func painted() -> bool:
	return _mat != null


## The mouth's frame in the figure's world (x across, y up, z out of the face), as the shader gets it.
func mouth_frame() -> Transform3D:
	var skel := get_skeleton()
	if skel == null or _head < 0:
		return Transform3D.IDENTITY
	return skel.global_transform * skel.get_bone_global_pose(_head) * _frame_local


func speaking() -> bool:
	if speaking_override >= 0:
		return speaking_override == 1
	if speaker_id == "":
		return false
	var vd: Node = get_node_or_null("/root/VoiceDirector")
	if vd == null or not bool(vd.call("is_playing")) or String(vd.get("current_speaker")) != speaker_id:
		return false
	# Agata's own voice also reads her thoughts (keys of data/story/text, kind «narration»/«item»): the lips move only for
	# what she says aloud — a scene's line
	return speaker_id != "agata" or String(vd.get("current_kind")) == "line"


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
	if skel == null:
		return
	step(delta)
	if _mat != null:
		_mat.set_shader_parameter("mouth_open", open)
		if open > 0.0:
			_mat.set_shader_parameter("mouth_inv", mouth_frame().affine_inverse())
	if open <= 0.0 or max_deg <= 0.0 or bone < 0:
		return
	var q := skel.get_bone_pose_rotation(bone)
	skel.set_bone_pose_rotation(bone, q * Quaternion(axis, deg_to_rad(max_deg * open)))
