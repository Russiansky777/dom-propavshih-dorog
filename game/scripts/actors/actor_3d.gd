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
##   - one-shot action (open / pick / reach) with fade in/out.
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
var foot_bones: Array = []       # [left foot, left toe, right foot, right toe] bone indices
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
var _act_name: String = ""


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
	var packed = load(path)
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
	# A villager may have no walk clip (data `require_walk` false: Pavel, Mitya, Ilya's wife — their stagings slide):
	# the stance stands in for it, nothing walks.
	if idle_pool.is_empty() or (not clips.has("walk") and bool(spec.get("require_walk", true))):
		load_error = "clips missing: " + str(clips)
		return false
	_build_tree()
	_build_camera()
	life = ActorLife3D.new()
	life.name = "Life"
	life.setup(spec.get("life", {}), skeleton)
	skeleton.add_child(life)
	for b in ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]:
		foot_bones.append(skeleton.find_bone(b))
	_measure_mids()
	if clips.has("walk"):
		build_root_motion()
	_start_idle_slot(0, _pick_idle(""), 0.0)
	pose(0.0, 0.0, 0.0, 0.0)
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


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "Tree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	var bt := AnimationNodeBlendTree.new()
	for slot in ["idle_a", "idle_b", "walk", "act"]:
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
	var actb := AnimationNodeBlend2.new()
	bt.add_node("actb", actb)
	bt.connect_node("actb", 0, "loco")
	bt.connect_node("actb", 1, "act_seek")
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
		_slot_t[s] = minf(float(_slot_t[s]) + delta, float(_slot_len[s]))
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
func pose(delta: float, walk_phase: float, w: float, act_w: float, act_name: String = "", act_t: float = 0.0) -> void:
	_advance_idle(delta)
	if life != null:
		life.idle_weight = clampf(1.0 - w, 0.0, 1.0) * (1.0 - clampf(act_w, 0.0, 1.0))
		life.advance(delta)
	_apply(walk_phase, w, act_w, act_name, act_t)


## Feet for a walk phase and weights at the current idle times (root-motion probe: the planted foot's
## displacement due to the walk itself, without the part caused by changing blend weights). The next
## pose() overrides it.
func feet_with(walk_phase: float, w: float, act_w: float = 0.0, act_name: String = "", act_t: float = 0.0) -> Array:
	_apply(walk_phase, w, act_w, act_name, act_t)
	return feet_model()


func _apply(walk_phase: float, w: float, act_w: float, act_name: String, act_t: float) -> void:
	tree.set("parameters/idle_a_seek/seek_request", float(_slot_t[0]))
	tree.set("parameters/idle_b_seek/seek_request", float(_slot_t[1]))
	tree.set("parameters/idle_mix/blend_amount", _idle_blend())
	tree.set("parameters/walk_seek/seek_request", fposmod(walk_phase, 1.0) * walk_len)
	tree.set("parameters/loco/blend_amount", clampf(w, 0.0, 1.0))
	if act_name != "" and clips.has(act_name):
		if act_name != _act_name:
			((tree.tree_root as AnimationNodeBlendTree).get_node("act") as AnimationNodeAnimation).animation = clips[act_name]
			_act_name = act_name
		tree.set("parameters/act_seek/seek_request", act_t)
	tree.set("parameters/actb/blend_amount", clampf(act_w, 0.0, 1.0) if _act_name != "" else 0.0)
	if bool(spec.get("center_feet", true)):
		var ib := _idle_blend()
		var idle_mid := _mid_of(_slot_name[0]).lerp(_mid_of(_slot_name[1]), ib)
		var wc := clampf(w, 0.0, 1.0)
		var loco_mid := idle_mid.lerp(_mid_of(clips.get("walk", "")), wc)
		var aw := clampf(act_w, 0.0, 1.0) if _act_name != "" else 0.0
		var mid := loco_mid.lerp(_mid_of(clips.get(_act_name, "")), aw)
		model.position = Vector3(-mid.x, 0.0, -mid.y)
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
		tree.advance(0.0)
		samples.append(feet_model())
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
	if life != null:
		life.active = was_life


## Which foot the walk clip has planted at this phase (0 = left, 1 = right): the root-motion foot, also
## in a blend with the idle, where the lower foot of the blended pose can be the swinging one.
func stance_at(phase: float) -> int:
	if stance_side.is_empty():
		return 0
	return int(stance_side[clampi(int(round(fposmod(phase, 1.0) * RM_N)), 0, RM_N)])


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
