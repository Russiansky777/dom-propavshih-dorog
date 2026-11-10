class_name NpcLive3D
extends Node
## A villager in real 3D (Director 30.10, 14:38: «как живые… остальные можно чуточку попроще»): the same Meshy model
## the villager's sheets were rendered from (actor data `rt3d`), drawn live by an Actor3D under the NpcActor's
## facade sprite — the sheet keeps the placement, depth scale, y-sort, contact shadow and room tone; the picture is
## the live one. Simpler than Agata: three looping states (idle with crossfaded repeats; listen and talk played
## forward, the end of each pass fading into the start of the next — Director 30.10, 17:36: «движения… иногда
## странные или рваные»: the old to-and-fro playback reversed every motion mid-air), a walk cycle whose cadence
## follows the staging's speed, and a body yaw that sets off and settles softly (any angle); a big turn standing
## is taken with small steps, as Agata does. The facade sprite is drawn invisible (its children — the shadow — stay).

const HIDE_SHADER_CODE := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.0); }\n"

var npc: Node2D = null              # the NpcActor
var view: Actor3D = null
var body: Sprite2D = null
var rt: Dictionary = {}
var yaw: float = 0.0
var yaw_target: float = 0.0
var yaw_v: float = 0.0               # yaw speed, rad/s
var _yaw_dir: float = 0.0            # the way it turns to the target (Actor3D.turn_step), chosen once per target
var _yaw_dir_target: float = 0.0
var step_w: float = 0.0              # stepping while turning on the spot
var state: String = "idle"
var walk_w: float = 0.0
var walking: bool = false
var walk_rate: float = 1.0           # walk cycles per second while walking
var walk_phase: float = 0.0
var act_name: String = ""
var act_w: float = 0.0
var act_t: float = 0.0
var _dialogue_clock_speed: float = 1.0
var _dialogue_clock_v: float = 0.0
## One-shot actions (block 3, Director 05.11: villagers do what the story says — hug, hand a key over, crank the
## windlass): a clip played once forward from the stance and back (`play_once`); `hold` keeps its last pose until
## `release_once` (a hug held through the lines). While the clip fades out its time stays at the end (no wrap).
var once := false
var once_hold := false
var _once_clip := false
var once_hold_at := -1.0   # share of the clip where a held action stops (the embrace at its closest); < 0 — at its end
var once_loop := false      # the action repeats (the tarring), each pass's end fading into the next one's start
var _hide_mat: ShaderMaterial = null
var room_floor_k: float = 0.5          # the room floor's foreshortening (screen depth px per floor metre across)
var _close_pending := false            # a walk has ended: the closing step once its fade is over (data feet.close_on_stop)
var _last_pos := Vector2.INF           # feet locks: a jump of the villager (staging places it) lets the feet go


## True when this villager should be drawn live: data `render` "3d" (desktop), the web build and runs without a
## display keep the sheets (as Agata).
static var forced: String = ""   # tests: "3d" / "sprites" for every villager regardless of data and display


static func wanted(spec: Dictionary) -> bool:
	if not spec.has("rt3d"):
		return false
	if forced != "":
		return forced == "3d"
	if DisplayServer.get_name() == "headless":
		return false
	return String(spec.get("render_web" if OS.has_feature("web") else "render", "sprites")) == "3d"


func setup(the_npc: Node2D, spec: Dictionary, floor_k: float) -> bool:
	npc = the_npc
	rt = spec.get("rt3d", {})
	model_id = String(spec.get("id", ""))
	view = Actor3D.new()
	add_child(view)
	if not view.setup(spec):
		push_warning("NpcLive3D: %s — 3D model not loaded (%s)" % [npc.name, view.load_error])
		view.queue_free()
		view = null
		return false
	view.set_floor_k(floor_k)
	room_floor_k = floor_k
	_setup_arm_body()
	_setup_jaw()
	body = Sprite2D.new()
	body.name = "Body3D"
	body.centered = false
	body.texture = view.get_texture()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	body.material = cm
	var sprite: CanvasItem = npc.get("sprite")
	sprite.add_child(body)
	var sh := Shader.new()
	sh.code = HIDE_SHADER_CODE
	_hide_mat = ShaderMaterial.new()
	_hide_mat.shader = sh
	sprite.material = _hide_mat
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_update_scale()
	return true


## The mouth by the voice of the villager's own line (data rt3d.jaw; Director 09.11, 21:21): a mouth painted on the
## face along the model's lip line opens with the loudness (scripts/actors/jaw_modifier.gd).
const JawModifier := preload("res://scripts/actors/jaw_modifier.gd")
var jaw: SkeletonModifier3D = null
var model_id: String = ""           # the actor's id (data/actors/<id>.json): per-model data files


func _setup_jaw() -> void:
	var d: Dictionary = rt.get("jaw", {})
	if d.is_empty():
		return
	var jm = JawModifier.new()
	jm.name = "Jaw"
	view.skeleton.add_child(jm)
	var id = npc.get("actor_id") if npc != null else null
	if jm.setup(d, view.skeleton, String(id) if id != null and String(id) != "" else model_id):
		jaw = jm
		jm.setup_mouth(view.material, view.skeleton, model_id)   # the lip line is the model's (data/actors_rest/mouth_<id>.json)
	else:
		jm.queue_free()


## A hand held at a point of the screen (Director 10.11, 18:59 — Ilya's hands on the windlass's crank as it turns):
## `screen` — canvas px, as the figure is drawn there; `weight` 1 holds, 0 lets go (eased in the modifier); `helps` —
## the second hand: the body does not go down for it, it reaches as far as the leading hand's posture lets it. The point
## is taken into the figure's own space on the plane the hand works in — between its shoulder and the chest's middle,
## across the camera's view — and HandHoldModifier (the last of the skeleton's modifiers) brings the hand there.
const HandHold := preload("res://scripts/actors/hand_hold_modifier.gd")
var hand_hold: SkeletonModifier3D = null


func hold_hand_at(side: String, screen: Vector2, weight: float, helps: bool = false) -> void:
	if view == null or body == null or view.camera == null or not view.camera.is_inside_tree():
		return
	if hand_hold == null:
		if weight <= 0.0:
			return
		hand_hold = HandHold.new()
		hand_hold.name = "HandHold"
		view.skeleton.add_child(hand_hold)
		hand_hold.setup(view.skeleton, view._skel_to_model().basis.orthonormalized())
		for s in ["Left", "Right"]:
			hand_hold.grip_local[s] = view.hand_grip_local(s)[0]
	var sk: Skeleton3D = view.skeleton
	var a := sk.find_bone(side + "Arm")
	var o := sk.find_bone(("Left" if side == "Right" else "Right") + "Arm")
	var ll := sk.find_bone("LeftUpLeg")
	var rl := sk.find_bone("RightUpLeg")
	if a < 0 or o < 0 or ll < 0 or rl < 0:
		return
	var px: Vector2 = body.global_transform.affine_inverse() * screen - body.offset
	var cam: Camera3D = view.camera
	var inv_sk: Transform3D = sk.global_transform.affine_inverse()
	# The point of the screen is a line into the picture; the hand takes the place on it that lies in front of its own
	# side of the body — halfway from the body's middle to its shoulder (the shoulders' places as the model is built,
	# not as the clip leans them). Seen from the side that line runs across the body, and the place is one; seen
	# from the front it runs along the body's front-back and any depth is at the same side — then the plane between
	# the shoulders as posed.
	var to_model: Basis = view._skel_to_model().basis.orthonormalized()
	var mid_rest: Vector3 = (sk.get_bone_global_rest(ll).origin + sk.get_bone_global_rest(rl).origin) * 0.5
	var want_x: float = (to_model * (sk.get_bone_global_rest(a).origin - mid_rest)).x * 0.5
	var mid: Vector3 = (sk.get_bone_global_pose(ll).origin + sk.get_bone_global_pose(rl).origin) * 0.5
	var pa: Vector3 = sk.global_transform * sk.get_bone_global_pose(a).origin
	var po: Vector3 = sk.global_transform * sk.get_bone_global_pose(o).origin
	var depth := -(cam.global_transform.affine_inverse() * pa.lerp(po, 0.3)).z
	var x0: float = (to_model * (inv_sk * cam.project_position(px, depth) - mid)).x
	var x1: float = (to_model * (inv_sk * cam.project_position(px, depth + 1.0) - mid)).x
	var per_m := x1 - x0
	if absf(per_m) > absf((to_model * (inv_sk.basis * cam.global_transform.basis.z)).length()) * 0.35:
		depth += clampf((want_x - x0) / per_m, -0.6, 0.6)
	hand_hold.hold(side, inv_sk * cam.project_position(px, depth), weight, helps)


## Hands kept out of the body (data rt3d.arm_body; Director 01.11, lines 10 and 52): a BodyClear modifier after all the
## others on the villager's skeleton.
const BodyClear := preload("res://scripts/actors/body_clear_modifier.gd")
const ArmRest := preload("res://scripts/actors/arm_rest.gd")
static var _rest_cache: Dictionary = {}    # rest file path → its data
var arm_body: SkeletonModifier3D = null    # BodyClear
var _rested := false                       # the arms' turn-in is in this figure's clips (arm_body.rest)
var _bc_strength := 0.0


func _setup_arm_body() -> void:
	var d: Dictionary = rt.get("arm_body", {})
	if d.is_empty():
		return
	var bc = BodyClear.new()
	bc.name = "BodyClear"
	view.skeleton.add_child(bc)
	var unit := 1.0 / maxf(view._skel_to_turn().basis.get_scale().y, 1e-6)
	if bc.setup(d, view.skeleton, view.meshes, unit, String(rt.get("scene", ""))):
		arm_body = bc
		# arms along the body (data arm_body.rest {file, gap_m, min_deg}; scripts/actors/arm_rest.gd): the baked turn-in
		# of each hanging arm, into this figure's copies of the clips
		var rest: Dictionary = d.get("rest", {})
		var rest_path := String(rest.get("file", ""))
		if rest_path != "" and OS.get_environment("DPD_ARM_REST_OFF") == "":   # the switch: probes' «before» shots
			if not _rest_cache.has(rest_path):
				var parsed = JSON.parse_string(FileAccess.get_file_as_string(rest_path)) if FileAccess.file_exists(rest_path) else null
				_rest_cache[rest_path] = parsed if parsed is Dictionary else {}
			ArmRest.apply(view.skeleton, view.anim, _rest_cache[rest_path], float(rest.get("scale", 1.0)))
			# rested — when the clips this figure stands, talks and listens with are all in the data (a test's figure on
			# other clips keeps BodyClear as before)
			var baked: Dictionary = (_rest_cache[rest_path] as Dictionary).get("clips", {})
			_rested = not baked.is_empty()
			for role in ["idle", "talk", "listen"]:
				if view.clips.has(role):
					var cn := String(view.clips[role])
					if not baked.has(cn.get_slice("/", cn.get_slice_count("/") - 1)):
						_rested = false
			if _rested:
				bc.strength = 0.0
		# the clearing baked into the stance clips (data arm_body.bake; BodyClear.bake)
		if d.has("bake"):
			var names := {}
			var roles: Array = d["bake"].get("roles", ["idle", "talk", "listen"])
			for role in roles:
				if view.clips.has(role):
					names[view.clips[role]] = true
			if roles.has("idle"):
				for e in view.idle_pool:
					names[e["name"]] = true
			var t0 := Time.get_ticks_msec()
			bc.bake(view.anim, names.keys())
			if OS.get_environment("BAKE_DBG") != "":
				print("bake %s: %d ms" % [rt.get("scene", ""), Time.get_ticks_msec() - t0])
	else:
		bc.queue_free()


## Where the villager looks (screen vector from the feet): the body yaw eases there.
func face(v: Vector2, floor_k: float, at_once: bool = false) -> void:
	if v.length_squared() < 1.0:
		return
	yaw_target = atan2(v.x, v.y / maxf(floor_k, 0.05))
	if at_once:
		yaw = yaw_target
		yaw_v = 0.0
		_yaw_dir = 0.0


func set_state(st: String) -> void:
	if once and st != "act":
		_end_once()
	state = st
	var want := _state_action(st)
	if want != act_name and want != "":
		act_name = want
		act_t = 0.0
		_once_clip = false   # the shown action fades out held where it was (Actor3D.pose), talk/listen loop again


## When listening uses the idle clip (06.11, 18:48), the stance goes on as it is — its phase and its life (breath,
## glances): a second copy of idle in the action layer, at another time, blended with the first and switching life off
## made the listener stiff (the reviewing AI, 06.11, 21:16). A distinct listen clip still plays in the action layer.
func _state_action(st: String) -> String:
	if st not in ["talk", "listen"] or not view.clips.has(st):
		return ""
	if st == "listen" and view.clips.get("listen") == view.clips.get("idle"):
		return ""
	return st


## Plays `clip` once (rt3d.clips role or clip name): from the stance into the action and back. False — no such clip.
func play_once(clip: String, hold: bool = false, hold_at: float = -1.0, loop: bool = false) -> bool:
	if view == null or not view.clips.has(clip):
		return false
	state = "act"
	act_name = clip
	act_t = 0.0
	once = true
	once_hold = hold or loop or hold_at >= 0.0
	once_hold_at = hold_at
	once_loop = loop
	_once_clip = true
	return true


## The next one-shot action's arm lowered or raised (stage data npc_act[].arm {side, drop_deg}; act_arm_modifier.gd):
## it holds for that clip only, coming and going with it.
const ActArm := preload("res://scripts/actors/act_arm_modifier.gd")
var act_arm: SkeletonModifier3D = null


func set_act_arm(d: Dictionary, clip: String) -> void:
	if view == null:
		return
	if act_arm == null:
		act_arm = ActArm.new()
		act_arm.name = "ActArm"
		view.skeleton.add_child(act_arm)
		if arm_body != null:
			view.skeleton.move_child(act_arm, arm_body.get_index())   # before BodyClear: it sees the arm where it is shown
	act_arm.setup(view.skeleton, String(d.get("side", "Right")), float(d.get("drop_deg", 0.0)), clip)


## The held action ends: the clip plays out to its end and the villager goes back to the stance.
func release_once(at_share: float = -1.0) -> void:
	once_hold = false
	# 09.11 (hand-over): the clip goes on from `at_share` — the same pose on its way back (give_small 0,25 ↔ 0,77), so
	# an empty hand is lowered at once, not first held out further as the rest of the reach would
	if at_share >= 0.0 and view != null and act_name != "":
		act_t = clampf(at_share, 0.0, 1.0) * view.action_length(act_name)
	if once_loop:
		# a loop plays its current pass out to the clip's end, then back to the stance (no jump to the end)
		once_loop = false
		if view != null:
			act_t = float(Actor3D.loop_times(act_t, maxf(view.action_length(act_name), 0.1), float(rt.get("loop_crossfade_s", 0.8)))[0])


## True while a one-shot action is still playing (or held).
func once_busy() -> bool:
	return once


func _end_once() -> void:
	once = false
	once_hold = false
	once_hold_at = -1.0
	if state == "act":
		state = "idle"


## Walking off in a staging at `speed_px` screen px/s (node scale `s`): the cycle's cadence follows the speed.
func walk(on: bool, speed_px: float = 0.0, s: float = 1.0) -> void:
	if walking and not on and view != null and bool(rt.get("feet", {}).get("close_on_stop", false)):
		# Director 01.11, line 55 «Нина тоже мельтешит»: coming to a stop the feet took three quick steps in 0.75 s (the
		# locks catching up with the stance one after another, while the walk faded out); now, as Agata's planned stop,
		# the stride planting holds the feet through the fade and then (Actor3D.stop_done) the foot left behind closes up
		# once, to where the stance puts it — the other stays unless far off
		view.stride_hold = true
		view.stride_hold_keep = true
		_close_pending = true
	elif on:
		_close_pending = false
	walking = on
	if on and view != null:
		var mps := speed_px / maxf(view.ppm * maxf(s, 0.01), 1.0)
		# a shorter stride (data walk_stride_k < 1: the walk shown at that weight over the stance — Pelageya's skirt hangs
		# on her legs, a full stride tore it in two) is taken quicker, so the feet still keep the floor
		walk_rate = clampf(mps / maxf(view.stride_m * _stride_k(), 0.1), 0.2, 2.5)


func _stride_k() -> float:
	if OS.get_environment("DPD_STRIDE_K") != "":   # probes
		return clampf(float(OS.get_environment("DPD_STRIDE_K")), 0.2, 1.0)
	return clampf(float(rt.get("walk_stride_k", 1.0)), 0.2, 1.0)


## Optional authored-dialogue exit: ease the outgoing clip's clock to rest while its pose fades.
## Without this setting the legacy clock is unchanged. Keeping speed and its derivative also
## makes a quick listen -> talk reversal continuous. Integrate the critically damped speed
## analytically, so remaining clip travel does not depend on the render/physics frame rate.
func _dialogue_phase_step(delta: float, playing: bool) -> float:
	var omega := float(rt.get("dialogue_clock_omega", 0.0))
	if omega <= 0.0:
		return delta
	if delta <= 0.0:
		return 0.0
	var target := 1.0 if playing else 0.0
	var x := _dialogue_clock_speed - target
	var b := _dialogue_clock_v + omega * x
	var e := exp(-omega * delta)
	var travel := target * delta + x * (1.0 - e) / omega + b * (1.0 - e * (1.0 + omega * delta)) / (omega * omega)
	_dialogue_clock_speed = target + (x + b * delta) * e
	_dialogue_clock_v = (_dialogue_clock_v - omega * b * delta) * e
	return maxf(travel, 0.0)


func process(delta: float) -> void:
	if view == null:
		return
	var diff := angle_difference(yaw, yaw_target)
	var r := Actor3D.turn_step(Vector4(yaw, yaw_v, _yaw_dir, _yaw_dir_target), yaw_target, delta, deg_to_rad(float(rt.get("turn_deg_s", 240.0))), float(rt.get("turn_ease_per_s", 7.0)), deg_to_rad(float(rt.get("turn_accel_deg_s2", 1100.0))))
	yaw = r.x
	yaw_v = r.y
	_yaw_dir = r.z
	_yaw_dir_target = r.w
	view.set_yaw(yaw)
	walk_w = move_toward(walk_w, 1.0 if walking else 0.0, delta / 0.3)
	if _close_pending and walk_w <= 0.0:
		_close_pending = false
		view.stop_done(0.0)
	# a big turn standing: small steps on the spot (a little of the walk), as Agata
	var stepping := not walking and view.clips.has("walk") and absf(diff) > deg_to_rad(float(rt.get("step_above_deg", 50.0)))
	step_w = move_toward(step_w, float(rt.get("step_weight", 0.3)) if stepping else 0.0, delta / 0.25)
	if walk_w > 0.0:
		walk_phase += delta * walk_rate
	elif step_w > 0.0:
		walk_phase += delta / maxf(view.walk_len, 0.1)
	var talk_on := not walking and (_state_action(state) != "" or once)
	act_w = move_toward(act_w, 1.0 if talk_on else 0.0, delta / float(rt.get("state_fade_s", 0.4)))
	var lt: Array = [act_t, 0.0, 0.0]
	if _once_clip and act_name != "" and (once or act_w > 0.0 or view.shown_act_w() > 0.0):
		# a one-shot action: forward once, held at its end (`hold`), the end kept while it fades back to the stance
		var L := maxf(view.action_length(act_name), 0.1)
		# 06.11 («руки дёргаются»): while the previous clip still gives way, this one waits at its first key — it used
		# to run on underneath and came in half-way through its quickest part (Mitya's knock at 0.9 s)
		var waiting: bool = String(view.get("_act_name")) != act_name
		var dt_act := 0.0 if waiting else delta
		if once_loop and once:
			act_t += dt_act * float(rt.get("act_speed", 1.0))
			lt = Actor3D.loop_times(act_t, L, float(rt.get("loop_crossfade_s", 0.8)))
		else:
			act_t += dt_act * float(rt.get("act_speed", 1.0))
			if once and once_hold and once_hold_at >= 0.0 and act_t >= once_hold_at * L:
				act_t = once_hold_at * L
			if act_t >= L:
				act_t = L
				if once and not once_hold:
					_end_once()
			lt = [minf(act_t, L - 0.001), 0.0, 0.0]
	elif act_name != "" and (act_w > 0.0 or view.shown_act_w() > 0.0):
		# listen / talk: forward, each pass's end fading into the next one's start (on while it is still shown)
		var sp := float(rt.get("talk_speed" if act_name == "talk" else "listen_speed", 1.0))
		act_t += _dialogue_phase_step(delta, talk_on) * sp
		lt = Actor3D.loop_times(act_t, maxf(view.action_length(act_name), 0.1), float(rt.get("loop_crossfade_s", 0.8)))
	if _once_clip and not once and act_w <= 0.0 and view.shown_act_w() <= 0.001:
		_once_clip = false
	view.pose(delta, fposmod(walk_phase, 1.0), maxf(walk_w * _stride_k(), step_w), act_w, act_name, float(lt[0]), float(lt[1]), float(lt[2]))
	if act_arm != null:
		var aw: float = view.shown_act_w() if (_once_clip and act_name == String(act_arm.clip)) else 0.0
		act_arm.weight = aw if aw >= float(act_arm.weight) else move_toward(float(act_arm.weight), aw, delta / 0.25)
	if arm_body != null and bool(rt.get("arm_body", {}).get("stance_free", false)):
		arm_body.strength = view.shown_act_w()
	elif arm_body != null and _rested:
		# arms along the body (arm_body.rest): the stance, talk and listen clips are already as close to the clothes as
		# the real surface lets them — BodyClear's hull (the farthest fold per sector) would push them back out. It stays
		# for the one-shot actions (their clips are not baked), coming in and out softly with them.
		_bc_strength = move_toward(_bc_strength, view.shown_act_w() if _once_clip else 0.0, delta / 0.25)
		arm_body.strength = _bc_strength
	# feet on the floor (Director 31.10, 15:04: «плавают влево-вправо… ноги идут сами по себе»): the stance clips shift
	# the weight with the feet sliding under it and the walk's feet skate against the staging's pace — the same foot
	# locks and stride planting as Agata's (data rt3d.feet)
	if not view.foot_ik.is_empty():
		var p: Vector2 = npc.global_position
		var ppm_s := view.ppm * maxf(absf(npc.scale.y), 0.01)
		if _last_pos != Vector2.INF and p.distance_to(_last_pos) > 0.5 * ppm_s:
			view.feet_reset()   # placed elsewhere by the staging, not walked there
			if arm_body != null:
				arm_body.snap = true
		_last_pos = p
		view.feet_step(delta, p, Vector2(ppm_s, ppm_s * maxf(room_floor_k, 0.05)))
	_update_scale()
	body.self_modulate = (npc.get("sprite") as CanvasItem).self_modulate


func _update_scale() -> void:
	if body == null or view == null:
		return
	var s := absf(npc.scale.y)
	var win := 1.0
	if npc.is_inside_tree():
		win = maxf(npc.get_viewport().get_final_transform().get_scale().y, 0.25)
	view.set_render_scale(s * win * float(rt.get("supersample", 1.5)))
	var sheet = npc.get("sheet")
	body.offset = view.sprite_offset()
	body.scale = Vector2.ONE * float(sheet.texture_scale) / view.render_scale
