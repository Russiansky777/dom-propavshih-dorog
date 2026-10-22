extends MechanicPanel
## M15а, mother's mirror (H2): the frame drawn together by the clamp, the glass clears onto Nina's room in
## Olkhovka — now, and twenty times faster (FastClock; ratio 1 once `road_held_both_ends`). Agata's pocket
## watch beside it counts her seconds; the wall clock's minute hand goes round in three of her minutes,
## the candle flickers, Nina changes pose every few seconds (5–6 poses), no sound. A click on the glass
## knocks — Nina does not turn. A click on the pocket watch compares the clocks (after `min_watch_s`):
## event "compared".
## Art: «Горница Нины» (партия 3): O3_bg and, on the same 1672×941 canvas at (0, 0), the clock face, the
## pendulum (axis 942, 259), the minute and hour hands drawn pointing at 12 (common axis 942, 201) and the
## candle flame (wick ≈ 445, 425). The glass shows `room_art.region` of the canvas. The hands turn by
## Nina's time, the pendulum beats twenty times too fast (a blur), the flame flickers. Nina has no art yet
## (her 3D figure is being made, assets/characters/nina): a grey-haired silhouette drawn by the engine in
## canvas px, poses in data (mechanic.poses: at = feet, height).

var fclock: FastClock = null
var room: Control = null
var room_rect: Rect2 = Rect2()
var nina: Node2D = null
var art: Node2D = null
var hand_min: Node2D = null       # pivot node at the hands' axis; the sprite under it is drawn at 12
var hand_hour: Node2D = null
var pendulum: Node2D = null       # pivot node at the pendulum's axis
var flame: Node2D = null          # pivot node at the wick
var watch: Control = null
var watch_sec: Line2D = null
var watch_min: Line2D = null
var pose_id: String = ""
var poses_seen: Array[String] = []
var knocks: int = 0
var compared_sent: bool = false
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


## The room as the glass shows it: the canvas region `room_art.region` scaled into the glass.
func _build_room() -> void:
	var ra: Dictionary = spec.get("room_art", {})
	var reg: Array = ra.get("region", [230, 40, 1060, 700])
	var k := room_rect.size.x / float(reg[2])
	art = Node2D.new()
	art.name = "Art"
	art.scale = Vector2(k, k)
	art.position = -Vector2(float(reg[0]), float(reg[1])) * k
	room.add_child(art)
	_sprite(art, "Room", String(ra.get("bg", "")), Vector2.ZERO)
	_sprite(art, "ClockFace", String(ra.get("clock_face", "")), Vector2.ZERO)
	pendulum = _pivot("Pendulum", String(ra.get("pendulum", "")), v2(ra.get("pendulum_axis", [942, 259])))
	hand_min = _pivot("HandMin", String(ra.get("hand_min", "")), v2(ra.get("hands_axis", [942, 201])))
	hand_hour = _pivot("HandHour", String(ra.get("hand_hour", "")), v2(ra.get("hands_axis", [942, 201])))
	flame = _pivot("Flame", String(ra.get("flame", "")), v2(ra.get("wick", [445, 425])))
	# Nina (silhouette until her figure comes) — between the room and the glass tint.
	nina = Node2D.new()
	nina.name = "Nina"
	art.add_child(nina)
	_update_room()


func _sprite(parent: Node, node_name: String, image: String, at: Vector2) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = node_name
	sp.centered = false
	sp.position = at
	if image != "" and ResourceLoader.exists(image):
		sp.texture = load(image)
	parent.add_child(sp)
	return sp


## A canvas-sized layer turning round `axis`: a node at the axis, the layer under it shifted back.
func _pivot(node_name: String, image: String, axis: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.position = axis
	art.add_child(n)
	_sprite(n, "Image", image, -axis)
	return n


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
	hand_min.rotation_degrees = fclock.minute_hand_deg()
	hand_hour.rotation_degrees = fclock.hour_hand_deg()
	# Pendulum: real ходики beat about once a second; at twenty times faster it is a blur.
	pendulum.rotation_degrees = sin(fclock.real_s * TAU * fclock.ratio * 0.5) * 7.0
	pendulum.modulate.a = 0.55 if fclock.ratio > 2.0 else 1.0
	# The flame flickers (no sound: the glass carries none).
	var fl := 1.0 + 0.08 * sin(clock * 11.0) + 0.05 * sin(clock * 23.0)
	flame.scale = Vector2(1.0, fl)
	flame.modulate.a = 0.85 + 0.15 * sin(clock * 7.0)
	var pose := FastClock.pose_at(spec.get("poses", []), ne)
	var pid := String(pose.get("id", ""))
	if pid != pose_id:
		pose_id = pid
		if not poses_seen.has(pid):
			poses_seen.append(pid)
		_draw_nina(pose)
	# Within a pose she moves twenty times too fast as well: a quick sway.
	nina.position = Vector2(sin(fclock.real_s * 9.0) * 4.0, 0) if fclock.ratio > 2.0 else Vector2.ZERO


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
		var hs := hgt * 0.06
		obj.polygon = PackedVector2Array([hp, hp + Vector2(hs, 0), hp + Vector2(hs, hs * 1.2), hp + Vector2(0, hs * 1.2)])
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
