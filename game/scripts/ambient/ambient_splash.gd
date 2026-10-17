class_name AmbientSplash
extends Node2D
## One splash of a planted foot in a puddle (AmbientFootfall), in two nodes so each sorts right:
##   DROPS — a few drops thrown up and out on the floor plane, falling under gravity; drawn as short
##           streaks along their motion, z = foot y + 1 (over the boot, y-sorted with the actors);
##   RING  — rings spreading on the water from the foot (floor, z −8, under the actors).
## Everything is in metres on the floor (AmbientGround): sizes follow the room depth scale as Agata.
## Lifetime 0.3–0.5 s (data `footfall_defaults.splash`), then the node frees itself.

enum { DROPS, RING }

const G: float = 9.81

var part: int = DROPS
var ground: AmbientGround = null
var cfg: Dictionary = {}
var seed_value: int = 0
var forward: Vector2 = Vector2.RIGHT   # floor direction of the walk (drops lean forward a little)
var age: float = 0.0
var life: float = 0.45

var _drops: Array[Dictionary] = []      # {v: Vector2 floor m/s, vz: m/s up, r: m, t_end: s}
var _ppm: float = 200.0
var _sq: float = 0.3
var _color := Color(0.82, 0.8, 0.76, 0.85)
var _ring_color := Color(0.88, 0.9, 0.94, 0.5)
var _dark_color := Color(0.25, 0.18, 0.12, 0.45)
var _ring_m: float = 0.24
var _crown_s: float = 0.15


func start() -> void:
	var sp: Dictionary = cfg.get("splash", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_ppm = ground.ppm(position.y)
	_sq = ground.squash(position.y)
	var lmin := float(sp.get("life_min_s", 0.3))
	var lmax := float(sp.get("life_max_s", 0.5))
	life = rng.randf_range(lmin, lmax)
	_color = Color.html(String(sp.get("drop_color", "#d2ccc2d8")))
	_ring_color = Color.html(String(sp.get("ring_color", "#e2e6ee80")))
	_dark_color = Color.html(String(sp.get("dark_color", "#40302073")))
	_ring_m = float(sp.get("ring_m", 0.24))
	_crown_s = float(sp.get("crown_s", 0.15))
	if part == DROPS:
		var n := rng.randi_range(int(sp.get("drops_min", 6)), int(sp.get("drops_max", 10)))
		for i in n:
			var ang := rng.randf_range(-PI, PI)
			var hv := rng.randf_range(float(sp.get("speed_min_mps", 0.3)), float(sp.get("speed_max_mps", 0.9)))
			var v := Vector2(cos(ang), sin(ang)) * hv + forward * hv * 0.35
			# Time aloft fits the splash life: vz = g·T/2 with T within the life.
			var t_air := rng.randf_range(life * 0.55, life * 0.95)
			_drops.append({"v": v, "vz": G * t_air / 2.0, "r": rng.randf_range(float(sp.get("drop_min_m", 0.003)), float(sp.get("drop_max_m", 0.007))), "t_end": t_air})
	queue_redraw()


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	queue_redraw()


## Floor point (metres from the foot) + height (metres) → local screen offset.
func _to_screen(g: Vector2, h: float) -> Vector2:
	return Vector2(g.x * _ppm, g.y * _ppm * _sq - h * _ppm)


func _draw() -> void:
	_crown()
	if part == DROPS:
		var fade := 1.0 - smoothstep(0.6, 1.0, age / life)
		for d in _drops:
			if age > float(d["t_end"]) + 0.04:
				continue
			var t: float = minf(age, d["t_end"])
			var v: Vector2 = d["v"]
			var vz: float = d["vz"]
			var h := maxf(vz * t - 0.5 * G * t * t, 0.0)
			var p := _to_screen(v * t, h)
			var t0 := maxf(t - 0.04, 0.0)
			var h0 := maxf(vz * t0 - 0.5 * G * t0 * t0, 0.0)
			var p0 := _to_screen(v * t0, h0)
			var w := maxf(float(d["r"]) * 2.0 * _ppm, 1.6)
			# A round drop with a short fading trail; two tones: a dark rim reads on the bright sky in
			# a puddle, a light core on dark mud.
			var dark := Color(_dark_color, _dark_color.a * fade)
			var light := Color(_color, _color.a * fade)
			if p.distance_to(p0) > 1.0:
				draw_line(p0, p, Color(light, light.a * 0.45), w * 0.55, true)
			draw_circle(p, (w + 1.0) * 0.5, dark, true, -1.0, true)
			draw_circle(p, w * 0.5, light, true, -1.0, true)
	else:
		# Two rings (outer, then a smaller one 0.12 s later), ease-out spread, fading; each a dark
		# trough outside and a light crest inside, like the drop rings of the water shader.
		for ring in [[1.0, 0.0], [0.6, 0.12]]:
			var kk := clampf((age - float(ring[1])) / life, 0.0, 1.0)
			if kk <= 0.0:
				continue
			var ee := 1.0 - (1.0 - kk) * (1.0 - kk)
			var r := _ring_m * float(ring[0]) * ee * _ppm
			var fade := (1.0 - kk) * (1.0 - kk * 0.3)
			var lw := maxf(1.2, 0.006 * _ppm)
			_ellipse(r + lw, (r + lw) * _sq, Color(_dark_color, _dark_color.a * fade * 0.8), lw)
			_ellipse(r, r * _sq, Color(_ring_color, _ring_color.a * fade), lw)


## The water thrown up round the boot in the first ~0.15 s: a low ring of spray. Its near half is
## drawn by DROPS (in front of the boot), its far half by RING (on the floor, behind the boot).
func _crown() -> void:
	var k := age / _crown_s
	if k >= 1.0:
		return
	var r := lerpf(0.06, 0.16, 1.0 - (1.0 - k) * (1.0 - k)) * _ppm
	var h := 0.035 * sin(k * PI) * _ppm
	var fade := (1.0 - k)
	var lw := maxf(1.5, 0.014 * _ppm)
	var a0 := 0.0 if part == DROPS else PI
	var pts := PackedVector2Array()
	for i in 17:
		var a := a0 + PI * float(i) / 16.0
		pts.append(Vector2(cos(a) * r, sin(a) * r * _sq - h))
	draw_polyline(pts, Color(_dark_color, _dark_color.a * fade), lw + 1.2, true)
	draw_polyline(pts, Color(_color, _color.a * fade), lw, true)


func _ellipse(rx: float, ry: float, c: Color, w: float) -> void:
	if rx < 0.5:
		return
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, c, w, true)
