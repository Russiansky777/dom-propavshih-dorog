class_name AmbientRoot
extends Node2D
## The ambient layer of one room («Живой мир»), built by AmbientBuilder from the merged spec
## (preset + data/story/ambient/<LOC>.json). Children:
##   Rain       Polygon2D over the frame, ambient_rain.gdshader                     (z 4096)
##   Sway/<id>  Polygon2D per `sway_regions` entry, ambient_sway.gdshader              (z −9)
##   Water/<id> Polygon2D per `water` / `puddles` entry, ambient_water.gdshader        (z −9)
##   Dust/<id>  CPUParticles2D per `dust` entry                                        (z per entry)
##   Footfall   splashes in puddles, prints in mud when Agata's foot is planted        (see its doc)
## No node here takes input. Interiors have only sway (trees behind the windows) and dust.

const SWAY_SHADER: Shader = preload("res://shaders/ambient_sway.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/ambient_water.gdshader")
const RAIN_SHADER: Shader = preload("res://shaders/ambient_rain.gdshader")
const MAX_POLY: int = 32

var room: Room = null
var room_id: String = ""
var spec: Dictionary = {}
var ground: AmbientGround = null
var rain: Polygon2D = null
var footfall: AmbientFootfall = null
var sway: Array[Polygon2D] = []
var water: Array[Polygon2D] = []
var dust: Array[CPUParticles2D] = []

var _bg_tex: Texture2D = null
var _bg_origin := Vector2.ZERO
var _bg_size := Vector2(1920, 1080)


func setup(p_room: Room, p_room_id: String, p_spec: Dictionary) -> void:
	room = p_room
	room_id = p_room_id
	spec = p_spec
	ground = AmbientGround.for_room(room)
	_find_background()
	var wind: Dictionary = spec.get("wind", {})
	var sway_box := _group("Sway")
	var i := 0
	for r in spec.get("sway_regions", []):
		var n := _make_sway(r, wind, i)
		if n != null:
			sway_box.add_child(n)
			sway.append(n)
		i += 1
	var water_box := _group("Water")
	var rain_amount := _rain_intensity()
	for w in spec.get("water", []):
		var n := _make_water(w, spec.get("water_style", {}), rain_amount, 0)
		if n != null:
			water_box.add_child(n)
			water.append(n)
	for w in spec.get("puddles", []):
		var n := _make_water(w, spec.get("puddle_style", {}), rain_amount, 1)
		if n != null:
			water_box.add_child(n)
			water.append(n)
	var dust_box := _group("Dust")
	for d in spec.get("dust", []):
		var n := _make_dust(d)
		if n != null:
			dust_box.add_child(n)
			dust.append(n)
	if spec.has("rain"):
		rain = _make_rain(spec["rain"], wind)
		add_child(rain)
	if not spec.get("puddles", []).is_empty() or not spec.get("mud", []).is_empty():
		footfall = AmbientFootfall.new()
		footfall.name = "Footfall"
		add_child(footfall)
		footfall.setup(self)


func _group(n: String) -> Node2D:
	var g := Node2D.new()
	g.name = n
	add_child(g)
	return g


func _rain_intensity() -> float:
	if not spec.has("rain"):
		return 0.0
	return clampf(float(spec["rain"].get("intensity", 0.5)), 0.0, 1.0)


## The background picture the region shaders redraw (RoomBuilder: Background/Image, art scale).
func _find_background() -> void:
	var img := room.get_node_or_null("Background/Image") as Sprite2D
	if img == null or img.texture == null:
		return
	_bg_tex = img.texture
	_bg_origin = img.position
	_bg_size = img.texture.get_size() * img.scale


func has_picture() -> bool:
	return _bg_tex != null


static func _padded(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	while out.size() < MAX_POLY:
		out.append(Vector2.ZERO)
	return out


## Stable 0..1 phase per region: from the data, else from the id (neighbours differ).
static func _phase(entry: Dictionary, i: int) -> float:
	if entry.has("phase"):
		return fposmod(float(entry["phase"]), 1.0)
	var h := String(entry.get("id", str(i))).hash()
	return float(absi(h) % 1000) / 1000.0


func _make_sway(r: Dictionary, wind: Dictionary, i: int) -> Polygon2D:
	var src_tex := _bg_tex
	var src_origin := _bg_origin
	var src_size := _bg_size
	var alpha := false
	var pts := AmbientData.shape_of(r)
	if r.has("layer"):
		# A separate picture of only the swaying thing (transparent elsewhere), drawn like a room
		# layer: art scale × optional `scale`, moved by `offset`.
		var l: Dictionary = r["layer"]
		var path := String(l.get("image", ""))
		if path == "" or not ResourceLoader.exists(path):
			push_warning("Ambient %s: sway layer image missing: %s" % [room_id, path])
			return null
		src_tex = load(path)
		var art := room.art_scale if room.art_scale > 0.0 else 1920.0 / maxf(src_tex.get_size().x, 1.0)
		var sc := art * float(l.get("scale", 1.0))
		var off: Array = l.get("offset", [0, 0])
		src_origin = Vector2(float(off[0]), float(off[1]))
		src_size = src_tex.get_size() * sc
		alpha = true
		if pts.is_empty():
			pts = AmbientData.rect_poly([src_origin.x, src_origin.y, src_size.x, src_size.y])
	if src_tex == null or pts.size() < 3 or pts.size() > MAX_POLY:
		if pts.size() > MAX_POLY:
			push_warning("Ambient %s: sway region %s has %d points (max %d)" % [room_id, r.get("id", i), pts.size(), MAX_POLY])
		return null
	var box := AmbientData.bbox(pts)
	var n := Polygon2D.new()
	n.name = String(r.get("id", "sway_%d" % i))
	n.polygon = pts
	n.z_index = clampi(int(r.get("z", AmbientBuilder.Z_GROUND)), -10, 4096)
	var m := ShaderMaterial.new()
	m.shader = SWAY_SHADER
	m.set_shader_parameter("src_tex", src_tex)
	m.set_shader_parameter("src_origin", src_origin)
	m.set_shader_parameter("src_size", src_size)
	m.set_shader_parameter("src_alpha", alpha)
	m.set_shader_parameter("poly", _padded(pts))
	m.set_shader_parameter("poly_n", pts.size())
	m.set_shader_parameter("feather_px", float(r.get("feather_px", 0.0 if alpha else 24.0)))
	if bool(r.get("clip", false)):
		m.set_shader_parameter("clip_rect", Vector4(box.position.x + 1.0, box.position.y + 1.0, box.size.x - 2.0, box.size.y - 2.0))
	var kind := String(r.get("kind", "tree"))
	m.set_shader_parameter("kind", 1 if kind == "grass" else 0)
	m.set_shader_parameter("anchor_y", float(r.get("anchor_y", box.end.y)))
	m.set_shader_parameter("top_y", float(r.get("top_y", box.position.y)))
	var strength := float(wind.get("strength", 1.0))
	m.set_shader_parameter("amp_px", float(r.get("amp_px", 3.0)) * strength)
	m.set_shader_parameter("freq_hz", float(r.get("freq_hz", 0.35)))
	m.set_shader_parameter("phase", _phase(r, i))
	m.set_shader_parameter("wind_dir", float(wind.get("dir", 1.0)))
	m.set_shader_parameter("gust_rate", float(wind.get("gust_rate", 0.12)))
	m.set_shader_parameter("gust_depth", float(wind.get("gust_depth", 0.6)))
	m.set_shader_parameter("flutter", float(r.get("flutter", 0.3)))
	m.set_shader_parameter("wave_px", float(r.get("wave_px", 320.0)))
	m.set_shader_parameter("keep_below_sat", float(r.get("keep_below_sat", 0.0)))
	n.material = m
	return n


## mode 0 = river/lake, 1 = puddle. `style` = water_style / puddle_style of the preset/room.
func _make_water(w: Dictionary, style: Dictionary, rain_amount: float, mode: int) -> Polygon2D:
	if _bg_tex == null:
		return null
	var e := AmbientData.merge(style, w)
	var pts := AmbientData.shape_of(e)
	if pts.size() < 3 or pts.size() > MAX_POLY:
		push_warning("Ambient %s: water %s needs 3..%d points" % [room_id, e.get("id", "?"), MAX_POLY])
		return null
	var box := AmbientData.bbox(pts)
	var n := Polygon2D.new()
	n.name = String(e.get("id", "water"))
	n.polygon = pts
	n.z_index = clampi(int(e.get("z", AmbientBuilder.Z_GROUND)), -10, 4096)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("src_tex", _bg_tex)
	m.set_shader_parameter("src_origin", _bg_origin)
	m.set_shader_parameter("src_size", _bg_size)
	m.set_shader_parameter("poly", _padded(pts))
	m.set_shader_parameter("poly_n", pts.size())
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("feather_px", float(e.get("feather_px", 16.0 if mode == 0 else 6.0)))
	var fl: Array = e.get("flow", [-12.0, 0.0] if mode == 0 else [0.0, 0.0])
	m.set_shader_parameter("flow", Vector2(float(fl[0]), float(fl[1])))
	var rp: Array = e.get("ripple_px", [0.5, 2.0] if mode == 0 else [0.5, 0.8])
	m.set_shader_parameter("ripple_px", Vector2(float(rp[0]), float(rp[1])))
	m.set_shader_parameter("y_range", Vector2(box.position.y, box.end.y))
	m.set_shader_parameter("glint", float(e.get("glint", 0.25 if mode == 0 else 0.12)))
	m.set_shader_parameter("rain", clampf(rain_amount * float(e.get("rings", 1.0)), 0.0, 1.0))
	m.set_shader_parameter("ring_cell_m", float(e.get("ring_cell_m", 0.45)))
	m.set_shader_parameter("ring_m", float(e.get("ring_m", 0.07)))
	m.set_shader_parameter("ring_period", float(e.get("ring_period_s", 1.1)))
	m.set_shader_parameter("protect_sat", float(e.get("protect_sat", 0.32 if mode == 0 else 1.5)))
	m.set_shader_parameter("depth", ground.depth_uniform())
	m.set_shader_parameter("ground", ground.ground_uniform())
	var ex: Array = e.get("exclude", [])
	var exv: Array[Vector4] = []
	for r in ex.slice(0, 4):
		exv.append(Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	while exv.size() < 4:
		exv.append(Vector4.ZERO)
	m.set_shader_parameter("exclude", exv)
	m.set_shader_parameter("exclude_n", mini(ex.size(), 4))
	n.material = m
	n.set_meta("ambient_kind", "puddle" if mode == 1 else "water")
	return n


func _make_rain(r: Dictionary, wind: Dictionary) -> Polygon2D:
	var n := Polygon2D.new()
	n.name = "Rain"
	n.polygon = AmbientData.rect_poly([0, 0, 1920, 1080])
	n.z_index = AmbientBuilder.Z_RAIN
	var m := ShaderMaterial.new()
	m.shader = RAIN_SHADER
	m.set_shader_parameter("intensity", clampf(float(r.get("intensity", 0.5)), 0.0, 1.0))
	m.set_shader_parameter("slant", tan(deg_to_rad(float(r.get("slant_deg", 10.0)))))
	m.set_shader_parameter("gust_slant", tan(deg_to_rad(float(r.get("gust_slant_deg", 3.0)))))
	m.set_shader_parameter("gust_rate", float(wind.get("gust_rate", 0.12)))
	if r.has("color"):
		m.set_shader_parameter("color", Color.html(String(r["color"])))
	var layers: Array = r.get("layers", [])
	for k in mini(layers.size(), 3):
		var L: Dictionary = layers[k]
		m.set_shader_parameter("layer%d" % k, Vector4(float(L.get("len_px", 18)), float(L.get("width_px", 1.1)), float(L.get("speed_px_s", 800)), float(L.get("alpha", 0.2))))
		m.set_shader_parameter("cells%d" % k, Vector3(float(L.get("cell_px", 17)), float(L.get("gap_px", 110)), float(L.get("density", 0.5))))
	n.material = m
	return n


## Dust motes in a light beam: slow, sparse, soft, fading in and out (emission points inside the area).
func _make_dust(d: Dictionary) -> CPUParticles2D:
	var pts := AmbientData.shape_of(d)
	if pts.size() < 3:
		return null
	var p := CPUParticles2D.new()
	p.name = String(d.get("id", "dust"))
	p.z_index = clampi(int(d.get("z", 2)), -10, 4096)
	p.amount = clampi(int(d.get("amount", 18)), 1, 80)
	p.lifetime = float(d.get("lifetime_s", 9.0))
	p.preprocess = p.lifetime
	p.randomness = 0.5
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var box := AmbientData.bbox(pts)
	var rng := RandomNumberGenerator.new()
	rng.seed = String(d.get("id", "dust")).hash()
	var emit := PackedVector2Array()
	var tries := 0
	while emit.size() < 64 and tries < 4000:
		tries += 1
		var q := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if Geometry2D.is_point_in_polygon(q, pts):
			emit.append(q)
	p.emission_points = emit
	p.direction = Vector2(float(d.get("drift_x", 1.0)), -0.15)
	p.spread = 180.0
	p.gravity = Vector2(0.0, float(d.get("gravity", 1.5)))
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = float(d.get("speed_px_s", 6.0))
	p.tangential_accel_min = -1.5
	p.tangential_accel_max = 1.5
	p.damping_min = 0.0
	p.damping_max = 0.4
	p.texture = _dot_texture()
	var sz := float(d.get("size_px", 3.0))
	p.scale_amount_min = sz * 0.5 / 16.0
	p.scale_amount_max = sz * 1.2 / 16.0
	var c := Color.html(String(d.get("color", "#fff2d8")))
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	var a := float(d.get("alpha", 0.55))
	ramp.colors = PackedColorArray([Color(c, 0.0), Color(c, a), Color(c, a * 0.8), Color(c, 0.0)])
	p.color_ramp = ramp
	return p


static var _dot: Texture2D = null


## Soft round dot 16 px (radial gradient), shared by every dust emitter.
static func _dot_texture() -> Texture2D:
	if _dot != null:
		return _dot
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 16
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_dot = t
	return _dot


## On/off without rebuilding (FPS comparison through the web probe).
func set_active(on: bool) -> void:
	visible = on
	for d in dust:
		d.emitting = on
	if footfall != null:
		footfall.active = on


## Counts for tests and the web probe.
func stats() -> Dictionary:
	var out := {"room": room_id, "rain": rain != null, "sway": sway.size(), "water": 0, "puddles": 0,
		"dust": dust.size(), "dust_particles": 0, "visible": visible}
	for w in water:
		if String(w.get_meta("ambient_kind", "water")) == "puddle":
			out["puddles"] += 1
		else:
			out["water"] += 1
	for d in dust:
		out["dust_particles"] += d.amount
	if footfall != null:
		out.merge(footfall.stats())
	return out
