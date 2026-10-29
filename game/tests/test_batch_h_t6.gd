extends SceneTree
## Batch H, task T6 (Director 24.10, Docs/DECISIONS.md «Сон и смена дня»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_h_t6.gd
##   - every day ends with sleep: day one — the lezhanka by Dunya's stove in H1 (mother sees Agata there in the little
##     mirror, M19); days two and three — the bed in Nina's room (O3); the attic bed is Dunya's: «Дунина… Лягу у печи —
##     там теплее» on the night of day one, no sleep there ever. «Рано ложиться» / «пора спать» at both sleeping places;
##   - the change of day: «День второй / третий / четвёртый» over the black of the sleep (and «День первый» for a new
##     game) — once per change; a load of the save after it does not show it again.
## Exit code 0 only when every check passed.

var TOD = null

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var card: Node = null
var _card_seen: Array[String] = []   # texts of the card seen on screen while draining


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
	TOD = load("res://scripts/core/time_of_day.gd")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	card = main_node.get_node_or_null("GameUi/DayCard")
	_check(card != null, "GameUi/DayCard exists")
	await _test("T6: day one — sleep on the lezhanka by the stove; the attic bed is Dunya's", _test_day_one)
	await _test("T6: day two — the bed at Nina's after the talk with Ilya (N02) → «День третий»", _test_day_two)
	await _test("T6: day three — the bed at Nina's once the four deeds are done (M24) → «День четвёртый»", _test_day_three)
	await _test("T6: the day card — once per change, not again after a load; «День первый» for a new game", _test_card_once)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch H (T6): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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
	for f in ["house_unlocked", "house_open", "h1_shutter_open", "h1_scarf_removed"]:
		gs.set_flag(f, true)
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	sr._on_state_reset()
	await _frames(1)
	return rm.current_room


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


## Clicks through the beats (time guard: the sleep stagings with the card take ~12 s). Records the card's words.
func _drain() -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging()) and Time.get_ticks_msec() - t0 < 40000:
		if card != null and String(card.probe().get("text", "")) != "" and (_card_seen.is_empty() or _card_seen.back() != card.probe()["text"]):
			_card_seen.append(String(card.probe()["text"]))
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if seen.is_empty() or seen.back() != "stage":
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", b.get("text", "")))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


func _click(id: String) -> Dictionary:
	var h := _hotspot(id)
	_check(h != null and h.visible, "hotspot %s in %s" % [id, rm.current_room.room_id if rm.current_room else "?"])
	if h == null:
		return {}
	sr.interact(h)
	await _frames(1)
	return sr.current_beat


func _key(b: Dictionary) -> String:
	return String(b.get("text_key", ""))


# --- Day one ---------------------------------------------------------------------------------

func _test_day_one() -> void:
	# «Рано ложиться» at the lezhanka before the day's deeds; no night starts.
	for c in [["M05", "H4.bed.early_d1_door"], ["M07", "H4.bed.early_d1_class"]]:
		_flags_before(String(c[0]))
		await _enter("H1", "from_H3")
		var b := await _click("lezhanka")
		_check(_key(b) == String(c[1]) and String(b.get("speaker", "")) == "agata", "before %s: «рано» %s, got %s" % [c[0], c[1], str(b)])
		await _drain()
		_check(not gs.has_flag("started_N01"), "before %s: no night" % c[0])
	# The night: the gallery says where to sleep, the attic bed is Dunya's, the lezhanka ends the day.
	_flags_before("N01")
	rm.change_room("H3", "from_O1")
	await _frames(3)
	_check(_key(sr.current_beat) == "H3.night.to_bed" and sd.text("@H3.night.to_bed").contains("у печи"), "the gallery: «лягу у печи» (%s)" % str(sr.current_beat))
	await _drain()
	_check(sd.text("@ui.bedtime_d1_goal").contains("лежанка"), "the journal's bedtime goal names the lezhanka: %s" % sd.text("@ui.bedtime_d1_goal"))
	await _enter("H4", "from_H1")
	var b := await _click("bed")
	_check(_key(b) == "H4.bed.dunya_night" and String(b.get("text", "")).begins_with("Дунина") and String(b.get("speaker", "")) == "agata",
		"the attic bed on the night of day one: «Дунина… Лягу у печи — там теплее» (%s)" % str(b))
	await _drain()
	_check(not gs.has_flag("started_N01") and TOD.current_state() == "d1_night", "no sleep in the attic")
	await _enter("H1", "from_H4")
	_card_seen.clear()
	_check(sr.planned_interaction(_hotspot("lezhanka")) == "use", "the lezhanka is a use (cursor)")
	b = await _click("lezhanka")
	_check(_key(b) == "H1.lezhanka.late_d1", "«пора спать» first: %s" % str(b))
	var seen := await _drain()
	_check(gs.has_flag("done_N01") and rm.current_room.room_id == "H1", "N01 by the stove: %s" % str(seen))
	_check(TOD.current_state() == "d2_morning", "day two morning (%s)" % TOD.current_state())
	_check(_card_seen == ["День второй"], "the card «День второй» once over the black: %s" % str(_card_seen))
	# Next days: the attic bed only looks, the lezhanka says where Agata sleeps now.
	await _enter("H4", "from_H1")
	b = await _click("bed")
	_check(_key(b) == "H4.bed.look" and not gs.has_flag("started_N02"), "the attic bed by day: a look (%s)" % str(b))
	await _drain()
	await _enter("H1", "from_H4")
	b = await _click("lezhanka")
	_check(_key(b) == "H4.bed.early_d2", "the lezhanka on day two: «день в разгаре» (%s)" % str(b))
	await _drain()
	_flags_before("M21")
	await _enter("H1", "from_H4")
	b = await _click("lezhanka")
	_check(_key(b) == "H1.lezhanka.after_d1", "the lezhanka on day three: «теперь сплю у мамы» (%s)" % str(b))
	await _drain()


# --- Day two ---------------------------------------------------------------------------------

func _test_day_two() -> void:
	_flags_before("M19c")
	await _enter("O3", "from_O4")
	var b := await _click("bed")
	_check(_key(b) == "O3.bed.early_d2", "before the talk with Ilya: «рано» (%s)" % str(b))
	await _drain()
	_check(not gs.has_flag("started_N02"), "no night before M20")
	# The talk with Ilya ends: the journal points to the bed, the room stays at night.
	_flags_before("M20")
	sr._complete_scene("M20")
	await _frames(1)
	_check(gs.journal_goal == sd.text("@ui.bedtime_d2_goal"), "after M20 the journal points to the bed: %s" % gs.journal_goal)
	_check(not gs.has_flag("morning_day3") and TOD.current_state() == "d2_night", "after M20 it is still night (%s)" % TOD.current_state())
	await _drain()
	await _enter("O3", "from_O4")
	_card_seen.clear()
	b = await _click("bed")
	_check(_key(b) == "O3.bed.late_d2", "«пора спать» at Nina's: %s" % str(b))
	var seen := await _drain()
	_check(gs.has_flag("done_N02") and gs.has_flag("morning_day3") and TOD.current_state() == "d3_morning", "N02 → day three morning (%s): %s" % [TOD.current_state(), str(seen)])
	_check(_card_seen == ["День третий"], "the card «День третий» once: %s" % str(_card_seen))
	_check(sr.can_start("M21"), "M21 can start in the morning")


# --- Day three -------------------------------------------------------------------------------

func _test_day_three() -> void:
	_flags_before("M23a", ["done_M23b"])
	await _enter("O3", "from_O4")
	var b := await _click("bed")
	var t := String(b.get("text", ""))
	# J (стр. 178): spoken as recorded lines — «Рано ещё спать.», then each deed left on its own.
	_check(_key(b) == "H4.bed.early_short", "day three: «Рано ещё спать.» first (%s)" % _key(b))
	var keys: Array[String] = [_key(b)]
	var g := 0
	while not sr.current_beat.is_empty() and g < 20:
		sr.advance()
		await process_frame
		g += 1
		if not sr.current_beat.is_empty():
			keys.append(_key(sr.current_beat))
	_check(keys.has("H4.bed.todo_M23a") and not keys.has("H4.bed.todo_M23b"), "day three: what is left, each its own line: %s" % str(keys))
	await _drain()
	_flags_before("M23d")
	gs.set_flag("done_M23d", true)
	sr._complete_scene("M23d")
	await _frames(1)
	_check(gs.journal_goal == sd.text("@ui.bedtime_d3_goal") and gs.journal_goal.contains("горнице"), "the journal: the bed at mum's: %s" % gs.journal_goal)
	await _drain()
	_flags_before("M24")
	await _enter("H4", "from_H1")
	b = await _click("bed")
	_check(_key(b) == "H4.bed.look" and not gs.has_flag("started_M24"), "day three evening: no sleep in the attic (%s)" % str(b))
	await _drain()
	await _enter("O3", "from_O4")
	_card_seen.clear()
	b = await _click("bed")
	_check(_key(b) == "H4.bed.late_d3", "«пора спать» on day three: %s" % str(b))
	var seen := await _drain()
	_check(gs.has_flag("done_M24") and TOD.day_of(TOD.current_state()) == 4, "M24 → day four (%s): %s" % [TOD.current_state(), str(seen)])
	_check(_card_seen == ["День четвёртый"], "the card «День четвёртый» once: %s" % str(_card_seen))
	b = await _click("bed")
	_check(_key(b) == "H4.bed.after_d4", "the bed on day four: %s" % str(b))
	await _drain()


# --- The card --------------------------------------------------------------------------------

func _test_card_once() -> void:
	# A sleep, then the checkpoint save «День второй» is loaded: the card does not come again.
	_flags_before("N01")
	await _enter("H1", "from_H4")
	await _click("lezhanka")
	await _drain()
	_check(gs.has_flag("day_card_ui_day_card_2"), "the card's flag is set")
	var n: int = (card.probe()["shown"] as Array).size()
	var slot: String = rm.checkpoint_prefix + "day2"
	_check(rm.load_game(slot), "the checkpoint «День второй» loads")
	for i in 30:
		await process_frame
	_check((card.probe()["shown"] as Array).size() == n and String(card.probe()["phase"]) == "", "no card after the load")
	_check(not sr.play_day_card("@ui.day_card_2"), "the same card never twice")
	# An autosave made mid-sleep restarts the scene, but the card stays shown once.
	_flags_before("N01", ["day_card_ui_day_card_2"])
	await _enter("H1", "from_H4")
	_card_seen.clear()
	await _click("lezhanka")
	await _drain()
	_check(_card_seen.is_empty() and gs.has_flag("done_N01"), "a sleep replayed after its card: no second card (%s)" % str(_card_seen))
	# A new game: «День первый» over its own black, then the room.
	rm.new_game()
	sr.play_first_day_card()
	await _frames(2)
	var p: Dictionary = card.probe()
	_check(String(p["key"]) == "@ui.day_card_1" and float(p["black"]) > 0.9 and String(p["phase"]) != "", "a new game opens with «День первый» on black: %s" % str(p))
	var t0 := Time.get_ticks_msec()
	while String(card.probe()["phase"]) != "" and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	_check(String(card.probe()["phase"]) == "" and float(card.probe()["black"]) == 0.0, "the card goes and the room shows")
	sr.play_first_day_card()
	await _frames(1)
	_check(String(card.probe()["phase"]) == "", "«День первый» once")
