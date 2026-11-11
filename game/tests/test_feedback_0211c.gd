extends SceneTree
## Director's playthrough 02.11 evening, block Б (Docs/FEEDBACK_DIRECTOR_2026-11-02b_map.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0211c.gd
##   № 2: Tikhon's loaf on the chair — the tail is its own outline: the left ear and the back are not dragged by the
##        tail; self-check — the old vertical line gives the ear a tail weight;
##   № 6: gestures — a gesture picture on the body's own mesh dissolves in and out (the mechanism; the pictures — партия 18);
##   № 14: the caught perch smaller and hanging down; № 16: the rod begins at the fist, not behind the hand;
##   № 20: the crossings back to the turn and from it — no painted bank fading in (arrival_fade false), the same rope
##        and ring as there;
##   № 25: Tikhon at the dinner breathes and moves his head on his lines.
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
	await _test("0211c-2 the loaf's tail is its own outline: the ear and the back stay; self-check — the old line drags the ear", _test_tail)
	await _test("0211c-6 a gesture picture on the body's mesh dissolves in and out, never while he speaks", _test_gesture)
	await _test("0211c-14/16 the perch smaller and hanging; the rod begins at the fist", _test_fishing_look)
	await _test("0211c-20 the crossings to and from the turn: no painted bank fading in, the same rope and ring", _test_crossings)
	await _test("0211c-25 Tikhon at the dinner breathes and moves with his words", _test_dinner_tikhon)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== feedback 02.11 evening, block Б: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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

func _puppet() -> Node:
	var pups: Array = load("res://scripts/actors/puppet_actor.gd").all_in(rm.current_room)
	return pups[0] if not pups.is_empty() else null


## The tail weight of the mesh vertex nearest to `src` (source px of the pose).
func _tail_w(p: Node, src: Vector2) -> float:
	var poly: Polygon2D = p.get("poly")
	var feet: Array = p.get("spec").get("feet_px", [0, 0])
	var ts := float(p.get("tex_scale"))
	var best := -1
	var bd := INF
	for i in poly.polygon.size():
		var q: Vector2 = poly.polygon[i] / ts + Vector2(float(feet[0]), float(feet[1]))
		var d := q.distance_to(src)
		if d < bd:
			bd = d
			best = i
	var w := 0.0
	for b in poly.get_bone_count():
		if String(poly.get_bone_path(b)).get_file().begins_with("tail"):
			w += poly.get_bone_weights(b)[best]
	return w


func _test_tail() -> void:
	_fresh()
	await _enter("H1")
	await _finish()
	var p := _puppet()
	_check(p != null and String(p.get("variant")) == "loaf", "Tikhon in the loaf on the chair (before the shelf)")
	if p == null:
		return
	var ear := _tail_w(p, Vector2(625, 470))     # the left ear's foot, by the tail's top
	var back := _tail_w(p, Vector2(640, 700))    # the back behind the tail
	var tail := _tail_w(p, Vector2(300, 900))    # the tail's middle
	_check(ear < 0.05 and back < 0.25, "the ear (%.2f) and the back (%.2f) not dragged by the tail" % [ear, back])
	_check(tail > 0.9, "the tail itself follows its bones (%.2f)" % tail)
	# self-check: the old vertical line (no tail_poly) gave the ear a share of the tail
	var regs: Dictionary = p.get("spec")["regions"]
	var keep = regs["tail_poly"]
	regs.erase("tail_poly")
	p.call("_skin", (p.get("poly") as Polygon2D).polygon)
	var ear_old := 0.0
	ear_old = _tail_w_last(p, Vector2(625, 470))
	regs["tail_poly"] = keep
	_check(ear_old > 0.3, "self-check: with the old line the ear went with the tail (%.2f)" % ear_old)


## After a re-skin the polygon has a second set of bones appended: read the last set.
func _tail_w_last(p: Node, src: Vector2) -> float:
	var poly: Polygon2D = p.get("poly")
	var feet: Array = p.get("spec").get("feet_px", [0, 0])
	var ts := float(p.get("tex_scale"))
	var best := -1
	var bd := INF
	for i in poly.polygon.size():
		var q: Vector2 = poly.polygon[i] / ts + Vector2(float(feet[0]), float(feet[1]))
		var d := q.distance_to(src)
		if d < bd:
			bd = d
			best = i
	var n := poly.get_bone_count()
	var bones: int = (p.get("bones") as Dictionary).size()
	var w := 0.0
	for b in range(n - bones, n):
		if String(poly.get_bone_path(b)).get_file().begins_with("tail"):
			w += poly.get_bone_weights(b)[best]
	return w


func _test_gesture() -> void:
	_fresh(["q04_corner_stove"])
	await _enter("H1")
	await _finish()
	var p := _puppet()
	_check(p != null and String(p.get("variant")) == "", "Tikhon on his shelf in the base pose")
	# the loaf on the chair has no gestures of its own (the pictures belong to the base pose)
	if p == null:
		return
	# партия 18: two gestures (the ear, the belly) from the data
	var gp: Array = p.get("gesture_polys")
	_check(gp.size() == 2, "both gesture pictures built on the mesh: %d" % gp.size())
	for g0 in gp:
		_check((g0 as Polygon2D).texture != (p.get("poly") as Polygon2D).texture and (g0 as Polygon2D).modulate.a == 0.0, "a gesture of its own picture, hidden at rest")
	for g0 in gp:
		(g0 as Polygon2D).get_meta("spec")["hold_s"] = 0.4
		(g0 as Polygon2D).get_meta("spec")["fade_s"] = 0.15
	if gp.is_empty():
		return
	var g: Polygon2D = gp[0]
	var body: Polygon2D = p.get("poly")
	_check(g.get_bone_count() == body.get_bone_count() and g.polygon.size() == body.polygon.size(), "same mesh and bones as the body")
	p.call("play_gesture", 0)
	await _wait_s(0.3)
	_check(g.modulate.a > 0.9 and int(p.get("gesture_on")) == 0, "dissolved in (%.2f)" % g.modulate.a)
	await _wait_s(0.6)
	_check(g.modulate.a < 0.05 and int(p.get("gesture_on")) == -1, "and out again (%.2f)" % g.modulate.a)
	p.call("play_gesture", 0)
	await _wait_s(0.2)
	p.set("talking", true)
	await _wait_s(0.3)
	_check(g.modulate.a < 0.05, "a line — the paw goes back at once (%.2f)" % g.modulate.a)
	p.set("talking", false)


func _wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame


func _test_fishing_look() -> void:
	var fp_script = load("res://scripts/mechanics/fishing_panel.gd")
	var pc: Dictionary = fp_script.SPRITES["perch_caught"]
	_check(float(pc["scale"]) <= 0.21 and float(pc.get("rot_deg", 0.0)) >= 60.0, "the perch smaller (%.3f, was 0.283) and hanging (%.0f°)" % [float(pc["scale"]), float(pc.get("rot_deg", 0.0))])
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
	await _frames(6)
	var fp: Node = _find_panel(root)
	_check(fp != null, "the fishing panel")
	if fp == null:
		return
	var rs: Dictionary = fp.get("rod_seen")
	_check(not rs.is_empty(), "the rod drawn from her hand: %s" % str(rs))
	if not rs.is_empty():
		var grip: Vector2 = rs["grip"]
		var dirv: Vector2 = (rs["tip"] as Vector2) - grip
		var out: float = ((rs["butt"] as Vector2) - grip).dot(dirv.normalized())
		_check(out > 0.0, "the rod starts at the fist's far side (%.1f px past the grip), not behind the hand" % out)
		_check((rs["grip"] as Vector2).y > (rs["hand"] as Vector2).y, "the grip a palm below the wrist bone")
		# self-check: the old butt (behind the grip by 0,12 of the rod) lies behind the hand
		var old := (rs["hand"] as Vector2) - ((rs["tip"] as Vector2) - (rs["hand"] as Vector2)) * 0.12
		_check((old - grip).dot(dirv.normalized()) < 0.0, "self-check: the old butt was behind the hand")
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


func _test_crossings() -> void:
	var specs: Array = []
	for rid in ["R2", "R3", "Z3"]:
		for e in sd.rooms[rid].get("exits", []):
			var m: Dictionary = e.get("mechanic", {})
			if String(m.get("type", "")) == "crossing":
				specs.append([rid + "→" + String(e.get("to", "")), m])
	_check(specs.size() >= 3, "three crossings by the rope: %d" % specs.size())
	for s in specs:
		var m: Dictionary = s[1]
		var art: Dictionary = m.get("art", {})
		_check(m.get("arrival_fade", true) == false, "%s: no painted bank fading in (arrival_fade false)" % s[0])
		_check(String(art.get("rope", "")).ends_with("fg_rope_clean.png") and art.has("ring_back") and art.has("ring_front"), "%s: the clean rope and the ring of two halves" % s[0])


func _test_dinner_tikhon() -> void:
	_fresh()
	load("res://scripts/rooms/frame_video.gd").set("videos_enabled", false)   # the drawn Tikhon is the clip-less variant (since 10.11 every cup has clips)
	await _enter("EP_dinner")
	load("res://scripts/rooms/frame_video.gd").set("videos_enabled", true)
	var lay: Node = rm.current_room.get_node_or_null("Layers/tikhon")
	_check(lay != null and lay.get("life_mat") != null and String(lay.get("life_char")) == "tikhon", "the dinner's Tikhon has the frame's life (%s)" % (str(lay.get("life_char")) if lay != null else "no layer"))
	if lay == null:
		return
	sr.current_beat = {"type": "line", "speaker": "tikhon", "line_id": "M26_30", "text": "Полка у печи — моя приёмная."}
	await _wait_s(0.8)
	_check(float(lay.get("life_talk")) > 0.5, "on his line his head moves (life_talk %.2f)" % float(lay.get("life_talk")))
	sr.current_beat = {}
	await _frames(3)
