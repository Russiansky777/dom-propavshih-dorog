extends MechanicPanel
## M18p, the crossing (R2): Agata hauls the boat along the bridge rope, hand over hand (Director 23.10, F12:
## «тянуть на себя канат, и лодка подплывала к берегу, раз 10 в сумме, плавно, и менялась картинка как в
## жизни»; F15: the boat hangs on a ring that slides along the rope — the ring and the rope through it are seen).
## About `pulls` pulls: a click, Space, or a short drag of the mouse towards herself (down the screen). Each
## pull moves the boat on smoothly (`pull_s`, eased), the rope runs back through the ring (its strands slide
## towards the viewer — RopeLine's shader on the painted rope, in perspective), the ring jerks and creaks, water
## slaps the bow. The view changes as it would: the far shores grow (a band of the painting zoomed on the rope's
## vanishing point), the far pier (from the arrival painting) comes out of the fog, the fog thins, snow begins to
## fall near the pier; the last pulls cross-fade into the arrival painting (R3). No failure. Event "crossed".
## Everything is data (the scene's `mechanics` spec): art, vanishing point, band, pier crop, ring, numbers.
## Coordinates: canvas px of the 1672×941 paintings (shown full screen ×1920/1672).

## (uv_rect: the crop's place in the whole painting — an AtlasTexture's UV runs over the whole picture)
const BAND_SHADER := "shader_type canvas_item;\nuniform float feather = 0.28;\nuniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec2 q = (UV - uv_rect.xy) / uv_rect.zw;\n\tfloat a = smoothstep(0.0, feather, q.y) * smoothstep(0.0, feather, 1.0 - q.y);\n\tCOLOR = vec4(c.rgb, c.a * a) * COLOR;\n}\n"
## The far pier cut from the arrival painting: soft all round (an ellipse), so it rises out of the fog, no edges.
const FEATHER_SHADER := "shader_type canvas_item;\nuniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec2 d = ((UV - uv_rect.xy) / uv_rect.zw - vec2(0.5, 0.55)) * vec2(2.0, 2.0);\n\tfloat a = smoothstep(1.0, 0.3, length(d));\n\tCOLOR = vec4(c.rgb, c.a * a) * COLOR;\n}\n"
const FOG_SHADER := "shader_type canvas_item;\nuniform float density = 0.8;\nuniform float t = 0.0;\nuniform vec4 tint : source_color = vec4(0.62, 0.66, 0.74, 1.0);\nfloat h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }\nfloat n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }\nvoid fragment() {\n\tvec2 p = UV * vec2(6.0, 2.0);\n\tfloat f = n(p + vec2(t * 0.05, 0.0)) * 0.6 + n(p * 2.3 - vec2(t * 0.08, 0.0)) * 0.4;\n\tfloat band = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.55, UV.y);\n\tCOLOR = vec4(tint.rgb, density * band * (0.55 + 0.45 * f));\n}\n"
## The painted rope runs back through the ring: pixels of the rope layer are sampled further along the rope's
## axis (towards the vanishing point) by `phase` — scaled by the distance from the vanishing point, so near strands
## move faster than far ones; the ring (a circle) stays still.
const ROPE_SHADER := "shader_type canvas_item;\nuniform vec2 vp;\nuniform vec2 dir;\nuniform float phase = 0.0;\nuniform float period = 60.0;\nuniform float ref_dist = 600.0;\nuniform vec2 tex_size;\nuniform vec2 ring;\nuniform float ring_r = 40.0;\nvarying vec2 pos;\nvoid vertex() { pos = VERTEX; }\nvoid fragment() {\n\tfloat d = max(dot(pos - vp, dir), 1.0);\n\tfloat k = d / ref_dist;\n\tfloat off = mod(phase * k, period * k);\n\tfloat keep = smoothstep(ring_r, ring_r * 1.25, length(pos - ring));\n\tvec2 q = pos - dir * off * keep;\n\tvec4 moved = texture(TEXTURE, q / tex_size);\n\tvec4 here = texture(TEXTURE, UV);\n\tCOLOR = (moved.a > 0.5 && here.a > 0.5) ? moved : here;\n}\n"

var k: float = 1.0
var stage: Control = null        # everything that bobs with the boat
var band: TextureRect = null
var pier: TextureRect = null
var fog: ColorRect = null
var fog_mat: ShaderMaterial = null
var rope: TextureRect = null
var rope_mat: ShaderMaterial = null
var ring: TextureRect = null
var arrival: TextureRect = null
var snow: SnowField = null
var hint: Label = null
var pulls_total: int = 10
var pulls: int = 0               # finished pulls
var pulling: bool = false
var queued: int = 0
var pull_t: float = 0.0
var progress: float = 0.0        # 0 … 1 along the crossing (what the view shows)
var rope_phase: float = 0.0
var crossed_sent: bool = false
var _done_t: float = 0.0
var _press: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _drag_pulled: bool = false
var _vp: Vector2 = Vector2.ZERO
var _ring: Vector2 = Vector2.ZERO
var _jolt: float = 0.0


func build() -> void:
	k = 1920.0 / 1672.0
	pulls_total = maxi(int(spec.get("pulls", 10)), 1)
	var art: Dictionary = spec.get("art", {})
	_vp = v2(spec.get("vp", [780, 382])) * k
	_ring = v2(spec.get("ring", [1160, 640])) * k
	stage = Control.new()
	stage.name = "Stage"
	stage.size = Vector2(1920, 1080)
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.gui_input.connect(_on_input)
	add_child(stage)
	var full := [0, 0, 1672, 941]
	crop(String(art.get("bg", "")), full, Vector2.ZERO, k, stage).name = "Bg"
	# The far shores: a band of the same painting zoomed on the vanishing point, soft at its edges.
	var b: Array = spec.get("shore_band", [0, 150, 1672, 250])
	band = crop(String(art.get("bg", "")), b, Vector2(float(b[0]), float(b[1])) * k, k, stage)
	band.name = "ShoreBand"
	band.pivot_offset = _vp - band.position
	var bm := ShaderMaterial.new()
	bm.shader = _shader(BAND_SHADER)
	bm.set_shader_parameter("uv_rect", _uv_rect(b, Vector2(1672, 941)))
	band.material = bm
	# The far pier (the arrival painting) out of the fog at the vanishing point.
	var pc: Dictionary = spec.get("pier", {})
	if pc.has("region"):
		var pr: Array = pc["region"]
		pier = crop(String(pc.get("image", art.get("arrival", ""))), pr, Vector2.ZERO, 1.0, stage)
		pier.name = "FarPier"
		pier.modulate = Color(0.55, 0.6, 0.7, 0.0)
		var fm := ShaderMaterial.new()
		fm.shader = _shader(FEATHER_SHADER)
		var ptex: Texture2D = (pier.texture as AtlasTexture).atlas if pier.texture is AtlasTexture else null
		fm.set_shader_parameter("uv_rect", _uv_rect(pr, ptex.get_size() if ptex != null else Vector2(1672, 941)))
		pier.material = fm
	# Fog over the river between us and the far bank.
	fog = ColorRect.new()
	fog.name = "Fog"
	var fr: Array = spec.get("fog_rect", [0, 120, 1672, 380])
	fog.position = Vector2(float(fr[0]), float(fr[1])) * k
	fog.size = Vector2(float(fr[2]), float(fr[3])) * k
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = _shader(FOG_SHADER)
	fog.material = fog_mat
	stage.add_child(fog)
	# Snow near the far pier (more flakes as we come closer).
	snow = SnowField.new()
	snow.name = "Snow"
	snow.size = Vector2(1920, 1080)
	snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snow.setup(int(spec.get("snow_amount", 160)))
	stage.add_child(snow)
	# The rope (the painted layer, its strands sliding back through the ring) and the ring over it.
	rope = crop(String(art.get("rope", "")), full, Vector2.ZERO, k, stage)
	rope.name = "Rope"
	rope_mat = ShaderMaterial.new()
	rope_mat.shader = _shader(ROPE_SHADER)
	rope_mat.set_shader_parameter("vp", _vp)
	rope_mat.set_shader_parameter("dir", (_ring - _vp).normalized())
	rope_mat.set_shader_parameter("period", float(spec.get("twist_px", 34.0)) * k)
	rope_mat.set_shader_parameter("ref_dist", (_ring - _vp).length())
	rope_mat.set_shader_parameter("tex_size", Vector2(1920, 1080))
	rope_mat.set_shader_parameter("ring", _ring)
	rope_mat.set_shader_parameter("ring_r", float(spec.get("ring_r", 46.0)) * k)
	rope.material = rope_mat
	var rr: Array = spec.get("ring_box", [1105, 590, 110, 110])
	ring = crop(String(art.get("rope", "")), rr, Vector2(float(rr[0]), float(rr[1])) * k, k, stage)
	ring.name = "Ring"
	ring.pivot_offset = _ring - ring.position
	# Arrival: the far pier's own painting fades in over the last pulls.
	arrival = crop(String(art.get("arrival", "")), full, Vector2.ZERO, k, self)
	arrival.name = "Arrival"
	arrival.pivot_offset = Vector2(960, 540)
	arrival.modulate.a = 0.0
	hint = label(text("hint"), v2(spec.get("hint_pos", [560, 980])), 800, &"CloseupLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_view()


static func _uv_rect(r: Array, tex: Vector2) -> Vector4:
	return Vector4(float(r[0]) / tex.x, float(r[1]) / tex.y, float(r[2]) / tex.x, float(r[3]) / tex.y)


static var _shaders: Dictionary = {}


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


## Pulls done, the one under way counted by how far it has gone (eased: the boat surges, then glides).
func _target_progress() -> float:
	var part := 0.0
	if pulling:
		var x := clampf(pull_t / float(spec.get("pull_s", 0.9)), 0.0, 1.0)
		part = sin(x * PI * 0.5)
	return clampf((float(pulls) + part) / float(pulls_total), 0.0, 1.0)


func _apply_view() -> void:
	var p := progress
	var e := p * p * (3.0 - 2.0 * p)
	band.scale = Vector2.ONE * lerpf(1.0, float(spec.get("shore_zoom", 1.6)), e)
	if pier != null:
		var pc: Dictionary = spec.get("pier", {})
		var w := lerpf(float(pc.get("from_w", 70.0)), float(pc.get("to_w", 560.0)), e)
		var reg: Array = pc["region"]
		var h := w * float(reg[3]) / float(reg[2])
		pier.size = Vector2(w, h)
		var foot := v2(pc.get("foot", [0.5, 0.86]))
		pier.position = _vp - Vector2(w * foot.x, h * foot.y)
		var a := smoothstep(0.08, 0.7, p)
		pier.modulate = Color(0.55, 0.6, 0.7).lerp(Color(0.9, 0.9, 0.95), smoothstep(0.4, 1.0, p))
		pier.modulate.a = a
	var fg: Array = spec.get("fog", [0.85, 0.15])
	fog_mat.set_shader_parameter("density", lerpf(float(fg[0]), float(fg[1]), e))
	var sn: Array = spec.get("snow", [0.04, 1.0])
	snow.ratio = lerpf(float(sn[0]), float(sn[1]), smoothstep(0.2, 1.0, p))
	var af := float(spec.get("arrival_from", 0.8))
	var ar := smoothstep(af, 1.0, p)
	arrival.modulate.a = ar
	arrival.scale = Vector2.ONE * lerpf(1.25, 1.0, ar)


func tick(delta: float) -> void:
	fog_mat.set_shader_parameter("t", clock)
	if pulling:
		pull_t += delta
		var ps := float(spec.get("pull_s", 0.9))
		# the rope runs back through the ring while the hands haul (fast at first, then easing)
		rope_phase += delta * float(spec.get("rope_speed", 140.0)) * (1.0 - clampf(pull_t / ps, 0.0, 1.0))
		if pull_t >= ps:
			pulling = false
			pulls += 1
			if queued > 0 and pulls < pulls_total:
				queued -= 1
				_start_pull()
	progress = lerpf(progress, _target_progress(), clampf(delta * 10.0, 0.0, 1.0))
	if absf(progress - _target_progress()) < 0.0005:
		progress = _target_progress()
	rope_mat.set_shader_parameter("phase", rope_phase)
	# The boat: a slow bob on the water, a surge and a dip of the bow with each pull.
	_jolt = maxf(_jolt - delta * 2.2, 0.0)
	var surge := sin(clampf(pull_t / float(spec.get("pull_s", 0.9)), 0.0, 1.0) * PI) if pulling else 0.0
	stage.position = Vector2(0, sin(clock * 0.9) * 3.0 + surge * 5.0)
	stage.rotation = sin(clock * 0.7) * 0.003
	ring.rotation_degrees = sin(_jolt * 30.0) * 3.5 * _jolt
	ring.position = v2(spec.get("ring_box", [1105, 590, 110, 110])) * k + Vector2(-_jolt * 4.0, 0)
	_apply_view()
	if pulls >= pulls_total and not pulling and not crossed_sent:
		_done_t += delta
		if _done_t >= float(spec.get("arrive_hold_s", 0.8)) and not dialogue_up():
			crossed_sent = true
			hint.visible = false
			event("crossed")


## One pull, hand over hand. Ignored once the boat is there; a pull asked for during one runs right after it.
func pull() -> bool:
	if pulls >= pulls_total or crossed_sent:
		return false
	if pulling:
		if pull_t > float(spec.get("pull_s", 0.9)) * 0.5 and queued == 0 and pulls + 1 < pulls_total:
			queued = 1
		return false
	_start_pull()
	return true


func _start_pull() -> void:
	pulling = true
	pull_t = 0.0
	_jolt = 1.0
	sound("ring_creak")
	sound("water_slap")


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if ev.pressed:
			_press = ev.position
			_pressing = true
			_drag_pulled = false
		elif _pressing:
			_pressing = false
			if not _drag_pulled:
				pull()   # a click
	elif ev is InputEventMouseMotion and _pressing and not _drag_pulled:
		var d: Vector2 = ev.position - _press
		# towards herself: down the screen (the rope comes back over the gunwale)
		if d.y > float(spec.get("drag_px", 50.0)) and d.y > absf(d.x) * 0.5:
			_drag_pulled = true
			pull()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
		if is_visible_in_tree() and not dialogue_up():
			get_viewport().set_input_as_handled()
			pull()


func probe() -> Dictionary:
	return {"pulls": pulls, "pulls_total": pulls_total, "pulling": pulling, "progress": progress, "rope_phase": rope_phase,
		"band_scale": band.scale.x, "fog": float(fog_mat.get_shader_parameter("density")), "snow": snow.ratio,
		"pier_w": pier.size.x if pier != null else 0.0, "arrival": arrival.modulate.a, "crossed": crossed_sent,
		"rope": {"x": _ring.x + 140.0, "y": _ring.y + 120.0}, "center": {"x": 960.0, "y": 640.0}}


## Falling snow drawn by hand: `ratio` of the flakes are shown (CPUParticles2D cannot thin its flakes smoothly).
class SnowField extends Control:
	var flakes: Array = []    # [pos, speed, size, drift phase]
	var ratio: float = 0.0
	var _t: float = 0.0

	func setup(n: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for i in n:
			flakes.append([Vector2(rng.randf() * 1920.0, rng.randf() * 1080.0), rng.randf_range(35.0, 95.0), rng.randf_range(1.3, 3.4), rng.randf() * TAU])

	func _process(delta: float) -> void:
		_t += delta
		for f in flakes:
			f[0] += Vector2(sin(_t * 0.8 + f[3]) * 10.0 + 6.0, f[1]) * delta
			if f[0].y > 1090.0:
				f[0] = Vector2(fposmod(f[0].x, 1920.0), -10.0)
			if f[0].x > 1930.0:
				f[0].x = -10.0
		queue_redraw()

	func _draw() -> void:
		var n := int(round(ratio * flakes.size()))
		for i in n:
			var f: Array = flakes[i]
			draw_circle(f[0], f[2], Color(0.95, 0.96, 1.0, 0.8))
