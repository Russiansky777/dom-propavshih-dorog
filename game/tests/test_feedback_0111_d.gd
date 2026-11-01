extends SceneTree
## Group D of the Director's playthrough 01.11 (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md; «стр.» — a line of
## Docs/FEEDBACK_DIRECTOR_2026-11-01_raw.txt) — figure motion, the part done before the models' own pass:
##   стр. 56: Nina walks over to Tamara (M23a) half as fast as before — 2.6 → 5.2 s for the same way;
##   стр. 61, 68: a figure in a composed frame (the door, the workshop, the council at the mill with the manager) is
##     not a still picture: it breathes and sways (StateLayer life, game/shaders/frame_figure.gdshader), and the one
##     whose line is being said moves its head with the words; the others do not; when the line is over it calms down.
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
	await _test("стр. 61, 68: frame figures breathe and sway; the speaker moves with the words, the others do not", _test_frame_life)
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


func _test_frame_life() -> void:
	var fv = main_node.find_child("FrameView", true, false)
	_check(fv != null, "no FrameView")
	if fv == null:
		return
	# every composed figure of every frame comes alive (the data say who is drawn: compose.char)
	var dir := DirAccess.open("res://data/story/rooms")
	var frames: Array = []
	for f in dir.get_files():
		if f.ends_with(".json") and (f.begins_with("F_") or f.begins_with("EP_")):
			frames.append(f.get_basename())
	frames.sort()
	for fid in frames:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/%s.json" % fid))
		var chars: Array = []
		for l in doc.get("layers", []):
			var c = l.get("compose", {})
			if c is Dictionary and String(c.get("char", "")) != "" and not (l.get("life", true) is bool and not l.get("life", true)):
				chars.append(String(c["char"]))
		sr.set_frame(fid, false)
		await _frames(2)
		var live := _life_layers(fv)
		for ch in chars:
			_check(live.has(ch), "%s: the figure %s is a still picture (no life)" % [fid, ch])
	# the council at the mill (M23b, стр. 68): the manager's line — he moves with the words, Pavel, Ilya, Agata do not
	sr.set_frame("F_mill_manager", false)
	await _frames(3)
	var live := _life_layers(fv)
	_check(live.size() == 4, "F_mill_manager: %d live figures (pavel, manager, ilya, agata expected)" % live.size())
	if live.has("manager"):
		var m = live["manager"]
		var t0 = m.life_mat.get_shader_parameter("time_s")
		await _frames(10)
		_check(float(m.life_mat.get_shader_parameter("time_s")) > float(t0), "the frame's clock does not run (time_s)")
		_check(float(m.life_mat.get_shader_parameter("breath_frac")) > 0.0 and float(m.life_mat.get_shader_parameter("sway_frac")) > 0.0, "no breathing or sway in the frame figure")
		sr.current_beat = {"type": "line", "speaker": "manager", "text": "Год рычаг провисел — проверка: эта реплика длинная, её говорят."}
		await create_timer(0.6).timeout   # talk_in_s 0.25
		_check(m.life_talk > 0.9, "the manager's own line: his head does not move with the words (talk %.2f)" % m.life_talk)
		for other in ["pavel", "ilya", "agata"]:
			if live.has(other):
				_check(float(live[other].life_talk) < 0.01, "%s moves with the manager's words (talk %.2f)" % [other, float(live[other].life_talk)])
		sr.current_beat = {}
		await create_timer(0.9).timeout   # talk_out_s 0.5
		_check(m.life_talk < 0.01, "line over — the manager still talks (talk %.2f)" % m.life_talk)
		# two figures do not breathe in step
		if live.has("pavel"):
			_check(absf(float(m.life_mat.get_shader_parameter("phase")) - float(live["pavel"].life_mat.get_shader_parameter("phase"))) > 0.3, "the manager and Pavel breathe in step")
	sr.set_frame("", false)
	await _frames(2)
