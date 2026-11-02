extends SceneTree
## Group D of the Director's playthrough 01.11 (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md; «стр.» — a line of
## Docs/FEEDBACK_DIRECTOR_2026-11-01_raw.txt) — figure motion, the part done before the models' own pass:
##   стр. 56: Nina walks over to Tamara (M23a) half as fast as before — 2.6 → 5.2 s for the same way;
##   стр. 61, 68: a figure in a composed frame (the door, the workshop, the lesson, the council at the mill with the
##     manager) is not a still picture: it plays its sheet's clips (compose.anim, tools/make_frame_layers.py → atlas,
##     StateLayer, game/shaders/frame_anim.gdshader) — the rest clip all the time (the shown sheet frame changes), and
##     the one whose line is being said plays the talk clip (hands, head, mouth) — cells the rest clip never shows; the
##     others stay in their rest clip; when the line is over it goes back. A figure without a talk clip (Agata) moves
##     its head with the words (warp). Self-check: the old still / warp-only layer (no anim) fails these checks.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0111_d.gd
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var main_node: Node = null


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	await _test("стр. 56: Nina walks to Tamara in M23a half as fast (5.2 s, was 2.6)", _test_nina_pace)
	await _test("стр. 61, 68: frame figures play their sheet clips; the speaker plays the talk gesture, the others do not", _test_frame_life)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("==== Feedback 01.11 group D: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


static func nina_go_s(doc: Dictionary) -> float:
	for s in doc.get("scenes", []):
		if String(s.get("id", "")) != "M23a":
			continue
		for st in s.get("stage", []):
			for g in st.get("npc_go", []):
				if String(g.get("id", "")) == "nina" and String(g.get("face", "")) == "tamara":
					return float(g.get("s", 0.0))
	return -1.0


func _test_nina_pace() -> void:
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/scenes/E4.json"))
	var s := nina_go_s(doc)
	_check(s >= 5.0, "M23a: Nina's walk to Tamara takes %.1f s (the Director: half as fast as 2.6 s → 5.2)" % s)
	# self-check: the old staging is caught
	var old := {"scenes": [{"id": "M23a", "stage": [{"npc_go": [{"id": "nina", "to": [575, 790], "s": 2.6, "face": "tamara"}]}]}]}
	_check(nina_go_s(old) < 5.0, "self-check: the old 2.6 s walk is not caught")


func _life_layers(fv: Node) -> Dictionary:
	var out := {}
	if fv == null or fv.room == null:
		return out
	for l in fv.room.get_node("Layers").get_children():
		if l.get("life_mat") != null:
			out[String(l.get("life_char"))] = l
	return out


## The cells a layer shows over `seconds` (sampled every few frames); -1 — a still picture (no sheet clips).
func _sample_cells(layers: Array, seconds: float) -> Dictionary:
	var out := {}
	for l in layers:
		out[l] = []
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _frames(3)
		for l in layers:
			out[l].append(int(l.call("anim_cell")) if l.has_method("anim_cell") else -1)
	return out


## The figure plays its sheet: every sample is a sheet frame and at least `min_distinct` different frames were shown.
static func plays_sheet(cells: Array, min_distinct: int = 3) -> bool:
	var seen := {}
	for c in cells:
		if int(c) < 0:
			return false
		seen[int(c)] = true
	return seen.size() >= min_distinct


## Every sample lies in the clip [first, first + frames) of the atlas description `meta`.
static func all_in_clip(cells: Array, meta: Dictionary, role: String) -> bool:
	var cl: Dictionary = meta.get("clips", {}).get(role, {})
	if cl.is_empty() or cells.is_empty():
		return false
	for c in cells:
		if int(c) < int(cl["first"]) or int(c) >= int(cl["first"]) + int(cl["frames"]):
			return false
	return true


func _test_frame_life() -> void:
	var fv = main_node.find_child("FrameView", true, false)
	_check(fv != null, "no FrameView")
	if fv == null:
		return
	# every composed figure of every frame comes alive (the data say who is drawn: compose.char); one with clips
	# (compose.anim) plays its atlas, the still picture hidden
	var dir := DirAccess.open("res://data/story/rooms")
	var frames: Array = []
	for f in dir.get_files():
		if f.ends_with(".json") and (f.begins_with("F_") or f.begins_with("EP_")):
			frames.append(f.get_basename())
	frames.sort()
	var nina_frames: Array = []
	for fid in frames:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/%s.json" % fid))
		var chars: Array = []
		var animated: Array = []
		for l in doc.get("layers", []):
			var c = l.get("compose", {})
			if c is Dictionary and String(c.get("char", "")) != "" and not (l.get("life", true) is bool and not l.get("life", true)):
				chars.append(String(c["char"]))
				if c.has("anim"):
					animated.append(String(c["char"]))
		if chars.has("nina"):
			nina_frames.append(fid)
		sr.set_frame(fid, false)
		await _frames(2)
		var live := _life_layers(fv)
		for ch in chars:
			_check(live.has(ch), "%s: the figure %s is a still picture (no life)" % [fid, ch])
		for ch in animated:
			if live.has(ch):
				var l = live[ch]
				_check(not (l.get("anim") as Dictionary).is_empty(), "%s: %s has compose.anim but plays no atlas (tools/make_frame_layers.py)" % [fid, ch])
				var img := l.get_node_or_null("Image") as CanvasItem
				_check(img == null or not img.visible, "%s: %s — the still picture is drawn over the clip" % [fid, ch])
	# стр. 61: Nina in every frame she is in (the door, the workshop, the lesson) plays her rest clip — the shown
	# sheet frame changes over time
	_check(nina_frames.size() >= 3, "frames with Nina: %s (the door, the workshop, the lesson expected)" % [nina_frames])
	for fid in nina_frames:
		sr.set_frame(fid, false)
		await _frames(2)
		var live := _life_layers(fv)
		if not live.has("nina"):
			continue
		var smp := await _sample_cells([live["nina"]], 1.5)
		var cells: Array = smp[live["nina"]]
		_check(plays_sheet(cells), "%s: Nina is still — shown sheet frames %s" % [fid, _uniq(cells)])
		_check(all_in_clip(cells, live["nina"].anim, "rest"), "%s: no line of hers, but Nina is not in her rest clip" % fid)
	# стр. 68: the council at the mill (M23b) — whoever's line it is plays the talk clip, the others stay at rest
	sr.set_frame("F_mill_manager", false)
	await _frames(3)
	var live := _life_layers(fv)
	_check(live.size() == 4, "F_mill_manager: %d live figures (pavel, manager, ilya, agata expected)" % live.size())
	var all_l: Array = live.values()
	var quiet := await _sample_cells(all_l, 1.2)
	for ch in live:
		_check(plays_sheet(quiet[live[ch]]), "F_mill_manager: %s is still at rest — frames %s" % [ch, _uniq(quiet[live[ch]])])
	for speaker in ["manager", "pavel", "ilya"]:
		if not live.has(speaker):
			continue
		var m = live[speaker]
		_check(m.anim.get("clips", {}).has("talk"), "%s: no talk clip in the frame atlas" % speaker)
		sr.current_beat = {"type": "line", "speaker": speaker, "text": "Год рычаг провисел — проверка: эта реплика длинная, её говорят."}
		await create_timer(0.6).timeout   # anim_talk_in_s 0.25
		_check(m.life_talk > 0.9, "%s's own line: the talk clip has not come in (talk %.2f)" % [speaker, m.life_talk])
		var smp := await _sample_cells(all_l, 1.5)
		_check(all_in_clip(smp[m], m.anim, "talk") and plays_sheet(smp[m], 2), "%s's own line: he does not gesture — shown frames %s (talk clip %s)" % [speaker, _uniq(smp[m]), m.anim.get("clips", {}).get("talk", {})])
		for other in live:
			if other == speaker:
				continue
			_check(all_in_clip(smp[live[other]], live[other].anim, "rest") and float(live[other].life_talk) < 0.01, "%s gestures with %s's words — frames %s" % [other, speaker, _uniq(smp[live[other]])])
		sr.current_beat = {}
		await create_timer(1.0).timeout   # anim_talk_out_s 0.4
		var after := await _sample_cells([m], 0.5)
		_check(m.life_talk < 0.01 and all_in_clip(after[m], m.anim, "rest"), "%s: line over — still gesturing (talk %.2f, frames %s)" % [speaker, m.life_talk, _uniq(after[m])])
	# Agata's sheet has no talk clip yet: her head moves with her words (warp), her rest clip goes on
	if live.has("agata"):
		var a = live["agata"]
		sr.current_beat = {"type": "line", "speaker": "agata", "text": "Помню, Павел. Наберём — только сперва мост поставить надо."}
		await create_timer(0.6).timeout
		_check(float(a.life_mat.get_shader_parameter("warp_talk")) > 0.9, "Agata's own line: she does not move with the words (warp %.2f)" % float(a.life_mat.get_shader_parameter("warp_talk")))
		sr.current_beat = {}
		await create_timer(1.0).timeout
	# two figures do not move in step
	if live.has("manager") and live.has("pavel"):
		_check(absf(float(live["manager"]._anim_phase) - float(live["pavel"]._anim_phase)) > 0.05, "the manager and Pavel move in step")
	# self-check: the old layer — the same figure as a still picture with the warp only (no compose.anim) — fails
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/F_mill_manager.json"))
	var old_l: Dictionary = {}
	for l in doc["layers"]:
		if String(l.get("id", "")) == "manager":
			old_l = (l as Dictionary).duplicate(true)
	old_l["compose"].erase("anim")
	var old_layer = load("res://scripts/rooms/state_layer.gd").new()
	var spr := Sprite2D.new()
	spr.name = "Image"
	spr.texture = load(String(old_l["image"]))
	old_layer.add_child(spr)
	fv.room.get_node("Layers").add_child(old_layer)
	old_layer.setup(old_l)
	sr.current_beat = {"type": "line", "speaker": "manager", "text": "Проверка старого слоя."}
	var old_smp := await _sample_cells([old_layer], 0.8)
	_check(old_layer.life_mat != null, "self-check: the old warp layer was not built")
	_check(not plays_sheet(old_smp[old_layer]), "self-check: the old still/warp figure passes as playing its sheet")
	_check(not all_in_clip(old_smp[old_layer], live.get("manager", old_layer).anim, "talk"), "self-check: the old still/warp figure passes as gesturing")
	_check(not plays_sheet([5, 5, 5, 5]) and not plays_sheet([-1, -1, -1]), "self-check: a frozen frame passes as playing")
	sr.current_beat = {}
	old_layer.queue_free()
	sr.set_frame("", false)
	await _frames(2)


func _uniq(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if not out.has(c):
			out.append(c)
	return out
