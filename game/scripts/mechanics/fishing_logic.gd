class_name FishingLogic
extends RefCounted
## The fight with a hooked perch (Директор 01.11, 21:59: «вернуть натяжение… окунь вытягивался независимо от натяжения;
## а в обычной рыбалке смысл другой: он уплывает, если не тянуть»). Pure logic, no drawing (FishingPanel draws it).
##
## `tension` 0..1 — how hard the string is held: a press (mouse button / Space held) raises it by `pull` a second,
## let go — it falls by `release`; the fish's runs (рывки, now and then: `run_rate` a second, `run_s` long, force
## `run_force`) yank it up while they last. Three zones on the scale:
##   below `green.x` — slack: the fish swims away (`dist` grows, faster on a run, the line paying out) and works the hook
##                     loose: `slack_risk` fills (in `slack_s` at a full slack) — at 1 the perch is off ("escaped");
##   green           — the string held right: the perch comes in at `reel` m a second (slower against a run);
##   above `green.y` — too hard: it still comes in, slower, but `over_risk` fills (in `over_s` at the very top, faster
##                     on a run) — at 1 the string snaps / the hook tears out ("snapped").
## The risks drain back (`recover` a second) while the string is held right. `dist` from `start_m`; the perch is
## landed at 0 ("landed"), it is gone if it gets `max_m` out ("escaped"). Nothing is landed without the string held:
## with no press the tension falls to nothing and the perch leaves.
## «Облегчить мини-игры» (TimingBar.slow): `green_easy` instead of `green`, the fish `easy_fish` as strong and as
## often on its runs, swimming away slower, the risks `easy_risk` times slower, the needle `easy_needle` as fast.

signal event(name: String)   # "run" (the fish starts a run), "landed", "escaped", "snapped"

const DEFAULTS := {
	"green": [0.42, 0.72], "green_easy": [0.3, 0.84],
	"pull": 0.6, "release": 0.55, "yank": 0.5,
	"reel": 0.85, "swim": 0.55, "pay": 1.1, "pay_held": 0.55, "haul": 0.45,
	"start_m": 4.5, "max_m": 10.0,
	"slack_s": 1.7, "over_s": 1.1, "recover": 0.6,
	"run_rate": 0.4, "run_s": [0.7, 1.5], "run_force": [0.55, 1.0],
	"easy_fish": 0.6, "easy_risk": 1.7, "easy_needle": 0.8,
}

var cfg: Dictionary = {}
var easy: bool = false
var green: Vector2 = Vector2(0.42, 0.72)
var pull: float = 0.6
var release: float = 0.55
var yank: float = 0.5
var reel: float = 0.85
var swim: float = 0.55
var pay: float = 1.1
var pay_held: float = 0.55
var haul: float = 0.45
var start_m: float = 4.5
var max_m: float = 10.0
var slack_s: float = 1.7
var over_s: float = 1.1
var recover: float = 0.6
var run_rate: float = 0.4
var run_s: Vector2 = Vector2(0.7, 1.5)
var run_force: Vector2 = Vector2(0.55, 1.0)
var fish_k: float = 1.0

var state: String = "fight"    # fight | landed | escaped | snapped
var tension: float = 0.0
var dist: float = 4.5
var slack_risk: float = 0.0
var over_risk: float = 0.0
var pulling: bool = false
var run_t: float = 0.0         # seconds of the current run left (0 — the fish is not running)
var run_f: float = 0.0
var away: float = 0.0          # m/s the fish gained in the last step (+ away, − coming in): the panel turns it
var time_s: float = 0.0
var rng := RandomNumberGenerator.new()


func _init(p_cfg: Dictionary = {}, p_easy: bool = false, seed_v: int = -1) -> void:
	cfg = p_cfg.duplicate()
	if seed_v >= 0:
		rng.seed = seed_v
	configure(p_easy)
	dist = start_m
	tension = (green.x + green.y) * 0.5


func _v(k: String) -> Variant:
	return cfg.get(k, DEFAULTS[k])


static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The parameters from the data, eased or not («Облегчить» may be toggled mid-fight: the state stays as it is).
func configure(p_easy: bool) -> void:
	easy = p_easy
	green = _vec(_v("green_easy") if easy else _v("green"))
	var needle := float(_v("easy_needle")) if easy else 1.0
	pull = float(_v("pull")) * needle
	release = float(_v("release")) * needle
	yank = float(_v("yank"))
	reel = float(_v("reel"))
	fish_k = float(_v("easy_fish")) if easy else 1.0
	swim = float(_v("swim")) * fish_k
	pay = float(_v("pay"))
	pay_held = float(_v("pay_held"))
	haul = float(_v("haul"))
	start_m = float(_v("start_m"))
	max_m = float(_v("max_m"))
	var rk := float(_v("easy_risk")) if easy else 1.0
	slack_s = float(_v("slack_s")) * rk
	over_s = float(_v("over_s")) * rk
	recover = float(_v("recover"))
	run_rate = float(_v("run_rate")) * fish_k
	run_s = _vec(_v("run_s"))
	run_force = _vec(_v("run_force")) * fish_k


## The zone the needle is in: "slack", "green", "over".
func zone(t: float = -1.0) -> String:
	var v := tension if t < 0.0 else t
	if v < green.x:
		return "slack"
	if v > green.y:
		return "over"
	return "green"


## How far in, 0 (just hooked, `start_m` out) … 1 (landed); below 0 while it is further out than at the strike.
func progress() -> float:
	return 1.0 - dist / maxf(start_m, 0.01)


func running() -> bool:
	return run_t > 0.0


func done() -> bool:
	return state != "fight"


func step(delta: float) -> void:
	if state != "fight" or delta <= 0.0:
		return
	time_s += delta
	# the fish: a run now and then — it yanks the string and takes line
	if run_t > 0.0:
		run_t = maxf(run_t - delta, 0.0)
		if run_t == 0.0:
			run_f = 0.0
	elif rng.randf() < delta * run_rate:
		run_t = rng.randf_range(run_s.x, run_s.y)
		run_f = rng.randf_range(run_force.x, run_force.y)
		event.emit("run")
	tension += (pull if pulling else -release) * delta + run_f * yank * delta
	tension = clampf(tension, 0.0, 1.0)
	var d0 := dist
	match zone():
		"slack":
			var deep := 1.0 - tension / maxf(green.x, 0.01)        # 0 at the band's edge, 1 — the string hangs
			dist += (swim * (0.4 + 0.6 * deep) + run_f * pay) * delta
			slack_risk += (0.35 + 0.65 * deep) / maxf(slack_s, 0.05) * delta
			over_risk = maxf(over_risk - recover * delta, 0.0)
		"green":
			dist -= maxf(reel - run_f * pay_held, 0.0) * delta
			slack_risk = maxf(slack_risk - recover * delta, 0.0)
			over_risk = maxf(over_risk - recover * delta, 0.0)
		"over":
			var hard := (tension - green.y) / maxf(1.0 - green.y, 0.01)   # 0 at the band's edge, 1 — at the very top
			dist -= reel * haul * delta
			over_risk += (0.35 + 0.65 * hard) * (1.0 + run_f) / maxf(over_s, 0.05) * delta
			slack_risk = maxf(slack_risk - recover * delta, 0.0)
	dist = clampf(dist, 0.0, max_m)
	away = (dist - d0) / delta
	if over_risk >= 1.0:
		_end("snapped")
	elif slack_risk >= 1.0 or dist >= max_m:
		_end("escaped")
	elif dist <= 0.0:
		_end("landed")


func _end(s: String) -> void:
	state = s
	pulling = false
	run_t = 0.0
	run_f = 0.0
	event.emit(s)
