class_name FastClock
extends RefCounted
## Time in mother's mirror (M15а). The world's rule: a place no road leads to lives exactly 20 times faster
## (Docs/SCENARIO_FINAL.md §4.3 — «Дать другое число или замедлить время ради сцены нельзя»); once the road
## is held from both ends (three lights, `road_held_both_ends`) the time is common — ratio 1.
## Agata's pocket watch counts her real seconds; Nina's clock counts `ratio` times as many.

var ratio: float = 20.0
var start_minutes: float = 18.0 * 60.0 + 40.0   # Nina's clock when the glass clears: 18:40
var real_s: float = 0.0                          # Agata's seconds at the mirror (her pocket watch)


func _init(p_ratio: float = 20.0, p_start_minutes: float = -1.0) -> void:
	ratio = p_ratio
	if p_start_minutes >= 0.0:
		start_minutes = p_start_minutes


func advance(dt: float) -> void:
	real_s += dt


## Minutes on Nina's clock since the glass cleared: exactly ratio × Agata's minutes.
func nina_elapsed_minutes() -> float:
	return real_s * ratio / 60.0


func nina_minutes() -> float:
	return start_minutes + nina_elapsed_minutes()


## Hands of the wall clock (ходики), degrees clockwise from twelve.
func minute_hand_deg() -> float:
	return fmod(nina_minutes(), 60.0) * 6.0


func hour_hand_deg() -> float:
	return fmod(nina_minutes() / 60.0, 12.0) * 30.0


## Agata's pocket watch: real seconds and minutes.
func watch_second_deg() -> float:
	return fmod(real_s, 60.0) * 6.0


func watch_minute_deg() -> float:
	return fmod(real_s / 60.0 + 23.0, 60.0) * 6.0


## The pose Nina is in now: `poses` [{id, minutes}] repeat in a cycle of Nina's minutes.
static func pose_at(poses: Array, nina_elapsed: float) -> Dictionary:
	var total := 0.0
	for p in poses:
		total += float(p.get("minutes", 1.0))
	if total <= 0.0 or poses.is_empty():
		return {}
	var t := fmod(nina_elapsed, total)
	for p in poses:
		t -= float(p.get("minutes", 1.0))
		if t < 0.0:
			return p
	return poses[poses.size() - 1]


## Candle left (1 → `min_left`) over `burn_minutes` of Nina's time, then a new one is lit.
static func candle_left(nina_elapsed: float, burn_minutes: float, min_left: float = 0.2) -> float:
	var f := fmod(nina_elapsed, burn_minutes) / burn_minutes
	return 1.0 - f * (1.0 - min_left)
