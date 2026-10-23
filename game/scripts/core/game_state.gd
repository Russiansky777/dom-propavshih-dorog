extends Node
## Autoload `GameState`: the single source of truth for story state.
##
## Holds flags (semantic names only, e.g. `office_latch_open`), inventory item ids,
## the current room id and the player position. Persists as JSON in
## `user://saves/<slot>.json`. Never stores drawing coordinates as story state;
## `player_pos` is a restore convenience, not a story fact.

signal flag_changed(flag: String, value: bool)
signal inventory_changed()
signal state_reset()
signal state_loaded(slot: String)
signal state_saved(slot: String)
signal hint_shown(text: String)
signal goal_changed(text: String)

const SAVE_VERSION: int = 2
const SAVE_DIR: String = "user://saves"
## Slot kinds: "auto" (RoomManager: room change, scene beat, every 5 minutes of play — never in the middle of a
## line, a staging or a close-up; its own row in the menu, G4/G5), "quick" (F5/F9), "1".."3" (menu), checkpoints
## of scenes («day2»…), "pre_finale" (reserved for the point of no return; unused in M1).
const MANUAL_SLOTS: Array[String] = ["1", "2", "3"]

var flags: Dictionary = {}          # String -> bool
var inventory: Array[String] = []   # item ids, no duplicates
var current_room: String = ""
var player_pos: Vector2 = Vector2.ZERO
var journal_goal: String = ""       # current goal text (from the last main scene result)
var journal_goal_scene: String = "" # scene id that set the goal
var counters: Dictionary = {}       # String -> int (puzzle errors, hint tiers, ...)


# --- Flags -----------------------------------------------------------------

func set_flag(flag: String, value: bool = true) -> void:
	assert(flag != "", "flag name must not be empty")
	var old: bool = flags.get(flag, false)
	flags[flag] = value
	if old != value:
		flag_changed.emit(flag, value)


func has_flag(flag: String) -> bool:
	if flag.begins_with("tod_"):
		return TimeOfDay.has_virtual(flag)   # time of day: derived from the story, never stored (F17)
	return bool(flags.get(flag, false))


# --- Inventory -------------------------------------------------------------

func add_item(item_id: String) -> bool:
	## Returns false if the item is already held (an obligatory item is never given twice).
	if item_id == "" or inventory.has(item_id):
		return false
	inventory.append(item_id)
	inventory_changed.emit()
	return true


func has_item(item_id: String) -> bool:
	return inventory.has(item_id)


func remove_item(item_id: String) -> bool:
	var idx := inventory.find(item_id)
	if idx < 0:
		return false
	inventory.remove_at(idx)
	inventory_changed.emit()
	return true


# --- Hints (one-line UI message, consumed by the HUD) ----------------------

func show_hint(text: String) -> void:
	hint_shown.emit(text)


# --- Journal goal / counters ----------------------------------------------

func set_goal(text: String, scene_id: String = "") -> void:
	journal_goal = text
	journal_goal_scene = scene_id
	goal_changed.emit(text)


func get_counter(key: String) -> int:
	return int(counters.get(key, 0))


func set_counter(key: String, value: int) -> void:
	counters[key] = value


func inc_counter(key: String) -> int:
	var v := get_counter(key) + 1
	counters[key] = v
	return v


# --- Reset / persistence ---------------------------------------------------

func reset() -> void:
	flags.clear()
	inventory.clear()
	current_room = ""
	player_pos = Vector2.ZERO
	journal_goal = ""
	journal_goal_scene = ""
	counters.clear()
	state_reset.emit()


func to_dict(title: String = "") -> Dictionary:
	var d := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"saved_unix": Time.get_unix_time_from_system(),   # sub-second order of saves (title «Продолжить» — the newest)
		"flags": flags.duplicate(),
		"inventory": Array(inventory),
		"current_room": current_room,
		"player_pos": {"x": player_pos.x, "y": player_pos.y},
		"journal_goal": journal_goal,
		"journal_goal_scene": journal_goal_scene,
		"counters": counters.duplicate(),
	}
	# A named save (a scene's checkpoint, e.g. «День второй» after the night by the stove): the menu shows the title.
	if title != "":
		d["title"] = title
	return d


func from_dict(data: Dictionary) -> bool:
	var version := int(data.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		push_error("GameState: unsupported save version %s" % str(data.get("version")))
		return false
	# version 1 (M0 probe) lacks journal/counters: defaults below cover it.
	flags.clear()
	var raw_flags: Dictionary = data.get("flags", {})
	for k in raw_flags.keys():
		flags[String(k)] = bool(raw_flags[k])
	inventory.clear()
	for item in data.get("inventory", []):
		inventory.append(String(item))
	current_room = String(data.get("current_room", ""))
	var p: Dictionary = data.get("player_pos", {})
	player_pos = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	journal_goal = String(data.get("journal_goal", ""))
	journal_goal_scene = String(data.get("journal_goal_scene", ""))
	counters.clear()
	var raw_counters: Dictionary = data.get("counters", {})
	for k in raw_counters.keys():
		counters[String(k)] = int(raw_counters[k])
	return true


static func save_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


func save(slot: String, title: String = "") -> bool:
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("GameState: cannot create %s (%s)" % [SAVE_DIR, error_string(err)])
		return false
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot open %s for writing (%s)" % [save_path(slot), error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(to_dict(title), "\t"))
	f.close()
	state_saved.emit(slot)
	return true


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(save_path(slot))


func load(slot: String) -> bool:
	## Replaces the whole state from `user://saves/<slot>.json`.
	## Emits `state_loaded`; callers (RoomManager) are responsible for rebuilding the scene.
	if not has_save(slot):
		push_warning("GameState: no save in slot '%s'" % slot)
		return false
	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if f == null:
		push_error("GameState: cannot read %s" % save_path(slot))
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameState: save '%s' is not a JSON object" % slot)
		return false
	if not from_dict(parsed):
		return false
	state_loaded.emit(slot)
	goal_changed.emit(journal_goal)
	# Re-announce every flag so listeners (rooms, HUD, mirror) resync.
	for k in flags.keys():
		flag_changed.emit(k, flags[k])
	return true


## Summary of a slot for menus: {} when empty. `label` — «День второй · Мастерская · вечер» (G4), `place_time` —
## the same without the day (a checkpoint row already names its day).
func save_info(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var room := String(parsed.get("current_room", ""))
	var fl: Dictionary = parsed.get("flags", {}) if parsed.get("flags", {}) is Dictionary else {}
	var parts := place_parts(room, fl)
	return {"saved_at": String(parsed.get("saved_at", "")), "saved_unix": _saved_unix(parsed), "room": room,
		"goal": String(parsed.get("journal_goal", "")), "title": String(parsed.get("title", "")),
		"label": " · ".join(PackedStringArray([parts["day"], parts["place"], parts["time"]].filter(func(x): return x != ""))),
		"place_time": " · ".join(PackedStringArray([parts["place"], parts["time"]].filter(func(x): return x != "")))}


## When a save was written, seconds since the epoch: `saved_unix`, or `saved_at` (whole seconds) for older saves.
static func _saved_unix(parsed: Dictionary) -> float:
	if parsed.has("saved_unix"):
		return float(parsed["saved_unix"])
	var at := String(parsed.get("saved_at", ""))
	return float(Time.get_unix_time_from_datetime_string(at)) if at != "" else 0.0


## The newest existing save among `slots` ("" — none): the title screen's «Продолжить».
func latest_save(slots: Array) -> String:
	var best := ""
	var best_t := -1.0
	for s in slots:
		var info := save_info(String(s))
		if info.is_empty():
			continue
		var t := float(info.get("saved_unix", 0.0))
		if t > best_t:
			best_t = t
			best = String(s)
	return best


## Where and when a state is, in words (G4, Director 23.10: «автосохранение с местом и временем: "День второй,
## мастерская, вечер"»): {day: «День второй», place: «Мастерская», time: «вечер»} — the day and the time of day
## from the story state in `flags` (TimeOfDay: data/story/time, the journal's own line «День второй · вечер»), the
## place from the room's name. Works for old saves too: everything comes from their flags and room.
static func place_parts(room_id: String, flag_set: Dictionary) -> Dictionary:
	var out := {"day": "", "place": StoryData.place_name(room_id) if room_id != "" else "", "time": ""}
	var spec := TimeOfDay.state_spec(TimeOfDay.state_for(flag_set))
	var line := StoryData.text(String(spec.get("label", ""))) if not spec.is_empty() else ""
	var bits := line.split(" · ")
	if bits.size() >= 2:
		out["day"] = bits[0]
		out["time"] = bits[bits.size() - 1]
	elif line != "":
		out["day"] = line
	return out


## «День второй · Мастерская · вечер» for the running game.
func place_label() -> String:
	var parts := place_parts(current_room, flags)
	return " · ".join(PackedStringArray([parts["day"], parts["place"], parts["time"]].filter(func(x): return x != "")))


func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))
