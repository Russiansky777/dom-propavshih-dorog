extends SceneTree
## Batch I, task I-T5 — review-2 by ChatGPT and the Director's voice notes (25.10, Docs/tasks/I_T5_review2.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_i_t5.gd
##   1. the bird drawing in M22 (section 6.1): scarf / boat / bridge / nothing — each answer of Ulyana and Agata sounds
##      only for its own drawing (the boat and the bridge are `then` of the scarf line, with their own conditions);
##   2. the free day in two orders, a→b→c→d and c→d→a→b (6.4): every scene starts from its real trigger (Tamara on the
##      street, the mill yard, entering the house, Tikhon) and the evening comes after the fourth;
##   3. `{left}` before bed (6.5): one deed — just it; several — «…, … и …»;
##   4. the new talks with Tikhon: each is offered by its flags, says Tikhon / Agata / Tikhon, and only once; the two
##      inside scenes (M10, M26) — after Agata's answer and after the answer about Wednesday, Ulyana and Agata last;
##   5. the brace (6.3): «при такой воде…» while the plate is under water, «там и поставлю» at dusk;
##      the mother's mirror again (6.2): «Здесь минута — там двадцать» before the knot, a neutral line once time is common;
##   6. the Director's words stay (map 25.10, voice notes): the hint about the mother's mirror after the water,
##      «мистика» nowhere, the changed lines as he gave them.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var mv: Node = null

const HOUSE := ["house_unlocked", "h1_shutter_open", "stove_lit", "h1_scarf_removed", "q04_corner_stove"]


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
	mv = main_node.get_node("MechanicView")
	rm.autosave_enabled = false
	await _test("I-T5 6.1: the bird drawing — scarf / boat / bridge / nothing, each answer only for its drawing", _test_drawing)
	await _test("I-T5 6.4: the free day a→b→c→d and c→d→a→b from the real triggers", _test_free_day)
	await _test("I-T5 6.5: {left} before bed — one deed, several deeds joined with «и»", _test_left)
	await _test("I-T5: new talks with Tikhon — by flags, Tikhon / Agata / Tikhon, once; M10 and M26 inside the scenes", _test_tikhon_talks)
	await _test("I-T5 6.2, 6.3: the brace before / after the water; the mother's mirror again before / after the knot", _test_brace_mirror)
	await _test("I-T5: the Director's words stay — the hint after the water, no «мистика», his changed lines", _test_director_words)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch I (I-T5): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


func _drain(pick_id: String = "") -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 40000:
		if sr.mechanic_open:
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
			var k := String(b.get("text_key", ""))
			seen.append("%s:%s" % [String(b.get("speaker", "")), k if k != "" else String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


## Enter a room; what the entry said and played (first-entry lines, scenes on enter).
func _enter(room_id: String, spawn: String = "default") -> Array:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	return await _drain()


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _talk(hs_id: String, pick_id: String = "") -> Array:
	var h := _hotspot(hs_id)
	if h == null:
		return ["<no hotspot %s>" % hs_id]
	sr.interact(h)
	await _frames(1)
	return await _drain(pick_id)


## The option ids Tikhon offers now (after his shelf request, if any); the dialogue is closed with «leave».
func _tikhon_options() -> Array:
	var h := _hotspot("tikhon")
	if h == null:
		return []
	sr.interact(h)
	await _frames(1)
	var ids: Array = []
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 8:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			for o in b.get("options", []):
				ids.append(String(o.get("id", "")))
			break
		sr.advance()
		await process_frame
	await _drain("leave")
	return ids


func _lines_of(id: String) -> Array:
	var out: Array = []
	for ln in sd.scene(id).get("mandatory_lines", []):
		out.append(ln)
		for t in ln.get("then", []):
			out.append(t)
	return out


func _has_line(seen: Array, speaker: String, begins: String) -> bool:
	return seen.any(func(x): return String(x).begins_with(speaker + ":" + begins))


# --- 1. The drawing ----------------------------------------------------------------------

func _test_drawing() -> void:
	var answers := {
		"v03_add_scarf": ["ulyana:А кто ей шарф повязал", "agata:И шарф я"],
		"v03_add_boat": ["ulyana:А лодку с дымом кто", "agata:Я у твоего папы подсмотрела"],
		"v03_add_bridge": ["ulyana:Кто мостик нарисовал", "agata:Будет, Уля"],
	}
	for drawn in ["v03_add_scarf", "v03_add_boat", "v03_add_bridge", ""]:
		_flags_before("M22", [drawn] if drawn != "" else [])
		gs.set_flag("v03_marked", drawn != "")
		var seen := await _enter("O1")
		_check(gs.has_flag("done_M22"), "%s: M22 played in the class: %s" % [drawn, str(seen)])
		for f in answers.keys():
			for a in answers[f]:
				var said: bool = seen.any(func(x): return String(x).begins_with(a))
				_check(said == (f == drawn), "%s: «%s» %s" % [drawn if drawn != "" else "nothing drawn", a, "missing" if f == drawn else "said for another drawing"])
		_check(_has_line(seen, "nina", "К Дуне домой пойду"), "%s: the scene goes on to Nina after the drawing" % drawn)


# --- 2. The free day ----------------------------------------------------------------------

## Plays one deed of the free day from its trigger; true when its done flag is set.
func _play_deed(id: String) -> bool:
	match id:
		"M23a":
			await _enter("O4")
			await _talk("tamara")
		"M23b":
			await _enter("Z2")
			await _enter("M1")
		"M23c":
			await _enter("H3")
			await _enter("H1", "from_H3")
		"M23d":
			if rm.current_room == null or rm.current_room.room_id != "H1":
				await _enter("H1", "from_H3")
			await _talk("tikhon", "agata")
	return gs.has_flag("done_" + id)


func _test_free_day() -> void:
	for order in [["M23a", "M23b", "M23c", "M23d"], ["M23c", "M23d", "M23a", "M23b"]]:
		_flags_before("M23a")
		for i in order.size():
			var id: String = order[i]
			_check(sr.can_start(id), "%s: %s can start after %s" % ["→".join(order), id, str(order.slice(0, i))])
			var ok: bool = await _play_deed(id)
			_check(ok, "%s: %s played from its trigger (room %s)" % ["→".join(order), id, rm.current_room.room_id if rm.current_room else "-"])
			if not ok:
				break
		_check(not sr.can_start("M24") or gs.has_flag("done_M23d"), "%s: the evening only after all four" % "→".join(order))
		var all_done: bool = order.all(func(x): return gs.has_flag("done_" + String(x)))
		_check(all_done, "%s: all four deeds done" % "→".join(order))


# --- 3. {left} ------------------------------------------------------------------------------

func _bed_text() -> String:
	var sl: Dictionary = {}
	for h in sd.room("O3").get("hotspots", []):
		if h.has("sleep"):
			sl = h["sleep"]
	if sl.is_empty():
		for h in sd.room("O3").get("hotspots", []):
			for k in h.keys():
				if h[k] is Dictionary and h[k].has("early"):
					sl = h[k]
	return String(sr.sleep_early_beat(sl).get("text", ""))


func _test_left() -> void:
	_flags_before("M23a")
	var t := _bed_text()
	_check(t.contains("Надо ещё повидать Тамару на раздаче писем, зайти к Павлу на мельницу, сходить к маме в Дунин дом и поговорить с Тихоном о Дуне."),
		"four deeds: «…, …, … и …»: %s" % t)
	gs.set_flag("done_M23a", true)
	gs.set_flag("done_M23b", true)
	t = _bed_text()
	_check(t.contains("Надо ещё сходить к маме в Дунин дом и поговорить с Тихоном о Дуне."), "two deeds joined with «и»: %s" % t)
	gs.set_flag("done_M23c", true)
	t = _bed_text()
	_check(t == "Рано ещё спать. Надо ещё поговорить с Тихоном о Дуне.", "one deed — just it: %s" % t)
	_check(not t.contains("{left}") and not t.contains(", ."), "no raw placeholder: %s" % t)


# --- 4. Tikhon -------------------------------------------------------------------------------

func _test_tikhon_talks() -> void:
	# topic → (scene before which the state is built, extra flags)
	var topics := {
		"cream": ["M04", []],
		"supper": ["M04", ["visited_H2", "h1_asked_mend"]],
		"tea": ["M04", ["visited_H3", "h1_asked_door"]],
		"snow": ["M07", []],
		"duty": ["M09", []],
		"quiet": ["M15a", []],
		"hear": ["M15s", ["h1_tikhon_after_mirror"]],
		"home": ["M24", ["tikhon_knows_dunya", "h1_asked_after_dunya"]],
	}
	for topic in topics.keys():
		var spec: Array = topics[topic]
		_flags_before(String(spec[0]), HOUSE + spec[1])
		await _enter("H1", "from_H3")
		var opts := await _tikhon_options()
		_check(opts.has(topic), "%s: offered by its flags: %s" % [topic, str(opts)])
		var seen := await _talk("tikhon", topic)
		var a := seen.find("tikhon:H1.tikhon." + topic)
		var b := seen.find("agata:H1.tikhon.%s_2" % topic)
		var c := seen.find("tikhon:H1.tikhon.%s_3" % topic)
		_check(a >= 0 and b > a and c > b, "%s: Tikhon, Agata, Tikhon in turn: %s" % [topic, str(seen)])
		_check(gs.has_flag("h1_asked_" + topic), "%s: its flag is set" % topic)
		opts = await _tikhon_options()
		_check(not opts.has(topic), "%s: only once: %s" % [topic, str(opts)])
	# Out of their window — not offered (the first day's talk does not linger into day two).
	_flags_before("M09", HOUSE + ["visited_H2", "h1_asked_mend", "visited_H3", "h1_asked_door"])
	await _enter("H1", "from_H3")
	var later := await _tikhon_options()
	for t in ["cream", "supper", "tea", "snow", "home"]:
		_check(not later.has(t), "morning of day two: «%s» is not offered: %s" % [t, str(later)])
	# Inside the scenes: M10 after Agata's answer; M26 after the answer about Wednesday, before the cups; last words stay.
	var m10 := _lines_of("M10")
	_check(m10.size() == 6 and String(m10[1].get("speaker", "")) == "agata" and String(m10[2].get("text", "")) == "Тётя тоже тебе спать мешала?"
		and String(m10[5].get("text", "")) == "Громко заботилась.", "M10: the talk after Agata's answer: %s" % str(m10.map(func(l): return l.get("text", ""))))
	for ln in m10.slice(2):
		_check(not ln.has("if") and not ln.has("unless"), "M10: the inserted lines have no conditions of their own")
	var m26 := _lines_of("M26")
	var texts: Array = m26.map(func(l): return String(l.get("text", "")))
	var wed := texts.find("Среда.")
	var tease := texts.find("Ворчишь, а сам гостей дожидаешься.")
	var cups := texts.find("Синяя… Моя ведь! Я её Дуне дарила.")
	_check(wed >= 0 and tease == wed + 1 and cups == tease + 4, "M26: the talk right after «Среда.» and before the cups: %d %d %d" % [wed, tease, cups])
	for ln in m26.slice(tease, tease + 4):
		_check(not ln.has("if") and not ln.has("unless"), "M26: the talk sounds after either answer (Nina's or Agata's) — no conditions")
	_check(String(m26[m26.size() - 2].get("speaker", "")) == "ulyana" and String(m26.back().get("speaker", "")) == "agata",
		"M26: Ulyana's question and Agata's answer stay last")
	# Played: the M26 talk sounds when Nina answered (line 19 is then skipped).
	_flags_before("M26", ["tikhon_told_nina"])
	sr.start_scene("M26")
	await _frames(2)
	var seen26 := await _drain()
	_check(_has_line(seen26, "nina", "Среда, Тихон") and not seen26.has("agata:Среда.") and _has_line(seen26, "agata", "Ворчишь, а сам гостей")
		and _has_line(seen26, "tikhon", "Ещё смеются"), "M26 with Nina's answer: the talk still sounds: %s" % str(seen26))


# --- 5. The brace and the mirror -------------------------------------------------------------

func _test_brace_mirror() -> void:
	_flags_before("M15a")
	# J (Р8, Директор 29.10): a thing on a wrong place — everywhere the short «Сюда не подходит».
	_check(sr.item_refusal("brace_plate") == "@item.wrong_generic", "before dusk: «Сюда не подходит» (J, Р8)")
	gs.set_flag("evening_dusk", true)
	_check(sr.item_refusal("brace_plate") == "@item.wrong_generic", "at dusk: the same short refusal (J, Р8)")
	for common in [false, true]:
		var base := ["done_M14", "nina_mirror_clamped", "has_clamp", "house_unlocked", "h2_bundle_unwrapped", "nina_time_compared"]
		_flags_before("M15a", base + (["road_held_both_ends"] if common else []))
		gs.add_item("pocket_watch")
		await _enter("H2")
		var h = _hotspot("bundle_nina")
		sr.open_mechanic(sr.mechanic_spec(h), "bundle_nina")
		await _frames(3)
		var p = mv.panel
		_check(p != null, "the mother's mirror opens")
		if p == null:
			continue
		p.hold_watch()
		await _frames(1)
		var k := String(sr.current_beat.get("text_key", ""))
		var want := "H2d.nina_mirror.watch_again_common" if common else "H2d.nina_mirror.watch_again"
		_check(k == want, "%s: the watch again says %s, got %s" % ["common time" if common else "20:1", want, k])
		while not sr.current_beat.is_empty():
			sr.advance()
			await process_frame
		sr.close_mechanic()
		await _frames(2)


# --- 6. The Director's words --------------------------------------------------------------

func _test_director_words() -> void:
	var water: Dictionary = sd.text_line("@H1.tikhon.water")
	_check(String(water.get("text", "")).contains("Мамино зеркало") and String(water.get("text", "")).contains("колокол"),
		"the hint after the water stays (map 103) with ChatGPT's grumbling: %s" % str(water))
	for k in sd.texts.keys():
		var e: Dictionary = sd.texts[k]
		var ln = e.get("line", {})
		_check(not String(e.get("text", "")).contains("мистик") and not (ln is Dictionary and String(ln.get("text", "")).contains("мистик")), "«мистика» replaced: %s" % k)
	for id in sd.scene_order:
		for ln in _lines_of(id):
			_check(not String(ln.get("text", "")).contains("мистик"), "«мистика» replaced: %s" % id)
	var said := {
		"M13": "Коль воду спущу — то пруд пустой останется.",
		"M21b": "А как прежде сделать — нельзя?",
		"M25": "Я ворот кручу, а ты знаки подавай.",
		"M15": "Снова дорога — с двух концов!",
	}
	for id in said.keys():
		var found := false
		for ln in _lines_of(id):
			if String(ln.get("text", "")).contains(said[id]):
				found = true
		_check(found, "%s: the Director's words «%s»" % [id, said[id]])
	_check(sd.text("@H1.after_mirror.tikhon_2").contains("покуда не спишь — делами займись"), "Tikhon after the mirror: the Director's words of 29.10 (стр. 116, batch J)")
	_check(sd.text("@Z2.exit_H1.unlock_after").contains("Теперь и отсюда"), "the house door: the Director's own words stay (map 34–35)")
	_check(sd.text("@O1.board.use").contains("моё послание кто прочёл"), "the board: the Director's words (map 59 → his approved text of 30.10, F10)")
	var m20 := _lines_of("M20")
	_check(m20.any(func(l): return String(l.get("text", "")) == "Ну, раз хотела — буду тебе сестрой, Уля."), "M20: Agata's answer as the Director heard and approved it")
