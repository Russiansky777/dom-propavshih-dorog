extends SceneTree
## Batch J — Director's playthrough 29.10 (Docs/FEEDBACK_DIRECTOR_2026-10-29_map.md), part A (logic):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_j.gd
##   A1 (стр. 47 + ИИ-регрессия 26.10): the H3 door — the knock arrows themselves strike (a real mouse click on the
##      arrow seats the beam); the error says what is wrong: the hinges or the threshold;
##   A2 (ИИ-регрессия 26.10): the office mirror probe's strike point is the wedge in work while the wedges go in;
##   A3 (стр. 60): the lezhanka is clicked on the bench with the blanket, not through the stove;
##   A4 (стр. 117, 184): after dusk Pavel and the gate say the water is down;
##   A5 (стр. 112): once the office is open the bell does not open the mirror's close-up again;
##   A6 (стр. 176): at the end of M23a Nina walks off toward the river, not into her own porch;
##   A8 (стр. 175): Agata answers Ulyana «никто больше не потеряется».
##   A9 (Р11): where the boat is, there is Pelageya — after the knot she rows it to her pier (M16s–M16 there), after the
##      lights back to the plate; the turn and the pier never show the boat without her;
##   B1 (Р13 + Director 29.10 18:30): a new game opens with the intro — three cards on black with the voice-over,
##      a click / Space fades to the next, after the last «День первый»; once (intro_seen in the save); a load stops it;
##   E2 (стр. 130–131): one answering lantern (flashes three times in the close-up, then burns) — in R1 and at the boat (Z3);
##   E1 (Р2): river fog over the far bank in R1 / Z3 / M1 / H4 until the knot (road_held_both_ends); the knot tied
##      with the room on screen — the fog lifts (eases out, then hidden); a load after the knot — no fog at once;
##      at dusk the painted-dusk rooms (R1, Z3) switch to their dusk fog; snow on the far bank only after the knot.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var cp: Node = null
var ui: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
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
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	cp = main_node.get_node("Closeup")
	ui = main_node.get_node("GameUi")
	var player: Node = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _test("J-A1 H3 door: a click on the knock arrow seats the beam; the error names the hinges or the threshold", _test_door)
	await _test("J-A2 office mirror probe: the strike point is the wedge in work while wedges go in", _test_wedge_probe)
	await _test("J-A3 H1: the bench with the blanket is the lezhanka (not the stove); scarf and shelf on it still win", _test_lezhanka)
	await _test("J-A4 M4: after dusk Pavel says the water is down, the gate's status too", _test_water_down)
	await _test("J-A5 H2: once the office is open the bell rings by itself, no mirror close-up", _test_bell_after)
	await _test("J-A6/A8 data: Nina walks to the river at the end of M23a; Agata answers Ulyana", _test_data)
	await _test("J-E1 fog over the far bank until the knot, lifting when the knot is tied", _test_fog)
	await _test("J-A9 Р11: the boat and Pelageya always together (the knot → her pier, the lights → the turn)", _test_boat_with_pelageya)
	await _test("J-B1 intro: three cards on black with the voice-over, a click goes on, then «День первый», once", _test_intro)
	gs.reset()
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch J: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _enter(room: String, spawn: String = "default") -> void:
	rm.change_room(room, spawn)
	await physics_frame
	await physics_frame
	await _frames(3)


func _drain() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_busy()) and guard < 400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if not b.is_empty():
			seen.append(String(b.get("text_key", b.get("text", ""))))
		if sr.mechanic_open or sr.puzzle_open:
			break
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif not b.is_empty():
			sr.advance()
		await process_frame
	return seen


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == id:
			return h
	return null


func _set_flags(flags: Array) -> void:
	for f in flags:
		gs.set_flag(String(f), true)


## Game (1920x1080 canvas) → window coordinates (as test_closeups.gd).
func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(2)


func _button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, true)
	await _button(at, false)


func _drag(from: Vector2, to: Vector2, steps: int = 8) -> void:
	await _move(from)
	await _button(from, true)
	for k in range(1, steps + 1):
		await _move(from.lerp(to, float(k) / steps))
	await _button(to, false)
	await _wait(0.35)


func _v(d: Dictionary) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))


func _probe() -> Dictionary:
	return cp.call("probe_positions")


# --- A1. The H3 door ---------------------------------------------------------------------

func _to_h3() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "seen_school_door", "seen_workshop",
		"seen_bell", "knows_rule_things_remember", "has_school_door", "has_bell", "has_mirror_home", "seen_mirror_home"])
	sr.grant_item("door_hinges")
	await _enter("H3")
	await _wait(0.3)


func _open_door() -> bool:
	var h := _hotspot("school_door")
	if h == null:
		_check(false, "H3 has the school door hotspot")
		return false
	sr.select_item("door_hinges")
	sr.interact(h)
	var g := 0
	while not sr.puzzle_open and g < 600:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g += 1
	await _frames(3)
	_check(sr.puzzle_open, "the hinges on the door open the close-up")
	return sr.puzzle_open


func _test_door() -> void:
	await _to_h3()
	Engine.time_scale = 2.0
	if not await _open_door():
		Engine.time_scale = 1.0
		return
	var p := _probe()
	# Two hinges only, the right notch — the error names the hinges.
	for pair in [["hinge_1", "top"], ["hinge_2", "middle"]]:
		p = _probe()
		await _drag(_v(p["pieces"][pair[0]]), _v(p["slots"][pair[1]]) + Vector2(14, 12))
	sr.puzzle_set_mark(2)
	await _frames(2)
	sr.puzzle_check()
	await _frames(2)
	var msg := String(sr.puzzle.get("message", ""))
	_check(msg == sd.text("@H3.puzzle.error_pieces"), "two hinges: the error says the hinges («%s»)" % msg)
	# Three hinges, the beam near the V notch but not seated: the arrows show; a click ON the arrow knocks it.
	p = _probe()
	await _drag(_v(p["pieces"]["hinge_3"]), _v(p["slots"]["bottom"]) + Vector2(-10, 20))
	sr.puzzle_set_mark(-1)
	await _frames(2)
	p = _probe()
	_check(p["placed"].size() == 3, "three hinges in (%s)" % str(p["placed"]))
	await _drag(_v(p["beam"]), _v(p["beam"]) + Vector2(_v(p["anchor"]).x - _v(p["marks"][2]).x - 26.0, 0), 6)
	await _wait(0.1)
	p = _probe()
	_check(int(p["mark"]) == -1 and int(p["near"]) == 2, "near the V notch, not seated (%s)" % str([p["mark"], p["near"], p["near_off"]]))
	var arrows: Array = cp.get("seat_arrows")
	var taps := 0
	for k in 12:
		p = _probe()
		if int(p["mark"]) == 2 or int(p.get("near", -1)) != 2:
			break
		var off := float(p.get("near_off", 0.0))
		var a: Label = arrows[0 if off < 0.0 else 1]
		_check(a.visible, "the arrow to strike is shown")
		await _click(a.position + a.size * 0.5)
		await _wait(0.15)
		taps += 1
	p = _probe()
	_check(int(p["mark"]) == 2 and taps >= 1 and int(p["seat_taps"]) >= taps, "clicks on the arrow knocked the V notch in: mark=%d after %d clicks" % [int(p["mark"]), taps])
	# The wrong notch with all three hinges — the error names the threshold.
	sr.puzzle_set_mark(1)
	await _frames(2)
	sr.puzzle_check()
	await _frames(2)
	msg = String(sr.puzzle.get("message", ""))
	_check(msg == sd.text("@H3.puzzle.error_mark"), "wrong notch: the error says the threshold («%s»)" % msg)
	sr.close_puzzle()
	await _drain()
	Engine.time_scale = 1.0


# --- A2. The wedges' strike point ----------------------------------------------------------

func _test_wedge_probe() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "done_M05", "done_N01", "done_M09", "done_M09s",
		"done_M09b", "met_pavel", "seen_office_door", "seen_office_photo", "seen_shift_schedule", "pavel_agreed_signals",
		"office_mirror_mounted", "has_mirror_mill", "bell_clapper_hung", "has_bell_clapper"])
	await _enter("H2")
	await _drain()
	var h := _hotspot("stand_zm")
	_check(h != null, "H2 has the stand")
	if h == null:
		return
	sr.interact(h)
	var g := 0
	while not sr.mechanic_open and g < 400:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g += 1
	_check(sr.mechanic_open, "the stand with the mirror opens the close-up")
	await _frames(3)
	var mv: Node = main_node.get_node_or_null("MechanicView")
	var pr: Dictionary = mv.call("probe").get("panel", {}) if mv != null else {}
	var ws: Dictionary = pr.get("wedge_strike", {})
	var st: Dictionary = pr.get("strike", {})
	_check(not ws.is_empty() and _v(st).distance_to(_v(ws)) < 1.0, "while the wedges go in, the bots' strike point is the wedge (%s vs bell %s)" % [str(st), str(pr.get("bell"))])
	sr.close_mechanic()
	await _drain()


# --- A3. The lezhanka ------------------------------------------------------------------------

func _test_lezhanka() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "stove_lit", "h1_scarf_removed", "met_tikhon", "done_Q04", "q04_corner_stove"])
	await _enter("H1")
	await _drain()
	var room: Node = rm.current_room
	var bench_pt := Vector2(470, 640)   # the left part of the bench, in front of the stove (was the stove's)
	var hit: Node = room.call("pick", bench_pt)
	_check(hit != null and String(hit.get("hotspot_id")) == "lezhanka", "the bench with the blanket is the lezhanka, got %s" % (String(hit.get("hotspot_id")) if hit != null else "none"))
	var stove_pt := Vector2(220, 480)   # the stove's mouth
	hit = room.call("pick", stove_pt)
	_check(hit != null and String(hit.get("hotspot_id")) == "stove", "the stove's mouth is still the stove, got %s" % (String(hit.get("hotspot_id")) if hit != null else "none"))
	# With the scarf on the bench (before it is taken) the scarf wins over the lezhanka.
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "house_open"])
	await _enter("H1")
	await _drain()
	hit = rm.current_room.call("pick", Vector2(640, 600))
	_check(hit != null and String(hit.get("hotspot_id")) == "scarf", "the scarf on the bench wins, got %s" % (String(hit.get("hotspot_id")) if hit != null else "none"))


# --- A4. The water is down ------------------------------------------------------------------

func _test_water_down() -> void:
	var talk: Array = []
	for h in sd.room("M4").get("hotspots", []):
		if String(h.get("id", "")) == "pavel":
			talk = h.get("talk", {}).get("by_flags", [])
	var keys: Array = talk.map(func(e): return String(e.get("text", "")))
	var i_dusk := keys.find("@M4.pavel.after_dusk")
	var i_open := keys.find("@M4.pavel.after")
	_check(i_dusk >= 0 and i_open > i_dusk, "Pavel: after dusk the «water is down» line comes before «теперь ждать надо» (%s)" % str(keys))
	_check(not sd.text("@M4.pavel.after_dusk").contains("ждать"), "the after-dusk line does not say «ждать»")
	var texts: Dictionary = {}
	for h in sd.room("M4").get("hotspots", []):
		if h.has("mechanic"):
			texts = h["mechanic"].get("texts", {})
	_check(texts.get("label_status_drained", "") == "@M4.sluice.label_status_drained" and not sd.text("@M4.sluice.label_status_drained").contains("к вечеру"),
		"the gate's status after dusk does not promise «к вечеру сойдёт»")


# --- A5. The bell after the office ------------------------------------------------------------

func _test_bell_after() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "done_M05", "seen_bell", "knows_rule_things_remember",
		"bell_clapper_hung", "office_mirror_mounted", "office_mirror_clamped", "lantern_check_seen", "office_unbolted", "done_M10", "done_M11", "done_M12"])
	await _enter("H2")
	await _drain()
	var h := _hotspot("bell")
	_check(h != null, "H2 has the bell")
	if h == null:
		return
	sr.interact(h)
	await _frames(4)
	_check(not sr.mechanic_open, "the bell does not open the mirror's close-up any more")
	var seen := await _drain()
	_check(seen.has("H2d.bell.after_office"), "the bell's own line (%s)" % str(seen))
	# Before the office is open, the bell still opens the same close-up as the stand.
	gs.set_flag("office_unbolted", false)
	sr.interact(h)
	var g := 0
	while not sr.mechanic_open and g < 200:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g += 1
	_check(sr.mechanic_open, "before the office is open the bell opens the close-up as before")
	sr.close_mechanic()
	await _drain()


# --- A6, A8. Data ------------------------------------------------------------------------------

func _test_data() -> void:
	var m23a: Dictionary = sd.scene("M23a")
	var end_go: Array = []
	for st in m23a.get("stage", []):
		if str(st.get("at", "")) == "end":
			end_go = st.get("npc_go", [])
	_check(end_go.size() == 1 and String(end_go[0].get("id", "")) == "nina", "M23a ends with Nina walking off (%s)" % str(end_go))
	if end_go.size() == 1:
		var to := Vector2(float(end_go[0]["to"][0]), float(end_go[0]["to"][1]))
		var porch := Vector2(1355, 655)   # her porch in O4 (rooms/O4.json nina rect)
		var river_exit := Vector2(725, 560)   # the exit toward the far support (R3)
		_check(to.distance_to(river_exit) < to.distance_to(porch), "…toward the river, not to her porch (%s)" % str(to))
	var then: Array = []
	for h in sd.room("O1").get("hotspots", []):
		for o in h.get("choice", {}).get("options", []) if h.has("choice") else []:
			if String(o.get("id", "")) == "lights":
				then = o.get("then", [])
		for o in h.get("talk", {}).get("options", []) if h.has("talk") else []:
			if String(o.get("id", "")) == "lights":
				then = o.get("then", [])
	_check(then.size() >= 3 and String(then[-1]) == "@O1d.ulyana.lights_c", "Ulyana's question gets Agata's answer (%s)" % str(then))
	var ln: Dictionary = sd.text_line("@O1d.ulyana.lights_c")
	_check(String(ln.get("speaker", "")) == "agata" and String(ln.get("text", "")).contains("Обещаю"), "Agata: «…Обещаю» (%s)" % str(ln))


func _fog_root() -> Node:
	return rm.current_room.get_node_or_null("Ambient") if rm.current_room != null else null


func _test_fog() -> void:
	gs.reset()
	for rid in ["R1", "Z3", "M1", "H4"]:
		await _enter(rid)
		var amb := _fog_root()
		_check(amb != null and amb.fog.size() >= 1, "%s: fog regions built (%s)" % [rid, str(amb.stats() if amb != null else {})])
		if amb == null:
			continue
		var showing: Array = amb.fog_showing()
		_check(not showing.is_empty() and not String(showing[0]).ends_with("_dusk"), "%s: day fog on before the knot (%s)" % [rid, str(showing)])
		for n in amb.fog:
			_check(n.z_index >= 0 and n.z_index < 100, "%s/%s: fog z %d — over the layers, under the figures" % [rid, n.name, n.z_index])
	# Dusk of day two in the painted-dusk rooms: their own dusk fog instead of the day one.
	gs.reset()
	_set_flags(["evening_dusk"])
	await _enter("Z3")
	var z3 := _fog_root()
	if z3 != null:
		var sh: Array = z3.fog_showing()
		_check(sh.size() == 1 and String(sh[0]) == "fog_far_dusk", "Z3 at dusk: only the dusk fog (%s)" % str(sh))
		# The knot tied here, on screen: the fog lifts — still drawn a moment, rising and thinning, then gone.
		gs.set_flag("road_held_both_ends", true)
		await _frames(3)
		var n: Polygon2D = z3.fog[1] if z3.fog.size() > 1 else null
		var lift0 := float((n.material as ShaderMaterial).get_shader_parameter("lift")) if n != null else -1.0
		_check(n != null and n.visible and lift0 < 0.5, "Z3: right after the knot the fog is still there, lifting (lift %.2f)" % lift0)
		await _wait(2.5)
		var lift1 := float((n.material as ShaderMaterial).get_shader_parameter("lift")) if n != null else -1.0
		_check(lift1 > lift0 and lift1 < 1.0, "Z3: the fog rises and thins over its fade (lift %.2f → %.2f)" % [lift0, lift1])
		await _wait(6.5)
		_check(z3.fog_showing().is_empty(), "Z3: after the fade no fog (%s)" % str(z3.fog_showing()))
		var snow: Node = rm.current_room.get_node_or_null("Effects/far_snowfall")
		_check(snow != null and snow.visible, "Z3: after the knot snow falls on the far bank")
	# A save after the knot: no fog at once in any room, snow on the far bank.
	gs.reset()
	_set_flags(["evening_dusk", "road_held_both_ends"])
	for rid in ["R1", "M1", "H4"]:
		await _enter(rid)
		var amb := _fog_root()
		if amb != null:
			_check(amb.fog_showing().is_empty(), "%s after the knot: no fog (%s)" % [rid, str(amb.fog_showing())])
		var sn: Node = rm.current_room.get_node_or_null("Effects/far_snowfall")
		if sn == null:
			sn = rm.current_room.get_node_or_null("Effects/far_snowfall_left")
		_check(sn != null and sn.visible, "%s after the knot: snow falls on the far bank" % rid)
	# стр. 130–131: the far bank answered — one lantern, steady, at the pier (R1) and back at the boat (Z3).
	_set_flags(["far_lights_answered"])
	for rid in ["R1", "Z3"]:
		await _enter(rid)
		var fl: Node = rm.current_room.get_node_or_null("Effects/far_light")
		_check(fl != null and fl.visible, "%s after the lights: the answering lantern burns on the far bank" % rid)
		_check(rm.current_room.get_node_or_null("Layers/far_lights") == null, "%s: no three painted lights any more" % rid)
	gs.reset()


func _test_intro() -> void:
	var intro: Node = ui.get("intro_card")
	var card: Node = ui.get("day_card")
	_check(intro != null and card != null, "GameUi has the intro and the day cards")
	if intro == null or card == null:
		return
	var keys: Array = MenuConfig.section("intro").get("keys", [])
	_check(keys.size() >= 2 and keys.size() <= 3, "2–3 intro cards (Director 18:30): %s" % str(keys))
	for k in keys:
		_check(sd.text(String(k)) != String(k) and not sd.text(String(k)).is_empty(), "intro text %s exists" % k)
		_check(root.get_node("VoiceDirector").is_narration_key(String(k).trim_prefix("@")), "intro card %s is voiced by the narrator" % k)
	rm.new_game()
	sr.play_first_day_card()
	await _frames(3)
	var p: Dictionary = intro.probe()
	_check(String(p["phase"]) != "" and int(p["index"]) == 0 and float(p["black"]) > 0.99, "the intro starts on black with the first card (%s)" % str(p))
	_check(String(card.probe()["phase"]) == "", "«День первый» waits for the intro")
	_check(gs.has_flag("intro_seen"), "intro_seen in the save")
	await _wait(1.6)
	_check(float(intro.probe()["alpha"]) > 0.9, "the first card faded in (alpha %.2f)" % float(intro.probe()["alpha"]))
	# A click: the card fades out at once, the next fades in.
	await _click(Vector2(960, 540))
	await _wait(1.2)
	p = intro.probe()
	_check(int(p["index"]) == 1 and int(p["skipped"]) >= 1, "a click goes on to the second card (%s)" % str(p))
	# Space: the same.
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(1.2)
	_check(int(intro.probe()["index"]) == keys.size() - 1, "Space goes on to the last card (%s)" % str(intro.probe()))
	# The last card left to its own timing: it holds (voice or reading time), then «День первый» over black.
	var t0 := Time.get_ticks_msec()
	while String(intro.probe()["phase"]) != "" and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	_check(String(intro.probe()["phase"]) == "" and (intro.probe()["shown"] as Array).size() >= keys.size(), "the last card goes by itself (%s)" % str(intro.probe()))
	await _frames(2)
	var dp: Dictionary = card.probe()
	_check(String(dp["key"]) == "@ui.day_card_1" and String(dp["phase"]) != "" and float(dp["black"]) > 0.9, "then «День первый» on black (%s)" % str(dp))
	# Once: the next call goes straight to the day card's «once» rule; a load stops a running intro.
	var n := (intro.probe()["shown"] as Array).size()
	sr.play_first_day_card()
	await _frames(2)
	_check((intro.probe()["shown"] as Array).size() == n, "the intro only once per game")
	gs.reset()
	rm.new_game()
	sr.play_first_day_card()
	await _frames(2)
	_check(String(intro.probe()["phase"]) != "", "a new game: the intro again")
	gs.state_loaded.emit("test")
	await _frames(2)
	_check(String(intro.probe()["phase"]) == "" and float(intro.probe()["black"]) == 0.0, "a load stops the intro")
	gs.reset()


func _layer_vis(id: String) -> bool:
	var n: Node = rm.current_room.get_node_or_null("Layers/" + id)
	return n != null and (n as CanvasItem).visible


func _pel_vis() -> bool:
	var h := _hotspot("pelageya")
	return h != null and h.visible


func _test_boat_with_pelageya() -> void:
	var ends := {}
	for sid in ["M15", "M16"]:
		for st in sd.scene(sid).get("stage", []):
			if str(st.get("at", "")) == "end":
				ends[sid] = st.get("sets", [])
	_check((ends.get("M15", []) as Array).has("boat_to_pier"), "M15 ends rowing the boat to the pier (%s)" % str(ends))
	_check((ends.get("M16", []) as Array).has("boat_back_at_turn"), "M16 ends rowing it back to the plate (%s)" % str(ends))
	# The knot tied: the boat and Pelageya at her pier, none at the turn.
	gs.reset()
	_set_flags(["evening_dusk", "rope_brought", "done_M15s", "done_M15", "rope_on_ring", "road_held_both_ends", "boat_to_pier"])
	await _enter("Z3")
	_check(not _layer_vis("boat_dusk") and not _pel_vis(), "after the knot, at the turn: neither the boat nor Pelageya")
	await _enter("R1")
	_check(not _layer_vis("no_boat_dusk") and _pel_vis(), "after the knot, at the pier: the boat (no «empty» patch) and Pelageya")
	# The lights answered: both back at the plate.
	_set_flags(["done_M16s", "far_snow_seen", "far_lights_answered", "boat_back_at_turn", "done_M16"])
	await _enter("R1")
	_check(_layer_vis("no_boat_dusk") and not _pel_vis(), "after the lights, at the pier: neither")
	await _enter("Z3")
	_check(_layer_vis("boat_dusk") and _pel_vis(), "after the lights, at the turn: the boat and Pelageya")
	gs.reset()
