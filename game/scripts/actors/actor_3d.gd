class_name Actor3D
extends SubViewport
## Agata in real 3D inside the 2D room (actor data `render: "3d"`, block `rt3d`).
##
## The same Meshy model, texture and skeleton the sprite sheets were rendered from
## (assets/characters/agata/rt3d/agata_rt.glb: mesh decimated for the web, all clips in one file) is
## drawn every frame into this transparent SubViewport by an orthographic camera at the room's
## elevation; the Player shows the texture on a Sprite2D at its feet, so y-sort, occluders, the
## contact shadow, the room tone and the cast light shadows stay the 2D ones.
##
## Motion is driven from outside, deterministically (AnimationTree in manual mode, TimeSeek inputs):
##   - yaw: any angle, continuous (the Player eases it towards the walking direction / a hotspot);
##   - locomotion weight w (0 = idle, 1 = walk) and the walk phase;
##   - idle: two slots crossfading between variants of calm idles (no loop seam ever shows: at the
##     end of a clip the next one fades in over `idle.crossfade_s`);
##   - one-shot action (open / pick / reach) with fade in/out; a second instance of the same clip (act2) blends in
##     for seamless loops (talk, listen: the end of one pass fades into the start of the next) and for cuts
##     inside a clip (the long hold of «open» skipped by a crossfade);
##   - every weight the callers ramp is shown through a critically damped follower (`blend_omega`), and all
##     tracks are interpolated cubically: no velocity kink where a fade, a step or a key starts or ends;
##   - the walk plays as a loop baked from its best cycle (`walk_loop`): no pop at the cycle's seam.
## Root motion of the walk is measured from the clip itself (`build_root_motion`): the stance foot's
## backward slide per phase → the Player advances by exactly that, so the planted foot stays on the floor.

const SHADER := preload("res://shaders/actor_3d.gdshader")
const RM_N := 240  # phase samples of the walk's root-motion table

var spec: Dictionary = {}
var ok: bool = false
var load_error: String = ""

var turn: Node3D = null          # yaw pivot; feet at the origin
var oblique: Node3D = null       # depth stretch of the floor (oblique projection), parent of `turn`
var floor_k: float = 0.0         # room floor foreshortening used by the oblique stretch (0 = off)
var model: Node3D = null
var skeleton: Skeleton3D = null
var anim: AnimationPlayer = null
var tree: AnimationTree = null
var camera: Camera3D = null
var life: ActorLife3D = null
var meshes: Array[MeshInstance3D] = []
var material: ShaderMaterial = null

var clips: Dictionary = {}       # role → animation name (with library prefix)
var idle_pool: Array = []        # idle variants: [{name, weight}]
var walk_len: float = 1.0
var walk_speed_mps: float = 1.3  # natural speed of the walk clip (stride per cycle / cycle length)
var stride_m: float = 1.3
var root_d: PackedFloat32Array = PackedFloat32Array()  # cumulative stance-foot slide (m), RM_N+1 values
var contacts: PackedFloat32Array = PackedFloat32Array()  # phases where a foot gets planted
var stance_side: PackedByteArray = PackedByteArray()    # 0 = left, 1 = right planted, per phase sample
var stride_floor: Array = [0.0, 0.0, 0.0, 0.0]           # lowest height of [L ankle, L ball, R ankle, R ball] walking
var clip_feet_h: Array = []                               # the walk clip's [L ankle, L ball, R ankle, R ball] heights per phase sample (m)
var hips_h: PackedFloat32Array = PackedFloat32Array()    # the walk's hips height per phase sample (model m)
## The walk's bob deepened (data walk.bob_deepen): the body goes down this much more at the bottom of each step — the
## figure lowered by it, the feet kept where the clip has them by the leg IK (stride planting). Metres, ≤ 0, shown now.
var _bob_y: float = 0.0
var _hips_top: float = 0.0
var foot_bones: Array = []       # [left foot, left toe, right foot, right toe] bone indices
## Middle of each stance of the walk cycle: [phase, side (0 left / 1 right), stance foot position (model frame)].
var stance_mids: Array = []
## Mid-point of the two feet (floor x, z in the model frame, clip average) per clip: the model is shifted
## by the blend of these so the feet stay centred on her position whatever clip is in front — idle
## variants with a stance a few cm forward or back do not make the feet skate over a crossfade.
var clip_mid: Dictionary = {}

var elev_deg: float = 14.0
var frame_px: Vector2 = Vector2(320, 420)   # frame in sheet px (node scale 1)
var pivot: Vector2 = Vector2(0.5, 0.94)
var ppm: float = 214.8           # sheet px per ortho metre at this elevation
var render_scale: float = 1.0    # texture px per sheet px
var _sized: bool = false

# Idle slots (A/B crossfade)
var _slot_name: Array = ["", ""]
var _slot_t: Array = [0.0, 0.0]
var _slot_len: Array = [1.0, 1.0]
var _slot_active: int = 0
var _slot_mix: float = 0.0       # 0 = slot A, 1 = slot B (eased towards the active slot)
var _idle_rng := RandomNumberGenerator.new()
## Playback rate of the idle clips for this figure (data `idle.desync.rate_jitter`): two villagers built
## from the same library idle never breathe and sway in step (Director 01.11).
var idle_rate: float = 1.0
var _act_name: String = ""

# Weights as shown (critically damped followers of what the callers ask) and the action slot as shown.
var _w_s: float = 0.0
var _w_v: float = 0.0
var _a_s: float = 0.0
var _a_v: float = 0.0
var _shown_t: float = 0.0
var _shown_t2: float = 0.0
var _shown_mix: float = 0.0
var _shown_phase: float = 0.0


## Builds everything from the actor data. Returns false (load_error set) when the model or a clip is missing.
func setup(actor_spec: Dictionary) -> bool:
	spec = actor_spec.get("rt3d", {})
	name = "Actor3D"
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(log(maxf(float(spec.get("msaa", 4)), 1.0)) / log(2.0)), 0, 3)]
	# a number, or "room": the room's floor foreshortening k = sin(elevation) (set_elevation per room) —
	# then a step towards the viewer moves the drawn foot exactly as much as the floor under it
	var ev = spec.get("camera_elev_deg", 14.0)
	elev_deg = 14.0 if typeof(ev) == TYPE_STRING else float(ev)
	var fr: Array = spec.get("frame_px", [320, 420])
	frame_px = Vector2(float(fr[0]), float(fr[1]))
	var pv: Array = spec.get("pivot", [0.5, 0.94])
	pivot = Vector2(float(pv[0]), float(pv[1]))
	# Same height on screen as the sprite figure: the sheets are a 14° ortho render at
	# frame_h / (height × margin) px per metre; a standing figure projects to height × cos(elev).
	ppm = _ppm_for(elev_deg)
	var path := String(spec.get("scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		load_error = "no 3D model " + path
		return false
	var packed = _packed(path)
	if not (packed is PackedScene):
		load_error = "not a scene: " + path
		return false
	# Oblique floor (data `oblique_floor`): the world's depth axis is stretched by k / sin(elevation), so a
	# step towards the viewer moves the drawn foot as much as the room's floor (k) while heights keep the
	# 14° look (face, proportions). Applied above the yaw pivot: the figure turns inside it.
	oblique = Node3D.new()
	oblique.name = "Oblique"
	add_child(oblique)
	turn = Node3D.new()
	turn.name = "Turn"
	oblique.add_child(turn)
	model = (packed as PackedScene).instantiate()
	turn.add_child(model)
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	anim = _find(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or anim == null:
		load_error = "model without Skeleton3D/AnimationPlayer"
		return false
	for n in _all(model):
		if n is MeshInstance3D:
			meshes.append(n)
	_apply_material()
	_resolve_clips()
	_smooth_tracks()
	_smooth_kinks()
	_hang_arms()
	_bake_walk_loop()
	# A villager may have no walk clip (data `require_walk` false: Pavel, Mitya, Ilya's wife — their stagings slide):
	# the stance stands in for it, nothing walks.
	if idle_pool.is_empty() or (not clips.has("walk") and bool(spec.get("require_walk", true))):
		load_error = "clips missing: " + str(clips)
		return false
	_build_tree()
	_build_camera()
	for b in ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]:
		foot_bones.append(skeleton.find_bone(b))
	life = ActorLife3D.new()
	life.name = "Life"
	life.setup(spec.get("life", {}), skeleton)
	skeleton.add_child(life)
	_setup_arm_tone()
	_setup_limit()   # the clips' pose first: the IKs and the look come after it and are not slowed by it
	_setup_feet()    # legs first: the skirt's pushers ride on the legs as the IK leaves them
	_setup_arm_clear()
	_setup_look()    # before the skirt: the springs run last, once per frame
	_setup_skirt()
	_setup_springs()
	_measure_mids()
	if clips.has("walk"):
		build_root_motion()
	_start_idle_slot(0, _pick_idle(""), 0.0)
	_desync_idle(String(actor_spec.get("id", "")))
	pose(0.0, 0.0, 0.0, 0.0)
	_measure_foot_rest()
	_measure_arm_ref()
	ok = true
	return true


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


## The model's own albedo, lit like the sprite renders (shaders/actor_3d.gdshader, values from data).
## K (стр. 16): the model was briefly kept for the whole game — but the instances share the scene's Animation resources,
## which setup tunes in place (loop modes, cubic keys), so a second instance (tests that vary the data, a reload) started
## from already tuned clips (CI 41249423897: the walk-stop jolt and the braid's rest changed). Back to the resource
## cache: the model stays loaded while a figure uses it. The big cost of a room change was the villagers' sheets
## (NpcActor: placement-only sheet for a live villager).
static func _packed(path: String) -> Resource:
	return load(path)


func _apply_material() -> void:
	var tex: Texture2D = null
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
				tex = (m as BaseMaterial3D).albedo_texture
	material = ShaderMaterial.new()
	material.shader = SHADER
	if tex != null:
		material.set_shader_parameter("albedo_tex", tex)
	var lt: Dictionary = spec.get("light", {})
	for k in lt.keys():
		var v = lt[k]
		if String(k).begins_with("_"):
			continue
		if v is Array and v.size() == 3:
			material.set_shader_parameter(k, Vector3(float(v[0]), float(v[1]), float(v[2])))
		else:
			material.set_shader_parameter(k, float(v))
	# Data `keep_materials`: surfaces of these materials keep their own (the villagers' dark mouth cavity — no texture).
	var keep: Array = spec.get("keep_materials", [])
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var kept := false
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m != null and keep.has(String(m.resource_name)):
				kept = true
		if not kept:
			mi.material_override = material


## Roles → clip names from data (`clips`, `idle.pool`); a name is matched against the player's
## animation list with or without the library prefix and Blender's ".001" suffixes.
func _resolve_clips() -> void:
	var names := anim.get_animation_list()
	var lookup := func(want: String) -> String:
		for n in names:
			var bare := String(n).get_slice("/", String(n).get_slice_count("/") - 1)
			if bare == want or bare.get_slice(".", 0) == want:
				return String(n)
		return ""
	var c: Dictionary = spec.get("clips", {})
	for role in c.keys():
		if String(role).begins_with("_"):
			continue
		var got: String = lookup.call(String(c[role]))
		if got != "":
			clips[String(role)] = got
	var idle: Dictionary = spec.get("idle", {})
	for it in idle.get("pool", []):
		var got: String = lookup.call(String(it.get("clip", "")))
		if got != "":
			var e := {"name": got, "weight": float(it.get("weight", 1.0)), "from": float(it.get("from", 0.0)), "to": float(it.get("to", 1.0))}
			idle_pool.append(e)
	if idle_pool.is_empty() and clips.has("idle"):
		idle_pool.append({"name": clips["idle"], "weight": 1.0, "from": 0.0, "to": 1.0})
	for role in clips.keys():
		var a := anim.get_animation(clips[role])
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR if role == "walk" else Animation.LOOP_NONE
	walk_len = anim.get_animation(clips["walk"]).length if clips.has("walk") else 1.0


## Cubic interpolation between the clips' keys (30 per second): linear interpolation draws every bone along a
## polyline — a small velocity kink at each key, 30 times a second, which reads as a faint tremor at 60 fps.
func _smooth_tracks() -> void:
	if not bool(spec.get("cubic", true)):
		return
	var names: Array = []
	for e in idle_pool:
		names.append(e["name"])
	for role in clips.keys():
		if not names.has(clips[role]):
			names.append(clips[role])
	for nm in names:
		var a := anim.get_animation(nm)
		if a == null:
			continue
		for i in a.get_track_count():
			var ty := a.track_get_type(i)
			if ty == Animation.TYPE_POSITION_3D or ty == Animation.TYPE_ROTATION_3D or ty == Animation.TYPE_SCALE_3D:
				a.track_set_interpolation_type(i, Animation.INTERPOLATION_CUBIC)


## Hands and arms without a twitch (Director 06.11, 15:08: «руки всё ещё иногда дёргаются»): the Meshy clips carry
## single-key kinks — Talk_with_Hands_Open has two in the left hand at 0.52 and 0.68 s (7 mm per 1/60 s² against
## 1–2 mm around them, tests/probe_hand_spikes.gd), the loop met them every 3.2 s. The rotation keys of the arm and
## hand bones of every clip but the walk get a gaussian (data rt3d.smooth {sigma_frames, bones}). The kinks were not
## one key: the gesture flicks the wrist in 2–3 keys (Mitya talk 0.75 s: 6.6 mm per 1/60 s² — the arm root 0.6);
## σ 1.5 / 2.5 / 3.5 keys left 9 / 8 / 7 spikes over 4 mm, σ 5 none (worst 3.6 mm) — the villagers take 5 (≈ 0.17 s:
## a gesture of half a second and more keeps its shape). Every key, the ends too (clamped: an end key kept as it was
## stood out against its smoothed neighbours — a kink at the end of each one-shot action).
const SMOOTH_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "Neck", "Head"]


func _smooth_kinks() -> void:
	var sm: Dictionary = spec.get("smooth", {})
	var sigma := float(sm.get("sigma_frames", 0.0))   # off unless the actor's data ask (villagers: 5)
	if sigma <= 0.0:
		return
	var bones: Array = sm.get("bones", SMOOTH_BONES)
	var per_clip: Dictionary = sm.get("clips", {})   # role → its own σ (a clip borrowed from another body: pick_up)
	var done := {}
	for role in clips.keys():
		if role == "walk" or done.has(clips[role]):
			continue
		var sg := float(per_clip.get(role, sigma))
		var r := int(ceil(sg * 2.5))
		var w := PackedFloat32Array()
		for k in range(-r, r + 1):
			w.append(exp(-0.5 * float(k * k) / (sg * sg)))
		done[clips[role]] = true
		var a := anim.get_animation(clips[role])
		if a == null or a.has_meta("kinks_smoothed"):
			continue   # the clips are shared by every copy of the model (one load per game): smoothed once
		a.set_meta("kinks_smoothed", true)
		for i in a.get_track_count():
			if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(a.track_get_path(i).get_concatenated_subnames())
			if not bones.has(bone):
				continue
			var n := a.track_get_key_count(i)
			if n < 2 * r + 3:
				continue
			var q: Array = []
			for k in n:
				q.append(a.track_get_key_value(i, k))
			for k in range(0, n):
				var acc := Quaternion(0, 0, 0, 0)
				var ws := 0.0
				var q0: Quaternion = q[k]
				for j in range(-r, r + 1):
					var kk := clampi(k + j, 0, n - 1)
					var qj: Quaternion = q[kk]
					if q0.dot(qj) < 0.0:
						qj = -qj
					acc = Quaternion(acc.x + qj.x * w[j + r], acc.y + qj.y * w[j + r], acc.z + qj.z * w[j + r], acc.w + qj.w * w[j + r])
					ws += w[j + r]
				a.track_set_key_value(i, k, acc.normalized())


## Arms hanging, not spread (Director 06.11, 15:56: «остальных тоже явно коробит»): Meshy's talk clip takes the upper
## arms out sideways to 30–34° (Mitya, Nina, Ilya's wife, Tamara — tests/probe_villager_arm_spread.gd; a relaxed arm
## hangs at 5–12°). Data rt3d.arm_hang {from_deg, k, roles}: in those clips, at every key of the upper arm, its sideways angle in the hips' frame beyond `from_deg` is kept at `k` (the
## rest is turned down toward the body in the plane of the arm and the side); an arm brought forward in a gesture has
## little sideways angle and keeps it. BodyClear later takes the hand out of the clothes as before.
func _hang_arms() -> void:
	var ah: Dictionary = spec.get("arm_hang", {})
	if ah.is_empty():
		return
	var s0 := deg_to_rad(float(ah.get("from_deg", 12.0)))
	var k := clampf(float(ah.get("k", 0.35)), 0.0, 1.0)
	var names := {}
	for role in ah.get("roles", ["idle", "talk", "listen"]):
		if clips.has(role):
			names[clips[role]] = true
	for e in idle_pool:
		names[e["name"]] = true
	var hips := skeleton.find_bone("Hips")
	if hips < 0:
		return
	# the hips' frame at rest: up toward the head, `out` toward the left arm's side
	var head := skeleton.find_bone("Head")
	var la := skeleton.find_bone("LeftArm")
	if head < 0 or la < 0:
		return
	var hr := skeleton.get_bone_global_rest(hips)
	var up: Vector3 = (hr.affine_inverse() * skeleton.get_bone_global_rest(head).origin).normalized()
	var lp: Vector3 = hr.affine_inverse() * skeleton.get_bone_global_rest(la).origin
	var out_l: Vector3 = (lp - up * lp.dot(up)).normalized()
	for nm in names.keys():
		var a := anim.get_animation(nm)
		if a == null or a.has_meta("arms_hung"):
			continue   # shared by every copy of the model: once
		a.set_meta("arms_hung", true)
		var tr := {}
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				tr[String(a.track_get_path(i).get_concatenated_subnames())] = i
		for side in ["Left", "Right"]:
			var arm := skeleton.find_bone(side + "Arm")
			var fore := skeleton.find_bone(side + "ForeArm")
			if arm < 0 or fore < 0 or not tr.has(side + "Arm"):
				continue
			var out: Vector3 = out_l if side == "Left" else -out_l
			var chain: Array = []   # the arm's parents below the hips, hips first
			var b := skeleton.get_bone_parent(arm)
			while b >= 0 and b != hips:
				chain.push_front(b)
				b = skeleton.get_bone_parent(b)
			var along: Vector3 = skeleton.get_bone_rest(fore).origin.normalized()
			var ti: int = tr[side + "Arm"]
			for key in a.track_get_key_count(ti):
				var t := a.track_get_key_time(ti, key)
				var qp := Quaternion.IDENTITY
				for cb in chain:
					var bn := skeleton.get_bone_name(cb)
					var ql: Quaternion = a.rotation_track_interpolate(tr[bn], t) if tr.has(bn) else skeleton.get_bone_rest(cb).basis.get_rotation_quaternion()
					qp = qp * ql
				var qa: Quaternion = a.track_get_key_value(ti, key)
				var d: Vector3 = (qp * qa) * along
				var sa := asin(clampf(d.dot(out), -1.0, 1.0))
				if sa <= s0:
					continue
				var axis := d.cross(out)
				if axis.length() < 1e-5:
					continue
				var turn := Quaternion(axis.normalized(), -(sa - (s0 + (sa - s0) * k)))
				a.track_set_key_value(ti, key, (qp.inverse() * turn * qp * qa).normalized())


## The walk as a seamless loop (data `walk_loop` [from, to], seconds of the clip): keys every 1/30 s from `from`,
## and after the last one the first again, one key interval later. Agata's Walking_Woman ends on its last key, so
## the clip as such jumped 6 cm back to its first pose in no time once a cycle; the villagers' one-second walks end
## on two closing keys (a hitch once a cycle); the long walks (Pavel, Mitya, Ilya) loop on their best-matching
## cycle. Windows from tests/probe_walkloop.gd (seam second difference ≤ the clip's own).
func _bake_walk_loop() -> void:
	if not clips.has("walk"):
		return
	var wl = spec.get("walk_loop", null)
	if not (wl is Array) or (wl as Array).size() < 2:
		return
	var src := anim.get_animation(clips["walk"])
	var h := 1.0 / float(spec.get("walk_loop_fps", 30.0))
	var from := float(wl[0])
	var n := int(round((float(wl[1]) - from) / h))
	if n < 8 or from < 0.0 or from + (n - 1) * h > src.length + 0.001:
		push_warning("Actor3D: walk_loop %s outside the clip (%.3f s)" % [str(wl), src.length])
		return
	var dst := Animation.new()
	dst.length = n * h
	dst.loop_mode = Animation.LOOP_LINEAR
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var j := dst.add_track(ty)
		dst.track_set_path(j, src.track_get_path(i))
		dst.track_set_interpolation_type(j, Animation.INTERPOLATION_CUBIC if bool(spec.get("cubic", true)) else Animation.INTERPOLATION_LINEAR)
		dst.track_set_interpolation_loop_wrap(j, true)
		var vals: Array = []
		for k in n:
			var t := minf(from + k * h, src.length)
			if ty == Animation.TYPE_POSITION_3D:
				vals.append(src.position_track_interpolate(i, t))
			elif ty == Animation.TYPE_ROTATION_3D:
				vals.append(src.rotation_track_interpolate(i, t))
			else:
				vals.append(src.scale_track_interpolate(i, t))
		_smooth_seam(vals, int(spec.get("walk_loop_smooth", 0)), ty == Animation.TYPE_ROTATION_3D)
		for k in n:
			if ty == Animation.TYPE_POSITION_3D:
				dst.position_track_insert_key(j, k * h, vals[k])
			elif ty == Animation.TYPE_ROTATION_3D:
				dst.rotation_track_insert_key(j, k * h, vals[k])
			else:
				dst.scale_track_insert_key(j, k * h, vals[k])
	var lib := AnimationLibrary.new()
	lib.add_animation("walk", dst)
	anim.add_animation_library("rt_loop", lib)
	clips["walk"] = "rt_loop/walk"
	walk_len = dst.length


## Seam of a looped key sequence (values at equal steps, the last followed by the first): the `m` keys before
## and after the seam are redrawn as one cubic Hermite arc from the key m+1 before it to the key m after it, with
## the motion's own speed at both ends — a cycle that does not quite close (Agata's walk) closes smoothly.
## Rotations are redrawn in the rotation-vector space around the arc's first key.
static func _smooth_seam(vals: Array, m: int, is_rot: bool) -> void:
	var n := vals.size()
	if m <= 0 or n < 4 * m + 4:
		return
	var ia := n - 1 - m          # arc start (kept)
	var ib := m                  # arc end (kept), index after the wrap
	var span := float(2 * m + 1) # key steps from ia to ib across the seam
	var to_v := func(x):
		return x
	var q0 := Quaternion.IDENTITY
	if is_rot:
		q0 = (vals[ia] as Quaternion).normalized()
		to_v = func(x):
			var d: Quaternion = q0.inverse() * (x as Quaternion).normalized()
			if d.w < 0.0:
				d = -d
			var ang := d.get_angle()
			return Vector3.ZERO if ang < 1e-9 else d.get_axis() * ang
	var pa: Vector3 = to_v.call(vals[ia])
	var pb: Vector3 = to_v.call(vals[ib])
	var ma: Vector3 = pa - to_v.call(vals[ia - 1])          # per key step
	var mb: Vector3 = to_v.call(vals[ib + 1]) - pb
	for s in range(1, 2 * m + 1):
		var u := float(s) / span
		var u2 := u * u
		var u3 := u2 * u
		var p: Vector3 = (2.0 * u3 - 3.0 * u2 + 1.0) * pa + (u3 - 2.0 * u2 + u) * span * ma + (-2.0 * u3 + 3.0 * u2) * pb + (u3 - u2) * span * mb
		var idx := (ia + s) % n
		if is_rot:
			var ang := p.length()
			vals[idx] = q0 * (Quaternion.IDENTITY if ang < 1e-9 else Quaternion(p / ang, ang))
		else:
			vals[idx] = p


## The skirt on its own bones (tools/rig_skirt.py: a ring of chains Skirt<c>_<k> from the hips to the hem; Director
## 30.10, 19:16 «сгибы юбки не красиво» — the auto-rig had the hem on the shins, so a step split the skirt into two
## «trouser legs» creased between them): each chain is a spring (SpringBoneSimulator3D) that hangs, swings after a turn
## or a step and is pushed by capsules on the thighs and shins (data rt3d.skirt). Nothing when the model has no skirt.
var skirt: SpringBoneSimulator3D = null


func _setup_skirt() -> void:
	var sk: Dictionary = spec.get("skirt", {})
	if sk.is_empty() or skeleton.find_bone("Skirt0_0") < 0:
		return
	var n := 0
	while skeleton.find_bone("Skirt%d_0" % n) >= 0:
		n += 1
	var last := 0
	while skeleton.find_bone("Skirt0_%d" % (last + 1)) >= 0:
		last += 1
	skirt = SpringBoneSimulator3D.new()
	skirt.name = "Skirt"
	skeleton.add_child(skirt)
	skirt.setting_count = n
	# springs and pushers work in world metres (the Meshy skeleton itself is in centimetres under a 0.01 scale)
	var u := float(sk.get("units_per_m", 1.0))
	for c in n:
		skirt.set_root_bone_name(c, "Skirt%d_0" % c)
		skirt.set_end_bone_name(c, "Skirt%d_%d" % [c, last])
		skirt.set_extend_end_bone(c, true)
		skirt.set_end_bone_direction(c, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		skirt.set_end_bone_length(c, float(sk.get("end_length_m", 0.18)) * u)
		skirt.set_radius(c, float(sk.get("radius_m", 0.03)) * u)
		skirt.set_stiffness(c, float(sk.get("stiffness", 1.5)))
		skirt.set_drag(c, float(sk.get("drag", 0.4)))
		skirt.set_gravity(c, float(sk.get("gravity", 0.3)) * u)
		skirt.set_gravity_direction(c, Vector3.DOWN)
		skirt.set_enable_all_child_collisions(c, true)
	for col in sk.get("colliders", []):
		var b := skeleton.find_bone(String(col.get("bone", "")))
		if b < 0:
			continue
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Push_" + String(col["bone"])
		skirt.add_child(cap)   # in the tree first: the bone name resolves against the skeleton
		cap.bone_name = String(col["bone"])
		cap.bone = b
		var h := float(col.get("height_m", 0.4)) * u
		cap.radius = float(col.get("radius_m", 0.07)) * u
		cap.height = h + 2.0 * cap.radius
		cap.position_offset = Vector3(0.0, h * 0.5, 0.0)   # the bone's own +Y runs along it (Blender rig)
	# after the springs (a pose turned before them is not taken by the simulator: it swings the chains from its own state)
	var dr: Dictionary = sk.get("drive", {})
	if not dr.is_empty():
		_setup_skirt_drive(dr, n, last)


## The skirt carried by the legs before its springs (SkirtDrive; data rt3d.skirt.drive {leg_r_m, spread_m, reach_k,
## max_deg}): nothing when absent.
const SkirtDrive := preload("res://scripts/actors/skirt_drive_modifier.gd")
var skirt_drive: SkeletonModifier3D = null    # SkirtDrive


func _setup_skirt_drive(dr: Dictionary, n: int, last: int) -> void:
	var hips := skeleton.find_bone("Hips")
	var ids := ["LeftLeg", "LeftFoot", "RightLeg", "RightFoot"].map(func(b): return skeleton.find_bone(b))
	if hips < 0 or ids.has(-1) or last < 2:
		return
	skirt_drive = SkirtDrive.new()
	skirt_drive.name = "SkirtDrive"
	skeleton.add_child(skirt_drive)
	var ch: Array = []
	for c in n:
		ch.append([skeleton.find_bone("Skirt%d_0" % c), skeleton.find_bone("Skirt%d_%d" % [c, last - 1]), skeleton.find_bone("Skirt%d_%d" % [c, last])])
	skirt_drive.chains = ch
	skirt_drive.shin_bones = [[ids[0], ids[1]], [ids[2], ids[3]]]
	skirt_drive.hips_bone = hips
	var ank := (skeleton.get_bone_global_rest(ids[1]).origin + skeleton.get_bone_global_rest(ids[3]).origin) * 0.5
	skirt_drive.up = (skeleton.get_bone_global_rest(hips).origin - ank).normalized()
	skirt_drive.units_per_m = 1.0 / maxf(_skel_to_model().basis.get_scale().x, 1e-6)
	skirt_drive.leg_r_m = float(dr.get("leg_r_m", 0.075))
	skirt_drive.spread_m = float(dr.get("spread_m", 0.16))
	skirt_drive.reach_k = float(dr.get("reach_k", 1.0))
	skirt_drive.max_deg = float(dr.get("max_deg", 35.0))


## A safety net for the joints (Director 30.10, «идеальная Агата»: «иногда странные или рваные»): whatever the clips do
## — a clip switch, a fade cut short — no joint of the body turns faster than rt3d.limit_deg_s
## (LimitAngularVelocityModifier3D over all bones, right after the clips; the IKs, the look and the springs come after
## it with their own smoothing — limited, a locked foot lagged 25 mm off its spot). Fast natural motions stay well under it
## (a gesture, the walk's arm swing: up to some 600°/s); a pop of 30° in one 1/60 s frame (1800°/s) is spread over a
## few frames instead. A cut (room change, load) resets it.
var limiter: LimitAngularVelocityModifier3D = null


func _setup_limit() -> void:
	var deg := float(spec.get("limit_deg_s", 0.0))
	if deg <= 0.0:
		return
	limiter = LimitAngularVelocityModifier3D.new()
	limiter.name = "JointLimit"
	skeleton.add_child(limiter)
	limiter.exclude = true          # no chains excluded: every bone is limited
	limiter.max_angular_velocity = deg_to_rad(deg)


## The walking arms' tone (ArmToneModifier, right after the clip and the breathing; data rt3d.walk.arm_tone
## {elbow_keep, wrist_keep, abd_keep}): nothing when absent.
const ArmTone := preload("res://scripts/actors/arm_tone_modifier.gd")
var arm_tone: SkeletonModifier3D = null    # ArmTone


func _setup_arm_tone() -> void:
	var at: Dictionary = spec.get("walk", {}).get("arm_tone", {})
	if at.is_empty():
		return
	arm_tone = ArmTone.new()
	arm_tone.name = "ArmTone"
	skeleton.add_child(arm_tone)
	arm_tone.elbow_keep = float(at.get("elbow_keep", 0.55))
	arm_tone.wrist_keep = float(at.get("wrist_keep", 0.5))
	arm_tone.abd_keep = float(at.get("abd_keep", 0.5))
	arm_tone.to_model = _skel_to_model().basis.orthonormalized()
	var ab: Array = []
	var fb: Array = []
	var hb: Array = []
	var rf: Array = []
	var rh: Array = []
	for side in ["Left", "Right"]:
		ab.append(skeleton.find_bone(side + "Arm"))
		var f := skeleton.find_bone(side + "ForeArm")
		var h := skeleton.find_bone(side + "Hand")
		fb.append(f)
		hb.append(h)
		rf.append(skeleton.get_bone_rest(f).basis.get_rotation_quaternion() if f >= 0 else Quaternion.IDENTITY)
		rh.append(skeleton.get_bone_rest(h).basis.get_rotation_quaternion() if h >= 0 else Quaternion.IDENTITY)
	arm_tone.arm_bones = ab
	arm_tone.fore_bones = fb
	arm_tone.hand_bones = hb
	arm_tone.rest_fore = rf
	arm_tone.rest_hand = rh


## The standing spread of each upper arm (frontal plane, rad), from the stance as posed — the walking arm is brought in
## towards it.
func _measure_arm_ref() -> void:
	if arm_tone == null:
		return
	var ref: Array = []
	for i in 2:
		var a: int = arm_tone.arm_bones[i]
		var f: int = arm_tone.fore_bones[i]
		var d: Vector3 = arm_tone.to_model * (skeleton.get_bone_global_pose(f).origin - skeleton.get_bone_global_pose(a).origin)
		ref.append(atan2((1.0 if i == 0 else -1.0) * d.x, -d.y))
	arm_tone.abd_ref = ref


## Other things that hang and swing (Director 30.10, 23:22 — the braid and the bag on springs): each entry of
## rt3d.springs is a bone chain the rig gives it (tools/rig_skirt.py: Braid0..2 under Head) with its own
## SpringBoneSimulator3D — after the skirt, so it swings off the finished pose — and its own pushers (the back for the
## braid), so the skirt's leg capsules do not touch it. Data: {name, root, end, stiffness, drag, gravity, radius_m,
## end_length_m, colliders: [{bone, height_m, radius_m, offset_m}]}; nothing when the rig has no such bones.
var springs: Dictionary = {}       # name → SpringBoneSimulator3D


func _setup_springs() -> void:
	for sp in spec.get("springs", []):
		var root := String(sp.get("root", ""))
		var end := String(sp.get("end", ""))
		if skeleton.find_bone(root) < 0 or skeleton.find_bone(end) < 0:
			continue
		var sim := SpringBoneSimulator3D.new()
		sim.name = "Spring_" + String(sp.get("name", root))
		skeleton.add_child(sim)
		sim.setting_count = 1
		sim.set_root_bone_name(0, root)
		sim.set_end_bone_name(0, end)
		sim.set_extend_end_bone(0, true)
		sim.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		sim.set_end_bone_length(0, float(sp.get("end_length_m", 0.03)))
		sim.set_radius(0, float(sp.get("radius_m", 0.015)))
		sim.set_stiffness(0, float(sp.get("stiffness", 2.0)))
		sim.set_drag(0, float(sp.get("drag", 0.5)))
		sim.set_gravity(0, float(sp.get("gravity", 0.4)))
		sim.set_gravity_direction(0, Vector3.DOWN)
		sim.set_enable_all_child_collisions(0, true)
		for col in sp.get("colliders", []):
			var b := skeleton.find_bone(String(col.get("bone", "")))
			if b < 0:
				continue
			var cap := SpringBoneCollisionCapsule3D.new()
			cap.name = "Push_" + String(col["bone"])
			sim.add_child(cap)   # in the tree first: the bone name resolves against the skeleton
			cap.bone_name = String(col["bone"])
			cap.bone = b
			var h := float(col.get("height_m", 0.2))
			cap.radius = float(col.get("radius_m", 0.1))
			cap.height = h + 2.0 * cap.radius
			var off: Array = col.get("offset_m", [0.0, 0.0, 0.0])
			cap.position_offset = Vector3(float(off[0]), h * 0.5 + float(off[1]), float(off[2]))
		springs[String(sp.get("name", root))] = sim


## The arm kept out of the bag (Director 31.10, 00:01 «пересмотри и увидь сам, что недоработано»): the bag hangs at
## her right hip, and the clips were recorded without it — the walk's arm swing, the talk gesture and «open» put the
## right hand through it. A TwoBoneIK3D on that arm moves the hand out past the bag's outer side whenever the clip
## puts it inside the bag (a box at rest by the hips, model metres), softly, only as deep as it goes in. Data
## rt3d.bag_clear {arm, box_min_m, box_max_m, hand_r_m}.
var arm_ik: TwoBoneIK3D = null
var _arm_target: Node3D = null
var _arm_pole: Node3D = null
var _arm_w: float = 0.0
var _arm_box: AABB = AABB()
var _arm_rest_hips: Transform3D = Transform3D.IDENTITY   # the hips at rest, model space (metres)
var _arm_bones: Array = []                                # [upper arm, forearm, hand, hips]
var arm_push_m: float = 0.0                               # how deep the clip put the hand in this frame (tests)
var arm_clear_on: bool = true                             # off — probes and the tests' self-check
var arm_soft_switch: bool = true                          # off — the tests' self-check: out/behind flips in one frame, full reach
var _arm_back_s: float = 0.0                              # 0 — the hand goes out past the bag, 1 — behind it
var _arm_inf: float = 0.0                                 # the IK's weight shown
var _arm_off := Vector3.ZERO                               # the push shown (hips-at-rest frame, m) and its speed
var _arm_off_v := Vector3.ZERO
var _arm_wi: float = 0.0


## How deep a hand at `hand_m` (model space) is inside the bag, seen from hips `hips_now` (model space); 0 outside.
func bag_depth(hand_m: Vector3, hips_now: Transform3D) -> float:
	var bc: Dictionary = spec.get("bag_clear", {})
	if bc.is_empty():
		return 0.0
	var r := float(bc.get("hand_r_m", 0.04))
	var q: Vector3 = _arm_rest_hips * (hips_now.affine_inverse() * hand_m)
	if q.y < _arm_box.position.y or q.y > _arm_box.end.y or q.z < _arm_box.position.z or q.z > _arm_box.end.z:
		return 0.0
	if q.x < _arm_box.position.x - r or q.x > _arm_box.end.x:
		return 0.0
	return q.x - (_arm_box.position.x - r)


func _skel_to_model() -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _setup_arm_clear() -> void:
	var bc: Dictionary = spec.get("bag_clear", {})
	if bc.is_empty():
		return
	var side := String(bc.get("arm", "Right"))
	var names := [side + "Arm", side + "ForeArm", side + "Hand", "Hips"]
	_arm_bones = []
	for nm in names:
		var b := skeleton.find_bone(nm)
		if b < 0:
			return
		_arm_bones.append(b)
	var lo: Array = bc.get("box_min_m", [0, 0, 0])
	var hi: Array = bc.get("box_max_m", [0, 0, 0])
	var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
	_arm_box = AABB(a, Vector3(float(hi[0]), float(hi[1]), float(hi[2])) - a)
	_arm_rest_hips = _skel_to_model() * skeleton.get_bone_global_rest(int(_arm_bones[3]))
	arm_ik = TwoBoneIK3D.new()
	arm_ik.name = "ArmClear_" + side
	skeleton.add_child(arm_ik)
	arm_ik.setting_count = 1
	arm_ik.set_root_bone_name(0, names[0])
	arm_ik.set_middle_bone_name(0, names[1])
	arm_ik.set_end_bone_name(0, names[2])
	_arm_target = Node3D.new()
	_arm_target.name = "ArmTarget"
	oblique.add_child(_arm_target)
	_arm_pole = Node3D.new()
	_arm_pole.name = "ArmPole"
	oblique.add_child(_arm_pole)
	arm_ik.set_target_node(0, arm_ik.get_path_to(_arm_target))
	arm_ik.set_pole_node(0, arm_ik.get_path_to(_arm_pole))
	arm_ik.influence = 0.0


## One frame, after the pose: where the clip has the hand, seen from the hips as they stood at rest; inside the bag's
## box (grown by the hand's radius) it is moved out past the box's outer side (the side away from the body: −x for
## the right hip), the IK fading in with the depth and out as the hand leaves.
func arm_clear_step(delta: float) -> void:
	if arm_ik == null:
		return
	var bc: Dictionary = spec.get("bag_clear", {})
	var r := float(bc.get("hand_r_m", 0.04))
	var to_turn := _skel_to_turn()
	var to_model := _skel_to_model()
	var hips_now: Transform3D = to_model * skeleton.get_bone_global_pose(int(_arm_bones[3]))
	# model-space hand → as if the hips stood at rest
	var hand_m: Vector3 = to_model * skeleton.get_bone_global_pose(int(_arm_bones[2])).origin
	var q: Vector3 = _arm_rest_hips * (hips_now.affine_inverse() * hand_m)
	var outer := _arm_box.position.x if float(bc.get("out_sign", -1.0)) < 0.0 else _arm_box.end.x
	var depth := (q.x - (outer - r)) if outer == _arm_box.position.x else ((outer + r) - q.x)
	var far_side := (q.x - (_arm_box.end.x + r)) if outer == _arm_box.position.x else ((_arm_box.position.x - r) - q.x)
	# in y and z: full inside the box, fading over 3 cm outside it
	var out_yz := maxf(maxf(_arm_box.position.y - q.y, q.y - _arm_box.end.y), maxf(_arm_box.position.z - q.z, q.z - _arm_box.end.z))
	var gw := float(bc.get("gate_m", 0.05))
	var f_yz := clampf(1.0 - out_yz / gw, 0.0, 1.0)
	# every gate fades over 2 cm (01.11, line 20: gates that switched in one frame — the hand or the forearm passing the
	# bag's inner side — moved the target by centimetres at once)
	var gate_h := clampf(-far_side / gw, 0.0, 1.0) * f_yz * (1.0 if arm_clear_on else 0.0)
	var want := clampf(depth / 0.02, 0.0, 1.0) * gate_h
	arm_push_m = maxf(depth, 0.0) * (1.0 if far_side < 0.0 else 0.0) * f_yz
	# the forearm as well: its middle (half-way to the elbow) kept out too — a hand moved out past the bag with the
	# forearm still through it was half the cure (probe_arm_bag: forearm 41 mm in the bag, hand 3–6)
	var fore_m: Vector3 = to_model * skeleton.get_bone_global_pose(int(_arm_bones[1])).origin
	var qf: Vector3 = _arm_rest_hips * (hips_now.affine_inverse() * hand_m.lerp(fore_m, 0.5))
	var out_yz_f := maxf(maxf(_arm_box.position.y - qf.y, qf.y - _arm_box.end.y), maxf(_arm_box.position.z - qf.z, qf.z - _arm_box.end.z))
	var f_yz_f := clampf(1.0 - out_yz_f / gw, 0.0, 1.0)
	var depth_f := (qf.x - (outer - r)) if outer == _arm_box.position.x else ((outer + r) - qf.x)
	var far_f := (qf.x - (_arm_box.end.x + r)) if outer == _arm_box.position.x else ((_arm_box.position.x - r) - qf.x)
	var gate_f := clampf(-far_f / gw, 0.0, 1.0) * f_yz_f * (1.0 if arm_clear_on else 0.0)
	var fk := float(bc.get("forearm_k", 2.0))
	var extra := maxf(depth_f, 0.0) * fk * gate_f   # the middle of the forearm goes as far as the hand (forearm_k)
	want = maxf(want, clampf(depth_f / 0.02, 0.0, 1.0) * gate_f)
	_arm_w = move_toward(_arm_w, want, delta / 0.08)
	# out past the bag's outer side: never in towards it (the push is outward only), as deep as each part is in, gated
	# softly — the target never jumps whatever the IK's weight is
	# plus margin_m as the hand or the forearm comes near (CI 01.11: in the talk gesture the arm's reach held the hand
	# 6–11 mm short of the bag's side — the test's limit 12)
	var near0 := maxf(gate_h * clampf((depth + gw) / gw, 0.0, 1.0), gate_f * clampf((depth_f + gw) / gw, 0.0, 1.0))
	var margin := float(bc.get("margin_m", 0.0)) * near0
	var out_d := maxf(maxf(depth, 0.0) * gate_h, extra) + margin
	var sgn := -1.0 if outer == _arm_box.position.x else 1.0
	var qt := q
	qt.x = q.x + sgn * out_d
	# or behind the bag (Director 31.10, 17:45: «рука, которая у сумки, чуть более оттопырена»): standing, the hand and
	# the forearm hang over the bag's back edge — out sideways that took the arm a hand's breadth off the coat; behind
	# it, a few centimetres back. Whichever way is shorter (the forearm's middle counts double, as above).
	if bool(bc.get("behind", false)):
		var back_h := (q.z - (_arm_box.position.z - r)) * clampf(depth / 0.01, 0.0, 1.0) * gate_h
		var back_f := (qf.z - (_arm_box.position.z - r)) * fk * clampf(depth_f / 0.01, 0.0, 1.0) * gate_f
		var need_back := maxf(maxf(back_h, back_f), 0.0) + margin * clampf(maxf(back_h, back_f) / 0.01, 0.0, 1.0)
		var need_out := out_d
		# the way out changes softly (Director 01.11, line 20: «правая рука иногда резко дёргается… места не сходятся»):
		# the shorter of the two flipped as the stance swayed the hand across the line where both are equal, and the
		# target jumped 7–9 cm in one frame with the IK at full weight (tests/probe_arm_jerk.gd: 87 mm/frame² against
		# the left hand's 2). Now the choice holds until the other way is shorter by `switch_m`, and the target goes over
		# `switch_s` through the bag's back-outer corner (out and back both) — outside the bag all the way.
		var want_back := _arm_back_s > 0.5
		var hyst := float(bc.get("switch_m", 0.015))
		if need_back <= 0.0 or need_back > need_out + hyst:
			want_back = false
		elif need_back < need_out - hyst:
			want_back = true
		if not arm_soft_switch:
			want_back = need_back > 0.0 and need_back < need_out
			_arm_back_s = 1.0 if want_back else 0.0
		elif _arm_w <= 0.001:
			_arm_back_s = 1.0 if want_back else 0.0   # not pushed: nothing shown to switch from
		else:
			_arm_back_s = move_toward(_arm_back_s, 1.0 if want_back else 0.0, delta / maxf(float(bc.get("switch_s", 0.3)), 0.01))
		var sb := _arm_back_s * _arm_back_s * (3.0 - 2.0 * _arm_back_s)
		qt.x = q.x + sgn * out_d * clampf(2.0 * (1.0 - sb), 0.0, 1.0)
		qt.z = q.z - need_back * clampf(2.0 * sb, 0.0, 1.0)
	# the push itself through a quick follower (`push_omega`, 1/s): continuous, but the talk gesture's loop carries the hand
	# across its gates in a few frames — kinks of 2 cm/frame²; quick, so it never lags the hand into the bag (at 30/s the
	# hand went 15 mm in: CI 01.11)
	var off := qt - q
	if arm_soft_switch and delta > 0.0:
		var om := float(bc.get("push_omega", 60.0))
		for c in 3:
			var rs := spring(_arm_off[c], _arm_off_v[c], off[c], om, delta)
			_arm_off[c] = rs.x
			_arm_off_v[c] = rs.y
		qt = q + _arm_off
	# the IK's weight by how near the hand or the forearm is to the bag (full inside, fading over gate_m outside it):
	# continuous with the hand's own motion, and full wherever a push can be (by the push's size it was a third of the
	# way at 12 mm of push and the hand went 13 mm into the bag; on its own timer it jumped the hand 2–3 cm a frame)
	var near_h := gate_h * clampf((depth + gw) / gw, 0.0, 1.0)
	var near_f := gate_f * clampf((depth_f + gw) / gw, 0.0, 1.0)
	# walking, as before — by how deep the clip swings the hand in (_arm_w): at full weight near the bag the clearance spread
	# the swinging arm 31° (the clip's own 25°, «Walk rhythm» ≤ 28: a doll's paw held out)
	var wi := lerpf(maxf(near_h, near_f), _arm_w, clampf(_w_s, 0.0, 1.0)) if arm_soft_switch else _arm_w
	if arm_soft_switch:
		# up with the push at once, down no faster than over release_s (the gesture pulls the hand out of the box in two
		# frames: the IK's weight fell 0.9 → 0.2 and the hand jumped back onto the clip)
		_arm_wi = maxf(wi, move_toward(_arm_wi, wi, delta / maxf(float(bc.get("release_s", 0.15)), 0.01)))
		wi = _arm_wi
	_arm_inf = wi * wi * (3.0 - 2.0 * wi)
	var target_m: Vector3 = hips_now * (_arm_rest_hips.affine_inverse() * qt)
	var yaw_b := Basis(Vector3.UP, get_yaw())
	var model_to_turn := to_turn * to_model.affine_inverse()
	var sh: Vector3 = to_turn * skeleton.get_bone_global_pose(int(_arm_bones[0])).origin
	var el: Vector3 = to_turn * skeleton.get_bone_global_pose(int(_arm_bones[1])).origin
	var hd: Vector3 = to_turn * skeleton.get_bone_global_pose(int(_arm_bones[2])).origin
	var tt: Vector3 = model_to_turn * target_m
	# a soft reach (01.11, line 20): the hanging arm is nearly straight, and a target pushed out and back from the clip's
	# hand lay at or past the arm's full length — there the two-bone solution swings the elbow centimetres for a
	# millimetre of the hand (the elbow 22–53 mm/frame² standing and as the talk gesture set in, against the clip's own 2–4). The
	# target's distance from the shoulder eases into soft_k of the arm's length instead of reaching it.
	if arm_soft_switch:
		var reach := el.distance_to(sh) + hd.distance_to(el)
		var sk0 := float(bc.get("soft_k", 0.94)) * reach
		var dv := tt - sh
		var dl := dv.length()
		if dl > sk0 and reach > 1e-4:
			var rest := reach - sk0
			tt = sh + dv / dl * (sk0 + rest * (1.0 - exp(-(dl - sk0) / maxf(rest, 1e-5))))
	_arm_target.position = yaw_b * tt
	# the elbow keeps the way it bends: the pole a little beyond the elbow, away from the shoulder–hand line
	var bend := el - (sh + hd) * 0.5
	if arm_soft_switch:
		# the hanging arm is almost straight: the clip's bend is a few millimetres and its direction swung round from frame
		# to frame, the elbow with it (01.11, line 20: 30–50 mm/frame²); a little of «elbow back» (pole_back_m) keeps it
		bend += Vector3(0.0, 0.0, -float(bc.get("pole_back_m", 0.03)))
	if bend.length() < 0.01:
		bend = Vector3(0.0, 0.0, -1.0)
	_arm_pole.position = yaw_b * (el + bend.normalized() * 0.3)
	arm_ik.influence = _arm_inf


## Feet that stay where they stand (Director 30.10 «идеальная Агата»: stopping, a foot set down skated 14 cm on
## average, up to 22; turning on the spot 21, up to 25 — game/tests/test_agata_3d.gd «Feet hold the floor»): a foot
## the animation has set down is locked to its spot of the screen floor and a TwoBoneIK3D per leg keeps it there
## while the body moves, the blend changes or the stance turns; when the stance has gone on from it (step_m; turning
## step_turn_m, out of the straight leg's reach at once) it steps — lifted, carried where the stance will be a moment
## later (lead_s), set down — one foot in the air at a time; once she has come to rest it steps into the stance
## (settle_m within settle_s). It lets go when the animation lifts the foot or the full stride takes over (the
## walk's root motion keeps the planted foot there already), fading in and out. Data rt3d.feet.
var foot_ik: Array = []          # TwoBoneIK3D per leg [left, right]
var _foot_target: Array = []     # Node3D in the floor frame (under `oblique`)
var _foot_pole: Array = []
var _foot_lock: Array = [null, null]   # locked point (Vector3: screen floor x px, height m, screen floor y px) or null
var _foot_w: Array = [0.0, 0.0]
var _foot_rest_h: Array = [0.0, 0.0]


func _setup_feet() -> void:
	var fk: Dictionary = spec.get("feet", {})
	if fk.is_empty() or foot_bones.size() < 4 or foot_bones[0] < 0 or foot_bones[2] < 0:
		return
	var sides := ["Left", "Right"]
	for i in 2:
		var ik := TwoBoneIK3D.new()
		ik.name = "FootIK_" + sides[i]
		skeleton.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, sides[i] + "UpLeg")
		ik.set_middle_bone_name(0, sides[i] + "Leg")
		ik.set_end_bone_name(0, sides[i] + "Foot")
		var tg := Node3D.new()
		tg.name = "FootTarget_" + sides[i]
		oblique.add_child(tg)
		var pl := Node3D.new()
		pl.name = "KneePole_" + sides[i]
		oblique.add_child(pl)
		ik.set_target_node(0, ik.get_path_to(tg))
		ik.set_pole_node(0, ik.get_path_to(pl))
		ik.influence = 0.0
		foot_ik.append(ik)
		_foot_target.append(tg)
		_foot_pole.append(pl)
	_setup_boots()


## The boots (BootFixModifier, right after the foot IK): the feet's rest (bind) pose — how the boots were made to
## stand — and the ankle's height above the floor in it (model metres). Data rt3d.feet.boot {toe_keep, flat}.
const BootFix := preload("res://scripts/actors/boot_fix_modifier.gd")
var boot: SkeletonModifier3D = null    # BootFix
var _foot_bind_h: Array = [0.0, 0.0]


func _setup_boots() -> void:
	var bt: Dictionary = spec.get("feet", {}).get("boot", {})
	if bt.is_empty():
		return
	boot = BootFix.new()
	boot.name = "Boots"
	skeleton.add_child(boot)
	boot.toe_keep = float(bt.get("toe_keep", 0.35))
	var tm := _skel_to_model()
	boot.up = (tm.basis.inverse() * Vector3.UP).normalized()
	var fb: Array = []
	var tb: Array = []
	var rfs: Array = []
	var rhs: Array = []
	var rts: Array = []
	for i in 2:
		var f: int = foot_bones[i * 2]
		var t: int = foot_bones[i * 2 + 1]
		fb.append(f)
		tb.append(t)
		var rf: Transform3D = skeleton.get_bone_global_rest(f)
		var rt: Transform3D = skeleton.get_bone_global_rest(t) if t >= 0 else rf
		rfs.append(rf.basis.orthonormalized())
		var d: Vector3 = rt.origin - rf.origin
		var bup: Vector3 = boot.up
		var hd: Vector3 = d - bup * d.dot(bup)
		rhs.append(hd.normalized() if hd.length() > 1e-6 else Vector3.FORWARD)
		rts.append(skeleton.get_bone_rest(t).basis.get_rotation_quaternion() if t >= 0 else Quaternion.IDENTITY)
		_foot_bind_h[i] = (tm * rf.origin).y
	boot.foot_bones = fb if bool(bt.get("flat", true)) else [-1, -1]
	boot.toe_bones = tb
	boot.rest_foot = rfs
	boot.rest_heading = rhs
	boot.rest_toe_rot = rts


## Rest heights of the feet (ankle above the floor in the stance), measured once the stance is posed.
func _measure_foot_rest() -> void:
	var f := feet_model()
	_foot_rest_h = [f[0].y, f[2].y]
	if boot != null:
		# the stance's ankles above where the boots stand them: the whole figure goes down by it out of the stride
		_boot_drop = maxf(minf(f[0].y, f[2].y) - minf(float(_foot_bind_h[0]), float(_foot_bind_h[1])), 0.0)
		_foot_rest_h = [f[0].y - _boot_drop, f[2].y - _boot_drop]


var _boot_drop: float = 0.0     # metres the stance clips hold the body above its boots (rt3d.feet.boot)


## One frame of the foot locks, after the pose and the body's move: `origin_px` — where the figure stands on the
## screen floor, `px_per_m` — screen px per metre across (x) and in depth (y) at its present depth scale. A locked
## point is kept on the screen floor itself, so neither the body's move nor the figure growing as it comes nearer
## drags it. A locked foot the stance has drifted away from (turning on the spot, a new stance) is not dragged
## either: it steps — lifted in a low arc and set down where the stance wants it, one foot at a time.
var _foot_step: Array = [null, null]   # [from (screen floor point), t 0..1] while stepping


func _floor_local(p: Vector3, o: Vector2, k: Vector2) -> Vector3:
	return Vector3((p.x - o.x) / k.x, p.y, (p.z - o.y) / k.y)


func _floor_screen(p: Vector3, o: Vector2, k: Vector2) -> Vector3:
	return Vector3(o.x + p.x * k.x, p.y, o.y + p.z * k.y)


var _feet_yaw: float = 0.0
var _feet_yaw_v: float = 0.0
var _feet_still_t: float = 0.0

## Planting in the stride (data rt3d.feet.stride; with walk.root "even"): the figure goes on evenly while the clip's
## stance foot does not, so the IK holds the foot that is down where it was set: each frame the shown ankle keeps its
## spot on the screen floor, moved only as the clip rolls it over its contact — the heel while the toe is up, the ball
## while the heel is up (their own motion, weighted by how near each is to the stance floor). Off the floor the offset
## from the clip's foot fades out (air_s), so the swing ends where the clip sets the foot down.
var _st_t: Array = [null, null]          # shown ankle (screen floor point) or null
var _st_prev: Array = [null, null]       # last frame's clip [ankle, ball] (floor frame, body-relative)
var _st_w: Array = [0.0, 0.0]
## The player's planned stop (Player._planned_stop_3d): the stride planting goes on holding the feet through the stop
## and until the stance is shown, though the walk weight falls (stride_hold_keep: while the stop itself runs).
var stride_hold: bool = false
var stride_hold_keep: bool = false
var _closing: int = -1        # closing steps left after a planned stop (−1: none going on)
var _closing_t: float = 0.0
## 01.11 (Director, morning page: «при остановке — семенит, доступает»): the closing step used to wait until the stance
## had fully blended in (shown weight < 0.03) and then landed on the half-blended pose, so a settling step followed it.
## Now Player calls stop_done() the moment its planned stop ends: the feet pass from the stride planting to the locks at
## once, and the foot left behind steps straight to where the stance itself puts it (`_close_feet`, the pose at
## weight 0). The closing is dropped only when a walk is asked for again (`w_cmd`), not while the stance still blends.
var _close_feet: Array = []
var _close_unit: float = 0.0   # the body's glide still to come per unit of shown weight (pivot +z, m): the closing step reckons with it
var w_cmd: float = 0.0        # the locomotion weight asked for this frame (pose(w)), before the follower
var dbg_errs: Array = []      # probes: this frame's lock errors per foot
var dbg_reach: Array = [0.0, 0.0]   # probes: the leg's reach less the distance hip → lock, per foot
var stride_off: Array = [Vector3.ZERO, Vector3.ZERO]   # shown − clip ankle on the floor (m; tests, probes)


## A «переступ» (Player._shuffle_begin; Director 01.11, line 3 «мельтешит… куча перестановок ног»): a short move from
## standing is two steps — the lead foot (the one on the side she moves to) to where it will stand at the end, then the
## other, overlapping by `ov` of a step — each landing on a fixed spot of the floor (the stance at the end of the move,
## turned the way she will face), while the body goes over. No other step is taken and no lock let go meanwhile; the body
## dips a little (`dip`) so the legs reach both spots at the widest.
var shuffle: Dictionary = {}
var _shuffle_dip: float = 0.0
var _shuffle_grace: float = 0.0


func shuffle_begin(end_px: Vector2, yaw_f: float, t0: float, dur: float, ov: float, dip: float) -> void:
	_closing = -1
	_close_feet = []
	shuffle = {"t": 0.0, "end": end_px, "yaw": yaw_f, "t0": t0, "dur": dur, "ov": ov, "dip": dip, "started": [false, false], "land": [], "lead": -1}


## True while a foot is in the air in a step of the locks (Player waits with a «переступ» until it is down: taken over
## mid-air, the foot was set straight down to the floor and lifted again — a third lift, CI 01.11 «short move 1»).
func feet_stepping() -> bool:
	return _foot_step[0] != null or _foot_step[1] != null


## True while a step of the «переступ» is still to come or going on.
func shuffle_busy() -> bool:
	if shuffle.is_empty():
		return false
	var st: Array = shuffle["started"]
	return not (bool(st[0]) and bool(st[1])) or _foot_step[0] != null or _foot_step[1] != null


func shuffle_end() -> void:
	shuffle = {}
	_shuffle_dip = 0.0
	# just set down, the feet stay a moment whatever the stance does (CI 01.11 «short move 1: 3 lifts»: a stance variant's
	# crossfade or its own weight shift right after the «переступ» made a third step at once)
	_shuffle_grace = float(spec.get("shuffle", {}).get("grace_s", 1.0)) if not spec.is_empty() else 1.0


## Per frame, inside feet_step before the feet: the landings (first frame) and the steps' starts.
func _shuffle_feet(delta: float, f: Array, anim: Array, o: Vector2, k: Vector2) -> void:
	var sh := shuffle
	sh["t"] = float(sh["t"]) + delta
	var t: float = sh["t"]
	var dur: float = sh["dur"]
	var t0: float = sh["t0"]
	var T := t0 + dur * (2.0 - float(sh["ov"]))
	_shuffle_dip = float(sh["dip"]) * sin(PI * clampf((t - t0) / maxf(T - t0, 0.05), 0.0, 1.0))
	if (sh["land"] as Array).is_empty():
		var yb := Basis(Vector3.UP, float(sh["yaw"]))
		var end: Vector2 = sh["end"]
		var land: Array = []
		var cur: Array = []
		for i in 2:
			land.append(_floor_screen(yb * (f[i * 2] as Vector3), end, k))
			cur.append(_floor_local(_foot_lock[i], o, k) if _foot_lock[i] != null else (anim[i] as Vector3))
		sh["land"] = land
		var dl := Vector2((end.x - o.x) / k.x, (end.y - o.y) / k.y)
		var mid: Vector3 = ((cur[0] as Vector3) + (cur[1] as Vector3)) * 0.5
		var lead := 0
		if dl.length() > 0.03:
			# the foot on the side she moves to goes first (moving right, the right foot): the feet never cross
			var d0 := Vector2((cur[0] as Vector3).x - mid.x, (cur[0] as Vector3).z - mid.z).dot(dl)
			lead = 0 if d0 >= 0.0 else 1
		else:
			# turning on the spot: the foot that has farther to go
			var e0 := Vector2(_floor_local(land[0], o, k).x - (cur[0] as Vector3).x, _floor_local(land[0], o, k).z - (cur[0] as Vector3).z).length()
			var e1 := Vector2(_floor_local(land[1], o, k).x - (cur[1] as Vector3).x, _floor_local(land[1], o, k).z - (cur[1] as Vector3).z).length()
			lead = 0 if e0 >= e1 else 1
		sh["lead"] = lead
	var lead_i: int = sh["lead"]
	var started: Array = sh["started"]
	for i in [lead_i, 1 - lead_i]:
		var start := t0 if i == lead_i else t0 + dur * (1.0 - float(sh["ov"]))
		if bool(started[i]) or t < start:
			continue
		started[i] = true
		var from: Vector3 = _foot_lock[i] if _foot_lock[i] != null else _floor_screen(anim[i], o, k)
		_foot_step[i] = [from, 0.0, _planted_y(i, anim[i]), Vector3.ZERO, dur, sh["land"][i]]


func _stride_plant(i: int, a: Vector3, b: Vector3, delta: float, o: Vector2, k: Vector2, sk: Dictionary) -> void:
	var lo := 0.008
	var hi := float(sk.get("down_m", 0.025))
	# down when the *clip* has the foot down (01.11, the stop: blended with the stance the swing foot came to floor level
	# while the clip still carried it forward — planted there, it was dragged back under the body (or the body pulled
	# back to it); now it is held only from the clip's own heel strike, and until then kept a little up, as the clip has it)
	var ha := a.y - float(stride_floor[i * 2])
	var hb := b.y - float(stride_floor[i * 2 + 1])
	var has_clip := clip_feet_h.size() >= 4   # no walk table (an actor without a walk clip): the blended heights, as before
	var ca := clip_foot_h(i * 2, _shown_phase) if has_clip else ha
	var cb := clip_foot_h(i * 2 + 1, _shown_phase) if has_clip else hb
	var wa := 1.0 - smoothstep(lo, hi, ca)
	var wb := 1.0 - smoothstep(lo, hi, cb)
	var p := maxf(wa, wb)
	var lift := maxf(minf(ca, cb) - minf(ha, hb), 0.0) * float(sk.get("lift_keep", 0.6)) * (1.0 - p)
	var off := Vector3.ZERO
	if _st_t[i] != null:
		off = _floor_local(_st_t[i], o, k) - a
		var planted := off
		var air := off
		if _st_prev[i] != null:
			var da: Vector3 = a - (_st_prev[i][0] as Vector3)
			var db: Vector3 = b - (_st_prev[i][1] as Vector3)
			var dc := da if wa + wb < 1e-3 else (da * wa + db * wb) / (wa + wb)
			# planted: the old spot (the body has moved on under it) rolled by the ankle's motion about the contact
			planted = off + da - dc
			# in the air: back towards the clip's foot
			air = (stride_off[i] as Vector3) * exp(-delta / maxf(float(sk.get("air_s", 0.08)), 0.01))
		off = air.lerp(planted, p)
		off.y = 0.0
		off = off.limit_length(float(sk.get("max_m", 0.12)))
	stride_off[i] = off
	_st_t[i] = _floor_screen(a + off + Vector3(0.0, lift, 0.0), o, k)
	_st_prev[i] = [a, b]


## Where a set-down ankle stands: with boots, at its height in the boots' own pose (the stance clips held it 4 cm
## higher — the soles off the floor), plus whatever the clip lifts it above its stance; without, as the clip has it.
func _planted_y(i: int, a: Vector3) -> float:
	if boot == null:
		return a.y
	return float(_foot_bind_h[i]) + maxf(a.y - float(_foot_rest_h[i]), 0.0)


func feet_step(delta: float, origin_px: Vector2, px_per_m: Vector2) -> void:
	if foot_ik.is_empty():
		return
	var fk: Dictionary = spec.get("feet", {})
	var f := feet_model()
	var yaw := get_yaw()
	var yaw_b := Basis(Vector3.UP, yaw)
	# how fast the body turns: a step goes where the stance will be a moment later (into the turn), as people step
	_feet_yaw_v = lerpf(_feet_yaw_v, angle_difference(_feet_yaw, yaw) / maxf(delta, 1e-4), clampf(delta * 20.0, 0.0, 1.0))
	_feet_yaw = yaw
	var lead_b := Basis(Vector3.UP, yaw + _feet_yaw_v * float(fk.get("lead_s", 0.12)))
	var turning := absf(_feet_yaw_v) > 0.6
	var walking := _w_s > float(fk.get("walk_off", 0.97)) or stride_hold
	# block 3 (Director 06.11, 12:30: «Митя и Пелагея постоянно дёргаются, мельтешат»): a whole-body action clip (act_body
	# full — the villager bends for the lantern, hauls the rope, tars the boat) moves the legs itself; the foot locks
	# fought it and stepped 6–16 times in one action. While such a clip is shown the feet follow it, the locks let go;
	# after it they are set where the feet stand, and one step brings them back to the stance if needed.
	var act_free := feet_free_in_acts and act_body_full.has(_act_name) and _a_s > 0.05
	if stride_hold and _w_s < 0.03 and not stride_hold_keep:
		stride_hold = false   # the stance is in: the locks take the feet from the stride planting
		_closing = 1          # after a planned stop: the foot left behind closes up — one step, not a shuffle
		_closing_t = 0.0
		_close_feet = []
	if _closing >= 0:
		_closing_t += delta
		if w_cmd > 0.05:
			_closing = -1   # walking again (or stepping round on the spot: the turn's own steps)
			_close_feet = []
	# the closing step lands where the stance puts the foot, not where the half-blended pose has it this frame
	var closing_to: Array = _close_feet if (_closing > 0 and _close_feet.size() >= 4) else []
	var o := origin_px
	var k := Vector2(maxf(px_per_m.x, 1e-3), maxf(px_per_m.y, 1e-3))
	var step_s := maxf(float(fk.get("step_s", 0.24)), 0.05)
	var sk: Dictionary = fk.get("stride", {})
	var stride_on := not sk.is_empty() and bool(sk.get("on", true))
	var anim: Array = []
	var locks: Array = []
	var errs: Array = []
	var targets: Array = []
	var from_y: Array = [-INF, -INF]   # a closing step sets off from the height the stride held the foot at (heel up)
	var xf := _skel_to_turn()
	if not shuffle.is_empty():
		var an: Array = []
		for i in 2:
			an.append(yaw_b * (f[i * 2] as Vector3) - Vector3(0.0, _bob_y, 0.0))
		_shuffle_feet(delta, f, an, o, k)
	for i in 2:
		var a: Vector3 = yaw_b * f[i * 2]                     # the animated ankle in the floor frame
		a.y -= _bob_y                                         # where the clip has it: the deepened bob is the body's only
		anim.append(a)
		if stride_on and walking and _st_t[i] == null:
			# into the stride: a foot held (locked or stepping) goes on being held where it is shown
			_st_t[i] = _foot_lock[i]
			_st_prev[i] = null
			_st_w[i] = float(_foot_w[i])
		if stride_on and (walking or float(_st_w[i]) > 0.0):
			_stride_plant(i, a, yaw_b * f[i * 2 + 1] - Vector3(0.0, _bob_y, 0.0), delta, o, k, sk)
		# the leg's reach from the hip (thigh + shin as posed, a little short of straight)
		var side := "Left" if i == 0 else "Right"
		var hip: Vector3 = yaw_b * (xf * skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpLeg")).origin)
		var knee: Vector3 = yaw_b * (xf * skeleton.get_bone_global_pose(skeleton.find_bone(side + "Leg")).origin)
		var reach: float = ((knee - hip).length() + (a - knee).length()) * float(fk.get("reach", 1.0))
		var lifted: bool = a.y > float(_foot_rest_h[i]) + float(fk.get("lift_m", 0.035))
		if _closing >= 0 and _a_s < 0.05:
			lifted = false   # after a stop the toe-off of the last stride blends out of the pose: not a lift, the lock holds
		var lock = null if _foot_lock[i] == null else _floor_local(_foot_lock[i], o, k)
		var st = _foot_step[i]
		var err := 0.0
		if st != null:
			# stepping: from the old spot (fixed on the floor) to where the stance wants the foot
			st[1] = minf(float(st[1]) + delta / (float(st[4]) if st.size() > 4 else step_s), 1.0)
			var u: float = st[1]
			# lifted first, carried, set down: the foot leaves and meets the floor going straight up and down
			var h := clampf((u - 0.15) / 0.7, 0.0, 1.0)
			var e := h * h * (3.0 - 2.0 * h)
			# the landing spot was chosen as the foot left the floor (st[3], by the body, the turn foreseen): a foot that
			# follows a spot turning with her and then stops dead on it jolts (17.6 mm per frame turning on the spot)
			var to: Vector3 = st[3]
			if st.size() > 5:
				to = _floor_local(st[5], o, k)   # a «переступ»: a fixed spot of the floor, whatever the body does meanwhile
			elif _w_v > 0.0 and _w_s > 0.02:
				# setting off, this step is the stride's first swing: it lands where the stride sets the foot down, not
				# where the stance stood as it left (it then stood 10–12 cm behind its foot and stepped again at once)
				to = to.lerp(Vector3(a.x, to.y, a.z), smoothstep(0.02, 0.2, _w_s))
			var pos: Vector3 = _floor_local(st[0], o, k).lerp(to, e)
			pos.y = lerpf(float(st[2]), _planted_y(i, a), e) + float(fk.get("step_lift_m", 0.05)) * sin(PI * u)
			lock = pos
			if u >= 1.0 or walking or lifted:
				st = null
				lock = null if (walking or lifted) else lock
			_foot_step[i] = st
		elif lock != null:
			err = Vector2(lock.x - a.x, lock.z - a.z).length()
			if not closing_to.is_empty():
				# measured against the stance she is coming to, where it will stand once the body's glide is over
				var ac: Vector3 = yaw_b * ((closing_to[i * 2] as Vector3) + Vector3(0.0, 0.0, _close_unit * _w_s))
				err = Vector2(lock.x - ac.x, lock.z - ac.z).length()
			dbg_reach[i] = reach - Vector3(lock.x, _planted_y(i, a), lock.z).distance_to(hip)
			if lifted or walking or act_free or (err > float(fk.get("release_m", 0.3)) and shuffle.is_empty()):
				lock = null
				err = 0.0
			elif _out_of_reach(Vector3(lock.x, _planted_y(i, a), lock.z), hip, reach):
				# the body has gone on past the leg's reach: the leg straightens, the heel comes up — and this foot
				# steps first
				err = maxf(err, 10.0)
		elif not lifted and not walking and not act_free and float(_foot_w[i]) <= 0.001:
			lock = Vector3(a.x, a.y, a.z)
			if _st_t[i] != null and float(_st_w[i]) > 0.0:
				# out of the stride: locked where the stride planting holds it, the IK staying on
				var held := _floor_local(_st_t[i], o, k)
				lock = Vector3(held.x, a.y, held.z)
				from_y[i] = held.y
				_foot_w[i] = _st_w[i]
				_st_w[i] = 0.0
				_st_t[i] = null
				_st_prev[i] = null
				stride_off[i] = Vector3.ZERO
			if not closing_to.is_empty():
				# after a stop the foot left behind may step in this same frame — no setting its heel down first
				var ac0: Vector3 = yaw_b * ((closing_to[i * 2] as Vector3) + Vector3(0.0, 0.0, _close_unit * _w_s))
				err = Vector2(lock.x - ac0.x, lock.z - ac0.z).length()
		locks.append(lock)
		errs.append(err)
		# held at the lock's spot, at the height a set-down foot stands at
		targets.append(null if lock == null else (lock if _foot_step[i] != null else Vector3(lock.x, _planted_y(i, a), lock.z)))
	dbg_errs = errs.duplicate()
	# a foot the stance has moved away from steps after it — the farther one first, one foot in the air at a time
	# (the next may leave as the other is being set down)
	# once she has come to rest after a turn or a stop, a foot left off its stance steps into place once more
	var still := not turning and _w_s < 0.05
	_feet_still_t = (_feet_still_t + delta) if still else 0.0
	var settling := _feet_still_t > 0.15 and _feet_still_t < float(fk.get("settle_s", 0.8))
	var need := float(fk.get("step_turn_m", 0.035)) if turning else (float(fk.get("settle_m", 0.035)) if settling else float(fk.get("step_m", 0.07)))
	_shuffle_grace = maxf(_shuffle_grace - delta, 0.0) if w_cmd < 0.05 else 0.0
	var first := 0 if float(errs[0]) >= float(errs[1]) else 1
	for i in [first, 1 - first]:
		var other = _foot_step[1 - i]
		var need_i := need
		if _closing > 0 and not closing_to.is_empty():
			need_i = float(fk.get("close_need_m", 0.03))   # the closing step itself: taken even from a little behind
		elif _closing == 0 and not turning:
			need_i = maxf(need, float(fk.get("close_m", 0.15)))   # closed up: the other foot stays unless far off
		if _shuffle_grace > 0.0:
			need_i = maxf(need_i, float(fk.get("close_m", 0.15)))
		if _foot_step[i] == null and locks[i] != null and float(errs[i]) > need_i and (other == null or float(other[1]) >= 0.75) and shuffle.is_empty():
			var dur := step_s
			if _closing > 0:
				_closing -= 1
				dur = maxf(float(fk.get("close_step_s", step_s)), 0.05)   # closing up after a stop: an unhurried step
			# it leaves from the height it stands at now (the lock or the stance, whichever is higher — as drawn)
			# and lands where the stance will be when it is set down (the turn going on at its present speed)
			var t_land := float(fk.get("lead_s", 0.08)) + step_s * 0.85
			var land_b := Basis(Vector3.UP, yaw + _feet_yaw_v * t_land)
			var land_src: Vector3 = closing_to[i * 2] if not closing_to.is_empty() else f[i * 2]
			var land := _clear_of_other(land_b * land_src, i, yaw_b, f, o, k, float(fk.get("min_sep_m", 0.12)))
			# kept by the body (it goes with her as she still comes to a stop), not turned with her
			var y0 := _planted_y(i, anim[i])
			var u0 := 0.0
			if float(from_y[i]) > y0 + 0.01:
				y0 = float(from_y[i])   # the closing step: the heel is already up from the toe-off — no setting it down first
				u0 = 0.15
			_foot_step[i] = [_floor_screen(locks[i], o, k), u0, y0, land, dur]
			if u0 > 0.0:
				targets[i] = Vector3((locks[i] as Vector3).x, y0 + float(fk.get("step_lift_m", 0.05)) * sin(PI * u0), (locks[i] as Vector3).z)
	for i in 2:
		var lock = locks[i]
		var a: Vector3 = anim[i]
		_foot_lock[i] = null if lock == null else _floor_screen(lock, o, k)
		var want := 1.0 if lock != null else 0.0
		_foot_w[i] = move_toward(float(_foot_w[i]), want, delta / maxf(float(fk.get("fade_s", 0.12)), 0.01))
		var w: float = _foot_w[i]
		_st_w[i] = move_toward(float(_st_w[i]), 1.0 if (stride_on and walking) else 0.0, delta / maxf(float(fk.get("fade_s", 0.12)), 0.01))
		if float(_st_w[i]) <= 0.0:
			_st_t[i] = null
			_st_prev[i] = null
			stride_off[i] = Vector3.ZERO
		var sw: float = _st_w[i] if _st_t[i] != null else 0.0
		if lock != null:
			(_foot_target[i] as Node3D).position = targets[i]
		elif sw > 0.0:
			(_foot_target[i] as Node3D).position = _floor_local(_st_t[i], o, k)
		elif w > 0.0:
			# fading out: the target slides back to the animated foot
			var t: Vector3 = (_foot_target[i] as Node3D).position
			(_foot_target[i] as Node3D).position = t.lerp(a, clampf(delta / 0.08, 0.0, 1.0))
		# the knee points the way the body faces
		var knee: Vector3 = yaw_b * (_skel_to_turn() * skeleton.get_bone_global_pose(skeleton.find_bone(("Left" if i == 0 else "Right") + "Leg")).origin)
		(_foot_pole[i] as Node3D).position = knee + yaw_b * Vector3(0.0, 0.0, 0.6)
		var wi := maxf(w, sw)
		(foot_ik[i] as TwoBoneIK3D).influence = wi * wi * (3.0 - 2.0 * wi)
		if boot != null:
			# the boot flat on the floor while set down: locked (lifted off in a step's middle), or in the stride while
			# the clip's ankle is down at the height the boots stand at
			var bw := 0.0
			if lock != null:
				bw = w * (1.0 - (sin(PI * float(_foot_step[i][1])) if _foot_step[i] != null else 0.0))
			else:
				bw = clampf((float(_foot_bind_h[i]) + 0.035 - a.y) / 0.02, 0.0, 1.0) * (1.0 - w)
			boot.weights[i] = move_toward(float(boot.weights[i]), bw, delta / 0.06)


## A step's landing kept clear of the other foot: turning far on the spot the stance comes round to where the other
## foot still stands — the step stops short beside it instead of landing on it (the feet crossed into one line).
func _clear_of_other(to: Vector3, i: int, yaw_b: Basis, f: Array, o: Vector2, k: Vector2, min_sep: float) -> Vector3:
	var other: Vector3 = _floor_local(_foot_lock[1 - i], o, k) if _foot_lock[1 - i] != null else yaw_b * f[(1 - i) * 2]
	var d := Vector2(to.x - other.x, to.z - other.z)
	if d.length() >= min_sep:
		return to
	if d.length() < 1e-4:
		var side := yaw_b * Vector3(1.0 if i == 1 else -1.0, 0.0, 0.0)   # left foot on her left
		d = Vector2(side.x, side.z)
	d = d.normalized() * min_sep
	return Vector3(other.x + d.x, to.y, other.z + d.y)


func _out_of_reach(p: Vector3, hip: Vector3, reach: float) -> bool:
	return p.distance_to(hip) > reach


## A cut (room change, load): the feet stand where the new pose puts them.
func feet_reset() -> void:
	if limiter != null:
		limiter.reset()
	_arm_off = Vector3.ZERO
	_arm_off_v = Vector3.ZERO
	_arm_wi = 0.0
	shuffle = {}
	_shuffle_dip = 0.0
	_shuffle_grace = 0.0
	stride_hold = false
	stride_hold_keep = false
	_closing = -1
	_close_feet = []
	_calm_lp = Vector2.INF
	_calm_off = Vector2.ZERO
	for i in 2:
		_foot_lock[i] = null
		_foot_step[i] = null
		_foot_w[i] = 0.0
		_st_t[i] = null
		_st_prev[i] = null
		_st_w[i] = 0.0
		stride_off[i] = Vector3.ZERO
	_feet_yaw = get_yaw()
	_feet_yaw_v = 0.0
	for ik in foot_ik:
		(ik as TwoBoneIK3D).influence = 0.0


## Where the eyes go (Director 30.10, 19:16 «как сделать идеальную Агату»: she looks at the one who speaks and at what
## she goes to): a LookAtModifier3D on the head, after the clip, the breathing and the skirt; the head turns softly
## towards a point (duration, eased) within the neck's limits, the influence fades in and out with the follower.
## Data rt3d.look {weight, duration_s, yaw_limit_deg, pitch_limit_deg}; nothing when absent.
var look: LookAtModifier3D = null
var look_target: Node3D = null
var _look_on: bool = false
var _look_w: float = 0.0
var _look_v: float = 0.0


func _setup_look() -> void:
	var lk: Dictionary = spec.get("look", {})
	if lk.is_empty() or skeleton.find_bone("Head") < 0:
		return
	look_target = Node3D.new()
	look_target.name = "LookTarget"
	oblique.add_child(look_target)
	look = LookAtModifier3D.new()
	look.name = "Look"
	skeleton.add_child(look)
	look.bone_name = "Head"
	look.bone = skeleton.find_bone("Head")
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z     # the face looks along the head's +Z (Meshy rig)
	look.primary_rotation_axis = Vector3.AXIS_Y
	look.use_secondary_rotation = true
	look.relative = false   # aims from the rest pose: while she looks at someone the head holds steady
	look.duration = float(lk.get("duration_s", 0.5))
	look.transition_type = Tween.TRANS_SINE
	look.ease_type = Tween.EASE_IN_OUT
	look.use_angle_limitation = true
	look.symmetry_limitation = true
	look.primary_limit_angle = deg_to_rad(float(lk.get("yaw_limit_deg", 60.0)))
	look.primary_damp_threshold = 1.0
	look.secondary_limit_angle = deg_to_rad(float(lk.get("pitch_limit_deg", 25.0)))
	look.secondary_damp_threshold = 1.0
	look.target_node = look.get_path_to(look_target)
	look.influence = 0.0


## The point to look at, in the floor frame (x right, y up, z towards the viewer; metres from the feet), or off.
var _look_weight: float = -1.0   # this look's share of the head turn (< 0: rt3d.look.weight)


var _look_goal := Vector3.ZERO
var _look_vel := Vector3.ZERO


## Where to look (floor frame, metres from her feet): the point itself glides there (a critically damped follower,
## look.target_omega) — a new target while she already looks somewhere (the stance's gaze → the one who speaks) used to
## jump, and the head turned 8° in a frame.
func set_look(p_floor: Vector3, on: bool, weight: float = -1.0) -> void:
	if look == null:
		return
	if on and (not _look_on or _look_w < 0.02):
		look_target.position = p_floor      # from looking nowhere: the influence fades in, the point can start there
		_look_vel = Vector3.ZERO
	_look_on = on
	_look_weight = weight
	if on:
		_look_goal = p_floor


func _advance_look(delta: float) -> void:
	if look == null:
		return
	var w := (_look_weight if _look_weight >= 0.0 else float(spec.get("look", {}).get("weight", 0.8))) if _look_on else 0.0
	if delta > 0.0:
		var r := spring(_look_w, _look_v, w, float(spec.get("look", {}).get("fade_omega", 6.0)), delta)
		_look_w = r.x
		_look_v = r.y
	look.influence = clampf(_look_w, 0.0, 1.0)
	if _look_on and delta > 0.0:
		var om := float(spec.get("look", {}).get("target_omega", 5.0))
		var p := look_target.position
		for ax in 3:
			var r2 := spring(p[ax], _look_vel[ax], _look_goal[ax], om, delta)
			p[ax] = r2.x
			_look_vel[ax] = r2.y
		look_target.position = p


## A critically damped follower, exact for any step: position and velocity after `dt` going to `target`
## (no overshoot, velocity continuous whatever the target does).
static func spring(x: float, v: float, target: float, omega: float, dt: float) -> Vector2:
	var y := x - target
	var j := v + omega * y
	var e := exp(-omega * dt)
	return Vector2(target + (y + j * dt) * e, (v - omega * j * dt) * e)


## One frame of a body turn: the yaw speed follows the speed wanted for the angle left (an eased approach, capped,
## and never faster than can be stopped in time) and changes by at most `accel` per second² — a turn sets off and
## settles softly, whatever the angle. `state` = (yaw, yaw speed, turning way −1/0/+1, target); returns the next state.
## The way is the cheaper of the two counting the body's momentum — the angle along it, plus braking and coming back
## when the body turns the other way now — and it changes only when the other is cheaper by 30° (Director 30.10,
## 19:16: «крутится на 360, прежде чем повернуться в нужную сторону»: a body carried past its target by braking, or
## past «straight behind», took the way round the whole circle).
static func turn_step(state: Vector4, target: float, delta: float, cap: float, ease: float, accel: float) -> Vector4:
	var yaw := state.x
	var v := state.y
	var dir := state.z
	var d := angle_difference(yaw, target)
	var l_pos := fposmod(d, TAU)                     # going +: [0, 2π)
	var l_neg := l_pos - TAU if l_pos > 0.0 else 0.0  # going −: (−2π, 0]
	var brake := v * v / (2.0 * maxf(accel, 0.01))
	var c_pos := l_pos + (2.0 * brake if v < -0.05 else 0.0)
	var c_neg := -l_neg + (2.0 * brake if v > 0.05 else 0.0)
	var best := 1.0 if c_pos <= c_neg else -1.0
	if dir == 0.0 or (best != dir and absf(c_pos - c_neg) > deg_to_rad(30.0)):
		dir = best
	var left := l_pos if dir > 0.0 else l_neg
	var want := signf(left) * minf(minf(cap, absf(left) * ease), sqrt(2.0 * accel * absf(left)))
	v = move_toward(v, want, accel * delta)
	yaw = wrapf(yaw + v * delta, -PI, PI)
	if absf(d) < deg_to_rad(0.5) and absf(v) < 0.05:
		dir = 0.0
	return Vector4(yaw, v, dir, target)


## Times of a clip played as a seamless loop (`tau` seconds since it started; clip `len_s`, crossfade `xf`):
## [time in the act slot, time in act2, mix 0..1 towards act2]. Each pass starts `len_s − xf` after the last;
## while one pass ends the next one fades in (smoothstep), so no seam is ever seen.
static func loop_times(tau: float, len_s: float, xf: float) -> Array:
	xf = clampf(xf, 0.0, len_s * 0.45)
	var period := maxf(len_s - xf, 0.05)
	var k := floorf(maxf(tau, 0.0) / period)
	var u := maxf(tau, 0.0) - k * period
	if k >= 1.0 and u < xf and xf > 0.0:
		var m := u / xf
		return [u + period, u, m * m * (3.0 - 2.0 * m)]
	return [u, 0.0, 0.0]


## Talking and listening with the hands and the head, the body kept (Director 01.11, line 6: «фигура Павла, когда Агата
## с ним говорит, слишком резко меняющаяся… изгиб не совсем естественный, разом выпирает»; line 10: Pelageya «тело
## само её кидает из стороны в сторону»): every villager's talk clip (Talk_with_Hands_Open) pushes the hips 7–12 cm out
## to the side and forward, leans the torso 5° back (the belly «выпирает»), bends the knees to 49° and turns both toes
## up 18–27° (tests/probe_villager_motion.gd). Data rt3d.act_body {keep, bones}: the listed bones (hips, spine, legs)
## take only `keep` of the action clip, the arms, the neck and the head all of it (a second Blend2 with track filters).
var act_body_k: float = -1.0     # < 0: no act_body — the action clip drives every bone alike
var _gate := 1.0   # the action weight's gate while one clip gives way to the next (pose)
var act_body_full: Dictionary = {}   # act_body.full: roles whose clip moves the whole body (block 3: hug, crank, kneel)
var feet_free_in_acts := true        # block 3: the foot locks let go during those clips (off — the tests' self-check)


func _act_body_now() -> float:
	return 1.0 if act_body_full.has(_act_name) else act_body_k


func _setup_act_body(bt: AnimationNodeBlendTree, actb: AnimationNodeBlend2) -> bool:
	var ab: Dictionary = spec.get("act_body", {})
	if ab.is_empty():
		return false
	var body := {}
	for b in ab.get("bones", ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]):
		body[String(b)] = true
	# Director 06.11, 15:56 («остальных тоже коробит»): the talk clip drops the head every gesture — the neck and the
	# head (act_body.upper) are kept at `keep` too. Not the shoulders: a stance shoulder under the clip's arm spreads the
	# arms like a scarecrow (Nina listening 44°, tests/probe_villager_arm_spread.gd)
	for b in ab.get("upper", []):
		body[String(b)] = true
	var paths := {}
	for role in clips.keys():
		var a := anim.get_animation(clips[role])
		if a == null:
			continue
		for i in a.get_track_count():
			paths[a.track_get_path(i)] = true
	for e in idle_pool:
		var a2 := anim.get_animation(e["name"])
		for i in a2.get_track_count():
			paths[a2.track_get_path(i)] = true
	var actb_body := AnimationNodeBlend2.new()
	actb.filter_enabled = true
	actb_body.filter_enabled = true
	for p in paths.keys():
		var np: NodePath = p
		var bone := String(np.get_concatenated_subnames())
		if body.has(bone):
			actb_body.set_filter_path(np, true)
		else:
			actb.set_filter_path(np, true)
	# a node's output feeds one input only: the body branch has its own copy of the action slots (same clip, same times)
	for slot in ["act_b", "act2_b"]:
		var an := AnimationNodeAnimation.new()
		an.animation = idle_pool[0]["name"]
		bt.add_node(slot, an)
		bt.add_node(slot + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(slot + "_seek", 0, slot)
	bt.add_node("act_mix_b", AnimationNodeBlend2.new())
	bt.connect_node("act_mix_b", 0, "act_b_seek")
	bt.connect_node("act_mix_b", 1, "act2_b_seek")
	bt.add_node("actb_body", actb_body)
	bt.connect_node("actb_body", 0, "actb")
	bt.connect_node("actb_body", 1, "act_mix_b")
	act_body_k = clampf(float(ab.get("keep", 0.3)), 0.0, 1.0)
	for r in ab.get("full", []):
		act_body_full[String(r)] = true
	return true


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "Tree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	var bt := AnimationNodeBlendTree.new()
	for slot in ["idle_a", "idle_b", "walk", "act", "act2"]:
		var a := AnimationNodeAnimation.new()
		a.animation = clips.get("walk", idle_pool[0]["name"]) if slot == "walk" else idle_pool[0]["name"]
		bt.add_node(slot, a)
		var s := AnimationNodeTimeSeek.new()
		bt.add_node(slot + "_seek", s)
		bt.connect_node(slot + "_seek", 0, slot)
	var idle_mix := AnimationNodeBlend2.new()
	bt.add_node("idle_mix", idle_mix)
	bt.connect_node("idle_mix", 0, "idle_a_seek")
	bt.connect_node("idle_mix", 1, "idle_b_seek")
	var loco := AnimationNodeBlend2.new()
	bt.add_node("loco", loco)
	bt.connect_node("loco", 0, "idle_mix")
	bt.connect_node("loco", 1, "walk_seek")
	var act_mix := AnimationNodeBlend2.new()
	bt.add_node("act_mix", act_mix)
	bt.connect_node("act_mix", 0, "act_seek")
	bt.connect_node("act_mix", 1, "act2_seek")
	var actb := AnimationNodeBlend2.new()
	bt.add_node("actb", actb)
	bt.connect_node("actb", 0, "loco")
	bt.connect_node("actb", 1, "act_mix")
	if _setup_act_body(bt, actb):
		bt.connect_node("output", 0, "actb_body")
	else:
		bt.connect_node("output", 0, "actb")
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true


## Same height on screen as the sprite figure at any elevation: the sheets are a 14° ortho render at
## frame_h / (height × margin) px per metre; a standing figure projects to height × cos(elevation).
func _ppm_for(deg: float) -> float:
	return float(spec.get("sheet_ppm", 214.8)) * cos(deg_to_rad(14.0)) / cos(deg_to_rad(deg))


## True when the data asks for the room's own elevation (camera_elev_deg "room").
func follows_room() -> bool:
	return typeof(spec.get("camera_elev_deg", 14.0)) == TYPE_STRING


## New camera elevation (degrees): scale and camera placement follow.
func set_elevation(deg: float) -> void:
	deg = clampf(deg, 5.0, 60.0)
	if is_equal_approx(deg, elev_deg) and camera != null:
		return
	elev_deg = deg
	ppm = _ppm_for(deg)
	if camera != null:
		_place_camera()


## Orthographic camera at the elevation, looking at the figure so that the feet (origin) land on the
## pivot pixel of the frame.
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 50.0
	add_child(camera)
	camera.current = true
	_place_camera()
	set_render_scale(1.0)


func _place_camera() -> void:
	camera.size = frame_px.y / ppm
	var e := deg_to_rad(elev_deg)
	var up := Vector3(0, cos(e), -sin(e))
	var back := Vector3(0, sin(e), cos(e))
	var target := up * ((pivot.y - 0.5) * camera.size)
	target.x = -(pivot.x - 0.5) * frame_px.x / ppm
	camera.transform = Transform3D(Basis.looking_at(-back, up), target + back * 10.0)


## Texture px per sheet px: the frame is rendered at about the size it takes on screen.
func set_render_scale(q: float) -> void:
	var step := 0.125
	q = clampf(round(q / step) * step, float(spec.get("min_render_scale", 0.5)), float(spec.get("max_render_scale", 3.0)))
	if is_equal_approx(q, render_scale) and _sized:
		return
	_sized = true
	render_scale = q
	size = Vector2i(int(round(frame_px.x * q)), int(round(frame_px.y * q)))


## Where a bone is in this frame's texture (px), as the camera sees it; Vector2.INF without it. Директор 01.11,
## стр. 59: the fishing rod comes out of Agata's hand (FishingPanel → Player.bone_screen).
func bone_frame_px(bone: String) -> Vector2:
	if skeleton == null or camera == null:
		return Vector2.INF
	var b := skeleton.find_bone(bone)
	if b < 0:
		return Vector2.INF
	var p: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
	return camera.unproject_position(p)


## Sprite2D offset/scale that put this texture's pivot at the parent's origin, frame in sheet px.
func sprite_offset() -> Vector2:
	return -Vector2(pivot.x * size.x, pivot.y * size.y)


func set_yaw(yaw: float) -> void:
	turn.rotation = Vector3(0, yaw, 0)


func get_yaw() -> float:
	return turn.rotation.y


# --- Idle variants ----------------------------------------------------------------------------

func _pick_idle(prev: String) -> Dictionary:
	if idle_pool.size() == 1:
		return idle_pool[0]
	var total := 0.0
	for e in idle_pool:
		if e["name"] != prev or bool(spec.get("idle", {}).get("allow_repeat", false)):
			total += float(e["weight"])
	var r := _idle_rng.randf() * total
	for e in idle_pool:
		if e["name"] == prev and not bool(spec.get("idle", {}).get("allow_repeat", false)):
			continue
		r -= float(e["weight"])
		if r <= 0.0:
			return e
	return idle_pool[0]


func _start_idle_slot(slot: int, e: Dictionary, t0: float) -> void:
	var a := anim.get_animation(e["name"])
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node("idle_a" if slot == 0 else "idle_b") as AnimationNodeAnimation
	node.animation = e["name"]
	var L := a.length
	_slot_name[slot] = e["name"]
	_slot_t[slot] = L * float(e.get("from", 0.0)) + t0
	_slot_len[slot] = L * float(e.get("to", 1.0))
	_slot_active = slot


## Data `idle.desync` {slot, phase, rate_jitter}: this figure's idle starts at its own point of the clip and
## plays a few percent faster or slower. `slot` (unique per villager) places the figure on a golden-ratio
## sequence, so any two figures are guaranteed apart in phase and rate (Godot's generator seeded with
## two different ids gave Mitya and Tamara the same draw — CI 01.11). Same figure, same motion every run.
func _desync_idle(actor_id: String) -> void:
	# 02.11 (Director, стр. 36: «Ульяна в классе — слишком быстро качается»): data `idle.rate` — the figure's own
	# idle tempo (a child's stance clip from the Meshy library sways at an adult's pace); the jitter multiplies it.
	var base_rate := float(spec.get("idle", {}).get("rate", 1.0))
	idle_rate = base_rate
	var d: Dictionary = spec.get("idle", {}).get("desync", {})
	if d.is_empty():
		return
	var k := int(d.get("slot", absi(hash(actor_id)) % 97))
	var u_rate := fposmod(0.1 + k * 0.6180339887, 1.0)
	var u_phase := fposmod(0.5 + k * 0.3819660113, 1.0)
	var u_breath := fposmod(0.7 + k * 0.3819660113, 1.0)
	var jit := float(d.get("rate_jitter", 0.0))
	idle_rate = base_rate * (1.0 + jit * (2.0 * u_rate - 1.0))
	_idle_rng.seed = 1000003 * (k + 1)
	if bool(d.get("phase", true)):
		var room := float(_slot_len[0]) - float(_slot_t[0]) - idle_crossfade_s() - 0.1
		if room > 0.0:
			_slot_t[0] = float(_slot_t[0]) + u_phase * room
	if life != null:
		life.desync(u_breath, 7919 * (k + 1))


## Where this figure's idle is now (tests): clip name and time in it.
func idle_phase() -> Array:
	return [String(_slot_name[_slot_active]), float(_slot_t[_slot_active])]


func seed_idle(s: int) -> void:
	_idle_rng.seed = s


## Name of the idle clip in front now (tests).
func current_idle() -> String:
	return String(_slot_name[_slot_active])


func idle_crossfade_s() -> float:
	return float(spec.get("idle", {}).get("crossfade_s", 0.8))


## Advances the idle slots: when the active clip is `crossfade_s` from its end, the next variant
## starts in the other slot and fades in (eased), so no seam is ever seen.
func _advance_idle(delta: float) -> void:
	for s in 2:
		_slot_t[s] = minf(float(_slot_t[s]) + delta * idle_rate, float(_slot_len[s]))
	var xf := idle_crossfade_s()
	if float(_slot_len[_slot_active]) - float(_slot_t[_slot_active]) <= xf:
		var other := 1 - _slot_active
		_start_idle_slot(other, _pick_idle(_slot_name[_slot_active]), 0.0)
	var target := float(_slot_active)
	var rate := delta / maxf(xf, 0.05)
	_slot_mix = move_toward(_slot_mix, target, rate)


func _idle_blend() -> float:
	# smoothstep of the linear ramp: no velocity kink at the start/end of a crossfade
	return _slot_mix * _slot_mix * (3.0 - 2.0 * _slot_mix)


# --- Pose ---------------------------------------------------------------------------------------

## Poses the skeleton for this frame. `walk_phase` 0..1, `w` locomotion weight, action time/weight.
## `act_t2`/`act_mix`: a second instance of the same clip at that time, blended in by `act_mix` (loops, cuts).
## The weights pass through the followers; a new clip in the action slot waits until the one shown has faded out.
func pose(delta: float, walk_phase: float, w: float, act_w: float, act_name: String = "", act_t: float = 0.0, act_t2: float = 0.0, act_mix: float = 0.0) -> void:
	_advance_idle(delta)
	var om := float(spec.get("blend_omega", 16.0))
	var a_target := clampf(act_w, 0.0, 1.0)
	# Director 06.11, 15:08 («руки всё ещё иногда дёргаются»): a change of clip (talk → listen, an action after a line)
	# used to drop the old clip's weight to 0 and then call the new one in at full — a step for the spring, whose
	# answer to a step starts at its highest acceleration (ω²): the arms jolted 7–12 mm per 1/60 s² off the stance
	# (tests/probe_hand_spikes.gd, probe_action_jitter). Now a gate eases the weight down and back up (smoothstep over
	# switch_fade_s): no step reaches the spring, the hands set off and settle softly.
	var switching := act_name != "" and act_name != _act_name and _act_name != ""
	if switching and _gate <= 0.0 and _a_s <= 0.002:
		_a_s = 0.0
		_a_v = 0.0
		switching = false   # the old clip is out: _apply takes the new one, the gate opens
	if switching:
		act_name = _act_name   # the previous clip fades out first
		act_t = _shown_t
		act_t2 = _shown_t2
		act_mix = _shown_mix
	if delta > 0.0:
		_gate = move_toward(_gate, 0.0 if switching else 1.0, delta / maxf(float(spec.get("switch_fade_s", 0.35)), 0.01))
	else:
		_gate = 0.0 if switching else 1.0
	a_target *= smoothstep(0.0, 1.0, _gate)
	if switching:
		pass
	elif act_name == "":
		act_name = _act_name
		act_t = _shown_t
		act_t2 = _shown_t2
		act_mix = _shown_mix
	w_cmd = clampf(w, 0.0, 1.0)
	if delta > 0.0:
		var r := spring(_w_s, _w_v, clampf(w, 0.0, 1.0), om, delta)
		_w_s = r.x
		_w_v = r.y
		r = spring(_a_s, _a_v, a_target, om, delta)
		_a_s = r.x
		_a_v = r.y
		if absf(_w_s - clampf(w, 0.0, 1.0)) < 0.0005 and absf(_w_v) < 0.01:
			_w_s = clampf(w, 0.0, 1.0)
			_w_v = 0.0
		if absf(_a_s - a_target) < 0.0005 and absf(_a_v) < 0.01:
			_a_s = a_target
			_a_v = 0.0
	else:
		_w_s = clampf(w, 0.0, 1.0)
		_a_s = a_target
		_w_v = 0.0
		_a_v = 0.0
	if life != null:
		life.idle_weight = (1.0 - _w_s) * (1.0 - _a_s)
		life.advance(delta)
	_advance_look(delta)
	_shown_t = act_t
	_shown_t2 = act_t2
	_shown_mix = act_mix
	_shown_phase = walk_phase
	_apply(walk_phase, _w_s, _a_s, act_name, act_t, act_t2, act_mix)
	_calm_step(delta, act_name)


## Standing still without floating (Director 31.10, 15:04: «фигуры типа Пелагеи тупо плавают влево-вправо, это не
## айдл»): the Meshy stance clips carry the hips 9–14 cm side to side in a few seconds (Pelageya 13.8 cm every 5 s, the
## talk clips ~10 cm; tests/probe_npc_clips.gd) — a body rocking, not a weight shift. Standing (and in the clips listed
## in `acts`), the hips' wander from their slow average (low-passed over `tau_s`) is kept at `keep`: the whole figure
## is moved back by the rest, the feet held where they stand by the foot locks. Data rt3d.calm {keep, tau_s, acts}.
var _calm_lp := Vector2.INF   # the hips' slow average (model frame x, z, m)
var _calm_off := Vector2.ZERO  # the figure moved back by this (model frame x, z, m)


func _calm_step(delta: float, act_name: String) -> void:
	var c: Dictionary = spec.get("calm", {})
	if c.is_empty() or delta <= 0.0:
		return
	var h := bone_model("Hips") - model.position
	var hv := Vector2(h.x, h.z)
	if _calm_lp == Vector2.INF:
		_calm_lp = hv
	_calm_lp += (hv - _calm_lp) * (1.0 - exp(-delta / maxf(float(c.get("tau_s", 2.5)), 0.1)))
	var act_k := 1.0
	if act_name != "" and not (c.get("acts", []) as Array).has(act_name):
		act_k = 1.0 - clampf(_a_s, 0.0, 1.0)
	var wgt := (1.0 - clampf(_w_s, 0.0, 1.0)) * act_k
	_calm_off = (hv - _calm_lp) * (1.0 - float(c.get("keep", 0.4))) * wgt


## A cut (room change, load, render switch): the shown weights jump to zero at once, no fade from before.
func snap_weights() -> void:
	_w_s = 0.0
	_w_v = 0.0
	_a_s = 0.0
	_a_v = 0.0


## Locomotion and action weights as shown this frame (after the followers).
func shown_w() -> float:
	return _w_s


## The follower's speed on the locomotion weight (Player's planned stop runs the follower ahead to plan its curve).
func shown_v() -> float:
	return _w_v


## The feet (pivot frame, as feet_model) at walk phase `phase` with the locomotion weight `w`, everything else as shown
## last frame; the shown pose is put back. For the planned stop: the stance's feet (w 0) against the stride's (w 1).
func feet_at_weights(phase: float, w: float) -> Array:
	_apply(phase, w, _a_s, _act_name, _shown_t, _shown_t2, _shown_mix)
	var out := feet_model()
	_apply(_shown_phase, _w_s, _a_s, _act_name, _shown_t, _shown_t2, _shown_mix)
	return out


## Player: the planned stop has ended (its last step is down). The stride planting lets go now, the locks hold the feet
## where they are, and the foot left behind steps once to where the stance puts it. (Before: the hold went on until
## the stance had fully blended in, and the step then landed on a half-blended pose — a settling step after it.)
func stop_done(glide_unit: float = 0.0) -> void:
	stride_hold = false
	stride_hold_keep = false
	_closing = 1
	_closing_t = 0.0
	_close_unit = glide_unit
	_close_feet = feet_at_weights(_shown_phase, 0.0)


func shown_act_w() -> float:
	return _a_s


## Feet at another walk phase with everything else as shown last frame (root-motion probe: the planted foot's
## displacement due to the walk itself, without the part caused by changing blend weights). The next pose()
## overrides it.
func feet_at_phase(walk_phase: float) -> Array:
	_apply(walk_phase, _w_s, _a_s, _act_name, _shown_t, _shown_t2, _shown_mix)
	return feet_model()


func _apply(walk_phase: float, w: float, act_w: float, act_name: String, act_t: float, act_t2: float = 0.0, act_mix: float = 0.0) -> void:
	tree.set("parameters/idle_a_seek/seek_request", float(_slot_t[0]))
	tree.set("parameters/idle_b_seek/seek_request", float(_slot_t[1]))
	tree.set("parameters/idle_mix/blend_amount", _idle_blend())
	tree.set("parameters/walk_seek/seek_request", fposmod(walk_phase, 1.0) * walk_len)
	tree.set("parameters/loco/blend_amount", clampf(w, 0.0, 1.0))
	if act_name != "" and clips.has(act_name):
		if act_name != _act_name:
			var bt := tree.tree_root as AnimationNodeBlendTree
			(bt.get_node("act") as AnimationNodeAnimation).animation = clips[act_name]
			(bt.get_node("act2") as AnimationNodeAnimation).animation = clips[act_name]
			if act_body_k >= 0.0:
				(bt.get_node("act_b") as AnimationNodeAnimation).animation = clips[act_name]
				(bt.get_node("act2_b") as AnimationNodeAnimation).animation = clips[act_name]
			_act_name = act_name
		tree.set("parameters/act_seek/seek_request", act_t)
		tree.set("parameters/act2_seek/seek_request", act_t2)
		if act_body_k >= 0.0:
			tree.set("parameters/act_b_seek/seek_request", act_t)
			tree.set("parameters/act2_b_seek/seek_request", act_t2)
	tree.set("parameters/act_mix/blend_amount", clampf(act_mix, 0.0, 1.0))
	if act_body_k >= 0.0:
		tree.set("parameters/act_mix_b/blend_amount", clampf(act_mix, 0.0, 1.0))
	tree.set("parameters/actb/blend_amount", clampf(act_w, 0.0, 1.0) if _act_name != "" else 0.0)
	if act_body_k >= 0.0:
		tree.set("parameters/actb_body/blend_amount", (clampf(act_w, 0.0, 1.0) * _act_body_now()) if _act_name != "" else 0.0)
	if arm_tone != null:
		arm_tone.weight = clampf(w, 0.0, 1.0) * (1.0 - (clampf(act_w, 0.0, 1.0) if _act_name != "" else 0.0))
	if bool(spec.get("center_feet", true)):
		var ib := _idle_blend()
		var idle_mid := _mid_of(_slot_name[0]).lerp(_mid_of(_slot_name[1]), ib)
		var wc := clampf(w, 0.0, 1.0)
		var loco_mid := idle_mid.lerp(_mid_of(clips.get("walk", "")), wc)
		var aw := clampf(act_w, 0.0, 1.0) if _act_name != "" else 0.0
		var mid := loco_mid.lerp(_mid_of(clips.get(_act_name, "")), aw * (_act_body_now() if act_body_k >= 0.0 else 1.0))   # the feet: as much of the clip as the legs take
		# out of the stride the clips (captured on a flat-footed body) hold her 4 cm up off her boots — down by that much
		_bob_y = _bob_at(walk_phase) * wc
		model.position = Vector3(-mid.x - _calm_off.x, -_boot_drop * (1.0 - wc) + _bob_y - _shuffle_dip, -mid.y - _calm_off.y)
	tree.advance(0.0)


## Average feet mid-point of every clip used (20 samples over the clip, idle slot A, alone).
func _measure_mids() -> void:
	var names: Array = []
	for e in idle_pool:
		names.append(e["name"])
	for role in clips.keys():
		if not names.has(clips[role]):
			names.append(clips[role])
	var bt := tree.tree_root as AnimationNodeBlendTree
	var node := bt.get_node("idle_a") as AnimationNodeAnimation
	var keep := node.animation
	model.position = Vector3.ZERO
	for nm in names:
		node.animation = nm
		var L := anim.get_animation(nm).length
		var acc := Vector2.ZERO
		for i in 20:
			tree.set("parameters/idle_a_seek/seek_request", L * (float(i) + 0.5) / 20.0)
			tree.set("parameters/idle_mix/blend_amount", 0.0)
			tree.set("parameters/loco/blend_amount", 0.0)
			tree.set("parameters/actb/blend_amount", 0.0)
			if act_body_k >= 0.0:
				tree.set("parameters/actb_body/blend_amount", 0.0)
			tree.advance(0.0)
			var f := feet_model()
			acc += Vector2((f[0].x + f[2].x) * 0.5, (f[0].z + f[2].z) * 0.5)
		clip_mid[nm] = acc / 20.0
	node.animation = keep


func _mid_of(nm: String) -> Vector2:
	return clip_mid.get(nm, Vector2.ZERO)


func action_length(act: String) -> float:
	if not clips.has(act):
		return 0.0
	return anim.get_animation(clips[act]).length


# --- Root motion of the walk ---------------------------------------------------------------------

## Samples the walk clip over one cycle: at each phase the stance foot (the lower one) and its forward
## (model +Z) coordinate; the cumulative backward slide of the stance foot is the ground covered.
func build_root_motion() -> void:
	var was_life := life.active if life != null else false
	if life != null:
		life.active = false
	root_d = PackedFloat32Array()
	contacts = PackedFloat32Array()
	root_d.resize(RM_N + 1)
	hips_h.resize(RM_N + 1)
	var prev_side := -1
	var prev_z := 0.0
	var acc := 0.0
	root_d[0] = 0.0
	var samples: Array = []
	for i in RM_N + 1:
		var ph := float(i) / float(RM_N)
		tree.set("parameters/walk_seek/seek_request", fposmod(ph, 1.0) * walk_len * (0.999999 if i == RM_N else 1.0))
		tree.set("parameters/loco/blend_amount", 1.0)
		tree.set("parameters/actb/blend_amount", 0.0)
		if act_body_k >= 0.0:
			tree.set("parameters/actb_body/blend_amount", 0.0)
		tree.advance(0.0)
		samples.append(feet_model())
		hips_h[i] = bone_model("Hips").y
	stance_side.resize(RM_N + 1)
	for i in RM_N + 1:
		var f: Array = samples[i]
		var side := 0 if minf(f[0].y, f[1].y) <= minf(f[2].y, f[3].y) else 1
		stance_side[i] = side
		var z: float = f[side * 2].z
		if i > 0:
			if side == prev_side:
				acc += prev_z - z
			else:
				contacts.append(float(i) / float(RM_N))
				# the swapped-in foot: no slide counted across the switch sample
			root_d[i] = acc
		prev_side = side
		prev_z = z
	stride_m = maxf(acc, 0.01)
	walk_speed_mps = stride_m / maxf(walk_len, 0.01)
	_hips_top = -INF
	for v in hips_h:
		_hips_top = maxf(_hips_top, v)
	# the stance's floor: per foot the lowest the clip puts the ankle and the ball (stride planting, feet_step)
	clip_feet_h = []
	for k in 4:
		var lo := INF
		var col := PackedFloat32Array()
		col.resize(RM_N + 1)
		for i in RM_N + 1:
			lo = minf(lo, (samples[i][k] as Vector3).y)
			col[i] = (samples[i][k] as Vector3).y
		stride_floor[k] = lo
		clip_feet_h.append(col)
	# an even walk (data walk.root "even"; Director 31.10, 02:14 «плывёт… равномерно, а не идёт»): the figure goes on at
	# the speed a flat-set foot slides back in the clip — the median over the phases both its ankle and ball are down
	# — and the hips' own swing inside the figure makes the pace: quickest between the steps, slowest over the planted
	# foot, as a body vaulting over a stiff leg goes. The clip's own stance foot speeds up and stalls (one step 0.6,
	# the next 1.9 m/s): measured from it, the body lurched every other step and dragged at every double support.
	if str(spec.get("walk", {}).get("root", "foot")) == "even":
		var sp: Array = []
		var dt := walk_len / float(RM_N)
		for i in range(1, RM_N + 1):
			for side in 2:
				var a0: Vector3 = samples[i - 1][side * 2]
				var a1: Vector3 = samples[i][side * 2]
				var b1: Vector3 = samples[i][side * 2 + 1]
				if a1.y - float(stride_floor[side * 2]) < 0.006 and b1.y - float(stride_floor[side * 2 + 1]) < 0.006:
					sp.append((a0.z - a1.z) / dt)
		if sp.size() >= 8:
			sp.sort()
			walk_speed_mps = float(sp[sp.size() / 2])
			stride_m = walk_speed_mps * walk_len
			for i in RM_N + 1:
				root_d[i] = stride_m * float(i) / float(RM_N)
	stance_mids = []
	var seg_start := 0
	for i in range(1, RM_N + 2):
		if i == RM_N + 1 or stance_side[i] != stance_side[seg_start]:
			if i - seg_start >= 8 and i <= RM_N:
				var mid := (seg_start + i - 1) / 2
				stance_mids.append([float(mid) / float(RM_N), int(stance_side[mid]), samples[mid][int(stance_side[mid]) * 2]])
			seg_start = i
	if life != null:
		life.active = was_life


## Walk phase to set off from standing: a phase of the stance whose planted foot lies where that foot stands now
## (`feet_now`: feet_model() in the stance) — the blend from the stance into the stride then hardly moves it.
## `ahead` (0..1 of the stance) starts a little past its middle. −1 when unknown.
func start_phase(feet_now: Array, ahead: float = 0.0) -> float:
	var best := -1.0
	var best_d := INF
	for m in stance_mids:
		var side := int(m[1])
		if feet_now.size() < 4:
			return float(m[0])
		var d := Vector2(feet_now[side * 2].x - m[2].x, feet_now[side * 2].z - m[2].z).length()
		if d < best_d:
			best_d = d
			best = float(m[0])
	return best + ahead if best >= 0.0 else best


## Which foot the walk clip has planted at this phase (0 = left, 1 = right): the root-motion foot, also
## in a blend with the idle, where the lower foot of the blended pose can be the swinging one.
func stance_at(phase: float) -> int:
	if stance_side.is_empty():
		return 0
	return int(stance_side[clampi(int(round(fposmod(phase, 1.0) * RM_N)), 0, RM_N)])


## The walk's bob deepened (Director 31.10, 02:14 «плывёт… равномерно»): the clip's hips rise and fall 3.1 cm a step,
## a walking body's centre of mass about 5 cm — highest over the planted foot, lowest in the double support (OUHSC gait
## kinematics; Frontiers Hum Neurosci 2017, 10.3389/fnhum.2017.00187). Below its highest the body goes down `k` times
## more (data walk.bob_deepen; only with the stride planting, which keeps the feet on the floor); 0 off.
func _bob_at(phase: float) -> float:
	var k := float(spec.get("walk", {}).get("bob_deepen", 0.0))
	if k <= 0.0 or hips_h.size() < RM_N + 1 or spec.get("feet", {}).get("stride", {}).is_empty():
		return 0.0
	var x := fposmod(phase, 1.0) * RM_N
	var i := int(floor(x))
	var h := lerpf(hips_h[i], hips_h[mini(i + 1, RM_N)], x - float(i))
	return -k * (_hips_top - h)


## The walk clip's own height of foot point k ([L ankle, L ball, R ankle, R ball]) above its stance floor at phase ph.
func clip_foot_h(k: int, ph: float) -> float:
	if clip_feet_h.size() < 4:
		return 0.0
	var col: PackedFloat32Array = clip_feet_h[k]
	var x := fposmod(ph, 1.0) * RM_N
	var i := int(floor(x))
	var h := lerpf(col[i], col[mini(i + 1, RM_N)], x - float(i))
	return h - float(stride_floor[k])


## The walk goes on evenly (data walk.root "even"), the feet held by the stride planting.
func even_root() -> bool:
	return str(spec.get("walk", {}).get("root", "foot")) == "even"


## Ground covered (model metres) by the walk between phases p0 and p1 (p1 may exceed 1: wraps).
func root_between(p0: float, p1: float) -> float:
	if p1 < p0:
		return 0.0
	var total := 0.0
	var whole := floorf(p1) - floorf(p0)
	total += whole * stride_m
	total += _root_at(fposmod(p1, 1.0)) - _root_at(fposmod(p0, 1.0))
	return total


func _root_at(p: float) -> float:
	var x := clampf(p, 0.0, 1.0) * RM_N
	var i := int(floor(x))
	if i >= RM_N:
		return root_d[RM_N]
	return lerpf(root_d[i], root_d[i + 1], x - float(i))


## Positions of [left foot, left toe, right foot, right toe] in the yaw pivot's frame (metres; the
## model faces +Z at yaw 0, y up, feet at y ≈ 0).
func feet_model() -> Array:
	var out: Array = []
	var xf := _skel_to_turn()
	for b in foot_bones:
		if b < 0:
			out.append(Vector3.ZERO)
			continue
		out.append(xf * skeleton.get_bone_global_pose(b).origin)
	return out


## Skeleton space → yaw pivot space (product of the local transforms in between; valid outside the
## scene tree too, unlike global_transform).
func _skel_to_turn() -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != turn:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Any bone's position in the yaw pivot's frame (tests: idle jerks, sliding).
func bone_model(bone_name: String) -> Vector3:
	var b := skeleton.find_bone(bone_name)
	if b < 0:
		return Vector3.ZERO
	return _skel_to_turn() * skeleton.get_bone_global_pose(b).origin


## Screen offset (sheet px at node scale 1) of a point given in the floor frame (x right, y up, z towards
## the viewer) as drawn by this camera.
func screen_of(p_floor: Vector3) -> Vector2:
	var e := deg_to_rad(elev_deg)
	return Vector2(p_floor.x, -p_floor.y * cos(e) + p_floor.z * sin(e) * depth_stretch()) * ppm


## World depth (z) stretch of the oblique floor: k / sin(elevation), 1 when off.
func depth_stretch() -> float:
	if floor_k <= 0.0:
		return 1.0
	return floor_k / maxf(sin(deg_to_rad(elev_deg)), 0.01)


## Room floor foreshortening for the oblique projection (data rt3d.oblique_floor true).
func set_floor_k(k: float) -> void:
	floor_k = k if bool(spec.get("oblique_floor", false)) else 0.0
	if oblique != null:
		oblique.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, depth_stretch())), Vector3.ZERO)


## Same, rotated by the current yaw (floor frame: x right, z towards the viewer).
func bone_floor(bone_name: String) -> Vector3:
	return Basis(Vector3.UP, get_yaw()) * bone_model(bone_name)


## Triangles of the drawn mesh (tests: web budget).
func triangle_count() -> int:
	var n := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n
