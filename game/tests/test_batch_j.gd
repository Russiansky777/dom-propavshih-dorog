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
##   A10 (Р5 + Director 18:51): the tar pot on Dunya's workbench — before Pavel's request «not now», then once into the bag;
##      the lever alone does not open the sluice, the tar on the winch does (the walk itself — test_day2.gd);
##   E3 (стр. 199, 202): the last frame — the candle burns on its wick (a live flame), snow falls behind the window panes,
##      Nina's cup larger and on the table, Tikhon turned to the people;
##   B1 (Р13 + Director 29.10 18:30): a new game opens with the intro — three cards on black with the voice-over,
##      a click / Space fades to the next, after the last «День первый»; once (intro_seen in the save); a load stops it;
##   E2 (стр. 130–131): one answering lantern (flashes three times in the close-up, then burns) — in R1 and at the boat (Z3);
##   D2 (стр. 139, 140, 143): M18 — turned to each other at once, apart after the hug, Mitya walks up the path;
##   D1 (стр. 89, 157): Agata looks at a person's feet (not over their head — her back was to the screen); they turn to her;
##   E10 (стр. 57): the drizzle at night in the lane by the post (light route) not darkened with the ambient layer;
##   G1 (стр. 120, 191, 192): «Раз!», «Два!» at the brace; zones by mode; the log's red band;
##   F1 (стр. 6, 7): the save's real date and time; «Удалить» with the game's yes / no dialog;
##   E9 (стр. 15, 96, 144): the flume by the sluice state, Z3 lapping at the bank, R3 ripple under the stones;
##   E8 (стр. 77, 79, 109): the office mirror's frame fades into the dark like the bell; mother's mirror carved, no handle;
##   E7 (стр. 72): a lit window is covered by a figure in front of it (its light no longer on her), dimmer at the curtains;
##   E6 (a real-game frame): R1 at dusk with the rope off the stopper — no white streak over the dark far bank;
##   E5 (стр. 95, 46): the H1 mug as big as the chosen cup (the painted clay mug under it gone); the H4 bed larger;
##   E4 (стр. 9): the Z1 counter lower (same width, ×0.84 from the front legs); Tamara clicked through it too;
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
	await _test("J-A10 Р5: the tar — «not now» before Pavel asks, then once; the tar on the winch opens the sluice", _test_tar)
	await _test("J-E3 the last frame: the candle burns, snow behind the window, the cup on the table, Tikhon to the people", _test_last_frame)
	await _test("J-B1 intro: three cards on black with the voice-over, a click goes on, then «День первый», once", _test_intro)
	await _test("J-E4 Z1 (стр. 9): the counter lower (×0.84, legs in place); Tamara is clicked through the counter too", _test_counter)
	await _test("J-E5 sizes: the H1 mug as big as the chosen cup (стр. 95), no clay mug under it; the H4 bed larger (стр. 46)", _test_sizes)
	await _test("J-E6 R1 dusk, the rope off the stopper: before the knot the patch is the dark bank's, after it the snowy one's", _test_rope_patch)
	await _test("J-E7 lit windows (стр. 72): a figure in front covers the light, it comes back behind her; dimmer at the curtains", _test_windows)
	await _test("J-E9 water (стр. 15, 96, 144): the flume holds, then rushes once the sluice is open; Z3's near water laps at the bank; R3 ripples under the stones", _test_water)
	await _test("J-F1 saves (стр. 6, 7): the real date and time on a slot; «Удалить» asks in the game's dialog, the red cross keeps, the green tick deletes", _test_save_delete)
	await _test("J-G1 mini-games (стр. 120, 191, 192): «Раз!», «Два!» at the brace; normal zones narrower, «Облегчить» a little wider; the log's red band bigger", _test_minigames)
	await _test("J-E10 the drizzle at night in the lane by the post (стр. 57): not darkened with the «living world» layer", _test_rain_night)
	await _test("J-D1 talking (стр. 89, 157): Agata looks at a person's feet, not above them (no more back to the screen); the person turns to her", _test_facing)
	await _test("J-D2 M18 at the far pier (стр. 139, 140, 143): mother and son turn to each other at once, step apart after the hug, Mitya walks up the path", _test_m18_staging)
	await _test("J-E8 mirror close-ups (стр. 77, 79, 109): the office mirror's frame fades into the dark like the bell; mother's mirror in a carved frame, no grey handle", _test_mirror_frames)
	await _test("J-F2 the mill's schedule (стр. 80): the words stay on the sheet; the whole close-up in the carved frame, «Закрыть» below it", _test_schedule)
	await _test("J-D4 the empty boat (стр. 133): its bow rides on the painted rope to the far bank and melts only near its end", _test_boat_rope)
	await _test("J-D5 the crossing (стр. 137): the rope runs through the iron eye (the iron alone stays); at the shore the boat's view goes to black and the far pier comes out of it — never the boat again", _test_crossing_black)
	await _test("J-G2 crosses and noughts with Ulyana: from her choice in class; chalk grid and marks by hand; she plays well, not perfectly; a game ends in a word and «Ещё раз» / «Хватит»", _test_ttt)
	await _test("J-G3 the spoons with Tikhon: from his questions; he taps, Agata answers in the same rhythm; a miss — the same round again; «Хватит» puts it away", _test_rhythm)
	await _test("J-G5 the knot's rope is alive (стр. 125): the lead-in sways and tightens as the end goes through; the end follows the hand off the path; the knot logic is the same", _test_rope_alive)
	await _test("J-G4 the string with Mitya (fishing): from his questions on the free day; strike when the float dives; keep the string in the green — the perch comes in; too hard — it snaps", _test_fishing)
	await _test("J-D3 staging (стр. 147, 167, 172): Nina at her porch in O4; in class Agata turns to whoever speaks; Nina walks out through the class door, gone in the black", _test_staging_d3)
	await _test("J-E11 the dinner (стр. 203): the main door shut and an empty chair first; Ulyana comes in through it at «Ульяна по новому мосту прибежала»", _test_dinner_door)
	await _test("J-T51 Tikhon livelier (25.10 стр. 51): besides ears and head — a tail flick, a yawn with the wide mouth, a stretch; more yawns in the dark", _test_tikhon_life)
	await _test("J-R4 no shelf anywhere: the office door flag renamed; an old save with the old name loads with the new", _test_flag_rename)
	await _test("J-E12 the mill wheel's water (25.10 стр. 15, 29.10 стр. 96 — «ничего не изменилось»): the race runs TO the wheel, the rising buckets pour off the left, each paddle cuts in on the right with spray; nothing pours with the pond let down; the epilogue cascade runs", _test_wheel_water)
	await _test("J-R11b the boat on the free day (29.10 стр. 189: «лодки на втором берегу нет, а «К лодке» есть»): the boat is where it was last taken along the rope; «К лодке» over it, «Подтянуть лодку по канату» when it is on the other side", _test_boat_follows)
	await _test("J-E14 the beam end (25.10 стр. 165): the choice «Агата» shows «Агата» cut in the wood, not the painted «Дуня»", _test_beam_agata)
	await _test("J-P161 sheets in the hands sway so one sees it (29.10 стр. 161; 30.10: ±0.32° was not seen): Nina's letters turn about their middle by ≥0.5°, the writing stays readable", _test_paper_sway)
	await _test("J-N67 the night by the stove (25.10 стр. 67): after her two lines Agata is asleep — out of sight at «Спи уж», up again in the morning", _test_night_asleep)
	await _test("J-T145 Tikhon after the news (25.10 стр. 145: «на деле он только выше на печь залезает»): he settles on Agata's bench by the stove, not higher up the stove than his shelf", _test_tikhon_bench)
	await _test("J-H41 the school porch (25.10 стр. 12): Agata climbs the steps up to the door — higher on the screen, not shrinking into the distance", _test_school_steps)
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


# --- E4. The post-office counter -------------------------------------------------------------

func _pick_id(at: Vector2) -> String:
	var hit: Node = rm.current_room.call("pick", at)
	return String(hit.get("hotspot_id")) if hit != null and hit.get("hotspot_id") != null else "none"


func _test_counter() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01"])
	await _enter("Z1")
	await _drain()
	var layer: Node = rm.current_room.find_child("counter", true, false)
	var spr: Sprite2D = layer.get_node_or_null("Image") if layer != null else null
	_check(spr != null, "the counter layer is built")
	if spr != null:
		_check(absf(spr.scale.y / spr.scale.x - 0.84) < 0.005, "the counter is lower, same width: scale %s" % str(spr.scale))
		var legs_y := spr.position.y + 775.0 * spr.scale.y
		_check(absf(legs_y - 890.0) < 2.0, "the front legs stay on the floor at y 890, got %.1f" % legs_y)
	_check(_pick_id(Vector2(1070, 350)) == "tamara", "Tamara above the counter, got %s" % _pick_id(Vector2(1070, 350)))
	_check(_pick_id(Vector2(1070, 820)) == "tamara", "through the counter in front of her — Tamara, got %s" % _pick_id(Vector2(1070, 820)))
	_check(_pick_id(Vector2(1000, 530)) == "drawings", "the sheets on the counter stay the drawings, got %s" % _pick_id(Vector2(1000, 530)))
	_check(_pick_id(Vector2(800, 820)) != "tamara", "the counter away from her is not Tamara")
	# Morning of day 3 (M22): Tamara has crossed to Olkhovka — her click area through the counter goes with her.
	_set_flags(["done_M22"])
	for h in rm.current_room.get_hotspots():
		h.call("refresh")
	await physics_frame
	await physics_frame
	_check(_pick_id(Vector2(1070, 820)) != "tamara", "no Tamara through the counter after M22, got %s" % _pick_id(Vector2(1070, 820)))


# --- E5. Sizes: the mug and the cup, the attic bed --------------------------------------------

## Screen-space opaque bbox of a layer's sprite (alpha > 0.25).
func _layer_box(layer_id: String) -> Rect2:
	var layer: Node = rm.current_room.find_child(layer_id, true, false)
	var spr: Sprite2D = layer.get_node_or_null("Image") if layer != null else null
	if spr == null or spr.texture == null:
		return Rect2()
	var img := spr.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()   # transparent margins off
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in range(used.position.y, used.end.y, 2):
		for x in range(used.position.x, used.end.x, 2):
			if img.get_pixel(x, y).a > 0.25:
				lo = Vector2(minf(lo.x, x), minf(lo.y, y))
				hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
	if lo.x == INF:
		return Rect2()
	return Rect2(spr.position + lo * spr.scale, (hi - lo) * spr.scale)


func _test_sizes() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "v01_cup_blue"])
	await _enter("H1")
	await _drain()
	var mug := _layer_box("mug_table")
	var cup := _layer_box("cup_table_blue")
	_check(mug.size.y > 0 and cup.size.y > 0, "the mug and the chosen cup are on the table")
	_check(absf(mug.size.y / maxf(cup.size.y, 1.0) - 1.0) < 0.3, "the mug about the cup's height: %.0f vs %.0f px" % [mug.size.y, cup.size.y])
	_check(mug.size.x < cup.size.x * 1.25, "the mug about as wide as the cup with its saucer: %.0f vs %.0f px (both with their shadow)" % [mug.size.x, cup.size.x])
	var table: Node = rm.current_room.find_child("table_chair", true, false)
	var tspr: Sprite2D = table.get_node_or_null("Image") if table != null else null
	_check(tspr != null and tspr.texture.resource_path.ends_with("fg_table_chair_nomug.png"), "the table without the painted clay mug")
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "house_open"])
	await _enter("H4")
	await _drain()
	var bed := _layer_box("bed")
	_check(bed.size.x > 460.0, "the attic bed is a real bed now: %.0f px long (was ≈ 350)" % bed.size.x)
	_check(absf(bed.end.y - 682.0) < 6.0, "its legs stay on the floor at y ≈ 682, got %.0f" % bed.end.y)
	var hs: Node = _hotspot("bed")
	_check(hs != null and _pick_id(Vector2(1300, 600)) == "bed", "the bigger bed is clicked on its left half too, got %s" % _pick_id(Vector2(1300, 600)))


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


## J-E6 (a real-game frame 29.10): at dusk before the knot the rope patch, filled over the snowy bank, glowed as a
## white streak over the dark one. Two patches now, by road_held_both_ends; the dark one is not lighter than the
## far bank it lies on (its opaque pixels in the far-bank strip, mean luminance).
func _test_rope_patch() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "rope_brought", "evening_dusk"])
	await _enter("R1")
	await _drain()
	_check(_layer_vis("stopper_empty_dusk_dark") and not _layer_vis("stopper_empty_dusk"), "before the knot — the dark-bank patch")
	var n: Node = rm.current_room.get_node_or_null("Layers/stopper_empty_dusk_dark")
	var spr: Sprite2D = n.get_node_or_null("Image") if n != null else null
	if spr != null:
		var img := spr.texture.get_image()
		if img.is_compressed():
			img.decompress()
		var lum := 0.0
		var cnt := 0
		for y in range(340, 400):         # the far-bank strip of the rope, layer px (x 680–820)
			for x in range(680, 820):
				var c := img.get_pixel(x, y)
				if c.a > 0.6:
					lum += c.get_luminance()
					cnt += 1
		_check(cnt > 0 and lum / cnt < 0.35, "the patch over the dark bank is dark too: mean luminance %.2f over %d px" % [lum / maxf(cnt, 1), cnt])
	# …and the river fog lies over it (the next frame showed the patch as a dark band without fog)
	var amb: Node = _fog_root()
	if amb != null and n != null:
		for f in amb.get("fog"):
			if (f as CanvasItem).visible:
				_check((f as CanvasItem).z_index > (n as CanvasItem).z_index, "fog %s (z %d) over the rope patch (z %d)" % [f.name, f.z_index, n.z_index])
	gs.set_flag("road_held_both_ends", true)
	await _frames(3)
	_check(_layer_vis("stopper_empty_dusk") and not _layer_vis("stopper_empty_dusk_dark"), "after the knot — the snowy-bank patch")


## J-E7 (Director 29.10, стр. 72; 25.10 стр. 110, 155): the lit windows lay their light on Agata walking past. Under the
## figures they went grey-green under the night grade, so they stay over it and a figure in front covers them: the
## window fades by how much of its pane she hides, and comes back when she has passed. Dimmer at the curtains.
func _test_windows() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "house_open", "stove_lit"])
	await _enter("Z2")
	await _drain()
	await _frames(3)
	var tg: Node = rm.current_room.get_node_or_null("TimeOfDay")
	_check(tg != null, "Z2 has its time of day")
	if tg == null:
		return
	var lit: Array = tg.call("probe")["windows_lit"]
	_check(lit.has("house_w2"), "dusk with the stove lit: the house windows glow (%s)" % str(lit))
	var win: Node2D = null
	for n in tg.get("windows"):
		if String(n.name) == "house_w2":
			win = n
	if win == null:
		return
	var a0 := win.modulate.a
	_check(a0 > 0.9, "the window glows while nobody is in front (%.2f)" % a0)
	var player: Node2D = main_node.get_node("World/Player")
	var box: Rect2 = win.get_meta("box")
	var room = rm.current_room
	# stand so the figure's box covers the pane: feet under the window by the figure's height at that depth
	var feet := Vector2(box.get_center().x, box.end.y + 30.0)
	for i in 6:
		var h := 345.0 * float(room.call("depth_scale", feet.y))
		feet.y = box.position.y + h * 0.75
	player.global_position = feet
	await _wait(0.8)
	_check(win.modulate.a < a0 * 0.5, "Agata in front of the window covers its light (%.2f → %.2f)" % [a0, win.modulate.a])
	player.global_position = Vector2(box.get_center().x + 700.0, feet.y)
	await _wait(0.8)
	_check(win.modulate.a > 0.9, "she walked on — the window glows again (%.2f)" % win.modulate.a)
	var pane: Polygon2D = win.get_node_or_null("Pane")
	if pane != null and pane.texture != null:
		var img := pane.texture.get_image()
		var mid := img.get_pixel(img.get_width() / 2, img.get_height() / 2).a
		var side := img.get_pixel(int(img.get_width() * 0.2), img.get_height() / 2).a
		_check(side < mid * 0.85, "dimmer towards the curtains: side %.2f, middle %.2f" % [side, mid])


func _test_mirror_frames() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "done_M09", "done_M09b", "office_mirror_mounted", "has_mirror_mill"])
	await _enter("H2")
	await _drain()
	var mvn: Node = main_node.get_node("MechanicView")
	var h: Node = _hotspot("stand_zm")
	sr.open_mechanic(sr.mechanic_spec(h), "stand_zm")
	await _frames(3)
	_check(sr.mechanic_open and mvn.find_child("FrameCloseup", true, false) is SoftWindow, "the office mirror's frame sits in a soft window (as the bell)")
	var fc: Node = mvn.find_child("FrameCloseup", true, false)
	_check(fc != null and fc.find_child("Frame", true, false) != null, "the workshop crop is inside it")
	sr.call("close_mechanic")
	await _frames(2)
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_open", "done_M14", "nina_mirror_clamped", "h2_bundle_unwrapped"])
	await _enter("H2")
	await _drain()
	sr.open_mechanic(sr.mechanic_spec(_hotspot("bundle_nina")), "bundle_nina")
	await _frames(3)
	var fr: Node = mvn.find_child("Frame", true, false)
	_check(sr.mechanic_open and fr != null and not (fr is Panel), "mother's mirror: the carved frame, not the flat brown panel")
	_check(mvn.find_child("Clamp", true, false) == null, "no grey handle at the side")
	sr.call("close_mechanic")
	await _frames(2)


func _test_schedule() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["house_unlocked", "done_N01", "done_M09", "met_pavel"])
	await _enter("M1")
	await _drain()
	var h: Node = _hotspot("schedule")
	sr.open_view(h.data["view"], "schedule")
	await _wait(1.2)
	var cv: Node = main_node.get_node("CloseupView")   # the view ("Closeup" is the door puzzle)
	var blocks: Array = []
	for n in cv.find_children("Text*", "Label", true, false):
		if n is HandWriting:
			blocks.append(n)
	_check(blocks.size() == 2, "two written blocks on the sheet (shifts, signals): %d" % blocks.size())
	for b in blocks:
		var hw: HandWriting = b
		hw.call("_fit")
		_check(hw.written_bottom() <= hw.fit_height + 0.5, "%s ends on the sheet: %.0f of %.0f px" % [hw.name, hw.written_bottom(), hw.fit_height])
	var fr: Node = cv.find_child("Frame", true, false)
	_check(fr is Control, "the close-up sits in the carved frame")
	var close_btn: Control = cv.get("close_button")
	if fr is Control and close_btn != null:
		var fb := (fr as Control).get_global_rect().end.y + 16.0
		_check(close_btn.get_global_rect().position.y >= fb - 1.0, "«Закрыть» below the frame: %.0f ≥ %.0f" % [close_btn.get_global_rect().position.y, fb])
	sr.close_view()
	await _frames(2)


func _test_boat_rope() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "evening_dusk", "rope_brought", "rope_on_ring", "plate_braced", "done_M15", "done_M16", "boat_back_at_turn"])
	await _enter("Z3")
	await _drain()
	var spec: Dictionary = {}
	for st in sd.call("scene", "M17").get("stage", []):
		if st.has("layer_go"):
			spec = st
	var bl := rm.current_room.get_node_or_null("Layers/boat_dusk") as Node2D
	_check(not spec.is_empty() and bl != null and bl.visible, "the boat at the plate and its staging")
	if spec.is_empty() or bl == null:
		return
	var g: Dictionary = spec["layer_go"][0]
	var pv := Vector2(float(g["pivot"][0]), float(g["pivot"][1]))
	# the painted rope (rooms Z3 effects rope_on_ring_dusk): from the ring to the far bank, sagging
	var a := Vector2(1281, 572)
	var b := Vector2(1150, 402)
	var rope: Array[Vector2] = []
	for i in 41:
		var e := float(i) / 40.0
		rope.append(a.lerp(b, e) + Vector2(0, 14.0 * 4.0 * e * (1.0 - e)))
	sr.call("_stage_layer_go", {"layer_go": [g]})
	var worst := 0.0
	var alpha_mid := 1.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(float(g["s"]) * 1000.0) - 100:
		var q := pv * bl.scale.x + bl.position
		var dmin := 1e9
		for r in rope:
			dmin = minf(dmin, q.distance_to(r))
		worst = maxf(worst, dmin)
		if Time.get_ticks_msec() - t0 < int(float(g["s"]) * 500.0):
			alpha_mid = minf(alpha_mid, bl.modulate.a)
		await process_frame
	_check(worst < 8.0, "the bow stays on the rope all the way (worst %.1f px)" % worst)
	_check(alpha_mid > 0.95, "still clearly seen on the first half of the way (alpha %.2f)" % alpha_mid)
	await _wait(0.4)
	_check(bl.modulate.a < 0.1, "melted at the far end (alpha %.2f)" % bl.modulate.a)


func _test_crossing_black() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "house_unlocked", "ferry_verified", "boat_shuttle_open", "done_M17", "done_M18p", "crossing_hauled", "done_M18", "evening_dusk"])
	await _enter("R2", "from_Z3")
	await _drain()
	var h: Node = _hotspot("rope")
	_check(h != null, "the rope in the boat")
	if h == null:
		return
	sr.open_mechanic(sr.mechanic_spec(h), "rope")
	await _frames(3)
	var mvn: Node = main_node.get_node("MechanicView")
	var panel = mvn.get("panel")
	_check(sr.mechanic_open and panel != null, "the crossing is open")
	if panel == null:
		return
	var rm_mat: ShaderMaterial = panel.get("rope_mat")
	var ring: Control = panel.get("ring")
	_check(rm_mat != null and bool(rm_mat.get_shader_parameter("use_eye")), "the rope runs through the eye (no frozen piece by the ring)")
	_check(ring != null and ring.material is ShaderMaterial, "the ring on top keeps the iron only")
	sr.mechanic_event("crossed")
	var bad := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		var a := float(ui.call("stage_probe")["alpha"])
		if not sr.mechanic_open and rm.current_room != null and rm.current_room.room_id == "R2" and a < 0.98:
			bad += 1
		await process_frame
	_check(bad == 0, "the boat's view (R2) is never seen after the close-up (%d frames)" % bad)
	_check(not sr.mechanic_open and rm.current_room != null and rm.current_room.room_id == "R3" and float(ui.call("stage_probe")["alpha"]) < 0.05,
			"at the far pier, out of the black")


func _test_ttt() -> void:
	var TTT = load("res://scripts/mechanics/tictactoe_panel.gd")
	# the best move: take a win, block a line of two
	_check(int(TTT.best_move(["o", "o", "", "x", "x", "", "", "", ""], "o")) == 2, "she takes a win in one")
	_check(int(TTT.best_move(["x", "x", "", "", "o", "", "", "", ""], "o")) == 2, "she blocks a line of two")
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M21b", "done_M22", "house_open", "met_nina", "met_ulyana"])
	await _enter("O1", "from_O2")
	await _drain()
	var h: Node = _hotspot("ulyana")
	_check(h != null and h.visible, "Ulyana in class")
	if h == null:
		return
	sr.interact(h)
	var tw := 0
	while sr.current_options().is_empty() and tw < 240:
		tw += 1
		if not sr.current_beat.is_empty() and sr.current_beat.get("type") != "options":
			sr.advance()
		await process_frame
	var opts: Array = sr.current_options()
	var ids: Array = opts.map(func(o): return String(o.get("id", "")))
	_check(ids.has("ttt"), "her choice offers the game: %s" % str(ids))
	sr.choose("ttt")
	var guard := 0
	while not sr.mechanic_open and guard < 200:
		guard += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	_check(sr.mechanic_open, "after the words the board opens")
	var mvn: Node = main_node.get_node("MechanicView")
	var panel = mvn.get("panel")
	if panel == null:
		return
	await _wait(0.8)
	var pr: Dictionary = panel.call("probe")
	_check(pr["turn"] == "x" and not pr["over"], "Agata starts")
	# play the centre, then keep taking the first free cell until the game ends
	panel.call("play_cell", 4)
	var t0 := Time.get_ticks_msec()
	while not bool(panel.call("probe")["over"]) and Time.get_ticks_msec() - t0 < 20000:
		var b: Array = panel.call("probe")["board"]
		if String(panel.call("probe")["turn"]) == "x":
			for i in 9:
				if String(b[i]) == "":
					panel.call("play_cell", i)
					break
		await _wait(0.2)
	pr = panel.call("probe")
	_check(pr["over"] and pr["games"] == 1 and int(pr["marks"]) >= 5, "a game played to its end: %s" % str(pr["result"]))
	await _wait(1.3)
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	pr = panel.call("probe")
	_check(pr["again"] and pr["stop"], "«Ещё раз» after the game, «Хватит» — the close-up's own button")
	_check(int((pr["tally"] as Array)[0]) + int((pr["tally"] as Array)[1]) == (0 if pr["result"] == "draw" else 1), "the score in chalk: a stick for the game won (%s)" % str(pr["tally"]))
	_check(mvn.get("sounds_played").count("chalk") >= 5, "every mark has its chalk scrape: %s" % str(mvn.get("sounds_played")))
	var flag: String = {"won": "ttt_won", "lost": "ttt_lost", "draw": "ttt_draw"}[String(pr["result"])]
	_check(gs.has_flag(String(flag)), "the game's event sets %s" % flag)
	panel.get("again_btn").emit_signal("pressed")
	await _frames(2)
	pr = panel.call("probe")
	_check(not pr["over"] and int(pr["marks"]) == 0 and pr["turn"] == "o", "again: a clean board, Ulyana starts now")
	var cb: Button = mvn.get("close_button")
	_check(cb != null and cb.visible and cb.text == sd.text("@mech.ttt.label_stop"), "one way out, bottom right: «%s»" % (cb.text if cb != null else "?"))
	cb.emit_signal("pressed")
	guard = 0
	while (sr.mechanic_open or not sr.current_beat.is_empty()) and guard < 300:
		guard += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	_check(not sr.mechanic_open and gs.has_flag("ttt_played"), "«Хватит» puts the board away")


func _rhythm_wait(panel, ph: String, limit_s: float = 12.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while String(panel.call("probe")["phase"]) != ph and Time.get_ticks_msec() - t0 < int(limit_s * 1000.0):
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	return String(panel.call("probe")["phase"]) == ph


func _test_rhythm() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "met_tikhon"])
	await _enter("H1")
	await _drain()
	var h: Node = _hotspot("tikhon")
	_check(h != null, "Tikhon in the room")
	if h == null:
		return
	sr.interact(h)
	var tw := 0
	while sr.current_options().is_empty() and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty() and sr.current_beat.get("type") != "options":
			sr.advance()
		await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids.has("spoons"), "his questions offer the spoons: %s" % str(ids))
	sr.choose("spoons")
	tw = 0
	while not sr.mechanic_open and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	var panel = main_node.get_node("MechanicView").get("panel")
	_check(sr.mechanic_open and panel != null, "the board with the cups opens")
	if panel == null:
		return
	var pattern: Array = panel.get("rounds")[0]
	_check(await _rhythm_wait(panel, "agata"), "he taps first, then it is her turn")
	_check(int(panel.call("probe")["played"]) == pattern.size(), "all his taps sounded")
	# answered in his rhythm
	for i in pattern.size():
		if i > 0:
			await _wait(float(pattern[i]) - float(pattern[i - 1]))
		panel.call("tap")
	await _frames(2)
	_check(bool(panel.call("probe")["ok"]), "in time — right: %s" % str(panel.call("probe")["judged"]))
	_check(await _rhythm_wait(panel, "agata", 15.0) and int(panel.call("probe")["round"]) == 1, "the next round, longer")
	# out of time: all at once
	var n2: int = (panel.get("rounds")[1] as Array).size()
	for i in n2:
		panel.call("tap")
		await _wait(0.05)
	await _frames(2)
	_check(not bool(panel.call("probe")["ok"]), "out of time — wrong")
	_check(await _rhythm_wait(panel, "agata", 15.0) and int(panel.call("probe")["round"]) == 1 and int(panel.call("probe")["misses"]) == 1, "a miss — the same round again")
	_check(panel.find_child("Slow", true, false) != null, "«Облегчить» on the board")
	var tol0 := float(panel.call("probe")["tol"])
	var slow_cb := panel.find_child("Slow", true, false) as CheckButton  # (not TimingBar.slow: the test compiles before the autoloads)
	slow_cb.button_pressed = not slow_cb.button_pressed
	_check(float(panel.call("probe")["tol"]) != tol0, "«Облегчить» changes the tolerance at once (%.2f → %.2f)" % [tol0, float(panel.call("probe")["tol"])])
	slow_cb.button_pressed = not slow_cb.button_pressed
	var mv: Node = main_node.get_node("MechanicView")
	mv.get("close_button").emit_signal("pressed")
	var said := false
	tw = 0
	while (sr.mechanic_open or not sr.current_beat.is_empty()) and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty():
			said = said or String(sr.current_beat.get("text", "")).contains(sd.text("@H1.tikhon.spoons_quit").left(10))
			sr.advance()
		await process_frame
	_check(not sr.mechanic_open, "«Хватит» puts it away")
	_check(said, "with his word: «%s»" % sd.text("@H1.tikhon.spoons_quit"))


func _test_rope_alive() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["evening_dusk", "done_M15a", "nina_mirror_clamped", "nina_time_compared", "has_brace_plate", "skoba_on_plate", "plate_braced", "rope_brought", "done_M15s"])
	await _enter("Z3")
	await _drain()
	var h: Node = _hotspot("pier_plate")
	_check(h != null, "the plate by the pier")
	if h == null:
		return
	sr.open_mechanic(sr.mechanic_spec(h), "pier_plate")
	await _frames(10)
	var p = main_node.get_node("MechanicView").get("panel")
	_check(p != null and bool(p.call("probe").get("knot_stage", false)), "the knot waits")
	if p == null:
		return
	var back: Line2D = p.get("rope_back")
	var a0: PackedVector2Array = back.points
	await _frames(40)
	var a1: PackedVector2Array = back.points
	var moved := 0.0
	for i in mini(a0.size(), a1.size()):
		moved = maxf(moved, a0[i].distance_to(a1[i]))
	_check(moved > 1.5, "the lead-in sways by itself (max shift %.1f px in 40 frames)" % moved)
	var kn = p.get("knot")
	var st: PackedVector2Array = kn.strokes[0]
	var sag0 := float(p.get("_sag"))
	await _move(kn.end_point())
	await _button(kn.end_point(), true)
	var hand := Vector2.ZERO
	for i in range(1, st.size() - 1):
		var nrm := (st[i] - st[i - 1]).orthogonal().normalized()
		hand = st[i] + nrm * 45.0
		await _move(hand)
	await _frames(20)
	var pts: PackedVector2Array = back.points
	var drawn_end: Vector2 = pts[pts.size() - 1]
	var logic_end: Vector2 = kn.end_point()
	_check(kn.grabbed and kn.stroke == 0 and kn.progress > 0.0, "the end goes along the first stroke (progress %.0f)" % kn.progress)
	_check(drawn_end.distance_to(logic_end) > 20.0 and drawn_end.distance_to(hand) < logic_end.distance_to(hand), "the drawn end follows the hand off the path (%s → %s, hand %s)" % [str(logic_end), str(drawn_end), str(hand)])
	_check(float(p.get("_sag")) < sag0 - 1.0, "the lead-in tightens as the rope goes in (sag %.1f → %.1f)" % [sag0, float(p.get("_sag"))])
	await _button(hand, false)
	await _wait(0.6)
	_check(not kn.grabbed and kn.progress == 0.0 and String(p.call("probe")["knot_path"]["state"]) == "free", "let go mid-stroke — slips back as before")
	sr.close_mechanic()
	await _frames(3)


func _test_fishing() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["started_M19", "done_M19", "done_M21b", "done_M22", "free_walk_day3", "morning_day3", "house_open", "met_nina", "met_mitya"])
	await _enter("O4", "from_O2")
	await _drain()
	var h: Node = _hotspot("mitya")
	_check(h != null and h.visible, "Mitya by the fence")
	if h == null:
		return
	sr.interact(h)
	var tw := 0
	while sr.current_options().is_empty() and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty() and sr.current_beat.get("type") != "options":
			sr.advance()
		await process_frame
	var ids: Array = sr.current_options().map(func(o): return String(o.get("id", "")))
	_check(ids.has("fish"), "his questions offer fishing: %s" % str(ids))
	sr.choose("fish")
	tw = 0
	while not sr.mechanic_open and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	var panel = main_node.get_node("MechanicView").get("panel")
	_check(sr.mechanic_open and panel != null, "the river opens")
	if panel == null:
		return
	_check(panel.find_child("River", true, false) != null, "the river is a part of the painting")
	# the float dives: strike, then keep the string in the green
	panel.set("phase", "bite")
	panel.set("phase_t", 0.0)
	panel.call("press", true)
	_check(String(panel.call("probe")["phase"]) == "fight", "a strike in time hooks the fish")
	var g: Array = panel.call("probe")["green"]
	var mid := (float(g[0]) + float(g[1])) * 0.5
	var t0 := Time.get_ticks_msec()
	while String(panel.call("probe")["phase"]) == "fight" and Time.get_ticks_msec() - t0 < 25000:
		panel.call("press", float(panel.call("probe")["tension"]) < mid)
		await process_frame
	_check(String(panel.call("probe")["phase"]) == "caught" and gs.has_flag("mitya_fish_caught"), "kept in the green — the perch is in: %s" % str(panel.call("probe")))
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	_check(bool(panel.call("probe")["again"]), "«Ещё» after the catch")
	panel.get("again_btn").emit_signal("pressed")
	panel.set("phase", "bite")
	panel.set("phase_t", 0.0)
	panel.call("press", true)
	var lost0 := int(panel.call("probe")["lost"])
	t0 = Time.get_ticks_msec()
	while String(panel.call("probe")["phase"]) == "fight" and Time.get_ticks_msec() - t0 < 10000:
		panel.call("press", true)   # pulling all the time
		await process_frame
	_check(String(panel.call("probe")["phase"]) == "wait" and int(panel.call("probe")["lost"]) == lost0 + 1, "pulled too hard — the string snaps, wait again")
	var mvf: Node = main_node.get_node("MechanicView")
	var snd: Array = mvf.get("sounds_played")
	_check(snd.has("line_snap") and snd.has("water_slap"), "the string snaps with a crack, the perch comes out with a splash: %s" % str(snd))
	_check(panel.find_child("Slow", true, false) != null, "«Облегчить» under the bar")
	var hint_l: Label = panel.get("hint")
	var hb := hint_l.get_global_rect().end.y
	var ab := (panel.get("again_btn") as Button).get_global_rect().end.y
	_check(hb < 930.0 and ab < 940.0, "the hint and «Ещё» stay above the text box (hint bottom %.0f, «Ещё» %.0f)" % [hb, ab])
	mvf.get("close_button").emit_signal("pressed")
	tw = 0
	while (sr.mechanic_open or not sr.current_beat.is_empty()) and tw < 300:
		tw += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	_check(not sr.mechanic_open and gs.has_flag("mitya_fished"), "«Хватит» — back on the street")


func _test_dinner_door() -> void:
	var room: Dictionary = sd.call("room", "EP_dinner")
	var lay := {}
	for l in room.get("layers", []):
		lay[String(l.get("id", ""))] = l
	_check(lay.has("family_closed") and (lay["family_closed"].get("unless", []) as Array).has("ep_ulyana_came")
			and (lay.get("family", {}).get("if", []) as Array).has("ep_ulyana_came"), "two states of the family layer: the door shut, then open with Ulyana")
	_check(ResourceLoader.exists(String(lay.get("family_closed", {}).get("image", ""))), "the shut-door layer is in the game")
	var m26: Dictionary = sd.call("scene", "M26")
	var at := -1
	for st in m26.get("stage", []):
		if (st.get("sets", []) as Array).has("ep_ulyana_came"):
			at = int(st.get("at", -1))
	var lines: Array = m26.get("mandatory_lines", [])
	_check(at >= 0 and at < lines.size() and String(lines[at].get("text", "")).contains("Ульяна") and String(lines[at + 1].get("speaker", "")) == "ulyana",
			"the door opens at the line that brings her in, just before her own words (at %d)" % at)


func _test_tikhon_life() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "met_tikhon"])
	await _enter("H1")
	await _drain()
	var pup: Node = null
	for c in rm.current_room.get_children():
		if c.has_method("pick_accent"):
			pup = c
	_check(pup != null, "Tikhon (the puppet) in the house")
	if pup == null:
		return
	var acc: AnimationPlayer = pup.get("accent")
	for an in ["tail_flick", "yawn", "stretch", "ear_twitch_l", "head_tilt"]:
		_check(acc.has_animation(an), "he can %s" % an)
	var seen := {}
	for i in 200:
		seen[String(pup.call("pick_accent", float(i) / 200.0))] = true
	_check(seen.has("yawn") and seen.has("stretch") and seen.has("tail_flick") and seen.has("head_tilt"), "all of them come up in turn: %s" % str(seen.keys()))
	acc.play("yawn")
	await _wait(0.9)
	var mf := int(pup.get("mouth_frame"))
	_check(mf == (pup.get("mouth_frames") as Array).size() and mf > 0, "the yawn opens the mouth wide (frame %d)" % mf)
	await _wait(1.4)
	_check(int(pup.get("mouth_frame")) == 0, "and closes it after")


func _test_flag_rename() -> void:
	gs.reset()
	var d: Dictionary = gs.call("to_dict")
	d["flags"] = {"office_shelf_lifted": true, "done_M13a": true}
	_check(bool(gs.call("from_dict", d)), "an old save loads")
	_check(gs.has_flag("office_door_opened") and not gs.has_flag("office_shelf_lifted"), "the old flag comes in under its new name")
	gs.reset()


func _test_school_steps() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M21b", "house_open", "met_nina", "met_ulyana", "school_path_open"])
	await _enter("O2", "porch")
	await _drain()
	var player: Node2D = main_node.get_node("World/Player")
	var room: Node = rm.current_room
	_check(room.get("stairs") is Array and (room.get("stairs") as Array).size() == 1, "the porch steps are in the room data")
	var bottom := Vector2(560, 738)   # the front edge of the lowest step
	var top := Vector2(556, 622)
	var s_bottom := float(room.call("depth_scale_at", bottom))
	var s_top := float(room.call("depth_scale_at", top))
	var s_flat := float(room.call("depth_scale", top.y))
	_check(s_top > s_bottom * 0.9 and s_top > s_flat * 1.05, "on the steps she keeps her size (bottom %.3f, door %.3f; a flat floor would give %.3f)" % [s_bottom, s_top, s_flat])
	# she walks there by herself: the exit to the class is at the top of the steps
	var ex: Node = null
	for e in room.call("get_exits"):
		if String(e.get("target_room")) == "O1":
			ex = e
	_check(ex != null, "the door to the class")
	if ex == null:
		return
	var stand: Vector2 = ex.call("get_stand_position") if ex.has_method("get_stand_position") else top
	_check(stand.y < 640.0, "the door is reached at the top of the steps (stand %s)" % str(stand))
	player.call("walk_to", stand)
	var t0 := Time.get_ticks_msec()
	var min_y := 2000.0
	while bool(player.call("is_walking")) and Time.get_ticks_msec() - t0 < 12000:
		min_y = minf(min_y, player.global_position.y)
		await process_frame
	_check(player.global_position.distance_to(stand) < 12.0, "she gets up to the door (%s, wanted %s)" % [str(player.global_position), str(stand)])
	_check(absf(player.scale.y) > s_flat * 1.05, "and is not shrunk at the door (scale %.3f)" % absf(player.scale.y))


func _test_staging_d3() -> void:
	# 147: Nina by her house in O4 — in front of the fence at the foot of her steps, not behind it to the left
	var o4: Dictionary = sd.call("room", "O4")
	var nina_r: Array = []
	for h in o4.get("hotspots", []):
		if String(h.get("id")) == "nina":
			nina_r = h.get("rect", [])
	_check(nina_r.size() == 4 and float(nina_r[1]) + float(nina_r[3]) >= 690.0 and float(nina_r[0]) + float(nina_r[2]) * 0.5 >= 1370.0,
			"O4: Nina's feet by her porch (%s)" % str(nina_r))
	# 167: in class Agata turns to the speaker
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M21b", "house_open", "met_nina", "met_ulyana"])
	await _enter("O1", "from_O2")
	await _frames(4)
	var player: Node2D = main_node.get_node("World/Player")
	var nina: Node2D = rm.current_room.get_node_or_null("npc_nina")
	var uly: Node2D = rm.current_room.get_node_or_null("npc_ulyana")
	_check(nina != null and uly != null, "Nina and Ulyana in the class")
	if nina != null and uly != null:
		sr.call("_face_speaker", {"speaker": "ulyana"})
		var sheet = player.get("sheet")
		if sheet != null and not bool(player.call("is_3d")):
			_check(int(player.get("direction")) == int(sheet.call("direction_index", uly.global_position - player.global_position)), "Ulyana speaks — Agata turns to her")
			sr.call("_face_speaker", {"speaker": "nina"})
			_check(int(player.get("direction")) == int(sheet.call("direction_index", nina.global_position - player.global_position)), "Nina speaks — Agata turns to her")
			var before := int(player.get("direction"))
			sr.call("_face_speaker", {"speaker": "narrator"})
			_check(int(player.get("direction")) == before, "the narrator's line keeps her as she is")
	# 172, 140 (25.10): the end of M22 — Nina walks into the open class door; the black comes while she is in the
	# doorway (no dissolve on screen), and in the black she is gone and the door is shut
	var m22: Dictionary = sd.call("scene", "M22")
	var goes := false
	var faces := false
	for st in m22.get("stage", []):
		for g in st.get("npc_go", []):
			if _at_key(st) == "end" and String(g.get("id")) == "nina" and bool(g.get("in_black", false)) and g.has("door"):
				goes = true
		for g in st.get("npc_face", []):
			if int(st.get("at", -1)) == 0 and String(g.get("id")) == "agata" and String(g.get("face")) == "nina":
				faces = true
	_check(goes and faces, "M22: Agata turns to mother at the start; Nina walks out through the class door at the end, gone in the black")
	# 145, 169: the knock on Ilya's shutter, Nina's knuckle on the board — sounds the engine makes, at their lines
	var knocks := {}
	for sid in ["M19", "M22"]:
		for st in sd.call("scene", sid).get("stage", []):
			for snd in st.get("sounds", []):
				if String(snd.get("id", "")).begins_with("synth:knock"):
					knocks[sid] = String(snd["id"])
	var synth = load("res://scripts/mechanics/synth_sfx.gd")
	_check(knocks.get("M19", "") == "synth:knock_shutter" and knocks.get("M22", "") == "synth:knock_board"
			and synth.stream("knock_shutter").data.size() > 1000 and synth.stream("knock_board").data.size() > 1000,
			"the knocks are there and sound: %s" % str(knocks))
	var alpha_at_black := [-1.0]
	var door_seen := [false]
	var on_fade := func(to: float, _s: float) -> void:
		if to >= 0.99 and alpha_at_black[0] < 0.0 and nina != null and is_instance_valid(nina):
			alpha_at_black[0] = (nina as CanvasItem).modulate.a
			door_seen[0] = rm.current_room.get_node_or_null("StageDoor") != null
	sr.stage_fade.connect(on_fade)
	await _drain()
	await _wait(3.5)
	await _drain()
	sr.stage_fade.disconnect(on_fade)
	_check(gs.has_flag("done_M22") and (nina == null or not is_instance_valid(nina) or not nina.visible), "after M22 Nina has left the class")
	if nina != null and alpha_at_black[0] >= 0.0:
		_check(alpha_at_black[0] > 0.95 and door_seen[0], "she is still there, in the open door, when the black comes — no dissolve on screen (alpha %.2f, door %s)" % [alpha_at_black[0], str(door_seen[0])])
	_check(rm.current_room.get_node_or_null("StageDoor") == null, "the door is shut again after the black")
	# 177: on the free day Agata walks round Mitya by the fence in O4, not through him
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["started_M19", "done_M19", "done_M21b", "done_M22", "free_walk_day3", "morning_day3", "house_open", "met_nina", "met_mitya"])
	await _enter("O4", "from_O2")
	await _drain()
	await physics_frame
	await physics_frame
	var reg := rm.current_room.get_node_or_null("Walkable") as NavigationRegion2D
	_check(reg != null, "O4 has its floor")
	if reg != null:
		var nm := reg.get_navigation_map()
		var path := NavigationServer2D.map_get_path(nm, Vector2(1150, 822), Vector2(1600, 822), true)
		var inside := 0
		for i in range(1, path.size()):
			for k in 11:
				var q := path[i - 1].lerp(path[i], float(k) / 10.0)
				var dq := (q - Vector2(1367, 820)) / Vector2(44, 15)
				if dq.length() < 1.0:
					inside += 1
		_check(path.size() >= 2 and inside == 0, "the way past Mitya goes round his feet (%d points inside, path %d)" % [inside, path.size()])


func _water(id: String) -> Polygon2D:
	var amb: Node = _fog_root()
	if amb == null:
		return null
	for w in amb.get("water"):
		if String(w.name) == id:
			return w
	return null


func _test_water() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_N01", "done_M09", "met_pavel"])
	await _enter("M4")
	await _drain()
	var held := _water("flume_held")
	var rush := _water("flume_rush")
	_check(held != null and held.visible and rush != null and not rush.visible, "the sluice shut: the flume's water stands at the gate")
	gs.set_flag("sluice_opened", true)
	await _frames(3)
	_check(rush != null and rush.visible and not held.visible, "the sluice open: the pond rushes through the flume")
	if rush != null:
		var fl: Vector2 = (rush.material as ShaderMaterial).get_shader_parameter("flow")
		_check(fl.length() > 40.0 and float((rush.material as ShaderMaterial).get_shader_parameter("streaks")) >= 0.9, "a fast flow with foam lines: flow %s" % str(fl))
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01"])
	await _enter("Z3")
	await _drain()
	var near := _water("near_water")
	_check(near != null and float((near.material as ShaderMaterial).get_shader_parameter("lap")) > 0.5, "Z3: the near water laps at the bank")
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01"])
	await _enter("R3")
	await _drain()
	_check(_water("near_stones") != null and _water("near_stones").visible, "R3: the water under the stone bank ripples")


func _test_save_delete() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01"])
	await _enter("Z2")
	await _drain()
	var slot := "1"   # GameState.MANUAL_SLOTS[0]
	_check(rm.save_game(slot), "saved to slot %s" % slot)
	ui.call("open_menu_panel", "load")
	await _frames(2)
	var row: Dictionary = ui.get("slot_rows")[slot]
	var txt := (row["info"] as Label).text
	var re := RegEx.create_from_string("\\d{2}\\.\\d{2}\\.\\d{4}, \\d{2}:\\d{2}")
	_check(re.search(txt) != null, "the slot shows when it was saved: «%s»" % txt)
	var db: Button = row.get("delete", null)
	_check(db != null and db.visible, "«Удалить» on the saved slot")
	db.pressed.emit()
	await _frames(2)
	_check(ui.call("delete_dialog_open"), "it asks first")
	var dlg: Control = ui.get("delete_dialog")
	(dlg.find_child("No", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(not ui.call("delete_dialog_open") and gs.has_save(slot), "the red cross keeps the save")
	db.pressed.emit()
	await _frames(2)
	(dlg.find_child("Yes", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(not gs.has_save(slot) and not db.visible, "the green tick deletes it")
	ui.call("close_menu_panel")


func _test_minigames() -> void:
	var TB = load("res://scripts/mechanics/timing_bar.gd")
	var was: bool = TB.slow
	TB.slow = false
	_check(is_equal_approx(TB.green_k(), 0.7), "normal mode: the green zone 0.7 of the data's width")
	TB.slow = true
	_check(is_equal_approx(TB.green_k(), 1.1), "«Облегчить»: 1.1 — about as the old normal")
	TB.slow = was
	# The log: the red band (the stone) under the green one is about a third of the gauge, not a tenth.
	var wspec: Dictionary = {}
	for sc in (sd.get("scenes") as Dictionary).values():
		for m in (sc as Dictionary).get("mechanics", []):
			if String(m.get("spec", {}).get("type", "")) == "windlass":
				wspec = m["spec"]
	var lg := WindlassLogic.new(wspec.get("logic", {}))
	lg.ease(1.0, 0.7)
	_check(1.0 - lg.zone().y >= 0.25, "the log's red band: %.2f of the gauge" % (1.0 - lg.zone().y))
	# The brace: Agata counts the first two blows.
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M15a", "evening_dusk", "has_brace_plate"])
	await _enter("Z3")
	await _drain()
	var h: Node = _hotspot("pier_plate")
	var spec: Dictionary = sr.mechanic_spec(h) if h != null else {}
	if spec.is_empty():
		for hh in sd.room("Z3").get("hotspots", []):
			if String(hh.get("id", "")) == "pier_plate":
				spec = hh.get("mechanic", {})
	sr.open_mechanic(spec, "pier_plate")
	await _frames(3)
	var mvn: Node = main_node.get_node("MechanicView")
	var panel = mvn.get("panel")
	_check(panel != null and panel.has_method("pop_word"), "the plate close-up is open")
	if panel != null and panel.get("timing") != null:
		for n in [1, 2]:
			panel.timing.logic.hits = n
			panel.call("_on_struck", "hit")
			await _frames(1)
		var said: Array = panel.get("words_said")
		_check(said.has("mech.plate.count_1") and said.has("mech.plate.count_2"), "«Раз!», «Два!» after the first two blows: %s" % str(said))
	sr.call("close_mechanic")
	await _frames(2)


func _test_rain_night() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M07", "done_M08", "house_open"])
	await _enter("Z4")
	await _drain()
	await _frames(3)
	var amb: Node = _fog_root()
	var tg: Node = rm.current_room.get_node_or_null("TimeOfDay")
	_check(amb != null and tg != null and String(tg.get("route")) == "light", "Z4 is lit by its lights (the «living world» takes the grade)")
	var rain = amb.get("rain") if amb != null else null
	_check(rain != null, "it drizzles in Z4")
	if rain != null:
		var m: Color = (amb as CanvasItem).modulate * (rain as CanvasItem).modulate
		_check(m.r >= 0.59 and m.g >= 0.59 and m.b >= 0.59, "the drizzle keeps at least 0.6 of its brightness at night: %s (layer %s)" % [str(m), str((amb as CanvasItem).modulate)])


func _test_facing() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_N01", "house_unlocked"])
	await _enter("M1")
	await _drain()
	var h: Node = _hotspot("pavel")
	var actor: Node2D = rm.current_room.get_node_or_null("npc_pavel")
	var player: Node2D = main_node.get_node("World/Player")
	_check(h != null and actor != null, "Pavel stands in the mill yard")
	if h == null or actor == null:
		return
	var lp: Vector2 = player.call("_look_point", h)
	_check(absf(lp.y - actor.global_position.y) < 4.0, "Agata looks at Pavel's feet (%s), not the middle of his box (%s)" % [str(lp), str(h.global_position)])
	# from her stand the look is across, not up: the sheet row is a side or front one, not the back
	var stand: Vector2 = h.call("get_stand_position")
	var v := lp - stand
	_check(absf(v.x) > absf(v.y) or v.y > 0.0, "from her stand the look goes across or down to him: %s" % str(v))
	actor.call("set_state", "talk")
	await _frames(2)
	var to_her := player.global_position - actor.global_position
	var sheet = actor.get("sheet")
	if sheet != null and not (actor.has_method("is_3d") and bool(actor.call("is_3d"))):
		_check(int(actor.get("direction")) == int(sheet.call("direction_index", to_her)), "talking, Pavel turns to Agata")


func _test_m18_staging() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "started_M18p", "done_M18p", "evening_dusk"])
	await _enter("R3")
	await _drain()
	var pel: Node = rm.current_room.get_node_or_null("npc_pelageya")
	var mit: Node = rm.current_room.get_node_or_null("npc_mitya")
	_check(pel != null and mit != null, "Pelageya and Mitya at the far pier")
	if pel == null or mit == null:
		return
	sr.call("_run_stage", {"npc_face": [{"id": "pelageya", "face": "mitya"}, {"id": "mitya", "face": "pelageya"}]})
	await _frames(2)
	_check(pel.get("partner") == mit and mit.get("partner") == pel, "npc_face: they turn to each other where they stand")
	var m18: Dictionary = sd.call("scene", "M18")
	var ats: Array = []
	var end_go := false
	var apart := false
	for st in m18.get("stage", []):
		ats.append(_at_key(st))
		for g in st.get("npc_go", []):
			if _at_key(st) == "end" and String(g.get("id")) == "mitya":
				end_go = true
			if _at_key(st) == "4" and String(g.get("id")) == "pelageya":
				apart = absf(float(g["to"][0]) - 520.0) > 120.0
	_check(ats.has("1") and end_go and apart, "M18: faces at «Мама.», apart after the hug, Mitya off up the path at the end: %s" % str(ats))
	gs.set_flag("done_M18", true)
	for h in rm.current_room.get_hotspots():
		h.call("refresh")
	await _frames(2)
	_check(not _hotspot("mitya").visible, "after M18 Mitya is gone from the pier (up the path)")


## A staging's `at` as text: a line number (JSON gives it as a float) or "end".
func _at_key(st: Dictionary) -> String:
	var a = st.get("at", -1)
	return String(a) if a is String else str(int(a))


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



func _test_tar() -> void:
	gs.reset()
	_set_flags(["done_M01", "house_unlocked", "house_open", "done_M13", "has_key_sluice"])
	await _enter("H2")
	var pot := _hotspot("tar_pot")
	_check(pot != null and pot.visible, "H2: the tar pot on the workbench")
	if pot == null:
		return
	sr.interact(pot)
	await _frames(2)
	var seen := await _drain()
	_check(seen.has("H2.tar_pot.not_now") and not gs.has_item("tar"), "before Pavel asks: «сейчас ни к чему», nothing taken (%s)" % str(seen))
	gs.set_flag("sluice_key_inserted", true)
	sr.interact(pot)
	await _frames(2)
	seen = await _drain()
	_check(seen.has("H2.tar_pot.take") and gs.has_item("tar") and sr.journal_goal().contains("К затвору"), "after: poured into a jar, the goal — back to the sluice (%s, %s)" % [str(seen), sr.journal_goal()])
	sr.interact(pot)
	await _frames(2)
	seen = await _drain()
	_check(gs.inventory.count("tar") == 1 and seen.has("H2.tar_pot.taken"), "once only (%s)" % str(seen))
	# The sluice: the lever in — no close-up; the tar on the winch — the close-up.
	var gate: Dictionary = {}
	for h in sd.room("M4").get("hotspots", []):
		if String(h.get("id", "")) == "gate":
			gate = h
	var iu: Dictionary = gate.get("item_use", {})
	_check(not bool(iu.get("key_sluice", {}).get("open_mechanic", false)) and bool(iu.get("tar", {}).get("open_mechanic", false)),
		"the lever does not open the sluice any more, the tar does")
	_check((gate.get("mechanic", {}).get("requires", {}).get("flags", []) as Array).has("windlass_tarred"), "the sluice close-up needs the winch tarred")
	gs.reset()


func _test_last_frame() -> void:
	var room: Dictionary = sd.room("EP_dinner")
	var snow := 0
	for e in room.get("effects", []):
		if String(e.get("type", "")) == "snow" and bool(e.get("far", false)) and int(e.get("z", 1)) < 0:
			snow += 1
	_check(snow >= 2, "snow behind the window panes, under the people (%d effects)" % snow)
	var lights: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/lights/EP_dinner.json"))
	var lit := false
	for src in (lights as Dictionary).get("sources", []) if lights is Dictionary else []:
		var r: Array = src.get("rect", [0, 0, 0, 0])
		var on_wick := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).has_point(Vector2(1287, 520))
		if on_wick and float(src.get("params", {}).get("flame", 0.0)) > 0.5:
			lit = true
	_check(lit, "the candle light sits on the wick and draws a live flame")
	for l in room.get("layers", []):
		var c: Dictionary = l.get("compose", {})
		if String(l.get("id", "")) == "tikhon":
			_check(bool(c.get("mirror", false)), "Tikhon turned to the people at the table")
		if String(l.get("id", "")) == "cup_blue":
			_check(float(c.get("width", 0)) >= 50.0 and float(c.get("at", [0, 0])[1]) < 540.0, "the cup larger and on the table (%s)" % str(c.get("at")))


# --- J-E12. The mill wheel's water ----------------------------------------------------------------

func _test_wheel_water() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_N01", "done_M09", "met_pavel"])
	await _enter("M1")
	await _drain()
	var amb: Node = _fog_root()
	var ww = rm.current_room.get_node_or_null("Ambient/Wheel/wheel_water")
	var wheel = rm.current_room.get_node_or_null("Layers/wheel")
	_check(ww is AmbientWheel and wheel != null and wheel.is_spinning(), "M1: the wheel turns and its water is drawn over it")
	if not (ww is AmbientWheel):
		return
	_check(rm.current_room.get_node_or_null("Layers/wheel_drips") == null, "no painted drips standing still beside the turning paddles")
	# Which way the water must go: the wheel turns clockwise (its bottom goes left) — the race brings the water from the
	# gate on the right TO the wheel, so it pushes the bottom paddles the way they go.
	var race := _water("race")
	var fl: Vector2 = (race.material as ShaderMaterial).get_shader_parameter("flow") if race != null else Vector2.ZERO
	_check(float(wheel.data.get("spin", {}).get("deg_per_s", 0.0)) > 0.0 and fl.x < -30.0, "the race runs toward the wheel, the way its bottom paddles go (flow %s)" % str(fl))
	var cut: Array = ww.probe()["cut"]
	var hub: Vector2 = ww.hub()
	_check(cos(deg_to_rad(float(cut[0]))) > 0.2 and cos(deg_to_rad(float(cut[1]))) < -0.2, "paddles cut in on the right, come up on the left (%s)" % str(cut))
	var p0: Dictionary = ww.probe()
	await create_timer(3.0).timeout
	var p1: Dictionary = ww.probe()
	var poured := int(p1["poured"]) - int(p0["poured"])
	var entries := int(p1["entries"]) - int(p0["entries"])
	# 16 paddles at 22°/s — about one paddle a second cuts in; the buckets pour all the time.
	_check(poured > 200 and entries >= 2 and entries <= 5 and int(p1["drops"]) > 40, "3 s: %d drops poured, %d paddles cut in, %d drops in the air" % [poured, entries, int(p1["drops"])])
	# The pour is on the rising (left) side, below the axle: sample the drops in the air.
	var left := 0
	var right := 0
	for d in ww.get("_drops"):
		if int(d[3]) == AmbientWheel.POUR:
			if (d[0] as Vector2).x < hub.x:
				left += 1
			else:
				right += 1
	_check(left > 20 and right < left / 8 + 1, "the water pours off the rising left side (%d left, %d right)" % [left, right])
	# 30.10, 14:30 («воду — до реалистичной»): the pour is continuous clear streams (ribbons drawn with the water shader),
	# not separate sticks; they leave the lips on the left, hold together for a while, then tear into drops.
	var pr: Dictionary = ww.probe()
	_check(int(pr["streams"]) >= 4 and int(pr["stream_pts"]) > 60, "the buckets pour as streams: %d streams, %d parcels in them" % [int(pr["streams"]), int(pr["stream_pts"])])
	var streams_item = ww.get_node_or_null("Streams")
	_check(streams_item != null and streams_item.material is ShaderMaterial and (streams_item.material as ShaderMaterial).shader.resource_path.ends_with("wheel_water_ribbon.gdshader"),
		"the streams are drawn by the water shader (the background through them, a sky highlight)")
	var foam_item = ww.get_node_or_null("Foam")
	_check(foam_item != null and foam_item.material is ShaderMaterial, "the foam under the wheel is lace (noise shader), not flat discs")
	# Smooth at any frame rate: parcels that leave in one long frame get their own head start — never two on one spot
	# (a pile-up drew saw-tooth shards in the first try).
	var piled := 0
	var pairs := 0
	var on_left := 0
	var on_right := 0
	for key in ww.get("_streams"):
		var pts: Array = ww.get("_streams")[key]["pts"]
		for j in range(1, pts.size()):
			if bool(pts[j][6]) and bool(pts[j - 1][6]):
				pairs += 1
				if (pts[j][0] as Vector2).distance_to(pts[j - 1][0]) < 0.02:
					piled += 1
		for q in pts:
			if bool(q[6]):
				if (q[0] as Vector2).x < hub.x:
					on_left += 1
				else:
					on_right += 1
	_check(pairs > 40 and piled == 0, "no parcels piled on one spot in a stream (%d of %d neighbours)" % [piled, pairs])
	_check(on_left > 40 and on_right == 0, "the streams hang off the rising left side (%d left, %d right)" % [on_left, on_right])
	# A slow frame (as in the web build on a weak machine): one 0.05-s step lets several parcels out — they are spread
	# along their fall, not stacked.
	ww.call("_step", 0.05, false)
	piled = 0
	for key in ww.get("_streams"):
		var pts2: Array = ww.get("_streams")[key]["pts"]
		for j in range(1, pts2.size()):
			if bool(pts2[j][6]) and bool(pts2[j - 1][6]) and (pts2[j][0] as Vector2).distance_to(pts2[j - 1][0]) < 0.02:
				piled += 1
	_check(piled == 0, "after a 50-ms frame the new parcels are spread out too (%d piled)" % piled)
	# The pond let down: the wheel stands, nothing pours, the node is hidden.
	gs.set_flag("pond_lowered", true)
	await _frames(3)
	var q0 := int(ww.probe()["poured"])
	await create_timer(1.0).timeout
	_check(not ww.visible and not wheel.is_spinning() and int(ww.probe()["poured"]) == q0, "pond let down: the wheel stands, no water pours")
	# The epilogue picture: the cascade off the painted wheel runs.
	gs.set_flag("pond_lowered", false)
	await _enter("EP_pavel")
	var cas = rm.current_room.get_node_or_null("Ambient/Wheel/cascade")
	_check(cas is AmbientWheel, "EP_pavel: the cascade is drawn")
	if cas is AmbientWheel:
		var c0 := int(cas.probe()["poured"])
		await create_timer(1.0).timeout
		_check(int(cas.probe()["poured"]) - c0 > 150 and int(cas.probe()["landed"]) > 0, "EP_pavel: water falls off the buckets into the race (%s)" % str(cas.probe()))




# --- J-R11b. The boat follows the crossings ------------------------------------------------------

func _exit_vis(to: String) -> Node:
	for e in rm.current_room.get_exits():
		if String(e.target_room) == to:
			return e
	return null


func _test_boat_follows() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "house_unlocked", "ferry_verified", "rope_brought", "rope_on_ring", "road_held_both_ends", "done_M15", "done_M16", "boat_back_at_turn",
		"done_M17", "started_M18p", "done_M18p", "crossing_hauled", "done_M18", "evening_dusk", "done_M21b", "done_M22", "boat_shuttle_open", "morning_day3", "free_walk_day3"])
	# The free day begins with the boat at the turn: at the far pier no boat, and the way across says what it is —
	# pull the boat over by the rope (a rope ferry), not «К лодке» to a boat that is not there.
	await _enter("R3", "from_O4")
	await _drain()
	var ex = _exit_vis("R2")
	_check(not _layer_vis("boat_day") and not _layer_vis("boat_evening") and not _pel_vis() and ex != null and ex.visible
		and String(ex.call("label_text")) == "Подтянуть лодку по канату", "the boat at the turn: at the far pier no boat, «Подтянуть лодку по канату» (%s)" % (str(ex.call("label_text")) if ex != null else "no exit"))
	await _enter("Z3")
	await _drain()
	var zx = _exit_vis("R2")
	_check((_layer_vis("boat_day") or _layer_vis("boat_shuttle_dusk")) and zx != null and zx.visible and String(zx.call("label_text")) != "Подтянуть лодку по канату",
		"at the turn: the boat and «В лодку»")
	# Across along the rope (the close-up's own event): the boat comes with Agata; Pelageya stays at the turn (T9).
	sr.open_mechanic(zx.data["mechanic"], "exit_R2")
	await _frames(3)
	sr.mechanic_event("crossed")
	var g := 0
	while (rm.current_room == null or rm.current_room.room_id != "R3") and g < 600:
		g += 1
		await process_frame
	await _frames(30)
	await _drain()
	ex = _exit_vis("R2")
	_check(gs.has_flag("boat_at_far") and rm.current_room.room_id == "R3" and (_layer_vis("boat_day") or _layer_vis("boat_evening")) and not _pel_vis()
		and ex != null and ex.visible and String(ex.call("label_text")) == "К лодке", "across: at the far pier the boat and «К лодке»; Pelageya waits at the turn")
	if ex != null:
		var lb := _layer_box("boat_day") if _layer_vis("boat_day") else _layer_box("boat_evening")
		_check(lb.size.x > 0.0 and Rect2(Vector2(1150, 760), Vector2(640, 300)).intersects(lb), "«К лодке» is over the boat by the rope's post (boat %s)" % str(lb))
	# Back: the boat goes to the turn again; there «Подтянуть лодку» is gone, «В лодку» again.
	sr.open_mechanic(ex.data["mechanic"], "exit_R2")
	await _frames(3)
	sr.mechanic_event("crossed")
	g = 0
	while (rm.current_room == null or rm.current_room.room_id != "Z3") and g < 600:
		g += 1
		await process_frame
	await _frames(30)
	_check(not gs.has_flag("boat_at_far") and rm.current_room.room_id == "Z3" and (_layer_vis("boat_day") or _layer_vis("boat_shuttle_dusk")), "back: the boat at the turn again")
	gs.reset()

func _test_beam_agata() -> void:
	var lay: Dictionary = {}
	for l in sd.room("EP_beam").get("layers", []):
		if (l.get("if", []) as Array).has("beam_dunya"):
			lay = l
	_check(String(lay.get("image", "")).ends_with("cut_agata.png") and ResourceLoader.exists(String(lay.get("image", ""))),
		"the «Агата» choice draws cut_agata.png (%s)" % str(lay.get("image", "")))
	_check(sd.text("@EP.beam.written_dunya") == "Агата", "and the word is «Агата»")


func _test_paper_sway() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M21", "house_unlocked", "met_nina"])
	await _enter("O3")
	await _drain()
	var hv := _hotspot("nina_letters")
	_check(hv != null, "O3: Nina's letters")
	if hv == null:
		return
	sr.open_view(hv.data["view"], "nina_letters")
	await _frames(10)
	var cv: Node = main_node.get_node("CloseupView")
	cv.call("turn_page", 1)   # page 1 is the bundle on the table; a letter in the hands comes next
	await _frames(10)
	var sheet: Control = null
	for sh in cv.get("sheets"):
		if (sh as Control).get_node_or_null("Sway") != null and (sh as Control).is_visible_in_tree():
			sheet = sh
	_check(sheet != null, "a letter held in the hands has the sway")
	if sheet == null:
		return
	var rots: Array[float] = []
	var mids: Array[Vector2] = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		rots.append(rad_to_deg(sheet.rotation))
		mids.append(sheet.get_global_transform() * (sheet.size * 0.5))
		await process_frame
	var span: float = rots.max() - rots.min()
	var drift := 0.0
	for m in mids:
		drift = maxf(drift, m.distance_to(mids[0]))
	_check(span >= 0.5 and span <= 2.0, "it turns enough to be seen: %.2f° over 4 s" % span)
	_check(drift <= 9.0, "about its middle — the middle moves only %.1f px (no swinging from a corner)" % drift)
	sr.close_view()


func _test_night_asleep() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	_set_flags(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "done_M04", "done_M05", "done_M07", "done_M08", "h3_night_to_bed"])
	await _enter("H1")
	_check(sr.start_scene("N01"), "N01 starts")
	var at_sleep := ""
	var morning_seen := false
	var g := 0
	while g < 3000 and not gs.has_flag("done_N01"):
		g += 1
		var b: Dictionary = sr.current_beat
		if not b.is_empty() and not sr.is_staging():
			var t := String(b.get("text", ""))
			if t.begins_with("Спи уж") and at_sleep == "":
				at_sleep = "hidden" if not rm.player.visible else "visible"
			if t.begins_with("Ты с утра"):
				morning_seen = rm.player.visible
			sr.advance()
		await process_frame
	_check(at_sleep == "hidden", "at «Спи уж» Agata is not standing by the stove (%s)" % at_sleep)
	_check(morning_seen and rm.player.visible and gs.has_flag("done_N01"), "in the morning she is up again")


func _test_tikhon_bench() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/tikhon.json"))
	var after: Dictionary = {}
	var shelf: Dictionary = {}
	for p in cfg.get("place", {}).get("H1", []):
		if (p.get("if", []) as Array).has("tikhon_knows_dunya"):
			after = p
		elif (p.get("if", []) as Array).has("q04_corner_stove"):
			shelf = p
	var f: Array = after.get("feet", [0, 0])
	_check(not after.is_empty() and float(f[1]) >= float(shelf.get("feet", [0, 9999])[1]), "not higher than his shelf (feet y %s vs %s)" % [str(f[1]), str(shelf.get("feet", [0, 0])[1])])
	# The bench (лежанка) in front of the stove: its seat x 420–800, y ≈ 560–640 on screen (rooms/H1.json, the scarf on it).
	_check(float(f[0]) >= 420.0 and float(f[0]) <= 800.0 and float(f[1]) >= 560.0 and float(f[1]) <= 640.0, "on Agata's bench by the stove (feet %s)" % str(f))

