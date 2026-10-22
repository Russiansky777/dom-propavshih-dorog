class_name HookPuzzle
extends RefCounted
## The hook and the bar (M12). Pavel, outside the office door, leads an iron hook down along the door,
## blind; Agata sees the bar in the mirror and rings the mill signals: "one" — go on (down), "two" — stop,
## "long" — lift. Lifted within `tolerance` of the bar, the hook takes it out of the brackets (solved).
## Lifted anywhere else, or let down past the bottom of the gap, it slips off and Pavel brings it back to
## the top — no penalty, no counter, nothing lost (scenario: «Рано или поздно — крюк соскальзывает,
## Павел возвращает его наверх и ведёт снова. Наказания нет»).
##
## Positions are fractions of the gap: 0 — top, 1 — bottom. State names (probe/tests):
##   wait (at the top, Pavel waits for "one"), down, stopped, lift_bar, lift_empty, slipping, solved.

signal event(name: String)   # "moving", "stopped", "slipped", "returned", "solved"

var bar: float = 0.55
var tolerance: float = 0.06
var speed: float = 0.1          # gap fractions per second going down
var return_speed: float = 0.6   # back to the top after a slip
var lift_s: float = 0.9         # the bar coming up with the hook
var slip_s: float = 0.45        # the empty hook jerks up and slides off

var pos: float = 0.0
var state: String = "wait"
var lift_amount: float = 0.0    # 0..1 while the bar is being lifted (drawn by the panel)
var _t: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	bar = float(cfg.get("bar", bar))
	tolerance = float(cfg.get("tolerance", tolerance))
	speed = float(cfg.get("speed", speed))
	return_speed = float(cfg.get("return_speed", return_speed))
	lift_s = float(cfg.get("lift_s", lift_s))
	slip_s = float(cfg.get("slip_s", slip_s))


func solved() -> bool:
	return state == "solved"


func at_bar() -> bool:
	return absf(pos - bar) <= tolerance


## A signal from the bell. Ignored while the hook is busy (lifting, slipping) or the bar is out.
func apply(sig: String) -> void:
	match state:
		"wait", "stopped":
			if sig == "one":
				state = "down"
				event.emit("moving")
			elif sig == "long":
				_lift()
		"down":
			if sig == "two":
				state = "stopped"
				event.emit("stopped")
			elif sig == "long":
				_lift()


func _lift() -> void:
	_t = 0.0
	state = "lift_bar" if at_bar() else "lift_empty"


func step(dt: float) -> void:
	match state:
		"down":
			pos += speed * dt
			if pos >= 1.0:
				pos = 1.0
				_slip()
		"lift_bar":
			_t += dt
			lift_amount = clampf(_t / lift_s, 0.0, 1.0)
			if _t >= lift_s:
				state = "solved"
				event.emit("solved")
		"lift_empty":
			_t += dt
			pos = maxf(pos - 0.08 * dt / maxf(slip_s, 0.01), 0.0)
			if _t >= slip_s:
				_slip()
		"slipping":
			pos -= return_speed * dt
			if pos <= 0.0:
				pos = 0.0
				state = "wait"
				event.emit("returned")


func _slip() -> void:
	state = "slipping"
	event.emit("slipped")
