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
	await _test("K-108 the first span → the bridge: one black, never lifted in between", _test_one_black)
	await _test("K-108 a kept black that no scene takes up lifts by itself", _test_kept_black_lifts)
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
	_check(cfg.load("user://settings.cfg") != OK or not bool(cfg.get_value("access", "timing_slow", false)) or bool(tb.slow), "the setting as saved")
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
		sr.use_exit(ex)
		await _frames(4)
		if round_i == 0:
			_check(heard.has("synth:bolt_unlock"), "the first time: the bolt is heard (%s)" % str(heard))
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
