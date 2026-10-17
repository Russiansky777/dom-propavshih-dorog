class_name AmbientPrints
extends Node2D
## Boot prints in the mud (AmbientFootfall): decals on the floor (z −8), darker than the ground,
## oriented along the walk on the floor plane (perspective from AmbientGround), alternating left and
## right foot. Each print holds, then fades out over `fade_s` (20–30 s in data); at most
## `max_prints`, the oldest is dropped first. Redrawn at ~10 Hz (the fade is slow), and at once
## when a print is added.

## Boot sole in metres: u along the foot (toe +), v across. Sole and heel are separate prints.
const SOLE: Array = [[0.13, 0.0], [0.12, 0.03], [0.09, 0.046], [0.04, 0.047], [0.0, 0.038], [-0.03, 0.032],
	[-0.03, -0.03], [0.0, -0.036], [0.04, -0.045], [0.09, -0.044], [0.12, -0.028]]
const HEEL: Array = [[-0.06, 0.034], [-0.1, 0.036], [-0.125, 0.026], [-0.13, 0.0], [-0.125, -0.026], [-0.1, -0.034], [-0.06, -0.032]]
const FOOT_GAP_M: float = 0.055   # half the distance between the left and right foot tracks

var ground: AmbientGround = null
var max_prints: int = 24
var fade_s: float = 25.0
var color := Color(0.12, 0.08, 0.05)
var alpha: float = 0.34
var sheen := Color(0.78, 0.8, 0.86, 0.45)   # sky reflected in the water inside the print (a × sheen.a)

var _prints: Array[Dictionary] = []   # {pos, fwd (floor unit), side, age}
var _redraw_acc: float = 0.0


func add(pos: Vector2, floor_fwd: Vector2, side: float) -> void:
	# Each print a little different: the mud gives way unevenly (±8 % per outline point, seeded).
	var jit := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos.round())
	for i in SOLE.size() + HEEL.size():
		jit.append(rng.randf_range(0.92, 1.08))
	_prints.append({"pos": pos, "fwd": floor_fwd, "side": side, "age": 0.0, "jit": jit})
	while _prints.size() > max_prints:
		_prints.pop_front()
	queue_redraw()


func count() -> int:
	return _prints.size()


func ages() -> Array[float]:
	var out: Array[float] = []
	for p in _prints:
		out.append(float(p["age"]))
	return out


func alpha_at(age: float) -> float:
	return alpha * (1.0 - smoothstep(fade_s * 0.35, fade_s, age))


## Advances the prints' age (also used by tests to jump in time).
func advance(dt: float) -> void:
	for p in _prints:
		p["age"] = float(p["age"]) + dt
	while not _prints.is_empty() and float(_prints[0]["age"]) >= fade_s:
		_prints.pop_front()
	_redraw_acc += dt
	if _redraw_acc >= 0.1:
		_redraw_acc = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	if not _prints.is_empty():
		advance(delta)


func _draw() -> void:
	for p in _prints:
		var a := alpha_at(float(p["age"]))
		if a <= 0.003:
			continue
		var pos: Vector2 = p["pos"]
		var fwd: Vector2 = p["fwd"]
		var lat := Vector2(-fwd.y, fwd.x)
		var k := ground.ppm(pos.y)
		var sq := ground.squash(pos.y)
		var centre := pos + _to_screen(lat * FOOT_GAP_M * float(p["side"]), k, sq)
		var c := Color(color, a)
		var jit: PackedFloat32Array = p["jit"]
		var ji := 0
		for shape in [SOLE, HEEL]:
			var pts := PackedVector2Array()
			var inner := PackedVector2Array()
			var mid := Vector2.ZERO
			for uv in shape:
				mid += Vector2(float(uv[0]), float(uv[1])) / float(shape.size())
			for uv in shape:
				var u := Vector2(float(uv[0]), float(uv[1]))
				u = mid + (u - mid) * jit[ji]
				ji += 1
				var g: Vector2 = fwd * u.x + lat * u.y
				pts.append(centre + _to_screen(g, k, sq))
				# Water held in the pressed mud: a smaller glossy patch towards the far side.
				var ui := mid + (u - mid) * 0.6
				var gi: Vector2 = fwd * ui.x + lat * ui.y
				inner.append(centre + _to_screen(gi, k, sq) + Vector2(0, -0.01 * k * sq))
			draw_colored_polygon(pts, c)
			draw_colored_polygon(inner, Color(sheen, a * sheen.a))
			# Mud pushed up round the print catches the light on its near side.
			var rim := pts.duplicate()
			rim.append(pts[0])
			for i in rim.size():
				rim[i] = rim[i] + Vector2(0, 1)
			draw_polyline(rim, Color(1.0, 0.9, 0.78, a * 0.18), 1.0, true)


static func _to_screen(g: Vector2, k: float, sq: float) -> Vector2:
	return Vector2(g.x * k, g.y * k * sq)
