extends SceneTree
## Director's playthrough 01.11, group К1 — rooms, frames, staging props (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md;
## «стр.» — a line of Docs/FEEDBACK_DIRECTOR_2026-11-01_raw.txt):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0111_k1.gd
##   стр. 17, 74: Tikhon's shelf in the dinner frame (the last frame) runs right and UP — the board mirrored and turned;
##   стр. 73: the titmouse poster in the lesson frame wears the hat and boots of O1 (and Agata's V03 drawing by its flag);
##   стр. 72: Pelageya by the tarred boat stands on the snow in front of the trestle, not above its feet;
##   стр. 75: the blue cup at dinner stands on the table, not on the rim of a bowl behind it;
##   стр. 49: a lantern stands by Mitya at the far pier (the glow on its glass), gone with him after M18;
##   стр. 51: Mitya calling Ilya stands right of the right-hand road, at Ilya's house, and looks right;
##   стр. 54: the chair at mum's (O3) is drawn over Agata standing behind it (occluders by its legs, day and night);
##   стр. 57: Tamara's sack of letters is there with her (not only after M23a), Mitya's board from the morning of day three;
##   стр. 60: the coat is on the hook from the line where Nina hangs it (M23c), not only after the scene;
##   стр. 63: the sleeve — one click: the close-up, its words and the choice of the seam together;
##   стр. 67: the council frame at the mill (F_mill_manager) has the yard's drizzle, as its rain is heard;
##   стр. 69: the first span's frames show the crossing rope on the plate's ring;
##   стр. 43: «В лодку» at the turn only where the boat is (not while Pelageya has taken it to her pier, M15 → M16);
##   стр. 41: the brace (M15s) — the pier R1 (where Pelageya's boat stands) and the turn Z3 (the support) are one evening:
##            the mean luminance of the two backgrounds as drawn (painted dusk layers × the room's time grade) within 15 %,
##            the same at evening and night; self-check — the old grades (both «painted») fail it (×1,6).
## (in other files: стр. 1 — test_batch_j «J-E4» (Tamara's feet behind the counter, click_rect); стр. 2 — test_agata_3d
##  «Round the counter's corner»; стр. 28, 54 floor — data clearance / no_walk_samples, test_room_geometry.)
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
	await _test("K1-17/74 Tikhon's shelf in the dinner frame: the board mirrored, nearly level (02.11 вечер), Tikhon on its middle", _test_shelf)
	await _test("K1-73 the titmouse in the lesson frame: hat and boots as in the class (O1), Agata's drawing by its flag", _test_bird)
	await _test("K1-72 Pelageya by the tarred boat: feet on the snow in front of the trestle (not above its feet)", _test_pelageya_boat)
	await _test("K1-75 the dinner cup stands on the table top, clear of the bowl behind it", _test_cup)
	await _test("K1-49 Mitya's lantern stands by him at the far pier, the glow on its glass; gone with him after M18", _test_lantern)
	await _test("K1-51 Mitya calling Ilya (M19): right of the right-hand road, at Ilya's house, looking right", _test_mitya_m19)
	await _test("K1-54 the chair at mum's (O3) is drawn over Agata behind it — occluders by its legs, day and night", _test_chair)
	await _test("K1-57 the sack of letters is there with Tamara; Mitya's board from the morning of day three", _test_sack_board)
	await _test("K1-60 the coat is on the hook from the line where Nina hangs it (M23c)", _test_coat)
	await _test("K1-63 the sleeve: one click — the close-up, the words and the choice of the seam", _test_sleeve)
	await _test("K1-67 the council frame at the mill: the drizzle that is heard is seen", _test_mill_rain)
	await _test("K1-69 the first span's frames: the crossing rope on the plate's ring", _test_span_rope)
	await _test("K1-43 «В лодку» at the turn only where the boat is", _test_boat_exit)
	await _test("K1-16 Tikhon curled on the armchair faces into the room (right), not the chair's arm", _test_tikhon_chair)
	await _test("K1-42 the evening support in the water has its iron plate with the ring — the rope ends at the ring, not in bare stone", _test_plate_dusk)
	await _test("K1-41 the brace (M15s): the pier (R1) and the turn (Z3) — one evening, their backgrounds' luminance within 15 %; the narration's dusk no darker than before", _test_one_evening)
	gs.reset()
	Engine.time_scale = 1.0
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== feedback 01.11 K1: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


## Every scene before `upto`: done, with its grants and its staging's `sets` (the boat's comings and goings).
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


func _layer(room_id: String, id: String) -> Dictionary:
	for l in sd.rooms.get(room_id, {}).get("layers", []):
		if String(l.get("id", "")) == id:
			return l
	return {}


func _layer_node(room: Node, id: String) -> CanvasItem:
	for box in ["Layers", "Occluders"]:
		var n = room.get_node_or_null(box + "/" + id) if room != null else null
		if n != null:
			return n as CanvasItem
	return null


func _layer_visible(room: Node, id: String) -> bool:
	var n := _layer_node(room, id)
	return n != null and n.visible


## Opaque bbox (alpha > 0.5) of a layer picture in its canvas pixels.
func _opaque_box(res: String) -> Rect2:
	var tex = load(res)
	if tex == null:
		return Rect2()
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if img.get_pixel(x, y).a > 0.5:
				lo = Vector2(minf(lo.x, x), minf(lo.y, y))
				hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
	if lo.x == INF:
		return Rect2()
	return Rect2(lo, hi - lo + Vector2.ONE)


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == id:
			return h
	return null


func _build_frame(id: String) -> Node:
	var room = load("res://scripts/rooms/room_builder.gd").build(id)
	if room != null:
		root.add_child(room)
		await _frames(2)
	return room


func _free(room: Node) -> void:
	if room != null and is_instance_valid(room):
		root.remove_child(room)
		room.free()


# --- Tests -------------------------------------------------------------------------------

func _test_shelf() -> void:
	var l := _layer("EP_dinner", "tikhon_shelf")
	var c: Dictionary = l.get("compose", {})
	# 02.11 вечер (Директор 22:50: «убрать наклон практически до горизонтальной») supersedes 01.11 «направо и вверх»:
	# the board mirrored, turned back to nearly level (test_feedback_0211b «0211b-24»)
	_check(bool(c.get("mirror", false)), "the board mirrored: %s" % str(c.get("mirror")))
	# the picture itself: the board's top edge is higher (smaller y) at its right end than at its left
	var tex = load(String(l.get("image", "")))
	_check(tex != null, "the shelf picture")
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var box := _opaque_box(String(l["image"]))
	var tops: Array[float] = []
	for fx in [0.2, 0.8]:
		var x := int(box.position.x + box.size.x * fx)
		var top := -1.0
		for y in range(int(box.position.y), int(box.end.y)):
			if img.get_pixel(x, y).a > 0.5:
				top = float(y)
				break
		tops.append(top)
	_check(absf(tops[1] - tops[0]) <= 3.0, "the board nearly level (02.11 вечер): top at 20%% y %.0f, at 80%% y %.0f" % [tops[0], tops[1]])
	# Tikhon sits on its middle: his feet over the board
	var tk := _opaque_box(String(_layer("EP_dinner", "tikhon").get("image", "")))
	_check(tk.get_center().x > box.position.x + box.size.x * 0.25 and tk.get_center().x < box.position.x + box.size.x * 0.75, "Tikhon on the middle of the board (%s on %s)" % [str(tk), str(box)])
	_check(absf(tk.end.y - (box.position.y + box.size.y * 0.3)) < 25.0, "Tikhon's feet on the board's top (%s on %s)" % [str(tk), str(box)])


func _test_bird() -> void:
	var o1: Dictionary = {}
	for l in sd.rooms["O1"].get("layers", []):
		o1[String(l.get("id", ""))] = l
	for id in ["bird_doodles", "bird_add_scarf", "bird_add_boat", "bird_add_bridge", "bird_mark", "bird_reply_scarf", "bird_reply_boat", "bird_reply_bridge"]:
		var l := _layer("EP_lesson", id)
		_check(not l.is_empty(), "EP_lesson has %s" % id)
		if l.is_empty():
			continue
		_check(str(l.get("if", [])) == str(o1.get(id, {}).get("if", [])), "%s shows by the same flags as in O1: %s / %s" % [id, str(l.get("if", [])), str(o1.get(id, {}).get("if", []))])
		_check(String(l.get("compose", {}).get("src", "")).ends_with("O1/state_%s.png" % id), "%s is the O1 drawing" % id)
	# in the frame as built: hat and boots always; the boat only with v03_add_boat
	_fresh(["v03_add_boat", "v03_marked"])
	var fr := await _build_frame("EP_lesson")
	_check(_layer_visible(fr, "bird_doodles"), "the hat and the boots on the poster")
	_check(_layer_visible(fr, "bird_add_boat") and not _layer_visible(fr, "bird_add_scarf"), "Agata's boat, not the scarf")
	# the doodles sit on the poster: hat [1350,185,1396,214) of the O1 canvas, the poster is in the same place (0, −1)
	var box := _opaque_box(String(_layer("EP_lesson", "bird_doodles").get("image", "")))
	_check(box.position.distance_to(Vector2(1343, 185)) < 6.0, "the doodles where the hat is (%s)" % str(box))
	_free(fr)


func _test_pelageya_boat() -> void:
	# 05.11 (block 2): the frame's people are live figures — the npc hotspots' feet and figure_h (screen px), not the
	# composed layers (canvas px ×1.148): the trestle's feet ≈ y 907 on screen; below 905 is the line box (0511-6)
	var room = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/EP_boat.json"))
	var hs := {}
	for h in room.get("hotspots", []):
		hs[String(h.get("id", ""))] = h
	var c: Dictionary = hs.get("pelageya", {})
	var feet: Array = c.get("feet", [0, 0])
	_check(float(feet[1]) >= 900.0 and float(feet[1]) < 905.0, "her feet on the snow in front of the trestle (its feet ≈ y 907, the line box from 905): y %s" % str(feet[1]))
	var m: Dictionary = hs.get("mitya", {})
	# depth: nearer than Mitya → not smaller than him × 0.9 (she is the shorter)
	_check(float(c.get("figure_h", 0)) >= float(m.get("figure_h", 0)) * 0.9, "her height by the depth (%s vs Mitya %s)" % [str(c.get("figure_h")), str(m.get("figure_h"))])


func _test_cup() -> void:
	var bowl := Rect2(888, 512, 32, 28)   # the small bowl of the dinner picture behind the big one (canvas px)
	for id in ["cup_blue", "cup_white"]:
		var box := _opaque_box(String(_layer("EP_dinner", id).get("image", "")))
		_check(box.size.x > 30.0, "%s drawn (%s)" % [id, str(box)])
		_check(not box.intersects(bowl), "%s clear of the bowl behind (%s)" % [id, str(box)])
		_check(box.end.y < 562.0 and box.end.y > 540.0, "%s stands on the table top, inside its front edge y 565 (%s)" % [id, str(box)])


func _test_lantern() -> void:
	var l := _layer("R3", "mitya_lantern")
	_check(not l.is_empty() and (l.get("unless", []) as Array).has("done_M18"), "the lantern layer, gone after M18")
	var box := _opaque_box(String(l.get("image", "")))
	var k := 1920.0 / 1672.0
	var lamp := Rect2(box.position * k, box.size * k)   # screen
	_check(lamp.size.y > 40.0 and lamp.size.y < 70.0, "a lantern ≈ 0.38 m by Mitya (1.8 m = 250 px): %.0f px" % lamp.size.y)
	var mitya_feet := Vector2(520, 666)
	# партия 15 (02.11): the painted lantern stands on the snow of the wall top, base centre canvas (536, 587) — screen
	# (615, 674), a little in front of his feet line (the wall's edge), right of them
	var base := Vector2(box.get_center().x, box.end.y)
	_check(base.distance_to(Vector2(536, 587)) < 8.0, "the painted lantern's base on the wall at canvas (536, 587): %s" % str(base))
	_check(absf(lamp.end.y - mitya_feet.y) < 12.0 and lamp.position.x > mitya_feet.x + 30.0 and lamp.position.x < mitya_feet.x + 130.0, "standing on the stone beside his feet (%s)" % str(lamp))
	var lt: Dictionary = {}
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/lights/R3.json"))
	for s in (doc.get("sources", []) if doc is Dictionary else []):
		if String(s.get("id", "")) == "mitya_lantern":
			lt = s
	var r: Array = lt.get("rect", [0, 0, 0, 0])
	var gc: Array = lt.get("params", {}).get("glass_center", [0.5, 0.5])
	var glow := Vector2(float(r[0]) + float(r[2]) * float(gc[0]), float(r[1]) + float(r[3]) * float(gc[1]))
	_check(lamp.has_point(glow) and glow.distance_to(Vector2(616, 652)) < 8.0, "the glow on the painted glass (screen 616, 652): %s in %s" % [str(glow), str(lamp)])
	# партия 15: the flame is painted — the engine's own flame over it burnt the painted one white (render 02.11)
	_check(float(lt.get("params", {}).get("flame", 1.0)) <= 0.01 and float(lt.get("params", {}).get("glass", 1.0)) <= 0.4, "the engine glow only breathes over the painted flame (flame %s, glass %s)" % [str(lt.get("params", {}).get("flame")), str(lt.get("params", {}).get("glass"))])
	_check((lt.get("unless", []) as Array).has("done_M18"), "the glow goes with Mitya after M18")
	# in the room: on the evening of day two, before M18
	_fresh()
	_flags_before("M18")
	await _enter("R3")
	_check(_layer_visible(rm.current_room, "mitya_lantern"), "R3 before M18: the lantern stands by Mitya")
	gs.set_flag("done_M18", true)
	await _frames(3)
	_check(not _layer_visible(rm.current_room, "mitya_lantern"), "after M18: gone with him")


func _test_mitya_m19() -> void:
	_fresh()
	_flags_before("M19")
	await _enter("O4")
	if sr.current_beat.is_empty():
		sr.start_scene("M19")
	await _frames(3)
	var h := _hotspot("mitya")
	_check(h != null and h.visible, "Mitya on the street in M19")
	var npc := rm.current_room.get_node_or_null("npc_mitya") as Node2D
	var feet := Vector2.ZERO
	if npc != null:
		feet = npc.global_position
	elif h != null:
		var r: Array = h.data.get("rect", [0, 0, 0, 0])
		feet = Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]))
	# the right-hand road runs between Nina's fence (x ≈ 1700 at y 630) and Ilya's house (x 1720–1920)
	_check(feet.x > 1780.0, "right of the right-hand road, at Ilya's house: feet %s" % str(feet))
	var face: Array = h.data.get("face", []) if h != null else []
	_check(face.size() == 2 and float(face[0]) > feet.x + 40.0, "standing, he looks right, at Ilya's house: face %s" % str(face))
	# while the narrator tells of his knocking he listens facing the house, not turned to Agata (listen_keeps_face)
	await _frames(60)
	if npc != null and npc.get("sheet") != null:
		var want0: int = npc.sheet.direction_index(Vector2(float(face[0]), float(face[1])) - feet)
		_check(int(npc.direction) == want0, "at «…да в ставню колотит» he faces Ilya's house (row %d, want %d, state %s)" % [int(npc.direction), want0, String(npc.get("state"))])
	# his call «Илья! Илья, выходи…» goes to the shutter on the right, not to Agata (she is to his left)
	var called := false
	var guard := 0
	while guard < 400 and not sr.is_done("M19"):
		guard += 1
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty() or sr.is_staging():
			continue
		if String(b.get("speaker", "")) == "mitya" and b.get("type") == "line":
			await _frames(4)
			if npc != null and npc.get("sheet") != null:
				var want: int = npc.sheet.direction_index(Vector2(1920, 470) - feet)
				_check(int(npc.direction) == want, "calling Ilya he faces the shutter on the right (row %d, want %d; Agata at %s)" % [int(npc.direction), want, str(player.global_position.round())])
			called = true
			break
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		else:
			sr.advance()
	_check(called, "Mitya's call comes in M19")
	sr.call("_on_state_reset")


func _test_chair() -> void:
	for night in [false, true]:
		var sfx := "_night" if night else ""
		for part in [["chair_back", 1080], ["chair_leg_near", 1080], ["chair_far", 990]]:
			var l := _layer("O3", String(part[0]) + sfx)
			_check(bool(l.get("occluder", false)) and int(l.get("z", 0)) == int(part[1]), "%s%s: an occluder at z %d" % [part[0], sfx, part[1]])
	_fresh(["done_M19", "done_M21b", "morning_day3"])
	await _enter("O3")
	var occ := _layer_node(rm.current_room, "chair_back")
	_check(occ != null and occ.visible and not _layer_visible(rm.current_room, "chair_back_night"), "by day: the day chair over her")
	# the chair's right post (screen 1035, 700) is covered by the layer: Agata standing behind it is hidden there
	var box := _opaque_box(String(_layer("O3", "chair_back").get("image", "")))
	var k := 1920.0 / 1672.0
	_check(Rect2(box.position * k, box.size * k).has_point(Vector2(1030, 700)), "the occluder covers the chair's right post (%s)" % str(box))
	# Agata at the letters' stand (1080, 830) is behind the chair (its legs on the floor at y 975–1066): drawn under it
	player.global_position = Vector2(1080, 830)
	player.call("_update_depth")
	await _frames(3)
	_check(int(player.z_index) < int(occ.z_index if occ != null else 0), "Agata at the table (z %d) under the chair (z %d)" % [int(player.z_index), int(occ.z_index if occ != null else 0)])
	# Director 09.11, 22:18 («опять момент со стулом выглядит странно»): where she comes in from the street and where she
	# stands to talk (the floor's left edge, y 1050–1055) her figure is wider than the gap to the chair — drawn over the
	# chair's back she stood «in» it, and a step up across y 1020 threw her behind it. The back is the chair's near side:
	# it is over her at every place of the floor's left edge. Self-check: at the old z 1020 the entry place was over it.
	var room_d: Dictionary = sd.room("O3")
	var places: Array = [room_d.get("spawns", {}).get("from_O4", [0, 0])]
	for h in room_d.get("hotspots", []):
		if h.has("stand") and float(h["stand"][0]) < 1180.0:
			places.append(h["stand"])
	var over_old := 0
	for pl in places:
		player.global_position = Vector2(float(pl[0]), float(pl[1]))
		player.call("_update_depth")   # as a step does (standing, the depth is not recomputed every frame)
		await _frames(2)
		_check(int(player.z_index) < int(occ.z_index if occ != null else 0), "at %s by the chair Agata (z %d) is drawn over its back (z %d) — she stands «in» the chair" % [str(pl), int(player.z_index), int(occ.z_index if occ != null else 0)])
		if int(player.z_index) >= 1020:
			over_old += 1
	_check(over_old > 0, "self-check K1-54: no place by the chair below the back's old z 1020 — the check sees nothing")
	# at night the painted night layer is over the picture: the night chair goes by the same flags
	var night := _layer("O3", "night")
	for part in ["chair_back", "chair_leg_near", "chair_far"]:
		_check(str(_layer("O3", part + "_night").get("if", [])) == str(night.get("if", [])) and str(_layer("O3", part).get("unless", [])) == str(night.get("if", [])), "%s: day / night by the night layer's flags %s" % [part, str(night.get("if", []))])


func _test_sack_board() -> void:
	_fresh()
	_flags_before("M22")
	gs.set_flag("morning_day3", true)
	await _enter("O4")
	_check(_layer_visible(rm.current_room, "mitya_board"), "the morning of day three: Mitya's board at the fence already")
	_check(not _layer_visible(rm.current_room, "letters_bag"), "no sack before Tamara comes")
	gs.set_flag("done_M22", true)
	await _frames(3)
	var tam := _hotspot("tamara")
	_check(tam != null and tam.visible and not gs.has_flag("done_M23a"), "Tamara is here with her letters, before M23a")
	_check(_layer_visible(rm.current_room, "letters_bag"), "the sack is there with her (not only after M23a)")


func _test_coat() -> void:
	_fresh()
	_flags_before("M23c")
	await _enter("H1")
	_check(not _layer_visible(rm.current_room, "nina_coat") and not _layer_visible(rm.current_room, "nina_coat_hung"), "no coat before mum comes")
	if sr.current_beat.is_empty():
		sr.start_scene("M23c")
	var guard := 0
	var hung_at := ""
	while not sr.is_done("M23c") and guard < 4000:
		guard += 1
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty() or sr.is_staging():
			continue
		if hung_at == "" and (_layer_visible(rm.current_room, "nina_coat_hung") or _layer_visible(rm.current_room, "nina_coat")):
			hung_at = String(b.get("line_id", b.get("text_key", "?")))
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		else:
			sr.advance()
	_check(hung_at != "" and hung_at != "M23c_0" and not hung_at.is_empty(), "the coat on the hook during the scene (from %s)" % hung_at)
	_check(hung_at == "M23c_1", "right after «Вешает на пустой крючок…» (line 1), got %s" % hung_at)
	await _frames(3)
	_check(_layer_visible(rm.current_room, "nina_coat") and not _layer_visible(rm.current_room, "nina_coat_hung"), "after the scene: the coat layer of before (one picture, not two): coat %s, hung %s, done %s, room %s" % [_layer_visible(rm.current_room, "nina_coat"), _layer_visible(rm.current_room, "nina_coat_hung"), sr.is_done("M23c"), rm.current_room.get("room_id")])


func _test_sleeve() -> void:
	_fresh()
	_flags_before("Q03")
	_set_flags(["done_M23c", "nina_visited_house"])
	await _enter("H1")
	await _frames(3)
	var h := _hotspot("nina_coat")
	_check(h != null and h.visible, "the coat on the hook")
	if h == null:
		return
	sr.interact(h)
	var got_choice := false
	var guard := 0
	while guard < 300 and not sr.current_beat.is_empty():
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			got_choice = true
			sr.choose("A")
		else:
			sr.advance()
		await process_frame
	_check(got_choice, "the choice of the seam comes with the first click")
	_check(gs.has_flag("q03_hidden_seam"), "the sleeve sewn in one go")
	if sr.view_open:
		sr.close_view()


func _test_mill_rain() -> void:
	var fr := await _build_frame("F_mill_manager")
	var rain := false
	if fr != null:
		for n in fr.find_children("*", "", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("ambient_rain.gd"):
				rain = true
	_check(rain, "the frame has the yard's drizzle (AmbientRain)")
	var M1 := await _build_frame("M1")
	var rain_m1 := false
	if M1 != null:
		for n in M1.find_children("*", "", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("ambient_rain.gd"):
				rain_m1 = true
	_check(rain_m1, "self-check: the yard M1 itself rains")
	_free(fr)
	_free(M1)


func _test_span_rope() -> void:
	for id in ["F_span", "F_span_done"]:
		var fr := await _build_frame(id)
		var rope: Node = null
		if fr != null:
			for n in fr.find_children("*", "", true, false):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("room_effect.gd") and String((n.get("data") as Dictionary).get("type", "")) == "rope":
					rope = n
		_check(rope != null and (rope as CanvasItem).is_visible_in_tree(), "%s: the crossing rope drawn" % id)
		_free(fr)


func _test_tikhon_chair() -> void:
	_fresh(["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"])
	await _enter("H1")
	var pups: Array = load("res://scripts/actors/puppet_actor.gd").all_in(rm.current_room)   # not the class name: compiled after the autoloads
	_check(not pups.is_empty(), "Tikhon in the living room")
	if pups.is_empty():
		return
	var t = pups[0]
	_check(String(t.variant) == "loaf", "on the armchair, curled (loaf): %s, place %d" % [String(t.variant), int(t.place_index)])
	# the loaf picture has his head to the right of his body: not mirrored = he looks right, into the room
	_check(t.scale.x > 0.0, "not mirrored on the armchair — his head to the right, into the room (scale %s)" % str(t.scale))
	_fresh(["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "q04_corner_stove"])
	await _enter("H1")
	pups = load("res://scripts/actors/puppet_actor.gd").all_in(rm.current_room)
	if not pups.is_empty():
		_check(pups[0].scale.x < 0.0, "on his shelf by the stove — mirrored as before (looks into the room)")


func _test_plate_dusk() -> void:
	# 02.11 вечер, № 7: the plate with the rope and its knot only after the knot (plate_rope_dusk); before it — the same
	# plate and ring without the rope (plate_dusk). Both with the evening's low water
	var l := _layer("Z3", "plate_rope_dusk")
	var l0 := _layer("Z3", "plate_dusk")
	var wl := _layer("Z3", "water_low")
	_check(str(wl.get("unless", [])) == str(l.get("unless", [])) and (l.get("if", []) as Array).has("evening_dusk") and (l.get("if", []) as Array).has("rope_on_ring"), "the plate with the rope shows with the evening's low water, after the knot (%s / %s)" % [str(l.get("if")), str(l.get("unless"))])
	_check((l0.get("if", []) as Array).has("evening_dusk") and (l0.get("unless", []) as Array).has("rope_on_ring"), "the plate without the rope — at dusk until the knot (%s / %s)" % [str(l0.get("if")), str(l0.get("unless"))])
	_check(int(l.get("z", 0)) >= 2 and int(l0.get("z", 0)) >= 2, "the plate over the live water of the low pond (ambient draws it over layers z ≤ 1, as boat_day): z %s" % str(l.get("z", 0)))
	var box := _opaque_box(String(l.get("image", "")))
	var k := 1920.0 / 1672.0
	var plate := Rect2(box.position * k, box.size * k)
	var rope: Dictionary = {}
	for e in sd.rooms["Z3"].get("effects", []):
		if String(e.get("id", "")) == "rope_on_ring_dusk":
			rope = e
	var from: Array = rope.get("from", [0, 0])
	_check(plate.grow(2.0).has_point(Vector2(float(from[0]), float(from[1]))), "the rope's end %s on the plate %s" % [str(from), str(plate)])
	_fresh()
	_flags_before("M16s")
	gs.set_flag("evening_dusk", true)
	await _enter("Z3")
	_check(_layer_visible(rm.current_room, "plate_rope_dusk") and not _layer_visible(rm.current_room, "plate_dusk"), "after the knot, at dusk: the plate on the support, with the rope")


func _test_boat_exit() -> void:
	# [scene before which the state is taken, boat expected at the plate]
	# (coordinator 01.11, стр. 44: M16s plays at the turn right after the knot — Pelageya takes the boat to her pier at its end)
	for case in [["M15", true, "after the brace (M15s): the boat at the plate"], ["M16s", true, "after the knot (M15), «туман сошёл» still to come here: the boat at the plate"],
			["M16", false, "after M16s: Pelageya has taken the boat to her pier"], ["M17", true, "after the lights (M16): the boat back at the turn"]]:
		_fresh()
		_flags_before(String(case[0]))
		gs.set_flag("evening_dusk", true)
		await _enter("Z3")
		var ex = rm.current_room.get_node_or_null("Exits/to_R2")
		var shown: bool = ex != null and (ex as CanvasItem).visible and bool(ex.call("is_active"))
		var boat := _layer_visible(rm.current_room, "boat_dusk") or _layer_visible(rm.current_room, "boat_shuttle_dusk") or _layer_visible(rm.current_room, "boat_day")
		_check(boat == bool(case[1]), "%s — boat layer %s" % [case[2], boat])
		_check(shown == boat, "%s — «В лодку» %s, boat %s" % [case[2], shown, boat])


# --- стр. 41: one evening at the pier and at the turn --------------------------------------------------------------

## Mean linear luminance (Rec.709) of the room as built now — the background and every visible full-canvas layer, alpha
## composited at 1/8 size — times the grade multiplier `grade` (TimeOfDay.tint_of; the light map multiplies the art).
## The figures, the living-world shaders and the lamps' glow are not in it: the backgrounds only (Director 23:32).
func _bg_luminance(room: Node, grade: Color) -> float:
	var bg_spr: Sprite2D = null
	var bgn = room.get_node_or_null("Background")
	if bgn != null:
		for c in ([bgn] + bgn.get_children()):
			if c is Sprite2D:
				bg_spr = c
	var base: Image = null
	if bg_spr != null and bg_spr.texture != null:
		base = bg_spr.texture.get_image()
	if base == null:
		var spec: Dictionary = sd.rooms.get(String(room.get("room_id")), {})
		base = (load(String(spec.get("background", {}).get("image", ""))) as Texture2D).get_image()
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
			var mod := spr.modulate
			for y in h:
				for x in w:
					var c := img.get_pixel(x, y)
					if c.a <= 0.0:
						continue
					var d := base.get_pixel(x, y)
					base.set_pixel(x, y, Color(lerpf(d.r, c.r * mod.r, c.a), lerpf(d.g, c.g * mod.g, c.a), lerpf(d.b, c.b * mod.b, c.a), 1.0))
	var sum := 0.0
	for y in h:
		for x in w:
			var c := base.get_pixel(x, y)
			var r := Color(minf(c.r * grade.r, 1.0), minf(c.g * grade.g, 1.0), minf(c.b * grade.b, 1.0)).srgb_to_linear()
			sum += r.r * 0.2126 + r.g * 0.7152 + r.b * 0.0722
	return sum / float(w * h)


## The two backgrounds at the scene's moment (flags before `upto`, evening_dusk), each under `grades` [R1, Z3].
func _evening_pair(upto: String, grades: Array) -> Array:
	var out := []
	var rooms := ["R1", "Z3"]
	for i in 2:
		_fresh()
		_flags_before(upto)
		gs.set_flag("evening_dusk", true)
		await _enter(rooms[i])
		out.append(_bg_luminance(rm.current_room, grades[i]))
	return out


func _test_one_evening() -> void:
	const LIMIT := 1.15
	# by path, not class name: a class_name script referring to autoloads must not compile before them (-s run)
	var TOD = load("res://scripts/core/time_of_day.gd")
	var RL = load("res://scripts/lighting/room_lighting.gd")
	for case in [["M15s", "d2_dusk", "the brace (dusk)"], ["M16", "d2_evening", "the lights (evening)"], ["M18p", "d2_night", "the crossing (night)"]]:
		var st := String(case[1])
		var grades := [TOD.tint_of(TOD.grade("R1", st)), TOD.tint_of(TOD.grade("Z3", st))]
		var now: Array = await _evening_pair(String(case[0]), grades)
		var ratio: float = float(now[1]) / maxf(float(now[0]), 0.0001)
		_check(ratio <= LIMIT and ratio >= 1.0 / LIMIT, "%s: the turn / the pier %.2f (Y %.4f / %.4f), must be within ×%.2f" % [case[2], ratio, now[1], now[0], LIMIT])
		if st == "d2_dusk":
			# self-check: the grades before стр. 41 (both «painted» at dusk) — the turn 1,6 × the pier — must fail the same bound
			var old: Array = await _evening_pair("M15s", [Color.WHITE, Color.WHITE])
			var old_ratio: float = float(old[1]) / maxf(float(old[0]), 0.0001)
			_check(old_ratio > LIMIT, "self-check: the old «painted» dusk must be caught (turn / pier %.2f > %.2f)" % [old_ratio, LIMIT])
			# the pier is lifted, the turn lowered (not one of them dragged all the way)
			_check(grades[0].get_luminance() > 1.02 and grades[1].get_luminance() < 0.98, "R1 lifted (%s), Z3 lowered (%s)" % [grades[0], grades[1]])
	# the narration's dusk (stage dim of M15s) over the lowered turn: no darker than the 0,5 over the old painted turn
	var dim := 0.0
	for stg in sd.scene("M15s").get("stage", []):
		dim = maxf(dim, float(stg.get("dim", 0.0)))
	var zg: Color = TOD.tint_of(TOD.grade("Z3", "d2_dusk"))
	_check((1.0 - dim) * zg.get_luminance() >= 0.47, "the narration under dim %.2f over the turn (×%.2f): about as light as 0,5 over the painted turn (≥ 0,47; the Director's 0,82 gave 0,18)" % [dim, zg.get_luminance()])
	# the figures were not what was too bright (23:32): the turn's dusk tone on them back to 0,62
	var t: Array = []
	for src in (RL.load_data("Z3").get("sources", []) as Array):
		if String(src.get("id", "")) == "dusk_figures":
			t = src.get("actor_tint", [])
	_check(t.size() >= 3 and float(t[0]) >= 0.6, "Z3 dusk_figures actor_tint back to ≈0,62 (the background is lowered by the grade, which reaches the figures too): %s" % str(t))
