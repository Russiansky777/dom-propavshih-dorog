class_name AmbientRain
extends Node2D
## «Живой мир» — drizzle over the whole room (data `rain`), z 4096: over everything in the room,
## under the UI (CanvasLayer). Thin slanted streaks in depth layers (far → near: shorter, thinner,
## slower, fainter), each layer a CPUParticles2D of streak sprites aligned to their motion. Only the
## streak pixels are drawn — a full-screen rain shader cost one more full-screen pass, which halved
## the frame rate where the renderer is fill-bound (software WebGL; weak integrated GPUs).
## Per layer in data: len_px, width_px, speed_px_s, alpha, cell_px, gap_px, density — the number of
## streaks is density × intensity × (frame width / cell_px) × (frame height / (len_px + gap_px)),
## × quality `particles`; quality `rain_layers` keeps only the nearest layers.
## The slant (slant_deg) leans with the wind gusts (same slow noise as the sway shader, gust_rate).

const FRAME := Vector2(1920, 1080)

var emitters: Array[CPUParticles2D] = []
var slant: float = 0.2          # tan of the angle from the vertical (+ = falls to the right)
var gust_slant: float = 0.06
var gust_rate: float = 0.12
var layer_lean: Array[float] = []
var _t: float = 0.0
var _last_dir := Vector2.ZERO


func setup(r: Dictionary, wind: Dictionary, quality: Dictionary) -> void:
	slant = tan(deg_to_rad(float(r.get("slant_deg", 10.0))))
	gust_slant = tan(deg_to_rad(float(r.get("gust_slant_deg", 3.0))))
	gust_rate = float(wind.get("gust_rate", 0.12))
	var intensity := clampf(float(r.get("intensity", 0.5)), 0.0, 1.0)
	var color := Color.html(String(r.get("color", "#d8dfe8")))
	var layers: Array = r.get("layers", [])
	if layers.is_empty():
		layers = [{"len_px": 9, "width_px": 0.9, "speed_px_s": 520, "alpha": 0.2, "cell_px": 9, "gap_px": 60, "density": 0.55},
			{"len_px": 18, "width_px": 1.1, "speed_px_s": 820, "alpha": 0.27, "cell_px": 17, "gap_px": 110, "density": 0.5},
			{"len_px": 34, "width_px": 1.5, "speed_px_s": 1250, "alpha": 0.32, "cell_px": 37, "gap_px": 200, "density": 0.45}]
	var keep := clampi(int(quality.get("rain_layers", layers.size())), 1, layers.size())
	var share := clampf(float(quality.get("particles", 1.0)), 0.05, 2.0)
	var first := layers.size() - keep   # drop the far (densest) layers first
	for k in range(first, layers.size()):
		var L: Dictionary = layers[k]
		var lean := lerpf(0.8, 1.0, float(k) / maxf(float(layers.size() - 1), 1.0))  # far streaks lean a little less
		emitters.append(_make_layer(L, k, intensity, color, share, lean))
		layer_lean.append(lean)
		add_child(emitters[-1])
	_apply_slant(true)


func _make_layer(L: Dictionary, k: int, intensity: float, color: Color, share: float, lean: float) -> CPUParticles2D:
	var length := float(L.get("len_px", 18))
	var width := float(L.get("width_px", 1.1))
	var speed := float(L.get("speed_px_s", 800))
	var cell := float(L.get("cell_px", 17))
	var gap := float(L.get("gap_px", 110))
	var t := absf(slant * lean) + absf(gust_slant)
	var span_x := FRAME.x + FRAME.y * t + 80.0
	var count := float(L.get("density", 0.5)) * intensity * (span_x / cell) * (FRAME.y / (length + gap)) * share
	var p := CPUParticles2D.new()
	p.name = "Layer%d" % k
	p.amount = maxi(int(round(count)), 1)
	p.texture = streak_texture(length, width)
	p.lifetime = (FRAME.y + 2.0 * length) / speed * sqrt(1.0 + t * t) + 0.05
	p.preprocess = p.lifetime
	p.randomness = 1.0
	p.lifetime_randomness = 0.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(span_x / 2.0, 1.0)
	p.spread = 0.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.92
	p.initial_velocity_max = speed * 1.08
	p.particle_flag_align_y = true
	p.color = Color(color, float(L.get("alpha", 0.25)))
	var ramp := Gradient.new()   # each streak a little brighter or fainter
	ramp.set_color(0, Color(1, 1, 1, 0.6))
	ramp.set_color(1, Color(1, 1, 1, 1.0))
	p.color_initial_ramp = ramp
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p.set_meta("count", p.amount)
	return p


## A streak sprite: `length` px long, soft across (≈ width px), brighter towards the head (+y, the
## direction of motion once aligned).
static func streak_texture(length: float, width: float) -> ImageTexture:
	var w := maxi(int(ceil(width)) + 2, 3)
	var h := maxi(int(round(length)), 2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := (float(w) - 1.0) / 2.0
	for y in h:
		var along := 0.25 + 0.75 * float(y) / float(h - 1)
		for x in w:
			var across := clampf(1.0 - (absf(float(x) - c) - width * 0.5 + 0.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, across * along))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_t += delta
	_apply_slant(false)


## Lean of the rain now: base slant + gust (smooth value noise in 0..1, like amb_noise1 in the shaders).
func slant_now() -> float:
	var x := _t * gust_rate + 3.0
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	var g := lerpf(_hash(i), _hash(i + 1.0), f)
	return slant + gust_slant * (g - 0.5) * 2.0


func _apply_slant(force: bool) -> void:
	var s := slant_now()
	var d := Vector2(s, 1.0).normalized()
	if not force and d.distance_squared_to(_last_dir) < 0.000004:
		return
	_last_dir = d
	for k in emitters.size():
		var p := emitters[k]
		var lean := layer_lean[k]
		p.direction = Vector2(s * lean, 1.0).normalized()
		# Emit along a line above the frame, shifted against the slant so the streaks cover it.
		var t := s * lean
		p.position = Vector2(FRAME.x / 2.0 - FRAME.y * t / 2.0, -float(p.texture.get_height()))


static func _hash(p: float) -> float:
	var x := fposmod(p * 0.1031, 1.0)
	x *= x + 33.33
	x *= x + x
	return fposmod(x, 1.0)


func particle_count() -> int:
	var n := 0
	for p in emitters:
		n += p.amount
	return n


func set_active(on: bool) -> void:
	visible = on
	for p in emitters:
		p.emitting = on
