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
		if ok:
			return st
	return {}


func label_text() -> String:
	var st := current_state()
	return StoryData.text(String(st.get("label", data.get("label", target_room))))


func refresh() -> void:
	var st := current_state()
	if fill != null:
		var c := base_color
		if st.has("color"):
			c = Color.html(String(st["color"]))
			c.a = 0.45
		elif not is_open():
			c.a = 0.12
		fill.color = c
	if caption != null:
		caption.text = label_text()
		caption.modulate = Color(1, 1, 1, 1.0 if is_open() else 0.6)


func trigger() -> void:
	StoryRunner.use_exit(self)
