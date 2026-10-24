class_name DayCard
extends CanvasLayer
## The change of day (T6, Director 24.10: «каждый день кончается сном… затемнение, в стиле игры всплывает „День
## первый / второй / третий / четвёртый“, затем проявление в новый день»). The words in the font and gold of the title
## screen, between two golden rules that fade out at both ends; they come up softly on black and go. StoryRunner
## asks for it (signal day_card_requested): a scene staging while its screen is black (scenes data `stage[].day_card`,
## the staging's own black holds meanwhile) or the start of a new game (`own_black`: this layer's black, which then
## fades into the first room). Once per change of day: StoryRunner keeps the flag day_card_<n> in the save, so a load
## never shows it again. Timing and look — data/story/menu.json → day_card.

const LAYER := 44            # above the game and its staging black (GameUi 5), under the credits (45) and the pause (50)

var black: ColorRect
var words: Label
var rules: Control
var phase: String = ""       # "" | "in" | "hold" | "out" | "black_out" (tests, the web probe)
var text_key: String = ""
var shown: Array[String] = []   # every card shown this session, in order (tests)

var _cfg: Dictionary = {}
var _tween: Tween = null
var _line_c := Color(1, 0.72, 0.36)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE   # the pause menu holds it where it is, like the staging under it
	_cfg = MenuConfig.section("day_card")
	_line_c = MenuConfig.color(_cfg.get("line_color"), _line_c)
	black = ColorRect.new()
	black.name = "Black"
	black.color = Color(0, 0, 0, 0)
	black.size = MenuConfig.SCREEN
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	rules = Control.new()
	rules.name = "Rules"
	rules.size = MenuConfig.SCREEN
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules.modulate.a = 0.0
	rules.draw.connect(_draw_rules)
	add_child(rules)
	words = Label.new()
	words.name = "Words"
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.position = Vector2(0, 470)
	words.size = Vector2(MenuConfig.SCREEN.x, 140)
	words.add_theme_font_override("font", UiTheme.font(String(_cfg.get("font", "body"))))
	words.add_theme_font_size_override("font_size", int(_cfg.get("font_px", 72)))
	words.add_theme_color_override("font_color", MenuConfig.color(_cfg.get("text_color"), Color(1, 0.86, 0.6)))
	words.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	words.add_theme_constant_override("shadow_offset_y", 3)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.modulate.a = 0.0
	add_child(words)
	visible = false
	StoryRunner.day_card_requested.connect(show_card)
	GameState.state_reset.connect(_stop)
	GameState.state_loaded.connect(func(_slot): _stop())


## Seconds the words take on screen (in + hold + out): the staging under them holds its black that long.
static func seconds() -> float:
	var c := MenuConfig.section("day_card")
	return float(c.get("in_s", 1.2)) + float(c.get("hold_s", 1.8)) + float(c.get("out_s", 1.0))


func is_running() -> bool:
	return phase != ""


func show_card(key: String, own_black: bool) -> void:
	_stop()
	text_key = key
	shown.append(key)
	words.text = StoryData.text(key)
	visible = true
	black.color.a = 1.0 if own_black else 0.0
	black.mouse_filter = Control.MOUSE_FILTER_STOP if own_black else Control.MOUSE_FILTER_IGNORE
	rules.queue_redraw()
	phase = "in"
	_tween = create_tween()
	_tween.tween_property(words, "modulate:a", 1.0, float(_cfg.get("in_s", 1.2))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(rules, "modulate:a", 1.0, float(_cfg.get("in_s", 1.2)) * 1.3).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func(): phase = "hold")
	_tween.tween_interval(float(_cfg.get("hold_s", 1.8)))
	_tween.tween_callback(func(): phase = "out")
	_tween.tween_property(words, "modulate:a", 0.0, float(_cfg.get("out_s", 1.0))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(rules, "modulate:a", 0.0, float(_cfg.get("out_s", 1.0)))
	if own_black:
		_tween.tween_callback(func(): phase = "black_out")
		_tween.tween_property(black, "color:a", 0.0, float(_cfg.get("black_out_s", 1.2)))
	_tween.tween_callback(_stop)


func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	phase = ""
	visible = false
	words.modulate.a = 0.0
	rules.modulate.a = 0.0
	black.color.a = 0.0
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Two golden rules above and under the words, bright in the middle and fading out at both ends (the title screen's).
func _draw_rules() -> void:
	var half := float(_cfg.get("rule_half_px", 260))
	var cx := MenuConfig.SCREEN.x * 0.5
	for y in [float(_cfg.get("rule_top_y", 478)), float(_cfg.get("rule_bottom_y", 604))]:
		var pts := PackedVector2Array([Vector2(cx - half, y), Vector2(cx - half + 90, y), Vector2(cx + half - 90, y), Vector2(cx + half, y)])
		var c := _line_c
		rules.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.22), Color(c, 0.22), Color(c, 0)]), 7.0, true)
		rules.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.9), Color(c, 0.9), Color(c, 0)]), 2.0, true)
	var r := 6.0
	for x in [cx - half - 14, cx + half + 14]:
		for y in [float(_cfg.get("rule_top_y", 478)), float(_cfg.get("rule_bottom_y", 604))]:
			var at := Vector2(x, y)
			rules.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, 0), at + Vector2(0, -r * 0.8), at + Vector2(r, 0), at + Vector2(0, r * 0.8)]), Color(_line_c, 0.8))


func probe() -> Dictionary:
	return {"phase": phase, "text": words.text if phase != "" else "", "key": text_key, "shown": shown.duplicate(),
		"alpha": words.modulate.a, "black": black.color.a}
