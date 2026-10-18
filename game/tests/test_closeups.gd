extends SceneTree
## Headless tests of the H3 close-ups. Usage:
##   godot --headless --path game -s res://tests/test_closeups.gd
## Behind them — the Director's notes of 18.10:
##   «В квесте с дверью всё должно делаться мышью — и петли и зарубка»;
##   «петли у нас две, а на рисунке и двери — три»;
##   «Когда Агата смотрит в зеркало — не интуитивно… показать то, что описывается».
## Every action below is a real mouse event (InputEventMouseMotion / InputEventMouseButton through
## Input.parse_input_event), from the bag and the room to the close-ups; no key is needed anywhere
## (Esc is only checked as an optional extra on the mirror).
## Exit code 0 only when every check passed.

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var sfx: Node
var main_node: Node = null
var ui: Node = null
var cp: Node = null      # Closeup (door puzzle)
var cv: Node = null      # CloseupView (mirror)
var player: Node2D = null
var _results: Array = []
var _fails: Array[String] = []
var SLOT := "test_closeups_%d" % OS.get_process_id()   # parallel runs share user://saves


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
	sfx = root.get_node("SfxDirector")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	cp = main_node.get_node("Closeup")
	cv = main_node.get_node("CloseupView")
	player = main_node.get_node("World/Player")
	player.walk_speed = 1600.0
	player.speed_factor = 6.0
	await _test("Data: three hinges — items.json set, three sockets on the frame, three pieces; texts say «три», never «две»", _test_data)
	await _test("Door by mouse only: bag → door, drag hinges into sockets (miss returns, occupied refused), slide the threshold, click the handle", _test_door_mouse)
	await _test("Door: two hinges or a wrong notch never pass; three hinges + the V notch do; sounds of sfx.json", _test_door_rules)
	await _test("Save/load during the close-up: hinges neither lost nor doubled; after M05 never given again", _test_save_load)
	await _test("Mirror: a click opens the close-up (frame face-on, live reflection with Agata, old photo), text over it; click / «Закрыть» / Esc close it", _test_mirror)
	await _test("Mirror math: the homography maps the upright glass onto the painted quadrilateral", _test_homography)
	gs.reset()
	gs.delete_save(SLOT)
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== closeups: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Game (1920x1080 canvas) → window coordinates: Input.parse_input_event takes what the OS would send,
## and the viewport maps it back through the stretch transform (headless reports a tiny window).
func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(at)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(2)


func _button(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _win(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _click(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await _move(at)
	await _button(at, true, button)
	await _button(at, false, button)


## Press at `from`, move in steps, release at `to`.
func _drag(from: Vector2, to: Vector2, steps: int = 8) -> void:
	await _move(from)
	await _button(from, true)
	for k in range(1, steps + 1):
		await _move(from.lerp(to, float(k) / steps))
	await _button(to, false)
	await _wait(0.35)   # snap / return tween


func _v(d: Dictionary) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))


func _probe() -> Dictionary:
	return cp.call("probe_positions")


func _to_h3_before_m05(extra_flags: Array = []) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "seen_school_door", "seen_workshop",
			"seen_bell", "knows_rule_things_remember", "has_school_door", "has_bell", "has_mirror_home",
			"seen_mirror_home"] + extra_flags:   # M04's grants (it completes at the door, before any look at the mirror)
		gs.set_flag(String(f), true)
	sr.grant_item("door_hinges")
	rm.change_room("H3", "default")
	await _frames(6)
	await _wait(0.3)


func _wait_until(cond: Callable, timeout: float = 15.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await process_frame
	return false


func _hotspot_center(id: String) -> Vector2:
	for h in rm.current_room.get_hotspots():
		if h.get("hotspot_id") == id:
			var r: Array = h.data.get("rect", [0, 0, 0, 0])
			return Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0)
	return Vector2(-1, -1)


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.get("hotspot_id") == id:
			return h
	return null


## Opens the door close-up with the mouse only: the hinges' pocket in the bag, then the door.
func _open_door_by_mouse() -> bool:
	await _frames(2)
	var inv: Dictionary = ui.call("probe_positions").get("inventory", {})
	if not inv.has("door_hinges"):
		_check(false, "the hinges' pocket must be in the bag: %s" % [inv])
		return false
	await _click(_v(inv["door_hinges"]))
	_check(sr.selected_item == "door_hinges", "a click on the pocket takes the hinges in hand (got '%s')" % sr.selected_item)
	await _click(_hotspot_center("school_door"))
	var ok: bool = await _wait_until(func(): return sr.puzzle_open, 20.0)
	_check(ok, "hinges on the door (mouse) must open the close-up")
	await _frames(3)
	return ok


func _drop_hinge_into(pid: String, slot: String, offset: Vector2 = Vector2(14, 12)) -> void:
	var p := _probe()
	await _drag(_v(p["pieces"][pid]), _v(p["slots"][slot]) + offset)


func _slide_beam_to_notch(i: int, miss_px: float = 12.0) -> void:
	## Drag the beam so notch i lands `miss_px` from the door's mark (within the snap distance).
	var p := _probe()
	var notch := _v(p["marks"][i])
	var anchor := _v(p["anchor"])
	var grab := _v(p["beam"])
	await _drag(grab, grab + Vector2(anchor.x - notch.x + miss_px, 0), 6)


func _sounds_since(n0: int) -> Array:
	var out: Array = []
	var ev: Array = sfx.get("events")
	for i in range(mini(n0, ev.size()), ev.size()):
		if String(ev[i].get("kind", "")) == "closeup":
			out.append(String(ev[i].get("sound", "")))
	return out


# --- Tests -----------------------------------------------------------------------------------

func _test_data() -> void:
	var item: Dictionary = sd.item("door_hinges")
	var set_count := int(item.get("set_count", 0))
	_check(set_count == 3, "items.json door_hinges set_count must be 3, got %d" % set_count)
	var door: Dictionary = {}
	for h in sd.room("H3").get("hotspots", []):
		if String(h.get("id", "")) == "school_door":
			door = h
	var pz: Dictionary = door.get("puzzle", {})
	var pieces: Array = pz.get("pieces", [])
	var correct := (pz.get("slots", []) as Array).filter(func(s): return bool(s.get("correct", false)))
	_check(pieces.size() == set_count, "puzzle pieces (%d) == hinges in the set (%d)" % [pieces.size(), set_count])
	_check(correct.size() == 3 and (pz.get("slots", []) as Array).size() == 3, "three sockets on the frame, all three for hinges")
	var two := RegEx.create_from_string("(^|[^а-яё])(две|два|двух)([^а-яё]|$)")
	var three := RegEx.create_from_string("(^|[^а-яё])(три|трёх)([^а-яё]|$)")
	for k in ["@H2.hinges_box.use", "@H3.puzzle.intro"]:
		var t: String = sd.text(k).to_lower()
		_check(three.search(t) != null and two.search(t) == null, "%s must say «три», not «две»: %s" % [k, t])
	var sc: Dictionary = sd.scene("M05")
	_check(String(sc.get("puzzle", {}).get("solution", "")).contains("три"), "E1 M05 solution says three hinges")
	_check(sd.scene("M05").get("consumes", []).has("door_hinges"), "the set is consumed by M05 as one item")
	# Sounds named by the puzzle exist in sfx.json (no new sounds).
	for k in pz.get("sounds", {}).keys():
		if String(k).begins_with("_"):
			continue
		var sid := String(pz["sounds"][k])
		_check((sfx.get("sounds") as Dictionary).has(sid), "puzzle sound %s → %s is not in sfx.json" % [k, sid])


func _test_door_mouse() -> void:
	await _to_h3_before_m05()
	Engine.time_scale = 2.0
	if not await _open_door_by_mouse():
		Engine.time_scale = 1.0
		return
	var p := _probe()
	_check(p["pieces"].size() == 3, "three hinges in the tray, got %s" % [p["pieces"].keys()])
	_check(p["leaf"], "the leaf stands in the opening")
	_check(int(p["mark"]) == -1, "no notch under the door's mark at the start (beam shifted)")
	# Cursor tells what can be done.
	await _move(_v(p["pieces"]["hinge_1"]))
	_check(int(_probe()["cursor"]) == Control.CURSOR_DRAG, "over a hinge: open hand (drag) cursor, got %d" % int(_probe()["cursor"]))
	await _move(_v(p["beam"]))
	_check(int(_probe()["cursor"]) == Control.CURSOR_DRAG, "over the threshold: open hand (it is pulled sideways); not ↔ — that shape is an exit arrow")
	await _move(_v(p["handle"]))
	_check(int(_probe()["cursor"]) == Control.CURSOR_POINTING_HAND, "over the handle: pointing hand")
	_check(cp.get("handle_label").visible, "hovering the handle shows «%s»" % sd.text("@H3.puzzle.check"))
	# A miss: released far from any socket → back in the tray, nothing placed.
	await _drag(_v(p["pieces"]["hinge_1"]), Vector2(720, 300))
	p = _probe()
	_check(p["placed"].is_empty(), "a hinge dropped off the sockets is not placed: %s" % [p["placed"]])
	_check(_v(p["pieces"]["hinge_1"]).distance_to(_v(p["tray"]["hinge_1"])) < 2.0, "the missed hinge slides back to its tray place")
	# Into the top socket (released 18 px off: snaps).
	await _drop_hinge_into("hinge_1", "top")
	p = _probe()
	_check(String(p["placed"].get("top", "")) == "hinge_1", "hinge_1 snaps into the top socket: %s" % [p["placed"]])
	_check(_v(p["pieces"]["hinge_1"]).distance_to(_v(p["slots"]["top"])) < 2.0, "the snapped hinge sits on the socket centre")
	# The occupied socket is not a target.
	await _drop_hinge_into("hinge_2", "top")
	p = _probe()
	_check(String(p["placed"].get("top", "")) == "hinge_1" and not p["placed"].values().has("hinge_2"), "an occupied socket refuses a second hinge: %s" % [p["placed"]])
	# Middle by drag; bottom by click-click (in hand, then a click at the socket).
	await _drop_hinge_into("hinge_2", "middle")
	p = _probe()
	await _click(_v(p["pieces"]["hinge_3"]))
	_check(String(_probe()["carry"]) == "hinge_3", "a click on a tray hinge takes it in hand")
	await _move(_v(p["slots"]["bottom"]) + Vector2(-10, 20))
	_check(int(_probe()["cursor"]) == Control.CURSOR_CAN_DROP, "a hinge in hand: closed-hand cursor")
	await _click(_v(p["slots"]["bottom"]) + Vector2(-10, 20))
	await _wait(0.2)
	p = _probe()
	_check(p["placed"] == {"top": "hinge_1", "middle": "hinge_2", "bottom": "hinge_3"}, "three hinges in three sockets: %s" % [p["placed"]])
	# A click on a placed hinge takes it back to the tray; drag it back.
	await _click(_v(p["pieces"]["hinge_2"]))
	await _wait(0.35)
	p = _probe()
	_check(not p["placed"].has("middle"), "a click on a placed hinge returns it to the tray: %s" % [p["placed"]])
	_check(_v(p["pieces"]["hinge_2"]).distance_to(_v(p["tray"]["hinge_2"])) < 2.0, "…and it is back in the tray")
	await _drop_hinge_into("hinge_2", "middle", Vector2(-20, -25))
	_check(_probe()["placed"].size() == 3, "hinge_2 back in the middle socket")
	# Threshold: click on the V notch brings it under the door's mark.
	p = _probe()
	await _click(_v(p["marks"][2]))
	await _wait(0.3)
	p = _probe()
	_check(int(p["mark"]) == 2, "a click on the V notch aligns it under the door's mark: mark=%d" % int(p["mark"]))
	_check(absf(_v(p["marks"][2]).x - _v(p["anchor"]).x) < 1.0, "the V notch is exactly under the door's mark after the click")
	# Close the door with the handle → winter.
	await _click(_v(p["handle"]))
	await _frames(3)
	p = _probe()
	_check(bool(p["solved"]) and String(p["view"]) == "winter", "a click on the handle closes the door: solved, winter (%s)" % [p])
	var closed: bool = await _wait_until(func(): return not sr.puzzle_open, 25.0)
	_check(closed, "the close-up leaves by itself after success")
	# M05's line: advanced with the mouse on the dialogue box.
	for i in 10:
		if sr.current_beat.is_empty():
			break
		var dc: Dictionary = ui.call("probe_positions").get("dialogue_click", {})
		await _click(_v(dc) if not dc.is_empty() else Vector2(960, 1000))
		await _frames(3)
	await _frames(4)
	_check(gs.has_flag("done_M05") and gs.has_flag("door_school_installed"), "M05 done, the door installed")
	_check(not gs.has_item("door_hinges"), "the set of hinges is consumed")
	Engine.time_scale = 1.0


func _test_door_rules() -> void:
	await _to_h3_before_m05()
	Engine.time_scale = 2.0
	if not await _open_door_by_mouse():
		Engine.time_scale = 1.0
		return
	var n0: int = (sfx.get("events") as Array).size()
	var hints: Array = sd.scene_hints("M05")
	# Two hinges + the right notch: not enough.
	await _drop_hinge_into("hinge_1", "top")
	await _drop_hinge_into("hinge_2", "bottom")
	await _slide_beam_to_notch(2)
	var p := _probe()
	_check(int(p["mark"]) == 2, "dragging the beam within the snap distance aligns the V notch: mark=%d" % int(p["mark"]))
	_check(absf(_v(p["marks"][2]).x - _v(p["anchor"]).x) < 1.0, "…and snaps it exactly under the mark")
	await _click(_v(p["handle"]))
	await _frames(2)
	p = _probe()
	_check(not bool(p["solved"]) and int(p["errors"]) == 1 and String(p["view"]) == "wall", "two hinges never pass (three are needed): %s" % [p])
	_check(not bool(p["leaf"]), "a wrong close: the wall is seen behind the leaf for a moment")
	await _wait(1.8)
	_check(bool(_probe()["leaf"]), "…then the leaf is back to work on")
	# Three hinges + a wrong (straight) notch: not accepted either.
	await _drop_hinge_into("hinge_3", "middle")
	await _slide_beam_to_notch(1, -10.0)
	p = _probe()
	_check(int(p["mark"]) == 1, "a straight notch under the mark is the chosen one (wrong): mark=%d" % int(p["mark"]))
	await _click(_v(p["handle"]))
	await _frames(2)
	p = _probe()
	_check(not bool(p["solved"]) and int(p["errors"]) == 2, "a wrong notch never passes: %s" % [p])
	_check(String(p["hint"]) == String(hints[0]) if not hints.is_empty() else true, "after the second error the drawing hint shows: '%s'" % String(p["hint"]))
	# A beam left between notches = no notch chosen.
	await _wait(1.8)
	p = _probe()
	var grab := _v(p["beam"])
	await _drag(grab, grab + Vector2(80, 0), 4)
	_check(int(_probe()["mark"]) == -1, "the beam left between notches chooses none: mark=%d" % int(_probe()["mark"]))
	# Right notch by drag, the button «Закрыть дверь» (duplicate of the handle) → success.
	await _slide_beam_to_notch(2, -20.0)
	_check(int(_probe()["mark"]) == 2, "V notch aligned again")
	await _click(_v(_probe()["check"]))
	await _frames(2)
	_check(bool(_probe()["solved"]), "three hinges + the V notch: the door closes (button duplicate)")
	var s := _sounds_since(n0)
	var pz: Dictionary = sr.puzzle.get("spec", {})
	for k in ["take", "snap", "return", "beam", "close_error", "close_success"]:
		var sid := String(pz.get("sounds", {}).get(k, ""))
		_check(s.has(sid), "sound '%s' (%s) played: %s" % [k, sid, s])
	await _click(_v(_probe()["close"]))
	await _frames(2)
	_check(not sr.puzzle_open, "«Закрыть» (mouse) leaves the close-up")
	Engine.time_scale = 1.0


func _count_in_inventory(id: String) -> int:
	var n := 0
	for it in gs.inventory:
		if String(it) == id:
			n += 1
	return n


func _test_save_load() -> void:
	await _to_h3_before_m05()
	Engine.time_scale = 2.0
	if not await _open_door_by_mouse():
		Engine.time_scale = 1.0
		return
	await _drop_hinge_into("hinge_1", "top")
	await _drop_hinge_into("hinge_2", "middle")
	_check(_probe()["placed"].size() == 2, "two hinges placed before the save")
	_check(rm.save_game(SLOT), "save while the close-up is open (as an autosave would)")
	_check(_count_in_inventory("door_hinges") == 1, "the set stays in the bag while hinges sit in the frame")
	_check(rm.load_game(SLOT), "load")
	await _frames(4)
	_check(not sr.puzzle_open and not cp.visible, "a load closes the close-up (it would act on the old room)")
	_check(_count_in_inventory("door_hinges") == 1, "after load: exactly one set of hinges (%d)" % _count_in_inventory("door_hinges"))
	_check(not gs.has_flag("door_school_installed"), "after load: the door is not installed")
	if not await _open_door_by_mouse():
		Engine.time_scale = 1.0
		return
	var p := _probe()
	_check(p["placed"].is_empty() and p["pieces"].size() == 3, "reopened: three hinges, all in the tray (%s)" % [p["placed"]])
	for pid in p["pieces"].keys():
		_check(_v(p["pieces"][pid]).distance_to(_v(p["tray"][pid])) < 2.0, "%s in its tray place" % pid)
	# Solve, then save/load: consumed for good, never given again.
	await _drop_hinge_into("hinge_1", "top")
	await _drop_hinge_into("hinge_2", "middle")
	await _drop_hinge_into("hinge_3", "bottom")
	await _slide_beam_to_notch(2)
	await _click(_v(_probe()["handle"]))
	await _wait_until(func(): return not sr.puzzle_open, 25.0)
	for i in 10:
		if sr.current_beat.is_empty():
			break
		sr.advance()
		await _frames(2)
	await _frames(3)
	_check(gs.has_flag("done_M05") and not gs.has_item("door_hinges"), "M05 done, hinges consumed")
	_check(rm.save_game(SLOT), "save after M05")
	_check(rm.load_game(SLOT), "load after M05")
	await _frames(4)
	_check(_count_in_inventory("door_hinges") == 0 and gs.has_flag("door_school_installed"), "after load: no hinges in the bag, door installed")
	rm.change_room("H2", "default")
	await _frames(4)
	var box := _hotspot("hinges_box")
	_check(box != null and not box.visible, "the hinges' box in H2 stays empty/hidden: the set is never given twice")
	Engine.time_scale = 1.0


func _test_mirror() -> void:
	await _to_h3_before_m05()
	var mirror_c := _hotspot_center("mirror_home")
	Engine.time_scale = 2.0
	await _click(mirror_c)
	var ok: bool = await _wait_until(func(): return sr.view_open, 20.0)
	Engine.time_scale = 1.0
	_check(ok, "a click on the mirror opens its close-up")
	if not ok:
		return
	await _frames(3)
	_check(cv.visible and cv.call("is_open"), "CloseupView is shown")
	_check(sr.is_busy(), "the close-up holds the input (no walking/hover underneath)")
	_check(String(sr.current_beat.get("text", "")) == sd.text("@H3.mirror_home.use"), "its text (the old photo, the reflection) is shown over it — also when M04 already granted seen_mirror_home: '%s'" % String(sr.current_beat.get("text", "")))
	_check(gs.has_flag("seen_mirror_home"), "the mirror counts as seen")
	_check(cv.layer < ui.layer, "the close-up lies under the dialogue box (layer %d < %d)" % [cv.layer, ui.layer])
	var pr: Dictionary = cv.call("probe")
	_check(bool(pr.get("reflection", {}).get("shares_world", false)), "the reflection renders the live game world")
	_check(String(pr.get("reflection", {}).get("agata", "")) == "idle_0", "Agata in the glass faces it (idle_0): %s" % [pr.get("reflection", {})])
	var gal: SubViewport = cv.get("gallery_vp")
	_check(gal != null and gal.canvas_cull_mask == 1 and player.visibility_layer == 2, "the gallery view draws the room without the player (mask %s, player layer %d)" % [gal.canvas_cull_mask if gal else -1, player.visibility_layer])
	var mat: ShaderMaterial = cv.get("mirror_material")
	_check(mat != null and mat.get_shader_parameter("reflection") is ViewportTexture, "the glass shows the reflection's ViewportTexture")
	_check(cv.get("photo") != null and (cv.get("photo").get_node("Picture") as TextureRect).texture is AtlasTexture, "the old photo (a region of the room's own painting) is next to it")
	# The dialogue box takes the first click; the next click closes the close-up.
	var dc: Dictionary = ui.call("probe_positions").get("dialogue_click", {})
	await _click(_v(dc))
	await _frames(3)
	_check(sr.current_beat.is_empty() and sr.view_open, "a click reads on: the text is over, the mirror stays")
	await _click(Vector2(1300, 600))
	await _frames(3)
	_check(not sr.view_open and not cv.visible, "a click on the close-up closes it")
	_check(player.visibility_layer == 1, "the player's visibility layer is restored (%d)" % player.visibility_layer)
	_check(not sr.is_busy(), "the room takes clicks again")
	# Second look: the look text; «Закрыть» by mouse.
	await _click(mirror_c)
	ok = await _wait_until(func(): return sr.view_open, 20.0)
	_check(ok and String(sr.current_beat.get("text", "")) == sd.text("@H3.mirror_home.look"), "second click: close-up again, with the look text")
	dc = ui.call("probe_positions").get("dialogue_click", {})
	await _click(_v(dc))
	await _frames(2)
	await _click(_v(cv.call("probe").get("close", {})))
	await _frames(2)
	_check(not sr.view_open, "«Закрыть» closes it")
	# Esc (optional extra).
	await _click(mirror_c)
	ok = await _wait_until(func(): return sr.view_open, 20.0)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	var up := esc.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)
	_check(ok and not sr.view_open, "Esc closes it too")
	for i in 5:
		if sr.current_beat.is_empty():
			break
		sr.advance()
		await _frames(2)
	# A load while the mirror is open closes it.
	await _click(mirror_c)
	ok = await _wait_until(func(): return sr.view_open, 20.0)
	_check(rm.save_game(SLOT), "save")
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(not sr.view_open and not cv.visible and player.visibility_layer == 1, "a load closes the mirror close-up and restores the player")


func _test_homography() -> void:
	var View = load("res://scripts/ui/closeup_view.gd")
	var spec: Dictionary = {}
	for h in sd.room("H3").get("hotspots", []):
		if String(h.get("id", "")) == "mirror_home":
			spec = h.get("view", {})
	var fr: Dictionary = spec.get("frame", {})
	var g: Array = fr.get("glass", [300, 714])
	var m: Array = fr.get("margin", [120, 210, 120, 150])
	var o := Vector2(float(m[0]), float(m[1]))
	var gs2 := Vector2(float(g[0]), float(g[1]))
	var dst: Array[Vector2] = [o, o + Vector2(gs2.x, 0), o + gs2, o + Vector2(0, gs2.y)]
	var src: Array[Vector2] = []
	for p in fr.get("glass_quad", []):
		src.append(Vector2(float(p[0]), float(p[1])))
	_check(src.size() == 4, "four glass corners in the data")
	if src.size() != 4:
		return
	var h: PackedFloat64Array = View.homography(dst, src)
	for i in 4:
		var q: Vector2 = View.apply_homography(h, dst[i])
		_check(q.distance_to(src[i]) < 0.01, "corner %d → %s (expected %s)" % [i, q, src[i]])
	var tex: Texture2D = load(String(fr.get("image", "")))
	var c: Vector2 = View.apply_homography(h, o + gs2 / 2)
	_check(Rect2(Vector2.ZERO, tex.get_size()).has_point(c), "the glass centre maps inside the painting")
