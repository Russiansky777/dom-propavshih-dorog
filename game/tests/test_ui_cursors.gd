extends SceneTree
## Headless test of the interface remarks of Director 18.10:
##   godot --headless --path game -s res://tests/test_ui_cursors.gd
##   1. «старорусский курсор»: every cursor drawing (UiCursors, game/assets/ui/glyphs/cursor_*.svg) is 32×32
##      and 64×64 @2x (not bigger), has the dark-brown ink and the cream contour, the hot spot sits at the
##      very tip (nothing opaque beyond it), each kind has its own shape and the ordinary one is the arrow;
##      the old exit-arrow cursors are gone (no ExitCursors);
##   2. exits: in every room, the pointer on every exit → the ordinary arrow (no big exit arrow), the
##      caption and the destination icon of rooms/_index.json exit_cue.icons (or the exit's `icon`);
##      the icon is left of the caption, does not cover it, both stay in the frame under the bar — also
##      with the pointer at the frame corners; the reveal key shows the icons too;
##   3. hotspots: an object → «перст» (look), a character → arrow with a banderole (talk), an item from
##      the bag in hand → «перст с искрой» (use);
##   4. the hint panel: text ≥ HINT_TEXT_MIN_PX (≥ 24 px at 1280×720), the Space tip in every tier, under
##      the bar in the frame, no duplicate on the bottom line, a click / a dialogue put it away;
##   5. the Z4 sign «ПОЧТА»: the layer is there, every painted pixel lies on the board (rooms/Z4.json
##      layers.post_sign_text.board), the letters cover a real part of it, the sign hotspot is over it.
## Exit code 0 only when every check passed.

const TOP_H := 80.0
const INK := Color("#3d2513")
const CREAM := Color("#f3e5c4")

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
	Input.use_accumulated_input = false
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	await _test("Cursor drawings: 32 px (64 @2x), ink + cream, hot spot at the tip, own shape per kind; no exit-arrow cursors", _test_cursor_images)
	await _test("Every exit of every room: ordinary arrow, caption + destination icon left of it, in the frame", _test_exit_icons)
	await _test("Hotspots: object → look, character → talk, item in hand → use", _test_hotspot_cursors)
	await _test("Hint panel: large text, the Space tip in every tier, under the bar, put away by a click / dialogue", _test_hint_panel)
	await _test("Z4 sign «ПОЧТА»: layer on the board, letters cover it, hotspot over it", _test_sign)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== ui cursors / icons / hint / sign: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- helpers ------------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _physics(n: int = 3) -> void:
	for i in n:
		await physics_frame


func _enter(room: String) -> void:
	sr.call("_on_state_reset")
	rm.change_room(room, "")
	await _frames(2)
	await _physics(3)
	sr.call("_on_state_reset")
	await _frames(1)


func _move_mouse(at: Vector2) -> void:
	var win := InputEventMouseMotion.new()
	win.position = root.get_screen_transform() * at
	win.global_position = win.position
	Input.parse_input_event(win)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	await _frames(3)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)
		await _frames(1)


func _exit_rect(e: Node2D) -> Rect2:
	var shape: CollisionShape2D = e.get_node("Shape")
	var sz: Vector2 = (shape.shape as RectangleShape2D).size
	return Rect2(e.global_position - sz * 0.5, sz)


## A point of the exit where Room.pick answers this exit (a hotspot may sit over part of it).
func _pick_point(e: Node2D) -> Vector2:
	if e.get("cue") != null and rm.current_room.pick(e.cue.global_position) == e:
		return e.cue.global_position
	var r := _exit_rect(e)
	for fy in [0.5, 0.3, 0.7, 0.15, 0.85]:
		for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var p := r.position + r.size * Vector2(fx, fy)
			if p.y > TOP_H + 4 and rm.current_room.pick(p) == e:
				return p
	return Vector2(-1, -1)


func _is_ink(c: Color) -> bool:
	return c.a > 0.9 and absf(c.r - INK.r) < 0.08 and absf(c.g - INK.g) < 0.08 and absf(c.b - INK.b) < 0.08


func _is_cream(c: Color) -> bool:
	return c.a > 0.9 and absf(c.r - CREAM.r) < 0.08 and absf(c.g - CREAM.g) < 0.08 and absf(c.b - CREAM.b) < 0.08


# --- 1. Cursor drawings -------------------------------------------------------------------

func _test_cursor_images() -> void:
	_check(not ResourceLoader.exists("res://scripts/ui/exit_cursors.gd"), "the old exit-arrow cursors (ExitCursors) are gone")
	var shapes := {}
	for kind in UiCursors.SHAPES.keys():
		shapes[UiCursors.shape(kind)] = kind
		_check(UiGlyphs.svg(UiGlyphs.CURSOR_PREFIX + kind).begins_with("<svg"), "cursor_%s.svg is read as text (import «keep»)" % kind)
		for s in [1, 2]:
			var img := UiCursors.image(kind, s)
			_check(img != null and img.get_width() == UiCursors.BASE * s and img.get_height() == UiCursors.BASE * s,
				"%s @%dx: %d px image" % [kind, s, UiCursors.BASE * s])
			if img == null:
				continue
			var ink := 0
			var cream := 0
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if _is_ink(c):
						ink += 1
					elif _is_cream(c):
						cream += 1
			_check(ink > 20 * s * s and cream > 20 * s * s, "%s @%dx: dark-brown ink (%d px) and a cream contour (%d px)" % [kind, s, ink, cream])
			var hs := UiCursors.hotspot(kind, s)
			_check(hs.x >= 0 and hs.y >= 0 and hs.x < img.get_width() and hs.y < img.get_height(), "%s @%dx: hot spot %s in the image" % [kind, s, str(hs)])
			if UiCursors.POINTS.has(kind):
				# The tip: the opaque pixel farthest along the pointing direction; the hot spot is on it.
				var d: Vector2 = UiCursors.POINTS[kind]
				var tip := Vector2.ZERO
				var best := -1e9
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a >= 0.5:
							var p := Vector2(x + 0.5, y + 0.5)
							if p.dot(d) > best:
								best = p.dot(d)
								tip = p
				_check(tip.distance_to(hs + Vector2(0.5, 0.5)) <= 1.5 * s, "%s @%dx: hot spot %s at the tip %s" % [kind, s, str(hs), str(tip)])
			else:
				_check(img.get_pixel(int(hs.x), int(hs.y)).a > 0.5, "%s @%dx: hot spot %s on the hand" % [kind, s, str(hs)])
	_check(shapes.size() == UiCursors.SHAPES.size(), "every cursor kind has its own shape: %s" % str(shapes))
	_check(UiCursors.shape("arrow") == Input.CURSOR_ARROW and UiCursors.shape("") == Input.CURSOR_ARROW, "the ordinary pointer is the arrow")
	_check(UiCursors.pixel_scale() == 1, "headless / web: 32 px cursors")


# --- 2. Exits: arrow, caption, icon -------------------------------------------------------

func _test_exit_icons() -> void:
	var icons: Dictionary = sd.rooms_index.get("exit_cue", {}).get("icons", {})
	var hover: Label = ui.get("hover_label")
	var icon: TextureRect = ui.get("hover_icon")
	var exits_seen := 0
	for rid in sd.rooms_index.get("in_scope", []):
		await _enter(String(rid))
		for e in rm.current_room.get_exits():
			if not e.has_method("icon_name"):
				continue
			if e.has_method("is_active") and not e.is_active():
				continue   # H36: shown only in its state («В лодку» at the turn while the boat is there)
			var se = e   # StoryExit (class names of room scripts need the autoloads: not typed here)
			var want := String(se.data.get("icon", icons.get(se.target_room, "")))
			_check(want != "" and UiGlyphs.exists(UiGlyphs.EXIT_PREFIX + want), "%s→%s: icon «%s» has a drawing" % [rid, se.target_room, want])
			_check(se.icon_name() == want, "%s→%s: icon_name %s = data %s" % [rid, se.target_room, se.icon_name(), want])
			var at := _pick_point(se)
			if at.x < 0:
				_check(false, "%s→%s: no point of the exit picks it" % [rid, se.target_room])
				continue
			await _move_mouse(at)
			await _frames(2)
			exits_seen += 1
			var tag := "%s→%s" % [rid, se.target_room]
			_check(String(ui.get("_cursor_kind")) == "arrow" and int(ui.get("cursor_shape")) == Input.CURSOR_ARROW,
				"%s: ordinary arrow over the exit — no exit-arrow cursor (kind '%s', shape %d)" % [tag, ui.get("_cursor_kind"), int(ui.get("cursor_shape"))])
			_check(hover.visible and hover.text == se.label_text(), "%s: caption «%s»" % [tag, hover.text])
			_check(icon.visible and icon.texture != null, "%s: destination icon shown" % tag)
			if icon.visible:
				_layout_ok(tag, icon.get_global_rect(), hover.get_global_rect())
				_check(String(ui.call("exit_hints_probe")["hover_icon"]) == want, "%s: probe names icon %s" % [tag, want])
	_check(exits_seen >= 25, "hovered %d exits" % exits_seen)
	# The pair stays in the frame at its corners (long caption, pointer at the right / bottom / top).
	await _enter("Z4")
	ui.call("_show_hover", "Очень длинная подпись выхода для проверки края кадра", "street")
	for p in [Vector2(1915, 1075), Vector2(1915, TOP_H + 2), Vector2(4, 1075), Vector2(4, TOP_H + 2), Vector2(960, 540)]:
		ui.call("_place_hover", p)
		_layout_ok("corner %s" % str(p), icon.get_global_rect(), hover.get_global_rect())
	ui.call("_show_hover", "", "")
	_check(not icon.visible and not hover.visible, "caption and icon go out together")
	# Space: exit names carry their icons too.
	await _move_mouse(Vector2(960, 700))
	ui.call("reveal_hotspots")
	await _frames(2)
	var reveal: HotspotReveal = ui.get("reveal")
	for t in reveal.targets:
		if String(t["kind"]) == "exit":
			_check(t.get("icon_tex") != null, "Space: exit %s shows its icon" % t["id"])
			var lr: Rect2 = t["label_rect"]
			_check(lr.position.x >= 0 and lr.end.x <= 1920 and lr.position.y >= TOP_H and lr.end.y <= 1080, "Space: %s label with icon in the frame %s" % [t["id"], str(lr)])
	reveal.cancel()


func _layout_ok(tag: String, ir: Rect2, hr: Rect2) -> void:
	_check(ir.end.x <= hr.position.x + 0.5, "%s: icon %s left of the caption %s, not over it" % [tag, str(ir), str(hr)])
	_check(absf(ir.get_center().y - hr.get_center().y) <= 3.0, "%s: icon centred on the caption line" % tag)
	_check(ir.size.y >= 24.0 and ir.size.y <= 30.0, "%s: icon %.0f px tall (24–30)" % [tag, ir.size.y])
	for r in [ir, hr]:
		_check(r.position.x >= 0 and r.end.x <= 1920 and r.position.y >= TOP_H and r.end.y <= 1080, "%s: %s in the frame under the bar" % [tag, str(r)])


# --- 3. Hotspot cursors -------------------------------------------------------------------

func _hotspot(id: String) -> Node2D:
	for h in rm.current_room.get_hotspots():
		if h.has_method("is_active") and String(h.get("hotspot_id")) == id:
			return h
	return null


func _hover_hotspot(h: Node2D) -> bool:
	var c: Vector2 = h.global_position
	for d in [Vector2.ZERO, Vector2(0, -20), Vector2(0, 20), Vector2(-20, 0), Vector2(20, 0)]:
		if rm.current_room.pick(c + d) == h:
			await _move_mouse(c + d)
			await _frames(2)
			return true
	return false


func _test_hotspot_cursors() -> void:
	await _enter("Z1")
	var tamara := _hotspot("tamara")
	var letters := _hotspot("letters")
	_check(tamara != null and letters != null, "Z1: Tamara and the letters")
	if tamara == null or letters == null:
		return
	if await _hover_hotspot(letters):
		_check(String(ui.get("_cursor_kind")) == "look" and int(ui.get("cursor_shape")) == Input.CURSOR_POINTING_HAND, "object: «перст» (got %s)" % ui.get("_cursor_kind"))
		_check(not (ui.get("hover_icon") as TextureRect).visible, "object: no destination icon")
	else:
		_check(false, "letters not pickable")
	if await _hover_hotspot(tamara):
		_check(String(ui.get("_cursor_kind")) == "talk" and int(ui.get("cursor_shape")) == Input.CURSOR_HELP, "character: arrow with a banderole (got %s)" % ui.get("_cursor_kind"))
	else:
		_check(false, "Tamara not pickable")
	gs.add_item("key_house")
	sr.select_item("key_house")
	await _frames(2)
	if await _hover_hotspot(letters):
		_check(String(ui.get("_cursor_kind")) == "use" and int(ui.get("cursor_shape")) == Input.CURSOR_CROSS, "item in hand over an object: «перст с искрой» (got %s)" % ui.get("_cursor_kind"))
	sr.select_item("")
	await _frames(2)
	await _move_mouse(Vector2(1000, 760))
	if rm.current_room.pick(Vector2(1000, 760)) == null:
		_check(String(ui.get("_cursor_kind")) == "arrow", "empty floor: the arrow (got %s)" % ui.get("_cursor_kind"))
	# An exit that takes an item (Z2 → H1: the house key at the door) — «перст с искрой» with the key in hand.
	await _enter("Z2")
	var door: Node2D = null
	for e in rm.current_room.get_exits():
		if String(e.get("target_room")) == "H1":
			door = e
	if door != null and (door.get("data") as Dictionary).has("item_use"):
		gs.add_item("key_house")
		sr.select_item("key_house")
		var at := _pick_point(door)
		await _move_mouse(at)
		await _frames(2)
		_check(String(ui.get("_cursor_kind")) == "use", "key in hand over the house door: «перст с искрой» (got %s)" % ui.get("_cursor_kind"))
		sr.select_item("")
		await _frames(2)
		await _move_mouse(at + Vector2(1, 0))
		await _frames(2)
		_check(String(ui.get("_cursor_kind")) == "arrow", "empty hand over the door: the arrow (got %s)" % ui.get("_cursor_kind"))
	gs.reset()
	await _frames(2)


# --- 4. Hint panel ------------------------------------------------------------------------

func _test_hint_panel() -> void:
	await _enter("Z4")
	await _move_mouse(Vector2(960, 760))
	var panel: PanelContainer = ui.get("hint_panel")
	var text: Label = ui.get("hint_text")
	var tip: Label = ui.get("hint_tip")
	var line: Label = ui.get("hint_line")
	var min_px := int(ui.get("HINT_TEXT_MIN_PX"))
	_check(min_px * 720.0 / 1080.0 >= 24.0, "the minimum itself reads at 1280×720 (%d → %.1f px)" % [min_px, min_px * 720.0 / 1080.0])
	for tier in [1, 2, 3]:
		ui.call("_on_hint_pressed")
		await _frames(3)
		_check(panel.visible, "tier %d: panel shown" % tier)
		var px: int = text.get_theme_font_size("font_size")
		_check(px >= min_px, "tier %d: hint text %d px ≥ %d (%.1f px at 1280×720)" % [tier, px, min_px, px * 720.0 / 1080.0])
		_check(text.get_theme_font("font").get_font_name() == "PT Serif", "hint text face PT Serif")
		_check(text.text != "", "tier %d: text" % tier)
		_check(String(ui.get("hint_title").text) == sd.text("@ui.hint_title", {"tier": mini(tier, 3)}), "tier %d: title «%s»" % [tier, ui.get("hint_title").text])
		_check(tip.visible and tip.text == sd.text("@ui.hint_space_tip") and tip.text.contains("Пробел"), "tier %d: the Space tip «%s»" % [tier, tip.text])
		_check(tip.get_theme_font_size("font_size") >= 26, "tier %d: tip %d px" % [tier, tip.get_theme_font_size("font_size")])
		var r := panel.get_global_rect()
		_check(r.position.y >= TOP_H and r.end.y <= 1080 and r.position.x >= 0 and r.end.x <= 1920, "tier %d: panel %s in the frame under the bar" % [tier, str(r)])
		_check(tip.get_global_rect().end.y <= r.end.y and text.get_global_rect().end.y <= r.end.y, "tier %d: text and tip inside the panel" % tier)
		_check(not line.text.contains(text.text), "tier %d: no duplicate on the bottom line" % tier)
	_check(sd.text("@ui.hint_space_tip") == "Пробел — показать все места и действия", "tip text (data, ru_exits.json)")
	# A click anywhere puts it away (the click goes on).
	await _click(Vector2(960, 760))
	_check(not panel.visible, "click: panel away")
	# A dialogue puts it away.
	ui.call("_on_hint_pressed")
	await _frames(2)
	_check(panel.visible, "shown again")
	sr.set("current_beat", {"type": "line", "text": "…", "speaker_name": ""})
	await _frames(3)
	_check(not panel.visible, "dialogue: panel away")
	sr.call("_on_state_reset")
	await _frames(2)
	gs.reset()


# --- 5. Z4 sign ---------------------------------------------------------------------------

func _test_sign() -> void:
	await _enter("Z4")
	var spec: Dictionary = {}
	for l in _z4_layers():
		if String(l.get("id", "")) == "post_sign_text":
			spec = l
	_check(not spec.is_empty(), "rooms/Z4.json has the layer post_sign_text")
	var node: Node = rm.current_room.find_child("post_sign_text", true, false)
	_check(node != null and (node as CanvasItem).is_visible_in_tree(), "the sign layer is drawn")
	if node == null or spec.is_empty():
		return
	var spr: Sprite2D = node.get_node("Image")
	var img := spr.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var quad := PackedVector2Array()
	for p in spec["board"]:
		quad.append(Vector2(float(p[0]), float(p[1])))
	var grown := _grow(quad, 1.5)
	var xf := spr.get_global_transform()
	var painted := 0
	var outside := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				painted += 1
				if not Geometry2D.is_point_in_polygon(xf * Vector2(x + 0.5, y + 0.5), grown):
					outside += 1
	var area := absf(_area(quad)) / (spr.global_scale.x * spr.global_scale.y)
	_check(outside == 0, "every painted pixel on the board (%d of %d outside)" % [outside, painted])
	_check(painted > area * 0.08 and painted < area * 0.6, "letters cover %.0f %% of the board" % (100.0 * painted / maxf(area, 1.0)))
	var hs: Node2D = _hotspot("post_sign")
	var c := (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
	_check(hs != null and rm.current_room.pick(c) == hs, "the board centre %s picks the sign hotspot" % str(c))
	_check(sd.text("@Z4.post_sign.look").contains("Почта"), "the look text names «Почта»")


func _z4_layers() -> Array:
	var f := FileAccess.get_file_as_string("res://data/story/rooms/Z4.json")
	var d = JSON.parse_string(f)
	return d.get("layers", []) if d is Dictionary else []


func _area(q: PackedVector2Array) -> float:
	var a := 0.0
	for i in q.size():
		a += q[i].cross(q[(i + 1) % q.size()])
	return a * 0.5


func _grow(q: PackedVector2Array, by: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(q, by)
	return res[0] if not res.is_empty() else q
