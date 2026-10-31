class_name StoryHotspot
extends Hotspot
## Data-driven hotspot built by RoomBuilder from data/story/rooms/<id>.json.
## Everything it does is described by `data`; `trigger()` hands the click to StoryRunner.

## The hotspot moved (a `states` entry with its own rect/stand took over) — PuppetActor re-places itself.
signal geometry_changed()

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


## Visible when every `visible_if` flag is set and no `hidden_if` flag is set, and no `hidden_when`
## condition holds ({all: [flags], not: [flags]} — e.g. Pelageya is away from the pier in the evening until
## the rope is on the plate: hidden when evening_dusk is set and done_M15 is not).
func is_active() -> bool:
	return data_active(data)


static func data_active(data: Dictionary) -> bool:
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


## The first `states` entry whose `if` flags all hold and none of its `unless`, else {}.
func current_state() -> Dictionary:
	return state_of(data)


static func state_of(d: Dictionary) -> Dictionary:
	for st in d.get("states", []):
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


func refresh() -> void:
	var active := is_active()
	visible = active
	for c in get_children():  # "Shape" and the extra `pick_rects` shapes (PickShape0…)
		if c is CollisionShape2D:
			c.set_deferred("disabled", not active)
	var st := current_state()
	_apply_geometry(st)
	if fill != null:
		var c := base_color
		if st.has("color"):
			c = Color.html(String(st["color"]))
		if fill.color != c:
			fill.color = c  # assigning an equal colour still forces a polygon re-upload (WebGL noise)
	_update_beckon(active)
	if caption != null:
		var t := label_text()
		if caption.text != t:
			caption.text = t


## A state may move the hotspot: `rect` / `stand` in a `states` entry replace the base ones while the
## state holds (H1: Tikhon in the armchair until Q04, then on the shelf he chose; the installed shelf).
## Same geometry as RoomBuilder: position = rect centre, Shape = rect size, StandPoint relative to it.
func _apply_geometry(st: Dictionary) -> void:
	var r: Array = st.get("rect", data.get("rect", []))
	if r.size() != 4:
		return
	var size := Vector2(float(r[2]), float(r[3]))
	var centre := Vector2(float(r[0]), float(r[1])) + size / 2.0
	var sp: Array = st.get("stand", data.get("stand", [r[0], r[1]]))
	var stand_at := Vector2(float(sp[0]), float(sp[1])) - centre
	var shape := get_node_or_null("Shape")
	var stand := get_node_or_null("StandPoint")
	var rs: RectangleShape2D = shape.shape if shape is CollisionShape2D and shape.shape is RectangleShape2D else null
	if position.is_equal_approx(centre) and (rs == null or rs.size.is_equal_approx(size)) \
			and (not (stand is Node2D) or (stand as Node2D).position.is_equal_approx(stand_at)):
		return
	position = centre
	for c in get_children():  # extra `pick_rects` stay where the data put them on screen
		if c is CollisionShape2D and c.has_meta("abs_centre"):
			c.position = (c.get_meta("abs_centre") as Vector2) - centre
	if rs != null:
		rs.size = size
	if stand is Node2D:
		stand.position = stand_at
	if fill != null:
		fill.polygon = PackedVector2Array([-size / 2.0, Vector2(size.x, -size.y) / 2.0, size / 2.0, Vector2(-size.x, size.y) / 2.0])
	geometry_changed.emit()


## Rooms data `beckon` {if, unless}: a pulsing glow while the flags hold (HotspotBeckon).
func beckon_on() -> bool:
	var b: Dictionary = data.get("beckon", {})
	if b.is_empty():
		return false
	for f in b.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in b.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func _update_beckon(active: bool) -> void:
	var on := active and beckon_on()
	var bk := get_node_or_null("Beckon") as HotspotBeckon
	if on and bk == null:
		bk = HotspotBeckon.new()
		bk.name = "Beckon"
		var r: Array = current_state().get("rect", data.get("rect", [0, 0, 80, 80]))
		bk.radius = clampf(maxf(float(r[2]), float(r[3])) * 0.6, 30.0, 160.0)
		add_child(bk)
	elif not on and bk != null:
		bk.queue_free()
		remove_child(bk)


func trigger() -> void:
	StoryRunner.interact(self)
