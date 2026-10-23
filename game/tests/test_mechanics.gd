extends SceneTree
## Headless tests of the shared mechanics of the Director's notes 23.10 (Docs/FEEDBACK_DIRECTOR_2026-10-23.md,
## F4–F9). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_mechanics.gd
## What is proved:
##   - «Точный удар» (TimingLogic / TimingBar): N hits in a row finish it; a miss resets the series, holds the
##     marker while the consequence plays, then it can be done — no dead end; «медленнее» slows the sweep and is
##     kept in user://settings.cfg next to the volumes; a real click and the Space key strike; nothing moves or
##     strikes while a text is on screen;
##   - «Протянуть узел» (KnotPath): the end follows the pointer only along the stroke; off the path or let go in
##     the middle — it slips back to the stroke's start, finished strokes stay; no shortcut across the knot;
##   - «Рассмотреть» (F9): every inventory item the built game can give has items.json `examine` with Agata's
##     line and a picture (its art, or the icon — listed); each opens full screen from the bag, a double click or
##     the magnifier opens it, a single click still takes the item in hand; Esc / click / «Закрыть» close it;
##     inside an open close-up it is on top and Esc closes only it; a load closes it;
##   - mother's mirror (F4): Nina's clock beside the glass goes twenty times faster — the minute hand round in
##     three real minutes, the hour hand twelve times slower, the pendulum swings visibly; Agata's watch is not
##     there until she holds it to the glass from the bag; then both go and after compare_s the realisation
##     (the flag of M15а, its lines); another item does nothing; save/load: compared stays compared.
## Exit code 0 only when every check passed.

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node = null
var ui: Node = null
var mv: Node = null
var ex: Node = null
var player: Node2D = null
var _results: Array = []
var _fails: Array[String] = []
var _reached_end: bool = false
var SLOT := "test_mech_%d" % OS.get_process_id()
var SETTINGS := "user://test_mech_settings_%d.cfg" % OS.get_process_id()
## Scripts that use autoloads are loaded at run time (autoloads do not exist yet when -s compiles).
var _TB = null   # TimingBar
var _IB = null   # InventoryBag


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
	_TB = load("res://scripts/mechanics/timing_bar.gd")
	_IB = load("res://scripts/ui/inventory_bag.gd")
	_TB.settings_path = SETTINGS
	await _test("Logic: timing — N hits in a row; a miss resets the series and holds the marker, then it goes on", _test_timing_logic)
	await _test("Logic: knot path — along the stroke only; off it or let go: back to the stroke's start; no shortcut", _test_knot_logic)
	await _test("Setting «медленнее»: saved beside the volumes, read back, slows every bar", _test_slow_setting)
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	mv = main_node.get_node("MechanicView")
	ex = main_node.get_node("ItemExamine")
	player = main_node.get_node("World/Player")
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	await _test("Timing bar on screen: a real click and Space strike; nothing moves or strikes under a text", _test_timing_bar_input)
	await _test("Data: every inventory item the game gives has an examine view (Agata's line + art or icon)", _test_examine_data)
	await _test("Examine each item: full screen, its picture, Agata's line, closes by click", _test_examine_each)
	await _test("Bag: double click / magnifier opens it, single click still takes in hand; Esc; load closes it", _test_examine_bag)
	await _test("Mother's mirror (F4): the clock beside the glass goes 20×, the watch from the bag, the realisation", _test_fast_mirror)
	await _test("Examine inside a close-up: on top of it, Esc closes only the examine", _test_examine_over_mechanic)
	await _test("The plate (F5–F7): the brace by «точный удар» — a miss makes it jump off and resets; the knot drawn along the path — slips back, no penalty; textured rope; save/load", _test_plate)
	await _test("The shutter (F8): the latch caught up in the green opens it; dropped — again, nothing lost; then only a look", _test_latch)
	await _test("The crossing (F12, F15): ~10 pulls by click or drag toward herself; the far bank grows, fog thins, snow; no failure, no way out but across; then the far pier", _test_crossing)
	await _test("Living water (F14): every room that declares water builds it — ripple, trembling reflections, sparkles, flow lines from data", _test_water)
	gs.reset()
	gs.delete_save(SLOT)
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== mechanics: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(1)


func _button(at: Vector2, pressed: bool, double: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.double_click = double and pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(1)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, true)
	await _button(at, false)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await _frames(1)


func _v(d) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0))) if d is Dictionary else Vector2.ZERO


func _staging_done() -> void:
	var g := 0
	while sr.is_staging() and g < 2000:
		await process_frame
		g += 1


func _finish() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	await _staging_done()
	while not sr.current_beat.is_empty() and guard < 100:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")))
		else:
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", ""))])
			sr.advance()
		await process_frame
		await _staging_done()
	await _frames(2)
	return seen


func _fresh(items: Array = [], flags: Array = []) -> void:
	sr.close_examine()
	sr.close_mechanic()
	gs.reset()
	sr.call("_on_state_reset")
	for f in flags:
		gs.set_flag(String(f), true)
	for it in items:
		gs.add_item(String(it))
		gs.set_flag("has_" + String(it), true)
	await _frames(2)


## Inventory items the built game can give: their scene plays only in rooms in scope, or a hotspot gives them.
func _obtainable_items() -> Array[String]:
	var out: Array[String] = []
	for id in sd.items.keys():
		var it: Dictionary = sd.items[id]
		if not bool(it.get("inventory", false)):
			continue
		var ok := it.has("source_hotspot")
		var scn := String(it.get("source_scene", ""))
		if scn != "" and not sd.scene(scn).is_empty():
			ok = true
			for loc in sd.scene(scn).get("locations", []):
				if not sd.in_scope(String(loc)):
					ok = false
		if ok:
			out.append(String(id))
	return out


# --- Logic ---------------------------------------------------------------------------------

func _test_timing_logic() -> void:
	var t := TimingLogic.new({"hits": 3, "period_s": 2.0, "green": 0.2, "miss_s": 0.9, "hit_s": 0.25})
	_check(t.pos() == 0.0 and not t.in_green(t.pos()), "starts at the left end, in the red")
	t.step(0.5)   # a quarter of the sweep there and back → the middle
	_check(absf(t.pos() - 0.5) < 1e-6 and t.in_green(t.pos()), "after half a sweep the marker is in the green (%.3f)" % t.pos())
	_check(t.strike() == "hit" and t.hits == 1 and t.state == "hit", "a strike in the green is a hit")
	_check(t.strike() == "busy", "while the blow lands the next strike waits")
	var p0 := t.pos()
	t.step(0.2)
	_check(t.pos() == p0, "the marker holds a moment after a hit")
	t.step(0.1)
	_check(t.state == "run", "then it runs again")
	# Run on to the red and miss: the series is gone, the marker waits, then starts from the left end.
	while t.in_green(t.pos()):
		t.step(0.02)
	t.step(0.1)
	_check(t.strike() == "miss" and t.hits == 0 and t.misses == 1 and t.state == "miss", "a strike in the red: the series resets")
	t.step(0.5)
	_check(t.strike() == "busy" and t.state == "miss", "during the consequence nothing strikes")
	t.step(0.5)
	_check(t.state == "run" and t.pos() == 0.0, "after the consequence: from the left end again")
	# Three in a row → done (no dead end after any number of misses).
	var guard := 0
	while not t.done() and guard < 2000:
		guard += 1
		t.step(0.01)
		if t.state == "run" and absf(t.pos() - t.center) < 0.05:
			t.strike()
	_check(t.done() and t.total_hits >= 3 and t.hits == 3, "three hits in a row finish it (%d hits, %d misses)" % [t.total_hits, t.misses])
	_check(t.strike() == "done_already", "after done nothing more")
	# Edges and the slow setting.
	var e := TimingLogic.new({"hits": 1, "green": 0.2})
	_check(e.in_green(0.4) and e.in_green(0.6) and not e.in_green(0.39) and not e.in_green(0.61), "green zone 0.4–0.6")
	_check(e.warmth(0.5) == 1.0 and e.warmth(0.0) == 0.0 and e.warmth(0.3) > 0.0 and e.warmth(0.3) < 1.0, "warmth: red at the ends, amber near the green")
	var s := TimingLogic.new({"period_s": 2.0})
	s.slow_k = _TB.SLOW_K
	s.step(0.5)
	_check(s.pos() < 0.5 * 0.6, "slower: half a second moves the marker less (%.3f)" % s.pos())
	var g := TimingLogic.new({"period_s": 2.0, "green": 0.2})
	var wait := g.seconds_to_green()
	g.step(wait)
	_check(g.in_green(g.pos()), "seconds_to_green leads into the green (%.3f s → %.3f)" % [wait, g.pos()])
	_reached_end = true


func _test_knot_logic() -> void:
	var cfg := {"tolerance": 50, "grab_r": 60, "max_lead": 120,
		"strokes": [[[0, 0], [200, 0]], [[200, 0], [200, 200]], [[200, 200], [400, 200]]]}
	var k := KnotPath.new(cfg)
	_check(k.strokes.size() == 3 and not k.done() and k.end_point() == Vector2.ZERO, "three strokes, the end at the start")
	_check(not k.grab(Vector2(150, 0)), "a press far from the end does not take it")
	_check(k.grab(Vector2(20, 10)), "a press near the end takes it")
	_check(k.drag(Vector2(80, 20)) == "move" and absf(k.progress - 80.0) < 1.0, "the end follows along the stroke (%.1f)" % k.progress)
	_check(k.drag(Vector2(120, 140)) == "slip" and k.progress == 0.0 and k.stroke == 0 and k.slips == 1, "off the path: back to the stroke's start")
	_check(k.grab(Vector2(0, 0)) and k.drag(Vector2(100, 0)) == "move", "taken again")
	_check(k.release() == "slip" and k.progress == 0.0, "let go in the middle: it slips back")
	k.grab(Vector2(0, 0))
	_check(k.drag(Vector2(190, 0)) == "slip", "no jump ahead past max_lead (a shortcut is a slip)")
	k.grab(Vector2(0, 0))
	for x in [60, 120, 180, 200]:
		k.drag(Vector2(x, 5))
	_check(k.stroke == 1 and k.progress == 0.0 and k.grabbed, "first stroke done; the hand keeps the end")
	k.drag(Vector2(205, 100))
	k.drag(Vector2(260, 160))   # off the second stroke
	_check(k.stroke == 1 and k.progress == 0.0, "a slip on the second stroke keeps the first")
	_check(k.rope_points().size() >= 2 and k.rope_points()[k.rope_points().size() - 1] == Vector2(200, 0), "the rope is drawn along the finished stroke")
	k.grab(Vector2(200, 0))
	for y in [80, 160, 200]:
		k.drag(Vector2(200, y))
	for x in [300, 400]:
		k.drag(Vector2(x, 200))
	_check(k.done() and not k.grabbed and k.end_point() == Vector2(400, 200), "all three strokes: the knot is tied")
	_check(k.drag(Vector2(0, 0)) == "free" and k.done(), "after the knot nothing undoes it")
	var off := KnotPath.new({"strokes": [[[10, 10], [20, 10]]]}, Vector2(100, 50), 2.0)
	_check(off.strokes[0][0] == Vector2(120, 70) and off.strokes[0][1] == Vector2(140, 70), "canvas → screen: offset and scale")
	_reached_end = true


func _test_slow_setting() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music_volume", 0.42)
	cf.save(SETTINGS)
	_check(_TB.set_slow(true), "saved")
	_TB.slow = false
	_TB.load_settings(true)
	_check(_TB.slow, "read back on")
	var cf2 := ConfigFile.new()
	cf2.load(SETTINGS)
	_check(is_equal_approx(float(cf2.get_value("audio", "music_volume", 0.0)), 0.42), "the volumes stay in the same file")
	var bar = _TB.new()
	bar.setup({"period_s": 2.0})
	_check(is_equal_approx(bar.logic.slow_k, _TB.SLOW_K), "a new bar is slow")
	bar.free()
	_TB.set_slow(false)
	var bar2 = _TB.new()
	bar2.setup({"period_s": 2.0})
	_check(bar2.logic.slow_k == 1.0, "off again: normal speed")
	bar2.free()
	_reached_end = true


# --- Timing bar input --------------------------------------------------------------------------

func _test_timing_bar_input() -> void:
	await _fresh()
	var layer := CanvasLayer.new()
	layer.layer = 6
	root.add_child(layer)
	var bar = _TB.new()
	bar.position = Vector2(560, 500)
	bar.size = Vector2(800, 70)
	layer.add_child(bar)
	bar.setup({"hits": 2, "period_s": 2.0, "green": 0.2, "hint": "@ui.timing_hint"})
	var results: Array[String] = []
	bar.struck.connect(func(r): results.append(r))
	await _frames(2)
	_check(bar.hint != null and bar.hint.text.contains("Пробел"), "the bar says how: «%s»" % (bar.hint.text if bar.hint else ""))
	_check(bar.slow_check != null and bar.slow_check.text != "", "«медленнее» right beside the bar")
	bar.logic.phase = 0.25   # the middle
	await _click(bar.get_global_rect().get_center())
	_check(results == ["hit"], "a real click in the green is a hit (%s)" % str(results))
	await create_timer(0.3).timeout
	bar.logic.phase = 0.25
	await _key(KEY_SPACE)
	_check(results == ["hit", "done"], "Space strikes too; two in a row — done (%s)" % str(results))
	# Under a text nothing moves or strikes.
	var b2 = _TB.new()
	b2.size = Vector2(400, 60)
	layer.add_child(b2)
	b2.setup({"hits": 1})
	sr.narrate("Проверка: текст на экране.")
	await _frames(1)
	var p0: float = b2.logic.pos()
	await _frames(10)
	_check(b2.logic.pos() == p0 and b2.strike() == "busy", "a text on screen: the marker waits, strikes are ignored")
	await _finish()
	await _frames(5)
	_check(b2.logic.pos() != p0, "the text read: the marker runs again")
	layer.queue_free()
	await _frames(2)
	_reached_end = true


# --- Examine -----------------------------------------------------------------------------------

func _test_examine_data() -> void:
	var items := _obtainable_items()
	_check(items.size() >= 15, "inventory items of the built game: %d" % items.size())
	var icon_only: Array[String] = []
	for id in items:
		var e: Dictionary = sr.examine_spec(id)
		if e.is_empty():
			_check(false, "%s: no examine in items.json (every bag item opens up close — F9)" % id)
			continue
		var key := String(e.get("text", ""))
		var ln: Dictionary = sd.text_line(key)
		_check(key.begins_with("@") and sd.texts.has(key.substr(1)), "%s: examine.text %s is a text key" % [id, key])
		_check(String(ln.get("speaker", "")) == "agata" and String(ln.get("text", "")).length() > 10, "%s: the line is Agata's (%s)" % [id, str(ln)])
		var art := String(e.get("art", ""))
		if art != "":
			_check(ResourceLoader.exists(art), "%s: art %s exists" % [id, art])
		else:
			var big := "res://assets/examine/%s.png" % _IB.icon_name(id)
			_check(ResourceLoader.exists(big) or _IB.icon_for(id) != null, "%s: no art — the icon must exist" % id)
			icon_only.append(id)
	print("    examine: %d items, art %d, icon enlarged %d: %s" % [items.size(), items.size() - icon_only.size(), icon_only.size(), ", ".join(icon_only)])
	_reached_end = true


func _test_examine_each() -> void:
	var items := _obtainable_items()
	await _fresh(items)
	for id in items:
		_check(sr.examine_item(id), "%s: opens" % id)
		await _frames(2)
		var pr: Dictionary = ex.probe()
		_check(bool(pr.get("open", false)) and String(pr.get("item", "")) == id, "%s: the close-up is open (%s)" % [id, str(pr)])
		var pic: Dictionary = pr.get("picture", {})
		_check(float(pic.get("w", 0)) >= 300.0 or float(pic.get("h", 0)) >= 300.0, "%s: the picture is large (%s)" % [id, str(pic)])
		var e: Dictionary = sr.examine_spec(id)
		_check(String(pr.get("source", "")) == ("art" if e.has("art") else "icon"), "%s: picture from %s" % [id, String(pr.get("source", ""))])
		var b: Dictionary = sr.current_beat
		_check(String(b.get("speaker", "")) == "agata" and String(b.get("text", "")) == String(sd.text_line(String(e.get("text", ""))).get("text", "?")),
			"%s: Agata's line plays over it (%s)" % [id, str(b)])
		if e.has("watch"):
			_check(bool(pr.get("watch", false)), "%s: the watch goes" % id)
		if e.has("note"):
			_check(bool(pr.get("note", false)), "%s: the journal page beside it" % id)
		await _click(Vector2(1500, 900))   # the text first
		_check(ex.is_open(), "%s: a click reads the line, the close-up stays" % id)
		await _frames(1)
		await _click(Vector2(1500, 900))
		_check(not ex.is_open() and sr.examined_item == "", "%s: a click after the line closes it" % id)
		_check(gs.has_item(id), "%s: still in the bag" % id)
	_reached_end = true


func _test_examine_bag() -> void:
	await _fresh(["pocket_watch", "photo_bridge", "plan_crossing"])
	rm.change_room("Z1", "default")
	await _frames(4)
	await _finish()
	var bag = ui.get("bag")
	bag.refresh()
	await _frames(2)
	var it: Dictionary = bag.probe()["items"]
	var p := _v(it["photo_bridge"])
	await _move(p)
	await _button(p, true)
	await _button(p, false)
	_check(sr.selected_item == "photo_bridge" and not ex.is_open(), "a single click takes it in hand (no close-up)")
	await _button(p, true, true)
	await _button(p, false)
	await _frames(2)
	_check(ex.is_open() and String(ex.item_id) == "photo_bridge" and sr.selected_item == "", "a double click: the close-up; nothing in hand")
	await _finish()
	await _key(KEY_ESCAPE)
	_check(not ex.is_open(), "Esc closes it")
	await _move(_v(it["pocket_watch"]))
	await _frames(2)
	var badge := _v(it["pocket_watch"]["badge"])
	await _click(badge)
	_check(ex.is_open() and String(ex.item_id) == "pocket_watch", "the magnifier in the pocket's corner opens it")
	await _finish()
	var close: Dictionary = ex.probe().get("close", {})
	await _click(_v(close))
	_check(not ex.is_open(), "«Закрыть»")
	# Item in hand → examine puts it back; a load closes an open close-up.
	sr.select_item("plan_crossing")
	_check(bag.examine("plan_crossing") and sr.selected_item == "", "examine from the probe: in hand → back in the bag")
	await _finish()
	_check(rm.save_game(SLOT), "save")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(not ex.is_open() and sr.examined_item == "", "a load closes the close-up")
	# Tooltip says how.
	var tip_ok: bool = String(sd.text("@ui.bag_examine")).contains("Двойной")
	_check(tip_ok, "the tooltip line about examining exists")
	_reached_end = true


func _test_examine_over_mechanic() -> void:
	await _open_mother_mirror()
	_check(sr.mechanic_open, "mother's mirror open")
	_check(sr.examine_item("pocket_watch"), "the watch up close while at the mirror")
	await _frames(2)
	_check(ex.get_index() > mv.get_index() and ex.layer == mv.layer and ex.layer < ui.layer, "examine draws over the close-up and under the text box")
	await _finish()
	await _key(KEY_ESCAPE)
	_check(not ex.is_open() and sr.mechanic_open, "Esc closes the examine only; the mirror stays")
	sr.close_mechanic()
	await _frames(2)
	_reached_end = true


# --- Mother's mirror ------------------------------------------------------------------------------

func _open_mother_mirror(flags: Array = []) -> void:
	var base := ["done_M14", "nina_mirror_clamped", "has_clamp", "house_unlocked", "h2_bundle_unwrapped"]
	await _fresh(["pocket_watch", "journal_manager"], base + flags)
	rm.change_room("H2", "default")
	await _frames(4)
	await _finish()
	var h = rm.current_room.get_node_or_null("Hotspots/bundle_nina")
	sr.open_mechanic(sr.mechanic_spec(h), "bundle_nina")
	await _frames(3)


func _test_fast_mirror() -> void:
	Engine.time_scale = 1.0
	await _open_mother_mirror()
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "fast_mirror", "mother's mirror opens")
	var p = mv.panel
	var pr: Dictionary = p.probe()
	_check(not bool(pr.get("holding", true)) and not p.watch.visible, "Agata's watch is not there by itself")
	_check(p.loupe != null and p.loupe.size.x >= 200.0 and p.loupe.size.y >= 300.0, "the wall clock up close beside the glass (%s)" % str(p.loupe.size if p.loupe else Vector2.ZERO))
	_check(p.loupe.get_global_rect().end.x <= 1920.0 and p.slot.get_global_rect().end.x <= 1920.0, "both on screen")
	# The hands go: over real frames, at exactly 20×, in the glass and up close.
	var m0: float = p.loupe_min.rotation_degrees
	var h0: float = p.loupe_hour.rotation_degrees
	var r0: float = p.fclock.real_s
	var pend: Array[float] = []
	for i in 60:
		await process_frame
		pend.append(p.loupe_pend.rotation_degrees)
	var dr: float = p.fclock.real_s - r0
	var dm: float = fposmod(p.loupe_min.rotation_degrees - m0, 360.0)
	_check(absf(dm - dr * 2.0) < 0.05, "minute hand: %.3f° in %.3f s = 2°/s (a turn in 3 min)" % [dm, dr])
	_check(is_equal_approx(p.loupe_min.rotation_degrees, p.hand_min.rotation_degrees), "the glass and the close-up show the same time")
	_check(absf(fposmod(p.loupe_hour.rotation_degrees - h0, 360.0) - dm / 12.0) < 0.02, "the hour hand twelve times slower")
	var lo: float = pend.min()
	var hi: float = pend.max()
	_check(hi - lo > 10.0, "the pendulum swings (%.1f…%.1f°)" % [lo, hi])
	var c := FastClock.new(20.0, 0.0)
	c.advance(180.0)
	_check(is_equal_approx(c.nina_elapsed_minutes(), 60.0) and is_equal_approx(fmod(c.minute_hand_deg(), 360.0), 0.0), "180 real seconds = one turn of the minute hand")
	# The empty place says what to do; a knock; the wrong item does nothing.
	await _click(_v(pr.get("watch", {})))
	var seen := await _finish()
	_check(seen.size() == 1 and seen[0].begins_with("agata:") and seen[0].contains("сумке"), "the empty place: Agata says her watch is in the bag (%s)" % str(seen))
	sr.select_item("journal_manager")
	await _click(_v(pr.get("glass", {})))
	seen = await _finish()
	_check(gs.has_item("journal_manager") and not p.holding and int(p.wrong_items) == 1 and seen.size() == 1, "another item: nothing happens, it stays in the bag (%s)" % str(seen))
	# The watch from the bag onto the glass.
	var bag = ui.get("bag")
	bag.refresh()
	await _frames(2)
	await _click(_v(bag.probe()["items"]["pocket_watch"]))
	_check(sr.selected_item == "pocket_watch", "the watch taken from the bag by a click (the bag works over the close-up)")
	await _click(_v(pr.get("glass", {})))
	_check(p.holding and p.watch.visible and gs.has_item("pocket_watch") and sr.selected_item == "", "held to the glass: both clocks side by side; the watch stays Agata's")
	_check(not gs.has_flag("nina_time_compared"), "no realisation at once")
	seen = await _finish()
	var w0: float = p.watch.minute_deg()
	var n0: float = p.fclock.nina_elapsed_minutes()
	Engine.time_scale = 4.0
	var guard := 0
	while not gs.has_flag("nina_time_compared") and guard < 2000:
		await process_frame
		guard += 1
	Engine.time_scale = 1.0
	_check(gs.has_flag("nina_time_compared"), "after compare_s the comparison")
	_check(p.hold_s >= float(p.spec.get("compare_s", 10.0)) - 0.05 and p.hold_s < float(p.spec.get("compare_s", 10.0)) + 1.0, "about %s s of holding (%.2f)" % [str(p.spec.get("compare_s")), p.hold_s])
	var dn: float = (p.fclock.nina_elapsed_minutes() - n0) * 60.0
	var dw: float = fposmod(p.watch.minute_deg() - w0, 360.0) * 10.0   # 6°/min → s
	_check(absf(dn - dw * 20.0) < 2.0, "her watch and the wall clock: 20× (%.1f s vs %.1f s)" % [dw, dn])
	_check(String(p.elapsed_mine.text) != "" and String(p.elapsed_nina.text) != "", "how much passed on each: «%s» / «%s»" % [p.elapsed_mine.text, p.elapsed_nina.text])
	seen = await _finish()
	var all := " ".join(seen)
	_check(all.contains("На моих три минуты") and all.contains("Пока я сплю"), "the realisation in Agata's words: %s" % str(seen))
	_check(gs.has_flag("done_M15a"), "M15а done")
	# Save/load: compared stays; holding the watch again — no second event.
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLOT) and rm.load_game(SLOT), "save/load")
	await _frames(3)
	_check(gs.has_flag("nina_time_compared") and gs.has_flag("done_M15a") and not sr.can_start("M15a"), "after the load: compared, M15а does not replay")
	var h = rm.current_room.get_node_or_null("Hotspots/bundle_nina")
	sr.open_mechanic(sr.mechanic_spec(h), "bundle_nina")
	await _frames(3)
	p = mv.panel
	sr.select_item("pocket_watch")
	await _click(_v(p.probe().get("glass", {})))
	seen = await _finish()
	_check(p.holding and p.compared_sent and seen.size() == 1, "again: the rule as a reminder, no second realisation (%s)" % str(seen))
	sr.close_mechanic()
	await _frames(2)
	_reached_end = true


# --- Living water (F14) ----------------------------------------------------------------------------

func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _test_water() -> void:
	var rooms_with_water := 0
	var dir := DirAccess.open("res://data/story/ambient")
	var files: Array[String] = []
	for fn in dir.get_files():
		if fn.ends_with(".json") and not fn.begins_with("_"):
			files.append(fn)
	files.sort()
	for fn in files:
		var rid := fn.get_basename()
		if not sd.in_scope(rid):
			continue
		var spec = _read_json("res://data/story/ambient/" + fn)
		var water: Array = spec.get("water", []) if spec is Dictionary else []
		if water.is_empty():
			continue
		rooms_with_water += 1
		for state in [[], ["evening_dusk"]]:
			await _fresh([], ["house_unlocked"] + state)
			rm.change_room(rid, "default")
			await _frames(3)
			await _finish()
			var amb = rm.current_room.get_node_or_null("Ambient")
			_check(amb != null, "%s: the ambient layer is built" % rid)
			if amb == null:
				continue
			for w in water:
				var id := String(w.get("id", ""))
				var n: Node = null
				for x in amb.water:
					if String(x.name) == id:
						n = x
				_check(n != null, "%s: water %s is built" % [rid, id])
				if n == null:
					continue
				var mat := n.material as ShaderMaterial
				_check(mat != null and mat.shader.resource_path.ends_with("ambient_water.gdshader"), "%s/%s: the water shader" % [rid, id])
				if mat == null:
					continue
				var want_vis := true
				for f in w.get("if", []):
					want_vis = want_vis and state.has(String(f))
				for f in w.get("unless", []):
					want_vis = want_vis and not state.has(String(f))
				_check(n.visible == want_vis, "%s/%s: shown %s with flags %s (per-state variant)" % [rid, id, str(want_vis), str(state)])
				_check(float(mat.get_shader_parameter("tremble_px")) > 0.0 and float(mat.get_shader_parameter("sparkle")) > 0.0,
					"%s/%s: reflections tremble, sparkles on" % [rid, id])
				var rp: Vector2 = mat.get_shader_parameter("ripple_px")
				_check(rp.y >= 1.0, "%s/%s: a ripple you can see (near %.1f px)" % [rid, id, rp.y])
				if float(w.get("streaks", 0.0)) > 0.0:
					_check(is_equal_approx(float(mat.get_shader_parameter("streaks")), float(w["streaks"])), "%s/%s: flow lines from data" % [rid, id])
	_check(rooms_with_water >= 6, "rooms with water in scope: %d (Z2, Z3, R1, R2, R3, M1, M4 …)" % rooms_with_water)
	_reached_end = true


# --- The plate: brace and knot (F5–F7) ----------------------------------------------------------------

func _panel() -> Dictionary:
	return mv.probe().get("panel", {})


func _open_plate(flags: Array) -> void:
	await _fresh([], ["house_unlocked", "evening_dusk", "done_M15a", "skoba_on_plate"] + flags)
	rm.change_room("Z3", "default")
	await _frames(4)
	await _finish()
	var h = rm.current_room.get_node_or_null("Hotspots/pier_plate")
	sr.open_mechanic(sr.mechanic_spec(h), "pier_plate")
	await _frames(3)


## Waits until the bar's marker is near the middle of the green (want_green) or well in the red, then clicks `at`.
func _strike_at(at: Vector2, want_green: bool) -> void:
	await _move(at)
	var g := 0
	while g < 900:
		var t: Dictionary = _panel().get("timing", {})
		if t.is_empty():
			break
		var z: Array = t.get("zone", [0.4, 0.6])
		var c := (float(z[0]) + float(z[1])) * 0.5
		var d := absf(float(t.get("pos", 0.0)) - c)
		var ok := (d < 0.03) if want_green else (d > 0.3)
		if String(t.get("state", "")) == "run" and not bool(t.get("paused", true)) and ok:
			break
		await process_frame
		g += 1
	await _button(at, true)
	await _button(at, false)


func _drag_path(points: Array, release: bool = true) -> Vector2:
	var start := _v(points[0])
	await _move(start)
	await _button(start, true)
	var last := start
	for j in range(1, points.size()):
		var a := _v(points[j - 1])
		var b := _v(points[j])
		var steps := maxi(1, int(a.distance_to(b) / 20.0))
		for k in steps:
			last = a.lerp(b, float(k + 1) / steps)
			await _move(last)
	if release:
		await _button(last, false)
	return last


func _test_plate() -> void:
	Engine.time_scale = 1.0
	await _open_plate([])
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "plate", "the plate close-up")
	var p = mv.panel
	var pr := _panel()
	_check(not pr.get("timing", {}).is_empty() and int(pr["timing"].get("needed", 0)) == 3, "the «точный удар» bar under the plate: three in a row")
	var sk := _v(pr.get("skoba", {}))
	await _strike_at(sk, true)
	await _strike_at(sk, true)
	_check(int(_panel().get("blows", 0)) == 2 and not gs.has_flag("plate_braced"), "two hits: two blows, not yet braced")
	await _strike_at(sk, false)
	var seen := await _finish()
	_check(int(_panel().get("blows", -1)) == 0 and int(_panel().get("jumps", 0)) == 1 and not gs.has_flag("plate_braced"), "a miss: the brace jumps off, the series starts again")
	_check(seen.size() == 1 and seen[0].begins_with("agata:"), "Agata says so once (%s)" % str(seen))
	_check(gs.has_flag("skoba_on_plate") and not gs.has_item("brace_plate"), "nothing lost: the brace is still on the plate")
	for i in 3:
		await _strike_at(sk, true)
	seen = await _finish()
	_check(gs.has_flag("plate_braced") and gs.has_flag("done_M15s"), "three in a row: braced, M15s (%s)" % str(seen))
	await _frames(3)
	pr = _panel()
	_check(bool(pr.get("knot_stage", false)) and bool(pr.get("rope_textured", false)), "the rope comes: drawn with the rope's own texture (F5)")
	_check(pr.get("timing", {}).is_empty(), "the bar is gone once braced")
	# Save in the middle (braced, knot not tied) → load → the brace stays, the knot waits.
	sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLOT) and rm.load_game(SLOT), "save/load between the brace and the knot")
	await _frames(3)
	_check(gs.has_flag("plate_braced") and not gs.has_flag("rope_on_ring") and not sr.can_start("M15s"), "after the load: braced, M15s does not replay")
	var h = rm.current_room.get_node_or_null("Hotspots/pier_plate")
	sr.open_mechanic(sr.mechanic_spec(h), "pier_plate")
	await _frames(3)
	p = mv.panel
	pr = _panel()
	_check(pr.get("timing", {}).is_empty() and bool(pr.get("knot_stage", false)), "reopened: no bar, the knot")
	# The knot: let go in the middle of the first stroke — it slips back; finish the stroke and the second; off the path on the third.
	var strokes: Array = pr.get("strokes", [])
	await _drag_path(strokes[0].slice(0, 3))
	seen = await _finish()
	_check(int(_panel().get("slips", 0)) == 1 and int(_panel().get("stroke", -1)) == 0, "let go mid-stroke: slips back to its start (%s)" % str(seen))
	var at := await _drag_path(strokes[0] + strokes[1].slice(1) , false)
	_check(int(_panel().get("stroke", -1)) == 2, "two strokes drawn (stroke %d)" % int(_panel().get("stroke", -1)))
	await _move(at + Vector2(0, -320))
	await _button(at + Vector2(0, -320), false)
	await _finish()
	_check(int(_panel().get("stroke", -1)) == 2 and int(_panel().get("slips", 0)) == 2 and not gs.has_flag("rope_on_ring"), "off the path on the third: back to its start, the first two stay")
	var s3: Array = [pr["strokes"][2][0]] + pr["strokes"][2].slice(1)
	await _drag_path(s3)
	await create_timer(1.0).timeout
	seen = await _finish()
	_check(gs.has_flag("rope_on_ring") and gs.has_flag("done_M15"), "the knot tied: rope on the ring, M15 (%s)" % str(seen))
	_check(bool(_panel().get("rope_tied_visible", false)) if sr.mechanic_open else true, "the painted knot shown")
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(2)
	_check(rm.save_game(SLOT) and rm.load_game(SLOT), "save/load after the knot")
	await _frames(3)
	_check(gs.has_flag("rope_on_ring") and not sr.can_start("M15"), "tied stays tied after a load")
	_reached_end = true


# --- The H1 shutter latch (F8) ----------------------------------------------------------------------

func _test_latch() -> void:
	Engine.time_scale = 1.0
	await _fresh([], ["house_unlocked"])
	rm.change_room("H1", "default")
	await _frames(4)
	await _finish()
	var h = rm.current_room.get_node_or_null("Hotspots/shutter")
	_check(sr.planned_interaction(h) == "use", "the first click: Agata reaches for the shutter (the open action)")
	player.call("walk_to_and_interact", h)
	var g := 0
	while not sr.mechanic_open and g < 2000:
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
		g += 1
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "latch" and gs.has_flag("h1_shutter_latch") and not gs.has_flag("h1_shutter_open"),
		"the tight latch close-up; the shutter not open yet")
	await _finish()
	var pr := _panel()
	var at := _v(pr.get("shutter", {}))
	_check(not pr.get("timing", {}).is_empty() and int(pr["timing"].get("needed", 0)) == 1, "one catch on the «точный удар» bar")
	await _strike_at(at, false)
	var seen := await _finish()
	_check(int(_panel().get("drops", 0)) == 1 and not gs.has_flag("h1_shutter_open"), "released low: the latch drops back, still closed")
	_check(seen.size() == 1 and seen[0].begins_with("agata:"), "Agata says so once (%s)" % str(seen))
	# Closed and opened again: a direct click opens the close-up (no second action, no penalty).
	sr.close_mechanic()
	await _frames(2)
	_check(sr.planned_interaction(h) == "mechanic", "the next click opens the latch at once")
	sr.open_mechanic(sr.mechanic_spec(h), "shutter")
	await _frames(3)
	at = _v(_panel().get("shutter", {}))
	await _strike_at(at, true)
	await create_timer(1.2).timeout
	seen = await _finish()
	_check(gs.has_flag("h1_shutter_open") and not sr.mechanic_open, "caught up in the green: the shutter opens, the close-up closes (%s)" % str(seen))
	_check(seen.any(func(x): return x.contains("посветлело")), "«Ставня подалась, в комнате посветлело»")
	_check(sr.planned_interaction(h) == "text", "the open shutter is only a look now")
	_check(rm.save_game(SLOT) and rm.load_game(SLOT), "save/load")
	await _frames(3)
	h = rm.current_room.get_node_or_null("Hotspots/shutter")
	_check(gs.has_flag("h1_shutter_open") and sr.planned_interaction(h) == "text" and not sr.mechanic_open, "after a load: open, nothing replays")
	_reached_end = true


# --- The crossing (F12, F15) -------------------------------------------------------------------------

func _test_crossing() -> void:
	Engine.time_scale = 1.0
	var flags := ["house_unlocked", "done_M15", "rope_on_ring", "road_held_both_ends", "done_M16", "three_lights_sent", "far_lights_answered",
		"done_M17", "ferry_verified", "evening_dusk"]
	await _fresh(["school_ribbon"], flags)
	rm.change_room("R2", "default")
	await _frames(4)
	var seen := await _finish()
	_check(seen.size() >= 4 and seen.any(func(x): return x.begins_with("pelageya:")), "Pelageya speaks first (%d lines)" % seen.size())
	var g := 0
	while not sr.mechanic_open and g < 300:
		await process_frame
		g += 1
	_check(sr.mechanic_open and String(mv.spec.get("type", "")) == "crossing", "then the crossing close-up")
	_check(not mv.close_button.visible, "no «Закрыть»: the only way is across")
	await _key(KEY_ESCAPE)
	_check(sr.mechanic_open, "Esc does not leave the boat")
	var p = mv.panel
	var pr := _panel()
	_check(int(pr.get("pulls_total", 0)) >= 8 and int(pr.get("pulls_total", 0)) <= 12, "about ten pulls (%d)" % int(pr.get("pulls_total", 0)))
	var b0 := float(pr.get("band_scale", 0))
	var f0 := float(pr.get("fog", 0))
	var s0 := float(pr.get("snow", 0))
	var rp0 := float(pr.get("rope_phase", 0))
	# A click — one pull, the boat moves on smoothly (progress grows over several frames).
	var c := _v(pr.get("center", {}))
	await _click(c)
	var progs: Array[float] = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200:
		await process_frame
		progs.append(float(_panel().get("progress", 0)))
	_check(int(_panel().get("pulls", 0)) == 1 or bool(_panel().get("pulling", false)), "a click pulls")
	var smooth := true
	for i in range(1, progs.size()):
		if progs[i] < progs[i - 1] - 1e-6:
			smooth = false
	_check(smooth and progs[progs.size() - 1] > 0.07 and progs[2] < progs[progs.size() - 1] and progs.size() > 10, "the boat moves on smoothly (%.3f → %.3f over %d frames)" % [progs[0], progs[progs.size() - 1], progs.size()])
	_check(float(_panel().get("rope_phase", 0)) > rp0, "the rope runs back through the ring")
	_check(mv.sounds_played.has("ring_creak") and mv.sounds_played.has("water_slap"), "the ring creaks, water at the bow")
	# A short drag toward herself — a pull too.
	while bool(_panel().get("pulling", false)):
		await process_frame
	var n1 := int(_panel().get("pulls", 0))
	await _move(c)
	await _button(c, true)
	for k in 6:
		await _move(c + Vector2(4, 14 * (k + 1)))
	await _button(c + Vector2(4, 84), false)
	while bool(_panel().get("pulling", false)):
		await process_frame
	_check(int(_panel().get("pulls", 0)) == n1 + 1, "a drag toward herself pulls (%d → %d)" % [n1, int(_panel().get("pulls", 0))])
	# The rest by clicks (and one Space).
	g = 0
	while int(_panel().get("pulls", 0)) < int(pr.get("pulls_total", 10)) and g < 40:
		g += 1
		if g == 3:
			await _key(KEY_SPACE)
		else:
			await _click(c)
		var w := 0
		while bool(_panel().get("pulling", false)) and w < 200:
			await process_frame
			w += 1
	pr = _panel()
	_check(float(pr.get("band_scale", 0)) > b0 + 0.3 and float(pr.get("fog", 1)) < f0 - 0.4 and float(pr.get("snow", 0)) > s0 + 0.5,
		"the far bank grew (%.2f→%.2f), fog thinned (%.2f→%.2f), snow (%.2f→%.2f)" % [b0, float(pr.get("band_scale", 0)), f0, float(pr.get("fog", 1)), s0, float(pr.get("snow", 0))])
	_check(float(pr.get("arrival", 0)) > 0.9, "the far pier's own painting at the end")
	g = 0
	while not gs.has_flag("crossing_hauled") and g < 400:
		await process_frame
		g += 1
	_check(gs.has_flag("crossing_hauled"), "across: crossing_hauled")
	seen = await _finish()
	g = 0
	while _room() != "R3" and g < 600:
		await process_frame
		g += 1
	seen += await _finish()
	_check(_room() == "R3" and gs.has_flag("done_M18p"), "the boat at the far pier: R3, M18p done (room %s)" % _room())
	_check(gs.has_flag("done_M18") or seen.any(func(x): return x.begins_with("mitya:")), "Mitya at the far pier (%s)" % str(seen).left(200))
	# Save/load after: nothing replays; R2 again later — no hauling again.
	_check(rm.save_game(SLOT) and rm.load_game(SLOT), "save/load at the far pier")
	await _frames(3)
	_check(gs.has_flag("crossing_hauled") and not sr.can_start("M18p") and not sr.mechanic_open, "crossed stays crossed")
	rm.change_room("R2", "default")
	await _frames(4)
	await _finish()
	_check(not sr.mechanic_open, "R2 again: no second hauling")
	_reached_end = true


func _room() -> String:
	return rm.current_room.room_id if rm.current_room != null else ""
