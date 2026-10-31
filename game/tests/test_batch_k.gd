extends SceneTree
## Batch K — Director's playthrough 31.10 (Docs/FEEDBACK_DIRECTOR_2026-10-31_map.md; «стр.» — a line of
## Docs/FEEDBACK_DIRECTOR_2026-10-31_raw.txt):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_k.gd
##   стр. 70: the brace on the support while the water is high — why not (not «Сюда не подходит»), the brace stays;
##   стр. 21: the house door's first unlocking says nothing of «и отсюда» (that is the side door's line);
##   стр. 17, 30, 45: the hands act only where they do something — the rope is not «reached for»;
## (in other files: стр. 5 — test_batch_j «J-E4»; стр. 4 — test_menus «Title items»; стр. 56 — test_day2 office mirror;
##  стр. 8–9 — test_agata_3d «Corners near the end»; стр. 30, 45 — test_agata_3d «Talking to someone».)
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
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
	player = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _test("K-70 the brace on the support while the water is high: Agata says why not, the brace stays in the bag", _test_brace_high)
	await _test("K-21 the house door's first unlocking: no «Теперь и отсюда…» (the side door's line)", _test_house_door_line)
	await _test("K-17 the rope at the pier: looked at and talked of, not reached for", _test_rope_no_action)
	gs.reset()
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch K: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


func _drain() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_busy()) and guard < 400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if not b.is_empty():
			seen.append(String(b.get("text_key", b.get("text", ""))))
		if sr.mechanic_open or sr.puzzle_open:
			break
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif not b.is_empty():
			sr.advance()
		await process_frame
	return seen


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == id:
			return h
	return null


func _set_flags(flags: Array) -> void:
	for f in flags:
		gs.set_flag(String(f), true)


# --- Tests -------------------------------------------------------------------------------

func _test_brace_high() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "done_M04", "done_M05", "done_M07"])
	gs.add_item("brace_plate")
	await _enter("Z3")
	for id in ["plate", "old_pier_base"]:
		var h := _hotspot(id)
		_check(h != null and h.visible, "Z3 by day: «%s» is there" % id)
		if h == null:
			continue
		sr.select_item("brace_plate")
		_check(sr.planned_interaction(h) == "item_use", "%s with the brace: an answer of its own, not «Сюда не подходит» (%s)" % [id, sr.planned_interaction(h)])
		sr.interact(h)
		await _frames(1)
		var seen := await _drain()
		_check(seen.has("Z3.plate.brace_high"), "%s: «До плиты сейчас не достать — вода высоко…» (%s)" % [id, str(seen)])
		_check(gs.has_item("brace_plate"), "%s: the brace stays in the bag" % id)
		sr.select_item("")


func _test_house_door_line() -> void:
	var z2: Dictionary = {}
	for e in sd.rooms["Z2"].get("exits", []):
		if String(e.get("to", "")) == "H1":
			z2 = e
	var key_use: Dictionary = z2.get("item_use", {}).get("key_house", {})
	_check(not key_use.is_empty(), "Z2 → H1: the key unlocks the house door")
	_check(not JSON.stringify(key_use.get("then", [])).contains("unlock_after"), "the first unlocking says «Теперь и отсюда…» (%s)" % str(key_use.get("then", [])))
	var z4_said := false
	for oe in sd.rooms["Z4"].get("on_enter", []):
		z4_said = z4_said or String(oe.get("text", "")) == "@Z4.side_door.now_open"
	_check(z4_said, "the side door's lane (Z4) still says it after the first time through")


func _test_rope_no_action() -> void:
	var rope: Dictionary = {}
	for h in sd.rooms["R1"].get("hotspots", []):
		if String(h.get("id", "")) == "rope":
			rope = h
	_check(not rope.is_empty() and String(rope.get("action_anim", "")) == "", "R1 rope: no hand action (%s)" % rope.get("action_anim", ""))
