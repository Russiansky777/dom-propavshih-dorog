extends CanvasLayer
## Close-up for `match_marks` puzzles (M05 school door). Everything is done with the mouse
## (Director 18.10: «в квесте с дверью всё должно делаться мышью — и петли и зарубка»):
##   - hinges: drag one from the tray onto a socket of the frame. While a hinge is held the free
##     sockets show a faint ring, the one it would land in glows; released within `drag.snap_px` of a
##     free socket it snaps in, otherwise it slides back to the tray. A placed hinge is dragged off (to
##     another free socket or anywhere = back to the tray) or simply clicked back into the tray. A click
##     on a tray hinge takes it in hand (it follows the pointer), the next click places it by the same
##     rule; right click puts it back;
##   - threshold: the beam slides left/right under the door — drag it, or click a notch to bring that
##     notch under the door's mark (`marks.anchor`); a notch released within `marks.snap_px` of the mark
##     snaps under it and is the chosen one (StoryRunner.puzzle_set_mark), else none is;
##   - the door: a click on its handle closes it (the check; the «Закрыть дверь» button does the same).
##     Wrong — the leaf swings away and the gallery wall is behind it for a moment, then the leaf is back
##     to work on; right — winter behind it: with `art.winter_view` (Director 23.10, F18: «там просто синий
##     прямоугольник со снегом») the winter classroom itself — a crop of its painting (`image`, `region` in
##     the picture's pixels, fitted to the opening; `modulate` — cold daylight), cold light spilling over the
##     threshold (`light` {color, alpha, depth, spread}), snow drifting out through the doorway (`snow`
##     {amount}) and a faint breath of cold at the threshold (`breath` {amount, alpha}); without it the old
##     flat colour and caption;
##   - cursor: open hand over a hinge or the beam, closed hand while one is held / the beam is pulled,
##     pointing hand on the handle (not the ↔ shapes: ExitCursors draws the exit arrows on those); sounds of sfx.json by puzzle `sounds` (take / snap / return / beam / close_*).
##   - seating the notch (Director 24.10, H18: «для зарубки — подумать, как сделать установку игрой»; data
##     `marks.seat`): the beam dragged near a notch (within `marks.snap_px`) is not chosen yet — it must be knocked
##     exactly under the door's mark: a click on an end of the beam (`seat.end_frac` of its length) knocks it
##     `seat.tap_px` toward the other end; within `seat.tol_px` it sits in the notch (that notch is chosen). The
##     guide line is amber while near, the knock arrows at the beam's ends show which end to strike;
##     a click in the middle of the beam only shows the hint. Without `seat` — the old snap and click-to-align.
## Rules stay in StoryRunner (puzzle_place / puzzle_set_mark / puzzle_check). Positions, snap distances
## and the number of hinges are rooms data (puzzle.art / drag / slots / pieces / marks) — no if-branches.

const SUCCESS_CLOSE_SECONDS: float = 2.2
const MAX_VOICE_WAIT_S: float = 15.0   # the success voice-over holds the close-up at most this long
const WALL_PEEK_S: float = 1.6         # after a wrong «close»: the wall behind the open leaf, then back
const GLOW := Color(1.0, 0.86, 0.5)

var root: Control
var title_label: Label
var message_label: Label
var hint_label: Label
var door_view: ColorRect        # what is seen through the open door (wall / winter)
var door_leaf: Control
var snow: CPUParticles2D
var winter_label: Label
var winter_view: TextureRect = null   # the classroom through the open door (F18)
var winter_front: Node2D = null       # cold light on the threshold, snow drifting out, breath of cold (F18)
var check_button: Button
var close_button: Button
var beam_node: Control           # beam image + notch markers; moves by `_beam_shown_dx`
var handle_glow: Panel
var tray_node: Panel              # hinge tray: framed, captioned, dims when empty (Director 18.10: looked like a placeholder)
var handle_label: Label
var guide_line: ColorRect        # door mark ↔ aligned notch
var piece_nodes: Dictionary = {}   # piece id -> Control (hinge picture)
var slot_glows: Dictionary = {}    # slot id -> Panel
var notch_marks: Array[ColorRect] = []
## Kept for older probes/tests: slot id -> centre (Vector2).
var slot_centers: Dictionary = {}

var spec: Dictionary = {}
var piece_size: Vector2 = Vector2(100, 130)
var tray_rect: Rect2 = Rect2(1400, 500, 440, 150)
var handle_rect: Rect2 = Rect2()
var beam_hit_base: Rect2 = Rect2()
var notch_base: Array[Vector2] = []
var anchor: Vector2 = Vector2.ZERO
var snap_px: float = 60.0
var click_px: float = 6.0
var return_s: float = 0.25
var mark_snap_px: float = 40.0
var seat: Dictionary = {}          # H18: knocking the notch exactly under the mark (marks.seat); empty — old snap
var seat_tol_px: float = 4.0
var seat_tap_px: float = 8.0
var seat_end_frac: float = 0.18
var seat_taps: int = 0             # knocks given (tests)
var seat_arrows: Array[Label] = [] # ▶ at the left end, ◀ at the right end: where to strike
var seat_hint: Label = null
var _seat_hint_t: float = -100.0
var shift_range: Vector2 = Vector2(-400, 400)

var _beam_dx: float = 0.0          # where the beam rests (aligned notch or where it was left)
var _beam_shown_dx: float = 0.0    # where it is drawn (drag / tween)
var _beam_tween: Tween = null
var _drag: Dictionary = {}         # {kind: "piece"|"beam", pid, from_slot, press, offset, moved, start_dx}
var _carry: String = ""            # piece in hand after a click (follows the pointer)
var _carry_offset: Vector2 = Vector2.ZERO
var _target_slot: String = ""
var _piece_tweens: Dictionary = {} # pid -> Tween
var _peeking: bool = false         # the wall behind the opened leaf, for WALL_PEEK_S of game time
var _peek_serial: int = 0
var _last_errors: int = 0
var _hover_handle: bool = false
var _pulse_t: float = 0.0
var selected_piece: String = ""    # = _carry (older name, kept for probes)


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
	piece_nodes.clear()
	slot_glows.clear()
	notch_marks.clear()
	slot_centers.clear()
	_drag = {}
	_carry = ""
	selected_piece = ""
	_target_slot = ""
	_piece_tweens.clear()
	_beam_tween = null


# --- Building ------------------------------------------------------------------------------

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


func _ring(rect: Rect2, radius: int = 10, width: int = 3) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.10)
	sb.border_color = GLOW
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.35)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _r(a, fallback: Rect2) -> Rect2:
	if a is Array and a.size() == 4:
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return fallback


static func _v(a, fallback: Vector2) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback


## Art layer: PNG mapped to the 1920x1080 base, then `offset`/`scale` (same convention as rooms).
func _art_layer(name: String, layer_spec: Dictionary) -> TextureRect:
	var image := String(layer_spec.get("image", ""))
	if image == "" or not ResourceLoader.exists(image):
		return null
	var tr := TextureRect.new()
	tr.name = name
	tr.texture = load(image)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sc := float(layer_spec.get("scale", 1.0))
	var off: Array = layer_spec.get("offset", [0, 0])
	tr.position = Vector2(float(off[0]), float(off[1]))
	tr.size = Vector2(1920.0 * sc, 1080.0 * sc)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _square_button(text: String, center: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = center - size / 2
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build() -> void:
	if root != null:
		root.queue_free()
	piece_nodes.clear()
	slot_glows.clear()
	notch_marks.clear()
	slot_centers.clear()
	_drag = {}
	_carry = ""
	_target_slot = ""
	spec = StoryRunner.puzzle.get("spec", {})
	var art: Dictionary = spec.get("art", {})
	var drag: Dictionary = spec.get("drag", {})
	var marks: Dictionary = spec.get("marks", {})
	snap_px = float(drag.get("snap_px", 60.0))
	click_px = float(drag.get("click_px", 6.0))
	return_s = float(drag.get("return_s", 0.25))
	mark_snap_px = float(marks.get("snap_px", 40.0))
	seat = marks.get("seat", {}) if marks.get("seat", {}) is Dictionary else {}
	seat_tol_px = float(seat.get("tol_px", seat_tol_px))
	seat_tap_px = float(seat.get("tap_px", seat_tap_px))
	seat_end_frac = float(seat.get("end_frac", seat_end_frac))
	piece_size = _v(art.get("hinge", {}).get("size", null), Vector2(100, 130))
	tray_rect = _r(art.get("tray", null), Rect2(1400, 500, 440, 150))
	handle_rect = _r(art.get("handle", null), Rect2())
	beam_hit_base = _r(art.get("beam", {}).get("hit", null), Rect2(560, 870, 520, 70))
	anchor = _v(marks.get("anchor", null), Vector2(beam_hit_base.get_center().x, beam_hit_base.position.y))
	notch_base.clear()
	for p in marks.get("positions", []):
		notch_base.append(_v(p, Vector2.ZERO))
	shift_range = _v(marks.get("shift_range", null), Vector2(-400, 400))
	_beam_dx = float(marks.get("start_shift", 0.0))
	_beam_shown_dx = _beam_dx
	_last_errors = int(StoryRunner.puzzle.get("errors", 0))
	_peeking = false

	root = Control.new()
	root.name = "Closeup"
	root.position = Vector2.ZERO
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.add_child(_rect(Color(0.05, 0.05, 0.06, 1.0), Rect2(0, 0, 1920, 1080)))
	title_label = _label(StoryData.text(String(spec.get("title", ""))), Rect2(40, 20, 470, 120), 30, false)
	title_label.name = "Title"
	root.add_child(title_label)

	# Doorway (what is behind the leaf), the leaf, the frame.
	var opening := _r(art.get("opening", null), Rect2(560, 81, 325, 736))
	door_view = _rect(Color(0.36, 0.30, 0.25), opening)
	door_view.name = "DoorView"
	root.add_child(door_view)
	winter_label = _label("", Rect2(opening.position + Vector2(10, 14), Vector2(opening.size.x - 20, 50)), 24)
	winter_label.name = "WinterLabel"
	root.add_child(winter_label)
	var wv: Dictionary = art.get("winter_view", {})
	if not wv.is_empty():
		winter_view = _winter_picture(wv, opening)
		if winter_view != null:
			root.add_child(winter_view)
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
	door_leaf = Control.new()   # anchor for the leaf picture; hidden while the door stands open
	door_leaf.name = "DoorLeaf"
	door_leaf.position = opening.position
	door_leaf.size = opening.size
	door_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(door_leaf)
	var leaf := _art_layer("DoorLeafImage", art.get("door_leaf", {}))
	if leaf != null:
		leaf.position -= opening.position
		door_leaf.add_child(leaf)
	else:
		var lr := _rect(Color(0.48, 0.34, 0.20), Rect2(Vector2.ZERO, opening.size))
		door_leaf.add_child(lr)
	var frame := _art_layer("FrameImage", art.get("frame", {}))
	if frame != null:
		root.add_child(frame)

	# Handle: glow + caption on hover (the click closes the door).
	if handle_rect.size != Vector2.ZERO:
		handle_glow = _ring(handle_rect.grow(4), 24, 2)
		handle_glow.name = "HandleGlow"
		handle_glow.visible = false
		root.add_child(handle_glow)
		handle_label = _label(StoryData.text(String(spec.get("check_label", "@ui.close"))),
			Rect2(handle_rect.position + Vector2(-60, handle_rect.size.y + 6), Vector2(handle_rect.size.x + 120, 34)), 20)
		handle_label.name = "HandleLabel"
		handle_label.visible = false
		root.add_child(handle_label)

	# Sockets: rings shown while a hinge is held (target glows).
	for sl in spec.get("slots", []):
		var sid := String(sl["id"])
		var c := _v(sl.get("pos", null), Vector2(918, 400))
		slot_centers[sid] = c
		var g := _ring(Rect2(c - (piece_size + Vector2(10, 10)) / 2, piece_size + Vector2(10, 10)))
		g.name = "Slot_" + sid
		g.tooltip_text = StoryData.text(String(sl.get("label", "")))
		g.visible = false
		root.add_child(g)
		slot_glows[sid] = g

	# Threshold beam (moves horizontally) with notch markers and the guide line to the door's mark.
	beam_node = Control.new()
	beam_node.name = "Beam"
	beam_node.position = Vector2(_beam_shown_dx, 0)
	beam_node.size = Vector2(1920, 1080)
	beam_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(beam_node)
	var beam := _art_layer("BeamImage", art.get("beam", {}))
	if beam != null:
		beam_node.add_child(beam)
	else:
		beam_node.add_child(_rect(Color(0.42, 0.30, 0.18), beam_hit_base))
	for i in notch_base.size():
		var m := _rect(Color(GLOW.r, GLOW.g, GLOW.b, 0.0), Rect2(notch_base[i] + Vector2(-5, -4), Vector2(10, 26)))
		m.name = "Mark_%d" % i
		beam_node.add_child(m)
		notch_marks.append(m)
	guide_line = _rect(Color(GLOW.r, GLOW.g, GLOW.b, 0.85), Rect2(anchor.x - 1.5, anchor.y, 3, 30))
	guide_line.name = "Guide"
	guide_line.visible = false
	root.add_child(guide_line)
	root.add_child(_label(StoryData.text(String(marks.get("label", ""))), Rect2(330, 960, 260, 40), 20, false))
	seat_arrows.clear()
	if not seat.is_empty():
		for k in 2:
			var a := _label("▶" if k == 0 else "◀", Rect2(0, 0, 40, 40), 30)
			a.name = "Knock%s" % ("Left" if k == 0 else "Right")
			a.add_theme_color_override("font_color", GLOW)
			a.visible = false
			root.add_child(a)
			seat_arrows.append(a)
		seat_hint = _label(StoryData.text(String(seat.get("label", ""))), Rect2(330, 1000, 1000, 40), 20, false)
		seat_hint.name = "SeatHint"
		seat_hint.visible = false
		root.add_child(seat_hint)

	# Reference drawing and its caption; piece tray.
	var drawing := _art_layer("DrawingImage", art.get("drawing", {}))
	if drawing != null:
		root.add_child(drawing)
	var cap_rect := _r(art.get("drawing_caption", null), Rect2(1400, 456, 345, 30))
	root.add_child(_label(StoryData.text(String(marks.get("drawing_label", ""))), cap_rect, 18))
	tray_node = Panel.new()
	tray_node.name = "Tray"
	tray_node.position = tray_rect.position
	tray_node.size = tray_rect.size
	tray_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.12, 0.10, 0.08, 0.85)
	tsb.border_color = Color(0.55, 0.42, 0.25, 0.9)
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(8)
	tray_node.add_theme_stylebox_override("panel", tsb)
	root.add_child(tray_node)
	var tray_cap := String(marks.get("tray_label", ""))
	if tray_cap != "":
		root.add_child(_label(StoryData.text(tray_cap), Rect2(tray_rect.position + Vector2(0, tray_rect.size.y + 4), Vector2(tray_rect.size.x, 26)), 18))
	var hinge_spec: Dictionary = art.get("hinge", {})
	var hinge_path := String(hinge_spec.get("image", ""))
	var hinge_tex: Texture2D = load(hinge_path) if hinge_path != "" and ResourceLoader.exists(hinge_path) else null
	var hsc := float(hinge_spec.get("scale", 0.22))
	var bb: Array = hinge_spec.get("bbox", [991, 282, 369, 537])  # 1920-space bbox of the drawn hinge
	# A pale place for every hinge inside the tray (children of the tray: they dim with it): when all
	# hinges are in the frame the tray shows three faint outlines — «they were here», not an empty box.
	for pc in spec.get("pieces", []):
		var ppid := String(pc["id"])
		var hs := Vector2(float(bb[2]) * hsc, float(bb[3]) * hsc) + Vector2(12, 12)
		var place := Panel.new()
		place.name = "Place_" + ppid
		place.size = hs
		place.position = _tray_center(ppid) - tray_rect.position - hs / 2
		place.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0, 0, 0, 0.28)
		psb.border_color = Color(0.55, 0.42, 0.25, 0.45)
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(6)
		place.add_theme_stylebox_override("panel", psb)
		if hinge_tex != null:
			var ghost := TextureRect.new()
			ghost.name = "Outline"
			ghost.texture = hinge_tex
			ghost.stretch_mode = TextureRect.STRETCH_SCALE
			ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ghost.size = Vector2(1920.0 * hsc, 1080.0 * hsc)
			ghost.position = Vector2(-float(bb[0]) * hsc + 6, -float(bb[1]) * hsc + 6)
			ghost.modulate = Color(0.94, 0.89, 0.79, 0.16)
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			place.add_child(ghost)
		tray_node.add_child(place)
	for pc in spec.get("pieces", []):
		var pid := String(pc["id"])
		var b := Control.new()
		b.name = "Piece_" + pid
		b.size = piece_size
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.tooltip_text = StoryData.text(String(pc.get("label", "")))
		if hinge_tex != null:
			var img := TextureRect.new()
			img.name = "Image"
			img.texture = hinge_tex
			img.stretch_mode = TextureRect.STRETCH_SCALE
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.size = Vector2(1920.0 * hsc, 1080.0 * hsc)
			img.position = Vector2(-float(bb[0]) * hsc + (piece_size.x - float(bb[2]) * hsc) / 2,
				-float(bb[1]) * hsc + (piece_size.y - float(bb[3]) * hsc) / 2)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(img)
		else:
			b.add_child(_rect(Color(0.25, 0.22, 0.2), Rect2(Vector2(20, 10), piece_size - Vector2(40, 20))))
		root.add_child(b)
		piece_nodes[pid] = b
		b.position = _tray_center(pid) - piece_size / 2

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
	# Game typefaces for the text and the two buttons (UiTheme).
	var t := UiTheme.get_theme()
	for l in [[title_label, &"CloseupTitle"], [message_label, &"CloseupLabel"], [hint_label, &"CloseupLabel"]]:
		(l[0] as Label).theme = t
		(l[0] as Label).theme_type_variation = l[1]
		(l[0] as Label).remove_theme_font_size_override("font_size")
	for b in [check_button, close_button]:
		b.theme = t
	if not wv.is_empty():
		winter_front = _winter_front(wv, opening)
		root.add_child(winter_front)


## The winter classroom in the opening: a region of the classroom painting scaled into the doorway.
func _winter_picture(wv: Dictionary, opening: Rect2) -> TextureRect:
	var path := String(wv.get("image", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("CloseupPuzzle: winter view image missing: %s" % path)
		return null
	var at := AtlasTexture.new()
	at.atlas = load(path)
	var r: Array = wv.get("region", [0, 0, 400, 900])
	at.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var tr := TextureRect.new()
	tr.name = "WinterView"
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = opening.position
	tr.size = opening.size
	tr.modulate = Color.html(String(wv.get("modulate", "#ffffff")))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.visible = false
	return tr


## Over the frame and the threshold: cold light spilling out of the doorway, flakes drifting out toward the
## gallery (growing as they come closer, fading), a few slow puffs of cold air at the threshold. Additive.
func _winter_front(wv: Dictionary, opening: Rect2) -> Node2D:
	var front := Node2D.new()
	front.name = "WinterFront"
	front.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var lt: Dictionary = wv.get("light", {})
	var lc := Color.html(String(lt.get("color", "#cfe0ff")))
	var la := float(lt.get("alpha", 0.3))
	var depth := float(lt.get("depth", 240.0))
	var spread := float(lt.get("spread", 1.8))
	var x0 := opening.position.x
	var x1 := opening.end.x
	var y0 := opening.end.y - 4.0
	var cx := (x0 + x1) * 0.5
	var hw := (x1 - x0) * 0.5 * spread
	var spill := Polygon2D.new()
	spill.name = "Light"
	# H20 (Director 24.10: «свет из двери — резкие границы»): the spill is a soft mask of the trapezoid (LightMask —
	# feathered sides, fading with depth), cut only at the threshold line itself, where the floor begins.
	var trap := [[x0 + 6.0, y0 - 30.0], [x1 - 6.0, y0 - 30.0], [cx + hw, y0 + depth], [cx - hw, y0 + depth]]
	var m := LightMask.build([trap], maxf(depth * 0.28, 24.0),
		{"from": [cx, y0], "to": [cx, y0 + depth * 1.1], "alpha_from": 1.0, "alpha_to": 0.0})
	var mr: Rect2 = m["rect"]
	var mt: Texture2D = m["texture"]
	var mts := Vector2(mt.get_width(), mt.get_height())
	var quad := PackedVector2Array([Vector2(mr.position.x, y0), Vector2(mr.end.x, y0), mr.end, Vector2(mr.position.x, mr.end.y)])
	var uvs := PackedVector2Array()
	for q in quad:
		uvs.append((q - mr.position) / mr.size * mts)
	spill.polygon = quad
	spill.uv = uvs
	spill.texture = mt
	spill.color = Color(lc, la)
	spill.material = add
	front.add_child(spill)
	# A soft glow just inside the doorway (daylight of the classroom on the jambs).
	var g := Gradient.new()
	g.set_color(0, Color(lc, la * 0.55))
	g.set_color(1, Color(lc, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = gt
	glow.position = opening.get_center()
	glow.scale = Vector2(opening.size.x * 1.7, opening.size.y * 1.15) / 64.0
	glow.material = add
	front.add_child(glow)
	var sn: Dictionary = wv.get("snow", {})
	var flakes := CPUParticles2D.new()
	flakes.name = "SnowOut"
	flakes.amount = int(sn.get("amount", 60))
	flakes.lifetime = 5.0
	flakes.preprocess = 4.0
	flakes.position = Vector2(cx, opening.position.y + opening.size.y * 0.25)
	flakes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flakes.emission_rect_extents = Vector2(opening.size.x * 0.42, opening.size.y * 0.25)
	flakes.direction = Vector2(0.0, 1.0)
	flakes.spread = 55.0
	flakes.gravity = Vector2(0, 26)
	flakes.initial_velocity_min = 18.0
	flakes.initial_velocity_max = 55.0
	flakes.scale_amount_min = 1.6
	flakes.scale_amount_max = 3.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.6))
	flakes.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 0.9))
	fade.add_point(0.75, Color(1, 1, 1, 0.75))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	flakes.color_ramp = fade
	front.add_child(flakes)
	var br: Dictionary = wv.get("breath", {})
	if int(br.get("amount", 0)) > 0:
		var bg := Gradient.new()
		bg.set_color(0, Color(0.9, 0.95, 1.0, 1.0))
		bg.set_color(1, Color(0.9, 0.95, 1.0, 0.0))
		var bt := GradientTexture2D.new()
		bt.gradient = bg
		bt.fill = GradientTexture2D.FILL_RADIAL
		bt.fill_from = Vector2(0.5, 0.5)
		bt.fill_to = Vector2(1.0, 0.5)
		bt.width = 64
		bt.height = 64
		var puff := CPUParticles2D.new()
		puff.name = "Breath"
		puff.texture = bt
		puff.amount = int(br.get("amount", 6))
		puff.lifetime = 5.0
		puff.preprocess = 5.0
		puff.position = Vector2(cx, y0 - 30.0)
		puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		puff.emission_rect_extents = Vector2(opening.size.x * 0.4, 14)
		puff.direction = Vector2(0, 1)
		puff.spread = 80.0
		puff.gravity = Vector2(0, -4)
		puff.initial_velocity_min = 8.0
		puff.initial_velocity_max = 22.0
		puff.scale_amount_min = 2.4
		puff.scale_amount_max = 4.2
		var pg := Curve.new()
		pg.add_point(Vector2(0.0, 0.5))
		pg.add_point(Vector2(1.0, 1.4))
		puff.scale_amount_curve = pg
		var pr := Gradient.new()
		var pa := float(br.get("alpha", 0.08))
		pr.set_color(0, Color(1, 1, 1, 0.0))
		pr.add_point(0.3, Color(1, 1, 1, pa))
		pr.set_color(pr.get_point_count() - 1, Color(1, 1, 1, 0.0))
		puff.color_ramp = pr
		puff.material = add
		front.add_child(puff)
	return front


# --- Geometry -------------------------------------------------------------------------------

func _tray_center(pid: String) -> Vector2:
	var ids: Array = []
	for pc in spec.get("pieces", []):
		ids.append(String(pc["id"]))
	var i := maxi(ids.find(pid), 0)
	var n := maxi(ids.size(), 1)
	var step := tray_rect.size.x / float(n)
	return Vector2(tray_rect.position.x + step * (i + 0.5), tray_rect.position.y + tray_rect.size.y / 2)


func _piece_center(pid: String) -> Vector2:
	var b: Control = piece_nodes.get(pid)
	return b.position + b.size / 2 if b != null else Vector2.ZERO


func _set_piece_center(pid: String, c: Vector2) -> void:
	var b: Control = piece_nodes.get(pid)
	if b != null:
		b.position = c - b.size / 2


func _rest_center(pid: String) -> Vector2:
	var slot := StoryRunner.puzzle_piece_slot(pid)
	return slot_centers[slot] if slot != "" and slot_centers.has(slot) else _tray_center(pid)


func _piece_at(pos: Vector2) -> String:
	# Topmost first (later children are drawn above).
	var best := ""
	var best_idx := -1
	for pid in piece_nodes.keys():
		var b: Control = piece_nodes[pid]
		if Rect2(b.position, b.size).grow(4).has_point(pos) and b.get_index() > best_idx:
			best = pid
			best_idx = b.get_index()
	return best


## Free socket (or the piece's own) nearest to `c` within snap_px; "" if none.
func _slot_near(c: Vector2, pid: String) -> String:
	var placed: Dictionary = StoryRunner.puzzle.get("placed", {})
	var best := ""
	var best_d := snap_px
	for sid in slot_centers.keys():
		if placed.has(sid) and String(placed[sid]) != pid:
			continue
		var d := c.distance_to(slot_centers[sid])
		if d <= best_d:
			best = sid
			best_d = d
	return best


func _beam_hit() -> Rect2:
	return Rect2(beam_hit_base.position + Vector2(_beam_shown_dx, 0), beam_hit_base.size)


func _notch_x(i: int, dx: float) -> float:
	return notch_base[i].x + dx


## The notch within mark_snap_px of the door's mark at shift `dx`, or -1.
func _notch_at_anchor(dx: float) -> int:
	var best := -1
	var best_d := mark_snap_px
	for i in notch_base.size():
		var d := absf(_notch_x(i, dx) - anchor.x)
		if d <= best_d:
			best = i
			best_d = d
	return best


func _dx_for(i: int) -> float:
	return anchor.x - notch_base[i].x


func _leaf_shown() -> bool:
	var view := String(StoryRunner.puzzle.get("view", ""))
	if view == "winter":
		return false
	return not _peeking


func _solved() -> bool:
	return bool(StoryRunner.puzzle.get("solved", false))


# --- Rendering ------------------------------------------------------------------------------

func _render() -> void:
	if root == null or not visible:
		return
	var st: Dictionary = StoryRunner.puzzle
	message_label.text = String(st.get("message", ""))
	hint_label.text = String(st.get("hint", ""))
	var errors := int(st.get("errors", 0))
	if errors > _last_errors:
		_peeking = true
		_peek_serial += 1
		var serial := _peek_serial
		get_tree().create_timer(WALL_PEEK_S).timeout.connect(func():
			if serial == _peek_serial:
				_peeking = false
				_render())
	_last_errors = errors
	# Hinges at rest: in their socket or in the tray (not the one held or flying).
	for pid in piece_nodes.keys():
		if _is_moving(pid):
			continue
		_set_piece_center(pid, _rest_center(pid))
	# Beam: the chosen notch under the mark, else where it was left.
	var mark := int(st.get("mark", -1))
	if mark >= 0 and mark < notch_base.size():
		_beam_dx = _dx_for(mark)
	if _drag.get("kind", "") != "beam" and (_beam_tween == null or not _beam_tween.is_running()):
		_beam_shown_dx = _beam_dx
	_update_beam_visuals()
	# Doorway.
	var view := String(st.get("view", ""))
	var leaf := _leaf_shown()
	door_leaf.visible = leaf
	if view == "winter":
		door_view.color = Color(0.62, 0.72, 0.86)
		# The classroom itself when the data gives its picture (F18); the old caption only on the flat colour.
		winter_label.text = "" if winter_view != null else StoryData.location_name("O1")
		snow.emitting = true
	else:
		door_view.color = Color(0.36, 0.30, 0.25)
		winter_label.text = ""
		snow.emitting = false
	if winter_view != null:
		winter_view.visible = view == "winter"
	if winter_front != null:
		winter_front.visible = view == "winter"
		for c in winter_front.get_children():
			if c is CPUParticles2D:
				(c as CPUParticles2D).emitting = view == "winter"
	var solved := _solved()
	check_button.disabled = solved
	_update_glows()
	if solved:
		_auto_close()


func _is_moving(pid: String) -> bool:
	if _carry == pid or String(_drag.get("pid", "")) == pid:
		return true
	var tw: Tween = _piece_tweens.get(pid)
	return tw != null and tw.is_valid() and tw.is_running()


func _update_beam_visuals() -> void:
	if beam_node == null:
		return
	beam_node.position.x = _beam_shown_dx
	var mark := int(StoryRunner.puzzle.get("mark", -1))
	var preview := _notch_at_anchor(_beam_shown_dx) if _drag.get("kind", "") == "beam" else -1
	for i in notch_marks.size():
		var on := i == mark and absf(_beam_shown_dx - _beam_dx) < 1.0
		var a := 0.9 if on else (0.55 if i == preview else 0.0)
		notch_marks[i].color = Color(GLOW.r, GLOW.g, GLOW.b, a)
	if not seat.is_empty() and preview < 0 and mark < 0:
		preview = _notch_at_anchor(_beam_shown_dx)   # resting near a notch, not seated: still shown (amber)
	var aligned := (mark >= 0 and absf(_beam_shown_dx - _beam_dx) < 1.0) or preview >= 0
	guide_line.visible = aligned
	var seated := mark >= 0 and absf(_beam_shown_dx - _beam_dx) < 1.0
	guide_line.color = Color(0.55, 0.85, 0.45, 0.95) if seated or (preview >= 0 and _seat_off(preview, _beam_shown_dx) <= seat_tol_px) \
		else (Color(1.0, 0.62, 0.25, 0.95) if not seat.is_empty() else Color(GLOW.r, GLOW.g, GLOW.b, 0.85))
	_update_seat_arrows(preview if not seated else -1)
	if aligned and notch_base.size() > 0:
		var i := mark if preview < 0 else preview
		var ny := notch_base[i].y
		guide_line.position = Vector2(anchor.x - 1.5, minf(anchor.y, ny))
		guide_line.size = Vector2(3, maxf(absf(ny - anchor.y), 6.0))


## How far notch i is from the door's mark at shift dx (px, signed: + — the notch is right of the mark).
func _notch_off(i: int, dx: float) -> float:
	return _notch_x(i, dx) - anchor.x


func _seat_off(i: int, dx: float) -> float:
	return absf(_notch_off(i, dx))


## The knock arrows at the beam's ends: shown while a notch is near the mark but not seated; the end to strike
## glows (the notch right of the mark — strike the right end, it goes left), the other is faint.
func _update_seat_arrows(near: int) -> void:
	if seat_arrows.is_empty():
		return
	var hit := _beam_hit()
	var show: bool = near >= 0 and String(_drag.get("kind", "")) != "beam" and not _solved()
	var off := _notch_off(near, _beam_shown_dx) if near >= 0 else 0.0
	for k in 2:
		var a: Label = seat_arrows[k]
		a.visible = show
		a.position = Vector2(hit.position.x - 44.0 if k == 0 else hit.end.x + 4.0, hit.get_center().y - 20.0)
		var want := (k == 0 and off < 0.0) or (k == 1 and off > 0.0)
		a.modulate = Color(1, 1, 1, 1.0 if want else 0.3)
	if seat_hint != null:
		var hk := clampf(1.0 - (_pulse_t - _seat_hint_t) / 1.5, 0.0, 1.0)
		seat_hint.visible = show or hk > 0.0
		seat_hint.modulate = Color(1.0, 1.0 - 0.3 * hk, 1.0 - 0.6 * hk, 1.0)


## A knock on an end of the beam (H18): it moves seat_tap_px toward the other end; within tol_px of the mark the
## nearest notch sits in it (chosen).
func _knock(dir: float) -> void:
	seat_taps += 1
	var to := clampf(_beam_shown_dx + dir * seat_tap_px, shift_range.x, shift_range.y)
	_beam_dx = to
	if int(StoryRunner.puzzle.get("mark", -1)) != -1:
		StoryRunner.puzzle_set_mark(-1)
	_sound("beam")
	var i := _notch_at_anchor(to)
	if i >= 0 and _seat_off(i, to) <= seat_tol_px:
		_align_beam(i)
		return
	if _beam_tween != null and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = create_tween()
	_beam_tween.tween_method(func(v: float): _beam_shown_dx = v; _update_beam_visuals(), _beam_shown_dx, to, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_beam_tween.finished.connect(func(): _beam_shown_dx = _beam_dx; _update_beam_visuals())


func _update_glows() -> void:
	var holding := _carry != "" or String(_drag.get("kind", "")) == "piece"
	var held := _carry if _carry != "" else String(_drag.get("pid", ""))
	var placed: Dictionary = StoryRunner.puzzle.get("placed", {})
	var in_tray := 0
	for pid in piece_nodes.keys():
		if StoryRunner.puzzle_piece_slot(pid) == "":
			in_tray += 1
	var pulse := 0.18 + 0.14 * (0.5 + 0.5 * sin(_pulse_t * 3.0))
	if tray_node != null:
		tray_node.modulate = Color(1, 1, 1, 1.0 if (in_tray > 0 or holding) else 0.35)
	for sid in slot_glows.keys():
		var g: Panel = slot_glows[sid]
		var free: bool = not placed.has(sid) or String(placed[sid]) == held
		if _solved() or not free:
			g.visible = false
		elif holding:
			g.visible = true
			g.modulate = Color(1, 1, 1, 1.0 if sid == _target_slot else 0.35)
		elif in_tray > 0:
			g.visible = true   # quiet invitation: empty sockets breathe while hinges wait in the tray
			g.modulate = Color(1, 1, 1, pulse)
		else:
			g.visible = false
	if handle_glow != null:
		var show_h := _hover_handle and _leaf_shown() and not _solved() and not holding and _drag.is_empty()
		handle_glow.visible = show_h
		handle_label.visible = show_h


func _process(delta: float) -> void:
	if root == null or not visible:
		return
	_pulse_t += delta
	if _drag.is_empty() and _carry == "":
		_update_glows()
	if seat_hint != null and seat_hint.visible:
		_update_beam_visuals()


func _auto_close() -> void:
	await get_tree().create_timer(SUCCESS_CLOSE_SECONDS).timeout
	# The success message's voice-over (VoiceDirector, kind "puzzle") is heard to its end before the
	# close-up goes; «Закрыть» closes it at once (and cuts the voice).
	var vd := get_node_or_null("/root/VoiceDirector")
	var waited := 0.0
	while vd != null and bool(vd.call("is_speaking_kind", "puzzle")) and waited < MAX_VOICE_WAIT_S \
			and StoryRunner.puzzle_open:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if StoryRunner.puzzle_open and bool(StoryRunner.puzzle.get("solved", false)):
		StoryRunner.close_puzzle()


# --- Mouse ----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if root == null or not visible:
		return
	if event is InputEventKey:
		# Optional: Esc leaves the close-up (the mouse path is «Закрыть»).
		if event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			if _carry != "":
				_return_to_tray(_carry)
				_carry = ""
			else:
				StoryRunner.close_puzzle()
		return
	if not (event is InputEventMouse):
		return
	var pos: Vector2 = event.position
	if event is InputEventMouseMotion:
		_on_motion(pos)
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if _solved():
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _carry != "":
			_return_to_tray(_carry)
			_carry = ""
			selected_piece = ""
			_target_slot = ""
			_update_glows()
			get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _press(pos):
			get_viewport().set_input_as_handled()
	elif not _drag.is_empty():
		_release(pos)
		get_viewport().set_input_as_handled()


func _press(pos: Vector2) -> bool:
	if _carry != "":
		_drop_piece(_carry, pos + _carry_offset, "")
		_carry = ""
		selected_piece = ""
		_set_cursor(_cursor_for(pos))
		return true
	var pid := _piece_at(pos)
	if pid != "":
		var tw: Tween = _piece_tweens.get(pid)
		if tw != null and tw.is_valid():
			tw.kill()
		_drag = {"kind": "piece", "pid": pid, "from_slot": StoryRunner.puzzle_piece_slot(pid), "press": pos,
			"offset": _piece_center(pid) - pos, "moved": false}
		piece_nodes[pid].move_to_front()
		_sound("take")
		_set_cursor(Control.CURSOR_CAN_DROP)
		_update_glows()
		return true
	if handle_rect.size != Vector2.ZERO and handle_rect.has_point(pos) and _leaf_shown():
		_close_door()
		return true
	if _beam_hit().has_point(pos):
		if _beam_tween != null and _beam_tween.is_valid():
			_beam_tween.kill()
		_drag = {"kind": "beam", "press": pos, "start_dx": _beam_shown_dx, "moved": false}
		_set_cursor(Control.CURSOR_CAN_DROP)
		return true
	return false


func _on_motion(pos: Vector2) -> void:
	if not _drag.is_empty():
		if pos.distance_to(_drag["press"]) > click_px:
			_drag["moved"] = true
		if _drag["kind"] == "piece":
			var c: Vector2 = pos + _drag["offset"]
			_set_piece_center(String(_drag["pid"]), c)
			_target_slot = _slot_near(c, String(_drag["pid"]))
			_update_glows()
			_set_cursor(Control.CURSOR_CAN_DROP)
		else:
			_beam_shown_dx = clampf(float(_drag["start_dx"]) + pos.x - Vector2(_drag["press"]).x, shift_range.x, shift_range.y)
			_update_beam_visuals()
			_set_cursor(Control.CURSOR_CAN_DROP)
		return
	if _carry != "":
		var c := pos + _carry_offset
		_set_piece_center(_carry, c)
		_target_slot = _slot_near(c, _carry)
		_update_glows()
		_set_cursor(Control.CURSOR_CAN_DROP)
		return
	var over_handle := handle_rect.size != Vector2.ZERO and handle_rect.has_point(pos) and _leaf_shown() and not _solved()
	if over_handle != _hover_handle:
		_hover_handle = over_handle
		_update_glows()
	_set_cursor(_cursor_for(pos))


func _cursor_for(pos: Vector2) -> Control.CursorShape:
	if _solved():
		return Control.CURSOR_ARROW
	if _piece_at(pos) != "":
		return Control.CURSOR_DRAG
	if handle_rect.size != Vector2.ZERO and handle_rect.has_point(pos) and _leaf_shown():
		return Control.CURSOR_POINTING_HAND
	if _beam_hit().has_point(pos):
		return Control.CURSOR_DRAG
	return Control.CURSOR_ARROW


func _set_cursor(shape: Control.CursorShape) -> void:
	if root != null and root.mouse_default_cursor_shape != shape:
		root.mouse_default_cursor_shape = shape


func _release(pos: Vector2) -> void:
	var d := _drag
	_drag = {}
	if d["kind"] == "piece":
		var pid := String(d["pid"])
		if not bool(d["moved"]):
			if String(d["from_slot"]) != "":
				# Click on a placed hinge: back to the tray.
				StoryRunner.puzzle_place(pid, "")
				_return_to_tray(pid)
			else:
				# Click on a tray hinge: in hand until the next click.
				_carry = pid
				selected_piece = pid
				_carry_offset = Vector2.ZERO
				_set_piece_center(pid, pos)
				_target_slot = _slot_near(pos, pid)
		else:
			_drop_piece(pid, pos + Vector2(d["offset"]), String(d["from_slot"]))
		_update_glows()
		_set_cursor(_cursor_for(pos) if _carry == "" else Control.CURSOR_CAN_DROP)
		return
	# Beam.
	if not seat.is_empty():
		_release_beam_seat(pos, d)
		_set_cursor(_cursor_for(pos))
		return
	if not bool(d["moved"]):
		# Click on the beam: the notch nearest the click comes under the door's mark.
		var best := -1
		var best_d := INF
		for i in notch_base.size():
			var dd := absf(_notch_x(i, _beam_shown_dx) - pos.x)
			if dd < best_d:
				best = i
				best_d = dd
		if best >= 0:
			_align_beam(best)
	else:
		var i := _notch_at_anchor(_beam_shown_dx)
		if i >= 0:
			_align_beam(i)
		else:
			_beam_dx = _beam_shown_dx
			if int(StoryRunner.puzzle.get("mark", -1)) != -1:
				StoryRunner.puzzle_set_mark(-1)
			_update_beam_visuals()
	_set_cursor(_cursor_for(pos))


## H18: the beam let go — near a notch it rests there unseated (to be knocked in), exactly at it — seated; a click on
## an end knocks it, a click in the middle shows the hint.
func _release_beam_seat(pos: Vector2, d: Dictionary) -> void:
	if not bool(d["moved"]):
		var hit := _beam_hit()
		var f := (pos.x - hit.position.x) / maxf(hit.size.x, 1.0)
		if f <= seat_end_frac:
			_knock(1.0)
		elif f >= 1.0 - seat_end_frac:
			_knock(-1.0)
		else:
			_seat_hint_t = _pulse_t
			_update_beam_visuals()
		return
	_beam_dx = _beam_shown_dx
	var i := _notch_at_anchor(_beam_shown_dx)
	if i >= 0 and _seat_off(i, _beam_shown_dx) <= seat_tol_px:
		_align_beam(i)
		return
	if int(StoryRunner.puzzle.get("mark", -1)) != -1:
		StoryRunner.puzzle_set_mark(-1)
	if i >= 0:
		_sound("beam")
	_update_beam_visuals()


func _drop_piece(pid: String, center: Vector2, from_slot: String) -> void:
	var target := _slot_near(center, pid)
	_target_slot = ""
	if target != "":
		StoryRunner.puzzle_place(pid, target)
		_tween_piece(pid, slot_centers[target], 0.08)
		_sound("snap")
	else:
		if from_slot != "" or StoryRunner.puzzle_piece_slot(pid) != "":
			StoryRunner.puzzle_place(pid, "")
		_return_to_tray(pid)


func _return_to_tray(pid: String) -> void:
	_tween_piece(pid, _tray_center(pid), return_s)
	_sound("return")


func _tween_piece(pid: String, to_center: Vector2, seconds: float) -> void:
	var b: Control = piece_nodes.get(pid)
	if b == null:
		return
	var old: Tween = _piece_tweens.get(pid)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.tween_property(b, "position", to_center - b.size / 2, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func(): _piece_tweens.erase(pid))
	_piece_tweens[pid] = tw


func _align_beam(i: int) -> void:
	_beam_dx = _dx_for(i)
	if _beam_tween != null and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = create_tween()
	_beam_tween.tween_method(func(v: float): _beam_shown_dx = v; _update_beam_visuals(), _beam_shown_dx, _beam_dx, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_beam_tween.finished.connect(func(): _beam_shown_dx = _beam_dx; _update_beam_visuals())
	_sound("beam")
	StoryRunner.puzzle_set_mark(i)


func _close_door() -> void:
	if _solved():
		return
	var ok := StoryRunner.puzzle_check()
	_sound("close_success" if ok else "close_error")
	_hover_handle = false
	_render()


func _on_check() -> void:
	if _carry != "":
		_return_to_tray(_carry)
		_carry = ""
		selected_piece = ""
	_close_door()


func _sound(kind: String) -> void:
	var sid := String(spec.get("sounds", {}).get(kind, ""))
	var sfx := get_node_or_null("/root/SfxDirector")
	if sid != "" and sfx != null and sfx.has_method("play_sound"):
		sfx.call("play_sound", sid, "closeup")


# --- Probe (web walkthrough, tests) -----------------------------------------------------------

func probe_positions() -> Dictionary:
	var st: Dictionary = StoryRunner.puzzle
	var out := {"open": visible and root != null, "pieces": {}, "slots": {}, "marks": [], "check": {}, "close": {},
		"solved": bool(st.get("solved", false)), "view": String(st.get("view", "")),
		"errors": int(st.get("errors", 0)), "hint": String(st.get("hint", "")),
		"mark": int(st.get("mark", -1)), "placed": (st.get("placed", {}) as Dictionary).duplicate(),
		"carry": _carry, "dragging": String(_drag.get("kind", "")), "leaf": false}
	if root == null or not visible:
		return out
	for pid in piece_nodes.keys():
		out["pieces"][pid] = _xy(_piece_center(pid))
	for sid in slot_centers.keys():
		out["slots"][sid] = _xy(slot_centers[sid])
	for i in notch_base.size():
		out["marks"].append(_xy(Vector2(_notch_x(i, _beam_shown_dx), notch_base[i].y + 10)))
	out["anchor"] = _xy(anchor)
	out["beam"] = _xy(_beam_hit().get_center())
	out["beam_dx"] = _beam_shown_dx
	out["seat"] = not seat.is_empty()
	out["seat_taps"] = seat_taps
	var hb := _beam_hit()
	# Where to knock (bots): a point on each end of the beam.
	out["knock_left"] = _xy(Vector2(hb.position.x + hb.size.x * seat_end_frac * 0.5, hb.get_center().y))
	out["knock_right"] = _xy(Vector2(hb.end.x - hb.size.x * seat_end_frac * 0.5, hb.get_center().y))
	var near := _notch_at_anchor(_beam_shown_dx)
	out["near"] = near
	out["near_off"] = _notch_off(near, _beam_shown_dx) if near >= 0 else 0.0
	out["seat_hint"] = seat_hint != null and seat_hint.visible
	out["guide_color"] = guide_line.color.to_html() if guide_line != null else ""
	if handle_rect.size != Vector2.ZERO:
		out["handle"] = _xy(handle_rect.get_center())
	out["tray"] = {}
	for pid in piece_nodes.keys():
		out["tray"][pid] = _xy(_tray_center(pid))
	out["leaf"] = door_leaf != null and door_leaf.visible
	out["cursor"] = int(root.mouse_default_cursor_shape)
	out["check"] = _center(check_button)
	out["close"] = _center(close_button)
	return out


func _xy(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}


func _center(c: Control) -> Dictionary:
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}
