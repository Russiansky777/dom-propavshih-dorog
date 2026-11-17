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

## The same review, the second rule — «a villager who speaks is a villager in sight» (Q08: «Своих к чаю позвали — и
## Тамара с Ульяной пришли», then Tamara and Ulyana spoke over a room with only Agata and Mama in it). Every line whose
## speaker is not the narrator is judged once, a frame after it comes on screen: the speaker has a figure shown in the
## room — or in the frame (FrameView) when one is open. Not judged: a close-up, a mechanic or a bag item over the room
## (the room is not seen), a staging (its black). `speakers_unseen` — «scene/line: speaker» once each.
var speakers_unseen: Array[String] = []
var _lines_judged: Dictionary = {}


func _ready() -> void:
	rm = get_node("/root/RoomManager")
	sr = get_node("/root/StoryRunner")
	gs = get_node("/root/GameState")
	process_mode = Node.PROCESS_MODE_ALWAYS
	sr.beat_changed.connect(_on_beat)


func _on_beat() -> void:
	var b: Dictionary = sr.current_beat
	if String(b.get("type", "")) != "line":
		return
	var sp := String(b.get("speaker", ""))
	if sp == "" or sp == "narrator":
		return
	var key := "%s|%s|%s" % [String(sr.active_scene), String(b.get("line_id", "")), String(b.get("text", ""))]
	await get_tree().process_frame
	if _lines_judged.has(key) or sr.current_beat != b:
		return
	if bool(sr.get("view_open")) or bool(sr.get("mechanic_open")) or String(sr.get("examined_item")) != "" or sr.is_staging():
		return
	_lines_judged[key] = true
	var place: Node = _shown_place()
	if place == null:
		return
	var pl = rm.get("player") if place == rm.current_room else null
	if not shows_people(place, pl):
		return
	if not speaker_in_sight(place, sp, pl):
		speakers_unseen.append("%s/%s «%s»: %s is not in sight in %s" % [String(sr.active_scene), String(b.get("line_id", "")),
			String(b.get("text", "")).left(40), sp, String(place.get("room_id"))])


## The frame shown over the world, else the current room.
func _shown_place() -> Node:
	for fv in get_tree().get_nodes_in_group("frame_view"):
		var r = fv.get("room")
		if r != null and is_instance_valid(r):
			return r
	var cur = rm.current_room
	return cur if cur != null and is_instance_valid(cur) else null


## Where the rule judges: a place that shows its people as figures — a room with Agata in it, or with a villager's
## hotspot (a frame of live figures: the council at the mill). Not judged: the view from the boat (R2 — neither), a frame
## that is a picture (the mirror's empty room, the epilogue's dinner — its people painted and filmed, no hotspots).
static func shows_people(place: Node, the_player: Node) -> bool:
	if the_player != null and is_instance_valid(the_player) and (the_player as CanvasItem).is_visible_in_tree():
		return true
	for h in place.find_children("*", "", true, false):
		if h.has_method("kind") and String(h.call("kind")) == "npc":
			return true
	return false


## The rule itself (tests' self-check too): a figure of `id` shown in `place` — Agata the player of a room, anyone
## else (and Agata in a frame) a villager figure (npc_<id>, a puppet — Tikhon) visible and not faded out, or a painted
## figure: the hotspot `id` shown with its picture.
static func speaker_in_sight(place: Node, id: String, the_player: Node) -> bool:
	if id == "agata" and the_player != null and is_instance_valid(the_player):
		return (the_player as CanvasItem).is_visible_in_tree() and (the_player as CanvasItem).modulate.a > 0.5
	for n in ["npc_" + id, "puppet_" + id]:
		var f := place.get_node_or_null(n) as CanvasItem
		if f != null and f.is_visible_in_tree() and f.modulate.a > 0.5:
			return true
	for h in place.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id and (h as CanvasItem).is_visible_in_tree():
			var img := h.get_node_or_null("Image") as CanvasItem
			if img != null and img.is_visible_in_tree():
				return true
	return false


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	var step := _t
	_t = 0.0
	# untyped first: a room freed by a test's teardown is a «previously freed instance», which a typed var refuses
	var cur = rm.current_room
	if cur == null or not is_instance_valid(cur):
		_hidden_t.clear()
		return
	var room: Node = cur
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
