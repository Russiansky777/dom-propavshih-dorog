class_name SluiceLogic
extends RefCounted
## The mill sluice (M14), by the office journal: «открывать по зарубке и ждать, иначе берега поплывут».
## The gate opens one notch at a time; after each notch the water on the gauge falls towards that notch's
## level, and the next notch is refused (Pavel holds the winch) until the gauge shows the fall has settled.
## Skipping a notch is impossible: a drag past the next notch stops at it. Pure logic, the panel draws it.

var levels: Array = [1.0, 0.7, 0.42, 0.15]   # gauge level settled at notch 0 (closed) … last (fully open)
var fall_per_s: float = 0.07                 # how fast the gauge falls towards the notch's level
var settle_tol: float = 0.015

var notch: int = 0
var level: float = 1.0


func _init(cfg: Dictionary = {}, start_notch: int = 0) -> void:
	if cfg.has("levels"):
		levels = cfg["levels"]
	fall_per_s = float(cfg.get("fall_per_s", fall_per_s))
	settle_tol = float(cfg.get("settle_tol", settle_tol))
	notch = clampi(start_notch, 0, last_notch())
	level = float(levels[notch])   # a reopened close-up (or a loaded save) finds the water settled


func last_notch() -> int:
	return levels.size() - 1


func settled() -> bool:
	return absf(level - float(levels[notch])) <= settle_tol


func finished() -> bool:
	return notch == last_notch() and settled()


## "ok" — opened one more notch; "wait" — the water has not settled, Pavel holds the winch; "done" — fully open.
func open_next() -> String:
	if notch >= last_notch():
		return "done"
	if not settled():
		return "wait"
	notch += 1
	return "ok"


func step(dt: float) -> void:
	level = move_toward(level, float(levels[notch]), fall_per_s * dt)
