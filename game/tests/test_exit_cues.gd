extends SceneTree
## Headless test of the exit hints (Director 18.10: «Проход в галерею не интуитивен, что нужно нажать
## вниз» — exits off the frame edge were invisible):
##   godot --headless --path game -s res://tests/test_exit_cues.gd
##   1. every exit of every room (rooms/_index.json in_scope) either has a mark (ExitCue) or is drawn
##      in the art (cue "door", no mark); a mark's direction equals the frame edge its exit rect
##      touches; the mark lies in the exit rect and a click there picks that exit; it stays in the
##      frame under the top bar, does not cover another mark or a hotspot's centre;
##   2. ExitCue.classify — the derivation rules on synthetic rects (edge, two edges, side, explicit);
##   3. hover: the pointer on an exit → its mark is hot, the caption with the destination icon, the
##      cursor stays the ordinary pointer (the big exit arrows are gone, Director 18.10); on an object →
##      «перст» (look); off → back to normal;
##   4. the reveal key (Space): every active hotspot and every exit of the room for 1.5 s, the exit
##      marks light up; nothing during a dialogue; the menu names the key;
##   5. marks fade out under a dialogue and come back after it.
## Cursor drawings, every exit's icon and its layout, the hint panel, the Z4 sign: tests/test_ui_cursors.gd.
## Exit code 0 only when every check passed.

const TOP_H := 80.0

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null


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
	Input.use_accumulated_input = false   # parse_input_event moves the pointer at once (headless reads Input)
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	await _test("Every exit of every room: a mark or drawn in the art; direction = frame edge; mark in the exit rect, clickable, in the frame, not under the bar", _test_rooms)
	await _test("ExitCue.classify: edge, two edges, side, explicit cue, inner rect = door", _test_classify)
	await _test("Hover: exit → mark hot + caption + icon, ordinary pointer (no exit arrow cursor); drawn door → the same; object → «перст»", _test_hover)
	await _test("Space: every active hotspot and exit for 1.5 s, marks light up; nothing during a dialogue; menu names the key", _test_reveal)
	await _test("Marks fade out under a dialogue and return", _test_cursors_and_fade)
	await _test("F20 (Director 23.10): no «к повороту» at the mill; «спуск к причалу» higher and north-east; «в переулок к почте» mid-road", _test_f20)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== exit cues: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait_s(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _physics(n: int = 3) -> void:
	for i in n:
		await physics_frame


func _enter(room: String) -> void:
	sr.call("_on_state_reset")
	rm.change_room(room, "")
	await _frames(2)
	await _physics(3)
	sr.call("_on_state_reset")   # no scene dialogue left over (M01, V02 …)
	await _frames(1)


func _exits() -> Array:
	var out: Array = []
	for e in rm.current_room.get_exits():
		if e.has_method("cursor_kind"):
			out.append(e)
	return out


func _exit_to(target: String) -> Node:
	for e in _exits():
		if String(e.get("target_room")) == target:
			return e
	return null


func _exit_rect(e: Node2D) -> Rect2:
	var shape: CollisionShape2D = e.get_node("Shape")
	var sz: Vector2 = (shape.shape as RectangleShape2D).size
	return Rect2(e.global_position - sz * 0.5, sz)


func _move_mouse(at: Vector2) -> void:
	# Headless: the viewport reads the pointer from Input in window pixels (the window is tiny and the
	# 1920×1080 canvas is stretched into it) — so the event for Input goes through the screen transform.
	var win := InputEventMouseMotion.new()
	win.position = root.get_screen_transform() * at
	win.global_position = win.position
	Input.parse_input_event(win)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)   # Controls under the pointer (bar, panels) see it in canvas pixels
	await _frames(3)
	if root.get_mouse_position().distance_to(at) > 1.0:
		_fails.append("pointer not moved to %s (viewport reads %s)" % [str(at), str(root.get_mouse_position())])


func _press_space() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		ev.keycode = KEY_SPACE
		ev.pressed = pressed
		root.push_input(ev, true)
		await _frames(1)


# --- 1. Every room -----------------------------------------------------------------------

func _test_rooms() -> void:
	var rooms: Array = sd.rooms_index.get("in_scope", [])
	_check(rooms.size() >= 11, "in_scope lists the rooms (%d)" % rooms.size())
	var marks := 0
	var doors := 0
	for rid in rooms:
		await _enter(String(rid))
		var room = rm.current_room
		_check(room != null and room.room_id == rid, "%s: room built" % rid)
		if room == null:
			continue
		var placed: Array = []   # [target, covered rect]
		var hotspot_centres: Array = []
		for h in room.get_hotspots():
			if h.has_method("is_active") and h.is_active():
				hotspot_centres.append([h.hotspot_id, h.global_position])   # rect centre (states may move it)
		for e in _exits():
			var se = e
			var tag := "%s→%s" % [rid, se.target_room]
			var rect := _exit_rect(se)
			var edges := ExitCue.touched_edges(rect)
			_check(se.cue_dir in ["door", "left", "right", "down", "up"], "%s: cue '%s'" % [tag, se.cue_dir])
			if se.cue_dir == "door":
				doors += 1
				_check(se.cue == null and se.get_node_or_null("Cue") == null, "%s: drawn in the art — no mark" % tag)
				_check(not (se.cue_source == "edge" or se.cue_source == "side"), "%s: a door must come from data (cue) or an inner rect, not from an edge" % tag)
				continue
			marks += 1
			var cue: ExitCue = se.cue
			_check(cue != null and is_instance_valid(cue) and cue.get_parent() == se, "%s: mark node under the exit" % tag)
			if cue == null:
				continue
			_check(cue.direction == se.cue_dir, "%s: mark direction %s = exit cue %s" % [tag, cue.direction, se.cue_dir])
			if not edges.is_empty():
				_check(cue.direction in edges, "%s: rect %s touches %s, mark points %s" % [tag, str(rect), str(edges), cue.direction])
			else:
				_check(se.cue_source == "cue", "%s: a mark inside the frame (path into the depth) must be set in data, got %s" % [tag, se.cue_source])
			var at := cue.global_position
			_check(rect.grow(0.5).has_point(at), "%s: mark %s inside the exit rect %s (click on it = the exit)" % [tag, str(at), str(rect)])
			var picked = room.pick(at)
			_check(picked == se, "%s: a click on the mark picks the exit (got %s)" % [tag, str(picked.get("name") if picked != null else null)])
			var cov := cue.covered_rect()
			_check(cov.position.y >= TOP_H + 4.0, "%s: mark %s stays under the top bar / bag" % [tag, str(cov)])
			_check(cov.position.x >= -2.0 and cov.end.x <= 1922.0 and cov.end.y <= 1082.0, "%s: mark %s inside the frame" % [tag, str(cov)])
			# A slanted mark (F20: «спуск к причалу» на северо-восток) carries the data angle.
			if se.data.has("cue_deg"):
				_check(is_equal_approx(cue.angle_deg, float(se.data["cue_deg"])), "%s: mark angle %s = cue_deg %s" % [tag, str(cue.angle_deg), str(se.data["cue_deg"])])
			else:
				_check(is_nan(cue.angle_deg), "%s: no cue_deg — the mark points along its direction" % tag)
			# At the frame edge for an edge exit: within 60 px of that edge — unless the data places it
			# (cue_at: F20 «в переулок к почте — на середину дороги и чуть правее»).
			match "" if se.data.has("cue_at") else cue.direction:
				"down":
					if "down" in edges:
						_check(at.y >= 1080.0 - 60.0, "%s: mark at the bottom edge (y %.0f)" % [tag, at.y])
				"left":
					if "left" in edges:
						_check(at.x <= 60.0, "%s: mark at the left edge (x %.0f)" % [tag, at.x])
				"right":
					if "right" in edges:
						_check(at.x >= 1920.0 - 60.0, "%s: mark at the right edge (x %.0f)" % [tag, at.x])
			for p in placed:
				_check(not (p[1] as Rect2).intersects(cov), "%s: mark overlaps the mark of %s" % [tag, p[0]])
			for hc in hotspot_centres:
				_check(not cov.has_point(hc[1]), "%s: mark covers the centre of hotspot %s" % [tag, hc[0]])
			placed.append([se.target_room, cov])
	_check(marks >= 8, "marks built: %d" % marks)
	_check(doors >= 8, "drawn doors: %d" % doors)
	print("        marks %d, drawn doors %d" % [marks, doors])


# --- 2. Rules -----------------------------------------------------------------------------

func _test_classify() -> void:
	var cases := [
		[{}, Rect2(420, 995, 840, 85), "down", "edge"],               # Z4 → street: wide at the bottom
		[{}, Rect2(0, 660, 100, 420), "left", "edge"],                # left + bottom, tall → left
		[{}, Rect2(1800, 760, 120, 320), "right", "edge"],            # right + bottom, tall → right
		[{}, Rect2(0, 990, 400, 90), "down", "edge"],                 # left + bottom, wide → down
		[{}, Rect2(860, 150, 240, 540), "door", "default"],           # inner rect → drawn door
		[{"side": "bottom", "x": 1100}, Rect2(900, 1000, 400, 80), "down", "side"],
		[{"side": "right"}, Rect2(1790, 560, 130, 520), "right", "side"],
		[{"cue": "door"}, Rect2(1790, 90, 130, 610), "door", "cue"],  # a drawn door at the edge (O1 → O2)
		[{"cue": "up"}, Rect2(380, 560, 320, 90), "up", "cue"],        # path into the depth
	]
	for c in cases:
		var info := ExitCue.classify(c[0], c[1])
		_check(info["dir"] == c[2] and info["source"] == c[3], "classify(%s, %s) = %s/%s, expected %s/%s" % [str(c[0]), str(c[1]), info["dir"], info["source"], c[2], c[3]])
	var bottom := ExitCue.classify({}, Rect2(420, 995, 840, 85))
	_check((bottom["at"] as Vector2).is_equal_approx(Vector2(840, 1080.0 - ExitCue.EDGE_INSET)), "bottom mark at the edge under the rect centre: %s" % str(bottom["at"]))
	var high := ExitCue.classify({}, Rect2(0, 60, 100, 200))
	_check((high["at"] as Vector2).y >= ExitCue.TOP_SAFE, "a side mark never rises under the bar: %s" % str(high["at"]))
	var depth := ExitCue.classify({"cue": "up"}, Rect2(380, 560, 320, 90))
	_check((depth["at"] as Vector2).is_equal_approx(Vector2(540, 605)), "a path mark at the rect centre: %s" % str(depth["at"]))
	var at := ExitCue.classify({"cue": "down", "cue_at": [700, 1030]}, Rect2(500, 1000, 400, 80))
	_check((at["at"] as Vector2).is_equal_approx(Vector2(700, 1030)), "cue_at wins: %s" % str(at["at"]))


# --- 3. Hover -----------------------------------------------------------------------------

func _test_hover() -> void:
	await _enter("Z4")
	var street = _exit_to("Z2")
	_check(street != null and street.cue_dir == "down" and street.cue != null, "Z4: the street exit has a down mark (Director 18.10)")
	if street == null or street.cue == null:
		return
	await _move_mouse(street.cue.global_position)
	await _frames(4)
	_check(street.cue.is_hot(), "pointer on the mark: the mark is hot")
	# Director 18.10: the big exit arrow cursor is gone — over an exit the ordinary «стрела-указка».
	_check(String(ui.get("_cursor_kind")) == "arrow", "exit: ordinary pointer, no exit arrow (got '%s')" % ui.get("_cursor_kind"))
	_check(int(ui.get("cursor_shape")) == Input.CURSOR_ARROW, "exit: cursor shape is the arrow (%d)" % int(ui.get("cursor_shape")))
	var hover: Label = ui.get("hover_label")
	_check(hover.visible and hover.text == sd.text("@Z4.exit_Z2.label"), "caption «%s» (got «%s»)" % [sd.text("@Z4.exit_Z2.label"), hover.text])
	var icon: TextureRect = ui.get("hover_icon")
	_check(icon.visible and icon.texture != null, "exit caption carries the destination icon")
	# A drawn door: no mark, the ordinary pointer, the caption and the icon.
	var post = _exit_to("Z1")
	_check(post != null and post.cue_dir == "door" and post.cue == null, "Z4: the post-office door is drawn — no mark")
	if post != null:
		await _move_mouse(_exit_rect(post).get_center())
		await _frames(3)
		_check(String(ui.get("_cursor_kind")) == "arrow", "drawn door: ordinary pointer (got '%s')" % ui.get("_cursor_kind"))
		_check(icon.visible, "drawn door: the destination icon")
		_check(hover.visible and hover.text == sd.text("@Z4.exit_Z1.label"), "drawn door caption «%s»" % hover.text)
		_check(not street.cue.is_hot(), "the street mark is no longer hot")
	# An object: the ordinary pointer.
	var obj = null
	for h in rm.current_room.get_hotspots():
		if h.has_method("is_active") and h.is_active():
			obj = h
			break
	if obj != null:
		var c: Vector2 = obj.global_position
		await _move_mouse(c)
		await _frames(3)
		if rm.current_room.pick(c) == obj:
			_check(String(ui.get("_cursor_kind")) == "look", "object «%s»: «перст» (got '%s')" % [obj.hotspot_id, ui.get("_cursor_kind")])
			_check(not icon.visible, "object «%s»: no destination icon" % obj.hotspot_id)
	# Empty floor: back to normal.
	await _move_mouse(Vector2(1000, 700))
	await _frames(3)
	if rm.current_room.pick(Vector2(1000, 700)) == null:
		_check(String(ui.get("_cursor_kind")) == "arrow" and not street.cue.is_hot() and not icon.visible, "off the exit: ordinary pointer, mark idle, no icon")
	# The gallery from the living room (H1): whatever the H1 data says, the player sees how to get there.
	await _enter("H1")
	var gal = _exit_to("H3")
	_check(gal != null, "H1 has an exit to the gallery")
	if gal != null:
		_check(gal.cue_dir == "door" or gal.cue != null, "H1→H3: a mark or a drawn door (%s)" % gal.cue_dir)
		var at: Vector2 = gal.cue.global_position if gal.cue != null else _exit_rect(gal).get_center()
		await _move_mouse(at)
		await _frames(3)
		_check(String(ui.get("_cursor_kind")) == "arrow", "H1→H3: ordinary pointer (got '%s')" % ui.get("_cursor_kind"))
		_check(hover.visible and hover.text == gal.label_text(), "H1→H3: caption «%s»" % hover.text)
	await _move_mouse(Vector2(4, 1076))


# --- 4. Reveal ----------------------------------------------------------------------------

func _test_reveal() -> void:
	await _enter("Z2")
	await _move_mouse(Vector2(960, 500))
	var reveal: HotspotReveal = ui.get("reveal")
	_check(not reveal.active(), "no reveal before the key")
	await _press_space()
	_check(reveal.active(), "Space starts the reveal")
	var ids: Array = []
	for t in reveal.targets:
		ids.append("%s:%s" % [t["kind"], t["id"]])
	for h in rm.current_room.get_hotspots():
		if h.has_method("is_active") and h.is_active():
			_check(ids.has("hotspot:" + h.hotspot_id), "reveal shows hotspot %s" % h.hotspot_id)
		elif h.has_method("is_active"):
			_check(not ids.has("hotspot:" + h.hotspot_id), "hidden hotspot %s is not revealed" % h.hotspot_id)
	for e in _exits():
		_check(ids.has("exit:" + e.target_room), "reveal shows exit → %s" % e.target_room)
		if e.cue != null:
			_check(e.cue.is_hot(), "exit mark → %s lit during the reveal" % e.target_room)
	for t in reveal.targets:
		var lr: Rect2 = t.get("label_rect", Rect2())
		_check(lr.size.x > 0 and lr.position.y >= TOP_H and lr.end.y <= 1080.0 and lr.position.x >= 0 and lr.end.x <= 1920.0,
			"label of %s:%s on screen under the bar (%s)" % [t["kind"], t["id"], str(lr)])
		_check(String(t.get("label", "")) != "", "label text for %s:%s" % [t["kind"], t["id"]])
	var t0 := Time.get_ticks_msec()
	while reveal.active() and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	var lasted := (Time.get_ticks_msec() - t0) / 1000.0
	_check(not reveal.active() and lasted >= 1.2 and lasted <= 2.0, "the reveal ends after ≈1.5 s (%.2f s)" % lasted)
	for e in _exits():
		if e.cue != null:
			_check(not e.cue.revealed, "mark → %s back to idle after the reveal" % e.target_room)
	# Nothing during a dialogue.
	sr.set("current_beat", {"type": "line", "text": "…", "speaker_name": ""})
	await _frames(2)
	await _press_space()
	_check(not reveal.active(), "no reveal while a dialogue is open")
	sr.call("_on_state_reset")
	await _frames(2)
	# Pressing again restarts; a room change ends it.
	await _press_space()
	_check(reveal.active(), "Space again → reveal")
	rm.change_room("Z3", "")
	await _frames(2)
	_check(not reveal.active(), "room change ends the reveal")
	sr.call("_on_state_reset")
	# The menu names the key.
	var keys: Label = ui.get("menu_panel").find_child("KeysHint", true, false)
	_check(keys != null and keys.text == sd.text("@ui.controls_reveal") and keys.text.contains("Пробел"), "menu line names the key: «%s»" % (keys.text if keys else "—"))
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	_check(ev.is_action_pressed("reveal_hotspots"), "Space is bound to reveal_hotspots")
	for a in ["quick_save", "quick_load"]:
		_check(not ev.is_action_pressed(a), "Space does not trigger %s" % a)


# --- 5. Cursor images, fade under dialogue ------------------------------------------------

func _alpha_at(img: Image, x: int, y: int) -> float:
	return img.get_pixel(x, y).a


func _test_cursors_and_fade() -> void:
	var tex := ExitCue.textures()
	_check(tex.has("mark") and (tex["mark"] as Texture2D).get_width() == int(ExitCue.MARK_CANVAS), "mark texture rasterised")
	# Fade: marks visible in a room, gone under a dialogue, back after it.
	await _enter("Z3")
	await _move_mouse(Vector2(4, 300))
	var cue: ExitCue = null
	for e in _exits():
		if e.cue != null:
			cue = e.cue
			break
	_check(cue != null, "Z3 has a mark")
	if cue == null:
		return
	await _wait_s(0.8)
	var idle := cue.current_alpha()
	_check(idle > 0.3, "mark visible in the room (alpha %.2f)" % idle)
	sr.set("current_beat", {"type": "line", "text": "…", "speaker_name": ""})
	await _wait_s(0.8)
	_check(cue.current_alpha() < 0.05, "mark fades out under a dialogue (alpha %.2f)" % cue.current_alpha())
	sr.call("_on_state_reset")
	await _wait_s(0.8)
	_check(cue.current_alpha() > 0.3, "mark back after the dialogue (alpha %.2f)" % cue.current_alpha())


# --- F20 ----------------------------------------------------------------------------------

## Director 23.10: «от мельницы стрелка „к повороту“ — убрать, только путает»; «„спуск к причалу“ у дома
## чуть поднять и направить на северо-восток»; «„в переулок к почте“ — поднять на середину дороги и чуть
## правее». The mill ↔ turn path is gone both ways (the turn is reached from the street or the pier).
func _test_f20() -> void:
	gs.set_flag("done_M01", true)
	await _enter("M1")
	_check(_exit_to("Z3") == null, "M1: no exit to the turn (Z3)")
	await _enter("Z3")
	_check(_exit_to("M1") == null, "Z3: no exit to the mill (M1)")
	# H7 (Director 24.10): from the turn only the way to the pier, its mark — the old «на улицу» one turned north-west.
	_check(_exit_to("Z2") == null and _exit_to("R1") != null, "H7: Z3 leads only to the pier")
	var to_pier = _exit_to("R1")
	if to_pier != null and to_pier.cue != null:
		var ap: float = to_pier.cue.angle_deg
		_check(ap <= -110.0 and ap >= -160.0, "H7: Z3 → pier mark points north-west (angle %s)" % str(ap))
	await _enter("R1")
	var to_turn = _exit_to("Z3")
	_check(to_turn != null and to_turn.cue != null and to_turn.cue.global_position.x < 400.0 and to_turn.cue.global_position.y > 900.0
		and to_turn.cue.angle_deg >= 20.0 and to_turn.cue.angle_deg <= 70.0, "H7: at the pier, bottom left, a mark south-east to the turn")
	await _enter("Z2")
	var pier = _exit_to("R1")
	_check(pier != null and pier.cue != null, "Z2: «спуск к причалу» has a mark")
	if pier != null and pier.cue != null:
		var a: float = pier.cue.angle_deg
		_check(not is_nan(a) and a <= -110.0 and a >= -160.0, "H7: the pier mark points north-west (angle %s)" % str(a))
		_check(_exit_to("Z3") == null, "H7: from the street only the way down to the pier")
		_check(pier.cue.global_position.y < 695.0 - 15.0, "Z2: the pier mark is raised (y %.0f < 680)" % pier.cue.global_position.y)
		var room = rm.current_room
		_check(room.pick(pier.cue.global_position) == pier, "Z2: a click on the slanted mark is the exit")
	var lane = _exit_to("Z4")
	_check(lane != null and lane.cue != null, "Z2: «в переулок к почте» has a mark")
	if lane != null and lane.cue != null:
		var p: Vector2 = lane.cue.global_position
		_check(p.y >= 640.0 and p.y <= 760.0, "Z2: the lane mark is on the road (y %.0f, road 640–760)" % p.y)
		_check(p.x > 100.0, "Z2: the lane mark is right of the post corner (x %.0f)" % p.x)
		_check(lane.cue.direction == "left", "Z2: the lane mark still points left")
	gs.reset()
