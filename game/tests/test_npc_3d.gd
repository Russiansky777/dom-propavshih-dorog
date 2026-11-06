extends SceneTree
## Villagers in real 3D (Director 30.10: «как живые… остальные можно чуточку попроще»; NpcLive3D, actor data rt3d):
##   - every villager with rt3d loads its live model (Meshy mesh decimated for Steam, skeleton, four clips);
##   - the facade sheet is drawn invisible, the live figure stands at the same feet (body under the sprite);
##   - talk / listen fade in over the stance and out again; the body turns to Agata at any angle, smoothly;
##   - walking off in a staging plays the walk cycle and stops at the end.
## Headless: the rendering is a dummy, the skeleton and the blend weights are real.
##   godot --headless --path game -s res://tests/test_npc_3d.gd

var gs: Node
var rm: Node
var sr: Node
var main_node: Node
var LiveScript = null
var _results: Array = []
var _cur_ok := true
var _cur_msgs: Array = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_cur_ok = false
		_cur_msgs.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_s(sec: float) -> void:
	var t := 0.0
	var guard := 0
	while t < sec and guard < 100000:
		await process_frame
		t += 1.0 / 60.0
		guard += 1


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	LiveScript = load("res://scripts/actors/npc_live_3d.gd")
	LiveScript.forced = "3d"
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	var t0 := Time.get_ticks_msec()
	await _test_models()
	_report("Every villager with rt3d: live model loaded (200k-ish triangles, v3, Meshy rig, idle/listen/talk/walk), facade invisible", t0)
	t0 = Time.get_ticks_msec()
	await _test_states()
	_report("Talk / listen fade in and out over the stance; turning to Agata is smooth at any angle; walking off plays the cycle", t0)
	t0 = Time.get_ticks_msec()
	await _test_bodies()
	_report("Bodies in a conversation (Director 01.11, lines 6, 10, 52, 53, 55): talking and listening with the hands and the head — the body does not bulge, rock, crouch like a heron or step about; the boots stand flat; the hands stay out of the body", t0)
	t0 = Time.get_ticks_msec()
	await _test_stop_steps()
	_report("Coming to a stop (Director 01.11, line 55 «Нина тоже мельтешит»): after walking off in a staging the feet close up in one or two steps, not a patter", t0)
	LiveScript.forced = ""
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== villagers 3D: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _report(name: String, t0: int) -> void:
	print(("PASS  " if _cur_ok else "FAIL  ") + name + "  (%d ms)" % (Time.get_ticks_msec() - t0))
	for m in _cur_msgs:
		print("        - " + str(m))
	_results.append([name, _cur_ok])
	_cur_ok = true
	_cur_msgs = []


## A villager standing in a room: the first NpcActor with a live view, trying rooms where villagers stand.
func _find_live() -> Node:
	# every room × two moments of the story (day one after the post; day two after the mill) — the first live villager
	var sd: Node = root.get_node("StoryData")
	var early := ["done_M01"]
	var mid: Array = []
	for id in sd.scene_order:
		if id == "M17":
			break
		mid.append("done_" + id)
		for f in sd.scene(id).get("grants", {}).get("flags", []):
			mid.append(String(f))
	for flags in [early, mid]:
		for rid in ["R1", "M3", "O3", "O1", "Z1", "M2", "R3", "Z3", "R2", "M1", "O4", "H1"]:
			gs.reset()
			for f in flags:
				gs.set_flag(f, true)
			rm.change_room(rid, "default")
			await _frames(8)
			for n in rm.current_room.get_children():
				if n.get("live") != null:
					return n
	return null


func _test_models() -> void:
	var ids := ["nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana", "tamara"]
	var moves := {}   # id -> [idle time now, idle rate, breath period, breath t]
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		_check(spec is Dictionary and spec.has("rt3d"), "%s: actor data without rt3d" % id)
		if not (spec is Dictionary):
			continue
		var v := Actor3D.new()
		root.add_child(v)
		var ok := v.setup(spec)
		_check(ok, "%s: live model not loaded (%s)" % [id, v.load_error])
		if ok:
			var tris := v.triangle_count()
			# 06.11 (block 3): the v3 models — 200k triangles (v2 were ≈120k)
			_check(tris > 150000 and tris < 260000, "%s: %d triangles (expected ≈200k, v3)" % [id, tris])
			for role in ["idle", "listen", "talk"]:
				_check(v.clips.has(role), "%s: clip %s missing" % [id, role])
			moves[id] = [float(v.idle_phase()[1]), v.idle_rate, v.life.breath_period_s, v.life.t]
			# Tamara never walks in a staging (scenes' npc_go): her walk clip is not used, its stride is not checked
			if v.clips.has("walk") and id != "tamara":
				_check(v.stride_m > 0.5 and v.stride_m < 3.5, "%s: ground covered by one walk clip %.2f m (Ilya's clip has two cycles)" % [id, v.stride_m])
		v.queue_free()
		await _frames(1)
	# Director 01.11: Ilya and Ulyana stood and swayed exactly alike. Every pair of villagers: the idle starts
	# at another point of the clip or runs at another rate, and they do not breathe in step.
	var keys := moves.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Array = moves[keys[i]]
			var b: Array = moves[keys[j]]
			_check(absf(a[0] - b[0]) > 0.15 or absf(a[1] - b[1]) > 0.01, "%s and %s: idle in step (t %.2f/%.2f, rate %.3f/%.3f)" % [keys[i], keys[j], a[0], b[0], a[1], b[1]])
			_check(absf(a[2] - b[2]) > 0.02 or absf(a[3] - b[3]) > 0.3, "%s and %s: breathe in step" % [keys[i], keys[j]])


func _test_states() -> void:
	var n: Node = await _find_live()
	_check(n != null, "no villager drawn live in any room on day one or day two")
	if n == null:
		return
	var live = n.live
	_check(n.sprite.material != null, "%s: facade not hidden" % n.actor_id)
	_check(live.body != null and live.body.get_parent() == n.sprite, "%s: live figure is not under the facade sprite" % n.actor_id)
	var fade_s := float(live.rt.get("state_fade_s", 0.4))   # 01.11: 0.4 → 0.7 s (Director, line 6 «слишком резко меняющаяся»)
	n.set_state("talk")
	await _wait_s(fade_s + 0.2)
	_check(live.act_name == "talk" and live.act_w > 0.95, "%s talking: talk weight %.2f (%s)" % [n.actor_id, live.act_w, live.act_name])
	var t1: float = live.act_t
	await _wait_s(0.3)
	_check(absf(live.act_t - t1) > 0.05, "%s talking: the clip runs (%.2f → %.2f)" % [n.actor_id, t1, live.act_t])
	n.set_state("idle")
	await _wait_s(fade_s + 0.2)
	_check(live.act_w < 0.01, "%s idle again: talk faded out (%.2f)" % [n.actor_id, live.act_w])
	# turn: a target behind — yaw moves every frame by less than the cap, and gets there
	var y0: float = live.yaw
	live.face(Vector2(0, -100), 0.55)
	var max_step := 0.0
	var prev: float = live.yaw
	for i in 90:
		await process_frame
		max_step = maxf(max_step, absf(angle_difference(prev, live.yaw)))
		prev = live.yaw
	_check(absf(angle_difference(live.yaw, live.yaw_target)) < deg_to_rad(3.0), "%s: did not turn to the target (%.0f° left)" % [n.actor_id, rad_to_deg(absf(angle_difference(live.yaw, live.yaw_target)))])
	_check(max_step < deg_to_rad(240.0 / 60.0 * 1.6), "%s: turn jumped %.1f° in a frame" % [n.actor_id, rad_to_deg(max_step)])
	_check(absf(angle_difference(y0, live.yaw)) > deg_to_rad(90.0), "%s: the turn was too small" % n.actor_id)
	# walk off: cycle plays, then stops
	var target: Vector2 = n.global_position + Vector2(160, 20)
	n.go_off(target, 1.2, false, rm.current_room)
	await _wait_s(0.6)
	_check(live.walking and live.walk_w > 0.6, "%s walking off: walk weight %.2f" % [n.actor_id, live.walk_w])
	await _wait_s(1.2)
	_check(not live.walking, "%s: still walking after the staging" % n.actor_id)
	_check(n.global_position.distance_to(target) < 2.0, "%s did not get there" % n.actor_id)



# --- Bodies in a conversation (Director 01.11) ---------------------------------------------------------------------

const DT := 1.0 / 60.0
const BODY_SEQ := [["idle", 2.0], ["talk", 4.5], ["idle", 1.5], ["listen", 3.0], ["idle", 1.0]]
const TOE_MAX_DEG := 6.0        # a set-down boot's toe above the model's own foot line (old: 13–27° in «talk»)
const LEAN_V_MAX := 14.0        # the torso's lean (hips → neck) changes at most this fast, deg/s (old: 24–33 in «talk»)
const SIDE_MAX := 3.0           # the torso's sideways lean over a «talk», range, deg (old: 6)
const LEGS_SWING_MAX := 6.0     # the legs' slope (hips over the ankles) over a «talk» and the stance after it, range, deg (old Ulyana: 13 — the heron)
const STEPS_MAX := 1            # steps taken standing through a conversation (old: 2–4 every «talk»)
const HAND_MAX_M := 0.012       # how deep a hand / forearm (with its thickness) is in the body as drawn (the clips: up to 7 cm)

var _body_m: Dictionary = {}


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


## The figure as drawn (after every modifier): toe pitch above the bind pose's foot line per foot, the torso's lean
## (forward, sideways), the legs' slope.
func _body_measure(v: Actor3D) -> Dictionary:
	var sk := v.skeleton
	var xf := v._skel_to_turn()
	var pos := func(nm: String) -> Vector3:
		return xf * sk.get_bone_global_pose(sk.find_bone(nm)).origin
	var rest := func(nm: String) -> Vector3:
		return xf * sk.get_bone_global_rest(sk.find_bone(nm)).origin
	var toe: Array = []
	for side in ["Left", "Right"]:
		var d: Vector3 = pos.call(side + "ToeBase") - pos.call(side + "Foot")
		var d0: Vector3 = rest.call(side + "ToeBase") - rest.call(side + "Foot")
		toe.append(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())) - rad_to_deg(atan2(d0.y, Vector2(d0.x, d0.z).length())))
	var h: Vector3 = pos.call("Hips")
	var lean: Vector3 = pos.call("neck") - h
	var fm: Vector3 = (pos.call("LeftFoot") + pos.call("RightFoot")) * 0.5
	return {"toe": toe, "lean": Vector2(rad_to_deg(atan2(lean.z, lean.y)), rad_to_deg(atan2(lean.x, lean.y))),
		"legs": rad_to_deg(atan2(h.z - fm.z, h.y - fm.y))}


## A villager through idle → talk → idle → listen → idle as NpcLive3D poses it. `old`: the data as before 01.11 (no
## act_body, arm_body, boots; the state fade 0.4 s) — the self-check.
func _body_run(id: String, old: bool, clear_off: bool = false) -> Dictionary:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if old:
		for k in ["act_body", "arm_body", "concat", "calm_shoulders", "shoulder_weights"]:
			(spec["rt3d"] as Dictionary).erase(k)
		# the clips of that time (the v2 stance and talk; 06.11 the new Meshy motions came)
		spec["rt3d"]["clips"]["idle"] = "idle"
		spec["rt3d"]["clips"]["listen"] = "listen"
		spec["rt3d"]["clips"]["talk"] = "talk"
		if spec["rt3d"].has("idle"):
			spec["rt3d"]["idle"]["pool"] = [{"clip": "idle", "weight": 1}]
		(spec["rt3d"]["feet"] as Dictionary).erase("boot")
		spec["rt3d"]["state_fade_s"] = 0.4
	if clear_off and spec["rt3d"].has("arm_body"):
		(spec["rt3d"]["arm_body"] as Dictionary).erase("bake")   # the clips as they came (06.11: the clearing is baked in)
	var n := _fake_npc()
	var live = LiveScript.new()
	n.add_child(live)
	var out := {"toe": 0.0, "lean_v": 0.0, "side": 0.0, "legs": 0.0, "steps": 0, "hand_in": 0.0, "hand": 0.0, "ok": false}
	if not live.setup(n, spec, 0.55):
		n.queue_free()
		return out
	out["ok"] = true
	if clear_off and live.arm_body != null:
		live.arm_body.enabled = false   # the self-check: the hands as the clip has them, measured the same way
	live.face(Vector2(0, 1), 0.55, true)
	var v: Actor3D = live.view
	_body_m = {}
	var cb := func(): _body_m = _body_measure(v)
	v.skeleton.skeleton_updated.connect(cb)
	var prev_lean := Vector2.INF
	var stepping := [false, false]
	var talk_side := [INF, -INF]
	var legs := [INF, -INF]
	var phase := 0
	for seg in BODY_SEQ:
		live.set_state(seg[0])
		phase += 1
		var t := 0.0
		while t < float(seg[1]):
			live.process(DT)
			await process_frame
			t += DT
			if _body_m.is_empty():
				continue
			var m := _body_m
			for i in 2:
				if v._foot_lock[i] != null and v._foot_step[i] == null and t > 0.3:
					out["toe"] = maxf(out["toe"], float(m["toe"][i]))
				var st: bool = v._foot_step[i] != null
				if st and not stepping[i] and phase > 1:
					out["steps"] += 1
				stepping[i] = st
			var lean: Vector2 = m["lean"]
			if prev_lean != Vector2.INF:
				out["lean_v"] = maxf(out["lean_v"], (lean - prev_lean).length() / DT)
			prev_lean = lean
			if phase == 2:
				talk_side = [minf(talk_side[0], lean.y), maxf(talk_side[1], lean.y)]
			if phase == 2 or phase == 3:
				legs = [minf(legs[0], float(m["legs"])), maxf(legs[1], float(m["legs"]))]
			if live.arm_body != null and t > 0.3:
				for i in 2:
					out["hand_in"] = maxf(out["hand_in"], float(live.arm_body.depth_m[i]))
					out["hand"] = maxf(out["hand"], float(live.arm_body.shown_m[i]))
	out["side"] = talk_side[1] - talk_side[0]
	out["legs"] = legs[1] - legs[0]
	v.skeleton.skeleton_updated.disconnect(cb)
	n.queue_free()
	await process_frame
	return out


func _test_bodies() -> void:
	var ids := ["nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana", "tamara"]
	for id in ids:
		var r: Dictionary = await _body_run(id, false)
		_check(r["ok"], "%s: live model not loaded" % id)
		if not r["ok"]:
			continue
		print("        %-9s toe %4.1f°  lean %4.1f°/s  side %3.1f°  legs %3.1f°  steps %d  hand in clip %4.1f cm → drawn %3.1f cm" % [id, r["toe"], r["lean_v"], r["side"], r["legs"], r["steps"], r["hand_in"] * 100.0, r["hand"] * 100.0])
		_check(r["toe"] <= TOE_MAX_DEG, "%s: a set-down boot's toe up %.1f° (≤ %.0f; line 6 «ступня задрана»)" % [id, r["toe"], TOE_MAX_DEG])
		_check(r["lean_v"] <= LEAN_V_MAX, "%s: the torso's lean changed at %.0f°/s (≤ %.0f; line 6 «резко меняющаяся… разом выпирает»)" % [id, r["lean_v"], LEAN_V_MAX])
		_check(r["side"] <= SIDE_MAX, "%s: talking, the torso rocks %.1f° sideways (≤ %.0f; line 10 «кидает из стороны в сторону»)" % [id, r["side"], SIDE_MAX])
		_check(r["legs"] <= LEGS_SWING_MAX, "%s: talking, the legs' slope swings %.1f° — the feet left behind the body (≤ %.0f; line 53 «как цапля»)" % [id, r["legs"], LEGS_SWING_MAX])
		_check(int(r["steps"]) <= STEPS_MAX, "%s: %d steps standing through a conversation (≤ %d; line 55 «мельтешит»)" % [id, r["steps"], STEPS_MAX])
		_check(r["hand"] <= HAND_MAX_M, "%s: a hand %.1f cm in the body as drawn (≤ %.1f; lines 10, 52)" % [id, r["hand"] * 100.0, HAND_MAX_M * 100.0])

	# self-check: the data as it was fails the same metrics where the Director saw it
	var p_old: Dictionary = await _body_run("pavel", true)
	print("        pavel (old) toe %4.1f°  lean %4.1f°/s  side %3.1f°  legs %3.1f°  steps %d" % [p_old["toe"], p_old["lean_v"], p_old["side"], p_old["legs"], p_old["steps"]])
	_check(p_old["toe"] > TOE_MAX_DEG and p_old["lean_v"] > LEAN_V_MAX and p_old["side"] > SIDE_MAX and int(p_old["steps"]) > STEPS_MAX, "self-check: Pavel with the old data passes (toe %.1f°, lean %.0f°/s, side %.1f°, steps %d) — the metrics would not catch line 6" % [p_old["toe"], p_old["lean_v"], p_old["side"], p_old["steps"]])
	var pe_off: Dictionary = await _body_run("pelageya", false, true)
	print("        pelageya (hands not kept out) drawn %.1f cm" % (pe_off["hand"] * 100.0))
	# self-check of the hand metric: her clip as it came (the clearing not baked in) does put the left hand into her hip
	# (06.png)
	_check(pe_off["hand_in"] >= 0.03, "self-check: Pelageya's clip hand only %.1f cm in her body — the hull would not catch the 06.png hand" % (pe_off["hand_in"] * 100.0))
	_check(pe_off["hand"] > 0.03, "self-check: Pelageya's hands as the clip has them measure %.1f cm in the body as drawn — the metric would not catch 06.png" % (pe_off["hand"] * 100.0))
	var u_old: Dictionary = await _body_run("ulyana", true)
	print("        ulyana (old) legs %3.1f°  steps %d" % [u_old["legs"], u_old["steps"]])
	_check(u_old["legs"] > LEGS_SWING_MAX, "self-check: Ulyana with the old data: legs swing %.1f° — the metric would not catch the heron (line 53)" % u_old["legs"])



const STOP_STEPS_MAX := 2       # steps from the end of a walk until she stands (old: 3 in 0.75 s — Nina, Pelageya)


## Walks 2.5 s carried along as a staging carries her (NpcActor.go_off), stops, stands 2 s: steps after the stop.
func _stop_run(id: String, old: bool) -> int:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if old:
		var fk: Dictionary = spec["rt3d"]["feet"]
		fk.erase("close_on_stop")
		fk["step_turn_m"] = 0.035
		fk["settle_m"] = 0.05
		fk["step_s"] = 0.24
		(spec["rt3d"] as Dictionary).erase("step_weight")
	var n := _fake_npc()
	var live = LiveScript.new()
	n.add_child(live)
	if not live.setup(n, spec, 0.55):
		n.queue_free()
		return -1
	live.face(Vector2(1, 0), 0.55, true)
	for i in 30:
		live.process(DT)
		await process_frame
	live.walk(true, 80.0, 1.0)
	for i in 150:
		n.global_position += Vector2(80.0 * DT, 0.0)
		live.process(DT)
		await process_frame
	live.walk(false)
	var steps := 0
	var stepping := [false, false]
	for i in 120:
		live.process(DT)
		await process_frame
		for k in 2:
			var st: bool = live.view._foot_step[k] != null
			if st and not stepping[k]:
				steps += 1
			stepping[k] = st
	n.queue_free()
	await process_frame
	return steps


func _test_stop_steps() -> void:
	var line := "       "
	for id in ["nina", "pelageya", "ulyana", "tamara", "ilya"]:
		var k := await _stop_run(id, false)
		line += " %s %d" % [id, k]
		_check(k >= 0 and k <= STOP_STEPS_MAX, "%s: %d steps coming to a stop (≤ %d)" % [id, k, STOP_STEPS_MAX])
	var k_old := await _stop_run("nina", true)
	print(line + "  | nina (old) %d" % k_old)
	_check(k_old > STOP_STEPS_MAX, "self-check: Nina with the old data stops in %d steps — the count would not catch the patter" % k_old)
