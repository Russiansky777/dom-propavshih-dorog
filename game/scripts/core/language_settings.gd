class_name LanguageSettings
extends RefCounted
## Language of the voice and of the subtitles (Director 02.11 23:39, 03.11 14:35: «в настройках две кнопки по горизонтали:
## Русский и English для голоса; ниже — Русские субтитры, English subtitles, Без субтитров; при выборе английского —
## предупреждение, что субтитры и озвучка экспериментальные и могут содержать ошибки, с галочкой „понял“»).
## user://settings.cfg [language] voice = "ru" | "en", subtitles = "ru" | "en" | "none" (the file of the volumes —
## TimingBar.settings_path). Subtitles «en» — StoryData reads res://data/story_en (tools/build_story_en.py), the menus
## and every text follow; «none» — the words of a voiced line are not shown (unvoiced text still is). Voice «en» —
## VoiceDirector plays res://assets/voice/en. `en_acknowledged` — the warning was confirmed once (never asked again).

const VOICES := ["ru", "en"]
const SUBTITLES := ["ru", "en", "none"]

static var voice: String = "ru"
static var subtitles: String = "ru"
static var en_acknowledged: bool = false
static var _loaded: bool = false


static func load_settings(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if FileAccess.file_exists(TimingBar.settings_path) and cf.load(TimingBar.settings_path) == OK:
		voice = String(cf.get_value("language", "voice", "ru"))
		subtitles = String(cf.get_value("language", "subtitles", "ru"))
		en_acknowledged = bool(cf.get_value("language", "en_acknowledged", false))
	else:
		voice = "ru"
		subtitles = "ru"
		en_acknowledged = false
	if not VOICES.has(voice):
		voice = "ru"
	if not SUBTITLES.has(subtitles):
		subtitles = "ru"


## The language of the words on screen: the subtitles' one; «none» keeps the menus and the texts in the voice's language.
static func text_lang() -> String:
	load_settings()
	if subtitles == "none":
		return voice
	return subtitles


static func _save() -> bool:
	var cf := ConfigFile.new()
	if FileAccess.file_exists(TimingBar.settings_path):
		cf.load(TimingBar.settings_path)   # keep the other settings
	cf.set_value("language", "voice", voice)
	cf.set_value("language", "subtitles", subtitles)
	cf.set_value("language", "en_acknowledged", en_acknowledged)
	return cf.save(TimingBar.settings_path) == OK


## Sets the voice / the subtitles; returns true when the words on screen changed language (StoryData reloads).
static func set_voice(v: String) -> bool:
	load_settings()
	if not VOICES.has(v):
		return false
	var before := text_lang()
	voice = v
	_save()
	return text_lang() != before


static func set_subtitles(s: String) -> bool:
	load_settings()
	if not SUBTITLES.has(s):
		return false
	var before := text_lang()
	subtitles = s
	_save()
	return text_lang() != before


static func acknowledge_en() -> void:
	load_settings()
	en_acknowledged = true
	_save()


## Tests: back to the defaults without touching the file.
static func reset_memory() -> void:
	voice = "ru"
	subtitles = "ru"
	en_acknowledged = false
	_loaded = true
