extends Node
## TR1 (Director 24.10): the shooting mode for trailers — a separate entry scene (scenes/trailer/Trailer.tscn) that
## plays one shot of a plan (data/trailer/<id>.json) without any interface, for Godot's Movie Maker:
##   godot --path game --write-movie out/frame.png --fixed-fps 60 --resolution 3840x2160 \
##         res://scenes/trailer/Trailer.tscn -- --trailer=res://data/trailer/test_7s.json --shot=house
## (tools/make_trailer.sh renders every shot, tools/trailer_assemble.py cuts and mixes them with ffmpeg).
##
## Shot kinds (all content is data):
##   art        — a flat picture split into depth layers (tools/make_trailer_layers.py): a push-in about an anchor,
##                every pixel zoomed by its own depth (parallax without seams), the menu's living water/wind/window,
##                mist over the water, the lamp's glow and motes in its light.
##   room       — a real room of the game in a story state (`state` as a start point): Agata walks with the game's
##                own walk, the camera eases its zoom and follows her; occluders move faster than the room.
##   title_card — the game's name in the menu's gold on black with a glint across the letters, the tagline under it.
## The shot runs for its duration plus a tail (the next shot's transition) plus `preroll_s` at the start (cut off in
## the edit: the room's light and sound settle). After the last frame the tree quits — Movie Maker closes the files.

const SCREEN := Vector2(1920, 1080)
const DEFAULT_PLAN := "res://data/trailer/test_7s.json"

var plan: Dictionary = {}
var shot: Dictionary = {}
var fps: int = 60
var preroll_s: float = 0.0
var length_s: float = 0.0          # visible part: duration + tail
var frame: int = 0
var total_frames: int = 0
var quit_at_end: bool = true
var errors: Array[String] = []

var _t: float = 0.0                # shot time (negative during the preroll)
var _stage: Node2D = null          # art: the picture's space (art px)
var _layers: Array = []            # art: [{node, mat}]
var _attached: Array = []          # art: [{node, depth}] mist / glow / motes, zoomed by their depth
var _glows: Array = []
var _motes: Array = []             # [{node, data, pts}]
var _post: ShaderMaterial = null
var _world: Node2D = null
var _player: Node2D = null
var _camera: Camera2D = null
var _cam_pos := Vector2.ZERO
var _cam_vel := Vector2.ZERO
var _occ_base: Dictionary = {}     # occluder node -> its own position
var _cues: Array = []              # the room's exit marks: interface, never in the picture
var _walk_started: bool = false
var _title: Dictionary = {}        # title_card nodes


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not plan.is_empty():   # a test loaded the plan before adding the scene
		build()
		return
	var path := DEFAULT_PLAN
	var shot_id := ""
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--trailer="):
			path = s.substr(10)
		elif s.begins_with("--shot="):
			shot_id = s.substr(7)
	if not load_plan(path, shot_id):
		for e in errors:
			push_error("Trailer: " + e)
		if quit_at_end:
			get_tree().quit(1)
		return
	build()


## Reads the plan and picks the shot (first one when `shot_id` is empty). False with `errors` on a bad plan.
func load_plan(path: String, shot_id: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("no plan " + path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or not data.get("shots") is Array or (data["shots"] as Array).is_empty():
		errors.append("bad plan " + path)
		return false
	plan = data
	fps = int(plan.get("fps", 60))
	for a in OS.get_cmdline_user_args():   # tools/trailer_render.sh passes the movie's fps: the frame count must match it
		if String(a).begins_with("--fps="):
			fps = int(String(a).substr(6))
	var shots: Array = plan["shots"]
	var idx := 0
	if shot_id != "":
		idx = -1
		for i in shots.size():
			if String(shots[i].get("id", "")) == shot_id:
				idx = i
		if idx < 0:
			errors.append("no shot '%s' in %s" % [shot_id, path])
			return false
	shot = shots[idx]
	var tail := 0.0
	if idx + 1 < shots.size():
		tail = float(shots[idx + 1].get("transition_in", {}).get("duration", 0.0))
	preroll_s = float(shot.get("preroll_s", 0.0))
	length_s = float(shot.get("duration", 2.0)) + tail
	total_frames = int(round((preroll_s + length_s) * fps))
	_t = -preroll_s
	return true


func build() -> void:
	match String(shot.get("kind", "")):
		"art":
			_build_art()
		"room":
			_build_room()
		"title_card":
			_build_title()
		"phrase":
			_build_phrase()
		"daycard":
			_build_daycard()
		_:
			push_error("Trailer: unknown shot kind '%s'" % shot.get("kind", ""))
	_build_post()
	_build_veil()
	_apply(0.0)


func _process(_delta: float) -> void:
	if plan.is_empty():
		return
	# The movie's own clock: exactly one frame per frame (Movie Maker's fixed fps), the same picture on every render.
	_apply(1.0 / fps)
	frame += 1
	if frame >= total_frames and quit_at_end:
		get_tree().quit()


func _apply(dt: float) -> void:
	_t = -preroll_s + float(frame) / fps
	var u := clampf(_t / maxf(length_s, 0.001), 0.0, 1.0)
	match String(shot.get("kind", "")):
		"art":
			_tick_art(u)
		"room":
			_tick_room(u, dt)
		"title_card":
			_tick_title()
		"phrase":
			_tick_phrase()
	_tick_veil()


## Plan ease curves: no linear starts and stops.
static func ease_curve(kind: String, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match kind:
		"linear":
			return u
		"smoother":
			return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
		"out_cubic":
			return 1.0 - pow(1.0 - u, 3.0)
		"in_out_cubic":
			return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
		_:
			return 0.5 - 0.5 * cos(PI * u)   # sine_in_out


static func v2(a, def: Vector2 = Vector2.ZERO) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else def


static func col(a, def: Color = Color.WHITE) -> Color:
	if not a is Array or a.size() < 3:
		return def
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)


# --- art: a flat picture in depth -------------------------------------------------------------

func _build_art() -> void:
	var art_size := v2(shot.get("art_size"), Vector2(1672, 941))
	_stage = Node2D.new()
	_stage.name = "Stage"
	add_child(_stage)
	var mask: Texture2D = load(String(shot.get("fx_mask", ""))) if shot.has("fx_mask") else null
	var depth: Texture2D = load(String(shot.get("depth_tex", ""))) if shot.has("depth_tex") else null
	var fx: Dictionary = MenuConfig.section(String(shot.get("fx_from_menu", "title"))).get("fx", {}) if shot.has("fx_from_menu") else {}
	var par: Dictionary = shot.get("parallax", {})
	var k := v2(par.get("k"), Vector2(1, 1))
	for l in shot.get("layers", []):
		if String(l.get("kind", "image")) == "mist":
			_add_mist(l)
			continue
		var tr := TextureRect.new()
		tr.name = String(l.get("id", "layer"))
		tr.texture = load(String(l["image"]))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = art_size
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/trailer/trailer_layer.gdshader")
		mat.set_shader_parameter("art_size", art_size)
		mat.set_shader_parameter("anchor", v2(shot.get("anchor")))
		mat.set_shader_parameter("k0", k.x)
		mat.set_shader_parameter("k1", k.y)
		mat.set_shader_parameter("depth_channel", int(l.get("depth_channel", 0)))
		if depth != null:
			mat.set_shader_parameter("depth_tex", depth)
		if mask != null:
			mat.set_shader_parameter("mask_tex", mask)
		for group in ["water", "sway", "window"]:
			var g: Dictionary = fx.get(group, {})
			for key in g.keys():
				if not String(key).begins_with("_"):
					mat.set_shader_parameter("%s_%s" % [group, key], float(g[key]))
		tr.material = mat
		_stage.add_child(tr)
		_layers.append({"node": tr, "mat": mat})
	for g in shot.get("glows", []):
		_add_glow(g, _stage)
	if shot.has("motes"):
		_add_motes(shot["motes"], _stage)


func _add_mist(l: Dictionary) -> void:
	var r: Array = l.get("rect", [0, 0, 100, 100])
	var holder := Node2D.new()
	holder.name = String(l.get("id", "mist"))
	_stage.add_child(holder)
	var cr := ColorRect.new()
	cr.position = Vector2(float(r[0]), float(r[1]))
	cr.size = Vector2(float(r[2]), float(r[3]))
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/trailer/trailer_mist.gdshader")
	mat.set_shader_parameter("mist_color", col(l.get("color")))
	mat.set_shader_parameter("alpha", float(l.get("alpha", 0.3)))
	mat.set_shader_parameter("speed_px", float(l.get("speed_px", 10.0)))
	mat.set_shader_parameter("noise_scale", float(l.get("scale", 0.006)))
	mat.set_shader_parameter("rect_size", cr.size)
	cr.material = mat
	holder.add_child(cr)
	_attached.append({"node": holder, "depth": float(l.get("depth", 0.0)), "mat": mat})


func _soft_dot(size: int = 64) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = size
	tex.height = size
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.4, Color(1, 1, 1, 0.35))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	tex.gradient = g
	return tex


func _add_glow(g: Dictionary, parent: Node) -> void:
	var holder := Node2D.new()
	holder.name = "Glow_" + String(g.get("id", ""))
	parent.add_child(holder)
	var sp := Sprite2D.new()
	sp.texture = _soft_dot(256)
	sp.position = v2(g.get("center"))
	var rad := float(g.get("radius", 150))
	sp.scale = Vector2.ONE * (rad * 2.0 / 256.0)
	var c := col(g.get("color"))
	sp.modulate = Color(c, float(g.get("alpha", 0.2)))
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = m
	holder.add_child(sp)
	_glows.append({"sprite": sp, "data": g, "seed": float(_glows.size()) * 17.3})
	_attached.append({"node": holder, "depth": float(g.get("depth", 0.0))})


## Motes in the light: a fixed seeded set (the same on every render), drifting slowly up and sideways on smooth
## noise, twinkling; additive soft dots.
func _add_motes(m: Dictionary, parent: Node) -> void:
	var holder := Node2D.new()
	holder.name = "Motes"
	parent.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	var r: Array = m.get("rect", [0, 0, 100, 100])
	var sz := v2(m.get("size_px"), Vector2(1, 2.5))
	var pts: Array = []
	for i in int(m.get("amount", 40)):
		pts.append({"p": Vector2(rng.randf_range(float(r[0]), float(r[0]) + float(r[2])), rng.randf_range(float(r[1]), float(r[1]) + float(r[3]))),
			"s": rng.randf_range(sz.x, sz.y), "ph": rng.randf() * TAU, "sp": rng.randf_range(0.4, 1.0)})
	var dot := _soft_dot(32)
	var c := col(m.get("color"))
	var a := float(m.get("alpha", 0.5))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	holder.material = mat
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	holder.draw.connect(func():
		for q in pts:
			var t := _t + 3.0
			var ph: float = q["ph"]
			var p: Vector2 = q["p"] + Vector2(sin(t * 0.35 * q["sp"] + ph) * 9.0 + t * 2.0 * q["sp"], -t * 5.0 * q["sp"] + cos(t * 0.5 + ph) * 4.0)
			p.y = rect.position.y + fposmod(p.y - rect.position.y, rect.size.y)
			p.x = rect.position.x + fposmod(p.x - rect.position.x, rect.size.x)
			# Fade near the rect's edges (no pop at the wrap) and twinkle.
			var e := minf(minf(p.x - rect.position.x, rect.end.x - p.x) / 30.0, minf(p.y - rect.position.y, rect.end.y - p.y) / 30.0)
			var tw := 0.55 + 0.45 * sin(t * 2.1 * q["sp"] + ph * 3.0)
			var s: float = q["s"] * 3.0
			holder.draw_texture_rect(dot, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(c, a * tw * clampf(e, 0.0, 1.0))))
	_motes.append(holder)
	if shot.get("kind") == "art":
		_attached.append({"node": holder, "depth": float(m.get("depth", 0.0))})


func _rel_zoom(cam_zoom: float, d: float) -> float:
	var k := v2(shot.get("parallax", {}).get("k"), Vector2(1, 1))
	return (1.0 + (cam_zoom - 1.0) * (k.x + (k.y - k.x) * d)) / cam_zoom


func _tick_art(u: float) -> void:
	var z := v2(shot.get("zoom"), Vector2(1, 1))
	var zc := lerpf(z.x, z.y, ease_curve(String(shot.get("ease", "sine_in_out")), u))
	var view: Array = shot.get("view", [0, 0, 1920, 1080])
	var v0 := Vector2(float(view[0]), float(view[1]))
	var s0 := SCREEN.x / float(view[2])
	var anchor := v2(shot.get("anchor"))
	_stage.scale = Vector2.ONE * s0 * zc
	_stage.position = (anchor - v0) * s0 - anchor * s0 * zc
	var t := _t + float(shot.get("time_offset_s", 4.0))
	for l in _layers:
		var mat: ShaderMaterial = l["mat"]
		mat.set_shader_parameter("cam_zoom", zc)
		mat.set_shader_parameter("time_s", t)
	for a in _attached:
		var r := _rel_zoom(zc, float(a["depth"]))
		var n: Node2D = a["node"]
		n.scale = Vector2.ONE * r
		n.position = anchor * (1.0 - r)
		if a.has("mat"):
			(a["mat"] as ShaderMaterial).set_shader_parameter("time_s", t)
	_tick_glows(t)
	for m in _motes:
		(m as Node2D).queue_redraw()


func _tick_glows(t: float) -> void:
	for g in _glows:
		var d: Dictionary = g["data"]
		var hz := float(d.get("flicker_hz", 7.0))
		var n := sin(t * hz * 1.3 + g["seed"]) * 0.5 + sin(t * hz * 2.9 + g["seed"] * 2.0) * 0.3 + sin(t * hz * 0.37) * 0.2
		var c: Color = (g["sprite"] as Sprite2D).modulate
		c.a = float(d.get("alpha", 0.2)) * (1.0 + float(d.get("flicker", 0.15)) * n)
		(g["sprite"] as Sprite2D).modulate = c


# --- room: the game itself --------------------------------------------------------------------

func _build_room() -> void:
	for bus in shot.get("mute_buses", []):
		var i := AudioServer.get_bus_index(String(bus))
		if i >= 0:
			AudioServer.set_bus_mute(i, true)
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_player = (load("res://scenes/actors/Player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	RoomManager.autosave_enabled = false     # the trailer never writes the player's saves
	RoomManager.setup(_world, _player)
	var state: Dictionary = shot.get("state", {}).duplicate()
	state["room"] = String(shot.get("room", "H1"))
	_merge_start_point(state)
	var ag: Dictionary = shot.get("agata", {})
	if not RoomManager.start_with(state):
		push_error("Trailer: room %s did not start" % state["room"])
		return
	if ag.has("from"):
		_player.call("enter_room", RoomManager.current_room, v2(ag["from"]))
		if ag.has("to"):
			_player.call("face_towards", v2(ag["to"]))
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_world.add_child(_camera)
	_camera.make_current()
	var cam: Dictionary = shot.get("camera", {})
	_cam_pos = v2(cam.get("center_from"), SCREEN / 2)
	var occ := RoomManager.current_room.get_node_or_null("Occluders")
	if occ != null:
		for n in occ.get_children():
			if n is Node2D:
				_occ_base[n] = (n as Node2D).position
	_cues = RoomManager.current_room.find_children("*", "ExitCue", true, false)
	_hide_cues()
	if shot.has("motes"):
		_add_motes(shot["motes"], _world)
	_setup_ui()


## `state.start_point` — a point of data/story/start_points.json as the base: its done_through and flags, then the
## shot's own `flags` / `unset` / `add_items` on top (the shot's `done_through` / `room` win when given).
func _merge_start_point(state: Dictionary) -> void:
	var sp_id := String(state.get("start_point", ""))
	if sp_id == "":
		return
	var base: Dictionary = StoryData.start_points.get(sp_id, {}).duplicate(true)
	for k in ["flags", "add_items", "unset", "remove_items"]:
		var merged: Array = base.get(k, []).duplicate()
		merged.append_array(state.get(k, []))
		state[k] = merged
	if not state.has("done_through"):
		state["done_through"] = base.get("done_through", "")
	if not state.has("spawn") and base.has("spawn") and String(base.get("room", "")) == String(state.get("room", "")):
		state["spawn"] = base["spawn"]


func _hide_cues() -> void:
	for c in _cues:
		if is_instance_valid(c):
			(c as Node2D).visible = false
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED


func _tick_room(u: float, dt: float) -> void:
	if _camera == null:
		return
	_hide_cues()
	var ag: Dictionary = shot.get("agata", {})
	if not _walk_started and ag.has("to") and _t >= float(ag.get("start_s", 0.0)):
		_walk_started = true
		_player.call("walk_to", v2(ag["to"]))
	var cam: Dictionary = shot.get("camera", {})
	var z := v2(cam.get("zoom"), Vector2(1, 1))
	_camera.zoom = Vector2.ONE * lerpf(z.x, z.y, ease_curve(String(cam.get("ease", "sine_in_out")), u))
	var start := v2(cam.get("center_from"), SCREEN / 2)
	var from := v2(ag.get("from"), _player.global_position)
	var goal := start + (_player.global_position - from) * float(cam.get("follow", 0.4))
	if dt > 0.0:
		# Critically damped spring: the camera eases after her, never jerks with the steps.
		var w := float(cam.get("spring_hz", 1.2)) * TAU
		var acc := (goal - _cam_pos) * w * w - _cam_vel * 2.0 * w
		_cam_vel += acc * dt
		_cam_pos += _cam_vel * dt
	_camera.position = _clamp_view(_cam_pos, _camera.zoom.x)
	var shift := _camera.position - start
	var p := float(shot.get("occluder_parallax", 0.0))
	for n in _occ_base.keys():
		if is_instance_valid(n):
			(n as Node2D).position = _occ_base[n] - shift * p
	for m in _motes:
		(m as Node2D).queue_redraw()
	_tick_ui()


## The camera never shows past the room's picture.
func _clamp_view(c: Vector2, zoom: float) -> Vector2:
	var half := SCREEN / (2.0 * zoom)
	return Vector2(clampf(c.x, half.x, SCREEN.x - half.x), clampf(c.y, half.y, SCREEN.y - half.y))


# --- title card -------------------------------------------------------------------------------

func _build_title() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TitleCard"
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = SCREEN
	layer.add_child(black)
	var font := UiTheme.font(String(shot.get("font", "body")))
	# A warm breath of light behind the words (the lamp's gold, very faint).
	var halo := Sprite2D.new()
	halo.texture = _soft_dot(256)
	halo.position = Vector2(SCREEN.x / 2, float(shot.get("title_y", 500)))
	halo.scale = Vector2(1500.0, 520.0) / 256.0
	var hm := CanvasItemMaterial.new()
	hm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = hm
	halo.modulate = Color(col(shot.get("line_color"), Color(1, 0.72, 0.36)), 0.0)
	layer.add_child(halo)
	var rules := Control.new()
	rules.size = SCREEN
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_c := col(shot.get("line_color"), Color(1, 0.72, 0.36))
	var half := float(shot.get("rule_half_px", 300))
	var ys: Array = shot.get("rule_y", [400, 560])
	rules.draw.connect(func():
		for y in ys:
			var x0 := SCREEN.x / 2 - half
			var x1 := SCREEN.x / 2 + half
			var pts := PackedVector2Array([Vector2(x0, y), Vector2(x0 + half * 0.5, y), Vector2(x1 - half * 0.5, y), Vector2(x1, y)])
			rules.draw_polyline_colors(pts, PackedColorArray([Color(line_c, 0), Color(line_c, 0.22), Color(line_c, 0.22), Color(line_c, 0)]), 7.0, true)
			rules.draw_polyline_colors(pts, PackedColorArray([Color(line_c, 0), Color(line_c, 0.9), Color(line_c, 0.9), Color(line_c, 0)]), 2.0, true))
	layer.add_child(rules)
	var box_h := 240.0
	var shadow := _title_label(StoryData.text(String(shot.get("title", ""))), font, int(shot.get("title_px", 120)), box_h)
	shadow.position = Vector2(0, float(shot.get("title_y", 500)) - box_h / 2 + 4)
	shadow.modulate = Color(0, 0, 0, 0.7)
	layer.add_child(shadow)
	var title := _title_label(StoryData.text(String(shot.get("title", ""))), font, int(shot.get("title_px", 120)), box_h)
	title.position = Vector2(0, float(shot.get("title_y", 500)) - box_h / 2)
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	title.add_theme_constant_override("outline_size", 3)
	var gold: Array = shot.get("gold", [])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/trailer/trailer_title.gdshader")
	mat.set_shader_parameter("box_size", Vector2(SCREEN.x, box_h))
	if gold.size() == 3:
		mat.set_shader_parameter("gold_dark", col(gold[0]))
		mat.set_shader_parameter("gold_light", col(gold[1]))
		mat.set_shader_parameter("gold_low", col(gold[2]))
	var asc := font.get_ascent(int(shot.get("title_px", 120)))
	var hgt := font.get_height(int(shot.get("title_px", 120)))
	var top := (box_h - hgt) / 2.0
	mat.set_shader_parameter("glyph_top", (top + asc * 0.28) / box_h)
	mat.set_shader_parameter("glyph_bottom", (top + asc) / box_h)
	mat.set_shader_parameter("glint_width", float(shot.get("glint_width", 0.05)))
	mat.set_shader_parameter("glint_gain", float(shot.get("glint_gain", 0.6)))
	title.material = mat
	layer.add_child(title)
	var sub := _title_label(StoryData.text(String(shot.get("subtitle", ""))), font, int(shot.get("subtitle_px", 40)), 100.0)
	sub.position = Vector2(0, float(shot.get("subtitle_y", 620)) - 50)
	sub.add_theme_color_override("font_color", col(shot.get("subtitle_color"), Color(0.86, 0.79, 0.68)))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	sub.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(sub)
	var w := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(shot.get("title_px", 120))).x / SCREEN.x
	var gw := float(shot.get("glint_width", 0.14))
	_title = {"halo": halo, "title": title, "shadow": shadow, "sub": sub, "rules": rules, "mat": mat,
		"span": Vector2(0.5 - w / 2.0 - gw, 0.5 + w / 2.0 + gw)}


func _title_label(text: String, font: Font, px: int, h: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(SCREEN.x, h)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _window(t: float, span) -> float:
	var s := v2(span, Vector2(0, 1))
	return ease_curve("smoother", (t - s.x) / maxf(0.001, s.y - s.x))


func _tick_title() -> void:
	if _title.is_empty():
		return
	var t := _t
	var a := _window(t, shot.get("title_in"))
	(_title["mat"] as ShaderMaterial).set_shader_parameter("appear", a)
	(_title["shadow"] as Label).modulate.a = 0.7 * a
	(_title["rules"] as Control).modulate.a = a
	(_title["halo"] as Sprite2D).modulate.a = float(shot.get("halo_alpha", 0.07)) * a
	(_title["sub"] as Label).modulate.a = _window(t, shot.get("subtitle_in"))
	var g := v2(shot.get("glint"), Vector2(0.7, 1.7))
	var gu := (t - g.x) / maxf(0.001, g.y - g.x)
	# The run crosses the words (their own width on the screen), a little past each end; outside the run — no glint.
	var span: Vector2 = _title["span"]
	var pos := lerpf(span.x, span.y, ease_curve("sine_in_out", gu)) if gu >= 0.0 and gu <= 1.0 else -1.0
	(_title["mat"] as ShaderMaterial).set_shader_parameter("glint_pos", pos)


# --- post: grade and vignette -----------------------------------------------------------------

func _build_post() -> void:
	if String(shot.get("kind", "")) in ["title_card", "phrase", "daycard"]:
		return
	var layer := CanvasLayer.new()
	layer.name = "Post"
	layer.layer = 100
	add_child(layer)
	var cr := ColorRect.new()
	cr.size = SCREEN
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = load("res://shaders/trailer/trailer_post.gdshader")
	var g: Dictionary = shot.get("grade", {})
	_post.set_shader_parameter("tint", Vector3(col(g.get("tint")).r, col(g.get("tint")).g, col(g.get("tint")).b))
	var lift := col(g.get("lift"), Color(0, 0, 0))
	_post.set_shader_parameter("lift", Vector3(lift.r, lift.g, lift.b))
	_post.set_shader_parameter("vignette", float(g.get("vignette", 0.3)))
	cr.material = _post
	layer.add_child(cr)


# --- phrase: words on black -------------------------------------------------------------------

func _build_phrase() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Phrase"
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = SCREEN
	layer.add_child(black)
	var font := UiTheme.font(String(shot.get("font", "body")))
	var px := int(shot.get("px", 72))
	var width := float(shot.get("width", 1560))
	var text := StoryData.text(String(shot.get("text", "")))
	var y := float(shot.get("y", 540))
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2((SCREEN.x - width) / 2.0, y - 160.0)
	l.size = Vector2(width, 320.0)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col(shot.get("color"), Color(1.0, 0.86, 0.6)))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	var rule := Control.new()
	rule.size = SCREEN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_c := col(shot.get("line_color"), Color(1.0, 0.72, 0.36))
	var lines := l.get_line_count()
	var ry := y + float(lines) * font.get_height(px) * 0.5 + 34.0
	rule.draw.connect(func():
		var half := float(shot.get("rule_half_px", 120))
		var pts := PackedVector2Array([Vector2(SCREEN.x / 2 - half, ry), Vector2(SCREEN.x / 2, ry), Vector2(SCREEN.x / 2 + half, ry)])
		rule.draw_polyline_colors(pts, PackedColorArray([Color(line_c, 0), Color(line_c, 0.8), Color(line_c, 0)]), 2.0, true))
	layer.add_child(rule)
	_title = {"label": l, "rule": rule}


func _tick_phrase() -> void:
	if _title.is_empty():
		return
	var a := _window(_t, shot.get("in", [0.5, 1.4])) * (1.0 - _window(_t, shot.get("out", [2.2, 2.9])))
	(_title["label"] as Label).modulate.a = a
	(_title["rule"] as Control).modulate.a = a * 0.9


# --- day card: the game's own «День второй» -----------------------------------------------------

func _build_daycard() -> void:
	var black := CanvasLayer.new()
	black.layer = 0
	add_child(black)
	var cr := ColorRect.new()
	cr.color = Color.BLACK
	cr.size = SCREEN
	black.add_child(cr)
	var card := CanvasLayer.new()
	card.set_script(load("res://scripts/ui/day_card.gd"))
	add_child(card)
	_title = {"card": card}
	(card as Object).call("show_card", String(shot.get("key", "@ui.day_card_2")), true)


# --- ui: the game's own close-ups, panels and a line of text over a room, with a hand on the mouse ---------

var _mech_view: CanvasLayer = null
var _closeup_view: CanvasLayer = null
var _game_ui: CanvasLayer = null
var _cursor: Sprite2D = null
var _cursor_pos := Vector2(960, 540)
var _ui_done: Dictionary = {}      # event index -> true
var _mouse_down: bool = false
var _strikes_left: int = 0         # timing bars: strike each time the slider is in the green
var _strike_gap: float = 0.6
var _strike_next: float = 0.0
var _press_until: float = -1.0     # a key (Space) pressed every _press_gap seconds
var _press_gap: float = 0.5
var _press_next: float = 0.0
var _veil: ColorRect = null


func _setup_ui() -> void:
	var ui: Dictionary = shot.get("ui", {})
	if ui.is_empty():
		return
	_mech_view = CanvasLayer.new()
	_mech_view.set_script(load("res://scripts/mechanics/mechanic_view.gd"))
	add_child(_mech_view)
	_closeup_view = CanvasLayer.new()
	_closeup_view.set_script(load("res://scripts/ui/closeup_view.gd"))
	add_child(_closeup_view)
	if ui.has("say"):
		_game_ui = CanvasLayer.new()
		_game_ui.set_script(load("res://scripts/ui/game_ui.gd"))
		add_child(_game_ui)
		_strip_game_ui()
	if bool(ui.get("cursor", false)):
		var layer := CanvasLayer.new()
		layer.layer = 120
		add_child(layer)
		_cursor = Sprite2D.new()
		var img := UiCursors.image(String(ui.get("cursor_kind", "arrow")), 2)
		_cursor.texture = ImageTexture.create_from_image(img)
		_cursor.centered = false
		_cursor.offset = -UiCursors.hotspot(String(ui.get("cursor_kind", "arrow")), 2)
		_cursor.visible = false
		layer.add_child(_cursor)
	_cursor_pos = v2(ui.get("cursor_from"), Vector2(1500, 900))


## Only the dialogue box of the game's interface stays; the bag, the journal, the goal line are not for the picture.
func _strip_game_ui() -> void:
	var box: Node = (_game_ui.get("text_label") as Node)
	if box == null:
		return
	while box.get_parent() != null and box.get_parent() != _game_ui:
		box = box.get_parent()
	for c in _game_ui.get_children():
		if c != box and c is CanvasItem:
			(c as CanvasItem).visible = false
	_game_ui.set_meta("keep_only", box)


func _tick_ui() -> void:
	var ui: Dictionary = shot.get("ui", {})
	if ui.is_empty():
		return
	if _game_ui != null and _game_ui.has_meta("keep_only"):
		# The interface shows and hides its parts as the story moves: keep everything but the dialogue box hidden.
		var keep: Node = _game_ui.get_meta("keep_only")
		for c in _game_ui.get_children():
			if c != keep and c is CanvasItem and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
	var events: Array = ui.get("events", [])
	for i in events.size():
		var e: Dictionary = events[i]
		if _ui_done.has(i) or _t < float(e.get("at_s", 0.0)):
			continue
		_ui_done[i] = true
		_run_event(e)
	_tick_strikes()
	if _t < _press_until and _t >= _press_next:
		_press_next = _t + _press_gap
		_run_event({"do": "press", "key": "Space"})
	if bool(ui.get("hide_chrome", false)):
		_hide_chrome()
	# The hand: keyframes `moves` [{at_s, to, dur}] ease from where the last one left it.
	var pos := _cursor_pos
	var from := v2(ui.get("cursor_from"), Vector2(1500, 900))
	for m in ui.get("moves", []):
		var t0 := float(m.get("at_s", 0.0))
		var u := clampf((_t - t0) / maxf(0.001, float(m.get("dur", 0.6))), 0.0, 1.0)
		if _t >= t0:
			var to := v2(m.get("to"))
			pos = from.lerp(to, ease_curve("sine_in_out", u))
			if u >= 1.0:
				from = to
		else:
			break
	if pos != _cursor_pos or _cursor != null and not _cursor.visible:
		_cursor_pos = pos
		_send_mouse_motion(pos)
	if _cursor != null:
		_cursor.visible = _t >= float(ui.get("cursor_in_s", 0.0))
		_cursor.position = _cursor_pos


func _run_event(e: Dictionary) -> void:
	match String(e.get("do", "")):
		"view":
			var h := _hotspot_data(String(e.get("room", "")), String(e.get("hotspot", "")))
			StoryRunner.open_view(h.get("view", {}), String(e.get("hotspot", "")))
		"mechanic":
			var h := _hotspot_data(String(e.get("room", "")), String(e.get("hotspot", "")))
			for f in e.get("flags", []):
				GameState.set_flag(String(f), true)
			StoryRunner.open_mechanic(h.get("mechanic", {}), String(e.get("hotspot", "")))
		"say":
			StoryRunner.mechanic_say(String(e.get("key", "")))
		"click":
			_send_click(v2(e.get("at"), _cursor_pos))
		"press":
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(String(e.get("key", "Space")))
			ev.physical_keycode = ev.keycode
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate() as InputEventKey
			up.pressed = false
			Input.parse_input_event(up)
		"flag":
			GameState.set_flag(String(e.get("flag", "")), bool(e.get("value", true)))
		"counter":
			GameState.set_counter(String(e.get("name", "")), int(e.get("value", 0)))
		"strike":
			_strikes_left = int(e.get("count", 1))
			_strike_gap = float(e.get("gap_s", 0.6))
			_strike_next = _t
		"press_every":
			_press_until = _t + float(e.get("for_s", 3.0))
			_press_gap = float(e.get("gap_s", 0.5))
			_press_next = _t
		_:
			push_error("Trailer: unknown ui event %s" % str(e))


func _hotspot_data(room_id: String, hotspot_id: String) -> Dictionary:
	for h in StoryData.room(room_id).get("hotspots", []):
		if String(h.get("id", "")) == hotspot_id:
			return h
	push_error("Trailer: no hotspot %s/%s" % [room_id, hotspot_id])
	return {}


func _send_mouse_motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _mouse_down else 0
	get_viewport().push_input(ev, true)


func _send_click(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = p
		ev.global_position = p
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		_mouse_down = pressed
		get_viewport().push_input(ev, true)


## A timing bar on screen is struck when its slider stands in the green (the film shows the game being won).
func _tick_strikes() -> void:
	if _strikes_left <= 0 or _t < _strike_next or _mech_view == null:
		return
	for b in _mech_view.find_children("*", "TimingBar", true, false):
		var bar := b as TimingBar
		if bar.is_visible_in_tree() and bar.logic != null and bar.logic.in_green(bar.logic.pos()):
			bar.strike()
			_strikes_left -= 1
			_strike_next = _t + _strike_gap
			return


## The close buttons, page buttons and the like are the game's interface: not in the picture.
func _hide_chrome() -> void:
	if _mech_view != null:
		for n in ["close_button"]:
			var c = _mech_view.get(n)
			if c != null:
				(c as CanvasItem).visible = false
	if _closeup_view != null:
		for n in ["close_button", "prev_button", "next_button"]:
			var c = _closeup_view.get(n)
			if c != null:
				(c as CanvasItem).visible = false


# --- veil: black dips inside a shot ---------------------------------------------------------------

func _build_veil() -> void:
	if not shot.has("veil"):
		return
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.size = SCREEN
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_veil)


## `veil` [{at_s, dur, from, to}] — the black's opacity eases from `from` to `to`; the last key that has begun rules.
func _tick_veil() -> void:
	if _veil == null:
		return
	var a := 0.0
	for k in shot.get("veil", []):
		if _t >= float(k.get("at_s", 0.0)):
			var u := clampf((_t - float(k.get("at_s", 0.0))) / maxf(0.001, float(k.get("dur", 0.4))), 0.0, 1.0)
			a = lerpf(float(k.get("from", 0.0)), float(k.get("to", 0.0)), ease_curve("sine_in_out", u))
	_veil.color.a = a
