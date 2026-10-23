class_name CarvedFrame
extends RefCounted
## The game's frame for bars and gauges (H34, Director 24.10: «все ползунки, бегунки и шкалы — вписать в стиль игры,
## хорошие рамки»): dark carved wood with a gold bead, as on the title menu's panel — a band of wood round the field,
## grooves cut across it, a thin gold line inside and out, a gold rosette in every corner. Static drawing on any
## CanvasItem (TimingBar, the windlass bar, the sluice gauge), so every mini-game gets the same frame from one place.
##
## `draw_rail` — a painted wooden rail with cut divisions (H30 «рейка уровня — красивее, не графично»): a plank with
## grain, worn paint, notches cut in and numbered, the water seen through a glassy band.

const WOOD := Color(0.27, 0.17, 0.095)
const WOOD_DARK := Color(0.085, 0.052, 0.03)
const WOOD_LIGHT := Color(0.47, 0.31, 0.17)
const GOLD := Color(0.93, 0.76, 0.45)
const GOLD_DIM := Color(0.62, 0.47, 0.25)
const SHADOW := Color(0, 0, 0, 0.5)


## A carved frame round `inner` (the field stays free for the owner). `band` — the wood's width.
static func draw_frame(ci: CanvasItem, inner: Rect2, band: float = 12.0) -> void:
	var outer := inner.grow(band)
	# A soft shadow under the frame.
	for i in 4:
		ci.draw_rect(outer.grow(2.0 + i * 2.5), Color(0, 0, 0, 0.11), false, 3.0)
	# The wood: three tones from the outer edge in, as a rounded moulding.
	ci.draw_rect(outer, WOOD_DARK)
	ci.draw_rect(outer.grow(-band * 0.18), WOOD)
	ci.draw_rect(Rect2(outer.position + Vector2(band * 0.18, band * 0.18), Vector2(outer.size.x - band * 0.36, band * 0.22)), WOOD_LIGHT)
	ci.draw_rect(inner.grow(band * 0.28), WOOD_DARK)
	# Grooves cut across the band, evenly, leaving the corners for the rosettes.
	var step := maxf(band * 1.6, 14.0)
	var x := outer.position.x + band * 2.0
	while x < outer.end.x - band * 2.0:
		_groove(ci, Vector2(x, outer.position.y + band * 0.25), Vector2(x, inner.position.y - band * 0.35))
		_groove(ci, Vector2(x, inner.end.y + band * 0.35), Vector2(x, outer.end.y - band * 0.25))
		x += step
	var y := outer.position.y + band * 2.0
	while y < outer.end.y - band * 2.0:
		_groove(ci, Vector2(outer.position.x + band * 0.25, y), Vector2(inner.position.x - band * 0.35, y))
		_groove(ci, Vector2(inner.end.x + band * 0.35, y), Vector2(outer.end.x - band * 0.25, y))
		y += step
	# The gold bead: outside and round the field.
	ci.draw_rect(outer.grow(-1.0), GOLD_DIM, false, 1.5)
	ci.draw_rect(inner.grow(band * 0.28), GOLD, false, 2.0)
	ci.draw_rect(inner.grow(band * 0.28 + 2.0), Color(GOLD_DIM, 0.6), false, 1.0)
	# Rosettes in the corners.
	var r := band * 0.8
	for c in [outer.position + Vector2(band, band) * 0.92, Vector2(outer.end.x, outer.position.y) + Vector2(-band, band) * 0.92,
			outer.end - Vector2(band, band) * 0.92, Vector2(outer.position.x, outer.end.y) + Vector2(band, -band) * 0.92]:
		rosette(ci, c, r)


## A small carved rosette: four gold petals round a dark eye.
static func rosette(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 1.5, SHADOW)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var d := Vector2.from_angle(a)
		var n := Vector2(-d.y, d.x)
		ci.draw_colored_polygon(PackedVector2Array([c, c + d * r * 0.55 + n * r * 0.42, c + d * r, c + d * r * 0.55 - n * r * 0.42]), GOLD)
	ci.draw_circle(c, r * 0.28, WOOD_DARK)
	ci.draw_circle(c, r * 0.14, GOLD_DIM)


## A leaf-shaped gold pointer (as the menu's hover leaf), tip at `tip`, pointing along `dir`.
static func leaf(ci: CanvasItem, tip: Vector2, dir: Vector2, length: float, col: Color = GOLD) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	var base := tip - d * length
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(base + d * length * t + n * sin(t * PI) * length * 0.32)
	for i in range(7, 0, -1):
		var t := float(i) / 8.0
		pts.append(base + d * length * t - n * sin(t * PI) * length * 0.32)
	ci.draw_colored_polygon(_offset(pts, Vector2(1.5, 2.0)), SHADOW)
	ci.draw_colored_polygon(pts, col)
	ci.draw_line(base, tip - d * length * 0.12, col.darkened(0.45), 1.5)


## Paint shading over a flat field: a light top edge and a darker bottom, so the colours read as enamel on wood.
static func shade(ci: CanvasItem, r: Rect2, vertical: bool = false) -> void:
	var bands := 8
	for i in bands:
		var t := float(i) / bands
		var a := 0.18 * (1.0 - t * 2.0)
		var col := Color(1, 0.95, 0.85, a) if a > 0.0 else Color(0, 0, 0, -a * 1.4)
		if vertical:
			ci.draw_rect(Rect2(r.position.x + r.size.x * t, r.position.y, r.size.x / bands + 0.5, r.size.y), col)
		else:
			ci.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t, r.size.x, r.size.y / bands + 0.5), col)


## A painted wooden rail (the gauge at the sluice): plank, grain, worn white paint, cut divisions every `div`
## of the height with numbers, `water` (0..1 from the bottom) seen as a dark glassy band.
static func draw_rail(ci: CanvasItem, r: Rect2, water: float, notches: Array, mark: float, font: Font = null) -> void:
	draw_frame(ci, r, 10.0)
	ci.draw_rect(r, Color(0.80, 0.74, 0.62))
	# Grain: long thin streaks of the wood through the worn paint.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4517
	for i in 22:
		var gx := r.position.x + rng.randf() * r.size.x
		var gy := r.position.y + rng.randf() * r.size.y * 0.8
		ci.draw_line(Vector2(gx, gy), Vector2(gx + rng.randf_range(-2, 2), gy + rng.randf_range(40, 160)), Color(0.45, 0.33, 0.2, 0.25), 1.0)
	# Divisions: a short cut every tenth, a long one every half, numbers in old style on the right.
	for k in range(1, 10):
		var y := r.end.y - r.size.y * k / 10.0
		var long := k % 5 == 0
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x * (0.55 if long else 0.32), y), Color(0.16, 0.1, 0.06, 0.9), 2.5 if long else 1.5)
		if font != null:
			ci.draw_string(font, Vector2(r.position.x + r.size.x * 0.62, y + 7), str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.2, 0.13, 0.08, 0.85))
	# The water: a glassy dark band from the bottom, a lighter rim at its surface.
	var h := r.size.y * clampf(water, 0.0, 1.0)
	if h > 0.5:
		var wr := Rect2(r.position.x, r.end.y - h, r.size.x, h)
		ci.draw_rect(wr, Color(0.14, 0.26, 0.34, 0.5))
		ci.draw_rect(Rect2(wr.position, Vector2(wr.size.x, minf(4.0, h))), Color(0.75, 0.86, 0.9, 0.7))
	# The step notches cut into the wood (dark wedges from the left edge).
	for lv in notches:
		var y := r.end.y - r.size.y * clampf(float(lv), 0.0, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, y - 5), Vector2(r.position.x + r.size.x * 0.5, y), Vector2(r.position.x, y + 5)]), Color(0.12, 0.07, 0.04))
	# The red mark: a painted band right across, with a gold leaf pointing at it from the side.
	var my := r.end.y - r.size.y * clampf(mark, 0.0, 1.0)
	ci.draw_rect(Rect2(r.position.x, my - 3.5, r.size.x, 7), Color(0.68, 0.12, 0.08))
	ci.draw_rect(Rect2(r.position.x, my - 3.5, r.size.x, 2), Color(0.9, 0.4, 0.3, 0.6))
	leaf(ci, Vector2(r.position.x - 12, my), Vector2.RIGHT, 30.0)
	shade(ci, r, true)


static func _groove(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	ci.draw_line(a, b, Color(0, 0, 0, 0.45), 2.0)
	ci.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), Color(WOOD_LIGHT, 0.5), 1.0)


static func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out
