class_name LightSource
extends Node2D
## One entry of `sources[]` in data/story/lights/<LOC>.json. Types:
##   ambient — room-wide darkening: the room's light map is lowered by `subtract` (every lit surface
##             × (1 − subtract)); fire, glows and the UI keep their brightness;
##   point   — radial light (`mode: "sub"` darkens): `pos`, `radius`, optional non-uniform `scale`
##             [sx, sy] (a light pool on the floor is an ellipse), `falloff`;
##   mask    — soft polygon (`polygons`, `feather`): light or darkness exactly where the painted
##             light is (a window patch, a lit doorway);
##   shaft   — visible beam: additive unshaded sprite of a soft polygon with a `gradient`;
##   fire    — the stove fire: quad over the opening (`rect`) with shaders/fire_stove.gdshader;
##   glow    — lamp glass / bloom: quad (`rect`) with shaders/light_glow.gdshader.
## ambient / point / mask draw into the room's LIGHT MAP (RoomLighting: a 1/4-resolution SubViewport,
## value = light × 0.5, cleared to 0.5 = daylight as painted); the room's art multiplies by it
## (shaders/light_receive.gdshader). Godot's Light2D is not used: under GL Compatibility in WebGL2
## one Light2D cost 85–93 % of the frame rate in the software-GL measurement (tools/light_fps.mjs).
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

const LM_SCALE := 0.5            # light map value = light × LM_SCALE (room art × 2 × value)

var lm: Sprite2D = null           # this source's sprite in the room's light map (ambient/point/mask)
var lm_color: Color = Color.WHITE
var lm_sub: bool = false
var lm_strength: float = 0.0      # current energy × presence × flicker
var sprite: Sprite2D = null
var _mat: ShaderMaterial = null
var _base_pos: Vector2 = Vector2.ZERO
var _alpha: float = 1.0
var _mask: Dictionary = {}      # LightMask.build result of a mask (sampled for actor tones)
var _radius: float = 0.0
var _falloff: float = 1.6
var _scale: Vector2 = Vector2.ONE


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


static var _blend_add: CanvasItemMaterial = null
static var _blend_sub: CanvasItemMaterial = null
static var _white: ImageTexture = null


## Drops the shared resources (tests call it before quitting: no "resources still in use").
static func release_shared() -> void:
	_blend_add = null
	_blend_sub = null
	_white = null
	LightMask.clear_cache()


static func white_texture() -> ImageTexture:
	if _white == null:
		var img := Image.create(QUAD_SIZE, QUAD_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


## A sprite for the light map (drawn into RoomLighting's SubViewport, not into the room).
func _make_lm(tex: Texture2D, sub: bool) -> Sprite2D:
	if _blend_add == null:
		_blend_add = CanvasItemMaterial.new()
		_blend_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_blend_sub = CanvasItemMaterial.new()
		_blend_sub.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	var s := Sprite2D.new()
	s.name = source_id
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.material = _blend_sub if sub else _blend_add
	lm_sub = sub
	lm = s
	return s


func _build_ambient() -> void:
	lm_color = _color(data.get("subtract", [0.5, 0.5, 0.5]), Color(0.5, 0.5, 0.5))
	var s := _make_lm(white_texture(), true)
	s.centered = false
	s.scale = Vector2(1920.0, 1080.0) / float(QUAD_SIZE)


func _build_point() -> void:
	lm_color = _color(data.get("color", "#ffffff"), Color.WHITE)
	_radius = float(data.get("radius", 400.0))
	_falloff = float(data.get("falloff", 1.6))
	var s := _make_lm(LightMask.radial(256, _falloff), String(data.get("mode", "add")) == "sub")
	_base_pos = _vec(data.get("pos", [960, 540]), Vector2(960, 540))
	_scale = _vec(data.get("scale", [1, 1]), Vector2.ONE)
	s.position = _base_pos
	s.scale = _scale * (_radius * 2.0 / 256.0)


func _build_mask() -> void:
	lm_color = _color(data.get("color", "#ffffff"), Color.WHITE)
	var m := LightMask.build(data.get("polygons", []), float(data.get("feather", 40.0)), data.get("gradient", {}))
	_mask = m
	var r: Rect2 = m["rect"]
	var s := _make_lm(m["texture"], String(data.get("mode", "add")) == "sub")
	s.centered = false
	s.position = r.position
	s.scale = Vector2(float(m["texel"]), float(m["texel"]))
	_base_pos = r.get_center()


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
	var s := Sprite2D.new()
	s.name = "Quad"
	s.texture = white_texture()
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


## What this light does to a figure (signed, per channel; SUB is negative), the same quantity it adds
## to a lit surface of the room ÷ the surface's albedo: colour × current strength × coverage. Masks
## (floor patches) and point lights are read under the feet (what the floor by her gets), the ambient
## everywhere. Actors are toned by the sum of this over the room's sources instead of being lit per
## pixel — per pixel their upper body would take the light of the wall behind them.
func light_on_actor(feet: Vector2, chest: Vector2) -> Color:
	if lm == null or lm_strength <= 0.0005:
		return Color(0, 0, 0, 0)
	var k := 0.0
	if kind == "ambient":
		k = 1.0
	elif not _mask.is_empty():
		k = LightMask.sample(_mask, feet)
	elif kind == "point" and _radius > 0.0:
		var local := (chest - lm.position) / Vector2(maxf(absf(_scale.x), 0.001), maxf(absf(_scale.y), 0.001))
		var t := local.length() / _radius
		k = 0.0 if t >= 1.0 else pow(1.0 - t, _falloff) * (1.0 - t * t * 0.15)
	var e := lm_strength * k * (-1.0 if lm_sub else 1.0)
	return Color(lm_color.r * e, lm_color.g * e, lm_color.b * e, 0.0)


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


## Actor tone, additive part: `actor_warm` {color: [r, g, b], near_px, far_px, floor?} — the warm
## cast of a fire / lamp on a figure (a slightly negative red = a cool cast by a window), full at
## near_px, gone at far_px (floor distance from `floor`, else from the shadow floor point),
## × presence × flicker × current energy / base energy.
func actor_warm(feet: Vector2, c: float) -> Color:
	var w = data.get("actor_warm")
	if not (w is Dictionary):
		return Color(0, 0, 0, 0)
	var col := _color(w.get("color", [0.3, 0.15, 0.0]), Color(0.3, 0.15, 0.0))
	var d := floor_distance(feet, c)
	if w.has("floor"):  # its own floor point (a source without a cast shadow: the window patch)
		var v := feet - _vec(w["floor"], Vector2.ZERO)
		d = Vector2(v.x, v.y / maxf(c, 0.05)).length()
	var k := 1.0 - smoothstep(float(w.get("near_px", 150.0)), float(w.get("far_px", 900.0)), d)
	var base := float(data.get("energy", 1.0))
	k *= presence() * flicker_factor() * (energy / base if base > 0.0 else 1.0)
	return Color(col.r * k, col.g * k, col.b * k, 0.0)


func _apply() -> void:
	var pr := presence()
	var ff := flicker_factor()
	if lm != null:
		lm_strength = energy * pr * ff
		var e := lm_strength * LM_SCALE
		lm.self_modulate = Color(lm_color.r * e, lm_color.g * e, lm_color.b * e, 1.0)
		lm.visible = lm_strength > 0.0005
		if kind == "point" and data.has("jitter_px"):
			lm.position = _base_pos + Vector2(flicker_value, -absf(flicker_value) * 0.5) * float(data["jitter_px"])
	if sprite != null:
		if kind == "shaft":
			_mat.set_shader_parameter("intensity", _alpha * energy * pr * ff)
		elif _mat != null:
			_mat.set_shader_parameter("intensity", energy * pr * ff)
			_mat.set_shader_parameter("flicker", flicker_value)
		sprite.visible = pr > 0.001
