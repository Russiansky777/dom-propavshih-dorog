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

var _walking: bool = false
var _target: Vector2 = Vector2.ZERO
var _pending: Node2D = null
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
var _settling: bool = false       # logical position arrived; the drawn figure is finishing its steps
var walk_time: float = 0.0      # game seconds spent in the current walk (probe/measurements)
var _distance_walked: float = 0.0
var _step_phase: int = 0
var _path_ready: bool = false
var _path_wait_frames: int = 0   # physics frames spent waiting for the navigation map / a path

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
	_set_step_phase(0)
	_update_depth()


## Walking runs in _process, on the same delta as the sprite's frame clock: the logical position and
## the walk cycle can never drift apart, even when physics ticks are capped under load.
func _process(delta: float) -> void:
	if _walking:
		_walk_step(delta)
	if _frame_pending:
		_finish_frame_change()
	_update_foot_lock()


## The drawn figure stands at `_drawn_pos` while a frame is shown: offset from the logical position,
## and scaled for its own depth (so nothing about it changes until the next frame).
func _update_foot_lock() -> void:
	if sprite == null:
		return
	if _lock_active and _walking and sprite.animation.begins_with(sheet.walk_action):
		var s := maxf(absf(scale.y), 0.001)
		var s_drawn := room.depth_scale(_drawn_pos.y) if room != null else s
		sprite.position = (_drawn_pos - global_position) / s
		sprite.scale = Vector2.ONE * (s_drawn / s)
	else:
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2.ONE


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
	_lock_active = sheet != null and sheet.foot_lock
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
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.frame_changed.connect(_on_action_frame)
	sprite.animation_finished.connect(_on_animation_finished)
	add_child(sprite)
	if sheet.shadow_alpha > 0.0:
		sprite.add_child(ActorShadow.make(sheet))  # child of the sprite: follows the foot-lock offset
	body.visible = false
	_play_idle()


func uses_sheet() -> bool:
	return sprite != null


## Screen motion → sheet direction row (mapping lives in data/actors/<id>.json).
func direction_index(motion: Vector2) -> int:
	return sheet.direction_index(motion) if sheet != null else 0


func face_towards(target: Vector2) -> void:
	var v := target - global_position
	if sheet != null and v.length_squared() > 1.0:
		direction = sheet.direction_index(v)
		_play_idle()


func _play_idle() -> void:
	if sprite == null:
		return
	var anim := sheet.anim_name(sheet.idle_action, direction)
	if sprite.animation != anim:
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.speed_scale = 1.0
	sprite.play(anim)


## Drops a running cross-fade (room change: the old pose must not linger in the new room).
func _cut_fade() -> void:
	var fade := get_node_or_null("Crossfade") as CanvasItem
	if fade != null:
		fade.visible = false


## Effective speed in px/s at the current depth and direction row (farther = slower on screen;
## towards/away from the viewer slower than across — the row's cycle on screen, see ActorSheet).
func current_speed_px() -> float:
	var s := absf(scale.y)
	if sheet != null:
		return sheet.walk_speed_row_px(direction, s) * floor_factor() * speed_factor
	return walk_speed * s * speed_factor


## Walk-cycle frame rate: constant (frames × speed_mps / cycle_meters), × speed_factor.
func current_walk_fps() -> float:
	if sheet == null:
		return 0.0
	return sheet.walk_fps_const() * speed_factor


## Plays the walk animation through speed_scale so feet match the ground covered; frames are never set by hand.
func _update_walk_anim() -> void:
	if sprite == null:
		return
	var anim := sheet.anim_name(sheet.walk_action, direction)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()


## One click on the room: hotspot/exit → walk to its stand point and interact; else walk there.
func click_at(world_pos: Vector2) -> void:
	if StoryRunner.is_busy() or _acting:
		return  # dialogue, puzzle, transition or an action in progress owns the input
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
	if _walking:
		_adopt_drawn_position()  # a new target mid-walk: continue from where the figure is drawn
	_target = target
	_path_ready = false
	_path_wait_frames = 0
	nav_agent.target_position = target
	_walking = true
	walk_time = 0.0
	_lock_start()
	walk_started.emit(target)


## Moves the logical position onto the drawn one (no visible hop when a walk ends or changes).
## The drawn position lies on the trail already walked, so it is on the floor.
func _adopt_drawn_position() -> void:
	if sprite != null and _lock_active:
		global_position = _drawn_pos
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2.ONE
	_lock_active = false


## True once the navigation path for the current walk has been received.
func has_path() -> bool:
	return _path_ready


## Called by RoomManager when a room is entered: binds depth parameters and places the figure.
func enter_room(new_room: Room, pos: Vector2) -> void:
	room = new_room
	_walking = false
	_pending = null
	_cancel_action()
	_lock_active = false
	if sprite != null:
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2.ONE
	global_position = pos
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
	var node := _pending
	_pending = null
	var act := _action_for(node)
	if act != "":
		var v := node.global_position - global_position
		if v.length_squared() > 1.0:
			direction = sheet.direction_index(v)
	elif node != null and is_instance_valid(node):
		face_towards(node.global_position)
	else:
		_play_idle()
	arrived.emit(global_position)
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		if act != "":
			_start_action(act, node)
			return
		node.call("trigger")
		interaction_performed.emit(node)


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
	_acting = true
	_action = act
	_action_node = node
	_action_fired = false
	var anim := sheet.anim_name(act, direction)
	if sprite.animation != anim:
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.speed_scale = 1.0
	sprite.play(anim)
	action_started.emit(act, node)


func is_acting() -> bool:
	return _acting


func current_action() -> String:
	return _action if _acting else ""


## Key frame reached (or the clip ended without it): the interaction happens — exactly once.
func _fire_action() -> void:
	if _action_fired:
		return
	_action_fired = true
	var node := _action_node
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		action_fire_count += 1
		node.call("trigger")
		interaction_performed.emit(node)


func _on_action_frame() -> void:
	if _acting and not _action_fired and sprite.animation.begins_with(_action + "_") and sprite.frame >= sheet.action_key_frame(_action):
		_fire_action()


func _on_animation_finished() -> void:
	if not _acting:
		return
	_fire_action()
	var act := _action
	var node := _action_node
	_acting = false
	_action = ""
	_action_node = null
	_play_idle()
	action_finished.emit(act, node)


## Room change / load: the action is dropped without its effect (nothing half-applied).
func _cancel_action() -> void:
	_acting = false
	_action = ""
	_action_node = null
	_action_fired = false


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
		s = room.depth_scale(global_position.y)
	# Sheets carry every direction, so no mirroring; the placeholder body flips on `facing`.
	scale = Vector2(s, s) if sprite != null else Vector2(s * facing, s)
	z_index = clampi(int(global_position.y), -4096, 4096)
