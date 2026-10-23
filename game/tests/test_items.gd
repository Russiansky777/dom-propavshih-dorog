extends SceneTree
## Headless test of items and choices after the Director's notes of 18.10:
##   godot --headless --path game -s res://tests/test_items.gd
##   - «дверь от дома открывается и без ключа … в первое вхождение требовалось его применить, он пропадал
##     и дальше дверь оставалась открытой»: Z2 → the front door is locked and names the key; another item
##     does nothing; the key from the bag on the door → unlock text, the key leaves the bag for good
##     (has_key_house stays, a second grant gives nothing), house_unlocked, Agata walks in; the door stays
##     open — after a load too; a new game locks it again;
##   - «где будет стоять фотография — никакой выбор ничего не меняет»: the family photo stands on the stove
##     ledge; «На столе» → it stands on the side table (the ledge is clear), «На полке» → on the corner shelf;
##     the hotspot follows the drawn photo; each option plays Agata's reaction; a load keeps the place;
##     the same for the cups: both on the window sill, the chosen one on the side table (the other stays);
##     V03 «Оставить свою пометку» → the pencil mark on the bird picture, «как есть» → no mark;
##   - «мел … на ученический стол, чтобы было видно»: the chalk lies on a pupil's desk (on the desk's opaque
##     pixels, above the desks layer, ≥ 30 px long), the hotspot is on it and picks it; the old place on the
##     teacher's desk has no chalk (the drawn pieces are patched over) and no hotspot; taken → gone from the
##     desk; written on the board → out of the bag, and M08 does not give it back (the board offers what to write
##     since 22.10 — game/tests/test_day_one.gd covers the three lines and «не писать»).
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var SLOT := "test_items_%d" % OS.get_process_id()


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
	await _test("Key: the front door is locked and names the key; another item does nothing; key on the door → unlock text, out of the bag for good, walks in; open afterwards and after a load; a new game locks it", _test_key)
	await _test("Photo (V01): on the stove ledge; «На столе» → on the side table, «На полке» → on the corner shelf, the ledge clear; hotspot follows; Agata's reaction; a load keeps it", _test_photo)
	await _test("Cups (V01): both on the window sill; the chosen one on the side table above it, the other stays; switching swaps; reaction; a load keeps it", _test_cups)
	await _test("Chalk: on a pupil's desk (visible, above the desks, on the desk), hotspot on it; the teacher's desk has no chalk and no hotspot; taken → gone; board → out of the bag, M08 does not give it back", _test_chalk)
	await _test("V03 / G37: add a scarf, a boat with smoke or a little bridge to the bird (each its own drawing on the poster), or leave it", _test_bird_mark)
	await _test("Voice: the new and changed item lines have recordings the game plays (first person — Agata, the rest — ZAKADR)", _test_voice)
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
	print("==== items: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room_id: String, flags: Array, items: Array = [], pos: Vector2 = Vector2.INF) -> Node:
	sr._on_state_reset()
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	for it in items:
		gs.add_item(String(it))
		gs.set_flag("has_" + String(it), true)
	if pos == Vector2.INF:
		rm.change_room(room_id, "default")
	else:
		rm.change_room(room_id, "default", pos)
	await physics_frame
	await physics_frame
	await _frames(2)
	return rm.current_room


func _drain() -> void:
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 40:
		guard += 1
		if sr.current_beat.get("type") == "options":
			return
		sr.advance()
		await process_frame


func _layer(room: Node, id: String) -> Node:
	var n: Node = room.get_node_or_null("Layers/" + id)
	return n if n != null else room.get_node_or_null("Occluders/" + id)


## Screen rect of the opaque pixels (alpha > 60) of a layer's image (layer canvas drawn at the art scale).
func _layer_rect(room: Node, id: String) -> Rect2:
	var n: Node = _layer(room, id)
	if n == null:
		return Rect2()
	var spr: Sprite2D = n.get_node_or_null("Image")
	var path := ""
	for l in sd.room(room.room_id).get("layers", []):
		if String(l.get("id", "")) == id:
			path = String(l.get("image", ""))
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or spr == null:
		return Rect2()
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in range(0, img.get_height(), 1):
		for x in range(0, img.get_width(), 1):
			if img.get_pixel(x, y).a > 0.24:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2()
	var p0 := spr.position + Vector2(x0, y0) * spr.scale
	var p1 := spr.position + Vector2(x1 + 1, y1 + 1) * spr.scale
	return Rect2(p0, p1 - p0)


func _hotspot(room: Node, id: String) -> Node2D:
	return room.get_node_or_null("Hotspots/" + id)


func _hotspot_rect(h: Node2D) -> Rect2:
	var shape: CollisionShape2D = h.get_node_or_null("Shape")
	if shape == null:
		return Rect2()
	var sz: Vector2 = (shape.shape as RectangleShape2D).size
	return Rect2(h.global_position + shape.position - sz / 2.0, sz)


## The hotspot sits on the drawn thing: the centre of the layer's opaque pixels is inside the hotspot
## rect and a click there picks this hotspot.
func _check_on(room: Node, hotspot_id: String, layer_id: String, what: String) -> void:
	var h := _hotspot(room, hotspot_id)
	var lr := _layer_rect(room, layer_id)
	_check(h != null and h.visible, "%s: hotspot %s visible" % [what, hotspot_id])
	_check(lr.size.x > 0, "%s: layer %s has pixels" % [what, layer_id])
	if h == null or lr.size.x <= 0:
		return
	var hr := _hotspot_rect(h)
	var c := lr.get_center()
	_check(hr.has_point(c), "%s: the hotspot %s %s covers the drawn %s (centre %s)" % [what, hotspot_id, str(hr), layer_id, str(c.round())])
	_check(room.pick(c) == h, "%s: a click on the drawn %s picks %s (got %s)" % [what, layer_id, hotspot_id, str(room.pick(c))])


func _visible(room: Node, id: String) -> bool:
	var n: Node = _layer(room, id)
	return n != null and (n as CanvasItem).visible


func _choose(h: Node, option: String) -> String:
	sr.interact(h)
	await process_frame
	var opts: Array = sr.current_options()
	_check(not opts.is_empty(), "the choice opens on %s" % h.name)
	sr.choose(option)
	await process_frame
	var key := String(sr.current_beat.get("text_key", ""))
	await _drain()
	await _frames(2)
	return key


# --- Tests -------------------------------------------------------------------------------

func _test_key() -> void:
	var room: Node = await _enter("Z2", ["done_M01", "met_tamara", "knows_pier_trace"], ["key_house", "pocket_watch"])
	var e: Node = room.get_node_or_null("Exits/to_H1")
	_check(e != null and not e.is_open(), "Z2→H1 locked before the key is applied")
	if e == null:
		return
	sr.use_exit(e)
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.closed", "locked: the text names the key in the bag (%s)" % str(sr.current_beat))
	_check(sd.text("@Z2.exit_H1.closed").to_lower().find("ключ") >= 0, "the locked text speaks of the key")
	await _drain()
	_check(gs.current_room == "Z2" and gs.has_item("key_house"), "still on the street, the key still in the bag")
	sr.select_item("pocket_watch")
	sr.use_exit(e)
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "ui.item_no_effect", "the watch does not open the door (%s)" % str(sr.current_beat))
	await _drain()
	_check(gs.has_item("pocket_watch") and not gs.has_flag("house_unlocked"), "nothing changed by the wrong item")
	sr.select_item("key_house")
	sr.use_exit(e)
	await process_frame
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.unlock", "key on the door → unlock text (%s)" % str(sr.current_beat))
	_check(not gs.has_item("key_house"), "the key left the bag (stays in the lock)")
	_check(gs.has_flag("house_unlocked") and gs.has_flag("has_key_house") and e.is_open(), "door unlocked; has_key_house stays")
	await _drain()
	var fr := 0
	while gs.current_room != "H1" and fr < 60:
		await process_frame
		fr += 1
	await physics_frame
	_check(gs.current_room == "H1", "after the text Agata walks in (room %s)" % gs.current_room)
	_check(sr.can_start("M03") or sr.is_done("M03") or sr.requires_met(sd.scene("M03").get("requires", {})), "M03 can run in the unlocked house")
	sr.grant_item("key_house")
	_check(not gs.has_item("key_house"), "the key is never given a second time")
	_check(rm.save_game(SLOT), "save in H1")
	rm.change_room("Z2", "from_H1")
	await _frames(3)
	var e2: Node = rm.current_room.get_node_or_null("Exits/to_H1")
	_check(e2 != null and e2.is_open(), "the door stays open from now on")
	sr.use_exit(e2)
	await _frames(4)
	_check(gs.current_room == "H1", "the open door lets Agata in without the key")
	rm.change_room("Z2", "from_H1")
	await _frames(2)
	gs.set_flag("house_unlocked", false)   # tamper; the save must restore it
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	_check(gs.has_flag("house_unlocked") and not gs.has_item("key_house"), "after a load: unlocked, the key used")
	rm.change_room("Z2", "from_H1")
	await _frames(3)
	var e3: Node = rm.current_room.get_node_or_null("Exits/to_H1")
	_check(e3 != null and e3.is_open(), "after a load the door is open")
	gs.reset()
	await process_frame
	_check(e3 != null and not e3.is_open(), "a new game locks the door again")


func _h1_flags() -> Array:
	return ["done_M01", "done_M02", "house_unlocked", "done_M03", "started_M03", "met_tikhon", "house_open",
		"stove_lit", "h1_shutter_open", "h1_scarf_removed"]


func _test_photo() -> void:
	var room: Node = await _enter("H1", _h1_flags(), ["letter_tamara"])
	var h := _hotspot(room, "photo")
	_check(_visible(room, "photo_ledge") and not _visible(room, "photo_table") and not _visible(room, "photo_shelf"), "before the choice: on the stove ledge only")
	_check_on(room, "photo", "photo_ledge", "ledge")
	var ledge := _layer_rect(room, "photo_ledge")
	_check(ledge.size.x >= 20.0 and ledge.size.y >= 26.0, "the photo on the ledge is big enough to see: %s" % str(ledge.size))
	var key: String = await _choose(h, "table")
	_check(key == "H1.photo.react_table", "«На столе» → Agata's reaction (%s)" % key)
	_check(gs.has_flag("v01_photo_table") and _visible(room, "photo_table") and not _visible(room, "photo_ledge") and not _visible(room, "photo_shelf"),
		"«На столе»: on the side table, the ledge clear")
	_check_on(room, "photo", "photo_table", "table")
	var tl := _layer(room, "photo_table")
	var table := _layer(room, "table_chair")
	_check(tl != null and table != null and (tl as CanvasItem).z_index < (table as CanvasItem).z_index, "the photo stands behind the book: drawn under the side table layer")
	key = await _choose(h, "shelf")
	_check(key == "H1.photo.react_shelf", "«На полке» → Agata's reaction (%s)" % key)
	_check(gs.has_flag("v01_photo_shelf") and not gs.has_flag("v01_photo_table"), "exclusive: one place")
	_check(_visible(room, "photo_shelf") and not _visible(room, "photo_table") and not _visible(room, "photo_ledge"), "«На полке»: on the corner shelf, table and ledge clear")
	_check_on(room, "photo", "photo_shelf", "shelf")
	_check(_layer_rect(room, "photo_shelf").get_center().y < 340.0, "the shelf is the corner shelf above the stove ledge")
	_check(rm.save_game(SLOT), "save")
	gs.set_flag("v01_photo_shelf", false)
	gs.set_flag("v01_photo_table", true)
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	room = rm.current_room
	_check(_visible(room, "photo_shelf") and not _visible(room, "photo_table"), "a load keeps the photo on the shelf")


func _test_cups() -> void:
	var room: Node = await _enter("H1", _h1_flags())
	var h := _hotspot(room, "cups")
	_check(_visible(room, "cup_sill_blue") and _visible(room, "cup_sill_white"), "both cups wait on the window sill")
	_check(not _visible(room, "cup_table_blue") and not _visible(room, "cup_table_white"), "nothing on the side table yet")
	_check_on(room, "cups", "cup_sill_blue", "sill")
	var key: String = await _choose(h, "blue")
	_check(key == "H1.cups.react_blue", "blue → reaction (%s)" % key)
	_check(_visible(room, "cup_table_blue") and not _visible(room, "cup_sill_blue") and _visible(room, "cup_sill_white"), "blue on the side table, white stays on the sill")
	_check_on(room, "cups", "cup_table_blue", "table blue")
	var cl := _layer(room, "cup_table_blue")
	var table := _layer(room, "table_chair")
	_check(cl != null and table != null and (cl as CanvasItem).z_index > (table as CanvasItem).z_index, "the cup stands ON the side table (drawn above it)")
	key = await _choose(h, "white")
	_check(key == "H1.cups.react_white", "white → reaction (%s)" % key)
	_check(_visible(room, "cup_table_white") and not _visible(room, "cup_table_blue") and _visible(room, "cup_sill_blue") and not _visible(room, "cup_sill_white"),
		"switching: white on the table, blue back on the sill")
	_check(rm.save_game(SLOT), "save")
	gs.set_flag("v01_cup_white", false)
	_check(rm.load_game(SLOT), "load")
	await _frames(3)
	room = rm.current_room
	_check(_visible(room, "cup_table_white") and not _visible(room, "cup_sill_white"), "a load keeps the white cup on the table")


func _o1_flags() -> Array:
	return ["done_M01", "done_M02", "house_unlocked", "done_M03", "house_open", "done_M04", "done_M05",
		"door_school_installed", "done_M06", "seen_class_traces", "o1_saw_winter"]


func _test_chalk() -> void:
	var room: Node = await _enter("O1", _o1_flags(), [], Vector2(1000, 740))
	_check(_visible(room, "chalk_desk"), "the chalk lies on the desk before it is taken")
	_check(_visible(room, "teacher_chalk_patch"), "the drawn chalk on the teacher's desk is patched over")
	_check_on(room, "chalk", "chalk_desk", "desk")
	var r := _layer_rect(room, "chalk_desk")
	_check(r.size.x >= 30.0, "the chalk is long enough to see: %.0f px" % r.size.x)
	var desks := _layer(room, "desks")
	var cl := _layer(room, "chalk_desk")
	_check(desks != null and cl != null and (cl as CanvasItem).z_index > (desks as CanvasItem).z_index, "the chalk is drawn above the desks (on the desk top)")
	# on the desk: the desks layer is opaque under the chalk's centre
	var dimg := Image.load_from_file(ProjectSettings.globalize_path("res://assets/rooms/O1/fg_desks.png"))
	var dspr: Sprite2D = desks.get_node("Image") if desks != null else null
	if dimg != null and dspr != null:
		var c := (r.get_center() - dspr.position) / dspr.scale
		_check(dimg.get_pixel(int(c.x), int(c.y)).a > 0.9, "the chalk lies on the desk's opaque surface")
	var old_pick = room.pick(Vector2(630, 488))
	_check(old_pick == null or String(old_pick.name) != "chalk", "nothing called chalk on the teacher's desk any more")
	var h := _hotspot(room, "chalk")
	sr.interact(h)
	await process_frame
	await _drain()
	await _frames(2)
	_check(gs.has_item("chalk"), "taken")
	_check(not _visible(room, "chalk_desk") and not h.visible, "taken → gone from the desk")
	gs.set_flag("done_M07", true)
	gs.set_flag("observed_path_loop", true)
	await _frames(2)
	await _drain()
	_check(gs.has_flag("done_M08"), "M08 done after the loop (the board is optional, Docs/SCENARIO_FINAL.md M08)")
	_check(gs.has_item("chalk"), "M08's grant does not duplicate the chalk already taken")
	sr.select_item("chalk")
	sr.interact(_hotspot(room, "board"))
	await process_frame
	_check(not sr.current_options().is_empty(), "chalk on the board → what to write")
	sr.choose("here")
	await process_frame
	await _drain()
	await _frames(3)
	await _drain()
	_check(gs.has_flag("board_here") and _visible(room, "board_written"), "written on the board: «Я была здесь. Агата» (the drawn chalk)")
	_check(not gs.has_item("chalk"), "the chalk stays at the board — M08's grant does not put it back")


func _test_bird_mark() -> void:
	# G37 (Director 23.10: «эпизод подрисовать птице — пусть будет, и ответ Ульяны зависит от выбора»): Agata adds a
	# scarf, Ilya's boat with smoke or a little bridge on stone piers — or leaves the poster as it is.
	for v in ["scarf", "boat", "bridge"]:
		var room: Node = await _enter("O1", _o1_flags(), [], Vector2(1000, 740))
		var h := _hotspot(room, "bird_drawing")
		_check(h != null and h.visible and not _visible(room, "bird_add_" + v), "%s: nothing added before V03" % v)
		_check(_visible(room, "bird_doodles"), "the hat (Agata, long ago) and the boots (Ulyana) are on the bird")
		var ids: Array = []
		sr.interact(h)
		await process_frame
		ids = sr.current_options().map(func(o): return String(o.get("id", "")))
		_check(ids == ["scarf", "boat", "bridge", "leave"], "three things to add, or leave: %s" % str(ids))
		sr.choose(v)
		await process_frame
		var key := String(sr.current_beat.get("text_key", ""))
		await _drain()
		await _frames(2)
		_check(key == "O1.bird_drawing.react_" + v, "%s: Agata's own words after the choice (%s)" % [v, key])
		_check(gs.has_flag("v03_add_" + v) and gs.has_flag("v03_marked") and gs.has_flag("done_V03"), "%s: its flag, «marked», V03 done" % v)
		for o in ["scarf", "boat", "bridge"]:
			_check(_visible(room, "bird_add_" + o) == (o == v), "%s: drawing %s shown %s" % [v, o, str(o == v)])
		var r := _rect_of_node(room.get_node("Layers/bird_add_" + v))
		_check(_hotspot_rect(h).encloses(r), "%s: the drawing is on the poster %s (%s)" % [v, str(_hotspot_rect(h)), str(r)])
	var room2: Node = await _enter("O1", _o1_flags(), [], Vector2(1000, 740))
	var h2 := _hotspot(room2, "bird_drawing")
	var key2: String = await _choose(h2, "leave")
	_check(gs.has_flag("v03_left") and not gs.has_flag("v03_marked"), "«как есть» → nothing added")
	for o in ["scarf", "boat", "bridge"]:
		_check(not _visible(room2, "bird_add_" + o), "«как есть» → no %s" % o)
	_check(key2 == "O1.v03.done", "«как есть» → the reaction plays (%s)" % key2)


## Screen box of a layer node (its picture or its stand-in's crops / shapes / texts).
func _rect_of_node(n: Node) -> Rect2:
	var box := Rect2()
	var first := true
	for c in n.find_children("*", "", true, false):
		var r := Rect2()
		if c is Sprite2D and (c as Sprite2D).texture != null:
			var spr := c as Sprite2D
			var sz: Vector2 = spr.texture.get_size() * spr.scale
			r = Rect2(spr.global_position, sz)
		elif c is Label:
			r = Rect2((c as Label).global_position, (c as Label).size)
		else:
			continue
		box = r if first else box.merge(r)
		first = false
	return box


## Recorded in one request (pipeline/voice, run 39124518023): the door, the reactions, the photo by the sketch,
## the chalk on the desk, the cups on the sill. Each must resolve to a file whose text matches (sha1).
## (Z1.drawings.photo — the pier photo of 18.10 — is gone with the photo: block 1, 22.10, the bridge photo instead;
## its new text waits for the Director's text pass before it is recorded.)
func _test_voice() -> void:
	var vd: Node = root.get_node_or_null("VoiceDirector")
	_check(vd != null, "VoiceDirector autoload")
	if vd == null:
		return
	var want := {
		"Z2.exit_H1.closed": "agata", "Z2.exit_H1.unlock": "narrator",
		"H1.photo.react_table": "agata", "H1.photo.react_shelf": "agata", "H1.cups.react_blue": "agata",
		"H1.cups.react_white": "agata", "H1.cups.look": "narrator", "O1.chalk.use": "narrator", "O1.chalk.look": "narrator",
	}
	for key in want.keys():
		var v: Dictionary = vd.narration_voice(key)
		_check(String(v.get("speaker", "")) == String(want[key]), "%s is read by %s (got %s)" % [key, want[key], v.get("speaker")])
		var status: String = vd.line_status(String(v["id"]), sd.text("@" + key))
		_check(status == "ok", "%s: recording %s — %s" % [key, v["id"], status])
