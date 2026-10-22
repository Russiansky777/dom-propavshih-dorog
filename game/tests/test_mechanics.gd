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


func _finish() -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
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
