extends RefCounted
## The text of the «Лицензии» screen (review 12.11: «в игре нет текста лицензий» — needed before Steam).
## A game made with Godot has to carry the engine's license and the notices of the third-party code built into it
## (https://docs.godotengine.org/en/stable/about/complying_with_licenses.html); the engine gives them itself
## (Engine.get_license_text, get_copyright_info, get_license_info) — always those of the very build the game runs on.
## The game's fonts are under the SIL Open Font License 1.1: their notices and the license text come from
## res://data/licenses.json (tools/make_licenses.py ← assets/fonts/<font>/OFL.txt).
## The headings are the game's texts (data/story/text/ru_menu.json, translated); the licenses stay as their authors wrote them.

const FONTS_DATA := "res://data/licenses.json"


static func fonts() -> Array:
	if not FileAccess.file_exists(FONTS_DATA):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(FONTS_DATA))
	return d.get("fonts", []) if d is Dictionary else []


## `heads` — the headings: {intro, engine, third, texts, fonts}. `font_list` — the fonts' entries (tests pass their own).
static func build(heads: Dictionary, font_list: Array) -> String:
	var out := PackedStringArray()
	out.append(String(heads.get("intro", "")))
	out.append("")
	out.append("══ %s ══" % String(heads.get("engine", "Godot Engine")))
	out.append("")
	out.append(Engine.get_license_text().strip_edges())
	out.append("")
	out.append("══ %s ══" % String(heads.get("third", "Third-party")))
	out.append("")
	for c in Engine.get_copyright_info():
		out.append(String(c.get("name", "")))
		for p in c.get("parts", []):
			for line in p.get("copyright", []):
				out.append("    © " + String(line))
			out.append("    License: " + String(p.get("license", "")))
		out.append("")
	out.append("══ %s ══" % String(heads.get("fonts", "Fonts")))
	out.append("")
	for f in font_list:
		out.append("%s — %s (%s)" % [String(f.get("name", "")), String(f.get("license", "")), ", ".join(PackedStringArray(f.get("files", [])))])
		out.append("")
		out.append(String(f.get("text", "")))
		out.append("")
	out.append("══ %s ══" % String(heads.get("texts", "License texts")))
	out.append("")
	var li: Dictionary = Engine.get_license_info()
	var names: Array = li.keys()
	names.sort()
	for n in names:
		out.append("── %s ──" % String(n))
		out.append("")
		out.append(String(li[n]).strip_edges())
		out.append("")
	return "\n".join(out)
