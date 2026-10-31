extends SceneTree
## Headless test of the living room H1 after the Director's notes of 18.10 (data/story/rooms/H1.json,
## game/data/actors/tikhon.json, tools/make_h1_layers.py):
##   godot --headless --path game -s res://tests/test_h1.gd
##   - «печь и клик на неё слишком высоко»: a click on the obvious parts of the stove (oven door, its
##     frame, the hearth with firewood, the side face) picks the stove; the pots above the cornice do not;
##     the stand point is in front of the oven door; the spots on the stove body (shelf sockets, scarf,
##     Tikhon) win where they are;
##   - «Тихон изначально в комнате, а не появляется … на кресле, пока нет полки»: from the first entry
##     (no flags) the puppet and its hotspot are visible, sitting on the armchair cushion (feet on opaque
##     cushion pixels, seat height plausible by the room depth), drawn above the chair and under the near
##     armrest; a click on his body picks him; M03 still starts with the third step (scarf), plays his
##     lines once, does not repeat after loading, grants nothing twice, and he stays in the armchair;
##   - «полка … широкой частью прилегать к печи»: after Q04 A he sits on the shelf on the stove side face
##     (layer on the face, not a bench in the room); after Q04 B (coordinator 18.10: the ChatGPT B shelf
##     hung over the hot oven door) on the shelf on the wall left of the porch door above the side table —
##     off the stove and the oven door, the tail away from the stove; the hotspot follows him (states
##     rect/stand); a loaded save puts him back;
##   - «дырки для полки должны быть изначально»: the sockets layers (stove side, wall by the table) are
##     visible until their shelf is installed and hidden after; the stove look text mentions them;
##   - «быть побольше»: ≈ 0.33 of Agata's height at his floor depth;
##   - exits: the only door drawn in H1 leads to the porch (Z2, cue door); the gallery has no door in the
##     art — mark «down» at the bottom edge (behind the viewer); the attic — mark «up» under the ceiling in
##     the stove corner (H4 comes back down), not a second «down» at the bottom edge.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var player: Node2D = null
var SLOT := "test_h1_%d" % OS.get_process_id()
var spec: Dictionary = {}       # game/data/actors/tikhon.json
var room_spec: Dictionary = {}  # rooms/H1.json


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
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/tikhon.json"))
	room_spec = sd.room("H1")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("Stove: a click on the oven door, its frame, the hearth and the side face picks the stove; the pots above do not; stand in front of the door", _test_stove_click)
	await _test("Tikhon is in H1 from the start: in the armchair (on the cushion, above the chair, under the near armrest), ≈0.33 of Agata, clickable", _test_tikhon_start)
	await _test("M03 from the armchair: starts with the third step as before, his lines once, nothing twice, not again after loading", _test_m03_once)
	await _test("Q04 A: shelf on the stove side face, sockets hidden, Tikhon on the shelf (hotspot follows), loaded save keeps him there", _test_q04_a)
	await _test("Q04 B: the shelf on the wall by the table (off the stove and the oven door), Tikhon on it, tail away from the stove; sockets", _test_q04_b)
	await _test("Exits: the drawn door → porch (cue door), gallery behind the viewer (mark down), attic up under the ceiling by the stove; a click on the attic mark goes up to H4", _test_exits)
	await _test("G7: shutter closed — Agata does not go into the workshop, the gallery or the attic (one line each, her voice); open — she does", _test_dark_rooms)
	await _test("G9/G11/G14: the shelf says why not now (wet towel; cold stove; dark), Tikhon asks for it in M03, the stove look after the shelf has no sockets", _test_shelf_reasons)
	await _test("G12: the leaning shelf, shelf A and shelf B are one shelf (same board size); the towel lies on the bench, then hangs on the left hook", _test_shelf_sizes)
	await _test("G13: state layers of the stove line up with the base (the open door frame covers the closed door, its foot on the ledge)", _test_stove_align)
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
	print("==== H1: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(flags: Array, items: Array = ["key_house"], pos: Vector2 = Vector2(1200, 900)) -> Node:
	sr._on_state_reset()
	gs.reset()
	gs.set_flag("done_M01", true)
	gs.set_flag("done_M02", true)
	gs.set_flag("house_unlocked", true)   # the house is entered only after the key is applied (18.10)
	for it in items:
		gs.add_item(String(it))
	for f in flags:
		gs.set_flag(String(f), true)
	rm.change_room("H1", "default", pos)
	await physics_frame
	await physics_frame
	await _frames(2)
	return rm.current_room


func _hotspot(room: Node, id: String) -> Node2D:
	return room.get_node_or_null("Hotspots/" + id)


func _puppet(room: Node) -> Node2D:
	var pups: Array = load("res://scripts/actors/puppet_actor.gd").all_in(room)
	return pups[0] if pups.size() == 1 else null


func _place_entry(flags_if: Array) -> Dictionary:
	for e in spec.get("place", {}).get("H1", []):
		if Array(e.get("if", [])) == flags_if:
			return e
	return {}


## Click like the player: walk to the hotspot under `pos`, interact, wait until idle.
## The H1 shutter (G8): opened by the action itself (no latch close-up since 23.10); read the line that follows.
func _open_latch() -> void:
	var g := 0
	while (not gs.has_flag("h1_shutter_open") or not sr.current_beat.is_empty()) and g < 600:
		g += 1
		if not sr.current_beat.is_empty():
			sr.advance()
		await process_frame
	_check(not sr.mechanic_open, "G8: the shutter opens without a close-up mini-game")


func _click(pos: Vector2) -> void:
	player.call("click_at", pos)
	var n := 0
	while n < 2400:
		await process_frame
		n += 1
		if not player.call("is_walking") and not player.call("is_acting"):
			break
	await _frames(2)


## Clicks through the beats (options: first, or the given ids in order); returns "speaker:text" lines.
func _finish(choices: Array = []) -> Array:
	var seen: Array = []
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 200:
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
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text", ""))])
			sr.advance()
		await _frames(1)
	await _frames(3)
	return seen


func _layer_visible(room: Node, id: String) -> bool:
	for path in ["Layers/" + id, "Occluders/" + id]:
		var n := room.get_node_or_null(path)
		if n != null:
			return (n as CanvasItem).is_visible_in_tree()
	return false


## A sprite's picture as an Image in the sprite's own pixels (an AtlasTexture crop of a stand-in — only its region).
func _sprite_image(spr: Sprite2D) -> Image:
	var tex := spr.texture
	if tex is AtlasTexture:
		var img: Image = (tex as AtlasTexture).atlas.get_image()
		if img.is_compressed():
			img.decompress()
		return img.get_region(Rect2i((tex as AtlasTexture).region))
	var im: Image = tex.get_image()
	if im.is_compressed():
		im.decompress()
	return im


## The picture of a layer: its image, or (art ordered, not delivered — batch 9) the first crop of its stand-in.
func _layer_sprite(room: Node, id: String) -> Sprite2D:
	var n := room.get_node_or_null("Layers/" + id)
	if n == null:
		return null
	if n.get_node_or_null("Image") is Sprite2D:
		return n.get_node("Image")
	return n.get_node_or_null("StandIn/Crop0") as Sprite2D


func _rect_of(h: Node2D) -> Rect2:
	var rs: Vector2 = ((h.get_node("Shape") as CollisionShape2D).shape as RectangleShape2D).size
	return Rect2(h.global_position - rs / 2.0, rs)


# --- Tests -------------------------------------------------------------------------------

func _test_stove_click() -> void:
	var room: Node = await _enter([])
	await physics_frame
	var stove := _hotspot(room, "stove")
	_check(stove != null, "H1 has the stove hotspot")
	if stove == null:
		return
	# Obvious places on the stove body (screen 1920x1080): oven door centre, its arch, the white face
	# right of the door, the hearth with firewood, the side face, the base under the door, the rect centre.
	var r := _rect_of(stove)
	var points := {"oven door": Vector2(220, 490), "door arch": Vector2(220, 420), "face right of door": Vector2(330, 470),
		"face left of door": Vector2(100, 480), "hearth (firewood)": Vector2(215, 700), "base under door": Vector2(250, 610),
		"side face": Vector2(470, 400), "rect centre": r.get_center()}
	for k in points:
		var hit = room.pick(points[k])
		_check(hit == stove, "a click on the %s %s must pick the stove, got %s" % [k, str(points[k]), str(hit.name) if hit else "nothing"])
	# Not the top with pots (the old rect began at y 140 and the Director clicked there in vain).
	for p in [Vector2(250, 210), Vector2(450, 230)]:
		var hit = room.pick(p)
		_check(hit != stove, "the pots above the cornice %s are not the stove's click area" % str(p))
	_check(r.position.y >= 270.0 and r.end.y >= 740.0, "stove rect covers the body from the cornice down to the floor: %s" % str(r))
	# Stand point in front of the oven door, on the floor, left of the armchair.
	var sp: Vector2 = stove.call("get_stand_position")
	_check(sp.x > 120.0 and sp.x < 330.0 and sp.y > 775.0 and sp.y < 830.0, "Agata stands in front of the oven door: %s" % str(sp))
	# A real click on the oven door walks Agata there and lights the stove (first use).
	await _click(Vector2(220, 490))
	_check(player.global_position.distance_to(sp) < 12.0, "after the click Agata is at the stove stand %s, got %s" % [str(sp), str(player.global_position.round())])
	_check(gs.has_flag("stove_lit"), "the click on the oven door used the stove (stove_lit)")
	await _finish()
	# Spots on the stove body win where they are.
	var sc := _hotspot(room, "scarf")
	_check(sc != null and room.pick(sc.global_position) == sc, "the wet scarf on the bench wins over the stove")
	var shelf := _hotspot(room, "shelf")
	_check(shelf != null and (not shelf.visible or room.pick(shelf.global_position) == shelf), "H12: the shelf on the bench (once the scarf is off) wins over the stove")
	var t := _hotspot(room, "tikhon")
	_check(t != null and room.pick(t.global_position) == t, "Tikhon wins over everything under him")
	# The stove look tells about the sockets (one phrase, no instruction).
	var look := String(sd.text("@H1.stove.look"))
	_check(look.contains("гнёзд") or look.contains("гнезд"), "the stove look mentions the sockets: «%s»" % look)


func _test_tikhon_start() -> void:
	var room: Node = await _enter([])
	var t := _puppet(room)
	var hs := _hotspot(room, "tikhon")
	_check(t != null and hs != null, "H1 holds Tikhon's puppet and hotspot on the first entry")
	if t == null or hs == null:
		return
	_check(not gs.has_flag("started_M03") and t.visible and hs.visible, "Tikhon is there before M03 (no «appearing»)")
	var chair := _place_entry([])
	_check(not chair.is_empty(), "tikhon.json place.H1 has an entry without flags (the armchair)")
	_check(t.global_position.is_equal_approx(Vector2(chair["feet"][0], chair["feet"][1])), "before the shelf he sits in the armchair %s, got %s" % [str(chair.get("feet")), str(t.global_position)])
	# Draw order: above the chair, under the near armrest.
	var chair_layer: CanvasItem = room.get_node_or_null("Occluders/table_chair")
	var arm_layer: CanvasItem = room.get_node_or_null("Occluders/chair_arm")
	_check(chair_layer != null and arm_layer != null, "the chair and its near armrest are separate occluders")
	if chair_layer != null and arm_layer != null:
		_check(chair_layer.z_index < t.z_index and t.z_index < arm_layer.z_index, "z: chair %d < Tikhon %d < armrest %d" % [chair_layer.z_index, t.z_index, arm_layer.z_index])
		# The armrest layer is the chair's own pixels: same texture size, scale and position.
		var cs: Sprite2D = chair_layer.get_node("Image")
		var asp: Sprite2D = arm_layer.get_node("Image")
		_check(cs.texture.get_size() == asp.texture.get_size() and cs.scale.is_equal_approx(asp.scale) and cs.position.is_equal_approx(asp.position),
			"armrest overlay registered with the chair (size %s/%s, scale %s/%s, pos %s/%s)" % [str(cs.texture.get_size()), str(asp.texture.get_size()), str(cs.scale), str(asp.scale), str(cs.position), str(asp.position)])
		# Feet on the cushion: the chair is opaque at the feet and just under them (sits, does not hang).
		var img: Image = cs.texture.get_image()
		if img.is_compressed():
			img.decompress()
		for dy in [0.0, 8.0, 20.0]:
			var q: Vector2 = (t.global_position + Vector2(0, dy) - cs.global_position) / cs.scale
			var a := img.get_pixelv(Vector2i(q)).a if Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(q) else 0.0
			_check(a > 0.9, "the chair is under his feet (+%d px): alpha %.2f at %s" % [int(dy), a, str(q.round())])
		# The armrest does not cover his face: his head (upper third) is free of armrest pixels.
		var aimg: Image = asp.texture.get_image()
		if aimg.is_compressed():
			aimg.decompress()
		var head: Vector2 = t.global_position + Vector2(0, -t.figure_height_px() * 0.75)
		var qa: Vector2 = (head - asp.global_position) / asp.scale
		var aa := aimg.get_pixelv(Vector2i(qa)).a if Rect2(Vector2.ZERO, Vector2(aimg.get_size())).has_point(qa) else 0.0
		_check(aa < 0.1, "the near armrest does not cover his head %s (alpha %.2f)" % [str(head.round()), aa])
	# Seat height by the room depth: feet above the floor under the chair by a seat (0.25–0.6 m).
	var px_m: float = 345.0 * room.depth_scale(t.depth_y) / 1.657
	var seat_m: float = (t.depth_y - t.global_position.y) / px_m
	_check(seat_m > 0.25 and seat_m < 0.6, "feet on a seat: %.2f m above the floor under the chair" % seat_m)
	# Size: ≈ 0.33 of Agata's height at his floor depth (Director: «быть побольше немного»; was 0.28).
	var ratio: float = t.figure_height_px() / (337.0 * room.depth_scale(t.depth_y))
	_check(absf(ratio - 0.33) < 0.02, "Tikhon ≈ 0.33 of Agata's height, got %.2f" % ratio)
	print("        armchair: feet %s, floor %.0f, seat %.2f m, height %.0f px (%.2f × Agata), z %d, mirror %s" % [str(t.global_position), t.depth_y, seat_m, t.figure_height_px(), ratio, t.z_index, str(t.scale.x < 0)])
	# Clicks on his body pick him (over the chair and the stove rect).
	await physics_frame
	var body: Vector2 = t.global_position + Vector2(0, -t.figure_height_px() * 0.45)
	_check(room.pick(body) == hs, "a click on his body %s picks Tikhon" % str(body.round()))
	_check(_rect_of(hs).has_point(t.global_position + Vector2(0, -2)), "his hotspot rect %s is on the figure (feet %s)" % [str(_rect_of(hs)), str(t.global_position)])
	# Sockets visible, no shelf yet.
	_check(_layer_visible(room, "holes_stove") and room.get_node_or_null("Layers/holes_table") == null and not _layer_visible(room, "shelf_stove"),
		"H13: sockets in one place (stove side), no shelf hung before Q04")


## Tikhon's M03 lines as the bot sees them (text cut like _finish does).
func _m03_lines(speaker: String) -> Array:
	var sd: Node = root.get_node("StoryData")
	var out: Array = []
	for l in sd.scene("M03")["mandatory_lines"]:
		if String(l["speaker"]) == speaker:
			out.append(String(l["text"]))
		# J (стр. 23, 32): Tikhon introduces himself in a `then` line right after his first words
		for t in l.get("then", []):
			if t is Dictionary and String(t.get("speaker", "")) == speaker:
				out.append(String(t.get("text", "")))
	return out


func _test_m03_once() -> void:
	var room: Node = await _enter([])
	var t := _puppet(room)
	var inv_before: int = gs.inventory.size()
	for id in ["shutter", "stove"]:
		await _click(_hotspot(room, id).global_position)
		await _finish()
		if id == "shutter":
			await _open_latch()   # G8 (23.10): a simple action again
	_check(not gs.has_flag("started_M03"), "M03 has not started before the third step")
	await _click(_hotspot(room, "scarf").global_position)
	var seen := await _finish(["ask"])
	var tikhon_lines := seen.filter(func(x): return String(x).begins_with("tikhon:"))
	_check(gs.has_flag("done_M03") and gs.has_flag("met_tikhon"), "M03 done after the scarf: %s" % str(seen))
	var m03_tikhon: Array = _m03_lines("tikhon")
	# K (Director 31.10, 21:24 «давай поправим про Дуню и вещи места… вставку в диалоге одобряю»): + «Дуня всё
	# приговаривала: вещи своё место помнят…» before «Нынче среда?» — nine
	_check(tikhon_lines.size() == m03_tikhon.size() and tikhon_lines.size() == 9 and tikhon_lines.any(func(x): return String(x).contains("вещи своё место помнят")),
		"Tikhon's nine M03 lines (Docs/SCENARIO_FINAL.md M03, with the shelf request G11; J: + «Тихон. При печи смотрителем состою…»; K: + Dunya's saying) play once: %s" % str(tikhon_lines))
	_check(seen.any(func(x): return String(x).begins_with("tikhon:") and String(x).contains("полку мне повесь")), "G11: after the first talk at the lit stove Tikhon asks to hang his shelf: %s" % str(seen))
	_check(seen.any(func(x): return String(x).contains("Вечер долгий")), "«Вечер долгий» in M03")
	_check(seen.any(func(x): return String(x).contains("А ты один здесь?")) and seen.any(func(x): return String(x).contains("И печь тут,")), "«Ты здесь один?» / «Печь тоже здесь.» in M03")
	_check(t != null and t.place_index == spec["place"]["H1"].size() - 1, "after M03 he is still in the armchair (place %d)" % (t.place_index if t else -9))
	var inv_after: int = gs.inventory.size()
	_check(inv_after == inv_before, "M03 grants no items (inventory %d → %d)" % [inv_before, inv_after])
	# Clicking Tikhon now: his questions (home knowledge, M03 «по вопросам»), not M03 again — only about what Agata
	# has seen (C13, ИИ-чтение 23.10): before the gallery and the workshop there is only «Ничего. Дежурь».
	await _click(_hotspot(room, "tikhon").global_position)
	if String(sr.current_beat.get("text_key", "")) == "H1.tikhon.ask_shelf":
		sr.advance()
		await process_frame
	var early: Array = sr.current_options().map(func(o): return String(o.get("id", ""))) if sr.current_beat.get("type", "") == "options" else []
	_check(early == ["tamara", "cream", "spoons", "leave"], "C13: no questions about the door, the bundle or the bell before seeing them: %s" % str(early))
	await _finish(["leave"])
	gs.set_flag("visited_H2", true)
	gs.set_flag("visited_H3", true)
	await _click(_hotspot(room, "tikhon").global_position)
	if String(sr.current_beat.get("text_key", "")) == "H1.tikhon.ask_shelf":
		sr.advance()
		await process_frame
	var later: Array = sr.current_options().map(func(o): return String(o.get("id", ""))) if sr.current_beat.get("type", "") == "options" else []
	_check(later == ["door", "bundle", "bell", "dunya_mend", "tamara", "cream", "spoons", "leave"], "C13: after the gallery and the workshop all four questions: %s" % str(later))
	var again := await _finish(["door"])
	_check(not again.any(func(x): return m03_tikhon.has(String(x).trim_prefix("tikhon:"))), "a click on Tikhon after M03 does not replay M03: %s" % str(again))
	_check(again.has("options:door") and again.any(func(x): return String(x).contains("Нина просила")), "a click on Tikhon after M03 opens his questions: %s" % str(again))
	# Save → new game → load: no scene replays, nothing doubles, he is in the armchair.
	_check(rm.save_game(SLOT), "save in H1 after M03")
	var inv: Array = gs.inventory.duplicate()
	rm.new_game()
	await _frames(3)
	_check(rm.load_game(SLOT), "load the H1 save")
	await physics_frame
	await _frames(4)
	_check(sr.current_beat.is_empty() and not sr.is_busy(), "loading does not start a scene: %s" % str(sr.current_beat))
	_check(gs.inventory == inv, "inventory after load equals the saved one: %s vs %s" % [str(gs.inventory), str(inv)])
	var t2 := _puppet(rm.current_room)
	_check(t2 != null and t2.visible and t2.place_index == spec["place"]["H1"].size() - 1, "after loading he is in the armchair")


func _test_q04_a() -> void:
	var m03 := ["done_M03", "started_M03", "met_tikhon", "house_open", "stove_lit", "h1_shutter_open", "h1_scarf_removed"]
	var room: Node = await _enter(m03)
	var t := _puppet(room)
	var hs := _hotspot(room, "tikhon")
	var shelf := _hotspot(room, "shelf")
	_check(shelf != null and shelf.visible, "the shelf sockets hotspot is there after M03")
	await _click(shelf.global_position)
	var seen := await _finish(["A"])
	_check(gs.has_flag("q04_corner_stove") and gs.has_flag("done_Q04"), "Q04 A chosen: %s" % str(seen))
	await physics_frame
	await _frames(2)
	_check(_layer_visible(room, "shelf_stove") and not _layer_visible(room, "holes_stove"), "the shelf is on the stove, its sockets are covered (hidden)")
	var e := _place_entry(["q04_corner_stove"])
	_check(t.place_index >= 0 and t.global_position.is_equal_approx(Vector2(e["feet"][0], e["feet"][1])), "Tikhon moved onto the shelf %s, got %s" % [str(e.get("feet")), str(t.global_position)])
	_check(t.visible and hs.visible, "Tikhon is visible on the shelf")
	# Defect «полка идёт длинной в комнату»: the layer lies on the stove side face (screen x 400–600),
	# a short shelf seen along the face (≤ 200 px wide, not the 580-px bench), and he sits on it.
	var lay: Sprite2D = _layer_sprite(room, "shelf_stove")
	var img: Image = _sprite_image(lay)
	var used: Rect2i = img.get_used_rect()
	var box := Rect2(lay.global_position + Vector2(used.position) * lay.scale, Vector2(used.size) * lay.scale)
	_check(box.position.x > 380.0 and box.end.x < 620.0 and box.size.x < 200.0 and box.position.y > 430.0 and box.end.y < 600.0,
		"the shelf layer sits on the stove side face (screen box %s)" % str(box))
	_check(box.has_point(t.global_position), "his feet %s are on the shelf (layer box %s)" % [str(t.global_position), str(box)])
	var q: Vector2 = (t.global_position + Vector2(0, 4) - lay.global_position) / lay.scale
	_check(img.get_pixelv(Vector2i(q)).a > 0.5, "the shelf is opaque right under his feet (does not hang in the air)")
	# The hotspot followed him; a click on his body picks him, a click on the shelf below picks the shelf.
	await physics_frame
	var body: Vector2 = t.global_position + Vector2(0, -t.figure_height_px() * 0.45)
	_check(room.pick(body) == hs, "a click on his body on the shelf %s picks Tikhon (rect %s)" % [str(body.round()), str(_rect_of(hs))])
	var done := _hotspot(room, "shelf_done")
	_check(done != null and done.visible and room.pick(Vector2(t.global_position.x + 20, t.global_position.y + 40)) == done, "a click under him on the shelf picks the installed shelf")
	var ratio: float = t.figure_height_px() / (337.0 * room.depth_scale(t.depth_y))
	print("        shelf A: feet %s, floor %.0f, height %.0f px (%.2f × Agata), layer %s" % [str(t.global_position), t.depth_y, t.figure_height_px(), ratio, str(box)])
	# Save/load keeps him on the shelf.
	_check(rm.save_game(SLOT), "save after Q04 A")
	rm.new_game()
	await _frames(3)
	rm.load_game(SLOT)
	await physics_frame
	await _frames(4)
	var t2 := _puppet(rm.current_room)
	_check(t2 != null and t2.global_position.is_equal_approx(Vector2(e["feet"][0], e["feet"][1])), "after loading he is on the shelf by the stove")
	_check(sr.current_beat.is_empty(), "loading does not replay Q04")


func _test_q04_b() -> void:
	# H13 (Director 24.10): one place for the shelf; B is «Не сейчас» — the shelf stays on the bench, Tikhon in his
	# armchair, the story stays open (the choice comes again).
	var room: Node = await _enter(["done_M03", "started_M03", "met_tikhon", "house_open", "stove_lit", "h1_shutter_open", "h1_scarf_removed"])
	sr.interact(_hotspot(room, "shelf"))
	await _frames(3)
	await _finish(["B"])
	var t := _puppet(room)
	var e := _place_entry([])
	_check(gs.has_flag("q04_declined") and not gs.has_flag("done_Q04") and _layer_visible(room, "shelf_on_bench") and not _layer_visible(room, "shelf_stove"),
		"B «не сейчас»: the shelf stays on the bench, Q04 open")
	_check(t != null and t.global_position.is_equal_approx(Vector2(e["feet"][0], e["feet"][1])), "B: Tikhon stays in the armchair %s" % str(e.get("feet")))
	sr.interact(_hotspot(room, "shelf"))
	await _frames(3)
	_check(String(sr.current_beat.get("type", "")) == "options", "the choice comes again after «не сейчас»")
	await _finish(["A"])
	_check(gs.has_flag("done_Q04") and gs.has_flag("q04_corner_stove"), "changed her mind: the shelf by the stove")

func _test_exits() -> void:
	var room: Node = await _enter(["done_M03", "started_M03", "met_tikhon", "house_open", "stove_lit", "h1_shutter_open", "h1_scarf_removed"])
	await physics_frame
	var z2: Node2D = room.get_node_or_null("Exits/to_Z2")
	var h3: Node2D = room.get_node_or_null("Exits/to_H3")
	var h4: Node2D = room.get_node_or_null("Exits/to_H4")
	_check(z2 != null and h3 != null and h4 != null, "H1 has exits to Z2, H3, H4")
	if z2 == null or h3 == null or h4 == null:
		return
	_check(String(z2.get("cue_dir")) == "door" and _rect_of(z2).has_point(Vector2(1000, 420)), "the drawn door (centre 1000,420) is the porch exit, cue door: %s" % str(z2.get("cue_dir")))
	_check(String(h3.get("cue_dir")) == "down" and _rect_of(h3).end.y >= 1072.0, "gallery: mark «down» at the bottom edge (%s, %s)" % [str(h3.get("cue_dir")), str(_rect_of(h3))])
	var r4 := _rect_of(h4)
	_check(String(h4.get("cue_dir")) == "up" and r4.end.y < 300.0 and r4.position.y >= 80.0, "attic: mark «up» under the ceiling, below the top bar (%s, %s)" % [str(h4.get("cue_dir")), str(r4)])
	_check(room.pick(r4.get_center()) == h4, "a click on the attic mark picks the attic exit")
	# Only one exit leaves through the bottom edge now (the attic is no longer a second «down»).
	var downs := 0
	for e in room.get_node("Exits").get_children():
		if String(e.get("cue_dir")) == "down":
			downs += 1
	_check(downs == 1, "one «down» mark in H1 (gallery), got %d" % downs)
	# Real click: Agata walks under it and goes up to the attic.
	await _click(r4.get_center())
	var n := 0
	while rm.current_room.room_id != "H4" and n < 120:
		await process_frame
		n += 1
	await _finish()
	_check(rm.current_room.room_id == "H4", "the attic mark leads to H4, got %s" % rm.current_room.room_id)


## G7 (Director 23.10: «при закрытых ставнях свет из соседней комнаты»): while the shutter is closed the exits to the
## workshop, the gallery and the attic refuse with Agata's own line (rooms/H1.json exits[].requires + closed_text).
func _test_dark_rooms() -> void:
	var room: Node = await _enter([])
	for dark in ["H2", "H3", "H4"]:
		var ex = room.get_node_or_null("Exits/to_" + dark)
		_check(ex != null and not ex.is_open(), "H1→%s closed while the shutter is closed" % dark)
		if ex == null:
			continue
		sr.use_exit(ex)
		await _frames(3)
		var b: Dictionary = sr.current_beat
		_check(String(b.get("text_key", "")) == "H1.exit_%s.dark" % dark and String(b.get("speaker", "")) == "agata",
			"H1→%s: Agata says it is dark — first the shutter: %s" % [dark, str(b)])
		_check(String(b.get("text", "")).to_lower().contains("ставн"), "H1→%s: the line names the shutter: %s" % [dark, String(b.get("text", ""))])
		await _finish()
		await _frames(6)
		_check(rm.current_room.room_id == "H1", "H1→%s: still in the living room" % dark)
	gs.set_flag("h1_shutter_open", true)
	await _frames(3)
	for dark in ["H2", "H3", "H4"]:
		var ex2 = rm.current_room.get_node_or_null("Exits/to_" + dark)
		_check(ex2 != null and ex2.is_open(), "H1→%s open with the shutter open" % dark)


func _beat_key_after(h: Node2D) -> Dictionary:
	sr.interact(h)
	await _frames(3)
	var b: Dictionary = sr.current_beat.duplicate()
	await _finish()
	return b


## G9: the shelf, clicked before its time, speaks of the wet towel on the bench (ни сесть, ни лечь); G11: then of the
## cold stove (or of the dark), and after the first talk at the lit stove Tikhon asks for it and the choice opens;
## G14: the stove after the shelf no longer talks of the mount sockets.
func _test_shelf_reasons() -> void:
	var room: Node = await _enter([])
	var shelf := _hotspot(room, "shelf")
	_check(shelf != null and not shelf.visible, "H12: the shelf lies under the wet scarf — not clickable until the scarf is off")
	gs.set_flag("h1_scarf_removed", true)
	await _frames(2)
	_check(shelf.visible, "H12: the scarf off — the shelf on the bench")
	var b := await _beat_key_after(shelf)
	_check(String(b.get("text_key", "")) == "H1.shelf.not_yet" and String(b.get("text", "")).contains("печь"), "G11: towel gone, stove cold — first the stove: %s" % str(b))
	gs.set_flag("stove_lit", true)
	b = await _beat_key_after(shelf)
	_check(String(b.get("text_key", "")) == "H1.shelf.not_yet_dark", "G11: stove lit, shutter closed — first the shutter: %s" % str(b))
	# M03 lines carry Tikhon's request (data): after them the choice opens.
	var asks := false
	for l in sd.scene("M03")["mandatory_lines"]:
		if String(l.get("speaker", "")) == "tikhon" and String(l.get("text", "")).contains("полку"):
			asks = true
	_check(asks, "G11: M03 has Tikhon asking for the shelf")
	for f in ["h1_shutter_open", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	sr.interact(shelf)
	await _frames(3)
	_check(String(sr.current_beat.get("type", "")) == "options", "after M03 the shelf opens the choice: %s" % str(sr.current_beat))
	await _finish(["A"])
	_check(gs.has_flag("done_Q04"), "Q04 done")
	var stove := _hotspot(room, "stove")
	b = await _beat_key_after(stove)
	_check(String(b.get("text_key", "")) == "H1.stove.look_settled" and not String(b.get("text", "")).contains("гнёзд"), "G14: the stove after the shelf: %s" % str(b))


func _diff_box(node: Node, under: Node) -> Rect2:
	## Screen box of the pixels where two full-canvas layers at the same place differ (the thing one adds to the other).
	var sa: Sprite2D = node.get_node("Image")
	var sb: Sprite2D = under.get_node("Image")
	var ia: Image = _sprite_image(sa)
	var ib: Image = _sprite_image(sb)
	var lo := Vector2i(ia.get_width(), ia.get_height())
	var hi := Vector2i(-1, -1)
	for y in range(0, mini(ia.get_height(), ib.get_height()), 2):
		for x in range(0, mini(ia.get_width(), ib.get_width()), 2):
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.45:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2()
	return Rect2(sa.global_position + Vector2(lo) * sa.scale, Vector2(hi - lo) * sa.scale)


func _used_box(node: Node) -> Rect2:
	## Screen box of the opaque pixels of a layer node: its picture, or the crops of its stand-in (art pending).
	var box := Rect2()
	var first := true
	var sprites: Array = []
	if node.get_node_or_null("Image") is Sprite2D:
		sprites.append(node.get_node("Image"))
	var si := node.get_node_or_null("StandIn")
	if si != null:
		for c in si.get_children():
			if c is Sprite2D:
				sprites.append(c)
	for spr in sprites:
		var img: Image = _sprite_image(spr)
		var u: Rect2i = img.get_used_rect()
		var r := Rect2((spr as Sprite2D).global_position + Vector2(u.position) * (spr as Sprite2D).scale, Vector2(u.size) * (spr as Sprite2D).scale)
		box = r if first else box.merge(r)
		first = false
	return box


## G12: the shelf leaning by the bench and the hung shelf (A on the stove, B by the porch door) are drawn at one size
## (batch 9 art: one 92-px board; until it comes, the old pictures scaled to it in data); the towel lies on the bench
## until taken, then hangs on the LEFT hook (the middle one is Nina's coat) and the bench is bare.
func _test_shelf_sizes() -> void:
	# H12 (Director 24.10, batch 10b): the wet scarf lies over the shelf on the bench; taken — the bare bench and the shelf
	# lying on it (the same 92-px board as the hung shelf A); hung — the shelf by the stove, the bench empty.
	var room: Node = await _enter([])
	_check(_layer_visible(room, "scarf_over_shelf") and not _layer_visible(room, "shelf_on_bench") and not _layer_visible(room, "bench_bare") and not _layer_visible(room, "hook_coat"),
		"before: the scarf over the shelf on the bench, the hook empty")
	_check(room.get_node_or_null("Layers/shelf_leaning") == null and room.get_node_or_null("Layers/shelf_table") == null, "no leaning shelf, no place by the table")
	await _enter(["done_M03", "met_tikhon", "stove_lit", "h1_shutter_open", "h1_scarf_removed"])
	room = rm.current_room
	_check(_layer_visible(room, "shelf_on_bench") and _layer_visible(room, "bench_bare") and not _layer_visible(room, "scarf_over_shelf"), "scarf off: the shelf lies on the bare bench")
	# Batch 11 (30.10): the layer is the whole wide bench with the shelf on it — the shelf is where it differs from the bare bench.
	var lying := _diff_box(room.get_node("Layers/shelf_on_bench"), room.get_node("Layers/bench_bare"))
	await _enter(["done_M03", "met_tikhon", "stove_lit", "h1_shutter_open", "h1_scarf_removed", "q04_corner_stove", "done_Q04"])
	room = rm.current_room
	_check(not _layer_visible(room, "shelf_on_bench") and _layer_visible(room, "bench_bare") and _layer_visible(room, "hook_coat"),
		"after: the shelf is off the bench, the towel on the hook")
	var a := _used_box(room.get_node("Layers/shelf_stove"))
	var towel := _used_box(room.get_node("Layers/hook_coat"))
	_check(towel.get_center().x < 1260.0 and towel.position.y > 220.0 and towel.position.y < 300.0,
		"the towel hangs on the left hook (≈1217, 247 on screen), not the middle one where Nina's coat goes: %s" % str(towel))
	# I-T2 (Director, line 32: «снятая полка крупнее»): the lying shelf is the same board drawn ×1.4 (± 25 %) — nearer the eye
	var lying_k := 1.4
	_check(absf(lying.size.x / lying_k - a.size.x) / a.size.x < 0.25, "the shelf on the bench is the same shelf (%.0f / %.2f vs board %.0f)" % [lying.size.x, lying_k, a.size.x])
	print("        shelf A %s, on the bench %s, towel %s" % [str(a), str(lying), str(towel)])

## G13 (Director 23.10: «топящаяся печь разорвана»): every state layer with `align` (rooms data) puts its detail onto the
## same detail of the background — the frame of the open oven door onto the closed door: foot on the ledge, centred,
## same size (±tol), and its opaque part covers the closed door, which is dark iron in the background.
func _test_stove_align() -> void:
	var room: Node = await _enter(["stove_lit", "h1_shutter_open"])
	var bg: Sprite2D = room.get_node("Background/Image")
	var bimg: Image = bg.texture.get_image()
	if bimg.is_compressed():
		bimg.decompress()
	var n := 0
	for l in room_spec.get("layers", []):
		if not l.has("align"):
			continue
		n += 1
		var al: Dictionary = l["align"]
		var node: Node = room.get_node_or_null("Layers/" + String(l["id"]))
		if node == null:
			node = room.get_node_or_null("Occluders/" + String(l["id"]))
		_check(node != null and (node as CanvasItem).is_visible_in_tree(), "%s is built and shown" % l["id"])
		if node == null:
			continue
		var spr: Sprite2D = node.get_node("Image")
		var img: Image = spr.texture.get_image()
		if img.is_compressed():
			img.decompress()
		var lr: Array = al["layer_rect"]
		var br: Array = al["base_rect"]
		var tol := float(al.get("tol_px", 12))
		var lrect := Rect2(spr.global_position + Vector2(lr[0], lr[1]) * spr.scale, Vector2(lr[2], lr[3]) * spr.scale)
		var brect := Rect2(bg.global_position + Vector2(br[0], br[1]) * bg.scale, Vector2(br[2], br[3]) * bg.scale)
		_check(absf(lrect.end.y - brect.end.y) <= tol, "%s: foot of the detail %.0f on the base's %.0f" % [l["id"], lrect.end.y, brect.end.y])
		_check(absf(lrect.get_center().x - brect.get_center().x) <= tol, "%s: centred %.0f vs %.0f" % [l["id"], lrect.get_center().x, brect.get_center().x])
		_check(absf(lrect.size.x - brect.size.x) <= 2.0 * tol and absf(lrect.size.y - brect.size.y) <= 2.0 * tol, "%s: same size %s vs %s" % [l["id"], str(lrect.size), str(brect.size)])
		# The base detail is what the layer must hide (the closed door: dark iron) …
		var dark := 0
		var total := 0
		for y in range(int(br[1]) + 4, int(br[1] + br[3]) - 4, 6):
			for x in range(int(br[0]) + 4, int(br[0] + br[2]) - 4, 6):
				total += 1
				if bimg.get_pixel(x, y).get_luminance() < 0.35:
					dark += 1
		_check(total > 0 and float(dark) / total > 0.6, "%s: the base detail is the dark closed door (%d/%d dark)" % [l["id"], dark, total])
		# … and every point of it is under an opaque pixel of the layer (nothing of the old state shows).
		var holes := 0
		var probes := 0
		for y in range(int(brect.position.y) + 2, int(brect.end.y) - 2, 5):
			for x in range(int(brect.position.x) + 2, int(brect.end.x) - 2, 5):
				probes += 1
				var q: Vector2 = (Vector2(x, y) - spr.global_position) / spr.scale
				var inside := q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height()
				if not inside or img.get_pixelv(Vector2i(q)).a < 0.5:
					holes += 1
		_check(probes > 0 and holes <= probes / 50, "%s: the layer covers the base detail (%d of %d points uncovered)" % [l["id"], holes, probes])
		print("        %s: detail %s on base %s, uncovered %d/%d" % [l["id"], str(lrect), str(brect), holes, probes])
	_check(n >= 1, "H1 has the stove alignment data")
