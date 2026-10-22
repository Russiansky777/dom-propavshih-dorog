class_name BellSignal
extends RefCounted
## Turns presses on the bell into the mill signals of the shift schedule (M1: «Один удар — пускай. Два —
## стой. Долгий — подымай.»): a short press is a strike; one strike and a pause is "one", two strikes close
## together are "two", a press held longer than `long_s` is "long". Pure logic on the caller's clock (the
## panel's accumulated time — Engine.time_scale speeds it up in tests), so the timing is testable exactly.

var long_s: float = 0.6      # held this long → "long" (fires while still held)
var gap_s: float = 0.55      # after a lone strike this long → "one"; a second strike inside it → "two"

var pressed: bool = false
var _press_t: float = 0.0
var _consumed: bool = false
var _strikes: int = 0
var _last_strike_t: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	long_s = float(cfg.get("long_s", long_s))
	gap_s = float(cfg.get("gap_s", gap_s))


func reset() -> void:
	pressed = false
	_consumed = false
	_strikes = 0


## Mouse down on the bell at time t. The bell sounds at once (the strike is the press).
func press(t: float) -> Array[String]:
	var out: Array[String] = []
	pressed = true
	_press_t = t
	_consumed = false
	return out


## Mouse up at time t: a short press counts as a strike; the second strike within gap_s is "two".
func release(t: float) -> Array[String]:
	var out: Array[String] = []
	if not pressed:
		return out
	pressed = false
	if _consumed:
		return out
	if t - _press_t >= long_s:
		_strikes = 0
		out.append("long")
		return out
	_strikes += 1
	_last_strike_t = t
	if _strikes >= 2:
		_strikes = 0
		out.append("two")
	return out


## Called every frame: a held press becomes "long" as soon as it is long enough; a lone strike becomes "one"
## after the pause.
func tick(t: float) -> Array[String]:
	var out: Array[String] = []
	if pressed and not _consumed and t - _press_t >= long_s:
		_consumed = true
		_strikes = 0
		out.append("long")
	elif not pressed and _strikes == 1 and t - _last_strike_t >= gap_s:
		_strikes = 0
		out.append("one")
	return out
