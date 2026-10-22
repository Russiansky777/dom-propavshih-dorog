extends MechanicPanel
## M15, the plate on the near pier at the turn (Z3), in the dusk, the water let down: the cast letters
## «Ольховка», the ring for the rope, the crack. Dunya's brace, put on the crack from the bag
## (`skoba_on_plate`), is driven in with three blows of the mouse — event "braced". When Pelageya has
## brought the rope (`rope_brought`), its free end is dragged to the ring and tied the way she shows:
## three places in turn; a wrong place — she shows again from the start, no penalty — event "tied".
## Art (партия 3): closeup_plate (the plate on the wet pier stone) and two layers on its canvas at (0, 0) —
## the brace across the crack and the rope tied on the ring. The brace layer sinks into place with the
## blows; the rope being dragged is a line drawn by the engine until it is tied (then the rope layer).
## Coordinates: `ring`, `ring_r`, `skoba_box` in canvas px (1672×941, shown full screen); `rope_free`,
## `rope_from`, `knot` (offsets from the ring) in screen px.

var k: float = 1.0                  # canvas → screen
var ring_c: Vector2 = Vector2.ZERO  # screen
var ring_r: float = 40.0            # screen
var skoba: TextureRect = null
var skoba_hit: Control = null
var rope_art: TextureRect = null
var blows: int = 0
var rope: Line2D = null
var rope_end: Vector2 = Vector2.ZERO
var rope_hit: Control = null
var rope_on_ring: bool = false
var knot_step: int = 0
var knot_marks: Array[Control] = []
var knot_errors: int = 0
var _dragging: bool = false
var _skoba_box: Rect2 = Rect2()


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	k = 1920.0 / 1672.0
	crop(String(art.get("bg", "")), full, Vector2.ZERO, k).name = "Plate"
	ring_c = v2(spec.get("ring", [555, 505])) * k
	ring_r = float(spec.get("ring_r", 150)) * k
	var sb: Array = spec.get("skoba_box", [890, 482, 300, 84])
	_skoba_box = Rect2(Vector2(float(sb[0]), float(sb[1])) * k, Vector2(float(sb[2]), float(sb[3])) * k)
	# The brace (its layer on the whole canvas; it sinks into place with the blows).
	skoba = crop(String(art.get("skoba", "")), full, Vector2.ZERO, k)
	skoba.name = "Skoba"
	skoba_hit = hit_area(_skoba_box.grow(30), _on_skoba_input, "SkobaHit")
	# The rope tied on the ring (layer) and the rope being brought (line).
	rope_art = crop(String(art.get("rope", "")), full, Vector2.ZERO, k)
	rope_art.name = "RopeTied"
	rope = Line2D.new()
	rope.name = "Rope"
	rope.width = 34
	rope.default_color = Color(0.62, 0.5, 0.32)
	rope.joint_mode = Line2D.LINE_JOINT_ROUND
	rope.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(rope)
	rope_end = v2(spec.get("rope_free", [330, 960]))
	rope_hit = hit_area(Rect2(rope_end - Vector2(60, 60), Vector2(120, 120)), _on_rope_input, "RopeEnd")
	var marks: Array = spec.get("knot", [[-150, 60], [0, -175], [150, 60]])
	for i in marks.size():
		var m := hit_area(Rect2(ring_c + v2(marks[i]) - Vector2(34, 34), Vector2(68, 68)), _on_knot_input.bind(i), "Knot%d" % i)
		var dot := Polygon2D.new()
		dot.name = "Dot"
		dot.color = Color(1.0, 0.85, 0.45, 0.85)
		dot.polygon = PlaceholderArt.circle_points(Vector2(34, 34), 15)
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
	var placed := flag("skoba_on_plate") or braced()
	skoba.visible = placed
	var sink := 1.0 if braced() else float(blows) / 3.0
	skoba.position = Vector2(0, -34.0 * (1.0 - sink))
	skoba_hit.visible = placed and not braced()
	var rope_here := flag("rope_brought")
	var tied := flag("rope_on_ring")
	rope_art.visible = tied
	rope.visible = rope_here and not tied
	if rope.visible:
		var start := v2(spec.get("rope_from", [-40, 1100]))
		var end := ring_c + Vector2(-ring_r * 0.2, ring_r * 0.95) if rope_on_ring else rope_end
		rope.points = PackedVector2Array([start, start.lerp(end, 0.5) + Vector2(0, 50), end])
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
				rope_end = v2(spec.get("rope_free", [330, 960]))
			_place_rope_hit()
			_refresh()
	elif ev is InputEventMouseMotion and _dragging:
		accept_event()
		rope_end = rope_hit.position + ev.position
		_refresh()


func _place_rope_hit() -> void:
	if not rope_on_ring:
		rope_hit.position = rope_end - Vector2(60, 60)


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
		"knot_step": knot_step, "knot_errors": knot_errors, "knot": marks, "rope_tied_visible": rope_art.visible}
