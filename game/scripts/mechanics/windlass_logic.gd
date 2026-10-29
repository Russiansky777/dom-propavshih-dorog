class_name WindlassLogic
extends RefCounted
## The first span (M25): Ilya at the windlass lowers the first log from the shore crib onto the near pier; Agata
## gives the mill signals from Pelageya's board — «Пускай» (lower), «Стой» (stop), «Подымай» (raise): the same three
## as for the hook in the office, but now her brother is next to her and hears her voice (scenario §8, M25).
##
## Positions are fractions of the way down: 0 — the far end hoisted high over the water (Ilya holds it there at the
## start), `rest` — the far end on the ring of the old plate. Any «Стой» within `tolerance` of `rest` settles the log on
## the ring (solved): going down, going up, or already stopped there (G46, Director 23.10: «Стой» on the way up and a
## second «Стой» in the zone did nothing — the log never settled). Let down past `rest + tolerance` — it knocks against
## the stone of the pier and stays there, skewed (`bump_over` below the zone, so a «Стой» there is not «at the ring»),
## until the player signals «Подымай»: then Ilya hauls it up (stop it at the ring on the way, or let it go to the
## top) and they try again. No penalty, no counter (the same rule as the hook: «Наказания нет»). Stopped too high —
## «Пускай» again.
##
## States (probe / tests): wait (at the top), down, stopped, up, bumped (on the stone edge), settling, solved.

signal event(name: String)   # "moving", "stopped", "bumped", "raised", "settling", "solved"

var rest: float = 0.82
var tolerance: float = 0.06
var speed: float = 0.12          # fractions per second going down
var raise_speed: float = 0.3     # going up
var settle_s: float = 0.8
var bump_over: float = 0.03      # how far below the ring zone the log lies against the stone

var pos: float = 0.0
var state: String = "wait"
var settle: float = 0.0          # 0..1 while settling on the ring (drawn by the panel)
var _t: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	rest = float(cfg.get("rest", rest))
	tolerance = float(cfg.get("tolerance", tolerance))
	speed = float(cfg.get("speed", speed))
	raise_speed = float(cfg.get("raise_speed", raise_speed))
	settle_s = float(cfg.get("settle_s", settle_s))
	bump_over = float(cfg.get("bump_over", bump_over))


## «Облегчить мини-игры» (G3): the log moves `slow` times slower and the ring zone is `wide` times wider (kept above
## the stone: the zone never reaches past the bump line).
func ease(slow: float, wide: float) -> void:
	speed /= maxf(slow, 0.01)
	raise_speed /= maxf(slow, 0.01)
	# J (стр. 192): the normal zone narrower too (wide < 1), «Облегчить» a little wider; never past the stone
	tolerance = minf(tolerance * maxf(wide, 0.3), maxf(1.0 - rest - bump_over, tolerance))


func solved() -> bool:
	return state == "solved"


func at_ring() -> bool:
	return absf(pos - rest) <= tolerance


## A signal: "lower" (пускай), "stop" (стой), "raise" (подымай). Returns true when Ilya acts on it.
func apply(sig: String) -> bool:
	match state:
		"wait", "stopped":
			if sig == "lower":
				state = "down"
				event.emit("moving")
				return true
			if sig == "raise" and pos > 0.0:
				state = "up"
				event.emit("moving")
				return true
			if sig == "stop" and state == "stopped" and at_ring():
				_settle()   # stopped in the zone and «Стой» again: it is at the ring — let it settle
				return true
		"down", "up":
			if sig == "stop":
				if at_ring():
					_settle()
				else:
					state = "stopped" if pos > 0.0 else "wait"
					event.emit("stopped")
				return true
			if sig == "raise" and state == "down":
				state = "up"
				return true
			if sig == "lower" and state == "up":
				state = "down"
				return true
		"bumped":
			if sig == "raise":
				state = "up"
				event.emit("raised")
				return true
	return false


func _settle() -> void:
	state = "settling"
	_t = 0.0
	event.emit("settling")


func step(dt: float) -> void:
	match state:
		"down":
			pos += speed * dt
			if pos > rest + tolerance:
				pos = rest + tolerance + bump_over
				state = "bumped"
				event.emit("bumped")
		"up":
			pos -= raise_speed * dt
			if pos <= 0.0:
				pos = 0.0
				state = "wait"
				event.emit("stopped")
		"settling":
			_t += dt
			settle = clampf(_t / maxf(settle_s, 0.01), 0.0, 1.0)
			pos = lerpf(pos, rest, settle)
			if settle >= 1.0:
				pos = rest
				state = "solved"
				event.emit("solved")


## The log's angle for the panel: `max_deg` at the top, 0 on the ring; past the ring (bumped) a little below 0 and
## skewed — the far end against the stone.
func angle(max_deg: float) -> float:
	if pos <= rest:
		return max_deg * (1.0 - pos / maxf(rest, 0.01))
	return -max_deg * 0.12 * (pos - rest) / maxf(tolerance, 0.01)


## The zone of the ring in positions (the gauge's green band): [rest - tolerance, rest + tolerance].
func zone() -> Vector2:
	return Vector2(rest - tolerance, rest + tolerance)
