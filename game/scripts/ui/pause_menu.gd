class_name PauseMenu
extends CanvasLayer
## Pause menu (Director 23.10: «паузы меню должно всплывать на первый план, чуть замыливая картинку на экране … по
## нажатию Esc»): the carved wooden board at the bottom of the screen (H58, Director 24.10 — art of batch 10a,
## game/assets/ui/menu/pause_panel.png, «Пауза» cut in the art) pops up over the game frame, which is slightly
## blurred and dimmed behind it (pause_blur.gdshader on the screen texture). Two rows drawn here on the empty wood
## (texts ui.pause_*, data/story/menu.json pause): Продолжить, Сохранить, Загрузить / Настройки, В главное меню,
## Выход из игры (not on the web); hover — as on the title menu: a warm glow, two golden lines and the leaf;
## «Esc — вернуться» under the short bottom ornament, centred.
##
## While it is open the tree is paused (Main syncs it from `visibility_changed`): game time, walking, NPCs, lines,
## stagings and mini-games stand still; a voice line is held and resumes. This layer always runs.
## Esc (handle_escape): a close-up or a mechanic closes itself first (their own _input; a mechanic that cannot be
## left — the boat's crossing — keeps Esc, the «Меню» button above it still pauses); then the save / settings panel,
## the journal or the plan; only with nothing open does Esc open the pause — and Esc again closes it.

signal action_taken(id: String)

const LAYER := 50

var game_ui: Node = null       # GameUi: the save / load / settings panel, the journal and the plan
var title: Node = null         # TitleScreen: «В главное меню»
var blur: ColorRect
var sheet: Control             # the board with the items: pops in as one
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
var _leaf: Texture2D = null
var _glow: GradientTexture2D = null


func _ready() -> void:
	set_meta("ui_click", true)   # K (Director 31.10, стр. 1): the menu's buttons tick and click (SfxDirector)
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
	panel.name = "Board"
	panel.texture = MenuConfig.texture("pause_panel.png")
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.position = Vector2(0, oy)
	panel.size = MenuConfig.SCREEN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(panel)
	# The board's middle is the pivot of the pop-in.
	sheet.pivot_offset = Vector2(960, (float(_lay.get("pivot_y", 787)) + float(_lay.get("offset_y", 0))) * MenuConfig.sy())
	_leaf = MenuConfig.texture("title_leaf.png")
	_glow = GradientTexture2D.new()
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(0.5, 0.0)
	_glow.width = 128
	_glow.height = 32
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_glow.gradient = g
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
	hint.add_theme_color_override("font_color", MenuConfig.color(_lay.get("hint_color"), Color(0.8, 0.68, 0.5)))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	hint.add_theme_constant_override("shadow_offset_y", 2)
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
	var cols: Array = _lay.get("col_x", [512, 840, 1168])
	var rows: Array = _lay.get("baselines", [752, 814])
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


## The save / load / settings panel opens over the blurred frame alone: the board steps aside while it is up.
func _process(_delta: float) -> void:
	if visible and game_ui != null:
		sheet.visible = not bool(game_ui.call("menu_panel_open"))


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
	var fs := int(_lay.get("font_px", 40))
	var text_c := MenuConfig.color(_lay.get("text_color"), Color(0.86, 0.79, 0.68))
	var hover_c := MenuConfig.color(_lay.get("hover_color"), Color(1, 0.86, 0.6))
	var line_c := MenuConfig.color(_lay.get("line_color"), Color(1, 0.72, 0.36))
	var glow_c := MenuConfig.color(_lay.get("glow_color"), Color(1, 0.62, 0.25, 0.3))
	var rows: Array = _lay.get("baselines", [752, 814])
	var cols: Array = _lay.get("col_x", [512, 840, 1168])
	var top_k := float(_lay.get("hl_top", 38))
	var bot_k := float(_lay.get("hl_bottom", 17))
	for id in order:
		var it := _item(id)
		var cx := float(cols[int(it.get("col", 0))]) * sx
		var bl := (float(rows[int(it.get("row", 0))]) + oy) * sy
		var w := _font.get_string_size(labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(cx - w / 2, bl)
		if id == hovered and not bool(disabled.get(id, false)):
			# As on the title menu: the glow, two golden rules fading at the ends, the leaf before the word.
			var half := maxf(float(_lay.get("col_w", 300)) * sx, w + 110.0) * 0.5
			var top := bl - top_k * sy
			var bot := bl + bot_k * sy
			decor.draw_texture_rect(_glow, Rect2(cx - half - 24, top - 6, half * 2 + 48, bot - top + 12), false, glow_c)
			for y in [top, bot]:
				_golden_line(cx - half, cx + half, y, line_c)
			if _leaf != null:
				var lh := (bot - top) * 0.92
				var lw := lh * float(_leaf.get_width()) / maxf(1.0, float(_leaf.get_height()))
				decor.draw_texture_rect(_leaf, Rect2(base.x - lw - 14, (top + bot) * 0.5 - lh * 0.5, lw, lh), false)
		var col := hover_c if id == hovered else text_c
		if bool(disabled.get(id, false)):
			col = Color(text_c, 0.38)
		decor.draw_string(_font, base + Vector2(0, 2), labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		decor.draw_string(_font, base, labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A golden rule of the highlight (the title menu's): bright in the middle, fading out at both ends.
func _golden_line(x0: float, x1: float, y: float, c: Color) -> void:
	var pts := PackedVector2Array([Vector2(x0, y), Vector2(x0 + 50, y), Vector2(x1 - 50, y), Vector2(x1, y)])
	decor.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.22), Color(c, 0.22), Color(c, 0)]), 7.0, true)
	decor.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.95), Color(c, 0.95), Color(c, 0)]), 2.0, true)


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
