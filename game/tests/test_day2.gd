extends SceneTree
## Headless tests of day two (E2–E3, Docs/SCENARIO_FINAL.md §7, block 2). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_day2.gd
## What the coordinator asked to prove (block 2 brief):
##   - the hook puzzle is solved and slips back to the top without any penalty;
##   - the sluice does not open all at once (one notch at a time, wait for the gauge);
##   - the office mirror shows Pavel's light in the same frame as the bell strike;
##   - time in mother's mirror is exactly 20:1 (1:1 once the road is held from both ends);
##   - the ribbon is given once (scene, save/load, talking again);
##   - a save in the middle of day two and its load replay no one-time event and block nothing;
##   - the whole day two plays through by script, from the morning by the stove to the far pier (R3).
## The close-ups are driven with real mouse events (Input.parse_input_event), as a player would.
## Exit code 0 only when every check passed.

const AUTOSAVE := "test_day2_auto"
## Items used up on day one (the key in the lock, the hinges on the door, the chalk at the board, the mitten
## on the step); the rest of day one's bag goes into day two.
const DAY_ONE_SPENT := ["key_house", "door_hinges", "chalk", "mitten"]
var MID_SLOT := "test_day2_mid_%d" % OS.get_process_id()
var SLUICE_SLOT := "test_day2_sluice_%d" % OS.get_process_id()

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node = null
var mv: Node = null      # MechanicView
var player: Node2D = null
var _results: Array = []
var _fails: Array[String] = []
var _reached_end: bool = false   # a test that stops on a script error never reaches its end: FAIL, not PASS


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
	await _test("Logic: bell signals (one / two / long) from presses and pauses", _test_bell_logic)
	await _test("Logic: hook — slips and comes back to the top without penalty, then lifts the bar", _test_hook_logic)
	await _test("Logic: sluice — one notch at a time, the next only after the gauge settles", _test_sluice_logic)
	await _test("Logic: mother's mirror — Nina's clock runs exactly 20× Agata's watch; 1× once the road is held", _test_clock_logic)
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_slot = AUTOSAVE
	mv = main_node.get_node("MechanicView")
	player = main_node.get_node("World/Player")
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	await _test("Data: day-two rooms, scenes, texts — no echo chain left, goals without codes", _test_data)
	await _test("Whereabouts: on day one Pavel sends Agata home till morning; in the evening Pelageya waits at the turn, not at the pier", _test_whereabouts)
	await _test("The brace: taken on day one or day two, never twice; forgotten — at the plate Agata remembers it and goes back", _test_brace_paths)
	await _test("Whole day two by script: morning → mill → mirror and bell → office → sluice → mother's mirror → plate → three lights → ribbon → R3", _test_walkthrough)
	await _test("Office mirror by mouse: wedges, the light in the same frame as the strike, the hook by bell signals", _test_office_mirror_mouse)
	await _test("Sluice by mouse: a drag past two notches opens one; the next is refused until the water settles", _test_sluice_mouse)
	await _test("Mother's mirror on screen: 20:1 over real frames, poses change, knock, compare", _test_fast_mirror_panel)
	await _test("Save in the middle of day two: load replays nothing, the sluice keeps its notches, the day goes on", _test_save_load)
	gs.reset()
	for s in [AUTOSAVE, MID_SLOT, SLUICE_SLOT]:
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
	print("==== day2: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


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


func _drag(from: Vector2, to: Vector2, steps: int = 8) -> void:
	await _move(from)
	await _button(from, true)
	for k in range(1, steps + 1):
		await _move(from.lerp(to, float(k) / steps))
	await _button(to, false)


func _v(d) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0))) if d is Dictionary else Vector2.ZERO


func _panel() -> Dictionary:
	return mv.probe().get("panel", {})


## Advance every text on screen (options: first, or the given ids in turn).
func _finish(choices: Array = []) -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	await _staging_done()
	while not sr.current_beat.is_empty() and guard < 200:
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
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", "")).left(40)])
			sr.advance()
		await process_frame
		await _staging_done()
	await _frames(2)
	return seen


## The close-up of `type` opens (a text before it is read through).
func _wait_mechanic(type: String) -> void:
	var g := 0
	while not (sr.mechanic_open and String(mv.spec.get("type", "")) == type) and g < 120:
		if not sr.current_beat.is_empty() and not sr.mechanic_open:
			print("    (text before the close-up: %s)" % str(sr.current_beat.get("text", "")).left(60))
			sr.advance()
		await process_frame
		g += 1


## A scene staging (fade with sounds, block 1's `stage`) holds the beats: wait for it.
func _staging_done() -> void:
	var g := 0
	while sr.is_staging() and g < 2000:
		await process_frame
		g += 1


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


## Walk to a hotspot and click it (the game's own path: Room.pick → walk → trigger).
func _use(id: String) -> bool:
	var h := _hotspot(id)
	if h == null or not h.visible:
		_check(false, "hotspot %s missing or hidden in %s" % [id, _room()])
		return false
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


## Every visible hotspot of the room is picked at the centre of its own rect: a bigger rect with a higher
## pick_priority over it would steal the click (the stand «ЗМ» enlarged over Nina's bundle, 22.10).
func _check_picks(where: String) -> void:
	await physics_frame
	await physics_frame
	for h in rm.current_room.get_hotspots():
		if not h.visible or not h.has_method("is_active") or not h.call("is_active"):
			continue
		var got = rm.current_room.pick(h.global_position)
		var got_id := String(got.get("hotspot_id")) if got != null and got.get("hotspot_id") != null else str(got)
		_check(got == h, "%s: a click at the centre of %s picks %s" % [where, String(h.get("hotspot_id")), got_id])


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


## End of day one: every E0–E1 main scene done with its grants (what block 1 leaves: the night by the stove
## and the save «День второй»), the inventory as after day one, Agata in H1.
func _day_one_done(with_night: bool = true) -> void:
	gs.reset()
	await _frames(1)
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if int(sc.get("episode", -1)) > 1 or String(sc.get("type", "")) == "quest":
			continue
		if not with_night and id == "N01":
			continue
		gs.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for it in sc.get("grants", {}).get("items", []):
			gs.set_flag("has_" + String(it), true)
			var meta: Dictionary = sd.item(String(it))
			if bool(meta.get("inventory", false)) and not DAY_ONE_SPENT.has(String(it)):
				gs.add_item(String(it))
	# The house key went into the lock (exit item_use): its flags, not the key.
	gs.set_flag("house_unlocked", true)
	# What day two needs (M09 requires: the night by the stove of block 1, whose morning ends day one).
	if with_night:
		for f in sd.scene("M09").get("requires", {}).get("flags", []):
			gs.set_flag(String(f), true)


# --- Logic -------------------------------------------------------------------------------

func _test_bell_logic() -> void:
	var b := BellSignal.new({"long_s": 0.6, "gap_s": 0.55})
	b.press(0.0)
	_check(b.release(0.1).is_empty(), "a strike alone is not decided at once")
	_check(b.tick(0.4).is_empty(), "inside the pause still undecided")
	_check(b.tick(0.7) == ["one"], "one strike and a pause → one")
	b.press(1.0)
	b.release(1.1)
	b.press(1.3)
	_check(b.release(1.4) == ["two"], "two strikes close together → two (decided at the second)")
	_check(b.tick(3.0).is_empty(), "nothing more after two")
	b.press(4.0)
	_check(b.tick(4.3).is_empty(), "held 0.3 s — not yet long")
	_check(b.tick(4.65) == ["long"], "held past 0.6 s → long while still held")
	_check(b.release(5.0).is_empty(), "release after long adds nothing")
	_check(b.tick(6.0).is_empty(), "long leaves no strike behind")
	_reached_end = true


func _test_hook_logic() -> void:
	var h := HookPuzzle.new({"bar": 0.5, "tolerance": 0.06, "speed": 0.1, "return_speed": 0.6})
	var events: Array[String] = []
	h.event.connect(func(n): events.append(n))
	_check(h.state == "wait" and h.pos == 0.0, "the hook starts at the top, waiting")
	h.apply("two")
	_check(h.state == "wait", "stop before go does nothing")
	h.apply("one")
	_check(h.state == "down", "one → down")
	for i in 70:
		h.step(0.1)
	_check(h.pos > 0.56 and h.state == "down", "after 7 s it is past the bar (%.2f)" % h.pos)
	h.apply("long")
	_check(h.state == "lift_empty", "lift away from the bar → empty")
	for i in 10:
		h.step(0.1)
	_check("slipped" in events and h.state == "slipping", "the empty hook slips off")
	for i in 30:
		h.step(0.1)
	_check(h.state == "wait" and h.pos == 0.0 and "returned" in events, "Pavel brings it back to the top (%s %.2f)" % [h.state, h.pos])
	_check(not h.solved(), "no bar out after a slip")
	# Down to the bottom: slips too, back to the top — still no penalty.
	h.apply("one")
	for i in 120:
		h.step(0.1)
	_check(h.state == "wait" and h.pos == 0.0, "past the bottom of the gap: slips and comes back up")
	# Now right: go, stop at the bar, lift.
	h.apply("one")
	while h.pos < 0.49:
		h.step(0.05)
	h.apply("two")
	_check(h.state == "stopped" and h.at_bar(), "stopped at the bar (%.2f)" % h.pos)
	h.step(1.0)
	_check(h.state == "stopped", "a stopped hook stays")
	h.apply("long")
	_check(h.state == "lift_bar", "lift at the bar → takes the bar")
	for i in 12:
		h.step(0.1)
	_check(h.solved() and "solved" in events, "the bar is out of the brackets")
	_reached_end = true


func _test_sluice_logic() -> void:
	var s := SluiceLogic.new({"levels": [1.0, 0.7, 0.42, 0.15], "fall_per_s": 0.07})
	_check(s.notch == 0 and s.settled(), "closed and settled at the start")
	_check(s.open_next() == "ok" and s.notch == 1, "first notch opens")
	_check(s.open_next() == "wait" and s.notch == 1, "the next notch at once is refused (Pavel holds the winch)")
	for i in 20:
		s.step(0.1)
	_check(not s.settled() and s.open_next() == "wait", "2 s later the water is still falling — still refused")
	for i in 30:
		s.step(0.1)
	_check(s.settled() and s.open_next() == "ok" and s.notch == 2, "once settled — the next notch")
	for i in 60:
		s.step(0.1)
	s.open_next()
	for i in 60:
		s.step(0.1)
	_check(s.finished() and s.open_next() == "done", "all notches open and settled")
	var r := SluiceLogic.new({"levels": [1.0, 0.7, 0.42, 0.15]}, 2)
	_check(r.notch == 2 and r.settled(), "reopened at a saved notch: water settled at that level")
	_reached_end = true


func _test_clock_logic() -> void:
	var c := FastClock.new(20.0, 1120.0)
	var dts := [0.016, 0.017, 0.033, 0.5, 1.0, 0.0166667, 3.25]
	var total := 0.0
	for d in dts:
		c.advance(d)
		total += d
	_check(is_equal_approx(c.nina_elapsed_minutes() * 60.0, total * 20.0), "Nina's seconds = 20 × Agata's (%.6f vs %.6f)" % [c.nina_elapsed_minutes() * 60.0, total * 20.0])
	var c2 := FastClock.new(20.0, 0.0)
	c2.advance(180.0)
	_check(is_equal_approx(c2.nina_elapsed_minutes(), 60.0) and is_equal_approx(fmod(c2.minute_hand_deg(), 360.0), 0.0),
		"three of Agata's minutes — the minute hand goes once round (an hour)")
	c2.advance(60.0)
	_check(is_equal_approx(c2.nina_elapsed_minutes(), 80.0), "a minute here — twenty there")
	var c3 := FastClock.new(1.0, 0.0)
	c3.advance(60.0)
	_check(is_equal_approx(c3.nina_elapsed_minutes(), 1.0), "common time: a minute is a minute")
	var poses := [{"id": "a", "minutes": 10}, {"id": "b", "minutes": 5}]
	_check(FastClock.pose_at(poses, 3.0).get("id") == "a" and FastClock.pose_at(poses, 12.0).get("id") == "b" and FastClock.pose_at(poses, 16.0).get("id") == "a", "poses cycle in Nina's minutes")
	_check(FastClock.candle_left(0.0, 120.0) == 1.0 and FastClock.candle_left(60.0, 120.0) < 0.7, "the candle burns down")
	_reached_end = true


# --- Data --------------------------------------------------------------------------------

func _test_data() -> void:
	for id in ["M09", "M09s", "M09b", "M10", "M11", "M12", "M13a", "M13", "M14", "M15a", "M15s", "M15", "M16", "M17", "M18p", "M18"]:
		var sc: Dictionary = sd.scene(id)
		_check(not sc.is_empty(), "scene %s missing" % id)
		_check(String(sc.get("goal", "")) != "", "%s: a goal for the journal" % id)
	for id in ["V04", "V05", "UTRO2"]:
		_check(sd.scene(id).is_empty(), "%s is gone (old echo / Pavel's guilt chain; the morning is the end of N01)" % id)
	# The morning of day two is the end of block 1's night (N01): Tikhon's line after the morning fade, before the
	# checkpoint «День второй» — a scene starting after the checkpoint replayed on loading it (defect 22.10).
	var night: Dictionary = sd.scene("N01")
	var nl: Array = night.get("mandatory_lines", [])
	_check(String(nl[nl.size() - 1].get("speaker", "")) == "tikhon" and String(nl[nl.size() - 1].get("text", "")).begins_with("Колокол не трогай до обеда"), "N01 ends with Tikhon's morning line")
	var morning_at := -1
	for st in night.get("stage", []):
		if float(st.get("dim", -1.0)) == 0.0:
			morning_at = int(st.get("at", -1)) if typeof(st.get("at")) != TYPE_STRING else -1
	_check(morning_at == nl.size() - 1, "the morning fade comes right before Tikhon's morning line (at %d)" % morning_at)
	_check(sd.scene("M09").get("requires", {}).get("flags", []).has("done_N01"), "M09 waits for the night by the stove")
	var all_text := ""
	for f in ["E2.json", "E3.json"]:
		all_text += FileAccess.get_file_as_string("res://data/story/scenes/" + f)
	all_text += FileAccess.get_file_as_string("res://data/story/text/ru_E2_E3.json")
	for word in ["эхо", "Эхо", "наряд", "накладн", "оттиск", "рейс"]:
		_check(not all_text.contains(word), "day two still mentions «%s»" % word)
	for rid in ["M1", "M2", "M3", "M4", "R2", "R3"]:
		_check(sd.in_scope(rid), "%s in scope" % rid)
	# Every scene of day two is started by its rooms' data (talk / complete_when / enter), never by a bare entry
	# (defect 22.10: a room's `scenes` map written into talk.scenes left M16 undeclared — it started on entering R1).
	for id in ["M09", "M09s", "M09b", "M10", "M11", "M12", "M13a", "M13", "M14", "M15a", "M15s", "M15", "M16", "M17", "M18p", "M18"]:
		_check(not sd.scene_trigger_rooms(id).is_empty(), "%s: declared in one of its rooms (trigger or complete_when)" % id)
	_check(not sd.text("@M1.schedule.label").begins_with("[") and not sd.text("@H2d.office_mirror.title").begins_with("["), "texts of ru_E2_E3.json are loaded (a second text file)")
	var ratio := 0.0
	for h in sd.room("H2").get("hotspots", []):
		if String(h.get("mechanic", {}).get("type", "")) == "fast_mirror":
			ratio = float(h["mechanic"].get("ratio", 0))
	_check(ratio == 20.0, "mother's mirror ratio is 20 in data (%s)" % ratio)
	_reached_end = true


# --- Whereabouts ------------------------------------------------------------------------

func _test_whereabouts() -> void:
	await _day_one_done()
	# The night of day one (and its morning) is what opens day two; without it Pavel waits.
	var night: Array = sd.scene("M09").get("requires", {}).get("flags", [])
	for f in night:
		gs.set_flag(String(f), false)
	rm.change_room("M1", "default")
	await _frames(3)
	await _finish()
	await _use("pavel")
	var b: Dictionary = sr.current_beat
	_check(not gs.has_flag("started_M09"), "no day-two talk with Pavel before the morning")
	_check(String(b.get("text_key", "")) == "M1.pavel.day1" and String(b.get("speaker", "")) == "pavel", "Pavel: come in the morning (%s)" % str(b))
	await _finish()
	# Evening of day two: Pelageya at the turn with the boat until the rope is on the plate.
	await _day_one_done()
	for f in ["done_N01", "evening_dusk"]:
		gs.set_flag(f, true)
	rm.change_room("R1", "default")
	await _frames(3)
	await _finish()
	_check(_hotspot("pelageya") != null and not _hotspot("pelageya").visible, "evening, rope not on the plate: Pelageya is not at the pier")
	rm.change_room("Z3", "default")
	await _frames(3)
	await _finish()
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "evening: Pelageya at the turn")
	gs.set_flag("done_M15", true)
	await _frames(2)
	_check(not _hotspot("pelageya").visible, "after the knot she leaves the turn")
	rm.change_room("R1", "default")
	await _frames(3)
	await _finish()
	_check(_hotspot("pelageya").visible, "…and is back at the pier for the three lights")
	_reached_end = true


# --- The brace ---------------------------------------------------------------------------

func _test_brace_paths() -> void:
	await _day_one_done()
	# Day one, after the school plan: the brace from Dunya's bench (block 1's hotspot), once.
	rm.change_room("H2", "default")
	await _frames(3)
	await _finish()
	await _use("brace")
	await _finish()
	_check(gs.inventory.count("brace_plate") == 1, "the brace taken (%s)" % str(gs.inventory))
	_check(_hotspot("brace") == null or not _hotspot("brace").visible, "the bench has no second brace")
	# Mother's mirror (M15а) gives nothing of the kind.
	for f in ["done_N01", "done_M09", "done_M09s", "done_M09b", "done_M10", "done_M11", "done_M12", "done_M13a", "done_M13", "done_M14", "pond_lowered", "sluice_opened", "nina_mirror_clamped", "nina_time_compared"]:
		gs.set_flag(f, true)
	await _frames(3)
	await _finish()
	_check(gs.has_flag("done_M15a") and gs.inventory.count("brace_plate") == 1, "M15а done, the brace still once")
	# Forgotten: no brace in the bag at the plate.
	gs.remove_item("brace_plate")
	rm.change_room("Z3", "default")
	await _frames(3)
	await _finish()
	await _use("pier_plate")
	var b: Dictionary = sr.current_beat
	_check(not sr.mechanic_open, "without the brace the plate close-up does not open")
	_check(String(b.get("text_key", "")) == "Z3d.plate_dry.no_skoba" and String(b.get("speaker", "")) == "agata", "Agata remembers the brace on Dunya's bench (%s)" % str(b))
	await _finish()
	gs.add_item("brace_plate")
	await _use("pier_plate")
	b = sr.current_beat
	_check(String(b.get("text_key", "")) == "Z3d.plate_dry.use_skoba", "with the brace in the bag: put it on the crack (%s)" % str(b))
	await _finish()
	await _use_item("brace_plate", "pier_plate")
	await _wait_mechanic("plate")
	_check(sr.mechanic_open and not gs.has_item("brace_plate") and gs.has_flag("skoba_on_plate"), "the brace on the crack: out of the bag, the close-up open")
	sr.close_mechanic()
	await _frames(2)
	_check(not gs.has_item("brace_plate"), "the brace stays on the plate")
	_reached_end = true


# --- Walkthrough -------------------------------------------------------------------------

func _test_walkthrough() -> void:
	rm.autosave_enabled = true
	Engine.time_scale = 4.0
	# Day one ends at the school; back through the school door into the gallery: the night by the stove
	# (block 1's N01: fade, H1, morning with Tikhon's line, the save «День второй»).
	await _day_one_done(false)
	rm.change_room("H3", "default")
	await _frames(3)
	var seen := await _finish()
	var g0 := 0
	while not gs.has_flag("done_N01") and g0 < 600:
		seen.append_array(await _finish())
		await process_frame
		g0 += 1
	await _finish()
	_check(gs.has_flag("done_N01") and gs.has_flag("night_day1"), "the night by the stove: %s" % str(seen))
	_check(_room() == "H1", "morning in the living room (%s)" % _room())
	_check(seen.any(func(x): return x.begins_with("tikhon:Колокол не трогай до обеда")), "Tikhon's morning line: %s" % str(seen))
	_check(sr.journal_goal() == String(sd.scene("N01")["goal"]), "journal: the goal from yesterday — the mill, the sluice key")
	_check(sr.current_beat.is_empty() and not sr.is_staging(), "after the morning nothing else plays by itself")
	# To the mill: H1 → Z2 → M1.
	_check(await _go("Z2"), "H1→Z2")
	_check(await _go("M1"), "Z2→M1 (the mill yard is built)")
	var pv: Node = rm.current_room.get_node_or_null("npc_pavel")
	_check(pv != null and pv.get("sprite") != null and pv.get("sprite").sprite_frames != null,
		"Pavel is a 3D figure (sheets from the pipeline), not the flat front")
	await _use("pavel")
	seen = await _finish()
	_check(gs.has_flag("done_M09") and gs.has_flag("met_pavel"), "M09 with Pavel: %s" % str(seen))
	await _use("pavel")
	seen = await _finish()
	_check(not gs.has_flag("done_M09b"), "the agreement waits until Agata has looked round")
	await _use("schedule")
	await _finish()
	_check(await _go("M2"), "M1→M2")
	await _use("office_door")
	await _finish()
	await _use("photo")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "photo", "the photo opens as a close-up")
	await _finish()
	sr.close_mechanic()
	await _frames(2)
	seen = await _finish()
	_check(gs.has_flag("done_M09s"), "M09s after the door, the photo and the schedule: %s" % str(seen))
	_check(not (await _go("M3")), "the office door stays shut")
	await _finish()
	_check(await _go("M1"), "M2→M1")
	await _use("pavel")
	seen = await _finish()
	_check(gs.has_flag("done_M09b") and gs.has_item("mirror_mill"), "Pavel gives the office mirror: %s" % str(gs.inventory))
	_check(sr.journal_goal().contains("стойку"), "goal: the mirror onto the stand")
	# Home: the stand, the wedges, the clapper, the lantern, the hook.
	_check(await _go("Z2"), "M1→Z2")
	_check(await _go("H1"), "Z2→H1")
	await _finish()
	_check(sr.journal_goal().contains("мастерская"), "the goal names the room of the stand: %s" % sr.journal_goal())
	# The mirror tried on a wrong place in the house says where the stand is (Director 23:53).
	_check(sr.item_refusal("mirror_mill") == "@item.mirror_mill.wrong", "in H1 the office mirror points to the stand «ЗМ»")
	_check(await _go("H2"), "H1→H2")
	seen = await _finish()
	_check(gs.has_flag("h2_saw_stand_zm") and seen.any(func(t): return t.contains("на левом верстак")),
			"entering the workshop with the office mirror: Agata names the stand on the left bench: %s" % str(seen))
	await _check_picks("H2 with the office mirror")
	await _use_item("mirror_mill", "tall_frame")
	seen = await _finish()
	_check(gs.has_item("mirror_mill") and seen.any(func(t): return t.contains("Не та рама")),
			"the tall carved frame points to the left bench: %s" % str(seen))
	await _use_item("mirror_mill", "clapper_box")
	seen = await _finish()
	_check(gs.has_item("mirror_mill") and seen.any(func(t): return t.contains("нужна тётина стойка")),
			"the office mirror on another thing in the workshop says where the stand is: %s" % str(seen))
	_check(await _go("H1"), "H2→H1 (the stand thought is said once)")
	await _finish()
	_check(await _go("H2"), "H1→H2 again")
	seen = await _finish()
	_check(not seen.any(func(t): return t.contains("на левом верстак")), "the stand thought is not repeated: %s" % str(seen))
	await _use_item("mirror_mill", "stand_zm")
	await _frames(2)
	_check(not gs.has_item("mirror_mill") and gs.has_flag("office_mirror_mounted"), "the mirror goes onto the stand (out of the bag)")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "office_mirror", "the office mirror close-up opens")
	await _finish()
	var p = mv.panel
	for w in _panel().get("wedges", []):
		await _click(_v(w))
	await _frames(2)
	seen = await _finish()
	_check(gs.has_flag("office_mirror_clamped") and gs.has_flag("done_M10"), "two wedges clamp the frame → M10: %s" % str(seen))
	await _click(_v(_panel().get("bell", {})))
	await _finish()
	_check(not gs.has_flag("lantern_check_seen"), "without the clapper the bell is mute")
	sr.close_mechanic()
	await _frames(2)
	await _use("clapper_box")
	await _finish()
	_check(gs.has_item("bell_clapper"), "the clapper from its box")
	await _use_item("bell_clapper", "bell")
	await _finish()
	_check(gs.has_flag("bell_clapper_hung") and not gs.has_item("bell_clapper"), "the clapper hung on the bell")
	await _use("bell")
	await _frames(2)
	_check(sr.mechanic_open, "the bell opens the same close-up (ring while watching the glass)")
	await _finish()
	p = mv.panel
	var bell := _v(_panel().get("bell", {}))
	await _move(bell)
	await _button(bell, true)
	await _button(bell, false)
	seen = await _finish()
	_check(gs.has_flag("lantern_check_seen") and gs.has_flag("done_M11"), "one strike — the light — M11: %s" % str(seen))
	# The hook: go, stop at the bar, lift.
	await _ring(bell, 1)
	var guard := 0
	while p.hook.pos < p.hook.bar - 0.02 and guard < 600:
		await process_frame
		guard += 1
	await _ring(bell, 2)
	_check(p.hook.state == "stopped" and p.hook.at_bar(), "stopped at the bar by two strikes (%s %.2f)" % [p.hook.state, p.hook.pos])
	await _ring_long(bell)
	guard = 0
	while not gs.has_flag("office_unbolted") and guard < 600:
		await process_frame
		guard += 1
	seen = await _finish()
	_check(gs.has_flag("office_unbolted") and gs.has_flag("done_M12"), "long ring lifts the bar → M12: %s" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(MID_SLOT), "save in the middle of day two (after the bar)")
	# Back to the mill: the shelf, the office.
	_check(await _go("H1"), "H2→H1")
	_check(await _go("Z2"), "H1→Z2")
	_check(await _go("M1"), "Z2→M1")
	_check(await _go("M2"), "M1→M2")
	_check(_hotspot("pavel") != null and _hotspot("pavel").visible, "Pavel waits at the office door")
	await _use("office_door_open")
	seen = await _finish()
	_check(gs.has_flag("office_shelf_lifted") and gs.has_flag("done_M13a"), "the shelf lifted together: %s" % str(seen))
	_check(await _go("M3"), "M2→M3 (the office)")
	await _use("key_nail")
	await _finish()
	await _use("journal")
	await _finish()
	await _use("clamp")
	seen = await _finish(["promise"])
	_check(gs.has_item("key_sluice") and gs.has_item("journal_manager") and gs.has_item("clamp"), "key, journal, clamp: %s" % str(gs.inventory))
	_check(gs.has_flag("done_M13") and gs.has_flag("pavel_answer_promise") and not gs.has_flag("pavel_answer_family"), "M13 with the answer to Pavel: %s" % str(seen))
	# The sluice.
	_check(await _go("M2"), "M3→M2")
	_check(await _go("M1"), "M2→M1")
	_check(await _go("M4"), "M1→M4")
	await _use("gate")
	await _finish()
	_check(not sr.mechanic_open, "without the key the gate does not open")
	await _use_item("key_sluice", "gate")
	await _frames(2)
	_check(sr.mechanic_open and not gs.has_item("key_sluice") and gs.has_flag("sluice_key_inserted"), "the key in the winch opens the sluice close-up")
	await _finish()
	p = mv.panel
	guard = 0
	while not gs.has_flag("sluice_opened") and guard < 30:
		guard += 1
		while is_instance_valid(p) and not p.logic.settled() and not gs.has_flag("sluice_opened"):
			await process_frame
		if gs.has_flag("sluice_opened") or not is_instance_valid(p):
			break
		p.try_open()
		await _finish()
		await _frames(2)
	await _frames(2)
	seen = await _finish()
	_check(gs.has_flag("sluice_opened") and gs.has_flag("pond_lowered") and gs.has_flag("done_M14"), "the sluice opened notch by notch → M14: %s" % str(seen))
	_check(sr.journal_goal().contains("струбцин"), "goal: the clamp to mother's mirror")
	# Mother's mirror.
	_check(await _go("M1"), "M4→M1")
	var wheel = rm.current_room.get_node_or_null("Layers/wheel")
	_check(wheel != null and not wheel.is_spinning(), "the wheel stands while the pond is let down")
	_check(await _go("Z2"), "M1→Z2")
	_check(await _go("H1"), "Z2→H1")
	await _finish()
	_check(await _go("H2"), "H1→H2")
	# The brace: Dunya's bench, once the school plan is known (block 1: hotspot brace) — taken now if not on day one.
	_check(rm.current_room.get_node_or_null("Layers/office_mirror") != null and rm.current_room.get_node("Layers/office_mirror").visible,
		"the office mirror stays in Dunya's stand on the bench (batch 3 layer)")
	if not gs.has_flag("has_brace_plate"):
		# Batch 3: the office mirror's stand stands where the brace lay — the brace lies on the stool, still takeable.
		_check(not _hotspot("brace").visible and _hotspot("brace_stool").visible and rm.current_room.get_node("Layers/skoba_stool").visible
			and not rm.current_room.get_node("Layers/skoba").visible, "the brace (with the plate drawing) on the stool while the mirror stands on its place")
		await _use("brace_stool")
		await _finish()
		_check(not _hotspot("brace_stool").visible and not rm.current_room.get_node("Layers/skoba_stool").visible, "taken from the stool — gone from it")
	_check(gs.inventory.count("brace_plate") == 1, "the brace is in the bag before the turn, once")
	await _use_item("clamp", "bundle_nina")
	await _frames(2)
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "fast_mirror" and not gs.has_item("clamp"), "the clamp on the frame opens mother's mirror")
	await _finish()
	p = mv.panel
	await _click(_v(_panel().get("watch", {})))
	await _finish()
	_check(not gs.has_flag("nina_time_compared"), "too early to compare")
	while p.fclock.real_s < 16.0:
		await process_frame
	await _click(_v(_panel().get("watch", {})))
	seen = await _finish()
	_check(gs.has_flag("nina_time_compared") and gs.has_flag("done_M15a") and gs.has_flag("evening_dusk"), "compare → M15а, dusk: %s" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	# The plate.
	_check(await _go("H1"), "H2→H1")
	_check(await _go("Z2"), "H1→Z2")
	_check(await _go("Z3"), "Z2→Z3")
	_check(_hotspot("pier_plate") != null and _hotspot("pier_plate").visible and not _hotspot("old_pier_base").visible, "the plate of the pier above the water")
	_check(rm.current_room.get_node("Layers/water_low").visible and not _hotspot("plate").visible, "batch 3: the water let down at dusk (layer); the shore stone has no label in the evening")
	# Batch 7: the shore stone never carries the plate (it is on the pier under water) — over the dusk layer too.
	var lz: Node = rm.current_room.get_node("Layers")
	_check(lz.get_node("stone_no_plate_dusk").visible and not lz.get_node("stone_no_plate").visible
		and lz.get_node("stone_no_plate_dusk").get_index() > lz.get_node("water_low").get_index(),
		"the stone without the plate is drawn over the evening water layer")
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "Pelageya at the turn with the boat")
	await _use_item("brace_plate", "pier_plate")
	await _frames(2)
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "plate", "the brace on the crack opens the plate close-up")
	await _finish()
	for i in 3:
		await _click(_v(_panel().get("skoba", {})))
	seen = await _finish()
	_check(gs.has_flag("plate_braced") and gs.has_flag("done_M15s") and gs.has_flag("rope_brought"), "three blows → M15s, rope brought: %s" % str(seen))
	await _frames(2)
	await _drag(_v(_panel().get("rope_end", {})), _v(_panel().get("ring", {})))
	await _finish()
	_check(bool(_panel().get("rope_on_ring", false)), "the rope end at the ring")
	var marks: Array = _panel().get("knot", [])
	await _click(_v(marks[1]))
	await _finish()
	_check(int(_panel().get("knot_step", -1)) == 0 and int(_panel().get("knot_errors", 0)) == 1, "a wrong move — shown again, no penalty")
	for m in marks:
		await _click(_v(m))
	seen = await _finish()
	_check(gs.has_flag("rope_on_ring") and gs.has_flag("done_M15"), "the knot → M15: %s" % str(seen))
	if sr.mechanic_open:
		sr.close_mechanic()
		await _frames(2)
	# Three lights.
	_check(await _go("R1"), "Z3→R1")
	_check(not gs.has_flag("started_M16") and sr.current_beat.is_empty(), "nothing starts by itself at the pier: the lights are the player's")
	_check(_hotspot("pelageya").visible, "Pelageya back at the pier")
	await _use("lantern")
	await _wait_mechanic("lantern")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "lantern", "the signal lantern close-up (beat %s)" % str(sr.current_beat))
	await _finish()
	p = mv.panel
	var lp := _v(_panel().get("lantern", {}))
	for i in 3:
		await _click(lp)
		while bool(_panel().get("shutter_open", false)):
			await process_frame
	guard = 0
	while not gs.has_flag("far_lights_answered") and guard < 1200:
		await process_frame
		guard += 1
	seen = await _finish()
	_check(gs.has_flag("far_lights_answered") and gs.has_flag("road_held_both_ends") and gs.has_flag("done_M16"), "three flashes → three lights → M16: %s" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	var lay: Node = rm.current_room.get_node("Layers")
	_check(lay.get_node("far_lights").visible and lay.get_node("far_snow").visible and not lay.get_node("far_dark").visible and lay.get_node("dusk").visible,
		"batch 3 layers: dusk, the far bank under snow (not dark), the three lights")
	# Ribbon (once).
	await _use("pelageya")
	seen = await _finish()
	_check(gs.has_flag("done_M17") and gs.has_item("school_ribbon") and gs.has_flag("ferry_verified"), "the empty boat returns with the ribbon: %s" % str(seen))
	# Director 22.10: shown directly — the boat goes along the rope on its ring and no longer turns back to its pier.
	_check(seen.any(func(x): return x.contains("Кольцо — на канат")), "Pelageya puts the ring on the rope: %s" % str(seen))
	var m17_text := ""
	for ln in sd.scene("M17").get("mandatory_lines", []):
		m17_text += String(ln.get("text", "")) + "\n"
	_check(seen.any(func(x): return x.begins_with("narration:Кольцо скользит по канату")) and m17_text.contains("теперь не разворачивает"),
		"the empty boat follows the ring along the rope, not back to the pier: %s" % str(seen))
	_check(seen.any(func(x): return x == "agata:Не повернула. Идёт по канату."), "Agata: it did not turn back")
	var n_before: int = gs.inventory.count("school_ribbon")
	await _use("pelageya")
	await _finish()
	sr.grant_item("school_ribbon")
	_check(gs.inventory.count("school_ribbon") == 1 and n_before == 1, "the ribbon is given once (talk again, grant again)")
	_check(not sr.can_start("M17"), "M17 never starts again")
	# Crossing and the far pier.
	_check(await _go("R2"), "R1→R2 (along the rope)")
	seen = await _finish()
	_check(gs.has_flag("done_M18p"), "the crossing: %s" % str(seen))
	_check(not rm.player.visible, "R2 is seen from the boat: no figure of Agata (player_hidden)")
	_check(await _go("R3"), "R2→R3")
	seen = await _finish()
	_check(rm.player.visible, "at the far pier Agata is in the frame again")
	_check(rm.current_room.get_node_or_null("npc_mitya") != null, "Mitya is a 3D figure at the far pier")
	_check(gs.has_flag("done_M18") and gs.has_flag("met_mitya") and gs.has_flag("knows_twenty_years"), "Mitya at the far pier: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("mitya:")), "Mitya speaks")
	# Block 3 (22.10): the path leads up to the street of Olkhovka — the meeting with mother (M19) starts there.
	_check(await _go("O4"), "the path leads up to the street of Olkhovka")
	_check(gs.has_flag("started_M19"), "the meeting with mother begins on the street (M19)")
	await _finish()
	_check(gs.inventory.count("school_ribbon") == 1, "ribbon still once")
	Engine.time_scale = 1.0


## Strikes on the bell with the mouse: `n` short clicks close together, then the pause that decides.
	_reached_end = true


func _ring(at: Vector2, n: int) -> void:
	for i in n:
		await _button(at, true)
		await _button(at, false)
	var p = mv.panel
	var t0: float = p.clock
	while p.clock - t0 < 0.7:
		await process_frame


func _ring_long(at: Vector2) -> void:
	var p = mv.panel
	await _button(at, true)
	var t0: float = p.clock
	while p.clock - t0 < 0.75:
		await process_frame
	await _button(at, false)


# --- Office mirror by mouse ------------------------------------------------------------------

func _test_office_mirror_mouse() -> void:
	Engine.time_scale = 4.0
	await _day_one_done()
	for f in ["done_N01", "done_M09", "done_M09s", "done_M09b", "met_pavel", "seen_office_door", "seen_office_photo", "seen_shift_schedule", "pavel_agreed_signals",
			"office_mirror_mounted", "has_mirror_mill", "bell_clapper_hung", "has_bell_clapper"]:
		gs.set_flag(f, true)
	rm.change_room("H2", "default")
	await _frames(3)
	await _finish()
	await _use("stand_zm")
	await _frames(2)
	_check(sr.mechanic_open, "the stand with the mounted mirror opens the close-up")
	await _finish()
	var p = mv.panel
	var pr := _panel()
	_check(not pr.get("clamped", true), "not clamped yet")
	await _click(_v(pr.get("bell", {})))
	await _finish()
	_check(not gs.has_flag("lantern_check_seen"), "an unclamped frame shows nothing: the strike proves nothing yet")
	await _click(_v(pr["wedges"][0]))
	_check(not gs.has_flag("office_mirror_clamped"), "one wedge is not enough")
	await _click(_v(pr["wedges"][1]))
	await _finish()
	_check(gs.has_flag("office_mirror_clamped"), "two wedges clamp")
	_check(p.office_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the office view is redrawn every frame")
	# The strike and the light: same process frame.
	var bell := _v(_panel().get("bell", {}))
	await _move(bell)
	_check(not p.office.light_on, "no light before the strike")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _win(bell)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await process_frame
	_check(p.strike_frame >= 0 and p.light_frame == p.strike_frame, "the light comes on in the glass in the strike's own frame (strike %d, light %d)" % [p.strike_frame, p.light_frame])
	_check(p.office.light_on and gs.has_flag("lantern_check_seen"), "the light is on and the check is in the story state")
	await _button(bell, false)
	await _finish()
	# The hook: wrong first (long ring away from the bar) — slips, back to the top, nothing lost.
	var counters_before: Dictionary = gs.counters.duplicate()
	await _ring(bell, 1)
	_check(p.hook.state == "down", "one strike — the hook goes down (%s)" % p.hook.state)
	await _ring_long(bell)
	_check(p.hook.state in ["lift_empty", "slipping", "wait"], "long ring away from the bar — the hook comes up empty (%s)" % p.hook.state)
	var guard := 0
	while p.hook.state != "wait" and guard < 900:
		await process_frame
		guard += 1
		if not sr.current_beat.is_empty():
			await _finish()
	_check(p.hook.state == "wait" and p.hook.pos == 0.0, "back at the top after the slip")
	_check(not gs.has_flag("office_unbolted") and gs.counters == counters_before, "no penalty: no flag lost, no counter grown")
	_check(p.signals_seen.has("one") and p.signals_seen.has("long"), "signals from the mouse: %s" % str(p.signals_seen))
	# Right.
	await _ring(bell, 1)
	guard = 0
	while p.hook.pos < p.hook.bar - 0.02 and guard < 900:
		await process_frame
		guard += 1
	await _ring(bell, 2)
	_check(p.signals_seen.has("two") and p.hook.state == "stopped", "two strikes stop the hook (%s)" % p.hook.state)
	await _ring_long(bell)
	guard = 0
	while not gs.has_flag("office_unbolted") and guard < 900:
		await process_frame
		guard += 1
	await _finish()
	_check(gs.has_flag("office_unbolted") and p.office.door_given, "the bar is lifted, the door gives in the glass")
	sr.close_mechanic()
	await _frames(2)
	Engine.time_scale = 1.0
	_reached_end = true


# --- Sluice by mouse --------------------------------------------------------------------------

func _test_sluice_mouse() -> void:
	Engine.time_scale = 4.0
	await _day_one_done()
	for f in ["done_N01", "done_M09", "done_M09s", "done_M09b", "done_M10", "done_M11", "done_M12", "done_M13a", "done_M13", "office_unbolted", "office_shelf_lifted",
			"has_key_sluice", "has_journal_manager", "has_clamp", "sluice_key_inserted"]:
		gs.set_flag(f, true)
	gs.add_item("clamp")
	rm.change_room("M4", "default")
	await _frames(3)
	await _finish()
	var lever = rm.current_room.get_node_or_null("Layers/lever_closed")
	_check(lever != null and lever.visible, "the key in the winch shows the lever")
	await _use("gate")
	await _frames(2)
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "sluice", "the sluice close-up")
	await _finish()
	var p = mv.panel
	var pr := _panel()
	_check(int(pr.get("notch", -1)) == 0, "closed at the start")
	# Drag the lever from the first notch past two notches at once.
	await _drag(_v(pr.get("lever_tip", {})), _v(pr.get("last_notch_point", {})), 10)
	await _frames(2)
	pr = _panel()
	_check(int(pr.get("notch", -1)) == 1, "a drag past two notches opens only one (notch %d)" % int(pr.get("notch", -1)))
	await _finish()
	# At once again: refused.
	await _drag(_v(pr.get("lever_tip", {})), _v(pr.get("next_notch", {})), 6)
	await _frames(2)
	pr = _panel()
	_check(int(pr.get("notch", -1)) == 1 and int(pr.get("refused", 0)) >= 1, "the next notch at once is refused (Pavel holds the winch)")
	var seen := await _finish()
	_check(seen.any(func(x): return x.begins_with("pavel:")), "Pavel says to wait: %s" % str(seen))
	_check(not gs.has_flag("sluice_opened"), "not open all at once")
	# Save with one notch open, load: the notch stays.
	sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLUICE_SLOT), "save with a notch open")
	_check(rm.load_game(SLUICE_SLOT), "load it")
	await _frames(3)
	await _use("gate")
	await _frames(2)
	await _finish()
	p = mv.panel
	_check(p.logic.notch == 1 and p.logic.settled(), "after the load the first notch is still open, the water settled")
	# Wait each time, then the next notch — by mouse.
	var guard := 0
	while not gs.has_flag("sluice_opened") and guard < 10:
		guard += 1
		while is_instance_valid(p) and not p.logic.settled() and not gs.has_flag("sluice_opened"):
			await process_frame
		if gs.has_flag("sluice_opened") or not is_instance_valid(p):
			break
		pr = _panel()
		await _drag(_v(pr.get("lever_tip", {})), _v(pr.get("next_notch", {})), 6)
		await _frames(2)
		await _finish()
	await _frames(3)
	await _finish()
	_check(gs.has_flag("sluice_opened") and gs.has_flag("pond_lowered"), "the last notch settled → the sluice is open")
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(2)
	var lo = rm.current_room.get_node_or_null("Layers/lever_open")
	_check(lo != null and lo.visible, "the lever stands in the open notch in the room")
	Engine.time_scale = 1.0
	_reached_end = true


# --- Mother's mirror ------------------------------------------------------------------------------

func _test_fast_mirror_panel() -> void:
	Engine.time_scale = 1.0
	await _day_one_done()
	for f in ["done_M14", "nina_mirror_clamped", "has_clamp"]:
		gs.set_flag(f, true)
	rm.change_room("H2", "default")
	await _frames(3)
	await _finish()
	await _use("bundle_nina")
	await _frames(2)
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "fast_mirror", "mother's mirror opens")
	var p = mv.panel
	var r0: float = p.fclock.real_s
	var n0: float = p.fclock.nina_elapsed_minutes()
	var t0 := Time.get_ticks_usec()
	for i in 90:
		await process_frame
	var real_wall := float(Time.get_ticks_usec() - t0) / 1_000_000.0
	var dr: float = p.fclock.real_s - r0
	var dn: float = (p.fclock.nina_elapsed_minutes() - n0) * 60.0
	_check(dr > 0.0 and absf(dn - 20.0 * dr) < 1e-6, "over 90 frames: Nina's %.4f s = 20 × Agata's %.4f s exactly" % [dn, dr])
	_check(absf(dr - real_wall) < 0.25 + real_wall * 0.1, "Agata's watch follows the real seconds (%.3f vs wall %.3f)" % [dr, real_wall])
	# Nina changes pose at twenty times: jump the clock and see the poses go round.
	p.fclock.advance(60.0)   # twenty of Nina's minutes
	await _frames(2)
	_check(p.poses_seen.size() >= 2, "Nina changes pose (%s)" % str(p.poses_seen))
	var poses: Array = p.spec.get("poses", [])
	_check(poses.size() >= 5 and poses.size() <= 6, "5–6 poses in data (%d)" % poses.size())
	await _click(_v(_panel().get("glass", {})))
	var seen := await _finish()
	_check(int(_panel().get("knocks", 0)) == 1 and seen.size() == 1, "a knock: Nina does not turn (%s)" % str(seen))
	await _click(_v(_panel().get("glass", {})))
	seen = await _finish()
	_check(seen.is_empty() and mv.sounds_played.count("knock") >= 2, "further knocks only sound")
	sr.close_mechanic()
	await _frames(2)
	# Common time after the three lights.
	gs.set_flag("road_held_both_ends", true)
	await _use("bundle_nina")
	await _frames(2)
	p = mv.panel
	var r1: float = p.fclock.real_s
	var n1: float = p.fclock.nina_elapsed_minutes()
	for i in 30:
		await process_frame
	_check(p.fclock.ratio == 1.0 and absf((p.fclock.nina_elapsed_minutes() - n1) * 60.0 - (p.fclock.real_s - r1)) < 1e-6,
		"once the road is held from both ends the mirror's clock goes with Agata's")
	sr.close_mechanic()
	await _frames(2)
	_reached_end = true


# --- Save / load -----------------------------------------------------------------------------------

func _test_save_load() -> void:
	Engine.time_scale = 4.0
	_check(gs.has_save(MID_SLOT), "the mid-day-two save from the walkthrough exists")
	if not gs.has_save(MID_SLOT):
		return
	_check(rm.load_game(MID_SLOT), "load the save made after the bar")
	await _frames(3)
	_check(_room() == "H2", "the room comes back (%s)" % _room())
	_check(sr.current_beat.is_empty() and not sr.mechanic_open, "nothing replays on load (no line, no close-up)")
	for id in ["N01", "M09", "M09s", "M09b", "M10", "M11", "M12"]:
		_check(gs.has_flag("done_" + id) and not sr.can_start(id), "%s stays done" % id)
	_check(not gs.has_item("mirror_mill") and not gs.has_item("bell_clapper"), "the mirror and the clapper are not back in the bag")
	_check(not gs.has_flag("office_shelf_lifted") and not gs.has_flag("done_M13"), "what came after the save is undone")
	# Re-entering rooms plays nothing old.
	_check(await _go("H1"), "H2→H1")
	_check(sr.current_beat.is_empty(), "no morning again in H1")
	_check(await _go("Z2"), "H1→Z2")
	_check(await _go("M1"), "Z2→M1")
	_check(sr.current_beat.is_empty(), "no Pavel's story again")
	_check(await _go("M2"), "M1→M2")
	await _use("office_door_open")
	await _finish()
	_check(gs.has_flag("done_M13a"), "the day goes on after the load: the shelf")
	_check(await _go("M3"), "into the office after the load")
	await _use("key_nail")
	await _finish()
	_check(gs.inventory.count("key_sluice") == 1, "the key once")
	Engine.time_scale = 1.0
	_reached_end = true
