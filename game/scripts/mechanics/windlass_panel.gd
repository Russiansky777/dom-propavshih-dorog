extends MechanicPanel
## M25, the first span (Z3, day four): the turn of the shore with Ilya's windlass; the first log hangs on its rope with
## the far end over the water. Agata calls the mill signals from Pelageya's board (three plaques at the left: «Пускай»,
## «Стой», «Подымай» — clicks); Ilya answers aloud and turns the windlass. The log turns about its shore end (on the
## crib) — `pivot` — and goes down onto the ring of the near pier's old plate: stopped at the ring it settles (event
## "laid" → span_first_laid, the close-up closes and the scene goes on); let down past it — it knocks on the stone,
## Ilya waits for «Подымай» (WindlassLogic). Everything with the mouse.
## Art: tools/make_span_layers.py — beam_waiting.png (the scene of batch 5 without the log) and beam.png (only the
## log, in its own canvas place, so angle 0 is exactly the delivered picture). `overlays` — figures composited by
## tools/make_frame_layers.py (Ilya at the windlass) drawn over the log. Coordinates in canvas px (1672×941).

var logic: WindlassLogic = null
var beam: TextureRect = null
var plaques: Dictionary = {}       # signal → Button
var call_label: Label = null
var reply_label: Label = null
var signals_seen: Array[String] = []
var laid_sent: bool = false
var _call_t: float = -10.0
var _k: float = 1920.0 / 1672.0


func build() -> void:
	var art: Dictionary = spec.get("art", {})
	var full := [0, 0, 1672, 941]
	crop(String(art.get("waiting", "")), full, Vector2.ZERO, _k).name = "Waiting"
	beam = crop(String(art.get("beam", "")), full, Vector2.ZERO, _k)
	beam.name = "Beam"
	beam.pivot_offset = v2(spec.get("pivot", [1240, 575])) * _k
	for o in spec.get("overlays", []):
		crop(String(o), full, Vector2.ZERO, _k)
	logic = WindlassLogic.new(spec.get("logic", {}))
	logic.event.connect(_on_logic_event)
	if flag(String(spec.get("done_flag", "span_first_laid"))):
		logic.pos = logic.rest
		logic.state = "solved"
		laid_sent = true
	# Pelageya's signal board: three plaques.
	var board := ColorRect.new()
	board.name = "SignalBoard"
	board.color = Color(0.22, 0.15, 0.09, 0.88)
	board.position = Vector2(40, 600)
	board.size = Vector2(330, 330)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	label(text("label_board"), Vector2(56, 612), 300)
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
	call_label = label("", Vector2(420, 860), 700, &"CloseupTitle")
	reply_label = label("", v2(spec.get("reply_pos", [700, 520])) * _k, 520, &"CloseupLabel")
	label(text("label_hint"), Vector2(420, 930), 1000)
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
	else:
		reply_label.text = text("reply_wait")


func _on_logic_event(name: String) -> void:
	match name:
		"bumped":
			# Ilya's «Стукнулось о камень!…» goes into the reply line, not a modal box: a modal box swallowed the next
			# signals until it was clicked away (AI gate M3 item 15, 23.10) — the player saw buttons that did nothing.
			sound("hammer")
			reply_label.text = text("bump")
			_call_t = clock + 1.5
		"settling":
			sound("knock")
		"solved":
			if not laid_sent:
				laid_sent = true
				event("laid")


func tick(delta: float) -> void:
	if not dialogue_up():
		logic.step(delta)
	if clock - _call_t > 2.2:
		call_label.text = ""
		reply_label.text = ""
	_redraw()


func _redraw() -> void:
	if beam == null:
		return
	var a := logic.angle(float(spec.get("max_deg", 9.0)))
	beam.rotation = deg_to_rad(a)
	for sig in plaques:
		(plaques[sig] as Button).disabled = laid_sent


func probe() -> Dictionary:
	var out := {"state": logic.state, "pos": logic.pos, "rest": logic.rest, "tolerance": logic.tolerance,
		"angle": rad_to_deg(beam.rotation) if beam != null else 0.0, "laid": laid_sent, "signals": signals_seen.duplicate()}
	for sig in plaques:
		out["plaque_" + sig] = center_of(plaques[sig])
	return out
