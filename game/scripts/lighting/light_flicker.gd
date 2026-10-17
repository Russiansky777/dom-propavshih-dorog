class_name LightFlicker
extends RefCounted
## Smooth random flicker of a flame (stove, lamp, a lit doorway): a value around 0 in about −1..1,
## from two octaves of 1D simplex noise (slow breathing + quick licks) — no visible period, no
## frame-rate dependence (a function of time only). `amount` scales the result where it is used.
## Data (lights/<LOC>.json, `flicker`): {amount, speed, seed}.

var noise := FastNoiseLite.new()
var speed: float = 1.0
var amount: float = 0.0


func _init(spec: Dictionary = {}, default_seed: int = 0) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(spec.get("seed", default_seed))
	noise.frequency = 1.0
	speed = float(spec.get("speed", 1.0))
	amount = float(spec.get("amount", 0.0))


## Raw value at time `t` (seconds), roughly −1..1.
func sample(t: float) -> float:
	var slow := noise.get_noise_1d(t * speed * 1.7)
	var quick := noise.get_noise_1d(t * speed * 7.3 + 101.0)
	return clampf(slow * 0.65 + quick * 0.45, -1.0, 1.0)


## Multiplier for an intensity: 1 + amount × sample(t) (never below 0).
func factor(t: float) -> float:
	return maxf(0.0, 1.0 + amount * sample(t))
