extends SceneTree
## Director's playthrough 01.11, group Т — texts and voice (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md; «стр.» — a line
## of Docs/FEEDBACK_DIRECTOR_2026-11-01_raw.txt):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0111_T.gd
##   стр. 12: Pelageya's «Вот стопор — кол с замком» taken out — no beat, the recorded M02_7/M02_8 keep their ids;
##   стр. 24, 25, 26, 32, 33, 36, 40, 46, 50, 65, 66, 70: the words the Director caught (a repeat, a corner the chalk is not
##     in, a bridge Tikhon cannot know of, the label, «на мельнице», a table the glass does not show, «за двоих молчал», the
##     boat taken to the plate a second time, «Седой», a stick nobody holds, «по вашему слову», Ilya knowing the office) —
##     gone from the data, the new words in place;
##   стр. 62: a bridging line of Tikhon right after «Значит, вечер кончился», before either branch (Nina / Agata);
##   стр. 4, 11, 14, 18, 27, 30, 47, 64, 76: the voice request (voice_direction.json → voice_text) carries the asked
##     emphasis / pause / stress;
##   every line whose words changed waits for its new take (voice_pending.json) and is in the request voice_K24.json,
##     take 1 = voice_text.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null

## Lines whose words changed (manifest ids) — they wait for a new take.
const NEW_TEXT := ["agata:O1.enter.winter", "agata:O1.board.chalk", "O1.board.chalk_mama", "O1.board.chalk_ilya",
	"tikhon:H1.tikhon.spoons_quit", "H2.bell.look", "H2d.office_mirror.clamped",
	"tikhon:H1.tikhon.quiet_3", "M16_0_then0", "M18_7", "M23d_4_then0", "M23b_0", "M23b_2", "M25_3"]
## Lines re-directed only (emphasis / pause / stress): manifest id → what the request must carry.
## «Семнадцатый заход» (01.11 20:00): lines with «ни одна» were rephrased and re-recorded (K27) — what the words now carry.
const ACCENT := {
	"Z2.landmarks.look": "Тут и мельничная крыша, и спуск к воде",
	"M02_2": "Гребу-то я на тот берег",
	"pelageya:R1.pelageya.manager": "Сам ушёл домой, в Ольховку",
	"tikhon:H1.tikhon.spoons_done": "СМЕТАНКИ",
	"agata:examine.photo_bridge": "У берега — ",
	"M17_1": "бечева́",
	"H1d.nina_coat.look_done": "Рукав теперь зашит",
	"M26_37": "ОДНО НА ВСЕХ!",
	"H4.v02.done": "Под крышей светло",
}
const REQUESTS := ["voice_K24.json", "voice_K25.json", "voice_K27.json", "voice_K28.json", "voice_K29.json"]


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

	await _test("стр. 24–70: the caught words are gone, the new ones in place", _test_words)
	await _test("стр. 12: «Вот стопор — кол с замком» taken out — no beat, the next voices keep their ids", _test_stopper_cut)
	await _test("стр. 62: Tikhon's bridging line after «Значит, вечер кончился» — before either branch", _test_tikhon_bridge)
	await _test("стр. 4–76: the voice request carries the emphasis; changed lines chosen or waiting (K24/K25/K27)", _test_voice_request)

	var failed := _results.filter(func(r): return not r[1]).size()
	print("\n==== feedback 01.11 Т: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _txt(key: String) -> String:
	return String(sd.text("@" + key))


func _line_txt(key: String) -> String:
	return String(sd.text_line("@" + key).get("text", ""))


func _scene_line(scene_id: String, i: int) -> Dictionary:
	var lines: Array = sd.scene(scene_id).get("mandatory_lines", [])
	return lines[i] if i < lines.size() else {}


## A text without the words the Director caught — `banned` (lower case) is matched without case.
func _clean(t: String, banned: Array) -> bool:
	var low := t.to_lower()
	for b in banned:
		if low.contains(String(b).to_lower()):
			return false
	return true


func _test_words() -> void:
	# self-check: the matcher sees the old wording
	_check(not _clean("Теперь и мой след в углу доски", ["в углу"]) and _clean("Теперь и на доске мой след", ["в углу"]),
		"self-check: _clean finds «в углу» in the old line and not in the new one")
	# стр. 24: «Как же это?» — said at the door (M05_0), not again on entering the class
	_check(String(_scene_line("M05", 0).get("text", "")).contains("как же это"), "M05_0 still «Да как же это…»")
	_check(_clean(_txt("O1.enter.winter"), ["как же это"]), "стр. 24: the winter entry does not repeat «Как же это?» (%s)" % _txt("O1.enter.winter"))
	# стр. 25: the chalk is in the middle of the board (state_board_*), not in its corner
	for k in ["O1.board.chalk", "O1.board.chalk_mama", "O1.board.chalk_ilya"]:
		_check(_clean(_txt(k), ["в углу"]) and _txt(k).contains("на доске"), "стр. 25: %s — «на доске», not «в углу» (%s)" % [k, _txt(k)])
	# стр. 26: the spoons are open from the first evening (done_M03) — the bridge is decided only on day three (M23b)
	for k in ["H1.tikhon.spoons_quit"]:
		_check(_clean(_txt(k), ["мост"]) and _clean(_line_txt(k), ["мост"]), "стр. 26: Tikhon's spoons line knows no bridge (%s)" % _line_txt(k))
	# стр. 32: the bell — no label sentence on the look (the label is read on use)
	_check(_clean(_txt("H2.bell.look"), ["ярлык"]) and _txt("H2.bell.look").contains("языка к нему нет"), "стр. 32: H2.bell.look (%s)" % _txt("H2.bell.look"))
	_check(_txt("H2.bell.use").contains("ярлык"), "the label is still read on use (H2.bell.use)")
	# стр. 33: the Director chose the old take on «Семнадцатый заход» (W231) — the hint «на мельнице» stays, text and voice agree
	_check(_txt("H2d.bell.ring_far").contains("на мельнице") and _line_txt("H2d.bell.ring_far") == _txt("H2d.bell.ring_far"), "стр. 33: ring_far — the old line kept (%s)" % _line_txt("H2d.bell.ring_far"))
	# стр. 36: the glass shows the office door only
	var clamped := _txt("H2d.office_mirror.clamped")
	# «Семнадцатый заход» (W232): the glass clears (it does not darken) once the wedges are in
	_check(_clean(clamped, ["стол", "комнату со снимка", "Потемнев"]) and clamped.contains("дверь") and clamped.contains("прояснилось"), "стр. 36: the clamped glass shows the door (%s)" % clamped)
	# стр. 40
	_check(_clean(_txt("H1.tikhon.quiet_3"), ["за двоих"]) and _clean(_line_txt("H1.tikhon.quiet_3"), ["за двоих"]), "стр. 40: quiet_3 (%s)" % _line_txt("H1.tikhon.quiet_3"))
	# стр. 46: after the knot the boat went to her pier (boat_to_pier) — she takes it to the plate «опять»
	var m16: Dictionary = _scene_line("M16", 0).get("then", [{}])[0]
	_check(String(m16.get("text", "")).contains("опять"), "стр. 46: «Лодку опять к плите отведу» (%s)" % m16.get("text", ""))
	# стр. 44: the boat leaves for her pier at the end of M16s (heard at the turn right after the knot), not of M15.
	_check(String(sd.scene("M16s").get("stage", [{}])[0].get("sets", [""])[0]) == "boat_to_pier", "the boat goes to the pier after the knot (end of M16s) — why «опять»")
	# стр. 50, 65, 66, 70
	_check(_clean(String(_scene_line("M18", 7).get("text", "")), ["седой"]), "стр. 50: M18_7 without «Седой» (%s)" % _scene_line("M18", 7).get("text", ""))
	_check(_clean(String(_scene_line("M23b", 0).get("text", "")), ["палк"]), "стр. 65: M23b_0 — no stick (%s)" % _scene_line("M23b", 0).get("text", ""))
	_check(_clean(String(_scene_line("M23b", 2).get("text", "")), ["по вашему слову"]), "стр. 66: M23b_2 (%s)" % _scene_line("M23b", 2).get("text", ""))
	_check(_clean(String(_scene_line("M25", 3).get("text", "")), ["теперь тебя слышно"]), "стр. 70: M25_3 — Ilya says what he hears himself (%s)" % _scene_line("M25", 3).get("text", ""))


func _test_stopper_cut() -> void:
	var cut := _scene_line("M02", 6)
	_check(String(cut.get("text", "")) == "" and String(_scene_line("M02", 7).get("text", "")).begins_with("Тянешь"), "M02_6 empty, M02_7 «Тянешь…» keeps its index")
	gs.reset()
	for f in ["done_M01"]:
		gs.set_flag(f, true)
	rm.change_room("R1", "default")
	await _frames(3)
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	_check(sr.start_scene("M02"), "M02 starts")
	var ids: Array[String] = []
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 100:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("scene", "") == "M02" and b.has("line_id"):
			ids.append(String(b["line_id"]))
			_check(String(b.get("text", "")).strip_edges() != "", "no empty beat (%s)" % b.get("line_id"))
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [{}])[0].get("id", "")))
		else:
			sr.advance()
		await process_frame
	_check(not ids.has("M02_6") and ids.has("M02_5") and ids.has("M02_7") and ids.find("M02_7") == ids.find("M02_5") + 1,
		"M02: …M02_5, M02_7… — the taken-out line has no beat (%s)" % str(ids))


func _test_tikhon_bridge() -> void:
	var ln := _scene_line("M23d", 4)
	_check(String(ln.get("text", "")) == "Значит, вечер кончился.", "M23d_4 «Значит, вечер кончился.»")
	var th: Array = ln.get("then", [])
	_check(th.size() == 1 and String(th[0].get("speaker", "")) == "tikhon" and not th[0].has("if") and not th[0].has("unless"),
		"M23d_4_then0: one line of Tikhon's, in both branches (%s)" % str(th))
	for who in ["nina", "agata"]:
		gs.reset()
		for f in ["done_M23c"]:
			gs.set_flag(f, true)
		rm.change_room("H1", "default")
		await _frames(3)
		while not sr.current_beat.is_empty():
			sr.advance()
			await process_frame
		if not sr.start_scene("M23d"):
			_check(false, "M23d starts (%s)" % who)
			continue
		var seq: Array[String] = []
		var guard := 0
		while not sr.current_beat.is_empty() and guard < 100:
			guard += 1
			var b: Dictionary = sr.current_beat
			if b.get("type") == "options":
				var pick := ""
				for o in b.get("options", []):
					if String(o.get("id", "")).contains(who) or String(o.get("sets", "")).contains(who):
						pick = String(o["id"])
				if pick == "":
					pick = String(b.get("options", [{}])[0].get("id", ""))
				sr.choose(pick)
			else:
				if b.get("scene", "") == "M23d" and b.has("line_id"):
					seq.append(String(b["line_id"]))
				sr.advance()
			await process_frame
		var i4 := seq.find("M23d_4")
		_check(i4 >= 0 and seq.find("M23d_4_then0") == i4 + 1, "%s: the bridging line right after «вечер кончился» (%s)" % [who, str(seq)])
		var after := seq.slice(i4 + 2)
		_check(not after.is_empty() and (after[0] == "M23d_5" or after[0].begins_with("M23d_6_then")),
			"%s: then the branch line (%s)" % [who, str(seq)])


func _json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else null


func _test_voice_request() -> void:
	var vd: Dictionary = _json("res://data/story/voice_direction.json")
	var pend: Dictionary = (_json("res://data/story/voice_pending.json") as Dictionary).get("lines", {})
	var takes := {}   # line → every take text of K24 / K25 / K27
	for rf in REQUESTS:
		var req = _json(ProjectSettings.globalize_path("res://").path_join("../pipeline/requests/" + rf))
		_check(req is Dictionary, "pipeline/requests/%s readable" % rf)
		if req is Dictionary:
			for it in req.get("items", []):
				var lid := String(it["line"])
				if not takes.has(lid):
					takes[lid] = []
				(takes[lid] as Array).append(String(it["text"]))
	for id in ACCENT:
		var vt := String(vd.get(id, {}).get("voice_text", ""))
		_check(vt.contains(String(ACCENT[id])), "%s: voice_text carries «%s» (%s)" % [id, ACCENT[id], vt])
		_check((takes.get(id, []) as Array).has(vt), "%s: voice_text is one of its recorded takes (chosen or to choose)" % id)
	# стр. 27: «Под крышей светло» without emphasis; стр. 64: «рукав» not stressed
	_check(not String(vd.get("H4.v02.done", {}).get("voice_text", "")).contains("СВЕТЛО"), "стр. 27: no caps on «светло»")
	_check(not String(vd.get("H1d.nina_coat.look_done", {}).get("voice_text", "")).contains("РУКАВ"), "стр. 64: no caps on «рукав»")
	_check(String(vd.get("H2.bell.look", {}).get("voice_text", "")).contains("ПОДВЕСЕ"), "стр. 32: «На ПОДВЕСЕ»")
	for id in NEW_TEXT:
		var vt := String(vd.get(id, {}).get("voice_text", ""))
		_check((takes.get(id, []) as Array).has(vt), "%s: voice_text is one of its recorded takes (%s)" % [id, vt])
		_check(pend.has(id) or String(vd.get(id, {}).get("k17", "")) != "" or String(vd.get(id, {}).get("k18", "")) != "", "%s: chosen on «Семнадцатый» / «Восемнадцатый заход» or waits for its take" % id)
