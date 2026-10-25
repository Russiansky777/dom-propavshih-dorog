extends SceneTree
## Headless tests of day two (E2–E3, Docs/SCENARIO_FINAL.md §7, block 2). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_day2.gd
## What the coordinator asked to prove (block 2 brief):
##   - the hook puzzle is solved and slips back to the top without any penalty;
##   - the sluice (G23): «точный удар» — a hit a notch and a step of water down, a miss back to the first notch;
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
	await _test("Logic: sluice (G23) — the water follows the winch: a step down per notch, back up on a slip", _test_sluice_logic)
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
	await _test("The clapper any time: taken and hung on day one, the bell rings far away; M11 needs no box, nothing given twice", _test_clapper_early)
	await _test("By state: the clamp waits for the sluice; Pelageya's lines at the pier follow the goal; the boat gone at dusk; «В лодку» after the knot; no Pelageya at the pier after the crossing", _test_states)
	await _test("Whole day two by script: morning → mill → mirror and bell → office → sluice → mother's mirror → plate → three lights → ribbon → R3", _test_walkthrough)
	await _test("Office mirror by mouse: four painted wedges, three «точный удар» hits each (G19), the light in the same frame as the strike, the hook by bell signals", _test_office_mirror_mouse)
	await _test("Sluice by mouse (G23/G24): «точный удар» — a hit in the green a notch and a step down, a miss back to the first notch, early → «Погоди»; red mark on the last notch; four in a row open it", _test_sluice_mouse)
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
	if _npc_goal_check and _room() == target:
		_check_npc_lines()
	return _room() == target


## F11 (Director 23.10: «фраза до лодки … отправляла к кому-то в дом, хотя по заданию нужно было плыть»): the line
## a click on any NPC of the room would say now (not a scene start) never sends Agata («иди / ступай / сходи …»)
## to a place the journal's goal does not name.
var _npc_goal_check := false
const GO_WORDS := ["иди", "ступай", "сходи", "беги", "возвращайся"]
const PLACE_STEMS := ["дом", "изб", "мельниц", "контор", "затвор", "мастерск", "поворот", "причал", "лодк", "опор", "улиц", "почт", "школ"]


func _npc_line_now(h: Node) -> String:
	var t: Dictionary = h.data.get("talk", {})
	var scn: String = sr.talk_scene(t)
	if scn != "" and sr.can_start(scn):
		return ""
	if scn != "" and not sr.is_done(scn) and t.has("before_text"):
		return sd.text(sr._talk_before_text(t, scn))
	for e in t.get("by_flags", []):
		if sr.requires_met({"flags": e.get("if", [])}):
			return sd.text(String(e.get("text", "")))
	return sd.text(String(t.get("after_text", ""))) if t.has("after_text") else ""


func _check_npc_lines() -> void:
	var goal: String = String(sr.journal_goal()).to_lower()
	for h in rm.current_room.get_hotspots():
		if not h.visible or not h.has_method("is_active") or not h.call("is_active") or String(h.data.get("kind", "")) != "npc":
			continue
		var line: String = _npc_line_now(h).to_lower()
		for clause in line.split(".", false):
			var go := false
			for w in GO_WORDS:
				if (" " + clause + " ").contains(" " + w + " ") or clause.strip_edges().begins_with(w):
					go = true
			if not go:
				continue
			for st in PLACE_STEMS:
				if clause.contains(st) and not goal.contains(st):
					_check(false, "%s in %s: «%s» sends Agata to «%s», the goal is «%s»" % [h.hotspot_id, _room(), clause.strip_edges(), st, goal])


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
	# The house key went into the lock (exit item_use): its flags, not the key. The living room steps of M03 (its room
	# complete_when — G7: the shutter open, or the inner rooms stay dark) and the gallery's side bolt (C12: its first entry).
	for f in ["house_unlocked", "h1_shutter_open", "h1_scarf_removed", "house_open"]:
		gs.set_flag(f, true)
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
	# F8 (Director 23.10): after «пускай» the hook sways along the gap; «стой» must catch it at the bar.
	var h := HookPuzzle.new({"bar": 0.5, "tolerance": 0.07, "speed": 0.35, "return_speed": 0.6, "sway": [0.2, 0.8], "timing": {"period_s": 2.0}})
	var events: Array[String] = []
	h.event.connect(func(n): events.append(n))
	_check(h.state == "wait" and h.pos == 0.0, "the hook starts at the top, waiting")
	h.apply("two")
	_check(h.state == "wait", "stop before go does nothing")
	h.apply("one")
	_check(h.state == "down", "one → down")
	for i in 10:
		h.step(0.1)
	_check(h.state == "sway" and "swaying" in events, "it reaches where Pavel feels for the bar and sways (%s %.2f)" % [h.state, h.pos])
	var p0 := h.pos
	h.step(0.3)
	_check(h.pos != p0 and h.pos >= 0.2 and h.pos <= 0.8, "the hook goes up and down within the sway (%.2f → %.2f)" % [p0, h.pos])
	# Wrong: «стой» away from the bar — it slips off and falls; Pavel brings it back to the top.
	var g := 0
	while absf(h.pos - 0.5) < 0.2 and g < 200:
		h.step(0.02)
		g += 1
	h.apply("two")
	_check(h.state == "falling" and h.misses == 1 and "missed" in events, "stopped away from the bar → it falls (%s)" % h.state)
	for i in 10:
		h.step(0.1)
	_check(h.pos > 0.0 and ("slipped" in events), "it slipped off, Pavel lifts it")
	for i in 30:
		h.step(0.1)
	_check(h.state == "wait" and h.pos == 0.0 and "returned" in events and not h.solved(), "back at the top, nothing lost (%s %.2f)" % [h.state, h.pos])
	# «Подымай» before it is caught — empty: falls as well.
	h.apply("one")
	for i in 10:
		h.step(0.1)
	h.apply("long")
	_check(h.state == "falling", "lifted before it is caught → falls")
	for i in 40:
		h.step(0.1)
	_check(h.state == "wait", "and comes back to the top")
	# Judged where it was when «стой» began (its first strike): a phase in the green counts even if it moved on.
	h.apply("one")
	for i in 10:
		h.step(0.1)
	var green_phase := 0.25    # the middle of the sweep = the bar
	while absf(h.pos - 0.5) < 0.2:
		h.step(0.02)
	h.apply("two", green_phase)
	_check(h.state == "stopped" and h.at_bar(), "«стой» begun at the bar catches it (%s %.2f)" % [h.state, h.pos])
	h.step(1.0)
	_check(h.state == "stopped", "a caught hook stays")
	h.apply("long")
	_check(h.state == "lift_bar", "«подымай» at the bar → takes the bar")
	for i in 12:
		h.step(0.1)
	_check(h.solved() and "solved" in events, "the bar is out of the brackets")
	_reached_end = true


func _test_sluice_logic() -> void:
	# G23: the water follows the winch's notch (TimingLogic counts the hits) — falls a step per notch, back up on a slip.
	var s := SluiceLogic.new({"levels": [1.0, 0.8, 0.6, 0.38, 0.15], "fall_per_s": 0.25, "rise_per_s": 0.9})
	_check(s.notch == 0 and s.settled() and s.steps() == 4, "closed and settled at the start; four steps down")
	s.set_notch(1)
	_check(not s.settled(), "one notch on: the water starts to fall")
	for i in 10:
		s.step(0.1)
	_check(s.settled() and is_equal_approx(s.level, 0.8), "a step down settles in under a second (%.3f)" % s.level)
	s.set_notch(2)
	s.step(0.3)
	var mid := s.level
	s.set_notch(0)   # the winch slipped: back to the first notch
	for i in 15:
		s.step(0.1)
	_check(mid < 0.8 and s.settled() and is_equal_approx(s.level, 1.0), "a slip: the water rises back to the start")
	for n in range(1, 5):
		s.set_notch(n)
		for i in 15:
			s.step(0.1)
	_check(s.finished() and is_equal_approx(s.level, 0.15), "four notches: the water down on the last level")
	var r := SluiceLogic.new({"levels": [1.0, 0.8, 0.6, 0.38, 0.15]}, 4)
	_check(r.notch == 4 and r.finished(), "an opened sluice reopened: the water down, settled")
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
	_check(String(nl[nl.size() - 1].get("speaker", "")) == "tikhon" and String(nl[nl.size() - 1].get("text", "")).begins_with("Ты с утра в колокол не бей"), "N01 ends with Tikhon's morning line (H23)")
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
	# F3 (Director 23.10 00:19, «не могу найти записи тёти»): the notes are what is painted — the drawings on the
	# wall over the boxes; the label says so, the rect covers the drawings (screen 671–924 × 169–393), the goal
	# before the workshop names the place.
	var notes := {}
	for h in sd.room("H2").get("hotspots", []):
		if String(h.get("id", "")) == "bench":
			notes = h
	var r: Array = notes.get("rect", [0, 0, 0, 0])
	var nr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_check(sd.text(String(notes.get("label", ""))).contains("чертеж") and not sd.text(String(notes.get("label", ""))).contains("верстак"),
			"the notes' label names the drawings, not a bench: %s" % sd.text(String(notes.get("label", ""))))
	_check(nr.has_point(Vector2(700, 200)) and nr.has_point(Vector2(900, 380)) and nr.size.y < 260.0, "the notes' rect covers the drawings over the boxes: %s" % str(r))
	_check(String(sd.scene("M03").get("goal", "")).contains("над ящиками"), "the goal before the workshop names where the notes are")
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
	# Playtest 22.10: on day one the passage and the sluice wait for the morning too — a line, not «ключ в конторе».
	for to in ["M2", "M4"]:
		var ex = rm.current_room.get_node_or_null("Exits/to_" + to)
		_check(ex != null and not ex.is_open(), "day one: M1→%s closed until the morning" % to)
		sr.use_exit(ex)
		await process_frame
		_check(String(sr.current_beat.get("text_key", "")) == "M1.exit_%s.closed" % to, "M1→%s: closed until the morning of day two (%s)" % [to, str(sr.current_beat)])
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


## The clapper any time (Director 23.10 00:03): taken from its box and hung on day one, the bell rings far away
## at the mill and nothing breaks; a save/load keeps it hung; on day two M11 needs no box — the mirror clamped,
## one strike, the lantern. The clapper is given once, never comes back to the bag, never gets lost.
func _test_clapper_early() -> void:
	await _day_one_done(false)
	var rung: Array[String] = []
	var on_synth := func(n: String): rung.append(n)
	sr.synth_sound_requested.connect(on_synth)
	# G44/H17 (Director 24.10): the clapper lies in the chest in the attic; the box in the workshop is gone.
	rm.change_room("H4", "from_H1")
	await _frames(3)
	await _finish()
	_check(_hotspot("chest") != null and _hotspot("chest").visible, "day one: the chest in the attic")
	var cl: Node = rm.current_room.get_node_or_null("Layers/chest_clapper")
	_check(cl != null and not cl.visible, "the chest is closed: the clapper not drawn yet")
	await _use("chest")
	await _finish()
	_check(gs.inventory.count("bell_clapper") == 1 and gs.has_flag("has_bell_clapper") and gs.has_flag("attic_chest_open"), "day one: the clapper from the chest, no condition (%s)" % str(gs.inventory))
	_check(rm.current_room.get_node("Layers/chest_open").visible and not rm.current_room.get_node("Layers/chest_clapper").visible, "the chest drawn open, the clapper gone from it")
	await _use("chest")
	await _finish()
	_check(gs.inventory.count("bell_clapper") == 1, "the chest gives it once")
	rm.change_room("H2", "from_H1")
	await _frames(3)
	await _finish()
	_check(_hotspot("clapper_box") == null and rm.current_room.get_node("Layers/crate_blank").visible, "the workshop crate has no «Язык колокола» label and no hotspot")
	await _use_item("bell_clapper", "bell")
	await _finish()
	_check(gs.has_flag("bell_clapper_hung") and not gs.has_item("bell_clapper"), "day one: the clapper hung on the bell")
	await _use("bell")
	var b: Dictionary = sr.current_beat
	_check(String(b.get("text_key", "")) == "H2d.bell.ring_far" and not sr.mechanic_open,
			"the bell rung before the office mirror: «where far away, at the mill», no close-up (%s)" % str(b))
	await _finish()
	_check(rung.has("bell"), "the bell sounds (engine sound): %s" % str(rung))
	_check(rm.save_game(MID_SLOT), "save on day one with the clapper hung")
	gs.reset()
	await _frames(2)
	_check(rm.load_game(MID_SLOT), "load it")
	await _frames(3)
	await _finish()
	_check(gs.has_flag("bell_clapper_hung") and not gs.has_item("bell_clapper") and gs.has_flag("has_bell_clapper"),
			"after the load: hung, not in the bag, the chest empty")
	# Day two up to Pavel's mirror (M09b) — the clapper is not in the way of anything.
	for f in sd.scene("M09").get("requires", {}).get("flags", []):
		gs.set_flag(String(f), true)
	for id in ["N01", "M09", "M09s", "M09b"]:
		gs.set_flag("done_" + id, true)
	gs.set_flag("has_mirror_mill", true)
	gs.add_item("mirror_mill")
	await _frames(2)
	await _use_item("mirror_mill", "stand_zm")
	await _wait_mechanic("office_mirror")
	await _finish()
	await _drive_wedges()
	await _frames(2)
	await _finish()
	_check(gs.has_flag("done_M10"), "the wedges clamp the frame → M10")
	await _click(_v(_panel().get("bell", {})))
	await _frames(2)
	await _finish()
	_check(gs.has_flag("lantern_check_seen") and gs.has_flag("done_M11"), "one strike with the clapper hung since day one → the lantern, M11")
	_check(gs.inventory.count("bell_clapper") == 0, "M11 gives no clapper back (%s)" % str(gs.inventory))
	sr.close_mechanic()
	await _frames(2)
	sr.synth_sound_requested.disconnect(on_synth)
	gs.delete_save(MID_SLOT)
	_reached_end = true


## Things that depend on the state but are off the walkthrough's path (logic review M2 22.10, items 1 and 3;
## F11, F13 — Director 23.10).
func _test_states() -> void:
	await _day_one_done()
	for id in ["M09", "M09s", "M09b", "M10", "M11", "M12", "M13a", "M13"]:
		for f in sd.scene(id).get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		gs.set_flag("done_" + id, true)
	gs.set_flag("has_clamp", true)
	gs.add_item("clamp")
	# Item 1: the clamp before the sluice — Agata says the sluice comes first; nothing is spent.
	rm.change_room("H2", "default")
	await _frames(3)
	await _finish()
	await _use_item("clamp", "bundle_nina")
	var b: Dictionary = sr.current_beat
	_check(String(b.get("text_key", "")) == "H2d.nina_mirror.clamp_early" and gs.has_item("clamp") and not sr.mechanic_open,
			"before the sluice the clamp waits: «Сначала затвор…» (%s)" % str(b))
	await _finish()
	# F11: Pelageya at the pier in the morning of day two — the water is at the mill (the goal), no «Дунин дом».
	rm.change_room("R1", "default")
	await _frames(3)
	await _finish()
	_check(_npc_line_now(_hotspot("pelageya")).contains("к Павлу на мельницу"), "day two morning: «Сперва к Павлу на мельницу» (T9, R14) (%s)" % _npc_line_now(_hotspot("pelageya")))
	gs.set_flag("done_M14")
	await _frames(2)
	_check(_npc_line_now(_hotspot("pelageya")).contains("со стопора канат сниму") and _npc_line_now(_hotspot("pelageya")).contains("к опоре"), "the water going down: G28 — she will take the rope off her stopper and bring it to the pier by boat (%s)" % _npc_line_now(_hotspot("pelageya")))
	# At dusk before the knot: the boat is gone from the pier — Agata says where (once).
	for f in ["done_M15a", "nina_time_compared", "evening_dusk"]:
		gs.set_flag(f)
	rm.change_room("Z3", "default")
	await _frames(3)
	await _finish()
	rm.change_room("R1", "default")
	await _frames(3)
	var seen := await _finish()
	_check(seen.any(func(x): return x.contains("На причале Пелагеи нет")) and not _hotspot("pelageya").visible, "at dusk: «Пелагеи на причале нет. Она у поворота…» (%s)" % str(seen))
	# G28: until Pelageya takes it, the rope is on her stopper (the painted one); no rope at the turn yet.
	_check(_hotspot("rope") != null and _hotspot("rope").visible and not rm.current_room.get_node("Layers/stopper_empty_dusk").visible, "G28: before M15s the rope is still on her stopper")
	rm.change_room("Z3", "default")
	await _frames(3)
	rm.change_room("R1", "default")
	await _frames(3)
	seen = await _finish()
	_check(not seen.any(func(x): return x.contains("Пелагея с ней")), "said once: %s" % str(seen))
	# Item 3: the boat before the knot — «вернёт сюда же» (H36: looked at at the pier, no exit into it); after the brace it
	# is at the turn — «В лодку» there: first the empty-boat check.
	_check(rm.current_room.get_node_or_null("Exits/to_R2") == null, "H36: no exit into the boat at the pier")
	sr.interact(_hotspot("boat"))
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed", "before the knot: «Без плиты лодку вернёт сюда же»")
	await _finish()
	for f in ["done_M15s", "skoba_on_plate", "plate_braced", "rope_brought", "done_M15", "rope_on_ring", "road_held_both_ends", "done_M16s", "far_snow_seen"]:
		gs.set_flag(f)
	await _frames(2)
	_check(not _hotspot("boat").visible, "H36: after the brace no boat at the pier")
	rm.change_room("Z3", "default")
	await _frames(3)
	var ex = rm.current_room.get_node("Exits/to_R2")
	sr.use_exit(ex)
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed_check", "after the knot: first the empty boat (%s)" % str(sr.current_beat))
	await _finish()
	rm.change_room("R1", "default")
	await _frames(3)
	await _finish()
	_check(_npc_line_now(_hotspot("pelageya")).contains("Три огня"), "after the knot Pelageya points to the lantern")
	# F13: after the crossing Pelageya is with Mitya at the far pier — not at this pier too.
	for f in ["done_M16", "three_lights_sent", "far_lights_answered", "done_M17", "ferry_verified", "done_M18p"]:
		gs.set_flag(f)
	await _frames(2)
	_check(not _hotspot("pelageya").visible, "after the crossing Pelageya is not at the near pier")
	gs.set_flag("boat_shuttle_open")
	await _frames(2)
	_check(not _hotspot("pelageya").visible, "once the boat goes both ways (blocks 3–5) she waits by the boat at the turn, not at the pier (T9, decision 24.10 22:26)")
	_reached_end = true


# --- Walkthrough -------------------------------------------------------------------------

func _test_walkthrough() -> void:
	_npc_goal_check = true
	rm.autosave_enabled = true
	Engine.time_scale = 4.0
	# Day one ends at the school; back through the school door into the gallery: the night by the stove
	# (block 1's N01: fade, H1, morning with Tikhon's line, the save «День второй»).
	await _day_one_done(false)
	rm.change_room("H3", "default")
	await _frames(3)
	var seen := await _finish()
	# H17/T6: the day ends with sleep on the lezhanka by the stove.
	rm.change_room("H1", "from_H3")
	await _frames(3)
	await _use("lezhanka")
	var g0 := 0
	while not gs.has_flag("done_N01") and g0 < 600:
		seen.append_array(await _finish())
		await process_frame
		g0 += 1
	await _finish()
	_check(gs.has_flag("done_N01") and gs.has_flag("night_day1"), "the night by the stove: %s" % str(seen))
	_check(_room() == "H1", "morning in the living room (%s)" % _room())
	_check(seen.any(func(x): return x.begins_with("tikhon:Ты с утра в колокол не бей")), "Tikhon's morning line: %s" % str(seen))
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
	# F19: the board opens its close-up (the sheet by the game) — a click after the text closes it, as a player does.
	_check(sr.view_open, "the shift board opens its close-up (F19)")
	sr.close_view()
	await _frames(2)
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
	await _use("mirror")
	seen = await _finish()
	_check(not gs.has_item("mirror_mill") and seen.any(func(x): return String(x).contains("Без Павлова слова")), "G18: the mirror is not taken before Pavel's leave: %s" % str(seen))
	_check(await _go("M1"), "M2→M1")
	var went: Array = []
	var on_went := func(id: String): went.append(id)
	sr.npc_went.connect(on_went)
	await _use("pavel")
	seen = await _finish()
	var g18 := 0
	while (sr.is_staging() or rm.current_room.room_id != "M2") and g18 < 600:
		await process_frame
		g18 += 1
	seen += await _finish()
	sr.npc_went.disconnect(on_went)
	_check(gs.has_flag("done_M09b") and gs.has_flag("pavel_blessed_mirror") and not gs.has_item("mirror_mill"), "G18: Pavel gives his leave, the mirror is not handed over by the talk: %s" % str(gs.inventory))
	_check(String(sd.scene("M09b")["mandatory_lines"][-1]["text"]).ends_with("За мной иди.") and seen.any(func(x): return String(x).begins_with("pavel:Оттуда и звони")), "G18: Pavel's last word «Иди за мной»: %s" % str(seen))
	_check(went == ["pavel"], "G18: Pavel walks off to the passage door before the fade (npc_go): %s" % str(went))
	_check(rm.current_room.room_id == "M2" and _hotspot("pavel") != null and _hotspot("pavel").visible, "G18: in the passage, Pavel is there (room %s)" % rm.current_room.room_id)
	await _use("mirror")
	seen = await _finish()
	_check(gs.has_item("mirror_mill") and gs.inventory.count("mirror_mill") == 1 and seen.any(func(x): return String(x).begins_with("pavel:Бери")), "G18: the mirror taken in the passage, with Pavel's word: %s" % str(seen))
	_check(_hotspot("mirror") == null or not _hotspot("mirror").visible, "G18: the mirror is gone from the passage — not taken twice")
	_check(sr.journal_goal().contains("стойку"), "goal: the mirror onto the stand")
	_check(await _go("M1"), "M2→M1")
	_check(_hotspot("pavel") == null or not _hotspot("pavel").visible, "G18: Pavel is not in the yard any more (he waits in the passage)")
	# Home: the stand, the wedges, the clapper, the lantern, the hook.
	_check(await _go("Z2"), "M1→Z2")
	_check(await _go("H1"), "Z2→H1")
	await _finish()
	_check(sr.journal_goal().contains("мастерской"), "the goal names the room of the stand: %s" % sr.journal_goal())
	# The mirror tried on a wrong place in the house says where the stand is (Director 23:53).
	_check(sr.item_refusal("mirror_mill") == "@item.mirror_mill.wrong", "in H1 the office mirror points to the stand «ЗМ»")
	_check(await _go("H2"), "H1→H2")
	seen = await _finish()
	_check(gs.has_flag("h2_saw_stand_zm") and seen.any(func(t): return t.contains("высокая резная рама посреди мастерской")),
			"entering the workshop with the office mirror: Agata names the stand — the tall carved frame: %s" % str(seen))
	await _check_picks("H2 with the office mirror")
	var sz := _hotspot("stand_zm")
	_check(sz != null and sz.global_position.distance_to(Vector2(1250, 407)) < 30.0,
			"the stand «ЗМ» is the tall carved frame in the middle of the workshop (Director 23.10)")
	await _use_item("mirror_mill", "bench")
	seen = await _finish()
	_check(gs.has_item("mirror_mill") and seen.any(func(t): return t.contains("в Дунину стойку")),
			"the office mirror on another thing in the workshop says where the stand is: %s" % str(seen))
	_check(await _go("H1"), "H2→H1 (the stand thought is said once)")
	await _finish()
	_check(await _go("H2"), "H1→H2 again")
	seen = await _finish()
	_check(not seen.any(func(t): return t.contains("высокая резная рама посреди мастерской")), "the stand thought is not repeated: %s" % str(seen))
	await _use_item("mirror_mill", "stand_zm")
	await _frames(2)
	_check(not gs.has_item("mirror_mill") and gs.has_flag("office_mirror_mounted"), "the mirror goes onto the stand (out of the bag)")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "office_mirror", "the office mirror close-up opens")
	await _finish()
	var p = mv.panel
	await _drive_wedges()
	await _frames(2)
	seen = await _finish()
	_check(gs.has_flag("office_mirror_clamped") and gs.has_flag("done_M10"), "four wedges, three hits each, clamp the frame → M10: %s" % str(seen))
	await _click(_v(_panel().get("bell", {})))
	await _finish()
	_check(not gs.has_flag("lantern_check_seen"), "without the clapper the bell is mute")
	sr.close_mechanic()
	await _frames(2)
	rm.change_room("H4", "from_H1")
	await _frames(3)
	await _use("chest")
	await _finish()
	_check(gs.has_item("bell_clapper"), "the clapper from the chest in the attic")
	rm.change_room("H2", "from_H1")
	await _frames(3)
	await _finish()
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
	# The hook: go, catch it at the bar while it sways (F8), lift.
	await _ring(bell, 1)
	await _ring_stop_at_bar(bell)
	var guard := 0
	_check(p.hook.state == "stopped" and p.hook.at_bar(), "caught at the bar by two strikes (%s %.2f)" % [p.hook.state, p.hook.pos])
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
	# G21 (Director 23.10: «открываем вдвоём — мужик пропадает будто за дверь, а она закрыта»): he stays by the door.
	_check(_hotspot("pavel") != null and _hotspot("pavel").visible, "G21: after the shelf Pavel is still in the passage by the door")
	_check(await _go("M3"), "M2→M3 (the office)")
	_check(_hotspot("pavel") != null and _hotspot("pavel").visible, "G21: Pavel is in the office when Agata comes in")
	# G22: Pavel names the clamp and what it is for; the clamp lies on the table (layer), not on the shelf.
	await _use("pavel")
	seen = await _finish()
	var pb: String = sd.text("@M3.pavel.before")
	_check(seen.any(func(x): return String(x).begins_with("pavel:Нужное бери")) and pb.contains("рычаг на гвозде") and pb.contains("трубцин") and pb.contains("раму"), "G20/G22: Pavel — the sluice lever on the nail, the clamp for Dunya's frame: %s" % pb)
	_check(rm.current_room.get_node("Layers/clamp_table").visible, "G22: the clamp lies on the office table")
	await _use("key_nail")
	await _finish()
	await _use("journal")
	await _finish()
	await _use("clamp")
	seen = await _finish(["promise"])
	_check(gs.has_item("key_sluice") and gs.has_item("journal_manager") and gs.has_item("clamp"), "lever, journal, clamp: %s" % str(gs.inventory))
	_check(sd.item_name("key_sluice") == "Рычаг затвора", "G20: the item is called «Рычаг затвора» (id key_sluice kept for saves): %s" % sd.item_name("key_sluice"))
	_check(not rm.current_room.get_node("Layers/clamp_table").visible and not rm.current_room.get_node("Layers/sluice_lever").visible, "G20/G22: lever and clamp taken — gone from the wall and the table")
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
	await _sluice_strikes(p, 4)
	await _wait_sluice_open()
	await _frames(2)
	seen = await _finish()
	_check(gs.has_flag("sluice_opened") and gs.has_flag("pond_lowered") and gs.has_flag("done_M14"), "the sluice opened notch by notch («точный удар», G23) → M14: %s" % str(seen))
	_check(sr.journal_goal().contains("струбцин"), "goal: the clamp to mother's mirror")
	# F10 (Director 23.10): why the water goes down — the plate comes out; the boat alone is turned back, the rope on the ring is not.
	_check(sr.journal_goal().contains("плита на опоре выйдет") and seen.any(func(x): return x.contains("Лодка туда не довезёт")),
			"at the sluice: the plate comes out of the water; a boat is turned back, the rope on the ring is another matter: %s / %s" % [sr.journal_goal(), str(seen)])
	# Mother's mirror.
	_check(await _go("M1"), "M4→M1")
	var wheel = rm.current_room.get_node_or_null("Layers/wheel")
	_check(wheel != null and not wheel.is_spinning(), "the wheel stands while the pond is let down")
	# H9 (10б): water and drips loop while the water runs, the still water frame takes over with the wheel stopped.
	var wlay: Node = rm.current_room.get_node("Layers")
	_check(wlay.get_node("wheel_water_still").visible and not wlay.get_node("wheel_water").visible and not wlay.get_node("wheel_drips").visible,
		"H9: pond let down — still water, no water loop, no drips")
	gs.set_flag("pond_lowered", false)
	await _frames(40)
	var ww: Node = wlay.get_node("wheel_water")
	var rot0: float = wheel.get_node("Image").rotation_degrees
	var seen_frames := {}
	for _i in 30:
		await _frames(2)
		seen_frames[ww.frame_index()] = true
	_check(wheel.is_spinning() and ww.visible and wlay.get_node("wheel_drips").visible and not wlay.get_node("wheel_water_still").visible,
		"H9: water runs — the wheel spins, water and drips drawn")
	_check(not is_equal_approx(rot0, wheel.get_node("Image").rotation_degrees) and seen_frames.size() == 3,
		"H9: the wheel turns and the water cycles through all 3 frames (%s)" % str(seen_frames.keys()))
	gs.set_flag("pond_lowered", true)
	await _frames(2)
	var rot1: float = wheel.get_node("Image").rotation_degrees
	await _frames(10)
	_check(not wheel.is_spinning() and is_equal_approx(rot1, wheel.get_node("Image").rotation_degrees), "H9: pond let down again — the wheel stands")
	_check(await _go("Z2"), "M1→Z2")
	_check(await _go("H1"), "Z2→H1")
	await _finish()
	_check(await _go("H2"), "H1→H2")
	# The brace: Dunya's bench, once the school plan is known (block 1: hotspot brace) — taken now if not on day one.
	_check(rm.current_room.get_node_or_null("Layers/office_mirror") != null and rm.current_room.get_node("Layers/office_mirror").visible,
		"the office mirror's glass stays in the tall carved frame «ЗМ» (Director 23.10)")
	if not gs.has_flag("has_brace_plate"):
		# The brace stays on the left bench (the stand «ЗМ» is the tall frame in the middle now, 23.10).
		_check(_hotspot("brace").visible and rm.current_room.get_node("Layers/skoba").visible, "the brace (with the plate drawing) on the bench")
		await _use("brace")
		await _finish()
		_check(not _hotspot("brace").visible and not rm.current_room.get_node("Layers/skoba").visible, "taken from the bench — gone from it")
	_check(gs.inventory.count("brace_plate") == 1, "the brace is in the bag before the turn, once")
	await _use_item("clamp", "bundle_nina")
	await _frames(2)
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "fast_mirror" and not gs.has_item("clamp"), "the clamp on the frame opens mother's mirror")
	await _finish()
	p = mv.panel
	# F4 (Director 23.10): the comparison is Agata's own act — her watch from the bag held to the glass.
	await _click(_v(_panel().get("watch", {})))
	await _finish()
	_check(not gs.has_flag("nina_time_compared") and not bool(_panel().get("holding", true)), "an empty place: no comparison without the watch")
	sr.select_item("pocket_watch")
	await _click(_v(_panel().get("glass", {})))
	await _finish()
	_check(bool(_panel().get("holding", false)) and gs.has_item("pocket_watch") and not gs.has_flag("nina_time_compared"), "the watch held to the glass, still Agata's; not at once")
	var g15 := 0
	while not gs.has_flag("nina_time_compared") and g15 < 3000:
		await process_frame
		g15 += 1
	seen = await _finish()
	_check(gs.has_flag("nina_time_compared") and gs.has_flag("done_M15a") and gs.has_flag("evening_dusk"), "compare → M15а, dusk: %s" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	# The plate.
	_check(await _go("H1"), "H2→H1")
	# H33 (Director 24.10): back in the living room Tikhon talks about Nina first (three lines, once).
	var h33 := await _finish()
	_check(h33.size() == 3 and String(h33[0]).begins_with("tikhon:Нину видела?"), "H33: Tikhon talks after the mirror: %s" % str(h33))
	# Polish 22.10 (C17): mother's small mirror shows Dunya's stove — Agata can stand at the stove and wave (block 3 reads it in M19).
	_check(_hotspot("wave") != null and _hotspot("wave").visible, "after mother's mirror: «Встать у печи и помахать»")
	await _use("wave")
	seen = await _finish()
	_check(gs.has_flag("waved_at_stove") and not _hotspot("wave").visible, "waved once: %s" % str(seen))
	# Dusk in the house is the time of day now (time/H1.json replaces the old evening_dusk tint, which also stayed on
	# days 3–4): the room is in a dusk state and its time-of-day light source for it is on.
	var h1tg = rm.current_room.get_node_or_null("TimeOfDay")
	var h1st := String(h1tg.call("probe").get("state", "")) if h1tg != null else ""
	var h1src = rm.current_room.get_node_or_null("Lighting/tod_" + h1st)
	_check(h1st in ["d2_dusk", "d2_evening"] and h1src != null and float(h1src.get("level")) > 0.5, "dusk in the house after mother's mirror (time of day %s)" % h1st)
	_check(await _go("Z2"), "H1→Z2")
	_check(await _go("R1"), "Z2→R1")   # H7: the turn is reached from the pier
	await _finish()                     # a line on arriving at the pier at dusk, if any
	var to_z3 := await _go("Z3")
	if not to_z3:
		await _finish()
		to_z3 = await _go("Z3")
	_check(to_z3, "R1→Z3 (in %s, beat %s)" % [_room(), str(sr.current_beat.get("text_key", ""))])
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
	# F7 (Director 23.10): three blows in a row on the «точный удар» bar.
	await _strike_green(_v(_panel().get("skoba", {})), 3)
	seen = await _finish()
	_check(gs.has_flag("plate_braced") and gs.has_flag("done_M15s") and gs.has_flag("rope_brought"), "three blows → M15s, rope brought: %s" % str(seen))
	await _frames(2)
	# F6: the knot — the rope's end drawn along the path; first a slip off the path (no penalty).
	var kp0 := _v(_panel().get("rope_end", {}))
	await _move(kp0)
	await _button(kp0, true)
	await _move(kp0 + Vector2(300, -260))
	await _button(kp0 + Vector2(300, -260), false)
	await _finish()
	_check(int(_panel().get("slips", 0)) == 1 and int(_panel().get("stroke", -1)) == 0 and not gs.has_flag("rope_on_ring"), "off the path — the end slips back, no penalty")
	await _tie_knot()
	await _frames(40)
	seen = await _finish()
	_check(gs.has_flag("rope_on_ring") and gs.has_flag("done_M15"), "the knot → M15: %s" % str(seen))
	# Polish 22.10 (A1): the road comes back here, at the knot — held from both ends; the lights only answer later.
	_check(gs.has_flag("road_held_both_ends") and not gs.has_flag("far_lights_answered"), "the knot holds the road from both ends (before the lights)")
	_check(seen.any(func(x): return x.contains("На том конце будто бы держат")), "Agata at the knot: «…держат с двух концов»: %s" % str(seen))
	if sr.mechanic_open:
		sr.close_mechanic()
		await _frames(2)
	# Three lights.
	_check(await _go("R1"), "Z3→R1")
	# A1: back at the pier the far bank is white for the first time — Pelageya sees it first (M16s), then the lantern.
	seen = await _finish()
	_check(gs.has_flag("done_M16s") and gs.has_flag("far_snow_seen") and not gs.has_flag("started_M16"), "M16s at the pier, the lights still the player's: %s" % str(seen))
	_check(seen.size() >= 2 and seen[1].begins_with("pelageya:") and seen[1].contains("черным-черно было"), "Pelageya notices the snow first: %s" % str(seen))
	_check(seen.any(func(x): return x.contains("Раз — пускай, два — стой")), "B10: three lights are «живые»: %s" % str(seen))
	var lay0: Node = rm.current_room.get_node("Layers")
	_check(lay0.get_node("far_snow").visible and not lay0.get_node("far_dark").visible and not lay0.get_node("far_lights").visible,
			"before the lantern: the far bank white, no lights yet")
	_check(_hotspot("pelageya").visible, "Pelageya back at the pier")
	await _use("lantern")
	await _wait_mechanic("lantern")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "lantern", "the signal lantern close-up (beat %s)" % str(sr.current_beat))
	await _finish()
	p = mv.panel
	var ld: Dictionary = _panel().get("lid_drag", {})
	var lp := _v(ld)
	var pull := float(ld.get("pull", 280.0))
	# H35 (Director 24.10): the plate is lifted by the mouse. A click without pulling opens nothing, the hint flashes.
	await _click(lp)
	await _frames(3)
	_check(int(_panel().get("flashes", -1)) == 0 and float(_panel().get("lid", 1.0)) < 0.01 and int(_panel().get("drag_clicks", 0)) == 1, "a click on the plate does not open it (%s)" % str(_panel().get("lid")))
	_check(p.drag_hint != null and p.drag_hint.visible and String(p.drag_hint.text).contains("вверх"), "the hint: pull it up")
	# Pulled half way: the plate follows the mouse; let go — it slides back down by itself, no flash.
	await _move(lp)
	await _button(lp, true)
	for k in range(1, 5):
		await _move(lp + Vector2(0, -pull * 0.45 * k / 4.0))
	var half := float(_panel().get("lid", 0.0))
	_check(half > 0.3 and half < 0.6 and bool(_panel().get("dragging", false)), "the plate follows the pointer (%.2f)" % half)
	var lid_y: float = p.lid.position.y
	_check(lid_y < float(p.lid.get_meta("rest_y")) - 10.0, "the plate moved up on screen")
	await _button(lp + Vector2(0, -pull * 0.45), false)
	var g2 := 0
	var falling: Array[float] = []
	while float(_panel().get("lid", 0.0)) > 0.0 and g2 < 300:
		falling.append(float(_panel().get("lid", 0.0)))
		await process_frame
		g2 += 1
	_check(falling.size() >= 3 and float(_panel().get("lid", 1.0)) == 0.0 and int(_panel().get("flashes", -1)) == 0, "let go half way: it slides back over %d frames, no flash" % falling.size())
	# Director / AI gate 23.10 (M2 item 16): deliberate signals a second and a half apart must count as one series.
	for i in 3:
		await _drag(lp, lp + Vector2(0, -pull), 10)
		if i == 0:
			_check(int(_panel().get("flashes", 0)) == 1 and bool(_panel().get("shutter_open", false)), "pulled to the end — the shutter opens: one flash")
		while bool(_panel().get("shutter_open", false)):
			await process_frame
		if i < 2:
			var t0: float = p.clock
			while p.clock - t0 < 1.6:
				await process_frame
	guard = 0
	while not gs.has_flag("far_lights_answered") and guard < 1200:
		await process_frame
		guard += 1
	seen = await _finish()
	_check(gs.has_flag("far_lights_answered") and gs.has_flag("road_held_both_ends") and gs.has_flag("done_M16"), "three flashes → three lights → M16: %s" % str(seen))
	_check(seen.any(func(x): return x.contains("Впервые за год огни")), "Pelageya at the answer: «Отвечают. Первые огни за год» (V13: not one more «Год там…»): %s" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	var lay: Node = rm.current_room.get_node("Layers")
	_check(lay.get_node("far_lights").visible and lay.get_node("far_snow").visible and not lay.get_node("far_dark").visible and lay.get_node("dusk").visible,
		"batch 3 layers: dusk, the far bank under snow (not dark), the three lights")
	# G45 (Director 23.10: «после использования ещё активен»): the lights have answered — the lantern is only a look now.
	var lh = rm.current_room.get_node_or_null("Hotspots/lantern")
	_check(lh != null and sr.planned_interaction(lh) in ["text", "use"], "G45: after the answer the lantern is only a look (%s)" % (sr.planned_interaction(lh) if lh else "?"))
	await _use("lantern")
	await _frames(3)
	var lseen := await _finish()
	_check(not sr.mechanic_open and lseen.size() == 1, "G45: a click on the lantern — one line, no signals again (%s)" % str(lseen))
	# H36 (T8): after the answer Pelageya goes to the boat at the turn — the empty boat from there.
	_check(not _hotspot("pelageya").visible, "H36: after the lights Pelageya is not at the pier")
	_check(await _go("Z3"), "H36: R1→Z3, to the boat at the turn")
	# Ribbon (once).
	await _use("pelageya")
	seen = await _finish()
	_check(gs.has_flag("done_M17") and gs.has_item("school_ribbon") and gs.has_flag("ferry_verified"), "the empty boat returns with the ribbon: %s" % str(seen))
	# Director 22.10: shown directly — the boat goes along the rope on its ring and no longer turns back to its pier.
	_check(seen.any(func(x): return x.begins_with("pelageya:Проверю, как на лодке")) and String(sd.scene("M17")["mandatory_lines"][0]["text"]).contains("кольцо надену"), "Pelageya puts the ring on the rope: %s" % str(seen))
	var m17_text := ""
	for ln in sd.scene("M17").get("mandatory_lines", []):
		m17_text += String(ln.get("text", "")) + "\n"
	_check(seen.any(func(x): return x.begins_with("narration:По канату скользит кольцо")) and m17_text.contains("Теперь идёт прямо"),
		"the empty boat follows the ring along the rope, not back to the pier: %s" % str(seen))
	_check(seen.any(func(x): return x == "agata:Не поворачивает. По канату идёт."), "Agata: it did not turn back")
	_check(seen.any(func(x): return x.contains("Не вернуло её! Значит, держат")), "F15: Pelageya — «Не вернуло. Значит, держат»: %s" % str(seen))
	_check(sr.journal_goal().contains("по канату"), "goal: into the boat, along the rope: %s" % sr.journal_goal())
	var n_before: int = gs.inventory.count("school_ribbon")
	await _use("pelageya")
	seen = await _finish()
	_check(seen.any(func(x): return x.begins_with("pelageya:") and x.contains("Садись")) and not seen.any(func(x): return x.contains("дом")), "F11: after the empty boat Pelageya calls into the boat (V2: not the M18p.1 line again): %s" % str(seen))
	sr.grant_item("school_ribbon")
	_check(gs.inventory.count("school_ribbon") == 1 and n_before == 1, "the ribbon is given once (talk again, grant again)")
	_check(not sr.can_start("M17"), "M17 never starts again")
	# Crossing and the far pier.
	_check(await _go("R2"), "Z3→R2 (along the rope, H36: from the turn)")
	seen = await _finish()
	_check(seen.any(func(x): return x.contains("Теперь назад не вынесет. По канату идём.")) and seen.any(func(x): return x.contains("Канат нас везёт, не лодка")),
			"F10/F15 at the crossing: «Теперь не вернёт…», «Не лодка нас везёт — канат…»: %s" % str(seen))
	_check(not rm.player.visible, "R2 is seen from the boat: no figure of Agata (player_hidden)")
	# F12 (Director 23.10): Agata hauls the boat along the rope — about ten pulls; then the far pier.
	await _wait_mechanic("crossing")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "crossing", "the crossing: haul the rope")
	var ts12 := Engine.time_scale
	Engine.time_scale = 1.0
	var gp := 0
	while sr.mechanic_open and not gs.has_flag("crossing_hauled") and gp < 60:
		if int(_panel().get("pulls", 0)) >= int(_panel().get("pulls_total", 10)):
			break   # across: the arrival plays, nothing more to haul
		gp += 1
		await _click(_v(_panel().get("center", {"x": 960, "y": 640})))
		var wp := 0
		while sr.mechanic_open and bool(_panel().get("pulling", false)) and wp < 300:
			await process_frame
			wp += 1
	var gw := 0
	while not gs.has_flag("crossing_hauled") and gw < 600:
		await process_frame
		gw += 1
	Engine.time_scale = ts12
	_check(gs.has_flag("crossing_hauled") and gp <= 14, "hauled across in %d pulls" % gp)
	seen = await _finish()
	var gr := 0
	while _room() != "R3" and gr < 600:
		await process_frame
		gr += 1
	seen += await _finish()
	_check(gs.has_flag("done_M18p") and _room() == "R3", "the crossing done, the boat at the far pier (R3): %s" % _room())
	_check(rm.player.visible, "at the far pier Agata is in the frame again")
	_check(rm.current_room.get_node_or_null("npc_mitya") != null, "Mitya is a 3D figure at the far pier")
	_check(gs.has_flag("done_M18") and gs.has_flag("met_mitya") and gs.has_flag("knows_twenty_years"), "Mitya at the far pier: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("mitya:")), "Mitya speaks")
	var m18_end := String(sd.scene("M18").get("mandatory_lines", [])[-1].get("text", ""))
	_check(seen.any(func(x): return x.begins_with("narration:Пелагея Митин рукав не выпускает")) and m18_end.contains("Он поднимает фонарь") and m18_end.contains("Пелагея у лодки остаётся"),
		"B13/C3: Mitya leads Agata with the lantern, Pelageya stays at the boat: %s / %s" % [m18_end, str(seen)])
	# F13 (Director 23.10): back into the boat — not now; Pelageya: «Сейчас — к матери. Назад повезу завтра».
	var back = rm.current_room.get_node_or_null("Exits/to_R2")
	_check(back != null and not back.is_open(), "the boat back is closed after the crossing")
	sr.use_exit(back)
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "R3.exit_R2.closed" and String(sr.current_beat.get("speaker", "")) == "pelageya",
			"Pelageya: «Сейчас — к матери. Назад повезу завтра» (%s)" % str(sr.current_beat))
	await _finish()
	_check(_room() == "R3", "still at the far pier")
	# Block 3 (22.10): the path leads up to the street of Olkhovka — the meeting with mother (M19) starts there.
	_check(await _go("O4"), "the path leads up to the street of Olkhovka")
	_check(gs.has_flag("started_M19"), "the meeting with mother begins on the street (M19)")
	await _finish()
	_check(gs.inventory.count("school_ribbon") == 1, "ribbon still once")
	_npc_goal_check = false
	Engine.time_scale = 1.0


## «Точный удар» (F7, F8): `n` strikes, each when the marker is near the middle of the green (time scale 1 for it).
func _strike_green(at: Vector2, n: int) -> void:
	var ts := Engine.time_scale
	Engine.time_scale = 1.0
	await _move(at)
	for i in n:
		var g := 0
		while g < 900:
			var t: Dictionary = _panel().get("timing", {})
			if t.is_empty():
				break
			var z: Array = t.get("zone", [0.4, 0.6])
			var c := (float(z[0]) + float(z[1])) * 0.5
			if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and absf(float(t.get("pos", 0.0)) - c) < 0.03:
				break
			await process_frame
			g += 1
		await _button(at, true)
		await _button(at, false)
	Engine.time_scale = ts


## «Протянуть узел» (F6): take the rope's end and draw it along every stroke of the knot.
func _tie_knot() -> void:
	var pr := _panel()
	var strokes: Array = pr.get("strokes", [])
	var start := _v(pr.get("rope_end", {}))
	await _move(start)
	await _button(start, true)
	var last := start
	for st in strokes:
		for j in range(1, st.size()):
			var a := _v(st[j - 1])
			var b := _v(st[j])
			var steps := maxi(1, int(a.distance_to(b) / 20.0))
			for k in steps:
				last = a.lerp(b, float(k + 1) / steps)
				await _move(last)
	await _button(last, false)


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


## F8: «стой» while the hook is at the bar — the first strike when the sway marker is near the middle of the green.
func _ring_stop_at_bar(at: Vector2) -> void:
	var p = mv.panel
	var g := 0
	while g < 1500:
		var hk: Dictionary = p.probe().get("hook", {})
		if String(hk.get("state", "")) == "sway":
			var lg = p.hook.timing
			if absf(lg.pos() - lg.center) < 0.04:
				break
		await process_frame
		g += 1
	await _ring(at, 2)


## F8: «стой» while the hook is far from the bar.
func _ring_stop_away(at: Vector2) -> void:
	var p = mv.panel
	var g := 0
	while g < 1500:
		if String(p.hook.state) == "sway" and absf(p.hook.timing.pos() - p.hook.timing.center) > 0.35:
			break
		await process_frame
		g += 1
	await _ring(at, 2)


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
	# G19 (Director 23.10: wedges «максимально нереалистичные; подбить по 3 раза»): four painted wedges, three hits each.
	_check((pr.get("wedges", []) as Array).size() == 4 and int(pr.get("wedge_work", -1)) == 0 and not pr.get("wedge_timing", {}).is_empty()
		and int(pr["wedge_timing"].get("needed", 0)) == 3, "G19: four wedges, the first in work, three hits on the bar (%s)" % str(pr.get("wedge_hits")))
	await _drive_wedges(Vector2.INF, 3)
	pr = _panel()
	_check(int(pr.get("wedges_driven", 0)) == 1 and int(pr.get("wedge_work", -1)) == 1 and not gs.has_flag("office_mirror_clamped"),
		"three hits drive the first wedge; one is not enough (%s)" % str(pr.get("wedge_hits")))
	await _drive_wedges(Vector2.INF, 1)
	# A miss: the wedge in work jumps out, the driven one stays.
	var g := 0
	while g < 4000:
		g += 1
		var t: Dictionary = _panel().get("wedge_timing", {})
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and float(t.get("pos", 0.5)) < 0.08:
			break
		await process_frame
	await _click(_v(_panel().get("wedge_strike", {})))
	await _frames(2)
	pr = _panel()
	_check(int(pr.get("wedge_slips", 0)) == 1 and (pr.get("wedge_hits", []) as Array)[1] == 0 and int(pr.get("wedges_driven", 0)) == 1,
		"a miss: the wedge in work jumps out, the driven one stays (%s)" % str(pr.get("wedge_hits")))
	var wseen := await _finish()
	_check(wseen.any(func(x): return x.begins_with("agata:")), "Agata says so once (%s)" % str(wseen))
	# Closed and opened again: the driven wedge is still in (GameState counter).
	sr.close_mechanic()
	await _frames(2)
	await _use("stand_zm")
	await _frames(2)
	await _finish()
	p = mv.panel
	pr = _panel()
	_check(int(pr.get("wedges_driven", 0)) == 1 and int(pr.get("wedge_work", -1)) == 1, "reopened: the first wedge still driven (%s)" % str(pr.get("wedge_hits")))
	# The rest — one hit by a click on a free spot of the close-up (G26: a click anywhere strikes).
	await _drive_wedges(_v(pr.get("free_click", {})), 1)
	_check(int(_panel().get("strikes_by_click", 0)) >= 1, "a click away from the wedges strikes the one in work")
	await _drive_wedges()
	await _finish()
	_check(gs.has_flag("office_mirror_clamped"), "four wedges, three hits each — the frame is clamped")
	_check(String(_panel().get("wedge_timing", {}).get("state", "gone")) == "gone" or _panel().get("wedge_timing", {}).is_empty(), "the wedges' bar is gone once clamped")
	_check(p.office_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the office view is redrawn every frame")
	# H26: the bell of партия 10б on its suspension over the trestles — stand (with the fixed hook), body, clapper; the
	# body and the clapper swing together round the suspension point, the stand stays.
	var bwin: Node = p.get_node_or_null("BellCloseup")
	_check(bwin is SoftWindow and bwin.content.get_node_or_null("Stand") != null, "the bell close-up of партия 10б, its edges fading (no pasted rectangle)")
	_check(p.bell.get_node_or_null("Body") != null and p.bell_clapper != null and p.bell_clapper.get_parent() == p.bell and p.bell_clapper.visible, "body and clapper on one swinging node; the clapper hung")
	var piv: Vector2 = p.bell.get_global_rect().position + p.bell.pivot_offset
	var bart: Dictionary = p.spec.get("bell", {}).get("art", {})
	var bk := float(p.spec.get("bell", {}).get("scale", 1.0))
	var bpos: Array = p.spec.get("bell", {}).get("pos", [0, 0])
	var bpiv: Array = bart.get("pivot", [0, 0])
	var bexp := Vector2(float(bpos[0]), float(bpos[1])) + (Vector2(float(bpiv[0]), float(bpiv[1])) - Vector2(float(bart["region"][0]), float(bart["region"][1]))) * bk
	_check(piv.distance_to(bexp) < 1.5, "the swing's pivot is the suspension point (%s vs %s)" % [str(piv), str(bexp)])
	# H27: the schedule card is built from the data's signals; the row wanted now is lit (the lantern: one strike).
	var sigs: Array = p.spec.get("bell", {}).get("signals", [])
	_check(sigs.size() == 3 and p.signal_rows.size() == 3, "a row per signal of the data (%d)" % p.signal_rows.size())
	var lt: String = p.legend_text()
	_check(lt.contains("1 удар") and lt.contains("пускай") and lt.contains("2 удара быстро") and lt.contains("стой") and lt.contains("держать"), "the legend: «1 удар — пускай», «2 удара быстро — стой», hold — «подымай» (%s)" % lt)
	_check(p.wanted_signal() == "one", "before the lantern: one strike is the row lit (%s)" % p.wanted_signal())
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
	var sw_body: float = 0.0
	for i in 6:
		await process_frame
		sw_body = maxf(sw_body, absf(p.bell.rotation_degrees))
	_check(sw_body > 0.5, "the strike swings the bell round its suspension (%.1f°)" % sw_body)
	_check(is_equal_approx(bwin.content.get_node("Stand").rotation, 0.0), "the hook and the stand stay still")
	await _button(bell, false)
	await _finish()
	_check(p.wanted_signal() == "one", "the hook at the top: «1 удар — пускай» is lit (%s)" % p.wanted_signal())
	# The hook: wrong first («стой» away from the bar) — it falls, back to the top, nothing lost.
	var counters_before: Dictionary = gs.counters.duplicate()
	await _ring(bell, 1)
	_check(p.hook.state in ["down", "sway"], "one strike — the hook goes down (%s)" % p.hook.state)
	_check(p.wanted_signal() == "two", "the hook goes: «2 удара быстро — стой» is lit (%s)" % p.wanted_signal())
	var hb: Dictionary = _panel().get("hook", {}).get("timing", {})
	_check(not hb.is_empty() and float(hb.get("zone", [0, 0])[1]) > float(hb.get("zone", [0, 0])[0]), "the upright bar beside the glass shows the bolt zone")
	await _ring_stop_away(bell)
	_check(p.hook.state in ["falling", "slipping", "wait"] and p.hook.misses == 1, "«стой» away from the bar — the hook falls (%s)" % p.hook.state)
	var guard := 0
	while p.hook.state != "wait" and guard < 900:
		await process_frame
		guard += 1
		if not sr.current_beat.is_empty():
			await _finish()
	_check(p.hook.state == "wait" and p.hook.pos == 0.0, "back at the top after the slip")
	_check(not gs.has_flag("office_unbolted") and gs.counters == counters_before, "no penalty: no flag lost, no counter grown")
	_check(p.signals_seen.has("one") and p.signals_seen.has("two"), "signals from the mouse: %s" % str(p.signals_seen))
	var legend: Node = p.find_child("BellLegend", true, false)
	_check(legend != null and legend.is_visible_in_tree() and p.legend_text().contains("держать") and p.legend_text().contains("2 удара"), "the bell legend on screen: one / two / hold for long (logic review M2, item 2)")
	# Right.
	await _ring(bell, 1)
	await _ring_stop_at_bar(bell)
	_check(p.signals_seen.has("two") and p.hook.state == "stopped", "two strikes at the bar catch the hook (%s)" % p.hook.state)
	_check(p.wanted_signal() == "long", "the hook under the bar: the long ring is lit (%s)" % p.wanted_signal())
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


## G19: the four wedges of the stand «ЗМ», three hits each on the «точный удар» bar, by real clicks on the wedge in work
## (or `at` — e.g. a free spot of the close-up) when the marker is in the middle of the green. Returns the clicks made.
func _drive_wedges(at: Vector2 = Vector2.INF, max_hits: int = 12) -> int:
	var made := 0
	var guard := 0
	# H26: the normal green is narrow (0.12) — headless frames are long, so the marker is slowed while the bot aims
	# (the clicks stay real; a player sees the normal speed).
	var ts := Engine.time_scale
	Engine.time_scale = minf(ts, 0.3)
	while made < max_hits and not gs.has_flag("office_mirror_clamped") and guard < 20000 and sr.mechanic_open:
		guard += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		var pr := _panel()
		var t: Dictionary = pr.get("wedge_timing", {})
		if t.is_empty():
			await process_frame
			continue
		var z: Array = t.get("zone", [0.4, 0.6])
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and absf(float(t.get("pos", 0.0)) - (float(z[0]) + float(z[1])) * 0.5) < 0.03:
			await _click(at if at != Vector2.INF else _v(pr.get("wedge_strike", {})))
			made += 1
			await _frames(2)
		else:
			await process_frame
	Engine.time_scale = ts
	return made


# --- Sluice by mouse (G23: «точный удар») -------------------------------------------------------------

## Strikes the sluice's bar with real clicks on the gate when the marker is in the middle of the green, `n` times
## (or until the sluice is open). Returns how many clicks were made.
func _sluice_strikes(p, n: int) -> int:
	var made := 0
	var guard := 0
	while made < n and not gs.has_flag("sluice_opened") and guard < 6000 and is_instance_valid(p) and sr.mechanic_open:
		guard += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		var t: Dictionary = _panel().get("timing", {})
		if t.is_empty():
			await process_frame
			continue
		var z: Array = t.get("zone", [0.4, 0.6])
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and absf(float(t.get("pos", 0.0)) - (float(z[0]) + float(z[1])) * 0.5) < 0.03:
			await _click(_v(_panel().get("strike", {})))
			made += 1
			await _frames(2)
		else:
			await process_frame
	return made


## After the last hit: the water settles on the last level, the event opens the sluice (≤ 900 frames).
func _wait_sluice_open() -> void:
	var g2 := 0
	while not gs.has_flag("sluice_opened") and g2 < 900 and sr.mechanic_open:
		g2 += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame


func _test_sluice_mouse() -> void:
	Engine.time_scale = 2.0
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
	_check(int(pr.get("notch", -1)) == 0 and not pr.get("timing", {}).is_empty(), "closed at the start; the «точный удар» bar under the gate")
	_check(int(pr["timing"].get("needed", 0)) == 4 and int(pr.get("steps", 0)) == 4, "G23: four steps down = four hits in a row (%s)" % str(pr["timing"].get("needed")))
	_check(bool(pr.get("work_mark_at_last", false)), "G24: the red mark on the gauge is on the last notch (level %.2f)" % float(pr.get("work_mark_level", -1)))
	# G24: the last step lands on the dial's last painted tick — where art pack 9 puts the red mark (M4_state_dial_mark_last:
	# x 811–840, y 503–524 of the canvas; the winch's socket 697, 523) — about 86° from upright.
	var tick := Vector2((811.0 + 840.0) * 0.5, (503.0 + 524.0) * 0.5) - Vector2(697, 523)
	var tick_deg := rad_to_deg(atan2(tick.x, -tick.y))
	_check(absf(float(pr.get("last_notch_deg", 0.0)) - tick_deg) < 3.0, "G24: the last notch %.0f° = the last painted tick %.0f°" % [float(pr.get("last_notch_deg", 0.0)), tick_deg])
	var dial = rm.current_room.get_node_or_null("Layers")
	_check(dial != null and (dial.find_child("dial_mark_last", true, false) != null or dial.find_child("StandIn", true, false) != null or rm.current_room.find_child("dial_mark_last", true, false) != null),
		"G24: the dial layer (pack 9) is in the room")
	_check((pr.get("overlays", []) as Array).has("dial_mark_last"), "G24: the dial with the red mark on the last tick laid over the gate in the close-up (%s)" % str(pr.get("overlays")))
	# Two hits: two notches, the water two steps down.
	await _sluice_strikes(p, 2)
	pr = _panel()
	_check(int(pr.get("notch", -1)) == 2 and not gs.has_flag("sluice_opened"), "two hits in the green: two notches (%d), not open yet" % int(pr.get("notch", -1)))
	# Right after a hit (the water still falling) a click is not a miss: Pavel says to wait.
	await _sluice_strikes(p, 1)
	await _click(_v(_panel().get("strike", {})))
	await _frames(2)
	pr = _panel()
	_check(int(pr.get("refused", 0)) >= 1 and int(pr.get("notch", -1)) == 3 and int(pr.get("slips", 0)) == 0, "a click while the water falls: «Погоди», nothing lost (%s)" % str(pr.get("refused")))
	var seen := await _finish()
	_check(seen.any(func(x): return x.begins_with("pavel:")), "Pavel says to wait: %s" % str(seen))
	# A miss (in the red): the winch slips back to the first notch, the water rises.
	var g := 0
	while g < 3000:
		g += 1
		var t: Dictionary = _panel().get("timing", {})
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and float(t.get("pos", 0.5)) < 0.08:
			break
		await process_frame
	await _click(_v(_panel().get("strike", {})))
	await _frames(2)
	pr = _panel()
	_check(int(pr.get("notch", -1)) == 0 and int(pr.get("slips", 0)) == 1 and not gs.has_flag("sluice_opened"), "a miss: back to the first notch (%d), the series again" % int(pr.get("notch", -1)))
	seen = await _finish()
	_check(seen.any(func(x): return x.begins_with("pavel:")), "Pavel: «Сорвался…» (%s)" % str(seen))
	await create_timer(1.0).timeout
	_check(float(_panel().get("level", 0.0)) > 0.9, "the water back up (%.2f)" % float(_panel().get("level", 0.0)))
	# A click on the picture away from the gate strikes too.
	var made := 0
	g = 0
	while made < 1 and g < 6000:
		g += 1
		var t: Dictionary = _panel().get("timing", {})
		var z: Array = t.get("zone", [0.4, 0.6])
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and absf(float(t.get("pos", 0.0)) - (float(z[0]) + float(z[1])) * 0.5) < 0.03:
			await _click(_v(_panel().get("free_click", {})))
			made += 1
		await process_frame
	_check(int(_panel().get("notch", -1)) == 1 and int(_panel().get("strikes_by_click", 0)) >= 1, "a click anywhere on the close-up strikes (notch %d)" % int(_panel().get("notch", -1)))
	# Closed in the middle and reopened: the series starts again from the first notch; flags untouched.
	sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLUICE_SLOT), "save with the close-up put away")
	_check(rm.load_game(SLUICE_SLOT), "load it")
	await _frames(3)
	await _use("gate")
	await _frames(2)
	await _finish()
	p = mv.panel
	_check(p.logic.notch == 0 and p.logic.settled() and not gs.has_flag("sluice_opened"), "after the load: from the first notch, nothing opened")
	await _sluice_strikes(p, 4)
	await _wait_sluice_open()
	await _frames(3)
	await _finish()
	_check(gs.has_flag("sluice_opened") and gs.has_flag("pond_lowered"), "four in a row → the sluice is open (sluice_opened, pond_lowered)")
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(2)
	var lo = rm.current_room.get_node_or_null("Layers/lever_open")
	var rot := -1.0
	if lo != null:
		for c in [lo] + lo.get_children():
			if c is Sprite2D:
				rot = c.rotation_degrees
	_check(lo != null and lo.visible and is_equal_approx(rot, 86.0), "the lever stands in the last notch in the room (%.0f°)" % rot)
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
	await _finish()   # 20 s at the glass without the watch: Agata thinks of her own watch (F4) — read it first
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
