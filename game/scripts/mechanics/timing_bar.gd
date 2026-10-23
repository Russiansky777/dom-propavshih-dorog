class_name TimingBar
extends Control
## «Точный удар» on screen (Director 23.10, F7/F8): a bar red → green in the middle → red, a brass marker
## running along it, a pip under the bar for every hit of the series. A click on the bar (or on whatever
## the owner forwards to `strike()` — the brace, the bell) or the Space key strikes. The owner reacts to
## `struck(result)`: "hit" (a blow lands), "miss" (the consequence: the brace jumps off, the hook falls),
## "done" (the series is complete). While a text is on screen the marker waits (nothing is missed while
## reading). Logic — TimingLogic; this node only draws it and takes the input.
##
## `vertical` draws the bar upright (0 — top): the hook in the office mirror sways along the door gap and
## the bar beside the glass shows where the bolt zone is. `drive = false` — the owner steps the logic
## itself (the hook moves the marker with the hook).
##
## Accessibility (G3, Director 23.10): menu «Облегчить мини-игры» (user://settings.cfg [access] timing_slow — the key
## kept from «Точный удар — медленнее», so an old setting still holds) — every timing mini-game, now and to come, is
## easier: the sweep SLOW_K times slower and the green zone EASY_GREEN_K times wider (apply_ease on a TimingLogic;
## the hook in the office mirror and the log at the windlass read slow_k()/green_k() too).

signal struck(result: String)
## A strike while the marker still holds after a hit (the blow is landing, the water is falling): the owner may say
## «погоди» (the sluice, G23). Not a miss — nothing changes.
signal early()

const SLOW_K := 1.8
const EASY_GREEN_K := 1.5
const SETTINGS_PATH := "user://settings.cfg"
const RED := Color(0.63, 0.17, 0.12)
const AMBER := Color(0.82, 0.57, 0.2)
const GREEN := Color(0.34, 0.6, 0.27)
const TRACK := Color(0.09, 0.065, 0.045, 0.92)
const BRASS := Color(0.98, 0.86, 0.56)
const THICK := 34.0

static var slow: bool = false
static var _loaded: bool = false
static var settings_path: String = SETTINGS_PATH

var logic: TimingLogic = null
var vertical: bool = false
var drive: bool = true
var hold: bool = false          # the owner pauses the bar (e.g. the hook waits for «пускай»)
var space_key: bool = true      # Space strikes (the owner may take the key for itself)
var hint: Label = null
var slow_check: CheckButton = null   # «Облегчить» right beside the bar (the same setting as in the menu)
var _flash: float = 0.0
var _flash_col: Color = GREEN
var _shake: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


## cfg: the mechanic's `timing` block (TimingLogic fields) + `hint` (a text key or plain text shown by the bar).
func setup(cfg: Dictionary, p_vertical: bool = false) -> void:
	load_settings()
	logic = TimingLogic.new(cfg)
	apply_ease(logic)
	vertical = p_vertical
	var h := String(cfg.get("hint", "@ui.timing_hint"))
	if h != "" and not vertical:
		hint = Label.new()
		hint.name = "Hint"
		hint.text = StoryData.text(h)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.theme_type_variation = &"CloseupLabel"
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)
	if bool(cfg.get("slow_toggle", true)) and not vertical:
		slow_check = CheckButton.new()
		slow_check.name = "Slow"
		slow_check.text = StoryData.text("@ui.timing_slow_short")
		slow_check.focus_mode = Control.FOCUS_NONE
		slow_check.button_pressed = slow
		slow_check.theme = UiTheme.get_theme()
		slow_check.toggled.connect(_on_slow_toggled)
		add_child(slow_check)
	_layout_hint()
	resized.connect(_layout_hint)
	queue_redraw()


func _layout_hint() -> void:
	if hint != null:
		hint.position = Vector2(0, size.y + 6)
		hint.size = Vector2(size.x, 36)
	if slow_check != null:
		slow_check.position = Vector2(size.x + 24, (size.y - 44) * 0.5)
		slow_check.size = Vector2(240, 44)


func _on_slow_toggled(on: bool) -> void:
	set_slow(on)
	if logic != null:
		# keep the marker where it is: the phase is a fraction of the sweep, only its speed and the zone change
		apply_ease(logic)
	queue_redraw()


## «Облегчить мини-игры» on a timing logic: slower sweep, wider green (both 1 when the setting is off).
static func apply_ease(l: TimingLogic) -> void:
	if l == null:
		return
	l.slow_k = slow_k()
	l.green_k = green_k()


## The sweep's period multiplier now (every timing mini-game): SLOW_K with «Облегчить», else 1.
static func slow_k() -> float:
	load_settings()
	return SLOW_K if slow else 1.0


## The zone's width multiplier now (every timing mini-game): EASY_GREEN_K with «Облегчить», else 1.
static func green_k() -> float:
	load_settings()
	return EASY_GREEN_K if slow else 1.0


## The bar is waiting: a text on screen (the modal takes the clicks) or the owner holds it.
func paused() -> bool:
	return hold or not StoryRunner.current_beat.is_empty()


func _process(delta: float) -> void:
	if logic == null:
		return
	if drive and not paused():
		logic.step(delta)
	_flash = maxf(_flash - delta * 2.5, 0.0)
	_shake = maxf(_shake - delta * 3.0, 0.0)
	queue_redraw()


## A strike now (mouse on the bar or on the owner's target, Space). Returns TimingLogic.strike()'s result.
func strike() -> String:
	if logic == null or paused():
		return "busy"
	var r := logic.strike()
	if r == "busy" and logic.state == "hit":
		early.emit()
	match r:
		"hit", "done":
			_flash = 1.0
			_flash_col = GREEN
		"miss":
			_flash = 1.0
			_flash_col = RED
			_shake = 1.0
	if r in ["hit", "done", "miss"]:
		struck.emit(r)
	queue_redraw()
	return r


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		strike()


func _input(event: InputEvent) -> void:
	if not space_key or logic == null or logic.done() or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		strike()


# --- Drawing ----------------------------------------------------------------------------------

func color_at(p: float) -> Color:
	if logic == null:
		return RED
	if logic.in_green(p):
		return GREEN
	return RED.lerp(AMBER, pow(logic.warmth(p), 1.6))


## Screen point of bar position p (0..1) on the bar's axis.
func _at(p: float) -> Vector2:
	if vertical:
		return Vector2(size.x * 0.5, lerpf(6.0, size.y - 6.0, p))
	return Vector2(lerpf(6.0, size.x - 6.0, p), size.y * 0.5)


func _draw() -> void:
	if logic == null:
		return
	var shake := Vector2(sin(_shake * 40.0) * 6.0 * _shake, 0) if not vertical else Vector2(0, sin(_shake * 40.0) * 6.0 * _shake)
	var thick := minf(THICK, (size.x if vertical else size.y) - 8.0)
	var track := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TRACK
	sb.border_color = Color(0.68, 0.55, 0.35, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	draw_style_box(sb, track)
	# The colours along the bar.
	var n := 120
	for i in n:
		var p0 := float(i) / n
		var p1 := float(i + 1) / n
		var a := _at(p0)
		var b := _at(p1)
		var r: Rect2
		if vertical:
			r = Rect2(Vector2(a.x - thick * 0.5, a.y), Vector2(thick, b.y - a.y + 0.6))
		else:
			r = Rect2(Vector2(a.x, a.y - thick * 0.5), Vector2(b.x - a.x + 0.6, thick))
		draw_rect(r, color_at((p0 + p1) * 0.5))
	# The green zone's edges: brass ticks.
	var z := logic.zone()
	for e in [z.x, z.y]:
		var c := _at(e)
		if vertical:
			draw_line(c + Vector2(-thick * 0.5 - 6, 0), c + Vector2(thick * 0.5 + 6, 0), BRASS, 2.0)
		else:
			draw_line(c + Vector2(0, -thick * 0.5 - 6), c + Vector2(0, thick * 0.5 + 6), BRASS, 2.0)
	if _flash > 0.0:
		var fr := Rect2(Vector2.ZERO, size).grow(4.0)
		draw_rect(fr, Color(_flash_col, 0.35 * _flash), false, 6.0)
	# The marker: a brass needle across the bar with a pointer.
	var m := _at(logic.pos()) + shake
	var col := BRASS if logic.state != "miss" else Color(1.0, 0.55, 0.45)
	if vertical:
		draw_line(m + Vector2(-thick * 0.5 - 12, 0), m + Vector2(thick * 0.5 + 12, 0), Color(0, 0, 0, 0.6), 7.0)
		draw_line(m + Vector2(-thick * 0.5 - 12, 0), m + Vector2(thick * 0.5 + 12, 0), col, 4.0)
		draw_colored_polygon(PackedVector2Array([m + Vector2(-thick * 0.5 - 12, -9), m + Vector2(-thick * 0.5 - 12, 9), m + Vector2(-thick * 0.5 + 2, 0)]), col)
	else:
		draw_line(m + Vector2(0, -thick * 0.5 - 12), m + Vector2(0, thick * 0.5 + 12), Color(0, 0, 0, 0.6), 7.0)
		draw_line(m + Vector2(0, -thick * 0.5 - 12), m + Vector2(0, thick * 0.5 + 12), col, 4.0)
		draw_colored_polygon(PackedVector2Array([m + Vector2(-10, -thick * 0.5 - 14), m + Vector2(10, -thick * 0.5 - 14), m + Vector2(0, -thick * 0.5 + 2)]), col)
	# Pips: the series.
	if logic.hits_needed > 1 and not vertical:
		var gap := 30.0
		var x0 := size.x * 0.5 - gap * (logic.hits_needed - 1) * 0.5
		for i in logic.hits_needed:
			var c := Vector2(x0 + gap * i, -18.0)
			var on := i < logic.hits or logic.done()
			draw_circle(c, 9.0, Color(0, 0, 0, 0.55))
			draw_circle(c, 7.0, GREEN.lightened(0.15) if on else Color(0.3, 0.24, 0.17))


# --- Settings (accessibility) -----------------------------------------------------------------

static func load_settings(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path) and cf.load(settings_path) == OK:
		slow = bool(cf.get_value("access", "timing_slow", false))


static func set_slow(on: bool) -> bool:
	slow = on
	_loaded = true
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path):
		cf.load(settings_path)   # keep the other settings (volumes)
	cf.set_value("access", "timing_slow", on)
	return cf.save(settings_path) == OK


func probe() -> Dictionary:
	if logic == null:
		return {}
	var r := get_global_rect()
	return {"x": r.get_center().x, "y": r.get_center().y, "pos": logic.pos(), "hits": logic.hits, "needed": logic.hits_needed,
		"misses": logic.misses, "state": logic.state, "in_green": logic.in_green(logic.pos()), "zone": [logic.zone().x, logic.zone().y],
		"period_s": logic.period_s * logic.slow_k, "paused": paused(), "to_green_s": logic.seconds_to_green(),
		"easy": slow, "green_w": logic.green_w()}
