extends SceneTree
## Headless tests of blocks 3–5 (E4–E5 + optional stories, Docs/SCENARIO_FINAL.md §8–9 with the polish approved by the
## Director 22.10 23:44). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_day3.gd
## What is proved:
##   - data: the scenes of blocks 3–4, frames (FrameView rooms) build, no old-chain words left, goals without codes;
##   - the windlass (M25): «пускай / стой / подымай», a bump on the stone without penalty, the log settles on the ring;
##   - start points (?start=…) give the state of the story up to their scene;
##   - the whole of blocks 3–4 by script from the far pier: mother, the clock, brother, the notebooks, the class with
##     mother (the answer on the board and the first common date), the free day in any order (letters, Nina in her
##     sister's house with frames, Tikhon — a choice, the mill with the manager — the bridge decided), the evening,
##     the first span by mouse on the plaques, the inscription, the epilogue to its last held shot and the end panel;
##   - choices leave traces: board answers, Tikhon's master, epilogue lines by flags;
##   - save/load at each checkpoint («День третий», «День четвёртый», after the end) replays nothing and blocks nothing;
##   - block 5: the optional stories (letter, sleeve, notches, tea, street sign, Nina's letters) once, with traces.
## Exit code 0 only when every check passed.

var AUTOSAVE := "test_day3_auto_%d" % OS.get_process_id()
var SLOT := "test_day3_mid_%d" % OS.get_process_id()
## Checkpoint slots of this run: per process — two suites on one machine (agents in parallel worktrees share
## user://) must not delete each other's «День третий» (23.10: a parallel run's cleanup removed test3_day3).
var CP := "test3_%d_" % OS.get_process_id()

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node = null
var frame_titles := {}
var mv: Node = null
var fv: Node = null
var cv: Node = null
var player: Node2D = null
var _results: Array = []
var _fails: Array[String] = []
var _reached_end: bool = false
var frames_seen: Array[String] = []


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	_reached_end = false
	var started := Time.get_ticks_msec()
	await fn.call()
	if not _reached_end:
		_fails.append("the test did not reach its end (script error above)")
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
	await _test("Logic: windlass — lower, bump without penalty, raise, stop at the ring, settle", _test_windlass_logic)
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_slot = AUTOSAVE
	rm.checkpoint_prefix = CP
	mv = main_node.get_node("MechanicView")
	fv = main_node.get_node("FrameView")
	cv = main_node.get_node("CloseupView")
	player = main_node.get_node("World/Player")
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	sr.frame_changed.connect(func(f, _h): if f != "": frames_seen.append(f))
	# The title bar names the frame's place (game_ui connects first, so its label is already updated here).
	var title_label: Label = main_node.get_node("GameUi").get("room_label")
	sr.frame_changed.connect(func(f, _h): if f != "": frame_titles[f] = title_label.text)
	await _test("Data: blocks 3–4 scenes, frames, texts — no old chain, goals without codes", _test_data)
	await _test("Frames: every frame room builds over the world (layers by flags, no hotspots)", _test_frames_build)
	await _test("Start points: the state up to their scene, the right room, items in the bag", _test_start_points)
	await _test("Blocks 3–4 by script: far pier → mother → … → first span by mouse → epilogue → end", _test_walkthrough)
	await _test("Save/load at the checkpoints: nothing replays, the story goes on", _test_save_load)
	await _test("Choices leave traces: board answers, Tikhon, epilogue lines and layers by flags", _test_traces)
	await _test("Block 5: optional stories — once each, traces in the epilogue", _test_optional)
	gs.reset()
	for s in [AUTOSAVE, SLOT, SLOT + "_d4", SLOT + "_end", CP + "day3", CP + "day4"]:
		gs.delete_save(s)
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== day3: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(1)


func _button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(1)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, true)
	await _button(at, false)


func _v(d) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0))) if d is Dictionary else Vector2.ZERO


func _staging_done() -> void:
	var g := 0
	while sr.is_staging() and g < 4000:
		await process_frame
		g += 1


## Advance every text on screen (options: first, or the given ids in turn). Stops at an open close-up.
func _finish(choices: Array = []) -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	await _staging_done()
	while not sr.current_beat.is_empty() and guard < 300:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", "")).left(48)])
			sr.advance()
		await process_frame
		await _staging_done()
	await _frames(2)
	return seen


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


func _room() -> String:
	return rm.current_room.room_id if rm.current_room != null else ""


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _use(id: String) -> bool:
	var h := _hotspot(id)
	if h == null or not h.visible:
		_check(false, "hotspot %s missing or hidden in %s" % [id, _room()])
		return false
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


func _use_item(item: String, id: String) -> bool:
	sr.select_item(item)
	if sr.selected_item != item:
		_check(false, "cannot take %s in hand (inventory %s)" % [item, str(gs.inventory)])
		return false
	return await _use(id)


func _go(target: String) -> bool:
	var e = rm.current_room.get_node_or_null("Exits/to_" + target) if rm.current_room != null else null
	if e == null:
		_check(false, "no exit %s→%s" % [_room(), target])
		return false
	var before := _room()
	player.call("click_at", e.global_position)
	await _wait_idle()
	var frames := 0
	while _room() == before and sr.current_beat.is_empty() and frames < 90:
		await process_frame
		frames += 1
	await _frames(2)
	return _room() == target


## A chain of rooms by their exits; texts on the way are read through.
func _route(rooms: Array) -> bool:
	for r in rooms:
		if not await _go(String(r)):
			_check(false, "route stopped at %s → %s" % [_room(), r])
			return false
		await _finish()
	return true


func _close_view() -> void:
	if sr.view_open:
		sr.close_view()
		await _frames(2)


# --- Logic -------------------------------------------------------------------------------

func _test_windlass_logic() -> void:
	var w := WindlassLogic.new({"rest": 0.8, "tolerance": 0.06, "speed": 0.2, "raise_speed": 0.5, "settle_s": 0.5})
	var events: Array[String] = []
	w.event.connect(func(n): events.append(n))
	_check(w.state == "wait" and w.pos == 0.0, "the log starts hoisted, waiting")
	_check(not w.apply("stop"), "stop at the top does nothing")
	_check(w.apply("lower") and w.state == "down", "«пускай» — the log goes down")
	for i in 60:
		w.step(0.1)
	_check(w.state == "bumped" and "bumped" in events, "let down past the ring — it knocks on the stone (%s %.2f)" % [w.state, w.pos])
	_check(not w.apply("lower") and w.state == "bumped", "on the stone «пускай» does nothing — Ilya waits for «подымай»")
	_check(w.apply("raise") and w.state == "up", "«подымай» — hauled up")
	for i in 40:
		w.step(0.1)
	_check(w.state == "wait" and w.pos == 0.0, "back at the top, nothing lost (%s %.2f)" % [w.state, w.pos])
	w.apply("lower")
	while w.pos < 0.4:
		w.step(0.05)
	w.apply("stop")
	_check(w.state == "stopped" and not w.solved(), "stopped too high — just stopped")
	w.apply("lower")
	while w.pos < 0.78:
		w.step(0.02)
	w.apply("stop")
	_check(w.state == "settling", "«стой» at the ring — settles (%.2f)" % w.pos)
	for i in 10:
		w.step(0.1)
	_check(w.solved() and "solved" in events and is_equal_approx(w.pos, w.rest), "the log lies on the ring")
	_check(w.angle(9.0) == 0.0, "angle 0 on the ring — exactly the delivered picture")
	_reached_end = true


# --- Data --------------------------------------------------------------------------------

const BLOCK34 := ["M19", "M19c", "M20", "M21", "M21b", "M22", "M23a", "M23b", "M23c", "M23d", "M24", "M25", "M26"]


func _test_data() -> void:
	for id in BLOCK34:
		var sc: Dictionary = sd.scene(id)
		_check(not sc.is_empty(), "scene %s missing" % id)
		_check(String(sc.get("goal", "")) != "", "%s: a goal for the journal" % id)
	for id in ["M27", "M28", "M29", "M30", "M31", "M32", "M33", "M34", "V06", "V07", "V08", "V09", "V10", "V11", "V12"]:
		_check(sd.scene(id).is_empty(), "%s (old chain) is gone" % id)
	var all_text := ""
	for f in ["E4.json", "E5.json"]:
		all_text += FileAccess.get_file_as_string("res://data/story/scenes/" + f)
	all_text += FileAccess.get_file_as_string("res://data/story/text/ru_E4_E5.json")
	all_text += FileAccess.get_file_as_string("res://data/story/quests.json")
	all_text += FileAccess.get_file_as_string("res://data/story/flags.json")
	all_text += FileAccess.get_file_as_string("res://data/story/items.json")
	for word in ["Размыв", "насос", "закрывающ", "ЗП", "пристанск", "карточк", "уйдёт под воду", "пять местных дней"]:
		_check(not all_text.contains(word), "blocks 3–5 still mention «%s»" % word)
	for rid in ["O3", "O4"]:
		_check(sd.in_scope(rid), "%s in scope" % rid)
	# D21: no seven-person council — the decision is at the mill with four.
	var m23b: Dictionary = sd.scene("M23b")
	var speakers := {}
	for ln in m23b.get("mandatory_lines", []):
		speakers[String(ln.get("speaker", ""))] = true
	speakers.erase("narrator")
	_check(speakers.size() == 4 and speakers.has("manager") and speakers.has("ilya"), "the mill beat decides the bridge with four people: %s" % str(speakers.keys()))
	_check(m23b.get("grants", {}).get("flags", []).has("bridge_decided"), "the bridge is decided at the mill (M23b)")
	# C18–C20: the lesson, then the dinner — Ulyana's line closes the game; Nina's «Доучись» always; on a Wednesday.
	var ep: Array = sd.scene("M26").get("mandatory_lines", [])
	_check(String(ep[ep.size() - 1].get("text", "")) == "А завтра тоже можно прийти?" and String(ep[ep.size() - 1].get("speaker", "")) == "ulyana", "the last line of the game is Ulyana's")
	var has_doucheis := false
	for ln in ep:
		if String(ln.get("text", "")).begins_with("Доучись") and not ln.has("if") and not ln.has("switch"):
			has_doucheis = true
	_check(has_doucheis, "Nina's «Доучись…» is said in every epilogue")
	_check(String(ep[0].get("text", "")).contains("в среду"), "the epilogue day is a Wednesday")
	var order: Array = []
	for st in sd.scene("M26").get("stage", []):
		order.append(String(st.get("frame", "")))
	_check(order.find("EP_lesson") >= 0 and order.find("EP_lesson") < order.find("EP_dinner"), "lesson before dinner: %s" % str(order))
	_check(String(sd.scene("M26").get("end_frame", "")) == "EP_dinner", "the dinner is the last shot")
	_reached_end = true


func _test_frames_build() -> void:
	for id in sd.rooms.keys():
		if not bool(sd.room(id).get("frame", false)):
			continue
		var r = load("res://scripts/rooms/room_builder.gd").build(String(id))
		_check(r != null, "frame %s builds" % id)
		if r == null:
			continue
		root.add_child(r)
		await _frames(1)
		_check(r.get_hotspots().is_empty() and r.get_exits().is_empty(), "%s: no hotspots, no exits" % id)
		root.remove_child(r)
		r.free()
	# FrameView over the world.
	gs.reset()
	rm.change_room("Z3", "default")
	await _frames(3)
	sr.set_frame("EP_dinner")
	await _frames(3)
	var p: Dictionary = fv.probe()
	_check(bool(p.get("open", false)) and String(p.get("frame", "")) == "EP_dinner", "FrameView shows the dinner: %s" % str(p))
	_check(not bool(p.get("layers", {}).get("cup_blue", true)), "the blue cup layer is off without v01_cup_blue")
	gs.set_flag("v01_cup_blue", true)
	await _frames(2)
	_check(bool(fv.probe().get("layers", {}).get("cup_blue", false)), "the blue cup Nina recognises — on with the flag")
	sr.set_frame("")
	await _frames(2)
	_check(not bool(fv.probe().get("open", true)), "the frame is cleared")
	_reached_end = true


# --- Start points ------------------------------------------------------------------------

func _test_start_points() -> void:
	var want := {"olkhovka": ["R3", "M18"], "day3": ["O3", "M20"], "freewalk": ["O1", "M22"], "span": ["Z3", "M24"], "epilogue": ["Z3", "M25"]}
	for pid in want.keys():
		_check(rm.start_at(pid), "start point %s" % pid)
		await _frames(3)
		_check(_room() == String(want[pid][0]), "%s: room %s (%s)" % [pid, want[pid][0], _room()])
		_check(gs.has_flag("done_" + String(want[pid][1])), "%s: %s done" % [pid, want[pid][1]])
		for it in ["pocket_watch", "school_ribbon", "drawing_ilya", "plan_crossing", "journal_manager"]:
			_check(gs.has_item(it), "%s: %s in the bag" % [pid, it])
		for it in ["key_house", "chalk", "clamp", "key_sluice", "brace_plate", "mirror_mill"]:
			_check(not gs.has_item(it), "%s: %s used up, not in the bag" % [pid, it])
		await _finish()
		if sr.mechanic_open:
			sr.close_mechanic()
			await _frames(2)
		sr.set_frame("")
	# The epilogue start point: the epilogue plays by itself at the turn.
	rm.start_at("epilogue")
	await _frames(3)
	_check(String(sr.active_scene) == "M26" or gs.has_flag("started_M26"), "?start=epilogue — the epilogue begins (%s)" % sr.active_scene)
	sr.call("_on_state_reset")
	_reached_end = true


# --- Walkthrough -------------------------------------------------------------------------

func _test_walkthrough() -> void:
	rm.autosave_enabled = true
	Engine.time_scale = 4.0
	frames_seen.clear()
	_check(rm.start_at("olkhovka"), "start at the far pier (end of day two)")
	await _frames(3)
	gs.set_flag("waved_at_stove", true)   # C17: block 2's optional wave at the stove
	var seen := await _finish()
	# M19: up the path to the street.
	_check(await _go("O4"), "R3→O4")
	seen = await _finish()
	_check(gs.has_flag("done_M19") and _room() == "O3", "M19: mother on the porch, then her room (%s): %s" % [_room(), str(seen)])
	_check(seen.any(func(x): return x.begins_with("mitya:Илья! Сестра твоя")), "Mitya knocks: %s" % str(seen))
	_check(rm.current_room.get_node("Layers/hand_min") != null, "Nina's clock is in her room")
	# M19c: the clock against the pocket watch.
	await _use("clock")
	seen = await _finish()
	_check(gs.has_flag("o3_clock_compared") and gs.has_flag("done_M19c"), "the watch against the clock → M19c: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("nina:Двадцать лет я в него смотрела")), "B12: Nina's twenty years at the hand mirror")
	_check(seen.any(func(x): return x.begins_with("nina:А позавчера ты встала у печи")), "C17: the wave at the stove is remembered")
	# M20 follows by itself: brother, his daughter, his wife, the night, the morning.
	seen.append_array(await _finish())
	var g := 0
	while not gs.has_flag("done_M20") and g < 400:
		seen.append_array(await _finish())
		await process_frame
		g += 1
	_check(gs.has_flag("done_M20") and gs.has_flag("met_ilya") and gs.has_flag("morning_day3"), "M20: Ilya, Ulyana, the wife; morning: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("ilya:Ты не выросла")), "Ilya: «Ты не выросла»")
	_check(gs.has_flag("wife_came"), "the wife came with the lamp: her figure is shown by wife_came (set in M20 before her line)")
	_check(gs.has_save(CP + "day3"), "checkpoint «День третий» written")
	_check(not _hotspot("ilya").visible and rm.current_room.get_node("Effects/night") != null and not rm.current_room.get_node("Effects/night").visible, "morning: the night tone is off, Ilya has gone home")
	_check(rm.save_game(SLOT), "save in the morning of day three")
	# M21: Nina about Dunya; notebooks, village list → M21b.
	await _use("nina")
	seen = await _finish()
	_check(gs.has_flag("done_M21") and gs.has_flag("knows_evdokia_death"), "M21: Dunya died at 72: %s" % str(seen))
	await _use("notebooks")
	await _frames(3)
	_check(sr.view_open and cv.probe().get("pages", 0) == 4, "the notebooks open as four spreads: %s" % str(cv.probe().get("pages")))
	var pr: Dictionary = cv.probe()
	_check(int(pr.get("page", -1)) == 0, "first spread first")
	await _finish()
	await _click(_v(cv.probe().get("next", {})))
	_check(int(cv.probe().get("page", -1)) == 1, "«Дальше» turns the page")
	var sheets: Array = cv.probe().get("sheets", [])
	var paths_text := ""
	for s in sheets:
		paths_text += String(s.get("text", ""))
	_check(paths_text.contains("Нижняя улица стояла пустой ещё до беды"), "A6: the lower street stood empty before the flood")
	await _close_view()
	await _use("village_list")
	await _frames(2)
	seen = await _finish()
	await _close_view()
	seen.append_array(await _finish())
	_check(gs.has_flag("done_M21b") and gs.has_flag("school_path_open") and gs.has_flag("lower_street_returned"), "M21b: «Как было — нет», the paths came back: %s" % str(seen))
	# M22: by the returned path to the class.
	_check(await _route(["O4", "O2"]), "O3→O4→O2 by the returned school path")
	_check(_hotspot("mitten_path") != null and _hotspot("mitten_path").visible and not _hotspot("mitten").visible, "the mitten lies on the path home")
	await _use("mitten_path")
	await _finish()
	_check(gs.has_item("mitten") and gs.has_flag("mitten_found_on_path"), "picked up silently — the same mitten, back in the bag")
	_check(await _go("O1"), "O2→O1")
	seen = await _finish()
	_check(gs.has_flag("done_M22") and gs.has_flag("nina_answered_board"), "M22 in the class with mother: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("narration:Нина читает на доске: «Мама, я иду»")), "Nina answers «Мама, я иду»")
	_check(seen.any(func(x): return x == "agata:У нас двадцать пятое октября."), "A3: Agata's date")
	_check(rm.current_room.get_node("Layers/nina_answer_mama").visible and rm.current_room.get_node("Layers/nina_answer_date").visible and not rm.current_room.get_node("Layers/nina_answer_here").visible, "the answer and the common date on the board")
	_check(rm.current_room.get_node("Layers/ulyana_bird_reply").visible, "Ulyana answered next to Agata's mark")
	_check(not _hotspot("nina").visible, "mother has gone to her sister's house")
	_check(gs.has_flag("boat_shuttle_open"), "F13: from the free day the boat goes both ways (boat_shuttle_open for the R3 ↔ R1 passage of block 2)")
	# The free day: through the school door — Nina in her sister's house (frames), Tikhon.
	frames_seen.clear()
	_check(await _go("H3"), "O1→H3 through the school door")
	await _finish()
	_check(await _go("H1"), "H3→H1")
	seen = await _finish()
	_check(gs.has_flag("done_M23c") and gs.has_flag("nina_visited_house"), "M23c: Nina in her sister's house: %s" % str(seen))
	_check(frames_seen.has("F_gallery_nina") and frames_seen.has("F_workshop_nina") and frames_seen.has("F_mirror_empty"), "frames: gallery, workshop, the empty room in the glass: %s" % str(frames_seen))
	_check(not fv.probe().get("open", true), "the frames are cleared after the scene")
	await _use("tikhon")
	seen = await _finish(["nina"])
	_check(gs.has_flag("done_M23d") and gs.has_flag("tikhon_told_nina") and not gs.has_flag("tikhon_told_agata"), "M23d: mother tells Tikhon: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("tikhon:Значит, вечер кончился")), "«Значит, вечер кончился»")
	_check(seen.any(func(x): return x.begins_with("tikhon:Хозяйка")), "Tikhon calls Nina «хозяйка»")
	await _frames(3)
	var tk = _hotspot("tikhon")
	_check(tk != null and tk.position.y < 300.0, "Tikhon moved from the armchair onto the stove (%s)" % str(tk.position if tk else null))
	# The mill: the manager comes back — the bridge is decided (D21).
	frames_seen.clear()
	_check(await _go("Z2"), "H1→Z2")
	await _finish()
	_check(await _go("M1"), "Z2→M1")
	seen = await _finish()
	_check(gs.has_flag("done_M23b") and gs.has_flag("bridge_decided"), "M23b at the mill: %s" % str(seen))
	_check(frames_seen.has("F_mill_manager"), "the mill frame with four people")
	_check(String(frame_titles.get("F_mill_manager", "")) == sd.location_name("M1"), "the title bar names the mill yard over the mill frame, not the room under it (%s)" % str(frame_titles.get("F_mill_manager")))
	_check(seen.any(func(x): return x.begins_with("pavel:Год ключ на гвозде висел")) and seen.any(func(x): return x.begins_with("ilya:Значит, мост. Пока лёд не встал")), "the manager, Pavel, Agata, Ilya decide the bridge")
	_check(seen.any(func(x): return x.begins_with("pavel:Ты слово давала")), "Pavel remembers Agata's word (pavel_answer_promise)")
	_check(not gs.has_flag("done_M24"), "the evening waits for Tamara's letters")
	# Letters: back to Olkhovka by the rope, Tamara on the street.
	_check(await _route(["Z2", "R1", "R2", "R3", "O4"]), "Zarechye → the pier → the crossing → Olkhovka")
	await _use("tamara")
	seen = await _finish()
	_check(gs.has_flag("done_M23a") and gs.has_flag("dunya_letter_on_stove"), "M23a: a year of letters: %s" % str(seen))
	seen.append_array(await _finish())
	var g2 := 0
	while not gs.has_flag("done_M24") and g2 < 200:
		seen.append_array(await _finish())
		await process_frame
		g2 += 1
	_check(gs.has_flag("done_M24") and gs.has_flag("morning_day4"), "M24: the evening of day three, then morning: %s" % str(seen))
	_check(gs.has_save(CP + "day4"), "checkpoint «День четвёртый» written")
	_check(rm.save_game(SLOT + "_d4"), "save on the morning of day four")
	# The first span.
	_check(await _route(["R3", "R2", "R1", "Z3"]), "to the turn")
	await _staging_done()
	var gw := 0
	while not sr.mechanic_open and gw < 300:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		await _staging_done()
		gw += 1
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "windlass", "the windlass close-up opens in the scene (M25)")
	var p = mv.panel
	var pr2: Dictionary = mv.probe().get("panel", {})
	# A bump first: let down past the ring.
	await _click(_v(pr2.get("plaque_lower", {})))
	var gb := 0
	while p.logic.state != "bumped" and gb < 2000:
		await process_frame
		gb += 1
	_check(p.logic.state == "bumped", "let down too far — knocks on the stone (%s)" % p.logic.state)
	await _finish()
	_check(not gs.has_flag("span_first_laid"), "no log on the ring after a bump")
	await _click(_v(pr2.get("plaque_raise", {})))
	gb = 0
	while p.logic.state != "wait" and gb < 2000:
		await process_frame
		gb += 1
	_check(p.logic.state == "wait", "«Подымай» — back at the top")
	# The stop by real game time (×1): under load a frame at ×4 can carry the log past the whole ring window
	# (23.10: a run beside a browser check missed the ring). Click as soon as the log enters the window.
	Engine.time_scale = 1.0
	await _click(_v(pr2.get("plaque_lower", {})))
	gb = 0
	while p.logic.pos < p.logic.rest - p.logic.tolerance * 0.8 and gb < 4000:
		await process_frame
		gb += 1
	await _click(_v(pr2.get("plaque_stop", {})))
	gb = 0
	while not gs.has_flag("span_first_laid") and gb < 2000:
		await process_frame
		gb += 1
	Engine.time_scale = 4.0
	_check(gs.has_flag("span_first_laid"), "«Стой» at the ring — the log lies on the ring")
	_check(p.signals_seen.has("lower") and p.signals_seen.has("stop") and p.signals_seen.has("raise"), "all three signals used: %s" % str(p.signals_seen))
	frames_seen.clear()
	seen = await _finish(["dunya"])
	var g3 := 0
	while not gs.has_flag("done_M26") and g3 < 600:
		seen.append_array(await _finish(["dunya"]))
		await process_frame
		g3 += 1
	_check(gs.has_flag("done_M25") and gs.has_flag("beam_dunya"), "M25: the inscription «Дуня»")
	_check(gs.has_flag("done_M26") and gs.has_flag("game_finished"), "M26: the epilogue to the end: %s" % str(seen.slice(0, 8)))
	for f in ["F_span_done", "EP_tamara", "EP_boat", "EP_pavel", "EP_beam", "EP_lesson", "EP_dinner"]:
		_check(frames_seen.has(f), "epilogue shot %s (%s)" % [f, str(frames_seen)])
	_check(String(frame_titles.get("EP_lesson", "")) == sd.location_name("O1") and String(frame_titles.get("EP_tamara", "")) == sd.text("@EP.place_bridge"),
		"epilogue titles: the class, the bridge — not the turn under the frames (%s)" % str(frame_titles))
	_check(seen.size() > 0 and seen[seen.size() - 1] == "ulyana:А завтра тоже можно прийти?", "the last line: Ulyana (%s)" % (seen[seen.size() - 1] if seen.size() > 0 else ""))
	await _frames(4)
	var fp: Dictionary = fv.probe()
	_check(bool(fp.get("open", false)) and String(fp.get("frame", "")) == "EP_dinner" and bool(fp.get("hold", false)), "the last shot stays: %s" % str(fp.get("frame")))
	_check(fp.has("new_game") and String(fp.get("traces", "")).length() > 0, "the end panel with the traces and «Начать заново»")
	_check(bool(fv.probe().get("layers", {}).get("cut_dunya", false)) == false, "(dinner has no beam layer)")
	_check(rm.save_game(SLOT + "_end"), "save after the end")
	Engine.time_scale = 1.0
	_reached_end = true


# --- Save / load ---------------------------------------------------------------------------

func _test_save_load() -> void:
	Engine.time_scale = 4.0
	for slot in [CP + "day3", SLOT]:
		_check(rm.load_game(slot), "load %s" % slot)
		await _frames(3)
		_check(_room() == "O3", "%s: in mother's room (%s)" % [slot, _room()])
		_check(sr.current_beat.is_empty() and not sr.is_staging(), "%s: nothing replays on load" % slot)
		_check(gs.has_flag("done_M20") and not sr.can_start("M20") and gs.has_flag("morning_day3"), "%s: the night is over, M20 stays done" % slot)
		await _use("nina")
		var seen := await _finish()
		_check(gs.has_flag("done_M21"), "%s: the day goes on after the load (M21): %s" % [slot, str(seen)])
	_check(rm.load_game(CP + "day4"), "load «День четвёртый»")
	await _frames(3)
	_check(sr.current_beat.is_empty() and not sr.is_staging() and not fv.probe().get("open", true), "day four: nothing replays, no frame left")
	_check(gs.has_flag("done_M24") and not gs.has_flag("done_M25"), "day four: before the span")
	_check(rm.load_game(SLOT + "_end"), "load after the end")
	await _frames(4)
	var fp: Dictionary = fv.probe()
	_check(bool(fp.get("open", false)) and String(fp.get("frame", "")) == "EP_dinner", "after the end the last shot is shown again (%s)" % str(fp))
	_check(sr.current_beat.is_empty(), "the epilogue does not replay")
	# A new game clears it.
	rm.new_game()
	await _frames(3)
	_check(not fv.probe().get("open", true) and _room() == "Z1", "a new game: no frame, the post office")
	await _finish()
	Engine.time_scale = 1.0
	_reached_end = true


# --- Traces --------------------------------------------------------------------------------

func _beats_of(scene_id: String, flags: Array) -> Array[String]:
	## The lines a scene would show under these flags (beat_allowed, as in the game).
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	var out: Array[String] = []
	for ln in sd.scene(scene_id).get("mandatory_lines", []):
		if ln.has("options"):
			continue
		if sr.beat_allowed(ln):
			out.append("%s:%s" % [String(ln.get("speaker", "")), String(ln.get("text", ""))])
	return out


func _test_traces() -> void:
	var here := _beats_of("M22", ["board_here"])
	_check(here.any(func(x): return x.contains("Все двадцать лет")) and not here.any(func(x): return x.contains("Дождалась")), "board «Я была здесь»: «И я. Все двадцать лет. Мама»")
	var none := _beats_of("M22", [])
	_check(none.any(func(x): return x.begins_with("narrator:Доска чистая")) and not none.any(func(x): return x.contains("Нина читает")), "no inscription: only the date")
	_check(none.any(func(x): return x.contains("двадцать пятое октября")), "the common date in every branch")
	var ilya := _beats_of("M22", ["board_ilya", "v03_marked"])
	_check(ilya.any(func(x): return x.contains("лодки с дымом")) and ilya.any(func(x): return x.contains("Я ответила")), "board «Илюша…» and the bird mark: Ulyana answered")
	var fam := _beats_of("M26", ["pavel_answer_family", "tikhon_told_agata", "v01_cup_white", "beam_blank"])
	_check(fam.any(func(x): return x.begins_with("pavel:Мама с братом")) and not fam.any(func(x): return x.begins_with("pavel:Слово сдержала")), "Pavel's epilogue line follows the answer in the office")
	_check(fam.any(func(x): return x.contains("спит у Агатиной лежанки")) and fam.any(func(x): return x.begins_with("agata:Среда")), "told by Agata: Tikhon sleeps by her bed; Agata answers «Среда»")
	_check(fam.any(func(x): return x.contains("Белая")) and fam.any(func(x): return x.contains("Торец первого прогона чистый")), "the white cup; the clean beam end")
	var prom := _beats_of("M26", ["pavel_answer_promise", "tikhon_told_nina", "q07_board_to_pelageya", "q01_mail_at_nina"])
	_check(prom.any(func(x): return x.begins_with("pavel:Слово сдержала")) and prom.any(func(x): return x.begins_with("nina:Среда, Тихон")), "promise kept; Nina answers Tikhon")
	_check(prom.any(func(x): return x.contains("Митина дощечка")) and prom.any(func(x): return x.contains("Через Нину")), "optional stories leave their lines")
	# Frame layers by flags: the beam end inscription.
	gs.reset()
	gs.set_flag("beam_roads", true)
	sr.set_frame("EP_beam")
	await _frames(3)
	var ly: Dictionary = fv.probe().get("layers", {})
	_check(bool(ly.get("cut_roads", false)) and not bool(ly.get("cut_dunya", true)), "the beam end shows the chosen inscription: %s" % str(ly))
	sr.set_frame("")
	gs.reset()
	_reached_end = true


# --- Block 5 ---------------------------------------------------------------------------------

func _test_optional() -> void:
	Engine.time_scale = 4.0
	# Q07 and Q01 on the street of Olkhovka, the free day.
	_check(rm.start_at("freewalk"), "start: the free day")
	await _frames(3)
	await _finish()
	_check(await _route(["O2", "O4"]), "O1→O2→O4")
	if _hotspot("mitya_board") != null:
		await _use("mitya_board")
		await _finish()
		await _close_view()
		await _use("mitya_board")
		var seen := await _finish(["B"])
		_check(gs.has_flag("q07_board_to_pelageya") and gs.has_flag("done_Q07"), "Q07: the board to Pelageya: %s" % str(seen))
		_check(not _hotspot("mitya_board").visible and not gs.has_flag("q07_board_with_mitya"), "the choice is made once — the board is put away")
	else:
		_check(false, "Q07: no board hotspot in O4")
	await _use("tamara")
	await _finish()
	if _hotspot("letters_bag") != null:
		await _use("letters_bag")
		await _finish()
		await _close_view()
		await _use("letters_bag")
		var seen2 := await _finish(["A"])
		_check(gs.has_flag("q01_mail_at_nina") and gs.has_flag("done_Q01"), "Q01: the letter through Nina: %s" % str(seen2))
	else:
		_check(false, "Q01: no letters bag hotspot in O4")
	# Q09 on the lower street.
	_check(await _go("S1"), "O4→S1 (the lower street came back)")
	await _finish()
	await _use("street_sign")
	await _finish()
	await _close_view()
	await _use("street_sign")
	var seen3 := await _finish(["B"])
	_check(gs.has_flag("q09_original_in_classroom") and gs.has_flag("done_Q09"), "Q09: the sign into the class: %s" % str(seen3))
	_check(await _go("O4"), "S1→O4")
	# Nina's letters in her room.
	_check(await _go("O3"), "O4→O3")
	await _finish()
	await _use("nina_letters")
	await _frames(2)
	_check(sr.view_open and int(cv.probe().get("pages", 0)) >= 3, "Nina's letters: several pages")
	await _finish()
	await _close_view()
	_check(gs.has_flag("nina_letters_read"), "Nina's letters read")
	# Q03 and Q08 in the house.
	_check(await _go("O4"), "O3→O4")
	_check(await _route(["O2", "O1", "H3", "H1"]), "through the school door home")
	await _finish()
	await _use("nina_coat")
	await _finish()
	await _close_view()
	await _use("nina_coat")
	var seen4 := await _finish(["A"])
	_check(gs.has_flag("q03_hidden_seam") and gs.has_flag("done_Q03"), "Q03: the sleeve sewn: %s" % str(seen4))
	await _use("tea_corner")
	var seen5 := await _finish(["A"])
	_check(gs.has_flag("q08_home_evening") and gs.has_flag("done_Q08"), "Q08: tea by the stove: %s" % str(seen5))
	var all_q := 0
	for q in ["Q01", "Q03", "Q07", "Q08", "Q09"]:
		if gs.has_flag("done_" + q):
			all_q += 1
	_check(all_q == 5, "all five optional stories done (%d)" % all_q)
	# Traces at the end panel.
	var tr: Array = fv.call("achieved")
	_check(tr.size() >= 5, "achievements reached: %d" % tr.size())
	Engine.time_scale = 1.0
	_reached_end = true
