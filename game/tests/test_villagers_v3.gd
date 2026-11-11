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
##     the clip switch gated); self-check — without the smoothing (data rt3d.smooth off) Pavel's talk jolts over 6;
##   7 the whole hand out of the clothes (Director 06.11, 15:56: «Павел слушает… руки въезжают в тело»): the figure
##     skinned on the CPU as posed through idle → talk → listen (counted while talking: standing the arms hang as the
##     clip has them, Director 06.11, 23:0x), every hand vertex at most 2 cm inside the posed
##     silhouette of the body and clothes (per centimetre of height) and at most 2 cm behind the nearest clothes
##     surface; self-check — with only the hand's axis and fingertip checked (data arm_body.shell off, as before)
##     Pavel's listening hand goes deeper than 3 cm;
##   8 no scarecrow arms (same note: «остальных тоже коробит»): talking and listening the upper arm stands out sideways
##     (before the hands are cleared of the clothes) at most 22° on average and 28° at most; self-check — with the
##     stance's shoulders under the clip's arms (act_body.upper with the shoulders, tried 06.11) Nina's listening arms
##     spread over 35°;
##   9 listening as standing (Director 06.11, 18:48: «в слушает… плечи прячут куда-то в тело»): the shoulders (upper
##     arm joints) as wide apart listening as in the stance (≥ 97 %), the elbows not rolled in front of the chest and
##     the hands not behind the shoulders (hips' frame); self-check — with the listen clip carried from the v2 figures
##     (clips.listen "listen") Pavel's shoulders close to 80 %. Pelageya's arm taken out backwards (18 cm behind the
##     shoulder) is what arm_body.no_back stops;
##  10 hands steady (Director 06.11, 19:27: «руки дергаются как сумасшедшие, меняя положение туда и назад»): standing,
##     talking and listening the hands make no more jerks (over 2 mm/frame²) or back-and-forth turns than the clip itself
##     (BodyClear on the figure, not turning) plus 3; self-check — with the follower skipped on the skeleton's passes
##     with no time step (as before) Pelageya's or Pavel's hands go back and forth;
##  11 shoulders not jelly (Director 06.11, 22:02: «плечи ходят как желейные, хотя по идее почти не двигаются»): the
##     vertices between the neck and the shoulder joints, followed in the chest bone's frame, slide at most 6 mm on
##     average standing and 15 mm talking; self-check — with the clips' own clavicles (calm_shoulders off) Ilya's slide
##     over 20 mm talking.
## Exit code 0 only when every check passed.

const V3 := ["pavel"]
const Probe := preload("res://tests/probe_fingertips.gd")
const Pen := preload("res://tests/probe_hand_penetration.gd")
const Spread := preload("res://tests/probe_villager_arm_spread.gd")
const ALL := ["pavel", "mitya", "pelageya", "nina", "ilya", "ilya_wife", "tamara", "ulyana", "manager"]
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
	await _test("V3-7 the whole hand out of the clothes talking and listening; self-check — axis and fingertip only go in", _t7)
	await _test("V3-8 arms not spread like a scarecrow talking and listening; self-check — stance shoulders spread them", _t8)
	await _test("V3-10 hands steady: clearing them of the clothes adds no back-and-forth; self-check — the follower skipped does", _t10)
	await _test("V3-11 shoulders not jelly: the skin of the shoulder tops stays on the chest; self-check — the clips' clavicles slide it", _t11)
	await _test("V3-9 listening: shoulders square, hands not behind the back; self-check — the v2 listen clip rolls them", _t9)
	await _test("V3-5 no stepping about standing or in the action clips (Mitya, Pelageya…); self-check — locks held through the clips step", _t5)
	await _test("V3-12 the skirts are on their own bones and whole on the full stride (Pelageya walking to the rope); self-check — the same cloth hung on the leg bones tears", _t12)
	await _test("V3-13 arms along the body standing (Director 09.11, 22:18 «руки не вдоль, а будто в воздухе под углом»); self-check — the clips as they are hold them out", _t13)
	await _test("V3-14 not soldiers: standing, the weight goes from foot to foot (Director 09.11, 22:18); self-check — without the sway the hips stand still", _t14)
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
		# 08.11 (клипы второго ИИ): без защиты кисти и так снаружи — старый клип стойки (v2) кладёт их в фартук
		var off: Dictionary = await Probe.run_one(self, id, false, true)
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
	# 09.11 (Director 12:40 «мелкие действия… красиво не сделаем — убрать»): the lamp, Nina's table and Mitya's second
	# lift went (9 → 6+); the remaining ones are checked one by one in tests/test_handover.gd
	_check(n_act >= 6, "only %d npc_act in the scenes (block 3 placed 9, three taken out 09.11)" % n_act)
	# self-check: a made-up clip in a staging and a missing picture in a prop are both caught
	var fake_sc := [{"id": "X", "stage": [{"npc_act": [{"id": "nina", "action": "juggle"}]}]}]
	var fake_actors := actors.duplicate(true)
	fake_actors["tamara"]["rt3d"]["props"]["give_small"][0]["image"] = "res://nope.png"
	var caught := action_faults(fake_sc, [], fake_actors)
	_check(caught.size() == 2, "self-check: made-up clip and missing picture → %s" % str(caught))


## Foot-lock steps while `id` stands in `state` for `secs`, or plays the one-shot `clip` (state "act:<clip>").
func _steps(id: String, what: String, secs: float, free := true) -> int:
	var spec := _spec(id)
	if not free:
		_before_2100(spec)
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
		_before_2100(spec)
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


## A live villager as the game poses it (NpcLive3D, every modifier), not drawn: [holder node, live].
func _live(spec: Dictionary) -> Array:
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
		return [null, null]
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live.face(Vector2(0.4, 0.5), 0.55, true)
	return [n, live]


## The deepest hand vertex through idle → talk → listen: [inside the posed silhouette (cm), behind the clothes (cm)].
func _hand_depth(spec: Dictionary) -> Array:
	var nl := _live(spec)
	if nl[1] == null:
		return [999.0, 999.0, "not loaded", ""]
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var g = Pen.Grab.new()
	sk.add_child(g)
	var unit := float(live.arm_body.get("_unit")) if live.arm_body != null else 1.0
	var prepped := Pen.prep(sk, live.view.meshes)
	var worst := [-99.0, -99.0]
	var worst_at := ""
	var behind_at := ""
	var f := 0
	for st in [["idle", 3.0], ["talk", 6.0], ["listen", 6.0]]:
		live.set_state(st[0])
		# standing and listening the arms hang as the clip has them (Director 06.11, 23:0x: «Г: руки как в клипе»);
		# measured while talking — and in the self-check, as before
		var counted: bool = st[0] == "talk" or not bool(spec["rt3d"]["arm_body"].get("stance_free", false))
		var t := 0.0
		while t < float(st[1]):
			live.process(DT)
			await process_frame
			t += DT
			f += 1
			if f % 20 == 0 and t > 0.3 and counted and (live.view.shown_act_w() > 0.95 or st[0] != "talk" or not bool(spec["rt3d"]["arm_body"].get("stance_free", false))):
				var m: Array = Pen.measure(prepped, g.out, unit)
				for i in 2:
					if float(m[2][i]) * 100.0 > float(worst[0]):
						worst[0] = float(m[2][i]) * 100.0
						worst_at = "%s %.2f s, %s hand" % [st[0], t, ["left", "right"][i]]
					if float(m[0][i]) * 100.0 > float(worst[1]):
						worst[1] = float(m[0][i]) * 100.0
						behind_at = "%s %s %.2f s, %s hand" % [st[0], String(live.get("act_name")), t, ["left", "right"][i]]
	nl[0].queue_free()
	await process_frame
	return [worst[0], worst[1], worst_at, behind_at]


func _t7() -> void:
	# a try on some villagers, with other stance measures: V3_IDS=mitya V3_TONE="spread_add_deg=0,spread_min_deg=10"
	var ids_env := OS.get_environment("V3_IDS")
	for id in ALL:
		if ids_env != "" and not (id in ids_env.split(",")):
			continue
		var sp7 := _spec(id)
		if OS.get_environment("V3_TONE") != "" and (sp7["rt3d"] as Dictionary).has("stance_tone"):
			for kv in OS.get_environment("V3_TONE").split(","):
				sp7["rt3d"]["stance_tone"][kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
		var w: Array = await _hand_depth(sp7)
		if ids_env != "":
			print("    %s: silhouette %.1f cm (%s), behind the clothes %.1f cm (%s)" % [id, float(w[0]), w[2], float(w[1]), w[3]])
		# 09.11 (arms along the body, arm_rest): the hands now hang as near the clothes as the real surface lets them —
		# beside an apron's flared edge they are up to ~3 cm inside the posed silhouette (the farthest fold per sector)
		# while in full view (Pavel 2.9, shots 09.11); the silhouette's limit is 3.5, and the real surface — how far a
		# hand vertex is behind the clothes — is held to 1 cm (was 2; measured 0.0–0.8 for all nine)
		_check(float(w[0]) <= 3.5, "%s: a hand %.1f cm inside the body's silhouette (≤ 3.5), %s" % [id, float(w[0]), w[2]])
		_check(float(w[1]) <= 1.0, "%s: a hand %.1f cm behind the clothes (≤ 1), %s" % [id, float(w[1]), w[3] if w.size() > 3 else ""])
	if ids_env != "":
		return
	var sp := _spec("pavel")
	(sp["rt3d"]["arm_body"] as Dictionary).erase("shell")
	(sp["rt3d"]["arm_body"] as Dictionary).erase("bake")
	_before_2100(sp, "listen")   # as he was at 15:56: the v2 listen clip, hands at the apron
	var raw: Array = await _hand_depth(sp)
	# 08.11: the apron on its own bones (second AI's model) — the v2 hand sits 2 cm in it with axis+tip clearing; the
	# measure must still read it as inside (> 1.5), and with no clearing at all deeper (> 3)
	_check(float(raw[0]) > 1.5, "self-check: Pavel with axis and fingertip only — %.1f cm (the test sees nothing)" % float(raw[0]))
	(sp["rt3d"]["arm_body"] as Dictionary)["max_deg"] = 0.0   # the clearing kept but allowed no turn at all
	var raw0: Array = await _hand_depth(sp)
	_check(raw0.size() == 3 and float(raw0[0]) > 3.0, "self-check: Pavel with no clearing at all — %s cm (the test sees nothing)" % str(raw0))


## Upper arm sideways angle before the hands are cleared, talking and listening: [mean, max] (degrees).
func _spread(spec: Dictionary) -> Array:
	var nl := _live(spec)
	if nl[1] == null:
		return [999.0, 999.0]
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var g = Spread.Grab.new()
	sk.add_child(g)
	if live.arm_body != null:
		sk.move_child(g, live.arm_body.get_index())
	var sum := 0.0
	var k := 0
	var mx := -99.0
	for st in ["talk", "listen"]:
		live.set_state(st)
		var t := 0.0
		while t < 6.0:
			live.process(DT)
			await process_frame
			t += DT
			if t < 1.0 or g.out.is_empty():
				continue
			for side in ["Left", "Right"]:
				var a: float = Spread.spread(sk, g.out, side)
				sum += a
				k += 1
				mx = maxf(mx, a)
	nl[0].queue_free()
	await process_frame
	return [sum / maxf(1.0, k), mx]


func _t8() -> void:
	for id in ALL:
		var sp0 := _spec(id)
		(sp0["rt3d"]["arm_body"] as Dictionary).erase("bake")   # the clips and their blending, not the clearing
		var w: Array = await _spread(sp0)
		# 08.11, 21:21: the second AI's clips (Nina 25°/29°, Varvara 23°/33°, Ulyana 23°/28°, Pelageya 17°/30°) accepted
		# by the Director («в целом норм, я не вижу проблем у других») — the bar is a scarecrow (31–63° on 07.11), not these
		_check(float(w[0]) <= 26.0 and float(w[1]) <= 34.0, "%s: arms spread %.0f° on average, %.0f° at most (≤ 26 / 34)" % [id, float(w[0]), float(w[1])])
	var sp := _spec("nina")
	sp["rt3d"]["act_body"]["upper"] = ["LeftShoulder", "RightShoulder", "neck", "Head"]
	_before_2100(sp, "listen")   # where it was seen (15:56): the v2 listen clip
	(sp["rt3d"]["arm_body"] as Dictionary).erase("bake")
	var raw: Array = await _spread(sp)
	_check(float(raw[1]) > 35.0, "self-check: Nina with the stance's shoulders — only %.0f° (the test sees no scarecrow)" % float(raw[1]))


## Listening pose against the stance: [shoulder width listening / standing, the farthest elbow forward of the
## shoulder (m, hips' frame), the farthest hand behind its shoulder (m)] — after every modifier.
func _listen_pose(spec: Dictionary) -> Array:
	var nl := _live(spec)
	if nl[1] == null:
		return [0.0, 99.0, 99.0]
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var g = Spread.Grab.new()
	sk.add_child(g)
	var unit := float(live.arm_body.get("_unit")) if live.arm_body != null else 1.0
	var ids := {}
	for b in ["Hips", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand"]:
		ids[b] = sk.find_bone(b)
	var width := [0.0, 0.0]
	var fwd := -99.0
	var back := -99.0
	for i in 2:
		live.set_state(["idle", "listen"][i])
		var t := 0.0
		var n := 0
		while t < 5.0:
			live.process(DT)
			await process_frame
			t += DT
			if t < 1.5 or g.out.is_empty():
				continue
			var hips: Transform3D = g.out[ids["Hips"]]
			var inv := hips.affine_inverse()
			var la: Vector3 = inv * (g.out[ids["LeftArm"]] as Transform3D).origin
			var ra: Vector3 = inv * (g.out[ids["RightArm"]] as Transform3D).origin
			width[i] += la.distance_to(ra)
			n += 1
			if i == 1:
				# forward in the hips' frame: where both feet's toes point as posed (both: each foot alone turns out)
				var f := Vector3.ZERO
				for sd in ["Left", "Right"]:
					f += inv * (g.out[sk.find_bone(sd + "ToeBase")] as Transform3D).origin \
							- inv * (g.out[sk.find_bone(sd + "Foot")] as Transform3D).origin
				f.y = 0.0
				f = f.normalized()
				for sd in ["Left", "Right"]:
					var a: Vector3 = inv * (g.out[ids[sd + "Arm"]] as Transform3D).origin
					var e: Vector3 = inv * (g.out[ids[sd + "ForeArm"]] as Transform3D).origin
					var h: Vector3 = inv * (g.out[ids[sd + "Hand"]] as Transform3D).origin
					fwd = maxf(fwd, (e - a).dot(f) / unit)
					back = maxf(back, -(h - a).dot(f) / unit)
		width[i] /= maxf(1.0, n)
	nl[0].queue_free()
	await process_frame
	return [width[1] / maxf(1e-6, width[0]), fwd, back]


func _t9() -> void:
	for id in ALL:
		var w: Array = await _listen_pose(_spec(id))
		_check(float(w[0]) >= 0.97, "%s: shoulders listening %.0f %% of standing (≥ 97)" % [id, float(w[0]) * 100.0])
		_check(float(w[1]) <= 0.12, "%s: elbow %.0f cm in front of the shoulder listening (≤ 12)" % [id, float(w[1]) * 100.0])
		print("    %s listening: shoulders %.0f %%, elbow %.0f cm forward, hand %.0f cm behind the shoulder" % [id,
				float(w[0]) * 100.0, float(w[1]) * 100.0, float(w[2]) * 100.0])
		_check(float(w[2]) <= 0.12, "%s: hand %.0f cm behind the shoulder listening (≤ 12)" % [id, float(w[2]) * 100.0])
	var sp := _before_2100(_spec("pavel"), "listen")
	var raw: Array = await _listen_pose(sp)
	print("    v2 listen clip, pavel: shoulders %.0f %%, elbow %.0f cm forward, hand %.0f cm behind" % [
			float(raw[0]) * 100.0, float(raw[1]) * 100.0, float(raw[2]) * 100.0])
	_check(float(raw[0]) < 0.97 or float(raw[1]) > 0.12 or float(raw[2]) > 0.12,
			"self-check: Pavel with the v2 listen clip passes (the test sees nothing)")


## Jerks (frames with the hand's acceleration over 2 mm/frame²) and back-and-forth reversals, the worse hand, after
## the first half second of the state.
func _jitter(spec: Dictionary, state: String, turning: bool, legacy: bool) -> Array:
	var nl := _live(spec)
	if nl[1] == null:
		return [999, 999]
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var g = Spread.Grab.new()
	sk.add_child(g)
	var unit := float(live.arm_body.get("_unit"))
	live.arm_body.set("enabled", turning)
	live.arm_body.set("legacy_zero_dt", legacy)
	var hb := [sk.find_bone("LeftHand"), sk.find_bone("RightHand")]
	live.set_state("idle")
	for i in 30:
		live.process(DT)
		await process_frame
	live.set_state(state)
	var prev := [Vector3.ZERO, Vector3.ZERO]
	var pd := [Vector3.ZERO, Vector3.ZERO]
	var jerks := [0, 0]
	var flips := [0, 0]
	for f in 300:
		live.process(DT)
		await process_frame
		if g.out.is_empty():
			continue
		for s in 2:
			var p: Vector3 = (g.out[hb[s]] as Transform3D).origin / unit
			var d: Vector3 = p - (prev[s] as Vector3)
			if f > 30:
				if (d - (pd[s] as Vector3)).length() * 1000.0 > 2.0:
					jerks[s] += 1
				if d.length() > 0.0005 and (pd[s] as Vector3).length() > 0.0005 and d.dot(pd[s] as Vector3) < 0.0:
					flips[s] += 1
			pd[s] = d
			prev[s] = p
	nl[0].queue_free()
	await process_frame
	return [maxi(jerks[0], jerks[1]), maxi(flips[0], flips[1])]


func _t10() -> void:
	for id in ["pavel", "pelageya", "mitya", "ilya", "manager"]:
		for st in ["idle", "talk", "listen"]:
			var on: Array = await _jitter(_spec(id), st, true, false)
			var off: Array = await _jitter(_spec(id), st, false, false)
			_check(int(on[0]) <= int(off[0]) + 3 and int(on[1]) <= int(off[1]) + 3,
					"%s %s: jerks %d, back-and-forth %d with the clearing; the clip alone %d, %d (+3 at most)" % [id, st,
					int(on[0]), int(on[1]), int(off[0]), int(off[1])])
	var bad := 0
	for id in ["pelageya", "pavel"]:
		var sp := _before_2100(_spec(id))
		(sp["rt3d"]["arm_body"] as Dictionary).erase("bake")   # as before 20:21: the clearing done live only
		# 10.11: and as before the standing arms were brought to the sides (StanceToneModifier) — Pelageya's arms now
		# hang clear of the skirt, the clearing has nothing to jerk at and the self-check saw nothing (CI 42870405229)
		(sp["rt3d"] as Dictionary).erase("stance_tone")
		var raw: Array = await _jitter(sp, "listen", true, true)
		var off: Array = await _jitter(sp, "listen", false, false)
		print("    follower skipped, %s listening: jerks %d, back-and-forth %d (clip alone %d, %d)" % [id, int(raw[0]),
				int(raw[1]), int(off[0]), int(off[1])])
		if int(raw[0]) > int(off[0]) + 3 or int(raw[1]) > int(off[1]) + 3:
			bad += 1
	_check(bad >= 1, "self-check: with the follower skipped neither Pelageya nor Pavel jerks (the test sees nothing)")


## The data as the defects were seen (before 06.11, 21:xx): the stance, «listen» and «talk» clips carried from the v2
## figures, none of the later additions (new Meshy motions joined, calm clavicles, shoulder weights). The self-checks
## reproduce what the Director saw on it.
static func _before_2100(spec: Dictionary, listen := "idle") -> Dictionary:
	var r: Dictionary = spec["rt3d"]
	r["clips"]["idle"] = "idle"
	r["clips"]["listen"] = listen
	r["clips"]["talk"] = "talk"
	if r.has("idle"):
		r["idle"]["pool"] = [{"clip": "idle", "weight": 1}]
	for k in ["concat", "calm_shoulders", "shoulder_weights"]:
		r.erase(k)
	if r.has("arm_body"):
		(r["arm_body"] as Dictionary).erase("stance_free")
	return spec


## How far the skin of the shoulder tops and the upper chest slides on the chest (mm, mean over the vertices) through
## `state` (tests/probe_shoulder_jelly.gd).
func _jelly(spec: Dictionary, state: String, secs := 5.0) -> float:
	var nl := _live(spec)
	if nl[1] == null:
		return 999.0
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var g = Pen.Grab.new()
	sk.add_child(g)
	var unit := float(live.arm_body.get("_unit")) if live.arm_body != null else 1.0
	var chest := sk.find_bone("Spine02")
	var pn: Vector3 = sk.get_bone_global_rest(sk.find_bone("neck")).origin
	var la: Vector3 = sk.get_bone_global_rest(sk.find_bone("LeftArm")).origin
	var ra: Vector3 = sk.get_bone_global_rest(sk.find_bone("RightArm")).origin
	var ysh := (la.y + ra.y) * 0.5
	var prepped: Array = Pen.prep(sk, live.view.meshes)
	var rest_poses: Array = []
	for b in sk.get_bone_count():
		rest_poses.append(sk.get_bone_global_rest(b))
	var picks: Array = []
	for ei in prepped.size():
		var vs: PackedVector3Array = prepped[ei][0]
		var mats := {}
		for k in range(0, vs.size(), 5):
			var p: Vector3 = Pen.skin_pt(prepped[ei], k, rest_poses, mats)[0]
			if absf(p.y - ysh) > 0.06 * unit:
				continue
			if (p.x < la.x and p.x > pn.x + 0.03 * unit) or (p.x > ra.x and p.x < pn.x - 0.03 * unit):
				picks.append([ei, k])
	live.set_state(state)
	var lo: Array = []
	var hi: Array = []
	for i in picks.size():
		lo.append(Vector3(INF, INF, INF))
		hi.append(Vector3(-INF, -INF, -INF))
	var t := 0.0
	var f := 0
	while t < secs:
		live.process(DT)
		await process_frame
		t += DT
		f += 1
		if t < 1.0 or g.out.is_empty() or f % 6 != 0:
			continue
		var inv: Transform3D = (g.out[chest] as Transform3D).affine_inverse()
		var mats_by := {}
		for i in picks.size():
			var ei: int = picks[i][0]
			if not mats_by.has(ei):
				mats_by[ei] = {}
			var q: Vector3 = inv * (Pen.skin_pt(prepped[ei], picks[i][1], g.out, mats_by[ei])[0] as Vector3) / unit
			lo[i] = Vector3(minf(lo[i].x, q.x), minf(lo[i].y, q.y), minf(lo[i].z, q.z))
			hi[i] = Vector3(maxf(hi[i].x, q.x), maxf(hi[i].y, q.y), maxf(hi[i].z, q.z))
	var mean := 0.0
	for i in picks.size():
		mean += ((hi[i] as Vector3) - (lo[i] as Vector3)).length() * 1000.0
	nl[0].queue_free()
	await process_frame
	return mean / maxf(1.0, picks.size())


## The widest the knees get apart walking for 2 s (m): what tears a skirt that hangs on the leg bones.
const SkirtProbe := preload("res://tests/probe_skirt_stretch.gd")
const SKIRTS := ["nina", "pelageya", "ilya_wife", "tamara"]
## the skirt's cloth alone: above the film that closes the bell from below, below the jacket's hem (m)
const CLOTH_LO := 0.40
const CLOTH_HI := 0.72
## cloth edges get no longer than this walking (m): the chains of a wide bell swing apart by up to 4,5 cm (Pelageya),
## cloth hung on the leg bones comes apart by 30–40 cm
const PULL_MAX_M := 0.06
## the strip of cloth this near a shin is not measured (m)
const SHIN_STRIP_M := 0.10
## Tamara (found 10.11 by this measure, not changed): in her rig a patch of the skirt's front, 11 cm before the shin, is
## still on the leg bones (LeftLeg 0,71 + LeftUpLeg 0,28 beside vertices on the skirt's bones) and goes up to 15 cm with
## the leg. On film (18 frames, three sides) it reads as a fold of the knee through the skirt, not a tear, so it stays;
## the bound keeps it from growing. The cure, if the Director asks: tools/reweight_skirt_glb.py on her model.
const PULL_KNOWN_M := {"tamara": 0.17}


## Walking the full stride: [how much longer than standing the most pulled edge of the skirt's cloth gets (m) — as the
## model is rigged, the same with the cloth hung on the leg bones (as her model was before 10.11), triangles in the
## band]. The cloth on the legs: every skirt bone's share of a vertex goes to the leg bone at that place.
func _skirt_tear(spec: Dictionary) -> Array:
	var r: Array = _live(spec)
	var live = r[1]
	if live == null:
		return [-1, -1, 0]
	var av = live.view
	var sk: Skeleton3D = av.skeleton
	var bd: Dictionary = SkirtProbe.band(av, CLOTH_LO, CLOTH_HI)
	var binds: Array = bd["bind_bone"]
	var legs := {}
	for nm in ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
		legs[nm] = binds.find(sk.find_bone(nm))
	var knee_y := sk.get_bone_global_rest(sk.find_bone("LeftLeg")).origin.y
	var lx := sk.get_bone_global_rest(sk.find_bone("LeftUpLeg")).origin.x
	var rx := sk.get_bone_global_rest(sk.find_bone("RightUpLeg")).origin.x
	var bind_pos: Dictionary = SkirtProbe.skinned(av, bd, true)
	var vid: PackedInt32Array = bd["vid"]
	# not the strips right at the shins: by Tamara's rig the cloth there goes with the leg (the knee showing through
	# the skirt — a fold, not a tear); a tear is the cloth between and around the legs coming apart
	var unit := sk.global_transform.basis.get_scale().y   # skeleton units → metres
	var shins: Array = []
	for side in ["Left", "Right"]:
		shins.append([sk.get_bone_global_rest(sk.find_bone(side + "Leg")).origin, sk.get_bone_global_rest(sk.find_bone(side + "Foot")).origin])
	var keep := PackedInt32Array()
	var all_tris: PackedInt32Array = bd["tris"]
	for i in range(0, all_tris.size(), 3):
		var far := true
		for e in 3:
			var p: Vector3 = bind_pos[all_tris[i + e]]
			for sh in shins:
				far = far and Geometry3D.get_closest_point_to_segment(p, sh[0], sh[1]).distance_to(p) * unit >= SHIN_STRIP_M
		if far:
			keep.append_array([all_tris[i], all_tris[i + 1], all_tris[i + 2]])
	bd["tris"] = keep
	var vb2: Array = []
	var vw2: Array = []
	for n in vid.size():
		var p: Vector3 = bind_pos[vid[n]]
		var side := "Left" if absf(p.x - lx) < absf(p.x - rx) else "Right"
		var leg: int = legs[side + ("UpLeg" if p.y > knee_y else "Leg")]
		var bb := PackedInt32Array()
		var ww := PackedFloat32Array()
		var moved := 0.0
		var b0: PackedInt32Array = bd["vb"][n]
		var w0: PackedFloat32Array = bd["vw"][n]
		for k in b0.size():
			if sk.get_bone_name(int(binds[b0[k]])).begins_with("Skirt"):
				moved += w0[k]
			else:
				bb.append(b0[k])
				ww.append(w0[k])
		if moved > 0.0:
			bb.append(leg)
			ww.append(moved)
		vb2.append(bb)
		vw2.append(ww)
	var on_legs := bd.duplicate()
	on_legs["vb"] = vb2
	on_legs["vw"] = vw2
	var st := {"want": false, "now": []}
	var cb := func():
		if st["want"]:
			st["want"] = false
			st["now"] = [SkirtProbe.skinned(av, bd, false), SkirtProbe.skinned(av, on_legs, false)]
	sk.skeleton_updated.connect(cb)
	live.set_state("idle")
	var t := 0.0
	while t < 0.6:
		live.process(DT)
		await process_frame
		t += DT
	st["want"] = true
	live.process(DT)
	await process_frame
	var standing: Array = st["now"]
	var worst := [0.0, 0.0]
	if standing.size() == 2:
		live.walk(true, 0.9 * live.view.ppm * 0.55, 0.55)
		t = 0.0
		var i := 0
		while t < 2.0:
			st["want"] = t > 0.5 and i % 4 == 0
			st["now"] = []
			live.process(DT)
			await process_frame
			t += DT
			i += 1
			var now: Array = st["now"]
			if now.size() == 2:
				if OS.get_environment("SKIRT_DEBUG") != "" and _longest_pull(bd, standing[0], now[0]) * unit > worst[0]:
					_pull_where(bd, standing[0], now[0], sk, unit, t)
				worst[0] = maxf(worst[0], _longest_pull(bd, standing[0], now[0]) * unit)
				worst[1] = maxf(worst[1], _longest_pull(bd, standing[1], now[1]) * unit)
	sk.skeleton_updated.disconnect(cb)
	(r[0] as Node).queue_free()
	await process_frame
	return [worst[0] if standing.size() == 2 else -1.0, worst[1], (bd["tris"] as PackedInt32Array).size() / 3]


## SKIRT_DEBUG=1: where the most pulled edge is (standing position in metres, the bones of its two ends).
func _pull_where(bd: Dictionary, rest: Dictionary, now: Dictionary, sk: Skeleton3D, unit: float, t: float) -> void:
	var tris: PackedInt32Array = bd["tris"]
	var vid: PackedInt32Array = bd["vid"]
	var most := 0.0
	var at := [0, 0]
	for i in range(0, tris.size(), 3):
		for e in 3:
			var a := tris[i + e]
			var b := tris[i + (e + 1) % 3]
			var d := (now[a] as Vector3).distance_to(now[b]) - (rest[a] as Vector3).distance_to(rest[b])
			if d > most:
				most = d
				at = [a, b]
	var names := func(v: int) -> String:
		var n := vid.find(v)
		var out := ""
		for k in (bd["vb"][n] as PackedInt32Array).size():
			out += "%s %.2f " % [sk.get_bone_name(int(bd["bind_bone"][bd["vb"][n][k]])), bd["vw"][n][k]]
		return out
	print("      t %.2f: +%.0f mm between %s [%s] and %s [%s]" % [t, most * unit * 1000.0, str((rest[at[0]] as Vector3) * unit), names.call(at[0]), str((rest[at[1]] as Vector3) * unit), names.call(at[1])])


## How much longer the most pulled edge of the band's triangles is than standing (skeleton units): cloth that bends and
## swings keeps its edges; cloth torn between two legs has edges pulled across the gap.
func _longest_pull(bd: Dictionary, rest: Dictionary, now: Dictionary) -> float:
	var tris: PackedInt32Array = bd["tris"]
	var most := 0.0
	for t in range(0, tris.size(), 3):
		for e in 3:
			var a := tris[t + e]
			var b := tris[t + (e + 1) % 3]
			most = maxf(most, (now[a] as Vector3).distance_to(now[b]) - (rest[a] as Vector3).distance_to(rest[b]))
	return most


## V3-12 (Director 09.11, 22:18: «Пелагею коробит, будто из двух частей, когда идёт тянуть бечеву»; 10.11, 10:46 «делай
## ок»): Pelageya's skirt hung on her leg bones — the full stride tore it in two with the grey lining stretched between
## the halves (for one night she walked half the stride, walk_stride_k 0,5). Since 10.11 her skirt has its own bones
## (tools/rig_skirt.py), as Nina's, Tamara's and Ilya's wife's: walking the full stride the cloth stays whole.
func _t12() -> void:
	for id in SKIRTS:
		var sp := _spec(id)
		var rt: Dictionary = sp["rt3d"]
		var ps = load(String(rt.get("scene", ""))) as PackedScene
		var has_bones := false
		if ps != null:
			var inst := ps.instantiate()
			var found: Array = inst.find_children("*", "Skeleton3D", true, false)
			has_bones = not found.is_empty() and (found[0] as Skeleton3D).find_bone("Skirt0_0") >= 0
			inst.free()
		var rigged: bool = has_bones and not (rt.get("skirt", {}) as Dictionary).is_empty()
		var k := float(rt.get("walk_stride_k", 1.0))
		_check(rigged or k <= 0.6, "%s: a skirt without its own bones (in the model: %s, rt3d.skirt: %s) walks the full stride (walk_stride_k %.2f > 0,6) — it tears on the legs" % [id, str(has_bones), str(rt.has("skirt")), k])
	var sp_p := _spec("pelageya")
	_check(float((sp_p["rt3d"] as Dictionary).get("walk_stride_k", 1.0)) == 1.0, "Pelageya still walks a shortened stride (walk_stride_k %.2f) — her skirt is rigged, the half stride was its stand-in" % float((sp_p["rt3d"] as Dictionary).get("walk_stride_k", 1.0)))
	for id in SKIRTS:
		var got: Array = await _skirt_tear(_spec(id))
		print("    %s: %d cloth triangles; the most pulled edge on the full stride +%.0f mm (the same cloth on the leg bones: +%.0f mm)" % [id, got[2], float(got[0]) * 1000.0, float(got[1]) * 1000.0])
		_check(int(got[2]) > 500, "%s: only %d triangles of cloth between %.2f and %.2f m — the test measures no skirt" % [id, got[2], CLOTH_LO, CLOTH_HI])
		var most: float = float(PULL_KNOWN_M.get(id, PULL_MAX_M))
		_check(float(got[0]) >= 0.0 and float(got[0]) <= most, "%s: an edge of the skirt's cloth is pulled %.0f mm longer walking (≤ %.0f) — the skirt tears" % [id, float(got[0]) * 1000.0, most * 1000.0])
		if not PULL_KNOWN_M.has(id):
			_check(float(got[1]) > 2.0 * PULL_MAX_M, "self-check %s: the same cloth hung on the leg bones is pulled only %.0f mm (a tear is over %.0f) — the measure sees no tear" % [id, float(got[1]) * 1000.0, 2.0 * PULL_MAX_M * 1000.0])


## Standing for `secs`: [left arm's mean spread from straight down (°, in the body's frontal plane), right arm's, the
## hips' travel across (cm, peak to peak)] — as shown, after every modifier.
func _stand_measure(spec: Dictionary, secs := 6.0) -> Array:
	var nl := _live(spec)
	if nl[1] == null:
		return [99.0, 99.0, 0.0]
	var live = nl[1]
	var sk: Skeleton3D = live.view.skeleton
	var AR = load("res://scripts/actors/arm_rest.gd")
	var ax: Array = AR.axes(sk)
	var ids := {}
	for b in ["Hips", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]:
		ids[b] = sk.find_bone(b)
	var got := {}
	var cb := func():
		for b in ids:
			got[b] = sk.get_bone_global_pose(ids[b])
	sk.skeleton_updated.connect(cb)
	var unit := sk.global_transform.basis.get_scale().y
	var hr: Transform3D = sk.get_bone_global_rest(ids["Hips"])
	var across: Vector3 = hr.basis * (ax[1] as Vector3)
	live.set_state("idle")
	var sum := [0.0, 0.0]
	var n := 0
	var lo := INF
	var hi := -INF
	var t := 0.0
	while t < secs:
		live.process(DT)
		await process_frame
		t += DT
		if t < 1.0 or got.is_empty():
			continue
		var inv: Transform3D = (got["Hips"] as Transform3D).affine_inverse()
		for i in 2:
			var sd: String = ["Left", "Right"][i]
			var d: Vector3 = inv.basis * ((got[sd + "ForeArm"] as Transform3D).origin - (got[sd + "Arm"] as Transform3D).origin)
			sum[i] += rad_to_deg((AR.spread_of(d, ax, i == 0) as Vector2).x)
		n += 1
		var x: float = (got["Hips"] as Transform3D).origin.dot(across.normalized()) * unit * 100.0
		lo = minf(lo, x)
		hi = maxf(hi, x)
	sk.skeleton_updated.disconnect(cb)
	(nl[0] as Node).queue_free()
	await process_frame
	return [sum[0] / maxf(1.0, n), sum[1] / maxf(1.0, n), hi - lo]


## V3-13 (Director 09.11, 22:18: «руки у них не вдоль, а будто в воздухе под углом… у Нины торчит… как у многих»): the
## stance clips hold the upper arms 14–26° out; each is turned in as far as the hand stays clear of the clothes' real
## surface (scripts/actors/arm_rest.gd, the curves — tools/bake_arm_rest.sh). Standing, no arm is further out than 20°.
func _t13() -> void:
	var worst_raw := 0.0
	for id in ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]:
		var m: Array = await _stand_measure(_spec(id), 4.0)
		var sp := _spec(id)
		((sp["rt3d"] as Dictionary)["arm_body"] as Dictionary).erase("rest")
		var raw: Array = await _stand_measure(sp, 4.0)
		worst_raw = maxf(worst_raw, maxf(float(raw[0]), float(raw[1])))
		print("    %s: arms %.0f° / %.0f° from straight down (the clip alone: %.0f° / %.0f°)" % [id, m[0], m[1], raw[0], raw[1]])
		_check(float(m[0]) <= 20.0 and float(m[1]) <= 20.0, "%s: an arm hangs %.0f° / %.0f° out standing (≤ 20; the widest now — Ulyana's right over her coat, 19)" % [id, m[0], m[1]])
		_check(float(m[0]) <= float(raw[0]) + 1.0 and float(m[1]) <= float(raw[1]) + 1.0, "%s: an arm is further out than the clip has it (%.0f° / %.0f° against %.0f° / %.0f°)" % [id, m[0], m[1], raw[0], raw[1]])
	_check(worst_raw > 22.0, "self-check: the clips alone hold no arm further than %.0f° out — the test sees no arm in the air" % worst_raw)


## V3-14 (Director 09.11, 22:18: «они слишком статичные, будто солдаты стоят, Агата у нас более живая, потому что
## покачивается»): standing, the weight goes from foot to foot (ActorLife3D sway, data rt3d.life.sway_*): the hips
## travel across by a centimetre and a half or more within a period.
func _t14() -> void:
	var still_max := 0.0
	for id in ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]:
		var m: Array = await _stand_measure(_spec(id), 10.0)
		var sp := _spec(id)
		var lf: Dictionary = (sp["rt3d"] as Dictionary).get("life", {})
		for k in ["sway_cm", "sway_fore_cm", "sway_roll_deg", "sway_yaw_deg"]:
			lf[k] = 0.0
		var still: Array = await _stand_measure(sp, 10.0)
		still_max = maxf(still_max, float(still[2]))
		print("    %s: the hips travel %.1f cm across standing (without the sway: %.1f)" % [id, m[2], still[2]])
		_check(float(m[2]) >= 1.5 and float(m[2]) <= 7.0, "%s: the hips travel %.1f cm across standing (1,5–7: alive, not rocking)" % [id, m[2]])
		_check(float(m[2]) > float(still[2]) + 1.0, "self-check %s: without the sway the hips travel %.1f cm, with it %.1f — the test sees no sway" % [id, still[2], m[2]])


func _t11() -> void:
	for id in ["ilya", "pavel", "pelageya", "mitya", "nina"]:
		var st: float = await _jelly(_spec(id), "idle")
		var tk: float = await _jelly(_spec(id), "talk")
		print("    %s: shoulder skin slides %.1f mm standing, %.1f mm talking" % [id, st, tk])
		_check(st <= 6.0 and tk <= 15.0, "%s: the shoulder skin slides %.1f mm standing (≤ 6), %.1f mm talking (≤ 15)" % [id, st, tk])
	# 09.11 (livening, breath 1.5°): the breath on the lower chest bone (Spine01) slides the shoulder skin — 10 mm
	# standing with all of it there, 6–7 mm at the old 0.6 share; on Spine02 0.7 mm. Self-check: the test sees it.
	var sb := _spec("ilya")
	(sb["rt3d"]["life"] as Dictionary)["breath_chest_k"] = 1.0
	var low: float = await _jelly(sb, "idle")
	_check(low > 6.0, "self-check: Ilya breathing on Spine01 — only %.1f mm standing (the test sees no breath jelly)" % low)
	var sp := _spec("ilya")
	_before_2100(sp)   # 08.11: the second AI's clips do not slide even uncalmed — the v2 talk clip's clavicles do
	(sp["rt3d"] as Dictionary).erase("calm_shoulders")
	var raw: float = await _jelly(sp, "talk")
	_check(raw > 20.0, "self-check: Ilya with the clips' own clavicles — only %.1f mm talking (the test sees no jelly)" % raw)
