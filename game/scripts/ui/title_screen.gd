class_name TitleScreen
extends CanvasLayer
## Title screen (main menu, Director 23.10): the carved panel over the river at dusk, shown on launch and by the pause
## menu's «В главное меню». The art is ChatGPT's clean frame (game/assets/ui/menu/title_bg.png) with the scratched
## signature as its own layer; the items are drawn here (texts ui.title_*, data/story/menu.json title) so hover
## works and the words can be translated. Hover: the leaf marker (cut from the original art) slides to the item,
## a warm glow and two golden lines frame it, as on the reference. Water, the birch and the near grass move and the
## window breathes — one shader over the art (title_bg.gdshader + title_fx_mask.png); nothing else moves.
##
## «Продолжить» — the newest save (autosave included), shown only when one exists; «Загрузить» / «Настройки» open
## the game's save and settings panel (GameUi.open_menu_panel) above this layer; «Выход» — not on the web.
## The tree is paused while the title is up (Main syncs it from `visibility_changed`); this layer always runs.

signal action_taken(id: String)

const LAYER := 60
const TOP := 47.5      # highlight row from baseline − TOP …
const BOTTOM := 24.5   # … to baseline + BOTTOM (art px; the reference's golden lines at 372 / 442 around 419.5)
const SLIDE_S := 0.16

var game_ui: Node = null              # GameUi: the save / load / settings panel
var slots_override: Array = []        # tests: the slots that count for «Продолжить» (default: every game slot)
var bg: TextureRect
var signature: TextureRect
var decor: Control
var leaf: TextureRect
var buttons: Dictionary = {}          # item id -> Button (a transparent hit area; the text is drawn by `decor`)
var order: Array = []                 # visible item ids, top to bottom
var labels: Dictionary = {}           # item id -> text
var highlighted: String = ""
var continue_slot: String = ""        # the save «Продолжить» loads ("" — none, the item is hidden)
var actions: Array = []               # tests / probe: activated items in order

var _lay: Dictionary = {}
var _font: FontVariation
var _hl_top: float = 0.0              # canvas y of the highlight row's top (slides between rows)
var _hl_tween: Tween = null
var _glow: GradientTexture2D


func _ready() -> void:
	set_meta("ui_click", true)   # K (Director 31.10, стр. 1): the menu's buttons tick and click (SfxDirector)
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var t := MenuConfig.section("title")
	_lay = t.get("layout", {})
	_font = FontVariation.new()
	_font.base_font = UiTheme.font("body")
	_font.spacing_glyph = int(_lay.get("glyph_spacing", 0))
	_build(t)
	GameState.state_loaded.connect(_on_state_loaded)


## «сборка 1a2b3c4 · 31.10 23:40» (local time of the build) from res://build_info.json {sha, utc}; "" without it.
static func build_stamp() -> String:
	if not FileAccess.file_exists("res://build_info.json"):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	if not (d is Dictionary) or String(d.get("sha", "")) == "":
		return ""
	var when := ""
	var utc := String(d.get("utc", ""))
	if utc.length() >= 16:
		var unix := Time.get_unix_time_from_datetime_string(utc.substr(0, 16) + ":00")
		var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
		var loc := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
		when = " · %02d.%02d %02d:%02d" % [loc.day, loc.month, loc.hour, loc.minute]
	return "сборка %s%s" % [String(d["sha"]), when]


func _build(t: Dictionary) -> void:
	bg = TextureRect.new()
	bg.name = "Background"
	bg.texture = MenuConfig.texture("title_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = MenuConfig.SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # the title catches every click: nothing of the game below
	var mask := MenuConfig.texture("title_fx_mask.png")
	if mask != null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/title_bg.gdshader")
		mat.set_shader_parameter("mask_tex", mask)
		mat.set_shader_parameter("art_size", MenuConfig.ART_SIZE)
		var fx: Dictionary = t.get("fx", {})
		for group in ["water", "sway", "window"]:
			var g: Dictionary = fx.get(group, {})
			for k in g.keys():
				mat.set_shader_parameter("%s_%s" % [group, k], float(g[k]))
		bg.material = mat
	add_child(bg)
	signature = TextureRect.new()
	signature.name = "Signature"
	signature.texture = MenuConfig.texture("title_signature.png")
	signature.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	signature.stretch_mode = TextureRect.STRETCH_SCALE
	signature.size = MenuConfig.SCREEN
	signature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	signature.visible = signature.texture != null
	add_child(signature)
	# K (31.10): which build this is — the commit and the time of the build (game/build_info.json, written by the
	# build workflow; absent in the editor), small in the bottom right corner, so a playthrough names its build.
	var stamp := Label.new()
	stamp.name = "BuildStamp"
	stamp.text = build_stamp()
	stamp.visible = stamp.text != ""
	stamp.add_theme_font_size_override("font_size", 15)
	stamp.add_theme_color_override("font_color", Color(0.94, 0.89, 0.79, 0.55))
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamp.size = Vector2(520, 24)
	stamp.position = MenuConfig.SCREEN - Vector2(540, 34)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor = Control.new()
	decor.name = "Decor"
	decor.size = MenuConfig.SCREEN
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.draw.connect(_draw_decor)
	add_child(decor)
	add_child(stamp)
	var box: Array = t.get("leaf_box", [110, 378, 166, 438])
	leaf = TextureRect.new()
	leaf.name = "Leaf"
	leaf.texture = MenuConfig.texture("title_leaf.png")
	leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	leaf.stretch_mode = TextureRect.STRETCH_SCALE
	leaf.size = MenuConfig.pt(float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(leaf)
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
	var empty := StyleBoxEmpty.new()
	for it in MenuConfig.section("title").get("items", []):
		var id := String(it.get("id", ""))
		var b := Button.new()
		b.name = "Title_" + id
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		b.mouse_entered.connect(set_highlight.bind(id))
		b.pressed.connect(activate.bind(id))
		add_child(b)
		buttons[id] = b
		labels[id] = StoryData.text(String(it.get("text", id)))


# --- Open / close ---------------------------------------------------------------------------

## A save loaded from the panel over the title («Загрузить»): the game is on — the title goes.
func _on_state_loaded(_slot: String) -> void:
	if visible:
		close()


func open() -> void:
	refresh()
	visible = true
	MusicDirector.play_menu_theme(String(MenuConfig.section("title").get("music", "")))


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Which items show (Continue only with a save, Quit only off the web) and where they stand.
func refresh() -> void:
	continue_slot = GameState.latest_save(slots_override if not slots_override.is_empty() else default_slots())
	order.clear()
	for it in MenuConfig.items("title"):
		var id := String(it.get("id", ""))
		if bool(it.get("needs_save", false)) and continue_slot == "":
			continue
		order.append(id)
	var sx := MenuConfig.sx()
	var sy := MenuConfig.sy()
	var left := float(_lay.get("row_left", 112))
	var right := float(_lay.get("row_right", 447))
	for id in buttons.keys():
		var b: Button = buttons[id]
		var i := order.find(id)
		b.visible = i >= 0
		if i < 0:
			continue
		var base := _baseline_art(i)
		b.position = Vector2(left * sx, (base - TOP) * sy)
		b.size = Vector2((right - left) * sx, (TOP + BOTTOM) * sy)
	if not order.has(highlighted):
		highlighted = ""
	set_highlight(highlighted if highlighted != "" else (order[0] if not order.is_empty() else ""), true)


## Every slot the game writes: the autosave, the quick save, the player's slots and the scene checkpoints.
static func default_slots() -> Array:
	var out: Array = [RoomManager.autosave_slot, "quick"]
	out.append_array(GameState.MANUAL_SLOTS)
	for cp in StoryData.checkpoints():
		out.append(RoomManager.checkpoint_prefix + String(cp["slot"]))
	return out


func _baseline_art(i: int) -> float:
	return float(_lay.get("first_baseline", 419.5)) + float(_lay.get("pitch", 72)) * i


# --- Highlight --------------------------------------------------------------------------------

func set_highlight(id: String, instant: bool = false) -> void:
	var i := order.find(id)
	if i < 0:
		return
	var target := (_baseline_art(i) - TOP) * MenuConfig.sy()
	var changed := id != highlighted
	highlighted = id
	if _hl_tween != null and _hl_tween.is_valid():
		_hl_tween.kill()
	if instant or not visible or not changed:
		_set_hl_top(target)
	else:
		_hl_tween = create_tween()
		_hl_tween.tween_method(_set_hl_top, _hl_top, target, SLIDE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	decor.queue_redraw()


func _set_hl_top(y: float) -> void:
	_hl_top = y
	var box: Array = MenuConfig.section("title").get("leaf_box", [110, 378, 166, 438])
	# The leaf keeps its place relative to the row as on the reference (leaf box top 378 vs. row top 372).
	leaf.position = Vector2(float(box[0]) * MenuConfig.sx(), y + (float(box[1]) - (419.5 - TOP)) * MenuConfig.sy())
	leaf.visible = highlighted != ""
	decor.queue_redraw()


func _draw_decor() -> void:
	var sx := MenuConfig.sx()
	var sy := MenuConfig.sy()
	var fs := int(_lay.get("font_px", 38))
	var text_x := float(_lay.get("text_x", 179)) * sx
	var dl := float(_lay.get("divider_left", 133)) * sx
	var dr := float(_lay.get("divider_right", 426)) * sx
	var rl := float(_lay.get("row_left", 112)) * sx
	var rr := float(_lay.get("row_right", 447)) * sx
	var div_c := MenuConfig.color(_lay.get("divider_color"), Color(0.55, 0.4, 0.26, 0.55))
	var line_c := MenuConfig.color(_lay.get("line_color"), Color(1, 0.72, 0.36))
	var glow_c := MenuConfig.color(_lay.get("glow_color"), Color(1, 0.62, 0.25, 0.3))
	var hl_i := order.find(highlighted)
	# Dividers under the rows (carved: a thin line, a small rhomb at the left end, an arrow tip at the right).
	for i in order.size():
		if i == hl_i or i + 1 == hl_i:
			continue   # the golden lines frame the highlighted row instead
		var y := (_baseline_art(i) + BOTTOM) * sy
		decor.draw_line(Vector2(dl + 14, y), Vector2(dr - 6, y), div_c, 1.6, true)
		_rhomb(Vector2(dl + 6, y), 5.5, div_c)
		decor.draw_colored_polygon(PackedVector2Array([Vector2(dr, y), Vector2(dr - 9, y - 3.5), Vector2(dr - 9, y + 3.5)]), div_c)
	if hl_i >= 0:
		var top := _hl_top
		var bot := _hl_top + (TOP + BOTTOM) * sy
		decor.draw_texture_rect(_glow, Rect2(rl - 30, top - 6, rr - rl + 60, bot - top + 12), false, glow_c)
		for y in [top, bot]:
			_golden_line(rl, rr, y, line_c)
	var text_c := MenuConfig.color(_lay.get("text_color"), Color(0.86, 0.79, 0.68))
	var hover_c := MenuConfig.color(_lay.get("hover_color"), Color(1, 0.86, 0.6))
	for i in order.size():
		var id: String = order[i]
		var base := Vector2(text_x, _baseline_art(i) * sy)
		var c := hover_c if id == highlighted else text_c
		decor.draw_string(_font, base + Vector2(0, 2), labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
		decor.draw_string(_font, base, labels[id], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


## A golden rule of the highlight: bright in the middle, fading out at both ends, with a soft glow under it.
func _golden_line(x0: float, x1: float, y: float, c: Color) -> void:
	var pts := PackedVector2Array([Vector2(x0, y), Vector2(x0 + 60, y), Vector2(x1 - 60, y), Vector2(x1, y)])
	var soft := PackedColorArray([Color(c, 0), Color(c, 0.22), Color(c, 0.22), Color(c, 0)])
	decor.draw_polyline_colors(pts, soft, 7.0, true)
	var hard := PackedColorArray([Color(c, 0), Color(c, 0.95), Color(c, 0.95), Color(c, 0)])
	decor.draw_polyline_colors(pts, hard, 2.0, true)


func _rhomb(at: Vector2, r: float, c: Color) -> void:
	decor.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, 0), at + Vector2(0, -r * 0.8), at + Vector2(r, 0), at + Vector2(0, r * 0.8)]), c)


# --- Actions ----------------------------------------------------------------------------------

## «Продолжить», «Новая игра», «Загрузить», «Настройки», «Выход» — the same as clicking the item.
func activate(id: String) -> void:
	if not visible or not order.has(id):
		return
	actions.append(id)
	action_taken.emit(id)
	match id:
		"continue":
			# the saves may have changed under the title (deleted in «Загрузить»: 31.10, Director line 4)
			refresh()
			if continue_slot == "":
				return
			var slot := continue_slot
			close()
			if not RoomManager.load_game(slot):
				open()
		"new_game":
			close()
			RoomManager.new_game()
			StoryRunner.play_first_day_card()
		"load":
			if game_ui != null:
				game_ui.call("open_menu_panel", "load")
		"settings":
			if game_ui != null:
				game_ui.call("open_menu_panel", "settings")
		"quit":
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or (game_ui != null and bool(game_ui.call("menu_panel_open"))):
		return
	var i := order.find(highlighted)
	if event.is_action_pressed("ui_down"):
		set_highlight(order[mini(i + 1, order.size() - 1)])
	elif event.is_action_pressed("ui_up"):
		set_highlight(order[maxi(i - 1, 0)])
	elif event.is_action_pressed("ui_accept") and highlighted != "":
		activate(highlighted)
	else:
		return
	get_viewport().set_input_as_handled()


# --- Probe ----------------------------------------------------------------------------------

## window.probeState.title: open, the items (id → centre of the clickable row), the highlighted one, the save
## «Продолжить» would load, whether the art layers and the animation are on.
func probe() -> Dictionary:
	var items := {}
	for id in order:
		var r := (buttons[id] as Button).get_global_rect()
		items[id] = {"x": r.get_center().x, "y": r.get_center().y, "text": labels[id]}
	return {"open": visible, "items": items, "order": order, "highlighted": highlighted, "continue_slot": continue_slot,
		"signature": signature.visible, "animated": bg.material != null, "actions": actions}
