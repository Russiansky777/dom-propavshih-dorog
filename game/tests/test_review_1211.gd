extends SceneTree
## The whole-project review of 12.11 (Director 17:16: «Полное ревью ещё одно полностью игры сделай + определи чёткие
## шаги дальнейшие»; Docs/REVIEW_FULL_2026-11-12.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1211.gd
##   R12-1 (the first full CI run since 11.11, 43267144034: «agata gesture: LeftFoot jolted 14.2 mm per 1/60 s», «the
##       right hand jerks: 9.0 mm/frame²»): a gesture borrowed from another figure («рука к груди», «спокойный» — Agata's
##       and Nina's) takes everything below the waist from the figure's own stance clip, copied over the gesture's
##       length. The stance clip is not a loop of its own (in the stance its variants cross-fade), and copied from its
##       start again its end jumped to its start inside the gesture: as drawn, Agata's hips, head and hands went 5 cm
##       in three frames (17 mm a frame) once per stance length. Now the copy goes there and back. For every figure
##       whose data borrows clips, every borrowed clip: the hips' travel and the legs' turns it took from the stance
##       change per 1/60 s no more than in the stance clip itself. Self-check — the copy from the start again
##       (Actor3D.fill_pingpong off) is caught on Agata.
##   R12-2 (review: «служебные клавиши F2, F3, F4, F8 работают в exe у любого игрока»; Director 12.11, 21:40 «доделывай
##       до финальной версии»): on the desktop the service keys are for our own launches only — a debug build, `-- --dev`
##       or a start point (`-- --start=<id>`); a plain launch of the exported game has none. Self-check — the rule as it
##       was (everything but the web) gives them to that plain launch.
##   R12-3 (review: «заголовок окна латиницей»): with the game's main scene up the window is titled «Дом пропавших
##       дорог»; the project's name (the saves' folder) is left as it was. Self-check — before the scene the title is not it.
##   R12-4 (review: «Клик по кровати в горнице» вместо «Щёлкнуть»): no scene hint says «Клик»; self-check — the old
##       hint is caught.
##   R12-5 (review: «метка собеседника может пережить смену комнаты»): StoryRunner.talk_with set by a click on a villager
##       that said nothing is gone a second later; while a line is on screen it stays (self-check: the mark does hold
##       through a talk — Mitya's fix of 11.11).
##   R12-6 (Director 12.11, 21:40: «нужны губы как минимум»): lips by sounds in the game itself — Agata's own line played
##       by VoiceDirector: the voice's clock goes on (line_time), the line has its table of letters, and her mouth's
##       driver gets a shape for the moment being said (the shapes themselves — tests/test_jaw.gd JW-6; the tables
##       against the recordings — tools/bake_lips.py --check). Self-check — a line that is not in the table gives none.
##   R12-7 (review: «в игре нет текста лицензий движка» — needed before Steam): the settings have a «Лицензии» button
##       (not over the lists of saves); it opens a screen whose text holds the engine's license, the name of every
##       third-party component the engine reports and every license text it names, and each of the game's fonts with
##       its own license text (data/licenses.json ← assets/fonts/<font>/OFL.txt; every font folder has an entry).
##       Self-check — built without the fonts the text has no font license.
##   R12-8 (Director 12.11, 23:35: «Агата не должна закрывать кого-то»; the play of 13.11: after the meeting with her
##       brother the family stays in Nina's room until Agata goes to bed, the control is the player's, and a click on
##       Nina stood Agata with her back to us right in front of Ilya): with the family in the room — the evening from M20
##       to the morning of day three — every place Agata walks to (each hotspot's stand as it is now, the exit's, the way
##       in), every point of the floor a click can send her to and the place a real walk into the family ends at cover
##       nobody (the frames of tools/validate_rooms.py 9b, no more than its npc_overlap_max); the bed and the exit are
##       still reached. Self-checks — the measure sees the old place (1620, 880) cover Ilya; next morning the floor is
##       whole again and the talk with Nina is back at its place.

const DT := 1.0 / 60.0

var _results: Array = []
var _main: Node = null   # the game's scene, once _test_title_and_talk has put it up
var _cur_ok := true
var _cur_msgs: Array = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_cur_ok = false
		_cur_msgs.append(msg)


func _report(name: String, t0: int) -> void:
	print(("PASS  " if _cur_ok else "FAIL  ") + name + "  (%d ms)" % (Time.get_ticks_msec() - t0))
	for m in _cur_msgs:
		print("        - " + str(m))
	_results.append([name, _cur_ok])
	_cur_ok = true
	_cur_msgs = []


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	await _test_borrowed_stance()
	_report("R12-1 Borrowed gestures (review 12.11): the stance under «рука к груди» and «спокойный» has no seam — hips and legs move no faster than in the stance clip itself", t0)
	t0 = Time.get_ticks_msec()
	_test_service_keys()
	_report("R12-2 Service keys (F2/F3/F4/F8): only a debug build, «-- --dev» or a start point has them — not a player's exe", t0)
	t0 = Time.get_ticks_msec()
	_test_hint_words()
	_report("R12-4 Hints: none says «Клик» — «Щёлкнуть», as everywhere", t0)
	t0 = Time.get_ticks_msec()
	await _test_title_and_talk()
	_report("R12-3 / R12-5 / R12-6 / R12-7 The window is titled «Дом пропавших дорог»; the talk partner's mark is gone a second after a click that said nothing and holds while a line is on screen; Agata's line played by the game has its lips by sounds; the settings open the licenses of the engine, its third-party parts and the fonts", t0)
	t0 = Time.get_ticks_msec()
	await _test_family_evening()
	_report("R12-8 Nina's room with the family in it (after M20, until the morning): no place Agata walks to and no point of the floor left to her puts her over anyone; the bed and the exit are reached", t0)
	root.get_node("GameState").reset()
	if _main != null and is_instance_valid(_main):
		root.remove_child(_main)
		_main.free()
	load("res://scripts/actors/player.gd").forced_render = ""
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== review 12.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


## Below the waist — what a borrowed gesture leaves to the figure's own stance (Actor3D._borrow_clips).
func _below_waist(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe") or bone.begins_with("Skirt")


## Largest change per 1/60 s over the first `upto` seconds of a clip: [the hips' travel (clip units), a turn of a bone
## below the waist (°), where the travel's largest was (s)].
func _steps(a: Animation, upto: float) -> Array:
	var travel := 0.0
	var travel_at := 0.0
	var turn := 0.0
	for t in a.get_track_count():
		var ty := a.track_get_type(t)
		var bone := String(a.track_get_path(t).get_concatenated_subnames())
		if ty == Animation.TYPE_POSITION_3D:
			var prev: Vector3 = a.position_track_interpolate(t, 0.0)
			var x := DT
			while x <= upto + 1e-6:
				var p: Vector3 = a.position_track_interpolate(t, x)
				if (p - prev).length() > travel:
					travel = (p - prev).length()
					travel_at = x
				prev = p
				x += DT
		elif ty == Animation.TYPE_ROTATION_3D and _below_waist(bone):
			var prev_q: Quaternion = a.rotation_track_interpolate(t, 0.0)
			var x2 := DT
			while x2 <= upto + 1e-6:
				var q: Quaternion = a.rotation_track_interpolate(t, x2)
				turn = maxf(turn, rad_to_deg(prev_q.angle_to(q)))
				prev_q = q
				x2 += DT
	return [travel, turn, travel_at]


func _clip(anim: AnimationPlayer, bare: String) -> Animation:
	for n in anim.get_animation_list():
		if String(n).get_slice("/", String(n).get_slice_count("/") - 1) == bare:
			return anim.get_animation(n)
	return null


## Per borrowed clip of the figure `id`: [role, the clip's steps, the stance clip's own steps, m per clip unit].
func _measure(id: String) -> Array:
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var rt: Dictionary = spec.get("rt3d", {})
	var n := _fake_npc()
	var live = NL.new()
	n.add_child(live)
	var out: Array = []
	if not live.setup(n, spec, 0.55):
		_check(false, "%s: live model not loaded" % id)
		n.queue_free()
		await process_frame
		return out
	var anim: AnimationPlayer = live.view.anim
	var own := _clip(anim, String(rt.get("clips", {}).get("idle", "")))
	_check(own != null, "%s: no stance clip «%s»" % [id, String(rt.get("clips", {}).get("idle", ""))])
	var unit: float = live.view._skel_to_turn().basis.get_scale().y
	for e in rt.get("borrow_clips", []):
		var role := String(e.get("as", e.get("clip", "")))
		var a: Animation = anim.get_animation("borrow/" + role) if anim.has_animation("borrow/" + role) else null
		_check(a != null, "%s: the borrowed clip «%s» is not in the figure's player" % [id, role])
		if a != null and own != null:
			out.append([role, _steps(a, a.length), _steps(own, own.length), unit, a.length, own.length])
	n.queue_free()
	await process_frame
	return out


func _test_borrowed_stance() -> void:
	var ids: Array = []
	var dir := DirAccess.open("res://data/actors")
	for f in dir.get_files():
		if not String(f).ends_with(".json"):
			continue
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/" + f))
		if spec is Dictionary and not ((spec.get("rt3d", {}) as Dictionary).get("borrow_clips", []) as Array).is_empty():
			ids.append(String(f).get_basename())
	ids.sort()
	_check(ids.has("agata") and ids.has("nina"), "figures with borrowed clips: %s — Agata and Nina are expected among them" % str(ids))
	for id in ids:
		var rows: Array = await _measure(id)
		_check(not rows.is_empty(), "%s: no borrowed clip measured" % id)
		for r in rows:
			var b: Array = r[1]
			var o: Array = r[2]
			var mm := float(r[3]) * 1000.0
			print("        %s «%s» (%.1f s over a stance of %.1f s): hips %.1f mm a frame at most (the stance itself %.1f), legs %.1f° (the stance %.1f°)" % [id, r[0], float(r[4]), float(r[5]), float(b[0]) * mm, float(o[0]) * mm, float(b[1]), float(o[1])])
			_check(float(b[0]) <= float(o[0]) * 1.3 + 0.0002 / maxf(float(r[3]), 1e-6), "%s «%s»: the hips go %.1f mm in one frame at %.2f s (the stance clip itself — %.1f at most): a seam of the stance inside the gesture" % [id, r[0], float(b[0]) * mm, float(b[2]), float(o[0]) * mm])
			_check(float(b[1]) <= float(o[1]) * 1.3 + 0.2, "%s «%s»: a leg bone turns %.1f° in one frame (the stance clip itself — %.1f° at most)" % [id, r[0], float(b[1]), float(o[1])])
	# self-check: the copy from the start again, as before 12.11 — the seam is found on Agata (Nina's stance clip stands
	# almost still, its end meets its start: printed for the record, not asked for)
	Actor3D.fill_pingpong = false
	Actor3D._borrowed.clear()
	var before := {}
	for id in ids:
		before[id] = await _measure(id)
	Actor3D.fill_pingpong = true
	Actor3D._borrowed.clear()
	var seen := false
	var txt := ""
	for id in ids:
		for r in before[id]:
			var b: Array = r[1]
			var o: Array = r[2]
			txt += " %s «%s» %.1f mm (the stance %.1f);" % [id, r[0], float(b[0]) * float(r[3]) * 1000.0, float(o[0]) * float(r[3]) * 1000.0]
			if id == "agata" and float(b[0]) > float(o[0]) * 3.0 + 0.002 / maxf(float(r[3]), 1e-6):
				seen = true
	print("        as before (the stance from its start again), the hips a frame at most —" + txt)
	_check(seen, "self-check: with the stance copied from its start again no seam is found on Agata —%s — the case is not reproduced" % txt)


# --- R12-2 ------------------------------------------------------------------------------------

func _test_service_keys() -> void:
	var M = load("res://scripts/main.gd")
	var none := PackedStringArray()
	_check(not M.debug_keys_for(false, false, false, none), "a player's exe (desktop, release, no arguments) has the service keys")
	_check(not M.debug_keys_for(false, false, false, PackedStringArray(["--title"])), "«-- --title» alone turns the service keys on")
	_check(M.debug_keys_for(false, false, false, PackedStringArray(["--dev"])), "«-- --dev» does not turn the service keys on")
	_check(M.debug_keys_for(false, false, false, PackedStringArray(["--start=day2"])), "a start point («-- --start=day2») has no service keys — the Director compares with them")
	_check(M.debug_keys_for(false, false, true, none), "a debug build (the editor, the tests) has no service keys")
	_check(not M.debug_keys_for(true, false, false, PackedStringArray(["--dev"])) and M.debug_keys_for(true, true, false, none), "the web: the keys are for the probe page only")
	# both places that read the keys ask this rule
	for f in ["res://scripts/actors/player.gd", "res://scripts/ambient/perf_overlay.gd"]:
		_check(FileAccess.get_file_as_string(f).contains("debug_keys_allowed()"), "%s no longer asks Main.debug_keys_allowed()" % f)
	# self-check: the rule as it was — everything but a player's web page
	var old_rule := func(web: bool, probe: bool) -> bool: return probe or not web
	_check(old_rule.call(false, false), "self-check: the old rule gave a player's exe no keys either — the test tells nothing")


# --- R12-4 ------------------------------------------------------------------------------------

func _hint_says_klik(h: String) -> bool:
	return h.begins_with("Клик") or h.contains(" клик") or h.contains("Кликн") or h.contains("кликн")


func _test_hint_words() -> void:
	var n := 0
	var dir := DirAccess.open("res://data/story/scenes")
	for f in dir.get_files():
		if not String(f).ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/scenes/" + f))
		for sc in (d.get("scenes", []) if d is Dictionary else []):
			for h in sc.get("hints", []):
				n += 1
				_check(not _hint_says_klik(String(h)), "scene %s: the hint «%s» says «Клик» — «Щёлкнуть» everywhere else" % [String(sc.get("id", "")), String(h)])
	_check(n > 50, "only %d scene hints read — the data's shape changed?" % n)
	_check(_hint_says_klik("Клик по кровати в горнице"), "self-check: the old hint «Клик по кровати в горнице» is not caught")


# --- R12-3, R12-5 -------------------------------------------------------------------------------

func _wait_s(s: float) -> void:
	var t := 0.0
	var guard := 0
	while t < s and guard < 200000:
		await process_frame
		t += maxf(root.get_process_delta_time(), 0.0005)
		guard += 1


func _test_title_and_talk() -> void:
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var want := "Дом пропавших дорог"
	var before := String(root.title)
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	_main = main_node
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	_check(String(root.title) == want, "the window is titled «%s», not «%s»" % [String(root.title), want])
	_check(before != want, "self-check: the window was titled «%s» before the game's scene — the test tells nothing" % before)
	# Director 13.11, 16:18: the English name — «The House of Lost Roads»: with the words on screen in English the
	# game's name is that one (the text ui.game_title; a language change reloads the scene, and _ready titles the window)
	var LS = load("res://scripts/core/language_settings.gd")
	var sd0 = root.get_node("StoryData")
	LS.load_settings()
	var subs0 := String(LS.subtitles)
	LS.subtitles = "en"
	sd0.reload()
	var en_title := String(main_node.call("game_title"))
	LS.subtitles = "ru"
	sd0.reload()
	var ru_title := String(main_node.call("game_title"))
	LS.subtitles = subs0
	sd0.reload()
	_check(en_title == "The House of Lost Roads", "in English the game is named «%s», not «The House of Lost Roads»" % en_title)
	_check(ru_title == want, "in Russian the game is named «%s», not «%s»" % [ru_title, want])
	_check(String(ProjectSettings.get_setting("application/config/name")) == "Dom propavshih dorog", "the project's name changed to «%s» — it names the saves' folder (user://): every save would be lost" % String(ProjectSettings.get_setting("application/config/name")))
	# R12-5
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "default", Vector2(1200, 960))
	for i in 8:
		await process_frame
	sr.current_beat = {}
	sr.talk_with = "mitya"
	sr.set("_talk_idle_s", 0.0)
	await _wait_s(0.3)
	_check(String(sr.talk_with) == "mitya", "the mark is gone 0.3 s after the click — a talk's first line may not be up yet")
	await _wait_s(1.4)
	_check(String(sr.talk_with) == "", "1.7 s after a click that said nothing the talk partner's mark is still «%s»" % String(sr.talk_with))
	# while a line is on screen the mark holds (11.11: Mitya listens to Agata's question)
	sr.talk_with = "mitya"
	sr.set("_talk_idle_s", 0.0)
	sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "R12_5", "text": "Митя, а ты рыбу удишь?"}
	await _wait_s(2.0)
	_check(String(sr.talk_with) == "mitya", "self-check: with a line on screen the mark was dropped after 2 s — Mitya would turn away again")
	sr.current_beat = {}
	await _wait_s(1.5)
	_check(String(sr.talk_with) == "", "the line over, 1.5 s later the mark is still «%s»" % String(sr.talk_with))
	# R12-6: lips by sounds on a line the game itself plays
	var LT = load("res://scripts/audio/lips_table.gd")
	var vd = root.get_node("VoiceDirector")
	var player = main_node.get_node("World/Player")
	var lid := "M01_1"
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voice/ru/manifest.json"))
	var text := String(man["lines"][lid]["text"]) if man is Dictionary and (man.get("lines", {}) as Dictionary).has(lid) else ""
	_check(text != "", "R12-6: the line %s is not in the game's voice manifest" % lid)
	if text != "" and String(vd.get("voice_lang")) == "ru":
		var st := String(vd.call("play_line", lid, "agata", text, "line"))
		_check(st == "playing", "R12-6: VoiceDirector did not start %s (%s)" % [lid, st])
		await _wait_s(0.8)
		var lt := float(vd.call("line_time"))
		_check(lt > 0.3 and lt < 2.5, "R12-6: 0.8 s into the line the voice's clock says %.2f s" % lt)
		_check(bool(LT.has_line("ru", lid)) and String(LT.class_at("ru", lid, lt)) != "", "R12-6: no table of letters for %s (data/lips/ru.json)" % lid)
		var jaw = player.get("jaw")
		_check(jaw != null, "R12-6: Agata has no mouth driver (render 3D off?)")
		if jaw != null:
			var sh: Vector2 = jaw.call("lip_shape")
			_check(sh.x > 0.0, "R12-6: Agata's mouth gets no shape for the letter being said (%.2f, %.2f)" % [sh.x, sh.y])
			jaw.set("line_override", "no_such_line")
			jaw.set("time_override", 0.5)
			var none: Vector2 = jaw.call("lip_shape")
			jaw.set("line_override", "")
			jaw.set("time_override", NAN)
			_check(none.x < 0.0, "self-check R12-6: a line that is not in the table gives a shape (%.2f, %.2f)" % [none.x, none.y])
		vd.call("stop", "test")
	await _test_licenses(main_node)
	gs.reset()


# --- R12-7 ------------------------------------------------------------------------------------

func _test_licenses(main_node: Node) -> void:
	var LTX = load("res://scripts/ui/licenses_text.gd")
	var sd = root.get_node("StoryData")
	var ui = main_node.get_node("GameUi")
	ui.call("open_menu_panel", "settings")
	for i in 4:
		await process_frame
	var lic: Button = ui.get("menu_panel").find_child("Licenses", true, false)
	_check(lic != null and lic.is_visible_in_tree() and lic.text == String(sd.call("text", "@ui.licenses")), "R12-7: the settings have no «Лицензии» button")
	if lic == null:
		return
	lic.pressed.emit()
	for i in 4:
		await process_frame
	_check(bool(ui.call("licenses_open")), "R12-7: «Лицензии» pressed, the screen is not open")
	var dlg: Control = ui.get("licenses_dialog")
	var body: RichTextLabel = dlg.find_child("Text", true, false) if dlg != null else null
	var txt := body.text if body != null else ""
	_check(txt.length() > 20000, "R12-7: the licenses' text is %d characters long" % txt.length())
	_check(txt.contains(Engine.get_license_text().strip_edges().substr(0, 80)), "R12-7: the engine's own license is not in the text")
	var missing: Array = []
	for c in Engine.get_copyright_info():
		if not txt.contains(String(c.get("name", ""))):
			missing.append(String(c.get("name", "")))
	_check(missing.is_empty() and Engine.get_copyright_info().size() > 10, "R12-7: third-party components of the engine not named: %s" % str(missing.slice(0, 6)))
	missing = []
	for n in Engine.get_license_info().keys():
		if not txt.contains("── %s ──" % String(n)) or not txt.contains(String(Engine.get_license_info()[n]).strip_edges().substr(0, 60)):
			missing.append(String(n))
	_check(missing.is_empty(), "R12-7: license texts the engine names are not in the text: %s" % str(missing.slice(0, 6)))
	var fonts: Array = LTX.fonts()
	var ids: Array = []
	for f in fonts:
		ids.append(String(f.get("id", "")))
		_check(txt.contains(String(f.get("name", ""))) and String(f.get("text", "")).length() > 3000 and txt.contains(String(f.get("text", ""))), "R12-7: the font «%s» with its license is not in the text" % String(f.get("name", "")))
	for d in DirAccess.get_directories_at("res://assets/fonts"):
		_check(ids.has(String(d)), "R12-7: the font folder «%s» has no entry in data/licenses.json (python3 tools/make_licenses.py)" % d)
	var heads := {"intro": "i", "engine": "e", "third": "t", "fonts": "f", "texts": "x"}
	_check(txt.contains("SIL OPEN FONT LICENSE") and not String(LTX.build(heads, [])).contains("SIL OPEN FONT LICENSE"), "self-check R12-7: the text built without the fonts still has a font license — the check tells nothing")
	ui.call("close_licenses")
	_check(not bool(ui.call("licenses_open")), "R12-7: «Закрыть» leaves the screen open")
	ui.call("open_menu_panel", "save")
	for i in 3:
		await process_frame
	_check(not lic.visible, "R12-7: «Лицензии» is shown over the list of saves")
	ui.call("close_menu_panel")


## The share of the figure farther from the viewer that the nearer one covers — the frames of tools/validate_rooms.py 9b:
## feet at the point, `hw` × the room's depth scale to each side, `fig` × the scale up (a villager's × its scale_factor).
func _cover(room, agata: Vector2, feet: Vector2, factor: float, hw: float, fig: float) -> float:
	var a_s := float(room.depth_scale(agata.y))
	var n_s := float(room.depth_scale(feet.y)) * factor
	var ox := minf(agata.x + hw * a_s, feet.x + hw * n_s) - maxf(agata.x - hw * a_s, feet.x - hw * n_s)
	var oy := minf(agata.y, feet.y) - maxf(agata.y - fig * a_s, feet.y - fig * n_s)
	if ox <= 0.0 or oy <= 0.0:
		return 0.0
	if agata.y > feet.y:
		return ox / (2.0 * hw * n_s) * oy / (fig * n_s)
	return ox / (2.0 * hw * a_s) * oy / (fig * a_s)


func _test_family_evening() -> void:
	if _main == null:
		_check(false, "R12-8: the game's scene is not up")
		return
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var sd = root.get_node("StoryData")
	var player: Node2D = _main.get_node("World/Player")
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/_index.json"))
	var aref: Dictionary = idx.get("agata_ref", {}) if idx is Dictionary else {}
	var hw := float(aref.get("figure_half_width_px", 0))
	var fig := float(aref.get("figure_px", 0))
	var limit := float(aref.get("npc_overlap_max", 0))
	_check(hw > 0.0 and fig > 0.0 and limit > 0.0, "R12-8: no figure frame in rooms/_index.json agata_ref")
	if hw <= 0.0 or fig <= 0.0:
		return
	# the evening after the meeting: every main scene through M20 done, nothing after it
	sr.current_beat = {}
	sr.call("_on_state_reset")
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		if id == "M20":
			break
	_check(gs.has_flag("wife_came") and not gs.has_flag("morning_day3") and not gs.has_flag("night_olkhovka"), "R12-8: the state is not the evening after M20")
	rm.change_room("O3", "from_O4")
	await physics_frame
	for i in 8:
		await physics_frame
	sr.call("_cancel_stage")
	sr.current_beat = {}
	var room = rm.current_room
	var family: Dictionary = {}   # id → [feet, scale factor]
	for id in ["nina", "ulyana", "ilya", "ilya_wife"]:
		var n: Node2D = room.get_node_or_null("npc_" + id)
		_check(n != null and n.visible, "R12-8: %s is not in the room this evening — the test looks at another state" % id)
		if n != null and n.visible:
			var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
			family[id] = [n.global_position, float((spec as Dictionary).get("npc", {}).get("scale_factor", 1.0)) if spec is Dictionary else 1.0]
	if family.size() < 4:
		return
	var worst_of := func(p: Vector2) -> Array:   # [share, who]
		var w := [0.0, ""]
		for id in family:
			var c := _cover(room, p, family[id][0], family[id][1], hw, fig)
			if c > float(w[0]):
				w = [c, id]
		return w
	# self-check: the measure sees the defect — the old place of the talk with Nina, right in front of Ilya
	var old: Array = worst_of.call(Vector2(1620, 880))
	_check(float(old[0]) > 0.5 and String(old[1]) == "ilya", "self-check R12-8: Agata at (1620, 880) covers %s by %.0f %% — the measure does not see her in front of Ilya" % [String(old[1]), float(old[0]) * 100.0])
	# 1. every place she walks to by a click on a thing, a villager, the exit; the way in
	var places: Array = [["the way in from_O4", player.global_position]]
	for hs in room.get_node("Hotspots").get_children():
		if hs is Node2D and hs.visible and hs.has_method("get_stand_position") and (not hs.has_method("can_click") or bool(hs.call("can_click"))):
			places.append([String(hs.name), hs.call("get_stand_position")])
	for ex in room.get_node("Exits").get_children():
		if ex.has_method("get_stand_position"):
			places.append([String(ex.name), ex.call("get_stand_position")])
	_check(places.size() >= 10, "R12-8: only %d places found in the room" % places.size())
	var map: RID = room.get_walkable().get_navigation_map()
	# a freshly baked floor answers only after the map's next syncs (run_tests.gd: ~5 physics frames) — wait for it
	var ready := 0
	while NavigationServer2D.map_get_closest_point(map, player.global_position).distance_to(player.global_position) > 3.0 and ready < 180:
		await physics_frame
		ready += 1
	_check(ready < 180, "R12-8: the floor's map does not answer (the way in %s → %s)" % [str(player.global_position), str(NavigationServer2D.map_get_closest_point(map, player.global_position))])
	for pl in places:
		var w: Array = worst_of.call(pl[1])
		_check(float(w[0]) <= limit, "R12-8: at «%s» %s Agata and %s are one over the other (%.0f %% of the figure behind)" % [pl[0], str(pl[1]), String(w[1]), float(w[0]) * 100.0])
		var on: Vector2 = NavigationServer2D.map_get_closest_point(map, pl[1])
		_check(on.distance_to(pl[1]) <= 3.0, "R12-8: «%s» %s is off the floor left to her this evening (nearest %s)" % [pl[0], str(pl[1]), str(on)])
	# 2. the floor: wherever a click sends her, she covers nobody
	var bad := 0
	var bad_s := ""
	var seen := 0
	var y := 745.0
	while y <= 1075.0:
		var x := 1050.0
		while x <= 1915.0:
			var q: Vector2 = NavigationServer2D.map_get_closest_point(map, Vector2(x, y))
			var w: Array = worst_of.call(q)
			seen += 1
			if float(w[0]) > limit or q.x < 1040.0 or q.y < 730.0:   # (0, 0) — a map that does not answer — is no floor point
				bad += 1
				if bad_s == "":
					bad_s = "a click at (%.0f, %.0f) → %s: %s covered by %.0f %%" % [x, y, str(q), String(w[1]), float(w[0]) * 100.0]
			x += 35.0
		y += 22.0
	_check(bad == 0, "R12-8: %d of %d floor points put Agata over someone; %s" % [bad, seen, bad_s])
	# 3. a real walk into the family: she stops where she covers nobody
	player.call("walk_to", Vector2(1610, 950))
	var t := 0.0
	while t < 0.3 or (bool(player.call("is_walking")) and t < 12.0):
		await physics_frame
		t += 1.0 / 60.0
	var w3: Array = worst_of.call(player.global_position)
	_check(not bool(player.call("is_walking")) and float(w3[0]) <= limit, "R12-8: sent to (1610, 950) Agata stops at %s — %s covered by %.0f %%" % [str(player.global_position), String(w3[1]), float(w3[0]) * 100.0])
	# 4. the bed (the goal of the evening) and the exit are reached from where the scene left her — by the clock
	var clock: Node = room.get_node_or_null("Hotspots/clock")
	var from: Vector2 = clock.call("get_stand_position") if clock != null else player.global_position
	for nm in ["Hotspots/bed", "Exits/to_O4"]:
		var node: Node = room.get_node_or_null(nm)
		_check(node != null, "R12-8: no %s in the room" % nm)
		if node == null:
			continue
		var to: Vector2 = node.call("get_stand_position")
		var path: PackedVector2Array = NavigationServer2D.map_get_path(map, from, to, true)
		_check(path.size() >= 2 and path[path.size() - 1].distance_to(to) <= 4.0, "R12-8: no way from the clock to %s %s (path ends at %s)" % [nm, str(to), str(path[path.size() - 1]) if path.size() > 0 else "—"])
	# self-check: the morning after — the family gone, the floor whole, the talk with Nina back at its place
	gs.set_flag("night_olkhovka", true)
	gs.set_flag("morning_day3", true)
	map = room.get_walkable().get_navigation_map()
	ready = 0
	while NavigationServer2D.map_get_closest_point(map, Vector2(1610, 950)).distance_to(Vector2(1610, 950)) > 3.0 and ready < 180:
		await physics_frame
		ready += 1
	var free: Vector2 = NavigationServer2D.map_get_closest_point(map, Vector2(1610, 950))
	_check(free.distance_to(Vector2(1610, 950)) <= 3.0, "self-check R12-8: next morning (1610, 950) is still off the floor (nearest %s) — the limit outlives the evening" % str(free))
	var nina_hs: Node = room.get_node_or_null("Hotspots/nina")
	_check(nina_hs != null and (nina_hs.call("get_stand_position") as Vector2).distance_to(Vector2(1620, 880)) <= 2.0, "self-check R12-8: next morning the talk with Nina is not at (1620, 880)")
