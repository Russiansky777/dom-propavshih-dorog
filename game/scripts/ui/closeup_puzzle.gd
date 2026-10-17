extends CanvasLayer
## Close-up view for `match_marks` puzzles (M05 school door). Built from the puzzle spec in the room
## JSON; all rules live in StoryRunner (puzzle_place / puzzle_set_mark / puzzle_check).
##
## Layout: door leaf on the left with the frame bar and its hinge sockets, threshold beam with
## notch positions below, reference drawing + piece tray + message on the right.

const DOOR_RECT := Rect2(320, 200, 720, 660)
const FRAME_RECT := Rect2(1070, 180, 110, 700)
const BEAM_RECT := Rect2(560, 880, 520, 40)
const DRAWING_RECT := Rect2(1400, 200, 440, 300)
const TRAY_RECT := Rect2(1400, 540, 440, 120)
const SUCCESS_CLOSE_SECONDS: float = 2.2

var root: Control
var title_label: Label
var message_label: Label
var hint_label: Label
var door_view: ColorRect        # what is seen through the open door (wall / winter)
var door_leaf: ColorRect
var snow: CPUParticles2D
var winter_label: Label
var slot_nodes: Dictionary = {}   # slot id -> Button
var piece_nodes: Dictionary = {}  # piece id -> Button
var mark_nodes: Array[Button] = []
var check_button: Button
var close_button: Button
var selected_piece: String = ""
var _tray_rect: Rect2 = TRAY_RECT


func _ready() -> void:
	layer = 6
	visible = false
	StoryRunner.puzzle_opened.connect(_open)
	StoryRunner.puzzle_closed.connect(_close)
	StoryRunner.puzzle_state_changed.connect(_render)


func _open() -> void:
	_build()
	visible = true
	_render()


func _close() -> void:
	visible = false
	if root != null:
		root.queue_free()
		root = null
	slot_nodes.clear()
	piece_nodes.clear()
	mark_nodes.clear()
	selected_piece = ""


func _label(text: String, rect: Rect2, size: int = 22, center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rect(color: Color, rect: Rect2) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Art layer: PNG mapped to the 1920x1080 base, then `offset`/`scale` (same convention as rooms).
func _art_layer(name: String, spec: Dictionary) -> TextureRect:
	var image := String(spec.get("image", ""))
	if image == "" or not ResourceLoader.exists(image):
		return null
	var tr := TextureRect.new()
	tr.name = name
	tr.texture = load(image)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sc := float(spec.get("scale", 1.0))
	var off: Array = spec.get("offset", [0, 0])
	tr.position = Vector2(float(off[0]), float(off[1]))
	tr.size = Vector2(1920.0 * sc, 1080.0 * sc)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _flat_button(center: Vector2, size: Vector2) -> Button:
	## Invisible click target over art (hover shows a faint outline).
	var b := Button.new()
	b.flat = true
	b.position = center - size / 2
	b.size = size
	b.modulate = Color(1, 1, 1, 0.25)
	return b


func _square_button(text: String, center: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = center - size / 2
	b.size = size
	b.add_theme_font_size_override("font_size", 18)
	return b


func _build() -> void:
	if root != null:
		root.queue_free()
	var spec: Dictionary = StoryRunner.puzzle.get("spec", {})
	root = Control.new()
	root.name = "Closeup"
	root.position = Vector2.ZERO
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.add_child(_rect(Color(0.05, 0.05, 0.06, 1.0), Rect2(0, 0, 1920, 1080)))
	title_label = _label(StoryData.text(String(spec.get("title", ""))), Rect2(320, 110, 1480, 60), 34, false)
	title_label.name = "Title"
	root.add_child(title_label)

	var art: Dictionary = spec.get("art", {})
	if not art.is_empty():
		_build_art(spec, art)
	else:
		_build_placeholder(spec)

	# Message, hint, buttons.
	message_label = _label("", Rect2(1400, 690, 440, 150), 22, false)
	message_label.name = "Message"
	root.add_child(message_label)
	hint_label = _label("", Rect2(1400, 850, 440, 70), 20, false)
	hint_label.name = "Hint"
	hint_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	root.add_child(hint_label)
	check_button = _square_button(StoryData.text(String(spec.get("check_label", "@ui.close"))), Vector2(1520, 970), Vector2(240, 56))
	check_button.name = "Check"
	check_button.pressed.connect(_on_check)
	root.add_child(check_button)
	close_button = _square_button(StoryData.text(String(spec.get("close_label", "@ui.close"))), Vector2(1760, 970), Vector2(160, 56))
	close_button.name = "Close"
	close_button.pressed.connect(func(): StoryRunner.close_puzzle())
	root.add_child(close_button)


func _render() -> void:
	if root == null or not visible:
		return
	var st: Dictionary = StoryRunner.puzzle
	var spec: Dictionary = st.get("spec", {})
	message_label.text = String(st.get("message", ""))
	hint_label.text = String(st.get("hint", ""))
	var placed: Dictionary = st.get("placed", {})
	# Pieces: in a socket or in the tray.
	var tray_i := 0
	for pid in piece_nodes.keys():
		var b: Button = piece_nodes[pid]
		var slot := StoryRunner.puzzle_piece_slot(pid)
		if slot != "" and slot_nodes.has(slot):
			var sb: Button = slot_nodes[slot]
			b.position = sb.position + sb.size / 2 - b.size / 2
		else:
			b.position = _tray_rect.position + Vector2(30 + tray_i * 150, 10)
			tray_i += 1
		b.button_pressed = selected_piece == pid
	var has_art: bool = not (spec.get("art", {}) as Dictionary).is_empty()
	for sid in slot_nodes.keys():
		var sb: Button = slot_nodes[sid]
		sb.text = "" if (placed.has(sid) or has_art) else "-"
	var mark := int(st.get("mark", -1))
	for i in mark_nodes.size():
		mark_nodes[i].text = "X" if i == mark else ""
		if has_art:
			mark_nodes[i].modulate = Color(1, 0.9, 0.5, 1.0) if i == mark else Color(1, 1, 1, 0.25)
	# Doorway preview.
	var view := String(st.get("view", ""))
	var solved := bool(st.get("solved", false))
	if door_leaf != null:
		door_leaf.visible = view == ""
	if view == "winter":
		door_view.color = Color(0.62, 0.72, 0.86)
		winter_label.text = StoryData.location_name("O1")
		snow.emitting = true
	elif view == "wall":
		door_view.color = Color(0.36, 0.30, 0.25)
		winter_label.text = ""
		snow.emitting = false
	check_button.disabled = solved
	if solved:
		_auto_close()


func _auto_close() -> void:
	await get_tree().create_timer(SUCCESS_CLOSE_SECONDS).timeout
	if StoryRunner.puzzle_open and bool(StoryRunner.puzzle.get("solved", false)):
		StoryRunner.close_puzzle()


func _on_piece_pressed(pid: String) -> void:
	if StoryRunner.puzzle_piece_slot(pid) != "":
		StoryRunner.puzzle_place(pid, "")  # back to the tray
		selected_piece = ""
	else:
		selected_piece = "" if selected_piece == pid else pid
	_render()


func _on_slot_pressed(slot_id: String) -> void:
	if selected_piece == "":
		# Clicking an occupied socket returns its piece to the tray.
		var placed: Dictionary = StoryRunner.puzzle.get("placed", {})
		if placed.has(slot_id):
			StoryRunner.puzzle_place(String(placed[slot_id]), "")
		return
	var placed: Dictionary = StoryRunner.puzzle.get("placed", {})
	if placed.has(slot_id):
		return
	StoryRunner.puzzle_place(selected_piece, slot_id)
	selected_piece = ""
	_render()


func _on_mark_pressed(index: int) -> void:
	StoryRunner.puzzle_set_mark(index)


func _on_check() -> void:
	StoryRunner.puzzle_check()


func probe_positions() -> Dictionary:
	var out := {"open": visible and root != null, "pieces": {}, "slots": {}, "marks": [], "check": {}, "close": {},
		"solved": bool(StoryRunner.puzzle.get("solved", false)), "view": String(StoryRunner.puzzle.get("view", "")),
		"errors": int(StoryRunner.puzzle.get("errors", 0)), "hint": String(StoryRunner.puzzle.get("hint", ""))}
	if root == null or not visible:
		return out
	for pid in piece_nodes.keys():
		out["pieces"][pid] = _center(piece_nodes[pid])
	for sid in slot_nodes.keys():
		out["slots"][sid] = _center(slot_nodes[sid])
	for b in mark_nodes:
		out["marks"].append(_center(b))
	out["check"] = _center(check_button)
	out["close"] = _center(close_button)
	return out


func _center(c: Control) -> Dictionary:
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}


func _build_placeholder(spec: Dictionary) -> void:
	# Doorway: what is behind the leaf (wall by default).
	door_view = _rect(Color(0.36, 0.30, 0.25), DOOR_RECT)
	door_view.name = "DoorView"
	root.add_child(door_view)
	winter_label = _label("", Rect2(DOOR_RECT.position + Vector2(20, 20), Vector2(DOOR_RECT.size.x - 40, 60)), 26)
	winter_label.name = "WinterLabel"
	root.add_child(winter_label)
	snow = CPUParticles2D.new()
	snow.name = "Snow"
	snow.emitting = false
	snow.amount = 160
	snow.lifetime = 4.0
	snow.position = Vector2(DOOR_RECT.position.x + DOOR_RECT.size.x / 2, DOOR_RECT.position.y)
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(DOOR_RECT.size.x / 2, 4)
	snow.direction = Vector2(0, 1)
	snow.spread = 12.0
	snow.gravity = Vector2(0, 40)
	snow.initial_velocity_min = 80.0
	snow.initial_velocity_max = 140.0
	snow.scale_amount_min = 2.0
	snow.scale_amount_max = 4.0
	snow.color = Color(1, 1, 1, 0.9)
	root.add_child(snow)
	# Door leaf (covers the doorway until the door is opened by success/error preview).
	door_leaf = _rect(Color(0.48, 0.34, 0.20), DOOR_RECT)
	door_leaf.name = "DoorLeaf"
	root.add_child(door_leaf)
	var leaf_label := _label(StoryData.text("@H3.school_door.label"), Rect2(Vector2(0, DOOR_RECT.size.y / 2 - 20), Vector2(DOOR_RECT.size.x, 40)), 24)
	door_leaf.add_child(leaf_label)

	# Frame bar with sockets.
	root.add_child(_rect(Color(0.30, 0.22, 0.14), FRAME_RECT))
	for s in spec.get("slots", []):
		var pos: Array = s.get("pos", [1120, 500])
		var b := _square_button("", Vector2(float(pos[0]), float(pos[1])), Vector2(90, 90))
		b.name = "Slot_" + String(s["id"])
		b.tooltip_text = StoryData.text(String(s.get("label", "")))
		b.pressed.connect(_on_slot_pressed.bind(String(s["id"])))
		root.add_child(b)
		slot_nodes[String(s["id"])] = b
		root.add_child(_label(StoryData.text(String(s.get("label", ""))), Rect2(float(pos[0]) + 56, float(pos[1]) - 12, 200, 30), 16, false))

	# Threshold beam with notch positions.
	root.add_child(_rect(Color(0.42, 0.30, 0.18), BEAM_RECT))
	var marks: Dictionary = spec.get("marks", {})
	root.add_child(_label(StoryData.text(String(marks.get("label", ""))), Rect2(BEAM_RECT.position.x - 240, BEAM_RECT.position.y + 4, 220, 32), 20))
	mark_nodes.clear()
	var positions: Array = marks.get("positions", [])
	for i in positions.size():
		var p: Array = positions[i]
		var b := _square_button("", Vector2(float(p[0]), float(p[1])), Vector2(50, 50))
		b.name = "Mark_%d" % i
		b.pressed.connect(_on_mark_pressed.bind(i))
		root.add_child(b)
		mark_nodes.append(b)

	# Reference drawing: beam with notch at the correct index, hinge marks at the correct slots.
	root.add_child(_rect(Color(0.90, 0.86, 0.74), DRAWING_RECT))
	root.add_child(_label(StoryData.text(String(marks.get("drawing_label", ""))), Rect2(DRAWING_RECT.position + Vector2(0, 8), Vector2(DRAWING_RECT.size.x, 30)), 20))
	var dbeam := Rect2(DRAWING_RECT.position.x + 60, DRAWING_RECT.position.y + 240, DRAWING_RECT.size.x - 120, 20)
	root.add_child(_rect(Color(0.35, 0.25, 0.15), dbeam))
	var correct_mark := int(marks.get("correct", 0))
	if positions.size() > 0:
		var t := (float(correct_mark) + 0.5) / float(positions.size())
		root.add_child(_rect(Color(0.1, 0.1, 0.1), Rect2(dbeam.position.x + dbeam.size.x * t - 6, dbeam.position.y - 16, 12, 36)))
	var dframe := Rect2(DRAWING_RECT.position.x + DRAWING_RECT.size.x - 70, DRAWING_RECT.position.y + 50, 24, 180)
	root.add_child(_rect(Color(0.35, 0.25, 0.15), dframe))
	var slots: Array = spec.get("slots", [])
	for i in slots.size():
		if bool(slots[i].get("correct", false)):
			var ty := dframe.position.y + dframe.size.y * (float(i) + 0.5) / float(slots.size())
			root.add_child(_rect(Color(0.1, 0.1, 0.1), Rect2(dframe.position.x - 10, ty - 8, 44, 16)))

	# Piece tray.
	root.add_child(_rect(Color(0.15, 0.14, 0.12), TRAY_RECT))
	var pieces: Array = spec.get("pieces", [])
	for i in pieces.size():
		var pid := String(pieces[i]["id"])
		var b := _square_button(StoryData.text(String(pieces[i].get("label", ""))), Vector2.ZERO, Vector2(110, 60))
		b.name = "Piece_" + pid
		b.toggle_mode = true
		b.pressed.connect(_on_piece_pressed.bind(pid))
		root.add_child(b)
		piece_nodes[pid] = b


## Real art: frame with sockets, door leaf over the opening, beam with notches, reference drawing,
## hinge pieces in a tray. Positions come from the data (slots.pos / marks.positions in closeup coords).
func _build_art(spec: Dictionary, art: Dictionary) -> void:
	var o: Array = art.get("opening", [560, 81, 325, 736])
	var opening := Rect2(float(o[0]), float(o[1]), float(o[2]), float(o[3]))
	door_view = _rect(Color(0.36, 0.30, 0.25), opening)
	door_view.name = "DoorView"
	root.add_child(door_view)
	winter_label = _label("", Rect2(opening.position + Vector2(10, 14), Vector2(opening.size.x - 20, 50)), 24)
	winter_label.name = "WinterLabel"
	root.add_child(winter_label)
	snow = CPUParticles2D.new()
	snow.name = "Snow"
	snow.emitting = false
	snow.amount = 120
	snow.lifetime = 4.0
	snow.position = Vector2(opening.position.x + opening.size.x / 2, opening.position.y)
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(opening.size.x / 2, 4)
	snow.direction = Vector2(0, 1)
	snow.spread = 12.0
	snow.gravity = Vector2(0, 40)
	snow.initial_velocity_min = 70.0
	snow.initial_velocity_max = 130.0
	snow.scale_amount_min = 2.0
	snow.scale_amount_max = 4.0
	snow.color = Color(1, 1, 1, 0.9)
	root.add_child(snow)
	var leaf := _art_layer("DoorLeafImage", art.get("door_leaf", {}))
	door_leaf = _rect(Color(0, 0, 0, 0), opening)  # transparent anchor; visibility toggles the leaf image
	door_leaf.name = "DoorLeaf"
	root.add_child(door_leaf)
	if leaf != null:
		door_leaf.add_child(leaf)
		leaf.position -= opening.position
	var frame := _art_layer("FrameImage", art.get("frame", {}))
	if frame != null:
		root.add_child(frame)
	for sl in spec.get("slots", []):
		var pos: Array = sl.get("pos", [900, 400])
		var b := _flat_button(Vector2(float(pos[0]), float(pos[1])), Vector2(80, 80))
		b.name = "Slot_" + String(sl["id"])
		b.tooltip_text = StoryData.text(String(sl.get("label", "")))
		b.pressed.connect(_on_slot_pressed.bind(String(sl["id"])))
		root.add_child(b)
		slot_nodes[String(sl["id"])] = b
	var beam := _art_layer("BeamImage", art.get("beam", {}))
	if beam != null:
		root.add_child(beam)
	var marks: Dictionary = spec.get("marks", {})
	var positions: Array = marks.get("positions", [])
	mark_nodes.clear()
	for i in positions.size():
		var p: Array = positions[i]
		var b := _flat_button(Vector2(float(p[0]), float(p[1])), Vector2(70, 70))
		b.name = "Mark_%d" % i
		b.pressed.connect(_on_mark_pressed.bind(i))
		root.add_child(b)
		mark_nodes.append(b)
	root.add_child(_label(StoryData.text(String(marks.get("label", ""))), Rect2(330, 870, 200, 60), 20))
	var drawing := _art_layer("DrawingImage", art.get("drawing", {}))
	if drawing != null:
		root.add_child(drawing)
		root.add_child(_label(StoryData.text(String(marks.get("drawing_label", ""))), Rect2(drawing.position.x, drawing.position.y + drawing.size.y + 4, drawing.size.x, 30), 18))
	var t: Array = art.get("tray", [1400, 500, 440, 150])
	var tray := Rect2(float(t[0]), float(t[1]), float(t[2]), float(t[3]))
	root.add_child(_rect(Color(0.15, 0.14, 0.12, 0.8), tray))
	var hinge_spec: Dictionary = art.get("hinge", {})
	var hinge_tex: Texture2D = load(String(hinge_spec.get("image", ""))) if ResourceLoader.exists(String(hinge_spec.get("image", ""))) else null
	var hsc := float(hinge_spec.get("scale", 0.22))
	for i in spec.get("pieces", []).size():
		var pid := String(spec["pieces"][i]["id"])
		var b := _flat_button(Vector2.ZERO, Vector2(110, 130))
		b.name = "Piece_" + pid
		b.toggle_mode = true
		b.pressed.connect(_on_piece_pressed.bind(pid))
		if hinge_tex != null:
			var img := TextureRect.new()
			img.name = "Image"
			img.texture = hinge_tex
			img.stretch_mode = TextureRect.STRETCH_SCALE
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			# The hinge PNG is a full canvas; show only its drawn part (bbox) scaled to ~130 px tall.
			var ts: Vector2 = hinge_tex.get_size()
			img.size = Vector2(1920.0 * hsc, 1080.0 * hsc)
			var bb: Array = hinge_spec.get("bbox", [991, 282, 369, 537])  # 1920-space bbox of the drawn hinge
			img.position = Vector2(-float(bb[0]) * hsc + (110 - float(bb[2]) * hsc) / 2, -float(bb[1]) * hsc + (130 - float(bb[3]) * hsc) / 2)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			img.clip_contents = false
			b.add_child(img)
			b.modulate = Color(1, 1, 1, 1)
		root.add_child(b)
		piece_nodes[pid] = b
	_tray_rect = tray
