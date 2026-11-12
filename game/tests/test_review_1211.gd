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

const DT := 1.0 / 60.0

var _results: Array = []
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
	_report("R12-3 / R12-5 The window is titled «Дом пропавших дорог»; the talk partner's mark is gone a second after a click that said nothing, and holds while a line is on screen", t0)
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
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	_check(String(root.title) == want, "the window is titled «%s», not «%s»" % [String(root.title), want])
	_check(before != want, "self-check: the window was titled «%s» before the game's scene — the test tells nothing" % before)
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
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()

