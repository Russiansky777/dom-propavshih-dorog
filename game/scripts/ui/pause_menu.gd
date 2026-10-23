class_name PauseMenu
extends CanvasLayer
## Pause menu (Director 23.10: «паузы меню должно всплывать на первый план, чуть замыливая картинку на экране … по
## нажатию Esc»): the embroidered towel (game/assets/ui/menu/pause_panel.png, ChatGPT's clean layer with the title
## «Пауза» and the borders) pops up over the game frame, which is slightly blurred and dimmed behind it
## (pause_blur.gdshader on the screen texture). Two columns drawn here (texts ui.pause_*, data/story/menu.json pause):
## Продолжить, Сохранить, Загрузить | Настройки, В главное меню, Выход из игры (not on the web); hover — a red
## cross-stitch frame drawn in code; «Esc — вернуться» in the gap of the bottom border.
##
## While it is open the tree is paused (Main syncs it from `visibility_changed`): game time, walking, NPCs, lines,
## stagings and mini-games stand still; a voice line is held and resumes. This layer always runs.
## Esc (handle_escape): a close-up or a mechanic closes itself first (their own _input); then the save / settings
## panel, the journal or the plan; only with nothing open does Esc open the pause — and Esc again closes it.

signal action_taken(id: String)

const LAYER := 50
const FRAME_STAR := ["...X...", "..X.X..", ".X.X.X.", "X.XXX.X", ".X.X.X.", "..X.X..", "...X..."]

var game_ui: Node = null       # GameUi: the save / load / settings panel, the journal and the plan
var title: Node = null         # TitleScreen: «В главное меню»
var blur: ColorRect
var sheet: Control             # the towel with the items: pops in as one
var panel: TextureRect
var decor: Control
var hint: Label
var buttons: Dictionary = {}   # item id -> Button (a transparent hit area; the text is drawn by `decor`)
var order: Array = []          # visible item ids
var labels: Dictionary = {}
var hovered: String = ""
var disabled: Dictionary = {}  # item id -> true: Save / Load while a line, a close-up or a staging is on
var actions: Array = []        # tests / probe

var _lay: Dictionary = {}
var _font: Font
var _tween: Tween = null
var _hint_text: String = ""


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var p := MenuConfig.section("pause")
	_lay = p.get("layout", {})
	_font = UiTheme.font("body_bold")
	_build(p)
	# A save loaded from the panel over the pause (or a new game): the game goes on.
	GameState.state_loaded.connect(func(_s): close())
	GameState.state_reset.connect(close)


func _build(p: Dictionary) -> void:
	var b_cfg: Dictionary = p.get("blur", {})
	blur = ColorRect.new()
	blur.name = "Blur"
	blur.size = MenuConfig.SCREEN
	blur.mouse_filter = Control.MOUSE_FILTER_STOP   # the game below gets no clicks while paused
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pause_blur.gdshader")
	mat.set_shader_parameter("radius_px", float(b_cfg.get("radius_px", 3.2)))
	mat.set_shader_parameter("dim", float(b_cfg.get("dim", 0.62)))
	blur.material = mat
	add_child(blur)
	sheet = Control.new()
	sheet.name = "Sheet"
	sheet.size = MenuConfig.SCREEN
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
	var oy := float(_lay.get("offset_y", 0)) * MenuConfig.sy()
	panel = TextureRect.new()
	panel.name = "Towel"
	panel.texture = MenuConfig.texture("pause_panel.png")
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.position = Vector2(0, oy)
	panel.size = MenuConfig.SCREEN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(panel)
	# The towel's middle (art y 449–876) is the pivot of the pop-in.
	sheet.pivot_offset = Vector2(960, (662.0 + float(_lay.get("offset_y", 0))) * MenuConfig.sy())
	decor = Control.new()
	decor.name = "Decor"
	decor.size = MenuConfig.SCREEN
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.draw.connect(_draw_decor)
	sheet.add_child(decor)
	var empty := StyleBoxEmpty.new()
	for it in p.get("items", []):
		var id := String(it.get("id", ""))
		var b := Button.new()
		b.name = "Pause_" + id
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		b.mouse_entered.connect(_on_hover.bind(id))
		b.pressed.connect(activate.bind(id))
		sheet.add_child(b)
		buttons[id] = b
		labels[id] = StoryData.text(String(it.get("text", id)))
	hint = Label.new()
	hint.name = "EscHint"
	hint.add_theme_font_override("font", UiTheme.font("body"))
	hint.add_theme_font_size_override("font_size", int(_lay.get("hint_px", 22)))
	hint.add_theme_color_override("font_color", MenuConfig.color(_lay.get("text_color"), Color(0.15, 0.12, 0.1)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(hint)
	_hint_text = StoryData.text("@ui.pause_esc_hint")
	_layout()


func _layout() -> void:
	order.clear()
	for it in MenuConfig.items("pause"):
		order.append(String(it.get("id", "")))
	var sx := MenuConfig.sx()
	var sy := MenuConfig.sy()
	var oy := float(_lay.get("offset_y", 0))
	var w := float(_lay.get("col_w", 380))
	var h := float(_lay.get("row_h", 70))
	for it in MenuConfig.section("pause").get("items", []):
		var id := String(it.get("id", ""))
		var b: Button = buttons[id]
		b.visible = order.has(id)
		var c := _cell_centre_art(it)
		b.position = Vector2((c.x - w / 2) * sx, (c.y - h / 2 + oy) * sy)
		b.size = Vector2(w * sx, h * sy)
	hint.text = _hint_text
	hint.size = Vector2(600, 40)
	var hb := (float(_lay.get("hint_baseline", 849)) + oy) * sy
	var f := hint.get_theme_font("font")
	var fs := hint.get_theme_font_size("font_size")
	hint.position = Vector2(float(_lay.get("hint_x", 832)) * sx - 300, hb - f.get_ascent(fs))


## Centre of an item's cell in art px (before the vertical offset): its column, its row's baseline − half a cap.
func _cell_centre_art(it: Dictionary) -> Vector2:
	var cols: Array = _lay.get("col_x", [651, 1052])
	var rows: Array = _lay.get("baselines", [633, 713, 793])
	return Vector2(float(cols[int(it.get("col", 0))]), float(rows[int(it.get("row", 0))]) - 13.0)


func _item(id: String) -> Dictionary:
	for it in MenuConfig.section("pause").get("items", []):
		if String(it.get("id", "")) == id:
			return it
	return {}


# --- Open / close ---------------------------------------------------------------------------

func is_open() -> bool:
	return visible


func open() -> void:
	if visible or (title != null and bool(title.call("is_open"))):
		return
	if game_ui != null:
		game_ui.call("prepare_for_pause")
	# Saving or loading in the middle of a line, a close-up or a staging would bring a save back mid-scene.
	var busy := StoryRunner.is_busy() or StoryRunner.current_frame != ""
	disabled = {"save": busy, "load": busy}
	hint.text = _hint_text
	hovered = "continue"
	visible = true
	VoiceDirector.set_paused(true)
	var fade := float(MenuConfig.section("pause").get("blur", {}).get("fade_s", 0.18))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	(blur.material as ShaderMaterial).set_shader_parameter("amount", 0.0)
	sheet.modulate.a = 0.0
	sheet.scale = Vector2(0.96, 0.96)
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(v: float): (blur.material as ShaderMaterial).set_shader_parameter("amount", v), 0.0, 1.0, fade)
	_tween.tween_property(sheet, "modulate:a", 1.0, fade)
	_tween.tween_property(sheet, "scale", Vector2.ONE, fade * 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	decor.queue_redraw()


func close() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if game_ui != null:
		game_ui.call("close_menu_panel")
	visible = false
	VoiceDirector.set_paused(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Esc, by the rule: an open save / settings panel, then the pause itself, then the journal or the plan; with nothing
## open — the pause opens. Close-ups and mechanics close themselves before this (their own _input). Returns true when
## Esc was used.
func handle_escape() -> bool:
	if game_ui != null and bool(game_ui.call("close_menu_panel")):
		return true
	if title != null and bool(title.call("is_open")):
		return false
	if visible:
		close()
		return true
	if game_ui != null and bool(game_ui.call("close_top_panel")):
		return true
	open()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if handle_escape():
			get_viewport().set_input_as_handled()


# --- Actions ----------------------------------------------------------------------------------

func activate(id: String) -> void:
	if not visible or not order.has(id):
		return
	if bool(disabled.get(id, false)):
		hint.text = StoryData.text("@ui.pause_busy")
		return
	actions.append(id)
	action_taken.emit(id)
	match id:
		"continue":
			close()
		"save", "load", "settings":
			if game_ui != null:
				game_ui.call("open_menu_panel", id)
		"main_menu":
			RoomManager.autosave()   # written now when nothing is going on; mid-line the last autosave stays
			close()
			GameState.reset()        # the running scene, its lines and close-ups end here
			if title != null:
				title.call("open")
		"quit":
			get_tree().quit()


func _on_hover(id: String) -> void:
	if hovered != id:
		hovered = id
		decor.queue_redraw()


# --- Drawing ----------------------------------------------------------------------------------

func _draw_decor() -> void:
	var sx := MenuConfig.sx()
	var sy := MenuConfig.sy()
	var oy := float(_lay.get("offset_y", 0))
	var fs := int(_lay.get("font_px", 42))
	var text_c := MenuConfig.color(_lay.get("text_color"), Color(0.15, 0.12, 0.1))
	var hover_c := MenuConfig.color(_lay.get("hover_color"), Color(0.55, 0.06, 0.07))
	var red := MenuConfig.color(_lay.get("red"), Color(0.62, 0.09, 0.09))
	var rows: Array = _lay.get("baselines", [633, 713, 793])
	var cols: Array = _lay.get("col_x", [651, 1052])
	var dy := float(_lay.get("divider_dy", 34))
	# Dividers under every row of both columns: a thin red line, a rhomb in the middle, dots at the ends.
	for c in cols.size():
		for r in rows.size():
			var y := (float(rows[r]) + dy + oy) * sy
			var cx := float(cols[c]) * sx
			var half := 168.0 * sx
			decor.draw_line(Vector2(cx - half + 8, y), Vector2(cx - 12, y), Color(red, 0.85), 1.6, true)
			decor.draw_line(Vector2(cx + 12, y), Vector2(cx + half - 8, y), Color(red, 0.85), 1.6, true)
			_rhomb(Vector2(cx, y), 6.0, red)
			_rhomb(Vector2(cx - half, y), 3.2, red)
			_rhomb(Vector2(cx + half, y), 3.2, red)
	for id in order:
		var it := _item(id)
		var cc := _cell_centre_art(it)
		var base := Vector2(cc.x * sx, (float(rows[int(it.get("row", 0))]) + oy) * sy)
		var w := _font.get_string_size(labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if id == hovered:
			# As wide as the column, or wider for a long word: the stars at the ends never touch the letters.
			var fw := maxf(float(_lay.get("col_w", 380)) * sx, w + 128.0)
			var fh := float(_lay.get("row_h", 66)) * sy
			_embroidered_frame(Rect2(cc.x * sx - fw / 2, (cc.y + oy) * sy - fh / 2, fw, fh), red)
		var col := hover_c if id == hovered else text_c
		if bool(disabled.get(id, false)):
			col = Color(text_c, 0.38)
		decor.draw_string(_font, base - Vector2(w / 2, 0), labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The hover frame, embroidered like the towel's borders: an outer red rule with cut corners, an inner row of cross
## stitches, and a cross-stitch star at each end.
func _embroidered_frame(r: Rect2, red: Color) -> void:
	var k := 9.0
	var o := PackedVector2Array([
		r.position + Vector2(k, 0), Vector2(r.end.x - k, r.position.y), Vector2(r.end.x, r.position.y + k),
		Vector2(r.end.x, r.end.y - k), Vector2(r.end.x - k, r.end.y), Vector2(r.position.x + k, r.end.y),
		Vector2(r.position.x, r.end.y - k), r.position + Vector2(0, k), r.position + Vector2(k, 0)])
	decor.draw_polyline(o, red, 2.6, true)
	var ins := r.grow(-6.0)
	var step := 7.0
	var x := ins.position.x + 4.0
	while x < ins.end.x - 3.0:
		_stitch(Vector2(x, ins.position.y), red)
		_stitch(Vector2(x, ins.end.y), red)
		x += step
	var y := ins.position.y + step
	while y < ins.end.y - 3.0:
		_stitch(Vector2(ins.position.x, y), red)
		_stitch(Vector2(ins.end.x, y), red)
		y += step
	var cell := 3.4
	for side in [r.position.x + 30.0, r.end.x - 30.0]:
		var top := Vector2(side - cell * 3.5, r.get_center().y - cell * 3.5)
		for j in FRAME_STAR.size():
			var line: String = FRAME_STAR[j]
			for i in line.length():
				if line[i] == "X":
					decor.draw_rect(Rect2(top + Vector2(i, j) * cell, Vector2(cell - 0.6, cell - 0.6)), red)


func _stitch(at: Vector2, c: Color) -> void:
	decor.draw_line(at + Vector2(-1.6, -1.6), at + Vector2(1.6, 1.6), c, 1.3, true)
	decor.draw_line(at + Vector2(-1.6, 1.6), at + Vector2(1.6, -1.6), c, 1.3, true)


func _rhomb(at: Vector2, r: float, c: Color) -> void:
	decor.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, 0), at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r)]), c)


# --- Probe ----------------------------------------------------------------------------------

## window.probeState.pause: open, the items (id → centre, text, disabled), the hovered one, the hint line, the blur.
func probe() -> Dictionary:
	var items := {}
	for id in order:
		var r := (buttons[id] as Button).get_global_rect()
		items[id] = {"x": r.get_center().x, "y": r.get_center().y, "text": labels[id], "disabled": bool(disabled.get(id, false))}
	var amount = (blur.material as ShaderMaterial).get_shader_parameter("amount")
	return {"open": visible, "items": items, "order": order, "hovered": hovered, "hint": hint.text,
		"blur": float(amount) if amount != null else 0.0, "actions": actions}
