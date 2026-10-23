extends SceneTree
## Headless test of the Zarechye plan (game/scripts/ui/zarechye_map.gd, data/story/map_zarechye.json).
##   godot --headless --path game -s res://tests/test_ui_map.gd
## Behind it — the Director's task of 17.10 «план Заречья должен быть интерактивным»:
##   - data: every place names real locations, its point lies on the picture, texts exist; the Z1
##     plan hotspot opens this plan and sets the journal flag (a known room flag);
##   - click on the plan in Z1: no look text, the picture rides in from the plan on the wall to the
##     full view over the darkened room; a click or Esc closes it (back to the wall);
##   - «Вы здесь» is the place of the current room; places not visited are paler; Olkhovka (school)
##     is hidden until one of its rooms was visited; entering a room sets visited_<room>;
##   - the journal shows «План» only after the plan was seen; from there it opens, and closing returns
##     to the journal; loading a save while the plan is open closes it.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
var mp: Control = null   # ZarechyeMap (untyped: autoloads do not exist yet when -s compiles)
var SLOT := "test_ui_map_%d" % OS.get_process_id()


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
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	mp = ui.get("map_view")
	await _test("Plan data: places → real locations, points on the picture, texts; Z1.plan opens it", _test_data)
	await _test("Click the plan in Z1: rides in from the wall, no look text, flag set; click closes back to the wall", _test_open_close)
	await _test("«Вы здесь» = current room; unvisited paler; Olkhovka hidden until visited; visited_<room> on entry; the far bank's layer and plaques (G2)", _test_here_and_visits)
	await _test("Journal «План» only after the plan was seen; opens from the journal, Esc returns to it; load closes", _test_journal)
	gs.reset()
	gs.delete_save(SLOT)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== ui map: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait_until(cond: Callable, timeout: float = 3.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await process_frame
	return false


func _enter(room: String) -> void:
	sr.call("_on_state_reset")
	rm.change_room(room, "")
	await _frames(3)
	sr.call("_on_state_reset")   # no scene dialogue left over (M01 etc.)
	await _frames(1)


func _hotspot(id: String) -> Node:
	var room = rm.current_room
	for h in room.get_hotspots():
		if String(h.get("hotspot_id")) == id:
			return h
	return null


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)
		await _frames(1)


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	root.push_input(ev, true)
	await _frames(1)


func _open_settled() -> bool:
	return await _wait_until(func(): return mp.visible and bool(mp.get("settled")), 3.0)


func _closed() -> bool:
	return await _wait_until(func(): return not mp.visible, 3.0)


# --- Tests ---------------------------------------------------------------------------------

func _test_data() -> void:
	var spec: Dictionary = mp.get("spec")
	_check(not spec.is_empty(), "map_zarechye.json loads")
	_check(ResourceLoader.exists(String(spec.get("image", ""))), "plan picture %s" % spec.get("image", ""))
	var isz: Array = spec.get("image_size", [0, 0])
	var tex: Texture2D = (mp.get("plan") as TextureRect).texture
	_check(tex != null and tex.get_width() == int(isz[0]) and tex.get_height() == int(isz[1]), "image_size matches the picture")
	var ids := {}
	for p in spec.get("places", []):
		var id := String(p.get("id", ""))
		_check(id != "" and not ids.has(id), "place id %s unique" % id)
		ids[id] = true
		for l in p.get("locs", []):
			_check(sd.locations.has(String(l)), "%s: location %s exists" % [id, l])
		var pt: Array = p.get("point", [-1, -1])
		_check(float(pt[0]) > 0 and float(pt[0]) < float(isz[0]) and float(pt[1]) > 0 and float(pt[1]) < float(isz[1]), "%s: point on the picture" % id)
		if p.has("label"):
			_check(sd.texts.has(String(p["label"]).substr(1)), "%s: text %s" % [id, p["label"]])
		_check(String(p.get("align", "above")) in ["above", "below", "left", "right", "center"], "%s: align" % id)
	for k in ["map.here", "map.close_hint", "ui.button_plan"]:
		_check(sd.texts.has(k), "text %s" % k)
	# Z1.plan → this panel; its flag is the journal flag and a known room flag.
	var plan: Dictionary = {}
	for h in sd.room("Z1").get("hotspots", []):
		if String(h.get("id", "")) == "plan":
			plan = h
	var pn: Dictionary = plan.get("panel", {})
	_check(String(pn.get("id", "")) == String(spec.get("id", "")), "Z1.plan.panel.id = %s" % spec.get("id", ""))
	_check((pn.get("sets", []) as Array).has(String(spec.get("journal_flag", ""))), "Z1.plan sets the journal flag")
	_check(sd.room("Z1").get("flags", {}).has(String(spec.get("journal_flag", ""))), "journal flag declared in Z1 flags")
	# Labels of single rooms come from locations.json.
	for p in spec.get("places", []):
		if not p.has("label"):
			_check(mp.call("place_name", p) == sd.location_name(String(p["locs"][0])), "%s: name from locations.json" % p["id"])


func _test_open_close() -> void:
	gs.reset()
	await _enter("Z1")
	var h := _hotspot("plan")
	_check(h != null, "Z1 has the plan hotspot")
	if h == null:
		return
	_check(sr.planned_interaction(h) == "panel", "planned interaction: panel (%s)" % sr.planned_interaction(h))
	sr.interact(h)
	await _frames(1)
	_check(mp.visible, "plan opened")
	_check(sr.current_beat.is_empty(), "no look text over the plan")
	_check(gs.has_flag("seen_plan_zarechye"), "seen_plan_zarechye set")
	var r: Array = h.get("data").get("rect")
	var start: Rect2 = (mp.get("plan") as Control).get_rect()
	_check(start.get_center().distance_to(Vector2(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0)) < 40.0 and start.size.x < 600.0,
		"starts at the plan on the wall: %s" % str(start))
	var backdrop: ColorRect = mp.get("backdrop")
	_check(await _open_settled(), "settles")
	var fin: Rect2 = (mp.get("plan") as Control).get_rect()
	_check(fin.size.x > 1600.0 and fin.position.x > 20.0 and fin.end.x < 1900.0, "ends nearly full screen with room at the edges: %s" % str(fin))
	_check(backdrop.color.a > 0.6 and backdrop.color.a < 0.9, "room darkened, still there (%.2f)" % backdrop.color.a)
	_check(not ui.get("hover_label").visible, "no hotspot hover over the plan")
	# A click anywhere closes it, back to the wall.
	await _click(Vector2(960, 540))
	await create_timer(0.25).timeout   # labels fade 0.1 s, then the picture shrinks
	var mid: Rect2 = (mp.get("plan") as Control).get_rect()
	_check(mid.size.x < fin.size.x, "shrinks back while closing")
	_check(await _closed(), "click closes")
	_check(sr.current_beat.is_empty() and not ui.get("journal_panel").visible, "nothing left open")
	# Esc closes too.
	sr.interact(h)
	_check(await _open_settled(), "reopens")
	await _esc()
	_check(await _closed(), "Esc closes")
	# With an item in hand the plan is just a place where it does not help.
	gs.add_item("key_house")
	sr.select_item("key_house")
	sr.interact(h)
	await _frames(1)
	_check(not mp.visible and not sr.current_beat.is_empty(), "item in hand → «не поможет», no plan")
	sr.call("_on_state_reset")


func _test_here_and_visits() -> void:
	gs.reset()
	await _enter("Z1")
	_check(gs.has_flag("visited_Z1"), "entering Z1 sets visited_Z1")
	sr.interact(_hotspot("plan"))
	_check(await _open_settled(), "open")
	var p: Dictionary = mp.call("probe")
	_check(p["here"] == "post" and p["here_room"] == "Z1", "«Вы здесь» at the post office (%s)" % p["here"])
	var labels: Dictionary = p["labels"]
	_check(labels.has("olkhovka") and not labels["olkhovka"]["visible"], "Olkhovka hidden before a visit")
	_check(labels["mill"]["visible"] and not labels["mill"]["visited"], "mill shown, not visited")
	var marks: Control = mp.get("marks")
	var mill_l: Control = marks.find_child("Label_mill", false, false)
	var post_l: Control = marks.find_child("Label_post", false, false)
	_check(mill_l != null and mill_l.theme_type_variation == &"MapLabelFaint", "unvisited place paler")
	var street_l: Control = marks.find_child("Label_street", false, false)
	if mill_l != null and street_l != null:
		var faint: Color = mill_l.get_theme_color("font_color")
		var ink: Color = (marks.find_child("Label_lane", false, false) as Control).get_theme_color("font_color") if gs.has_flag("visited_Z4") else Color(0.20, 0.12, 0.06)
		_check(faint.get_luminance() > ink.get_luminance() + 0.1, "faint ink lighter than visited ink")
	_check(post_l != null and post_l.modulate.a > 0.95 and post_l.theme_type_variation == &"MapLabelHere", "current place highlighted")
	_check(marks.find_child("Here", false, false) != null, "«Вы здесь» label")
	_check(marks.find_child("Label_olkhovka", false, false) == null, "no Olkhovka label node")
	# Labels lie on the picture, not off it.
	var pr: Rect2 = (mp.get("plan") as Control).get_global_rect()
	for c in marks.get_children():
		if c is Label:
			_check(pr.encloses((c as Control).get_global_rect()), "%s inside the picture" % c.name)
	mp.call("close_now")
	# Through the house to the school: Olkhovka appears, «Вы здесь» follows the room.
	await _enter("H1")
	_check(gs.has_flag("visited_H1"), "visited_H1")
	await _enter("O1")
	_check(gs.has_flag("visited_O1"), "visited_O1")
	mp.call("open_from", Rect2())
	_check(await _open_settled(), "open in O1")
	p = mp.call("probe")
	_check(p["here"] == "olkhovka", "«Вы здесь» at Olkhovka in O1 (%s)" % p["here"])
	_check(p["labels"]["olkhovka"]["visible"] and p["labels"]["olkhovka"]["visited"], "Olkhovka shown after the visit")
	_check(p["labels"]["house"]["visited"] and p["labels"]["post"]["visited"], "house and post office visited")
	mp.call("close_now")
	await _enter("H2")
	mp.call("open_from", Rect2())
	_check(await _open_settled(), "open in H2")
	_check(mp.call("probe")["here"] == "house", "H2 → the house")
	_check((mp.call("probe")["overlays"] as Array).is_empty(), "G2: before the far bank the plan shows nothing new across the river")
	mp.call("close_now")
	# G2 (Director 23.10: «нанести на карту то, что изменилось или добавилось»): once Agata has been on the far bank —
	# the batch-9 layer (school, houses, the rope crossing, the boat, the shed) and the plaques of the new places.
	gs.set_flag("visited_R3", true)
	mp.call("open_from", Rect2())
	_check(await _open_settled(), "open after the far pier")
	p = mp.call("probe")
	_check((p["overlays"] as Array).has("Overlay_zarechye_plan_overlay"), "G2: the plan's new layer is on (%s)" % str(p["overlays"]))
	for id in ["crossing", "far_pier", "ferry_shed"]:
		_check(p["labels"].has(id) and p["labels"][id]["visible"], "G2: «%s» on the plan" % id)
	_check(not p["labels"]["nina_house"]["visible"], "Nina's house only after a visit")
	var names := {}
	for id in p["labels"]:
		names[id] = String(mp.call("place_name", _place(id)))
	_check(names["crossing"] == "Переправа" and names["far_pier"] == "Дальняя опора" and names["ferry_shed"] == "Мастерская переправы"
		and names["olkhovka"] == "Школа" and names["olkhovka_street"] == "Улица Ольховки" and names["nina_house"] == "Дом Нины"
		and names["lower_street"] == "Нижняя улица", "G2: the plaques read as on the plan (%s)" % str(names))
	mp.call("close_now")


func _place(id: String) -> Dictionary:
	for pl in mp.call("places"):
		if String(pl.get("id", "")) == id:
			return pl
	return {}


func _test_journal() -> void:
	gs.reset()
	await _enter("Z1")
	var jb: Button = ui.get("journal_plan_button")
	ui.call("toggle_journal")
	await _frames(2)
	_check(not jb.visible, "no «План» before the plan was seen")
	ui.call("toggle_journal")
	sr.interact(_hotspot("plan"))
	_check(await _open_settled(), "seen on the wall")
	mp.call("close")
	_check(await _closed(), "closed")
	await _enter("Z2")
	ui.call("toggle_journal")
	await _frames(2)
	_check(jb.visible, "«План» in the journal after the plan was seen")
	var pp: Dictionary = ui.call("probe_positions")
	_check(pp["buttons"].has("JournalPlan"), "probe publishes the journal plan button")
	jb.pressed.emit()
	await _frames(1)
	_check(mp.visible and not ui.get("journal_panel").visible, "opens from the journal, journal hidden")
	_check(await _open_settled(), "settles")
	_check(mp.call("probe")["here"] == "street", "«Вы здесь» on the street in Z2")
	await _esc()
	_check(await _closed(), "Esc closes")
	await _frames(2)
	_check(ui.get("journal_panel").visible, "back in the journal")
	ui.call("toggle_journal")
	# The flag lives in the save; loading while the plan is open closes it.
	_check(rm.save_game(SLOT), "save")
	mp.call("open_from", Rect2())
	await _frames(2)
	_check(rm.load_game(SLOT), "load")
	await _frames(2)
	_check(not mp.visible, "load closes the plan")
	_check(gs.has_flag("seen_plan_zarechye"), "seen flag survives save/load")
