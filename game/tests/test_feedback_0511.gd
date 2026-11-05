extends SceneTree
## Director's notes 05.11, block 1 (Docs/CURRENT_STATE.md 05.11; DECISIONS 05.11):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0511.gd
##   1 «Облегчить» on the bell and hook stage of the office mirror's close-up (the wedges' bar had its own, the bell's
##     stage none); toggling it eases Pavel's hook at once; self-check — while the wedges go in it stays hidden;
##   2 the bell's clapper (язык колокола) used from the bag inside the close-up — no need to leave it; 2b: the language
##     changed inside a close-up — the same close-up opens again over the reloaded room;
##   3 «Пойдём к затвору» (M13): Pavel walks to the office door, it swings open, he goes and it shuts;
##   4 O3 by Nina: no walking on the spot — the walk that stalled at Nina's feet ends; self-check — without the guard
##     the same walk steps in place.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var player: Node = null
var PS = null


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
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	PS = load("res://scripts/actors/player.gd")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("0511-1 «Облегчить» on the bell and hook stage; eases Pavel at once; hidden while the wedges go in", _test_easy)
	await _test("0511-2 the bell's clapper from the bag goes on inside the close-up; self-check — a bare click leaves it mute", _test_clapper_closeup)
	await _test("0511-2b the language changed inside the close-up — the same close-up opens again", _test_lang_closeup)
	await _test("0511-3 «Пойдём к затвору»: Pavel walks to the office door, it opens and shuts", _test_pavel_door)
	await _test("0511-4 O3 by Nina: no walking on the spot; self-check — without the guard she steps in place", _test_o3_stall)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== feedback 05.11, block 1: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room: String, spawn: String = "default") -> void:
	rm.change_room(room, spawn)
	await physics_frame
	await physics_frame
	await _frames(3)


func _set_flags(flags: Array) -> void:
	for f in flags:
		gs.set_flag(String(f), true)


func _fresh(flags: Array = []) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(flags)


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running") or sr.call("is_staging")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


## Clicks a hotspot as the mouse does (walk there, then use) — with `item` in hand when given.
func _use(id: String, item: String = "") -> bool:
	var h: Node2D = rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null
	if h == null or not h.visible:
		return false
	if item != "":
		sr.select_item(item)
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


## Reads out every queued beat (first option for choices); returns the texts seen.
func _finish() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 2000:
		guard += 1
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")) if not opts.is_empty() else "")
		else:
			seen.append(String(b.get("text", "")))
			sr.advance()
		await process_frame
	await process_frame
	return seen


func _text(key: String) -> String:
	return String(sd.text(key))


func _hotspot(room_id: String, id: String) -> Dictionary:
	for h in sd.rooms.get(room_id, {}).get("hotspots", []):
		if String(h.get("id", "")) == id:
			return h
	return {}


func _scene_line(id: String, i: int) -> Dictionary:
	return sd.scene(id).get("mandatory_lines", [])[i]


## Top edge (first opaque row) of a picture's column, -1 when the column is empty.
func _top_at(img: Image, x: int) -> int:
	for y in img.get_height():
		if img.get_pixel(x, y).a > 0.5:
			return y
	return -1


func _flags_before(upto: String) -> void:
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for st in sc.get("stage", []):
			for f in st.get("sets", []):
				gs.set_flag(String(f), true)





func _wait_until(cond: Callable, limit: int = 900) -> bool:
	var g := 0
	while not cond.call() and g < limit:
		g += 1
		await process_frame
	return cond.call()


func _panel() -> Node:
	return main_node.find_child("MechanicView", true, false)


func _mech_probe() -> Dictionary:
	var mv := _panel()
	if mv == null:
		return {}
	var p = mv.call("probe") if mv.has_method("probe") else {}
	return p.get("panel", p) if p is Dictionary else {}


func _open_stand(clamped: bool) -> void:
	_fresh(["done_M01", "done_M02", "done_M03", "house_open", "house_unlocked", "done_N01", "done_M09", "done_M09s", "done_M09b",
		"office_mirror_mounted", "has_mirror_mill", "bell_clapper_hung", "pavel_agreed_signals"] + (["office_mirror_clamped", "lantern_check_seen"] if clamped else []))
	await _enter("H2")
	var h: Node = rm.current_room.get_node_or_null("Hotspots/stand_zm")
	sr.open_mechanic(sr.mechanic_spec(h), "stand_zm")
	await _frames(6)


func _test_easy() -> void:
	var TB = load("res://scripts/mechanics/timing_bar.gd")
	TB.settings_path = "user://test_0511_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TB.settings_path))
	TB.load_settings(true) if TB.has_method("load_settings") else null
	TB.set_slow(false)
	# self-check first: the wedges still to go in — their bar (with its own check) is up, ours hidden
	await _open_stand(false)
	var panel: Node = main_node.find_child("OfficeMirrorPanel", true, false)
	if panel == null:
		for n in main_node.find_children("*", "", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("office_mirror_panel.gd"):
				panel = n
				break
	_check(panel != null, "the office mirror close-up is open")
	if panel == null:
		sr.close_mechanic()
		return
	var p: Dictionary = panel.call("probe")
	_check(not bool(p.get("easy", {}).get("visible", true)) and not (p.get("wedge_timing", {}) as Dictionary).is_empty(),
		"self-check: while the wedges go in the bar is up and the bell's check hidden: %s" % str(p.get("easy")))
	sr.close_mechanic()
	await _frames(3)
	await _open_stand(true)
	panel = null
	for n in main_node.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("office_mirror_panel.gd"):
			panel = n
			break
	p = panel.call("probe")
	_check(bool(p.get("easy", {}).get("visible", false)) and not bool(p.get("easy", {}).get("pressed", true)),
		"the clamped frame: «Облегчить» on the close-up, off: %s" % str(p.get("easy")))
	var sp0 := float(p.get("hook", {}).get("speed", 0.0))
	var cb: CheckButton = panel.get("easy_check")
	cb.button_pressed = true   # as a click: toggled → TimingBar.set_slow + eased()
	await _frames(2)
	var p1: Dictionary = panel.call("probe")
	var sp1 := float(p1.get("hook", {}).get("speed", 0.0))
	_check(TB.slow and sp1 < sp0 * 0.95 and float(p1.get("hook", {}).get("reach", 0.0)) >= float(p.get("hook", {}).get("reach", 0.0)),
		"toggled mid-game: Pavel slower (%.3f → %.3f), the jerk no shorter, the setting on (%s)" % [sp0, sp1, str(TB.slow)])
	cb.button_pressed = false
	sr.close_mechanic()
	await _frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TB.settings_path))


func _test_lang_closeup() -> void:
	await _open_stand(true)
	_check(sr.mechanic_open and String(sr.mechanic.get("hotspot", "")) == "stand_zm", "the close-up open")
	main_node.call("_prepare_language_switch", true)
	_check(String(main_node.get("_reopen_mechanic")) == "stand_zm", "the close-up to reopen is remembered: «%s»" % main_node.get("_reopen_mechanic"))
	# the reload: a fresh state (as reload_current_scene + the slot load), then the resume
	sr.close_mechanic()
	gs.reset()
	sr.call("_on_state_reset")
	await _frames(3)
	main_node.call("_resume_after_language")
	await _frames(8)
	_check(sr.mechanic_open and String(sr.mechanic.get("hotspot", "")) == "stand_zm" and rm.current_room != null and String(rm.current_room.room_id) == "H2",
		"after the switch: H2, the same close-up open again (%s, %s)" % [str(sr.mechanic_open), str(sr.mechanic.get("hotspot", ""))])
	_check(gs.has_flag("office_mirror_clamped"), "the game's state came back with it")
	sr.close_mechanic()
	var pm = main_node.get("pause_menu")
	if pm != null and pm.has_method("close"):
		pm.call("close")
	root.get_tree().paused = false
	await _frames(3)


func _test_pavel_door() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_flags_before("M13")
	gs.set_flag("visited_M3", true)
	await _enter("M3", "from_M2")
	var pv := rm.current_room.get_node_or_null("npc_pavel") as Node2D
	_check(pv != null and pv.visible, "Pavel in the office")
	if pv == null:
		return
	var p0 := pv.global_position
	sr.start_scene("M13")
	var got_door := await _wait_until(func():
		if not sr.current_beat.is_empty() and not sr.is_staging():
			if sr.current_beat.get("type") == "options":
				sr.choose(String(sr.current_beat["options"][0]["id"]))
			else:
				sr.advance()
		return rm.current_room.get_node_or_null("StageDoor") != null, 3000)
	_check(got_door, "the office door swings open as Pavel walks up")
	if got_door:
		await create_timer(1.1).timeout
		var door: Node = rm.current_room.get_node_or_null("StageDoor")
		if door != null:
			var leaf: Sprite2D = door.get_child(1)
			var full := 1920.0 / float((leaf.texture as AtlasTexture).atlas.get_width())
			_check(leaf.scale.x < full * 0.8, "the leaf has turned on its hinge (scale %.2f of %.2f)" % [leaf.scale.x, full])
		_check(is_instance_valid(pv) and pv.global_position.distance_to(p0) > 150.0, "Pavel walks toward the door (%s → %s)" % [str(p0.round()), str(pv.global_position.round())])
	await _wait_until(func(): return sr.current_beat.is_empty() and not sr.is_staging(), 1200)
	await _frames(10)
	_check(gs.has_flag("done_M13") and String(rm.current_room.room_id) == "M3", "M13 done, Agata still in the office")
	_check(not is_instance_valid(pv) or not pv.visible or pv.modulate.a < 0.05, "Pavel gone through the door")
	_check(rm.current_room.get_node_or_null("StageDoor") == null or not (rm.current_room.get_node("StageDoor") as CanvasItem).visible, "the door shut again (no leaf left open)")


## A walk from the corner pocket by Nina's feet (where the probe found the 11 s walking on the spot) to the far left;
## `pin` — the floor holds the body for 1.5 s after she sets off (the stall itself, made certain: where exactly the
## navigation mesh's pocket catches her depends on the last frames of the walk before).
func _o3_walk(guard_s: float, pin: bool) -> Dictionary:
	player.set("stall_guard_s", guard_s)
	player.walk_to(Vector2(1640, 900))
	await _wait_until(func(): return not player.call("is_walking"), 900)
	player.walk_to(Vector2(1510, 770))
	await _wait_until(func(): return not player.call("is_walking"), 900)
	player.global_position = Vector2(1489, 785)
	await _frames(20)
	var stops0 := int(player.get("stall_stops"))
	player.walk_to(Vector2(210, 840))
	var t := 0.0
	var stall := 0.0
	var worst := 0.0
	var last: Vector2 = player.global_position
	var held: Vector2 = Vector2.INF
	while t < 8.0:
		await process_frame
		var d := player.get_process_delta_time()
		t += d
		if pin and t > 0.6 and t < 2.1:
			if held == Vector2.INF:
				held = player.global_position
			player.global_position = held
		var v: float = player.global_position.distance_to(last) / maxf(d, 0.001) / maxf(absf(player.scale.y), 0.05)
		last = player.global_position
		if not player.call("is_walking"):
			break
		if float(player.get("walk_w")) > 0.5 and v < 25.0:
			stall += d
			worst = maxf(worst, stall)
		else:
			stall = 0.0
	var out := {"pos": player.global_position.round(), "worst": snappedf(worst, 0.01), "t": snappedf(t, 0.01), "walking": player.call("is_walking"), "stops": int(player.get("stall_stops")) - stops0}
	if player.call("is_walking"):
		player.call("_cancel_walk")
	await _frames(10)
	return out


func _test_o3_stall() -> void:
	# the live figure from the start, as in the game and the probe (a switch mid-run keeps the sheets' bookkeeping)
	PS.forced_render = "3d"
	root.remove_child(main_node)
	main_node.free()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(4)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	_fresh(["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "met_tikhon"])
	rm.change_room("O3", "default", Vector2(-1, -1))
	await _frames(30)
	_check(player.call("is_3d"), "the live figure (3D)")
	var nina := rm.current_room.get_node_or_null("npc_nina") as Node2D
	_check(nina != null and nina.visible, "Nina in her room (her feet — the obstruction the walk stalled at)")
	var off := await _o3_walk(INF, true)
	var on := await _o3_walk(0.5, true)
	var free := await _o3_walk(0.5, false)
	_check(float(off["worst"]) >= 1.0, "self-check: without the guard, held by the floor, the legs walk on the spot (%s)" % str(off))
	_check(float(on["worst"]) < 0.6 and int(on["stops"]) >= 1, "with the guard: held by the floor, the walk ends within 0.6 s (%s)" % str(on))
	_check(float(free["worst"]) < 0.6 and not bool(free["walking"]) and int(free["stops"]) <= 1, "the real walk from the pocket round Nina: no stepping on the spot (%s)" % str(free))
	player.set("stall_guard_s", 0.5)
	PS.forced_render = ""


func _omp() -> Node:
	for n in main_node.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("office_mirror_panel.gd"):
			return n
	return null


func _test_clapper_closeup() -> void:
	_fresh(["done_M01", "done_M02", "done_M03", "house_open", "house_unlocked", "done_N01", "done_M09", "done_M09s", "done_M09b",
		"office_mirror_mounted", "has_mirror_mill", "pavel_agreed_signals", "office_mirror_clamped", "has_bell_clapper"])
	gs.add_item("bell_clapper")
	await _enter("H2")
	var h: Node = rm.current_room.get_node_or_null("Hotspots/stand_zm")
	sr.open_mechanic(sr.mechanic_spec(h), "stand_zm")
	await _frames(6)
	var panel := _omp()
	_check(panel != null, "the bell's close-up is open")
	if panel == null:
		return
	# self-check: a bare click — the bell is mute, nothing changes
	panel.call("bell_press")
	panel.call("bell_release")
	await _frames(2)
	_check(not gs.has_flag("bell_clapper_hung") and gs.has_item("bell_clapper"), "self-check: a bare click — still mute, the clapper in the bag")
	await _finish()
	# the clapper from the bag onto the bell, the close-up open — with the mouse: the pocket in the top bar, then the bell
	var bag: Node = null
	for n in main_node.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("inventory_bag.gd"):
			bag = n
			break
	var at: Dictionary = (bag.call("probe") as Dictionary).get("items", {}).get("bell_clapper", {}) if bag != null else {}
	_check(not at.is_empty(), "the clapper's pocket in the bag over the close-up")
	if not at.is_empty():
		await _mouse_click(Vector2(float(at["x"]), float(at["y"])))
	_check(sr.selected_item == "bell_clapper", "a click on the pocket takes the clapper in hand over the close-up (%s)" % sr.selected_item)
	var bc: Dictionary = (panel.call("probe") as Dictionary).get("bell", {})
	await _mouse_click(Vector2(float(bc.get("x", 0)), float(bc.get("y", 0))))
	await _frames(3)
	var seen := await _finish()
	_check(gs.has_flag("bell_clapper_hung") and not gs.has_item("bell_clapper") and sr.selected_item == "", "the clapper hung from the close-up, out of the bag (%s)" % str(gs.inventory))
	_check(sr.mechanic_open, "the close-up stays open")
	var cl: Control = panel.get("bell_clapper")
	_check(cl != null and cl.visible, "the clapper shows in the bell's mouth at once")
	_check(seen.any(func(x): return String(x) == _text("@H2d.bell.hang")), "the same words as in the room (@H2d.bell.hang): %s" % str(seen))
	sr.close_mechanic()
	await _frames(3)


func _mouse_click(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await _frames(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		root.push_input(ev, true)
		await _frames(2)
