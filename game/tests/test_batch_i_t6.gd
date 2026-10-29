extends SceneTree
## Batch I, task I-T6 — review-3 by ChatGPT, the Director's decisions (25.10, 19:01):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_i_t6.gd
##   1. every accepted line (Docs/review_chatgpt_2026-10-25_r3/review3_applied.json: «внесено» / «иначе») is in the game
##      data exactly, every rejected one kept its old text;
##   2. the Director's own words stay where review-3 argued with them (map 25.10, voice notes, D4): the hint after the
##      water, Tikhon after the mirror, the board, M01, M10, M17, M23c; and in the three lines taken «иначе»;
##   3. the changed lines are heard in play: M20 (Ulyana «раньше…»), M06 (the joy of the class), M17 (the boat goes on).
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null

const APPLIED := "Docs/review_chatgpt_2026-10-25_r3/review3_applied.json"
## Lines the Director rewrote later, in his playthrough of 29.10 (batch J, Docs/FEEDBACK_DIRECTOR_2026-10-29_map.md):
## review-3's text no longer applies to them — the J tests pin the new ones.
const J_SUPERSEDED := [8, 21, 22, 23, 24, 25, 26, 27, 28, 34, 35, 41, 42, 47, 48, 80, 81, 96]


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
	await _test("I-T6: 124 lines of review-3 — accepted ones in the data exactly, rejected ones unchanged", _test_applied)
	await _test("I-T6: the Director's own words stay where review-3 argued with them", _test_director_words)
	await _test("I-T6: changed lines heard in play — M20, M06, M17", _test_play)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch I (I-T6): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _flags_before(upto: String) -> void:
	sr._on_state_reset()
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == upto:
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for rid in sd.scene_trigger_rooms(id):
			var cw = sd.room(rid).get("scenes", {}).get(id, {}).get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []):
					gs.set_flag(String(f), true)


func _drain() -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 40000:
		if sr.mechanic_open:
			sr.close_mechanic()
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")) if not opts.is_empty() else "")
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


## The text behind an export id (tools/export_texts.py): text:<key>[#line], scene:<id>/lines[i]…, quest:<id>/lines[i].text.
func _text_of(id: String) -> String:
	if id.begins_with("text:"):
		var key := id.substr(5)
		var line := key.ends_with("#line")
		if line:
			key = key.trim_suffix("#line")
		var e: Dictionary = sd.texts.get(key, {})
		return String(e.get("line", {}).get("text", "")) if line else String(e.get("text", ""))
	var re := RegEx.new()
	re.compile("^(scene|quest):([^/]+)/lines\\[(\\d+)\\](.*)\\.text$")
	var m := re.search(id)
	if m == null:
		return "<bad id %s>" % id
	var lines: Array = sd.scene(m.get_string(2)).get("mandatory_lines", [])
	var obj: Dictionary = lines[int(m.get_string(3))]
	var rest := m.get_string(4)
	var re2 := RegEx.new()
	re2.compile("\\.(then|options)\\[([^\\]]+)\\]")
	for p in re2.search_all(rest):
		var arr: Array = obj.get(p.get_string(1), [])
		var k := p.get_string(2)
		if k.is_valid_int():
			obj = arr[int(k)]
		else:
			for o in arr:
				if String(o.get("id", "")) == k:
					obj = o
	return String(obj.get("text", ""))


func _test_applied() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(APPLIED)
	var f := FileAccess.open(path, FileAccess.READ)
	_check(f != null, "the applied list is at %s" % APPLIED)
	if f == null:
		return
	var list = JSON.parse_string(f.get_as_text())
	_check(list is Array and list.size() == 124, "124 lines of review-3: %s" % str(list.size() if list is Array else list))
	var counts := {}
	for e in list:
		var res := String(e["result"])
		counts[res] = int(counts.get(res, 0)) + 1
		var want := String(e["new"]) if e["new"] != null else String(e["old"])
		var have: String = _text_of(String(e["id"]))
		if J_SUPERSEDED.has(int(e["n"])):
			_check(not have.is_empty(), "%d %s: rewritten in batch J, still there" % [int(e["n"]), e["id"]])
			continue
		_check(have == want, "%d %s (%s): «%s» ≠ «%s»" % [int(e["n"]), e["id"], res, have, want])
	_check(counts == {"внесено": 110, "иначе": 5, "отклонено": 9}, "110 / 5 / 9: %s" % str(counts))


func _test_director_words() -> void:
	var water: String = sd.text("@H1.tikhon.water")
	_check(water.contains("Мамино зеркало") and water.contains("Струбцину"), "the hint after the water stays (Director, page 19:01): %s" % water)
	_check(sd.text("@H1.after_mirror.tikhon_2").contains("покуда день — делами займись") and sd.text("@H1.after_mirror.tikhon_2").contains("Печь я догляжу"),
		"Tikhon after the mirror: the Director's words of 29.10 (стр. 116: not «ляг поспи» in the daytime)")
	_check(sd.text("@O1.board.use").contains("Может, увидят послание-то моё"), "the board: map 59")
	_check(sd.text("@R1.pelageya.manager").contains("в тот вечер, перед паводком, год назад"), "Pelageya on the manager: map 23")
	_check(sd.text("@M1.pavel.before_agree").ends_with("Тогда и поговорим."), "Pavel before agreeing: map 79")
	var said := {
		"scene:M01/lines[9].text": "Лодочницу сама спрошу — что за чертовщина, что лодки назад приходят.",
		"scene:M09/lines[1].text": "как воду спустить-то?",
		"scene:M10/lines[1].text": "Да не бухти ты, для дела нужно.",
		"scene:M17/lines[0].text": "Проверю так — как на лодке полагается.",
		"scene:M23c/lines[8].text": "Задания к уроку. Да тебе — письма, из раза в раз.",
	}
	for id in said.keys():
		_check(_text_of(id).contains(said[id]), "%s: the Director's words «%s» — «%s»" % [id, said[id], _text_of(id)])


func _play(scene_id: String) -> Array:
	_flags_before(scene_id)
	var seen: Array = []
	var rooms: Array = sd.scene_trigger_rooms(scene_id)
	if not rooms.is_empty():
		rm.change_room(String(rooms[0]), "default")
		await physics_frame
		await _frames(3)
		seen += await _drain()
	if not sr.is_done(scene_id) and sr.current_beat.is_empty():
		_check(sr.start_scene(scene_id), "%s starts" % scene_id)
		await _frames(1)
	seen += await _drain()
	return seen


func _test_play() -> void:
	var seen := await _play("M20")
	_check(seen.any(func(x): return String(x) == "ulyana:Это тётя Агата? Папа, ты говорил, раньше она тебя старше была!"), "M20: Ulyana «раньше…»: %s" % str(seen))
	_check(seen.any(func(x): return String(x).begins_with("ilya:Да ты всё такая же…")), "M20: Ilya «Да ты всё такая же…»")
	seen = await _play("M06")
	_check(seen.any(func(x): return String(x) == "agata:Так здесь всё это время учились!"), "M06: the joy of the class: %s" % str(seen))
	seen = await _play("M17")
	_check(seen.any(func(x): return String(x) == "agata:Не сворачивает! По канату идёт!"), "M17: the boat goes on: %s" % str(seen))
	_check(seen.any(func(x): return String(x).begins_with("pelageya:Проверю так — как на лодке полагается")), "M17: the Director's words heard: %s" % str(seen))
