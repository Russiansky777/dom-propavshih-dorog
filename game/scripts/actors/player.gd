class_name Player
extends Node2D
## Click-to-walk player. Origin is at the feet.
##
## Visual: an AnimatedSprite2D built from the actor's sheets (data/actors/<id>.json + sprites.json,
## 8 directions × N frames); the placeholder polygon `Body` is the fallback when no sheet loads.
## Scale and z_index come from the room's depth parameters (z_index = int(y) for y-sort).
##
## Feet on the floor (root motion by the stance foot): the walk clip is drawn in place, and between
## sheet frames k and k+1 the planted foot slides back by stride_table[row][k] (measured per row and
## frame by tools/measure_stride.py; unequal — the clip is not uniform). The LOGICAL position moves
## smoothly along the navigation path at the row's mean speed (row cycle per period; the frame rate is
## constant, frames × speed_mps / cycle_meters, applied through AnimatedSprite2D.speed_scale) and is
## recorded as a trail. The DRAWN figure stands still while a frame is shown and, at each frame
## change, advances along that trail by exactly stride_table[row][k] × scale — so the planted foot
## stays on the same floor pixels. The drawn figure is never ahead of the logical one (walks start on
## the table's start_frame), so it never leaves the path walked; the lag is under one cycle and is
## absorbed when she stops (the logical position takes the drawn one).

signal walk_started(target: Vector2)
signal arrived(position: Vector2)
signal interaction_performed(node: Node2D)
signal action_started(action: String, node: Node2D)
signal action_finished(action: String, node: Node2D)

## Walking speed in px/s at scale 1 for the placeholder body. With an actor sheet the speed comes
## from the sheet data (metres per second × px per metre at the current depth scale).
@export var walk_speed: float = 260.0
## Multiplier applied to the sheet-derived speed (tests use it to hurry).
@export var speed_factor: float = 1.0
## Distance (in body units, i.e. divided by the current scale) per step frame (placeholder body).
@export var step_length: float = 36.0
@export var bob_height: float = 5.0
## Actor whose sheets are used (data/actors/<id>.json). Empty = placeholder polygon only.
@export var actor_id: String = "agata"

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var body: Node2D = $Body
@onready var step_a: CanvasItem = $Body/Legs/StepA
@onready var step_b: CanvasItem = $Body/Legs/StepB

var room: Room = null
var facing: int = 1
var sheet: ActorSheet = null
var sprite: AnimatedSprite2D = null
var direction: int = 0          # sheet row of the current facing (0 = towards the viewer)
## F22 (23.10): the row on screen turns through the neighbouring rows, one every TURN_STEP_S, instead of
## flipping to `direction` (where she heads: speed and stride follow it). From standing she turns on the spot
## (idle frames on the rows in between) and only then walks off; an action waits for the turn.
## I-T2: the step comes from data `turn.seconds_180` (180° = directions / 2 steps), each row change a short
## cross-fade `turn.blend_s` — the pose never jumps.
const TURN_STEP_S: float = 0.07
var turn_step_s: float = TURN_STEP_S
var turn_blend_s: float = 0.0
var shown_dir: int = 0
var _turn_t: float = 0.0
var _turn_hold: Array = []      # [action, node] waiting for the turn to finish

var _walking: bool = false
var _target: Vector2 = Vector2.ZERO
var _pending: Node2D = null
## perform_at: after the walk — {face: Vector2, act: String} (H15: to the chosen cup on the table and touch it).
var _then_act: Dictionary = {}
var _lock_active: bool = false
var _lock_hold: bool = false    # true while an animation switch replays the same frame
var _drawn_pos: Vector2 = Vector2.ZERO          # where the figure is drawn while the current frame is shown
var _trail: PackedVector2Array = PackedVector2Array()   # logical positions of this walk
var _trail_d: PackedFloat32Array = PackedFloat32Array() # arclength at each trail point
var _trail_i: int = 0
var _dist_logical: float = 0.0
var _dist_drawn: float = 0.0
var _last_walk_frame: int = -1
var lock_resyncs: int = 0       # times the drawn figure had to be clamped/re-synced (diagnostics)
var _frame_pending: bool = false  # a frame change seen this frame; settled after the logical step
# One-shot action at a hotspot (data action_anim): plays once, the interaction fires on the key frame.
var _acting: bool = false
var _action: String = ""
var _action_node: Node2D = null
var _action_fired: bool = false
var action_fire_count: int = 0    # interactions fired by actions (tests: exactly once per action)
## Carrying a thing to its place (hotspot data `carry`, G10: the wet kerchief from the bench to the hook):
## "pick" — the hotspot's action; "walk" — on the way to carry.to; "place" — carry.action_anim there. The
## interaction (flags, text, scene) fires once, when the thing is placed — or at once on a click that cuts
## the carry short, so the result is the same either way.
var _carry: Dictionary = {}
var _carry_node: Node2D = null
var _carry_stage: String = ""
var _settling: bool = false       # logical position arrived; the drawn figure is finishing its steps
var walk_time: float = 0.0      # game seconds spent in the current walk (probe/measurements)
var _closest_px: float = INF    # nearest the figure has come to the walk's end (3D: passing by is arriving)
var _path_seg: int = 0           # 3D: the path segment she has reached (path_follow; never goes back)
var _path_n: int = 0
var _path_first := Vector2.INF
var _path_last := Vector2.INF
var _distance_walked: float = 0.0
var _step_phase: int = 0
var _path_ready: bool = false
var _path_wait_frames: int = 0   # physics frames spent waiting for the navigation map / a path

# --- Real 3D mode (actor data `render: "3d"`, block `rt3d`; F8 / ?agata=3d|sprites switch) ---------
## "sprites" (sheets, 8 directions) or "3d" (the same model live: any angle, blended clips).
var render_mode: String = "sprites"
## Forced mode for the whole run (tests, URL ?agata=…, command line --agata=…); "" = actor data.
static var forced_render: String = ""
var view3d: Actor3D = null
var body3d: Sprite2D = null
var _spec: Dictionary = {}
var _rt: Dictionary = {}          # spec.rt3d
var _hide_mat: ShaderMaterial = null
var yaw3d: float = 0.0            # body yaw (radians; 0 = towards the viewer, +90° = screen right)
var yaw3d_target: float = 0.0
var _yaw_v: float = 0.0           # body yaw speed (rad/s): turns set off and settle softly (Actor3D.turn_step)
var _yaw_dir: float = 0.0         # the way the body turns to its target (−1/+1; 0 — settled), chosen once per target
var _yaw_dir_target: float = 0.0
var walk_w: float = 0.0           # idle(0) ↔ walk(1) blend
var walk_phase: float = 0.0       # walk cycle phase, unwrapped (whole cycles count up)
var _turn_step_w: float = 0.0     # stepping while turning on the spot
var _act_t: float = 0.0
var _act_w: float = 0.0
var _act_len: float = 1.0
var _act_speed: float = 1.0
var _act_fading: String = ""      # an action that ended: its last pose fades out
var _act_cfg: Dictionary = {}     # rt3d.actions[act]: the part of the clip played (from/to), a cut, the rate
## Talking (3D only, data rt3d.gesture): while a line of Agata's is on screen she gestures with the talk clip
## (legs from the stance, so the feet stay put), faded in and out over the idle — Director 30.10 «как живая».
var _gest_key: String = ""
var _gest_t: float = 0.0
var _gest_w: float = 0.0
var _gest_on: bool = false
var _gest_rng := RandomNumberGenerator.new()
var _facade_row: int = -1
var _facade_anim: String = ""

## Agata never walks without a navigation path (a straight line would cross furniture and water).
## A freshly added region is queryable only after the map's second sync (~5 physics frames): the
## agent re-queries every frame on its own and she simply stands until the path exists. Only a map
## with no floor at all gives up, after this many frames, without moving or interacting.
const PATH_GIVE_UP_FRAMES: int = 180


func _ready() -> void:
	# The sprite advances its frame in its own (internal) process; run ours after it so the
	# foot-lock offset reads the frame progress of the same render frame.
	process_priority = 10
	_setup_sprite()
	_register_agata_probe()
	_set_step_phase(0)
	_update_depth()


## Walking runs in _process, on the same delta as the sprite's frame clock: the logical position and
## the walk cycle can never drift apart, even when physics ticks are capped under load.
func _process(delta: float) -> void:
	if is_3d():
		_process_3d(delta)
		return
	_turn_tick(delta)
	if _walking:
		_walk_step(delta)
	if _frame_pending:
		_finish_frame_change()
	_update_foot_lock()


## Turning: one row towards `direction` every TURN_STEP_S, the animation going on (same frame) on the new row.
func _turn_tick(delta: float) -> void:
	if sheet == null or sprite == null:
		return
	if shown_dir == direction:
		_turn_t = 0.0
		if not _turn_hold.is_empty():
			var h: Array = _turn_hold
			_turn_hold = []
			if h[1] != null and is_instance_valid(h[1]):
				_start_action(String(h[0]), h[1])
		return
	_turn_t += delta
	if _turn_t >= turn_step_s:
		# one row per step and at most one per frame: a slow frame never skips a row
		_turn_t = minf(_turn_t - turn_step_s, turn_step_s)
		shown_dir = ActorSheet.step_toward(shown_dir, direction, sheet.directions)
		_show_row()


## The current animation on the row `shown_dir`, same frame and progress, no cross-fade (a turn step).
func _show_row() -> void:
	var cur := String(sprite.animation)
	var cut := cur.rfind("_")
	var base := cur.substr(0, cut) if cut > 0 else sheet.idle_action
	var anim := sheet.anim_name(base, shown_dir)
	if anim == cur or not sprite.sprite_frames.has_animation(anim):
		return
	var f := sprite.frame
	var p := sprite.frame_progress
	var playing := sprite.is_playing()
	_lock_hold = true  # a turn step is not a stride
	if turn_blend_s > 0.0:
		ActorCrossfade.begin(sprite, turn_blend_s)
	sprite.play(anim)
	if sprite.sprite_frames.get_frame_count(anim) > f:
		sprite.set_frame_and_progress(f, p)
	if not playing:
		sprite.pause()
	_lock_hold = false


## The drawn figure stands at `_drawn_pos` while a frame is shown: offset from the logical position,
## and scaled for its own depth (so nothing about it changes until the next frame).
func _update_foot_lock() -> void:
	if sprite == null:
		return
	if _lock_active and _walking and sprite.animation.begins_with(sheet.walk_action):
		var s := maxf(absf(scale.y), 0.001)
		var s_drawn := room.depth_scale_at(_drawn_pos) if room != null else s
		sprite.position = (_drawn_pos - global_position) / s
		sprite.scale = sheet.sprite_scale() * (s_drawn / s)
	else:
		sprite.position = Vector2.ZERO
		sprite.scale = sheet.sprite_scale()


## A walk frame changed (k → k+1): the drawn figure advances along the trail by the stance foot's
## slide for this row and frame × scale. Never ahead of the logical position; lag under one cycle.
func _on_frame_changed() -> void:
	if _lock_hold or not _lock_active or not _walking or sheet == null:
		return
	if not sprite.animation.begins_with(sheet.walk_action):
		return
	var f := sprite.frame
	if _last_walk_frame < 0:
		_last_walk_frame = f
		return
	var n := wrapi(f - _last_walk_frame, 0, sheet.walk_frames())
	var s := absf(scale.y)
	for i in n:
		_dist_drawn += sheet.stride_at(direction, _last_walk_frame + i) * s * floor_factor()
	_last_walk_frame = f
	# The sprite ticks before our _process: settle once the logical position has made this frame's
	# step; meanwhile listeners (footfall) already get the new position, as far as the trail goes.
	_drawn_pos = _trail_point(minf(_dist_drawn, _dist_logical))
	_frame_pending = true


func _finish_frame_change() -> void:
	_frame_pending = false
	var s := absf(scale.y)
	if _dist_drawn > _dist_logical + 0.5:
		_dist_drawn = _dist_logical  # would run ahead of the path walked: hold at the logical position
		if not _settling:
			lock_resyncs += 1  # (while settling, the last step simply ends on the target)
	elif _dist_logical - _dist_drawn > sheet.row_cycle_px(direction) * s * floor_factor():
		_dist_drawn = _dist_logical  # more than a cycle behind (timing hiccup): catch up
		lock_resyncs += 1
	_drawn_pos = _trail_point(_dist_drawn)


## Point of this walk's trail at arclength `d` (the drawn figure only moves forward).
func _trail_point(d: float) -> Vector2:
	if _trail.is_empty():
		return global_position
	while _trail_i < _trail.size() - 1 and _trail_d[_trail_i + 1] < d:
		_trail_i += 1
	if _trail_i >= _trail.size() - 1:
		return _trail[_trail.size() - 1]
	var d0: float = _trail_d[_trail_i]
	var d1: float = _trail_d[_trail_i + 1]
	var t := 0.0 if d1 - d0 < 0.0001 else clampf((d - d0) / (d1 - d0), 0.0, 1.0)
	return _trail[_trail_i].lerp(_trail[_trail_i + 1], t)


func _trail_add(p: Vector2, moved: float) -> void:
	_dist_logical += moved
	_trail.append(p)
	_trail_d.append(_dist_logical)
	if _trail_i > 600:  # drop the part the drawn figure has passed
		_trail = _trail.slice(_trail_i)
		_trail_d = _trail_d.slice(_trail_i)
		_trail_i = 0


func _lock_start() -> void:
	_lock_active = sheet != null and sheet.foot_lock and not is_3d()
	_frame_pending = false
	_settling = false
	_drawn_pos = global_position
	_trail = PackedVector2Array([global_position])
	_trail_d = PackedFloat32Array([0.0])
	_trail_i = 0
	_dist_logical = 0.0
	_dist_drawn = 0.0
	# Re-targeted mid-walk: keep counting from the frame on screen; from idle the walk anim starts
	# on the table's start frame (_update_walk_anim).
	_last_walk_frame = sprite.frame if sprite != null and sprite.animation.begins_with(sheet.walk_action) else -1


## Screen position of the drawn figure's feet.
func drawn_position() -> Vector2:
	if sprite == null:
		return global_position
	if _lock_active and _walking:
		return _drawn_pos
	return global_position + sprite.position * scale


## Mean ground per walk frame for the current row, in screen px at the current depth.
func stride_px() -> float:
	if sheet == null:
		return 0.0
	return sheet.row_cycle_px(direction) / float(sheet.walk_frames()) * absf(scale.y) * floor_factor()


## The room's floor foreshortening (rooms data `floor_foreshortening`, default 0.55).
func floor_foreshortening() -> float:
	if room != null and room.room_id != "" and StoryData.rooms.has(room.room_id):
		return float(StoryData.rooms[room.room_id].get("floor_foreshortening", ActorSheet.FLOOR_FORESHORTENING_DEFAULT))
	return ActorSheet.FLOOR_FORESHORTENING_DEFAULT


## Scale of the current row's steps and speed for the room's perspective (1 for profile rows).
func floor_factor() -> float:
	return sheet.row_floor_factor(direction, floor_foreshortening()) if sheet != null else 1.0


## Diagnostics for the probe: how far the drawn figure is behind the logical one along the path.
func lock_lag_px() -> float:
	return _dist_logical - _dist_drawn if _lock_active and _walking else 0.0


func _setup_sprite() -> void:
	if actor_id == "":
		return
	sheet = ActorSheet.load_actor(actor_id)
	if sheet == null or not sheet.is_loaded():
		push_warning("Player: actor '%s' sheet not loaded (%s); using placeholder body" % [actor_id, sheet.load_error if sheet else "?"])
		sheet = null
		return
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.offset = sheet.sprite_offset()
	sprite.sprite_frames = sheet.frames
	sprite.scale = sheet.sprite_scale()  # a k× sheet is drawn at 1/k (G56)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.frame_changed.connect(_on_action_frame)
	sprite.animation_finished.connect(_on_animation_finished)
	add_child(sprite)
	if sheet.shadow_alpha > 0.0:
		sprite.add_child(ActorShadow.make(sheet))  # child of the sprite: follows the foot-lock offset
	body.visible = false
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % actor_id))
	_spec = spec if spec is Dictionary else {}
	_rt = _spec.get("rt3d", {})
	var tn: Dictionary = _spec.get("turn", {})
	if tn.has("seconds_180"):
		turn_step_s = maxf(float(tn["seconds_180"]) / maxf(float(sheet.directions) * 0.5, 1.0), 0.02)
	turn_blend_s = float(tn.get("blend_s", 0.0))
	var want := forced_render if forced_render != "" else _render_from_env()
	if want == "":
		# Director 30.10 (14:38, 14:47): the live model is the figure of the game (Steam); the web build keeps the
		# sheets (`render_web`) — the site has no GPU budget to count on and a 1 GB limit.
		want = String(_spec.get("render_web" if OS.has_feature("web") else "render", "sprites"))
		# Headless test runs keep the sheets (their timings were measured on them); tests of the live model force
		# "3d" (forced_render), the game and the frame shots (a display) get the data's mode.
		if DisplayServer.get_name() == "headless":
			want = "sprites"
	if want == "3d":
		set_render_mode("3d")
	_play_idle()


func uses_sheet() -> bool:
	return sprite != null


## Screen motion → sheet direction row (mapping lives in data/actors/<id>.json).
func direction_index(motion: Vector2) -> int:
	return sheet.direction_index(motion) if sheet != null else 0


func face_towards(target: Vector2) -> void:
	var v := target - global_position
	if sheet != null and v.length_squared() > 1.0:
		if is_3d():
			yaw3d_target = _yaw_for_screen(v)
			_play_idle()
			return
		direction = sheet.direction_index(v)
		_play_idle()


func _play_idle() -> void:
	if sprite == null:
		return
	var anim := sheet.anim_name(sheet.idle_action, direction if is_3d() else shown_dir)
	if sprite.animation != anim and not is_3d():
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.speed_scale = 1.0
	sprite.play(anim)
	_facade_anim = anim


## Drops a running cross-fade (room change: the old pose must not linger in the new room).
func _cut_fade() -> void:
	var fade := get_node_or_null("Crossfade") as CanvasItem
	if fade != null:
		fade.visible = false


## Effective speed in px/s at the current depth and direction row (farther = slower on screen;
## towards/away from the viewer slower than across — the row's cycle on screen, see ActorSheet).
func current_speed_px() -> float:
	var s := absf(scale.y)
	if is_3d():
		return walk_speed_mps_3d() * view3d.ppm * s * _floor_proj(yaw3d) * speed_factor
	if sheet != null:
		return sheet.walk_speed_row_px(direction, s) * floor_factor() * speed_factor
	return walk_speed * s * speed_factor


## Walk-cycle frame rate: constant (frames × speed_mps / cycle_meters), × speed_factor.
func current_walk_fps() -> float:
	if sheet == null:
		return 0.0
	if is_3d():  # cycles per second of the live clip × the sheet's frames (same clip): comparable numbers
		return float(sheet.walk_frames()) * walk_rate_3d() / maxf(view3d.walk_len, 0.01) * speed_factor
	return sheet.walk_fps_const() * speed_factor


## Plays the walk animation through speed_scale so feet match the ground covered; frames are never set by hand.
func _update_walk_anim() -> void:
	if sprite == null:
		return
	var anim := sheet.anim_name(sheet.walk_action, shown_dir)
	var base_fps := sprite.sprite_frames.get_animation_speed(anim)
	var fps := current_walk_fps()
	sprite.speed_scale = fps / base_fps if base_fps > 0.0 else 1.0
	if sprite.animation != anim or not sprite.is_playing():
		var was_walk := String(sprite.animation).begins_with(sheet.walk_action)
		if sprite.animation != anim:
			ActorCrossfade.begin(sprite, sheet.crossfade_s)  # idle→walk or a new direction row
		var frame := sprite.frame
		var progress := sprite.frame_progress
		_lock_hold = true  # switching rows is not a stride: keep the drawn figure where it is
		sprite.play(anim)
		if was_walk and sprite.sprite_frames.get_frame_count(anim) > frame:
			sprite.set_frame_and_progress(frame, progress)  # keep the stride phase across direction changes
		elif not was_walk and sheet.has_stride_table():
			# From standing: start on the table's start frame, so the drawn figure never gets ahead.
			sprite.set_frame_and_progress(sheet.stride_start_frame, 0.0)
		_lock_hold = false
		if not was_walk:
			_last_walk_frame = sprite.frame


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F8 or event.physical_keycode == KEY_F8):
		# Comparison switch (Director): sprites ↔ live 3D, same place, same state.
		set_render_mode("sprites" if is_3d() else "3d")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()


## One click on the room: hotspot/exit → walk to its stand point and interact; else walk there.
## Walks to `to`, turns to `face` and plays the action `act` (no hotspot is triggered): a choice's own little staging
## (rooms data choice.options[].agata_go — H15: Agata carries the chosen cup to the table and touches it).
func perform_at(to: Vector2, face: Vector2, act: String) -> void:
	_then_act = {"face": face, "act": act}
	_pending = null
	if global_position.distance_to(to) < 4.0:
		_arrive()
	else:
		_start_walk(to)


func click_at(world_pos: Vector2) -> void:
	_then_act = {}
	if _carry_stage in ["walk", "place"] and not StoryRunner.is_busy():
		_carry_finish_now()  # a click cuts the carry short: the thing is in its place, the click goes on
	if StoryRunner.is_busy() or _acting:
		return  # dialogue, puzzle, transition or an action in progress owns the input
	_then_act = {}
	var target_node: Node2D = null
	if room != null:
		target_node = room.pick(world_pos)
	if target_node != null:
		walk_to_and_interact(target_node)
	else:
		walk_to(world_pos)


# --- Walking ---------------------------------------------------------------

func is_walking() -> bool:
	return _walking


func walk_to(target: Vector2) -> void:
	_pending = null
	_start_walk(target)


func walk_to_and_interact(node: Node2D) -> void:
	_pending = node
	var stand: Vector2 = node.global_position
	if node.has_method("get_stand_position"):
		stand = node.call("get_stand_position")
	_start_walk(stand)


func _start_walk(target: Vector2) -> void:
	_turn_hold = []
	if _walking:
		_adopt_drawn_position()  # a new target mid-walk: continue from where the figure is drawn
	_target = target
	_path_ready = false
	_path_wait_frames = 0
	nav_agent.target_position = target
	if start_at_mid_stance and is_3d() and not _walking and view3d != null and view3d.shown_w() < 0.05:
		# from standing (Director 30.10 «идеальная Агата»: the planted foot skated 12–15 cm as the stance blended into
		# the stride): the cycle starts in the stance of the foot that already stands where the stride puts it
		var ph := view3d.start_phase(view3d.feet_model(), _rtf("walk", "start_ahead", 0.0))
		if ph >= 0.0:
			walk_phase = floorf(walk_phase) + 1.0 + ph
	_walking = true
	walk_time = 0.0
	_closest_px = INF
	_path_seg = 0
	_path_n = 0
	_lock_start()
	walk_started.emit(target)


## Moves the logical position onto the drawn one (no visible hop when a walk ends or changes).
## The drawn position lies on the trail already walked, so it is on the floor.
func _adopt_drawn_position() -> void:
	if sprite != null and _lock_active:
		global_position = _drawn_pos
		sprite.position = Vector2.ZERO
		sprite.scale = sheet.sprite_scale()
	_lock_active = false


## True once the navigation path for the current walk has been received.
func has_path() -> bool:
	return _path_ready


## Called by RoomManager when a room is entered: binds depth parameters and places the figure.
## J (Director 29.10, стр. 22: «входит в дом — появляется лицом к экрану, не спиной»): coming in through a door she
## faces the room (the screen) at once, not the way she walked into the door on the other side.
func face_screen_dir(v: Vector2) -> void:
	if v.length_squared() < 0.0001:
		return
	if is_3d():
		yaw3d_target = _yaw_for_screen(v)
		yaw3d = yaw3d_target
		_yaw_v = 0.0
		_yaw_dir = 0.0
	elif sheet != null:
		direction = sheet.direction_index(v)
		shown_dir = direction
	_play_idle()


func enter_room(new_room: Room, pos: Vector2) -> void:
	room = new_room
	_walking = false
	_pending = null
	_cancel_action()
	_lock_active = false
	if sprite != null:
		sprite.position = Vector2.ZERO
		sprite.scale = sheet.sprite_scale()
	global_position = pos
	if view3d != null:
		if view3d.follows_room():
			view3d.set_elevation(rad_to_deg(asin(clampf(floor_foreshortening(), 0.1, 0.95))))
		view3d.set_floor_k(floor_foreshortening())
	walk_w = 0.0
	_turn_step_w = 0.0
	_yaw_v = 0.0
	_yaw_dir = 0.0
	if view3d != null:
		view3d.snap_weights()
		view3d.feet_reset()
	_rm_feet = []
	_rm_side = -1
	yaw3d_target = yaw3d
	_set_step_phase(0)
	_play_idle()
	_cut_fade()
	_update_depth()


func _walk_step(delta: float) -> void:
	walk_time += delta
	if nav_agent.is_navigation_finished():
		# The logical position is at the target; the drawn figure finishes its steps (feet still
		# locked) before she stops — she arrives where she was sent, not a stride short.
		if _lock_active and _dist_logical - _dist_drawn > 0.5 and sprite.animation.begins_with(sheet.walk_action):
			_settling = true
			return
		_arrive()
		return
	if nav_agent.get_current_navigation_path().is_empty():
		# Map not synced yet, or it changed under our feet (the agent re-queries each physics
		# frame): stand and wait for a real path. Never walk straight.
		_path_ready = false
		_path_wait_frames += 1
		if _path_wait_frames >= PATH_GIVE_UP_FRAMES:
			push_warning("Player: no navigation path to %s after %d frames; staying put" % [str(_target), _path_wait_frames])
			_cancel_walk()
		return
	_path_ready = true
	var next: Vector2 = nav_agent.get_next_path_position()
	var to_next := next - global_position
	var dist := to_next.length()
	# Direction first (the speed depends on the row); only above a threshold, so tiny path
	# corrections never twitch the sprite.
	if sheet != null and dist > maxf(sheet.direction_threshold_px, 1.0):
		direction = sheet.direction_index(to_next)
	if sheet != null and sprite != null and ActorSheet.row_steps(shown_dir, direction, sheet.directions) > 1 \
			and not String(sprite.animation).begins_with(sheet.walk_action):
		# from standing, more than 45° off the path: turn on the spot first (idle on the rows in between)
		if not String(sprite.animation).begins_with(sheet.idle_action):
			_play_idle()
		_update_depth()
		return
	var step := minf(current_speed_px() * delta, dist)
	if dist > 0.001:
		var motion := to_next / dist * step
		global_position += motion
		_advance_steps(step)
		if absf(motion.x) > 0.01:
			facing = 1 if motion.x > 0.0 else -1
		if _lock_active:
			_trail_add(global_position, step)
		_update_walk_anim()
	_update_depth()


## Stops without reaching the target: no interaction is triggered.
func _cancel_walk() -> void:
	if _carry_stage == "walk":
		_carry_finish_now()
	_walking = false
	_settling = false
	_pending = null
	_adopt_drawn_position()
	_set_step_phase(0)
	_play_idle()
	_update_depth()
	arrived.emit(global_position)


func _arrive() -> void:
	_walking = false
	_settling = false
	_adopt_drawn_position()
	_set_step_phase(0)
	_update_depth()
	if _carry_stage == "walk":
		_carry_arrive()
		return
	if not _then_act.is_empty():
		var ta := _then_act
		_then_act = {}
		_pending = null
		var fv := (ta["face"] as Vector2) - global_position
		if fv.length_squared() > 1.0:
			if is_3d():
				yaw3d_target = _yaw_for_screen(fv)
			else:
				direction = sheet.direction_index(fv)
		arrived.emit(global_position)
		var a := String(ta["act"])
		if a != "" and sheet != null and sheet.has_action(a):
			_start_action(a, null)
		else:
			_play_idle()
		return
	var node := _pending
	_pending = null
	var act := _action_for(node)
	if act != "":
		var v := _look_point(node) - global_position
		if v.length_squared() > 1.0:
			if is_3d():
				yaw3d_target = _yaw_for_screen(v)
			else:
				direction = sheet.direction_index(v)
	elif node != null and is_instance_valid(node):
		face_towards(_look_point(node))
	else:
		_play_idle()
	arrived.emit(global_position)
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		if act != "":
			_start_action(act, node)
			return
		node.call("trigger")
		interaction_performed.emit(node)


## Where Agata looks at a hotspot: rooms data `agata_face` [x, y] on it or its current state (H15: the cup on the sill;
## H29: the sluice lever where it hangs), else the hotspot's own position.
func _look_point(node: Node2D) -> Vector2:
	if node is StoryHotspot:
		var h := node as StoryHotspot
		var af: Array = h.current_state().get("agata_face", h.data.get("agata_face", []))
		if af.size() >= 2:
			return Vector2(float(af[0]), float(af[1]))
		# J (Director 29.10, стр. 89, 157: «Агата отвёрнута от Павла», «стоят от экрана, не смотрят на собеседника»):
		# a person is looked at where they stand — their feet, on the floor as hers — not the middle of the figure's
		# box, which is high above her feet and turned her back to the screen.
		if String(h.data.get("kind", "")) == "npc":
			var room := h.get_parent().get_parent() if h.get_parent() != null else null
			var actor: Node2D = room.get_node_or_null("npc_" + String(h.hotspot_id)) as Node2D if room != null else null
			if actor != null and actor.visible:
				return actor.global_position
			var shape := h.get_node_or_null("Shape") as CollisionShape2D
			if shape != null and shape.shape is RectangleShape2D:
				return h.global_position + Vector2(0, (shape.shape as RectangleShape2D).size.y * 0.5)
	return node.global_position


# --- One-shot actions at hotspots ------------------------------------------

## The hotspot's action animation (rooms data `action_anim`: open / pick / reach), when the click
## would change something (use, item use, choice) and the sheet has that action; else "".
func _action_for(node: Node2D) -> String:
	if sheet == null or node == null or not is_instance_valid(node) or not (node is StoryHotspot):
		return ""
	var act := String((node as StoryHotspot).data.get("action_anim", ""))
	if act == "" or not sheet.has_action(act):
		return ""
	var plan: String = StoryRunner.planned_interaction(node)
	return act if plan in ["use", "item_use", "choice"] else ""


func _start_action(act: String, node: Node2D) -> void:
	if not is_3d() and sheet != null and shown_dir != direction:
		# turn towards the hotspot first (F22); the action starts when the drawn row arrives
		_turn_hold = [act, node]
		_play_idle()
		return
	_acting = true
	_action = act
	_action_node = node
	_action_fired = false
	if _carry_stage == "" and node is StoryHotspot and not ((node as StoryHotspot).data.get("carry", {}) as Dictionary).is_empty():
		_carry = (node as StoryHotspot).data["carry"]
		_carry_node = node
		_carry_stage = "pick"
	if is_3d():
		_start_action_3d(act, node)
		action_started.emit(act, node)
		return
	var anim := sheet.anim_name(act, shown_dir)
	if sprite.animation != anim:
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.speed_scale = 1.0
	sprite.play(anim)
	action_started.emit(act, node)


func is_acting() -> bool:
	# an action waiting for the turn counts (F22), and so does the whole carry (G10: pick → walk → place)
	return _acting or not _turn_hold.is_empty() or _carry_stage != ""


func current_action() -> String:
	return _action if _acting else ""


## Key frame reached (or the clip ended without it): the interaction happens — exactly once.
func _fire_action() -> void:
	if _action_fired:
		return
	_action_fired = true
	if _carry_stage == "pick":
		_carry_set_layers(true)  # taken: gone from its old place, on its way
		return
	var node := _action_node
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		action_fire_count += 1
		node.call("trigger")
		interaction_performed.emit(node)
	if _carry_stage == "place":
		_carry_end()


func _on_action_frame() -> void:
	if _acting and not _action_fired and sprite.animation.begins_with(_action + "_") and sprite.frame >= sheet.action_key_frame(_action):
		_fire_action()


func _on_animation_finished() -> void:
	if not _acting:
		return
	_fire_action()
	if is_3d():
		_act_fading = _action  # the last pose of the clip fades into the idle
	var act := _action
	var node := _action_node
	_acting = false
	_action = ""
	_action_node = null
	_play_idle()
	action_finished.emit(act, node)
	if _carry_stage == "pick":
		_carry_stage = "walk"
		var to: Array = _carry.get("to", [])
		if to.size() >= 2:
			_pending = null
			_start_walk(Vector2(float(to[0]), float(to[1])))
		else:
			_carry_arrive()


## The carry's walk ended at carry.to: face carry.face and place the thing (carry.action_anim).
func _carry_arrive() -> void:
	var fc: Array = _carry.get("face", [])
	if fc.size() >= 2:
		var v := Vector2(float(fc[0]), float(fc[1])) - global_position
		if v.length_squared() > 1.0:
			if is_3d():
				yaw3d_target = _yaw_for_screen(v)
			else:
				direction = sheet.direction_index(v)
	arrived.emit(global_position)
	var act := String(_carry.get("action_anim", ""))
	if _carry_node == null or not is_instance_valid(_carry_node) or act == "" or sheet == null or not sheet.has_action(act):
		_carry_finish_now()
		_play_idle()
		return
	_carry_stage = "place"
	_start_action(act, _carry_node)


## The carry ends now with its full result (a click cut it short, or the placing could not play).
func _carry_finish_now() -> void:
	if _carry_stage == "":
		return
	var node := _carry_node
	var placing := _acting and _carry_stage == "place"
	_carry_end()
	_turn_hold = []  # a placing still waiting for the turn never starts
	if placing:
		_acting = false
		_action = ""
		_action_node = null
		_play_idle()
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		action_fire_count += 1
		node.call("trigger")
		interaction_performed.emit(node)


func _carry_end() -> void:
	_carry_set_layers(false)
	_carry = {}
	_carry_node = null
	_carry_stage = ""


## Layers of carry.show_layers shown ahead of their flags while the thing is carried (the bare bench).
func _carry_set_layers(on: bool) -> void:
	if room == null or not is_instance_valid(room):
		return
	for id in _carry.get("show_layers", []):
		var l := room.find_child(String(id), true, false) as StateLayer
		if l != null:
			l.set_forced(on)


## Carry stage for tests and the web probe: "", "pick", "walk", "place".
func carry_stage() -> String:
	return _carry_stage


## Room change / load: the action is dropped without its effect (nothing half-applied).
func _cancel_action() -> void:
	if _carry_stage != "":
		_carry_end()  # room change / load: dropped without its effect, like any action
	_acting = false
	_action = ""
	_action_node = null
	_action_fired = false
	_act_fading = ""
	_act_w = 0.0
	if view3d != null:
		view3d.snap_weights()


# --- Step animation (distance driven) -------------------------------------

func _advance_steps(moved: float) -> void:
	_distance_walked += moved / maxf(absf(scale.y), 0.05)
	var phase := int(floor(_distance_walked / step_length)) % 2
	if phase != _step_phase:
		_set_step_phase(phase)


func _set_step_phase(phase: int) -> void:
	_step_phase = phase
	# Alpha instead of `visible`: a visibility toggle forces a Polygon2D redraw/re-upload each
	# step, which under WebGL spams "INVALID_OPERATION: bindBuffer" warnings. Modulate does not.
	if step_a != null:
		step_a.self_modulate.a = 1.0 if phase == 0 else 0.0
	if step_b != null:
		step_b.self_modulate.a = 1.0 if phase == 1 else 0.0
	if body != null:
		body.position.y = -bob_height if phase == 1 else 0.0


# --- Depth -----------------------------------------------------------------

func _update_depth() -> void:
	var s := 1.0
	if room != null:
		s = room.depth_scale_at(global_position)
	# Sheets carry every direction, so no mirroring; the placeholder body flips on `facing`.
	scale = Vector2(s, s) if sprite != null else Vector2(s * facing, s)
	z_index = clampi(int(global_position.y), -4096, 4096)
	if is_3d():
		_update_view3d_scale()


# --- Real 3D mode -------------------------------------------------------------------------------
# The same model the sheets were rendered from, live (Actor3D). Everything around the figure stays
# 2D and unchanged: the "Sprite" node is kept as a facade with the sheet frames (drawn invisible) —
# it carries the contact ellipse and cast light shadows, the room tone, the mirror's frames, and its
# frame number follows the live clip phase, so footsteps, prints and the key frame of an action fire
# at the same moments of the same clips. The live picture is the Body3D child of the facade.

const HIDE_SHADER_CODE := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.0); }\n"


func is_3d() -> bool:
	return render_mode == "3d" and view3d != null and view3d.ok


## Mode requested outside the data: command line `--agata=3d|sprites` (after `--`), URL `?agata=…`.
static func _render_from_env() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--agata="):
			return String(a).get_slice("=", 1)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('agata') || ''", true)
		if q != null and String(q) in ["3d", "sprites"]:
			return String(q)
	return ""


func _rtf(section: String, key: String, def: float) -> float:
	var d: Dictionary = _rt.get(section, {}) if section != "" else _rt
	return float(d.get(key, def))


## Switches the figure between the sheets and the live model, in place (a walk or an action in
## progress is stopped without its effect). Returns false when the 3D model cannot be loaded.
func set_render_mode(mode: String) -> bool:
	if sprite == null or sheet == null:
		return false
	if mode == render_mode and (mode != "3d" or is_3d()):
		return true
	if _walking:
		_cancel_walk()
	if _acting:
		_cancel_action()
	if mode == "3d":
		if view3d == null:
			view3d = Actor3D.new()
			add_child(view3d)
			if not view3d.setup(_spec):
				push_warning("Player: 3D model not loaded (%s); staying on sprites" % view3d.load_error)
				view3d.queue_free()
				view3d = null
				return false
			if view3d.follows_room():
				view3d.set_elevation(rad_to_deg(asin(clampf(floor_foreshortening(), 0.1, 0.95))))
			view3d.set_floor_k(floor_foreshortening())
			body3d = Sprite2D.new()
			body3d.name = "Body3D"
			body3d.centered = false
			body3d.texture = view3d.get_texture()
			body3d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			if bool(_rt.get("premultiplied", true)):
				var cm := CanvasItemMaterial.new()
				cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
				body3d.material = cm
			sprite.add_child(body3d)
		view3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		body3d.visible = true
		if _hide_mat == null:
			var sh := Shader.new()
			sh.code = HIDE_SHADER_CODE
			_hide_mat = ShaderMaterial.new()
			_hide_mat.shader = sh
		sprite.material = _hide_mat
		render_mode = "3d"
		yaw3d = _yaw_for_row(direction)
		yaw3d_target = yaw3d
		_yaw_v = 0.0
		_yaw_dir = 0.0
		walk_w = 0.0
		_turn_step_w = 0.0
		_act_w = 0.0
		_act_fading = ""
		view3d.snap_weights()
		var fade := get_node_or_null("Crossfade") as CanvasItem
		if fade != null:
			fade.visible = false
		_update_depth()
		_process_3d(0.0)
	else:
		render_mode = "sprites"
		if view3d != null:
			view3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if body3d != null:
			body3d.visible = false
		sprite.material = null
		sprite.position = Vector2.ZERO
		sprite.scale = sheet.sprite_scale()
		_play_idle()
	return true


## Floor heading (yaw) of a screen vector: the room's floor is foreshortened by k vertically.
func _yaw_for_screen(v: Vector2) -> float:
	return atan2(v.x, v.y / maxf(floor_foreshortening(), 0.05))


## Screen direction of a body yaw (y down; length = how much a floor metre shrinks that way).
func _screen_of_yaw(y: float) -> Vector2:
	return Vector2(sin(y), cos(y) * floor_foreshortening())


func _floor_proj(y: float) -> float:
	return _screen_of_yaw(y).length()


func _yaw_for_row(row: int) -> float:
	if sheet == null:
		return 0.0
	var a := deg_to_rad(90.0 - 360.0 / float(sheet.directions) * float(row))
	if sheet.direction_order == "cw":
		a = deg_to_rad(90.0 + 360.0 / float(sheet.directions) * float(row))
	return _yaw_for_screen(Vector2(cos(a), sin(a)))


## Playback rate of the walk clip (data rt3d.walk.playback_rate; 1 = the clip's own cadence).
func walk_rate_3d() -> float:
	return _rtf("walk", "playback_rate", 1.0)


## Walking speed in floor metres per second (clip stride × cadence × rate).
func walk_speed_mps_3d() -> float:
	return view3d.walk_speed_mps * walk_rate_3d() if view3d != null else 0.0


func _process_3d(delta: float) -> void:
	if _walking:
		_walk_step_3d(delta)
	else:
		walk_w = move_toward(walk_w, 0.0, delta / maxf(_rtf("walk", "decel_s", 0.3), 0.01))
	_turn_3d(delta)
	var act_name := ""
	if _acting:
		_act_t = minf(_act_t + delta * _act_speed, _act_len)
		_act_w = move_toward(_act_w, 1.0, delta / maxf(_rtf("action", "fade_in_s", 0.2), 0.01))
		# the stance fades back in over the clip's last fade_out_s, while the clip still moves (not over a frozen
		# last pose after it)
		var left_s := (_act_len - _act_t) / maxf(_act_speed, 0.01)
		_act_w = minf(_act_w, left_s / maxf(_rtf("action", "fade_out_s", 0.35), 0.01))
		act_name = _action
	elif _act_fading != "":
		_act_w = move_toward(_act_w, 0.0, delta / maxf(_rtf("action", "fade_out_s", 0.35), 0.01))
		act_name = _act_fading
		if _act_w <= 0.0:
			_act_fading = ""
	var act_w := _act_w
	var ct := _act_clip_times(_act_t)
	if act_name == "" and _gesture_3d(delta):
		act_name = "talk"
		act_w = _gest_w
		ct = Actor3D.loop_times(_gest_t, view3d.action_length("talk"), float(_rt.get("gesture", {}).get("crossfade_s", 0.6)))
	view3d.set_yaw(yaw3d)
	_look_3d()
	var blend := maxf(walk_w, _turn_step_w)
	var probe: Array = []
	if root_motion_3d and _walking and _rm_side >= 0:
		# new phase, everything else as shown last frame: only the walk itself moves the planted foot
		probe = view3d.feet_at_phase(fposmod(walk_phase, 1.0))
	view3d.pose(delta, fposmod(walk_phase, 1.0), blend, act_w, act_name, float(ct[0]), float(ct[1]), float(ct[2]))
	_root_motion_3d(probe, blend)
	if foot_lock_3d:
		var ppm_s := view3d.ppm * maxf(absf(scale.y), 0.01)
		view3d.feet_step(delta, global_position, Vector2(ppm_s, ppm_s * maxf(floor_foreshortening(), 0.05)))
	_sync_facade_3d()
	_sync_body3d()
	if _acting and _act_t >= _act_len - 0.0001:
		_on_animation_finished()


## Where Agata looks (rt3d.look; Actor3D.set_look): at the one who has the line — or, her own line, at the one she
## speaks to (beat `to`) — then at the thing she does (action) or goes to (a hotspot within walk_look_px); else nowhere
## in particular (the clip and the breathing lead the head). A villager is looked at in the eyes, a thing at thing_m.
func _look_3d() -> void:
	if view3d == null or view3d.look == null:
		return
	var lk: Dictionary = _rt.get("look", {})
	var target := Vector2.INF
	var h := float(lk.get("thing_m", 1.0))
	var on_floor := false
	var b: Dictionary = StoryRunner.current_beat
	if String(b.get("type", "")) == "line":
		var sp := String(b.get("speaker", ""))
		var who := String(b.get("to", "")) if sp == "agata" else sp
		var n := _speaker_node(who)
		if n != null:
			target = n.global_position
			if n.get("actor_id") != null:
				on_floor = true    # a villager: his feet are on the floor; look at the eyes
				h = float(lk.get("speaker_eye_m", 1.5))
				var lv = n.get("live")
				if lv != null and lv.view != null:
					h = lv.view.bone_model("Head").y + 0.06
	if target == Vector2.INF and (_acting or not _turn_hold.is_empty()) and _action_node != null and is_instance_valid(_action_node):
		target = _look_point(_action_node)
	if target == Vector2.INF and _walking and _pending != null and is_instance_valid(_pending):
		var lp := _look_point(_pending)
		if lp.distance_to(global_position) < float(lk.get("walk_look_px", 520.0)):
			target = lp
	if target == Vector2.INF:
		view3d.set_look(Vector3.ZERO, false)
		return
	var s := absf(scale.y)
	var ppm_s := view3d.ppm * maxf(s, 0.01)
	var e := deg_to_rad(view3d.elev_deg)
	var d := target - global_position
	if not on_floor:
		d.y += h * ppm_s * cos(e)     # a point drawn at height h: its floor point lies below it on screen
	var k := maxf(floor_foreshortening(), 0.05)
	view3d.set_look(Vector3(d.x / ppm_s, h, d.y / (ppm_s * k)), true)


## The node of a character in the room: a villager (NpcActor actor_id) or a hotspot with that id (Tikhon).
func _speaker_node(who: String) -> Node2D:
	if who == "" or who == "agata" or room == null:
		return null
	for c in room.get_children():
		if c is Node2D and String(c.get("actor_id") if c.get("actor_id") != null else "") == who:
			return c
	for c in room.get_children():
		if c is StoryHotspot and String((c as StoryHotspot).data.get("id", "")) == who:
			return c
	return null


## The talk gesture's weight and time this frame; false when it is not shown. A new line of Agata's (long enough,
## standing) starts the clip at a random early point, so lines do not all open with the same hand; the clip is
## blended in its whole length (it starts and ends in the stance) and, while the line lasts, its end fades into
## its start again (gesture.crossfade_s) — no seam.
func _gesture_3d(delta: float) -> bool:
	var g: Dictionary = _rt.get("gesture", {})
	if g.is_empty() or view3d == null or not view3d.clips.has("talk"):
		return false
	var b: Dictionary = StoryRunner.current_beat
	var talking := String(b.get("type", "")) == "line" and String(b.get("speaker", "")) == "agata" and not _walking \
		and String(b.get("text", "")).length() >= int(g.get("min_chars", 24))
	var key := String(b.get("line_id", "")) + "|" + String(b.get("text", ""))
	var len_s := view3d.action_length("talk")
	if talking and key != _gest_key:
		_gest_key = key
		if _gest_w < 0.05:
			_gest_t = _gest_rng.randf_range(0.0, float(g.get("start_jitter", 0.2))) * len_s
		_gest_on = true
	elif not talking:
		_gest_on = false
		_gest_key = "" if b.is_empty() else _gest_key
	var fade := float(g.get("fade_in_s", 0.5)) if _gest_on else float(g.get("fade_out_s", 0.7))
	_gest_w = move_toward(_gest_w, float(g.get("weight", 0.85)) if _gest_on else 0.0, delta / maxf(fade, 0.01))
	if _gest_w <= 0.0 and view3d.shown_act_w() < 0.001:
		return false
	# runs on through the clip's passes; Actor3D.loop_times crossfades the end of one pass into the next
	_gest_t += delta * float(g.get("rate", 1.0))
	return true


## Body yaw eases towards its target (capped turn rate, and the rate itself changes softly — turn.accel_deg_s2 —
## so a turn sets off and settles without a jolt): any angle, no step.
## Standing, a big turn is taken with small steps (a little of the walk on the spot).
func _turn_3d(delta: float) -> void:
	var diff := angle_difference(yaw3d, yaw3d_target)
	var sf := maxf(speed_factor, 1.0)
	var cap := deg_to_rad(_rtf("turn", "max_deg_s", 400.0 if _walking else 300.0)) * sf
	var r := Actor3D.turn_step(Vector4(yaw3d, _yaw_v, _yaw_dir, _yaw_dir_target), yaw3d_target, delta, cap, _rtf("turn", "ease_per_s", 9.0) * sf, deg_to_rad(_rtf("turn", "accel_deg_s2", 1500.0)) * sf * sf)
	yaw3d = r.x
	_yaw_v = r.y
	_yaw_dir = r.z
	_yaw_dir_target = r.w
	var stepping := not _acting and walk_w < 0.3 and absf(diff) > deg_to_rad(_rtf("turn", "step_above_deg", 50.0))
	var sw := _rtf("turn", "step_weight", 0.3) if stepping else 0.0
	_turn_step_w = move_toward(_turn_step_w, sw, delta / 0.2)
	if _turn_step_w > 0.001 and walk_w <= 0.001 and view3d != null:
		walk_phase += delta * walk_rate_3d() / maxf(view3d.walk_len, 0.01)


## Root motion from the posed skeleton: the foot that was planted last frame (the lower one) must not
## move on the floor — the figure moves by exactly its displacement, R(yaw_old)·foot_old − R(yaw)·foot,
## forward and sideways, so turning happens on the planted foot as people do. Only while walking, and
## × walk weight / blended weight (stepping on the spot while turning moves nothing). Kept on the floor:
## a position off the navigation mesh is pulled back to its closest point.
var _rm_feet: Array = []
var _rm_side: int = -1
var _rm_yaw: float = 0.0
var _rm_blend: float = 0.0
var rm_last_px: Vector2 = Vector2.ZERO   # this frame's root motion on screen (tests, probe)
## Off only in the foot test's self-check: the figure then slides along the path at constant speed.
var root_motion_3d: bool = true
## A walk from standing starts in the stance of the foot already under her (Actor3D.start_phase); off — probes.
var start_at_mid_stance: bool = true
## Setting off, the planted foot stays put through the blend into the stride too (off — probes).
var plant_on_start: bool = true
## Feet locked to the floor while set down (Actor3D.feet_step; off — probes).
var foot_lock_3d: bool = true
var _rm_shown_w: float = 0.0


func _root_motion_3d(probe: Array, blend: float) -> void:
	rm_last_px = Vector2.ZERO
	if not probe.is_empty() and not _rm_feet.is_empty() and _rm_blend > 0.001 and walk_w > 0.001:
		var f_old: Vector3 = _rm_feet[_rm_side * 2]
		var f_new: Vector3 = probe[_rm_side * 2]
		var r_old := Basis(Vector3.UP, _rm_yaw)
		# walking part: the planted foot slid back in the body frame; turning part: the body turned about
		# the planted foot. Turning on a foot is what walking people do; starting from a stand (low weight)
		# she turns about her centre instead — no lurch sideways while she is still almost standing.
		var share := clampf(walk_w / maxf(_rm_blend, 0.001), 0.0, 1.0)
		var walk_part: Vector3 = r_old * (f_old - f_new) * share
		# setting off (the shown walk weight rising; Director 30.10 «идеальная Агата»): the planted foot is kept on the
		# floor through the blend from the stance into the stride too — it skated 10–15 cm back as she set off. Only
		# while the weight rises: stopping keeps the figure exactly at the end of its path.
		if plant_on_start and view3d.shown_w() > _rm_shown_w + 1e-5:
			var posed: Array = view3d.feet_model()
			walk_part += r_old * (f_new - (posed[_rm_side * 2] as Vector3))
		var turn_part: Vector3 = (r_old * f_new - Basis(Vector3.UP, yaw3d) * f_new) * clampf(walk_w, 0.0, 1.0)
		var d := Vector2(walk_part.x + turn_part.x, walk_part.z + turn_part.z)
		var ppm_s := view3d.ppm * absf(scale.y)
		var mv := Vector2(d.x * ppm_s, d.y * ppm_s * floor_foreshortening())
		var remaining := global_position.distance_to(_target) if nav_agent.is_navigation_finished() else float(path_follow(nav_agent.get_current_navigation_path(), global_position, _path_seg, 0.0)[2])
		if mv.length() > remaining and remaining < 12.0:
			mv = mv.normalized() * remaining  # never past the end of the walk
		var np := global_position + mv
		var nm := nav_agent.get_navigation_map()
		if nm.is_valid() and NavigationServer2D.map_get_iteration_id(nm) > 0:
			var cp := NavigationServer2D.map_get_closest_point(nm, np)
			if cp.distance_to(np) > 0.5:
				np = cp
		rm_last_px = np - global_position
		global_position = np
		_advance_steps(rm_last_px.length())
		if absf(rm_last_px.x) > 0.01:
			facing = 1 if rm_last_px.x > 0.0 else -1
		_update_depth()
	_rm_feet = view3d.feet_model()
	# planted foot: the lower one while mostly walking (exact); in a light blend with the idle the lower
	# foot can be the swinging one — then the one the walk clip has planted at this phase
	if blend >= 0.5:
		_rm_side = 0 if minf(_rm_feet[0].y, _rm_feet[1].y) <= minf(_rm_feet[2].y, _rm_feet[3].y) else 1
	else:
		_rm_side = view3d.stance_at(walk_phase)
	_rm_yaw = yaw3d
	_rm_blend = blend
	_rm_shown_w = view3d.shown_w()


func _walk_step_3d(delta: float) -> void:
	walk_time += delta
	if nav_agent.is_navigation_finished():
		_arrive()  # within the agent's tolerance (target_desired_distance), like the sheets
		return
	if nav_agent.get_current_navigation_path().is_empty():
		_path_ready = false
		_path_wait_frames += 1
		if _path_wait_frames >= PATH_GIVE_UP_FRAMES:
			push_warning("Player: no navigation path to %s after %d frames; staying put" % [str(_target), _path_wait_frames])
			_cancel_walk()
		return
	_path_ready = true
	nav_agent.get_next_path_position()   # the agent keeps its own bookkeeping (path updates, finished)
	var path := nav_agent.get_current_navigation_path()
	var n := path.size()
	if n != _path_n or path[0] != _path_first or path[n - 1] != _path_last:
		_path_n = n
		_path_first = path[0]
		_path_last = path[n - 1]
		_path_seg = 0
	var px_m := view3d.ppm * absf(scale.y)
	var pf := path_follow(path, global_position, _path_seg, _rtf("walk", "lookahead_m", 0.25) * px_m)
	_path_seg = int(pf[1])
	var rem: float = pf[2]
	var goal_pt: Vector2 = path[n - 1]
	var d_goal := global_position.distance_to(goal_pt)
	if rem <= nav_agent.target_desired_distance or d_goal <= nav_agent.target_desired_distance:
		_arrive()   # at the end of the path, whatever corners the agent still counts
		return
	# passing by (Director 30.10, 19:16 «крутится на 360, прежде чем повернуться»): a short walk that sets off facing
	# away curves in, misses the point by a few centimetres, goes on past it, stops, turns round and walks back —
	# a half turn more for nothing. On the last leg, once she has come within pass_m and moves away again, she is
	# there.
	var pass_px := _rtf("walk", "pass_m", 0.1) * px_m
	if d_goal < _closest_px:
		_closest_px = d_goal
	elif _closest_px < pass_px and d_goal > _closest_px + 0.5 and _path_seg >= n - 2:
		_arrive()
		return
	var to_next: Vector2 = (pf[0] as Vector2) - global_position
	_move_3d(to_next, to_next.length(), rem, delta)


## Following the path (Director 30.10 «крутится»): she used to steer at the agent's next corner; a body that turns
## with its momentum passes a corner a centimetre or two wider than the agent's 10 px, the corner is then behind her,
## and she stopped, turned round, walked back and missed it again (M1: 228–386° one way for a path asking 44°). Now
## she heads for a point `lookahead` px ahead of her along the path, measured from where she is nearest to it and
## never going back past a segment she has reached: it rounds the corners and is always in front of her.
## Returns [that point, the segment she is on, the path left from her (px), her nearest point on it].
static func path_follow(path: PackedVector2Array, pos: Vector2, seg_from: int, lookahead: float) -> Array:
	var n := path.size()
	if n == 0:
		return [pos, 0, 0.0, pos]
	if n == 1:
		return [path[0], 0, pos.distance_to(path[0]), path[0]]
	var j0 := clampi(seg_from, 0, n - 2)
	var best_d := INF
	var best_j := j0
	var best_p: Vector2 = path[j0]
	for j in range(j0, mini(j0 + 3, n - 1)):   # the next few segments only: never back, never across the room
		var a: Vector2 = path[j]
		var ab: Vector2 = path[j + 1] - a
		var t := 0.0 if ab.length_squared() < 1e-6 else clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := pos.distance_to(q)
		if d < best_d - 0.01:
			best_d = d
			best_j = j
			best_p = q
	var left := lookahead
	var at := best_p
	var j := best_j
	var carrot: Vector2 = path[n - 1]
	while j < n - 1:
		var nxt: Vector2 = path[j + 1]
		var seg := at.distance_to(nxt)
		if seg >= left and seg > 1e-6:
			carrot = at + (nxt - at) / seg * left
			break
		left -= seg
		at = nxt
		j += 1
	var rem := best_d
	at = best_p
	for k in range(best_j, n - 1):
		rem += at.distance_to(path[k + 1])
		at = path[k + 1]
	return [carrot, best_j, rem, best_p]


## Length of the rest of the navigation path from the current position (screen px).
func _remaining_px() -> float:
	var path := nav_agent.get_current_navigation_path()
	var i := nav_agent.get_current_navigation_path_index()
	var total := 0.0
	var prev := global_position
	for j in range(clampi(i, 0, path.size()), path.size()):
		total += prev.distance_to(path[j])
		prev = path[j]
	return total


## One frame of walking: heading → yaw target; locomotion weight up to 1, eased down over the last
## `stop_m`; the walk phase advances with the clip's cadence; the figure moves by exactly the ground
## the stance foot slid back over that phase (root motion), × the weight, projected on the room floor.
func _move_3d(dir: Vector2, seg_len: float, remaining: float, delta: float) -> void:
	if dir.length_squared() < 1e-6:
		return
	var s := absf(scale.y)
	var yaw_dir := _yaw_for_screen(dir)
	if global_position.distance_to(_target) > 24.0 or walk_time < 0.2:
		yaw3d_target = yaw_dir  # the last few px: keep the heading (the direction to a point that close jitters)
	var px_per_m := view3d.ppm * s * _floor_proj(yaw_dir)
	var stop_px := _rtf("walk", "stop_m", 0.45) * px_per_m
	var goal := 1.0 if remaining > stop_px else sqrt(clampf(remaining / maxf(stop_px, 0.001), 0.0, 1.0))
	var off := absf(angle_difference(yaw3d, yaw3d_target))
	# facing away from the path: turn first (on the spot, with small steps), then walk on — also in the last stretch
	# (Director 30.10, 19:16 «крутится на 360, прежде чем повернуться»: within stop_m of the end she used to keep
	# walking while turning towards the point, and circled round it before she faced it)
	goal *= clampf((cos(off) - 0.2) / 0.6, 0.0, 1.0)
	if goal > walk_w:
		walk_w = minf(walk_w + delta * maxf(speed_factor, 1.0) / maxf(_rtf("walk", "accel_s", 0.35), 0.01), goal)
	else:
		walk_w = maxf(walk_w - delta * maxf(speed_factor, 1.0) / maxf(_rtf("walk", "decel_s", 0.3), 0.01), goal)
	if walk_w > 0.001:
		walk_phase += delta * speed_factor * walk_rate_3d() * (0.55 + 0.45 * walk_w) / maxf(view3d.walk_len, 0.01)
	# the figure itself moves by root motion after the pose (_root_motion_3d)
	if not root_motion_3d:
		# self-check of the foot test only: constant speed along the path, feet free to skate
		var step := minf(walk_speed_mps_3d() * walk_w * px_per_m * delta * speed_factor, seg_len)
		global_position += dir.normalized() * step
		_update_depth()


## One-shot action in 3D. Data rt3d.actions[act]: the part of the clip played (`from`, `to`, s), an optional cut
## (`cut` [from, to, crossfade s]: a long hold inside the clip skipped by a crossfade of the clip into itself) and
## the playback `rate` (1 = the clip's own speed: a hand moves as fast as the motion capture moved it); old data
## `duration_s` sets the rate from the length instead.
func _start_action_3d(act: String, _node: Node2D) -> void:
	_act_fading = ""
	_act_t = 0.0
	var clip_len := maxf(view3d.action_length(act), 0.05)
	_act_cfg = _rt.get("actions", {}).get(act, {}).duplicate()
	var from := clampf(float(_act_cfg.get("from", 0.0)), 0.0, clip_len)
	var to := clampf(float(_act_cfg.get("to", clip_len)), from + 0.05, clip_len)
	_act_cfg["from"] = from
	_act_cfg["to"] = to
	_act_len = to - from
	var cut: Array = _act_cfg.get("cut", [])
	if cut.size() >= 2 and float(cut[0]) > from and float(cut[1]) > float(cut[0]) and float(cut[1]) < to:
		_act_len = (float(cut[0]) - from) + (to - float(cut[1]))
	else:
		_act_cfg.erase("cut")
	_act_len = maxf(_act_len, 0.05)
	if _act_cfg.has("rate"):
		_act_speed = clampf(float(_act_cfg["rate"]), 0.2, 3.0)
	else:
		var a: Dictionary = sheet.actions.get(act, {})
		var sheet_s := float(a.get("frames", 16)) / maxf(float(a.get("fps", 12)), 1.0)
		_act_speed = _act_len / maxf(float(_act_cfg.get("duration_s", sheet_s)), 0.1)
	_act_w = minf(_act_w, 1.0)


## Clip times of the action at action time `tau` (0.._act_len): [act slot, act2 slot, mix] — before a cut the clip
## plays on; over the crossfade the part after the cut fades in; then it plays from there.
func _act_clip_times(tau: float) -> Array:
	var from := float(_act_cfg.get("from", 0.0))
	var cut: Array = _act_cfg.get("cut", [])
	if cut.size() < 2:
		return [from + tau, 0.0, 0.0]
	var tc := float(cut[0]) - from
	var xf := clampf(float(cut[2]) if cut.size() > 2 else 0.35, 0.0, 1.5)
	if tau < tc:
		return [from + tau, 0.0, 0.0]
	if tau < tc + xf and xf > 0.0:
		var m := (tau - tc) / xf
		return [from + tau, float(cut[1]) + (tau - tc), m * m * (3.0 - 2.0 * m)]
	return [float(cut[1]) + (tau - tc), 0.0, 0.0]


## The facade (sheet sprite, drawn invisible) shows the row nearest to the yaw and the frame of the
## same clip phase: frame_changed fires where the sheet version fires (footsteps, prints, key frames).
func _sync_facade_3d() -> void:
	var row := sheet.direction_index(_screen_of_yaw(yaw3d))
	direction = row
	var anim := ""
	var frame := -1
	if _acting:
		anim = sheet.anim_name(_action, row)
		if sprite.sprite_frames.has_animation(anim):
			var n := sprite.sprite_frames.get_frame_count(anim)
			frame = clampi(int(_act_t / _act_len * float(n)), 0, n - 1)
	elif _walking and walk_w > 0.02:
		anim = sheet.anim_name(sheet.walk_action, row)
		var nw := sheet.walk_frames()
		frame = int(fposmod(walk_phase, 1.0) * float(nw)) % nw
	else:
		anim = sheet.anim_name(sheet.idle_action, row)
	if not sprite.sprite_frames.has_animation(anim):
		return
	_facade_anim = anim
	if frame < 0:
		if sprite.animation != anim or not sprite.is_playing():
			sprite.speed_scale = 1.0
			sprite.play(anim)
		return
	if sprite.animation != anim:
		# a new row or clip is not a step: switch silently, then let the frame change speak
		var prev := sprite.frame
		_lock_hold = true
		sprite.set_block_signals(true)
		sprite.play(anim)
		sprite.pause()
		sprite.set_frame_and_progress(clampi(prev, 0, sprite.sprite_frames.get_frame_count(anim) - 1), 0.0)
		sprite.set_block_signals(false)
		_lock_hold = false
	if sprite.is_playing():
		sprite.pause()
	if sprite.frame != frame:
		sprite.frame = frame


func _sync_body3d() -> void:
	if body3d == null:
		return
	body3d.self_modulate = sprite.self_modulate  # the room tone (RoomLighting tones the facade)
	body3d.visibility_layer = visibility_layer


## The live frame is rendered at about its on-screen size (depth scale × window stretch).
func _update_view3d_scale() -> void:
	if view3d == null or body3d == null:
		return
	var s := absf(scale.y)
	var win := 1.0
	if is_inside_tree():
		win = maxf(get_viewport().get_final_transform().get_scale().y, 0.25)
	view3d.set_render_scale(s * win * _rtf("", "supersample", 1.0))
	body3d.offset = view3d.sprite_offset()
	body3d.scale = Vector2.ONE * sheet.texture_scale / view3d.render_scale  # under the facade sprite (1/k)


# --- Web measurement hooks (only with ?agataprobe in the URL; tools/agata_fps.mjs) ----------------
#   agataMode("3d"|"sprites") — switch in place;  agataState — JSON every 0.25 s: mode, fps, yaw, walk
#   weight, render scale and size of the live frame, position, walking.
var _probe_cbs: Array = []


func _register_agata_probe() -> void:
	if not OS.has_feature("web"):
		return
	var search = JavaScriptBridge.eval("window.location.search", true)
	if search == null or String(search).find("agataprobe") < 0:
		return
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(args: Array) -> void:
		set_render_mode(String(args[0]) if args.size() > 0 else "3d"))
	# agataTune("msaa", 0|2|4) / agataTune("supersample", 0.5..2): cost of the live frame's options
	var tune := JavaScriptBridge.create_callback(func(args: Array) -> void:
		if args.size() < 2:
			return
		var key := String(args[0])
		var val := float(args[1])
		if key == "supersample":
			_rt["supersample"] = val
			_update_depth()
		elif key == "msaa" and view3d != null:
			view3d.msaa_3d = Viewport.MSAA_DISABLED if val < 2.0 else (Viewport.MSAA_2X if val < 4.0 else Viewport.MSAA_4X))
	_probe_cbs = [cb, tune]
	win.agataMode = cb
	win.agataTune = tune
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_publish_agata_probe)
	add_child(timer)
	JavaScriptBridge.eval("window.agataProbeReady = true;", true)


func _publish_agata_probe() -> void:
	var st := {"mode": render_mode, "is3d": is_3d(), "fps": Engine.get_frames_per_second(),
		"x": global_position.x, "y": global_position.y, "walking": _walking, "acting": _acting,
		"yaw": rad_to_deg(yaw3d), "w": walk_w, "scale": absf(scale.y)}
	if view3d != null:
		st["msaa"] = int(view3d.msaa_3d)
		st["render_scale"] = view3d.render_scale
		st["size"] = [view3d.size.x, view3d.size.y]
		st["idle"] = view3d.current_idle()
	JavaScriptBridge.eval("window.agataState = %s;" % JSON.stringify(st), true)
