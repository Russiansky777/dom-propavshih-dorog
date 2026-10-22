class_name PocketWatchDial
extends Control
## Agata's pocket watch, going (F4, F9): the painted watch (the bag icon, res://assets/icons/pocket_watch.png)
## with live hands drawn over its dial. The painted hands are covered by the dial's middle (the numerals at
## the rim stay painted); hour, minute and second hands are drawn from `seconds` (Agata's time). Used in the
## bag's close-up of the watch and next to mother's mirror when Agata holds it to the glass.
## Geometry of the dial on the picture (fractions of the icon): `dial_center`, `dial_r` (measured on the icon,
## data may override: items.json pocket_watch.examine.dial, the mirror's `watch_dial`).

const ICON := "res://assets/icons/pocket_watch.png"
const FACE := Color(0.93, 0.89, 0.8)
const INK := Color(0.12, 0.09, 0.07)
const RED := Color(0.62, 0.13, 0.09)

var dial_center: Vector2 = Vector2(0.534, 0.521)
var dial_r: float = 0.168
var seconds: float = 0.0          # time on the watch, s since 00:00 (the owner sets it; `run` advances it)
var run: bool = true              # advances `seconds` by real time
var zoom: float = 1.0             # >1: the watch drawn larger with its dial in the middle (clip the parent)
var texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	if texture == null and ResourceLoader.exists(ICON):
		texture = load(ICON)
	if seconds == 0.0:
		var t := Time.get_time_dict_from_system()
		seconds = float(t.hour) * 3600.0 + float(t.minute) * 60.0 + float(t.second)


func configure(cfg: Dictionary) -> void:
	if cfg.has("center"):
		dial_center = Vector2(float(cfg["center"][0]), float(cfg["center"][1]))
	if cfg.has("r"):
		dial_r = float(cfg["r"])


func _process(delta: float) -> void:
	if run:
		seconds += delta
	queue_redraw()


## Top-left of the watch picture in this control (zoom > 1 — the dial in the middle).
func _origin() -> Vector2:
	var s := minf(size.x, size.y) * zoom
	return Vector2.ZERO if zoom <= 1.0 else size * 0.5 - dial_center * s


func center() -> Vector2:
	return _origin() + dial_center * minf(size.x, size.y) * zoom


func radius() -> float:
	return dial_r * minf(size.x, size.y) * zoom


func _draw() -> void:
	var s := minf(size.x, size.y) * zoom
	var o := _origin()
	if texture != null:
		draw_texture_rect(texture, Rect2(o + Vector2(3, 5), Vector2(s, s)), false, Color(0, 0, 0, 0.35))
		draw_texture_rect(texture, Rect2(o, Vector2(s, s)), false)
	var c := center()
	var r := radius()
	# The dial's middle (under the painted hands), a little darker towards the rim like old enamel.
	draw_circle(c, r * 0.74, FACE.darkened(0.06))
	draw_circle(c, r * 0.68, FACE)
	for i in 60:
		if i % 5 == 0:
			continue
		var a := TAU * i / 60.0
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * r * 0.62, c + d * r * 0.67, Color(INK, 0.55), maxf(1.0, r * 0.012))
	var h := fmod(seconds / 3600.0, 12.0)
	var m := fmod(seconds / 60.0, 60.0)
	var sec := fmod(seconds, 60.0)
	_hand(c, h / 12.0 * TAU, r * 0.4, r * 0.06, INK)
	_hand(c, m / 60.0 * TAU, r * 0.6, r * 0.045, INK)
	var sa := floorf(sec) / 60.0 * TAU     # the second hand ticks
	var sd := Vector2(sin(sa), -cos(sa))
	draw_line(c - sd * r * 0.14, c + sd * r * 0.64, RED, maxf(1.5, r * 0.02))
	draw_circle(c, r * 0.05, Color(0.55, 0.42, 0.2))
	draw_circle(c, r * 0.025, INK)


## A tapered blued-steel hand.
func _hand(c: Vector2, ang: float, length: float, width: float, col: Color) -> void:
	var d := Vector2(sin(ang), -cos(ang))
	var n := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([c - d * length * 0.15 + n * width * 0.5, c + d * length * 0.55 + n * width,
		c + d * length, c + d * length * 0.55 - n * width, c - d * length * 0.15 - n * width * 0.5])
	draw_colored_polygon(pts, col)


## Minute hand angle in degrees (tests).
func minute_deg() -> float:
	return fmod(seconds / 60.0, 60.0) * 6.0
