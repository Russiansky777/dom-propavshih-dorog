class_name IntroCard
extends CanvasLayer
## The intro of a new game (Р13, Director 29.10: «вступление закадром — кто Агата и в чём её беда»; 18:30: «с озвучкой
## и в 2–3 фейд ин/аут кадра с текстом на чёрном фоне… оформление в нашем игровом стиле… держатся несколько секунд,
## либо переключаются так же фейдами на следующий при нажатии или щелчке»). Cards of text on black, in the look of
## the change-of-day card (DayCard: the title screen's body font, gold, golden rules fading at both ends); each card
## fades in with its voice-over (narrator, the text key's own recording), holds while the voice speaks and a beat after
## it (or its reading time when there is no recording), fades out into the next. A click or Space / Enter fades the card
## out at once (the voice fades with it). After the last card — «День первый» (StoryRunner.play_first_day_card), whose
## black takes over this one in the same frame. Once per game: StoryRunner keeps the flag intro_seen in the save.
## Keys, timing and look — data/story/menu.json → intro.

const LAYER := 44            # as DayCard: above the game, under the credits (45) and the pause (50)

var black: ColorRect
var words: Label
var rules: Control
var phase: String = ""       # "" | "in" | "hold" | "out" (tests, the web probe)
var index: int = -1
var keys: Array = []
var shown: Array[String] = []   # every card shown this session, in order (tests)
var skipped: int = 0            # cards cut short by a click / key (tests)

var _cfg: Dictionary = {}
var _tween: Tween = null
var _line_c := Color(1, 0.72, 0.36)
var _voice_id: String = ""
var _voice_heard: bool = false
var _hold_t: float = 0.0
var _after_t: float = 0.0
var _read_s: float = 5.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_cfg = MenuConfig.section("intro")
	_line_c = MenuConfig.color(_cfg.get("line_color"), _line_c)
	black = ColorRect.new()
	black.name = "Black"
	black.color = Color(0, 0, 0, 0)
	black.size = MenuConfig.SCREEN
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.gui_input.connect(_on_black_input)
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
	var w := float(_cfg.get("width_px", 1240))
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.position = Vector2((MenuConfig.SCREEN.x - w) * 0.5, float(_cfg.get("rule_top_y", 330)) + 24.0)
	words.size = Vector2(w, float(_cfg.get("rule_bottom_y", 750)) - float(_cfg.get("rule_top_y", 330)) - 48.0)
	words.add_theme_font_override("font", UiTheme.font(String(_cfg.get("font", "body"))))
	words.add_theme_font_size_override("font_size", int(_cfg.get("font_px", 42)))
	words.add_theme_constant_override("line_spacing", int(_cfg.get("line_spacing_px", 10)))
	words.add_theme_color_override("font_color", MenuConfig.color(_cfg.get("text_color"), Color(0.96, 0.89, 0.74)))
	words.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	words.add_theme_constant_override("shadow_offset_y", 3)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.modulate.a = 0.0
	add_child(words)
	visible = false
	StoryRunner.intro_requested.connect(play)
	GameState.state_loaded.connect(func(_slot): _stop())
	VoiceDirector.voice_started.connect(_on_voice_started)


func is_running() -> bool:
	return phase != ""


## Plays the cards `p_keys` (text keys) one after another; then «День первый».
func play(p_keys: Array) -> void:
	_stop()
	keys = p_keys.duplicate()
	index = -1
	visible = true
	black.color.a = 1.0
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	_next()


func _next() -> void:
	index += 1
	if index >= keys.size():
		_finish()
		return
	var key := String(keys[index])
	shown.append(key)
	words.text = StoryData.text(key)
	rules.queue_redraw()
	phase = "in"
	_hold_t = 0.0
	_after_t = 0.0
	_voice_heard = false
	_read_s = maxf(float(_cfg.get("min_hold_s", 4.5)), float(words.text.length()) / maxf(float(_cfg.get("read_cps", 14.0)), 1.0))
	# The voice starts with the fade-in; without a recording the card holds its reading time.
	var v: Dictionary = VoiceDirector.narration_voice(key.trim_prefix("@"))
	_voice_id = String(v.get("id", ""))
	var st := String(VoiceDirector.play_line(_voice_id, String(v.get("speaker", "narrator")), words.text, "narration"))
	if st == "playing":
		_voice_heard = true
	elif st != "waiting":
		_voice_id = ""
	var in_s := float(_cfg.get("in_s", 1.4))
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(words, "modulate:a", 1.0, in_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if index == 0:
		_tween.parallel().tween_property(rules, "modulate:a", 1.0, in_s * 1.3).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func(): phase = "hold")


func _process(delta: float) -> void:
	if phase != "hold":
		return
	_hold_t += delta
	if _speaking():
		return
	if _voice_heard:
		_after_t += delta
		if _after_t >= float(_cfg.get("after_voice_s", 1.4)):
			_out(false)
	elif _hold_t >= _read_s:
		_out(false)


func _speaking() -> bool:
	return _voice_id != "" and VoiceDirector.current_line == _voice_id and VoiceDirector.is_playing()


func _on_voice_started(line_id: String, _speaker: String) -> void:
	if line_id == _voice_id and phase != "":
		_voice_heard = true


## Fades the card out (`fast` — cut short by the player: quicker, the voice fades with it), then the next card.
func _out(fast: bool) -> void:
	if phase != "in" and phase != "hold":
		return
	phase = "out"
	if fast:
		skipped += 1
		if _speaking():
			VoiceDirector.fade_out(0.4, "intro_skip")
	var out_s := float(_cfg.get("out_s_click" if fast else "out_s", 0.5 if fast else 1.1))
	var last := index >= keys.size() - 1
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(words, "modulate:a", 0.0, out_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if last:
		_tween.parallel().tween_property(rules, "modulate:a", 0.0, out_s)
	_tween.tween_interval(float(_cfg.get("gap_s", 0.35)))
	_tween.tween_callback(_next)


## The last card gone: «День первый» over its own black (the same frame), then this layer goes.
func _finish() -> void:
	phase = ""
	StoryRunner.play_first_day_card()
	_stop()


func _on_black_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_out(true)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if phase == "" or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER:
		_out(true)
		get_viewport().set_input_as_handled()


## Tests and shots: the intro done at once (the voice stopped), «День первый» follows as usual.
func finish_now() -> void:
	if phase == "":
		return
	if _speaking():
		VoiceDirector.stop("intro_skip")
	_kill_tween()
	_finish()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _stop() -> void:
	_kill_tween()
	phase = ""
	visible = false
	words.modulate.a = 0.0
	rules.modulate.a = 0.0
	black.color.a = 0.0
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Golden rules above and under the text, as on the change-of-day card.
func _draw_rules() -> void:
	var half := float(_cfg.get("rule_half_px", 320))
	var cx := MenuConfig.SCREEN.x * 0.5
	var ys := [float(_cfg.get("rule_top_y", 330)), float(_cfg.get("rule_bottom_y", 750))]
	for y in ys:
		var pts := PackedVector2Array([Vector2(cx - half, y), Vector2(cx - half + 90, y), Vector2(cx + half - 90, y), Vector2(cx + half, y)])
		var c := _line_c
		rules.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.22), Color(c, 0.22), Color(c, 0)]), 7.0, true)
		rules.draw_polyline_colors(pts, PackedColorArray([Color(c, 0), Color(c, 0.9), Color(c, 0.9), Color(c, 0)]), 2.0, true)
	var r := 6.0
	for x in [cx - half - 14, cx + half + 14]:
		for y in ys:
			var at := Vector2(x, y)
			rules.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, 0), at + Vector2(0, -r * 0.8), at + Vector2(r, 0), at + Vector2(0, r * 0.8)]), Color(_line_c, 0.8))


func probe() -> Dictionary:
	return {"phase": phase, "index": index, "key": String(keys[index]) if index >= 0 and index < keys.size() else "",
		"text": words.text if phase != "" else "", "shown": shown.duplicate(), "skipped": skipped,
		"black": black.color.a, "alpha": words.modulate.a, "voice": _voice_id, "voice_heard": _voice_heard}
