extends Node
## Entry scene: wires RoomManager to the world container and the player, starts a new game at
## locations.json `start`, and (on web) publishes `window.probeState` for automated walkthroughs.

@onready var world: Node2D = $World
@onready var player: Player = $World/Player
@onready var game_ui: CanvasLayer = $GameUi
@onready var closeup: CanvasLayer = $Closeup

var _last_hint: String = ""
var _probe_dirty: bool = false


func _ready() -> void:
	RoomManager.setup(world, player)
	RoomManager.room_changed.connect(_mark_probe)
	GameState.flag_changed.connect(func(_f, _v): _mark_probe())
	GameState.state_loaded.connect(func(_s): _mark_probe())
	GameState.inventory_changed.connect(_mark_probe)
	GameState.hint_shown.connect(_on_hint_shown)
	StoryRunner.beat_changed.connect(_mark_probe)
	StoryRunner.puzzle_state_changed.connect(_mark_probe)
	StoryRunner.puzzle_opened.connect(_mark_probe)
	StoryRunner.puzzle_closed.connect(_mark_probe)
	StoryRunner.item_selection_changed.connect(func(_i): _mark_probe())
	player.walk_started.connect(func(_t): _mark_probe())
	player.arrived.connect(func(_p): _mark_probe())

	if not StoryData.loaded:
		push_error("Main: story data failed to load; see errors above")
	RoomManager.new_game()
	_publish_probe_state()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.probeReady = true;", true)
		# UI-only changes (journal/menu toggles, layout settling) have no signal: refresh periodically.
		var t := Timer.new()
		t.wait_time = 0.4
		t.autostart = true
		t.timeout.connect(_publish_probe_state)
		add_child(t)


func _on_hint_shown(text: String) -> void:
	_last_hint = text
	_mark_probe()


func _mark_probe(_a = null) -> void:
	if not OS.has_feature("web") or _probe_dirty:
		return
	_probe_dirty = true
	_publish_after_layout()


## Containers lay out their children one frame later; wait two frames before reading positions.
func _publish_after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_publish_probe_state()


## `window.probeState`: game state plus click targets (world coords == canvas coords at 1920x1080).
func _publish_probe_state() -> void:
	_probe_dirty = false
	if not OS.has_feature("web"):
		return
	var room := RoomManager.current_room
	var hotspots := {}
	var exits := {}
	if room != null:
		for h in room.get_hotspots():
			if h is StoryHotspot:
				var rect: Rect2 = _hotspot_rect(h)
				hotspots[h.hotspot_id] = {"x": rect.get_center().x, "y": rect.get_center().y, "visible": h.visible,
					"label": h.label_text()}
		for e in room.get_exits():
			if e is StoryExit:
				var rect: Rect2 = _hotspot_rect(e)
				exits[e.target_room] = {"x": rect.get_center().x, "y": rect.get_center().y, "open": e.is_open(),
					"exists": e.target_exists()}
	var state := {
		"room": GameState.current_room,
		"flags": GameState.flags,
		"inventory": GameState.inventory,
		"selected_item": StoryRunner.selected_item,
		"goal": StoryRunner.journal_goal(),
		"player": {"x": player.global_position.x, "y": player.global_position.y, "walking": player.is_walking()},
		"busy": StoryRunner.is_busy(),
		"beat": StoryRunner.current_beat.duplicate() if not StoryRunner.current_beat.is_empty() else {},
		"last_hint": _last_hint,
		"hotspots": hotspots,
		"exits": exits,
		"ui": game_ui.call("probe_positions") if game_ui.has_method("probe_positions") else {},
		"puzzle": closeup.call("probe_positions") if closeup.has_method("probe_positions") else {},
		"ticks": Time.get_ticks_msec(),
	}
	if state["beat"].has("callback"):
		state["beat"].erase("callback")
	JavaScriptBridge.eval("window.probeState = %s;" % JSON.stringify(state), true)


func _hotspot_rect(area: Area2D) -> Rect2:
	var shape := area.get_node_or_null("Shape")
	if shape is CollisionShape2D and shape.shape is RectangleShape2D:
		var size: Vector2 = shape.shape.size
		return Rect2(area.global_position - size / 2, size)
	return Rect2(area.global_position, Vector2.ZERO)
