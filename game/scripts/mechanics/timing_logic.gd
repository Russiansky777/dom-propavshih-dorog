class_name TimingLogic
extends RefCounted
## «Точный удар» (Director 23.10, F7/F8): a marker sweeps along a bar left → right → left at an even speed;
## the bar is red at both ends and green round `center`. A strike while the marker is inside the green is a
## hit; `hits` hits in a row finish it. A strike outside the green is a miss: the series starts again and
## the owner shows the consequence (the brace jumps off the crack, the hook slips and falls) while the
## marker waits `miss_s`. No limit on tries, nothing is lost — a miss only costs the series.
## Pure logic on its own clock (`step(dt)`): tests drive it exactly; TimingBar draws it and takes the input.
##
## Data (a mechanic's `timing` block, every field optional):
##   hits        how many in a row (3 — the brace; 1 — the hook, the shutter latch)
##   period_s    one full sweep there and back at normal speed (2.0)
##   green       width of the green zone as a fraction of the bar (0.2), centred at `center` (0.5)
##   miss_s      the pause after a miss while the consequence plays (0.9)
##   hit_s       the marker holds a moment after a hit — the blow lands (0.25)
##   start       where the marker starts, 0..1 (0 — the left end)
##   green_easy  (kept in the data, no longer read: J, Director 29.10 — every zone is `green` × green_k, normal 0.7,
##               «Облегчить» 1.1)
## Accessibility (G3, Director 23.10: «Облегчить мини-игры»): `slow_k` multiplies the period (TimingBar.SLOW_K) and
## `green_k` widens the green zone round its centre (TimingBar.EASY_GREEN_K) — TimingBar.apply_ease sets both.

var hits_needed: int = 3
var period_s: float = 2.0
var green: float = 0.2
var center: float = 0.5
var miss_s: float = 0.9
var hit_s: float = 0.25
var slow_k: float = 1.0
var green_k: float = 1.0      # «Облегчить»: the green zone this many times wider (centre kept, clamped to the bar)
var green_easy: float = 0.0   # «Облегчить»: this width instead of green × green_k (0 — not set)

var phase: float = 0.0        # 0..1 along one full sweep there and back
var hits: int = 0             # hits in the current series
var misses: int = 0           # every miss so far (tests; never shown, never punished)
var total_hits: int = 0
var state: String = "run"     # run | hit | miss | done
var last_pos: float = 0.0     # where the marker was at the last strike
var _state_t: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	hits_needed = maxi(int(cfg.get("hits", hits_needed)), 1)
	period_s = maxf(float(cfg.get("period_s", period_s)), 0.2)
	green = clampf(float(cfg.get("green", green)), 0.02, 0.9)
	green_easy = clampf(float(cfg.get("green_easy", 0.0)), 0.0, 0.9)
	center = clampf(float(cfg.get("center", center)), green * 0.5, 1.0 - green * 0.5)
	miss_s = maxf(float(cfg.get("miss_s", miss_s)), 0.0)
	hit_s = maxf(float(cfg.get("hit_s", hit_s)), 0.0)
	phase = clampf(float(cfg.get("start", 0.0)), 0.0, 1.0) * 0.5


## The marker, 0 (left end) … 1 (right end): an even triangle sweep.
func pos() -> float:
	return pos_at(phase)


## Where the marker is at sweep phase `ph` (the hook: where it was when the «стой» ring began).
static func pos_at(ph: float) -> float:
	var p := fposmod(ph, 1.0)
	return p * 2.0 if p < 0.5 else 2.0 - p * 2.0


## The green zone's width now: `green` × `green_k` («Облегчить»; `green_easy` when the data gives it), never wider than 0.9 of the bar.
func green_w() -> float:
	return clampf(green * green_k, 0.04, 0.9)


## The zone [from, to] on the bar; a widened zone near an end is shifted inwards so it stays as wide.
func zone() -> Vector2:
	var g := green_w()
	var c := clampf(center, g * 0.5, 1.0 - g * 0.5)
	return Vector2(c - g * 0.5, c + g * 0.5)


func in_green(p: float) -> bool:
	var z := zone()
	return p >= z.x - 1e-6 and p <= z.y + 1e-6


## How warm the bar is at `p`: 1 in the green, falling to 0 at the ends (the bar's colours).
func warmth(p: float) -> float:
	var z := zone()
	var d := maxf(z.x - p, p - z.y)
	if d <= 0.0:
		return 1.0
	var far := maxf(z.x, 1.0 - z.y)
	return clampf(1.0 - d / maxf(far, 0.01), 0.0, 1.0)


func done() -> bool:
	return state == "done"


func ready() -> bool:
	return state == "run"


func step(dt: float) -> void:
	match state:
		"run":
			phase = fmod(phase + dt / (period_s * slow_k), 1.0)
		"hit":
			_state_t += dt
			if _state_t >= hit_s:
				state = "run"
		"miss":
			_state_t += dt
			if _state_t >= miss_s:
				state = "run"
				phase = 0.0   # the series starts again from the left end


## A strike now: "hit", "done" (the last hit of the series), "miss", or "busy" (a consequence is playing).
func strike() -> String:
	if state != "run":
		return "busy" if state != "done" else "done_already"
	last_pos = pos()
	_state_t = 0.0
	if in_green(last_pos):
		hits += 1
		total_hits += 1
		if hits >= hits_needed:
			state = "done"
			return "done"
		state = "hit"
		return "hit"
	misses += 1
	hits = 0
	state = "miss"
	return "miss"


## Seconds until the marker is next inside the green (tests and the web check wait for it).
func seconds_to_green() -> float:
	if state != "run":
		return -1.0
	var per := period_s * slow_k
	var p0 := phase
	var z := zone()
	var mid := (z.x + z.y) * 0.5
	var near := green_w() * 0.3
	for i in 400:
		var ph := fmod(p0 + float(i) / 400.0, 1.0)
		var q := ph * 2.0 if ph < 0.5 else 2.0 - ph * 2.0
		if absf(q - mid) <= near:
			return float(i) / 400.0 * per
	return 0.0
