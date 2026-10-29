extends MechanicPanel
## Ритм с Тихоном (партия J, часть G; Директор 25.10: «ритм ложечкой с Тихоном»). Tikhon taps a little tune with his
## spoon on an empty cup; Agata answers with hers on her cup of tea — a click on the board or Space, as many taps,
## in the same rhythm. On the carved board two grooves: Tikhon's taps come up as brass studs as he plays, Agata's as
## chalk dots under them; after her last tap each of hers is marked right (gold) or off (red). The rhythm counts
## (the gaps between taps against his, `tol` of the gap — wider with «Облегчить»), not the speed she starts at.
## Rounds (`rounds` — offsets of the taps, s) grow longer; a miss — his grumble and the same round again; the last
## round answered — his word (`texts.done`) and event "done". «Хватит» (event "quit") puts it away at any time.

const STUD := Color(0.86, 0.68, 0.36)
const CHALK := Color(0.93, 0.93, 0.88, 0.95)
const OFF := Color(0.8, 0.3, 0.22)

var rounds: Array = []
var round_i: int = 0
var phase: String = "intro"      # intro | tikhon | agata | judged | done
var phase_t: float = 0.0
var played: Array = []           # Tikhon's taps sounded so far this round (offsets, s)
var taps: Array = []             # Agata's taps (clock, s)
var judged: Array = []           # per Agata's tap: true (in time) / false
var tol: float = 0.25
var misses: int = 0
var _board: Rect2 = Rect2(410, 300, 1100, 420)
var _draw: Control = null
var hint: Label = null
var stop_btn: Button = null


func build() -> void:
	rounds = spec.get("rounds", [[0.0, 0.5, 1.0], [0.0, 0.4, 0.8, 1.4], [0.0, 0.3, 0.6, 0.8, 1.4]])
	var easy := TimingBar.slow_k() > 1.0
	tol = float(spec.get("tol_easy", 0.36)) if easy else float(spec.get("tol", 0.25))
	var br: Array = spec.get("board", [410, 300, 1100, 420])
	_board = Rect2(float(br[0]), float(br[1]), float(br[2]), float(br[3]))
	_draw = Control.new()
	_draw.name = "Board"
	_draw.size = Vector2(1920, 1080)
	_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw.draw.connect(_on_draw)
	_draw.gui_input.connect(_on_board_input)
	add_child(_draw)
	hint = label("", Vector2(_board.position.x, _board.end.y + 28.0), _board.size.x, &"CloseupLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stop_btn = Button.new()
	stop_btn.name = "Stop"
	stop_btn.text = text("stop")
	stop_btn.theme = UiTheme.get_theme()
	stop_btn.size = Vector2(200, 54)
	stop_btn.position = Vector2(_board.get_center().x - 100.0, _board.end.y + 90.0)
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.pressed.connect(func(): event("quit"))
	add_child(stop_btn)
	_start_round(0, 1.2)


func _start_round(i: int, delay: float) -> void:
	round_i = clampi(i, 0, rounds.size() - 1)
	played.clear()
	taps.clear()
	judged.clear()
	phase = "intro"
	phase_t = -delay
	hint.text = text("listen")
	_draw.queue_redraw()


func _pattern() -> Array:
	return rounds[round_i]


func _span() -> float:
	var p := _pattern()
	return maxf(float(p[p.size() - 1]), 0.4)


func tick(delta: float) -> void:
	if dialogue_up():
		_draw.queue_redraw()
		return
	phase_t += delta
	match phase:
		"intro":
			if phase_t >= 0.0:
				phase = "tikhon"
				phase_t = 0.0
		"tikhon":
			var p := _pattern()
			while played.size() < p.size() and phase_t >= float(p[played.size()]):
				played.append(float(p[played.size()]))
				sound("spoon_tikhon")
			if played.size() == p.size() and phase_t >= _span() + 0.5:
				phase = "agata"
				phase_t = 0.0
				hint.text = text("repeat")
		"agata":
			# she has had time enough: a second and a half past the tune's length since her last tap (or the start)
			var since := phase_t - (float(taps[taps.size() - 1]) if not taps.is_empty() else 0.0)
			if (not taps.is_empty() and since > _span() * 0.6 + 1.2) or (taps.is_empty() and phase_t > 6.0):
				_judge()
		"judged":
			if phase_t >= 1.6:
				if _round_ok():
					if round_i + 1 >= rounds.size():
						phase = "done"
						hint.text = ""
						event("done")
					else:
						say("good_%d" % (round_i + 1))
						_start_round(round_i + 1, 0.8)
				else:
					misses += 1
					say("miss_%d" % (1 + (misses - 1) % 2))
					_start_round(round_i, 0.8)
	_draw.queue_redraw()


## Agata's tap (a click on the board, Space).
func tap() -> bool:
	if phase != "agata":
		return false
	taps.append(phase_t)
	sound("spoon_agata")
	if taps.size() >= _pattern().size():
		_judge()
	return true


func _judge() -> void:
	judged.clear()
	var p := _pattern()
	for i in taps.size():
		var ok := i < p.size()
		if ok and i > 0:
			var want := float(p[i]) - float(p[i - 1])
			var got := float(taps[i]) - float(taps[i - 1])
			ok = absf(got - want) <= maxf(want * tol, 0.07)
		judged.append(ok)
	phase = "judged"
	phase_t = 0.0
	hint.text = text("right") if _round_ok() else text("wrong")


func _round_ok() -> bool:
	return judged.size() == _pattern().size() and not judged.has(false)


func _on_board_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_draw.accept_event()
		tap()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		tap()


# --- Drawing ------------------------------------------------------------------------------------

func _on_draw() -> void:
	var c := _draw
	CarvedFrame.draw_frame(c, _board, 18.0)
	c.draw_rect(_board, CarvedFrame.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1311
	for k in 40:   # the grain of the board
		var y := _board.position.y + rng.randf() * _board.size.y
		var x := _board.position.x + rng.randf() * _board.size.x * 0.7
		c.draw_line(Vector2(x, y), Vector2(x + rng.randf_range(120, 380), y + rng.randf_range(-3, 3)), Color(0, 0, 0, 0.13), 2.0, true)
	var font := UiTheme.font("head_bold")
	var left := _board.position.x + 190.0
	var right := _board.end.x - 70.0
	var span := _span() + 0.4
	var rows := [[_board.position.y + _board.size.y * 0.36, "who_tikhon"], [_board.position.y + _board.size.y * 0.72, "who_agata"]]
	for r in rows:
		var y := float(r[0])
		c.draw_line(Vector2(left - 20.0, y), Vector2(right + 20.0, y), CarvedFrame.WOOD_DARK, 10.0, true)   # the groove
		c.draw_line(Vector2(left - 20.0, y + 4.0), Vector2(right + 20.0, y + 4.0), Color(CarvedFrame.WOOD_LIGHT, 0.5), 1.5, true)
		if font != null:
			c.draw_string(font, Vector2(_board.position.x + 36.0, y + 9.0), text(String(r[1])), HORIZONTAL_ALIGNMENT_LEFT, 140, 26, CarvedFrame.GOLD)
	var p := _pattern()
	# where Tikhon's studs go (shown as he taps; the empty seats are not shown — it is by ear)
	for i in played.size():
		var x := left + (right - left) * float(played[i]) / span
		var y := float(rows[0][0])
		var fresh := clampf(1.0 - (phase_t - float(played[i])) * 3.0, 0.0, 1.0) if phase == "tikhon" else 0.0
		c.draw_circle(Vector2(x, y), 13.0 + 5.0 * fresh, Color(0, 0, 0, 0.45))
		c.draw_circle(Vector2(x, y), 11.0 + 5.0 * fresh, STUD)
		c.draw_circle(Vector2(x - 3.0, y - 3.0), 3.5, Color(1, 0.95, 0.8, 0.8))
	# Agata's chalk dots, placed from her first tap at the place of his first
	if not taps.is_empty():
		var t0 := float(taps[0])
		for i in taps.size():
			var x := left + (right - left) * (float(p[0]) + float(taps[i]) - t0) / span
			var y := float(rows[1][0])
			var col := CHALK
			if phase == "judged" and i < judged.size():
				col = STUD if judged[i] else OFF
			c.draw_circle(Vector2(x, y), 12.0, Color(col, 0.25))
			c.draw_circle(Vector2(x, y), 8.0, col)
	CarvedFrame.shade(c, _board, false)


func probe() -> Dictionary:
	return {"phase": phase, "round": round_i, "rounds": rounds.size(), "played": played.size(), "taps": taps.size(),
		"judged": judged.duplicate(), "ok": _round_ok(), "misses": misses, "tol": tol,
		"board": {"x": _board.get_center().x, "y": _board.get_center().y}}
