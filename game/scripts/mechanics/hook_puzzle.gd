class_name HookPuzzle
extends RefCounted
## The hook and the bar (M12). Pavel, outside the office door, leads an iron hook down along the door, blind;
## Agata sees the bar in the mirror and rings the mill signals: "one" — go on, "two" — stop, "long" — lift.
## Director 23.10 (F8: «остановиться нужно в нужной зоне, а иначе неудача и падала палочка»): after "one" the
## hook does not just slide down — Pavel feels for the bar, the hook sways up and down along the gap (a
## «Точный удар» sweep, TimingLogic); "two" must catch it in the bolt zone (`bar` ± `tolerance`). Caught — it
## stops under the bar and "long" lifts the bar out of the brackets (solved). Stopped anywhere else (or lifted
## before it is caught) — it slips off and falls to the bottom of the gap, and Pavel brings it back to the top:
## "one" again. No penalty, no counter that matters, nothing lost (scenario: «Рано или поздно — крюк
## соскальзывает, Павел возвращает его наверх и ведёт снова. Наказания нет»).
##
## Positions are fractions of the gap: 0 — top, 1 — bottom. State names (probe/tests):
##   wait (at the top, Pavel waits for "one"), down (going down to where he feels for the bar), sway (feeling:
##   up and down — catch it), stopped (caught under the bar), lift_bar, falling, slipping (Pavel brings it up),
##   solved.

signal event(name: String)   # "moving", "swaying", "stopped", "missed", "slipped", "returned", "solved"

var bar: float = 0.41
var tolerance: float = 0.07
var speed: float = 0.35         # gap fractions per second going down to the sway
var return_speed: float = 0.6   # back to the top after a fall
var lift_s: float = 0.9         # the bar coming up with the hook
var fall_s: float = 0.55        # the hook slipping off and falling
var sway: Vector2 = Vector2(0.18, 0.74)   # the range Pavel feels along (top, bottom)
var timing: TimingLogic = null  # the sway: its marker is where the hook is within `sway`

var pos: float = 0.0
var state: String = "wait"
var lift_amount: float = 0.0    # 0..1 while the bar is being lifted (drawn by the panel)
var misses: int = 0
var _t: float = 0.0
var _fall_from: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	bar = float(cfg.get("bar", bar))
	tolerance = float(cfg.get("tolerance", tolerance))
	speed = float(cfg.get("speed", speed))
	return_speed = float(cfg.get("return_speed", return_speed))
	lift_s = float(cfg.get("lift_s", lift_s))
	fall_s = float(cfg.get("fall_s", fall_s))
	var sw: Array = cfg.get("sway", [sway.x, sway.y])
	sway = Vector2(float(sw[0]), float(sw[1]))
	var span := maxf(sway.y - sway.x, 0.05)
	var tcfg: Dictionary = cfg.get("timing", {}).duplicate()
	tcfg["hits"] = 1
	tcfg["center"] = clampf((bar - sway.x) / span, 0.0, 1.0)
	tcfg["green"] = clampf(2.0 * tolerance / span, 0.02, 0.9)
	tcfg["miss_s"] = 0.0
	tcfg["hit_s"] = 0.0
	timing = TimingLogic.new(tcfg)


func solved() -> bool:
	return state == "solved"


func at_bar() -> bool:
	return absf(pos - bar) <= tolerance + 1e-6


## The sweep's marker → the hook's place in the gap.
func _sway_pos() -> float:
	return lerpf(sway.x, sway.y, timing.pos())


## A signal from the bell. Ignored while the hook is busy (lifting, falling, coming back) or the bar is out.
## `at_phase` — the sweep phase when the «стой» ring began (its first strike): the hook is judged where it was
## when the ringing started, not where it got to by the second strike.
func apply(sig: String, at_phase: float = -1.0) -> void:
	match state:
		"wait":
			if sig == "one":
				state = "down"
				event.emit("moving")
		"down", "sway":
			if sig == "two":
				var p := timing.pos() if at_phase < 0.0 else TimingLogic.pos_at(at_phase)
				if state == "sway" and timing.in_green(p):
					pos = lerpf(sway.x, sway.y, p)
					state = "stopped"
					event.emit("stopped")
				else:
					_fall()
			elif sig == "long":
				_fall()
		"stopped":
			if sig == "long":
				_t = 0.0
				state = "lift_bar"


func step(dt: float) -> void:
	match state:
		"down":
			pos += speed * dt
			if pos >= sway.x:
				pos = sway.x
				state = "sway"
				timing.phase = 0.0
				timing.state = "run"
				event.emit("swaying")
		"sway":
			timing.step(dt)
			pos = _sway_pos()
		"lift_bar":
			_t += dt
			lift_amount = clampf(_t / lift_s, 0.0, 1.0)
			if _t >= lift_s:
				state = "solved"
				event.emit("solved")
		"falling":
			_t += dt
			var x := clampf(_t / fall_s, 0.0, 1.0)
			pos = lerpf(_fall_from, 1.0, x * x)
			if _t >= fall_s:
				state = "slipping"
				event.emit("slipped")
		"slipping":
			pos -= return_speed * dt
			if pos <= 0.0:
				pos = 0.0
				state = "wait"
				event.emit("returned")


## Stopped outside the bolt zone, or lifted empty: it slips off and falls; Pavel lifts it again.
func _fall() -> void:
	misses += 1
	_t = 0.0
	_fall_from = pos
	state = "falling"
	event.emit("missed")
