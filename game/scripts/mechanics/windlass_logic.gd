class_name WindlassLogic
extends RefCounted
## The first span (M25): Ilya at the windlass lowers the first log from the shore crib onto the near pier; Agata
## gives the mill signals from Pelageya's board — «Пускай» (lower), «Стой» (stop), «Подымай» (raise): the same three
## as for the hook in the office, but now her brother is next to her and hears her voice (scenario §8, M25).
##
## Positions are fractions of the way down: 0 — the far end hoisted high over the water (Ilya holds it there at the
## start), `rest` — the far end on the ring of the old plate. Stopped within `tolerance` of `rest` the log settles on
## the ring (solved). Let down past `rest + tolerance` — it knocks against the stone of the pier and stays there,
## skewed, until the player signals «Подымай»: then Ilya hauls it up to the top and they try again. No penalty,
## no counter (the same rule as the hook: «Наказания нет»). Stopped too high — «Пускай» again.
##
## States (probe / tests): wait (at the top), down, stopped, up, bumped (on the stone edge), settling, solved.

signal event(name: String)   # "moving", "stopped", "bumped", "raised", "settling", "solved"

var rest: float = 0.82
var tolerance: float = 0.06
var speed: float = 0.12          # fractions per second going down
var raise_speed: float = 0.3     # going up
var settle_s: float = 0.8

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
		"down":
			if sig == "stop":
				if at_ring():
					state = "settling"
					_t = 0.0
					event.emit("settling")
				else:
					state = "stopped"
					event.emit("stopped")
				return true
			if sig == "raise":
				state = "up"
				return true
		"up":
			if sig == "stop":
				state = "stopped" if pos > 0.0 else "wait"
				event.emit("stopped")
				return true
			if sig == "lower":
				state = "down"
				return true
		"bumped":
			if sig == "raise":
				state = "up"
				event.emit("raised")
				return true
	return false


func step(dt: float) -> void:
	match state:
		"down":
			pos += speed * dt
			if pos > rest + tolerance:
				pos = rest + tolerance
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
