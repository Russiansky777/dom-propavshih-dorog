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
var _ring_m: float = 0.24


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
	_ring_m = float(sp.get("ring_m", 0.24))
	if part == DROPS:
		var n := rng.randi_range(int(sp.get("drops_min", 6)), int(sp.get("drops_max", 10)))
		for i in n:
			var ang := rng.randf_range(-PI, PI)
			var hv := rng.randf_range(float(sp.get("speed_min_mps", 0.3)), float(sp.get("speed_max_mps", 0.9)))
			var v := Vector2(cos(ang), sin(ang)) * hv + forward * hv * 0.35
			# Time aloft fits the splash life: vz = g·T/2 with T within the life.
			var t_air := rng.randf_range(life * 0.55, life * 0.95)
			_drops.append({"v": v, "vz": G * t_air / 2.0, "r": rng.randf_range(0.005, 0.011), "t_end": t_air})
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
	if part == DROPS:
		for d in _drops:
			var t: float = minf(age, d["t_end"])
			if age > d["t_end"] + 0.06:
				continue
			var v: Vector2 = d["v"]
			var vz: float = d["vz"]
			var h := maxf(vz * t - 0.5 * G * t * t, 0.0)
			var p := _to_screen(v * t, h)
			var t0 := maxf(t - 0.025, 0.0)
			var h0 := maxf(vz * t0 - 0.5 * G * t0 * t0, 0.0)
			var p0 := _to_screen(v * t0, h0)
			var w := maxf(float(d["r"]) * 2.0 * _ppm, 1.0)
			var c := _color
			c.a *= 1.0 - smoothstep(0.6, 1.0, age / life)
			if p.distance_to(p0) > 0.5:
				draw_line(p0, p, c, w, true)
			else:
				draw_circle(p, w * 0.5, c, true, -1.0, true)
	else:
		# Two rings (outer, then a smaller one 0.12 s later), ease-out spread, fading.
		for ring in [[1.0, 0.0], [0.6, 0.12]]:
			var kk := clampf((age - float(ring[1])) / life, 0.0, 1.0)
			if kk <= 0.0:
				continue
			var ee := 1.0 - (1.0 - kk) * (1.0 - kk)
			var r := _ring_m * float(ring[0]) * ee * _ppm
			var c := _ring_color
			c.a *= (1.0 - kk) * (1.0 - kk * 0.3)
			_ellipse(r, r * _sq, c, maxf(1.2, 0.006 * _ppm))


func _ellipse(rx: float, ry: float, c: Color, w: float) -> void:
	if rx < 0.5:
		return
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, c, w, true)
