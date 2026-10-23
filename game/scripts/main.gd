extends Node
## Entry scene: wires RoomManager to the world container and the player, shows the title screen (or, for a start
## point, a test run or an automated browser, starts the game at once), and (on web) publishes `window.probeState`
## for automated walkthroughs.

@onready var world: Node2D = $World
@onready var player: Player = $World/Player
@onready var game_ui: CanvasLayer = $GameUi
@onready var closeup: CanvasLayer = $Closeup
@onready var closeup_view: CanvasLayer = get_node_or_null("CloseupView")
@onready var mechanic_view: CanvasLayer = get_node_or_null("MechanicView")
@onready var item_examine: CanvasLayer = get_node_or_null("ItemExamine")
@onready var frame_view: CanvasLayer = get_node_or_null("FrameView")
@onready var title: TitleScreen = get_node_or_null("Title")
@onready var pause_menu: PauseMenu = get_node_or_null("Pause")

## The title screen on launch: "" — decided by _title_wanted(), "show" / "skip" — set by a test before _ready.
var title_mode: String = ""

var _last_hint: String = ""
var _probe_dirty: bool = false
var _js_pause_cb: JavaScriptObject = null
var _js_isolate_cb: JavaScriptObject = null
var _clear_color_saved: Color = Color.BLACK
var _js_title_cb: JavaScriptObject = null
var _probe_paused: bool = false


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
	StoryRunner.examine_opened.connect(func(_i): _mark_probe())
	StoryRunner.examine_closed.connect(_mark_probe)
	StoryRunner.frame_changed.connect(func(_f, _h): _mark_probe())
	StoryRunner.item_selection_changed.connect(func(_i): _mark_probe())
	player.walk_started.connect(func(_t): _mark_probe())
	player.arrived.connect(func(_p): _mark_probe())

	if title != null and pause_menu != null:
		title.game_ui = game_ui
		pause_menu.game_ui = game_ui
		pause_menu.title = title
		game_ui.pause_requested.connect(pause_menu.open)
		title.visibility_changed.connect(_sync_pause)
		pause_menu.visibility_changed.connect(_sync_pause)
		title.visibility_changed.connect(_mark_probe)
		pause_menu.visibility_changed.connect(_mark_probe)

	if not StoryData.loaded:
		push_error("Main: story data failed to load; see errors above")
	# A start point for checking a later block (data/story/start_points.json): web `?start=<id>`, desktop
	# `-- --start=<id>`. Without one — the title screen (the player starts or continues from it); a test run or an
	# automated browser without one — a new game from the post office, as before the title existed.
	var sp := _start_point_arg()
	if sp == "" and _title_wanted():
		title.open()
	elif sp == "" or not RoomManager.start_at(sp):
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
		# window.probeTitle(id): the same as clicking a title item («new_game», «continue», «load», «settings»).
		_js_title_cb = JavaScriptBridge.create_callback(_on_probe_title)
		win.probeTitle = _js_title_cb
		JavaScriptBridge.eval("window.probeReady = true;", true)
		# UI-only changes (journal/menu toggles, layout settling) have no signal: refresh periodically.
		# It runs while the title or the pause menu holds the tree (process_mode always), not under probePause.
		var t := Timer.new()
		t.wait_time = 0.4
		t.autostart = true
		t.process_mode = Node.PROCESS_MODE_ALWAYS
		t.timeout.connect(_on_probe_timer)
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
	_probe_paused = paused
	_sync_pause()
	_publish_probe_state()


func _on_probe_timer() -> void:
	if not _probe_paused:
		_publish_probe_state()


func _on_probe_title(args: Array) -> void:
	if title != null and args.size() > 0:
		title.activate(String(args[0]))


## The tree stands still while the title screen or the pause menu is up, or the probe holds it.
func _sync_pause() -> void:
	var menus := (title != null and title.is_open()) or (pause_menu != null and pause_menu.is_open())
	get_tree().paused = _probe_paused or menus


## The title screen on launch — not for a test run (a `-s` script: the tree has a script), `-- --no-title`, an
## automated browser (navigator.webdriver: Playwright runners, the AI playtest) or a probe/start URL flag;
## `?title=1` / `-- --title` show it anyway (the menu's own web check).
func _title_wanted() -> bool:
	if title == null:
		return false
	if title_mode != "":
		return title_mode == "show"
	for a in OS.get_cmdline_user_args():
		if String(a) == "--title":
			return true
		if String(a) == "--no-title":
			return false
	if get_tree().get_script() != null:
		return false
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("""(function () {
			var q = new URLSearchParams(window.location.search);
			if (q.get('title') === '1') return 'show';
			if (q.get('title') === '0') return 'skip';
			var flags = ['start', 'agata', 'test', 'notitle'];
			for (var i = 0; i < flags.length; i++) if (q.has(flags[i])) return 'skip';
			for (const k of q.keys()) if (k.indexOf('probe') >= 0) return 'skip';   // ?probe, ?ambientprobe …
			return navigator.webdriver ? 'skip' : 'show';
		})()""", true)
		return String(v) == "show"
	return true


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


## Room layers (state layers, occluders) by id → shown now: what the art shows in this state.
func _layer_states(room: Node) -> Dictionary:
	var out := {}
	if room == null:
		return out
	for box in ["Layers", "Occluders"]:
		var c := room.get_node_or_null(box)
		if c == null:
			continue
		for l in c.get_children():
			if l is CanvasItem:
				out[String(l.name)] = (l as CanvasItem).is_visible_in_tree()
	return out


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
				var cue: ExitCue = e.cue
				if cue != null and is_instance_valid(cue):   # the visible mark (F20: where it stands, where it points)
					exits[e.target_room]["mark"] = {"x": cue.global_position.x, "y": cue.global_position.y,
						"angle": cue.angle_deg if not is_nan(cue.angle_deg) else ExitCue.dir_angle(cue.direction)}
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
		"examine": item_examine.call("probe") if item_examine != null else {},
		"frame": frame_view.call("probe") if frame_view != null else {},
		"layers": _layer_states(room),   # room art layers by id → shown (drawn states by flags, web checks)
		"time": TimeOfDay.probe(GameState.current_room),   # time of day (F17): state, phase, day, journal line
		"title": title.probe() if title != null else {},          # title screen: open, items → click targets
		"pause": pause_menu.probe() if pause_menu != null else {}, # pause menu: open, items, blur
		"paused": get_tree().paused,
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
		"lag": player.lock_lag_px(), "resyncs": player.lock_resyncs, "sprite_scale": spr.scale.x * float(player.sheet.texture_scale if player.sheet != null else 1.0),
		"action": player.current_action(), "action_fires": player.action_fire_count, "carry": player.carry_stage(),
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
