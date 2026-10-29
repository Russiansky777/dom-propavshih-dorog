extends MechanicPanel
## M15, the plate on the near pier at the turn (Z3), in the dusk, the water let down: the cast letters
## «Ольховка», the ring for the rope, the crack.
##   - The brace (F7, Director 23.10: «полоса от красного до зелёного в центре и снова красного, ползунок
##     лево-право, попасть в зелёную 3 раза подряд, при неудаче повтор»): Dunya's brace, put on the crack from the
##     bag (`skoba_on_plate`), is driven in by `timing.hits` blows in a row on the «Точный удар» bar under the
##     plate (TimingBar: a click on the brace or the bar, or Space). Each hit sinks it a step; a miss — the brace
##     jumps off the crack and the series starts again (nothing lost). Event "braced".
##   - The knot (F6: «тянуть мышкой, „завязывая“ узел»): when Pelageya has brought the rope (`rope_brought`), its
##     end lies by the ring; the player takes it and draws it along the knot, stroke by stroke as Pelageya shows —
##     under the ring and up through it, round over the front, into the loop and tight (KnotPath, `knot_path` in
##     data: strokes in canvas px, tolerance). Off the dotted path, or let go in the middle of a stroke, the end
##     slips back to where that stroke began — no penalty. Event "tied", then the painted knot (rope layer).
##   - F5 («канат … однородного цвета»): the rope being tied is the painted rope's own strip
##     (RopeLine/rope_tile.png), not a flat line; the part that goes behind the ring passes under its painted
##     lower arc.
## Art (партия 3): closeup_plate (the plate on the wet pier stone) and two layers on its canvas at (0, 0) — the
## brace across the crack and the rope tied on the ring. Coordinates of `ring`, `ring_r`, `skoba_box`,
## `knot_path.strokes`, `rope_from` — canvas px (1672×941, shown full screen).

var k: float = 1.0                  # canvas → screen
var ring_c: Vector2 = Vector2.ZERO  # screen
var ring_r: float = 40.0            # screen
var skoba: TextureRect = null
var skoba_hit: Control = null
var rope_art: TextureRect = null
var timing: TimingBar = null
var blows: int = 0
var jumps: int = 0
var _jump_t: float = -1.0
var knot: KnotPath = null
var rope_back: Line2D = null        # the rope up to and through the ring (behind its lower arc)
var rope_front: Line2D = null       # the rest of the knot (in front)
var rope_shadow: Line2D = null
var ring_front: Polygon2D = null    # the ring's painted lower arc, drawn over the rope that passes behind it
var guide: Line2D = null
var guide_arrow: Polygon2D = null
var end_grip: Control = null
var stroke_label: Label = null
var hint: Label = null
var slips: int = 0
var tied_t: float = -1.0
var _slip_from: Vector2 = Vector2.ZERO
var _slip_t: float = -1.0
var _drag_pos: Vector2 = Vector2.ZERO
var _skoba_box: Rect2 = Rect2()
# The living rope (J, стр. 125: «будто он полу-статичный и ни влево ни вправо не ходит совсем»): the lead-in from the
# boat sways with the current and tightens as the end is drawn through (a springy sag — it drops and bounces back
# when the end slips); the strands slide along the rope as it is hauled; the end follows the hand off the path
# (within the knot's tolerance) and the last part of the rope bends after it. Drawing only — the knot is KnotPath.
var _t: float = 0.0
var _sag: float = 48.0
var _sag_v: float = 0.0
var _hand_vis: Vector2 = Vector2.ZERO    # the end's offset from the path, eased
var _drawn_vis: float = 0.0             # how much rope has gone into the knot (for the strands), eased


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	k = 1920.0 / 1672.0
	crop(String(art.get("bg", "")), full, Vector2.ZERO, k).name = "Plate"
	ring_c = v2(spec.get("ring", [553, 512])) * k
	ring_r = float(spec.get("ring_r", 158)) * k
	var sb: Array = spec.get("skoba_box", [890, 482, 300, 84])
	_skoba_box = Rect2(Vector2(float(sb[0]), float(sb[1])) * k, Vector2(float(sb[2]), float(sb[3])) * k)
	# The brace (its layer on the whole canvas; it sinks into place with the blows).
	skoba = crop(String(art.get("skoba", "")), full, Vector2.ZERO, k)
	skoba.name = "Skoba"
	skoba.pivot_offset = _skoba_box.get_center()
	skoba_hit = hit_area(_skoba_box.grow(40), _on_skoba_input, "SkobaHit")
	# The tied rope (the painted layer) — shown once the knot is done.
	rope_art = crop(String(art.get("rope", "")), full, Vector2.ZERO, k)
	rope_art.name = "RopeTied"
	# The rope being tied: textured lines; the part behind the ring under the ring's own lower arc.
	var w := float(spec.get("rope_width", 64.0))
	rope_shadow = RopeLine.shadow(w, "RopeShadow")
	add_child(rope_shadow)
	rope_back = RopeLine.make(w, "RopeBack")
	add_child(rope_back)
	ring_front = _ring_arc(String(art.get("bg", "")), spec.get("ring_front_deg", [15.0, 165.0]))
	add_child(ring_front)
	rope_front = RopeLine.make(w, "RopeFront")
	add_child(rope_front)
	guide = Line2D.new()
	guide.name = "Guide"
	guide.width = 7.0
	guide.default_color = Color(1.0, 0.9, 0.55, 0.85)
	guide.texture = _dash_texture()
	guide.texture_mode = Line2D.LINE_TEXTURE_TILE
	guide.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(guide)
	guide_arrow = Polygon2D.new()
	guide_arrow.name = "GuideArrow"
	guide_arrow.color = Color(1.0, 0.9, 0.55, 0.95)
	add_child(guide_arrow)
	knot = KnotPath.new(spec.get("knot_path", {}), Vector2.ZERO, k)
	end_grip = Control.new()
	end_grip.name = "RopeEnd"
	end_grip.size = Vector2(1920, 1080)
	end_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	end_grip.gui_input.connect(_on_rope_input)
	add_child(end_grip)
	stroke_label = label("", Vector2.ZERO, 420, &"CloseupLabel")
	# «Точный удар» under the plate.
	timing = TimingBar.new()
	timing.name = "Timing"
	var tr: Array = spec.get("timing_rect", [560, 905, 800, 58])
	timing.position = Vector2(float(tr[0]), float(tr[1]))
	timing.size = Vector2(float(tr[2]), float(tr[3]))
	add_child(timing)
	timing.setup(spec.get("timing", {"hits": 3, "period_s": 2.0, "green": 0.2}))
	timing.struck.connect(_on_struck)
	strike_bar = timing   # G26: a click anywhere on the plate strikes too
	hint = label("", v2(spec.get("hint_pos", [1150, 120])), 720)
	_refresh()


## The ring's lower arc (annulus sector `deg` [from, to], 0° right, 90° down) cut out of the painting itself.
func _ring_arc(image: String, deg: Array) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = "RingFront"
	if image == "" or not ResourceLoader.exists(image):
		return p
	p.texture = load(image)
	var r_out := float(spec.get("ring_r", 158))
	var r_in := float(spec.get("ring_r_in", 98))
	var c := v2(spec.get("ring", [553, 512]))
	var pts := PackedVector2Array()
	var uv := PackedVector2Array()
	var n := 24
	var a0 := deg_to_rad(float(deg[0]))
	var a1 := deg_to_rad(float(deg[1]))
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		var q := c + Vector2(cos(a), sin(a)) * r_out
		pts.append(q * k)
		uv.append(q)
	for i in n + 1:
		var a := lerpf(a1, a0, float(i) / n)
		var q := c + Vector2(cos(a), sin(a)) * r_in
		pts.append(q * k)
		uv.append(q)
	p.polygon = pts
	p.uv = uv
	return p


static var _dash: ImageTexture = null


static func _dash_texture() -> ImageTexture:
	if _dash == null:
		var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
		for x in 16:
			for y in 4:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if x < 9 else 0.0))
		_dash = ImageTexture.create_from_image(img)
	return _dash


func flags_changed() -> void:
	if skoba != null:
		_refresh()


func braced() -> bool:
	return flag("plate_braced")


func tied() -> bool:
	return flag("rope_on_ring")


func knot_stage() -> bool:
	return flag("rope_brought") and not tied() and tied_t < 0.0


func _refresh() -> void:
	var placed := flag("skoba_on_plate") or braced()
	skoba.visible = placed
	skoba_hit.visible = placed and not braced()
	timing.visible = placed and not braced()
	_place_skoba()
	rope_art.visible = tied() or tied_t >= 0.0
	end_grip.visible = knot_stage()
	for n in [rope_back, rope_front, rope_shadow, ring_front, guide, guide_arrow, stroke_label]:
		n.visible = knot_stage() or (tied_t >= 0.0 and tied_t < 0.6 and n in [rope_back, rope_front, rope_shadow, ring_front])
	if timing.visible:
		hint.text = text("label_hint_brace")
	elif knot_stage():
		hint.text = text("label_hint_rope")
	else:
		hint.text = ""
	_draw_rope()


func _place_skoba() -> void:
	var sink := 1.0 if braced() else float(blows) / float(maxi(timing.logic.hits_needed if timing.logic else 3, 1))
	var y := -34.0 * (1.0 - sink)
	var rot := 0.0
	if _jump_t >= 0.0:
		# The brace jumps off the crack: up and askew, then drops back loose on the crack.
		var x := clampf(_jump_t / 0.6, 0.0, 1.0)
		y += -90.0 * sin(x * PI)
		rot = 9.0 * sin(x * PI)
	skoba.position = Vector2(0, y)
	skoba.rotation_degrees = rot


# --- The brace ------------------------------------------------------------------------------

func _on_skoba_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not braced():
			timing.strike()


func _on_struck(r: String) -> void:
	match r:
		"hit", "done":
			blows = timing.logic.hits
			sound("hammer")
			if r == "hit" and blows in [1, 2]:
				# J (стр. 120): Agata counts the blows — «Раз!», «Два!» (the third one drives it home)
				var ck := String(spec.get("texts", {}).get("count_%d" % blows, "@mech.plate.count_%d" % blows)).trim_prefix("@")
				pop_word(ck, v2(spec.get("count_pos", [700, 300])))
			if r == "done":
				timing.visible = false
				event("braced")
		"miss":
			blows = 0
			jumps += 1
			_jump_t = 0.0
			sound("clank")
			if jumps == 1:
				say("brace_jumped")
	_refresh()


# --- The knot ------------------------------------------------------------------------------

func _on_rope_input(ev: InputEvent) -> void:
	if not knot_stage():
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if knot.grab(ev.position):
				accept_event()
				_drag_pos = ev.position
				end_grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
		else:
			if knot.grabbed:
				accept_event()
				_after(knot.release())
	elif ev is InputEventMouseMotion and knot.grabbed:
		accept_event()
		_drag_pos = ev.position
		# Long moves are walked in small steps: a fast stroke along the path counts, a jump across does not.
		var r := ""
		var from := knot.end_point()
		var steps := maxi(1, int(from.distance_to(ev.position) / 24.0))
		for i in steps:
			r = knot.drag(from.lerp(ev.position, float(i + 1) / steps))
			if r != "move":
				break
		_after(r)


func _after(r: String) -> void:
	match r:
		"slip":
			slips += 1
			_slip_from = _drag_pos
			_slip_t = 0.0
			_hand_vis = Vector2.ZERO
			_sag_v += 90.0   # the slack drops back and bounces
			sound("rope_slip")
			if slips == 1:
				say("knot_slipped")
		"stroke":
			sound("rope_creak")
		"done":
			sound("rope_creak")
			tied_t = 0.0
	if r != "move":
		end_grip.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh()


## The rope from the boat (off the plate's lower left) to its end: the lead-in sags, then the knot so far.
func _draw_rope() -> void:
	if not rope_back.visible:
		return
	var from := v2(spec.get("rope_from", [-60, 1160])) * k
	var kp := knot.rope_points()
	var end := knot.end_point()
	if _slip_t >= 0.0:
		# slipping back: the end slides from where the hand was to the stroke's start
		var x := clampf(_slip_t / 0.3, 0.0, 1.0)
		end = _slip_from.lerp(knot.end_point(), x * x)
		kp = knot.rope_points()
		if kp.size() > 0:
			kp[kp.size() - 1] = end
	if _slip_t < 0.0:
		kp = _bend_to_hand(kp)
	var lead := _lead_points(from, kp[0] if kp.size() > 0 else end)
	var back := PackedVector2Array(lead)
	var front := PackedVector2Array()
	# The first stroke goes up behind the ring's lower arc (under its painted arc); the rest is in front of it.
	var n0 := knot.strokes[0].size() if knot.strokes.size() > 0 else 0
	for i in kp.size():
		if knot.stroke == 0 or i < n0:
			back.append(kp[i])
		else:
			if front.is_empty():
				front.append(kp[n0 - 1])
			front.append(kp[i])
	rope_back.points = back
	rope_front.points = front
	# the strands slide toward the end as the rope is hauled through the ring
	var back_len := KnotPath._length(back)
	RopeLine.set_phase(rope_back, -_drawn_vis)
	RopeLine.set_phase(rope_front, back_len - _drawn_vis)
	var all := PackedVector2Array(back)
	all.append_array(front)
	var sh := PackedVector2Array()
	for q in all:
		sh.append(q + Vector2(10, 14))
	rope_shadow.points = sh
	# The guide: the rest of the current stroke, dashed, with an arrow at its end and Pelageya's word for it.
	var g := knot.guide_points()
	guide.points = g
	guide_arrow.polygon = PackedVector2Array()
	if g.size() >= 2:
		var tip := g[g.size() - 1]
		var d := (tip - g[g.size() - 2]).normalized()
		var nrm := Vector2(-d.y, d.x)
		guide_arrow.polygon = PackedVector2Array([tip + d * 18.0, tip - d * 10.0 + nrm * 14.0, tip - d * 10.0 - nrm * 14.0])
		var labels: Array = spec.get("knot_path", {}).get("labels", [])
		if knot.stroke < labels.size():
			stroke_label.text = StoryData.text(String(labels[knot.stroke]))
			stroke_label.position = tip + Vector2(30, -20)


## The lead-in from the boat to where the knot begins: sagging (`_sag`, springy) and bowing with the current.
func _lead_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 14
	var nrm := (b - a).orthogonal().normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var bow := sin(_t * 0.85) * 11.0 + sin(_t * 2.1 + 1.3) * 4.0
	for i in n + 1:
		var u := float(i) / n
		var hump := 4.0 * u * (1.0 - u)
		var ripple := sin(TAU * u * 1.5 - _t * 2.4) * 3.0 * sin(PI * u)
		out.append(a.lerp(b, u) + Vector2(0, _sag * hump) + nrm * (bow * sin(PI * u) + ripple))
	return out


## The last stretch of the drawn rope bends toward the hand: the end by the whole offset, less and less back
## along the rope over `reach` px.
func _bend_to_hand(kp: PackedVector2Array) -> PackedVector2Array:
	if kp.size() < 2 or _hand_vis.length() < 0.3:
		return kp
	var out := PackedVector2Array(kp)
	var reach := 190.0
	var d := 0.0
	out[out.size() - 1] = kp[kp.size() - 1] + _hand_vis
	for i in range(kp.size() - 2, -1, -1):
		d += kp[i].distance_to(kp[i + 1])
		if d >= reach:
			break
		var w := 1.0 - d / reach
		out[i] = kp[i] + _hand_vis * w * w * (3.0 - 2.0 * w)
	# a long last segment: put a point in its middle so it bends, not swings straight
	var a := out[out.size() - 2]
	var b := out[out.size() - 1]
	if a.distance_to(b) > 40.0:
		var mid := kp[kp.size() - 2].lerp(kp[kp.size() - 1], 0.5) + _hand_vis * 0.6
		out.insert(out.size() - 1, mid)
	return out


func _live(delta: float) -> void:
	_t += delta
	var total := 0.0
	for l in knot.lengths:
		total += l
	var drawn := 0.0
	for i in mini(knot.stroke, knot.lengths.size()):
		drawn += knot.lengths[i]
	if not knot.done():
		drawn += knot.progress
	var pulled := clampf(drawn / maxf(total, 1.0), 0.0, 1.0)
	var target := lerpf(48.0, 14.0, pulled)
	_sag_v += (60.0 * (target - _sag) - 5.5 * _sag_v) * delta
	_sag += _sag_v * delta
	_drawn_vis = lerpf(_drawn_vis, drawn, 1.0 - exp(-12.0 * delta))
	var want := Vector2(sin(_t * 1.3) * 3.0, cos(_t * 0.9) * 2.0)   # lying by the ring, the end stirs a little
	if knot.grabbed:
		var off := _drag_pos - knot.end_point()
		want = off.limit_length(knot.tolerance * 0.8)
	_hand_vis = _hand_vis.lerp(want, 1.0 - exp(-14.0 * delta))


func tick(delta: float) -> void:
	if knot != null and rope_back.visible:
		_live(delta)
	if _jump_t >= 0.0:
		_jump_t += delta
		if _jump_t >= 0.6:
			_jump_t = -1.0
		_place_skoba()
	if _slip_t >= 0.0:
		_slip_t += delta
		if _slip_t >= 0.3:
			_slip_t = -1.0
	if knot != null and rope_back.visible:
		_draw_rope()
	if tied_t >= 0.0:
		tied_t += delta
		var x := clampf(tied_t / 0.6, 0.0, 1.0)
		rope_art.visible = true
		rope_art.modulate.a = x
		for n in [rope_back, rope_front, rope_shadow, ring_front]:
			n.modulate.a = 1.0 - x
		if tied_t >= 0.6 and not tied():
			event("tied")
			_refresh()


func probe() -> Dictionary:
	var strokes: Array = []
	for s in knot.strokes:
		var pts: Array = []
		for q in s:
			pts.append({"x": q.x, "y": q.y})
		strokes.append(pts)
	var e := knot.end_point()
	var nxt: Array = []
	for q in knot.guide_points():
		nxt.append({"x": q.x, "y": q.y})
	var kstate := "done" if (knot.done() or tied()) else ("grabbed" if knot.grabbed else ("slipping" if _slip_t >= 0.0 else "free"))
	var sk := center_of(skoba_hit)
	return {"knot_path": {"open": knot_stage(), "loops_done": knot.stroke, "loops_total": knot.strokes.size(), "state": kstate,
			"end": {"x": e.x, "y": e.y}, "next": nxt, "strokes": strokes, "tolerance": knot.tolerance, "grab_r": knot.grab_r,
			"how": "press on end, drag through next (then the following strokes) without releasing"},
		"strike": sk, "blows": blows, "braced": braced(), "skoba": center_of(skoba_hit), "skoba_visible": skoba.visible, "jumps": jumps,
		"timing": timing.probe() if timing.visible else {}, "ring": {"x": ring_c.x, "y": ring_c.y},
		"free_click": {"x": 1500.0, "y": 300.0}, "strikes_by_click": strikes_by_click,
		"rope_end": {"x": e.x, "y": e.y}, "knot_stage": knot_stage(), "stroke": knot.stroke, "strokes": strokes,
		"slips": slips, "rope_on_ring": tied(), "rope_tied_visible": rope_art.visible,
		"rope_textured": rope_back.texture != null}
