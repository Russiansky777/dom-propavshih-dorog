extends SceneTree
## Batch K — Director's playthrough 31.10 (Docs/FEEDBACK_DIRECTOR_2026-10-31_map.md; «стр.» — a line of
## Docs/FEEDBACK_DIRECTOR_2026-10-31_raw.txt):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_k.gd
##   стр. 70: the brace on the support while the water is high — why not (not «Сюда не подходит»), the brace stays;
##   стр. 21: the house door's first unlocking says nothing of «и отсюда» (that is the side door's line);
##   стр. 17, 30, 45: the hands act only where they do something — the rope is not «reached for»;
##   стр. 12: talk and listen only while the line is being said — then the villager stands quiet (idle, facing kept);
##   стр. 101: the workshop frame of M23c shows Nina's mirror where it lies since 29.10 (the near bench), Nina facing it;
##   стр. 1: menu buttons (title, pause, the board, the journal, the top bar) tick on hover and click on press (synth);
##   стр. 3: «Загрузить» — «Сохранений нет» centred, the slot names in one column; стр. 11: no «Подсказка» on the top bar —
##     the hint button is in the journal and its hint is shown there;
##   стр. 2: the settings switches — a brass pill, dark with the knob left when off, gold with it right when on;
##   стр. 31: the gallery side door's first unlocking — the bolt drawn back (synth:bolt_unlock), once;
##   стр. 85: the hug frame F_hug_pelageya — the third boot under Pelageya's skirt is snow (tools/retouch);
##   стр. 59, 78: every villager standing on the floor is an obstruction at the feet (+ Agata's half width), the floor
##     baked again when the flags change who is shown (Pavel in the office on the first visit — visited_M3 comes after
##     the room is built); the walk tour (probe_walk_tour.gd) counts frames inside their feet;
##   стр. 105: the night of day three (M24) — the stove bench in Dunya's house (H1) as well as the bed at mum's (O3);
##   стр. 46: night fog — a dark thin haze (every daytime fog has its `_night` twin under tod_dark), lit windows ×0.78;
##   стр. 62, 87: the pond at the sluice moves on both sides, the winter water at the far pier livelier;
##   стр. 61: the office journal written on the page's ruling (10°, the lines' pitch);
##   стр. 108: from the laid log to the epilogue's bridge one black (keep_black), and a kept black never sticks;
## (in other files: стр. 5 — test_batch_j «J-E4»; стр. 4 — test_menus «Title items»; стр. 56 — test_day2 office mirror;
##  стр. 8–9 — test_agata_3d «Corners near the end»; стр. 30, 45 — test_agata_3d «Talking to someone»;
##  стр. 57–58 — test_day2 «K-58»: «Слышал я твой звон» in the office.)
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
	await _test("K-12 talking hands rest once the line is said (words still on screen): Tamara talks, then stands quiet", _test_talk_rests)
	await _test("K-101 Nina in the workshop frame: her mirror on the near bench (as in H2), she faces it", _test_workshop_frame)
	await _test("K-85 the hug of Pelageya and Mitya: two boots under her skirt, not three", _test_hug_two_boots)
	await _test("K-2 the settings switches show off and on plainly; «Облегчить мини-игры» off by default", _test_switches)
	await _test("K-build the title names its build: commit and time", _test_build_stamp)
	await _test("K-31 the side door: the bolt is heard the first time it is unlocked, not after", _test_side_door_sound)
	await _test("K-1/3/11 menus: a soft tick on hover and a click on press; «Сохранений нет» centred, names in one column; the hint is in the journal", _test_menus_k)
	await _test("K-59/78 Agata walks round the villagers: their feet are out of the floor, also when one shows up after the room is built", _test_feet_off_floor)
	await _test("K-105 the night before day four: on the stove bench in Dunya's house as well as at mum's", _test_sleep_either)
	await _test("K-46/62/87/61 the world: night fog dark, windows dimmer; the pond at the sluice moves; the journal written on its ruling", _test_world_k)
	await _test("K-108 the first span → the bridge: one black, never lifted in between", _test_one_black)
	await _test("K-75 Pelageya goes for the rope: the narration plays in deep dusk, the light comes back after it", _test_m15s_dusk)
	await _test("K-93 M23a: Nina comes up to Tamara with no black before «Тамара и сама…»", _test_m23a_no_black)
	await _test("01.11-19: the bell before the school door is seen — Agata's thought without the door; after — about the door", _test_bell_thought)
	await _test("01.11-34: class seen but not the street — the bed says to go out through the yard, not «в классе не всё»", _test_bed_street)
	await _test("01.11-44: the rope tied at the turn — «Впервые за год туман сошёл» comes right there (Z3), not only at the old pier", _test_fog_lift_at_turn)
	await _test("01.11-13: Pavel and the sluice are named in the main talk with Pelageya (M02), before M09 calls him by name", _test_pavel_line_opened)
	await _test("Frames 01.11: a timing bar's long hint wraps within the bar; «Облегчить» below it does not overlap", _test_hint_wraps)
	await _test("K-108 a kept black that no scene takes up lifts by itself", _test_kept_black_lifts)
	await _test("K-16 a room change: a villager drawn live does not read its sheets", _test_room_change_cost)
	await _test("K-74 the far pier by day: the lanterns do not glow and the figures keep daylight; in the evening both lanterns burn", _test_r3_day_lights)
	await _test("K (AI №4) the mill on day three: «Помню, Павел» only after the promise; after «матушка и брат» — «Наберём, Павел» without it", _test_m23b_promise)
	await _test("Ревью 01.11 (Б-2): after mother's answer the chalk, the bird and the mitten do not take a choice any more (no answer out of time); before it they do", _test_late_choices)
	await _test("Ревью 01.11 (В-2, В-13): a villager walking off waits through a pause (the walk ends where the tween does); the yard loop's black survives a reset", _test_pause_timers)
	await _test("Ревью 01.11 (Б-9, Б-6): the optional stories close on quests.json closes_on (the first span); Esc inside an unclosable close-up is not eaten", _test_closes_on_and_esc)
	await _test("Ревью 01.11 (Г-24): the journal keeps one line per event — «сыграла» gives way to the result, «порыбачила» to the catch (flags.json desc_unless)", _test_journal_dupes)
	await _test("Ревью 01.11 (Г-5…Г-8, Г-33): a long line is shown in pages split at sentence ends; a click turns the page, the beat (and its voice) goes on", _test_subtitle_pages)
	await _test("Ревью 01.11 (Б-4): day four by the boat — out of the crossing's black straight into the first span's frame, no empty turn between", _test_day4_arrival)
	await _test("Ревью 01.11 (А-13/А-14): the pier base before Pelageya says nothing of the rope; «кто затвором ведал» only after the sluice answer", _test_early_knowledge)
	await _test("Ревью 01.11 (Б-5/А-16): the jetty's «К лодке» on the morning of day three says «сперва с матерью», not «завтра отвезу»; before that morning the old word", _test_morning_jetty_exit)
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


## Wall-clock seconds by process frames (process_frame runs on pause too — that is the point of the pause test).
func _secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


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


func _npc(id: String) -> Node:
	return rm.current_room.get_node_or_null("npc_" + id) if rm.current_room != null else null


func _test_talk_rests() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	await _enter("Z1")
	var vd: Node = root.get_node("VoiceDirector")
	vd.call("stop")
	var h := _hotspot("tamara")
	_check(h != null, "Tamara at the counter")
	if h == null:
		return
	sr.interact(h)
	var guard := 0
	while (sr.current_beat.is_empty() or String(sr.current_beat.get("speaker", "")) != "tamara") and guard < 600:
		guard += 1
		await process_frame
	var b: Dictionary = sr.current_beat
	_check(String(b.get("speaker", "")) == "tamara", "M01 begins with Tamara (%s)" % str(b.get("speaker")))
	var npc := _npc("tamara")
	_check(npc != null, "Tamara's figure")
	if npc == null:
		return
	vd.call("stop")   # no recording heard here: the time to say it decides
	await _frames(3)
	_check(String(npc.get("state")) == "talk", "while she says it: talk (%s)" % String(npc.get("state")))
	var est: float = maxf(vd.SPEAK_MIN_S, String(b.get("text", "")).length() * vd.SPEAK_S_PER_CHAR)
	var t := 0.0
	while t < est + 0.6:
		await process_frame
		t += root.get_process_delta_time()
	_check(sr.current_beat.get("text", "") == b.get("text", ""), "the line still on screen (no click)")
	_check(String(npc.get("state")) == "quiet", "said (%.1f s) — Tamara stands quiet, the hands at rest: %s" % [est, String(npc.get("state"))])
	_check(not bool(vd.call("line_being_said", b)), "VoiceDirector: the line is said")
	# a recording that played to its end says the same at once
	sr.advance()
	await _frames(2)
	var b2: Dictionary = sr.current_beat
	_check(bool(vd.call("line_being_said", b2)), "the next line is being said as it comes up")
	var playing: bool = bool(vd.call("is_playing")) and String(vd.get("current_line")) == String(b2.get("line_id", ""))
	if playing:
		_check(bool(vd.call("line_being_said", b2)), "its recording playing: being said")
	vd.call("stop")
	vd.set("_beat_voiced", true)
	_check(not bool(vd.call("line_being_said", b2)), "its voice heard and over: said, whatever its length (%s)" % vd.call("_key_of", b2))
	while not sr.current_beat.is_empty():
		await _drain()
		await process_frame


func _test_workshop_frame() -> void:
	var fr: Dictionary = sd.rooms["F_workshop_nina"]
	var h2: Dictionary = {}
	for l in sd.rooms["H2"].get("layers", []):
		if String(l.get("id", "")) == "nina_mirror":
			h2 = l
	var ids: Array = []
	var fm: Dictionary = {}
	var nina: Dictionary = {}
	for l in fr.get("layers", []):
		ids.append(String(l.get("id", "")))
		if String(l.get("id", "")) == "nina_mirror":
			fm = l
		if String(l.get("id", "")) == "nina":
			nina = l
	for k in ["scale", "scale_pivot", "offset"]:
		_check(str(fm.get(k)) == str(h2.get(k)), "the mirror where it lies in H2 — %s %s = %s" % [k, str(fm.get(k)), str(h2.get(k))])
	_check(ids.find("nina_mirror") > ids.find("bench_front"), "the mirror on the near bench is drawn over its front edge: %s" % str(ids))
	var c: Dictionary = nina.get("compose", {})
	var feet := Vector2(float(c.get("feet", [0, 0])[0]), float(c.get("feet", [0, 0])[1])) * (1920.0 / 1672.0)
	var mirror_at := Vector2(1300, 700)   # H2: «середина вещи — экран (1300, 700)»
	var dir_i := int(c.get("dir", -1))
	# rows: 0 front, counter-clockwise; 2 — to the right of the screen
	var dirs := {0: Vector2(0, 1), 1: Vector2(1, 1), 2: Vector2(1, 0), 3: Vector2(1, -1), 4: Vector2(0, -1), 5: Vector2(-1, -1), 6: Vector2(-1, 0), 7: Vector2(-1, 1)}
	var look: Vector2 = dirs.get(dir_i, Vector2.ZERO)
	_check(look.normalized().dot((mirror_at - feet).normalized()) > 0.8, "Nina faces her mirror (row %d, feet %s → mirror %s)" % [dir_i, str(feet), str(mirror_at)])
	_check(feet.distance_to(Vector2(875, 790)) < 60.0, "Nina where Agata stands for the mirror (%s)" % str(feet))


func _test_one_black() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == "M25":
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	await _enter("Z3")
	if not sr.is_done("M25") and sr.current_beat.is_empty():
		sr.start_scene("M25")
	var black_since := false
	var lowest_after_black := 1.0
	var reached := false
	var since := 0.0
	var t := 0.0
	while t < 40.0:
		await process_frame
		var d: float = root.get_process_delta_time()
		t += d
		since += d
		var a := float(ui.call("stage_probe").get("alpha", 0.0))
		if gs.has_flag("span_first_laid") and a >= 0.999:
			black_since = true
		if black_since and sr.current_frame != "EP_tamara":
			lowest_after_black = minf(lowest_after_black, a)
		if sr.current_frame == "EP_tamara":
			reached = true
			if a < 0.05:
				break
		if sr.mechanic_open:
			gs.set_flag("span_first_laid", true)
			sr.close_mechanic()
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty() or since < 0.3:
			continue
		since = 0.0
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif b.get("type") in ["line", "narration"]:
			sr.advance()
	_check(black_since, "the end of the span goes to black")
	_check(reached, "the epilogue's bridge comes (EP_tamara)")
	_check(lowest_after_black >= 0.999, "black all the way from the log to the bridge — never lifted in between (lowest %.3f; was 0.92: the empty turn glimmered)" % lowest_after_black)
	while not sr.current_beat.is_empty() or sr.is_staging():
		await _drain()
		await process_frame
	sr.call("_on_state_reset")


## Director 01.11, 14:47 (стр. 75: «сам подумай, как гармоничнее»): the black before «Пелагея на свой причал
## возвращается…» covers the time the narration tells — the line comes in deep dusk, then the turn is lit again.
func _test_m15s_dusk() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == "M15s":
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	await _enter("Z3")
	if sr.current_beat.is_empty():
		sr.start_scene("M15s")
	var dusk_at_line := -1.0
	var boat_at_line := false
	var since := 0.0
	var t := 0.0
	while t < 30.0 and not sr.is_done("M15s"):
		await process_frame
		var d: float = root.get_process_delta_time()
		t += d
		since += d
		var b: Dictionary = sr.current_beat
		if b.is_empty() or since < 0.4 or sr.is_staging():
			continue
		if String(b.get("line_id", "")) == "M15s_2" and dusk_at_line < 0.0:
			await _wait(0.8)
			dusk_at_line = float(ui.call("stage_probe").get("alpha", 0.0))
			boat_at_line = gs.has_flag("rope_brought")
		since = 0.0
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif b.get("type") in ["line", "narration"]:
			sr.advance()
	# 01.11 (Director, line 41: «всё ещё слишком мрачно на сцене, где лодка»): a dusk, not near-black — 0.82 → 0.5
	_check(dusk_at_line >= 0.4 and dusk_at_line <= 0.6, "«Пелагея на свой причал возвращается…» is told in dusk, the scene seen (%.2f)" % dusk_at_line)
	_check(boat_at_line, "01.11 (line 41): the boat at the plate already under the narration (rope_brought)")
	await _wait(1.0)
	_check(float(ui.call("stage_probe").get("alpha", 1.0)) < 0.05, "after the narration the turn is lit again")
	sr.call("_on_state_reset")


## Director 31.10, стр. 93 (frames 01.11): Nina walks up from the path to Tamara and the line comes — no fade between.
func _test_m23a_no_black() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == "M23a":
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	await _enter("O4")
	if sr.current_beat.is_empty():
		sr.start_scene("M23a")
	var darkest := 0.0
	var t := 0.0
	var reached := false
	while t < 15.0:
		await process_frame
		t += root.get_process_delta_time()
		darkest = maxf(darkest, float(ui.call("stage_probe").get("alpha", 0.0)))
		if String(sr.current_beat.get("line_id", "")) == "M23a_0":
			reached = true
			break
	_check(reached, "the first line of M23a comes")
	_check(darkest < 0.2, "no black before it (darkest %.2f)" % darkest)
	while not sr.current_beat.is_empty() or sr.is_staging():
		await _drain()
		await process_frame
	sr.call("_on_state_reset")


func _test_hint_wraps() -> void:
	var TB = load("res://scripts/mechanics/timing_bar.gd")
	var bar = TB.new()
	root.add_child(bar)
	bar.size = Vector2(360, 40)
	bar.setup({"period_s": 2.0, "green": 0.2, "hint": "@mech.office_mirror.wedges_hint", "slow_at": "below"})
	await _frames(3)
	var h: Label = bar.hint
	_check(h != null and h.size.x <= 361.0 and h.get_line_count() >= 2, "the hint wraps inside the bar's width (%s, %d lines)" % [str(h.size) if h != null else "-", h.get_line_count() if h != null else 0])
	var sc: Control = bar.slow_check
	_check(sc == null or sc.position.y >= h.position.y + h.size.y - 1.0, "«Облегчить» sits below the wrapped hint")
	bar.queue_free()
	await _frames(1)


func _test_bell_thought() -> void:
	for door_seen in [false, true]:
		gs.reset()
		sr.call("_on_state_reset")
		_set_flags(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open"] + (["seen_school_door"] if door_seen else []))
		await _enter("H2")
		var h := _hotspot("bell")
		_check(h != null, "the bell is in the workshop")
		if h == null:
			return
		sr.interact(h)
		await _frames(1)
		var seen := await _drain()
		if door_seen:
			_check(seen.has("H2.bell.thought") and not seen.has("H2.bell.thought_early"), "door seen: the thought about the school door (%s)" % str(seen))
		else:
			_check(seen.has("H2.bell.thought_early") and not seen.has("H2.bell.thought"), "door not seen: no word about the school door (%s)" % str(seen))


func _test_bed_street() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == "M08":
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	await _enter("H1")
	await _drain()
	var h := _hotspot("lezhanka")
	_check(h != null, "the bed by the stove")
	if h == null:
		return
	sr.interact(h)
	await _frames(1)
	var seen := await _drain()
	_check(seen.has("H4.bed.early_d1_street") and not sr.is_done("N01"), "before the street: «…тропа к деревне идёт…», no night yet (%s)" % str(seen))


## Director 01.11, стр. 13: «нужен ли доп. диалог с Пелагеей, чтобы открыть линию Павла? без него странно» — in M09 Agata
## calls Pavel by name and knows the sluice holds the water; the only place that named him was an optional question.
## Now a mandatory line of M02 names the sluice and Pavel, and M02 grants knows_sluice_key.
func _test_pavel_line_opened() -> void:
	var m02: Dictionary = sd.scene("M02")
	var said := ""
	for l in m02.get("mandatory_lines", []):
		said += " " + String(l.get("text", ""))
		for t in l.get("then", []):
			said += " " + String(t.get("text", ""))
	_check(said.contains("Павл") and said.contains("затвор"), "M02 (mandatory) names Pavel and the sluice")
	_check((m02.get("grants", {}).get("flags", []) as Array).has("knows_sluice_key"), "M02 grants knows_sluice_key (the «кто затвором ведал» question is open right after)")
	var m09: Dictionary = sd.scene("M09")
	var named_in_m09 := false
	for l in m09.get("mandatory_lines", []):
		if String(l.get("speaker", "")) == "agata" and String(l.get("text", "")).contains("Павел"):
			named_in_m09 = true
	_check(not named_in_m09 or said.contains("Павл"), "Agata may call him «Павел» in M09 only because Pelageya named him before")


func _test_fog_lift_at_turn() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == "M16s":
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	await _enter("Z3")
	var seen := false
	var t := 0.0
	while t < 6.0 and not seen:
		await process_frame
		t += root.get_process_delta_time()
		seen = sr.active_scene == "M16s" or sr.is_done("M16s")
	_check(seen, "M16s starts at the turn (Z3) once M15 is done (active: %s)" % sr.active_scene)
	# She speaks M16s here, so she is here while she speaks (Director 01.11, стр. 57–58: no voice from nowhere);
	# the boat leaves for her pier only after it (the staging moved from the end of M15 to the end of M16s).
	var heard := false
	var present_all := true
	t = 0.0
	while (not sr.current_beat.is_empty() or sr.is_staging() or not sr.is_done("M16s")) and t < 40.0:
		var b: Dictionary = sr.current_beat
		if String(b.get("speaker", "")) == "pelageya":
			heard = true
			var hp := _hotspot("pelageya")
			present_all = present_all and hp != null and hp.visible
		if not b.is_empty() and String(b.get("type", "")) != "options":
			await _frames(2)
			sr.advance()
		await process_frame
		t += root.get_process_delta_time()
	_check(heard and present_all, "Pelageya is at the turn while she speaks M16s (heard %s, present %s)" % [heard, present_all])
	_check(gs.has_flag("boat_to_pier") and _hotspot("pelageya") != null and not _hotspot("pelageya").visible,
		"after M16s she takes the boat to her pier (boat_to_pier %s)" % gs.has_flag("boat_to_pier"))
	# An older save: the boat already went to the pier at the end of M15 — then M16s waits for the pier, not here.
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == "M16s":
			break
		gs.set_flag("done_" + id, true)
		for f in sd.scene(id).get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	gs.set_flag("boat_to_pier", true)
	await _enter("Z3")
	await _frames(20)
	_check(sr.active_scene != "M16s" and not sr.is_done("M16s"), "old save (boat already at the pier): M16s not at the turn")
	await _enter("R1")
	t = 0.0
	while t < 6.0 and sr.active_scene != "M16s":
		await process_frame
		t += root.get_process_delta_time()
	_check(sr.active_scene == "M16s", "…it comes at the pier instead (active: %s)" % sr.active_scene)
	while not sr.current_beat.is_empty() or sr.is_staging():
		await _drain()
		await process_frame
	sr.call("_on_state_reset")


func _test_kept_black_lifts() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	await _enter("Z1")
	# a scene's last staging keeps the black and nothing takes it up: it lifts by itself
	sr.set("stage_dim", 1.0)
	sr.set("_keep_black", true)
	sr.stage_fade.emit(1.0, 0.0)
	sr.call("_complete_scene", "M01")
	var t := 0.0
	while t < 2.0:
		await process_frame
		t += root.get_process_delta_time()
	_check(float(sr.get("stage_dim")) == 0.0 and float(ui.call("stage_probe").get("alpha", 1.0)) < 0.05,
		"no scene took the black up — back to the room (dim %.2f, alpha %.2f)" % [float(sr.get("stage_dim")), float(ui.call("stage_probe").get("alpha", 1.0))])
	gs.reset()
	sr.call("_on_state_reset")


func _test_hug_two_boots() -> void:
	var tex := load("res://assets/rooms/F_hug_pelageya/bg.png") as Texture2D
	_check(tex != null, "the hug frame is there")
	if tex == null:
		return
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	# where the generator drew a third boot (canvas 515–550 × 605–655): snow now (dark boot ≈ 0.17, snow ≈ 0.8)
	var sum := 0.0
	var n := 0
	for y in range(605, 655, 2):
		for x in range(515, 550, 2):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	_check(sum / n > 0.6, "the extra boot is gone — snow there (%.2f)" % (sum / n))
	# the two boots she stands on are kept (canvas 565–600 × 610–650: dark leather)
	sum = 0.0
	n = 0
	for y in range(610, 650, 2):
		for x in range(565, 600, 2):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	_check(sum / n < 0.35, "her own two boots stay (%.2f)" % (sum / n))


func _on_floor(p: Vector2) -> bool:
	var map: RID = rm.current_room.get_walkable().get_navigation_map()
	return NavigationServer2D.map_get_closest_point(map, p).distance_to(p) < 2.0


func _test_feet_off_floor() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "done_M12", "office_unbolted", "office_door_opened", "done_M13a"])
	_check(not gs.has_flag("visited_M3"), "the office not visited yet")
	await _enter("M3")
	for i in 4:
		await physics_frame
	var pv := _hotspot("pavel")
	_check(pv != null and pv.visible, "Pavel in the office on the first visit")
	var feet := Vector2(1284 + 183 * 0.5, 123 + 637)
	_check(not _on_floor(feet), "M3: Pavel's feet %s are not floor — Agata goes round (the floor was baked again for him)" % str(feet))
	_check(_on_floor(Vector2(1130, 790)), "M3: the place to talk to him stays floor")
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01"])
	await _enter("R1")
	for i in 4:
		await physics_frame
	var pf := Vector2(1140 + 130 * 0.5, 440 + 300)
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "Pelageya on her pier")
	_check(not _on_floor(pf), "R1: Pelageya's feet %s are not floor" % str(pf))
	_check(not _on_floor(pf + Vector2(60, 0)), "R1: nor a step beside them (Agata's half width)")
	_check(_on_floor(Vector2(950, 800)), "R1: the place to talk to her stays floor")


func _flags_before(upto: String) -> void:
	gs.reset()
	sr.call("_on_state_reset")
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


func _test_sleep_either() -> void:
	# not all deeds yet: «Рано ещё спать…» on the bench too, no night
	_flags_before("M23d")
	await _enter("H1")
	var bench := _hotspot("lezhanka")
	_check(bench != null, "the stove bench")
	if bench == null:
		return
	sr.interact(bench)
	var seen := await _drain_all()
	_check(not gs.has_flag("started_M24") and seen.has("H4.bed.early_short"), "a deed left — «Рано ещё спать» (%s)" % str(seen))
	# all four deeds done: the night on the bench
	_flags_before("M24")
	await _enter("H1")
	bench = _hotspot("lezhanka")
	sr.interact(bench)
	await _drain_all()
	_check(gs.has_flag("done_M24") and gs.has_flag("morning_day4"), "M24 on the stove bench: the night, then the morning of day four")
	_check(String(rm.current_room.get("room_id")) == "H1", "the morning where she slept (%s)" % String(rm.current_room.get("room_id")))
	_check(sd.text("@ui.bedtime_d3_goal").contains("лежанке у печи"), "the journal names both places: %s" % sd.text("@ui.bedtime_d3_goal"))
	gs.reset()
	sr.call("_on_state_reset")


func _drain_all() -> Array[String]:
	var seen: Array[String] = []
	var t := 0.0
	while t < 30.0:
		await process_frame
		t += root.get_process_delta_time()
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if not sr.is_busy() and not sr.is_staging() and t > 1.0 and not player.call("is_walking") and not player.call("is_acting"):
				break
			continue
		seen.append(String(b.get("text_key", b.get("line_id", b.get("text", "")))))
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		else:
			sr.advance()
	return seen


func _test_switches() -> void:
	var th: Theme = load("res://scripts/ui/ui_theme.gd").get_theme()
	var off: Texture2D = th.get_icon(&"unchecked", &"CheckButton")
	var on: Texture2D = th.get_icon(&"checked", &"CheckButton")
	_check(off != null and on != null and off.get_width() >= 48 and off.get_height() >= 24, "a switch big enough to read (%s)" % str(off.get_size() if off != null else null))
	if off == null or on == null:
		return
	var io := off.get_image()
	var ii := on.get_image()
	# the knob: left when off, right when on (its colour differs from the track there)
	var mid := io.get_height() / 2
	_check(io.get_pixel(io.get_width() - 12, mid).get_luminance() < 0.25 and ii.get_pixel(ii.get_width() - 12, mid).get_luminance() < 0.25
		and ii.get_pixel(12, mid).get_luminance() > 0.5, "off: dark track at the right; on: gold track at the left, dark knob at the right")
	var cfg := ConfigFile.new()
	var tb = load("res://scripts/mechanics/timing_bar.gd")
	# an old settings file with the early key on (the Director's: «по умолчанию выключено», 31.10) — the switch stays off
	var keep_path: String = tb.settings_path
	var keep_slow: bool = tb.slow
	tb.settings_path = "user://test_k2_settings.cfg"
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("access", "timing_slow", true)
	old_cfg.save(tb.settings_path)
	tb.load_settings(true)
	_check(not bool(tb.slow), "K-2: the old key timing_slow = true no longer turns «Облегчить мини-игры» on")
	tb.set_slow(true)
	tb.load_settings(true)
	_check(bool(tb.slow), "K-2: the player's own choice is kept (new key)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tb.settings_path))
	tb.settings_path = keep_path
	tb.slow = keep_slow
	var src := FileAccess.get_file_as_string("res://scripts/mechanics/timing_bar.gd")
	_check(src.contains("static var slow: bool = false"), "«Облегчить мини-игры» is off in a new game")


func _test_build_stamp() -> void:
	var TS = load("res://scripts/ui/title_screen.gd")
	var had := FileAccess.file_exists("res://build_info.json")
	var keep := FileAccess.get_file_as_string("res://build_info.json") if had else ""
	var f := FileAccess.open("res://build_info.json", FileAccess.WRITE)
	f.store_string('{"sha": "abc1234", "utc": "2026-10-31T22:40Z"}')
	f.close()
	var st: String = TS.build_stamp()
	_check(st.begins_with("сборка abc1234 · 31.10 ") or st.begins_with("сборка abc1234 · 01.11 "), "the stamp: %s" % st)
	if had:
		f = FileAccess.open("res://build_info.json", FileAccess.WRITE)
		f.store_string(keep)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://build_info.json"))
	if not had:
		_check(TS.build_stamp() == "", "no file — no stamp (the editor)")


func _test_side_door_sound() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03"])
	var heard: Array[String] = []
	var on_snd := func(sid: String): heard.append(sid)
	sr.stage_sound_requested.connect(on_snd)
	# From the lane the side door stays shut until the bolt has been drawn from inside (AI review №11) — and that
	# one-way rule must not shut it from inside too (the edge in locations.json goes both ways).
	await _enter("Z4")
	var back: Node = null
	for e in rm.current_room.get_exits():
		if String(e.get("target_room")) == "H3":
			back = e
	_check(back != null and not back.is_open(), "the lane: the side door is shut before the first pass")
	for round_i in 2:
		await _enter("H3")
		var ex: Node = null
		for e in rm.current_room.get_exits():
			if String(e.get("target_room")) == "Z4":
				ex = e
		_check(ex != null, "H3: the side door to the lane")
		if ex == null:
			break
		heard.clear()
		var opens_inside: bool = ex.is_open()
		sr.use_exit(ex)
		await _frames(4)
		if round_i == 0:
			_check(opens_inside, "the gallery: the side door opens from inside before the first pass")
			_check(heard.has("synth:bolt_unlock"), "the first time: the bolt is heard (%s)" % str(heard))
			for i in 120:
				if rm.current_room != null and rm.current_room.room_id == "Z4":
					break
				await process_frame
			_check(rm.current_room != null and rm.current_room.room_id == "Z4", "the first pass leads into the lane")
			for e in rm.current_room.get_exits():
				if String(e.get("target_room")) == "H3":
					_check(e.is_open(), "the lane: after the first pass the side door opens from outside")
		else:
			_check(not heard.has("synth:bolt_unlock"), "after that: no bolt (%s)" % str(heard))
	sr.stage_sound_requested.disconnect(on_snd)
	var st: AudioStreamWAV = load("res://scripts/mechanics/synth_sfx.gd").stream("bolt_unlock")
	_check(st != null and st.data.size() > 20000, "the engine makes the bolt sound (%d bytes)" % (st.data.size() if st != null else 0))


func _test_menus_k() -> void:
	var sfx: Node = root.get_node("SfxDirector")
	var heard: Array[String] = []
	var on_snd := func(kind: String, sid: String, _f: String):
		if kind == "ui":
			heard.append(sid)
	sfx.sound_played.connect(on_snd)
	await _frames(2)
	var jb: Button = ui.get("journal_button")
	jb.mouse_entered.emit()
	jb.pressed.emit()
	await _frames(2)
	_check(heard.has("ui_hover") and heard.has("ui_click"), "the top bar's «Журнал»: a tick on hover, a click on press (%s)" % str(heard))
	var hb: Button = ui.get("hint_button")
	var jp: Control = ui.get("journal_panel")
	_check(hb != null and jp.is_ancestor_of(hb), "«Подсказка» is a button of the journal, not of the top bar")
	_check(not (ui.get("top_bar") as Node).is_ancestor_of(hb), "no «Подсказка» on the top bar")
	gs.reset()
	sr.call("_on_state_reset")
	await _enter("H1")
	if not jp.visible:
		ui.call("toggle_journal")
	await _frames(2)
	heard.clear()
	hb.pressed.emit()
	await _frames(2)
	var jh: Label = ui.get("journal_hint_label")
	_check(jh.visible and jh.text.length() > 10, "the hint shows in the journal: «%s»" % jh.text)
	_check(not (ui.get("hint_panel") as Control).visible, "not in a panel over the room")
	_check(heard.has("ui_click"), "the journal's buttons click too")
	ui.call("toggle_journal")
	await _frames(1)
	var el: Label = ui.get("menu_empty_label")
	_check(el.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and el.size_flags_horizontal & Control.SIZE_EXPAND, "«Сохранений нет» centred")
	var names: Array = []
	for slot in (ui.get("slot_rows") as Dictionary).keys():
		var row: Control = ui.get("slot_rows")[slot]["row"]
		names.append(int((row.get_child(0) as Control).custom_minimum_size.x))
	_check(not names.is_empty() and names.all(func(w): return w == int(names[0])) and int(names[0]) >= 220, "every slot name in one column (%s)" % str(names))
	sfx.sound_played.disconnect(on_snd)


func _test_world_k() -> void:
	var dark_fog := 0
	for rid in ["Z3", "H4", "R1", "M1"]:
		var amb = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/ambient/%s.json" % rid))
		var fogs: Array = amb.get("fog", [])
		var ids: Array = fogs.map(func(f): return String(f.get("id", "")))
		for f in fogs:
			if f.has("if"):
				continue
			_check((f.get("unless", []) as Array).has("tod_dark"), "%s %s: the daytime fog is off in the dark" % [rid, f.get("id")])
			_check(ids.has(String(f.get("id", "")) + "_night"), "%s %s: a night twin" % [rid, f.get("id")])
		for f in fogs:
			if String(f.get("id", "")).ends_with("_night"):
				dark_fog += 1
				_check(Color.html(String(f.get("color", "#ffffff"))).get_luminance() < 0.3, "%s %s: dark at night (%s)" % [rid, f.get("id"), f.get("color")])
	_check(dark_fog >= 5, "night fogs: %d" % dark_fog)
	var gain := float(load("res://scripts/core/time_of_day.gd").index().get("window_gain", 1.0))
	_check(gain < 0.9 and gain > 0.6, "lit windows a little dimmer: × %.2f" % gain)
	var m4 = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/ambient/M4.json"))
	var ws := {}
	for w in m4.get("water", []):
		ws[String(w.get("id", ""))] = w
	_check(ws.has("pond_left") and ws.has("pond_rails"), "M4: the pond left of the sluice and between the rails move (%s)" % str(ws.keys()))
	_check(ws.has("river") and ws["river"].has("flow") and float(ws["river"]["ripple_px"][1]) >= 2.5, "M4: the pond right of the sluice drifts and ripples")
	var wr: Dictionary = sd.item("journal_manager").get("examine", {}).get("writing", {})
	_check(absf(float(wr.get("angle_deg", 0)) - 10.0) < 1.5 and absf(float(wr.get("line_pitch", 0)) - 27.0) < 1.5, "the journal on its ruling: %s°, pitch %s" % [wr.get("angle_deg"), wr.get("line_pitch")])


func _test_room_change_cost() -> void:
	# The placement-only sheet has the same frames, the same sizes on screen — and costs a fraction.
	var AS = load("res://scripts/actors/actor_sheet.gd")
	var t0 := Time.get_ticks_usec()
	var bare = AS.load_actor("nina", {}, false)
	var t_bare := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var full = AS.load_actor("nina")
	var t_full := (Time.get_ticks_usec() - t0) / 1000.0
	print("  K-16: nina placement-only %.0f ms, full %.0f ms" % [t_bare, t_full])
	_check(full.is_loaded() and bare.is_loaded(), "both sheets load")
	# ревью 01.11 (В-6): the sheet is kept — a second load of the same actor is the same sheet, at once; the last four
	# actors stay, the fifth pushes the oldest out
	t0 = Time.get_ticks_usec()
	var again = AS.load_actor("nina")
	var t_again := (Time.get_ticks_usec() - t0) / 1000.0
	_check(again == full and t_again < 5.0, "the second load of nina is the kept sheet, %.2f ms (was %.0f)" % [t_again, t_full])
	for id in ["pavel", "mitya", "tamara", "ulyana"]:
		AS.load_actor(id)
	_check(AS.load_actor("nina") != full, "after four other actors nina's sheet is read anew (the cache keeps %d)" % AS.CACHE_MAX)
	AS.clear_cache()
	full = AS.load_actor("nina")
	_check(not bare.textures_loaded and full.textures_loaded, "the placement-only sheet says so")
	var names: PackedStringArray = full.frames.get_animation_names()
	_check(names == bare.frames.get_animation_names(), "the same animations")
	var same := true
	for a in names:
		if full.frames.get_frame_count(a) != bare.frames.get_frame_count(a):
			same = false
			continue
		for i in full.frames.get_frame_count(a):
			if full.frames.get_frame_texture(a, i).get_size() != bare.frames.get_frame_texture(a, i).get_size():
				same = false
	_check(same, "every frame the same size on screen (placement unchanged)")
	var pages := {}
	for a in names:
		for i in bare.frames.get_frame_count(a):
			pages[(bare.frames.get_frame_texture(a, i) as AtlasTexture).atlas] = true
	_check(pages.size() == 1 and pages.has(AS.stand_in()), "placement-only frames point at the 1-px stand-in only (%d textures)" % pages.size())
	# In a room: live villagers carry the placement-only sheet; a villager whose model is missing (a machine without
	# the models) falls back to the full sheet, so it is never drawn from the 1-px stand-in.
	var LV = load("res://scripts/actors/npc_live_3d.gd")
	LV.forced = "3d"
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03"])
	var seen := 0
	for pass_i in 2:
		await _enter("O3")
		for n in rm.current_room.get_children():
			if String(n.name).begins_with("npc_") and n.get("sheet") != null:
				seen += 1
				if n.live != null:
					_check(not n.sheet.textures_loaded, "%s live: sheet pages not read" % n.name)
				else:
					_check(n.sheet.textures_loaded, "%s not live: the full sheet (no stand-in figure)" % n.name)
		await _enter("H1")
	LV.forced = ""
	_check(seen > 0, "O3 has villagers (%d)" % seen)
	# (the model cache tried here was taken back: instances share the scene's Animation resources — see Actor3D._packed)


func _test_r3_day_lights() -> void:
	var ids := ["post_lantern", "mitya_lantern", "evening_figures"]
	for case in [["day 3 morning", ["done_N02"], 0.0], ["day 4", ["done_N02", "done_M22", "done_M24"], 0.0], ["day 2 evening", ["done_N01", "done_M15"], 1.0]]:
		gs.reset()
		sr.call("_on_state_reset")
		_set_flags(case[1])
		await _enter("R3")
		var rl = rm.current_room.get_node_or_null("Lighting")
		_check(rl != null, "R3 has its lighting")
		if rl == null:
			return
		for i in 6:
			await process_frame
		for sid in ids:
			var src = rl.source(sid)
			_check(src != null, "R3: source " + sid)
			if src != null:
				_check(is_equal_approx(src.presence(), float(case[2])), "%s: %s presence %.2f, expected %.0f" % [case[0], sid, src.presence(), case[2]])


func _test_m23b_promise() -> void:
	for answer in ["pavel_answer_promise", "pavel_answer_family"]:
		gs.reset()
		sr.call("_on_state_reset")
		_set_flags(["done_N02", "done_M22", answer])
		await _enter("M1")
		sr.start_scene("M23b")
		var texts := ""
		var guard := 0
		while (not sr.current_beat.is_empty() or sr.is_busy()) and guard < 400:
			guard += 1
			var b: Dictionary = sr.current_beat
			if not b.is_empty():
				texts += String(b.get("text", "")) + "\n"
			if b.get("type") == "options":
				sr.choose(String(b.get("options", [])[0].get("id", "")))
			elif not b.is_empty():
				sr.advance()
			await process_frame
		var remembers := texts.contains("Помню, Павел")
		var plain := texts.contains("Наберём, Павел")
		if answer == "pavel_answer_promise":
			_check(remembers and not plain, "promise: «Помню, Павел», not the plain line (%s)" % [texts.substr(0, 400)])
		else:
			_check(plain and not remembers, "family: «Наберём, Павел» without «Помню» (%s)" % [texts.substr(0, 400)])


## Ревью 01.11 (логика, Б-2): the board's chalk choice, the bird's drawing and the mitten on the step leave traces that
## get their answer in M22 (Nina on the board, Ulyana on the bird, the mitten found on the path). Done after M22 they
## would get the answer at once, out of time — so they refuse with a word once the answer has been given.
func _test_late_choices() -> void:
	# before: the chalk opens the choice
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "house_unlocked", "house_open"])
	gs.add_item("chalk")
	await _enter("O1", "from_H3")
	await _drain()
	var h: Node = _hotspot("board")
	sr.select_item("chalk")
	sr.interact(h)
	var tw := 0
	while sr.current_options().is_empty() and tw < 120 and sr.current_beat.get("type", "") != "options":
		tw += 1
		await process_frame
	_check(not sr.current_options().is_empty(), "before M22 the chalk opens the choice of what to write")
	sr.choose("none")
	await _drain()
	# after: mother has answered — the chalk only says why not, nothing is set
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "house_unlocked", "house_open", "started_M19", "done_M19", "done_M21b", "done_M22", "nina_answered_board", "school_path_open", "free_walk_day3", "morning_day3", "met_nina", "met_ulyana", "seen_class_traces"])
	gs.add_item("chalk")
	gs.add_item("mitten")
	await _enter("O1", "from_O2")
	await _drain()
	h = _hotspot("board")
	sr.select_item("chalk")
	sr.interact(h)
	var seen := await _drain()
	_check(sr.current_options().is_empty() and seen.any(func(x): return String(x).contains("chalk_late")) and not gs.has_flag("board_here") and not gs.has_flag("board_mama") and gs.has_item("chalk"),
		"after M22 the chalk is refused with a word, nothing written, the chalk stays: %s" % str(seen))
	var bird: Node = _hotspot("bird_drawing")
	if bird != null:
		sr.interact(bird)
		seen = await _drain()
		_check(sr.current_options().is_empty() and seen.any(func(x): return String(x).contains("bird_drawing.late")) and not gs.has_flag("v03_marked"), "after M22 the bird takes no drawing: %s" % str(seen))
	else:
		_check(false, "the bird drawing hotspot is in the class")
	await _enter("O2", "from_O1")
	await _drain()
	var step: Node = _hotspot("porch_step")
	_check(step != null, "the porch step is in the yard")
	if step != null:
		sr.select_item("mitten")
		sr.interact(step)
		seen = await _drain()
		_check(seen.any(func(x): return String(x).contains("mitten_late")) and not gs.has_flag("mitten_placed") and gs.has_item("mitten"), "once the path is open the mitten stays in the bag: %s" % str(seen))


## Ревью 01.11 (В-2): NpcActor.go_off ended the walk by a timer that kept running while the tree was paused (Esc): after
## the pause the figure stood in idle in the middle of the way while the tween went on. Now the timer waits with the tree.
## (В-13): a new game during the yard loop's black (_run_loop) touched a freed exit — now the loop is dropped with the stage.
func _test_pause_timers() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["started_M19", "done_M19", "done_M21b", "done_M22", "free_walk_day3", "morning_day3", "house_open", "met_nina", "met_tamara", "m23a_nina_here"])
	await _enter("O4", "from_O2")
	await _drain()
	var nina: Node = rm.current_room.get_node_or_null("npc_nina")
	_check(nina != null and nina.visible, "Nina on the street (the letters, day three)")
	if nina == null:
		return
	var from: Vector2 = nina.global_position
	var secs := 1.0
	nina.call("go_off", from + Vector2(-240, 0), secs, false, rm.current_room)
	await _secs(0.3)
	var mid: Vector2 = nina.global_position
	_check(bool(nina.get("walking")) and mid.distance_to(from) > 20.0, "she is on her way (%.0f px)" % mid.distance_to(from))
	paused = true   # the SceneTree itself
	await _secs(secs + 0.3)   # longer than the whole walk: an unpaused timer would have ended it by now
	_check(bool(nina.get("walking")) and nina.global_position.distance_to(mid) < 2.0, "paused: still walking in place, nothing ended (%s)" % str(nina.get("walking")))
	paused = false
	await _secs(secs)
	_check(not bool(nina.get("walking")) and nina.global_position.distance_to(from + Vector2(-240, 0)) < 3.0, "after the pause she finishes the way and stops at its end: %s" % str(nina.global_position))
	# В-13: the yard loop's black, then a reset before it lifts — no error, nothing left running
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "done_M07", "house_unlocked", "house_open"])
	await _enter("O2", "from_O1")
	await _drain()
	var ex: Node = null
	for e in rm.current_room.get_exits():
		if String(e.get("data").get("to", "")) == "O4":
			ex = e
	_check(ex != null, "the yard's way to the street (looped before the knot)")
	if ex != null:
		sr.use_exit(ex)
		await process_frame
		_check(bool(sr.get("_loop_running")), "the loop runs (black)")
		gs.reset()
		sr.call("_on_state_reset")
		await _secs(0.6)
		_check(not bool(sr.get("_loop_running")) and sr.current_beat.is_empty(), "a reset during the loop's black drops it: no loop running, no closed text")


func _test_closes_on_and_esc() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["started_M19", "done_M19", "done_M21b", "done_M22", "free_walk_day3", "morning_day3", "house_open", "met_nina", "met_ilya", "met_mitya"])
	_check(String(sd.scene("Q06").get("closes_on", "")) == "finale_confirmed" and String(sd.scene("Q07").get("closes_on", "")) == "finale_confirmed", "quests carry closes_on from quests.json")
	_check(sr.can_start("Q07") and sr.can_start("Q06"), "on the free day the stories can start")
	gs.set_flag("finale_confirmed", true)
	_check(not sr.can_start("Q07") and not sr.can_start("Q06") and not sr.can_start("Q02"), "after the first span (finale_confirmed) none of them starts")
	gs.set_flag("finale_confirmed", false)
	# Б-6: an unclosable close-up (the windlass of M25 is one; here any spec with closable false) lets Esc through
	var mvf: Node = main_node.get_node("MechanicView")
	var spec := {"type": "fishing", "title": "@mech.fish.label_title", "closable": false, "in_room": true, "simple": true, "float": [1600, 640], "texts": {"wait": "@mech.fish.label_wait", "again": "@mech.fish.label_again", "caught": "@mech.fish.caught", "early": "@mech.fish.early", "late": "@mech.fish.late"}}
	sr.open_mechanic(spec, "test")
	await _frames(2)
	_check(sr.mechanic_open and not (mvf.get("close_button") as Button).visible, "an unclosable close-up: no «Закрыть»")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	mvf.call("_input", ev)
	_check(sr.mechanic_open and not root.is_input_handled(), "Esc is left for the pause menu, the close-up stays")
	sr.close_mechanic()
	await _frames(2)


func _test_journal_dupes() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	gs.set_flag("ttt_played", true)
	var f: Array = sr.journal_facts()
	_check(f.any(func(x): return String(x).contains("сыграла с Ульяной")), "played, no result yet: «сыграла»: %s" % str(f))
	gs.set_flag("ttt_won", true)
	f = sr.journal_facts()
	_check(f.any(func(x): return String(x).contains("обыграла Ульяну")) and not f.any(func(x): return String(x).contains("сыграла с Ульяной")), "with the result only the result: %s" % str(f))
	gs.set_flag("mitya_fished", true)
	f = sr.journal_facts()
	_check(f.any(func(x): return String(x).contains("порыбачила")), "fished, nothing caught: «порыбачила»")
	gs.set_flag("mitya_fish_caught", true)
	f = sr.journal_facts()
	_check(f.any(func(x): return String(x).contains("окуня")) and not f.any(func(x): return String(x).contains("порыбачила")), "with the perch only the perch: %s" % str(f))


## Ревью 01.11 (Б-5/А-16): the exit R3→R2 is closed until the boat goes both ways (M23, blocks 3–5); its closed word was
## Pelageya's of the evening before («Сейчас — к матери. Завтра покатаю») — on the morning of day three «завтра» is today.
## Now the exit's `states` give the morning its own word (@R3.exit_R2.closed_morning) while `morning_day3` is set.
func _test_morning_jetty_exit() -> void:
	# the evening of day two: the old word
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "house_unlocked", "house_open", "done_M16", "done_M17", "ferry_verified", "crossing_hauled", "done_M18p", "done_M18", "met_mitya", "knows_twenty_years"])
	await _enter("R3", "from_R2")
	await _drain()
	var e: Node = rm.current_room.get_node_or_null("Exits/to_R2")
	_check(e != null, "R3 has an exit to R2 (the jetty — to the boat)")
	if e == null:
		return
	_check(not e.is_open(), "the boat back is closed before the shuttle (boat_shuttle_open)")
	sr.use_exit(e)
	var seen := await _drain()
	_check(seen.any(func(x): return String(x) == "R3.exit_R2.closed") and not seen.any(func(x): return String(x).contains("closed_morning")), "the evening before: the old word («завтра»): %s" % str(seen))
	_check(gs.current_room == "R3", "the closed exit keeps the room")
	# the morning of day three before mother's answer (M22 opens the shuttle): «сперва с матерью»
	_set_flags(["done_M19", "met_nina", "in_olkhovka", "done_M19c", "done_M20", "met_ilya", "met_ulyana", "done_N02", "morning_day3"])
	sr.use_exit(e)
	seen = await _drain()
	_check(seen.any(func(x): return String(x) == "R3.exit_R2.closed_morning") and not seen.any(func(x): return String(x) == "R3.exit_R2.closed"), "the morning of day three: «сперва с матерью», no «завтра»: %s" % str(seen))
	_check(gs.current_room == "R3", "still the jetty")
	# once the boat goes both ways the exit opens and the pull label is on it
	gs.set_flag("boat_shuttle_open", true)
	_check(e.is_open(), "with boat_shuttle_open the way to the boat is open")
	_check(String(e.current_state().get("label", "")) == "@R3.exit_R2.label_pull", "the pull label follows the open shuttle: %s" % str(e.current_state()))


## Ревью 01.11 (А-14): the look at the old pier base (Z3) spoke of the rope on the plate and «ближний конец» before
## Pelageya had said it (M02) — now a state `unless done_M02` keeps to Dunya's sheet (M01). (А-13): «А управляющий
## мельницы?» named a man nobody had mentioned — now the question is «А кто затвором ведал?» and follows the sluice answer.
func _test_early_knowledge() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "met_tamara", "knows_pier_trace"])
	gs.add_item("key_house")
	await _enter("Z3", "from_R1")
	await _drain()
	var base: Node = _hotspot("old_pier_base")
	_check(base != null, "the pier base is at the turn")
	if base != null:
		sr.interact(base)
		var seen := await _drain()
		_check(seen.has("Z3.old_pier_base.look_early") and not seen.has("Z3.old_pier_base.look"), "before M02: the early look (Dunya's sheet, no rope): %s" % str(seen))
		var early: String = sd.text("@Z3.old_pier_base.look_early")
		_check(not early.contains("канат") and not early.contains("ближний"), "the early look has no rope and no «ближний конец»: %s" % early)
		_set_flags(["done_M02", "met_pelageya", "knows_no_road", "knows_rope_on_plate"])
		sr.interact(base)
		seen = await _drain()
		_check(seen.has("Z3.old_pier_base.look") and not seen.has("Z3.old_pier_base.look_early"), "after M02: the full look: %s" % str(seen))
	# the questions at the pier: the sluice-keeper only after the sluice
	await _enter("R1", "from_Z3")
	await _drain()
	var pel: Node = _hotspot("pelageya")
	_check(pel != null, "Pelageya is at the pier on day one")
	if pel == null:
		return
	sr.interact(pel)
	var tw := 0
	while sr.current_options().is_empty() and tw < 120:
		tw += 1
		await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids.has("sluice") and not ids.has("manager"), "before the sluice answer no question about its keeper: %s" % str(ids))
	sr.choose("sluice")
	await _drain()
	_check(gs.has_flag("knows_sluice_key"), "the sluice answer is known")
	sr.interact(pel)
	tw = 0
	while sr.current_options().is_empty() and tw < 120:
		tw += 1
		await process_frame
	ids = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids.has("manager"), "after it — «А кто затвором ведал?»: %s" % str(ids))
	var lab: String = sd.text("@R1.pelageya.opt_manager")
	_check(not lab.contains("управляющ"), "the question names no manager: %s" % lab)
	# А-17: day one is a Sunday (the epilogue's «три недели спустя, среда» is day four) and the mill runs — the shifts
	# paper names no Sunday rest
	_check(not String(sd.text("@M1.schedule.paper_shifts")).contains("оскресен"), "А-17: the shifts paper has no «по воскресеньям стоять»")
	sr.choose("leave")
	await _drain()


## Ревью 01.11 (Б-4): on day four the boat's crossing (R3 → Z3 through `close_black`) came up out of the black onto the
## empty turn for its fade-in (0,7 s) and only then M25 cut to the first span's frame with the people — against G42.
## Now the black is handed over to the cut and the frame comes up out of it (StoryRunner._next_is_cut_frame).
func _test_day4_arrival() -> void:
	_flags_before("M25")
	_set_flags(["boat_shuttle_open", "boat_at_far"])
	await _enter("R3", "from_Z3")
	await _drain()
	var e: Node = rm.current_room.get_node_or_null("Exits/to_R2")
	_check(e != null and e.is_open(), "on day four the way to the boat is open")
	if e == null:
		return
	sr.use_exit(e)
	await _frames(3)
	_check(sr.mechanic_open, "the crossing opens as a close-up")
	if not sr.mechanic_open:
		return
	sr.mechanic_event("crossed")
	# from the moment the turn is the room until its frame is up, the screen stays black (no glimpse of the empty turn)
	var seen_turn := false
	var glimpse := -1.0
	var frame_up := false
	var t := 0.0
	var lifted_after := false
	while t < 6.0:
		await process_frame
		t += 1.0 / 60.0
		var a: float = float(ui.call("stage_probe").get("alpha", 0.0))
		if gs.current_room == "Z3":
			seen_turn = true
		if seen_turn and not frame_up:
			if sr.current_frame == "F_span":
				frame_up = true
			elif a < 0.95:
				glimpse = maxf(glimpse, 1.0 - a)
		if frame_up and a < 0.1:
			lifted_after = true
			break
	_check(seen_turn, "the boat brings her to the turn (Z3)")
	_check(frame_up, "M25 puts the first span's frame up")
	_check(glimpse < 0.0, "the turn is never seen before the frame (the black gave way by %.2f)" % glimpse)
	_check(lifted_after, "the frame comes up out of the black (a fade-in on the frame, within %.1f s)" % t)
	await _drain()


## Ревью 01.11 (Г-5…Г-8, Г-33): subtitles over 160 characters (Pelageya's rope, Nina's mirror, the long looks) — pages.
func _test_subtitle_pages() -> void:
	var GU = load("res://scripts/ui/game_ui.gd")
	# every line and look of the story: no page over 200 characters where a sentence end allows it
	var worst := 0
	var worst_txt := ""
	var split := 0
	var all: Array[String] = []
	for id in sd.scene_order:
		for ln in sd.scene(id).get("mandatory_lines", []):
			all.append(String(ln.get("text", "")))
	for k in sd.texts.keys():
		all.append(String(sd.texts[k].get("text", "")))
	for t in all:
		var pages: Array = GU.split_pages(t)
		if pages.size() > 1:
			split += 1
		for p in pages:
			var n: int = Gloss.plain(String(p)).length()
			if n > worst and String(p).count(". ") + String(p).count("! ") + String(p).count("? ") + String(p).count("… ") > 0:
				worst = n
				worst_txt = String(p)
	print("  pages: %d long texts split; longest page with a sentence end inside: %d" % [split, worst])
	_check(split >= 10, "the long texts are split (%d)" % split)
	_check(worst <= 200, "no page over 200 characters that could have been cut (%d): %s" % [worst, worst_txt])
	var rope := ""
	for ln in sd.scene("M02").get("mandatory_lines", []):
		if String(ln.get("text", "")).begins_with("Канат от мостового"):
			rope = String(ln["text"])
	var rp: Array = GU.split_pages(rope)
	_check(rp.size() == 2 and String(rp[0]).ends_with(".") and Gloss.plain(String(rp[0])).length() <= 170 and Gloss.plain(String(rp[1])).length() <= 170, "Pelageya's rope: two pages cut at a sentence end: %s" % str(rp))
	# in the dialogue box: the click turns the page, then advances
	gs.reset()
	sr.call("_on_state_reset")
	await _enter("H1")
	sr.call("_push", {"type": "line", "speaker": "pelageya", "speaker_name": "Пелагея", "text": rope, "line_id": "M02_5"})
	await _frames(2)
	_check(ui.get("dialogue_pages").size() == 2 and int(ui.get("dialogue_page")) == 0, "two pages, the first shown")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ui.call("_on_modal_input", ev)
	await _frames(2)
	_check(int(ui.get("dialogue_page")) == 1 and String(sr.current_beat.get("line_id", "")) == "M02_5", "the click shows the second page, the line goes on")
	ui.call("_on_modal_input", ev)
	await _frames(2)
	_check(sr.current_beat.is_empty(), "the next click goes on past the line")
