extends SceneTree
## Headless tests of the reworked optional stories (partia H, Director 24.10):
##   H47 — Q02 «На карте вырос сад»: Ulyana stays in the class (never hidden, never on the street), tells the way at the
##         map; the close-up: three places of the map shown by real clicks in order (school → Ulya's house → garden) —
##         each right one coloured, a wrong one (another house, or out of turn) — her word and everything uncoloured;
##         the garden of the tracing comes up, «Там теперь смородина», the choice at once; BOTH choices A and B to the
##         end (flags, Ulyana's reaction, look text, epilogue lines); save/load midway and after — nothing replays.
##   H48 — Q06 «Второй верстак»: the goal on screen, one hint line per step, every action a real mouse drag onto the lit
##         place: the wedge sits, wobbles and glides home (Ilya's word); a part let go elsewhere glides home; the key, the
##         stop block, the screw settle; the screw turned by driving the mouse round its handle (let go midway — kept);
##         the board on the bench — «Держит», the choice at once; BOTH choices A and B to the end (flags, lines, the shed
##         door on the street / the bench in Dunya's workshop); save/load midway reopens on the same step.
## Usage: godot --headless --audio-driver Dummy --path game -s res://tests/test_q02_q06.gd
## Exit code 0 only when every check passed.

var SLOT := "test_q0206_%d" % OS.get_process_id()
var AUTOSAVE := "test_q0206_auto_%d" % OS.get_process_id()
var CP := "testq0206_%d_" % OS.get_process_id()

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node = null
var mv: Node = null
var player: Node2D = null
var _results: Array = []
var _fails: Array[String] = []
var _reached_end: bool = false


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	_reached_end = false
	var started := Time.get_ticks_msec()
	await fn.call()
	if not _reached_end:
		_fails.append("the test did not reach its end (script error above)")
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
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_slot = AUTOSAVE
	rm.checkpoint_prefix = CP
	mv = main_node.get_node("MechanicView")
	player = main_node.get_node("World/Player")
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	await _test("H47 data: the way of three places in order, decoys, Ulyana never sent off, texts", _test_q02_data)
	await _test("H47 Q02: the way by clicks — right ones coloured, wrong resets, save/load midway, choice A to the end", _test_q02_a)
	await _test("H47 Q02: choice B to the end — the tracing to Ulyana, her reaction, the look, once", _test_q02_b)
	await _test("H48 data: five steps, parts from the 10b art, zones, one hint per step", _test_q06_data)
	await _test("H48 Q06: drags onto lit places, wrong part / wrong place glide home, turning, save/load, choice A", _test_q06_a)
	await _test("H48 Q06: choice B to the end — the bench in Dunya's workshop", _test_q06_b)
	await _test("H47/H48 traces: epilogue lines by both choices of each story", _test_traces)
	gs.reset()
	for s in [AUTOSAVE, SLOT + "_q02_mid", SLOT + "_q02_done", SLOT + "_q06_mid", CP + "day3", CP + "day4"]:
		gs.delete_save(s)
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== q02_q06: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2, pressed: bool = false) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	if pressed:
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)
	await _frames(1)


func _button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(1)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, true)
	await _button(at, false)


## A real drag: press at `a`, move in small steps to `b`, let go.
func _drag(a: Vector2, b: Vector2) -> void:
	await _move(a)
	await _button(a, true)
	var n := maxi(2, int(a.distance_to(b) / 18.0))
	for i in n:
		await _move(a.lerp(b, float(i + 1) / n), true)
	await _button(b, false)
	await _frames(2)


func _v(d) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0))) if d is Dictionary else Vector2.ZERO


func _staging_done() -> void:
	var g := 0
	while sr.is_staging() and g < 4000:
		await process_frame
		g += 1


func _finish(choices: Array = []) -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	await _staging_done()
	while not sr.current_beat.is_empty() and guard < 300:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", "")).left(60)])
			sr.advance()
		await process_frame
		await _staging_done()
	await _frames(2)
	return seen


func _wait(cond: Callable, frames: int = 600) -> bool:
	var g := 0
	while not cond.call() and g < frames:
		await process_frame
		g += 1
	return cond.call()


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


func _room() -> String:
	return rm.current_room.room_id if rm.current_room != null else ""


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _use(id: String) -> bool:
	var h := _hotspot(id)
	if h == null or not h.visible:
		_check(false, "hotspot %s missing or hidden in %s" % [id, _room()])
		return false
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


func _go(target: String) -> bool:
	var e = rm.current_room.get_node_or_null("Exits/to_" + target) if rm.current_room != null else null
	if e == null:
		_check(false, "no exit %s→%s" % [_room(), target])
		return false
	var before := _room()
	player.call("click_at", e.global_position)
	await _wait_idle()
	var frames := 0
	while _room() == before and sr.current_beat.is_empty() and frames < 90:
		await process_frame
		frames += 1
	await _frames(2)
	return _room() == target


func _route(rooms: Array) -> bool:
	for r in rooms:
		if not await _go(String(r)):
			_check(false, "route stopped at %s → %s" % [_room(), r])
			return false
		await _finish()
	return true


func _panel() -> Dictionary:
	return mv.probe().get("panel", {})


func _layer_visible(id: String) -> bool:
	for box in ["Layers", "Occluders"]:
		var n = rm.current_room.get_node_or_null(box + "/" + id) if rm.current_room != null else null
		if n != null:
			return (n as CanvasItem).visible
	return false


func _room_hotspot(room_id: String, id: String) -> Dictionary:
	for h in sd.room(room_id).get("hotspots", []):
		if String(h.get("id", "")) == id:
			return h
	return {}


# --- H47: Q02 ----------------------------------------------------------------------------------

func _test_q02_data() -> void:
	var hm := _room_hotspot("O1", "village_map")
	var m: Dictionary = hm.get("mechanic", {})
	_check(String(m.get("type", "")) == "map_route", "the map close-up is the way by clicks (map_route), not the pencil tracing (%s)" % m.get("type"))
	var way: Array = []
	var decoys := 0
	for p in m.get("places", []):
		if p.has("order"):
			way.append(p)
		else:
			decoys += 1
	way.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	_check(way.map(func(p): return String(p["id"])) == ["school", "ilya_house", "garden"], "the way: school → Ulya's house → the garden (%s)" % str(way.map(func(p): return p["id"])))
	_check(decoys >= 8, "other places to choose wrongly — houses, the mill, the bridge (%d)" % decoys)
	# the order is told before it is asked: Ulyana's words at the map name it, and the hint repeats it
	var said := ""
	for k in hm.get("use", {}).get("text", []):
		said += sd.text(String(k)) + " "
	_check(said.contains("От школы") and said.contains("дома") and said.contains("сад"), "Ulyana tells the way before the close-up: %s" % said)
	var hint: String = sd.text(String(m.get("texts", {}).get("label_hint", "")))
	_check(hint.contains("школа") and hint.contains("дом") and hint.contains("сад") and hint.contains("сначала"), "the hint: the order and «wrong — from the start»: %s" % hint)
	# Ulyana: no hiding in the class, no stand-in on the street
	var u := _room_hotspot("O1", "ulyana")
	_check(not u.has("hidden_when") and not u.has("hidden_if"), "Ulyana is not hidden in the class during Q02 (%s)" % str(u.get("hidden_when", u.get("hidden_if", ""))))
	_check(_room_hotspot("O4", "ulyana").is_empty(), "no Ulyana appearing on the street O4 for Q02")
	_reached_end = true


func _q02_open() -> void:
	_check(rm.start_at("freewalk"), "start: the free day (the class after M22)")
	await _frames(3)
	await _finish()
	_check(_room() == "O1", "in the class (%s)" % _room())


func _place(id: String) -> Vector2:
	return _v(_panel().get("places", {}).get(id, {}))


func _coloured() -> Array:
	return _panel().get("coloured", [])


## Click the three places of the way in order (from a fresh start of the way).
func _q02_route() -> void:
	for id in ["school", "ilya_house", "garden"]:
		await _click(_place(id))
		await _wait(func(): return _coloured().has(id), 120)


func _test_q02_a() -> void:
	Engine.time_scale = 2.0
	await _q02_open()
	var u := _hotspot("ulyana")
	_check(u != null and u.visible, "Ulyana studies in the class")
	await _use("village_map")
	var seen := await _finish()
	_check(gs.has_flag("q02_seen_map") and seen.any(func(x): return x.begins_with("agata:Всем классом эту карту")), "Agata knows the map: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("ulyana:Да это наш сад")) and seen.any(func(x): return x.begins_with("ulyana:От школы")),
		"Ulyana, there in the class: «Это же наш сад!» and the way «От школы — … до нашего дома … сад»: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("agata:Тогда [[пособи|помоги]] мне его найти")), "«Тогда помоги мне его найти»")
	_check(_hotspot("ulyana").visible, "Ulyana stays in the class — she does not vanish")
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "map_route", "the map close-up opens on the way")
	var pr := _panel()
	_check(String(pr.get("phase", "")) == "route" and int(pr.get("found", -1)) == 0 and _coloured().is_empty(), "nothing coloured yet (%s)" % str(pr.get("coloured")))
	_check(bool(pr.get("art", false)) and bool(pr.get("sheet_visible", false)), "the drawn map with the tracing sheet over it")
	_check(String(pr.get("hint", "")).contains("школа"), "the hint names the order: %s" % pr.get("hint"))
	# A wrong place first: Ulyana's word, nothing coloured.
	await _click(_place("house_n1"))
	seen = await _finish()
	_check(int(_panel().get("wrong", 0)) == 1 and seen.any(func(x): return x.begins_with("ulyana:Не туда")), "a wrong house: Ulyana «Не там! Давай сначала…»: %s" % str(seen))
	# A click where there is no place does nothing.
	await _click(Vector2(120, 1000))
	await _frames(2)
	_check(int(_panel().get("wrong", 0)) == 1 and sr.current_beat.is_empty(), "a click beside every place does nothing")
	# The school: coloured, number 1.
	await _click(_place("school"))
	await _wait(func(): return _coloured().has("school"), 120)
	_check(int(_panel().get("found", 0)) == 1 and _coloured() == ["school"], "the school — coloured (%s)" % str(_coloured()))
	# Out of turn (the garden before the house): everything uncoloured, the way from the start.
	await _click(_place("garden"))
	seen = await _finish()
	await _wait(func(): return _coloured().is_empty(), 120)
	pr = _panel()
	_check(int(pr.get("wrong", 0)) == 2 and int(pr.get("found", -1)) == 0 and _coloured().is_empty(), "out of turn: all uncoloured, found 0 (%s)" % str(pr.get("coloured")))
	_check(seen.any(func(x): return x.begins_with("ulyana:Не здесь. Давай опять")), "a second wrong: the short word: %s" % str(seen))
	# School and house, then put away midway: saved; reopened from the start of the way, the first words not again.
	await _click(_place("school"))
	await _click(_place("ilya_house"))
	await _wait(func(): return _coloured().size() == 2, 120)
	_check(_coloured().size() == 2 and int(_panel().get("found", 0)) == 2, "school, house — two coloured (%s)" % str(_coloured()))
	sr.close_mechanic()
	await _frames(3)
	_check(rm.save_game(SLOT + "_q02_mid"), "save in the middle of Q02")
	await _use("village_map")
	seen = await _finish()
	_check(sr.mechanic_open and not seen.any(func(x): return x.contains("эту карту")), "reopened: the close-up again, the first words not repeated: %s" % str(seen))
	_check(int(_panel().get("found", -1)) == 0, "reopened: the way from the start (nothing to lose — three clicks)")
	await _q02_route()
	_check(_coloured().size() == 3, "all three coloured (%s)" % str(_coloured()))
	await _wait(func(): return not sr.current_beat.is_empty() or gs.has_flag("q02_traced"), 400)
	_check(bool(_panel().get("tracing_visible", false)) or gs.has_flag("q02_traced"), "the garden of the tracing comes up on the plot")
	seen = await _finish(["A"])
	_check(gs.has_flag("q02_traced") and seen.any(func(x): return x.contains("Нынче там смородина")), "«Там теперь смородина»: %s" % str(seen))
	_check(seen.any(func(x): return x.begins_with("ulyana:Ещё яблоня")), "Ulyana: «И яблоня!»")
	_check(seen.any(func(x): return x == "options:A"), "the choice at once after the way")
	_check(gs.has_flag("q02_old_under_new") and not gs.has_flag("q02_new_primary") and gs.has_flag("done_Q02"), "A — the tracing over the old map; Q02 done")
	_check(seen.any(func(x): return x.contains("Старое под новым")) and seen.any(func(x): return x.begins_with("ulyana:Пусть висит")), "A: Agata's line and Ulyana's reaction: %s" % str(seen))
	_check(not sr.mechanic_open and _hotspot("ulyana").visible, "the close-up put away, Ulyana still in the class")
	await _use("village_map")
	seen = await _finish()
	_check(not sr.mechanic_open and seen.any(func(x): return x.contains("калька, на ней Ильин сад")) and not seen.any(func(x): return x.begins_with("options")), "once: afterwards the map is only looked at: %s" % str(seen))
	_check(rm.save_game(SLOT + "_q02_done"), "save after Q02")
	_check(rm.load_game(SLOT + "_q02_done"), "load after Q02")
	await _frames(4)
	_check(sr.current_beat.is_empty() and not sr.mechanic_open and gs.has_flag("done_Q02") and not sr.can_start("Q02"), "load after Q02: nothing replays, never again")
	Engine.time_scale = 1.0
	_reached_end = true


func _test_q02_b() -> void:
	Engine.time_scale = 2.0
	_check(rm.load_game(SLOT + "_q02_mid"), "load the middle of Q02 (map seen, the way not shown)")
	await _frames(4)
	_check(sr.current_beat.is_empty() and not sr.mechanic_open, "load mid-way: nothing replays")
	_check(gs.has_flag("q02_seen_map") and not gs.has_flag("q02_traced") and _hotspot("ulyana").visible, "load mid-way: the map seen, Ulyana in the class")
	await _use("village_map")
	await _finish()
	_check(sr.mechanic_open, "the map close-up again")
	await _q02_route()
	await _wait(func(): return not sr.current_beat.is_empty() or gs.has_flag("q02_traced"), 400)
	var seen := await _finish(["B"])
	_check(seen.any(func(x): return x == "options:B"), "choice B: %s" % str(seen))
	_check(gs.has_flag("q02_new_primary") and not gs.has_flag("q02_old_under_new") and gs.has_flag("done_Q02"), "B — the tracing to Ulyana; Q02 done")
	_check(seen.any(func(x): return x.contains("Ульяне отдам")) and seen.any(func(x): return x.begins_with("ulyana:Моя карта")), "B: Agata gives it, Ulyana: «Моя карта! Повешу дома у двери…»: %s" % str(seen))
	_check(not seen.any(func(x): return x.contains("Старое под новым") or x.contains("Пусть висит")), "B: no A lines")
	_check(_hotspot("ulyana").visible, "Ulyana still in the class (with her map)")
	await _use("village_map")
	seen = await _finish()
	_check(not sr.mechanic_open and seen.any(func(x): return x.contains("Ульяне отдали")) and not seen.any(func(x): return x.begins_with("options")), "B, once: the map without the tracing — it is Ulyana's now: %s" % str(seen))
	Engine.time_scale = 1.0
	_reached_end = true


# --- H48: Q06 ----------------------------------------------------------------------------------

func _test_q06_data() -> void:
	var m: Dictionary = _room_hotspot("O4", "ilya_workshop").get("mechanic", {})
	_check(String(m.get("type", "")) == "workbench" and (m.get("steps", []) as Array).size() == 5, "five steps (%s)" % str(m.get("steps")))
	_check(String(m.get("art", {}).get("bg", "")).ends_with("closeup_second_bench_clean.png") and ResourceLoader.exists(String(m.get("art", {}).get("bg", ""))), "the clean bench of batch 10b")
	for id in ["wedge", "key", "stop", "screw", "board"]:
		var p: Dictionary = m.get("parts", {}).get(id, {})
		_check(String(p.get("image", "")).ends_with("bench_part_%s.png" % id) and ResourceLoader.exists(String(p.get("image", ""))), "part %s — its own layer of batch 10b" % id)
	for i in range(1, 6):
		var h: String = sd.text(String(m.get("texts", {}).get("label_hint%d" % i, "")))
		_check(h != "" and not h.contains("\n") and h.length() < 110, "step %d: one line of hint (%s)" % [i, h])
	_check(sd.text(String(m.get("texts", {}).get("label_goal", ""))).contains("Ули"), "the goal names what and for whom")
	var said := ""
	for k in _room_hotspot("O4", "ilya_workshop").get("use", {}).get("text", []):
		said += sd.text(String(k)) + " "
	_check(said.contains("верстак") and said.contains("Уля"), "the goal is told before the close-up: %s" % said)
	_check(not m.has("timing"), "no «точный удар» bar on the bench any more (turning by the mouse)")
	_reached_end = true


func _q06_open() -> void:
	_check(rm.start_at("freewalk"), "start: the free day")
	await _frames(3)
	await _finish()
	_check(await _route(["O2", "O4"]), "class → yard → street")


func _part(id: String) -> Vector2:
	return _v(_panel().get("parts", {}).get(id, {}))


func _wait_free() -> void:
	await _wait(func(): return not bool(_panel().get("busy", true)) or not sr.current_beat.is_empty(), 300)


func _drag_to_target(id: String) -> void:
	await _wait_free()
	await _drag(_part(id), _v(_panel().get("target", {})))


## Drive the mouse round the screw's handle `turns` times (pressed all the way), then let go.
func _turn(turns: float) -> void:
	var t: Dictionary = _panel().get("turn", {})
	var c := _v(t.get("pivot", {}))
	var r := float(t.get("radius", 100.0))
	var ry := float(t.get("radius_y", r))
	var a0 := 0.0
	var start := c + Vector2(cos(a0) * r, sin(a0) * ry)
	await _move(start)
	await _button(start, true)
	var n := int(turns * 32.0)
	var last := start
	for i in n:
		var a := a0 + TAU * turns * float(i + 1) / n
		last = c + Vector2(cos(a) * r, sin(a) * ry)
		await _move(last, true)
		if gs.has_flag("q06_vise_tight"):
			break
	await _button(last, false)
	await _frames(2)


func _test_q06_a() -> void:
	Engine.time_scale = 1.0
	await _q06_open()
	_check(not _layer_visible("bench_shed"), "the shed door is shut before the choice")
	await _use("ilya_workshop")
	var seen := await _finish()
	_check(seen.any(func(x): return x.begins_with("mitya:За одним верстаком и вдвоём тесно")) and seen.any(func(x): return x.begins_with("ilya:А мы ещё и третьему место")) and seen.any(func(x): return x.begins_with("ilya:Уля давно")),
		"Mitya / Ilya / the goal — a bench for Ulya: %s" % str(seen))
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "workbench", "the second bench close-up")
	var pr := _panel()
	_check(int(pr.get("step", -1)) == 0 and String(pr.get("goal", "")).contains("Ули") and String(pr.get("hint", "")) != "" and String(pr.get("step_text", "")).contains("1 из 5"), "step 1: goal, step and one hint on screen (%s / %s)" % [pr.get("step_text"), pr.get("hint")])
	_check(bool(pr.get("art_parts", false)) and not bool(pr.get("stand_in", true)), "all parts drawn from the 10b layers")
	_check(bool(pr.get("zone_visible", false)) and not bool(pr.get("ghost_visible", true)), "step 1: the groove lit, no ghost (which fastening fits is the question)")
	var home_wedge := _v(pr["parts"]["wedge"]["home"])
	var home_key := _v(pr["parts"]["key"]["home"])
	# The wedge into the groove: it sits, wobbles, glides home; Ilya says why.
	await _drag_to_target("wedge")
	await _wait(func(): return not sr.current_beat.is_empty(), 300)
	seen = await _finish()
	await _wait(func(): return not bool(_panel().get("busy", true)), 300)
	pr = _panel()
	_check(int(pr.get("step", -1)) == 0 and int(pr.get("tries_wrong", 0)) == 1 and seen.any(func(x): return x.contains("болтаться")), "the wedge does not fit — Ilya: «…болтаться будет»: %s" % str(seen))
	_check(_v(pr["parts"]["wedge"]["at"]).distance_to(home_wedge) < 3.0, "the wedge glided back to where it lay")
	# The key let go away from the groove: glides home, nothing else.
	await _drag(_part("key"), Vector2(900, 800))
	await _wait(func(): return not bool(_panel().get("busy", true)), 300)
	pr = _panel()
	_check(int(pr.get("returns", 0)) == 1 and int(pr.get("step", -1)) == 0 and sr.current_beat.is_empty(), "let go elsewhere — no penalty, no words")
	_check(_v(pr["parts"]["key"]["at"]).distance_to(home_key) < 3.0, "the key glided back home")
	# While dragged over the groove the place lights up.
	await _wait_free()
	var a := _part("key")
	var b := _v(_panel().get("target", {}))
	await _move(a)
	await _button(a, true)
	for i in 12:
		await _move(a.lerp(b, float(i + 1) / 12.0), true)
	_check(String(_panel().get("dragging", "")) == "key" and bool(_panel().get("over_target", false)), "over the groove: the place glows brighter")
	await _button(b, false)
	await _wait(func(): return gs.has_flag("q06_fastening_fit"), 300)
	seen = await _finish()
	_check(gs.has_flag("q06_fastening_fit") and int(_panel().get("step", -1)) == 1 and seen.any(func(x): return x.contains("шпонка")), "the key sits — step 2: %s" % str(seen))
	# Put away midway; saved; opens again at the same step, the key in its seat, without the first words.
	sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLOT + "_q06_mid") and rm.load_game(SLOT + "_q06_mid"), "save/load in the middle of the bench")
	await _frames(4)
	_check(sr.current_beat.is_empty() and not sr.mechanic_open, "load mid-way: nothing replays")
	await _use("ilya_workshop")
	seen = await _finish()
	pr = _panel()
	_check(sr.mechanic_open and int(pr.get("step", -1)) == 1 and not seen.any(func(x): return x.contains("не поместиться")), "reopened at the same step, the first words not repeated: %s" % str(seen))
	_check(_v(pr["parts"]["key"]["at"]).distance_to(_v(pr["parts"]["key"]["home"])) < 3.0 and _v(pr["parts"]["key"]["home"]).distance_to(home_key) > 100.0, "the key stays in the groove after the load")
	_check(bool(pr.get("ghost_visible", false)), "step 2: the stop block's place shown")
	await _q06_rest("A")
	seen = _last_seen
	_check(gs.has_flag("q06_table_at_ilya") and not gs.has_flag("q06_table_at_agata") and gs.has_flag("done_Q06"), "A — the bench stays at Ilya's; Q06 done")
	_check(seen.any(func(x): return x.begins_with("mitya:Вот и втроём")) and seen.any(func(x): return x.contains("полку уж вместе")), "A: Mitya and Ilya after the choice: %s" % str(seen))
	_check(not sr.mechanic_open and _layer_visible("bench_shed"), "A: the shed door on the street is open, the bench inside")
	await _use("ilya_workshop")
	seen = await _finish()
	_check(not sr.mechanic_open and seen.any(func(x): return x.contains("второй верстак")) and not seen.any(func(x): return x.begins_with("options")), "once: afterwards the workshop is only looked at: %s" % str(seen))
	_reached_end = true


var _last_seen: Array[String] = []


## From step 2 (the key in) to the choice: the stop block, the screw, the turning, the board.
func _q06_rest(choice: String) -> void:
	await _drag_to_target("stop")
	await _wait(func(): return gs.has_flag("q06_stop_in"), 300)
	await _finish()
	_check(gs.has_flag("q06_stop_in") and int(_panel().get("step", -1)) == 2, "the stop block in — step 3")
	await _drag_to_target("screw")
	await _wait(func(): return gs.has_flag("q06_screw_set"), 300)
	var seen := await _finish()
	var pr := _panel()
	_check(gs.has_flag("q06_screw_set") and int(pr.get("step", -1)) == 3 and not pr.get("turn", {}).is_empty(), "the screw on its place — step 4: turn it (%s)" % str(seen))
	_check(String(pr.get("hint", "")).contains("по кругу"), "the hint says how: round and round (%s)" % pr.get("hint"))
	# Half the turning, let go: kept.
	await _turn(0.9)
	pr = _panel()
	var half := float(pr.get("turn", {}).get("progress", 0.0))
	_check(half > 0.3 and half < 0.7 and not gs.has_flag("q06_vise_tight"), "let go midway: the turns done are kept (%.2f)" % half)
	await _turn(1.4)
	await _wait(func(): return gs.has_flag("q06_vise_tight"), 300)
	seen = await _finish()
	_check(gs.has_flag("q06_vise_tight") and int(_panel().get("step", -1)) == 4 and seen.any(func(x): return x.contains("Туго")), "two turns: tight — step 5: %s" % str(seen))
	await _drag_to_target("board")
	await _wait(func(): return not sr.current_beat.is_empty() or gs.has_flag("q06_bench_built"), 400)
	_last_seen = await _finish([choice])
	_check(gs.has_flag("q06_bench_built") and _last_seen.any(func(x): return x.contains("Держит")), "the board on the bench — it holds: %s" % str(_last_seen))
	_check(_last_seen.any(func(x): return x == "options:" + choice), "the choice comes at once")


func _test_q06_b() -> void:
	_check(rm.load_game(SLOT + "_q06_mid"), "load the middle of the bench (the key in)")
	await _frames(4)
	_check(not gs.has_flag("done_Q06") and gs.has_flag("q06_fastening_fit") and not gs.has_flag("q06_stop_in"), "the load: step 2, nothing beyond")
	await _use("ilya_workshop")
	await _finish()
	_check(sr.mechanic_open and int(_panel().get("step", -1)) == 1, "the close-up on step 2")
	await _q06_rest("B")
	var seen := _last_seen
	_check(gs.has_flag("q06_table_at_agata") and not gs.has_flag("q06_table_at_ilya") and gs.has_flag("done_Q06"), "B — the bench to Dunya's workshop; Q06 done")
	_check(seen.any(func(x): return x.contains("Дуниной мастерской")) and not seen.any(func(x): return x.contains("втроём")), "B: Ilya's line, no A lines: %s" % str(seen))
	_check(not _layer_visible("bench_shed"), "B: the shed door on the street stays shut")
	_check(await _route(["O2", "O1", "H3", "H1", "H2"]), "through the school door to Dunya's workshop")
	await _finish()
	_check(_layer_visible("second_bench") and _hotspot("second_bench") != null and _hotspot("second_bench").visible, "H2: the second bench stands in the workshop")
	_reached_end = true


func _test_traces() -> void:
	for pair in [[["q02_old_under_new", "q06_table_at_ilya"], ["Нина детям показывает, как место менялось", "чинит. Рядом сохнет их полка"]],
			[["q02_new_primary", "q06_table_at_agata"], ["Ульяна по нему растолковывает гостю дорогу", "рамку для семейного снимка"]]]:
		gs.reset()
		for f in pair[0]:
			gs.set_flag(String(f), true)
		var all := ""
		for ln in sd.scene("M26").get("mandatory_lines", []):
			if ln.has("options"):
				continue
			if sr.beat_allowed(ln):
				all += String(ln.get("text", "")) + "\n"
			for t in ln.get("then", []):
				if sr.beat_allowed(t):
					all += String(t.get("text", "")) + "\n"
		for want in pair[1]:
			_check(all.contains(want), "%s: the epilogue says «%s»" % [str(pair[0]), want])
	gs.reset()
	_reached_end = true
