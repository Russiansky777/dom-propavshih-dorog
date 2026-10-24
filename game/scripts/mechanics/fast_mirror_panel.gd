extends MechanicPanel
## M15а, mother's mirror (H2): the frame drawn together by the clamp, the glass clears onto Nina's room in
## Olkhovka — now, and twenty times faster (FastClock; ratio 1 once `road_held_both_ends`): the candle
## flickers, Nina changes pose every few seconds (5–6 poses), no sound. A click on the glass knocks — Nina
## does not turn.
## Director 23.10 (F4: «смотришь в зеркало на мамины часы — они не идут, идут только Агатины»): the wall clock
## in the glass is 75 px of the painting — two degrees a second of its minute hand did not read as going. Now
##   - beside the glass, «У мамы»: the same ходики up close (`loupe.region` of the painting, the same hand and
##     pendulum layers) — the minute hand goes round in three of Agata's minutes, the hour hand twelve times
##     slower, the pendulum swings visibly fast (a capped beat with a blur trail: twenty real beats a second
##     would be a smear the eye reads as still);
##   - «У меня»: an empty place until Agata holds her own watch to the glass — the item `watch_item` from the
##     bag on the glass (or on that place). Then both go side by side, each with how much time has passed on
##     it; after `compare_s` real seconds the event "compared" (the flag; the scene M15а — «На моих три минуты —
##     у неё час. Минута здесь — двадцать там. Пока я сплю, у неё проходит неделя») — no automatic comparison.
## Art: «Горница Нины» (партия 3): O3_bg and, on the same 1672×941 canvas at (0, 0), the clock face, the
## pendulum (axis 942, 259), the minute and hour hands drawn pointing at 12 (common axis 942, 201) and the
## candle flame (wick ≈ 445, 425).
## Nina (23.10): her 3D figure in six poses, rendered for this glass (pipeline/render/render_mirror.py → the sheets
## `nina_sheets`, assets/characters/nina_mirror): the room rebuilt from the painting's perspective, each pose seen
## from the mirror's place, the table in front of her already cut out of the sheet. Data (mechanic.poses): `sheet`
## — which sheet, `at` — the floor under her (canvas px), `height` — her height there (canvas px), `path` — where
## she paces (walk), `shadow_m` — a soft contact shadow. Inside a pose she moves `motion_speedup` times too fast
## (the clips' natural tempo × that, capped where the eye still follows, like the pendulum); with common time — 1×.
## No sheet → the old engine silhouette (fallback).

const PENDULUM_MAX_HZ := 2.6     # the swing the eye still follows; at 20× the real beat would be ≈ 20 Hz
const PENDULUM_DEG := 9.0

var fclock: FastClock = null
var room: Control = null
var room_rect: Rect2 = Rect2()
var nina: Node2D = null
var art: Node2D = null
var hand_min: Node2D = null       # pivot node at the hands' axis; the sprite under it is drawn at 12
var hand_hour: Node2D = null
var hand_sec: Node2D = null       # the second hand (code-drawn, H32)
var pendulum: Node2D = null       # pivot node at the pendulum's axis
var flame: Node2D = null          # pivot node at the wick
var loupe: Control = null         # «У мамы»: the wall clock up close
var loupe_art: Node2D = null
var loupe_min: Node2D = null
var loupe_hour: Node2D = null
var loupe_sec: Node2D = null
var loupe_pend: Node2D = null
var loupe_ghosts: Array[Node2D] = []
var slot: Control = null          # «У меня»: where Agata's watch is held
var watch: PocketWatchDial = null
var slot_hint: Label = null
var elapsed_nina: Label = null
var elapsed_mine: Label = null
var holding: bool = false         # Agata holds her watch to the glass
var hold_s: float = 0.0           # real seconds since she did
var hold_start_nina: float = 0.0  # Nina's elapsed minutes when she did
var pose_id: String = ""
var pose_layer: Sprite2D = null
var nina_meta: Dictionary = {}    # sprites.json of the mirror poses
var nina_sheets: Dictionary = {}  # sheet id → {frames: SpriteFrames (rows "r0", "r1"), act}
var nina_sprite: AnimatedSprite2D = null
var nina_pose: Dictionary = {}
var walk_pos: Vector2 = Vector2.ZERO
var walk_dir: int = -1
var poses_seen: Array[String] = []
var knocks: int = 0
var compared_sent: bool = false
var wrong_items: int = 0
var _hinted: bool = false


func build() -> void:
	var road := flag(String(spec.get("common_time_flag", "road_held_both_ends")))
	fclock = FastClock.new(1.0 if road else float(spec.get("ratio", 20.0)), float(spec.get("start_minutes", 1120.0)))
	var r: Array = spec.get("glass", [150, 160, 1130, 747])
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
	_build_side()
	_update_room()


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
	pendulum = _pivot(art, "Pendulum", String(ra.get("pendulum", "")), v2(ra.get("pendulum_axis", [942, 259])))
	hand_min = _pivot(art, "HandMin", String(ra.get("hand_min", "")), v2(ra.get("hands_axis", [942, 201])))
	hand_hour = _pivot(art, "HandHour", String(ra.get("hand_hour", "")), v2(ra.get("hands_axis", [942, 201])))
	hand_sec = _second_hand(art)
	# A layer of the room for one pose (`room_layer`: the table without the small mirror while she holds it) —
	# over the painting, under Nina; hidden in the other poses or while the picture is not there.
	pose_layer = _sprite(art, "PoseLayer", "", Vector2.ZERO)
	pose_layer.visible = false
	# Nina — in front of the wall and the clock, behind the candle flame on the table (and the glass tint).
	nina = Node2D.new()
	nina.name = "Nina"
	art.add_child(nina)
	_load_nina_sheets()
	flame = _pivot(art, "Flame", String(ra.get("flame", "")), v2(ra.get("wick", [445, 425])))


## The mirror poses' sheets (packed atlases, like the characters' sheets): one SpriteFrames per sheet, a row per
## direction of the pose ("r0", "r1" — walking left and right).
func _load_nina_sheets() -> void:
	var dir := String(spec.get("nina_sheets", ""))
	if dir == "" or not FileAccess.file_exists(dir + "/sprites.json"):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "/sprites.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	nina_meta = parsed
	var sh := ActorSheet.new()
	sh.frame_w = int(nina_meta.get("frame_w", 288))
	sh.frame_h = int(nina_meta.get("frame_h", 384))
	var acts: Dictionary = nina_meta.get("actions", {})
	for id in acts.keys():
		var act: Dictionary = acts[id]
		var path := dir + "/" + String(act.get("sheet", String(id) + ".png"))
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		var sf := SpriteFrames.new()
		sf.remove_animation("default")
		var rows: int = maxi(1, (act.get("rows", []) as Array).size())
		for r in rows:
			var anim := "r%d" % r
			sf.add_animation(anim)
			sf.set_animation_loop(anim, true)
			sf.set_animation_speed(anim, float(act.get("fps", 12.0)))
			for i in ActorSheet.frame_sequence(int(act.get("frames", 1)), String(act.get("playback", "loop"))):
				sf.add_frame(anim, sh.frame_texture(tex, act, r, int(i)))
		nina_sheets[String(id)] = {"frames": sf, "act": act}


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
func _pivot(parent: Node2D, node_name: String, image: String, axis: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.position = axis
	parent.add_child(n)
	_sprite(n, "Image", image, -axis)
	return n


func _build_clamp() -> void:
	var cp := v2(spec.get("clamp_at", [1236, 420]))
	var clamp := Polygon2D.new()
	clamp.name = "Clamp"
	clamp.color = Color(0.3, 0.3, 0.32)
	clamp.polygon = PackedVector2Array([cp + Vector2(-14, -70), cp + Vector2(30, -70), cp + Vector2(30, 70), cp + Vector2(-14, 70), cp + Vector2(-14, 52), cp + Vector2(16, 52), cp + Vector2(16, -52), cp + Vector2(-14, -52)])
	add_child(clamp)


## Right of the frame: the wall clock up close («У мамы») and the place for Agata's watch («У меня»), side by side.
func _build_side() -> void:
	var x0 := room_rect.end.x + 46.0 + 44.0
	var col := 1900.0 - x0
	var lp: Dictionary = spec.get("loupe", {})
	var w := float(lp.get("width", minf((col - 30.0) * 0.5, 300.0)))
	var reg: Array = lp.get("region", [893, 148, 100, 180])
	var k := w / float(reg[2])
	var h := float(reg[3]) * k
	var top := float(lp.get("top", room_rect.position.y + (room_rect.size.y - h) * 0.5 - 40.0))
	# «У мамы»: a round window cut onto the clock (Director 24.10, H32: an ellipse round the face and the pendulum,
	# a soft edge and a vignette — not a rectangle; the same painting, its own copies of the moving layers).
	var win: Dictionary = spec.get("window", {})
	loupe = _window("Loupe", Rect2(x0, top, w, h), win)
	loupe.mouse_filter = Control.MOUSE_FILTER_STOP
	loupe.gui_input.connect(_on_glass_input)
	var ra: Dictionary = spec.get("room_art", {})
	loupe_art = Node2D.new()
	loupe_art.name = "Art"
	loupe_art.scale = Vector2(k, k)
	loupe_art.position = -Vector2(float(reg[0]), float(reg[1])) * k
	(loupe as SoftWindow).content.add_child(loupe_art)
	_sprite(loupe_art, "Room", String(ra.get("bg", "")), Vector2.ZERO)
	_sprite(loupe_art, "ClockFace", String(ra.get("clock_face", "")), Vector2.ZERO)
	var pax := v2(ra.get("pendulum_axis", [942, 259]))
	for i in 2:   # the blur trail of a pendulum beating too fast to follow
		var g := _pivot(loupe_art, "PendulumGhost%d" % i, String(ra.get("pendulum", "")), pax)
		g.modulate.a = 0.28 - i * 0.1
		loupe_ghosts.append(g)
	loupe_pend = _pivot(loupe_art, "Pendulum", String(ra.get("pendulum", "")), pax)
	loupe_min = _pivot(loupe_art, "HandMin", String(ra.get("hand_min", "")), v2(ra.get("hands_axis", [942, 201])))
	loupe_hour = _pivot(loupe_art, "HandHour", String(ra.get("hand_hour", "")), v2(ra.get("hands_axis", [942, 201])))
	loupe_sec = _second_hand(loupe_art)
	label(text("label_nina_clock"), Vector2(x0, top + h + 10.0), w, &"CloseupLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elapsed_nina = label("", Vector2(x0, top + h + 46.0), w, &"CloseupLabel")
	elapsed_nina.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# «У меня»: the place for Agata's watch.
	var sx := x0 + w + 30.0
	var sw := minf(w, 1900.0 - sx)
	slot = _window("WatchSlot", Rect2(sx, top + (h - sw) * 0.5, sw, sw), win)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.gui_input.connect(_on_slot_input)
	slot_hint = Label.new()
	slot_hint.name = "Hint"
	slot_hint.text = text("label_watch_slot")
	slot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_hint.theme_type_variation = &"CloseupLabel"
	slot_hint.position = slot.size * 0.15
	slot_hint.size = slot.size * 0.7
	slot_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(slot_hint)
	watch = PocketWatchDial.new()
	watch.name = "Watch"
	watch.zoom = 1.7
	watch.configure(spec.get("watch_dial", {}))
	watch.size = slot.size
	watch.visible = false
	watch.run = false
	(slot as SoftWindow).content.add_child(watch)
	label(text("label_my_watch"), Vector2(sx, top + h + 10.0), sw, &"CloseupLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elapsed_mine = label("", Vector2(sx, top + h + 46.0), sw, &"CloseupLabel")
	elapsed_mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A round window with a soft edge, a brass rim and a shadow (the clock up close, the watch's place) — one style
## for both (data `window`: SoftWindow.configure).
func _window(node_name: String, r: Rect2, cfg: Dictionary) -> Control:
	var p := SoftWindow.new()
	p.name = node_name
	p.position = r.position
	p.size = r.size
	p.configure(cfg)
	add_child(p)
	return p


## The ходики's second hand (H32), drawn like the painted hands: thin dark iron with a counterweight; geometry in
## canvas px of the room (`room_art.second_hand`).
func _second_hand(parent: Node2D) -> SecondHand:
	var ra: Dictionary = spec.get("room_art", {})
	var sh := SecondHand.new()
	sh.name = "HandSec"
	sh.position = v2(ra.get("hands_axis", [942, 201]))
	sh.configure(ra.get("second_hand", {}))
	parent.add_child(sh)
	return sh


class SecondHand extends Node2D:
	var length: float = 29.0
	var tail: float = 7.0
	var width: float = 0.8
	var color: Color = Color(0.19, 0.16, 0.14)

	func configure(cfg: Dictionary) -> void:
		length = float(cfg.get("length", length))
		tail = float(cfg.get("tail", tail))
		width = float(cfg.get("width", width))
		if cfg.get("color", null) is Array:
			var c: Array = cfg["color"]
			color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)

	func _draw() -> void:
		draw_line(Vector2(0, tail), Vector2(0, -length), color, width, true)
		draw_circle(Vector2(0, tail * 0.85), width * 1.9, color)
		draw_circle(Vector2.ZERO, width * 1.6, color)


func _update_room() -> void:
	var ne := fclock.nina_elapsed_minutes()
	for hm in [hand_min, loupe_min]:
		if hm != null:
			hm.rotation_degrees = fclock.minute_hand_deg()
	for sh in [hand_sec, loupe_sec]:
		if sh != null:
			sh.rotation_degrees = fclock.second_hand_deg()
	for hh in [hand_hour, loupe_hour]:
		if hh != null:
			hh.rotation_degrees = fclock.hour_hand_deg()
	# Pendulum: a real ходики beats about once a second; at twenty times that would be a smear — the swing is
	# capped where the eye still follows it, with a trail.
	var hz := minf(0.5 * fclock.ratio, PENDULUM_MAX_HZ)
	var ph := fclock.real_s * TAU * hz
	var deg := sin(ph) * PENDULUM_DEG
	for pn in [pendulum, loupe_pend]:
		if pn != null:
			pn.rotation_degrees = deg
	for i in loupe_ghosts.size():
		loupe_ghosts[i].visible = fclock.ratio > 2.0
		loupe_ghosts[i].rotation_degrees = sin(ph - 0.35 * (i + 1)) * PENDULUM_DEG
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
	if nina_sprite != null:
		nina_sprite.speed_scale = motion_speed()
	else:
		# The silhouette (no sheet): within a pose she moves twenty times too fast as well — a quick sway.
		nina.position = Vector2(sin(fclock.real_s * 9.0) * 4.0, 0) if fclock.ratio > 2.0 else Vector2.ZERO
	if holding:
		elapsed_mine.text = text("label_elapsed").format({"t": _mmss(hold_s)})
		elapsed_nina.text = text("label_elapsed").format({"t": _mmss((ne - hold_start_nina) * 60.0)})


static func _mmss(s: float) -> String:
	var t := int(floorf(s))
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


## How many times too fast she moves inside a pose: the 20:1 clock capped where the eye still follows a body
## (data `motion_speedup`); once the road is held from both ends — her own tempo.
func motion_speed() -> float:
	return minf(fclock.ratio, float(spec.get("motion_speedup", 2.5))) if fclock.ratio > 1.0 else 1.0


## The sheet a pose is drawn from: `sheet` (write_again → write) or the pose's own id.
static func pose_sheet(pose: Dictionary) -> String:
	return String(pose.get("sheet", pose.get("id", "")))


## Scale of the sheet in the room's canvas: her height there (`height`, canvas px) over her height in the sheet.
func sheet_scale(pose: Dictionary) -> float:
	var sheet_h := float(nina_meta.get("character_height_m", 1.63)) * float(nina_meta.get("px_per_m", 300.0))
	return float(pose.get("height", 300.0)) / maxf(1.0, sheet_h)


func _draw_nina(pose: Dictionary) -> void:
	for c in nina.get_children():
		c.queue_free()
	nina_sprite = null
	nina_pose = pose
	nina.position = Vector2.ZERO
	var layer := String(pose.get("room_layer", ""))
	pose_layer.visible = layer != "" and ResourceLoader.exists(layer)
	if pose_layer.visible:
		pose_layer.texture = load(layer)
	var at := v2(pose.get("at", [300, 440]))
	var sid := pose_sheet(pose)
	if nina_sheets.has(sid):
		var spr := AnimatedSprite2D.new()
		spr.name = "Figure"
		spr.sprite_frames = nina_sheets[sid]["frames"]
		spr.centered = false
		var piv: Dictionary = nina_meta.get("pivot", {})
		spr.offset = -Vector2(float(piv.get("x", 0.5)) * float(nina_meta.get("frame_w", 288)), float(piv.get("y", 0.95)) * float(nina_meta.get("frame_h", 384)))
		var k := sheet_scale(pose)
		spr.scale = Vector2(k, k)
		spr.position = at
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if pose.has("shadow_m"):
			spr.add_child(ActorShadow.make_size(float(pose["shadow_m"]) * float(nina_meta.get("px_per_m", 300.0)), 0.3, 0.42))
		walk_pos = at
		walk_dir = -1
		spr.animation = _row_anim(sid, walk_dir)
		spr.speed_scale = motion_speed()
		spr.play()
		nina.add_child(spr)
		nina_sprite = spr
		return
	_draw_silhouette(pose, at)


## The row of a sheet facing the way she walks (rows[].dir: [-1, 0] — to the left, [1, 0] — to the right).
func _row_anim(sid: String, dir_x: int) -> String:
	var rows: Array = (nina_sheets[sid]["act"] as Dictionary).get("rows", [])
	for r in rows.size():
		var d = (rows[r] as Dictionary).get("dir", null)
		if d is Array and signi(int(d[0])) == dir_x:
			return "r%d" % r
	return "r0"


## Walking (`path`): along the path and back, at the pace her feet set (the sheet's ground speed — the planted
## foot stays on the floor), turning at the ends.
func _move_nina(delta: float) -> void:
	if nina_sprite == null or not nina_pose.has("path"):
		return
	var path: Array = nina_pose["path"]
	var a := v2(path[0])
	var b := v2(path[path.size() - 1])
	var act: Dictionary = nina_sheets[pose_sheet(nina_pose)]["act"]
	var px_per_m := float(nina_pose.get("height", 300.0)) / float(nina_meta.get("character_height_m", 1.63))
	var step := float(act.get("ground_speed_mps", 1.0)) * px_per_m * motion_speed() * delta
	var lo := minf(a.x, b.x)
	var hi := maxf(a.x, b.x)
	walk_pos.x += step * walk_dir
	if walk_pos.x <= lo or walk_pos.x >= hi:
		walk_pos.x = clampf(walk_pos.x, lo, hi)
		walk_dir = -walk_dir
		var f := nina_sprite.frame
		nina_sprite.animation = _row_anim(pose_sheet(nina_pose), walk_dir)
		nina_sprite.play()
		nina_sprite.frame = f
	var t := 0.0 if is_equal_approx(hi, lo) else (walk_pos.x - a.x) / (b.x - a.x)
	walk_pos.y = lerpf(a.y, b.y, clampf(t, 0.0, 1.0))
	nina_sprite.position = walk_pos


## No sheet for the pose: the engine's grey-haired silhouette (as before the figure came).
func _draw_silhouette(pose: Dictionary, at: Vector2) -> void:
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
	_move_nina(delta)
	# A while at the glass without comparing: Agata thinks of her own watch (once per opening).
	if not holding and not _hinted and fclock.real_s >= float(spec.get("watch_hint_s", 20.0)) and not dialogue_up() \
			and not flag(String(spec.get("compared_flag", "nina_time_compared"))):
		_hinted = true
		say("watch_hint")
	if holding:
		hold_s += delta
		watch.seconds += delta
		if not compared_sent and hold_s >= float(spec.get("compare_s", 10.0)) and not dialogue_up():
			compared_sent = true
			event("compared")
	_update_room()


# --- Input ----------------------------------------------------------------------------------

func _watch_item() -> String:
	return String(spec.get("watch_item", "pocket_watch"))


## A click on the glass (or on the clock up close): with the watch in hand Agata holds it to the glass; with
## another thing in hand — it does nothing here; with empty hands — a knock, Nina does not turn.
func _on_glass_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _use_held_item():
			return
		knocks += 1
		sound("knock")
		if knocks == 1:
			say("knock_first")


func _on_slot_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _use_held_item():
			return
		if not holding:
			say("watch_slot_empty")


## The item in hand used on the mirror. True when something was in hand (handled).
func _use_held_item() -> bool:
	var held := String(StoryRunner.selected_item)
	if held == "":
		return false
	StoryRunner.select_item("")
	if held == _watch_item():
		hold_watch()
	else:
		wrong_items += 1
		say("wrong_item")
	return true


## Agata holds her pocket watch to the glass: both clocks go side by side; the comparison comes after
## `compare_s` real seconds (event "compared"). Again after the comparison — the rule as a reminder.
func hold_watch() -> bool:
	if holding:
		return false
	holding = true
	hold_s = 0.0
	hold_start_nina = fclock.nina_elapsed_minutes()
	watch.visible = true
	watch.run = false   # the panel's clock drives it: Agata's seconds are exactly the mirror's real seconds
	slot_hint.visible = false
	sound("knock")
	if flag(String(spec.get("compared_flag", "nina_time_compared"))):
		compared_sent = true
		say("watch_again")
	else:
		say("watch_hold")
	return true


## Tests: the comparison as the player makes it (hold the watch; the event comes after compare_s).
func compare() -> bool:
	return hold_watch()


func probe() -> Dictionary:
	return {"ratio": fclock.ratio, "real_s": fclock.real_s, "nina_minutes": fclock.nina_minutes(),
		"nina_elapsed": fclock.nina_elapsed_minutes(), "minute_deg": fclock.minute_hand_deg(), "hour_deg": fclock.hour_hand_deg(),
		"second_deg": loupe_sec.rotation_degrees if loupe_sec != null else -1.0,
		"loupe_minute_deg": loupe_min.rotation_degrees if loupe_min != null else 0.0,
		"pendulum_deg": loupe_pend.rotation_degrees if loupe_pend != null else 0.0, "pose": pose_id,
		"poses_seen": poses_seen.duplicate(), "knocks": knocks, "glass": center_of(room), "loupe": center_of(loupe),
		"watch": center_of(slot), "holding": holding, "hold_s": hold_s, "compared": compared_sent,
		"watch_minute_deg": watch.minute_deg() if watch != null else 0.0, "wrong_items": wrong_items,
		"nina": nina_probe()}


## Nina as drawn: from which sheet, where (canvas px of the room) and how tall; the visible part of the frame.
func nina_probe() -> Dictionary:
	if nina_sprite == null:
		return {"sheet": "", "silhouette": nina.get_child_count() > 0}
	return {"sheet": pose_sheet(nina_pose), "pose": pose_id, "at": [nina_sprite.position.x, nina_sprite.position.y],
		"scale": nina_sprite.scale.x,
		"height": sheet_scale(nina_pose) * float(nina_meta.get("character_height_m", 1.63)) * float(nina_meta.get("px_per_m", 300.0)),
		"animation": String(nina_sprite.animation), "playing": nina_sprite.is_playing(), "speed_scale": nina_sprite.speed_scale,
		"frames": nina_sprite.sprite_frames.get_frame_count(nina_sprite.animation)}
