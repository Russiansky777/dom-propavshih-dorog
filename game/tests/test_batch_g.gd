extends SceneTree
## Batch G (Director's playtest 23.10, Docs/FEEDBACK_DIRECTOR_2026-10-23b.md) — the story/rooms part that has no test
## of its own elsewhere (H1 → test_h1; G15/G16/C13/C27 → test_day_one; G18/G20/G21/G22 → test_day2; G37 → test_items /
## test_day3; C12 → run_tests):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_g.gd
##   - G17/G28: the rope is where the story says — on Pelageya's stopper until she takes it (M15s); after the knot it runs
##     from the plate ring at the turn over the water (Z3) and her stopper is empty (R1) in every light of days 2–4; the
##     closed boat says why (no road until the rope sits on the plate ring); the lines carry the chain;
##   - G38: no boat ride that just brings you back before the shuttle (R2 back, R3 «К лодке»); with it — the crossing;
##   - G29: M19 — Nina on her porch, Mitya by Ilya's house; after «Пойдём в тепло» she walks off to her door, then the
##     fade, then the room; nobody in two places;
##   - G30: Nina's room at night is lighter (the painted night layer weaker, the candle and the lamp light the room);
##   - G40: the family in Nina's room stands apart (no two figures on top of each other, Agata enters clear of them);
##   - G47: the windlass close-up of M25 has no «Закрыть» / Esc (a closed one left an empty turn);
##   - G31/G33: Nina's letters, the village list and Evdokia's notebooks are written in the handwriting font; the
##     notebooks' pseudo-writing is covered (or the clean pages are in); G32: the notches are on the left post by the clock.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null


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
	await _test("G17/G28: the rope on the stopper until M15s; after the knot — from the plate ring at the turn over the water, the stopper empty; the closed boat says why", _test_rope_where)
	await _test("G38: no boat ride back before the shuttle (R2 back, R3 «К лодке» refuse with a line); with the shuttle the crossing opens", _test_boat_back)
	await _test("G29: M19 — Nina on her porch and Mitya by Ilya's house; after her line she walks off to the door (npc_go), then the fade into the room", _test_nina_walk)
	await _test("G30/G40: Nina's room at night is lighter; the family stands apart, Agata comes in clear of them", _test_family_room)
	await _test("G47: the windlass close-up of the first span cannot be closed half-way", _test_windlass_closable)
	await _test("G31/G33/G32: letters, list and notebooks in the handwriting font, no pseudo-writing; the notches on the left post", _test_handwriting)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch G: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


## Every main scene before `upto` done with its grants and its room conditions (like RoomManager.start_at), + `extra`.
func _flags_before(upto: String, extra: Array = []) -> void:
	sr._on_state_reset()
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == upto:
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for it in sc.get("grants", {}).get("items", []):
			gs.set_flag("has_" + String(it), true)
		for rid in sd.scene_trigger_rooms(id):
			var cw = sd.room(rid).get("scenes", {}).get(id, {}).get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []):
					gs.set_flag(String(f), true)
	for f in ["house_unlocked", "house_open", "h1_shutter_open", "h1_scarf_removed"]:
		gs.set_flag(f, true)
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	return rm.current_room


func _drain(choices: Array = []) -> Array:
	var seen: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and guard < 2400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if sr.is_staging() and (seen.is_empty() or seen[-1] != "stage"):
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		elif b.get("type") == "stage":
			seen.append("stage")
			await process_frame
			continue
		else:
			seen.append("%s:%s" % [String(b.get("speaker", b.get("type", ""))), String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


func _visible(room: Node, path: String) -> bool:
	var n := room.get_node_or_null(path)
	return n != null and (n as CanvasItem).is_visible_in_tree()


func _hotspot(room: Node, id: String) -> Node2D:
	return room.get_node_or_null("Hotspots/" + id)


# --- Tests -------------------------------------------------------------------------------

func _test_rope_where() -> void:
	# Before Pelageya takes it: the rope is drawn on her stopper (the painting), nothing at the turn.
	_flags_before("M15s")
	var r1 := await _enter("R1")
	_check(_visible(r1, "Hotspots/rope") and not _visible(r1, "Hotspots/stopper_empty"), "before M15s the rope is on her stopper")
	for id in ["stopper_empty_dusk", "stopper_empty_day", "stopper_empty_morning"]:
		_check(not _visible(r1, "Layers/" + id), "before M15s no empty-stopper patch (%s)" % id)
	var z3 := await _enter("Z3")
	for id in ["rope_on_ring_dusk", "rope_on_ring_d3", "rope_on_ring_day"]:
		_check(not _visible(z3, "Effects/" + id), "before the knot no rope at the turn (%s)" % id)
	# The lines that carry the chain (G17): why the water, why the boat returns, what the rope on the ring changes, where the rope goes.
	var m14: String = String(sd.scene("M14")["mandatory_lines"][1]["text"])
	_check(m14.contains("вынесет") and m14.contains("дороги нет") and m14.contains("За кольцо канат") and m14.contains("По ней лодка и пойдёт"), "G17: Pavel — the boat comes back for there is no road; the rope on the ring is the road: %s" % m14)
	var ww: String = sd.text("@R1d.pelageya.wait_water")
	_check(ww.contains("со стопора канат сниму") and ww.contains("к опоре"), "G28: Pelageya says where the rope will go: %s" % ww)
	var s15: Array = sd.scene("M15s")["mandatory_lines"]
	_check(String(s15[1]["text"]).contains("канат со стопора сниму") and String(s15[2]["text"]).contains("со стопора канат снимает"), "G28: M15s — the rope taken off her stopper and brought to the plate")
	# After the knot, every light of days 2–4: the rope at the turn from the ring over the water; the stopper empty.
	for st in [["M16s", "dusk", []], ["M23a", "d3", []], ["M25", "d4", []]]:
		_flags_before(String(st[0]), st[2])
		z3 = await _enter("Z3")
		var shown: Array = []
		for id in ["rope_on_ring_dusk", "rope_on_ring_d3", "rope_on_ring_day"]:
			if _visible(z3, "Effects/" + id):
				shown.append(id)
		_check(shown.size() == 1, "%s: one rope at the turn (light of the moment): %s" % [st[0], str(shown)])
		if shown.size() == 1:
			var rope: Line2D = z3.get_node("Effects/" + String(shown[0]) + "/Rope")
			var pier: Rect2 = _rect_of(_hotspot(z3, "pier_plate")) if _hotspot(z3, "pier_plate") != null else Rect2(1160, 500, 320, 120)
			_check(pier.grow(30).has_point(rope.points[0]) and rope.points[rope.points.size() - 1].y < rope.points[0].y - 100.0,
				"%s: the rope starts at the plate on the pier %s and goes up over the water to the far shore: %s → %s" % [st[0], str(pier), str(rope.points[0]), str(rope.points[-1])])
		r1 = await _enter("R1")
		var patches: Array = []
		for id in ["stopper_empty_dusk", "stopper_empty_day", "stopper_empty_morning"]:
			if _visible(r1, "Layers/" + id):
				patches.append(id)
		var ropes: Array = []
		for id in ["rope_from_turn_dusk", "rope_from_turn_d3", "rope_from_turn_d34"]:
			if _visible(r1, "Effects/" + id):
				ropes.append(id)
		_check(patches.size() == 1 and ropes.size() == 1, "%s: at the pier the stopper is empty (one patch: %s) and the rope comes from the turn (%s)" % [st[0], str(patches), str(ropes)])
		_check(not _visible(r1, "Hotspots/rope") and _visible(r1, "Hotspots/stopper_empty"), "%s: the stopper hotspot is the empty stopper" % st[0])
		# Above the river ripple: the ambient water polygons draw the background (with its painted rope) at z 1 — a patch
		# under them left the rope on the water in the web build (web check 23.10).
		if patches.size() == 1:
			var pz: int = (r1.get_node("Layers/" + String(patches[0])) as CanvasItem).z_index
			var wz := -100
			var water: Node = r1.get_node_or_null("Ambient/Water")
			if water != null:
				for w in water.get_children():
					if w is CanvasItem and (w as CanvasItem).is_visible_in_tree():
						wz = maxi(wz, (w as CanvasItem).z_index)
			_check(pz > wz, "%s: the empty-stopper patch (z %d) draws above the river ripple (z %d)" % [st[0], pz, wz])
		# The whole painted rope goes — from the stopper to the far post, over the snowy far bank too (web check 23.10: a
		# piece of it hung from the far post over the water at dusk).
		if patches.size() == 1:
			var used: Rect2i = _layer_image(r1, String(patches[0])).get_used_rect()
			_check(used.position.x <= 690 and used.end.x >= 1280, "%s: the empty-stopper patch spans the rope from the far post to the stopper (x %d–%d of the 1672 canvas)" % [st[0], used.position.x, used.end.x])
		# The patch is cut from the frame shown under it: on days 3–4 that is the batch 9 low-water day frame (G52), not
		# the autumn background — just outside the rope (the soft edge of the patch) its pixels are the frame's own.
		if patches.size() == 1 and _visible(r1, "Layers/water_low_day"):
			var pi: Image = _layer_image(r1, String(patches[0]))
			var fi: Image = _layer_image(r1, "water_low_day")
			var diff := 0.0
			var n := 0
			for y in range(330, 440, 2):
				for x in range(660, 1300, 3):
					var c: Color = pi.get_pixel(x, y)
					if c.a > 0.0 and c.a < 0.23:
						var f: Color = fi.get_pixel(x, y)
						diff += (absf(c.r - f.r) + absf(c.g - f.g) + absf(c.b - f.b)) / 3.0
						n += 1
			_check(n > 50 and diff / maxf(n, 1) < 0.03, "%s: the empty-stopper patch is cut from the low-water day frame under it (edge mismatch %.3f over %d px)" % [st[0], diff / maxf(n, 1), n])
	# The empty stopper says where the rope is (by state); the closed boat says why (C27 / G17). A quiet moment: after M17.
	_flags_before("M18p")
	r1 = await _enter("R1")
	await _drain()
	sr.interact(_hotspot(r1, "stopper_empty"))
	await _frames(2)
	_check(String(sr.current_beat.get("text_key", "")) == "R1.stopper.look_ring" and String(sr.current_beat.get("text", "")).contains("кольцо плиты у поворота"), "the empty stopper: the rope is on the plate ring at the turn: %s" % str(sr.current_beat))
	await _drain()
	_check(sd.text("@R1.exit_R2.closed").contains("нет дороги") and sd.text("@R1.exit_R2.closed").contains("кольцо плиты"), "G17: the closed boat — no road until the rope is on the plate ring")


func _layer_image(room: Node, id: String) -> Image:
	var spr: Sprite2D = room.get_node("Layers/" + id + "/Image")
	var img: Image = spr.texture.get_image()
	if img.is_compressed():
		img.decompress()
	return img


func _rect_of(h: Node2D) -> Rect2:
	var rs: Vector2 = ((h.get_node("Shape") as CollisionShape2D).shape as RectangleShape2D).size
	return Rect2(h.global_position - rs / 2.0, rs)


func _test_boat_back() -> void:
	# The far pier on the night of the crossing: the boat does not take you back yet — Pelageya says so.
	_flags_before("M19")
	var r3 := await _enter("R3", "from_R2")
	var ex = r3.get_node_or_null("Exits/to_R2")
	_check(ex != null and not ex.is_open(), "R3 «К лодке» closed before the shuttle")
	if ex != null:
		sr.use_exit(ex)
		await _frames(2)
		_check(String(sr.current_beat.get("speaker", "")) == "pelageya" and not sr.mechanic_open, "R3: Pelageya refuses, no crossing: %s" % str(sr.current_beat))
		await _drain()
		_check(rm.current_room.room_id == "R3", "still at the far pier")
	# The boat view (R2) has no way back to the pier before the shuttle either.
	var r2 := await _enter("R2", "from_Z3")
	var back = r2.get_node_or_null("Exits/to_Z3")
	_check(back != null and not back.is_open(), "R2 «Назад, к повороту» closed before the shuttle (H36: the boat goes from the turn)")
	if back != null:
		sr.use_exit(back)
		await _frames(2)
		_check(String(sr.current_beat.get("text_key", "")) == "R2.exit_R1.closed", "R2: a line instead of a ride back: %s" % str(sr.current_beat))
		await _drain()
	# From the free day the boat goes both ways along the rope — the crossing close-up, not a bounce.
	_flags_before("M23a")
	r3 = await _enter("R3", "from_R2")
	ex = r3.get_node_or_null("Exits/to_R2")
	_check(ex != null and ex.is_open(), "with boat_shuttle_open the boat at R3 is open")
	if ex != null:
		sr.use_exit(ex)
		await _frames(3)
		_check(sr.mechanic_open and String(sr.mechanic.get("type", "")) == "crossing", "R3 → the crossing close-up (to the near pier)")
		sr.close_mechanic()
		await _frames(2)


func _test_nina_walk() -> void:
	_flags_before("M19")
	gs.set_flag("done_M19", false)
	var went: Array = []
	var on_went := func(id: String): went.append(id)
	sr.npc_went.connect(on_went)
	var o4 := await _enter("O4", "from_R3")
	await _frames(4)
	_check(gs.has_flag("started_M19"), "M19 starts on entering the street")
	_check(_visible(o4, "Hotspots/nina") and _visible(o4, "npc_nina"), "Nina stands on her porch during the meeting")
	_check(_visible(o4, "Hotspots/mitya") and _visible(o4, "npc_mitya"), "Mitya with his lantern by Ilya's house")
	var nina: Node2D = o4.get_node_or_null("npc_nina")
	var door: Rect2 = _rect_of(o4.get_node("Exits/to_O3"))
	var seen := await _drain()
	sr.npc_went.disconnect(on_went)
	_check(went == ["nina"], "after her line Nina walks off (npc_go): %s" % str(went))
	var said := -1
	var stage := -1
	for i in seen.size():
		if String(seen[i]).begins_with("nina:В тепло пойдём"):
			said = i
		if String(seen[i]) == "stage" and stage < 0 and said >= 0:
			stage = i
	_check(said >= 0 and stage > said and stage < seen.size() - 1 and String(seen[stage + 1]).begins_with("agata:Те самые ходики"), "her line on the street, then the walk and the fade, then «Ходики» in the room (%d, %d): %s" % [said, stage, str(seen)])
	_check(rm.current_room.room_id == "O3", "then the room: O3 (%s)" % rm.current_room.room_id)
	_check(_visible(rm.current_room, "Hotspots/nina") and gs.has_flag("m19_nina_home"), "in the room Nina is there (m19_nina_home from the fade)")
	_check(nina == null or not is_instance_valid(nina) or door.grow(80).has_point(nina.global_position), "she walked to her door %s" % str(door))
	# Mitya is not at the far pier at the same time (one place).
	_flags_before("M19")
	gs.set_flag("started_M19", true)
	var r3 := await _enter("R3", "from_O4")
	_check(not _visible(r3, "Hotspots/mitya"), "during M19 Mitya is on the street, not at the far pier")
	var o3 := await _enter("O3", "from_O4")
	_check(not _visible(o3, "Hotspots/nina"), "G41: while Nina is on the porch (M19 before the fade), she is not in her room too")


func _test_family_room() -> void:
	_flags_before("M20", ["started_M20", "wife_came"])
	gs.set_flag("done_M20", false)
	gs.set_flag("morning_day3", false)
	var o3 := await _enter("O3", "from_O4")
	await _frames(3)
	sr._cancel_stage()
	var feet: Dictionary = {}
	for id in ["nina", "ilya", "ilya_wife", "ulyana"]:
		var n: Node2D = o3.get_node_or_null("npc_" + id)
		_check(n != null and n.visible, "%s is in the room" % id)
		if n != null:
			feet[id] = n.global_position
	var ids: Array = feet.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Vector2 = feet[ids[i]]
			var b: Vector2 = feet[ids[j]]
			_check(absf(a.x - b.x) >= 120.0 or absf(a.y - b.y) >= 110.0, "G40: %s and %s are not on top of each other (%s, %s)" % [ids[i], ids[j], str(a), str(b)])
	var spawn: Vector2 = o3.get_spawn("from_O4").global_position
	for id in ids:
		_check(absf((feet[id] as Vector2).x - spawn.x) >= 170.0, "G40: Agata comes in clear of %s (spawn %s, feet %s)" % [id, str(spawn), str(feet[id])])
	# G30: at night the painted night layer is weaker and the candle and the lamp light the room.
	var night: Node = o3.get_node_or_null("Layers/night")
	_check(night != null and night.is_visible_in_tree(), "the night layer is on (tod_dark)")
	if night != null:
		var spr: Sprite2D = night.get_node("Image")
		_check(spr.modulate.a <= 0.8, "G30: the night layer is lighter (alpha %.2f)" % spr.modulate.a)
	var lights: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/lights/O3.json"))
	var room_light := 0.0
	for s in lights.get("sources", []):
		if String(s.get("type", "")) == "point" and Array(s.get("if", [])).has("tod_dark"):
			room_light += float(s.get("energy", 0.0)) * float(s.get("radius", 0.0)) / 1000.0
	_check(room_light >= 0.6, "G30: the candle and the lamp light the room (energy × radius %.2f)" % room_light)


func _test_windlass_closable() -> void:
	var spec: Dictionary = {}
	for m in sd.scene("M25").get("mechanics", []):
		if String(m.get("spec", {}).get("type", "")) == "windlass":
			spec = m["spec"]
	_check(not spec.is_empty() and spec.get("closable", true) == false, "G47: the windlass close-up of M25 is not closable")
	sr.open_mechanic(spec, "test_windlass")
	await _frames(3)
	var mv: Node = main_node.get_node_or_null("MechanicView")
	var btn = mv.get("close_button") if mv != null else null
	_check(btn != null and not (btn as Control).visible, "G47: no «Закрыть» on the windlass")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	_check(sr.mechanic_open, "G47: Esc does not close it either")
	sr.close_mechanic()
	await _frames(2)


func _font_path(lbl: Control) -> String:
	var f: Font = lbl.get_theme_font("font")
	return f.resource_path if f != null else ""


func _test_handwriting() -> void:
	var hand: Font = load("res://assets/fonts/bad_script/BadScript-Regular.ttf")
	_check(hand != null, "the handwriting font is in the game (Bad Script, SIL OFL)")
	for c in "Агата, доченька. Ёжик — № «твой» ЪЬЩ":
		_check(hand.has_char(c.unicode_at(0)), "Bad Script has «%s»" % c)
	_flags_before("M21b", ["done_M21"])
	var o3 := await _enter("O3", "from_O4")
	var cv: Node = main_node.get_node("CloseupView")
	for hid in ["nina_letters", "notebooks", "village_list"]:
		var h := _hotspot(o3, hid)
		_check(h != null and h.visible, "%s is there" % hid)
		if h == null:
			continue
		sr.open_view(h.data["view"], hid)
		await _frames(3)
		var texts: Array = []
		for lb in cv.find_children("Text*", "Label", true, false):
			if (lb as Label).text.strip_edges() != "":
				texts.append(lb)
		var n_hand := 0
		for lb in texts:
			if _font_path(lb).ends_with("BadScript-Regular.ttf"):
				n_hand += 1
		_check(texts.size() > 0 and n_hand == texts.size(), "%s: every written text is in the handwriting font (%d of %d)" % [hid, n_hand, texts.size()])
		if hid == "notebooks":
			# The pseudo-writing at the top of the left page: either the clean pages (batch 9) or paper patches over it.
			var clean := ResourceLoader.exists("res://assets/closeups/closeup_notebook_paths_clean.png")
			var covers := cv.find_children("Cover*", "ColorRect", true, false)
			_check(clean or covers.size() > 0, "G33: no pseudo-writing on the notebook pages (clean %s, patches %d)" % [str(clean), covers.size()])
		sr.close_view()
		await _frames(2)
		await _drain()
	# G32: the notches on the left post by the clock — the hotspot and the layer, left of the clock.
	_flags_before("M21", ["started_M20"])
	o3 = await _enter("O3", "from_O4")
	var notch := _hotspot(o3, "notches")
	var clock := _hotspot(o3, "clock")
	_check(notch != null and notch.visible and _rect_of(notch).end.x <= _rect_of(clock).position.x + 5.0, "G32: the notches hotspot is on the left post, left of the clock (%s / %s)" % [str(_rect_of(notch)), str(_rect_of(clock))])
	_check(_visible(o3, "Layers/notches_left"), "G32: the notches are drawn on the left post")
