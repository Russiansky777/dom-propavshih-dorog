extends SceneTree
## Director's playthrough 02.11 evening, block A (Docs/FEEDBACK_DIRECTOR_2026-11-02b_map.md; «№» — the map's numbers):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0211b.gd
##   № 0а: the menu's hover and click are the chosen recorded wood (sfx.json ui_hover / ui_click), not the synth;
##   № 5: the chalk is only the desk's — the path loop (M08) no longer gives it; self-check — the old grant gives it;
##   № 7: at dusk the plate on the support has no rope until the knot; self-check — the rope's colour is found on the
##        layer with the rope;
##   № 8, 17: the street's windows dimmer at night, no glow on Ilya's woodpile;
##   № 9: the village list on the table from the morning of day 3 (before Nina's words — a look);
##   № 11: «Пока всё» to Mitya — no line about the bridge again;
##   № 12, 13, 15: fishing — «леска», «Облегчить» over «Хватит», the catches' words: Mitya's on the first, Agata's
##        on the second (in the room, through the real choice);
##   № 18: Mitya comes to the shed three times quicker; № 1: the mill's arrow to the street further left;
##   № 3: the shelf at the stove nearly level (still up to the right); self-check — the mirrored board without the turn;
##   № 22: «Стукнулось о камень!»; № 24, 26, 27: the last frame's shelf smaller, left, level; Tikhon on it; the cup;
##        the fade to black twice as long.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var player: Node = null


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
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _test("0211b-0а the menu's hover and click: the chosen wood (recorded), not the synth; self-check — without the data the synth", _test_menu_sounds)
	await _test("0211b-5 the chalk only from the desk: the path loop (M08) gives none; self-check — the old grant would", _test_chalk)
	await _test("0211b-7 at dusk the plate has no rope until the knot; with the knot — the rope; self-check — rope colour found on the rope layer", _test_plate_rope)
	await _test("0211b-8/17 the street at night: windows dimmer, no glow on Ilya's woodpile", _test_windows)
	await _test("0211b-9 the village list on the table from the morning of day 3", _test_village_list)
	await _test("0211b-11 «Пока всё» to Mitya: no bridge line again", _test_mitya_bye)
	await _test("0211b-12/13/15 fishing: «леска», «Облегчить» over «Хватит», Mitya's word on the first catch, Agata's on the second", _test_fishing)
	await _test("0211b-1/18/22 the mill's arrow left; Mitya to the shed ×3 quicker; «Стукнулось о камень!»", _test_small)
	await _test("0211b-3 the shelf at the stove nearly level, still up to the right; self-check — the board before the turn", _test_shelf_level)
	await _test("0211b-24/26/27 the last frame: the shelf smaller, left, level, Tikhon on it; the cup; the fade twice as long", _test_last_frame)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== feedback 02.11 evening: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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



## Opaque box of a picture (res:// path), canvas px.
func _alpha_box(path: String) -> Rect2i:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	return img.get_used_rect()


## Top edge of a picture's opaque pixels at column x (canvas px), -1 if none.
func _top(path: String, x: int) -> int:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	return _top_at(img, x)


## Pixels of hemp-rope colour (warm, R > G > B, R − B > 0.16) in an opaque picture.
func _rope_pixels(path: String) -> int:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var n := 0
	var r := img.get_used_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r > c.g and c.g > c.b and c.r - c.b > 0.16:
				n += 1
	return n


func _layer(room_id: String, id: String) -> Dictionary:
	for l in sd.rooms.get(room_id, {}).get("layers", []):
		if String(l.get("id", "")) == id:
			return l
	return {}


func _layer_visible(room: Node, id: String) -> bool:
	var n: Node = room.get_node_or_null("Layers/" + id) if room != null else null
	return n != null and (n as CanvasItem).visible


# --- Tests -------------------------------------------------------------------------------

func _test_menu_sounds() -> void:
	var sfx: Node = root.get_node("SfxDirector")
	var got: Array = []
	var cb := func(kind: String, sid: String, file: String): got.append([kind, sid, file])
	sfx.connect("sound_played", cb)
	sfx.call("play_ui", "ui_hover")
	sfx.call("play_ui", "ui_click")
	_check(got.size() == 2 and String(got[0][2]) == "sfx_ui_hover_wood.wav" and String(got[1][2]) == "sfx_ui_click_wood.wav", "the chosen takes play: %s" % str(got))
	var sounds: Dictionary = sfx.get("sounds")
	var keep: Dictionary = sounds["ui_hover"]
	sounds.erase("ui_hover")
	got.clear()
	sfx.call("play_ui", "ui_hover")
	sounds["ui_hover"] = keep
	_check(got.size() == 1 and String(got[0][2]) == "", "self-check: without the data entry — the synth (no file): %s" % str(got))
	sfx.disconnect("sound_played", cb)
	for f in ["sfx_ui_hover_wood.wav", "sfx_ui_click_wood.wav"]:
		_check(ResourceLoader.exists("res://assets/sfx/" + f), "%s in the game" % f)


func _test_chalk() -> void:
	_check(not (sd.scene("M08").get("grants", {}).get("items", []) as Array).has("chalk"), "M08 grants no chalk")
	_fresh()
	_flags_before("M08")
	sr.call("_complete_scene", "M08")
	await _finish()
	_check(not gs.has_item("chalk") and not gs.has_flag("has_chalk"), "the path loop done, the desk not visited: no chalk in the bag")
	# the desk still has it
	await _enter("O1")
	await _finish()
	var cd: Node = rm.current_room.find_child("chalk_desk", true, false)
	_check(cd != null and (cd as CanvasItem).is_visible_in_tree(), "the chalk still lies on the desk")
	_check(await _use("chalk"), "the desk's chalk is there to take")
	await _finish()
	_check(gs.has_item("chalk"), "taken from the desk — in the bag")
	# self-check: the old data (M08 grants chalk) gives it without the desk
	_fresh()
	_flags_before("M08")
	var g: Dictionary = sd.scene("M08")["grants"]
	var keep: Array = g.get("items", [])
	g["items"] = ["chalk"]
	sr.call("_complete_scene", "M08")
	await _finish()
	g["items"] = keep
	_check(gs.has_item("chalk"), "self-check: with the old grant the loop gives the chalk")


func _test_plate_rope() -> void:
	var ring := _layer("Z3", "plate_dusk")
	var rope := _layer("Z3", "plate_rope_dusk")
	_check(not ring.is_empty() and not rope.is_empty(), "two plate layers")
	var n_ring := _rope_pixels(String(ring.get("image", "")))
	var n_rope := _rope_pixels(String(rope.get("image", "")))
	_check(n_ring <= 8, "the plate before the knot has no rope: %d rope-coloured px" % n_ring)
	_check(n_rope >= 150, "self-check: the rope's colour is found on the layer with the rope (%d px)" % n_rope)
	var rb := _alpha_box(String(ring.get("image", "")))
	var ob := _alpha_box(String(rope.get("image", "")))
	_check(ob.grow(4).encloses(rb) and rb.size.x >= 50, "the plate and the ring in the same place: %s within %s" % [str(rb), str(ob)])
	_fresh()
	_flags_before("M15")
	gs.set_flag("evening_dusk", true)
	gs.set_flag("rope_on_ring", false)
	await _enter("Z3")
	await _finish()
	_check(_layer_visible(rm.current_room, "plate_dusk") and not _layer_visible(rm.current_room, "plate_rope_dusk"), "at dusk before the knot: the plate, no rope")
	gs.set_flag("rope_on_ring", true)
	await _enter("Z3")
	await _finish()
	_check(_layer_visible(rm.current_room, "plate_rope_dusk") and not _layer_visible(rm.current_room, "plate_dusk"), "after the knot: the rope on the ring")


func _test_windows() -> void:
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/lights/O4.json"))
	var woodpile := Rect2(1600, 470, 110, 100)
	var n := 0
	for s in doc["sources"]:
		if String(s.get("type", "")) != "glow":
			continue
		n += 1
		var r: Array = s["rect"]
		var rr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		_check(not rr.intersects(woodpile), "%s on Ilya's woodpile %s" % [s["id"], str(rr)])
		_check(float(s["params"].get("glass", 1.0)) <= 0.5 and float(s["params"].get("halo", 1.0)) <= 0.12, "%s dimmer: glass %s halo %s" % [s["id"], str(s["params"].get("glass")), str(s["params"].get("halo"))])
	_check(n >= 13, "the windows still lit at night: %d" % n)


func _test_village_list() -> void:
	_fresh()
	_flags_before("M21")
	gs.set_flag("morning_day3", true)
	await _enter("O3")
	await _finish()
	_check(_layer_visible(rm.current_room, "village_list"), "the morning of day 3, before Nina's words: the list on the table")
	_check(await _use("village_list"), "the list can be clicked")
	var seen := await _finish()
	_check(seen.any(func(t): return t.contains("Мама записала")) and not gs.has_flag("o3_read_village_list"), "before M21 — a look, not the reading: %s" % str(seen))
	gs.set_flag("morning_day3", false)
	await _enter("O3")
	_check(not _layer_visible(rm.current_room, "village_list"), "the night before: no list yet")


func _test_mitya_bye() -> void:
	_fresh()
	_flags_before("M23a")
	await _enter("R3")
	await _finish()
	_check(await _use("mitya"), "Mitya on the jetty")
	var seen: Array[String] = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var ids: Array = (b.get("options", []) as Array).map(func(o): return String(o.get("id", "")))
			_check(ids.has("leave"), "«Пока всё» is offered: %s" % str(ids))
			seen.append("<choose leave>")
			sr.choose("leave")
		elif not b.is_empty():
			seen.append(String(b.get("text", "")))
			sr.advance()
		await process_frame
	var after: Array = seen.slice(seen.find("<choose leave>") + 1) if seen.has("<choose leave>") else []
	_check(seen.has("<choose leave>"), "the choice came: %s" % str(seen))
	_check(not after.any(func(t): return String(t).contains("По мосту бы пройти")), "after «Пока всё» no bridge line: %s" % str(after))


func _fishing_spec() -> Dictionary:
	for o in _hotspot("R3", "mitya").get("choice", {}).get("options", []):
		if o.get("mechanic", {}).get("type", "") == "fishing":
			return o["mechanic"]
	return {}


func _test_fishing() -> void:
	_check(String(sd.text("@mech.fish.escaped")).contains("леска") and not String(sd.text("@mech.fish.label_fight")).contains("бечёв"), "«леска», not «бечёвка»")
	var sp := _fishing_spec()
	var ea: Array = sp.get("easy_at", [0, 0])
	var easy := Rect2(float(ea[0]), float(ea[1]), 240, 44)
	var stop := Rect2(1680, 990, 200, 56)
	_check(easy.end.y <= stop.position.y and easy.end.y >= stop.position.y - 20.0 and easy.position.x <= stop.position.x + 40.0 and easy.end.x >= stop.end.x - 40.0, "«Облегчить» %s right over «Хватит» %s" % [str(easy), str(stop)])
	# in the room, through the real choice
	_fresh()
	_flags_before("M23a")
	await _enter("R3")
	await _finish()
	_check(await _use("mitya"), "Mitya on the jetty")
	var guard := 0
	while not bool(sr.get("mechanic_open")) and guard < 400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			sr.choose("fish")
		elif not b.is_empty():
			sr.advance()
		await process_frame
	_check(bool(sr.get("mechanic_open")), "the fishing opened from the choice")
	var fp: Node = _find_panel(root)
	_check(fp != null, "the fishing panel in the tree")
	if fp == null:
		return
	var words: Array = []
	for k in 2:
		var s0 := words.size()
		fp.call("_catch")
		await _frames(2)
		var g2 := 0
		while not sr.current_beat.is_empty() and g2 < 50:
			g2 += 1
			var b: Dictionary = sr.current_beat
			words.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", b.get("text", "")))])
			sr.advance()
			await process_frame
		if words.size() == s0:
			words.append("<none>")
		fp.call("_restart")
		await _frames(2)
	_check(words.size() >= 2 and String(words[0]).begins_with("mitya:mech.fish.caught"), "the first catch — Mitya's word: %s" % str(words))
	_check(words.any(func(w): return String(w) == "agata:mech.fish.caught_agata"), "the second catch — Agata's: %s" % str(words))
	sr.call("close_mechanic")
	await _finish()


func _find_panel(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("fishing_panel.gd"):
		return n
	for c in n.get_children():
		var f := _find_panel(c)
		if f != null:
			return f
	return null


func _test_small() -> void:
	for e in sd.rooms["M1"].get("exits", []):
		if String(e.get("to", "")) == "Z2":
			_check(float(e.get("cue_at", [999, 0])[0]) < 195.0, "the mill yard's arrow to the street further left: %s" % str(e.get("cue_at")))
	for st in sd.scene("Q06m").get("stage", []):
		for g in st.get("npc_go", []):
			if String(g.get("id", "")) == "mitya":
				_check(float(g.get("s", 99.0)) <= 2.0, "Mitya to the shed in ≤ 2 s (was 6): %s" % str(g.get("s")))
	_check(String(sd.text("@E5.windlass.bump")).begins_with("Стукнулось о камень"), "«Стукнулось о камень!» — no «О, …»: %s" % sd.text("@E5.windlass.bump"))


func _slope_deg(path: String, x0: int, x1: int) -> float:
	var t0 := _top(path, x0)
	var t1 := _top(path, x1)
	return rad_to_deg(atan2(float(t0 - t1), float(x1 - x0)))   # > 0: the right end higher


func _test_shelf_level() -> void:
	var p := "res://assets/rooms/H1/state_shelf_A.png"
	var deg := _slope_deg(p, 350, 480)
	_check(deg > 0.5 and deg <= 2.8, "the shelf's top rises to the right by %.1f° (0,5–2,8; was ≈ 3,8)" % deg)
	# self-check: the board as before the turn (the wide board of pack 12, mirrored on its place) rose ≈ 3,8°
	var src: Image = Image.load_from_file(ProjectSettings.globalize_path("res://").path_join("../assets/incoming/H1_state_shelf_A_wide.png"))
	_check(src != null and not src.is_empty(), "the source board readable")
	if src != null and not src.is_empty():
		src.flip_x()
		var r := src.get_used_rect()
		var xa := r.position.x + 10
		var xb := r.end.x - 25
		var old := rad_to_deg(atan2(float(_top_at(src, xa) - _top_at(src, xb)), float(xb - xa)))
		_check(old > 3.0, "self-check: the mirrored board without the turn rose %.1f° — the check would catch it" % old)
	_check(not sd.rooms["H1"].is_empty(), "H1 there")


func _test_last_frame() -> void:
	var sh := _layer("EP_dinner", "tikhon_shelf")
	var p := String(sh.get("image", ""))
	var box := _alpha_box(p)
	var deg := _slope_deg(p, box.position.x + int(box.size.x * 0.15), box.position.x + int(box.size.x * 0.8))   # the board, not its rounded ends
	_check(absf(deg) <= 1.0, "the shelf nearly level: %.1f°" % deg)
	_check(box.size.x <= 200 and box.get_center().x <= 450, "smaller and further left: %s (was 261 wide, centre ≈ 548)" % str(box))
	var tk := _alpha_box(String(_layer("EP_dinner", "tikhon").get("image", "")))
	_check(tk.get_center().x > box.position.x and tk.get_center().x < box.end.x and absf(float(tk.end.y) - float(box.position.y)) <= 14.0, "Tikhon sits on its board: %s on %s" % [str(tk), str(box)])
	for id in ["cup_blue", "cup_white"]:
		var at: Array = _layer("EP_dinner", id).get("compose", {}).get("at", [0, 0])
		_check(float(at[0]) < 831.0 and float(at[1]) > 509.0, "%s left and lower: %s" % [id, str(at)])
	var menu = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/menu.json"))
	_check(float(menu["credits"].get("fade_to_black_s", 0.0)) >= 4.0, "the last fade twice as long: %s s" % str(menu["credits"].get("fade_to_black_s")))
