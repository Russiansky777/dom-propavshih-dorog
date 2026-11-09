extends SceneTree
## Director's playthrough 02.11, block 1 (Docs/FEEDBACK_DIRECTOR_2026-11-02_map.md; «стр.» — a line of his file of 02.11):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0211.gd
##   стр. 8–10: the school door fits with the hinges and Dunya's drawing in the bag — no bell, no first click on the door
##              (БАГ: it waited for done_M04, which also needs the bell and the door clicked); the drawing is taken
##              from the bench into the bag and leaves it with the hinges once the door hangs; self-check — the old
##              requirement (done_M04) is not met in the same state;
##   стр. 6: Tikhon's shelf at the stove runs UP to the right (left end lower), Tikhon sits on its board;
##   стр. 11: in the class, the door home stops Agata once before the yard (M08) with her line about the other door;
##   стр. 13, 24, 29: Agata turns to Pavel (M13) and to Tikhon (M23d, his node is a puppet); Tamara stands side-on;
##   стр. 15: Agata's watch at mother's mirror — the whole picture turned, XII straight up;
##   стр. 16, 18, 28, fishing: the texts (no «самый день»; no mill signals after «черным-черно»; Ilya does not repeat
##              the shed's words; Ulya tells of Mitya's fishing — «захочешь», the goal says it is optional);
##   стр. 2, 22, 33, 36–38: board letters smaller; Ilya's wife by Ilya; the council's drizzle denser; Ulyana's idle slower
##              and turned right; no life on Agata in the last frame.
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
	await _test("02.11-8/9/10 the school door fits with the hinges and Dunya's drawing — no bell, no first click on the door; the drawing leaves with M05", _test_door)
	await _test("02.11-6 Tikhon's shelf at the stove runs up to the right; Tikhon sits on its board", _test_shelf)
	await _test("02.11-11 the class door home stops Agata once before the yard, with her line; the second click goes home", _test_class_door)
	await _test("02.11-13/24/29 facing: Agata to Pavel (M13) and to Tikhon (puppet, M23d); Tamara side-on, to Nina", _test_facing)
	await _test("02.11-15 Agata's watch at mother's mirror: the whole picture turned, XII straight up", _test_watch)
	await _test("02.11-16/18/28 texts; fishing — Ulya tells of it, optional", _test_texts)
	await _test("02.11-2/22/33/36/37/38 board letters, Ilya's wife, drizzle, Ulyana, the last frame", _test_small)
	# block 2
	await _test("02.11-17 after mother's mirror (d2 dusk): the street, the pier and the turn — one evening's colour (mean RGB within 8 %); self-check — the old grades fail", _test_dusk_colour)
	await _test("02.11-21 Mitya lifts the lantern (M18) and carries it in his hand: the stone's lantern goes, his hand has it (R3 after the line, O4 in M19)", _test_lantern_hand)
	await _test("02.11-28 Mitya comes up to Ilya's shed to help (Q06m) before the workbench is built, then is gone from the street", _test_mitya_shed)
	await _test("02.11-20 the crossing: no painted shore fading in over the boat's view — the pier grows to the last pull, ashore through the black", _test_crossing_end)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== feedback 02.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


# --- Tests -------------------------------------------------------------------------------

func _test_door() -> void:
	_fresh(["done_M01", "done_M02", "done_M03", "house_unlocked", "house_open", "stove_lit", "met_tikhon"])
	await _enter("H2")
	_check(await _use("bench"), "H2: the bench (Dunya's drawings) is there")
	await _finish()
	_check(gs.has_item("door_drawing"), "the bench gives Dunya's drawing into the bag (стр. 8)")
	_check(await _use("hinges_box"), "H2: the box of hinges is there")
	await _finish()
	_check(gs.has_item("door_hinges"), "the hinges are in the bag")
	_check(not gs.has_flag("seen_bell") and not gs.has_flag("seen_school_door") and not gs.has_flag("done_M04"),
			"the bell and the door not looked at — M04 not done (the Director's way: hinges taken, drawing looked at)")
	# self-check: the old requirement of the fit (done_M04) is not met in this very state — the bug of стр. 9
	_check(not sr.requires_met({"flags": ["done_M04"], "items": ["door_hinges"]}), "self-check: the old requirement (done_M04) fails here")
	var pz: Dictionary = _hotspot("H3", "school_door").get("puzzle", {})
	_check((pz.get("requires", {}).get("flags", []) as Array).is_empty(), "the fit asks no flags, only things in the bag: %s" % str(pz.get("requires")))
	await _enter("H3", "from_H1")
	await _finish()
	_check(await _use("school_door", "door_hinges"), "H3: the school door is there")
	await _frames(2)
	_check(sr.puzzle_open, "the hinges on the door open the fit — without the bell or a first click on the door (стр. 9–10)")
	if sr.puzzle_open:
		sr.puzzle_place("hinge_1", "top")
		sr.puzzle_place("hinge_2", "middle")
		sr.puzzle_place("hinge_3", "bottom")
		sr.puzzle_set_mark(2)
		_check(sr.puzzle_check(), "the right fit succeeds")
		sr.close_puzzle()
	await _finish()
	_check(gs.has_flag("door_school_installed") and gs.has_flag("done_M05"), "the door hangs (M05)")
	_check(not gs.has_item("door_drawing") and not gs.has_item("door_hinges"), "the drawing leaves the bag with the hinges (стр. 8: «как дверь откроем — убрать»)")
	_check(gs.has_flag("done_M04"), "M04 is closed with M05 — it never plays after the door hangs")
	_check(ResourceLoader.exists("res://assets/icons/door_drawing.png"), "the drawing has its bag icon")


func _test_shelf() -> void:
	var tex: Texture2D = load("res://assets/rooms/H1/state_shelf_A.png")
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	var left := _top_at(img, used.position.x + 12)
	var right := _top_at(img, used.end.x - 12)
	# 02.11 вечер, № 3: «совсем немного выровнять» — still not down to the right, the slope itself is checked in
	# test_feedback_0211b «0211b-3» (0,5–2,8°)
	_check(left > 0 and right > 0 and left >= right, "the board's top does not run down to the right: left end y %d, right end y %d (стр. 6)" % [left, right])
	# Tikhon's feet on the board: within its width and at its top (screen = canvas × 1920/1672)
	var k := 1920.0 / 1672.0
	var feet := Vector2.ZERO
	for p in JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/tikhon.json"))["place"]["H1"]:
		if (p.get("if", []) as Array).has("q04_corner_stove"):
			feet = Vector2(float(p["feet"][0]), float(p["feet"][1]))
	var board := Rect2(Vector2(used.position) * k, Vector2(used.size) * k)
	_check(feet.x > board.position.x + 20 and feet.x < board.end.x - 20, "Tikhon's feet over the board: x %.0f in %.0f..%.0f" % [feet.x, board.position.x, board.end.x])
	var top_mid := float(_top_at(img, int(feet.x / k))) * k
	_check(absf(feet.y - (top_mid + 25.0)) < 30.0, "Tikhon sits on the board's top: feet y %.0f, board top there %.0f" % [feet.y, top_mid])


func _test_class_door() -> void:
	_fresh(["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "door_school_installed", "house_unlocked", "house_open",
			"done_M06", "seen_class_traces", "done_M07", "knows_crossing_plan"])
	await _enter("O1", "from_H3")
	await _finish()
	var ex: Node = rm.current_room.get_node_or_null("Exits/to_H3")
	_check(ex != null, "O1: the door home")
	if ex == null:
		return
	sr.use_exit(ex)
	var seen := await _finish()
	await _frames(3)
	_check(rm.current_room.room_id == "O1", "first time: Agata stays in the class")
	_check(seen.any(func(t): return t.contains("вторая во двор")), "her line about the other door: %s" % str(seen))
	sr.use_exit(ex)
	await _frames(6)
	await physics_frame
	_check(rm.current_room.room_id == "H3", "second click: home to the gallery")
	# after the yard (M08) no stop at all
	_fresh(["done_M05", "door_school_installed", "done_M07", "done_M08"])
	await _enter("O1", "from_H3")
	await _finish()
	sr.use_exit(rm.current_room.get_node("Exits/to_H3"))
	await _frames(6)
	_check(rm.current_room.room_id == "H3" and not gs.has_flag("o1_yard_hint"), "after the yard the door home just goes home")


func _test_facing() -> void:
	var st: Array = sd.scene("M13").get("stage", [])
	_check(st.any(func(s): return int(s.get("at", -1)) == 0 and (s.get("npc_face", []) as Array).any(func(g): return g.get("id") == "agata" and g.get("face") == "pavel")),
			"M13: Agata turns to Pavel from his first line (стр. 13)")
	var st2: Array = sd.scene("M23d").get("stage", [])
	_check(st2.any(func(s): return (s.get("npc_face", []) as Array).any(func(g): return g.get("id") == "agata" and g.get("face") == "tikhon")),
			"M23d: Agata turns to Tikhon on her words to him (стр. 24)")
	# Tikhon's figure is a puppet — turning to him must find it
	_fresh(["done_M01", "done_M02", "done_M03", "house_unlocked", "stove_lit", "met_tikhon"])
	await _enter("H1")
	await _finish()
	var t: Node2D = sr.call("_actor_node", rm.current_room, "tikhon")
	_check(t != null and String(t.name) == "puppet_tikhon", "StoryRunner finds Tikhon's puppet for facing (got %s)" % str(t))
	var tam: Dictionary = _hotspot("O4", "tamara")
	_check(tam.has("face") and float(tam["face"][0]) > float(tam["rect"][0]) + 300.0, "Tamara stands side-on (faces right), not into the frame (стр. 29)")
	var st3: Array = sd.scene("M23a").get("stage", [])
	_check(st3.any(func(s): return (s.get("npc_face", []) as Array).any(func(g): return g.get("id") == "tamara" and g.get("face") == "nina")),
			"M23a: Tamara turns to Nina giving her the letters")


func _test_watch() -> void:
	var cfg: Dictionary = {}
	for h in sd.rooms["H2"]["hotspots"]:
		if h.has("mechanic") and String(h["mechanic"].get("type", "")) == "fast_mirror":
			cfg = h["mechanic"]["watch_dial"]
	var w := PocketWatchDial.new()
	w.configure(cfg)
	_check(absf(rad_to_deg(w.twelve_rad())) < 0.5, "XII straight up at mother's mirror: %.1f°" % rad_to_deg(w.twelve_rad()))
	_check(absf(w.picture_deg) > 20.0, "the whole picture is turned (picture_deg %.1f), not the hands alone" % w.picture_deg)
	w.free()


func _test_texts() -> void:
	_check(not _text("@H4.bed.early_d2").contains("день"), "стр. 16: the bed on the evening of day two — no «самый день»: %s" % _text("@H4.bed.early_d2"))
	var l2 := String(_scene_line("M16s", 2).get("text", ""))
	_check(not l2.contains("пускай") and l2.contains("живые"), "стр. 18: after «черным-черно» — no mill signals, only «три — живые»: %s" % l2)
	var ilya: Dictionary = _hotspot("O4", "ilya")
	var shed: Dictionary = _hotspot("O4", "ilya_workshop")
	var shed_keys: Array = shed.get("use", {}).get("text", [])
	for e in ilya.get("talk", {}).get("intro", []):
		_check(not shed_keys.has(e.get("text")), "стр. 28: Ilya does not repeat the shed's words (%s)" % str(e.get("text")))
	var then: Array = _scene_line("M22", 15).get("then", [])
	_check(then.any(func(x): return String(x.get("speaker", "")) == "ulyana" and String(x.get("text", "")).contains("Митя") and String(x.get("text", "")).contains("Захочешь")),
			"fishing: Ulya tells where Mitya fishes — «захочешь» (optional)")
	var goal := String(sd.scene("M22").get("goal", ""))
	_check(goal.contains("Митя") and goal.contains("захочется"), "fishing: the goal names Mitya as optional: %s" % goal)
	_check(not (sd.scene("M24").get("requires", {}).get("flags", []) as Array).has("o4_mitya_fish"), "the day ends without the fishing")


func _test_small() -> void:
	var board: Dictionary = {}
	for l in sd.rooms["R1"]["layers"]:
		if String(l.get("id", "")) == "signal_board_text":
			board = l
	_check(int(board.get("font_size", 99)) <= 7, "стр. 2: the board's letters at a distance are small (font %s)" % str(board.get("font_size")))
	var il: Dictionary = _hotspot("O3", "ilya")
	var wf: Dictionary = _hotspot("O3", "ilya_wife")
	var cx := func(r): return float(r[0]) + float(r[2]) * 0.5
	_check(cx.call(wf["rect"]) - cx.call(il["rect"]) < 200.0, "стр. 22: Ilya's wife by Ilya (centres %.0f apart, was 235)" % (cx.call(wf["rect"]) - cx.call(il["rect"])))
	var amb = load("res://scripts/ambient/ambient_data.gd").room("F_mill_manager")
	_check(float(amb.get("rain", {}).get("intensity", 0.0)) >= 0.85, "стр. 33: the council's drizzle is dense enough to see")
	var uly = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/ulyana.json"))
	# 08.11: the stance is the second AI's own clip (stance_ulyana_hybrid), accepted by the Director at its own pace
	# (21:21); the 0.6 rate was for the old stance_calm (стр. 36)
	var uly_clip := String(uly["rt3d"]["idle"].get("pool", [{}])[0].get("clip", ""))
	_check(float(uly["rt3d"]["idle"].get("rate", 1.0)) <= 0.7 or uly_clip == "stance_ulyana_hybrid", "стр. 36: Ulyana's idle slower (clip %s, rate %s)" % [uly_clip, str(uly["rt3d"]["idle"].get("rate", 1.0))])
	_check(_hotspot("O1", "ulyana").has("face"), "стр. 37: Ulyana half-turned right in the class")
	var ag: Dictionary = {}
	for l in sd.rooms["EP_dinner"]["layers"]:
		if String(l.get("id", "")) == "agata":
			ag = l
	_check(ag.get("life", true) is bool and not bool(ag.get("life", true)), "стр. 38: Agata in the last frame does not move")


# --- Block 2 ------------------------------------------------------------------------------

## Every scene before `upto`: done with its grants (the flags the story has reached there).
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


## Mean colour of a room's background as drawn (base + full-canvas layers on), under `grade`.
func _bg_mean(room: Node, grade: Color) -> Color:
	var spec: Dictionary = sd.rooms.get(String(room.get("room_id")), {})
	var base: Image = (load(String(spec.get("background", {}).get("image", ""))) as Texture2D).get_image()
	var bgn = room.get_node_or_null("Background")
	if bgn != null:
		for c in ([bgn] + bgn.get_children()):
			if c is Sprite2D and (c as Sprite2D).texture != null:
				base = (c as Sprite2D).texture.get_image()
	if base.is_compressed():
		base.decompress()
	base.convert(Image.FORMAT_RGBA8)
	var full := base.get_size()
	var w := base.get_width() / 8
	var h := base.get_height() / 8
	base.resize(w, h, Image.INTERPOLATE_BILINEAR)
	for box in ["Layers", "Occluders"]:
		var cont = room.get_node_or_null(box)
		if cont == null:
			continue
		for n in cont.get_children():
			if not n.has_method("setup") or not (n as CanvasItem).visible:
				continue
			var spr := n.get_node_or_null("Image") as Sprite2D
			if spr == null or spr.texture == null or spr.position != Vector2.ZERO:
				continue
			var img: Image = spr.texture.get_image()
			if img.is_compressed():
				img.decompress()
			if img.get_size() != full:
				continue
			img.convert(Image.FORMAT_RGBA8)
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
			for y in h:
				for x in w:
					var c := img.get_pixel(x, y)
					if c.a <= 0.0:
						continue
					var d := base.get_pixel(x, y)
					base.set_pixel(x, y, Color(lerpf(d.r, c.r, c.a), lerpf(d.g, c.g, c.a), lerpf(d.b, c.b, c.a), 1.0))
	var acc := Vector3.ZERO
	for y in h:
		for x in w:
			var c := base.get_pixel(x, y)
			acc += Vector3(minf(c.r * grade.r, 1.0), minf(c.g * grade.g, 1.0), minf(c.b * grade.b, 1.0))
	acc /= float(w * h)
	return Color(acc.x, acc.y, acc.z)


func _dusk_means(grades: Dictionary) -> Dictionary:
	var out := {}
	for r in ["Z2", "R1", "Z3"]:
		_fresh()
		_flags_before("M15s")
		gs.set_flag("evening_dusk", true)
		await _enter(r)
		out[r] = _bg_mean(rm.current_room, grades[r])
	return out


func _spread(m: Dictionary) -> float:
	# the largest relative difference of a channel from the three places' mean
	var worst := 0.0
	for ch in 3:
		var avg := 0.0
		for r in m:
			avg += float((m[r] as Color)[ch]) / 3.0
		for r in m:
			worst = maxf(worst, absf(float((m[r] as Color)[ch]) - avg) / maxf(avg, 0.0001))
	return worst


func _test_dusk_colour() -> void:
	var TOD = load("res://scripts/core/time_of_day.gd")
	var now := {}
	for r in ["Z2", "R1", "Z3"]:
		now[r] = TOD.tint_of(TOD.grade(r, "d2_dusk"))
	var m: Dictionary = await _dusk_means(now)
	_check(_spread(m) <= 0.08, "one evening's colour: %s (spread %.1f %%)" % [str(m), _spread(m) * 100.0])
	# self-check: the grades before стр. 17 (Z2 — the class's dusk tint, R1 and Z3 — the brightness-only gains of стр. 41)
	var old := {"Z2": Color.html("#8a90b4"), "R1": Color(1.155, 1.145, 1.075), "Z3": Color(0.87, 0.88, 0.93)}
	var mo: Dictionary = await _dusk_means(old)
	_check(_spread(mo) > 0.08, "self-check: the old grades must be caught (spread %.1f %%)" % (_spread(mo) * 100.0))


func _test_lantern_hand() -> void:
	var st: Array = sd.scene("M18").get("stage", [])
	# 09.11: the flag goes with the clip itself (npc_act[].sets at sets_at — his hand at the lantern), not a cut after it
	_check(st.any(func(s): return int(s.get("at", -1)) == 9 and ((s.get("sets", []) as Array).has("mitya_lantern_taken") \
		or (s.get("npc_act", []) as Array).any(func(g): return (g.get("sets", []) as Array).has("mitya_lantern_taken")))), "M18: on «Митя поднимает фонарь…» the lantern is taken")
	_fresh()
	_flags_before("M18")
	gs.set_flag("started_M18", true)
	gs.set_flag("mitya_lantern_taken", true)
	await _enter("R3")
	await _frames(4)
	var room = rm.current_room
	var stone := false
	for l in room.get_node("Layers").get_children():
		if String(l.name) == "mitya_lantern" and (l as CanvasItem).visible:
			stone = true
	_check(not stone, "the lantern on the stone is gone once he lifts it")
	var mitya: Node2D = room.get_node_or_null("npc_mitya")
	var held = mitya.get("held") if mitya != null else null
	_check(held != null and held.visible and held.pic.texture != null, "Mitya holds the lantern (HeldProp visible with its picture)")
	if held != null and mitya != null:
		var h: float = held.call("_figure_h")
		var d: Vector2 = held.global_position - mitya.global_position
		_check(d.y < -0.2 * h and d.y > -0.7 * h and absf(d.x) < 0.45 * h, "the lantern hangs at his hand: %s from his feet (figure %.0f px)" % [str(d), h])
	# the street in M19: still in his hand
	_fresh()
	_flags_before("M19")
	gs.set_flag("started_M19", true)
	gs.set_flag("mitya_lantern_taken", true)
	await _enter("O4")
	await _frames(4)
	var m2: Node2D = rm.current_room.get_node_or_null("npc_mitya")
	_check(m2 != null and m2.get("held") != null and m2.get("held").visible, "M19 on the street: «Впереди Митя с фонарём» — in his hand")
	# on the free day (fishing) — no lantern
	_fresh()
	_flags_before("M23a")
	gs.set_flag("mitya_lantern_taken", true)
	await _enter("R3")
	await _frames(4)
	var m3: Node2D = rm.current_room.get_node_or_null("npc_mitya")
	_check(m3 == null or m3.get("held") == null or not m3.get("held").visible, "fishing on the free day: no lantern in his hand")


func _test_mitya_shed() -> void:
	_check(sd.scene("Q06m").get("mandatory_lines", []).size() == 1 and String(sd.scene("Q06m")["mandatory_lines"][0].get("speaker", "")) == "mitya", "Q06m: Mitya's line that he came to help")
	_fresh()
	_flags_before("M23a")
	gs.set_flag("met_ilya", true)
	await _enter("O4")
	await _finish()
	_check(await _use("ilya_workshop"), "the shed is there")
	var seen := await _finish()
	_check(seen.any(func(t): return t.contains("подсоблю")), "Mitya says he will help: %s" % str(seen))
	_check(gs.has_flag("done_Q06m") and gs.has_flag("q06_bench_built"), "then the workbench is built (Q06a)")
	var m: Node2D = rm.current_room.get_node_or_null("npc_mitya")
	_check(m == null or not m.visible, "after the build Mitya is not on the street (back at the river)")


func _test_crossing_end() -> void:
	for spec in [sd.scene("M18p")["mechanics"][0]["spec"]]:
		_check(spec.get("arrival_fade", true) == false, "M18p: no arrival painting over the boat's view")
	for e in sd.rooms["R2"].get("exits", []):
		if (e as Dictionary).has("mechanic"):
			_check(e["mechanic"].get("arrival_fade", true) == false, "R2 → %s: no arrival painting" % String(e.get("to")))
