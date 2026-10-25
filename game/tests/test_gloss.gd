extends SceneTree
## H59, task T7 (Director 24.10): hints to old words.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_gloss.gd
##   - data: every `[[слово|значение]]` of the story is in data/story/glossary.json with the same meaning, there are no
##     stray `[[` / `]]`, every glossary word is used somewhere;
##   - Gloss: the plain text keeps the word only; the BBCode colours the word and underlines it (hint), the rest escaped;
##   - the dialogue (subtitles, looks, close-up messages — all through the text box): the word is shown as written,
##     gold, under it the hint with the meaning; a real mouse hover pops up the meaning in the game's style; a click on
##     the text still advances the dialogue;
##   - the journal shows marks the same way; buttons and plain labels never show the brackets.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null


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
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	await _test("T7: every marked word is in the glossary, no stray brackets", _test_data)
	await _test("T7: Gloss — plain text for voice, BBCode for the screen", _test_gloss_unit)
	await _test("T7: subtitles — gold dashed word, the meaning on hover, a click still advances", _test_dialogue)
	await _test("T7: journal and buttons — no brackets on screen", _test_journal_buttons)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== gloss (T7): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _drain() -> void:
	for i in 40:
		if sr.current_beat.is_empty() and not sr.is_busy():
			return
		sr.advance()
		await _frames(2)


## Game (1920x1080 canvas) → window coordinates, as test_closeups.gd: Input.parse_input_event takes what the OS sends.
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


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _strings(o: Variant, path: String, out: Array) -> void:
	if o is Dictionary:
		for k in o.keys():
			_strings(o[k], "%s.%s" % [path, k], out)
	elif o is Array:
		for i in o.size():
			_strings(o[i], "%s[%d]" % [path, i], out)
	elif o is String:
		out.append([path, o])


func _story_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json") and f != "glossary.json":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d not in ["ambient", "time"]:
			_story_files(dir.path_join(d), out)


# --- Tests -------------------------------------------------------------------------------

func _test_data() -> void:
	var doc: Dictionary = _json("res://data/story/glossary.json")
	_check(doc != null and doc.has("words"), "glossary.json loads")
	var gl := {}
	for w in doc.get("words", []):
		gl[String(w["word"]).to_lower()] = w
		_check(String(w.get("meaning", "")) != "" and String(w.get("lemma", "")) != "", "glossary %s: meaning and lemma" % w.get("word"))
		_check(String((w.get("source", {}) as Dictionary).get("url", "")).begins_with("http"), "glossary %s: source link" % w.get("word"))
	var files: Array = []
	_story_files("res://data/story", files)
	var used := {}
	var n_marks := 0
	for f in files:
		var strs: Array = []
		_strings(_json(f), f.get_file(), strs)
		for ps in strs:
			var s: String = ps[1]
			for m in Gloss.marks(s):
				n_marks += 1
				var g = gl.get(String(m["word"]).to_lower(), null)
				_check(g != null, "%s: «%s» not in glossary.json" % [ps[0], m["word"]])
				if g != null:
					used[String(m["word"]).to_lower()] = true
					_check(String(g["meaning"]) == String(m["meaning"]), "%s: meaning of «%s» differs from glossary" % [ps[0], m["word"]])
			var rest := RegEx.create_from_string(Gloss.PATTERN).sub(s, "", true)
			_check(not rest.contains("[[") and not rest.contains("]]"), "%s: stray [[ or ]]: %s" % [ps[0], s.left(60)])
	_check(n_marks >= 17, "marks in the story: %d (≥ 17 expected — one per glossary word at least)" % n_marks)
	for k in gl.keys():
		_check(used.has(k), "glossary word «%s» is not used in the story" % gl[k]["word"])


func _test_gloss_unit() -> void:
	var s := "Тихон дежурит [[подле|возле]] печи [b]."
	_check(Gloss.plain(s) == "Тихон дежурит подле печи [b].", "plain: word only — got «%s»" % Gloss.plain(s))
	_check(Gloss.marks(s).size() == 1 and Gloss.marks(s)[0]["meaning"] == "возле", "marks: one, meaning возле")
	var bb := Gloss.bbcode(s)
	_check(bb.contains("[hint=\"возле\"]подле[/hint]"), "bbcode: the word under a hint with the meaning — %s" % bb)
	_check(bb.contains("[color=#%s]" % Gloss.COLOR.to_html(false)), "bbcode: the word is gold")
	_check(bb.contains("[lb]b]"), "bbcode: other brackets escaped")
	_check(Gloss.plain("без пометок") == "без пометок" and Gloss.bbcode("без пометок") == "без пометок", "text without marks unchanged")


func _test_dialogue() -> void:
	await _drain()
	var raw: String = sd.text("@H1.tikhon.look")
	_check(Gloss.has_marks(raw), "H1.tikhon.look carries a mark (H59 text loaded)")
	sr.narrate_key("@H1.tikhon.look")
	await _frames(4)
	var tl: GlossText = ui.get("text_label")
	_check(tl is GlossText, "the dialogue text is a GlossText")
	_check(tl.story_text == raw, "the beat keeps the text as written (voice sha1 over it)")
	_check(tl.get_parsed_text() == Gloss.plain(raw), "on screen: the words only — «%s»" % tl.get_parsed_text())
	_check(tl.mouse_filter == Control.MOUSE_FILTER_PASS, "the text takes the hover and passes clicks on")
	var targets: Array = tl.gloss_targets()
	_check(targets.size() == 1, "one marked word found on screen (got %d)" % targets.size())
	if targets.is_empty():
		return
	var t: Dictionary = targets[0]
	_check(t["word"] == "подле" and t["meaning"] == "возле", "the word подле, meaning возле")
	_check(float(t["w"]) > 20.0 and float(t["w"]) < 200.0, "the word's box is word-sized: %s" % t)
	var local := Vector2(float(t["cx"]), float(t["cy"])) - tl.get_global_rect().position
	_check(tl.get_tooltip(local) == "возле", "the hint under the word reads «возле» (got «%s»)" % tl.get_tooltip(local))
	var tip: Control = tl._make_custom_tooltip("возле")
	var meaning := tip.find_child("Meaning", true, false) as Label
	var word := tip.find_child("Word", true, false) as Label
	_check(meaning != null and meaning.text == "возле", "the pop-up carries the meaning")
	# I-T2 (Director, line 22): the word is not repeated; the meaning in the word's gold, at the text's size
	_check(word == null, "the pop-up does not repeat the word")
	_check(meaning != null and meaning.get_theme_color("font_color") == Gloss.COLOR, "the meaning is in the gold of the marked word")
	_check(meaning != null and meaning.get_theme_font_size("font_size") == tl.get_theme_font_size("normal_font_size"),
		"the meaning is the size of the text it explains")
	tip.free()
	# A real hover: the mouse over the word → after the tooltip delay the pop-up is on screen.
	await _move(Vector2(float(t["cx"]), float(t["cy"])))
	await _move(Vector2(float(t["cx"]) + 1.0, float(t["cy"])))
	await _wait(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.5)
	await _frames(2)
	_check(tl.tooltip_open(), "hovering the word shows the meaning pop-up")
	_check(tl.last_tooltip_text == "возле", "the pop-up says «возле» (got «%s»)" % tl.last_tooltip_text)
	var probe: Dictionary = ui.call("probe_positions")
	_check(probe.has("gloss") and (probe["gloss"]["targets"] as Array).size() == 1, "the web probe sees the marked word")
	# A click on the text (not on the word) still advances the dialogue.
	var at := tl.get_global_rect().position + Vector2(6, tl.size.y * 0.5)
	await _move(at)
	await _button(at, true)
	await _button(at, false)
	await _frames(3)
	_check(sr.current_beat.is_empty(), "a click on the subtitle text advances (closes) the dialogue")
	await _drain()


func _test_journal_buttons() -> void:
	var jl: GlossText = ui.get("journal_facts_label")
	_check(jl is GlossText, "journal facts are a GlossText")
	jl.set_story_text("• Тихон [[подле|возле]] печи")
	_check(jl.get_parsed_text() == "• Тихон подле печи", "journal: words only on screen")
	_check(Gloss.plain("[[ворота|подъёмного механизма с валом]]") == "ворота", "buttons and plain labels get the word only")
