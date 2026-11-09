extends Node
## Gamepad play (Steam Deck; Director 08.11 19:34 / 09.11 01:19 «делаем какую-то часть для Steam Deck»): the whole game
## is mouse-driven, so a pad drives the mouse — nothing in rooms, panels, close-ups or mini-games changes.
##   left stick   — the cursor (speed grows with the tilt; data `cursor_speed` ×, user://settings.cfg [gamepad]);
##   right stick  — the cursor, slow (fine aiming in the mini-games);
##   A            — left click (walk, act, pick, advance a line);
##   B            — a held item goes back into the bag, otherwise Esc (close / pause);
##   X            — the journal;
##   Y            — reveal the active spots (Space);
##   LB / RB      — the previous / next item of the bag into the hand;
##   D-pad        — jump the cursor to the nearest active spot or exit in that direction;
##   Start        — Esc (the pause menu);
## Mouse events are synthesised through Input.parse_input_event, so every existing handler sees ordinary clicks. The
## pad is "active" from its first event until the real mouse moves; while it is, GameUi shows the button hints.
## Tests: tests/test_gamepad.gd (x11 — the cursor warp needs a display).

const DEADZONE := 0.18
const BASE_SPEED := 1100.0          # px/s at full tilt, ×cursor_speed
const FINE_SPEED := 260.0           # the right stick
const CANVAS := Vector2(1920.0, 1080.0)

var active: bool = false            # the pad gave the last input
var cursor_speed: float = 1.0
var vibration: bool = true          # settings.cfg [gamepad] vibration
var _device: int = 0                # the pad of the last event
var _rumble: Dictionary = {}        # synth sound → [weak, strong, s] (data/story/rumble.json)
var rumbles: Array = []             # tests: the rumbles started (sound, weak, strong, s)
var _axes: Dictionary = {}          # axis → value, from InputEventJoypadMotion (a real pad or a test's events)
var _pos: Vector2 = CANVAS * 0.5
var _lmb_down: bool = false
var _snap_targets: Callable = Callable()   # GameUi.reveal_targets
var _hint_cb: Callable = Callable()        # GameUi.set_pad_hints(active: bool)

signal pad_active_changed(on: bool)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rumble.json")) if FileAccess.file_exists("res://data/story/rumble.json") else null
	if d is Dictionary:
		_rumble = d.get("sounds", {})
	Input.joy_connection_changed.connect(func(_d: int, c: bool): if c: _set_active(true))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if FileAccess.file_exists("user://settings.cfg") and cf.load("user://settings.cfg") == OK:
		cursor_speed = clampf(float(cf.get_value("gamepad", "cursor_speed", 1.0)), 0.4, 2.5)
		vibration = bool(cf.get_value("gamepad", "vibration", true))


func set_cursor_speed(v: float) -> void:
	cursor_speed = clampf(v, 0.4, 2.5)
	var cf := ConfigFile.new()
	if FileAccess.file_exists("user://settings.cfg"):
		cf.load("user://settings.cfg")
	cf.set_value("gamepad", "cursor_speed", cursor_speed)
	cf.save("user://settings.cfg")


func set_vibration(on: bool) -> void:
	vibration = on
	var cf := ConfigFile.new()
	if FileAccess.file_exists("user://settings.cfg"):
		cf.load("user://settings.cfg")
	cf.set_value("gamepad", "vibration", vibration)
	cf.save("user://settings.cfg")


## A synthesised sound just played (MechanicView.play, SfxDirector.play_synth): its jolt on the pad, if it has one in
## data/story/rumble.json, the pad gives the input and «Вибрация» is on.
func rumble_for(sound_name: String) -> void:
	if not active or not vibration or not _rumble.has(sound_name):
		return
	var r: Array = _rumble[sound_name]
	rumbles.append([sound_name, float(r[0]), float(r[1]), float(r[2])])
	Input.start_joy_vibration(_device, float(r[0]), float(r[1]), float(r[2]))


## GameUi registers itself: where the spots are (D-pad jumps) and where to show the hints.
func bind_ui(targets: Callable, hints: Callable) -> void:
	_snap_targets = targets
	_hint_cb = hints


func _set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	if on:
		_pos = get_viewport().get_mouse_position() if get_viewport() != null else CANVAS * 0.5
	if _hint_cb.is_valid():
		_hint_cb.call(on)
	pad_active_changed.emit(on)


func _axis(a: int) -> float:
	return float(_axes.get(a, 0.0))


func _process(delta: float) -> void:
	if _axes.is_empty():
		return
	var l := Vector2(_axis(JOY_AXIS_LEFT_X), _axis(JOY_AXIS_LEFT_Y))
	var r := Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y))
	var v := Vector2.ZERO
	if l.length() > DEADZONE:
		var t := (l.length() - DEADZONE) / (1.0 - DEADZONE)
		v += l.normalized() * BASE_SPEED * cursor_speed * pow(t, 1.6)   # a soft start, fast across the screen
	if r.length() > DEADZONE:
		v += r.normalized() * FINE_SPEED * ((r.length() - DEADZONE) / (1.0 - DEADZONE))
	if v == Vector2.ZERO:
		return
	_set_active(true)
	_move_cursor(_pos + v * delta)


func _move_cursor(p: Vector2) -> void:
	_pos = Vector2(clampf(p.x, 0.0, CANVAS.x - 1.0), clampf(p.y, 0.0, CANVAS.y - 1.0))
	Input.warp_mouse(_pos)
	var m := InputEventMouseMotion.new()
	m.position = _pos
	m.global_position = _pos
	m.relative = Vector2.ZERO
	Input.parse_input_event(m)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and active and not (event as InputEventMouseMotion).relative.is_zero_approx():
		# the real mouse moved (our synthesised motions carry relative = 0)
		if (event as InputEventMouseMotion).position.distance_to(_pos) > 2.0:
			_set_active(false)
		return
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		_device = event.device
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		_axes[jm.axis] = jm.axis_value
		if absf(jm.axis_value) > DEADZONE:
			_set_active(true)
		return
	if not (event is InputEventJoypadButton):
		return
	var e := event as InputEventJoypadButton
	_set_active(true)
	match e.button_index:
		JOY_BUTTON_A:
			_mouse_button(MOUSE_BUTTON_LEFT, e.pressed)
		JOY_BUTTON_B:
			if e.pressed:
				if StoryRunner.selected_item != "":
					_mouse_button(MOUSE_BUTTON_RIGHT, true)
					_mouse_button(MOUSE_BUTTON_RIGHT, false)
				else:
					_key(KEY_ESCAPE, true)
					_key(KEY_ESCAPE, false)
		JOY_BUTTON_START:
			if e.pressed:
				_key(KEY_ESCAPE, true)
				_key(KEY_ESCAPE, false)
		JOY_BUTTON_X:
			if e.pressed:
				var ui := get_tree().get_first_node_in_group("game_ui")
				if ui != null and ui.has_method("toggle_journal"):
					ui.call("toggle_journal")
		JOY_BUTTON_Y:
			if e.pressed:
				_key(KEY_SPACE, true)
				_key(KEY_SPACE, false)
		JOY_BUTTON_LEFT_SHOULDER:
			if e.pressed:
				_cycle_item(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			if e.pressed:
				_cycle_item(1)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			if e.pressed:
				var dir := {JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
					JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN}[e.button_index] as Vector2
				_snap(dir)
	get_viewport().set_input_as_handled()


func _mouse_button(idx: int, pressed: bool) -> void:
	if idx == MOUSE_BUTTON_LEFT:
		if pressed == _lmb_down:
			return
		_lmb_down = pressed
	var b := InputEventMouseButton.new()
	b.button_index = idx
	b.pressed = pressed
	b.position = _pos
	b.global_position = _pos
	Input.parse_input_event(b)


func _key(code: Key, pressed: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	Input.parse_input_event(k)


## LB / RB: the bag's items in order; the next one goes into the hand (the same as a click on its pocket).
func _cycle_item(step: int) -> void:
	var items: Array = GameState.inventory.duplicate()
	if items.is_empty():
		return
	var cur := String(StoryRunner.selected_item)
	var i := items.find(cur)
	i = wrapi(i + step, 0, items.size()) if i >= 0 else (0 if step > 0 else items.size() - 1)
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.get("bag") != null:
		ui.get("bag").call("click_item", String(items[i]))
	else:
		StoryRunner.select_item(String(items[i]))


## D-pad: the nearest spot or exit in that direction (GameUi.reveal_targets — the same list Space reveals).
func _snap(dir: Vector2) -> void:
	if not _snap_targets.is_valid():
		return
	var best: Vector2 = Vector2.INF
	var best_d := INF
	for t in _snap_targets.call():
		var at: Vector2 = t.get("at", Vector2.INF)
		if at == Vector2.INF:
			continue
		var d: Vector2 = at - _pos
		if d.length() < 6.0:
			continue
		var along := d.dot(dir)
		if along <= 0.0:
			continue
		var across := absf(d.dot(Vector2(-dir.y, dir.x)))
		if across > along * 1.2:   # within a ~100° cone
			continue
		var score := along + across * 0.5
		if score < best_d:
			best_d = score
			best = at
	if best != Vector2.INF:
		_move_cursor(best)


## Tests and the web probe.
func probe() -> Dictionary:
	return {"active": active, "pos": _pos, "speed": cursor_speed, "joypads": Input.get_connected_joypads().size(), "axes": _axes.duplicate()}
