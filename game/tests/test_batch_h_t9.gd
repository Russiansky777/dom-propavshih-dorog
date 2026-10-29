extends SceneTree
## Batch H, task T9 — the ChatGPT read-through R01–R51 (Director 24.10, 19:02; Docs/review_chatgpt_2026-10-24):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_h_t9.gd
##   1. R36: the road comes back with the knot (M15) — the school yard no longer loops and lives by the common time;
##      until the crossing (M18) Agata herself does not go on to the village (first the signal, then Pelageya); the route
##      M15 → Z3 → R1 → Z2 → H1 → H3 → O1 → O2 is open; in the morning Nina shows the path (M21b);
##   2. R39: the letters (M23a) and Nina in her sister's house (M23c) in both orders — Nina is where she is handed
##      the letters and goes back after; one figure in one place;
##   3. looks by state: no «утром прочту» after reading, no «петли у меня» after the door is hung, no ring before the plan;
##   4. Q06's trace in the epilogue with the photo on the table and on the shelf (R47);
##   5. R51 and the decision of 24.10, 22:26: on day three Pelageya waits by the boat at the turn, the crossing is short;
##   6. R20: the tea starts where it was chosen (H1 or O3), the guests come; R17: no school path in Dunya's notebook.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null


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
	await _test("T9 R36: after the knot (M15) — no loop, common time, Agata waits for the crossing; the route home and back", _test_road_after_knot)
	await _test("T9 R39: letters (M23a) and Nina in her sister's house (M23c) — both orders", _test_letters_both_orders)
	await _test("T9: looks by state — repaired things and read papers", _test_looks_by_state)
	await _test("T9 R47: Q06's frame in the epilogue with the photo on the table and on the shelf", _test_q06_trace)
	await _test("T9 R51 + 24.10 22:26: day three — Pelageya by the boat at the turn, the crossing short", _test_day3_crossing)
	await _test("T9 R20/R17: the tea where it was chosen; the school path is not in Dunya's notebook", _test_tea_and_notebook)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch H (T9): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	await _drain()   # first-entry thoughts (R1 at dusk: «Пелагеи на причале нет…»)
	return rm.current_room


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _exit(to: String) -> Node:
	return rm.current_room.get_node_or_null("Exits/to_" + to) if rm.current_room != null else null


func _layer(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("Layers/" + id) as Node2D if rm.current_room != null else null


func _layer_on(id: String) -> bool:
	var l := _layer(id)
	return l != null and l.visible


func _drain(pick_id: String = "") -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 40000:
		if sr.mechanic_open:
			# A scene's close-up (the crossing of M18p): its events done by hand, then put away — the scene goes on.
			seen.append("mechanic")
			for ev in sr.mechanic.get("events", {}).values():
				for f in ev.get("sets", []):
					gs.set_flag(String(f), true)
			sr.close_mechanic()
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if seen.is_empty() or seen.back() != "stage":
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			for o in opts:
				if String(o.get("id", "")) == pick_id:
					pick = pick_id
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", b.get("text", "")))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen



func _key_of(b: Dictionary) -> String:
	return String(b.get("text_key", ""))


## What a click on the hotspot says first (its text key, or the scene line text).
func _says(hs_id: String) -> String:
	var h := _hotspot(hs_id)
	if h == null:
		return "<no hotspot %s>" % hs_id
	sr.interact(h)
	await _frames(1)
	var k := _key_of(sr.current_beat)
	var all := [k]
	while not sr.current_beat.is_empty() and all.size() < 6:
		sr.advance()
		await process_frame
		if not sr.current_beat.is_empty():
			all.append(_key_of(sr.current_beat))
	if sr.view_open:
		sr.close_view()
	await _drain()
	return ",".join(all)


func _exit_says(to: String) -> String:
	var e := _exit(to)
	if e == null:
		return "<no exit %s>" % to
	sr.use_exit(e)
	await _frames(1)
	var t0 := Time.get_ticks_msec()
	while sr.current_beat.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	var k := _key_of(sr.current_beat)
	await _drain()
	return k


# --- 1. R36 ------------------------------------------------------------------------------

func _test_road_after_knot() -> void:
	var tod: GDScript = load("res://scripts/core/time_of_day.gd")
	# Before the knot: the yard loops back (day one and day two alike), the class keeps its own time.
	_flags_before("M15")
	_check(tod.room_state("O2") == "class_own" and tod.room_state("O1") == "class_own", "before the knot: the class and the yard in their own time")
	await _enter("O2", "porch")
	_check(await _exit_says("O4") == "O2.exit_O4.loop", "before the knot: the gate leads round the school")
	# The knot (M15): the road is held from both ends — common time at once, no loop.
	_flags_before("M16s", ["house_unlocked", "house_open"])
	_check(gs.has_flag("road_held_both_ends") and not gs.has_flag("school_path_open"), "after M15: road held, the path not shown yet")
	_check(tod.room_state("O2") != "class_own" and tod.room_state("O1") != "class_own", "after M15: no own time in the class (%s)" % tod.room_state("O2"))
	# The route of the read-through: M15 → Z3 → R1 → Z2 → H1 → H3 → O1 → O2 (from the turn — only to the pier, H7).
	var route := [["Z3", "R1"], ["R1", "Z2"], ["Z2", "H1"], ["H1", "H3"], ["H3", "O1"], ["O1", "O2"]]
	for leg in route:
		await _enter(String(leg[0]))
		var e := _exit(String(leg[1]))
		_check(e != null and e.visible and e.is_open(), "route %s → %s open" % [leg[0], leg[1]])
	await _enter("O2", "porch")
	var pos_before: Vector2 = rm.player.global_position
	_check(await _exit_says("O4") == "O2.exit_O4.wait_signal", "after M15, before the lights: «сперва к причалу»")
	_check(rm.current_room.room_id == "O2" and rm.player.global_position.distance_to(pos_before) < 1.0, "no loop: Agata is not carried round the school")
	_check(not gs.has_flag("done_M16") and not gs.has_flag("started_M18p") and not gs.has_flag("in_olkhovka"), "the order of scenes holds: no shortcut past the lights and the crossing")
	_flags_before("M17")
	await _enter("O2", "porch")
	_check(await _exit_says("O4") == "O2.exit_O4.wait_crossing", "after the lights, before the crossing: «Сначала к Пелагее»")
	_flags_before("M18")
	await _enter("O2", "porch")
	_check(await _exit_says("O4") == "O2.exit_O4.wait_crossing", "on the crossing too: «Сначала к Пелагее»")
	# Evening of day two in Olkhovka: from the street the path is under snow (not the loop, not the class's own time).
	_flags_before("M21")
	await _enter("O4")
	_check(await _exit_says("O2") == "O4.exit_O2.closed", "evening of day two: the path from the street is snowed up")
	# Morning, M21b: Nina shows the path back since the evening; reading is not named as the cause.
	var m21b: Dictionary = sd.scene("M21b")
	var txt := ""
	for l in m21b.get("mandatory_lines", []):
		txt += String(l.get("text", "")) + " "
	_check(txt.contains("с вечера"), "M21b: the path is back since the evening: %s" % txt)
	_flags_before("M22")
	await _enter("O2", "porch")
	var e2 := _exit("O4")
	_check(e2 != null and e2.is_open(), "after M21b: the gate leads to the village")


# --- 2. R39 ------------------------------------------------------------------------------

func _nina_shown(room_id: String) -> bool:
	if rm.current_room == null or rm.current_room.room_id != room_id:
		return false
	var h := _hotspot("nina")
	return h != null and h.visible


func _run_letters() -> Array:
	await _enter("O4")
	_check(not _nina_shown("O4"), "before the letters: Nina is not on the street")
	sr.interact(_hotspot("tamara"))
	await _frames(1)
	var seen_nina := false
	var lines: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging()) and Time.get_ticks_msec() - t0 < 40000:
		if gs.has_flag("m23a_nina_here") and not gs.has_flag("m23a_nina_left"):
			seen_nina = seen_nina or _nina_shown("O4")
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			await process_frame
			continue
		lines.append(String(b.get("text", "")))
		sr.advance()
		await process_frame
	await _frames(2)
	_check(seen_nina, "M23a: Nina is on the street while the letters are handed out")
	_check(gs.has_flag("done_M23a") and not _nina_shown("O4"), "after M23a: Nina gone back from the street")
	return lines


func _test_letters_both_orders() -> void:
	# Order 1: letters first, then Dunya's house.
	_flags_before("M23a")
	var lines := await _run_letters()
	_check(lines.any(func(t): return String(t).contains("Нина к письмам вернулась")), "M23a: Nina's coming back is shown: %s" % str(lines))
	_check(lines.any(func(t): return String(t).contains("в Дунин дом")), "M23a: Nina goes back to Dunya's house: %s" % str(lines))
	await _enter("H1")
	_check(gs.has_flag("done_M23c") or _nina_shown("H1") or gs.has_flag("started_M23c"), "then Dunya's house: Nina there (M23c)")
	# The one-figure rule while the letters go: Nina is not in H1 at the same time.
	_flags_before("M23a", ["done_M23c", "started_M23c", "nina_visited_house"])
	gs.set_flag("m23a_nina_here", true)
	await _enter("H1")
	_check(not _nina_shown("H1"), "during M23a: Nina not in her sister's house")
	gs.set_flag("m23a_nina_left", true)
	await _frames(2)
	_check(_nina_shown("H1"), "after M23a: Nina back in her sister's house")
	# Order 2: Dunya's house first (M23c done), then the letters.
	_flags_before("M23a", ["done_M23c", "started_M23c", "nina_visited_house"])
	await _enter("H1")
	_check(_nina_shown("H1"), "M23c done first: Nina in her sister's house")
	lines = await _run_letters()
	_check(lines.any(func(t): return String(t).contains("Нина к письмам вернулась")) and lines.any(func(t): return String(t).contains("в Дунин дом")), "order 2: Nina comes to the letters and goes back: %s" % str(lines))
	await _enter("H1")
	_check(_nina_shown("H1"), "order 2: after the letters Nina is in her sister's house again")


# --- 3. Looks by state --------------------------------------------------------------------

func _test_looks_by_state() -> void:
	# R01: the boat at the pier — before the plan no ring, after the plan the ring.
	_flags_before("M03")
	await _enter("R1")
	var s := await _says("boat")
	_check(s.begins_with("R1.boat.look_no_plan"), "before the plan: the boat comes back, no ring (%s)" % s)
	_check(not sd.text("@R1.boat.look_no_plan").contains("кольц"), "the pre-plan look names no ring")
	_flags_before("M08")
	await _enter("R1")
	s = await _says("boat")
	_check(s.begins_with("R1.exit_R2.closed"), "after the plan: the rope and the ring (%s)" % s)
	_check(not sd.text("@R1.exit_R2.closed").contains("Сюда"), "«сюда» is gone — the same words at the turn")
	# R07: the hinge box — before the door is hung «петли у меня», after — on the door.
	_flags_before("M05", ["has_door_hinges"])
	await _enter("H2")
	s = await _says("hinges_box")
	_check(s.begins_with("H2.hinges_box.empty") and not s.begins_with("H2.hinges_box.empty_hung"), "hinges taken: «у меня» (%s)" % s)
	_flags_before("M06", ["has_door_hinges"])
	await _enter("H2")
	s = await _says("hinges_box")
	_check(s.begins_with("H2.hinges_box.empty_hung"), "door hung: the hinges are on the door (%s)" % s)
	# R16/R18: the notebooks and the list — «поутру / утром» only before the morning; read — «ещё раз».
	_flags_before("M21")
	await _enter("O3")
	_check((await _says("notebooks")).begins_with("O3.notebooks.look"), "evening: the notebooks wait for the morning")
	_check((await _says("village_list")).begins_with("O3.village_list.look"), "evening: the list waits for the morning")
	_flags_before("M21b")
	await _enter("O3")
	s = await _says("notebooks")
	_check(s.begins_with("O3.notebooks.use") and s.contains("O3.notebooks.school_path_late"), "morning: read, Nina adds the school path (%s)" % s)
	s = await _says("notebooks")
	_check(s.begins_with("O3.notebooks.again"), "read: «ещё раз прочесть» (%s)" % s)
	s = await _says("village_list")
	s = await _says("village_list")
	_check(s.begins_with("O3.village_list.again"), "read: the list again, no «утром прочту» (%s)" % s)
	# R03/R04: the bell with its clapper and the stand with the mirror never say «языка нет» / «пустая».
	_flags_before("M10", ["bell_clapper_hung"])
	await _enter("H2")
	s = await _says("bell")
	_check(not s.contains("H2.bell.look"), "the clapper hung: the bell rings, not «языка нет» (%s)" % s)
	_flags_before("M11")
	await _enter("H2")
	sr.interact(_hotspot("stand_zm"))
	await _frames(1)
	_check(sr.mechanic_open and _key_of(sr.current_beat) != "H2.stand_zm.look", "the mirror on the stand: the close-up, not «пустая»")
	sr.close_mechanic()
	await _drain()


# --- 4. R47 ------------------------------------------------------------------------------

func _epilogue_texts(extra: Array) -> Array:
	_flags_before("M26", extra)
	sr.start_scene("M26")
	var seen: Array = await _drain()
	sr.set_frame("")
	return seen


func _test_q06_trace() -> void:
	for photo in ["v01_photo_table", "v01_photo_shelf"]:
		var seen := await _epilogue_texts([photo, "q06_table_at_agata", "done_V01"])
		_check(seen.any(func(x): return String(x).contains("резную рамку")), "%s + Q06 at Agata's: the frame is named (%d lines)" % [photo, seen.size()])
		_check(seen.any(func(x): return String(x).contains("семейный снимок")), "%s: the photo line plays" % photo)
	var none := await _epilogue_texts(["v01_photo_table", "done_V01"])
	_check(not none.any(func(x): return String(x).contains("резную рамку")), "without Q06: no frame line")


# --- 5. Day three crossing -------------------------------------------------------------------

func _test_day3_crossing() -> void:
	_flags_before("M23a")
	await _enter("R1")
	_check(not _nina_shown("R1") and (_hotspot("pelageya") == null or not _hotspot("pelageya").visible), "day three: Pelageya is not at her pier")
	_check(gs.has_flag("r1_saw_pelageya_at_turn_d3"), "R1 on day three: Agata's thought leads to the turn")
	await _enter("Z3")
	var p := _hotspot("pelageya")
	_check(p != null and p.visible, "day three: Pelageya by the boat at the turn")
	sr.interact(p)
	await _frames(1)
	_check(_key_of(sr.current_beat) == "R1d.pelageya.shuttle", "Pelageya: «Садись, перевезу» (%s)" % _key_of(sr.current_beat))
	await _drain()
	var e := _exit("R2")
	_check(e != null and e.visible and e.is_open(), "«В лодку» at the turn")
	sr.use_exit(e)
	await _frames(2)
	_check(sr.mechanic_open and bool(sr.mechanic.get("auto", false)), "the crossing runs by itself (auto)")
	var t0 := Time.get_ticks_msec()
	while sr.mechanic_open and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	await _frames(3)
	var took := Time.get_ticks_msec() - t0
	_check(rm.current_room.room_id == "R3" and took < 9000, "across without hands, in %d ms (room %s)" % [took, rm.current_room.room_id])
	await _drain()
	# Back: from the far pier — a click skips straight to the shore.
	var back := _exit("R2")
	_check(back != null and back.is_open(), "R3: back to the boat")
	sr.use_exit(back)
	await _frames(3)
	var mv = main_node.find_child("MechanicView", true, false)
	var panel = mv.get("panel") if mv != null else null
	_check(panel != null and panel.has_method("skip"), "the auto crossing panel")
	if panel != null:
		panel.call("pull")
	t0 = Time.get_ticks_msec()
	while sr.mechanic_open and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	await _frames(3)
	_check(rm.current_room.room_id == "Z3" and Time.get_ticks_msec() - t0 < 3000, "a click — at the turn at once (room %s)" % rm.current_room.room_id)
	await _drain()


# --- 6. Tea and the notebook ------------------------------------------------------------------

func _test_tea_and_notebook() -> void:
	_check(not sd.text("@O3.notebooks.paper_paths").contains("школьн"), "R17: no school path in Dunya's notebook")
	_check(sd.text("@O3.notebooks.school_path_late").contains("после Дуни"), "R17: Nina says it went after Dunya")
	for opt in [["A", "H1", "q08_home_evening"], ["B", "O3", "q08_open_table"]]:
		_flags_before("M24", [])
		gs.set_flag("done_Q08", false)
		await _enter("H1")
		var tc := _hotspot("tea_corner")
		_check(tc != null and tc.visible, "the tea corner in Dunya's house")
		sr.interact(tc)
		await _frames(1)
		var seen: Array = await _drain(String(opt[0]))
		_check(gs.has_flag(String(opt[2])) and gs.has_flag("done_Q08"), "%s: the tea held (%s)" % [opt[0], str(seen)])
		_check(rm.current_room.room_id == String(opt[1]), "%s: the tea where it was chosen — %s (in %s)" % [opt[0], opt[1], rm.current_room.room_id])
		_check(seen.has("stage"), "%s: a fade — the guests come" % opt[0])
		_check(seen.any(func(x): return String(x).contains("tea_corner.go_")), "%s: Agata's call to tea named: %s" % [opt[0], str(seen)])
		_check(seen.any(func(x): return String(x).contains("Допили чай")), "%s: the guests go back to their business" % opt[0])
