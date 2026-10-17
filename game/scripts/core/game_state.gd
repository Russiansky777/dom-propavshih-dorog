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

const SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves"

var flags: Dictionary = {}          # String -> bool
var inventory: Array[String] = []   # item ids, no duplicates
var current_room: String = ""
var player_pos: Vector2 = Vector2.ZERO


# --- Flags -----------------------------------------------------------------

func set_flag(flag: String, value: bool = true) -> void:
	assert(flag != "", "flag name must not be empty")
	var old: bool = flags.get(flag, false)
	flags[flag] = value
	if old != value:
		flag_changed.emit(flag, value)


func has_flag(flag: String) -> bool:
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


# --- Reset / persistence ---------------------------------------------------

func reset() -> void:
	flags.clear()
	inventory.clear()
	current_room = ""
	player_pos = Vector2.ZERO
	state_reset.emit()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"flags": flags.duplicate(),
		"inventory": Array(inventory),
		"current_room": current_room,
		"player_pos": {"x": player_pos.x, "y": player_pos.y},
	}


func from_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_error("GameState: unsupported save version %s" % str(data.get("version")))
		return false
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
	return true


static func save_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


func save(slot: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("GameState: cannot create %s (%s)" % [SAVE_DIR, error_string(err)])
		return false
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot open %s for writing (%s)" % [save_path(slot), error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
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
	# Re-announce every flag so listeners (rooms, HUD, mirror) resync.
	for k in flags.keys():
		flag_changed.emit(k, flags[k])
	return true


func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))
