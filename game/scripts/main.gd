extends Node
## Entry scene: wires RoomManager to the world container and the player, starts a new game at
## locations.json `start`, and (on web) publishes `window.probeState` for automated walkthroughs.

@onready var world: Node2D = $World
@onready var player: Player = $World/Player
@onready var game_ui: CanvasLayer = $GameUi
@onready var closeup: CanvasLayer = $Closeup
@onready var closeup_view: CanvasLayer = get_node_or_null("CloseupView")
@onready var mechanic_view: CanvasLayer = get_node_or_null("MechanicView")
@onready var frame_view: CanvasLayer = get_node_or_null("FrameView")

var _last_hint: String = ""
var _probe_dirty: bool = false
var _js_pause_cb: JavaScriptObject = null
var _js_isolate_cb: JavaScriptObject = null
var _clear_color_saved: Color = Color.BLACK


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
	StoryRunner.view_opened.connect(_mark_probe)
	StoryRunner.view_closed.connect(_mark_probe)
	StoryRunner.mechanic_opened.connect(_mark_probe)
	StoryRunner.mechanic_closed.connect(_mark_probe)
	StoryRunner.frame_changed.connect(func(_f, _h): _mark_probe())
	StoryRunner.item_selection_changed.connect(func(_i): _mark_probe())
	player.walk_started.connect(func(_t): _mark_probe())
	player.arrived.connect(func(_p): _mark_probe())

	if not StoryData.loaded:
		push_error("Main: story data failed to load; see errors above")
	# A start point for checking a later block (data/story/start_points.json): web `?start=<id>`, desktop
	# `-- --start=<id>`. Without one — a new game from the post office, as always.
	var sp := _start_point_arg()
	if sp == "" or not RoomManager.start_at(sp):
		RoomManager.new_game()
	_publish_probe_state()
	if OS.has_feature("web"):
		# window.probePause(true/false): freezes the tree so a screenshot and the published state
		# describe the same instant (used by tools/screenshots.mjs for the stride frame series).
		_js_pause_cb = JavaScriptBridge.create_callback(_on_probe_pause)
		var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
		win.probePause = _js_pause_cb
		_js_isolate_cb = JavaScriptBridge.create_callback(_on_probe_isolate)
		win.probeIsolate = _js_isolate_cb
		JavaScriptBridge.eval("window.probeReady = true;", true)
		# UI-only changes (journal/menu toggles, layout settling) have no signal: refresh periodically.
		var t := Timer.new()
		t.wait_time = 0.4
		t.autostart = true
		t.timeout.connect(_publish_probe_state)
		add_child(t)


## window.probePause(paused, time_scale = 1): a long pause (screenshot) makes the next frame run the
## clamped maximum of physics steps (8 → 133 ms); a time_scale below 1 shortens that game-time step.
## window.probeIsolate(true/false): measurement view — the room (background, layers, occluders,
## effects) is hidden and the screen cleared to flat grey, so only the actors are drawn and every
## pixel that differs from grey belongs to a figure. Used by the stride stroboscope.
func _on_probe_isolate(args: Array) -> void:
	var on: bool = bool(args[0]) if args.size() > 0 else false
	var room := RoomManager.current_room
	if room != null:
		room.visible = not on
	if on:
		_clear_color_saved = RenderingServer.get_default_clear_color()
		RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5))
	else:
		RenderingServer.set_default_clear_color(_clear_color_saved)
	_publish_probe_state()


func _on_probe_pause(args: Array) -> void:
	var paused: bool = bool(args[0]) if args.size() > 0 else false
	if args.size() > 1 and args[1] != null:
		Engine.time_scale = clampf(float(args[1]), 0.05, 1.0)
	# Third argument: show actor shadows (the stride analysis hides them so the floor difference
	# against the reference frame is the figure alone).
	if args.size() > 2 and args[2] != null:
		var sh: Node = player.get_node_or_null("Sprite/Shadow")
		if sh is CanvasItem:
			sh.visible = bool(args[2])
	get_tree().paused = paused
	_publish_probe_state()


func _start_point_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--start="):
			return String(a).substr(8)
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('start') || ''", true)
		return String(v) if v != null else ""
	return ""


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
		"player": {"x": player.global_position.x, "y": player.global_position.y, "walking": player.is_walking(), "acting": player.is_acting()},
		"actor": _actor_state(),
		"npcs": _npc_states(room),
		"busy": StoryRunner.is_busy(),
		"beat": StoryRunner.current_beat.duplicate() if not StoryRunner.current_beat.is_empty() else {},
		"last_hint": _last_hint,
		"hotspots": hotspots,
		"exits": exits,
		"ui": game_ui.call("probe_positions") if game_ui.has_method("probe_positions") else {},
		"puzzle": closeup.call("probe_positions") if closeup.has_method("probe_positions") else {},
		"view": closeup_view.call("probe") if closeup_view != null else {},
		"mechanic": mechanic_view.call("probe") if mechanic_view != null else {},
		"frame": frame_view.call("probe") if frame_view != null else {},
		"ticks": Time.get_ticks_msec(),
		"physics_frames": Engine.get_physics_frames(),
	}
	if state["beat"].has("callback"):
		state["beat"].erase("callback")
	JavaScriptBridge.eval("window.probeState = %s;" % JSON.stringify(state), true)


## Sprite state for the stride measurement: what frame is drawn where, through which speed_scale.
func _actor_state() -> Dictionary:
	var spr: AnimatedSprite2D = player.get_node_or_null("Sprite")
	if spr == null:
		return {}
	var drawn: Vector2 = player.drawn_position()
	return {
		"anim": String(spr.animation), "frame": spr.frame, "progress": spr.frame_progress,
		"speed_scale": spr.speed_scale, "playing": spr.is_playing(),
		"drawn_x": drawn.x, "drawn_y": drawn.y, "scale": player.scale.y,
		"stride_px": player.stride_px(), "speed_px": player.current_speed_px(), "fps": player.current_walk_fps(),
		"direction": player.direction, "paused": get_tree().paused, "walk_time": player.walk_time,
		"lag": player.lock_lag_px(), "resyncs": player.lock_resyncs, "sprite_scale": spr.scale.x,
		"action": player.current_action(), "action_fires": player.action_fire_count,
		"shadow": _shadow_state(spr),
	}


func _shadow_state(spr: AnimatedSprite2D) -> Dictionary:
	var sh: Sprite2D = spr.get_node_or_null("Shadow")
	if sh == null:
		return {}
	var gs: Vector2 = sh.get_global_transform().get_scale()
	var tw: int = sh.texture.get_width() if sh.texture else 0
	return {"visible": sh.is_visible_in_tree(), "x": sh.global_position.x, "y": sh.global_position.y,
		"w": gs.x * tw, "h": gs.y * tw, "behind": sh.show_behind_parent, "tex": tw}


func _npc_states(room: Node) -> Dictionary:
	var out := {}
	for n in NpcActor.all_in(room):
		var spr: AnimatedSprite2D = n.get_node_or_null("Sprite")
		out[n.actor_id] = {"x": n.global_position.x, "y": n.global_position.y, "scale": n.scale.y, "visible": n.visible,
			"anim": String(spr.animation) if spr else "", "frame": spr.frame if spr else -1, "talking": n.talking}
	return out


func _hotspot_rect(area: Area2D) -> Rect2:
	var shape := area.get_node_or_null("Shape")
	if shape is CollisionShape2D and shape.shape is RectangleShape2D:
		var size: Vector2 = shape.shape.size
		return Rect2(area.global_position - size / 2, size)
	return Rect2(area.global_position, Vector2.ZERO)
