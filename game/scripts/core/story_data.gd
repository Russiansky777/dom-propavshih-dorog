extends Node
## Autoload `StoryData`: read-only access to data/story (copied into res://data/story by tools/sync_story_data.sh).
##
## Loads locations, items, flags, characters, scenes (E*.json + quests), rooms/*.json and text/*.json.
## Nothing here knows about specific scene ids: the game logic reads this data generically.

const DATA_DIR: String = "res://data/story"

var locations: Dictionary = {}          # id -> location dict
var edges: Dictionary = {}              # room id -> {other id -> requires: Array[String]}
var start_location: String = "Z1"
var items: Dictionary = {}              # id -> item dict
var flag_desc: Dictionary = {}          # flag -> {desc, min_episode?}
var characters: Dictionary = {}         # id -> character dict
var scenes: Dictionary = {}             # id -> scene dict (quests normalised to the same shape)
var scene_order: Array[String] = []     # ids in file order (episodes first, then quests)
var rooms: Dictionary = {}              # room id -> room dict
var rooms_index: Dictionary = {}
var texts: Dictionary = {}              # key -> {text, draft}
## Director's switches (data/story/meta.json → switches: the last shot, a word about Agata's future …): one
## value each, so an answer of the Director is a one-line change. Lines and stagings name them in `switch`.
var switches: Dictionary = {}
var autosave_cfg: Dictionary = {}       # meta.json `autosave` {interval_s} (G5)
var save_fixups: Array = []             # meta.json `save_fixups` [{if, unless, scene}] — old saves after a rule change (T8)
## Start points (data/story/start_points.json): a state to start from for checking a later part of the game.
var start_points: Dictionary = {}
var loaded: bool = false
var load_errors: Array[String] = []


func _ready() -> void:
	reload()


func reload() -> void:
	load_errors.clear()
	TimeOfDay.reload()   # время суток читает data/story/time заново (F17)
	_load_locations()
	_load_items()
	_load_flags()
	_load_characters()
	_load_scenes()
	_load_rooms()
	_load_texts()
	_load_meta()
	loaded = load_errors.is_empty()
	for e in load_errors:
		push_error("StoryData: " + e)


# --- Loading helpers -------------------------------------------------------

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("missing file " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("cannot open " + path)
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		load_errors.append("%s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _list_files(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_errors.append("missing dir " + dir_path)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(suffix) and not name.begins_with("_"):
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _load_locations() -> void:
	var doc = _read_json(DATA_DIR + "/locations.json")
	if doc == null:
		return
	locations.clear()
	edges.clear()
	start_location = String(doc.get("start", "Z1"))
	for l in doc.get("locations", []):
		locations[String(l["id"])] = l
		edges[String(l["id"])] = {}
	for e in doc.get("edges", []):
		var a := String(e["from"])
		var b := String(e["to"])
		var req: Array = e.get("requires", [])
		if not edges.has(a):
			edges[a] = {}
		if not edges.has(b):
			edges[b] = {}
		edges[a][b] = {"requires": req, "crossing": bool(e.get("crossing", false)), "how": String(e.get("how", ""))}
		edges[b][a] = {"requires": req, "crossing": bool(e.get("crossing", false)), "how": String(e.get("how", ""))}


func _load_items() -> void:
	var doc = _read_json(DATA_DIR + "/items.json")
	if doc == null:
		return
	items.clear()
	for it in doc.get("items", []):
		items[String(it["id"])] = it


func _load_flags() -> void:
	var doc = _read_json(DATA_DIR + "/flags.json")
	if doc == null:
		return
	flag_desc = doc.get("flags", {})


func _load_characters() -> void:
	var doc = _read_json(DATA_DIR + "/characters.json")
	if doc == null:
		return
	characters.clear()
	for c in doc.get("characters", []):
		characters[String(c["id"])] = c


func _load_scenes() -> void:
	scenes.clear()
	scene_order.clear()
	for name in _list_files(DATA_DIR + "/scenes", ".json"):
		var doc = _read_json(DATA_DIR + "/scenes/" + name)
		if doc == null:
			continue
		for sc in doc.get("scenes", []):
			var id := String(sc["id"])
			sc["episode"] = int(doc.get("episode", 0))
			scenes[id] = sc
			scene_order.append(id)
	var qdoc = _read_json(DATA_DIR + "/quests.json")
	if qdoc != null:
		for q in qdoc.get("quests", []):
			var id := String(q["id"])
			q["type"] = "quest"
			if not q.has("grants"):
				q["grants"] = {"flags": [], "items": []}
			if not q.has("mandatory_lines"):
				q["mandatory_lines"] = q.get("lines", [])
			scenes[id] = q
			scene_order.append(id)


func _load_rooms() -> void:
	rooms.clear()
	var idx = _read_json(DATA_DIR + "/rooms/_index.json")
	rooms_index = idx if idx != null else {}
	for name in _list_files(DATA_DIR + "/rooms", ".json"):
		var doc = _read_json(DATA_DIR + "/rooms/" + name)
		if doc == null:
			continue
		rooms[String(doc.get("id", name.get_basename()))] = doc


func _load_meta() -> void:
	var meta = _read_json(DATA_DIR + "/meta.json")
	switches = meta.get("switches", {}) if meta is Dictionary else {}
	autosave_cfg = meta.get("autosave", {}) if meta is Dictionary and meta.get("autosave", {}) is Dictionary else {}
	save_fixups = meta.get("save_fixups", []) if meta is Dictionary and meta.get("save_fixups", []) is Array else []
	start_points.clear()
	if FileAccess.file_exists(DATA_DIR + "/start_points.json"):
		var sp = _read_json(DATA_DIR + "/start_points.json")
		if sp is Dictionary:
			for p in sp.get("points", []):
				start_points[String(p.get("id", ""))] = p


## `switch` of a line or staging: "name" — the switch is true; "name=value" — it equals value.
func switch_on(expr: String) -> bool:
	var neg := expr.contains("!=")
	var parts := expr.split("!=" if neg else "=", true, 1)
	var v = switches.get(parts[0], null)
	if v is Dictionary:
		v = v.get("value", null)
	if parts.size() == 2:
		var eq: bool = v != null and str(v) == parts[1]
		return not eq if neg else eq
	return v != null and bool(v)


func _load_texts() -> void:
	texts.clear()
	for name in _list_files(DATA_DIR + "/text", ".json"):
		var doc = _read_json(DATA_DIR + "/text/" + name)
		if doc == null:
			continue
		for k in doc.get("texts", {}).keys():
			texts[String(k)] = doc["texts"][k]


# --- Queries ----------------------------------------------------------------

func has_room(room_id: String) -> bool:
	return rooms.has(room_id)


func room(room_id: String) -> Dictionary:
	return rooms.get(room_id, {})


func in_scope(room_id: String) -> bool:
	return rooms_index.get("in_scope", []).has(room_id)


func location_name(loc_id: String) -> String:
	var l: Dictionary = locations.get(loc_id, {})
	return String(l.get("name", loc_id))


## The place a room stands for, in words: its location's name; a frame room (frame: true) — its `place` (a location
## id) or `title` (a text key), as in the title bar. Save slots (G4) and the room line use it.
func place_name(room_id: String) -> String:
	var spec: Dictionary = room(room_id)
	if spec.has("place"):
		return location_name(String(spec["place"]))
	if spec.has("title"):
		return text(String(spec["title"]))
	return location_name(room_id)


func scene(scene_id: String) -> Dictionary:
	return scenes.get(scene_id, {})


## The journal goal after a scene (T8, Director 24.10: the free day names only what is still to do). `goal_left`
## {lead, head, items: [{if, unless, text}], joiner, none}: `lead`, then `head` + the items whose flags hold now (done
## ones drop out), joined by `joiner`; nothing left — `lead` + `none`. Without it — `goal` (or `result`).
func scene_goal(sc: Dictionary) -> String:
	var gl: Dictionary = sc.get("goal_left", {})
	if gl.is_empty():
		return String(sc.get("goal", sc.get("result", "")))
	var left: Array[String] = []
	for it in gl.get("items", []):
		var ok := true
		for f in it.get("if", []):
			if not GameState.has_flag(String(f)):
				ok = false
		for f in it.get("unless", []):
			if GameState.has_flag(String(f)):
				ok = false
		if ok:
			left.append(text(String(it.get("text", ""))))
	var lead := text(String(gl.get("lead", "")))
	var tail := text(String(gl.get("none", ""))) if left.is_empty() else text(String(gl.get("head", ""))) + String(gl.get("joiner", ", ")).join(left) + "."
	return (lead + " " + tail).strip_edges()


func scenes_in(room_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in scene_order:
		var sc: Dictionary = scenes[id]
		if sc.get("locations", []).has(room_id):
			out.append(id)
	return out


## Rooms that declare how `scene_id` is triggered (trigger or complete_when). A scene declared
## anywhere never auto-starts on entry elsewhere.
func scene_trigger_rooms(scene_id: String) -> Array[String]:
	var out: Array[String] = []
	for rid in rooms.keys():
		if rooms[rid].get("scenes", {}).has(scene_id):
			out.append(String(rid))
	return out


## Checkpoint saves of scenes in story order: [{scene, slot, title}] (scenes data `checkpoint`; N01 → «День второй»).
func checkpoints() -> Array:
	var out: Array = []
	for id in scene_order:
		var cp: Dictionary = scenes[id].get("checkpoint", {})
		if not cp.is_empty() and String(cp.get("slot", "")) != "":
			out.append({"scene": id, "slot": String(cp["slot"]), "title": String(cp.get("title", ""))})
	return out


func item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func item_name(item_id: String) -> String:
	return String(items.get(item_id, {}).get("name", item_id))


func item_is_inventory(item_id: String) -> bool:
	return bool(items.get(item_id, {}).get("inventory", false))


func character_name(char_id: String) -> String:
	var c: Dictionary = characters.get(char_id, {})
	var n = c.get("name", null)
	return String(n) if n != null else char_id


## Resolves "@key" references through data/story/text; plain strings pass through.
## `params` substitutes "{name}" placeholders.
func text(key_or_text: String, params: Dictionary = {}) -> String:
	var out := key_or_text
	if key_or_text.begins_with("@"):
		var key := key_or_text.substr(1)
		if key.begins_with("char."):
			out = character_name(key.substr(5))
		elif texts.has(key):
			out = String(texts[key].get("text", key_or_text))
		else:
			push_warning("StoryData: missing text for " + key_or_text)
			out = "[" + key + "]"
	for p in params.keys():
		out = out.replace("{%s}" % p, str(params[p]))
	return out


## The character line a text entry carries (field `line` {speaker, text[, tags]}): the words of a character
## next to Agata, shown and voiced as their line instead of `text` (data/story/voice.json → character_lines).
## {} when the entry has none (or for plain text).
func text_line(key_or_text: String) -> Dictionary:
	if not key_or_text.begins_with("@"):
		return {}
	var entry: Dictionary = texts.get(key_or_text.substr(1), {})
	var ln = entry.get("line", null)
	if ln is Dictionary and String(ln.get("speaker", "")) != "" and String(ln.get("text", "")) != "":
		return ln
	return {}


func text_is_draft(key_or_text: String) -> bool:
	if not key_or_text.begins_with("@"):
		return false
	var entry: Dictionary = texts.get(key_or_text.substr(1), {})
	return bool(entry.get("draft", false))


func flag_description(flag: String) -> String:
	var d: Dictionary = flag_desc.get(flag, {})
	return String(d.get("desc", ""))


## Hints for a scene as a 3-tier list (data `hints` array, or single `hint`, padded by generic UI hints).
func scene_hints(scene_id: String) -> Array[String]:
	var out: Array[String] = []
	var sc := scene(scene_id)
	if sc.has("hints"):
		for h in sc["hints"]:
			out.append(String(h))
	elif sc.has("hint"):
		out.append(String(sc["hint"]))
	var generic := ["@ui.hint_generic_1", "@ui.hint_generic_2", "@ui.hint_generic_3"]
	var gi := 0
	while out.size() < 3 and gi < generic.size():
		out.append(text(generic[gi]))
		gi += 1
	return out
