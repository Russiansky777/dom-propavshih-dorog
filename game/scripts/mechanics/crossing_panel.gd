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
## `auto` (T9, R51 — Director 24.10: a repeated crossing is short): Pelageya ferries — the pulls run by themselves,
## and a click, a drag or Space skips to the shore. The first crossing (M18p) stays by hand.

## (uv_rect: the crop's place in the whole painting — an AtlasTexture's UV runs over the whole picture)
const BAND_SHADER := "shader_type canvas_item;\nuniform float feather = 0.28;\nuniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec2 q = (UV - uv_rect.xy) / uv_rect.zw;\n\tfloat a = smoothstep(0.0, feather, q.y) * smoothstep(0.0, feather, 1.0 - q.y);\n\tCOLOR = vec4(c.rgb, c.a * a) * COLOR;\n}\n"
## The far pier cut from the arrival painting: soft all round (an ellipse), so it rises out of the fog, no edges.
const FEATHER_SHADER := "shader_type canvas_item;\nuniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec2 d = ((UV - uv_rect.xy) / uv_rect.zw - vec2(0.5, 0.55)) * vec2(2.0, 2.0);\n\tfloat a = smoothstep(1.0, 0.3, length(d));\n\tCOLOR = vec4(c.rgb, c.a * a) * COLOR;\n}\n"
const FOG_SHADER := "shader_type canvas_item;\nuniform float density = 0.8;\nuniform float t = 0.0;\nuniform vec4 tint : source_color = vec4(0.62, 0.66, 0.74, 1.0);\nfloat h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }\nfloat n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }\nvoid fragment() {\n\tvec2 p = UV * vec2(6.0, 2.0);\n\tfloat f = n(p + vec2(t * 0.05, 0.0)) * 0.6 + n(p * 2.3 - vec2(t * 0.08, 0.0)) * 0.4;\n\tfloat band = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.55, UV.y);\n\tCOLOR = vec4(tint.rgb, density * band * (0.55 + 0.45 * f));\n}\n"
## The painted rope runs back through the ring: pixels of the rope layer are sampled further along the rope's
## axis (towards the vanishing point) by `phase` — scaled by the distance from the vanishing point, so near strands
## move faster than far ones; the ring (a circle) stays still.
const ROPE_SHADER := "shader_type canvas_item;\nuniform vec2 vp;\nuniform vec2 dir;\nuniform float phase = 0.0;\nuniform float period = 60.0;\nuniform float ref_dist = 600.0;\nuniform vec2 tex_size;\nuniform vec2 ring;\nuniform float ring_r = 40.0;\nuniform bool use_eye = false;\nuniform bool slide_all = false;\nuniform vec2 eye;\nuniform vec2 eye_r = vec2(40.0);\nuniform vec2 hole;\nuniform vec2 hole_r = vec2(20.0);\nuniform vec4 bracket;\nvarying vec2 pos;\nvoid vertex() { pos = VERTEX; }\nuniform sampler2D iron_mask;\nuniform bool use_mask = false;\nbool in_iron(vec2 p) {\n\tif (use_mask) { return texture(iron_mask, p / tex_size).r > 0.5; }\n\tvec2 e = (p - eye) / eye_r;\n\tvec2 h = (p - hole) / hole_r;\n\tbool ring_part = dot(e, e) < 1.0 && dot(h, h) >= 1.0;\n\tbool plate = p.x > bracket.x && p.x < bracket.x + bracket.z && p.y > bracket.y && p.y < bracket.y + bracket.w;\n\treturn ring_part || plate;\n}\nvoid fragment() {\n\tvec4 here = texture(TEXTURE, UV);\n\tif (use_eye && in_iron(pos)) { COLOR = here; } else {\n\tfloat d = max(dot(pos - vp, dir), 1.0);\n\tfloat k = d / ref_dist;\n\tfloat per = period * k;\n\tfloat off = mod(phase * k, per);\n\tfloat keep = (use_eye || slide_all) ? 1.0 : smoothstep(ring_r, ring_r * 1.25, length(pos - ring));\n\tvec2 q = pos - dir * off * keep;\n\tif (use_eye) { for (int i = 0; i < 4; i++) { if (!in_iron(q)) { break; } q -= dir * per; } }\n\tvec4 moved = texture(TEXTURE, q / tex_size);\n\tCOLOR = (moved.a > 0.5 && here.a > 0.5) ? moved : here;\n\t}\n}\n"
## J (Директор 29.10, стр. 137: «кольцо и канат у кольца стоят, движется только остальной канат»): with the iron eye
## given (`eye` in the data), the rope runs on through the eye's hole too; samples are never taken from the iron (they
## step a twist further along), so the eye stays put and the rope slides through it. The overlay on top keeps the iron
## only (the plate and the eye round its hole) — not a frozen piece of rope.
const IRON_SHADER := "shader_type canvas_item;\nuniform vec2 origin;\nuniform vec2 eye;\nuniform vec2 eye_r = vec2(40.0);\nuniform vec2 hole;\nuniform vec2 hole_r = vec2(20.0);\nuniform vec4 bracket;\nuniform sampler2D iron_mask;\nuniform bool use_mask = false;\nuniform vec2 tex_size = vec2(1920.0, 1080.0);\nvarying vec2 pos;\nvoid vertex() { pos = VERTEX; }\nvoid fragment() {\n\tvec2 p = origin + pos;\n\tvec2 e = (p - eye) / eye_r;\n\tvec2 h = (p - hole) / hole_r;\n\tbool ring_part = dot(e, e) < 1.0 && dot(h, h) >= 1.0;\n\tbool plate = p.x > bracket.x && p.x < bracket.x + bracket.z && p.y > bracket.y && p.y < bracket.y + bracket.w;\n\tbool iron = use_mask ? texture(iron_mask, p / tex_size).r > 0.5 : (ring_part || plate);\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(c.rgb, iron ? c.a : 0.0) * COLOR;\n}\n"

## Director 10.11, 22:28 («допилить движение на лодке… может воду сделать живой, когда жмём»): the river round the boat is
## alive — its ripples sway, and while the boat is hauled the water runs past towards us (and under the bow), faster near
## the boat than out by the far bank. A shader on the painting itself: inside the water (below the far shore's line,
## outside the boat's gunwales — data `water`) every pixel is sampled from a little further towards the vanishing point,
## by the distance the boat has come (`water_flow`, px of the painting at the bottom edge); two layers half a period
## apart run on and are cross-faded so the shift never runs away (11.11: the first try blended two copies a period apart,
## as the windlass's drum — fine for its repeating coils, but the water only pulsed in place: a time slice showed no flow). The boat itself, the shores and the sky
## stay as painted.
const WATER_SHADER := "
shader_type canvas_item;
uniform vec2 tex_size = vec2(1672.0, 941.0);
uniform vec2 vp = vec2(780.0, 382.0);
uniform float horizon = 388.0;
uniform vec2 tip = vec2(836.0, 545.0);
uniform vec2 slopes = vec2(0.379, 0.415);
uniform float flow = 0.0;
uniform float t = 0.0;
uniform float period = 90.0;
uniform float ripple = 1.6;
float boat_y(float x) {
	return x < tip.x ? tip.y + (tip.x - x) * slopes.x : tip.y + (x - tip.x) * slopes.y;
}
// where a sample may be taken: inside the water (TEXTURE itself is read in fragment() only — a helper does not see it)
vec2 water_uv(vec2 q) {
	q.y = min(q.y, boat_y(q.x) - 4.0);
	q.y = max(q.y, horizon + 1.0);
	return q / tex_size;
}
void fragment() {
	vec2 px = UV * tex_size;
	vec4 base = texture(TEXTURE, UV);
	float w = smoothstep(horizon, horizon + 14.0, px.y) * (1.0 - smoothstep(boat_y(px.x) - 7.0, boat_y(px.x) + 1.0, px.y));
	if (w > 0.001) {
		float depth = clamp((px.y - horizon) / (tex_size.y - horizon), 0.0, 1.0);
		vec2 dir = normalize(px - vp);
		float per = mix(5.0, period, depth);
		// two layers half a period apart, each running on and coming back while the other covers it (a flow map's
		// two phases): the water moves on all the time, nothing jumps
		float ph = flow * mix(0.06, 1.0, depth) / per;
		float f1 = fract(ph);
		float f2 = fract(ph + 0.5);
		float rip = (sin(px.y * 0.11 + t * 1.7) * 0.7 + sin(px.y * 0.037 - t * 1.1 + px.x * 0.013) * 0.5) * ripple * depth;
		vec2 a = px - dir * (f1 * per) + vec2(rip, 0.0);
		vec2 b = px - dir * (f2 * per) + vec2(rip, 0.0);
		vec4 c = mix(texture(TEXTURE, water_uv(a)), texture(TEXTURE, water_uv(b)), abs(1.0 - 2.0 * f1));
		COLOR = mix(base, c, w);
	} else {
		COLOR = base;
	}
}
"
var water_mat: ShaderMaterial = null
var water_flow: float = 0.0      # px of the painting the water has run past at the bottom edge
var _prog_last: float = 0.0

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
var ring_back: TextureRect = null   # партия 17: the ring's arc behind the rope (data art.ring_back)
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
	var bg_rect := crop(String(art.get("bg", "")), full, Vector2.ZERO, k, stage)
	bg_rect.name = "Bg"
	var wd: Dictionary = spec.get("water", {})
	if not wd.is_empty():
		water_mat = ShaderMaterial.new()
		water_mat.shader = _shader(WATER_SHADER)
		water_mat.set_shader_parameter("vp", v2(spec.get("vp", [780, 382])))
		water_mat.set_shader_parameter("horizon", float(wd.get("horizon", 388.0)))
		water_mat.set_shader_parameter("tip", v2(wd.get("bow_tip", [836, 545])))
		var bl := v2(wd.get("bow_left", [0, 862]))
		var br := v2(wd.get("bow_right", [1672, 892]))
		var tp := v2(wd.get("bow_tip", [836, 545]))
		water_mat.set_shader_parameter("slopes", Vector2((bl.y - tp.y) / maxf(tp.x - bl.x, 1.0), (br.y - tp.y) / maxf(br.x - tp.x, 1.0)))
		water_mat.set_shader_parameter("period", float(wd.get("period_px", 90.0)))
		water_mat.set_shader_parameter("ripple", float(wd.get("ripple_px", 1.6)))
		bg_rect.material = water_mat
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
	# 02.11 (Director, стр. 20) — партия 17: the ring split by depth. `ring_back` (the arc behind the rope) is drawn
	# under the sliding rope, `ring_front` (the near arcs and the plate) over it; the rope layer `rope` is then the
	# painted rope alone (tools/make_rope_clean.py) — no mask, no iron carried along with the strands.
	var split := art.has("ring_back") and art.has("ring_front") and ResourceLoader.exists(String(art["ring_front"]))
	var rr0: Array = spec.get("ring_box", [1105, 590, 110, 110])
	if split:
		ring_back = crop(String(art["ring_back"]), rr0, Vector2(float(rr0[0]), float(rr0[1])) * k, k, stage)
		ring_back.name = "RingBack"
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
	rope_mat.set_shader_parameter("slide_all", split)   # партия 17: the rope runs on through the eye; the iron is its own layers
	var rr: Array = spec.get("ring_box", [1105, 590, 110, 110])
	ring = crop(String(art.get("ring_front" if split else "rope", "")), rr, Vector2(float(rr[0]), float(rr[1])) * k, k, stage)
	ring.name = "Ring"
	ring.pivot_offset = _ring - ring.position
	if ring_back != null:
		ring_back.pivot_offset = _ring - ring_back.position
	var eye: Dictionary = spec.get("eye", {}) if not split else {}
	if not eye.is_empty():
		var bk: Array = eye.get("bracket", [0, 0, 0, 0])
		var bracket := Vector4(float(bk[0]) * k, float(bk[1]) * k, float(bk[2]) * k, float(bk[3]) * k)
		for m in [rope_mat, null]:
			var mat: ShaderMaterial = m
			if mat == null:
				mat = ShaderMaterial.new()
				mat.shader = _shader(IRON_SHADER)
				mat.set_shader_parameter("origin", ring.position)
				ring.material = mat
			else:
				mat.set_shader_parameter("use_eye", true)
			mat.set_shader_parameter("eye", v2(eye.get("center", rr.slice(0, 2))) * k)
			mat.set_shader_parameter("eye_r", v2(eye.get("r", [40, 40])) * k)
			mat.set_shader_parameter("hole", v2(eye.get("hole", eye.get("center", rr.slice(0, 2)))) * k)
			mat.set_shader_parameter("hole_r", v2(eye.get("hole_r", [20, 20])) * k)
			mat.set_shader_parameter("bracket", bracket)
			# Director 01.11, стр. 48: the iron in front of the rope — the pixels of the iron itself (tools/make_ring_mask.py),
			# not the whole ellipse: where the painted rope lies over the ring, the running rope stays in front
			if eye.has("mask") and ResourceLoader.exists(String(eye["mask"])):
				mat.set_shader_parameter("iron_mask", load(String(eye["mask"])))
				mat.set_shader_parameter("use_mask", true)
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
	# 02.11 (Director, стр. 20: «доделать эти 10 кадров — последний уж сильно резко меняется кадр»): the whole arrival
	# painting faded in over the last pulls at its own framing — the view jumped from the far pier in the fog to the
	# painted shore. Data `arrival_fade` false: no painting over the crossing — the pier keeps coming closer to the
	# last pull, then the black of the `crossed` event takes us ashore (J-137: «через чёрное»).
	if not bool(spec.get("arrival_fade", true)):
		arrival.modulate.a = 0.0


func tick(delta: float) -> void:
	fog_mat.set_shader_parameter("t", clock)
	if bool(spec.get("auto", false)) and not pulling and pulls < pulls_total:
		_start_pull()
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
	if water_mat != null:
		# the water runs past as the boat comes on (px at the bottom edge per whole crossing), a slow drift always
		var wd: Dictionary = spec.get("water", {})
		water_flow += maxf(progress - _prog_last, 0.0) * float(wd.get("flow_px", 2600.0)) + delta * float(wd.get("drift_px_s", 4.0))
		_prog_last = progress
		water_mat.set_shader_parameter("flow", water_flow)
		water_mat.set_shader_parameter("t", clock)
	rope_mat.set_shader_parameter("phase", rope_phase)
	# The boat: a slow bob on the water, a surge and a dip of the bow with each pull.
	_jolt = maxf(_jolt - delta * 2.2, 0.0)
	var surge := sin(clampf(pull_t / float(spec.get("pull_s", 0.9)), 0.0, 1.0) * PI) if pulling else 0.0
	stage.position = Vector2(0, sin(clock * 0.9) * 3.0 + surge * 5.0)
	stage.rotation = sin(clock * 0.7) * 0.003
	ring.rotation_degrees = sin(_jolt * 30.0) * 3.5 * _jolt
	ring.position = v2(spec.get("ring_box", [1105, 590, 110, 110])) * k + Vector2(-_jolt * 4.0, 0)
	if ring_back != null:
		ring_back.rotation_degrees = ring.rotation_degrees
		ring_back.position = ring.position
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
	if bool(spec.get("auto", false)):
		skip()
		return true
	if pulling:
		if pull_t > float(spec.get("pull_s", 0.9)) * 0.5 and queued == 0 and pulls + 1 < pulls_total:
			queued = 1
		return false
	_start_pull()
	return true


## Auto crossing: straight to the shore (the arrival hold and the event follow in tick).
func skip() -> void:
	pulls = pulls_total
	pulling = false
	queued = 0
	progress = 1.0


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
	return {"auto": bool(spec.get("auto", false)), "pulls": pulls, "pulls_total": pulls_total, "pulling": pulling, "progress": progress, "rope_phase": rope_phase,
		"band_scale": band.scale.x, "fog": float(fog_mat.get_shader_parameter("density")), "snow": snow.ratio, "water_flow": water_flow,
		"water": water_mat != null,
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
