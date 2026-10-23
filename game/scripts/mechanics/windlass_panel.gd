extends MechanicPanel
## M25, the first span (Z3, day four): the turn of the shore with Ilya's windlass; the first log hangs on its rope with
## the far end over the water. Agata calls the mill signals from Pelageya's board (three plaques at the left: «Пускай»,
## «Стой», «Подымай» — clicks); Ilya answers aloud and turns the windlass. The log turns about its shore end (on the
## crib) — `pivot` — and goes down onto the ring of the near pier's old plate: stopped at the ring it settles (event
## "laid" → span_first_laid, the close-up closes and the scene goes on); let down past it — it knocks on the stone,
## Ilya waits for «Подымай» (WindlassLogic). Everything with the mouse.
## G46 (Director 23.10: «ничего не происходит ни в какой позиции, и не понятно, что и куда нужно»): the target is
## shown twice — a soft chalk glow on the ring of the plate where the far end must lie (`ring`: the far end of the
## log at angle 0, canvas px; it brightens while the log is in the zone), and a gauge of the log's height beside the
## board with the green band «у кольца» (the same colours as the «точный удар» bar) — exactly logic.rest ± tolerance;
## after a bump «Подымай» glows and Ilya's answer says it. The log swings `max_deg` (22°: a readable motion that keeps
## the far end in the frame).
## Art: tools/make_span_layers.py — beam_waiting.png (G47/G48: the turn of day four with the batch-9 site — the stack, the
## windlass, the crib — without the log) and beam.png (only the log, Z3_state_span_beam_day4, in its own canvas place, so
## angle 0 is exactly the delivered picture); `rope_from` — the drum, the rope to the log's far end is drawn here. `overlays` — figures composited by
## tools/make_frame_layers.py (Pelageya with her board, Agata, Ilya at the windlass — the same as the frame F_span
## under the close-up, G42: nobody vanishes when it opens) drawn over the log. Coordinates in canvas px (1672×941).

const GAUGE_RECT := Rect2(372, 652, 36, 248)

var logic: WindlassLogic = null
var beam: TextureRect = null
var rope: Line2D = null
var plaques: Dictionary = {}       # signal → Button
var ring_mark: RingMark = null
var gauge: HeightGauge = null
var raise_glow: ColorRect = null
var hint_label: Label = null
var call_label: Label = null
var reply_label: Label = null
var signals_seen: Array[String] = []
var laid_sent: bool = false
var bump_voice: String = ""        # G50: what VoiceDirector answered to Ilya's recorded «Стукнулось о камень!» (tests)
var _bump_line: String = ""
var _call_t: float = -10.0
var _k: float = 1920.0 / 1672.0


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	crop(String(art.get("waiting", "")), full, Vector2.ZERO, _k).name = "Waiting"
	beam = crop(String(art.get("beam", "")), full, Vector2.ZERO, _k)
	beam.name = "Beam"
	beam.pivot_offset = v2(spec.get("pivot", [1240, 575])) * _k
	# G47: the rope from the windlass drum to the far end of the log (not painted in the batch-9 site — the game draws it).
	if spec.has("rope_from"):
		rope = RopeLine.make(float(spec.get("rope_width", 6.0)), "WindlassRope")
		add_child(rope)
	# The chalk mark on the ring of the plate, over the log (a faint ring and a glow): the far end comes into it.
	ring_mark = RingMark.new()
	ring_mark.name = "RingMark"
	ring_mark.size = Vector2(1920, 1080)
	ring_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_mark.at = v2(spec.get("ring", [1000, 446])) * _k
	ring_mark.radius = float(spec.get("ring_r", 26.0)) * _k
	add_child(ring_mark)
	for o in spec.get("overlays", []):
		crop(String(o), full, Vector2.ZERO, _k).name = "Figure_" + String(o).get_file().get_basename()
	logic = WindlassLogic.new(spec.get("logic", {}))
	logic.ease(TimingBar.slow_k(), TimingBar.green_k())   # «Облегчить мини-игры» (G3): slower log, wider ring zone
	logic.event.connect(_on_logic_event)
	if flag(String(spec.get("done_flag", "span_first_laid"))):
		logic.pos = logic.rest
		logic.state = "solved"
		laid_sent = true
	# Pelageya's signal board: three plaques and the gauge of the log's height.
	var board := ColorRect.new()
	board.name = "SignalBoard"
	board.color = Color(0.22, 0.15, 0.09, 0.88)
	board.position = Vector2(40, 600)
	board.size = Vector2(490, 330)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	label(text("label_board"), Vector2(56, 612), 300)
	raise_glow = ColorRect.new()
	raise_glow.name = "RaiseGlow"
	raise_glow.color = Color(0.98, 0.8, 0.4, 0.0)
	raise_glow.position = Vector2(60, 828)
	raise_glow.size = Vector2(290, 88)
	raise_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raise_glow.visible = false
	add_child(raise_glow)
	var y := 670.0
	for sig in ["lower", "stop", "raise"]:
		var b := Button.new()
		b.name = "Signal_" + sig
		b.text = text("signal_" + sig)
		b.position = Vector2(70, y)
		b.size = Vector2(270, 68)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 32)
		b.pressed.connect(signal_pressed.bind(sig))
		add_child(b)
		plaques[sig] = b
		y += 84.0
	gauge = HeightGauge.new()
	gauge.name = "Gauge"
	gauge.position = GAUGE_RECT.position
	gauge.size = GAUGE_RECT.size
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.zone = logic.zone()
	add_child(gauge)
	var zl := label(text("label_gauge"), Vector2(GAUGE_RECT.end.x + 8, GAUGE_RECT.position.y + gauge.y_of(logic.rest) - 16), 110)
	zl.name = "GaugeZoneLabel"
	zl.add_theme_font_size_override("font_size", 20)
	zl.add_theme_color_override("font_color", TimingBar.GREEN.lightened(0.45))
	var sl := label(text("label_stone"), Vector2(GAUGE_RECT.end.x + 8, GAUGE_RECT.position.y + gauge.y_of(logic.rest + logic.tolerance) + 2), 110)
	sl.name = "GaugeStoneLabel"
	sl.add_theme_font_size_override("font_size", 18)
	call_label = label("", v2(spec.get("call_pos", [850, 868])), 700, &"CloseupTitle")
	reply_label = label("", v2(spec.get("reply_pos", [700, 520])) * _k, 520, &"CloseupLabel")
	hint_label = label(text("label_hint"), v2(spec.get("hint_pos", [560, 948])), 1080)
	hint_label.name = "Hint"
	_redraw()


## Agata calls a signal (a plaque clicked): her call on screen, Ilya's answer, the windlass moves.
func signal_pressed(sig: String) -> void:
	if laid_sent or logic.solved() or dialogue_up():
		return
	signals_seen.append(sig)
	call_label.text = text("call_" + sig)
	_call_t = clock
	if logic.apply(sig):
		reply_label.text = text("reply_" + sig)
		sound("knock" if sig == "stop" else "shutter")
	elif logic.state == "bumped":
		reply_label.text = text("reply_bump")   # against the stone: Ilya says again what he waits for — «Подымай»
	else:
		reply_label.text = text("reply_wait")


func _on_logic_event(name: String) -> void:
	match name:
		"bumped":
			# Ilya's «Стукнулось о камень!… Подымай» goes into the reply line, not a modal box: a modal box swallowed the
			# next signals until it was clicked away (AI gate M3 item 15, 23.10) — the player saw buttons that did nothing.
			# It stays while the log is against the stone, and «Подымай» glows (G46).
			sound("hammer")
			reply_label.text = text("reply_bump")
			_call_t = clock
			_say_bump()
		"settling":
			sound("knock")
		"solved":
			if not laid_sent:
				laid_sent = true
				event("laid")


func tick(delta: float) -> void:
	if not dialogue_up():
		logic.step(delta)
	if clock - _call_t > 2.2 and logic.state != "bumped":
		call_label.text = ""
		reply_label.text = ""
	_redraw()


## The far end of the log on screen now: the ring point (the far end at angle 0) turned about the pivot.
func far_end() -> Vector2:
	var pv := v2(spec.get("pivot", [1240, 575])) * _k
	return pv + (ring_mark.at - pv).rotated(beam.rotation)


func _redraw() -> void:
	if beam == null:
		return
	var a := logic.angle(float(spec.get("max_deg", 9.0)))
	beam.rotation = deg_to_rad(a)
	if rope != null:
		rope.points = RopeLine.sag_points(v2(spec.get("rope_from", [990, 598])) * _k, far_end(), 5.0, 12)
	for sig in plaques:
		(plaques[sig] as Button).disabled = laid_sent
	var in_zone := logic.at_ring() and logic.state != "bumped"
	ring_mark.lit = 1.0 if (in_zone or logic.state in ["settling", "solved"]) else 0.0
	ring_mark.done = logic.state in ["settling", "solved"]
	ring_mark.t = clock
	ring_mark.queue_redraw()
	gauge.pos = logic.pos
	gauge.in_zone = in_zone or logic.state in ["settling", "solved"]
	gauge.bumped = logic.state == "bumped"
	gauge.queue_redraw()
	var bumped := logic.state == "bumped" and not laid_sent
	raise_glow.visible = bumped
	if bumped:
		raise_glow.color.a = 0.45 + 0.35 * sin(clock * 5.0)
	(plaques["raise"] as Button).modulate = Color(1.25, 1.12, 0.85) if bumped else Color.WHITE


## G50 (Director 23.10: «озвучена, но звучит только надписью»): Ilya's recorded line plays when the log knocks
## against the stone — kind "puzzle" (ducks the music like a close-up's message); the reply line keeps its text.
func _say_bump() -> void:
	var key := String(spec.get("texts", {}).get("bump", ""))
	var ln: Dictionary = StoryData.text_line(key)
	if ln.is_empty():
		bump_voice = "no_line"
		return
	_bump_line = "%s:%s" % [String(ln["speaker"]), StoryRunner.text_key_of(key)]
	bump_voice = VoiceDirector.play_line(_bump_line, String(ln["speaker"]), String(ln["text"]), "puzzle")


func closing() -> void:
	if _bump_line != "" and VoiceDirector.current_line == _bump_line and VoiceDirector.is_playing():
		VoiceDirector.stop("closed")


func probe() -> Dictionary:
	var out := {"state": logic.state, "bump_voice": bump_voice, "bump_line": _bump_line, "pos": logic.pos, "rest": logic.rest, "tolerance": logic.tolerance,
		"angle": rad_to_deg(beam.rotation) if beam != null else 0.0, "laid": laid_sent, "signals": signals_seen.duplicate(),
		"reply": reply_label.text if reply_label != null else "", "hint": hint_label.text if hint_label != null else "",
		"raise_highlight": raise_glow != null and raise_glow.visible}
	for sig in plaques:
		out["plaque_" + sig] = center_of(plaques[sig])
	if gauge != null:
		var o := gauge.global_position
		out["gauge"] = {"top": o.y, "bottom": o.y + gauge.size.y, "x": o.x + gauge.size.x / 2,
			"zone_top": o.y + gauge.y_of(logic.zone().x), "zone_bottom": o.y + gauge.y_of(logic.zone().y),
			"marker": o.y + gauge.y_of(logic.pos), "in_zone": gauge.in_zone}
	if ring_mark != null:
		var fe := far_end()
		out["ring_mark"] = {"x": ring_mark.at.x, "y": ring_mark.at.y, "r": ring_mark.radius, "lit": ring_mark.lit}
		out["far_end"] = {"x": fe.x, "y": fe.y}
	if rope != null and rope.points.size() >= 2:
		var r0 := rope.points[rope.points.size() - 1]
		out["rope"] = {"from": {"x": rope.points[0].x, "y": rope.points[0].y}, "to": {"x": r0.x, "y": r0.y}}
	var figs: Array[String] = []
	for c in get_children():
		if String(c.name).begins_with("Figure_") and (c as CanvasItem).visible:
			figs.append(String(c.name).trim_prefix("Figure_"))
	out["figures"] = figs
	return out


## The chalk mark on the ring of the old plate: a soft glow where the far end must lie; brighter (and a green ring
## round it) while the log is in the zone; it fades once the log has settled.
class RingMark extends Control:
	var at: Vector2 = Vector2.ZERO
	var radius: float = 30.0
	var lit: float = 0.0
	var done: bool = false
	var t: float = 0.0
	var _lit_shown: float = 0.0
	var _fade: float = 1.0

	func _draw() -> void:
		_lit_shown = lerpf(_lit_shown, lit, 0.25)
		_fade = maxf(_fade - 0.02, 0.0) if done else 1.0
		if _fade <= 0.0:
			return
		var pulse := 0.5 + 0.5 * sin(t * 3.2)
		var base := (0.32 + 0.18 * pulse + 0.45 * _lit_shown) * _fade
		var warm := Color(1.0, 0.93, 0.7)
		for i in 6:
			var k := 1.0 - float(i) / 6.0
			draw_circle(at, radius * (0.55 + 0.85 * k), Color(warm.r, warm.g, warm.b, base * 0.12 * (1.0 - k * 0.5)))
		# the chalk ring itself, a little squashed — it lies flat on the plate
		var pts := PackedVector2Array()
		for i in 33:
			var a := TAU * float(i) / 32.0
			pts.append(at + Vector2(cos(a) * radius, sin(a) * radius * 0.55))
		draw_polyline(pts, Color(1.0, 0.97, 0.88, minf(base * 1.5, 0.9)), 3.0, true)
		if _lit_shown > 0.05:
			draw_arc(at, radius * 1.45, 0.0, TAU, 40, Color(0.75, 1.0, 0.65, 0.55 * _lit_shown * _fade), 3.0, true)


## The log's height beside Pelageya's board: 0 (hoisted) at the top, the green band «у кольца» = rest ± tolerance, the
## stone below it; a brass marker is the far end of the log now.
class HeightGauge extends Control:
	var zone: Vector2 = Vector2(0.75, 0.89)
	var pos: float = 0.0
	var in_zone: bool = false
	var bumped: bool = false

	func y_of(p: float) -> float:
		return clampf(p, 0.0, 1.0) * size.y

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TimingBar.TRACK)
		var zt := y_of(zone.x)
		var zb := y_of(zone.y)
		draw_rect(Rect2(0, zb, size.x, size.y - zb), TimingBar.RED.darkened(0.25))
		draw_rect(Rect2(0, zt, size.x, zb - zt), TimingBar.GREEN.lightened(0.15) if in_zone else TimingBar.GREEN)
		draw_rect(Rect2(Vector2.ZERO, size), TimingBar.BRASS.darkened(0.45), false, 2.0)
		var my := y_of(pos)
		var col := TimingBar.BRASS if not bumped else Color(1.0, 0.55, 0.4)
		draw_rect(Rect2(-6, my - 3, size.x + 12, 6), col)
		draw_colored_polygon(PackedVector2Array([Vector2(-16, my - 9), Vector2(-4, my), Vector2(-16, my + 9)]), col)
