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
	_report("Every villager with rt3d: live model loaded (120k-ish triangles, Meshy rig, idle/listen/talk/walk), facade invisible", t0)
	t0 = Time.get_ticks_msec()
	await _test_states()
	_report("Talk / listen fade in and out over the stance; turning to Agata is smooth at any angle; walking off plays the cycle", t0)
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
	var tries := [["R1", ["done_M01"]], ["M3", ["done_M01", "done_M02", "house_unlocked", "done_M03", "done_N01", "done_M09", "done_M09s"]],
		["O3", ["done_M01", "done_M02", "done_M03"]], ["Z1", ["done_M01"]]]
	for t in tries:
		gs.reset()
		for f in t[1]:
			gs.set_flag(f, true)
		rm.change_room(t[0], "default")
		await _frames(8)
		for n in rm.current_room.get_children():
			if n.get("live") != null:
				return n
	return null


func _test_models() -> void:
	var ids := ["nina", "pavel", "mitya", "pelageya", "ilya", "ilya_wife", "ulyana"]
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
			_check(tris > 80000 and tris < 160000, "%s: %d triangles (expected ≈120k)" % [id, tris])
			for role in ["idle", "listen", "talk"]:
				_check(v.clips.has(role), "%s: clip %s missing" % [id, role])
			if v.clips.has("walk"):
				_check(v.stride_m > 0.5 and v.stride_m < 3.5, "%s: ground covered by one walk clip %.2f m (Ilya's clip has two cycles)" % [id, v.stride_m])
		v.queue_free()
		await _frames(1)


func _test_states() -> void:
	var n: Node = await _find_live()
	_check(n != null, "no villager drawn live in R1 / M3 / O3 / Z1")
	if n == null:
		return
	var live = n.live
	_check(n.sprite.material != null, "%s: facade not hidden" % n.actor_id)
	_check(live.body != null and live.body.get_parent() == n.sprite, "%s: live figure is not under the facade sprite" % n.actor_id)
	n.set_state("talk")
	await _wait_s(0.6)
	_check(live.act_name == "talk" and live.act_w > 0.95, "%s talking: talk weight %.2f (%s)" % [n.actor_id, live.act_w, live.act_name])
	var t1: float = live.act_t
	await _wait_s(0.3)
	_check(absf(live.act_t - t1) > 0.05, "%s talking: the clip runs (%.2f → %.2f)" % [n.actor_id, t1, live.act_t])
	n.set_state("idle")
	await _wait_s(0.6)
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
