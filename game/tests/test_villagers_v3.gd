extends SceneTree
## Block 3 (Director 05.11, 22:51: villagers remade in Meshy, «не жертвовать реалистичностью или качеством»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_villagers_v3.gd
##   1 the villagers moved to v3 draw their v3 model (actor data rt3d.scene under <id>_v3/), it loads, has the four
##     clips the live figure needs (idle, listen, talk, walk) and its mesh is at least 150 000 triangles;
##   2 fingertips out of the body (Director 02.11, line 12 «пальцы Павла в теле»): standing, talking, listening the
##     hand's farthest point stays outside the body's hull (≤ 0.5 cm in); self-check — without the fingertip check
##     (data tip_r_m off) the same sequence puts them in deeper than 2 cm;
##   3 one-shot actions (play_once / npc_act): a clip plays once from the stance and back, `hold` keeps it until
##     released; self-check — an unknown clip plays nothing (false) and the villager stays in the stance.
## Exit code 0 only when every check passed.

const V3 := ["pavel"]
const Probe := preload("res://tests/probe_fingertips.gd")
const DT := 1.0 / 60.0

var _results: Array = []
var _fails: Array[String] = []


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
	await _test("V3-1 v3 model in data, loads with its clips", _t1)
	await _test("V3-2 fingertips out of the body (self-check: without the check they go in)", _t2)
	await _test("V3-3 one-shot action plays once / holds / unknown clip is refused", _t3)
	var failed := _results.filter(func(r): return not r[1]).size()
	print("\n%d/%d passed" % [_results.size() - failed, _results.size()])
	quit(1 if failed > 0 or _results.is_empty() else 0)


func _spec(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))


func _t1() -> void:
	for id in V3:
		var rt: Dictionary = _spec(id).get("rt3d", {})
		var scene := String(rt.get("scene", ""))
		_check(scene.contains("/%s_v3/" % id), "%s: rt3d.scene is not v3: %s" % [id, scene])
		var ps = load(scene) as PackedScene
		_check(ps != null, "%s: %s does not load" % [id, scene])
		if ps == null:
			continue
		var inst := ps.instantiate()
		var tris := 0
		var clips: Array = []
		for n in inst.find_children("*", "", true, false):
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var m: Mesh = (n as MeshInstance3D).mesh
				for s in m.get_surface_count():
					var idx = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
					tris += (idx.size() / 3) if idx != null else 0
			if n is AnimationPlayer:
				clips = Array((n as AnimationPlayer).get_animation_list())
		inst.free()
		_check(tris >= 150000, "%s: %d triangles (< 150 000)" % [id, tris])
		for c in ["idle", "listen", "talk", "walk"]:
			_check(clips.has(c), "%s: no clip %s (%s)" % [id, c, clips])


func _t2() -> void:
	for id in V3:
		var on: Dictionary = await Probe.run_one(self, id, true)
		var off: Dictionary = await Probe.run_one(self, id, false)
		_check(int(on["frames"]) > 100, "%s: the hands were not measured" % id)
		for i in 2:
			_check(float(on["tip"][i]) <= 0.5, "%s: fingertip %s %.1f cm in the body" % [id, ["L", "R"][i], float(on["tip"][i])])
		_check(maxf(float(off["tip"][0]), float(off["tip"][1])) > 2.0,
			"self-check: %s without the fingertip check — only %.1f / %.1f cm in (the test sees nothing)" % [id, float(off["tip"][0]), float(off["tip"][1])])


func _t3() -> void:
	var spec := _spec("pavel")
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
	var live = load("res://scripts/actors/npc_live_3d.gd").new()
	n.add_child(live)
	_check(live.setup(n, spec, 0.55), "pavel: live figure not set up")
	if live.view == null:
		n.queue_free()
		return
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# self-check: an unknown clip — nothing plays
	_check(not live.play_once("no_such_clip"), "self-check: an unknown clip was accepted")
	_check(not live.once_busy(), "self-check: busy after an unknown clip")
	# once: the clip («talk» stands in for an action) plays to its end, then back to the stance
	var L: float = live.view.action_length("talk")
	_check(live.play_once("talk"), "play_once(talk) refused")
	var peak := 0.0
	var t := 0.0
	while t < L + 2.0:
		live.process(DT)
		await process_frame
		t += DT
		peak = maxf(peak, live.view.shown_act_w())
		if t < L * 0.5:
			_check(live.once_busy(), "the action ended early at %.2f s of %.2f" % [t, L])
	_check(peak > 0.95, "the action never showed fully (%.2f)" % peak)
	_check(not live.once_busy(), "still busy %.1f s after the clip's end" % (t - L))
	_check(live.view.shown_act_w() < 0.02, "not back to the stance (%.2f)" % live.view.shown_act_w())
	_check(live.state == "idle", "state after the action: %s" % live.state)
	# hold: kept past the end until released
	live.play_once("talk", true)
	t = 0.0
	while t < L + 1.0:
		live.process(DT)
		await process_frame
		t += DT
	_check(live.once_busy() and live.view.shown_act_w() > 0.95, "a held action let go by itself")
	live.release_once()
	t = 0.0
	while t < 2.0:
		live.process(DT)
		await process_frame
		t += DT
	_check(not live.once_busy() and live.view.shown_act_w() < 0.02, "a released action did not go back to the stance")
	n.queue_free()
	await process_frame
