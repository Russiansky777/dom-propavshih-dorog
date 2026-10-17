class_name LightSource
extends Node2D
## One entry of `sources[]` in data/story/lights/<LOC>.json. Types:
##   ambient — room-wide darkening: DirectionalLight2D in SUB mode (every lit item × (1 − subtract));
##             unshaded effects (fire, glows) keep their brightness, the UI (CanvasLayer) is untouched;
##   point   — PointLight2D (ADD; `mode: "sub"` darkens) with a radial falloff: `pos`, `radius`,
##             optional non-uniform `scale` [sx, sy] (a light pool on the floor is an ellipse);
##   mask    — PointLight2D with a soft polygon texture (`polygons`, `feather`): light or darkness
##             exactly where the painted light is (a window patch, a lit doorway);
##   shaft   — visible beam: additive unshaded sprite of a soft polygon with a `gradient`;
##   fire    — the stove fire: quad over the opening (`rect`) with shaders/fire_stove.gdshader;
##   glow    — lamp glass / bloom: quad (`rect`) with shaders/light_glow.gdshader.
## Common: `if` / `unless` flags (all `if` set, no `unless` set → on), `fade_s` (on/off and energy
## changes ease over that time — 0.8 s for the H1 shutters; entering a room or loading a save shows
## the final state at once: no replayed transitions), `flicker` {group, amount, speed} — sources of
## one group share one noise (the fire, its light and its shadows breathe together), `energy_if`
## [{if, unless, energy}] — first match overrides `energy`, `z` for drawn types.
## `casts_actor_shadow` + `shadow` {floor:[x,y], alpha, alpha_far, len, len_far, near_px, far_px,
## sway_px, ...} — actors get an ActorLightShadow from this source (RoomLighting attaches them).

const QUAD_SIZE := 4

var source_id: String = ""
var kind: String = ""
var data: Dictionary = {}
var level: float = 0.0          # 0..1 eased presence
var target: float = 0.0
var energy: float = 1.0         # eased current base energy (energy / energy_if)
var energy_target: float = 1.0
var fade_s: float = 0.8
var flicker: LightFlicker = null
var flicker_amount: float = 0.0
var flicker_value: float = 0.0  # last raw −1..1 sample
var casts_shadow: bool = false
var shadow: Dictionary = {}

var light: Light2D = null
var sprite: Sprite2D = null
var _mat: ShaderMaterial = null
var _base_pos: Vector2 = Vector2.ZERO
var _alpha: float = 1.0
var _mask: Dictionary = {}      # LightMask.build result of a mask (sampled for actor tones)
var _radius: float = 0.0
var _falloff: float = 1.6


func setup(spec: Dictionary, group_flicker: LightFlicker) -> void:
	data = spec
	source_id = String(spec.get("id", "light"))
	name = source_id
	kind = String(spec.get("type", "point"))
	fade_s = maxf(float(spec.get("fade_s", 0.8)), 0.0)
	flicker = group_flicker
	flicker_amount = float(spec.get("flicker", {}).get("amount", 0.0)) if spec.get("flicker") is Dictionary else 0.0
	casts_shadow = bool(spec.get("casts_actor_shadow", false))
	shadow = spec.get("shadow", {})
	z_index = clampi(int(spec.get("z", 2)), -10, 4096)
	match kind:
		"ambient":
			_build_ambient()
		"point":
			_build_point()
		"mask":
			_build_mask()
		"shaft":
			_build_shaft()
		"fire":
			_build_quad("res://shaders/fire_stove.gdshader")
		"glow":
			_build_quad("res://shaders/light_glow.gdshader")
		_:
			push_warning("LightSource %s: unknown type '%s'" % [source_id, kind])
	energy_target = _energy_for_flags()
	energy = energy_target
	target = 1.0 if is_active() else 0.0
	level = target
	_apply()


static func _color(v, fallback: Color) -> Color:
	if v is String:
		return Color.html(v)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return fallback


static func _vec(v, fallback: Vector2) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


func _setup_light(l: Light2D) -> void:
	l.name = "Light"
	l.range_z_min = -4096
	l.range_z_max = 4096
	l.blend_mode = Light2D.BLEND_MODE_SUB if String(data.get("mode", "add")) == "sub" else Light2D.BLEND_MODE_ADD
	l.color = _color(data.get("color", "#ffffff"), Color.WHITE)
	l.shadow_enabled = false
	light = l
	add_child(l)


func _build_ambient() -> void:
	var d := DirectionalLight2D.new()
	_setup_light(d)
	d.blend_mode = Light2D.BLEND_MODE_SUB
	d.color = _color(data.get("subtract", [0.5, 0.5, 0.5]), Color(0.5, 0.5, 0.5))


func _build_point() -> void:
	var p := PointLight2D.new()
	_setup_light(p)
	var radius := float(data.get("radius", 400.0))
	_radius = radius
	_falloff = float(data.get("falloff", 1.6))
	p.texture = LightMask.radial(256, _falloff)
	p.texture_scale = radius * 2.0 / 256.0
	_base_pos = _vec(data.get("pos", [960, 540]), Vector2(960, 540))
	p.position = _base_pos
	var sc := _vec(data.get("scale", [1, 1]), Vector2.ONE)
	p.scale = sc


func _build_mask() -> void:
	var p := PointLight2D.new()
	_setup_light(p)
	var m := LightMask.build(data.get("polygons", []), float(data.get("feather", 40.0)), data.get("gradient", {}))
	_mask = m
	var r: Rect2 = m["rect"]
	p.texture = m["texture"]
	p.texture_scale = float(m["texel"])
	_base_pos = r.get_center()
	p.position = _base_pos


func _build_shaft() -> void:
	var m := LightMask.build(data.get("polygons", []), float(data.get("feather", 40.0)), data.get("gradient", {}))
	var r: Rect2 = m["rect"]
	var s := Sprite2D.new()
	s.name = "Shaft"
	s.texture = m["texture"]
	s.centered = false
	s.scale = Vector2(float(m["texel"]), float(m["texel"]))
	s.position = r.position
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/light_shaft.gdshader")
	_mat.set_shader_parameter("rect_px", r.size)
	_mat.set_shader_parameter("color", _color(data.get("color", "#fff2d8"), Color(1, 0.95, 0.85)))
	var g: Dictionary = data.get("gradient", {})
	var dir := _vec(g.get("to", [0, 1]), Vector2(0, 1)) - _vec(g.get("from", [0, 0]), Vector2.ZERO)
	_mat.set_shader_parameter("dir", dir.normalized() if dir.length() > 0.001 else Vector2(0, 1))
	for k in ["streak_amount", "streak_px", "drift"]:
		if data.has(k):
			_mat.set_shader_parameter(k, float(data[k]))
	_alpha = float(data.get("alpha", 0.15))
	s.material = _mat
	sprite = s
	add_child(s)


func _build_quad(shader_path: String) -> void:
	var r: Array = data.get("rect", [0, 0, 100, 100])
	var img := Image.create(QUAD_SIZE, QUAD_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var s := Sprite2D.new()
	s.name = "Quad"
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.position = Vector2(float(r[0]), float(r[1]))
	s.scale = Vector2(float(r[2]), float(r[3])) / float(QUAD_SIZE)
	_mat = ShaderMaterial.new()
	_mat.shader = load(shader_path)
	_mat.set_shader_parameter("size_px", Vector2(float(r[2]), float(r[3])))
	var params: Dictionary = data.get("params", {})
	for k in params.keys():
		var v = params[k]
		if v is Array and v.size() == 2:
			v = Vector2(float(v[0]), float(v[1]))
		elif v is Array and v.size() >= 3:
			v = _color(v, Color.WHITE)
		elif v is String and String(v).begins_with("#"):
			v = Color.html(v)
		_mat.set_shader_parameter(String(k), v)
	s.material = _mat
	sprite = s
	add_child(s)


# --- State -------------------------------------------------------------------

static func flags_hold(cond: Dictionary) -> bool:
	for f in cond.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in cond.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func is_active() -> bool:
	return flags_hold(data)


func _energy_for_flags() -> float:
	for e in data.get("energy_if", []):
		if e is Dictionary and flags_hold(e):
			return float(e.get("energy", 1.0))
	return float(data.get("energy", 1.0))


## Re-reads the flags. `snap`: jump to the final state (room entry, loaded save, reset).
func refresh(snap: bool = false) -> void:
	target = 1.0 if is_active() else 0.0
	energy_target = _energy_for_flags()
	if snap or fade_s <= 0.0:
		level = target
		energy = energy_target
	_apply()


## Advances fades (time-based, frame-rate independent) and pushes values to the nodes.
func step(delta: float, t: float) -> void:
	if fade_s > 0.0:
		level = move_toward(level, target, delta / fade_s)
		# Energy changes (energy_if) ease exponentially: ~98 % of the way after fade_s.
		energy = lerpf(energy, energy_target, 1.0 - exp(-delta * 4.0 / fade_s))
		if absf(energy - energy_target) < 0.0005:
			energy = energy_target
	else:
		level = target
		energy = energy_target
	flicker_value = flicker.sample(t) if flicker != null else 0.0
	_apply()


## Eased presence (smoothstep of the linear fade): what the eye sees.
func presence() -> float:
	return smoothstep(0.0, 1.0, level)


func flicker_factor() -> float:
	return maxf(0.0, 1.0 + flicker_amount * flicker_value)


## Strength for actor shadows: presence × flicker (the shadow breathes with the flame) × current
## energy / base `energy` (an `energy_if` that brightens the light in a dark room deepens its shadows).
func shadow_strength() -> float:
	if not casts_shadow:
		return 0.0
	var base := float(data.get("energy", 1.0))
	var ratio := energy / base if base > 0.0 else 1.0
	return presence() * flicker_factor() * ratio


## Floor point under the source the shadows point away from (sways a little with the flame).
func shadow_floor() -> Vector2:
	var p := _vec(shadow.get("floor", data.get("pos", [960, 700])), Vector2(960, 700))
	p.x += float(shadow.get("sway_px", 0.0)) * flicker_value
	return p


## What this light does to a figure (signed, per channel; SUB is negative), the same quantity
## Light2D adds to a lit surface ÷ its albedo: colour × current energy × coverage. Masks (floor
## patches) are read under the feet, point lights at the chest (`chest`), the ambient everywhere.
## Actors are toned by the sum of this over the room's sources instead of being lit per pixel —
## per pixel their upper body would take the light of the wall behind them.
func light_on_actor(feet: Vector2, chest: Vector2) -> Color:
	if light == null or not light.enabled:
		return Color(0, 0, 0, 0)
	var k := 0.0
	if light is DirectionalLight2D:
		k = 1.0
	elif not _mask.is_empty():
		k = LightMask.sample(_mask, feet)
	elif light is PointLight2D and _radius > 0.0:
		var sc: Vector2 = light.scale
		var local := (chest - light.position) / Vector2(maxf(absf(sc.x), 0.001), maxf(absf(sc.y), 0.001))
		var t := local.length() / _radius
		k = 0.0 if t >= 1.0 else pow(1.0 - t, _falloff) * (1.0 - t * t * 0.15)
	var e := light.energy * k * (-1.0 if light.blend_mode == Light2D.BLEND_MODE_SUB else 1.0)
	return Color(light.color.r * e, light.color.g * e, light.color.b * e, 0.0)


## Floor distance (floor units: screen y ÷ foreshortening `c`) from the source's floor point.
func floor_distance(feet: Vector2, c: float) -> float:
	var v := feet - shadow_floor()
	return Vector2(v.x, v.y / maxf(c, 0.05)).length()


## Actor tone, multiplicative part: `actor_tint` [r, g, b] at full presence (a dark room darkens
## and tones the figures like the floor around them — their art is lighter than the room's).
func actor_tint() -> Color:
	var t = data.get("actor_tint")
	if not (t is Array) or t.size() < 3:
		return Color.WHITE
	var p := presence()
	return Color(lerpf(1.0, float(t[0]), p), lerpf(1.0, float(t[1]), p), lerpf(1.0, float(t[2]), p), 1.0)


## Actor tone, additive part: `actor_warm` {color: [r, g, b], near_px, far_px} — the warm cast of a
## fire / lamp on a figure, full at near_px, gone at far_px (floor distance as for the shadows),
## × presence × flicker × current energy / base energy.
func actor_warm(feet: Vector2, c: float) -> Color:
	var w = data.get("actor_warm")
	if not (w is Dictionary):
		return Color(0, 0, 0, 0)
	var col := _color(w.get("color", [0.3, 0.15, 0.0]), Color(0.3, 0.15, 0.0))
	var d := floor_distance(feet, c)
	var k := 1.0 - smoothstep(float(w.get("near_px", 150.0)), float(w.get("far_px", 900.0)), d)
	var base := float(data.get("energy", 1.0))
	k *= presence() * flicker_factor() * (energy / base if base > 0.0 else 1.0)
	return Color(col.r * k, col.g * k, col.b * k, 0.0)


func _apply() -> void:
	var pr := presence()
	var ff := flicker_factor()
	if light != null:
		light.energy = energy * pr * ff
		light.enabled = light.energy > 0.001
		if light is PointLight2D and data.has("jitter_px"):
			light.position = _base_pos + Vector2(flicker_value, -absf(flicker_value) * 0.5) * float(data["jitter_px"])
	if sprite != null:
		if kind == "shaft":
			_mat.set_shader_parameter("intensity", _alpha * energy * pr * ff)
		elif _mat != null:
			_mat.set_shader_parameter("intensity", energy * pr * ff)
			_mat.set_shader_parameter("flicker", flicker_value)
		sprite.visible = pr > 0.001
