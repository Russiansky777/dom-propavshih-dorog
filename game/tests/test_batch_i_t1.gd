extends SceneTree
## Batch I, task I-T1 — texts, the story spine, Tikhon, Q06 (Director's playthrough 25.10, Docs/FEEDBACK_DIRECTOR_2026-10-25_map.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_i_t1.gd
##   1. what Agata knows (D1, Docs/SCENARIO_FINAL.md §5a): in M01 she says herself that a year passed without letters and
##      that the aunt did not come back; no «early» words in her lines of days 1–2 (×20 before the mother's mirror, death
##      before M21, «Павел слышал» before Pavel says it); Fyodor Lukich named once;
##   2. Tikhon can always be talked to: before M03 he grumbles, until the shelf hangs he asks for it first, topics by day
##      (the hint about the mother's mirror only while the water goes down and the mirror is not done);
##   3. Q06 hook: without Nina's word no line in the journal; with it — a fact, the free-day goal names Ilya's workshop,
##      the workshop is lit on entering the street (until the task starts);
##   4. the house door: «Отпереть дверь», then Agata's word, then the old label; M10 — Agata answers Tikhon; M23d — friend.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var _beckoned: Array = []


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
	sr.hotspots_beckoned.connect(func(ids): _beckoned.append_array(ids))
	await _test("I-T1 D1: what Agata knows — M01 in her own words, no early words on days 1–2, Fyodor Lukich once", _test_spine)
	await _test("I-T1: Tikhon can always be talked to — before M03, the shelf asked first, topics by day", _test_tikhon)
	await _test("I-T1: Q06 hook — journal and goal only after Nina's word, the workshop lit on the street", _test_q06_hook)
	await _test("I-T1: house door label, Agata's word after unlocking; M10 answer; M23d friend; Ulyana's sister lines", _test_small)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch I (I-T1): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _flags_before(upto: String, extra: Array = []) -> void:
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
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	await _drain()   # first-entry thoughts (R1 at dusk: «Пелагеи на причале нет…»)
	return rm.current_room


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _exit(to: String) -> Node:
	return rm.current_room.get_node_or_null("Exits/to_" + to) if rm.current_room != null else null


func _layer(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("Layers/" + id) as Node2D if rm.current_room != null else null


func _layer_on(id: String) -> bool:
	var l := _layer(id)
	return l != null and l.visible


func _drain(pick_id: String = "") -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 40000:
		if sr.mechanic_open:
			# A scene's close-up (the crossing of M18p): its events done by hand, then put away — the scene goes on.
			seen.append("mechanic")
			for ev in sr.mechanic.get("events", {}).values():
				for f in ev.get("sets", []):
					gs.set_flag(String(f), true)
			sr.close_mechanic()
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if seen.is_empty() or seen.back() != "stage":
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			for o in opts:
				if String(o.get("id", "")) == pick_id:
					pick = pick_id
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", b.get("text", "")))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen



func _key_of(b: Dictionary) -> String:
	return String(b.get("text_key", ""))


## What a click on the hotspot says first (its text key, or the scene line text).
func _says(hs_id: String) -> String:
	var h := _hotspot(hs_id)
	if h == null:
		return "<no hotspot %s>" % hs_id
	sr.interact(h)
	await _frames(1)
	var k := _key_of(sr.current_beat)
	var all := [k]
	while not sr.current_beat.is_empty() and all.size() < 6:
		sr.advance()
		await process_frame
		if not sr.current_beat.is_empty():
			all.append(_key_of(sr.current_beat))
	if sr.view_open:
		sr.close_view()
	await _drain()
	return ",".join(all)


func _exit_says(to: String) -> String:
	var e := _exit(to)
	if e == null:
		return "<no exit %s>" % to
	sr.use_exit(e)
	await _frames(1)
	var t0 := Time.get_ticks_msec()
	while sr.current_beat.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	var k := _key_of(sr.current_beat)
	await _drain()
	return k



# --- 1. Spine ------------------------------------------------------------------------------

## Every line of a scene with its `then` follow-ups: [{speaker, text}].
func _lines_of(id: String) -> Array:
	var out: Array = []
	for ln in sd.scene(id).get("mandatory_lines", []):
		out.append(ln)
		for t in ln.get("then", []):
			out.append(t)
		for o in ln.get("options", []):
			out.append({"speaker": String(ln.get("speaker", "agata")), "text": String(o.get("text", ""))})
	return out


func _test_spine() -> void:
	var m01_agata := ""
	var m01_tamara := ""
	for ln in _lines_of("M01"):
		if String(ln.get("speaker", "")) == "agata":
			m01_agata += String(ln.get("text", "")) + " "
		elif String(ln.get("speaker", "")) == "tamara":
			m01_tamara += String(ln.get("text", "")) + " "
	_check(m01_agata.contains("ни строчки") and m01_agata.contains("не вернулась") and m01_agata.contains("переменилось"),
		"M01: Agata herself says the year without letters, Tamara's letter and that the aunt did not come back: %s" % m01_agata)
	_check(not m01_tamara.contains("ни строчки") and not m01_tamara.contains("паводком мост снесло"),
		"M01: Tamara does not explain to Agata what Agata knows: %s" % m01_tamara)
	_check(m01_agata.contains("чертовщина"), "M01: Agata's surprise about the boats (line 9)")
	var asked := false
	for ln in _lines_of("M03"):
		if String(ln.get("speaker", "")) == "agata" and String(ln.get("text", "")).contains("так и не вернулась"):
			asked = true
	_check(asked, "M03: «Где тётя?» asked as «так и не вернулась?»")
	# Words Agata cannot say before she learns it: scene where it is learned → words.
	var early := {"M15a": ["двадцать", "Здесь минута"], "M21": ["умерла", "умерл"], "M09b": ["Павел слышал", "Павел на мельнице слышал"]}
	for learned in early.keys():
		for id in sd.scene_order:
			if id == learned:
				break
			for ln in _lines_of(id):
				if String(ln.get("speaker", "")) != "agata":
					continue
				for w in early[learned]:
					_check(not String(ln.get("text", "")).contains(w), "%s: Agata says «%s» before %s: %s" % [id, w, learned, ln.get("text", "")])
	_check(not sd.text("@H2.bell.use").contains("Павел"), "H2 bell label: no «Павел слышал» (Agata learns it from Pavel)")
	# Fyodor Lukich is named once in what the player reads (besides the speaker name over his lines).
	var named := 0
	for k in sd.texts.keys():
		if String(sd.texts[k].get("text", "")).contains("Фёдор Лукич"):
			named += 1
		var ln = sd.texts[k].get("line", {})
		if ln is Dictionary and String(ln.get("text", "")).contains("Фёдор Лукич"):
			named += 1
	var in_scenes := 0
	for id in sd.scene_order:
		for ln in _lines_of(id):
			if String(ln.get("text", "")).contains("Фёдор Лукич"):
				in_scenes += 1
	_check(in_scenes + (1 if named > 0 else 0) == 1, "Fyodor Lukich explained once: scenes %d, text entries %d" % [in_scenes, named])


# --- 2. Tikhon ----------------------------------------------------------------------------

func _first_beats(hs_id: String, n: int = 2) -> Array:
	var h := _hotspot(hs_id)
	var out: Array = []
	if h == null:
		return ["<no hotspot %s>" % hs_id]
	sr.interact(h)
	await _frames(1)
	while out.size() < n and not sr.current_beat.is_empty():
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var ids: Array = []
			for o in b.get("options", []):
				ids.append(String(o.get("id", "")))
			out.append("options:" + ",".join(ids))
			break
		out.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", ""))])
		sr.advance()
		await process_frame
	await _drain("leave")
	return out


func _test_tikhon() -> void:
	var house := ["house_unlocked", "h1_shutter_open"]
	_flags_before("M03", house)
	await _enter("H1")
	var b := await _first_beats("tikhon")
	_check(b.size() > 0 and String(b[0]) == "tikhon:H1.tikhon.before_met", "before M03 Tikhon grumbles (his line, not a look): %s" % str(b))
	_flags_before("M04", house + ["stove_lit", "h1_scarf_removed", "visited_H2", "visited_H3"])
	await _enter("H1")
	b = await _first_beats("tikhon")
	_check(b.size() >= 2 and String(b[0]) == "tikhon:H1.tikhon.ask_shelf" and String(b[1]).begins_with("options:"),
		"until the shelf hangs Tikhon asks for it first, then the questions: %s" % str(b))
	_check(b.size() >= 2 and String(b[1]).contains("mend") and String(b[1]).contains("tamara") and not String(b[1]).contains("water"),
		"day one topics (how Dunya mended, Tamara), no day-two hint: %s" % str(b))
	gs.set_flag("q04_corner_stove", true)
	b = await _first_beats("tikhon")
	_check(b.size() >= 1 and String(b[0]).begins_with("options:"), "with the shelf hung — straight to the questions: %s" % str(b))
	_flags_before("M15a", house + ["stove_lit", "h1_scarf_removed", "q04_corner_stove"])
	await _enter("H1")
	b = await _first_beats("tikhon")
	_check(b.size() >= 1 and String(b[0]).contains("water") and String(b[0]).contains("stove_mirror"),
		"water going down, mother's mirror not done: Tikhon's hint about it is offered (103): %s" % str(b))
	gs.set_flag("done_M15a", true)
	b = await _first_beats("tikhon")
	_check(b.size() >= 1 and not String(b[0]).contains("water") and String(b[0]).contains("nina"), "after the mirror: no hint, Nina instead: %s" % str(b))
	gs.set_flag("tikhon_knows_dunya", true)
	gs.set_flag("done_M18p", true)
	b = await _first_beats("tikhon")
	_check(b.size() >= 1 and String(b[0]).contains("after_dunya"), "after the news Tikhon has his own answer: %s" % str(b))
	var water: Dictionary = sd.text_line("@H1.tikhon.water")
	_check(String(water.get("speaker", "")) == "tikhon" and String(water.get("text", "")).to_lower().contains("мамино зеркало"), "the hint is Tikhon's own voice: %s" % str(water))


# --- 3. Q06 hook --------------------------------------------------------------------------

func _test_q06_hook() -> void:
	var desc: String = sd.flag_description("q06_hook")
	_check(desc != "", "q06_hook has a journal line")
	_flags_before("M22")
	_check(not sr.journal_facts().has(desc), "without Nina's word the journal does not name the workbench")
	_check(not String(sd.scene("M22").get("goal", "")).is_empty(), "M22 has a goal")
	_flags_before("M23a")
	_check(gs.has_flag("q06_hook") and sr.journal_facts().has(desc), "after M22 (Nina's word) the journal names Ilya's workshop")
	_check(sd.scene_goal(sd.scene("M23a")).contains("к Илье в мастерскую"), "free-day goal names the workshop: %s" % sd.scene_goal(sd.scene("M23a")))
	var nina_said := false
	for ln in _lines_of("M22"):
		if String(ln.get("speaker", "")) == "nina" and String(ln.get("text", "")).contains("к Илье в мастерскую"):
			nina_said = true
	_check(nina_said, "M22: Nina says it in words")
	_beckoned.clear()
	await _enter("O4")
	_check(_beckoned.has("ilya_workshop"), "entering the street lights Ilya's workshop: %s" % str(_beckoned))
	gs.set_flag("q06_started", true)
	_check(not sd.scene_goal(sd.scene("M23a")).contains("к Илье в мастерскую"), "started — the goal no longer names it")
	_beckoned.clear()
	await _enter("O2")
	await _enter("O4")
	_check(not _beckoned.has("ilya_workshop"), "started — no more light: %s" % str(_beckoned))


# --- 4. Small things ----------------------------------------------------------------------

func _test_small() -> void:
	_flags_before("M03")
	await _enter("Z2")
	var e := _exit("H1")
	_check(e != null and e.label_text() == sd.text("@Z2.exit_H1.label_unlock"), "locked house: the label says «Отпереть дверь»: %s" % (e.label_text() if e else "-"))
	gs.add_item("key_house")
	sr.select_item("key_house")
	sr.use_exit(e)
	await _frames(1)
	var seen := await _drain()
	_check(seen.any(func(x): return String(x).contains("Z2.exit_H1.unlock_after")), "after unlocking Agata says the house is open from here: %s" % str(seen))
	if rm.current_room.room_id != "Z2":
		await _enter("Z2")
	e = _exit("H1")
	_check(e != null and e.label_text() == sd.text("@Z2.exit_H1.label"), "then the old label: %s" % (e.label_text() if e else "-"))
	var m10 := _lines_of("M10")
	_check(m10.size() >= 2 and String(m10[1].get("speaker", "")) == "agata", "M10: Agata answers Tikhon at the bell")
	var friend := false
	for ln in _lines_of("M23d"):
		if String(ln.get("speaker", "")) == "tikhon" and String(ln.get("text", "")).contains("Друг"):
			friend = true
	_check(friend, "M23d: Tikhon's word about friendship (145)")
	var ul := 0
	for id in ["M20", "M22", "M26"]:
		for ln in _lines_of(id):
			if String(ln.get("speaker", "")) == "ulyana" and String(ln.get("text", "")).to_lower().contains("сестр"):
				ul += 1
	_check(ul >= 2 and ul <= 4, "Ulyana's «sister» lines: 2–4, got %d" % ul)
