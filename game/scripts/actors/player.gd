class_name Player
extends Node2D
## Click-to-walk player. Origin is at the feet.
##
## Visual: an AnimatedSprite2D built from the actor's sheets (data/actors/<id>.json + sprites.json,
## 8 directions × N frames); the placeholder polygon `Body` is the fallback when no sheet loads.
## Scale and z_index come from the room's depth parameters (z_index = int(y) for y-sort).
## Walk frames are driven by distance travelled, never by time, so feet never slide.

signal walk_started(target: Vector2)
signal arrived(position: Vector2)
signal interaction_performed(node: Node2D)

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
var _distance_walked: float = 0.0
var _step_phase: int = 0
var _path_ready: bool = false
var _path_retries: int = 0
var _path_fallback: bool = false

## Physics frames to wait for the navigation map before walking in a straight line.
## (Godot 4.7.2 needs ~5 frames after a region is added before paths are available.)
const PATH_RETRY_FRAMES: int = 30


func _ready() -> void:
	_setup_sprite()
	_set_step_phase(0)
	_update_depth()


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
	add_child(sprite)
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
	sprite.speed_scale = 1.0
	sprite.play(sheet.anim_name(sheet.idle_action, direction))


## Effective speed in px/s at the current depth (farther = slower on screen, nearer = faster).
func current_speed_px() -> float:
	var s := absf(scale.y)
	if sheet != null:
		return sheet.walk_speed_px(s) * speed_factor
	return walk_speed * s * speed_factor


## Walk-cycle frame rate for the current speed and scale (data: cycle length in metres).
func current_walk_fps() -> float:
	if sheet == null:
		return 0.0
	return sheet.walk_fps(current_speed_px(), absf(scale.y))


## Plays the walk animation through speed_scale so feet match the ground covered; frames are never set by hand.
func _update_walk_anim() -> void:
	if sprite == null:
		return
	var anim := sheet.anim_name(sheet.walk_action, direction)
	var base_fps := sprite.sprite_frames.get_animation_speed(anim)
	var fps := current_walk_fps()
	sprite.speed_scale = fps / base_fps if base_fps > 0.0 else 1.0
	if sprite.animation != anim or not sprite.is_playing():
		var frame := sprite.frame
		var progress := sprite.frame_progress
		sprite.play(anim)
		if sprite.sprite_frames.get_frame_count(anim) > frame:
			sprite.set_frame_and_progress(frame, progress)  # keep the stride phase across direction changes


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()


## One click on the room: hotspot/exit → walk to its stand point and interact; else walk there.
func click_at(world_pos: Vector2) -> void:
	if StoryRunner.is_busy():
		return  # dialogue, puzzle or transition owns the input
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
	_target = target
	_path_ready = false
	_path_retries = 0
	_path_fallback = false
	nav_agent.target_position = target
	_walking = true
	walk_started.emit(target)


## True when the navigation path is usable (or the straight-line fallback is active).
func is_path_fallback() -> bool:
	return _path_fallback


## Called by RoomManager when a room is entered: binds depth parameters and places the figure.
func enter_room(new_room: Room, pos: Vector2) -> void:
	room = new_room
	_walking = false
	_pending = null
	global_position = pos
	_set_step_phase(0)
	_play_idle()
	_update_depth()


func _physics_process(delta: float) -> void:
	if not _walking:
		return
	var next: Vector2
	if _path_fallback:
		next = _target
	else:
		if nav_agent.is_navigation_finished():
			_arrive()
			return
		next = nav_agent.get_next_path_position()
		if not _path_ready:
			if nav_agent.get_current_navigation_path().is_empty():
				# Map not synced yet: re-request the path for a few frames, then walk straight.
				_path_retries += 1
				if _path_retries < PATH_RETRY_FRAMES:
					nav_agent.target_position = _target
					return
				_path_fallback = true
				next = _target
			else:
				_path_ready = true
	var to_next := next - global_position
	var dist := to_next.length()
	var step := minf(current_speed_px() * delta, dist)
	if dist > 0.001:
		var motion := to_next / dist * step
		global_position += motion
		_advance_steps(step)
		if absf(motion.x) > 0.01:
			facing = 1 if motion.x > 0.0 else -1
		# Direction changes only above a threshold so tiny path corrections never twitch the sprite.
		if sheet != null and step > sheet.direction_threshold_px:
			direction = sheet.direction_index(motion)
		_update_walk_anim()
	if _path_fallback and global_position.distance_to(_target) <= 2.0:
		_arrive()
		return
	_update_depth()


func _arrive() -> void:
	_walking = false
	_set_step_phase(0)
	_update_depth()
	var node := _pending
	_pending = null
	if node != null and is_instance_valid(node):
		face_towards(node.global_position)
	else:
		_play_idle()
	arrived.emit(global_position)
	if node != null and is_instance_valid(node) and node.has_method("trigger"):
		node.call("trigger")
		interaction_performed.emit(node)


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
