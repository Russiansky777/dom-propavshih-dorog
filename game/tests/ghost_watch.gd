extends Node
## Review 17.11 — «a clickable villager is a visible one». A staging's npc_go with a fade walks a villager off and leaves
## the figure at alpha 0 by the door; the room is not rebuilt until a load or re-entry. If the villager's hotspot stays
## shown (its flags still say «here»), the room has an invisible person: the caption «Нина» over an empty floor, her
## lines said from nowhere (found: the morning of day three, M21). Added by the bot walkthroughs (run_tests.gd,
## test_day2.gd, test_day3.gd): it watches the current room all the time and records every villager whose hotspot is
## shown while the figure has been out of sight (alpha ≈ 0, not walking, no staging running) for over a second.

var violations: Array[String] = []
var _hidden_t: Dictionary = {}   # node path → seconds out of sight while clickable
var _seen: Dictionary = {}
var _t := 0.0
var rm: Node
var sr: Node
var gs: Node


func _ready() -> void:
	rm = get_node("/root/RoomManager")
	sr = get_node("/root/StoryRunner")
	gs = get_node("/root/GameState")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	var step := _t
	_t = 0.0
	var room: Node = rm.current_room
	if room == null or not is_instance_valid(room):
		_hidden_t.clear()
		return
	if sr.is_staging():
		return
	for n in room.get_children():
		if not String(n.name).begins_with("npc_") or not (n is CanvasItem):
			continue
		var h = n.get("hotspot")
		if h == null or not is_instance_valid(h) or not (h as CanvasItem).is_visible_in_tree():
			_hidden_t.erase(n.get_path())
			continue
		var gone: bool = out_of_sight_but_clickable((n as CanvasItem).modulate.a, bool(n.get("walking")), true)
		if not gone:
			_hidden_t.erase(n.get_path())
			continue
		var t: float = float(_hidden_t.get(n.get_path(), 0.0)) + step
		_hidden_t[n.get_path()] = t
		if t > 1.0:
			var key := "%s/%s" % [String(room.get("room_id")), String(n.name)]
			if not _seen.has(key):
				_seen[key] = true
				violations.append("%s: %s is clickable (its hotspot is shown) but out of sight (alpha %.2f at %s); scene «%s», beat «%s»" % [
					String(room.get("room_id")), String(n.name).substr(4), (n as CanvasItem).modulate.a,
					str((n as Node2D).global_position), String(sr.active_scene), String(sr.current_beat.get("text", "")).left(50)])


## The rule itself, for the tests' self-check: the same judgement on a given figure.
static func out_of_sight_but_clickable(figure_alpha: float, walking: bool, hotspot_shown: bool) -> bool:
	return hotspot_shown and figure_alpha < 0.05 and not walking
