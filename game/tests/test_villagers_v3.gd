extends SceneTree
## Block 3 (Director 05.11, 22:51: villagers remade in Meshy, «не жертвовать реалистичностью или качеством»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_villagers_v3.gd
##   1 the villagers moved to v3 draw their v3 model (actor data rt3d.scene under <id>_v3/), it loads, has the four
##     clips the live figure needs (idle, listen, talk, walk) and its mesh is at least 150 000 triangles;
##   2 fingertips out of the body (Director 02.11, line 12 «пальцы Павла в теле»): standing, talking, listening the
##     hand's farthest point stays outside the body's hull (≤ 0.5 cm in); self-check — without the fingertip check
##     (data tip_r_m off) the same sequence puts them in deeper than 2 cm;
##   3 one-shot actions (play_once / npc_act): a clip plays once from the stance and back, `hold` keeps it until
##     released; self-check — an unknown clip plays nothing (false) and the villager stays in the stance;
##   4 the data of the actions: every scene staging's npc_act and every hotspot's `act` names a clip the villager's
##     model has (actor data rt3d.clips), every thing in hand (rt3d.props, hotspot `held`) has its picture and its
##     clip; self-check — a made-up clip and a missing picture are caught;
##   5 no patter (Director 06.11, 12:30: «Митя и Пелагея постоянно дёргаются, мельтешат»): standing, talking, listening
##     and through every whole-body action clip the feet take at most one step; self-check — with the foot locks held
##     through the action clips (as before 06.11) Mitya's lantern pick-up and Pelageya's rope steps several times;
##   6 hands without a twitch (Director 06.11, 15:08: «руки всё ещё иногда дёргаются»): through idle → talk → listen →
##     idle and each one-shot action no hand jolts more than 6 mm per 1/60 s² (the clips' wrist flicks smoothed,
##     the clip switch gated); self-check — without the smoothing (data rt3d.smooth off) Pavel's talk jolts over 6.
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
	await _test("V3-4 every npc_act / act / prop names a clip and a picture that exist; self-check catches made-up ones", _t4)
	await _test("V3-6 hands do not twitch talking, listening, switching, acting; self-check — unsmoothed clips do", _t6)
	await _test("V3-5 no stepping about standing or in the action clips (Mitya, Pelageya…); self-check — locks held through the clips step", _t5)
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


## The faults of the actions' data (npc_act, hotspot act/held, actor props) — "" lists nothing wrong.
static func action_faults(scenes: Array, rooms: Array, actors: Dictionary) -> Array:
	var bad: Array = []
	var clips_of := func(id: String) -> Dictionary:
		var a: Dictionary = actors.get(id, {})
		return (a.get("rt3d", {}) as Dictionary).get("clips", {})
	for sc in scenes:
		for st in (sc as Dictionary).get("stage", []):
			for g in (st as Dictionary).get("npc_act", []):
				var id := String(g.get("id", ""))
				if not (clips_of.call(id) as Dictionary).has(String(g.get("action", ""))):
					bad.append("%s: npc_act %s.%s — no such clip" % [sc.get("id"), id, g.get("action")])
	for r in rooms:
		for h in (r as Dictionary).get("hotspots", []):
			var hd: Dictionary = h
			if hd.has("act") and not (clips_of.call(String(hd.get("id", ""))) as Dictionary).has(String(hd["act"].get("clip", ""))):
				bad.append("%s.%s: act %s — no such clip" % [r.get("id"), hd.get("id"), hd["act"].get("clip")])
			if hd.has("held") and not ResourceLoader.exists(String(hd["held"].get("image", ""))):
				bad.append("%s.%s: held picture %s missing" % [r.get("id"), hd.get("id"), hd["held"].get("image")])
	for id in actors.keys():
		var props: Dictionary = ((actors[id] as Dictionary).get("rt3d", {}) as Dictionary).get("props", {})
		for clip in props.keys():
			if not (clips_of.call(String(id)) as Dictionary).has(String(clip)):
				bad.append("%s: props for %s — no such clip" % [id, clip])
			for ps in props[clip]:
				if not ResourceLoader.exists(String(ps.get("image", ""))):
					bad.append("%s: prop picture %s missing" % [id, ps.get("image")])
	return bad


func _t4() -> void:
	var sd = root.get_node("StoryData")
	var scenes: Array = []
	for sid in sd.scene_order:
		scenes.append(sd.scene(sid))
	var rooms: Array = []
	for f in DirAccess.get_files_at("res://data/story/rooms"):
		if f.ends_with(".json"):
			rooms.append(JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/" + f)))
	var actors := {}
	for f in DirAccess.get_files_at("res://data/actors"):
		if f.ends_with(".json"):
			actors[f.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/" + f))
	var bad := action_faults(scenes, rooms, actors)
	_check(bad.is_empty(), "faults: %s" % str(bad))
	var n_act := 0
	for sc in scenes:
		for st in (sc as Dictionary).get("stage", []):
			n_act += ((st as Dictionary).get("npc_act", []) as Array).size()
	_check(n_act >= 9, "only %d npc_act in the scenes (block 3 placed 9+)" % n_act)
	# self-check: a made-up clip in a staging and a missing picture in a prop are both caught
	var fake_sc := [{"id": "X", "stage": [{"npc_act": [{"id": "nina", "action": "juggle"}]}]}]
	var fake_actors := actors.duplicate(true)
	fake_actors["tamara"]["rt3d"]["props"]["give_small"][0]["image"] = "res://nope.png"
	var caught := action_faults(fake_sc, [], fake_actors)
	_check(caught.size() == 2, "self-check: made-up clip and missing picture → %s" % str(caught))


## Foot-lock steps while `id` stands in `state` for `secs`, or plays the one-shot `clip` (state "act:<clip>").
func _steps(id: String, what: String, secs: float, free := true) -> int:
	var spec := _spec(id)
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
	if not live.setup(n, spec, 0.55):
		n.queue_free()
		return -1
	var v: Actor3D = live.view
	v.render_target_update_mode = SubViewport.UPDATE_DISABLED
	v.feet_free_in_acts = free
	live.face(Vector2(0.4, 0.5), 0.55, true)
	for i in 30:
		live.process(DT)
	if what.begins_with("act:"):
		live.play_once(what.substr(4))
		secs = maxf(secs, v.action_length(what.substr(4)) + 1.5)
	else:
		live.set_state(what)
	var steps := 0
	var was := [false, false]
	var t := 0.0
	while t < secs:
		live.process(DT)
		for i in 2:
			var on: bool = v._foot_step[i] != null
			if on and not was[i]:
				steps += 1
			was[i] = on
		t += DT
	n.queue_free()
	await process_frame
	return steps


func _t5() -> void:
	var acts := {"mitya": ["pick_up", "raise_lantern", "knock_shutter", "tar_brush"], "pelageya": ["pull_rope", "tar_brush"],
		"nina": ["place_table", "write_board", "hang_coat"], "tamara": ["give_small", "bag_strap"], "ilya": ["crank_windlass", "give_small"],
		"ilya_wife": ["hold_lamp"]}
	for id in ["mitya", "pelageya", "pavel", "nina", "ilya", "ilya_wife", "ulyana", "tamara", "manager"]:
		for st in ["idle", "talk", "listen"]:
			var k: int = await _steps(id, st, 6.0)
			_check(k >= 0 and k <= 1, "%s %s: %d steps standing (≤ 1)" % [id, st, k])
		for c in acts.get(id, []):
			var k2: int = await _steps(id, "act:" + c, 0.0)
			_check(k2 >= 0 and k2 <= 1, "%s %s: %d steps in the action (≤ 1)" % [id, c, k2])
	var self_m: int = await _steps("mitya", "act:pick_up", 0.0, false)
	var self_p: int = await _steps("pelageya", "act:pull_rope", 0.0, false)
	_check(self_m > 3 and self_p > 3, "self-check: locks held through the clips — Mitya %d, Pelageya %d steps (the test sees no patter)" % [self_m, self_p])


## The worst hand jolt (mm per 1/60 s²) of `id` through idle → talk → listen → idle, then each clip in `acts`.
func _hand_jolt(id: String, acts: Array, smooth := true) -> float:
	var spec := _spec(id)
	if not smooth:
		(spec["rt3d"] as Dictionary).erase("smooth")
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
	if not live.setup(n, spec, 0.55):
		n.queue_free()
		return 999.0
	var v: Actor3D = live.view
	v.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live.face(Vector2(0.4, 0.5), 0.55, true)
	var seq: Array = [["idle", 2.0], ["talk", 8.0], ["listen", 5.0], ["idle", 2.0]]
	for c in acts:
		seq.append(["act:" + String(c), v.action_length(String(c)) + 1.5])
	var worst := 0.0
	var h: Array = []
	for sq in seq:
		if String(sq[0]).begins_with("act:"):
			live.play_once(String(sq[0]).substr(4))
		else:
			live.set_state(String(sq[0]))
		var t := 0.0
		while t < float(sq[1]):
			live.process(DT)
			h.append([v.turn.transform * v.bone_model("LeftHand"), v.turn.transform * v.bone_model("RightHand")])
			if h.size() >= 3:
				for i in 2:
					var acc: Vector3 = h[-1][i] - 2.0 * h[-2][i] + h[-3][i]
					worst = maxf(worst, acc.length() * 1000.0)
			t += DT
	n.queue_free()
	await process_frame
	return worst


func _t6() -> void:
	var acts := {"mitya": ["raise_lantern", "knock_shutter", "tar_brush"], "pelageya": ["pull_rope", "tar_brush"],
		"nina": ["place_table", "write_board", "hang_coat"], "tamara": ["give_small", "bag_strap"], "ilya": ["crank_windlass", "give_small"],
		"ilya_wife": ["hold_lamp"]}
	for id in ["mitya", "pelageya", "pavel", "nina", "ilya", "ilya_wife", "ulyana", "tamara", "manager"]:
		var j: float = await _hand_jolt(id, acts.get(id, []))
		_check(j <= 6.0, "%s: a hand jolts %.1f mm per 1/60 s² (≤ 6)" % [id, j])
	var raw: float = await _hand_jolt("pavel", [], false)
	_check(raw > 6.0, "self-check: Pavel's unsmoothed talk — only %.1f mm (the test sees no twitch)" % raw)
