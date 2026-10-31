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
var _hide_mat: ShaderMaterial = null
var room_floor_k: float = 0.5          # the room floor's foreshortening (screen depth px per floor metre across)
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
	view = Actor3D.new()
	add_child(view)
	if not view.setup(spec):
		push_warning("NpcLive3D: %s — 3D model not loaded (%s)" % [npc.name, view.load_error])
		view.queue_free()
		view = null
		return false
	view.set_floor_k(floor_k)
	room_floor_k = floor_k
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
	state = st
	var want := ""
	if st == "talk" and view.clips.has("talk"):
		want = "talk"
	elif st == "listen" and view.clips.has("listen"):
		want = "listen"
	if want != act_name and want != "":
		act_name = want
		act_t = 0.0


## Walking off in a staging at `speed_px` screen px/s (node scale `s`): the cycle's cadence follows the speed.
func walk(on: bool, speed_px: float = 0.0, s: float = 1.0) -> void:
	walking = on
	if on and view != null:
		var mps := speed_px / maxf(view.ppm * maxf(s, 0.01), 1.0)
		walk_rate = clampf(mps / maxf(view.stride_m, 0.1), 0.2, 2.5)


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
	# a big turn standing: small steps on the spot (a little of the walk), as Agata
	var stepping := not walking and view.clips.has("walk") and absf(diff) > deg_to_rad(float(rt.get("step_above_deg", 50.0)))
	step_w = move_toward(step_w, float(rt.get("step_weight", 0.3)) if stepping else 0.0, delta / 0.25)
	if walk_w > 0.0:
		walk_phase += delta * walk_rate
	elif step_w > 0.0:
		walk_phase += delta / maxf(view.walk_len, 0.1)
	var talk_on := not walking and state in ["talk", "listen"] and act_name != ""
	act_w = move_toward(act_w, 1.0 if talk_on else 0.0, delta / float(rt.get("state_fade_s", 0.4)))
	var lt: Array = [act_t, 0.0, 0.0]
	if act_name != "" and (act_w > 0.0 or view.shown_act_w() > 0.0):
		# listen / talk: forward, each pass's end fading into the next one's start (on while it is still shown)
		var sp := float(rt.get("talk_speed" if act_name == "talk" else "listen_speed", 1.0))
		act_t += delta * sp
		lt = Actor3D.loop_times(act_t, maxf(view.action_length(act_name), 0.1), float(rt.get("loop_crossfade_s", 0.8)))
	view.pose(delta, fposmod(walk_phase, 1.0), maxf(walk_w, step_w), act_w, act_name, float(lt[0]), float(lt[1]), float(lt[2]))
	# feet on the floor (Director 31.10, 15:04: «плавают влево-вправо… ноги идут сами по себе»): the stance clips shift
	# the weight with the feet sliding under it and the walk's feet skate against the staging's pace — the same foot
	# locks and stride planting as Agata's (data rt3d.feet)
	if not view.foot_ik.is_empty():
		var p: Vector2 = npc.global_position
		var ppm_s := view.ppm * maxf(absf(npc.scale.y), 0.01)
		if _last_pos != Vector2.INF and p.distance_to(_last_pos) > 0.5 * ppm_s:
			view.feet_reset()   # placed elsewhere by the staging, not walked there
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
