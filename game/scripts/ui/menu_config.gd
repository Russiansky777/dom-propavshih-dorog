class_name MenuConfig
extends RefCounted
## data/story/menu.json for the title screen and the pause menu, plus the art → screen mapping: menu art is
## 1672×941 and is stretched over the 1920×1080 canvas, so every coordinate in the data is in art pixels.
## Textures: game/assets/ui/menu/ (tools/import_menu_art.py) — a missing file is null, never an error.

const PATH := "res://data/story/menu.json"
const ART_DIR := "res://assets/ui/menu/"
const ART_SIZE := Vector2(1672.0, 941.0)
const SCREEN := Vector2(1920.0, 1080.0)

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("MenuConfig: %s missing or not a JSON object" % PATH)
			_data = {"title": {}, "pause": {}}
	return _data


static func section(name: String) -> Dictionary:
	var d = data().get(name, {})
	return d if d is Dictionary else {}


static func sx() -> float:
	return SCREEN.x / ART_SIZE.x


static func sy() -> float:
	return SCREEN.y / ART_SIZE.y


## Art pixel → canvas pixel.
static func pt(x: float, y: float) -> Vector2:
	return Vector2(x * sx(), y * sy())


static func texture(file: String) -> Texture2D:
	var p := ART_DIR + file
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


static func color(v, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return fallback


## Items of a menu with the platform filter applied (`desktop_only` — not on the web build).
static func items(menu: String) -> Array:
	var out: Array = []
	for it in section(menu).get("items", []):
		if bool(it.get("desktop_only", false)) and OS.has_feature("web"):
			continue
		out.append(it)
	return out
