extends SceneTree
## Batch I, task I-T3 — art batch 10g in the game and the screen setting (25.10, Docs/tasks/I_T3_import_takes_art.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_i_t3.gd
##   1. screen (§2а): «Полный экран» in the settings and F11 switch full screen ⇄ window, the choice is saved in
##      user://settings.cfg [display] fullscreen and read back; the other settings in the file stay;
##   2. the 10g layers sit where the data says: the bed (H4) and its hotspot over the new drawing, autumn here / snow
##      there by day (Z3, R1 — v2 pictures, the span site without the old frost tint), the tit's cap and boots drawn in
##      (no muting layer), Ulyana's map in the finale without the candle tint; every copy matches its incoming file;
##   3. the hugs: M18 «сына обнимает» and M19 «Нина … обнимает» — black → the frame (F_hug_pelageya / F_hug_nina) →
##      back to the place on the next line;
##   4. Tikhon's mouth: three cut-outs on the head bone, the drawn mouth while silent, a mouth frame while his own
##      voice sounds, back to the drawn mouth after;
##   5. the gallery door (M05): with the leaf open onto the wall — the painted wall (art.wall_view), not a flat colour;
##      the classroom covers it when the door opens into winter;
##   6. the old photo by the home mirror shows little Agata (closeup_h3_old_photo_agata) and her words say so.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var cp: Node = null

const TEST_SETTINGS := "user://test_settings_i_t3.cfg"


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
	cp = main_node.get_node("Closeup")
	rm.autosave_enabled = false
	await _test("I-T3 §2а: full screen / window — the menu switch and F11, saved and read back", _test_screen)
	await _test("I-T3 10g: bed, autumn / snow by day, the tit, Ulyana's map — layers and copies as the data says", _test_layers)
	await _test("I-T3 10g: hugs — M18 and M19 go black → the hug frame → back to the place", _test_hugs)
	await _test("I-T3 10g: Tikhon's mouth moves only while his own voice sounds", _test_mouth)
	await _test("I-T3 10g: the gallery door open onto the wall shows the painted wall (M05_wall_behind)", _test_wall)
	await _test("I-T3 10g: the old photo by the home mirror — little Agata in it, and her words say so", _test_photo)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch I (I-T3): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait_until(cond: Callable, timeout: float = 15.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await process_frame
	return false


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _layer(id: String) -> Node:
	return rm.current_room.get_node_or_null("Layers/" + id) if rm.current_room != null else null


func _room_layer(room_id: String, id: String) -> Dictionary:
	for l in sd.room(room_id).get("layers", []):
		if String(l.get("id", "")) == id:
			return l
	return {}


## Plays the current scene to its end; returns [line_id, frame on screen] for every line shown.
func _drain_frames() -> Array:
	var seen: Array = []
	var fv: Node = main_node.get_node_or_null("FrameView")
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 60000:
		if sr.mechanic_open:
			sr.close_mechanic()
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty() or sr.is_staging():
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")) if not opts.is_empty() else "")
		else:
			var fr := ""
			if fv != null and bool(fv.call("is_open")):
				fr = String(fv.call("probe").get("frame", ""))
			seen.append([String(b.get("line_id", "")), fr])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


# --- 1. Screen ----------------------------------------------------------------------------------

func _test_screen() -> void:
	# loaded at run time: the test script compiles before the autoloads exist (TimingBar refers to StoryData)
	var DisplaySettings: GDScript = load("res://scripts/ui/display_settings.gd")
	var TimingBar: GDScript = load("res://scripts/mechanics/timing_bar.gd")
	var keep_path: String = TimingBar.settings_path
	TimingBar.settings_path = TEST_SETTINGS
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var pre := ConfigFile.new()
	pre.set_value("audio", "voice_volume", 0.6)
	pre.save(TEST_SETTINGS)
	DisplaySettings.load_settings(true)
	_check(not DisplaySettings.fullscreen, "nothing saved — a window")
	var gui: Node = main_node.get_node("GameUi")
	var chk: CheckButton = gui.get("fullscreen_check")
	_check(chk != null and chk.text.find("Полный экран") >= 0, "the settings have «Полный экран» (%s)" % (chk.text if chk != null else "—"))
	_check(chk != null and (gui.get("settings_rows") as Array).has(chk), "it is a settings row (shown in the settings mode)")
	if chk == null:
		TimingBar.settings_path = keep_path
		return
	chk.button_pressed = true
	await _frames(1)
	_check(DisplaySettings.fullscreen, "the switch turns full screen on")
	DisplaySettings.load_settings(true)
	_check(DisplaySettings.fullscreen, "full screen is read back from the settings file")
	var cf := ConfigFile.new()
	cf.load(TEST_SETTINGS)
	_check(bool(cf.get_value("display", "fullscreen", false)) and is_equal_approx(float(cf.get_value("audio", "voice_volume", 0.0)), 0.6),
		"[display] fullscreen saved, the voice volume in the same file kept")
	# F11 — anywhere, the switch follows.
	var ev := InputEventKey.new()
	ev.keycode = KEY_F11
	ev.pressed = true
	root.push_input(ev)
	await _frames(2)
	_check(not DisplaySettings.fullscreen and not chk.button_pressed, "F11 → a window, the menu switch shows it")
	DisplaySettings.load_settings(true)
	_check(not DisplaySettings.fullscreen, "the window is saved too")
	_check(bool(ProjectSettings.get_setting("display/window/size/resizable", false)), "the window can be resized")
	var cc: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3))
	_check(cc.get_luminance() < 0.08, "the margins on 16:10 / 21:9 are dark, not grey (%s)" % str(cc))
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items"
		and String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep", "scale stays canvas_items + keep")
	TimingBar.settings_path = keep_path
	DisplaySettings.load_settings(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))


# --- 2. Layers ----------------------------------------------------------------------------------

func _test_layers() -> void:
	var expect := {"H4": {"state_bed.png": "H4_state_bed_v2.png"},
		"Z3": {"state_water_low_day.png": "Z3_state_water_low_day_v2.png", "state_boat_day.png": "Z3_state_boat_day_v2.png",
			"state_span_site_day4.png": "Z3_state_span_site_day4_v2.png"},
		"R1": {"state_water_low_day.png": "R1_state_water_low_day_v2.png", "state_no_boat_day.png": "R1_state_no_boat_day_v2.png"},
		"EP_dinner": {"ulyana_map.png": "EP_dinner_ulyana_map_v2.png"},
		"F_hug_nina": {"bg.png": "F_hug_nina.png"}, "F_hug_pelageya": {"bg.png": "F_hug_pelageya.png"}}
	for rid in expect:
		var files: Dictionary = sd.room(rid).get("art_source", {}).get("files", {})
		for dst in expect[rid]:
			_check(String(files.get(dst, "")) == "assets/incoming/" + String(expect[rid][dst]), "%s: %s ← %s (%s)" % [rid, dst, expect[rid][dst], files.get(dst, "—")])
			_check(ResourceLoader.exists("res://assets/rooms/%s/%s" % [rid, dst]), "%s/%s is in the game" % [rid, dst])
	# J (29.10, стр. 53): the tit's layer is now drawn by tools/make_bird_layers.py from the same delivery (hat and boots in place)
	_check(String(sd.room("O1").get("art_source", {}).get("_bird_j", "")).contains("make_bird_layers") and ResourceLoader.exists("res://assets/rooms/O1/state_bird_doodles.png"),
		"O1: the tit's doodles come from make_bird_layers.py (batch 9 delivery)")
	_check(not _room_layer("Z3", "span_site_day4").has("modulate"), "Z3: the span site without the old frost tint")
	_check(not _room_layer("EP_dinner", "ulyana_map").has("modulate"), "EP_dinner: Ulyana's map in its own colours")
	_check(_room_layer("O1", "bird_boots_mute").is_empty(), "O1: no muting layer over the tit's boots — they are drawn muted")
	# The bed: the hotspot covers the new drawing (sheet bbox [1192, 500, 1508, 597) × 1920/1672).
	var bed: Dictionary = {}
	for h in sd.room("H4").get("hotspots", []):
		if String(h.get("id", "")) == "bed":
			bed = h
	var r: Array = bed.get("rect", [0, 0, 0, 0])
	var k := 1920.0 / 1672.0
	# J (29.10, стр. 46): the bed layer is ×1.4 about its back right leg (scale_pivot, the layer's own pixels)
	var bl_spec := _room_layer("H4", "bed")
	var sc := float(bl_spec.get("scale", 1.0))
	var pv_a: Array = bl_spec.get("scale_pivot", [1192, 500])
	var pv := Vector2(float(pv_a[0]), float(pv_a[1]))
	var a0 := pv + (Vector2(1192.0, 500.0) - pv) * sc
	var a1 := pv + (Vector2(1508.0, 597.0) - pv) * sc
	var drawn := Rect2(a0 * k, (a1 - a0) * k)
	var hs := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_check(hs.encloses(drawn.grow(-12.0)) and hs.size.x < drawn.size.x + 60.0, "H4: the bed hotspot sits on the new bed (%s vs %s)" % [str(hs), str(drawn)])
	# In the game: H4 shows the bed under the boxes; Z3 by day four — the new day, no tint on the site.
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["house_unlocked", "done_M01", "done_M02", "done_M03"]:
		gs.set_flag(f, true)
	rm.change_room("H4", "default")
	await _frames(4)
	var bl := _layer("bed")
	_check(bl != null and bl.visible, "H4: the bed layer is shown")


# --- 3. Hugs ------------------------------------------------------------------------------------

func _test_hugs() -> void:
	for case in [["M18", "R3", "F_hug_pelageya", 3, ["done_M18p", "ferry_verified"]], ["M19", "O4", "F_hug_nina", 4, ["done_M18", "done_M18p"]]]:
		var sid: String = case[0]
		gs.reset()
		sr.call("_on_state_reset")
		for f in case[4]:
			gs.set_flag(String(f), true)
		rm.change_room(String(case[1]), "default")
		await _frames(4)
		var frames := {}
		var on_frame := func(f, _h): frames[f if f != "" else "(none)"] = String(sr.current_beat.get("line_id", ""))
		sr.frame_changed.connect(on_frame)
		if sr.current_beat.is_empty() and not sr.is_staging() and not sr.is_done(sid):
			sr.start_scene(sid)
		var seen: Array = await _drain_frames()
		sr.frame_changed.disconnect(on_frame)
		_check(sr.is_done(sid), "%s played to the end" % sid)
		var at: int = case[3]
		var hug_line := "%s_%d" % [sid, at]
		var next_line := "%s_%d" % [sid, at + 1]
		var shown := {}
		for s in seen:
			shown[String(s[0])] = String(s[1])
		_check(String(shown.get(hug_line, "")) == String(case[2]), "%s: «обнимает» (%s) is shown over the hug frame %s (%s)" % [sid, hug_line, case[2], str(shown.get(hug_line, "—"))])
		_check(String(shown.get(next_line, "x")) == "", "%s: the next line (%s) is back at the place (%s)" % [sid, next_line, str(shown.get(next_line, "—"))])
		_check(frames.has(String(case[2])) and frames.has("(none)"), "%s: black → frame → back (%s)" % [sid, str(frames)])
		var ok := true
		for s in seen:
			if String(s[0]) != hug_line and String(s[1]) == String(case[2]):
				ok = false
		_check(ok, "%s: the hug frame only over its line" % sid)


# --- 4. Tikhon's mouth --------------------------------------------------------------------------

func _test_mouth() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["house_unlocked", "h1_shutter_open", "stove_lit", "done_M01", "done_M02", "done_M03"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "default")
	await _frames(6)
	var pup: Node = null
	for c in rm.current_room.get_children():
		if c.get("actor_id") != null and String(c.get("actor_id")) == "tikhon" and c.get("mouth_frames") != null:
			pup = c
	_check(pup != null, "Tikhon is in H1")
	if pup == null:
		return
	var m: Sprite2D = pup.get("mouth")
	_check(m != null and (pup.get("mouth_frames") as Array).size() == 3, "three mouth frames on his head")
	if m == null:
		return
	_check(m.get_parent() == (pup.get("bones") as Dictionary).get("head"), "the mouth rides the head bone")
	# his idle accents held off: a random yawn opens the mouth wide on its own (the yawn's mouth is meant) — CI 30.10
	# failed twice so («after the voice — the drawn mouth», «Tamara's voice…»: the yawn, not a voice)
	pup.set("_next_accent", 1e9)
	var acc: AnimationPlayer = pup.get("accent")
	if acc != null:
		acc.stop()
	await _frames(3)
	_check(int(pup.get("mouth_frame")) == 0 and not m.visible, "silent — the drawn mouth")
	var vd: Node = root.get_node("VoiceDirector")
	var st := String(vd.call("play_line", "M03_0", "tikhon", "Мокрое на сухое не клади."))
	_check(st == "" or st == "ok" or bool(vd.call("is_playing")), "his line M03_0 sounds (%s)" % st)
	var moved := {}
	var t0 := Time.get_ticks_msec()
	while bool(vd.call("is_playing")) and Time.get_ticks_msec() - t0 < 4000:
		moved[int(pup.get("mouth_frame"))] = true
		await process_frame
	_check(moved.size() >= 2 and (moved.has(1) or moved.has(2) or moved.has(3)), "while he speaks the mouth changes (%s)" % str(moved.keys()))
	vd.call("stop")
	await _frames(3)
	_check(int(pup.get("mouth_frame")) == 0 and not m.visible, "after the voice — the drawn mouth again")
	# Someone else's voice does not move his mouth.
	var other := String(vd.call("play_line", "M01_0", "tamara", "Батюшки… Агата? Нинина дочка! Ты ж через меня домой письма слала."))
	await _frames(8)
	_check(int(pup.get("mouth_frame")) == 0, "Tamara's voice does not move Tikhon's mouth (%s)" % other)
	vd.call("stop")


# --- 5. The wall behind the gallery door --------------------------------------------------------

func _test_wall() -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for f in ["done_M01", "done_M02", "done_M03", "house_open", "done_M04", "seen_school_door", "seen_workshop",
			"seen_bell", "knows_rule_things_remember", "has_school_door", "has_bell", "has_mirror_home", "seen_mirror_home"]:
		gs.set_flag(f, true)
	sr.grant_item("door_hinges")
	rm.change_room("H3", "default")
	await _frames(6)
	var h := _hotspot("school_door")
	sr.call("open_puzzle", h)
	var ok: bool = await _wait_until(func(): return sr.puzzle_open, 10.0)
	_check(ok, "the door close-up opens")
	if not ok:
		return
	await _frames(3)
	var wall: TextureRect = cp.get("wall_view")
	_check(wall != null and String(wall.texture.resource_path).ends_with("puzzle/M05/wall_behind.png"), "the wall picture is built from data (art.wall_view)")
	if wall == null:
		return
	var dv: ColorRect = cp.get("door_view")
	_check(wall.get_index() > dv.get_index(), "the wall lies over the old flat colour")
	sr.puzzle["view"] = "wall"
	sr.puzzle_state_changed.emit()
	await _frames(3)
	_check(wall.visible, "the leaf opened onto the wall — the painted wall")
	sr.puzzle["solved"] = true
	sr.puzzle["view"] = "winter"
	sr.puzzle_state_changed.emit()
	await _frames(3)
	var wv: TextureRect = cp.get("winter_view")
	_check(not wall.visible and wv != null and wv.visible, "the right door — the winter classroom, not the wall")
	await _wait_until(func(): return not sr.puzzle_open, 12.0)
	sr.call("_on_state_reset")
	await _frames(2)


# --- 6. The old photo -----------------------------------------------------------------------------

func _test_photo() -> void:
	var view: Dictionary = {}
	for h in sd.room("H3").get("hotspots", []):
		if String(h.get("id", "")) == "mirror_home":
			view = h.get("view", {})
	var ph: Dictionary = view.get("photo", {})
	_check(String(ph.get("image", "")) == "res://assets/closeups/closeup_h3_old_photo_agata.png" and ResourceLoader.exists(String(ph.get("image", ""))),
		"the photo is the 10g picture with little Agata (%s)" % str(ph.get("image", "")))
	var reg: Array = ph.get("region", [])
	_check(reg == [0, 0, 1000, 1180] or reg == [0.0, 0.0, 1000.0, 1180.0], "the whole picture, no crop (%s)" % str(reg))
	var said: String = sd.text("@H3.mirror_home.use")
	_check(said.find("я") >= 0 and said.find("в нём — я") >= 0, "Agata says she is in it (%s)" % said)
