class_name RoomEffect
extends Node2D
## Programmatic effects declared in rooms/<id>.json `effects[]`: {type, rect, if, unless, z}.
## fire: upward orange particles + a flickering light patch inside `rect` (stove opening).
## snow: falling white particles over `rect` (the whole room by default).
## tint: the room under a colour (`color`, `blend` "mul" — dusk, darkness of the far shore; "add" — snow
##   showing through, light) over `rect` or `points` — a stand-in until the dusk / far-shore layers come
##   (BRIEF_CHATGPT_v4 §C6), drawn by the engine, not painted.
## shapes: PlaceholderArt shapes (`shapes` [...], `blend` optional) — three far lights, a mirror glass on the
##   stand, fog, the empty-boat haze.
## rope: the bridge rope drawn like the painted one (RopeLine — the strip of the painted rope), from `from` to `to`
##   (screen px) with `sag` px at the middle, `width` [near, far] px tapering with the distance, a soft `shadow` alpha
##   under it on the water (0 — none), `tint` "#rrggbb" for the light of the scene (G28: where the rope is now —
##   on the ring of the plate at the turn and over the water to the far shore, not on Pelageya's stopper).

var data: Dictionary = {}
var particles: CPUParticles2D = null
var glow: Polygon2D = null
var _t: float = 0.0


func setup(p_data: Dictionary) -> void:
	data = p_data
	var r: Array = data.get("rect", [0, 0, 1920, 1080])
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	match String(data.get("type", "snow")):
		"tint":
			_setup_tint(rect)
		"shapes":
			var art := PlaceholderArt.build(data.get("shapes", []))
			art.material = _blend_material(String(data.get("blend", "mix")))
			art.use_parent_material = false
			for c in art.get_children():
				if c is CanvasItem and c.material == null:
					(c as CanvasItem).use_parent_material = true
			add_child(art)
		"rope":
			_setup_rope()
		"fire":
			particles = CPUParticles2D.new()
			particles.name = "Particles"
			_setup_fire(rect)
			add_child(particles)
		_:
			particles = CPUParticles2D.new()
			particles.name = "Particles"
			_setup_snow(rect)
			add_child(particles)
	if data.has("if") or data.has("unless"):
		GameState.flag_changed.connect(_on_flag_changed)
		GameState.state_reset.connect(refresh)
	refresh()


func _setup_tint(rect: Rect2) -> void:
	var p := Polygon2D.new()
	p.name = "Tint"
	if data.has("points"):
		var pts := PackedVector2Array()
		for q in data["points"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		p.polygon = pts
	else:
		p.polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
	p.color = Color.html(String(data.get("color", "#8090b0")))
	p.material = _blend_material(String(data.get("blend", "mul")))
	add_child(p)


func _setup_rope() -> void:
	var a := Vector2(float(data["from"][0]), float(data["from"][1]))
	var b := Vector2(float(data["to"][0]), float(data["to"][1]))
	var w: Array = data.get("width", [6, 3])
	var near := float(w[0])
	var far := float(w[1]) if w.size() > 1 else near
	var pts := RopeLine.sag_points(a, b, float(data.get("sag", 10.0)), 24)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, far / maxf(near, 0.01)))
	var sh_a := float(data.get("shadow", 0.0))
	if sh_a > 0.0:
		var sh := RopeLine.shadow(near, "RopeShadow")
		sh.width_curve = curve
		sh.default_color = Color(0, 0, 0, sh_a)
		var off := PackedVector2Array()
		for q in pts:
			off.append(q + Vector2(0, near * 1.6))
		sh.points = off
		add_child(sh)
	var rope := RopeLine.make(near, "Rope")
	rope.width_curve = curve
	rope.points = pts
	if data.has("tint"):
		rope.default_color = Color.html(String(data["tint"]))
	add_child(rope)


static func _blend_material(blend: String) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	match blend:
		"mul":
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		"add":
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		"sub":
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		_:
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	return m


func _setup_fire(rect: Rect2) -> void:
	glow = Polygon2D.new()
	glow.name = "Glow"
	glow.color = Color(1.0, 0.55, 0.15, 1.0)
	glow.self_modulate = Color(1, 1, 1, 0.35)
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
		# Flicker through self_modulate: changing Polygon2D.color would re-upload the polygon every frame.
		glow.self_modulate.a = 0.25 + 0.12 * sin(_t * 9.0) + 0.06 * sin(_t * 23.0)


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
