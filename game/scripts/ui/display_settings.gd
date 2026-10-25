class_name DisplaySettings
extends RefCounted
## I-T3 §2а (Director 25.10, 16:09: «игра на любых мониторах»): full screen or a window, the player's choice kept in
## user://settings.cfg [display] fullscreen (the file of the volumes and «Облегчить мини-игры» — TimingBar.settings_path).
## The picture is 1920×1080 scaled by `canvas_items` + `keep`: on 16:10 / 21:9 the rest is dark margins (the clear colour
## in project.godot), the window can be resized. Menu: GameUi settings «Полный экран»; F11 toggles anywhere.
## Web: the browser allows full screen only from a click or a key, which both are.

static var fullscreen: bool = false
static var _loaded: bool = false


static func load_settings(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if FileAccess.file_exists(TimingBar.settings_path) and cf.load(TimingBar.settings_path) == OK:
		fullscreen = bool(cf.get_value("display", "fullscreen", false))
	else:
		fullscreen = false


## At start: the saved mode (a window when nothing is saved). The web starts in the page — the browser refuses full
## screen without a gesture, so there the saved choice waits for the menu or F11.
static func apply_saved() -> void:
	load_settings()
	if fullscreen and not OS.has_feature("web"):
		_apply()


static func set_fullscreen(on: bool) -> bool:
	fullscreen = on
	_loaded = true
	_apply()
	var cf := ConfigFile.new()
	if FileAccess.file_exists(TimingBar.settings_path):
		cf.load(TimingBar.settings_path)   # keep the other settings
	cf.set_value("display", "fullscreen", on)
	return cf.save(TimingBar.settings_path) == OK


static func toggle() -> bool:
	load_settings()
	set_fullscreen(not fullscreen)
	return fullscreen


static func _apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
