extends SceneTree
## Director's answers 17.11 about Mama's ribbon (O3, the horenka).
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_1711.gd [-- shot=<file.png>]
##   F17-1 «Давай добавим и крупный кадр да» + «давай уберем да, по логике»: the ribbon picked in the bag and a real
##       click on Mama (start point bedtime2 — the evening of day two, Mama in the room) → Agata goes to her, the
##       close-up opens (Nina's hands braiding the ribbon, closeup_ribbon_braid.png, titled «Мамина лента») with the
##       narrator's words over it, the flag of the trace is set and the ribbon is gone from the bag. «а разрешения
##       достаточно? игра же у нас в фулл хд»: the picture is shown at no more than its own size (1440×810 drawn
##       ≈1400 wide in the carved frame — not stretched). Self-checks — the same action without `consumes` leaves the
##       ribbon in the bag; a picture drawn wider than it is (the whole 1920 screen) is caught by the size rule.
##       With `shot=<png>` (a run with a display) the frame of the close-up is saved for the Director.

const IMG := "res://assets/closeups/closeup_ribbon_braid.png"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node
var sr: Node
var sd: Node
var rm: Node


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
	_results.append(passed)
	print(("PASS  " if passed else "FAIL  ") + test_name + "  (%d ms)" % (Time.get_ticks_msec() - started))
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	rm = root.get_node("RoomManager")
	await _test("F17-1 Mama's ribbon: a real click → the close-up of the braiding with the words over it, the trace set, the ribbon gone from the bag, the picture not stretched; self-checks — no `consumes` keeps it, a stretched picture is caught", _test_ribbon)
	var failed := _results.count(false)
	print("==== feedback 17.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _shot_path() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("shot="):
			return String(a).substr(5)
	return ""


## How much a picture is stretched on screen (> 1.0 — drawn bigger than its pixels, soft).
static func stretch(shown: Vector2, tex: Vector2) -> float:
	return maxf(shown.x / maxf(tex.x, 1.0), shown.y / maxf(tex.y, 1.0))


func _click(at: Vector2) -> void:
	var win := root.get_final_transform() * at
	var m := InputEventMouseMotion.new()
	m.position = win
	m.global_position = win
	Input.parse_input_event(m)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = win
		ev.global_position = win
		Input.parse_input_event(ev)
		await process_frame


func _nina() -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == "nina":
			return h
	return null


func _test_ribbon() -> void:
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var p: Dictionary = (sd.start_points.get("bedtime2", {}) as Dictionary).duplicate(true)
	_check(not p.is_empty(), "no start point bedtime2")
	rm.start_with(p)
	for i in 10:
		await process_frame
	for i in 300:
		if not sr.is_busy():
			break
		await process_frame
	if not gs.has_item("school_ribbon"):
		gs.set_flag("has_school_ribbon")
		gs.add_item("school_ribbon")
	_check(gs.has_item("school_ribbon"), "the ribbon is not in the bag at the start")
	var h: Node = _nina()
	_check(h != null, "no Mama (hotspot nina) in the horenka at bedtime2")
	if h == null:
		return
	# the real way: the ribbon picked in the bag, a click on Mama
	sr.select_item("school_ribbon")
	var hd: Dictionary = h.get("data")
	var r: Array = hd.get("rect", [1250, 160, 160, 630])
	await _click(Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0))
	for i in 900:
		if gs.has_flag("ribbon_braided"):
			break
		await process_frame
	for i in 6:
		await process_frame
	_check(gs.has_flag("ribbon_braided"), "the click with the ribbon on Mama did not braid it (no ribbon_braided)")
	_check(not gs.has_item("school_ribbon"), "the ribbon is still in the bag after Mama braided it")
	_check(sr.view_open and String(sr.view.get("id", "")) == "ribbon_braid", "the close-up did not open: %s" % str(sr.view))
	var pics: Array = sr.view.get("pictures", [])
	_check(pics.size() == 1 and String(pics[0].get("image", "")) == IMG, "the close-up shows %s" % str(pics))
	_check(String(sr.view.get("title", "")) == "@O3.nina.ribbon.title" and sd.text("@O3.nina.ribbon.title") == "Мамина лента",
		"the close-up's title is not «Мамина лента»: %s" % sd.text(String(sr.view.get("title", ""))))
	var said: String = String(sr.current_beat.get("text", ""))
	_check(said.contains("вплетает её в Агатину косу"), "the narrator's words are not over the close-up: «%s»" % said)
	# the picture on screen: not stretched (Director: «а разрешения достаточно? игра же у нас в фулл хд»)
	var cv: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("closeup_view.gd"):
			cv = n
	var shown := Vector2.ZERO
	var tex_size := Vector2.ZERO
	if cv != null:
		for tr in cv.find_children("Image", "TextureRect", true, false):
			var t := tr as TextureRect
			if t.texture != null and t.texture.resource_path == IMG and t.is_visible_in_tree():
				shown = t.size
				tex_size = t.texture.get_size()
	_check(tex_size == Vector2(1440, 810), "the close-up's picture is %s, not 1440×810" % str(tex_size))
	_check(shown != Vector2.ZERO and stretch(shown, tex_size) <= 1.0,
		"the picture is drawn at %s from %s — stretched ×%.2f" % [str(shown), str(tex_size), stretch(shown, tex_size)])
	print("        (close-up drawn %s from %s pixels, ×%.3f)" % [str(shown), str(tex_size), stretch(shown, tex_size)])
	var shot := _shot_path()
	if shot != "":
		for i in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("        (frame saved: %s)" % shot)
	# self-check 1: the same action without `consumes` leaves the ribbon — and the check above would see it
	sr.close_view()
	var act: Dictionary = (hd.get("item_use", {}) as Dictionary).get("school_ribbon", {}).duplicate(true)
	act.erase("consumes")
	act.erase("view")
	gs.set_flag("ribbon_braided", false)
	gs.add_item("school_ribbon")
	sr.call("_run_action", h, act, "school_ribbon")
	_check(gs.has_item("school_ribbon"), "self-check: without `consumes` the ribbon still left the bag")
	# self-check 2: the whole screen's width from a 1440 picture is stretched, and the rule says so
	_check(stretch(Vector2(1920, 1080), Vector2(1440, 810)) > 1.0, "self-check: a stretched picture passed")
	sr.close_view()
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
