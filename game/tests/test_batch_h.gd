extends SceneTree
## Batch H, task T1 (Director's playtest 24.10, Docs/FEEDBACK_DIRECTOR_2026-10-24.md) — texts and scene logic:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_h.gd
##   - H1: one name for the aunt — Tamara explains once «тётя Дуня, мамина сестра … Евдокия»; everything else says Дуня
##     (the data check is tools/validate_story.py 1ж);
##   - H3/H23/H51: Pelageya at the boat in one tone; Tikhon's morning line soft and with a reason; Tikhon after the sad news
##     not cheerful;
##   - H33: back in the living room after the mother's mirror, Tikhon talks (three lines, once, not after a load);
##   - H42: Nina's chalk answer is on the board right after she writes it, the common date right after its line — while
##     she is still in the class;
##   - H43: Ulyana in the class answers about the bird's hat (her question, Agata's answer, hers) and talks about the lights;
##   - H49/H50: Nina hangs Dunya's coat on the hook (her own stays on her); after the sleeve is sewn the scene shows it and
##     the coat stays on its hook with «рукав зашит»;
##   - H55/H56: «А завтра тоже можно прийти?» gets Agata's answer; then black, the thanks and «Made by Yahor Zavatski»,
##     black again — and the title screen; a save after the end shows «Конец», not the credits again.
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
	await _test("H1/H3/H23/H51: the aunt explained once, then Дуня; Pelageya in one tone; Tikhon soft in the morning, not cheerful after the news", _test_lines)
	await _test("H33: after the mother's mirror Tikhon talks in the living room — three lines, once", _test_tikhon_after_mirror)
	await _test("H42: Nina's answer and the common date appear on the board while she is in the class", _test_board_in_time)
	await _test("H43: Ulyana answers about the bird's hat and talks about the lights", _test_ulyana_talk)
	await _test("H49/H50: Dunya's coat on the hook; the sewn sleeve shows and is said", _test_coat)
	await _test("H55/H56: Agata answers the last question; black → thanks + author → black → title; after a load — «Конец»", _test_finale)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch H (T1): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


## Every main scene before `upto` done with its grants and its room conditions (like RoomManager.start_at), + `extra`.
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
	for f in ["house_unlocked", "house_open", "h1_shutter_open", "h1_scarf_removed"]:
		gs.set_flag(f, true)
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	return rm.current_room


## Clicks through the beats on screen; `choices` — option ids in order (else the first). Returns "speaker:text" / "stage".
func _drain(choices: Array = [], until: Callable = Callable()) -> Array:
	var seen: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and guard < 2400:
		guard += 1
		if until.is_valid() and until.call():
			break
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


func _layer(room: Node, id: String) -> bool:
	var n := room.get_node_or_null("Layers/" + id) if room != null else null
	return n != null and (n as CanvasItem).visible


func _hotspot(room: Node, id: String) -> Node:
	return room.get_node_or_null("Hotspots/" + id) if room != null else null


func _line_text(scene_id: String, i: int) -> String:
	return String(sd.scene(scene_id)["mandatory_lines"][i].get("text", ""))


# --- Tests -------------------------------------------------------------------------------

func _test_lines() -> void:
	var m01 := _line_text("M01", 4)
	_check(m01.contains("Дуня — Евдокия, мамина сестра"), "H1: Tamara explains the aunt once: %s" % m01)
	_check(sd.text("@ui.goal_start").contains("Дуни, маминой сестры") and not sd.text("@ui.goal_start").contains("Евдоки"),
		"H1: the first goal says «тёти Дуни, маминой сестры»: %s" % sd.text("@ui.goal_start"))
	_check(sd.text("@map.house").contains("Дуни") and String(sd.scene("M21").get("title", "")).contains("Дуня"), "H1: the plan and the scene title say Дуня")
	var m02 := _line_text("M02", 2)
	_check(not m02.contains("Берег вижу") and m02.contains("к своему причалу"), "H3: Pelageya's line rewritten in one tone: %s" % m02)
	var n01 := _line_text("N01", 3)
	_check(not n01.contains("до обеда") and n01.contains("отоспаться"), "H23: Tikhon asks softly and says why: %s" % n01)
	var m23d := ""
	for ln in sd.scene("M23d")["mandatory_lines"]:
		if (ln as Dictionary).get("if", []).has("tikhon_told_nina") and String(ln.get("speaker", "")) == "tikhon":
			m23d = String(ln.get("text", ""))
	_check(m23d != "" and not m23d.contains("ещё тёплая") and m23d.contains("не трогай"), "H51: Tikhon grieves in his way: %s" % m23d)
	_check(sd.text("@Z3.old_pier_base.look").contains("За него держался мостовой канат"), "H2: what the plate's ring was for: %s" % sd.text("@Z3.old_pier_base.look"))
	_check(not sd.text("@H4.chest.look").contains("скатерть"), "H16: the chest is described as drawn (no tablecloth): %s" % sd.text("@H4.chest.look"))
	_check(not sd.text("@O2.exit_O4.loop").contains("другого окна той же школы") and sd.text("@O2.exit_O4.loop").contains("вокруг школы"),
		"H22: the loop explained: %s" % sd.text("@O2.exit_O4.loop"))


func _test_tikhon_after_mirror() -> void:
	_flags_before("M15s")
	_check(gs.has_flag("done_M15a") and not gs.has_flag("h1_tikhon_after_mirror"), "set-up: after M15a, before the talk")
	await _enter("H2")
	await _drain()
	await _enter("H1", "from_H2")
	var seen := await _drain()
	var want := ["tikhon:" + sd.text("@H1.after_mirror.tikhon_1"), "agata:" + sd.text("@H1.after_mirror.agata"), "tikhon:" + sd.text("@H1.after_mirror.tikhon_2")]
	_check(seen.size() >= 3 and seen.slice(0, 3) == want, "Tikhon, Agata, Tikhon on entering the living room: %s" % str(seen))
	_check(gs.has_flag("h1_tikhon_after_mirror"), "the talk is in the save (once)")
	await _enter("H2")
	await _drain()
	await _enter("H1", "from_H2")
	var again := await _drain()
	_check(not again.any(func(x): return String(x).contains(sd.text("@H1.after_mirror.tikhon_1"))), "not again on the next entry: %s" % str(again))
	_flags_before("M15a")
	await _enter("H1")
	var before := await _drain()
	_check(not gs.has_flag("h1_tikhon_after_mirror") and before.is_empty(), "not before the mirror: %s" % str(before))


func _test_board_in_time() -> void:
	_flags_before("M22", ["board_mama"])
	var o1 := await _enter("O1", "from_O2")
	_check(sr.active_scene == "M22", "M22 starts in the class: %s" % sr.active_scene)
	var date_line := String(_line_text("M22", 6))
	var answer_at := -1
	var date_at := -1
	var nina_there_at_answer := false
	var nina_there_at_date := false
	var lines_seen: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.active_scene == "M22") and guard < 3000:
		guard += 1
		if answer_at < 0 and _layer(o1, "nina_answer_mama"):
			answer_at = lines_seen.size()
			nina_there_at_answer = not gs.has_flag("done_M22")
		if date_at < 0 and _layer(o1, "nina_answer_date"):
			date_at = lines_seen.size()
			nina_there_at_date = not gs.has_flag("done_M22")
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			await process_frame
			continue
		if b.get("type") == "options":
			sr.choose(String(b["options"][0]["id"]))
		else:
			lines_seen.append(String(b.get("text", "")))
			sr.advance()
		await process_frame
	await _frames(3)
	var answer_line := lines_seen.find(_line_text("M22", 1))
	var date_i := lines_seen.find(date_line)
	_check(answer_line >= 0 and answer_at == answer_line + 1, "the answer «Дождалась» shows right after Nina writes it (line %d, layer at %d): %s" % [answer_line, answer_at, str(lines_seen)])
	_check(date_i >= 0 and date_at == date_i + 1, "the common date shows right after its line (line %d, layer at %d)" % [date_i, date_at])
	_check(nina_there_at_answer and nina_there_at_date, "both while Nina is still in the class (before the scene ends)")
	_check(gs.has_flag("done_M22") and gs.has_flag("nina_wrote_date") and _layer(rm.current_room, "nina_answer_mama") and _layer(rm.current_room, "nina_answer_date"),
		"after the scene both stay on the board")
	_flags_before("M22")
	o1 = await _enter("O1", "from_O2")
	await _drain()
	_check(not _layer(o1, "nina_answer_mama") and not _layer(o1, "nina_answer_here") and _layer(o1, "nina_answer_date"),
		"a blank board: no answer, only the date")
	# The acceptance start point (Docs/ACCEPTANCE_H.md): before the lesson, on the street of Olkhovka.
	_check(rm.start_at("classmama"), "?start=classmama")
	await _frames(3)
	_check(rm.current_room.room_id == "O4" and gs.has_flag("done_M21b") and not gs.has_flag("done_M22"), "classmama: the street, before the lesson")
	await _drain()


func _test_ulyana_talk() -> void:
	_flags_before("M23a", ["done_M22"])
	var o1 := await _enter("O1", "from_O2")
	await _drain()
	var h := _hotspot(o1, "ulyana")
	_check(h != null and h.visible, "Ulyana in the class after the lesson")
	if h == null:
		return
	sr.interact(h)
	await _frames(2)
	_check(String(sr.current_beat.get("type", "")) == "options" and String(sr.current_beat.get("prompt_key", "")) == "O1d.ulyana.prompt",
		"a click on Ulyana — «О чём спросить Ульяну?»: %s" % [sr.current_beat])
	var ids: Array = []
	for o in sr.current_options():
		ids.append(String(o["id"]))
	_check(ids == ["hat", "lights", "leave"], "questions: the hat, the lights, bye: %s" % str(ids))
	var seen := await _drain(["hat"])
	var want := ["options:hat", "ulyana:" + sd.text("@O1d.ulyana.hat_q"), "agata:" + sd.text("@O1d.ulyana.hat_a"), "ulyana:" + sd.text("@O1d.ulyana.hat_b")]
	_check(seen == want, "H43: her question, Agata's answer, hers: %s" % str(seen))
	_check(sd.text("@O1d.ulyana.hat_a").begins_with("Правда"), "Agata answers the question")
	sr.interact(h)
	await _frames(2)
	seen = await _drain(["lights"])
	_check(seen.size() == 5 and String(seen[3]).contains("время одно у всех") and String(seen[4]).contains("Обещаю"), "the lights: Mitya's twenty years, the road held at both ends, Agata's promise (J-A8): %s" % str(seen))


func _test_coat() -> void:
	var m23c := _line_text("M23c", 0)
	_check(m23c.contains("Дунино пальто") and m23c.contains("крючок"), "H49: Nina hangs Dunya's coat, not her own: %s" % m23c)
	_flags_before("M23d", ["done_M23c"])
	var h1 := await _enter("H1")
	await _drain()
	var coat := _hotspot(h1, "nina_coat")
	_check(coat != null and coat.visible and _layer(h1, "nina_coat"), "the coat on the hook, a hotspot over it")
	if coat == null:
		return
	_check(sd.text("@H1d.nina_coat.label") == "Дунино пальто", "its name: Дунино пальто")
	sr.interact(coat)
	await _frames(2)
	await _drain()
	if sr.view_open:
		sr.close_view()
	await _frames(2)
	await _drain()
	sr.interact(coat)
	await _frames(2)
	var seen := await _drain(["B"])
	_check(gs.has_flag("q03_patch_drawing") and gs.has_flag("done_Q03"), "Q03 done by the patch: %s" % str(seen))
	_check(seen.any(func(x): return String(x).begins_with("narration:") and String(x).contains("зашивает рукав Дуниного пальто")),
		"H50: what happened is shown: %s" % str(seen))
	_check(seen.any(func(x): return String(x).begins_with("nina:") and String(x).contains("Уля птицу на ней нарисует")), "Nina speaks of the patch")
	coat = _hotspot(rm.current_room, "nina_coat")
	_check(coat != null and coat.visible and _layer(rm.current_room, "nina_coat"), "the coat stays on its hook after the sleeve is sewn")
	if coat != null:
		sr.interact(coat)
		await _frames(2)
		var look := await _drain()
		_check(look.size() == 1 and String(look[0]).contains("Зашит рукав"), "a click: «рукав зашит»: %s" % str(look))


func _test_finale() -> void:
	var lines: Array = sd.scene("M26")["mandatory_lines"]
	_check(String(lines[-2].get("text", "")).contains("завтра тоже можно") and String(lines[-2].get("speaker", "")) == "ulyana" and String(lines[-1].get("speaker", "")) == "agata"
		and String(lines[-1].get("text", "")).contains("с обоих концов"), "H55: the last question and Agata's answer: %s" % [lines[-1]])
	var fv: Node = main_node.get_node("FrameView")
	var title: Node = main_node.get_node("Title")
	var credits: Node = fv.get("credits")
	_check(credits != null and credits.is_inside_tree(), "the credits layer is in the tree")
	if credits == null:
		return
	_check(fv.get("title") == title, "Main gives FrameView the title screen")
	_flags_before("M26")
	await _enter("Z3")
	_check(sr.active_scene == "M26", "the epilogue starts at the turn: %s" % sr.active_scene)
	Engine.time_scale = 4.0
	var seen := await _drain()
	_check(String(seen[-1]).begins_with("agata:Можно, Уля"), "Agata's answer is the last line: %s" % str(seen.slice(-2)))
	_check(gs.has_flag("game_finished"), "the game is finished")
	var phases: Array = []
	var thanks_ok := false
	for i in 1200:
		var p := String(credits.get("phase"))
		if phases.is_empty() or phases[-1] != p:
			phases.append(p)
		if p == "hold":
			var pr: Dictionary = credits.call("probe")
			thanks_ok = String(pr.get("thanks", "")) == "Спасибо за уделённое внимание, надеюсь, у Вас получилось проникнуться историей Агаты и её семьи." \
				and String(pr.get("author", "")) == "Made by Yahor Zavatski" and float(pr.get("black", 0)) > 0.99 and float(pr.get("text", 0)) > 0.99
		if p == "done":
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(phases.has("black") and phases.has("text") and phases.has("hold") and phases.has("out") and phases[-1] == "done",
		"black → text → hold → out → done: %s" % str(phases))
	_check(thanks_ok, "the thanks over black, «Made by Yahor Zavatski» under it")
	_check(bool(title.call("is_open")), "then the title screen")
	_check(not gs.has_flag("game_finished"), "the finished game's state is gone (like «В главное меню»)")
	title.call("close")
	# A save after the end (credits_seen in it): the last shot with «Конец», not the credits again.
	_flags_before("M26", ["done_M26", "epilogue_seen", "game_finished", "credits_seen"])
	sr.set_frame("EP_dinner", true)
	await _frames(4)
	_check(String(credits.get("phase")) in ["", "done"] and not bool(credits.get("visible")), "no credits the second time")
	_check(fv.get("end_panel") != null, "the end panel («Конец», traces) instead")
	sr.set_frame("", false)
	gs.reset()
	await _frames(2)
