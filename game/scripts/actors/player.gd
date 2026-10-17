class_name Player
extends Node2D
## Click-to-walk player. Origin is at the feet; the figure is ~180 px tall at scale 1.
##
## Scale and z_index come from the room's depth parameters (z_index = int(y) for y-sort).
## The two-frame step is driven by distance travelled, never by time, so feet never slide.

signal walk_started(target: Vector2)
signal arrived(position: Vector2)
signal interaction_performed(node: Node2D)

@export var walk_speed: float = 260.0
## Distance (in body units, i.e. divided by the current scale) per step frame.
@export var step_length: float = 36.0
@export var bob_height: float = 5.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var body: Node2D = $Body
@onready var step_a: CanvasItem = $Body/Legs/StepA
@onready var step_b: CanvasItem = $Body/Legs/StepB

var room: Room = null
var facing: int = 1

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
	_set_step_phase(0)
	_update_depth()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()


## One click on the room: hotspot/exit → walk to its stand point and interact; else walk there.
func click_at(world_pos: Vector2) -> void:
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
	var step := minf(walk_speed * delta, dist)
	if dist > 0.001:
		var motion := to_next / dist * step
		global_position += motion
		_advance_steps(step)
		if absf(motion.x) > 0.01:
			facing = 1 if motion.x > 0.0 else -1
	if _path_fallback and global_position.distance_to(_target) <= 2.0:
		_arrive()
		return
	_update_depth()


func _arrive() -> void:
	_walking = false
	_set_step_phase(0)
	_update_depth()
	arrived.emit(global_position)
	var node := _pending
	_pending = null
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
	scale = Vector2(s * facing, s)
	z_index = clampi(int(global_position.y), -4096, 4096)
