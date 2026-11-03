extends SceneTree
## English (Director 02.11 23:39, 03.11 14:35): subtitles and voice in Russian or English, chosen in the settings.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_l10n.gd
##   - the English copy of the data (tools/build_story_en.py → res://data/story_en): the same keys, scenes and rooms,
##     the words in English; StoryData reads it when the subtitles are English; self-check — without the copy, Russian;
##   - a Russian recording plays under an English subtitle (the sha1 guard only within one language); self-check —
##     the guard across languages would silence it;
##   - «Без субтитров»: a line that is heard shows no words, an unvoiced one is still shown;
##   - the menu: Голос — Русский / English, Субтитры — Русские / English / Без субтитров; English asks first with the
##     warning and the tick; the cross keeps the language; the choice is kept in user://settings.cfg [language].
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var player: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	var only := OS.get_environment("ONLY")
	if only != "":
		var hit := false
		for w in only.split(","):
			hit = hit or test_name.contains(w)
		if not hit:
			return
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)




var TB = null
var LS = null


func _run() -> void:
	await process_frame
	TB = load("res://scripts/mechanics/timing_bar.gd")
	LS = load("res://scripts/core/language_settings.gd")
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	TB.settings_path = "user://test_l10n_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TB.settings_path))
	LS.load_settings(true)
	sd.call("reload")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("l10n-1 the English copy: same keys and scenes, English words; StoryData reads it with English subtitles", _test_copy)
	await _test("l10n-2 a Russian recording under an English subtitle plays; self-check — the cross-language guard would silence it", _test_voice_under_en)
	await _test("l10n-3 «Без субтитров»: a heard line shows no words, an unvoiced one does", _test_no_subs)
	await _test("l10n-4 the menu: the language rows; English asks with the warning and the tick, the cross keeps it; kept in settings", _test_menu)
	await _test("l10n-5 English voice: an English recording plays under the English subtitle; a changed text silences it (self-check)", _test_voice_en)
	LS.reset_memory()
	sd.call("reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TB.settings_path))
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== l10n: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room: String, spawn: String = "default") -> void:
	rm.change_room(room, spawn)
	await physics_frame
	await physics_frame
	await _frames(3)


func _set_flags(flags: Array) -> void:
	for f in flags:
		gs.set_flag(String(f), true)


func _fresh(flags: Array = []) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(flags)


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running") or sr.call("is_staging")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


## Clicks a hotspot as the mouse does (walk there, then use) — with `item` in hand when given.
func _use(id: String, item: String = "") -> bool:
	var h: Node2D = rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null
	if h == null or not h.visible:
		return false
	if item != "":
		sr.select_item(item)
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


## Reads out every queued beat (first option for choices); returns the texts seen.
func _finish() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 2000:
		guard += 1
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")) if not opts.is_empty() else "")
		else:
			seen.append(String(b.get("text", "")))
			sr.advance()
		await process_frame
	await process_frame
	return seen


func _text(key: String) -> String:
	return String(sd.text(key))


func _hotspot(room_id: String, id: String) -> Dictionary:
	for h in sd.rooms.get(room_id, {}).get("hotspots", []):
		if String(h.get("id", "")) == id:
			return h
	return {}


func _scene_line(id: String, i: int) -> Dictionary:
	return sd.scene(id).get("mandatory_lines", [])[i]


## Top edge (first opaque row) of a picture's column, -1 when the column is empty.
func _top_at(img: Image, x: int) -> int:
	for y in img.get_height():
		if img.get_pixel(x, y).a > 0.5:
			return y
	return -1



# --- Tests -------------------------------------------------------------------------------

func _set_subs(v: String) -> void:
	LS.set_subtitles(v)
	sd.call("reload")
	root.get_node("VoiceDirector").call("reload_config")


func _test_copy() -> void:
	_check(DirAccess.dir_exists_absolute("res://data/story_en"), "res://data/story_en exists")
	var ru_new := String(sd.text("@ui.title_new_game"))
	var ru_line := String(sd.scene("M05")["mandatory_lines"][0]["text"])
	var ru_rooms: Array = sd.rooms.keys()
	var ru_scenes: Array = sd.scene_order.duplicate()
	var ru_keys: Array = sd.texts.keys()
	_set_subs("en")
	_check(String(sd.get("lang")) == "en" and String(sd.get("DATA_DIR")).ends_with("story_en"), "English subtitles — the English data (%s)" % sd.get("DATA_DIR"))
	var en_new := String(sd.text("@ui.title_new_game"))
	var en_line := String(sd.scene("M05")["mandatory_lines"][0]["text"])
	_check(en_new != ru_new and en_new.to_lower().contains("new"), "the menu in English: «%s» (was «%s»)" % [en_new, ru_new])
	_check(en_line != ru_line and not _has_cyrillic(en_line), "a scene line in English: «%s»" % en_line)
	_check(sd.rooms.keys() == ru_rooms and sd.scene_order == ru_scenes, "the same rooms and scenes")
	var missing := ru_keys.filter(func(k): return not sd.texts.has(k))
	_check(missing.is_empty(), "every text key there: %d missing" % missing.size())
	var cyr := 0
	var sample := []
	for k in sd.texts.keys():
		var t := String(sd.texts[k].get("text", "")) if sd.texts[k] is Dictionary else String(sd.texts[k])
		if _has_cyrillic(t) and not String(k).begins_with("ui.lang_") and not t.contains("ЗМ") and not t.contains("ЗГ"):
			cyr += 1
			if sample.size() < 5:
				sample.append(k)
	_check(cyr <= 3, "English texts without Russian words: %d left %s" % [cyr, str(sample)])
	_set_subs("ru")
	_check(String(sd.text("@ui.title_new_game")) == ru_new, "back to Russian")


func _has_cyrillic(t: String) -> bool:
	for i in t.length():
		var c := t.unicode_at(i)
		if c >= 0x0410 and c <= 0x044F:
			return true
	return false


func _test_voice_under_en() -> void:
	var vd: Node = root.get_node("VoiceDirector")
	var lid := "M05_0"
	_set_subs("en")
	var en_text := String(sd.scene("M05")["mandatory_lines"][0]["text"])
	_check(String(vd.call("line_status", lid, en_text)) == "ok", "the Russian voice of M05_0 under the English subtitle: %s" % vd.call("line_status", lid, en_text))
	# self-check: the guard within one language (the voice taken as English) silences a recording of other words
	vd.set("voice_lang", "en")
	_check(String(vd.call("line_status", lid, en_text)) == "text_changed", "self-check: the guard within one language would silence the Russian recording under the English words")
	vd.set("voice_lang", "ru")
	_set_subs("ru")
	_check(String(vd.call("line_status", lid, String(sd.scene("M05")["mandatory_lines"][0]["text"]))) == "ok", "Russian under Russian: ok")


func _test_no_subs() -> void:
	_set_subs("none")
	var ui: Node = main_node.get_node("GameUi")
	var heard := {"type": "line", "speaker": "agata", "speaker_name": "Агата", "line_id": "M05_0", "text": String(sd.scene("M05")["mandatory_lines"][0]["text"])}
	sr.current_beat = heard
	ui.call("_render_dialogue")
	var tl: Control = ui.get("text_label")
	_check(not tl.visible, "a heard line: no words on screen")
	var unvoiced := {"type": "line", "speaker": "agata", "speaker_name": "Агата", "line_id": "NO_SUCH_99", "text": "Строка без записи."}
	sr.current_beat = unvoiced
	ui.call("_render_dialogue")
	_check(tl.visible, "an unvoiced line is still shown")
	sr.current_beat = {}
	ui.call("_render_dialogue")
	_set_subs("ru")


func _test_menu() -> void:
	var ui: Node = main_node.get_node("GameUi")
	ui.call("open_menu_panel", "settings")
	await _frames(3)
	var lb: Dictionary = ui.get("lang_buttons")
	for k in ["voice:ru", "voice:en", "subs:ru", "subs:en", "subs:none"]:
		_check(lb.has(k), "button %s" % k)
	_check(String((lb.get("subs:none") as Button).text).contains("No subtitles"), "«Без субтитров» with its English below: «%s»" % (lb.get("subs:none") as Button).text)
	_check((lb["voice:ru"] as Button).button_pressed and (lb["subs:ru"] as Button).button_pressed, "Russian chosen at first")
	(lb["subs:en"] as Button).emit_signal("pressed")
	await _frames(2)
	_check(bool(ui.call("lang_dialog_open")), "English asks first: the warning is up")
	var w: Label = (ui.get("lang_dialog") as Node).find_child("Warning", true, false)
	_check(w != null and w.text.contains("experimental") and w.text.contains("ошибки"), "the warning in both languages")
	ui.call("_close_lang_dialog", false)
	_check(LS.subtitles == "ru" and (lb["subs:ru"] as Button).button_pressed, "the cross keeps Russian")
	(lb["voice:en"] as Button).emit_signal("pressed")
	await _frames(2)
	_check(bool(ui.call("lang_dialog_open")), "the English voice asks too")
	ui.call("_close_lang_dialog", true)
	_check(LS.voice == "en" and LS.en_acknowledged, "the tick switches the voice to English")
	var cf := ConfigFile.new()
	cf.load(TB.settings_path)
	_check(String(cf.get_value("language", "voice", "")) == "en", "kept in user://settings.cfg [language]")
	(lb["voice:ru"] as Button).emit_signal("pressed")
	_check(LS.voice == "ru", "Russian again without a question")
	ui.call("close_menu_panel")


func _test_voice_en() -> void:
	var vd: Node = root.get_node("VoiceDirector")
	if not FileAccess.file_exists("res://assets/voice/en/manifest.json"):
		print("    (no English recordings yet — res://assets/voice/en; the voice stays Russian)")
		LS.set_voice("en")
		vd.call("reload_config")
		_check(String(vd.get("voice_lang")) == "ru", "English voice chosen without recordings — the Russian ones play")
		LS.set_voice("ru")
		vd.call("reload_config")
		return
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voice/en/manifest.json"))
	var lines: Dictionary = man.get("lines", {})
	_check(lines.has("M05_0"), "M05_0 is recorded in English (%d recordings)" % lines.size())
	LS.set_voice("en")
	_set_subs("en")
	_check(String(vd.get("voice_lang")) == "en", "the English recordings are read")
	var en_text := String(sd.scene("M05")["mandatory_lines"][0]["text"])
	if lines.has("M05_0"):
		_check(String(vd.call("line_status", "M05_0", en_text)) == "ok", "M05_0 in English plays: %s" % vd.call("line_status", "M05_0", en_text))
		_check(String(vd.call("line_status", "M05_0", en_text + " x")) == "text_changed", "self-check: other English words — the recording is silent")
	var ok := 0
	var bad := []
	for lid in lines.keys():
		var e: Dictionary = lines[lid]
		if e.has("stale") or not e.has("scene"):
			continue
		if e.has("option") or e.has("then"):
			continue
		var ml: Array = sd.scene(String(e["scene"])).get("mandatory_lines", [])
		if int(e["index"]) >= ml.size():
			bad.append(lid)
			continue
		var ln: Dictionary = ml[int(e["index"])]
		if String(vd.call("line_status", String(lid), String(ln.get("text", "")))) == "ok":
			ok += 1
		elif bad.size() < 5:
			bad.append(lid)
	_check(bad.is_empty(), "scene recordings in English play under the English words: %d ok, failing %s" % [ok, str(bad)])
	LS.set_voice("ru")
	_set_subs("ru")
	_check(String(vd.get("voice_lang")) == "ru", "back to the Russian voice")
