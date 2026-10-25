class_name StoryExit
extends RoomExit
## Data-driven exit: target and `requires` come from locations.json edges, placement from the room JSON.
## A closed exit never crashes: it reacts with `closed_text` (or the data-defined `on_closed` behaviour).

var data: Dictionary = {}
var room_id: String = ""
var requires_flags: Array = []
var fill: Polygon2D = null
var caption: Label = null
var base_color: Color = Color(1, 1, 1, 0.25)
## How the player sees this exit (ExitCue.classify): "door" — drawn in the art, no mark; else the
## direction of its mark (left/right/down/up). `cue` is the mark node (null for a door).
var cue_dir: String = "door"
var cue_source: String = ""
var cue: ExitCue = null


func setup(p_room_id: String, p_data: Dictionary, p_requires: Array) -> void:
	room_id = p_room_id
	data = p_data
	target_room = String(data.get("to", ""))
	target_spawn = String(data.get("spawn", "default"))
	requires_flags = p_requires
	pick_priority = int(data.get("pick_priority", 1))
	if data.has("color"):
		base_color = Color.html(String(data["color"]))
	if not GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.connect(_on_flag_changed)
	if not GameState.state_reset.is_connected(refresh):
		GameState.state_reset.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(refresh):
		GameState.state_reset.disconnect(refresh)


func _on_flag_changed(_flag: String, _value: bool) -> void:
	refresh()


## True when every edge requirement holds.
func is_open() -> bool:
	for f in requires_flags:
		if not GameState.has_flag(String(f)):
			return false
	return true


## True when the target room can actually be built in this milestone.
func target_exists() -> bool:
	return RoomManager.has_room(target_room)


func missing_flags() -> Array[String]:
	var out: Array[String] = []
	for f in requires_flags:
		if not GameState.has_flag(String(f)):
			out.append(String(f))
	return out


func current_state() -> Dictionary:
	for st in data.get("states", []):
		var ok := true
		for f in st.get("if", []):
			if not GameState.has_flag(String(f)):
				ok = false
				break
		for f in st.get("unless", []):
			if GameState.has_flag(String(f)):
				ok = false
				break
		if ok:
			return st
	return {}


func label_text() -> String:
	var st := current_state()
	return StoryData.text(String(st.get("label", data.get("label", target_room))))


## Shown at all (H36: «В лодку» at the turn only while the boat is there): the same `visible_if` / `hidden_if` /
## `hidden_when` [{all, not}] as a hotspot. A hidden exit is not drawn, its mark is gone and it takes no clicks.
func is_active() -> bool:
	for f in data.get("visible_if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("hidden_if", []):
		if GameState.has_flag(String(f)):
			return false
	for c in data.get("hidden_when", []):
		var all_set := true
		for f in c.get("all", []):
			if not GameState.has_flag(String(f)):
				all_set = false
		var none_set := true
		for f in c.get("not", []):
			if GameState.has_flag(String(f)):
				none_set = false
		if all_set and none_set:
			return false
	return true


func refresh() -> void:
	var active := is_active()
	if visible != active:
		visible = active
	var shape := get_node_or_null("Shape")
	if shape is CollisionShape2D and shape.disabled == active:
		shape.set_deferred("disabled", not active)
	var st := current_state()
	if fill != null:
		var c := base_color
		if st.has("color"):
			c = Color.html(String(st["color"]))
			c.a = 0.45
		elif not is_open():
			c.a = 0.12
		if fill.color != c:
			fill.color = c
	if caption != null:
		var t := label_text()
		if caption.text != t:
			caption.text = t
		var m := Color(1, 1, 1, 1.0 if is_open() else 0.6)
		if caption.modulate != m:
			caption.modulate = m


## Pointer on / off this exit (GameUi hover): its mark brightens.
func set_hot(on: bool) -> void:
	if cue != null and is_instance_valid(cue):
		cue.hot = on


## How the exit is shown: the mark's direction, or "door" for an exit drawn in the art. (The cursor
## over an exit is the ordinary pointer since 18.10 — the big exit arrows are gone; GameUi.)
func cursor_kind() -> String:
	return cue_dir


## Icon of the destination drawn left of the caption while hovering (Director 18.10: «значок …
## мельницы либо дороги … когда наводишь и название появляется»): the exit's own `icon`, else
## rooms/_index.json → exit_cue.icons[target room]; "" when neither names one (UiGlyphs exit_<name>.svg).
func icon_name() -> String:
	if data.has("icon"):
		return String(data["icon"])
	var cue_rules: Dictionary = StoryData.rooms_index.get("exit_cue", {})
	return String(cue_rules.get("icons", {}).get(target_room, ""))


func trigger() -> void:
	StoryRunner.use_exit(self)
