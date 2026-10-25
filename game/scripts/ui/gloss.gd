class_name Gloss
extends RefCounted
## Hints to old words (H59, task T7, Director 24.10): the text of the data marks a word as `[[слово|значение]]`.
## On screen the word keeps the text's face, turns warm gold with a thin dashed underline (BBCode `[hint]`), and the
## modern meaning pops up on hover in the game's style (GlossText._make_custom_tooltip). The voice gets only the word
## (pipeline/voice/eleven_voice.api_text); the sha1 of a voiced line is taken over the text as written, marks included.
## The words and their sources — data/story/glossary.json (tools/validate_story.py checks every mark against it).

const COLOR := Color(0.96, 0.74, 0.38)          # warmer and deeper than the cream text, as gold leaf on wood
const PATTERN := "\\[\\[([^\\[\\]|]+)\\|([^\\[\\]|]+)\\]\\]"

static var _re: RegEx = null


static func _rx() -> RegEx:
	if _re == null:
		_re = RegEx.create_from_string(PATTERN)
	return _re


static func has_marks(s: String) -> bool:
	return s.contains("[[") and _rx().search(s) != null


## The text as read aloud / shown where no hint can be drawn: the words alone.
static func plain(s: String) -> String:
	if not s.contains("[["):
		return s
	return _rx().sub(s, "$1", true)


## [{word, meaning}] in order.
static func marks(s: String) -> Array:
	var out: Array = []
	if not s.contains("[["):
		return out
	for m in _rx().search_all(s):
		out.append({"word": m.get_string(1), "meaning": m.get_string(2)})
	return out


## BBCode for a RichTextLabel with bbcode_enabled: the rest of the text escaped, each mark coloured and underlined.
static func bbcode(s: String) -> String:
	var out := ""
	var pos := 0
	if s.contains("[["):
		for m in _rx().search_all(s):
			out += _esc(s.substr(pos, m.get_start() - pos))
			out += "[color=#%s][hint=\"%s\"]%s[/hint][/color]" % [COLOR.to_html(false), m.get_string(2).replace("\"", "'"), _esc(m.get_string(1))]
			pos = m.get_end()
	return out + _esc(s.substr(pos))


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


## The pop-up with the modern meaning inside the theme's TooltipPanel (dark wood, brass rule: UiTheme).
## I-T2 (Director, line 22): the word is not repeated — only its meaning, in the gold of the marked word and at the
## size of the text it stands in (`font_size`, 0 — the theme's), so it reads as the same voice.
static func make_tooltip(meaning: String, word: String = "", font_size: int = 0) -> Control:
	var v := VBoxContainer.new()
	v.name = "GlossTooltip"
	v.set_meta("word", word)
	var m := Label.new()
	m.name = "Meaning"
	m.text = meaning
	m.theme_type_variation = &"BagTooltipText"
	m.add_theme_color_override("font_color", COLOR)
	if font_size > 0:
		m.add_theme_font_size_override("font_size", font_size)
	v.add_child(m)
	return v
