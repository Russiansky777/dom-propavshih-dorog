extends SceneTree
## Steam Deck / gamepad (Director 08.11, 19:34; 09.11, 01:19): the pad drives the mouse (PadInput autoload), so the
## whole game plays from a controller without touching the rooms, panels or mini-games. Events are fed as a pad
## would send them (InputEventJoypadMotion / InputEventJoypadButton through Input.parse_input_event).
##   GP-1 the left stick moves the cursor: a full tilt right for 0.5 s moves it right by hundreds of px, the viewport's
##        mouse position follows, the stick released — it stays; the speed setting scales it;
##   GP-2 A at a walkable floor point = a click: Agata walks there; the hints label is shown while the pad is active
##        and goes when the real mouse moves;
##   GP-3 B = Esc: the pause menu opens; B again closes it;
##   GP-4 X opens and closes the journal; Y reveals the spots (the Space action);
##   GP-5 LB / RB take the bag's items into the hand in turn, B puts the item back;
##   GP-6 the D-pad jumps the cursor to the nearest active spot in that direction.
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/test_gamepad.gd

var fails := 0
var passes := 0
var main_node: Node = null
var gs
var sr
var rm
var pad
var ui


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func _button(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var r := InputEventJoypadButton.new()
	r.button_index = b
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	pad = root.get_node_or_null("PadInput")
	_check(pad != null, "PadInput autoload missing")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.find_child("GameUi", true, false)
	var player = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _frames(2)

	# GP-1 the stick moves the cursor
	Input.warp_mouse(Vector2(600, 600))
	await _frames(2)
	var p0: Vector2 = pad.probe()["pos"]
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames(30)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(2)
	var p1: Vector2 = pad.probe()["pos"]
	print("    stick right 0.5 s: %.0f → %.0f px (speed %.2f)" % [p0.x, p1.x, pad.cursor_speed])
	_check(p1.x - p0.x > 250.0 and absf(p1.y - p0.y) < 2.0, "GP-1 the cursor did not move right with the stick (%s → %s)" % [p0, p1])
	_check(root.get_viewport().get_mouse_position().distance_to(p1) < 3.0, "GP-1 the viewport's mouse is not where the pad put it (%s vs %s)" % [root.get_viewport().get_mouse_position(), p1])
	await _frames(10)
	_check(pad.probe()["pos"] == p1, "GP-1 the cursor drifts with the stick released")
	_check(bool(pad.probe()["active"]) and ui.pad_hints.visible, "GP-2 the hints are not shown while the pad is active")
	# the speed setting
	pad.set_cursor_speed(2.0)
	_axis(JOY_AXIS_LEFT_X, -1.0)
	await _frames(15)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(2)
	var p2: Vector2 = pad.probe()["pos"]
	_check(p1.x - p2.x > 250.0, "GP-1 speed 2.0 over 0.25 s moved only %.0f px" % (p1.x - p2.x))
	pad.set_cursor_speed(1.0)

	# GP-2 A = a click on the floor: Agata walks
	var floor_pt := Vector2(1100, 900)
	pad.call("_move_cursor", floor_pt)
	await _frames(2)
	var before: Vector2 = player.global_position
	await _button(JOY_BUTTON_A)
	await _frames(20)
	_check(player.is_walking() or player.global_position.distance_to(before) > 10.0, "GP-2 A at the floor did not make Agata walk (%s → %s)" % [before, player.global_position])
	await _frames(120)
	# the real mouse moves → the hints go
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300, 300)
	mm.global_position = mm.position
	mm.relative = Vector2(40, 40)
	Input.parse_input_event(mm)
	await _frames(2)
	_check(not bool(pad.probe()["active"]) and not ui.pad_hints.visible, "GP-2 the hints stay after the real mouse moved")

	# GP-3 B = Esc: the pause menu
	var pm = main_node.find_child("PauseMenu", true, false)
	_check(pm != null, "GP-3 no PauseMenu")
	if pm != null:
		await _button(JOY_BUTTON_B)
		await _frames(3)
		_check(bool(pm.call("is_open")), "GP-3 B did not open the pause menu")
		await _button(JOY_BUTTON_B)
		await _frames(3)
		_check(not bool(pm.call("is_open")), "GP-3 B again did not close the pause menu")

	# GP-4 X = the journal, Y = reveal
	await _button(JOY_BUTTON_X)
	await _frames(2)
	_check(ui.journal_panel.visible, "GP-4 X did not open the journal")
	await _button(JOY_BUTTON_X)
	await _frames(2)
	_check(not ui.journal_panel.visible, "GP-4 X again did not close the journal")
	await _button(JOY_BUTTON_Y)
	await _frames(2)
	_check(ui.reveal.visible or ui.reveal.get_child_count() > 0, "GP-4 Y did not reveal the spots")
	await _frames(90)

	# GP-5 LB / RB cycle the bag, B puts the item back
	gs.add_item("letter_tamara") if not gs.has_item("letter_tamara") else null
	gs.add_item("key_house") if not gs.has_item("key_house") else null
	await _frames(2)
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	var first := String(sr.selected_item)
	_check(first != "", "GP-5 RB took nothing into the hand")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	var second := String(sr.selected_item)
	_check(second != "" and second != first, "GP-5 RB again did not move to the next item (%s → %s)" % [first, second])
	await _button(JOY_BUTTON_LEFT_SHOULDER)
	_check(String(sr.selected_item) == first, "GP-5 LB did not go back to %s (%s)" % [first, sr.selected_item])
	await _button(JOY_BUTTON_B)
	await _frames(2)
	_check(String(sr.selected_item) == "", "GP-5 B did not put the item back (%s)" % sr.selected_item)

	# GP-6 the D-pad jumps to a spot
	var targets: Array = ui.reveal_targets()
	_check(targets.size() >= 1, "GP-6 no targets in the room to jump to")
	if targets.size() >= 1:
		pad.call("_move_cursor", Vector2(2, 540))
		await _frames(2)
		await _button(JOY_BUTTON_DPAD_RIGHT)
		await _frames(2)
		var at: Vector2 = pad.probe()["pos"]
		var hit := false
		for t in targets:
			if (t["at"] as Vector2).distance_to(at) < 3.0:
				hit = true
		_check(hit, "GP-6 D-pad right did not land on a spot (%s)" % at)
	print("==== gamepad: %d tests, %d passed, %d failed ====" % [passes + fails, passes, fails])
	quit(1 if fails > 0 else 0)
