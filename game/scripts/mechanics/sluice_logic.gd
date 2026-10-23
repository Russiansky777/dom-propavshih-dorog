class_name SluiceLogic
extends RefCounted
## The mill sluice (M14), by the office journal: «спускать пруд по зарубке и ждать, иначе берега поплывут».
## G23 (Director 23.10): the winch is turned on the «точный удар» bar — each hit in the green opens one more notch
## and the water on the gauge falls one step towards that notch's level; a miss lets the winch slip back to the
## first notch and the water rises to where it started. This class is the water: where the gauge is going (`notch`)
## and how fast it falls or rises; TimingLogic counts the hits, the panel draws both. Pure logic.

var levels: Array = [1.0, 0.8, 0.6, 0.38, 0.15]   # gauge level settled at notch 0 (closed) … last (fully open)
var fall_per_s: float = 0.25                       # how fast the gauge falls towards the notch's level
var rise_per_s: float = 0.9                        # how fast it comes back up after the winch slipped
var settle_tol: float = 0.015

var notch: int = 0
var level: float = 1.0


func _init(cfg: Dictionary = {}, start_notch: int = 0) -> void:
	if cfg.has("levels"):
		levels = cfg["levels"]
	fall_per_s = float(cfg.get("fall_per_s", fall_per_s))
	rise_per_s = float(cfg.get("rise_per_s", rise_per_s))
	settle_tol = float(cfg.get("settle_tol", settle_tol))
	notch = clampi(start_notch, 0, last_notch())
	level = float(levels[notch])   # a reopened close-up (or a loaded save) finds the water settled


## The number of steps down (hits in a row on the bar): levels − 1.
func steps() -> int:
	return levels.size() - 1


func last_notch() -> int:
	return levels.size() - 1


func target() -> float:
	return float(levels[notch])


func settled() -> bool:
	return absf(level - target()) <= settle_tol


func finished() -> bool:
	return notch == last_notch() and settled()


## The winch is at notch `n` now (a hit: one more; a miss: back to 0). The water follows in step().
func set_notch(n: int) -> void:
	notch = clampi(n, 0, last_notch())


func step(dt: float) -> void:
	var t := target()
	level = move_toward(level, t, (fall_per_s if level > t else rise_per_s) * dt)
