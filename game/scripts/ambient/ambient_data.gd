class_name AmbientData
extends RefCounted
## «Живой мир» — data of the ambient layer: data/story/ambient/<LOC>.json (copied to
## res://data/story/ambient by tools/sync_story_data.sh) plus shared presets and the footfall
## measurement in data/story/ambient/_index.json.
##
## A room file is merged over its `preset` (deep merge of dictionaries, arrays replace), so a new
## street (Z4) needs one line: {"id": "Z4", "preset": "street"} → drizzle + wind; puddles, mud and
## sway regions are added when its art exists. Rooms without a file get nothing.
## Schema and checks: tools/validate_ambient.py; behaviour: tests/test_ambient.gd.

const DIR: String = "res://data/story/ambient"

static var _index: Dictionary = {}
static var _rooms: Dictionary = {}     # LOC -> merged spec ({} = no ambient)
static var _loaded: bool = false
static var errors: Array[String] = []


static func reload() -> void:
	_loaded = false
	_index = {}
	_rooms = {}
	errors.clear()
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var idx = _read(DIR + "/_index.json")
	_index = idx if idx is Dictionary else {}


static func index() -> Dictionary:
	_ensure()
	return _index


## Merged ambient spec of a room ({} when the room has no ambient file).
static func room(room_id: String) -> Dictionary:
	_ensure()
	if _rooms.has(room_id):
		return _rooms[room_id]
	var spec := {}
	var path := "%s/%s.json" % [DIR, room_id]
	if FileAccess.file_exists(path):
		var doc = _read(path)
		if doc is Dictionary:
			spec = doc
			var preset := String(doc.get("preset", ""))
			if preset != "":
				var presets: Dictionary = _index.get("presets", {})
				if presets.has(preset):
					spec = merge(presets[preset], doc)
				else:
					errors.append("%s: unknown preset '%s'" % [path, preset])
					push_error("AmbientData: " + errors[-1])
	_rooms[room_id] = spec
	return spec


## Footfall measurement of an actor's walk sheet (contact frames, foot offset).
static func footfall(actor_id: String) -> Dictionary:
	return index().get("footfall", {}).get(actor_id, {})


## Ground model shared by the shaders and the footfall: see _index.json `camera`.
static func camera() -> Dictionary:
	return index().get("camera", {})


static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open " + path)
		return null
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		errors.append("%s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		push_error("AmbientData: " + errors[-1])
		return null
	return json.data


# --- Geometry helpers shared by the builder, footfall and tests ---------------------------------

static func poly(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func rect_poly(r: Array) -> PackedVector2Array:
	var x := float(r[0])
	var y := float(r[1])
	var w := float(r[2])
	var h := float(r[3])
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


## `polygon` [[x,y],…] or `rect` [x,y,w,h] of an entry (empty when neither).
static func shape_of(entry: Dictionary) -> PackedVector2Array:
	if entry.has("polygon"):
		return poly(entry["polygon"])
	if entry.has("rect"):
		return rect_poly(entry["rect"])
	return PackedVector2Array()


static func bbox(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
