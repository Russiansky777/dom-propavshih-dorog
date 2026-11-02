class_name PocketWatchDial
extends Control
## Agata's pocket watch, going (F4, F9): the painted watch (the bag icon, res://assets/icons/pocket_watch.png)
## with live hands drawn over its dial. The painted hands are covered by the dial's middle (the numerals at
## the rim stay painted); hour, minute and second hands are drawn from `seconds` (Agata's time). Used in the
## bag's close-up of the watch and next to mother's mirror when Agata holds it to the glass.
## Geometry of the dial on the picture: `dial_center` (fractions of the picture's width and height), `dial_r` (fraction of
## its height) — measured on the icon; data may override (items.json pocket_watch.examine.watch, the mirror's
## `watch_dial`). Another picture of the watch (`texture`, e.g. the close-up of партия 8 — a dial painted without
## hands) is drawn in its own aspect; `face` false — no enamel disc over the middle (nothing painted to cover).

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
var face: bool = true             # the enamel disc over the painted hands (the icon); false — the dial has none
## Директор 01.11, стр. 21 («циферблат чуть по часовой развернуть, чтобы 12 было посередине тёмной штуки»): where XII
## is painted (degrees clockwise from straight up, `dial_deg`) and how far the painted enamel disc is turned clockwise about
## the axis (`turn_deg`, the disc of `disc_r` × dial radius drawn again turned). The hands count from XII as it is drawn
## then (dial_deg + turn_deg) — they show the right time against the painted numerals.
var dial_deg: float = 0.0
var turn_deg: float = 0.0
var disc_r: float = 1.0
## 02.11 (Director, стр. 15: «часы, когда к маминым подносит — в идеале выровнять, чтобы 12 было сверху, повернуть всю
## картинку»): the whole watch picture (case, bow, enamel) turned by `picture_deg` clockwise about the dial's axis;
## −(dial_deg + turn_deg) puts the painted XII straight up. The hands follow the turned XII.
var picture_deg: float = 0.0


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
	face = bool(cfg.get("face", face))
	# Another picture of the watch (e.g. the close-up of партия 8, its dial painted without hands — one style
	# with the hands drawn over it, no disc of another colour).
	var art := String(cfg.get("art", ""))
	if art != "" and ResourceLoader.exists(art):
		texture = load(art)
	if cfg.has("zoom"):
		zoom = float(cfg["zoom"])
	dial_deg = float(cfg.get("dial_deg", dial_deg))
	turn_deg = float(cfg.get("turn_deg", turn_deg))
	disc_r = float(cfg.get("disc_r", disc_r))
	picture_deg = float(cfg.get("picture_deg", picture_deg))


func _process(delta: float) -> void:
	if run:
		seconds += delta
	queue_redraw()


## The picture's size as drawn: fitted into the control in its own aspect (the square icon: min(size) — as before), × zoom.
func picture_size() -> Vector2:
	var ts := texture.get_size() if texture != null else Vector2.ONE
	return ts * (minf(size.x / maxf(ts.x, 1.0), size.y / maxf(ts.y, 1.0)) * zoom)


## Top-left of the watch picture in this control (zoom > 1 — the dial in the middle).
func _origin() -> Vector2:
	var ps := picture_size()
	return Vector2.ZERO if zoom <= 1.0 else size * 0.5 - dial_center * ps


func center() -> Vector2:
	return _origin() + dial_center * picture_size()


func radius() -> float:
	return dial_r * picture_size().y


func _draw() -> void:
	var ps := picture_size()
	var o := _origin()
	var c := center()
	var r := radius()
	if absf(picture_deg) > 0.01:
		# the picture turned about the axis: rotate the canvas about c for the painted parts only
		var rot := deg_to_rad(picture_deg)
		draw_set_transform(c - c.rotated(rot), rot, Vector2.ONE)
	if texture != null:
		draw_texture_rect(texture, Rect2(o + Vector2(3, 5).rotated(-deg_to_rad(picture_deg)), ps), false, Color(0, 0, 0, 0.35))
		draw_texture_rect(texture, Rect2(o, ps), false)
	if texture != null and absf(turn_deg) > 0.01:
		_draw_turned_disc(c, r * disc_r, o, ps)
	if absf(picture_deg) > 0.01:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if face:
		# The dial's middle (under the painted hands), a little darker towards the rim like old enamel.
		draw_circle(c, r * 0.74, FACE.darkened(0.06))
		draw_circle(c, r * 0.68, FACE)
		for i in 60:
			if i % 5 == 0:
				continue
			var a := TAU * i / 60.0
			var d := Vector2(sin(a), -cos(a))
			draw_line(c + d * r * 0.62, c + d * r * 0.67, Color(INK, 0.55), maxf(1.0, r * 0.012), true)
	var h := fmod(seconds / 3600.0, 12.0)
	var m := fmod(seconds / 60.0, 60.0)
	var sec := fmod(seconds, 60.0)
	# 30.10 (сверка, 25.10 стр. 10 «стрелки сгладить до реализма»): гладкие края были, но стрелки — плоские чёрные
	# клинья. Теперь как у старых карманных часов: тонкая воронёная сталь с бликом вдоль оси, у часовой — кольцо
	# «яблоко» (бреге), под стрелками мягкая тень на эмали, секундная — тонкая с противовесом.
	var zero := twelve_rad()   # стр. 21: XII as drawn (the painted numeral, turned with the disc)
	_hand(c, zero + h / 12.0 * TAU, r * 0.42, r * 0.034, true)
	_hand(c, zero + m / 60.0 * TAU, r * 0.62, r * 0.026, false)
	var sa := zero + floorf(sec) / 60.0 * TAU     # the second hand ticks
	var sd := Vector2(sin(sa), -cos(sa))
	var sh := Vector2(1.0, 1.6) * maxf(1.0, r * 0.012)
	draw_line(c - sd * r * 0.16 + sh, c + sd * r * 0.64 + sh, Color(0, 0, 0, 0.18), maxf(1.2, r * 0.013), true)
	draw_line(c - sd * r * 0.16, c + sd * r * 0.64, RED, maxf(1.0, r * 0.011), true)
	draw_circle(c - sd * r * 0.12, maxf(1.5, r * 0.022), RED)
	draw_circle(c, r * 0.05, Color(0.62, 0.48, 0.24))
	draw_circle(c + Vector2(-0.3, -0.3) * r * 0.02, r * 0.022, Color(0.85, 0.72, 0.42))
	draw_circle(c, r * 0.014, Color(0.3, 0.22, 0.1))


## A tapered blued-steel hand: a soft shadow on the enamel, the dark steel, a light streak along its axis; the hour
## hand has the Breguet ring near its tip.
const STEEL := Color(0.07, 0.08, 0.14)
const STEEL_LIGHT := Color(0.42, 0.5, 0.72)


func _hand(c: Vector2, ang: float, length: float, width: float, ring: bool) -> void:
	var d := Vector2(sin(ang), -cos(ang))
	var n := Vector2(-d.y, d.x)
	var tip := length
	var pts := PackedVector2Array([c - d * length * 0.16 + n * width * 0.7, c + d * length * 0.5 + n * width * 0.55,
		c + d * tip * 0.93 + n * width * 0.35, c + d * tip, c + d * tip * 0.93 - n * width * 0.35,
		c + d * length * 0.5 - n * width * 0.55, c - d * length * 0.16 - n * width * 0.7])
	var sh := Vector2(1.0, 1.6) * maxf(1.0, width * 0.5)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + sh)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.16))
	draw_colored_polygon(pts, STEEL)
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, STEEL, 1.0, true)
	if ring:
		var rc := c + d * length * 0.7
		var rr := width * 1.55
		draw_arc(rc + sh, rr, 0.0, TAU, 28, Color(0, 0, 0, 0.16), maxf(1.0, width * 0.55), true)
		draw_arc(rc, rr, 0.0, TAU, 28, STEEL, maxf(1.0, width * 0.55), true)
	# The light along the steel (the hand is a little rounded): from the base to near the tip.
	draw_line(c + d * length * 0.02 + n * width * 0.12, c + d * length * 0.85 + n * width * 0.08, Color(STEEL_LIGHT, 0.55), maxf(0.8, width * 0.28), true)


## Minute hand angle in degrees (tests): from XII of the dial.
func minute_deg() -> float:
	return fmod(seconds / 60.0, 60.0) * 6.0


## Where XII is on screen, radians clockwise from straight up: the painted numeral plus the disc's turn.
func twelve_rad() -> float:
	return deg_to_rad(dial_deg + turn_deg + picture_deg)


## The enamel disc of the picture (radius `rd` about the axis) drawn again, turned by `turn_deg` clockwise: each rim
## point of the turned disc takes the picture's colour from where it was before the turn (a fan of UV'd triangles).
func _draw_turned_disc(c: Vector2, rd: float, o: Vector2, ps: Vector2) -> void:
	var n := 120
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var t := deg_to_rad(turn_deg)
	for i in n:
		var a := TAU * i / n
		var v := Vector2(cos(a), sin(a)) * rd
		pts.append(c + v.rotated(t))
		uvs.append((c + v - o) / ps)
		cols.append(Color.WHITE)
	draw_polygon(pts, cols, uvs, texture)
