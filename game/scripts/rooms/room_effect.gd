class_name RoomEffect
extends Node2D
## Programmatic effects declared in rooms/<id>.json `effects[]`: {type: "fire"|"snow", rect, if, unless, z}.
## Fire: upward orange particles + a flickering light patch inside `rect` (stove opening).
## Snow: falling white particles over `rect` (the whole room by default).

var data: Dictionary = {}
var particles: CPUParticles2D = null
var glow: Polygon2D = null
var _t: float = 0.0


func setup(p_data: Dictionary) -> void:
	data = p_data
	var r: Array = data.get("rect", [0, 0, 1920, 1080])
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	particles = CPUParticles2D.new()
	particles.name = "Particles"
	match String(data.get("type", "snow")):
		"fire":
			_setup_fire(rect)
		_:
			_setup_snow(rect)
	add_child(particles)
	if data.has("if") or data.has("unless"):
		GameState.flag_changed.connect(_on_flag_changed)
		GameState.state_reset.connect(refresh)
	refresh()


func _setup_fire(rect: Rect2) -> void:
	glow = Polygon2D.new()
	glow.name = "Glow"
	glow.color = Color(1.0, 0.55, 0.15, 0.35)
	glow.polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
	add_child(glow)
	particles.position = Vector2(rect.position.x + rect.size.x / 2, rect.end.y - 6)
	particles.amount = int(data.get("amount", 60))
	particles.lifetime = 0.9
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(rect.size.x * 0.35, 4)
	particles.direction = Vector2(0, -1)
	particles.spread = 18.0
	particles.gravity = Vector2(0, -160)
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 90.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	particles.color = Color(1.0, 0.6, 0.15, 0.9)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.95))
	ramp.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	particles.color_ramp = ramp


func _setup_snow(rect: Rect2) -> void:
	particles.position = Vector2(rect.position.x + rect.size.x / 2, rect.position.y)
	particles.amount = int(data.get("amount", 220))
	particles.lifetime = 6.0
	particles.preprocess = 6.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(rect.size.x / 2, 4)
	particles.direction = Vector2(0.15, 1)
	particles.spread = 10.0
	particles.gravity = Vector2(0, 30)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 120.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 4.0
	particles.color = Color(1, 1, 1, 0.85)


func _process(delta: float) -> void:
	if glow != null and visible:
		_t += delta
		glow.color.a = 0.25 + 0.12 * sin(_t * 9.0) + 0.06 * sin(_t * 23.0)


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(refresh):
		GameState.state_reset.disconnect(refresh)


func _on_flag_changed(_f: String, _v: bool) -> void:
	refresh()


func is_active() -> bool:
	for f in data.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func refresh() -> void:
	visible = is_active()
	if particles != null:
		particles.emitting = visible
