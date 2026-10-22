extends MechanicPanel
## M15, the plate on the near pier at the turn (Z3), in the dusk, the water let down: the cast letters
## «Ольховка», the ring for the rope, the crack. Dunya's brace, put on the crack from the bag
## (`skoba_on_plate`), is driven in with three blows of the mouse — event "braced". When Pelageya has
## brought the rope (`rope_brought`), its free end is dragged to the ring and tied the way she shows:
## three places in turn; a wrong place — she shows again from the start, no penalty — event "tied".
## Stand-in art until «Z3_plate_bg / _skoba / _rope» (BRIEF_CHATGPT_v4 §C5): a crop of the delivered Z3
## painting round the pier stone, with the plate, letters, ring and crack drawn by the engine; the brace —
## its icon (assets/icons/skoba_plate).

var plate_rect: Rect2 = Rect2()
var ring_c: Vector2 = Vector2.ZERO
var ring_r: float = 40.0
var skoba: TextureRect = null
var skoba_hit: Control = null
var blows: int = 0
var rope: Line2D = null
var rope_end: Vector2 = Vector2.ZERO
var rope_hit: Control = null
var rope_on_ring: bool = false
var knot_step: int = 0
var knot_marks: Array[Control] = []
var knot_errors: int = 0
var _dragging: bool = false


func build() -> void:
	var bgs: Dictionary = spec.get("stone", {})
	crop(String(bgs.get("image", "")), bgs.get("region", [1262, 505, 236, 200]), v2(bgs.get("pos", [300, 170])), float(bgs.get("scale", 3.6))).name = "Stone"
	var dusk := ColorRect.new()
	dusk.name = "Dusk"
	dusk.color = Color(0.25, 0.28, 0.42, 0.45)
	dusk.position = v2(bgs.get("pos", [300, 170]))
	var reg: Array = bgs.get("region", [1262, 505, 236, 200])
	dusk.size = Vector2(float(reg[2]), float(reg[3])) * float(bgs.get("scale", 3.6))
	dusk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dusk)
	var pr: Array = spec.get("plate", [430, 260, 600, 470])
	plate_rect = Rect2(float(pr[0]), float(pr[1]), float(pr[2]), float(pr[3]))
	var plate := Polygon2D.new()
	plate.name = "Plate"
	plate.color = Color(0.36, 0.34, 0.33)
	plate.polygon = PackedVector2Array([plate_rect.position, plate_rect.position + Vector2(plate_rect.size.x, 0), plate_rect.end, plate_rect.position + Vector2(0, plate_rect.size.y)])
	add_child(plate)
	for c in [plate_rect.position + Vector2(24, 24), plate_rect.position + Vector2(plate_rect.size.x - 24, 24),
			plate_rect.end - Vector2(24, 24), plate_rect.position + Vector2(24, plate_rect.size.y - 24)]:
		var rivet := Polygon2D.new()
		rivet.color = Color(0.22, 0.2, 0.19)
		rivet.polygon = PlaceholderArt.circle_points(c, 9)
		add_child(rivet)
	var word := Label.new()
	word.name = "Letters"
	word.text = text("label_letters")
	word.position = plate_rect.position + Vector2(40, plate_rect.size.y * 0.58)
	word.size = Vector2(plate_rect.size.x - 80, 90)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_override("font", UiTheme.font("head_bold"))
	word.add_theme_font_size_override("font_size", 64)
	word.add_theme_color_override("font_color", Color(0.24, 0.22, 0.21))
	word.add_theme_color_override("font_outline_color", Color(0.5, 0.48, 0.45))
	word.add_theme_constant_override("outline_size", 2)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(word)
	var crack := Line2D.new()
	crack.name = "Crack"
	crack.points = PlaceholderArt._points(spec.get("crack", [[600, 262], [640, 330], [615, 390], [668, 470], [650, 540]]))
	crack.width = 6
	crack.default_color = Color(0.08, 0.07, 0.07)
	add_child(crack)
	ring_c = v2(spec.get("ring", [930, 340]))
	ring_r = float(spec.get("ring_r", 42))
	var ring := Line2D.new()
	ring.name = "Ring"
	ring.points = PlaceholderArt.circle_points(ring_c, ring_r)
	ring.closed = true
	ring.width = 12
	ring.default_color = Color(0.2, 0.18, 0.17)
	add_child(ring)
	# The brace.
	var sk: Dictionary = spec.get("skoba", {})
	skoba = TextureRect.new()
	skoba.name = "Skoba"
	if ResourceLoader.exists(String(sk.get("icon", ""))):
		skoba.texture = load(String(sk["icon"]))
	skoba.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skoba.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skoba.size = Vector2(float(sk.get("size", 230)), float(sk.get("size", 230)))
	skoba.pivot_offset = skoba.size * 0.5
	skoba.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skoba)
	skoba_hit = hit_area(Rect2(v2(sk.get("at", [640, 400])) - skoba.size * 0.5, skoba.size), _on_skoba_input, "SkobaHit")
	# The rope and the knot.
	rope = Line2D.new()
	rope.name = "Rope"
	rope.width = 16
	rope.default_color = Color(0.55, 0.43, 0.27)
	rope.joint_mode = Line2D.LINE_JOINT_ROUND
	rope.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(rope)
	rope_end = v2(spec.get("rope_free", [1250, 760]))
	rope_hit = hit_area(Rect2(rope_end - Vector2(50, 50), Vector2(100, 100)), _on_rope_input, "RopeEnd")
	var marks: Array = spec.get("knot", [[-60, 10], [0, -70], [60, 20]])
	for i in marks.size():
		var m := hit_area(Rect2(ring_c + v2(marks[i]) - Vector2(30, 30), Vector2(60, 60)), _on_knot_input.bind(i), "Knot%d" % i)
		var dot := Polygon2D.new()
		dot.name = "Dot"
		dot.color = Color(1.0, 0.85, 0.45, 0.85)
		dot.polygon = PlaceholderArt.circle_points(Vector2(30, 30), 13)
		m.add_child(dot)
		knot_marks.append(m)
	label(text("label_hint"), v2(spec.get("hint_pos", [1100, 900])), 760)
	rope_on_ring = flag("rope_on_ring")
	_refresh()


func flags_changed() -> void:
	if skoba != null:
		_refresh()


func braced() -> bool:
	return flag("plate_braced")


func _refresh() -> void:
	var sk: Dictionary = spec.get("skoba", {})
	var at := v2(sk.get("at", [640, 400]))
	var placed := flag("skoba_on_plate") or braced()
	skoba.visible = placed
	var sink := 1.0 if braced() else float(blows) / 3.0
	skoba.position = at - skoba.size * 0.5 + Vector2(0, -36.0 * (1.0 - sink))
	skoba.rotation_degrees = float(sk.get("angle", 62)) - 6.0 * (1.0 - sink)
	skoba_hit.visible = placed and not braced()
	var rope_here := flag("rope_brought")
	rope.visible = rope_here
	var tied := flag("rope_on_ring")
	if rope_here:
		var start := v2(spec.get("rope_from", [1700, 1000]))
		var end := ring_c + Vector2(0, ring_r) if (rope_on_ring or tied) else rope_end
		rope.points = PackedVector2Array([start, start.lerp(end, 0.5) + Vector2(0, 40), end])
	rope_hit.visible = rope_here and not rope_on_ring and not tied
	for i in knot_marks.size():
		var m := knot_marks[i]
		m.visible = rope_on_ring and not tied
		var dot: Polygon2D = m.get_node("Dot")
		dot.color = Color(1.0, 0.85, 0.45, 0.9) if i == knot_step else Color(1, 1, 1, 0.12)


func _on_skoba_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if braced():
		return
	blows += 1
	sound("hammer")
	_refresh()
	if blows >= 3:
		event("braced")
		_refresh()


func _on_rope_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if ev.pressed:
			_dragging = true
		elif _dragging:
			_dragging = false
			var p: Vector2 = rope_hit.position + ev.position
			if p.distance_to(ring_c) <= ring_r + 70.0:
				rope_on_ring = true
				knot_step = 0
				say("rope_at_ring")
			else:
				rope_end = v2(spec.get("rope_free", [1250, 760]))
			_place_rope_hit()
			_refresh()
	elif ev is InputEventMouseMotion and _dragging:
		accept_event()
		rope_end = rope_hit.position + ev.position
		_refresh()


func _place_rope_hit() -> void:
	if not rope_on_ring:
		rope_hit.position = rope_end - Vector2(50, 50)


func _on_knot_input(ev: InputEvent, i: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if i != knot_step:
		knot_errors += 1
		knot_step = 0
		say("knot_wrong")
		_refresh()
		return
	knot_step += 1
	sound("shutter")
	if knot_step >= knot_marks.size():
		event("tied")
	_refresh()


func probe() -> Dictionary:
	var marks: Array = []
	for m in knot_marks:
		marks.append(center_of(m))
	return {"blows": blows, "braced": braced(), "skoba": center_of(skoba_hit), "skoba_visible": skoba.visible,
		"rope_end": center_of(rope_hit), "ring": {"x": ring_c.x, "y": ring_c.y}, "rope_on_ring": rope_on_ring,
		"knot_step": knot_step, "knot_errors": knot_errors, "knot": marks}
