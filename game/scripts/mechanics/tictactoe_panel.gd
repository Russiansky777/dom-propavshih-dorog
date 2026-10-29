extends MechanicPanel
## Крестики-нолики с Ульяной (партия J, часть G; Директор 25.10 и 29.10: «мелом, рукой, каждый знак по-своему»).
## A slate of the class board in the game's carved frame; the grid is chalked in first, by hand — four uneven lines.
## Agata's crosses (a click on a free cell, or the keys 1…9) and Ulyana's noughts are each drawn stroke by stroke,
## never twice the same: the length, the slant, a little overshoot, a loop that does not quite close. Ulyana is eight:
## she plays well, not perfectly (`skill` — the share of her moves that are the best; the rest are any free cell),
## and she thinks a moment before her move. A line of three is crossed out in chalk. Then a word from her (texts
## win / lose / draw), and «Ещё раз» (who starts goes to the other) or «Хватит» (event "done"). Events: "won", "lost",
## "draw" (data `events`) after each game. Everything is data: the spec's `skill`, `think_s`, `texts`, `events`.

const LINES := [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
const CHALK := Color(0.93, 0.93, 0.88, 0.92)
const SLATE := Color(0.13, 0.17, 0.15)

var board: Array = []            # 9 cells: "" | "x" | "o"
var marks: Array = []            # [{cell, kind, strokes: [[Vector2…]], t0}] — drawn as they come
var grid_strokes: Array = []     # the chalked grid
var grid_t0: float = 0.0
var win_line: Array = []         # [a, b] screen points of the crossing-out stroke
var win_t0: float = -1.0
var turn: String = "x"
var agata_starts: bool = true
var over: bool = false
var result: String = ""          # "won" | "lost" | "draw"
var games: int = 0
var wins: int = 0
var losses: int = 0
var draws: int = 0
var skill: float = 0.7
var think_s: float = 0.8
var _think: float = -1.0
var _rng := RandomNumberGenerator.new()
var _slate: Rect2 = Rect2(560, 150, 800, 760)
var _cell: Rect2 = Rect2(660, 230, 600, 600)
var _draw: Control = null
var hint: Label = null
var again_btn: Button = null
var stop_btn: Button = null


func build() -> void:
	_rng.seed = int(spec.get("seed", Time.get_ticks_usec()))
	skill = clampf(float(spec.get("skill", 0.7)), 0.0, 1.0)
	think_s = float(spec.get("think_s", 0.8))
	var sr: Array = spec.get("slate", [560, 150, 800, 760])
	_slate = Rect2(float(sr[0]), float(sr[1]), float(sr[2]), float(sr[3]))
	var side := minf(_slate.size.x, _slate.size.y) - 160.0
	_cell = Rect2(_slate.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	_draw = Control.new()
	_draw.name = "Slate"
	_draw.size = Vector2(1920, 1080)
	_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw.draw.connect(_on_draw)
	_draw.gui_input.connect(_on_slate_input)
	add_child(_draw)
	hint = label(text("hint"), Vector2(_slate.position.x, _slate.end.y + 24.0), _slate.size.x, &"CloseupLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	again_btn = _button(text("again"), Vector2(_slate.get_center().x - 230.0, _slate.end.y + 70.0), "Again")
	again_btn.pressed.connect(_new_game)
	stop_btn = _button(text("stop"), Vector2(_slate.get_center().x + 30.0, _slate.end.y + 70.0), "Stop")
	stop_btn.pressed.connect(func(): event("done"))
	_new_game()


func _button(t: String, at: Vector2, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = t
	b.theme = UiTheme.get_theme()
	b.position = at
	b.size = Vector2(200, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	add_child(b)
	return b


func _new_game() -> void:
	board = ["", "", "", "", "", "", "", "", ""]
	marks.clear()
	win_line = []
	win_t0 = -1.0
	over = false
	result = ""
	grid_strokes = _grid()
	grid_t0 = clock
	turn = "x" if agata_starts else "o"
	_think = think_s + 1.0 if turn == "o" else -1.0   # the grid first, then her move
	again_btn.visible = false
	stop_btn.visible = false
	hint.text = text("hint") if turn == "x" else text("her_first")
	_draw.queue_redraw()


## Four chalk lines across the slate: each a little crooked, a little longer or shorter than the grid.
func _grid() -> Array:
	var out: Array = []
	var s := _cell.size.x / 3.0
	for i in [1, 2]:
		var x: float = _cell.position.x + s * i + _rng.randf_range(-6.0, 6.0)
		out.append(_stroke(Vector2(x + _rng.randf_range(-5, 5), _cell.position.y - _rng.randf_range(4, 22)),
				Vector2(x + _rng.randf_range(-8, 8), _cell.end.y + _rng.randf_range(4, 22)), 3.0))
	for i in [1, 2]:
		var y: float = _cell.position.y + s * i + _rng.randf_range(-6.0, 6.0)
		out.append(_stroke(Vector2(_cell.position.x - _rng.randf_range(4, 22), y + _rng.randf_range(-5, 5)),
				Vector2(_cell.end.x + _rng.randf_range(4, 22), y + _rng.randf_range(-8, 8)), 3.0))
	return out


## A hand-drawn chalk stroke from a to b: a slight bow and a tremor along it.
func _stroke(a: Vector2, b: Vector2, tremor: float = 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 14
	var bow := _rng.randf_range(-0.05, 0.05) * a.distance_to(b)
	var nrm := (b - a).normalized().orthogonal()
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t) + nrm * (sin(t * PI) * bow + _rng.randf_range(-1.0, 1.0) * tremor * 0.35)
		pts.append(p)
	return pts


func _cell_rect(i: int) -> Rect2:
	var s := _cell.size.x / 3.0
	return Rect2(_cell.position + Vector2(float(i % 3), floorf(i / 3.0)) * s, Vector2(s, s))


## A cross, Agata's: two strokes, each its own length and slant, the second may overshoot.
func _cross(i: int) -> Array:
	var r := _cell_rect(i).grow(-_cell.size.x / 3.0 * _rng.randf_range(0.2, 0.28))
	var j := r.size.x * 0.08
	var a1 := r.position + Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))
	var b1 := r.end + Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))
	var a2 := Vector2(r.end.x, r.position.y) + Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))
	var b2 := Vector2(r.position.x, r.end.y) + Vector2(_rng.randf_range(-j, j * 1.6), _rng.randf_range(-j, j * 1.6))
	return [_stroke(a1, b1, 3.0), _stroke(a2, b2, 3.0)]


## A nought, Ulyana's: one loop, a little egg-shaped and leaning, its end running past or short of its start.
func _nought(i: int) -> Array:
	var r := _cell_rect(i)
	var c := r.get_center() + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	var rx := r.size.x * _rng.randf_range(0.26, 0.33)
	var ry := r.size.y * _rng.randf_range(0.27, 0.35)
	var lean := _rng.randf_range(-0.35, 0.35)
	var start := _rng.randf_range(-PI, PI)
	var sweep := TAU * _rng.randf_range(0.93, 1.08)
	var pts := PackedVector2Array()
	var n := 40
	for k in n + 1:
		var t := start - sweep * float(k) / n   # anticlockwise, as children write
		var wob := 1.0 + 0.05 * sin(t * 3.0 + start) + _rng.randf_range(-0.012, 0.012)
		var p := Vector2(cos(t) * rx, sin(t) * ry) * wob
		pts.append(c + p.rotated(lean))
	return [pts]


func _place(i: int, kind: String) -> void:
	board[i] = kind
	marks.append({"cell": i, "kind": kind, "strokes": _cross(i) if kind == "x" else _nought(i), "t0": clock})
	if String(spec.get("sound_chalk", "")) != "":
		sound(String(spec["sound_chalk"]))
	var w := _winner(board)
	if w != "":
		var ln: Array = _line_of(board)
		var a := _cell_rect(ln[0]).get_center()
		var b := _cell_rect(ln[2]).get_center()
		var d := (b - a).normalized()
		win_line = [_stroke(a - d * 40.0, b + d * 40.0, 3.0)]
		win_t0 = clock + 0.35
		_finish("won" if w == "x" else "lost")
	elif not board.has(""):
		_finish("draw")
	else:
		turn = "o" if kind == "x" else "x"
		if turn == "o":
			_think = think_s * _rng.randf_range(0.8, 1.4)
			hint.text = text("her_turn")
		else:
			hint.text = text("hint")
	_draw.queue_redraw()


func _finish(r: String) -> void:
	over = true
	result = r
	games += 1
	match r:
		"won":
			wins += 1
		"lost":
			losses += 1
		_:
			draws += 1
	agata_starts = not agata_starts
	hint.text = ""
	var key: String = String({"won": "win", "lost": "lose", "draw": "draw"}[r])
	get_tree().create_timer(0.9, false).timeout.connect(func():
		if not is_instance_valid(self):
			return
		event(r)
		say(key)
		again_btn.visible = true
		stop_btn.visible = true)


static func _winner(b: Array) -> String:
	for l in LINES:
		if b[l[0]] != "" and b[l[0]] == b[l[1]] and b[l[1]] == b[l[2]]:
			return String(b[l[0]])
	return ""


static func _line_of(b: Array) -> Array:
	for l in LINES:
		if b[l[0]] != "" and b[l[0]] == b[l[1]] and b[l[1]] == b[l[2]]:
			return l
	return []


## The best move for `who` (minimax, the whole tree is small).
static func best_move(b: Array, who: String) -> int:
	var best := -1
	var best_v := -99
	for i in 9:
		if b[i] != "":
			continue
		b[i] = who
		var v := -_negamax(b, "x" if who == "o" else "o")
		b[i] = ""
		if v > best_v:
			best_v = v
			best = i
	return best


static func _negamax(b: Array, who: String) -> int:
	var w := _winner(b)
	if w != "":
		return 1 if w == who else -1
	if not b.has(""):
		return 0
	var best := -99
	for i in 9:
		if b[i] != "":
			continue
		b[i] = who
		best = maxi(best, -_negamax(b, "x" if who == "o" else "o"))
		b[i] = ""
	return best


func _her_move() -> int:
	var free: Array = []
	for i in 9:
		if board[i] == "":
			free.append(i)
	if free.is_empty():
		return -1
	if _rng.randf() < skill:
		return best_move(board.duplicate(), "o")
	# a child's move: still takes a win in one, and mostly blocks a line of two
	for who in ["o", "x"]:
		for i in free:
			var b2: Array = board.duplicate()
			b2[i] = who
			if _winner(b2) == who and (who == "o" or _rng.randf() < 0.6):
				return i
	return int(free[_rng.randi() % free.size()])


func tick(delta: float) -> void:
	if not over and turn == "o" and _think >= 0.0:
		_think -= delta
		if _think < 0.0:
			var m := _her_move()
			if m >= 0:
				_place(m, "o")
	_draw.queue_redraw()


func _on_slate_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_draw.accept_event()
		click_at(ev.position)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
		play_cell(int(ev.keycode - KEY_1))


## Agata's cross in the cell under `at` (screen px) — if it is her turn and the cell is free.
func click_at(at: Vector2) -> bool:
	for i in 9:
		if _cell_rect(i).has_point(at):
			return play_cell(i)
	return false


func play_cell(i: int) -> bool:
	if over or turn != "x" or i < 0 or i > 8 or board[i] != "" or clock - grid_t0 < 0.6:
		return false
	_place(i, "x")
	return true


# --- Drawing ------------------------------------------------------------------------------------

func _on_draw() -> void:
	var c := _draw
	var outer := _slate
	CarvedFrame.draw_frame(c, outer, 16.0)
	c.draw_rect(outer, SLATE)
	# the slate: a little uneven, old chalk wiped off in clouds
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for k in 26:
		var p := outer.position + Vector2(rng.randf() * outer.size.x, rng.randf() * outer.size.y)
		c.draw_set_transform(p, rng.randf_range(-0.6, 0.6), Vector2(1.0, rng.randf_range(0.3, 0.7)))
		c.draw_circle(Vector2.ZERO, rng.randf_range(30.0, 110.0), Color(0.85, 0.88, 0.84, rng.randf_range(0.015, 0.04)))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the grid, drawn in by hand over the first half second
	var gt := clampf((clock - grid_t0) / 0.6, 0.0, 1.0) * grid_strokes.size()
	for k in grid_strokes.size():
		_chalk(c, grid_strokes[k], clampf(gt - k, 0.0, 1.0), 5.0)
	for m in marks:
		var strokes: Array = m["strokes"]
		var per := 0.18 if m["kind"] == "x" else 0.32
		var mt := (clock - float(m["t0"])) / per
		for k in strokes.size():
			_chalk(c, strokes[k], clampf(mt - k, 0.0, 1.0), 6.0)
	if not win_line.is_empty() and clock >= win_t0:
		_chalk(c, win_line[0], clampf((clock - win_t0) / 0.35, 0.0, 1.0), 6.0)
	CarvedFrame.shade(c, outer, false)


## A chalk stroke drawn up to `frac` of its length: a soft wide dust under a firm core, broken here and there.
func _chalk(c: CanvasItem, pts: PackedVector2Array, frac: float, w: float) -> void:
	if frac <= 0.0 or pts.size() < 2:
		return
	var n := int(ceil(frac * (pts.size() - 1)))
	var part := PackedVector2Array()
	for i in n + 1:
		part.append(pts[mini(i, pts.size() - 1)])
	if frac < 1.0:
		var last := frac * (pts.size() - 1)
		var i0 := int(floor(last))
		part[part.size() - 1] = pts[i0].lerp(pts[mini(i0 + 1, pts.size() - 1)], last - i0)
	c.draw_polyline(part, Color(CHALK, 0.22), w * 2.2, true)
	c.draw_polyline(part, CHALK, w, true)
	for i in range(1, part.size(), 3):
		c.draw_circle(part[i] + Vector2(1.5, -1.0), w * 0.3, Color(SLATE, 0.5))   # the chalk skips on the board


func probe() -> Dictionary:
	var cells := {}
	for i in 9:
		var r := _cell_rect(i)
		cells[str(i)] = {"x": r.get_center().x, "y": r.get_center().y}
	return {"board": board.duplicate(), "turn": turn, "over": over, "result": result, "games": games, "wins": wins,
		"losses": losses, "draws": draws, "cells": cells, "marks": marks.size(),
		"again": again_btn.visible, "stop": stop_btn.visible}
