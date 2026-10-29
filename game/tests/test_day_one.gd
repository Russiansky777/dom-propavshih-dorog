extends SceneTree
## Headless test of day one by the final scenario (Docs/SCENARIO_FINAL.md, section 6; block 1, 22.10):
##   godot --headless --path game -s res://tests/test_day_one.gd
##   - the teacher's drawer (M07) gives the bridge photo, Ilya's drawing and the plan exactly once: the close-up
##     opens with them, the second click finds the drawer empty (no close-up, nothing given), a save/load never
##     gives them again and never replays M07;
##   - the brace for the plate (H2) is not taken before the plan from the school: examine and Agata's thought,
##     the bag stays without it; after the plan it is taken once, the bench is empty, a load keeps it;
##   - the night by the stove (N01): back from the school (M07 + M08) into the gallery → fade, Agata at the stove
##     in the living room (dusk under the lines), two lines of Agata and Tikhon's grumble, morning, the checkpoint
##     «День второй» with its title; it never replays — not on re-entering the gallery, not after loading
##     «День второй», not after loading the autosave; a save from before the night plays it once more; a load in
##     the middle of the night stops it (no dusk, no lines left);
##   - the shown attempt at the pier (M02): a staging between the lines — black, the deck step and the wooden
##     knock (sfx.json), then Pelageya's lines go on;
##   - the board (M08): chalk on the board offers three lines (Ilya's only once the drawing is found) and «Пока
##     ничего не писать» (the chalk stays); a written line uses the chalk up, its flag is kept for the future, the
##     board shows it (picture or stand-in text);
##   - the mitten on the school step can be picked up again — the same one, once;
##   - the first entry into the classroom: «Там зима. А у нас ещё октябрь» once (not after a load);
##   - Tikhon by questions (M03): before meeting him only a look; after — four questions, answers in his voice.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var SLOT := "test_day1_%d" % OS.get_process_id()
var PREFIX := "test_day1_%d_" % OS.get_process_id()
var sounds: Array[String] = []


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
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	rm.autosave_slot = SLOT + "_auto"
	rm.checkpoint_prefix = PREFIX
	sr.stage_sound_requested.connect(func(sid: String): sounds.append(sid))
	Engine.time_scale = 4.0
	await _test("Drawer (M07): photo, drawing and plan once — close-up with them, then an empty drawer; a load never gives them again", _test_drawer)
	await _test("Drawer before the traces (G15, Director 23.10: the refusal had no reason): it opens at once — the plan is a trace itself; M06 then M07 play, three things once; the night chain plays on", _test_drawer_order)
	await _test("Brace (H2): only a look before the plan from the school; taken once after it; a load keeps it", _test_brace)
	await _test("Night by the stove (N01): once after the school — dusk, lines, morning, «День второй»; never replays after re-entry or loads; a save from before plays it once; a load mid-night stops it", _test_night)
	await _test("Pier (M02): Pelageya's words only — no fade (G16); the closed boat says why (no road until the rope is on the plate ring; before her — «сначала поговорю», C27)", _test_pier_attempt)
	await _test("Board (M08): three lines (Ilya's after the drawing) or none; written → chalk used, flag kept, board shows it", _test_board)
	await _test("Mitten: left on the step, picked up again — the same one, once", _test_mitten)
	await _test("Classroom: «Там зима. А у нас ещё октябрь» on the first entry only (not after a load)", _test_winter)
	await _test("Tikhon (M03): a look before meeting him; then four questions, answers in his voice", _test_tikhon)
	Engine.time_scale = 1.0
	gs.reset()
	for s in [SLOT, SLOT + "_auto", SLOT + "_pre", PREFIX + "day2"]:
		gs.delete_save(s)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== day one: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room_id: String, flags: Array, items: Array = [], spawn: String = "default") -> Node:
	sr._on_state_reset()
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	for it in items:
		gs.add_item(String(it))
		gs.set_flag("has_" + String(it), true)
	rm.change_room(room_id, spawn)
	await physics_frame
	await physics_frame
	await _frames(2)
	return rm.current_room


## Advances every beat (options answered with `choices`, else the first), waits through stagings.
## Returns what was on screen: "<speaker>:<text>" for lines and narration, "options:<id>", "stage".
func _drain(choices: Array = []) -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	var staged := false
	while (not sr.current_beat.is_empty() or sr.is_staging()) and guard < 4000:
		guard += 1
		if sr.is_staging():
			if not staged:
				seen.append("stage")
				staged = true
			await process_frame
			continue
		staged = false
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


## Interacts and lets deferred scene triggers run, collecting everything shown.
func _interact(h: Node, choices: Array = []) -> Array[String]:
	sr.interact(h)
	await process_frame
	var seen := await _drain(choices)
	await _frames(2)
	seen += await _drain(choices)
	return seen


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _ui() -> Node:
	return main_node.find_child("GameUi", true, false) if main_node != null else null


func _o1_flags() -> Array:
	return ["done_M01", "done_M02", "house_unlocked", "done_M03", "house_open", "met_tikhon", "stove_lit", "done_M04",
		"seen_workshop", "seen_bell", "seen_school_door", "done_M05", "door_school_installed", "done_M06", "seen_class_traces",
		"o1_saw_winter"]


# --- Tests -------------------------------------------------------------------------------

func _test_drawer_order() -> void:
	# N5, N7 (playtest r7): the hints of the workshop step never name the school door before it is seen; the door's hints name the gallery.
	for id in ["M01", "M02", "M03", "M04"]:
		for h in sd.scene_hints(id):
			_check(not String(h).to_lower().contains("школьн"), "%s hint names the school door before it is seen: %s" % [id, h])
	for h in sd.scene_hints("M05"):
		_check(String(h).contains("галере"), "M05 hint names the gallery: %s" % h)
	var flags := _o1_flags().filter(func(f): return not ["done_M06", "seen_class_traces"].has(f))
	await _enter("O1", flags)
	_check(sr.hint_scene() == "M06", "the next step is the traces (M06), hint scene %s" % sr.hint_scene())
	var hint: Dictionary = sr.next_hint()
	_check(String(hint.get("text", "")).contains("учился"), "the first hint: someone learned here (%s)" % str(hint))
	hint = sr.next_hint()
	_check(String(hint.get("text", "")).contains("Мешок") and String(hint.get("text", "")).contains("тетради"), "the second hint names the traces (%s)" % str(hint))
	var before: int = gs.inventory.size()
	# G15: no «сначала оглядеться» — the drawer opens with its close-up and the three things, the plan written over
	# and over in different inks is a trace itself: M06 («Кто-то продолжал здесь учиться») completes, then M07.
	sr.interact(_hotspot("teacher_drawer"))
	await process_frame
	_check(sr.view_open, "the drawer opens at once, with its close-up")
	var seen := await _drain()
	await _frames(2)
	seen += await _drain()
	sr.close_view()
	await _frames(3)
	seen += await _drain()
	_check(not seen.any(func(x): return x.contains("Сначала оглядеться")), "no refusal before the traces: %s" % str(seen))
	_check(gs.has_flag("seen_class_traces") and gs.has_flag("done_M06"), "the drawer counts as the trace → M06")
	_check(gs.has_flag("done_M07") and gs.inventory.size() == before + 3, "M07: the plan read, three things once (%s)" % str(gs.inventory))
	var at6 := -1
	var at7 := -1
	for i in seen.size():
		if at6 < 0 and String(seen[i]).contains("Так здесь всё это время учились"):
			at6 = i
		if at7 < 0 and String(seen[i]).contains("Дальний держим мы»."):
			at7 = i
	_check(at6 >= 0 and at7 > at6, "M06 then M07 in order (%d, %d): %s" % [at6, at7, str(seen)])
	for id in ["sack", "notebooks"]:
		await _interact(_hotspot(id))
	_check(gs.inventory.size() == before + 3, "the traces after the drawer give nothing again (%s)" % str(gs.inventory))


func _test_drawer() -> void:
	await _enter("O1", _o1_flags())
	var h := _hotspot("teacher_drawer")
	_check(h != null and h.visible, "the drawer is there")
	var before: int = gs.inventory.size()
	sr.interact(h)
	await process_frame
	_check(sr.view_open and String(sr.view.get("id", "")) == "teacher_drawer", "the close-up of the drawer opens with the three things")
	var cv: Node = main_node.find_child("CloseupView", true, false)
	if cv == null:
		for c in main_node.get_children():
			if c.has_method("probe") and c.get("sheets") != null:
				cv = c
	if cv != null:
		var pr: Dictionary = cv.call("probe")
		var texts: Array = (pr.get("sheets", []) as Array).map(func(x): return String(x.get("text", "")))
		_check((pr.get("sheets", []) as Array).size() == 3, "photo, drawing and plan in the close-up: %s" % str(pr.get("sheets", [])))
		_check(texts.any(func(t): return String(t).begins_with("Тому, кто через эту дверь придёт")), "the plan's text on the paper (M07 verbatim)")
	else:
		_check(false, "CloseupView node not found")
	var seen := await _drain()
	await _frames(2)
	seen += await _drain()
	sr.close_view()
	await _frames(2)
	for it in ["photo_bridge", "drawing_ilya", "plan_crossing"]:
		_check(gs.inventory.count(it) == 1, "%s in the bag once" % it)
	_check(gs.inventory.size() == before + 3, "exactly three things given (%s)" % str(gs.inventory))
	_check(gs.has_flag("done_M07") and gs.has_flag("knows_crossing_plan"), "M07 done, the plan is known")
	_check(seen.any(func(x): return x.contains("с дымом")) and seen.any(func(x): return x.contains("Дальний держим мы")), "M07 lines: Ilya's boats, «Держим мы»: %s" % str(seen))
	# Director 22.10: after the plan Agata says what the rope is, before «Держим мы».
	var rope_at := -1
	var held_at := -1
	for i in seen.size():
		if seen[i].contains("Опоры стоят, канат цел") and seen[i].contains("на кольцо верну") and seen[i].contains("лодка пройдёт"):
			rope_at = i
		if seen[i].contains("Дальний держим мы»."):
			held_at = i
	_check(rope_at >= 0 and rope_at == held_at - 1, "Agata: the rope is what is left of the bridge — right before «Держим мы» (%d, %d)" % [rope_at, held_at])
	# Polish 22.10 (B7): the key line — the door remembered its frame, the rope will remember the bridge — before the rope line.
	_check(rope_at >= 1 and seen[rope_at - 1].contains("канат на своём кольце мост вспомнит"), "B7: «Дверь на своих петлях вспомнила проём…» right before the rope line: %s" % str(seen))
	_check(not gs.inventory.has("invoice_chalk") and not gs.inventory.has("photo_school_pier") and not sd.items.has("invoice_chalk"), "no chalk invoice, no pier photo any more")
	# second click: empty drawer, no close-up, nothing given
	seen = await _interact(h)
	_check(not sr.view_open, "the empty drawer opens no close-up")
	_check(gs.inventory.size() == before + 3, "nothing given twice: %s" % str(gs.inventory))
	_check(String(h.call("label_text")) == sd.text("@O1.teacher_drawer.label_open"), "the drawer is labelled empty")
	# save / load: nothing again, M07 not replayed
	_check(rm.save_game(SLOT), "save")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(sr.current_beat.is_empty() and not sr.is_staging(), "M07 does not replay after a load")
	seen = await _interact(_hotspot("teacher_drawer"))
	_check(gs.inventory.size() == before + 3 and not sr.view_open, "after a load the drawer gives nothing: %s" % str(gs.inventory))


func _test_brace() -> void:
	var flags := ["done_M01", "done_M02", "house_unlocked", "done_M03", "house_open", "met_tikhon", "stove_lit"]
	await _enter("H2", flags)
	var h := _hotspot("brace")
	_check(h != null and h.visible, "the brace is on the bench")
	# J (стр. 94): the bundle and the mirror lie on the big near bench — occluders now, so found anywhere in the room
	var layers: Node = rm.current_room
	_check(layers.find_child("skoba", true, false).visible and layers.find_child("bundle", true, false).visible and not layers.find_child("nina_mirror", true, false).visible,
		"art batch 2 on the bench: the brace with the plate drawing, the bundle wrapped")
	await _interact(_hotspot("bundle_nina"))
	_check(not layers.find_child("bundle", true, false).visible and layers.find_child("nina_mirror", true, false).visible and not gs.has_item("bundle_nina"),
		"unwrapped: the mirror in its split frame instead of the bundle, nothing in the bag")
	var seen := await _interact(h)
	_check(not gs.has_item("brace_plate") and not gs.has_flag("has_brace_plate"), "not taken before the plan")
	_check(seen.size() == 1 and seen[0].contains("на что мне скоба теперь"), "Agata's thought before the plan: %s" % str(seen))
	_check(h.visible, "still on the bench")
	seen = await _interact(h)
	_check(not gs.has_item("brace_plate"), "a second try before the plan takes nothing either")
	gs.set_flag("knows_crossing_plan", true)
	await _frames(2)
	seen = await _interact(h)
	_check(gs.inventory.count("brace_plate") == 1, "taken after the plan: %s" % str(gs.inventory))
	_check(seen.any(func(x): return x.contains("так в плане написано. Возьму")), "Agata recalls the plan: %s" % str(seen))
	_check(not h.visible and not layers.find_child("skoba", true, false).visible, "the bench is empty after taking it (no brace drawn)")
	sr.grant_item("brace_plate")
	_check(gs.inventory.count("brace_plate") == 1, "never given twice")
	_check(rm.save_game(SLOT), "save")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(gs.inventory.count("brace_plate") == 1 and not _hotspot("brace").visible, "a load keeps it in the bag once, the bench empty")


func _night_flags() -> Array:
	return _o1_flags() + ["done_M07", "knows_crossing_plan", "done_M08", "observed_path_loop", "has_plan_crossing",
		"has_photo_bridge", "has_drawing_ilya", "q04_corner_stove", "done_Q04"]


## H17: up to the attic and a click on the bed (the same path as the mouse: interact on the hotspot).
func _to_bed() -> void:
	# T6 (Director 24.10): day one ends on the lezhanka by Dunya's stove (the attic bed is Dunya's).
	rm.change_room("H1", "from_H3")
	await _frames(2)
	await _drain()
	sr.interact(_hotspot("lezhanka"))
	await _frames(1)


func _test_night() -> void:
	gs.delete_save(PREFIX + "day2")
	# Back from the school: a save made in the classroom before the night.
	await _enter("O1", _night_flags())
	_check(not gs.has_flag("started_N01"), "no night in the classroom")
	_check(rm.save_game(SLOT + "_pre"), "save before the night")
	rm.change_room("H3", "from_O1")
	await _frames(2)
	# H17 (Director 24.10): the night no longer starts by itself — Agata says it is late and where the bed is.
	_check(not gs.has_flag("started_N01") and sr.current_beat.get("text_key", "") == "H3.night.to_bed", "H17: the gallery — «пора спать, кровать на чердаке», no night yet: %s" % str(sr.current_beat))
	await _drain()
	await _to_bed()
	_check(sr.current_beat.get("text_key", "") == "H1.lezhanka.late_d1", "H17/T6: the lezhanka — «пора спать» first: %s" % str(sr.current_beat))
	sr.advance()
	await _frames(2)
	_check(gs.has_flag("started_N01") and sr.is_staging(), "the bed starts the night with a staging")
	var ui := _ui()
	var max_alpha := 0.0
	var dusk_alpha := -1.0
	var lines: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and guard < 6000:
		guard += 1
		if ui != null:
			max_alpha = maxf(max_alpha, float(ui.call("stage_probe")["alpha"]))
		if not sr.is_staging() and sr.current_beat.get("type", "") == "line":
			if dusk_alpha < 0.0:
				await _frames(2)
				dusk_alpha = float(ui.call("stage_probe")["alpha"]) if ui != null else -1.0
				_check(rm.current_room.room_id == "H1", "the lines play by the stove in the living room, room=%s" % rm.current_room.room_id)
				var p: Vector2 = rm.player.global_position
				var spawn: Vector2 = rm.current_room.get_spawn("night").global_position
				_check(p.distance_to(spawn) < 2.0, "Agata at the stove (spawn night %s), at %s" % [str(spawn), str(p)])
			lines.append("%s:%s" % [String(sr.current_beat.get("speaker", "")), String(sr.current_beat.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(3)
	_check(max_alpha > 0.97, "the staging goes black (max overlay %.2f)" % max_alpha)
	_check(dusk_alpha > 0.4 and dusk_alpha < 0.7, "the lines read over dusk (overlay %.2f)" % dusk_alpha)
	# Then the morning: Tikhon on the armchair (SCENARIO_FINAL §7 «Утро», block 2 22.10) before the checkpoint.
	_check(lines.size() == 4 and lines[0].begins_with("agata:") and lines[1].begins_with("agata:") and lines[2].begins_with("tikhon:")
		and lines[3].begins_with("tikhon:Ты с утра в колокол не бей"),
		"two lines of Agata (Ilya, the plan), Tikhon's grumble, Tikhon's morning line: %s" % str(lines))
	_check(gs.has_flag("done_N01") and gs.has_flag("night_day1"), "N01 done")
	_check(sr.stage_dim == 0.0 and (ui == null or float(ui.call("stage_probe")["alpha"]) < 0.02), "morning: the overlay is clear")
	var info: Dictionary = gs.save_info(PREFIX + "day2")
	_check(String(info.get("title", "")) == "День второй" and String(info.get("room", "")) == "H1", "checkpoint «День второй» in H1: %s" % str(info))
	_check(gs.journal_goal == String(sd.scene("N01")["goal"]), "day two goal in the journal")
	# never again: re-enter the gallery
	rm.change_room("H3", "from_H1")
	await _frames(4)
	_check(not sr.is_staging() and sr.current_beat.is_empty() and not sr.can_start("N01"), "re-entering the gallery: no night")
	# load «День второй»
	_check(rm.load_game(PREFIX + "day2"), "load «День второй»")
	await _frames(4)
	_check(rm.current_room.room_id == "H1" and not sr.is_staging() and sr.current_beat.is_empty() and gs.has_flag("done_N01"), "after loading «День второй»: morning, nothing replays")
	# the menu shows the checkpoint row with its title
	if ui != null:
		ui.call("toggle_menu")
		await _frames(2)
		var row: Dictionary = ui.get("slot_rows").get("day2", {})
		_check(not row.is_empty() and String((row["row"] as Node).get_child(0).text) == "День второй", "the menu row «День второй»")
		ui.call("toggle_menu")
	# a save from before the night: the night plays once more, then never again
	_check(rm.load_game(SLOT + "_pre"), "load the save from before the night")
	await _frames(3)
	_check(not gs.has_flag("done_N01") and rm.current_room.room_id == "O1", "before the night: O1, N01 not done")
	rm.change_room("H3", "from_O1")
	await _frames(2)
	await _drain()
	await _to_bed()
	var seen := await _drain()
	_check(gs.has_flag("done_N01") and seen.count("stage") == 2, "the night plays once from the earlier save: %s" % str(seen))
	# a load in the middle of the night stops it: no dusk, no lines left over
	_check(rm.load_game(SLOT + "_pre"), "load before the night again")
	await _frames(3)
	await _to_bed()
	sr.advance()
	var g2 := 0
	while sr.is_staging() and g2 < 600:
		g2 += 1
		await process_frame
	_check(sr.current_beat.get("type", "") == "line", "the first night line is on screen")
	_check(rm.load_game(SLOT + "_pre"), "load mid-night")
	await _frames(4)
	_check(not sr.is_staging() and sr.current_beat.is_empty() and sr.stage_dim == 0.0, "the load stopped the night: no staging, no lines, no dusk")
	_check(ui == null or float(ui.call("stage_probe")["alpha"]) < 0.02, "the overlay is clear after the load")
	_check(not gs.has_flag("done_N01") and rm.current_room.room_id == "O1", "state of the save: before the night")


func _test_pier_attempt() -> void:
	await _enter("R1", ["done_M01", "met_tamara"])
	sounds.clear()
	var ui := _ui()
	# C27 (ИИ-чтение 23.10): before talking to Pelageya Agata does not know the boat is returned.
	sr.interact(_hotspot("boat"))   # H36 (T8): the boat at the pier is looked at, no exit into it
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed_first", "C27: before M02 — «Сначала поговорю с лодочницей» (%s)" % str(sr.current_beat))
	await _drain()
	var seen := await _interact(_hotspot("pelageya"))
	_check(gs.has_flag("done_M02"), "M02 done")
	# Polish 22.10 (D23, B9, B15): the boat shown, one line about the ice, the rope and its stopper, the plate, Mitya's post.
	_check(seen.size() == 10 and not seen.has("stage") and not sr.is_staging(), "G16: ten lines (J, Р2: + the fog over the river), no fade (the shown attempt is gone): %s" % str(seen))
	_check(seen.any(func(x): return x.contains("по льду пробовали, к своему же берегу")) and seen.any(func(x): return x.contains("Вот стопор — кол с замком"))
			and seen.any(func(x): return x.contains("на той опоре фонарь зажигал")), "ice, the stopper shown, Mitya's post: %s" % str(seen))
	_check(not seen.any(func(x): return x.contains("болотом") or x.contains("Воду держит мельничный затвор")), "the marsh and the sluice are questions now, not the talk: %s" % str(seen))
	# The rest — by the player's questions (any order, as often as wanted); the sluice question tells about the key.
	sr.interact(_hotspot("pelageya"))
	await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids == ["boats", "marsh", "sluice", "manager", "leave"], "Pelageya's questions: %s" % str(ids))
	var ans := await _drain(["sluice"])
	_check(gs.has_flag("knows_sluice_key") and ans.any(func(x): return x.contains("рычаг в конторе остался")), "the sluice question: the lever is in the office (G20): %s" % str(ans))
	ans = await _interact(_hotspot("pelageya"), ["leave"])
	_check(not ans.any(func(x): return x.contains("Ступай") or x.contains("дом")), "leaving Pelageya sends Agata nowhere: %s" % str(ans))
	_check(seen[2].contains("к своему причалу") and seen[1].contains("не перевезу"), "«Не довезу. Год пробую.» — «Гребу к тому берегу…» (H3, %s)" % str(seen))
	_check(not sounds.has("door_heavy"), "G16: no staged knock any more: %s" % str(sounds))
	# Director 22.10: the rope is the last piece of the bridge — the road itself; its far end is still on the other bank.
	_check(seen.any(func(x): return x.contains("пролёты снесло, каменные опоры остались") and x.contains("Дальний конец всё там") and x.contains("на плите ближней опоры был закреплён")), "the rope is what is left of the bridge (J, Р1: «ближней опоры»): %s" % str(seen))
	_check(seen.any(func(x): return x.contains("Тянешь, будто за корягу") and x.contains("Под водой к ней не подступиться")), "the plate under water, cracked: %s" % str(seen))
	_check(sr.stage_dim == 0.0 and (ui == null or float(ui.call("stage_probe")["alpha"]) < 0.02), "no dusk left at the pier")
	_check(rm.current_room.get_node_or_null("Exits/to_R2") == null and not gs.has_flag("ferry_verified"), "the crossing stays closed (H36: no exit into the boat at the pier)")
	sr.interact(_hotspot("boat"))
	await process_frame
	# T9 (R01): before the plan (M07) Agata does not know about the ring yet — the boat just comes back; the ring after the plan.
	_check(String(sr.current_beat.get("text_key", "")) == ("R1.exit_R2.closed" if gs.has_flag("knows_crossing_plan") else "R1.boat.look_no_plan"),
		"G17/R01: closed — before the plan no ring, after it the rope on the plate ring (%s)" % sr.current_beat.get("text", ""))
	await _drain()
	for w in ["рейс", "пристан"]:
		for k in ["R1.exit_R2.closed", "R1.instruction.use", "R1.pelageya.after", "Z3.old_pier_base.label", "Z1.drawings.use", "O1.teacher_drawer.use"]:
			_check(not sd.text("@" + k).to_lower().contains(w), "«%s» is gone from %s" % [w, k])
	# Polish 22.10 (B11, B14, B16): Tamara answers questions after M01 — the school for both banks, Dunya's sheet, «сразу ехать».
	await _enter("Z1", ["done_M01", "met_tamara"])
	sr.interact(_hotspot("tamara"))
	await process_frame
	ids = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids == ["school", "sheet", "late", "leave"], "Tamara's questions: %s" % str(ids))
	ans = await _drain(["late"])
	_check(ans.any(func(x): return x.contains("Потому и писала")), "«Надо было сразу ехать» — «…Я для того и писала»: %s" % str(ans))
	ans = await _interact(_hotspot("tamara"), ["school"])
	_check(ans.any(func(x): return x.contains("на оба берега")), "the school was one for both banks: %s" % str(ans))


func _test_board() -> void:
	await _enter("O1", _o1_flags() + ["done_M07"], ["chalk"])
	var board := _hotspot("board")
	sr.select_item("chalk")
	sr.interact(board)
	await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids == ["here", "mama", "none"], "without the drawing: three choices, no Ilya's line: %s" % str(ids))
	await _drain(["none"])
	_check(gs.has_item("chalk") and not gs.has_flag("board_here") and not gs.has_flag("board_mama"), "«Пока ничего не писать»: the chalk stays in the bag")
	gs.add_item("drawing_ilya")
	gs.set_flag("has_drawing_ilya", true)
	sr.select_item("chalk")
	sr.interact(board)
	await process_frame
	ids = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids == ["here", "mama", "ilya", "none"], "with the drawing: Ilya's line too: %s" % str(ids))
	await _drain(["ilya"])
	_check(gs.has_flag("board_ilya") and not gs.has_item("chalk") and gs.has_flag("has_chalk"), "written: flag kept, chalk used up (not given again)")
	var layer: Node = rm.current_room.get_node_or_null("Layers/board_ilya")
	var spr: Sprite2D = layer.get_node_or_null("Image") if layer != null else null
	_check(layer != null and layer.visible and spr != null and spr.texture != null and spr.texture.resource_path.ends_with("state_board_ilya.png"),
		"the board shows «Илюша, я нашла твой рисунок» (chalk drawing, batch 7)")
	_check(not rm.current_room.get_node("Layers/board_written").visible and not rm.current_room.get_node("Layers/board_mama").visible,
		"exactly one line on the board: the others are not drawn")
	_check(String(board.call("label_text")).contains("Илюша"), "the board's label names the line")
	sr.select_item("chalk")
	_check(sr.selected_item == "", "no chalk to write a second line")
	_check(rm.save_game(SLOT), "save")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(rm.current_room.get_node("Layers/board_ilya").visible and gs.has_flag("board_ilya"), "a load keeps the line")
	# the picture variant
	await _enter("O1", _o1_flags() + ["done_M07"], ["chalk"])
	sr.select_item("chalk")
	sr.interact(_hotspot("board"))
	await process_frame
	await _drain(["here"])
	_check(rm.current_room.get_node("Layers/board_written").visible and not rm.current_room.get_node("Layers/board_mama").visible, "«Я была здесь. Агата» — the drawn chalk")


func _test_mitten() -> void:
	await _enter("O2", _o1_flags() + ["done_M07"], ["mitten"])
	var step := _hotspot("porch_step")
	var m := _hotspot("mitten")
	_check(m != null and not m.visible, "nothing to pick up before the mitten is left")
	sr.select_item("mitten")
	var seen := await _interact(step)
	_check(gs.has_flag("mitten_placed") and not gs.has_item("mitten"), "left on the step")
	_check(seen.any(func(x): return x.contains("по кругу дорога водит")), "«Если вернусь к ней — дорога водит по кругу»: %s" % str(seen))
	_check(m.visible and rm.current_room.get_node("Layers/mitten").visible, "the mitten lies on the step")
	seen = await _interact(m)
	_check(gs.inventory.count("mitten") == 1 and gs.has_flag("mitten_taken_back"), "picked up again: %s" % str(gs.inventory))
	_check(not m.visible and not rm.current_room.get_node("Layers/mitten").visible, "the step is empty")
	_check(String(step.call("label_text")) == sd.text("@O2.porch_step.label"), "the step's label is plain again")
	sr.grant_item("mitten")
	_check(gs.inventory.count("mitten") == 1, "never given twice")


func _test_winter() -> void:
	var flags := _o1_flags()
	flags.erase("o1_saw_winter")
	await _enter("H3", flags)
	rm.change_room("O1", "from_H3")
	await _frames(3)
	_check(String(sr.current_beat.get("text", "")) == "Тут уж зима?.. А у нас ещё октябрь! Как же это?", "first entry: «Там зима…» (%s)" % sr.current_beat.get("text", ""))
	await _drain()
	_check(gs.has_flag("o1_saw_winter"), "flag set")
	_check(rm.save_game(SLOT), "save")
	rm.change_room("O2", "from_O1")
	await _frames(2)
	await _drain()
	rm.change_room("O1", "from_O2")
	await _frames(3)
	_check(sr.current_beat.is_empty(), "second entry: no repeat")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(sr.current_beat.is_empty(), "after a load: no repeat")


func _test_tikhon() -> void:
	await _enter("H1", ["done_M01", "done_M02", "house_unlocked"])
	var t := _hotspot("tikhon")
	var seen := await _interact(t)
	_check(seen.size() == 1 and String(seen[0]).begins_with("tikhon:"), "before M03: Tikhon grumbles his own line (I-T1: always talkable): %s" % str(seen))
	gs.set_flag("met_tikhon", true)
	gs.set_flag("done_M03", true)
	await _frames(2)
	# C13 (ИИ-чтение 23.10): only about what Agata has seen — before the gallery and the workshop, nothing to ask.
	sr.interact(t)
	await process_frame
	if String(sr.current_beat.get("text_key", "")) == "H1.tikhon.ask_shelf":
		sr.advance()
		await process_frame
	var ids0: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids0 == ["tamara", "cream", "spoons", "leave"], "C13: no questions about unseen things yet: %s" % str(ids0))
	await _drain(["leave"])
	gs.set_flag("visited_H2", true)
	sr.interact(t)
	await process_frame
	if String(sr.current_beat.get("text_key", "")) == "H1.tikhon.ask_shelf":
		sr.advance()
		await process_frame
	var ids1: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids1 == ["bundle", "bell", "dunya_mend", "tamara", "cream", "spoons", "leave"], "C13: after the workshop — the bundle and the bell: %s" % str(ids1))
	await _drain(["leave"])
	gs.set_flag("visited_H3", true)
	sr.interact(t)
	await process_frame
	if String(sr.current_beat.get("text_key", "")) == "H1.tikhon.ask_shelf":
		sr.advance()
		await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids == ["door", "bundle", "bell", "dunya_mend", "tamara", "cream", "spoons", "leave"], "four questions: %s" % str(ids))
	seen = await _drain(["bundle"])
	_check(seen.any(func(x): return x.begins_with("tikhon:") and x.contains("Нинино зеркало")), "the bundle: Nina's mirror, in Tikhon's voice: %s" % str(seen))
	seen = await _interact(t, ["bell"])
	_check(seen.any(func(x): return x.begins_with("tikhon:") and x.contains("Не здесь звенит")), "the bell rings elsewhere: %s" % str(seen))
	seen = await _interact(t, ["door"])
	_check(seen.any(func(x): return x.begins_with("tikhon:") and x.contains("Нина просила")), "the door: Nina asked: %s" % str(seen))
	# M03 itself: «к вечеру» / «Вечер долгий» / «Сегодня среда?»
	var texts: Array = sd.scene("M03")["mandatory_lines"].map(func(l): return String(l["text"]))
	for want in ["К сестре пошла. [[Баяла|говорила]] — к вечеру.", "Так год уже прошёл.", "Вечер долгий.", "По средам Тамара еду приносит. Нынче среда?"]:
		_check(texts.has(want), "M03 has «%s»" % want)
