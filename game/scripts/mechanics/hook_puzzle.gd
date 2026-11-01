class_name HookPuzzle
extends RefCounted
## The hook and the bar (M12). Pavel, outside the office door, blind, feeds an iron hook into the door gap from the
## BOTTOM and leads it up; Agata sees the bar in the mirror and rings the mill signals: "one" — «пускай», "two" —
## «стой», "long" — «подымай».
## Director 01.11, 22:26 (before: «что-то не так в ней… скорее в крюке или в механике»; the old version swayed the
## hook up and down along the gap with a «Точный удар» bar beside the glass — gone):
##   1. «пускай» — Pavel leads the hook up, slowly and steadily: no sway, no going back down.
##   2. The hook cannot pass the bar: it comes up against its underside and stops there (`stop_at` — the bent tip
##      touches the bar from below; the bar gives a tiny nudge in the glass). That is the moment for «стой».
##   3. «подымай» — Pavel jerks the hook up a short way (`reach`): from under the bar the bar comes out of its
##      brackets (lift_bar → solved).
##   4. Mistakes as in life, no penalty, nothing lost:
##      - «стой» not given in time (`contact_s` against the bar): Pavel keeps pushing blind — the hook scrapes and
##        drives the bar deeper into the brackets (M09, Pavel: «вслепую крюком скрести — засов глубже в скобы
##        загонишь»), the bar jolts, the hook slips down to the bottom; «пускай» again.
##      - «подымай» farther below the bar than a jerk reaches: the jerk goes into empty air — the hook jumps up a bit
##        and falls back where it was.
##      - «стой» far below: the hook simply stops there; «пускай» leads it on; «подымай» from just under the bar
##        (within `reach`) lifts it.
## While the bell is ringing (`listening`) Pavel holds still to hear which signal it is: a «стой» is judged where the
## hook was when its first strike rang.
##
## Positions are fractions of the gap: 0 — top, 1 — bottom; the hook only ever goes up (pos down) while Pavel leads
## it, and never above `stop_at` unless the bar is being lifted. State names (probe/tests, the signal card):
##   wait (at the bottom, Pavel waits for "one"), up (going up), contact (against the bar from below), held (stopped
##   below, out of reach), stopped (stopped under the bar, within reach), jerk (an empty jerk), jam (pushed too far:
##   the bar jolts deeper), falling (slipping down to the bottom), lift_bar, solved.

signal event(name: String)   # "moving", "contact", "held", "stopped", "jerked", "missed", "returned", "solved"

var bar: float = 0.41           # the bar's line in the gap (where the hook layer is drawn as is)
var under: float = 0.0295       # the hook's tip touches the bar's underside this far below `bar`
var start: float = 0.93         # where Pavel feeds the hook in (bottom of the gap)
var speed: float = 0.11         # gap fractions per second going up
var reach: float = 0.07         # how far a jerk («подымай») reaches up
var contact_s: float = 1.5      # how long Pavel stays against the bar before he pushes on blind
var lift_s: float = 0.9         # the bar coming up with the hook
var jerk_s: float = 0.6         # an empty jerk: up and back
var jam_s: float = 0.35         # the hook scraping, the bar jolting deeper
var fall_s: float = 0.8         # the hook slipping down to the bottom
var slow_k: float = 1.0         # «Облегчить мини-игры»: speed / slow_k, contact_s * slow_k
var reach_k: float = 1.0        # «Облегчить мини-игры»: reach * reach_k

var pos: float = 0.93
var state: String = "wait"
var listening: bool = false     # the bell is ringing: Pavel holds still to hear the signal
var lift_amount: float = 0.0    # 0..1 while the bar is being lifted
var misses: int = 0
var _t: float = 0.0
var _from: float = 0.0
var _after_jerk: String = "held"


func _init(cfg: Dictionary = {}) -> void:
	bar = float(cfg.get("bar", bar))
	under = float(cfg.get("under", under))
	start = float(cfg.get("start", start))
	speed = float(cfg.get("speed", speed))
	reach = float(cfg.get("reach", reach))
	contact_s = float(cfg.get("contact_s", contact_s))
	lift_s = float(cfg.get("lift_s", lift_s))
	jerk_s = float(cfg.get("jerk_s", jerk_s))
	jam_s = float(cfg.get("jam_s", jam_s))
	fall_s = float(cfg.get("fall_s", fall_s))
	pos = start


## «Облегчить мини-игры» (G3): Pavel leads the hook `slow` times slower (and waits as much longer against the bar),
## the jerk reaches `wide` times farther.
func ease(slow: float, wide: float) -> void:
	slow_k = maxf(slow, 0.01)
	reach_k = maxf(wide, 1.0)


func solved() -> bool:
	return state == "solved"


## Where the hook stops against the bar from below.
func stop_at() -> float:
	return bar + under


func lead_speed() -> float:
	return speed / slow_k


func jerk_reach() -> float:
	return reach * reach_k


func contact_time() -> float:
	return contact_s * slow_k


## Within a jerk's reach of the bar: «подымай» lifts it.
func in_reach() -> bool:
	return pos - stop_at() <= jerk_reach() + 1e-6


func at_bar() -> bool:
	return in_reach()


## The bar's lift for the picture, in units of a full lift: 0..1 while lifting; a tiny nudge up when the hook comes
## against it; a jolt down (deeper into the brackets) when Pavel pushes on blind.
func bar_shift() -> float:
	match state:
		"lift_bar", "solved":
			return lift_amount
		"contact":
			return 0.06 * maxf(0.0, 1.0 - _t / 0.3)
		"jam":
			return -0.12 * sin(clampf(_t / jam_s, 0.0, 1.0) * PI)
	return 0.0


## A signal from the bell. Ignored while the hook is busy (jerking, scraping, falling, lifting) or the bar is out.
func apply(sig: String) -> void:
	match sig:
		"one":
			if state in ["wait", "held", "stopped"]:
				state = "up"
				event.emit("moving")
			# "up", "contact": he is already going on — «пускай» changes nothing.
		"two":
			if state == "up":
				_stop()
			elif state == "contact":
				_t = 0.0
				state = "stopped"
				event.emit("stopped")
		"long":
			if state in ["wait", "up", "contact", "held", "stopped"]:
				if state == "contact" or in_reach():
					_from = pos
					_t = 0.0
					state = "lift_bar"
				else:
					_from = pos
					_after_jerk = "wait" if state == "wait" else "held"
					_t = 0.0
					misses += 1
					state = "jerk"
					event.emit("jerked")


func _stop() -> void:
	_t = 0.0
	if in_reach():
		state = "stopped"
		event.emit("stopped")
	else:
		state = "held"
		event.emit("held")


func step(dt: float) -> void:
	match state:
		"up":
			if listening:
				return
			pos = maxf(pos - lead_speed() * dt, stop_at())
			if pos <= stop_at() + 1e-6:
				pos = stop_at()
				_t = 0.0
				state = "contact"
				event.emit("contact")
		"contact":
			if listening:
				return
			_t += dt
			if _t >= contact_time():
				# no «стой»: Pavel pushes on blind — the hook scrapes, the bar goes deeper
				_t = 0.0
				misses += 1
				state = "jam"
				event.emit("missed")
		"jam":
			_t += dt
			if _t >= jam_s:
				_t = 0.0
				_from = pos
				state = "falling"
		"falling":
			_t += dt
			var x := clampf(_t / fall_s, 0.0, 1.0)
			pos = lerpf(_from, start, x * x)
			if _t >= fall_s:
				pos = start
				state = "wait"
				event.emit("returned")
		"jerk":
			_t += dt
			var x := clampf(_t / jerk_s, 0.0, 1.0)
			# a quick jerk up by the reach, then back down where it was
			pos = _from - jerk_reach() * sin(x * PI) * (1.0 - 0.35 * x)
			pos = maxf(pos, stop_at())
			if _t >= jerk_s:
				pos = _from
				state = _after_jerk
		"lift_bar":
			_t += dt
			# the hook goes the last bit up to the bar, then bar and hook come up together
			pos = lerpf(_from, stop_at(), clampf(_t / 0.15, 0.0, 1.0))
			lift_amount = clampf((_t - 0.15) / maxf(lift_s - 0.15, 0.01), 0.0, 1.0)
			if _t >= lift_s:
				pos = stop_at()
				lift_amount = 1.0
				state = "solved"
				event.emit("solved")
