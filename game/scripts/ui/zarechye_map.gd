class_name ZarechyeMap
extends Control
## The Zarechye plan up close (Director 17.10: «план Заречья должен быть интерактивным … если игрок
## заблудится, с подписями, что где»). Opened by a hotspot with `panel.id` = this plan's id (Z1.plan)
## or from the journal («План») once `journal_flag` is set; closed by a click or Esc.
##
## The picture "rides in" from where the plan hangs on the wall (the hotspot rect) to almost full
## screen; the room stays behind it, darkened at the edges. Over the picture, in the game typeface:
## place names (locations.json, or @map.* for places of several rooms), a dot at each place, «Вы здесь»
## at the place of the current room; places not visited yet (no visited_<room> flag) are paler,
## places with hidden_until_visited (Olkhovka across the river) appear only after a visit; `shown_if` [flags] — shown
## once those flags hold, visited or not (the ferry workshop across the river once the far bank is reached).
## G2 (Director 23.10: «нанести на карту то, что изменилось или добавилось»): `overlays` [{image, if}] — pictures on the
## plan's own canvas laid over it while their flags hold (art pack 9: the school, the houses, the rope crossing, the
## boat and the shed across the river — zarechye_plan_overlay, once the far bank is reached).
## Everything placed comes from data/story/map_zarechye.json; the UI never sets story flags.

signal closed(reopen_journal: bool)

const DATA_PATH := "res://data/story/map_zarechye.json"
const OPEN_S: float = 0.65
const CLOSE_S: float = 0.42
const FIT := Vector2(1760, 960)        # the picture fits this box, centred
const BACKDROP := Color(0.035, 0.022, 0.014, 0.76)
const INK := Color(0.33, 0.15, 0.08)
const HERE := Color(0.72, 0.17, 0.10)

var spec: Dictionary = {}
var backdrop: ColorRect
var plan: TextureRect
var marks: Control
var caption: Label
var close_hint: Label
var settled: bool = false
var from_journal: bool = false
var here_place: String = ""
var place_nodes: Dictionary = {}       # place id -> {label: Label, dot: Control, visited, shown}
var _src: Rect2
var _final: Rect2
var _tween: Tween = null
var _closing: bool = false
var _scale: float = 1.0
var overlays: Array = []               # [{node: TextureRect, if: [flags]}] — G2


func _init() -> void:
	name = "ZarechyeMap"
	visible = false
	position = Vector2.ZERO
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(BACKDROP, 0.0)
	backdrop.size = size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	plan = TextureRect.new()
	plan.name = "Plan"
	plan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plan.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # a crop while small, whole at the end
	plan.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plan)
	marks = Control.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marks)
	caption = Label.new()
	caption.name = "Caption"
	caption.theme_type_variation = &"HintLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	close_hint = Label.new()
	close_hint.name = "CloseHint"
	close_hint.theme_type_variation = &"MapHint"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(close_hint)


func _ready() -> void:
	spec = load_spec()
	var img := String(spec.get("image", ""))
	if img != "" and ResourceLoader.exists(img):
		plan.texture = load(img)
	for o in spec.get("overlays", []):
		var oi := String(o.get("image", ""))
		if oi == "" or not ResourceLoader.exists(oi):
			continue
		var tr := TextureRect.new()
		tr.name = "Overlay_" + oi.get_file().get_basename()
		tr.texture = load(oi)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # the same crop as the plan under it
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		plan.add_child(tr)
		overlays.append({"node": tr, "if": o.get("if", [])})
	var isz: Array = spec.get("image_size", [1376, 768])
	var aspect := float(isz[0]) / float(isz[1])
	var w := minf(FIT.x, FIT.y * aspect)
	var h := w / aspect
	_final = Rect2(Vector2((1920.0 - w) / 2.0, (1080.0 - h) / 2.0).round(), Vector2(w, h).round())
	_scale = w / float(isz[0])
	GameState.state_loaded.connect(func(_s): close_now())
	GameState.state_reset.connect(close_now)


static func load_spec() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("ZarechyeMap: no " + DATA_PATH)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return d if d is Dictionary else {}


func panel_id() -> String:
	return String(spec.get("id", "map_zarechye"))


func journal_flag() -> String:
	return String(spec.get("journal_flag", ""))


## The plan may be opened from the journal once its flag is set (it was seen on the wall).
func available_in_journal() -> bool:
	var f := journal_flag()
	return f != "" and GameState.has_flag(f)


func is_open() -> bool:
	return visible and not _closing


# --- Places ----------------------------------------------------------------------------

func places() -> Array:
	return spec.get("places", [])


func place_name(p: Dictionary) -> String:
	if p.has("label"):
		return StoryData.text(String(p["label"]))
	var locs: Array = p.get("locs", [])
	return StoryData.location_name(String(locs[0])) if not locs.is_empty() else String(p.get("id", ""))


func place_visited(p: Dictionary) -> bool:
	for l in p.get("locs", []):
		if GameState.has_flag("visited_" + String(l)):
			return true
	return false


func place_of_room(room_id: String) -> String:
	for p in places():
		if (p.get("locs", []) as Array).has(room_id):
			return String(p.get("id", ""))
	return ""


func _point(p: Dictionary) -> Vector2:
	var pt: Array = p.get("point", [0, 0])
	return Vector2(float(pt[0]), float(pt[1])) * _scale


func _build_marks() -> void:
	for o in overlays:
		(o["node"] as CanvasItem).visible = (o["if"] as Array).all(func(f): return GameState.has_flag(String(f)))
	for c in marks.get_children():
		c.queue_free()
	place_nodes.clear()
	marks.position = _final.position
	marks.size = _final.size
	here_place = place_of_room(GameState.current_room)
	for p in places():
		var id := String(p.get("id", ""))
		var visited := place_visited(p)
		var shown := visited or not bool(p.get("hidden_until_visited", false))
		if p.has("shown_if"):
			shown = (p["shown_if"] as Array).all(func(f): return GameState.has_flag(String(f)))
		var entry := {"label": null, "dot": null, "visited": visited, "shown": shown, "text": place_name(p)}
		place_nodes[id] = entry
		if not shown:
			continue
		var at := _point(p)
		var dot := MapDot.new()
		dot.name = "Dot_" + id
		dot.here = id == here_place
		dot.visited = visited
		dot.position = at - dot.size / 2.0
		marks.add_child(dot)
		var l := Label.new()
		l.name = "Label_" + id
		l.text = entry["text"]
		l.theme_type_variation = &"MapLabelHere" if id == here_place else (&"MapLabel" if visited else &"MapLabelFaint")
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marks.add_child(l)
		l.reset_size()
		l.position = _aligned(at, l.get_combined_minimum_size(), String(p.get("align", "above")), 14.0)
		if not visited:
			dot.modulate = Color(1, 1, 1, 0.55)   # the label is paler by its own style (still readable)
		entry["label"] = l
		entry["dot"] = dot
		if id == here_place:
			# «Вы здесь» on the side opposite to the name.
			var hl := Label.new()
			hl.name = "Here"
			hl.text = StoryData.text("@map.here")
			hl.theme_type_variation = &"MapHereLabel"
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			marks.add_child(hl)
			hl.reset_size()
			var side := "above" if String(p.get("align", "above")) == "below" else "below"
			hl.position = _aligned(at, hl.get_combined_minimum_size(), side, 16.0)
			entry["here_label"] = hl


static func _aligned(at: Vector2, sz: Vector2, align: String, gap: float) -> Vector2:
	match align:
		"below":
			return (at + Vector2(-sz.x / 2.0, gap)).round()
		"left":
			return (at + Vector2(-sz.x - gap, -sz.y / 2.0)).round()
		"right":
			return (at + Vector2(gap, -sz.y / 2.0)).round()
		"center":
			return (at - sz / 2.0).round()
	return (at + Vector2(-sz.x / 2.0, -sz.y - gap)).round()


# --- Open / close -----------------------------------------------------------------------

## `src` — where the picture starts (the plan on the wall, in screen coordinates). From the journal
## it starts small in the middle; closing then goes back to the journal.
func open_from(src: Rect2, journal: bool = false) -> void:
	if plan.texture == null:
		push_warning("ZarechyeMap: plan picture missing (%s)" % String(spec.get("image", "")))
	from_journal = journal
	_closing = false
	settled = false
	_src = src if src.size.x > 4.0 else Rect2(Vector2(960, 540) - Vector2(190, 106), Vector2(380, 212))
	_build_marks()
	caption.text = StoryData.text(String(spec.get("caption", ""))) if spec.has("caption") else ""
	caption.position = Vector2(_final.position.x + 40, _final.end.y - 58)
	caption.size = Vector2(_final.size.x - 80, 52)
	close_hint.text = StoryData.text("@map.close_hint")
	close_hint.position = Vector2(_final.end.x - 640, _final.position.y + 6)
	close_hint.size = Vector2(620, 30)
	_set_rect(0.0)
	plan.modulate.a = 0.0
	marks.modulate.a = 0.0
	caption.modulate.a = 0.0
	close_hint.modulate.a = 0.0
	backdrop.color = Color(BACKDROP, 0.0)
	visible = true
	_kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_rect, 0.0, 1.0, OPEN_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(plan, "modulate:a", 1.0, 0.22)
	_tween.tween_property(backdrop, "color:a", BACKDROP.a, OPEN_S)
	_tween.chain().tween_property(marks, "modulate:a", 1.0, 0.25)
	_tween.tween_property(caption, "modulate:a", 1.0, 0.3)
	_tween.tween_property(close_hint, "modulate:a", 0.85, 0.3)
	_tween.chain().tween_callback(func(): settled = true)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	settled = false
	_kill()
	_tween = create_tween()
	_tween.tween_property(marks, "modulate:a", 0.0, 0.1)
	_tween.parallel().tween_property(caption, "modulate:a", 0.0, 0.1)
	_tween.parallel().tween_property(close_hint, "modulate:a", 0.0, 0.1)
	_tween.tween_method(_set_rect, 1.0, 0.0, CLOSE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(backdrop, "color:a", 0.0, CLOSE_S)
	_tween.parallel().tween_property(plan, "modulate:a", 0.0, CLOSE_S * 0.6).set_delay(CLOSE_S * 0.4)
	_tween.tween_callback(_finish_close)


## Load / new game: away at once, no animation, no journal.
func close_now() -> void:
	_kill()
	if visible:
		visible = false
		_closing = false
		settled = false


func _finish_close() -> void:
	visible = false
	_closing = false
	closed.emit(from_journal)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _set_rect(t: float) -> void:
	plan.position = _src.position.lerp(_final.position, t)
	plan.size = _src.size.lerp(_final.size, t)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		close()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()


# --- Probe ------------------------------------------------------------------------------

func probe() -> Dictionary:
	var labels := {}
	for id in place_nodes.keys():
		var e: Dictionary = place_nodes[id]
		var d := {"visible": e["shown"] and visible, "visited": e["visited"], "text": e["text"]}
		if e["label"] != null:
			var r: Rect2 = (e["label"] as Control).get_global_rect()
			d["x"] = r.get_center().x
			d["y"] = r.get_center().y
		labels[id] = d
	return {"settled": settled, "here": here_place, "here_room": GameState.current_room, "labels": labels,
		"from_journal": from_journal, "rect": [plan.position.x, plan.position.y, plan.size.x, plan.size.y],
		"overlays": overlays.filter(func(o): return (o["node"] as CanvasItem).visible).map(func(o): return String((o["node"] as Node).name))}


## Ink dot at a place; the current place gets a pulsing red-ochre ring.
class MapDot extends Control:
	var here: bool = false
	var visited: bool = true
	var _t: float = 0.0

	func _init() -> void:
		size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if here:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		if here:
			var k := fmod(_t, 1.4) / 1.4
			draw_arc(c, 8.0 + 11.0 * k, 0.0, TAU, 32, Color(HERE, 0.75 * (1.0 - k)), 3.0, true)
			draw_circle(c, 8.0, Color(1.0, 0.95, 0.85, 0.9))
			draw_circle(c, 6.0, HERE)
		elif visited:
			draw_circle(c, 6.0, Color(1.0, 0.95, 0.85, 0.8))
			draw_circle(c, 4.5, INK)
		else:
			draw_arc(c, 5.0, 0.0, TAU, 20, INK, 2.0, true)
