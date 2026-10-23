extends SceneTree
## World batch E (Director 23.10): F19 — the shift board at the mill (a sheet on the board, a close-up that rides
## in like the post-office plan, the words by the game); F18 — the open school door shows the winter classroom
## itself (a crop of the O1 painting in the opening, cold light on the threshold, snow drifting out, a breath of
## cold) instead of a flat blue rectangle.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_world.gd
## Everything by the mouse (Input.parse_input_event), as a player would. Exit code 0 only when all checks passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
var cp: Node = null
var cv: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	Input.use_accumulated_input = false
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	cp = main_node.get_node("Closeup")
	cv = main_node.get_node("CloseupView")
	await _test("F19 board: a sheet on the board in M1; a click rides the close-up in from the board, the game's words «Распорядок смен» and the bell signals; text over it; a click closes", _test_board)
	await _test("F18 door: the open door shows the winter classroom (O1 crop in the opening), cold light on the threshold, snow drifting out, breath of cold; nothing of it while the leaf is shut", _test_door)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== world: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout: float = 15.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await process_frame
	return false


func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(2)


func _button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, true)
	await _button(at, false)


func _v(d: Dictionary) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.get("hotspot_id") == id:
			return h
	return null


# --- F19 -------------------------------------------------------------------------------------

func _test_board() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "done_M04", "done_M05", "done_M06",
			"done_M07", "done_M08", "done_N01", "night_day1", "done_M09", "met_pavel"]:
		gs.set_flag(f, true)
	rm.change_room("M1", "default")
	await _frames(6)
	sr.call("_on_state_reset")
	var sheet: Node = rm.current_room.get_node_or_null("Layers/schedule_sheet")
	_check(sheet != null and sheet.visible, "M1: the sheet hangs on the board (layer schedule_sheet)")
	var h := _hotspot("schedule")
	_check(h != null, "M1: the board hotspot")
	if h == null:
		return
	var r: Array = h.data.get("rect", [0, 0, 0, 0])
	var at := Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0)
	Engine.time_scale = 2.0
	await _click(at)
	var ok: bool = await _wait_until(func(): return sr.view_open, 20.0)
	Engine.time_scale = 1.0
	_check(ok, "a click on the board opens its close-up")
	if not ok:
		return
	await _frames(1)
	var root_view: Control = cv.get("root")
	_check(cv.call("zooming") and root_view.scale.x < 0.9, "the close-up rides in from the board (scale %.2f)" % root_view.scale.x)
	await _wait(0.8)
	_check(not cv.call("zooming") and root_view.scale.is_equal_approx(Vector2.ONE) and root_view.position.is_equal_approx(Vector2.ZERO), "… and settles full screen")
	var pr: Dictionary = cv.call("probe")
	var words := ""
	for s in pr.get("sheets", []):
		words += String(s.get("text", "")) + "\n"
	for want in ["@M1.schedule.paper_title", "@M1.schedule.paper_signals"]:
		_check(words.find(sd.text(want)) >= 0, "the board's words by the game: «%s»" % sd.text(want).substr(0, 40))
	_check(words.find("Один удар — пускай") >= 0 and words.find("Долгий — подымай") >= 0, "the bell signals are on the sheet")
	_check(String(sr.current_beat.get("text", "")) == sd.text("@M1.schedule.use"), "its text plays over it (got «%s»)" % String(sr.current_beat.get("text", "")))
	_check(gs.has_flag("seen_shift_schedule"), "the board counts as seen (M09s)")
	var dc: Dictionary = ui.call("probe_positions").get("dialogue_click", {})
	await _click(_v(dc))
	await _frames(3)
	await _click(Vector2(1500, 500))
	await _frames(3)
	_check(not sr.view_open and not cv.visible, "a click closes the close-up")
	# Second look: the look text, the same close-up.
	await _click(at)
	ok = await _wait_until(func(): return sr.view_open, 20.0)
	_check(ok and String(sr.current_beat.get("text", "")) == sd.text("@M1.schedule.look"), "second look: the close-up again, the look text")
	sr.call("close_view")
	sr.call("_on_state_reset")
	await _frames(2)


# --- F18 -------------------------------------------------------------------------------------

func _test_door() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "seen_school_door", "seen_workshop",
			"seen_bell", "knows_rule_things_remember", "has_school_door", "has_bell", "has_mirror_home", "seen_mirror_home"]:
		gs.set_flag(f, true)
	sr.grant_item("door_hinges")
	rm.change_room("H3", "default")
	await _frames(6)
	await _wait(0.3)
	var h := _hotspot("school_door")
	sr.call("open_puzzle", h)
	var ok: bool = await _wait_until(func(): return sr.puzzle_open, 10.0)
	_check(ok, "the door close-up opens")
	if not ok:
		return
	await _frames(3)
	var wv: TextureRect = cp.get("winter_view")
	var wf: Node2D = cp.get("winter_front")
	_check(wv != null and wf != null, "the winter view and its front are built from data (art.winter_view)")
	if wv == null or wf == null:
		return
	_check(not wv.visible and not wf.visible, "while the leaf is shut — no classroom, no cold")
	var art: Dictionary = h.data["puzzle"]["art"]
	var op: Array = art["opening"]
	_check(wv.position.is_equal_approx(Vector2(float(op[0]), float(op[1]))) and wv.size.is_equal_approx(Vector2(float(op[2]), float(op[3]))), "the classroom fills the opening exactly")
	_check(wv.texture is AtlasTexture and String((wv.texture as AtlasTexture).atlas.resource_path).ends_with("rooms/O1/bg.png"), "it is the O1 painting")
	var reg: Rect2 = (wv.texture as AtlasTexture).region
	_check(absf(reg.size.x / reg.size.y - float(op[2]) / float(op[3])) < 0.02, "no stretching: crop aspect = opening aspect")
	# The right answer (state as StoryRunner leaves it after the check), as on success.
	sr.puzzle["solved"] = true
	sr.puzzle["view"] = "winter"
	sr.puzzle_state_changed.emit()
	await _frames(3)
	_check(wv.visible and wf.visible, "door open: the classroom and the cold in the opening")
	var lbl: Label = cp.get("winter_label")
	_check(lbl.text == "", "no caption over the real view (was «Зимний класс» on a flat colour)")
	var dv: ColorRect = cp.get("door_view")
	_check(wv.get_index() > dv.get_index(), "the view lies over the old flat colour")
	var snow_out: CPUParticles2D = wf.get_node_or_null("SnowOut")
	var breath: CPUParticles2D = wf.get_node_or_null("Breath")
	var light: Polygon2D = wf.get_node_or_null("Light")
	_check(snow_out != null and snow_out.emitting and snow_out.amount <= 80, "snow drifts out of the doorway (cheap: ≤ 80 flakes)")
	_check(breath != null and breath.emitting and breath.amount <= 10, "a faint breath of cold at the threshold")
	_check(light != null and light.polygon[0].y >= float(op[1]) + float(op[3]) - 10.0, "cold light spills from the doorway onto the threshold")
	_check(wf.get_index() > (cp.get("beam_node") as Node).get_index(), "the cold lies over the threshold beam")
	await _wait_until(func(): return not sr.puzzle_open, 12.0)
	sr.call("_on_state_reset")
	await _frames(2)
