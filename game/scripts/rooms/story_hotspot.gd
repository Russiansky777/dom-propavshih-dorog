class_name StoryHotspot
extends Hotspot
## Data-driven hotspot built by RoomBuilder from data/story/rooms/<id>.json.
## Everything it does is described by `data`; `trigger()` hands the click to StoryRunner.

var data: Dictionary = {}
var room_id: String = ""
var fill: Polygon2D = null
var caption: Label = null
var base_color: Color = Color(0.6, 0.6, 0.6)
var _flag_listener := false


func setup(p_room_id: String, p_data: Dictionary) -> void:
	room_id = p_room_id
	data = p_data
	hotspot_id = String(data.get("id", name))
	pick_priority = int(data.get("pick_priority", 0))
	base_color = Color.html(String(data.get("color", "#999999")))
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


func kind() -> String:
	return String(data.get("kind", "object"))


func label_text() -> String:
	return StoryData.text(String(current_state().get("label", data.get("label", hotspot_id))))


## Visible when every `visible_if` flag is set and no `hidden_if` flag is set.
func is_active() -> bool:
	for f in data.get("visible_if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in data.get("hidden_if", []):
		if GameState.has_flag(String(f)):
			return false
	return true


## The first `states` entry whose `if` flags all hold, else {}.
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


func refresh() -> void:
	var active := is_active()
	visible = active
	var shape := get_node_or_null("Shape")
	if shape is CollisionShape2D:
		shape.set_deferred("disabled", not active)
	var st := current_state()
	if fill != null:
		var c := base_color
		if st.has("color"):
			c = Color.html(String(st["color"]))
		if fill.color != c:
			fill.color = c  # assigning an equal colour still forces a polygon re-upload (WebGL noise)
	if caption != null:
		var t := label_text()
		if caption.text != t:
			caption.text = t


func trigger() -> void:
	StoryRunner.interact(self)
