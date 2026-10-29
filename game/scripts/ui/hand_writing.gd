class_name HandWriting
extends Label
## Words written by hand (H8, H31, H45, H6 — Director 24.10: «рукописнее и неровнее», «текст смещён, не рукописный»,
## «шрифт топорно искусственный, а должна быть ручная неровная роспись»): the handwriting face (Bad Script) drawn
## letter by letter — each letter a little off the line, a little turned, a touch larger or smaller; every line
## drifts up or down along its length, starts a little in or out; the pen's ink fades through a word and is fresh at
## the next. Lines sit on the page's ruling when `line_pitch` / `first_baseline` are given (the journal's lines).
## Stays a Label (text, font and size live where the tests and the probe look); its own glyphs are invisible —
## `_draw` writes the letters. One seed per sheet: the same page looks the same every time it is opened.
##
## Data (a paper / writing block): "font": "hand" turns it on; "ink"; optional "line_pitch" and "first_baseline"
## (px of the block, before scaling), "hand_jitter" (1 — normal), "hand_slant_deg" (extra lean, default 0),
## "carved" — cut with a knife into wood (Р14, J: the signal board): the ink is the groove's shadow, each letter with a
## pale lit lower edge, no fading of the ink through a word.

var ink: Color = Color(0.17, 0.13, 0.09)
var line_pitch: float = 0.0       # 0 — by the font (1.18 × its height)
var first_baseline: float = 0.0   # 0 — the font's ascent (or centred vertically, as the Label's alignment says)
var jitter: float = 1.0
var slant_deg: float = 0.0
var seed_value: int = 0
var center_lines: bool = false
var carved: bool = false

var _lines: Array = []            # [{"words": [String], "w": float}]


## Turns a Label-like block into handwriting: the hand font at `size`, the ink, the ruling (scaled by `k`).
func setup(p: Dictionary, size_px: int, k: float = 1.0) -> void:
	add_theme_font_override("font", UiTheme.font("hand"))
	add_theme_font_size_override("font_size", size_px)
	add_theme_color_override("font_color", Color(0, 0, 0, 0))   # the Label's own glyphs stay unseen
	if p.has("ink"):
		ink = Color.html(String(p["ink"]))
	line_pitch = float(p.get("line_pitch", 0.0)) * k
	first_baseline = float(p.get("first_baseline", 0.0)) * k
	jitter = float(p.get("hand_jitter", 1.0))
	slant_deg = float(p.get("hand_slant_deg", 0.0))
	carved = bool(p.get("carved", false))
	seed_value = hash(text)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _font() -> Font:
	return get_theme_font("font")


func _fs() -> int:
	return get_theme_font_size("font_size")


func _wrap() -> void:
	_lines.clear()
	var f := _font()
	var fs := _fs()
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	for para in text.split("\n"):
		var words := String(para).split(" ", false)
		var cur: Array = []
		var w := 0.0
		for word in words:
			var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if not cur.is_empty() and w + space + ww > size.x * 0.97:
				_lines.append({"words": cur, "w": w})
				cur = []
				w = 0.0
			w += (space if not cur.is_empty() else 0.0) + ww
			cur.append(word)
		_lines.append({"words": cur, "w": w})


## Line count after wrapping (tests: the journal's lines fit its ruling).
func line_total() -> int:
	_wrap()
	return _lines.size()


## Baseline y of line i (block px).
func baseline_of(i: int) -> float:
	var f := _font()
	var fs := _fs()
	var pitch := line_pitch if line_pitch > 0.0 else f.get_height(fs) * 1.18
	var first := first_baseline
	if first <= 0.0:
		first = f.get_ascent(fs)
		if vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
			first += maxf(0.0, (size.y - pitch * (_lines.size() - 1) - f.get_height(fs)) * 0.5)
	return first + pitch * i


func _draw() -> void:
	_wrap()
	var f := _font()
	var fs := _fs()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var amp := jitter * fs / 28.0
	var lean := deg_to_rad(slant_deg)
	for i in _lines.size():
		var ln: Dictionary = _lines[i]
		var y := baseline_of(i)
		var x := rng.randf_range(-2.0, 5.0) * amp
		if center_lines or horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			x += (size.x - float(ln["w"])) * 0.5
		var drift := rng.randf_range(-0.012, 0.012) * jitter   # the line runs up or down a little
		var wave_ph := rng.randf() * TAU
		for word in ln["words"]:
			var a0 := rng.randf_range(0.86, 1.0)    # fresh ink at the word's start, a little fainter by its end
			var n := String(word).length()
			for ci in n:
				var ch := String(word)[ci]
				var adv := f.get_char_size(ch.unicode_at(0), fs).x
				var dy := sin(x * 0.045 + wave_ph) * 1.1 * amp + rng.randf_range(-0.9, 0.9) * amp + x * drift
				var rot := lean + rng.randf_range(-0.045, 0.045) * jitter
				var sc := 1.0 + rng.randf_range(-0.045, 0.05) * jitter
				var col := Color(ink, ink.a * a0 * (1.0 - 0.14 * float(ci) / maxf(1.0, float(n))))
				draw_set_transform(Vector2(x, y + dy), rot, Vector2(sc, sc))
				if carved:
					# a knife cut: the lit far edge of the groove, then the groove itself, the same depth all along
					draw_char(f, Vector2(maxf(1.0, fs * 0.04), maxf(1.4, fs * 0.055)), ch, fs, Color(1.0, 0.9, 0.74, 0.30))
					col = Color(ink, ink.a * 0.92)
				draw_char(f, Vector2.ZERO, ch, fs, col)
				x += adv * sc * rng.randf_range(0.98, 1.03)
			x += space * rng.randf_range(0.85, 1.25)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
