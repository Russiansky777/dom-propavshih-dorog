extends SceneTree
## The review before release (Director 15.11, 22:38: «перепройди ещё раз игру целиком и полностью и поищи, не осталось
## ли какого-либо вида багов, недоработок, неясностей сюжета, не интуитивности»; Docs/REVIEW_FULL_2026-11-15.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1511.gd
##   R15-1 (the replay under a display, pictures of the mini-games: «Выбрано: Струбцина — щёлкнуть по месту…» lies over
##       mother's mirror, the same line over the plate, the sluice, the office mirror): the line «Выбрано: …» stays 7 s —
##       a thing used sooner left it over the mini-game it opened. Now the line goes with the choice: the thing put back
##       or a mini-game opened — it is gone at once. Self-check — another hint on the same line is left its time.
##   R15-2 (the replay: on the third day, with all four errands done, Agata says «Всё, что хотела, сделала» and the goal
##       reads «Дела дня сделаны» — while the goal a minute before listed «к Илье в мастерскую — Уле место ладить» among
##       what is not done; that errand is optional and waits till morning): the evening's goal says so while Ilya's
##       workshop has been offered and not begun. Self-check — with the workshop begun the goal has no such words.

var _results: Array = []
var _fails: Array[String] = []


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
	await _test("R15-1 the line «Выбрано: …» goes when the thing is put back or opens a mini-game; self-check — another hint stays", _test_selection_hint)
	await _test("R15-2 the third evening's goal says Ilya's workshop waits till morning while it is offered and not begun; self-check — begun, it does not", _test_evening_goal)
	var failed := _results.count(false)
	print("==== review 15.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _test_selection_hint() -> void:
	var gs = root.get_node("GameState")
	var sr = root.get_node("StoryRunner")
	var sd = root.get_node("StoryData")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var ui = main_node.get_node("GameUi")
	var line: Label = ui.get("hint_line")
	gs.add_item("clamp")
	await process_frame
	var want := String(sd.call("text", "@ui.item_selected", {"item": sd.call("item_name", "clamp")}))
	sr.select_item("clamp")
	await process_frame
	_check(line.text == want and want.begins_with("Выбрано"), "picked: the line reads «%s» (it is «%s»)" % [want, line.text])
	sr.select_item("clamp")   # the same thing again — put back
	await process_frame
	_check(String(sr.selected_item) == "" and line.text == "", "put back: the line is gone at once (it is «%s»)" % line.text)
	# picked and used: a mini-game opens (the old photograph in the mill's entry — any panel will do)
	var spec: Dictionary = {}
	for h in sd.rooms["M2"].get("hotspots", []):
		var m = (h as Dictionary).get("mechanic")
		if m is Dictionary and String(m.get("type", "")) == "photo":
			spec = (m as Dictionary).duplicate(true)
	_check(not spec.is_empty(), "the test's mini-game: M2 has a photo panel")
	spec.erase("events")
	sr.select_item("clamp")
	await process_frame
	_check(line.text == want, "picked again: the line is back")
	sr.open_mechanic(spec, "photo")
	await process_frame
	_check(line.text == "", "a mini-game opened: the line «Выбрано: …» is not left over it (it is «%s»)" % line.text)
	sr.close_mechanic()
	sr.select_item("")
	await process_frame
	# self-check: a hint of another kind is not swept away with the choice
	ui.call("show_hint", "проверка: другая подсказка")
	await process_frame
	sr.select_item("clamp")
	await process_frame
	ui.call("show_hint", "проверка: другая подсказка")
	sr.select_item("")
	await process_frame
	_check(line.text == "проверка: другая подсказка", "self-check: another hint on the line stays when the choice is put back (it is «%s»)" % line.text)
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await process_frame


func _test_evening_goal() -> void:
	var gs = root.get_node("GameState")
	var sd = root.get_node("StoryData")
	gs.reset()
	var tod = load("res://scripts/core/time_of_day.gd")   # by path: the class leans on the autoloads, not there when this script compiles
	var bt: Dictionary = tod.state_spec("d3_evening").get("bedtime", {})
	_check(not bt.is_empty(), "the third evening has its bedtime in the time data")
	var plain := String(sd.call("text", "@ui.bedtime_d3_goal"))
	_check(String(sd.call("bedtime_goal", bt)) == plain, "the workshop never offered: the plain goal")
	gs.set_flag("q06_hook", true)
	var offered := String(sd.call("bedtime_goal", bt))
	_check(offered != plain and offered.begins_with(plain) and offered.contains("Иль"), "Ilya's workshop offered and not begun: the evening's goal says it waits («%s»)" % offered)
	gs.set_flag("q06_started", true)
	var begun := String(sd.call("bedtime_goal", bt))
	_check(begun == plain, "self-check: the workshop begun — the goal is the plain one («%s»)" % begun)
	gs.reset()
