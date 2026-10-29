class_name AmbientRoot
extends Node2D
## The ambient layer of one room («Живой мир»), built by AmbientBuilder from the merged spec
## (preset + data/story/ambient/<LOC>.json). Children:
##   Water/<id> Polygon2D per `water` / `puddles` entry, ambient_water.gdshader        (z −9)
##   Sway/<id>  Polygon2D per `sway_regions` entry, ambient_sway.gdshader              (z −9, drawn
##              after the water: a bush on the shore sways over the water behind it)
##   Dust/<id>  CPUParticles2D per `dust` entry                                        (z per entry)
##   Fog/<id>   Polygon2D per `fog` entry, ambient_fog.gdshader — river fog over the far bank (z 1 by
##              default: over the room layers at z 0, under the figures); when its flags turn it off
##              in the room, it lifts over `fade_s` (Р2, партия J) instead of vanishing
##   Rain       AmbientRain: streak particles in depth layers                        (z 4096)
##   Footfall   splashes in puddles, prints in mud when Agata's foot is planted        (see its doc)
## A region redraws the background picture; with `source: "layer:<id>"` it redraws that room layer
## instead (R1/Z3: the water at the shore is a separate layer over the background) and is drawn
## just above it. Entries with `if` / `unless` flags show only while the flags hold (H1: dust in
## the window beam only with the shutters open). No node here takes input. Interiors have only
## sway (trees behind the windows) and dust.

const SWAY_SHADER: Shader = preload("res://shaders/ambient_sway.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/ambient_water.gdshader")
const FOG_SHADER: Shader = preload("res://shaders/ambient_fog.gdshader")
const MAX_POLY: int = 32

var room: Room = null
var room_id: String = ""
var spec: Dictionary = {}
var ground: AmbientGround = null
var rain: AmbientRain = null
var quality: Dictionary = {}     # AmbientBuilder.quality(): rain_layers, particles, grass
var footfall: AmbientFootfall = null
var sway: Array[Polygon2D] = []
var water: Array[Polygon2D] = []
var dust: Array[CPUParticles2D] = []
var fog: Array[Polygon2D] = []

var _bg_tex: Texture2D = null
var _bg_origin := Vector2.ZERO
var _bg_size := Vector2(1920, 1080)


func setup(p_room: Room, p_room_id: String, p_spec: Dictionary) -> void:
	room = p_room
	room_id = p_room_id
	spec = p_spec
	ground = AmbientGround.for_room(room)
	quality = AmbientBuilder.quality()
	_find_background()
	var wind: Dictionary = spec.get("wind", {})
	var water_box := _group("Water")
	var rain_amount := _rain_intensity()
	for w in spec.get("water", []):
		var n := _make_water(w, spec.get("water_style", {}), rain_amount, 0)
		if n != null:
			water_box.add_child(n)
			water.append(n)
			_conditional(n, w)
	for w in spec.get("puddles", []):
		var n := _make_water(w, spec.get("puddle_style", {}), rain_amount, 1)
		if n != null:
			water_box.add_child(n)
			water.append(n)
			_conditional(n, w)
	var sway_box := _group("Sway")
	var i := 0
	for r in spec.get("sway_regions", []):
		if String(r.get("kind", "tree")) == "grass" and not bool(quality.get("grass", true)):
			i += 1
			continue  # low quality: no grass waves (large ground areas)
		var n := _make_sway(r, wind, i)
		if n != null:
			sway_box.add_child(n)
			sway.append(n)
			_conditional(n, r)
		i += 1
	var dust_box := _group("Dust")
	for d in spec.get("dust", []):
		var n := _make_dust(d)
		if n != null:
			dust_box.add_child(n)
			dust.append(n)
			_conditional(n, d)
	var fog_box := _group("Fog")
	for f in spec.get("fog", []):
		var n := _make_fog(f)
		if n != null:
			fog_box.add_child(n)
			fog.append(n)
			_conditional(n, f)
	if spec.has("rain"):
		rain = AmbientRain.new()
		rain.name = "Rain"
		rain.z_index = AmbientBuilder.Z_RAIN
		add_child(rain)
		rain.setup(spec["rain"], wind, quality)
	if not spec.get("puddles", []).is_empty() or not spec.get("mud", []).is_empty():
		footfall = AmbientFootfall.new()
		footfall.name = "Footfall"
		add_child(footfall)
		footfall.setup(self)
	if not _cond.is_empty():
		var gs := _game_state()
		if gs != null:
			gs.flag_changed.connect(_on_flag_changed)
			gs.state_reset.connect(_refresh_conditions)
		_refresh_conditions()


# --- Flag conditions (if / unless on an entry) ------------------------------------------------

var _cond: Array = []   # [node, if[], unless[]]
var _active: bool = true


func _conditional(n: Node, entry: Dictionary) -> void:
	if entry.has("if") or entry.has("unless"):
		_cond.append([n, entry.get("if", []), entry.get("unless", [])])


func _game_state() -> Node:
	return get_node_or_null("/root/GameState") if is_inside_tree() else (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")


func _on_flag_changed(_f: String, _v: bool) -> void:
	_refresh_conditions(true)


## `animate`: a flag changed while the room is shown — fog lifts over its `fade_s`; otherwise (build, load, new
## game) everything takes its final look at once.
func _refresh_conditions(animate: bool = false) -> void:
	var gs := _game_state()
	for c in _cond:
		var on := true
		for f in c[1]:
			if gs == null or not gs.call("has_flag", String(f)):
				on = false
		for f in c[2]:
			if gs != null and gs.call("has_flag", String(f)):
				on = false
		var node: CanvasItem = c[0]
		if node.has_meta("fog"):
			_set_fog(node as Polygon2D, on, animate)
			continue
		node.visible = on
		if node is CPUParticles2D:
			(node as CPUParticles2D).emitting = on and _active


func _exit_tree() -> void:
	var gs := _game_state()
	if gs != null:
		if gs.flag_changed.is_connected(_on_flag_changed):
			gs.flag_changed.disconnect(_on_flag_changed)
		if gs.state_reset.is_connected(_refresh_conditions):
			gs.state_reset.disconnect(_refresh_conditions)


## The picture a region redraws: the background, or a room layer (`source: "layer:<id>"`).
## Returns {tex, origin, size, alpha, z} (empty when missing).
func _source(entry: Dictionary) -> Dictionary:
	var src := String(entry.get("source", "background"))
	if src.begins_with("layer:"):
		var id := src.substr(6)
		var node: Node2D = null
		for box in ["Layers", "Occluders"]:
			var n := room.get_node_or_null("%s/%s" % [box, id]) as Node2D
			if n != null:
				node = n
				break
		var spr := node.get_node_or_null("Image") as Sprite2D if node != null else null
		if spr == null or spr.texture == null:
			push_warning("Ambient %s: source layer '%s' not found" % [room_id, id])
			return {}
		return {"tex": spr.texture, "origin": node.position + spr.position, "size": spr.texture.get_size() * spr.scale,
			"alpha": true, "z": node.z_index + 1}
	if _bg_tex == null:
		return {}
	return {"tex": _bg_tex, "origin": _bg_origin, "size": _bg_size, "alpha": false, "z": AmbientBuilder.Z_GROUND}


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


## Feather of a region edge for the shaders (ambient_common.gdshaderinc amb_edge): a `rect` entry →
## analytic (mode 1); an outline → a small distance texture over its bounding box (mode 2): cells of
## ≈ feather/4 px, scanline fill, two-pass chamfer distance to the nearest outside cell, / feather,
## clamped to 1 — made once per room build (≤ 12k cells), then one texture fetch per pixel.
static func set_edge(m: ShaderMaterial, entry: Dictionary, pts: PackedVector2Array, feather: float) -> void:
	m.set_shader_parameter("feather_px", feather)
	if feather <= 0.5:
		m.set_shader_parameter("edge_mode", 0)
		return
	if entry.has("rect") and not entry.has("polygon"):
		var r: Array = entry["rect"]
		m.set_shader_parameter("edge_mode", 1)
		m.set_shader_parameter("edge_rect", Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
		return
	var fm := feather_mask(pts, feather)
	m.set_shader_parameter("edge_mode", 2)
	m.set_shader_parameter("edge_tex", fm["tex"])
	var rr: Rect2 = fm["rect"]
	m.set_shader_parameter("edge_rect", Vector4(rr.position.x, rr.position.y, rr.size.x, rr.size.y))


static func feather_mask(pts: PackedVector2Array, feather: float) -> Dictionary:
	var box := AmbientData.bbox(pts)
	var cell := clampf(feather / 4.0, 1.0, 16.0)
	while (box.size.x / cell + 2.0) * (box.size.y / cell + 2.0) > 12000.0:
		cell *= 1.25
	var w := int(ceil(box.size.x / cell)) + 2
	var h := int(ceil(box.size.y / cell)) + 2
	var origin := box.position - Vector2(cell, cell)
	var big := 1.0e6
	var d := PackedFloat32Array()
	d.resize(w * h)
	d.fill(0.0)
	# Scanline fill at cell centres: inside → "far", outside stays 0.
	var n := pts.size()
	for j in h:
		var y := origin.y + (float(j) + 0.5) * cell
		var xs: Array[float] = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y > y) != (b.y > y):
				xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var i0 := maxi(int(ceil((xs[k] - origin.x) / cell - 0.5)), 0)
			var i1 := mini(int(floor((xs[k + 1] - origin.x) / cell - 0.5)), w - 1)
			for i in range(i0, i1 + 1):
				d[j * w + i] = big
			k += 2
	# Chamfer distance (in cells) to the nearest outside cell: forward then backward pass.
	var dg := 1.4142
	for j in range(1, h - 1):
		for i in range(1, w - 1):
			var idx := j * w + i
			if d[idx] > 0.0:
				d[idx] = minf(d[idx], minf(minf(d[idx - 1] + 1.0, d[idx - w] + 1.0), minf(d[idx - w - 1] + dg, d[idx - w + 1] + dg)))
	for j in range(h - 2, 0, -1):
		for i in range(w - 2, 0, -1):
			var idx := j * w + i
			if d[idx] > 0.0:
				d[idx] = minf(d[idx], minf(minf(d[idx + 1] + 1.0, d[idx + w] + 1.0), minf(d[idx + w + 1] + dg, d[idx + w - 1] + dg)))
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for idx in w * h:
		# Distance of the cell centre to the outline ≈ (chamfer − 0.5) cells.
		bytes[idx] = int(clampf((d[idx] - 0.5) * cell / feather, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)
	return {"tex": ImageTexture.create_from_image(img), "rect": Rect2(origin, Vector2(w, h) * cell), "cell": cell}


## Stable 0..1 phase per region: from the data, else from the id (neighbours differ).
static func _phase(entry: Dictionary, i: int) -> float:
	if entry.has("phase"):
		return fposmod(float(entry["phase"]), 1.0)
	var h := String(entry.get("id", str(i))).hash()
	return float(absi(h) % 1000) / 1000.0


func _make_sway(r: Dictionary, wind: Dictionary, i: int) -> Polygon2D:
	var src := _source(r)
	if src.is_empty() and not r.has("layer"):
		return null
	var src_tex: Texture2D = src.get("tex")
	var src_origin: Vector2 = src.get("origin", Vector2.ZERO)
	var src_size: Vector2 = src.get("size", Vector2.ONE)
	var alpha: bool = src.get("alpha", false)
	var z_default: int = src.get("z", AmbientBuilder.Z_GROUND)
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
		z_default = AmbientBuilder.Z_GROUND
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
	n.z_index = clampi(int(r.get("z", z_default)), -10, 4096)
	var m := ShaderMaterial.new()
	m.shader = SWAY_SHADER
	m.set_shader_parameter("src_tex", src_tex)
	m.set_shader_parameter("src_origin", src_origin)
	m.set_shader_parameter("src_size", src_size)
	m.set_shader_parameter("src_alpha", alpha)
	set_edge(m, r, pts, float(r.get("feather_px", 0.0 if alpha else 24.0)))
	if bool(r.get("clip", false)):
		m.set_shader_parameter("clip_rect", Vector4(box.position.x + 1.0, box.position.y + 1.0, box.size.x - 2.0, box.size.y - 2.0))
	var kind := String(r.get("kind", "tree"))
	m.set_shader_parameter("kind", 1 if kind == "grass" else 0)
	if r.has("anchor_line"):
		# Slanted root line [[x0, y0], [x1, y1]] (a shore, a verge); full sway `reach_px` above it.
		var al: Array = r["anchor_line"]
		var a0 := Vector2(float(al[0][0]), float(al[0][1]))
		var a1 := Vector2(float(al[1][0]), float(al[1][1]))
		var slope := (a1.y - a0.y) / (a1.x - a0.x) if absf(a1.x - a0.x) > 0.5 else 0.0
		m.set_shader_parameter("anchor_y", a0.y)
		m.set_shader_parameter("top_y", a0.y - float(r.get("reach_px", 80.0)))
		m.set_shader_parameter("anchor_slope", slope)
		m.set_shader_parameter("anchor_x0", a0.x)
	else:
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
	var e := AmbientData.merge(style, w)
	var src := _source(e)
	if src.is_empty():
		return null
	var pts := AmbientData.shape_of(e)
	if pts.size() < 3 or pts.size() > MAX_POLY:
		push_warning("Ambient %s: water %s needs 3..%d points" % [room_id, e.get("id", "?"), MAX_POLY])
		return null
	var box := AmbientData.bbox(pts)
	var n := Polygon2D.new()
	n.name = String(e.get("id", "water"))
	n.polygon = pts
	n.z_index = clampi(int(e.get("z", src["z"])), -10, 4096)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("src_tex", src["tex"])
	m.set_shader_parameter("src_origin", src["origin"])
	m.set_shader_parameter("src_size", src["size"])
	m.set_shader_parameter("src_alpha", src["alpha"])
	set_edge(m, e, pts, float(e.get("feather_px", 16.0 if mode == 0 else 6.0)))
	m.set_shader_parameter("mode", mode)
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
	m.set_shader_parameter("ring_gain", float(e.get("ring_gain", 1.0)))
	m.set_shader_parameter("ring_w_px", float(e.get("ring_w_px", 1.4)))
	m.set_shader_parameter("protect_sat", float(e.get("protect_sat", 0.32 if mode == 0 else 1.5)))
	# F14 (Director 23.10, «вода мёртвая»): trembling reflections and sparkles on every river by default; flow
	# lines where the data asks (the mill race, the flume at the sluice).
	m.set_shader_parameter("tremble_px", float(e.get("tremble_px", 1.1 if mode == 0 else 0.0)))
	m.set_shader_parameter("sparkle", float(e.get("sparkle", 0.45 if mode == 0 else 0.0)))
	m.set_shader_parameter("streaks", float(e.get("streaks", 0.0)))
	if e.has("streak_color"):
		m.set_shader_parameter("streak_color", Color.html(String(e["streak_color"])))
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


## Dust motes in a light beam: slow, sparse, soft, fading in and out (emission points inside the area).
func _make_dust(d: Dictionary) -> CPUParticles2D:
	var pts := AmbientData.shape_of(d)
	if pts.size() < 3:
		return null
	var p := CPUParticles2D.new()
	p.name = String(d.get("id", "dust"))
	p.z_index = clampi(int(d.get("z", 2)), -10, 4096)
	p.amount = clampi(int(round(float(d.get("amount", 18)) * float(quality.get("particles", 1.0)))), 1, 80)
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


## River fog (Р2, партия J): a veil of `color` over the far bank, see ambient_fog.gdshader.
func _make_fog(f: Dictionary) -> Polygon2D:
	var pts := AmbientData.shape_of(f)
	if pts.size() < 3 or pts.size() > MAX_POLY:
		push_warning("Ambient %s: fog %s needs 3..%d points" % [room_id, f.get("id", "?"), MAX_POLY])
		return null
	var box := AmbientData.bbox(pts)
	var n := Polygon2D.new()
	n.name = String(f.get("id", "fog"))
	n.polygon = pts
	n.z_index = clampi(int(f.get("z", 1)), -10, 4096)
	var m := ShaderMaterial.new()
	m.shader = FOG_SHADER
	set_edge(m, f, pts, float(f.get("feather_px", 60.0)))
	m.set_shader_parameter("color", Color.html(String(f.get("color", "#a9afbc"))))
	m.set_shader_parameter("density", clampf(float(f.get("density", 0.7)), 0.0, 1.0))
	m.set_shader_parameter("wisps", clampf(float(f.get("wisps", 0.5)), 0.0, 1.0))
	var pr: Array = f.get("profile", [box.position.y, box.position.y + box.size.y * 0.4, box.end.y - box.size.y * 0.15, box.end.y])
	m.set_shader_parameter("profile", Vector4(float(pr[0]), float(pr[1]), float(pr[2]), float(pr[3])))
	var dr: Array = f.get("drift", [8.0, 0.0])
	m.set_shader_parameter("drift", Vector2(float(dr[0]), float(dr[1])))
	m.set_shader_parameter("scale_px", float(f.get("scale_px", 200.0)))
	m.set_shader_parameter("lift_px", float(f.get("lift_px", 60.0)))
	m.set_shader_parameter("lift", 0.0)
	n.material = m
	n.set_meta("fog", true)
	n.set_meta("fade_s", float(f.get("fade_s", 6.0)))
	return n


## Fog on: at once (lift 0). Off: hidden at once, or — a flag changed while the room is shown — lifting over
## `fade_s` (rises and thins), then hidden. A lift in progress is cut short by the next change.
func _set_fog(n: Polygon2D, on: bool, animate: bool) -> void:
	var m := n.material as ShaderMaterial
	# has_meta first: get_meta(key, null) with a null default still reports a missing key (Godot 4)
	if n.has_meta("fog_tween"):
		var old: Variant = n.get_meta("fog_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.remove_meta("fog_tween")
	if on:
		m.set_shader_parameter("lift", 0.0)
		n.visible = true
		return
	var dur := float(n.get_meta("fade_s", 6.0))
	if not animate or not n.visible or dur <= 0.0 or not n.is_inside_tree() or not _active:
		n.visible = false
		m.set_shader_parameter("lift", 1.0)
		return
	var tw := n.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("lift", v), float(m.get_shader_parameter("lift")), 1.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: n.visible = false)
	n.set_meta("fog_tween", tw)


## Fog still showing (lift < 1) — for tests and the web probe.
func fog_showing() -> Array[String]:
	var out: Array[String] = []
	for n in fog:
		if n.visible:
			out.append(String(n.name))
	return out


## On/off without rebuilding (FPS comparison through the web probe).
func set_active(on: bool) -> void:
	_active = on
	visible = on
	for d in dust:
		d.emitting = on
	if rain != null:
		rain.set_active(on)
	if footfall != null:
		footfall.active = on
	_refresh_conditions()


## Counts for tests and the web probe.
func stats() -> Dictionary:
	var out := {"room": room_id, "rain": rain != null, "sway": sway.size(), "water": 0, "puddles": 0,
		"dust": dust.size(), "dust_particles": 0, "fog": fog.size(), "visible": visible, "quality": String(quality.get("id", "high")),
		"rain_layers": rain.emitters.size() if rain != null else 0, "rain_particles": rain.particle_count() if rain != null else 0}
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
