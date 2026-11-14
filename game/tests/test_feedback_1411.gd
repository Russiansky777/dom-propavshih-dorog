extends SceneTree
## Director 14.11 (after the build of 14.11 and the trailer's draft v3):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_1411.gd
##   21:14 «Мамино зеркало — надпись как-то странно стоит, может поднять её и в игре при этом и на видео»: the title
##         of mother's mirror lay on the top edge of its carved frame and began left of it. The frame is a little
##         smaller and lower, the title stands over the frame's left edge with air between them; the frame clear of
##         the game's top bar, of the line box below, its right edge where it was (the clamp and the clocks);
##         self-check — the layout until 14.11 (glass [150, 160, 1130, 747], title at (40, 96)) fails the same check.
## Exit code 0 only when every check passed.

const TOP_BAR_BOTTOM := 78.0     # the game's top bar (room name, bag, «Журнал», «Меню»)
const LINE_BOX_TOP := 950.0      # the dialogue box under a mechanic
const TITLE_AIR := 10.0          # between the title's line and the frame, px

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var sr: Node = null
var sd: Node = null


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
	await _test("14.11 mother's mirror: the title over the frame's left edge, clear of the frame; self-check — the old layout lies on it", _test_mirror_title)
	var failed := _results.count(false)
	print("==== feedback 14.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _mirror_spec() -> Dictionary:
	for h in sd.rooms.get("H2", {}).get("hotspots", []):
		if String((h as Dictionary).get("mechanic", {}).get("type", "")) == "fast_mirror":
			return (h["mechanic"] as Dictionary).duplicate(true)
	return {}


## Opens the mechanic as the game does and returns what is wrong with its title against its frame.
func _title_problems(spec: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var view := CanvasLayer.new()
	view.set_script(load("res://scripts/mechanics/mechanic_view.gd"))
	root.add_child(view)
	await _frames(2)
	sr.open_mechanic(spec, "bundle_nina")
	await _frames(4)
	var title: Label = view.get("title_label")
	var panel: Control = view.get("panel")
	var frame: Control = panel.get_node_or_null("Frame") if panel != null else null
	if title == null or frame == null:
		bad.append("no title or no frame (title %s, frame %s)" % [title, frame])
	else:
		var line_h := title.get_theme_font("font").get_height(title.get_theme_font_size("font_size"))
		var t := Rect2(title.global_position, Vector2(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x, line_h))
		var f := frame.get_global_rect()
		if t.end.y + TITLE_AIR > f.position.y:
			bad.append("the title's line ends at y %.0f, the frame begins at %.0f — less than %.0f px of air" % [t.end.y, f.position.y, TITLE_AIR])
		if t.position.x < f.position.x - 1.0:
			bad.append("the title begins at x %.0f, left of the frame (%.0f)" % [t.position.x, f.position.x])
		if t.position.y < TOP_BAR_BOTTOM + 8.0:
			bad.append("the title at y %.0f is under the top bar (to %.0f)" % [t.position.y, TOP_BAR_BOTTOM])
		if f.end.y > LINE_BOX_TOP - 8.0:
			bad.append("the frame ends at y %.0f, on the line box (%.0f)" % [f.end.y, LINE_BOX_TOP])
		if absf(f.end.x - 1314.0) > 1.0:
			bad.append("the frame's right edge at x %.0f (the clamp and the clocks stand by 1314)" % f.end.x)
	sr.close_mechanic()
	await _frames(2)
	view.queue_free()
	await _frames(2)
	return bad


func _test_mirror_title() -> void:
	gs.reset()
	for fl in ["nina_mirror_clamped", "h2_bundle_unwrapped", "done_M14", "house_unlocked"]:
		gs.set_flag(fl, true)
	var spec := _mirror_spec()
	_check(not spec.is_empty(), "the mirror's mechanic in H2")
	_check(String(sd.text(String(spec.get("title", "")))) == "Мамино зеркало", "the title's words: «%s»" % String(sd.text(String(spec.get("title", "")))))
	var now: Array[String] = await _title_problems(spec)
	_check(now.is_empty(), "the title and the frame: %s" % "; ".join(now))
	var old := spec.duplicate(true)
	old["glass"] = [150, 160, 1130, 747]
	old.erase("title_pos")
	var was: Array[String] = await _title_problems(old)
	_check(was.any(func(b): return String(b).contains("of air")) and was.any(func(b): return String(b).contains("left of the frame")),
			"self-check: the layout until 14.11 is caught on both counts (%s)" % "; ".join(was))
