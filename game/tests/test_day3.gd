extends SceneTree
## Headless tests of blocks 3–5 (E4–E5 + optional stories, Docs/SCENARIO_FINAL.md §8–9 with the polish approved by the
## Director 22.10 23:44). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_day3.gd
## What is proved:
##   - data: the scenes of blocks 3–4, frames (FrameView rooms) build, no old-chain words left, goals without codes;
##   - the windlass (M25): «пускай / стой / подымай», a bump on the stone without penalty, the log settles on the ring;
##     G46: any «Стой» in the ring zone settles it (down, up, stopped there), the target is shown (the chalk mark on the
##     ring, the gauge whose green band is logic.rest ± tolerance), after a bump «Подымай» glows — by real clicks;
##   - G43: from day three the boat goes both ways by the same pulls on the rope (day three, day four before and after
##     the log), no room with arrows on the way; G42: the people of the span are on screen from the first shot;
##   - start points (?start=…) give the state of the story up to their scene;
##   - the whole of blocks 3–4 by script from the far pier: mother, the clock, brother, the notebooks, the class with
##     mother (the answer on the board and the first common date), the free day in any order (letters, Nina in her
##     sister's house with frames, Tikhon — a choice, the mill with the manager — the bridge decided), the evening,
##     the first span by mouse on the plaques, the inscription, the epilogue to its last held shot and the end panel;
##   - choices leave traces: board answers, Tikhon's master, epilogue lines by flags;
##   - save/load at each checkpoint («День третий», «День четвёртый», after the end) replays nothing and blocks nothing;
##   - block 5: the optional stories (letter, sleeve, notches, tea, street sign, Nina's letters) once, with traces;
##     Q02/Q06 traces: both choices in epilogue lines, frames and rooms, skipped — no trace (the mini-games themselves,
##     reworked by H47/H48, step by step and both choices to the end — tests/test_q02_q06.gd).
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
	await _test("G46: the windlass by real clicks — mark, gauge = rest ± tolerance, bump → «Подымай», stop up and down", _test_windlass_panel)
	await _test("G43: the boat both ways by pulls on the rope — day three, day four before and after the log", _test_shuttle)
	await _test("Start points: the state up to their scene, the right room, items in the bag", _test_start_points)
	await _test("Blocks 3–4 by script: far pier → mother → … → first span by mouse → epilogue → end", _test_walkthrough)
	await _test("Save/load at the checkpoints: nothing replays, the story goes on", _test_save_load)
	await _test("Choices leave traces: board answers, Tikhon, epilogue lines and layers by flags", _test_traces)
	await _test("Block 5: optional stories — once each, traces in the epilogue", _test_optional)
	await _test("Block 5: Q02/Q06 traces — both choices in epilogue lines, frames and rooms; skipped — nothing, the end as before", _test_q02_q06_traces)
	await _test("Batch 8 art: drawn states by flags (board answers, coat, bag, board, night, day frames, epilogues) — one at a time, never stacked", _test_batch8)
	gs.reset()
	for s in [AUTOSAVE, SLOT, SLOT + "_d4", SLOT + "_end", CP + "day3", CP + "day4", SLOT + "_q02", SLOT + "_q02_done", SLOT + "_q06"]:
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
	# G46: «Стой» on the way UP at the ring settles too.
	var u := WindlassLogic.new({"rest": 0.8, "tolerance": 0.06, "speed": 0.2, "raise_speed": 0.5, "settle_s": 0.5})
	u.apply("lower")
	for i in 60:
		u.step(0.1)
	_check(u.state == "bumped" and not u.at_ring(), "bumped lies below the ring zone (%.2f) — a «Стой» there is not «at the ring»" % u.pos)
	_check(not u.apply("stop") and u.state == "bumped", "«Стой» against the stone does nothing — Ilya waits for «Подымай»")
	u.apply("raise")
	while u.pos > u.rest + u.tolerance * 0.3:
		u.step(0.02)
	_check(u.state == "up" and u.at_ring(), "hauled up into the ring zone (%.2f)" % u.pos)
	_check(u.apply("stop") and u.state == "settling", "«Стой» at the ring on the way up — settles (%s)" % u.state)
	for i in 10:
		u.step(0.1)
	_check(u.solved() and is_equal_approx(u.pos, u.rest), "up-stop: the log lies on the ring")
	# G46: a log stopped in the zone and «Стой» again — settles.
	var z := WindlassLogic.new({"rest": 0.8, "tolerance": 0.06})
	z.pos = 0.83
	z.state = "stopped"
	_check(z.apply("stop") and z.state == "settling", "stopped in the zone, «Стой» again — settles (%s)" % z.state)
	# G46: bump → raise → lower → stop at the ring — settles.
	var r := WindlassLogic.new({"rest": 0.8, "tolerance": 0.06, "speed": 0.2, "raise_speed": 0.5, "settle_s": 0.5})
	r.apply("lower")
	for i in 60:
		r.step(0.1)
	r.apply("raise")
	for i in 4:
		r.step(0.1)
	_check(r.state == "up" and r.pos < r.rest - r.tolerance, "bump, «Подымай» — above the ring again (%.2f)" % r.pos)
	_check(r.apply("lower") and r.state == "down", "«Пускай» on the way up — down again")
	while r.pos < r.rest - r.tolerance * 0.5:
		r.step(0.02)
	_check(r.apply("stop") and r.state == "settling", "bump → raise → lower → «Стой» at the ring — settles")
	_check(r.zone().is_equal_approx(Vector2(0.74, 0.86)), "the zone is rest ± tolerance (%s)" % str(r.zone()))
	# The data numbers of M25: a readable motion and a forgiving zone.
	var spec: Dictionary = sd.scene("M25").get("mechanics", [{}])[0].get("spec", {})
	var lg: Dictionary = spec.get("logic", {})
	var max_deg := float(spec.get("max_deg", 0))
	var tol := float(lg.get("tolerance", 0))
	var rest := float(lg.get("rest", 1))
	_check(max_deg >= 18.0, "the log swings visibly (max_deg %.1f ≥ 18)" % max_deg)
	_check(max_deg * tol / rest * 2.0 >= 3.5, "the ring zone is ≥ 3.5° of swing (%.2f°)" % (max_deg * tol / rest * 2.0))
	_check(2.0 * tol / float(lg.get("speed", 1)) >= 1.5, "the log stays ≥ 1.5 s in the zone going down (%.2f s)" % (2.0 * tol / float(lg.get("speed", 1))))
	_reached_end = true


## G46 by real input: the M25 close-up opened as in the scene, every signal a mouse click on its plaque (probe centres).
func _test_windlass_panel() -> void:
	gs.reset()
	Engine.time_scale = 4.0
	var spec: Dictionary = sd.scene("M25").get("mechanics", [{}])[0].get("spec", {})
	# G47/G48 (art pack 9): the turn of day four with the site — the stack, the windlass, the crib; the log on it only
	# once laid; the close-up and both frames on the same day-four base (no plate on the shore stone).
	_check(rm.start_at("span"), "start at the turn, day four")
	await _frames(3)
	var lay: Node = rm.current_room.get_node_or_null("Layers")
	_check(lay != null and lay.get_node("span_site_day4").visible and not lay.get_node("span_beam_day4").visible,
		"G47: Z3 on day four shows the site (stack, windlass, crib), no log on the pier yet — the turn is not empty under the close-up")
	gs.set_flag("span_first_laid", true)
	await _frames(2)
	_check(lay.get_node("span_beam_day4").visible, "G47: once laid, the first log lies on the pier in the room too")
	for fr in ["F_span", "F_span_done"]:
		_check(String(sd.room(fr).get("background", {}).get("image", "")) == String(spec.get("art", {}).get("waiting", "")),
			"G48: %s on the day-four base of the close-up (%s)" % [fr, sd.room(fr).get("background", {}).get("image", "")])
	_check(Vector2(float(spec["pivot"][0]), float(spec["pivot"][1])) == Vector2(1218, 570) and Vector2(float(spec["ring"][0]), float(spec["ring"][1])) == Vector2(1112, 503),
		"G47: pivot on the crib (1218, 570), the chalk mark at the log's far end on the ring (1112, 503)")
	sr.call("_on_state_reset")
	if sr.mechanic_open:
		sr.close_mechanic()
	sr.set_frame("")
	# G52 (art pack 9): the near pier by day on days three and four — low water, first snow, the far bank in winter; the
	# second day's snow and lights layers do not cover it.
	_check(rm.start_at("freewalk"), "start: the free day")
	await _frames(2)
	sr.call("_on_state_reset")
	rm.change_room("R1", "default")
	await _frames(3)
	var r1l: Node = rm.current_room.get_node_or_null("Layers")
	_check(r1l != null and r1l.get_node("water_low_day").visible and not r1l.get_node("far_snow").visible and not r1l.get_node("far_lights").visible,
		"G52: R1 on day three — the day picture of pack 9, not the evening layers of day two")
	# G54: the date on the board of the lesson — Nina's chalk (pack 9), not the game's font.
	var dl := {}
	for l in sd.room("EP_lesson").get("layers", []):
		if String(l.get("id", "")) == "date":
			dl = l
	_check(not dl.has("text") and String(dl.get("image", "")).ends_with("date.png") and ResourceLoader.exists(String(dl.get("image", ""))),
		"G54: «16 ноября» is painted chalk on the lesson's board (%s)" % str(dl.get("image", dl.get("text", ""))))
	sr.call("_on_state_reset")
	sr.set_frame("")
	gs.reset()
	await _frames(2)
	for run in ["up", "down"]:
		gs.set_flag("span_first_laid", false)
		sr.open_mechanic(spec, "")
		await _frames(3)
		_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "windlass", "%s: the windlass close-up opens" % run)
		var p = mv.panel
		var pr: Dictionary = mv.probe().get("panel", {})
		var figs: Array = pr.get("figures", [])
		_check(figs.has("pelageya") and figs.has("agata") and figs.has("ilya"), "G42: Pelageya, Agata and Ilya are in the close-up (%s)" % str(figs))
		_check(String(pr.get("hint", "")).contains("кольцо") and String(pr.get("hint", "")).contains("отметк"), "the hint says where: «%s»" % String(pr.get("hint", "")))
		var gg: Dictionary = pr.get("gauge", {})
		var h := float(gg.get("bottom", 0)) - float(gg.get("top", 0))
		var zt := (float(gg.get("zone_top", 0)) - float(gg.get("top", 0))) / maxf(h, 1.0)
		var zb := (float(gg.get("zone_bottom", 0)) - float(gg.get("top", 0))) / maxf(h, 1.0)
		_check(h > 150.0 and absf(zt - (p.logic.rest - p.logic.tolerance)) < 0.01 and absf(zb - (p.logic.rest + p.logic.tolerance)) < 0.01,
			"the gauge's green band «у кольца» = rest ± tolerance (%.3f–%.3f vs %.3f ± %.3f, %d px)" % [zt, zb, p.logic.rest, p.logic.tolerance, int(h)])
		var rm_: Dictionary = pr.get("ring_mark", {})
		var fe: Dictionary = pr.get("far_end", {})
		var d0 := _v(rm_).distance_to(_v(fe))
		_check(d0 > 80.0, "hoisted: the far end is well away from the mark on the ring (%d px)" % int(d0))
		var rp: Dictionary = pr.get("rope", {})
		_check(not rp.is_empty() and _v(rp.get("to", {})).distance_to(_v(fe)) < 1.0, "G47: the rope from the windlass drum goes to the log's far end")
		var plz: Vector2 = _v(pr.get("plaque_lower", {}))
		var pst: Vector2 = _v(pr.get("plaque_stop", {}))
		var prs: Vector2 = _v(pr.get("plaque_raise", {}))
		# Let it down past the ring — a bump, no penalty; «Подымай» glows and Ilya says it.
		await _click(plz)
		var g := 0
		while p.logic.state != "bumped" and g < 4000:
			await process_frame
			g += 1
		await _frames(2)
		pr = mv.probe().get("panel", {})
		_check(p.logic.state == "bumped" and bool(pr.get("raise_highlight", false)), "%s: bumped — «Подымай» glows" % run)
		_check(String(pr.get("reply", "")).contains("Подымай"), "Ilya's answer says «Подымай»: «%s»" % String(pr.get("reply", "")))
		# G50: Ilya's recorded line is heard, not only read.
		_check(String(pr.get("bump_line", "")) == "ilya:E5.windlass.bump" and String(pr.get("bump_voice", "")) in ["playing", "waiting"],
			"G50: «Стукнулось о камень!» in Ilya's voice (%s → %s)" % [String(pr.get("bump_line", "")), String(pr.get("bump_voice", ""))])
		await _click(pst)
		await _click(plz)
		await _frames(3)
		pr = mv.probe().get("panel", {})
		_check(p.logic.state == "bumped" and String(pr.get("reply", "")).contains("Подымай"), "«Стой» / «Пускай» against the stone: still waits, says «Подымай» again")
		_check(not gs.has_flag("span_first_laid"), "no log on the ring after a bump")
		# The stops by real game time (×1): under load a frame at ×4 can carry the log past the zone.
		Engine.time_scale = 1.0
		await _click(prs)
		if run == "up":
			# «Стой» on the way up, in the zone.
			g = 0
			while p.logic.pos > p.logic.rest + p.logic.tolerance * 0.4 and g < 4000:
				await process_frame
				g += 1
			_check(p.logic.state == "up" and p.logic.at_ring(), "hauled up into the zone (%s %.3f)" % [p.logic.state, p.logic.pos])
			pr = mv.probe().get("panel", {})
			_check(bool(pr.get("gauge", {}).get("in_zone", false)) and float(pr.get("ring_mark", {}).get("lit", 0)) > 0.5, "in the zone: the green band and the mark light up")
			await _click(pst)
		else:
			# bump → raise → lower → stop at the ring.
			g = 0
			while p.logic.pos > p.logic.rest - p.logic.tolerance - 0.15 and g < 4000:
				await process_frame
				g += 1
			await _click(plz)
			_check(p.logic.state == "down", "«Пускай» on the way up — down again (%s)" % p.logic.state)
			g = 0
			while p.logic.pos < p.logic.rest - p.logic.tolerance * 0.4 and g < 4000:
				await process_frame
				g += 1
			await _click(pst)
		g = 0
		while not gs.has_flag("span_first_laid") and g < 2000:
			await process_frame
			g += 1
		_check(gs.has_flag("span_first_laid"), "%s: «Стой» at the ring — the log lies on the ring" % run)
		_check(absf(p.logic.angle(float(spec.get("max_deg", 9.0)))) < 0.01 and _v(p.probe().get("far_end", {})).distance_to(_v(rm_)) < 2.0,
			"%s: the far end lies on the chalk mark" % run)
		await _finish()
		if sr.mechanic_open:
			sr.close_mechanic()
		await _frames(2)
		Engine.time_scale = 4.0
	gs.reset()
	Engine.time_scale = 1.0
	_reached_end = true


## The boat along the rope from the pier where the player stands (exit «В лодку» / «К лодке»): the crossing close-up,
## pulls by mouse clicks on it (the panel's input path), then the other pier. Returns true when it got there.
func _cross_by_rope(target: String) -> bool:
	var e = rm.current_room.get_node_or_null("Exits/to_R2") if rm.current_room != null else null
	if e == null:
		_check(false, "no exit to the boat in %s" % _room())
		return false
	player.call("click_at", e.global_position)
	await _wait_idle()
	var g := 0
	while not sr.mechanic_open and g < 120:
		await process_frame
		g += 1
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "crossing", "%s → %s: the boat by the rope — the pull close-up opens (room %s)" % [_room(), target, _room()])
	if not sr.mechanic_open:
		return false
	_check(_room() != "R2", "no room with arrows on the way (the boat view R2 is the close-up)")
	var pr: Dictionary = mv.probe().get("panel", {})
	var total := int(pr.get("pulls_total", 0))
	var c := _v(pr.get("center", {}))
	# T9 (R51, Director 24.10): a repeated crossing is short — Pelageya ferries, the pulls run by themselves; one
	# click goes straight to the shore. Only the first crossing (M18p) is ten pulls by hand.
	_check(bool(pr.get("auto", false)) and total <= 6, "the free-day crossing is short and runs by itself (auto %s, %d pulls)" % [str(pr.get("auto")), total])
	await _click(c)
	g = 0
	while not bool(pr.get("auto", false)) and sr.mechanic_open and int(mv.probe().get("panel", {}).get("pulls", 0)) < total and g < 40:
		g += 1
		await _click(c)
		var w := 0
		while sr.mechanic_open and bool(mv.probe().get("panel", {}).get("pulling", false)) and w < 400:
			await process_frame
			w += 1
	g = 0
	while _room() != target and g < 600:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g += 1
	await _finish()
	return _room() == target and not sr.mechanic_open


## G43: the boat both ways by real pulls — on the free day (day three), on day four before the log and after it.
func _test_shuttle() -> void:
	Engine.time_scale = 4.0
	_check(rm.start_at("freewalk"), "start: the free day")
	await _frames(3)
	await _finish()
	_check(gs.has_flag("boat_shuttle_open"), "day three: the boat goes both ways")
	# Day three: both ways from the turn (H36: the boat is at the plate). Day four: from the far pier to the turn — the
	# first span (M25) begins on arrival there, so the turn is not left by boat before it.
	rm.change_room("Z3", "from_R1")
	await _frames(3)
	await _finish()
	_check(_room() == "Z3", "day three: at the turn, by the boat (H36)")
	_check(await _cross_by_rope("R3"), "day three: Z3 → R3 by pulls (now %s)" % _room())
	_check(await _cross_by_rope("Z3"), "day three: R3 → Z3 by pulls (now %s)" % _room())
	for f in ["done_M23a", "done_M23b", "done_M23c", "done_M23d", "done_M24", "morning_day4"]:
		gs.set_flag(f, true)
	rm.change_room("R3", "from_R2")
	await _frames(3)
	await _finish()
	_check(await _cross_by_rope("Z3") or _room() == "Z3", "day four: R3 → Z3 by pulls (now %s)" % _room())
	_check(gs.has_flag("started_M25"), "day four: at the turn the first span begins")
	_check(rm.start_at("freewalk"), "back to the free day")
	await _frames(3)
	await _finish()
	# An old save left in the boat view: the ring takes the boat on by the same pulls, the forward arrow too.
	rm.change_room("R2", "from_R1")
	await _frames(3)
	await _finish()
	var ring = _hotspot("rope")
	_check(ring != null and sr.planned_interaction(ring) == "mechanic", "R2 from the free day: a click on the ring is the crossing, not a look")
	Engine.time_scale = 1.0
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
	_check(String(ep[ep.size() - 2].get("text", "")) == "А завтра тоже можно прийти?" and String(ep[ep.size() - 2].get("speaker", "")) == "ulyana"
		and String(ep[ep.size() - 1].get("speaker", "")) == "agata", "the last lines of the game: Ulyana's question, Agata's answer (H55)")
	var has_doucheis := false
	for ln in ep:
		if String(ln.get("text", "")).begins_with("Доучись") and not ln.has("if") and not ln.has("switch"):
			has_doucheis = true
	_check(has_doucheis, "Nina's «Доучись…» is said in every epilogue")
	_check(String(ep[0].get("text", "")).contains("среда"), "the epilogue day is a Wednesday")
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
	var want := {"olkhovka": ["R3", "M18"], "day3": ["O3", "N02"], "freewalk": ["O1", "M22"], "span": ["Z3", "M24"], "epilogue": ["Z3", "M25"]}
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
	# Batch G acceptance points (Docs/ACCEPTANCE_G.md): the sluice with the lever in the bag, the plate with the brace,
	# the pier with the rope on the ring — each before its own mini-game.
	var g_points := {"wedges": ["H2", "mirror_mill", "office_mirror_clamped"], "sluice": ["M4", "key_sluice", "sluice_opened"], "plate": ["Z3", "brace_plate", "plate_braced"], "lights": ["R1", "", "far_lights_answered"]}
	for pid in g_points.keys():
		_check(rm.start_at(pid), "start point %s" % pid)
		await _frames(3)
		var w: Array = g_points[pid]
		_check(_room() == String(w[0]), "%s: room %s (%s)" % [pid, w[0], _room()])
		if String(w[1]) != "":
			_check(gs.has_item(String(w[1])), "%s: %s in the bag" % [pid, w[1]])
		_check(not gs.has_flag(String(w[2])), "%s: %s not done yet — the mini-game is ahead" % [pid, w[2]])
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
	_check(seen.any(func(x): return x.begins_with("mitya:Илья! Сестра пришла")), "Mitya knocks: %s" % str(seen))
	_check(rm.current_room.get_node("Layers/hand_min") != null, "Nina's clock is in her room")
	var night_layer = rm.current_room.get_node_or_null("Layers/night")
	_check(night_layer != null and night_layer.visible and night_layer.get_node_or_null("Image") != null, "night in mother's room: the painted night layer (O3_night, партия 8), not an engine tone")
	# M19c: the clock against the pocket watch.
	await _use("clock")
	seen = await _finish()
	_check(gs.has_flag("o3_clock_compared") and gs.has_flag("done_M19c"), "the watch against the clock → M19c: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("nina:Двадцать лет в него глядела")), "B12: Nina's twenty years at the hand mirror")
	_check(seen.any(func(x): return x.begins_with("nina:Позавчера встала ты у печи")), "C17: the wave at the stove is remembered")
	# M20 follows by itself: brother, his daughter, his wife, the night, the morning.
	seen.append_array(await _finish())
	var g := 0
	while not gs.has_flag("done_M20") and g < 400:
		seen.append_array(await _finish())
		await process_frame
		g += 1
	_check(gs.has_flag("done_M20") and gs.has_flag("met_ilya") and not gs.has_flag("morning_day3"), "M20: Ilya, Ulyana, the wife; still night: %s" % str(seen))
	# T6 (Director 24.10): the day ends with sleep — the bed at mum's (N02), «День третий», the morning.
	await _use("bed")
	g = 0
	while not gs.has_flag("done_N02") and g < 400:
		seen.append_array(await _finish())
		await process_frame
		g += 1
	_check(gs.has_flag("done_N02") and gs.has_flag("morning_day3"), "N02: the night in the old bed, then morning: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("ilya:Ты не выросла")), "Ilya: «Ты не выросла»")
	_check(gs.has_flag("wife_came"), "the wife came with the lamp: her figure is shown by wife_came (set in M20 before her line)")
	_check(gs.has_save(CP + "day3"), "checkpoint «День третий» written")
	_check(not _hotspot("ilya").visible and rm.current_room.get_node_or_null("Layers/night") != null and not rm.current_room.get_node("Layers/night").visible, "morning: the painted night (O3_night, партия 8) is off, Ilya has gone home")
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
	_check(paths_text.contains("Ещё до беды пустой стояла"), "A6: the lower street stood empty before the flood")
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
	_check(seen.any(func(x): return x.begins_with("narration:На доске Нина читает: «Мама, я иду»")), "Nina answers «Мама, я иду»")
	_check(seen.any(func(x): return x == "agata:У нас нынче двадцать пятое октября."), "A3: Agata's date")
	_check(rm.current_room.get_node("Layers/nina_answer_mama").visible and rm.current_room.get_node("Layers/nina_answer_date").visible and not rm.current_room.get_node("Layers/nina_answer_here").visible, "the answer and the common date on the board")
	_check(rm.current_room.get_node("Layers/bird_reply_boat").visible and not rm.current_room.get_node("Layers/bird_reply_scarf").visible, "Ulyana answered next to Agata's boat (G37)")
	_check(not _hotspot("nina").visible, "mother has gone to her sister's house")
	_check(gs.has_flag("boat_shuttle_open"), "F13: from the free day the boat goes both ways (boat_shuttle_open for the R3 ↔ R1 passage of block 2)")
	# The free day: through the school door — Nina in her sister's house (frames), Tikhon.
	frames_seen.clear()
	_check(await _go("H3"), "O1→H3 through the school door")
	await _finish()
	_check(await _go("H1"), "H3→H1")
	seen = await _finish()
	_check(gs.has_flag("done_M23c") and gs.has_flag("nina_visited_house"), "M23c: Nina in her sister's house: %s" % str(seen))
	_check(rm.current_room.get_node_or_null("Effects/dusk") == null, "H1 on day three: the old evening_dusk tint is replaced by the time of day")
	_check(frames_seen.has("F_gallery_nina") and frames_seen.has("F_workshop_nina") and frames_seen.has("F_mirror_empty"), "frames: gallery, workshop, the empty room in the glass: %s" % str(frames_seen))
	_check(not fv.probe().get("open", true), "the frames are cleared after the scene")
	await _use("tikhon")
	seen = await _finish(["nina"])
	_check(gs.has_flag("done_M23d") and gs.has_flag("tikhon_told_nina") and not gs.has_flag("tikhon_told_agata"), "M23d: mother tells Tikhon: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("tikhon:Значит, вечер кончился")), "«Значит, вечер кончился»")
	_check(seen.any(func(x): return x.begins_with("tikhon:Теперь тебе хозяйкой быть")), "Tikhon calls Nina «хозяйка» — sadly, about Dunya's pot (H51)")
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
	_check(seen.any(func(x): return x.begins_with("pavel:Год на гвозде рычаг провисел")) and seen.any(func(x): return x.begins_with("ilya:Мост ставить надо. Пока льдом не схватило")), "the manager, Pavel, Agata, Ilya decide the bridge")
	_check(seen.any(func(x): return x.begins_with("pavel:Обещала ты")), "Pavel remembers Agata's word (pavel_answer_promise)")
	_check(not gs.has_flag("done_M24"), "the evening waits for Tamara's letters")
	# Seams with block 2 on the free day (23.10): Pavel after the decision, Zarechye in daylight, the boat both ways.
	_check(rm.current_room.get_node_or_null("Effects/dusk") == null, "M1 on day three: no evening_dusk tint")
	_check(await _route(["M4"]), "the mill yard → the sluice (Pavel's place since M13)")
	await _use("pavel")
	seen = await _finish()
	_check(seen.any(func(x): return x.begins_with("pavel:Пока пролёты ставите, воду ниже рабочей держу")), "Pavel after the bridge decision: the pond stays low while the spans go up (%s)" % str(seen))
	# Letters: back to Olkhovka by the rope, Tamara on the street.
	_check(await _route(["M1", "Z2", "R1"]), "the mill → Zarechye → the pier")
	_check(not rm.current_room.get_node("Layers/dusk").visible, "R1 on day three: daylight — the dusk layer of day two is off")
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "Pelageya at her pier with the boat")
	await _use("pelageya")
	seen = await _finish()
	_check(seen.any(func(x): return x.begins_with("pelageya:Лодка у поворота") and x.contains("Садись, канат довезёт")), "Pelageya: the boat goes both ways now, from the turn (H36: %s)" % str(seen))
	_check(await _route(["Z3"]), "to the turn, to the boat (H36)")
	_check(rm.current_room.get_node("Layers/boat_day").visible, "H36: the boat at the plate on day three")
	_check(await _cross_by_rope("R3"), "the crossing by pulls → the far pier (G43)")
	_check((_hotspot("mitya") == null or not _hotspot("mitya").visible) and (_hotspot("pelageya") == null or not _hotspot("pelageya").visible),
		"the far pier on the free day: Mitya is on the street, Pelageya at her own pier — nobody here twice")
	_check(await _route(["O4"]), "the far pier → Olkhovka")
	await _use("tamara")
	seen = await _finish()
	_check(gs.has_flag("done_M23a") and gs.has_flag("dunya_letter_on_stove"), "M23a: a year of letters: %s" % str(seen))
	seen.append_array(await _finish())
	# H17 (Director 24.10): the last deed of the day — Agata says it is late; the day ends at the bed in the attic.
	_check(gs.has_flag("bedtime_d3_evening"), "H17: all four deeds — Agata said «пора домой, спать» (flag bedtime_d3_evening)")
	_check(not gs.has_flag("started_M24") and gs.journal_goal == sd.text("@ui.bedtime_d3_goal"), "H17: the evening waits for the bed; the journal says where it is")
	# T6 (Director 24.10): days two and three end in the bed at mum's (O3), no longer in the attic.
	_check(await _route(["O3"]), "to mum's room for the night")
	await _use("bed")
	var g2 := 0
	while not gs.has_flag("done_M24") and g2 < 200:
		seen.append_array(await _finish())
		await process_frame
		g2 += 1
	_check(gs.has_flag("done_M24") and gs.has_flag("morning_day4"), "M24: the evening of day three, then morning: %s" % str(seen))
	_check(gs.has_save(CP + "day4"), "checkpoint «День четвёртый» written")
	_check(rm.save_game(SLOT + "_d4"), "save on the morning of day four")
	_check(_room() == "O3", "morning of day four at mum's (%s)" % _room())
	# The first span.
	var gui: Node = main_node.get_node("GameUi")
	var span_alpha := {}
	var on_frame := func(f, _h):
		span_alpha[f if f != "" else "(none)"] = float(gui.call("stage_probe").get("alpha", -1.0))
	sr.frame_changed.connect(on_frame)
	# H36: the boat lands at the turn — the first span (M25) begins right there.
	_check(await _route(["O4", "R3"]) and (await _cross_by_rope("Z3") or _room() == "Z3"), "from mum's room to the far pier, across by the rope (to the turn, H36)")
	_check(_room() == "Z3", "at the turn (the boat lands there, H36)")
	# Batch 8: Z3_state_water_low_day is the whole day-3–4 state (low water AND the stone without the plate) — never stacked
	# on the dusk low water or the stone layer.
	_check(not rm.current_room.get_node("Layers/water_low").visible and rm.current_room.get_node("Layers/water_low_day").visible
		and not rm.current_room.get_node("Layers/stone_no_plate").visible and not rm.current_room.get_node("Layers/stone_no_plate_dusk").visible,
		"Z3 on day four: the drawn low water by day (batch 8), not the dusk of day two, nothing stacked under it")
	# G42: the span shot comes by a cut — the people are there at once, no black, no empty shore first.
	var fp0: Dictionary = fv.probe()
	var ly0: Dictionary = fp0.get("layers", {})
	_check(String(fp0.get("frame", "")) == "F_span" and float(gui.call("stage_probe").get("alpha", 1.0)) < 0.01 and not sr.is_staging(),
		"G42: right on entering the turn — the frame F_span, no fade (%s, alpha %.2f)" % [String(fp0.get("frame", "")), float(gui.call("stage_probe").get("alpha", 1.0))])
	_check(bool(ly0.get("ilya", false)) and bool(ly0.get("pelageya", false)) and bool(ly0.get("agata", false)), "G42: Ilya, Pelageya and Agata in the first shot (%s)" % str(ly0))
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
	# G42: the close-up closes straight onto the frame with the laid log and the three of them (a cut, no black).
	var g3_ := 0
	while sr.mechanic_open and g3_ < 600:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g3_ += 1
	await _frames(2)
	var fp1: Dictionary = fv.probe()
	var ly1: Dictionary = fp1.get("layers", {})
	_check(String(fp1.get("frame", "")) == "F_span_done" and float(gui.call("stage_probe").get("alpha", 1.0)) < 0.01,
		"G42: after the log — the frame F_span_done at once, no fade (%s, alpha %.2f)" % [String(fp1.get("frame", "")), float(gui.call("stage_probe").get("alpha", 1.0))])
	_check(bool(ly1.get("ilya", false)) and bool(ly1.get("pelageya", false)) and bool(ly1.get("agata", false)) and bool(ly1.get("beam", false)),
		"G42: the log on the pier and the three of them (%s)" % str(ly1))
	seen = await _finish(["dunya"])
	var g3 := 0
	while not gs.has_flag("done_M26") and g3 < 600:
		seen.append_array(await _finish(["dunya"]))
		await process_frame
		g3 += 1
	_check(gs.has_flag("done_M25") and gs.has_flag("beam_dunya"), "M25: the inscription «Дуня»")
	sr.frame_changed.disconnect(on_frame)
	_check(float(span_alpha.get("(none)", 1.0)) > 0.9, "G42: between the span and the epilogue the empty shore is never shown (frame cleared under black: %s)" % str(span_alpha))
	_check(gs.has_flag("done_M26") and gs.has_flag("game_finished"), "M26: the epilogue to the end: %s" % str(seen.slice(0, 8)))
	for f in ["F_span_done", "EP_tamara", "EP_boat", "EP_pavel", "EP_beam", "EP_lesson", "EP_dinner"]:
		_check(frames_seen.has(f), "epilogue shot %s (%s)" % [f, str(frames_seen)])
	_check(String(frame_titles.get("EP_lesson", "")) == sd.location_name("O1") and String(frame_titles.get("EP_tamara", "")) == sd.text("@EP.place_bridge"),
		"epilogue titles: the class, the bridge — not the turn under the frames (%s)" % str(frame_titles))
	_check(seen.size() > 1 and seen[seen.size() - 2] == "ulyana:А завтра тоже можно прийти?" and String(seen[seen.size() - 1]).begins_with("agata:Можно, Уля"),
		"the last lines: Ulyana's question, Agata's answer (H55): %s" % str(seen.slice(-2)))
	await _frames(4)
	var fp: Dictionary = fv.probe()
	_check(bool(fp.get("open", false)) and String(fp.get("frame", "")) == "EP_dinner" and bool(fp.get("hold", false)), "the last shot stays: %s" % str(fp.get("frame")))
	_check(bool(fv.probe().get("layers", {}).get("cut_dunya", false)) == false, "(dinner has no beam layer)")
	# H56: the first end plays the credits (black, thanks, author) and ends on the title; the save made now has
	# credits_seen — loading it shows «Конец» and the traces (checked in the save/load test).
	_check(String(fp.get("credits", {}).get("phase", "")) in ["black", "text", "hold"] and gs.has_flag("credits_seen"), "the credits begin: %s" % str(fp.get("credits")))
	_check(rm.save_game(SLOT + "_end"), "save after the end")
	var title: Node = main_node.get_node("Title")
	for i in 2400:
		if String(fv.probe().get("credits", {}).get("phase", "")) == "done":
			break
		await process_frame
	_check(String(fv.probe().get("credits", {}).get("phase", "")) == "done" and bool(title.call("is_open")), "after the credits — the title screen")
	title.call("close")
	await _frames(2)
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
	_check(fp.has("new_game") and String(fp.get("traces", "")).length() > 0, "the end panel with the traces and «Начать заново» (credits already seen)")
	_check(String(fp.get("credits", {}).get("phase", "")) in ["", "done"], "no credits again after the load: %s" % str(fp.get("credits")))
	_check(sr.current_beat.is_empty(), "the epilogue does not replay")
	# The held last shot belongs to the finished story: flags set without a load (the AI room check sets them room by
	# room) that undo the end take the frame away (23.10: the dinner and «Конец» stayed over every later room).
	# (In the class, where neither the span nor the epilogue can start again by itself.)
	rm.change_room("O1", "from_O2")
	await _frames(3)
	_check(bool(fv.probe().get("open", false)), "the end frame stays over a room change while the story is at its end")
	gs.set_flag("done_M26", false)
	gs.set_flag("done_M25", false)
	await _frames(3)
	_check(not fv.probe().get("open", true) and sr.active_scene == "", "the end frame goes when the story is no longer at its end")
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
		# follow-up lines (`then`): right after it, each by its own conditions (StoryRunner.start_scene)
		for t in ln.get("then", []):
			if sr.beat_allowed(t):
				out.append("%s:%s" % [String(t.get("speaker", "narrator")), String(t.get("text", ""))])
	return out


func _test_traces() -> void:
	var here := _beats_of("M22", ["board_here"])
	_check(here.any(func(x): return x.contains("Все двадцать лет")) and not here.any(func(x): return x.contains("Дождалась")), "board «Я была здесь»: «И я. Все двадцать лет. Мама»")
	var none := _beats_of("M22", [])
	_check(none.any(func(x): return x.begins_with("narrator:Доска чиста")) and not none.any(func(x): return x.contains("Нина читает")), "no inscription: only the date")
	_check(none.any(func(x): return x.contains("двадцать пятое октября")), "the common date in every branch")
	var ilya := _beats_of("M22", ["board_ilya", "v03_marked", "v03_add_boat"])
	_check(ilya.any(func(x): return x.contains("лодки с дымом")) and ilya.any(func(x): return x.begins_with("ulyana:А лодку с дымом")), "board «Илюша…» and the boat on the bird: Ulyana answers about it")
	# G37: Ulyana's words follow what Agata drew on the bird.
	for v in [["v03_add_scarf", "ulyana:А кто ей шарф"], ["v03_add_boat", "ulyana:А лодку"], ["v03_add_bridge", "ulyana:Кто мостик"]]:
		var bv := _beats_of("M22", ["v03_marked", v[0]])
		var others: int = bv.filter(func(x): return x.begins_with("ulyana:А кто ей шарф") or x.begins_with("ulyana:А лодку") or x.begins_with("ulyana:Кто мостик")).size()
		_check(bv.any(func(x): return x.begins_with(v[1])) and others == 1, "G37 %s: one reply of Ulyana, about it (%s)" % [v[0], str(bv)])
	var nob := _beats_of("M22", [])
	_check(not nob.any(func(x): return x.begins_with("ulyana:А кто ей шарф") or x.begins_with("ulyana:А лодку") or x.begins_with("ulyana:Кто мостик")), "G37: nothing drawn — no reply about it")
	var fam := _beats_of("M26", ["pavel_answer_family", "tikhon_told_agata", "v01_cup_white", "beam_blank"])
	_check(fam.any(func(x): return x.begins_with("pavel:Мать и брат")) and not fam.any(func(x): return x.begins_with("pavel:Сдержала слово")), "Pavel's epilogue line follows the answer in the office")
	_check(fam.any(func(x): return x.contains("возле Агатиной лежанки спит")) and fam.any(func(x): return x.begins_with("agata:Среда")), "told by Agata: Tikhon sleeps by her bed; Agata answers «Среда»")
	_check(fam.any(func(x): return x.contains("Белая")) and fam.any(func(x): return x.contains("Чист торец первого прогона")), "the white cup; the clean beam end")
	var prom := _beats_of("M26", ["pavel_answer_promise", "tikhon_told_nina", "q07_board_to_pelageya", "q01_mail_at_nina"])
	_check(prom.any(func(x): return x.begins_with("pavel:Сдержала слово")) and prom.any(func(x): return x.begins_with("nina:Среда, Тихон")), "promise kept; Nina answers Tikhon")
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


# --- Block 5: Q02 and Q06 (Director 23.10 11:51) ----------------------------------------------------

func _panel() -> Dictionary:
	return mv.probe().get("panel", {})


func _wait(cond: Callable, frames: int = 600) -> bool:
	var g := 0
	while not cond.call() and g < frames:
		await process_frame
		g += 1
	return cond.call()


## Waits until the «точный удар» marker is near the middle of the green (want_green) or well in the red, then clicks `at`.
func _strike_at(at: Vector2, want_green: bool) -> void:
	await _move(at)
	var g := 0
	while g < 900:
		var t: Dictionary = _panel().get("timing", {})
		if t.is_empty():
			break
		var z: Array = t.get("zone", [0.4, 0.6])
		var c := (float(z[0]) + float(z[1])) * 0.5
		var d := absf(float(t.get("pos", 0.0)) - c)
		var ok := (d < 0.03) if want_green else (d > 0.3)
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and ok:
			break
		await process_frame
		g += 1
	await _button(at, true)
	await _button(at, false)


## Presses at the first point, moves the mouse along the polyline in small steps, lets go at the end (or not).
func _drag_path(points: Array, release: bool = true) -> Vector2:
	var start := _v(points[0])
	await _move(start)
	await _button(start, true)
	var last := start
	for j in range(1, points.size()):
		var a := _v(points[j - 1])
		var b := _v(points[j])
		var steps := maxi(1, int(a.distance_to(b) / 18.0))
		for k in steps:
			last = a.lerp(b, float(k + 1) / steps)
			await _move(last)
	if release:
		await _button(last, false)
	return last


## The picture a room layer draws (its own texture or the first textured child), "" for a stand-in or text.
func _layer_tex(room: Node, id: String) -> String:
	var n: Node = null
	for box in ["Layers", "Occluders"]:
		if n == null and room != null:
			n = room.get_node_or_null(box + "/" + id)
	if n == null:
		return ""
	for c in [n] + n.find_children("*", "", true, false):
		var t = c.get("texture") if (c is Sprite2D or c is TextureRect) else null
		if t is Texture2D:
			return (t as Texture2D).resource_path.get_file()
	return ""


func _enter_with(flags: Array, room: String, spawn: String = "default") -> void:
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	rm.change_room(room, spawn)
	await _frames(3)
	await _finish()


## Batch 8 (ChatGPT 23.10, assets/incoming/_meta_p8/README_RU.md): the drawn states replace the engine's text and tones.
## Each shows in its state only; the beam end carvings and the Z3 day water are never stacked on another variant.
func _test_batch8() -> void:
	Engine.time_scale = 1.0
	# The class board: Nina's answers in chalk are pictures (not the game font), each under its question; the date; Ulyana's reply.
	for q in ["here", "mama", "ilya"]:
		await _enter_with(["done_M22", "board_" + q, "nina_answered_board", "nina_wrote_date", "v03_marked", "v03_add_bridge"], "O1", "from_O2")
		var r: Node = rm.current_room
		for o in ["here", "mama", "ilya"]:
			_check(_layer_visible(r, "nina_answer_" + o) == (o == q), "O1 board «%s»: answer %s shown %s" % [q, o, str(o == q)])
		_check(_layer_tex(r, "nina_answer_" + q) == "state_answer_%s.png" % q, "O1: Nina's answer «%s» is the chalk drawing (%s)" % [q, _layer_tex(r, "nina_answer_" + q)])
		_check(_layer_visible(r, "nina_answer_date") and _layer_tex(r, "nina_answer_date") == "state_date.png", "O1: the date in chalk")
		_check(_layer_visible(r, "bird_reply_bridge") and not _layer_visible(r, "bird_reply_boat"), "O1: Ulyana's reply by the bird — about the bridge (G37)")
		_check(not _layer_visible(r, "class_sign"), "O1: no sign in the class without Q09")
	await _enter_with(["done_M22", "q09_original_in_classroom"], "O1", "from_O2")
	_check(_layer_visible(rm.current_room, "class_sign") and _layer_tex(rm.current_room, "class_sign") == "state_sign.png", "Q09 B: the old sign hangs in the class")
	await _enter_with(["done_M22", "lower_street_returned", "q09_original_in_classroom"], "S1")
	_check(_layer_visible(rm.current_room, "sign_removed"), "Q09 B: on the lower street the sign is gone from the post")
	# Nina's coat on the hook in Dunya's house after M23c.
	await _enter_with(["house_unlocked", "done_M20"], "H1")   # (with done_M22 entering H1 plays M23c — mum comes)
	_check(not gs.has_flag("done_M23c") and not _layer_visible(rm.current_room, "nina_coat"), "H1: no coat before mum comes")
	await _enter_with(["house_unlocked", "done_M22", "done_M23c"], "H1")
	_check(_layer_visible(rm.current_room, "nina_coat") and _hotspot("nina_coat") != null and _hotspot("nina_coat").visible, "H1: mum's coat on the hook, a hotspot over it")
	# Agata's scarf hangs on the same hook (h1_scarf_removed): the coat, hung later, is drawn over it — not hidden under it.
	await _enter_with(["house_unlocked", "done_M22", "done_M23c", "h1_scarf_removed"], "H1")
	var lay_box: Node = rm.current_room.get_node("Layers")
	var coat_n: Node = lay_box.get_node_or_null("nina_coat")
	var scarf_n: Node = lay_box.get_node_or_null("hook_coat")
	_check(coat_n != null and scarf_n != null and (coat_n as CanvasItem).visible and (scarf_n as CanvasItem).visible
		and ((coat_n as CanvasItem).z_index > (scarf_n as CanvasItem).z_index
			or ((coat_n as CanvasItem).z_index == (scarf_n as CanvasItem).z_index and coat_n.get_index() > scarf_n.get_index())),
		"H1: mum's coat over Agata's scarf on the same hook")
	# The street: Tamara's bag (M23a until Q01), Mitya's board (after M22 until Q07 gives it away).
	await _enter_with(["done_M22", "done_M23a"], "O4", "from_O2")
	_check(_layer_visible(rm.current_room, "letters_bag") and _layer_visible(rm.current_room, "mitya_board"), "O4: Tamara's bag and Mitya's board drawn")
	await _enter_with(["done_M22", "done_M23a", "done_Q01", "q07_board_to_pelageya"], "O4", "from_O2")
	_check(not _layer_visible(rm.current_room, "letters_bag") and not _layer_visible(rm.current_room, "mitya_board"), "O4: after Q01 / Q07 B — the bag and the board are gone")
	# Nina's room at night: the drawn night frame with the dark time of day only.
	await _enter_with(["house_unlocked", "done_M17", "done_M18", "done_M19", "met_nina"], "O3")
	var dark: bool = gs.has_flag("tod_dark")
	_check(dark and _layer_visible(rm.current_room, "night"), "O3 in the evening of day two: the night drawing (tod_dark %s)" % str(dark))
	await _enter_with(["house_unlocked", "done_M22", "evening_dusk"], "O3")
	_check(not gs.has_flag("tod_dark") and not _layer_visible(rm.current_room, "night"), "O3 on day three: no night layer")
	# Days 3–4: the drawn day frames of the crossing and the far pier; the low water by day at the turn.
	for rid in ["R2", "R3"]:
		await _enter_with(["house_unlocked", "evening_dusk", "done_M15a", "done_M15", "done_M17"], rid)
		_check(gs.has_flag("tod_day2") and not _layer_visible(rm.current_room, "day"), "%s on the night of day two: the evening drawing (no day frame)" % rid)
		await _enter_with(["house_unlocked", "evening_dusk", "done_M18", "done_M20", "done_M22"], rid)
		_check(_layer_visible(rm.current_room, "day") and _layer_tex(rm.current_room, "day") == "day.png", "%s on day three: the day frame" % rid)
	await _enter_with(["house_unlocked", "evening_dusk", "done_M15a", "done_M20", "done_M22"], "Z3")
	var r3: Node = rm.current_room
	var stacked := ["water_low", "stone_no_plate", "stone_no_plate_dusk"].filter(func(x): return _layer_visible(r3, x))
	_check(_layer_visible(r3, "water_low_day") and stacked.is_empty(), "Z3 on day three: the low water by day alone (stacked: %s)" % str(stacked))
	# The mill board: the sheet is drawn.
	await _enter_with(["house_unlocked", "done_N01", "done_M09", "met_pavel"], "M1")
	_check(_layer_visible(rm.current_room, "schedule_sheet") and _layer_tex(rm.current_room, "schedule_sheet") == "state_schedule_sheet.png", "M1: the schedule sheet on the board")
	# Epilogues: the beam end — exactly one carving for each choice; the dinner and the lesson — drawn figures, Agata added.
	gs.reset()
	rm.change_room("Z3", "default")
	await _frames(2)
	for c in ["dunya", "roads", "date"]:
		gs.reset()
		gs.set_flag("beam_" + c, true)
		sr.set_frame("EP_beam")
		await _frames(3)
		var ly: Dictionary = fv.probe().get("layers", {})
		var on := ["dunya", "roads", "date"].filter(func(x): return bool(ly.get("cut_" + x, false)))
		_check(on == [c], "EP_beam «%s»: one carving (%s)" % [c, str(on)])
		sr.set_frame("")
		await _frames(2)
	gs.reset()
	sr.set_frame("EP_beam")
	await _frames(3)
	var none_on := (fv.probe().get("layers", {}) as Dictionary).keys().filter(func(k): return String(k).begins_with("cut_") and bool(fv.probe()["layers"][k]))
	_check(none_on.is_empty(), "EP_beam with no inscription: a clean end (%s)" % str(none_on))
	sr.set_frame("")
	await _frames(2)
	sr.set_frame("EP_dinner")
	await _frames(3)
	var dl: Dictionary = fv.probe().get("layers", {})
	_check(bool(dl.get("family", false)) and bool(dl.get("agata", false)), "EP_dinner: the drawn family at the table, Agata added by the game")
	_check(not dl.has("nina") and not dl.has("ilya") and not dl.has("ilya_wife") and not dl.has("ulyana"), "EP_dinner: no 3D composites over the drawn family (%s)" % str(dl.keys()))
	sr.set_frame("")
	await _frames(2)
	sr.set_frame("EP_lesson")
	await _frames(3)
	var ll: Dictionary = fv.probe().get("layers", {})
	_check(bool(ll.get("children", false)) and not ll.has("ulyana"), "EP_lesson: the drawn children, no 3D Ulyana over them (%s)" % str(ll.keys()))
	sr.set_frame("")
	await _frames(2)
	# Examine: the 10 items of batch 8 have their own close-up pictures.
	# (closeup_key_sluice is not wired: the sluice key becomes a lever with its own art in batch G — Director 23.10b)
	for id in ["key_house", "door_hinges", "brace_plate", "chalk", "mitten", "bell_clapper", "clamp", "school_ribbon", "journal_manager", "pocket_watch"]:
		var ex: Dictionary = (sd.items.get(id, {}) as Dictionary).get("examine", {})
		var art := String(ex.get("art", ""))
		_check(art.ends_with("closeup_%s.png" % id) and ResourceLoader.exists(art), "examine %s: the drawn close-up (%s)" % [id, art])
	gs.reset()
	_reached_end = true


func _layer_visible(room: Node, id: String) -> bool:
	for box in ["Layers", "Occluders"]:
		var n = room.get_node_or_null(box + "/" + id) if room != null else null
		if n != null:
			return (n as CanvasItem).visible
	return false


func _test_q02_q06_traces() -> void:
	# Epilogue lines by the four choices; none when skipped; the last word is still Ulyana's.
	var a := _beats_of("M26", ["q02_old_under_new", "q06_table_at_ilya"])
	_check(a.any(func(x): return x.contains("Нина детям показывает, как место менялось")) and a.any(func(x): return x.contains("Рядом сохнет их полка")), "A/A: the lesson shows the map with the tracing; the oarlock and the drying shelf")
	_check(not a.any(func(x): return x.contains("растолковывает гостю дорогу") or x.contains("рамку для семейного")), "A/A: no B lines")
	var b := _beats_of("M26", ["q02_new_primary", "q06_table_at_agata", "v01_photo_table"])
	_check(b.any(func(x): return x.contains("Ульяна по нему растолковывает гостю дорогу")) and b.any(func(x): return x.contains("Илья на втором верстаке доделывает резную рамку для семейного снимка")), "B/B: Ulyana's drawing by the door; the frame for the family photo")
	_check(b.any(func(x): return x.contains("На столике")), "B: the photo stays where it was put on day one (the frame is for it)")
	_check(not b.any(func(x): return x.contains("как место менялось") or x.contains("уключину")), "B/B: no A lines")
	_check(b[b.size() - 2] == "ulyana:А завтра тоже можно прийти?" and b[b.size() - 1].begins_with("agata:Можно, Уля"),
		"the last lines are still Ulyana's question and Agata's answer (H55): %s" % str(b.slice(-2)))
	var none := _beats_of("M26", [])
	for t in ["как место менялось", "растолковывает гостю дорогу", "уключину", "рамку для семейного"]:
		_check(not none.any(func(x): return x.contains(t)), "skipped: no «%s»" % t)
	# The stagings still come on their lines.
	var lines: Array = sd.scene("M26").get("mandatory_lines", [])
	# Q02/Q06 traces are follow-ups (`then`) of the lines before them, not lines of their own: the epilogue was voiced
	# before they came (M26_<index>), an inserted line would shift every recording after it (23.10, 40 lines).
	var own := lines.filter(func(ln): return (ln.get("if", []) as Array).any(func(f): return String(f).begins_with("q02_") or String(f).begins_with("q06_")))
	# H55 (24.10) added Agata's answer as line 37 — after every recorded position, so nothing shifted.
	_check(own.is_empty() and lines.size() == 38, "Q02/Q06 epilogue lines are follow-ups — M26 keeps its 37 voiced positions + Agata's answer (%d lines, %d own)" % [lines.size(), own.size()])
	var flat: Array = []
	for ln in lines:
		flat.append(ln)
		flat.append_array(ln.get("then", []))
	var want := {"EP_boat": "К зиме лодку Пелагея с Митей смолят", "EP_pavel": "Павел стоит у рейки", "EP_lesson": "Зимнее утро, класс", "EP_dinner": "Вечером ужинают"}
	for st in sd.scene("M26").get("stage", []):
		var f := String(st.get("frame", ""))
		if want.has(f):
			_check(String(lines[int(st.get("at", 0))].get("text", "")).begins_with(want[f]), "%s comes on «%s…»" % [f, want[f]])
	# The quests' own epilogue words are the lines of the epilogue.
	for qid in ["Q02", "Q06"]:
		for o in sd.scene(qid).get("choice", {}).get("options", []):
			var fl := String(o.get("sets", ""))
			var ep := String(o.get("epilogue", ""))
			var found := false
			for ln in flat:
				if (ln.get("if", []) as Array).has(fl) and String(ln.get("text", "")).contains(ep):
					found = true
			_check(found, "%s %s: the epilogue says «%s»" % [qid, fl, ep])
	# Frame layers by flags.
	gs.reset()
	rm.change_room("Z3", "default")
	await _frames(3)
	for case in [["EP_lesson", "lesson_map", "q02_old_under_new"], ["EP_dinner", "ulyana_map", "q02_new_primary"],
			["EP_boat", "bench", "q06_table_at_ilya"], ["EP_dinner", "photo_frame", "q06_table_at_agata"]]:
		gs.reset()
		sr.set_frame(String(case[0]))
		await _frames(3)
		_check(not bool(fv.probe().get("layers", {}).get(String(case[1]), true)), "%s: %s off without %s" % case)
		gs.set_flag(String(case[2]), true)
		await _frames(2)
		_check(bool(fv.probe().get("layers", {}).get(String(case[1]), false)), "%s: %s on with %s" % case)
		sr.set_frame("")
		await _frames(2)
	# Rooms by flags: A — the shed open on the street; B — the bench in Dunya's workshop.
	gs.reset()
	for f in ["done_M22", "met_ilya", "q06_table_at_ilya"]:
		gs.set_flag(f, true)
	rm.change_room("O4", "default")
	await _frames(3)
	await _finish()
	_check(_layer_visible(rm.current_room, "bench_shed"), "A: the shed door open with the bench on the street")
	gs.set_flag("q06_table_at_ilya", false)
	await _frames(2)
	_check(not _layer_visible(rm.current_room, "bench_shed"), "without A the shed is shut")
	# The end panel names them.
	gs.reset()
	gs.set_flag("done_Q02", true)
	gs.set_flag("done_Q06", true)
	var titles := []
	for t in fv.call("achieved"):
		titles.append(String(t.get("id", "")))
	_check(titles.has("q02") and titles.has("q06"), "«Что осталось от твоих выборов»: Q02 and Q06 (%s)" % str(titles))
	# Skipped: the epilogue plays to its end without them.
	gs.reset()
	_check(rm.start_at("epilogue"), "start: the epilogue without Q02/Q06")
	await _frames(3)
	Engine.time_scale = 4.0
	var seen := await _finish()
	Engine.time_scale = 1.0
	_check(gs.has_flag("done_M26") and not gs.has_flag("done_Q02") and not gs.has_flag("done_Q06"), "skipped: the game ends as before")
	_check(not seen.any(func(x): return x.contains("как место менялось") or x.contains("уключину") or x.contains("рамку для семейного") or x.contains("растолковывает гостю дорогу")), "skipped: no trace lines")
	sr.set_frame("")
	gs.reset()
	_reached_end = true
