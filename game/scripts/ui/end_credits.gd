class_name EndCredits
extends CanvasLayer
## The credits after the last line of the game (H55/H56, Director 24.10): fade to black, the thanks and the author's
## name under it, fade out — and the title screen. Texts ui.credits_thanks / ui.credits_author, timing
## data/story/menu.json → credits. FrameView starts it once the last scene is over and `credits_seen` is not set; the
## flag is saved at once (autosave), so «Продолжить» after the credits shows the held last shot with «Конец» and the
## traces of the player's choices instead of the credits again. A click or Esc once the text is up skips the wait.

signal finished

const LAYER := 45            # above the game (GameUi 5, FrameView 3), under the pause menu (50) and the title (60)
const FLAG := "credits_seen"

var title: Node = null       # TitleScreen: opened at the end
var black: ColorRect
var box: VBoxContainer
var thanks: Label
var author: Label
var phase: String = ""       # "" | "black" | "text" | "hold" | "out" | "done" (tests, the web probe)

var _cfg: Dictionary = {}
var _tween: Tween = null
var _skippable: bool = false
var _hold_left: float = 0.0
var _text_t: float = 0.0          # seconds since the text began to appear (a click skips after skip_after_s)


func _ready() -> void:
	layer = LAYER
	visible = false
	_cfg = MenuConfig.section("credits")
	black = ColorRect.new()
	black.name = "Black"
	black.color = Color(0, 0, 0, 0)
	black.size = MenuConfig.SCREEN
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.gui_input.connect(_on_input)
	add_child(black)
	box = VBoxContainer.new()
	box.name = "Text"
	box.position = Vector2(260, 380)
	box.size = Vector2(1400, 320)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 48)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	add_child(box)
	thanks = _label("Thanks", "@ui.credits_thanks", "body", int(_cfg.get("thanks_px", 46)),
		MenuConfig.color(_cfg.get("text_color"), Color(0.93, 0.88, 0.78)))
	author = _label("Author", "@ui.credits_author", "head", int(_cfg.get("author_px", 34)),
		MenuConfig.color(_cfg.get("author_color"), Color(0.78, 0.70, 0.58)))


func _label(node_name: String, key: String, font_role: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = StoryData.text(key)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1400, 0)
	l.add_theme_font_override("font", UiTheme.font(font_role))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return l


func is_running() -> bool:
	return phase != "" and phase != "done"


## Fade to black → text in → hold → text out → the title screen.
func play() -> void:
	if is_running():
		return
	GameState.set_flag(FLAG, true)
	RoomManager.autosave()   # «Продолжить» after the end — the last shot with «Конец», not the credits again
	visible = true
	black.color.a = 0.0
	box.modulate.a = 0.0
	_skippable = false
	_text_t = 0.0
	phase = "black"
	_tween = create_tween()
	_tween.tween_property(black, "color:a", 1.0, float(_cfg.get("fade_to_black_s", 2.0)))
	_tween.tween_callback(func(): phase = "text")
	_tween.tween_property(box, "modulate:a", 1.0, float(_cfg.get("text_fade_in_s", 1.6)))
	_tween.tween_callback(_start_hold)


func _start_hold() -> void:
	phase = "hold"
	_hold_left = float(_cfg.get("hold_s", 8.0))


func _process(delta: float) -> void:
	if phase == "text" or phase == "hold":
		_text_t += delta
		_skippable = _skippable or _text_t >= float(_cfg.get("skip_after_s", 2.0))
	if phase != "hold":
		return
	_hold_left -= delta
	if _hold_left <= 0.0:
		_fade_out()


func _fade_out() -> void:
	if phase == "out" or phase == "done":
		return
	phase = "out"
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(box, "modulate:a", 0.0, float(_cfg.get("text_fade_out_s", 1.6)))
	_tween.tween_interval(float(_cfg.get("black_after_s", 0.8)))
	_tween.tween_callback(_to_title)


## The game is over: its state goes (like «В главное меню»), the title comes up over the black, then this layer hides.
func _to_title() -> void:
	phase = "done"
	GameState.reset()
	if title != null:
		title.call("open")
	visible = false
	black.color.a = 0.0
	box.modulate.a = 0.0
	_text_t = 0.0
	finished.emit()


func _on_input(ev: InputEvent) -> void:
	if not _skippable or (phase != "text" and phase != "hold"):
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_fade_out()


func _unhandled_input(ev: InputEvent) -> void:
	if visible and _skippable and (phase == "text" or phase == "hold") and ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_fade_out()


func probe() -> Dictionary:
	return {"phase": phase, "visible": visible, "black": black.color.a, "text": box.modulate.a,
		"thanks": thanks.text, "author": author.text}
