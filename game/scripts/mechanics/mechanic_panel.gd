class_name MechanicPanel
extends Control
## Base of a day-two close-up panel (MechanicView). A panel draws its stand-in art (crops of the delivered
## room paintings + shapes drawn by the engine, until the ordered close-ups come — BRIEF_CHATGPT_v4 §C),
## takes the mouse, and reports what the player did through `event(name)` (StoryRunner.mechanic_event →
## data `events.<name>`). Its time is its own accumulated `clock` (Engine.time_scale speeds it up in tests).

var view: MechanicView = null
var spec: Dictionary = {}
var clock: float = 0.0
## G26 (Director 23.10: «кликать и мышью»): while this «точный удар» bar is on screen, a left click anywhere on the
## close-up that nothing else takes (the picture, the background) strikes — as well as a click on the bar, the
## owner's target, or Space. Panels with a timing bar set it in build().
var strike_bar: TimingBar = null
var strikes_by_click: int = 0   # tests: strikes that came from a click on the close-up itself


func build() -> void:
	pass


func _enter_tree() -> void:
	if not GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.connect(_on_flag_changed)


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)


func _on_flag_changed(_f: String, _v: bool) -> void:
	flags_changed()


## Story state changed while the close-up is open (a scene's grants: Pelageya brings the rope while the
## plate is on screen) — panels redraw what depends on flags.
func flags_changed() -> void:
	pass


func opened() -> void:
	pass


func closing() -> void:
	pass


func probe() -> Dictionary:
	return {}


func flag(f: String) -> bool:
	return GameState.has_flag(f)


## A story event of this close-up (data `events.<name>`): flags, text, close.
func event(name: String) -> bool:
	return StoryRunner.mechanic_event(name)


## A text over the close-up: `texts.<key>` of the spec (a data key or plain text).
func say(key: String) -> void:
	var t := String(spec.get("texts", {}).get(key, key))
	StoryRunner.mechanic_say(t)


func text(key: String) -> String:
	return StoryData.text(String(spec.get("texts", {}).get(key, key)))


## The text box is up (its modal takes the clicks): panels hold their own timers too.
func dialogue_up() -> bool:
	return not StoryRunner.current_beat.is_empty()


func sound(sound_name: String) -> void:
	if view != null:
		view.play(sound_name)


func _process(delta: float) -> void:
	clock += delta
	tick(delta)


func _gui_input(ev: InputEvent) -> void:
	if strike_bar == null or not is_instance_valid(strike_bar) or not strike_bar.is_visible_in_tree():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		strikes_by_click += 1
		strike_bar.strike()


func tick(_delta: float) -> void:
	pass


# --- Drawing helpers ------------------------------------------------------------------------

## A part of a delivered painting (`image`, `region` [x, y, w, h] in its pixels) shown at `pos` with `scale`.
func crop(image: String, region: Array, pos: Vector2, scale_k: float, parent: Control = null) -> TextureRect:
	var tr := TextureRect.new()
	if ResourceLoader.exists(image):
		var at := AtlasTexture.new()
		at.atlas = load(image)
		at.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = pos
	tr.size = Vector2(float(region[2]), float(region[3])) * scale_k
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(tr)
	return tr


func label(t: String, pos: Vector2, w: float, variation: StringName = &"CloseupLabel", parent: Control = null) -> Label:
	var l := Label.new()
	# wrap before text and size: a Label without wrapping is as wide as its text and keeps that width
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	l.text = t
	l.position = pos
	l.size = Vector2(w, 40)
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l


## A clickable invisible area (with a hover outline) over part of the close-up.
func hit_area(rect: Rect2, on_input: Callable, node_name: String = "Hit") -> Control:
	var c := Control.new()
	c.name = node_name
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(on_input)
	add_child(c)
	return c


static func v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func center_of(c: Control) -> Dictionary:
	if c == null or not is_instance_valid(c):
		return {}
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}
