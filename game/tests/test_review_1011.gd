extends SceneTree
## The whole-game review of 10.11 (Director 13:00: «пройдёмся полностью по игре как тестировщик и обзорщик»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1011.gd
##   R-1 (Director 15:12: «Тихон и Дуня — можно поправить»): in M23d the narrator says «Потом перебирается поближе к
##       Агатиной лежанке и там укладывается», and Tikhon sat in the armchair to the end of the scene — the flag
##       tikhon_knows_dunya came only with the scene's grants. Now a short fade after the narrator's words sets it:
##       «Значит, вечер кончился» he says from the bench by the stove. The test plays the scene and looks where his
##       figure is at each line; self-check — the same scene without that staging is caught (he is still in the chair).
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
	player = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _test("R-1 M23d: Tikhon moves to Agata's bench after the narrator's words, before «Значит, вечер кончился»; self-check — without the staging he is still in the chair", _test_tikhon_moves)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== review 10.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running") or sr.call("is_staging")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


func _use(id: String) -> bool:
	var h: Node2D = rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null
	if h == null or not h.visible:
		return false
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


## Everything the story gave before scene `upto` (flags of the scenes' grants and stagings).
func _flags_before(upto: String) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for st in sc.get("stage", []):
			for f in st.get("sets", []):
				gs.set_flag(String(f), true)


## Reads the queued beats out; for each spoken line — where Tikhon's figure is and whether he knows:
## [{text, knows, pos}].
func _read_out(pick: String) -> Array:
	var log: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 4000:
		guard += 1
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var id := pick
			if not opts.any(func(o): return String(o.get("id", "")) == pick):
				id = String(opts[0].get("id", "")) if not opts.is_empty() else ""
			sr.choose(id)
		else:
			await _frames(2)   # the figure follows the flag on the next frame
			var t: Node2D = sr.call("_actor_node", rm.current_room, "tikhon")
			log.append({"text": String(b.get("text", "")), "knows": gs.has_flag("tikhon_knows_dunya"),
				"pos": t.global_position if t != null else Vector2.INF})
			sr.advance()
		await process_frame
	await _frames(2)
	return log


func _play_m23d() -> Array:
	_flags_before("M23d")
	gs.set_flag("tikhon_knows_dunya", false)
	await _enter("H1")
	await _read_out("")          # whatever the room says on entering
	if not await _use("tikhon"):
		return []
	return await _read_out("nina")


static func _line(log: Array, begins: String) -> Dictionary:
	for e in log:
		if String(e["text"]).begins_with(begins):
			return e
	return {}


# --- R-1 ------------------------------------------------------------------------------------

func _test_tikhon_moves() -> void:
	var sc: Dictionary = sd.scene("M23d")
	var lines: Array = sc.get("mandatory_lines", [])
	var narr := -1
	for i in lines.size():
		if String(lines[i].get("text", "")).contains("перебирается"):
			narr = i
	_check(narr >= 0, "M23d has the narrator's line about Tikhon moving")
	var stage: Array = sc.get("stage", [])
	_check(stage.any(func(s): return typeof(s.get("at")) != TYPE_STRING and int(s.get("at", -1)) == narr + 1 and (s.get("sets", []) as Array).has("tikhon_knows_dunya")),
		"the staging right after the narrator's line sets tikhon_knows_dunya (line %d)" % (narr + 1))
	var log := await _play_m23d()
	var before := _line(log, "Долго Тихон молчит")
	var after := _line(log, "Значит, вечер кончился")
	_check(not before.is_empty() and not after.is_empty(), "the scene played: the narrator's line and Tikhon's answer were read (%d lines)" % log.size())
	if before.is_empty() or after.is_empty():
		return
	var chair: Vector2 = before["pos"]
	var bench: Vector2 = after["pos"]
	_check(not bool(before["knows"]), "while the narrator speaks Tikhon is still in the armchair (the flag is not set yet)")
	_check(bool(after["knows"]), "«Значит, вечер кончился» — the flag is set by then")
	# the armchair is low at the left (feet y ≈ 790…890 of the room), the bench by the stove higher (≈ 460…620)
	_check(chair.y - bench.y > 120.0, "Tikhon's figure is up on the bench when he answers: armchair %s → bench %s" % [str(chair), str(bench)])
	_check(gs.has_flag("done_M23d"), "the scene completes")
	# Self-check: the same scene without the staging — he answers from the armchair, and the measure sees it.
	var kept: Array = stage.duplicate()
	var cut: Array = stage.filter(func(s): return not (s.get("sets", []) as Array).has("tikhon_knows_dunya"))
	stage.clear()
	stage.append_array(cut)
	var log2 := await _play_m23d()
	stage.clear()
	stage.append_array(kept)
	var after2 := _line(log2, "Значит, вечер кончился")
	_check(not after2.is_empty() and not bool(after2["knows"]) and absf((after2["pos"] as Vector2).y - chair.y) < 40.0,
		"self-check: without the staging he is still in the armchair at his answer, and the check tells (%s)" % str(after2.get("pos", null)))
