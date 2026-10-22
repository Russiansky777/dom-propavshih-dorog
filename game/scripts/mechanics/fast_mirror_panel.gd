extends MechanicPanel
## M15а, mother's mirror (H2): the frame drawn together by the clamp, the glass clears onto Nina's room in
## Olkhovka — now, and twenty times faster (FastClock; ratio 1 once `road_held_both_ends`). Agata's pocket
## watch beside it counts her seconds; the wall clock's minute hand goes round in three of her minutes,
## the candle burns down, Nina changes pose every few seconds (5–6 poses), no sound. A click on the glass
## knocks — Nina does not turn. A click on the pocket watch compares the clocks (after `min_watch_s`):
## event "compared".
## Stand-in art until «Горница Нины, O3» comes (BRIEF_CHATGPT_v4 §C4): a dark room drawn by the engine —
## window with snow, icon corner, table, candle, the wall clock, the little mirror, Nina as a grey-haired
## silhouette. Positions — data (mechanic.room, mechanic.poses).

var fclock: FastClock = null
var room: Control = null
var room_rect: Rect2 = Rect2()
var nina: Node2D = null
var hand_min: Line2D = null
var hand_hour: Line2D = null
var pendulum: Polygon2D = null
var candle: Polygon2D = null
var flame: Node2D = null
var watch: Control = null
var watch_sec: Line2D = null
var watch_min: Line2D = null
var pose_id: String = ""
var poses_seen: Array[String] = []
var knocks: int = 0
var compared_sent: bool = false
var _clock_c: Vector2 = Vector2.ZERO
var _clock_r: float = 46.0
var _candle_base: Vector2 = Vector2.ZERO
var _candle_h: float = 90.0
var _watch_c: Vector2 = Vector2.ZERO


func build() -> void:
	var road := flag(String(spec.get("common_time_flag", "road_held_both_ends")))
	fclock = FastClock.new(1.0 if road else float(spec.get("ratio", 20.0)), float(spec.get("start_minutes", 1120.0)))
	var r: Array = spec.get("glass", [460, 170, 760, 640])
	room_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	# The frame (wood, drawn): mother's mirror with its corners drawn together by the clamp.
	var frame := Panel.new()
	frame.name = "Frame"
	frame.position = room_rect.position - Vector2(46, 46)
	frame.size = room_rect.size + Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.34, 0.21, 0.11)
	sb.border_color = Color(0.52, 0.36, 0.2)
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	room = Control.new()
	room.name = "Room"
	room.position = room_rect.position
	room.size = room_rect.size
	room.clip_contents = true
	room.mouse_filter = Control.MOUSE_FILTER_STOP
	room.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	room.gui_input.connect(_on_glass_input)
	add_child(room)
	_build_room()
	var tint := ColorRect.new()
	tint.name = "Glass"
	tint.color = Color(0.75, 0.82, 0.9, 0.08)
	tint.size = room.size
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(tint)
	_build_clamp()
	_build_watch()


func _p(key: String, dflt: Array) -> Vector2:
	return v2(spec.get("room", {}).get(key, dflt))


func _build_room() -> void:
	var w := room_rect.size.x
	var h := room_rect.size.y
	var art := Node2D.new()
	art.name = "Art"
	room.add_child(art)
	var bg := PlaceholderArt.shape_node({"type": "gradient", "rect": [0, 0, w, h], "top": "#2a2018", "bottom": "#140f0b"})
	art.add_child(bg)
	var floor_p := Polygon2D.new()
	floor_p.color = Color(0.17, 0.12, 0.08)
	floor_p.polygon = PackedVector2Array([Vector2(0, h * 0.72), Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)])
	art.add_child(floor_p)
	# Window with snow.
	var wn := _p("window", [80, 90])
	var win := Polygon2D.new()
	win.color = Color(0.70, 0.74, 0.80)
	win.polygon = PackedVector2Array([wn, wn + Vector2(150, 0), wn + Vector2(150, 190), wn + Vector2(0, 190)])
	art.add_child(win)
	for seg in [[Vector2(75, 0), Vector2(75, 190)], [Vector2(0, 95), Vector2(150, 95)]]:
		var l := Line2D.new()
		l.points = PackedVector2Array([wn + seg[0], wn + seg[1]])
		l.width = 6
		l.default_color = Color(0.3, 0.2, 0.12)
		art.add_child(l)
	var sill := Polygon2D.new()
	sill.color = Color(0.95, 0.96, 0.98)
	sill.polygon = PackedVector2Array([wn + Vector2(0, 150), wn + Vector2(150, 140), wn + Vector2(150, 190), wn + Vector2(0, 190)])
	art.add_child(sill)
	# Icon corner with a lamp.
	var ic := _p("icon", [w - 120, 60])
	var icon := Polygon2D.new()
	icon.color = Color(0.45, 0.32, 0.12)
	icon.polygon = PackedVector2Array([ic, ic + Vector2(70, 0), ic + Vector2(70, 90), ic + Vector2(0, 90)])
	art.add_child(icon)
	art.add_child(PlaceholderArt.glow(ic + Vector2(35, 110), 26, Color(1.0, 0.5, 0.2, 0.7)))
	# Table, cup, the little mirror.
	var tb := _p("table", [250, 440])
	var table := Polygon2D.new()
	table.color = Color(0.36, 0.24, 0.13)
	table.polygon = PackedVector2Array([tb, tb + Vector2(330, 0), tb + Vector2(310, 30), tb + Vector2(20, 30)])
	art.add_child(table)
	for leg in [Vector2(30, 30), Vector2(290, 30)]:
		var lg := Polygon2D.new()
		lg.color = Color(0.28, 0.18, 0.1)
		lg.polygon = PackedVector2Array([tb + leg, tb + leg + Vector2(14, 0), tb + leg + Vector2(14, 120), tb + leg + Vector2(0, 120)])
		art.add_child(lg)
	var sm := _p("small_mirror", [520, 405])
	var mir := Polygon2D.new()
	mir.name = "SmallMirror"
	mir.color = Color(0.62, 0.66, 0.7)
	mir.polygon = PackedVector2Array([sm, sm + Vector2(26, 0), sm + Vector2(26, 34), sm + Vector2(0, 34)])
	art.add_child(mir)
	# Candle.
	_candle_base = _p("candle", [300, 440])
	candle = Polygon2D.new()
	candle.name = "Candle"
	candle.color = Color(0.93, 0.9, 0.8)
	art.add_child(candle)
	flame = PlaceholderArt.glow(_candle_base, 60, Color(1.0, 0.78, 0.4, 0.9))
	art.add_child(flame)
	# Wall clock (ходики): face, hands, pendulum — the hands are Nina's time.
	_clock_c = _p("clock", [w * 0.55, 150])
	_clock_r = float(spec.get("room", {}).get("clock_r", 48))
	var face := Polygon2D.new()
	face.color = Color(0.86, 0.82, 0.7)
	face.polygon = PlaceholderArt.circle_points(_clock_c, _clock_r)
	art.add_child(face)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var tick_l := Line2D.new()
		tick_l.points = PackedVector2Array([_clock_c + Vector2(sin(a), -cos(a)) * (_clock_r - 8), _clock_c + Vector2(sin(a), -cos(a)) * (_clock_r - 2)])
		tick_l.width = 3 if i % 3 == 0 else 1.5
		tick_l.default_color = Color(0.15, 0.1, 0.05)
		art.add_child(tick_l)
	pendulum = Polygon2D.new()
	pendulum.name = "Pendulum"
	pendulum.color = Color(0.7, 0.55, 0.2, 0.35)   # a blur: at twenty times it swings faster than the eye
	pendulum.polygon = PackedVector2Array([_clock_c + Vector2(0, _clock_r), _clock_c + Vector2(-24, _clock_r + 90), _clock_c + Vector2(24, _clock_r + 90)])
	art.add_child(pendulum)
	hand_hour = _hand(art, 5.0, Color(0.1, 0.07, 0.04))
	hand_min = _hand(art, 3.0, Color(0.1, 0.07, 0.04))
	# Nina.
	nina = Node2D.new()
	nina.name = "Nina"
	art.add_child(nina)
	_update_room()


func _hand(parent: Node, width: float, col: Color) -> Line2D:
	var l := Line2D.new()
	l.width = width
	l.default_color = col
	parent.add_child(l)
	return l


func _build_clamp() -> void:
	var cp := v2(spec.get("clamp_at", [1236, 420]))
	var clamp := Polygon2D.new()
	clamp.name = "Clamp"
	clamp.color = Color(0.3, 0.3, 0.32)
	clamp.polygon = PackedVector2Array([cp + Vector2(-14, -70), cp + Vector2(30, -70), cp + Vector2(30, 70), cp + Vector2(-14, 70), cp + Vector2(-14, 52), cp + Vector2(16, 52), cp + Vector2(16, -52), cp + Vector2(-14, -52)])
	add_child(clamp)


func _build_watch() -> void:
	var wr: Array = spec.get("watch", [1390, 560, 300])
	_watch_c = Vector2(float(wr[0]), float(wr[1]))
	var size := float(wr[2])
	watch = Control.new()
	watch.name = "Watch"
	watch.position = _watch_c - Vector2(size, size) * 0.5
	watch.size = Vector2(size, size)
	watch.mouse_filter = Control.MOUSE_FILTER_STOP
	watch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	watch.gui_input.connect(_on_watch_input)
	add_child(watch)
	var icon_path := String(spec.get("watch_icon", "res://assets/icons/pocket_watch.png"))
	if ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = watch.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		watch.add_child(tr)
	var face := Polygon2D.new()
	face.color = Color(0.95, 0.92, 0.84)
	face.polygon = PlaceholderArt.circle_points(watch.size * 0.5 + Vector2(0, size * 0.06), size * 0.26)
	watch.add_child(face)
	watch_min = _hand(watch, 4.0, Color(0.1, 0.08, 0.06))
	watch_sec = _hand(watch, 2.0, Color(0.6, 0.12, 0.08))
	label(text("label_watch"), _watch_c + Vector2(-size * 0.5, size * 0.5 + 6), size, &"CloseupLabel")


func _update_room() -> void:
	var ne := fclock.nina_elapsed_minutes()
	hand_min.points = PackedVector2Array([_clock_c, _clock_c + _dir(fclock.minute_hand_deg()) * (_clock_r - 10)])
	hand_hour.points = PackedVector2Array([_clock_c, _clock_c + _dir(fclock.hour_hand_deg()) * (_clock_r - 22)])
	# Pendulum: real ходики beat about once a second; at twenty times faster it is a blur.
	var swing := sin(fclock.real_s * TAU * fclock.ratio * 0.5) * 18.0
	pendulum.position = Vector2.ZERO
	pendulum.skew = deg_to_rad(swing * 0.3)
	pendulum.color.a = 0.35 if fclock.ratio > 2.0 else 0.85
	var left := FastClock.candle_left(ne, float(spec.get("candle_burn_minutes", 120.0)), 0.2)
	var ch := _candle_h * left
	candle.polygon = PackedVector2Array([_candle_base + Vector2(-9, 0), _candle_base + Vector2(9, 0), _candle_base + Vector2(9, -ch), _candle_base + Vector2(-9, -ch)])
	flame.position = _candle_base + Vector2(0, -ch - 12)
	var pose := FastClock.pose_at(spec.get("poses", []), ne)
	var pid := String(pose.get("id", ""))
	if pid != pose_id:
		pose_id = pid
		if not poses_seen.has(pid):
			poses_seen.append(pid)
		_draw_nina(pose)
	# Within a pose she moves twenty times too fast as well: a quick sway.
	nina.position = Vector2(sin(fclock.real_s * 9.0) * 3.0, 0) if fclock.ratio > 2.0 else Vector2.ZERO


func _dir(deg: float) -> Vector2:
	return Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))


func _draw_nina(pose: Dictionary) -> void:
	for c in nina.get_children():
		c.queue_free()
	var at := v2(pose.get("at", [300, 440]))
	var hgt := float(pose.get("height", 300))
	var sitting := bool(pose.get("sitting", false))
	var w := hgt * 0.36
	var rect := Rect2(at.x - w * 0.5, at.y - hgt, w, hgt)
	if sitting:
		rect = Rect2(at.x - w * 0.5, at.y - hgt * 0.72, w, hgt * 0.72)
	var fig := PlaceholderArt.silhouette(rect, Color(0.17, 0.16, 0.18), {})
	nina.add_child(fig)
	var head: Polygon2D = fig.get_node_or_null("Head")
	if head != null:
		head.color = Color(0.78, 0.78, 0.76)   # grey hair
	if pose.has("hold"):
		var obj := Polygon2D.new()
		obj.color = Color(0.85, 0.85, 0.8) if String(pose["hold"]) == "cup" else Color(0.62, 0.66, 0.7)
		var hp := Vector2(at.x + w * 0.45, at.y - hgt * (0.5 if not sitting else 0.4))
		obj.polygon = PackedVector2Array([hp, hp + Vector2(18, 0), hp + Vector2(18, 22), hp + Vector2(0, 22)])
		nina.add_child(obj)


func tick(delta: float) -> void:
	fclock.advance(delta)
	_update_room()
	watch_sec.points = PackedVector2Array([watch.size * 0.5 + Vector2(0, watch.size.y * 0.06), watch.size * 0.5 + Vector2(0, watch.size.y * 0.06) + _dir(fclock.watch_second_deg()) * watch.size.x * 0.22])
	watch_min.points = PackedVector2Array([watch.size * 0.5 + Vector2(0, watch.size.y * 0.06), watch.size * 0.5 + Vector2(0, watch.size.y * 0.06) + _dir(fclock.watch_minute_deg()) * watch.size.x * 0.17])


func _on_glass_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		knocks += 1
		sound("knock")
		if knocks == 1:
			say("knock_first")


func _on_watch_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		compare()


## Agata compares the wall clock with her pocket watch: only after she has watched a while.
func compare() -> bool:
	if compared_sent or flag(String(spec.get("compared_flag", "nina_time_compared"))):
		say("watch_again")
		return false
	if fclock.real_s < float(spec.get("min_watch_s", 15.0)):
		say("watch_wait")
		return false
	compared_sent = true
	return event("compared")


func probe() -> Dictionary:
	return {"ratio": fclock.ratio, "real_s": fclock.real_s, "nina_minutes": fclock.nina_minutes(),
		"nina_elapsed": fclock.nina_elapsed_minutes(), "minute_deg": fclock.minute_hand_deg(), "pose": pose_id,
		"poses_seen": poses_seen.duplicate(), "knocks": knocks, "glass": center_of(room), "watch": center_of(watch)}
