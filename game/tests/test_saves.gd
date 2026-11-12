extends SceneTree
## Saves of batch G (Director 23.10):
##   G4 — «строка "День второй H1…"»: a save slot says the day, the place and the time of day in words
##        («День второй · Мастерская · вечер»), from the story state of the save (old saves too);
##   G5 — «автосохранение раз в 5 минут»: a timed autosave into its own slot (never the player's), never in the middle
##        of a line, a staging or a close-up (it waits for the first free moment); entering a new day saves too;
##        loading the autosave repeats no one-off event (CLAUDE.md) and blocks nothing; the menu shows its row.
##   godot --headless --path game -s res://tests/test_saves.gd
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
var player: Node2D = null
var SLOT := "test_saves_%d" % OS.get_process_id()
var MANUAL := "test_saves_manual_%d" % OS.get_process_id()
var CP := "test_saves_cp_%d_" % OS.get_process_id()
var _reached_end: bool = false   # a test that stopped on a script error must not pass


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	_reached_end = false
	var started := Time.get_ticks_msec()
	await fn.call()
	if not _reached_end:
		_fails.append("the test stopped before its end (script error?)")
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	# The test's own autosave slot, set before the menu is built (its «Автосохранение» row reads it): the shared
	# user://saves/auto.json is written by other test runs on this machine at any moment.
	rm.autosave_slot = SLOT
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	ui = main_node.get_node("GameUi")
	player = main_node.get_node("World/Player")
	rm.autosave_enabled = false
	rm.autosave_slot = SLOT
	rm.checkpoint_prefix = CP
	await _test("G4: a slot says the day, the place and the time of day in words (also an old save); the menu shows it", _test_label)
	await _test("G5: every interval of play an autosave — never in a line, a close-up, an item close-up; it waits and then saves; manual slots untouched", _test_timer)
	await _test("G5: entering a new day saves («День второй» in the autosave)", _test_new_day)
	await _test("G5: loading the autosave repeats no one-off event and blocks nothing; the menu's «Автосохранение» row loads it", _test_load_no_repeat)
	await _test("Ревью 01.11 (В-1): a save is written through a temporary file with a .bak of the old one; a cut-off file, wrong kinds or an unknown room leave the running game as it was and read the backup", _test_damaged_saves)
	await _test("Review 12.11: the reference saves of every data version load as they were saved — the room, the bag, the goal; nothing plays by itself; the current version has its own", _test_reference_saves)
	gs.reset()
	for s in [SLOT, MANUAL, CP + "day2", CP + "day3", CP + "day4", SLOT + "_dmg"]:
		gs.delete_save(s)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== saves (G4, G5): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Reference saves ------------------------------------------------------------------------

## Review 12.11 («формат сохранений не закреплён: нет эталонных сохранений, номер версии не меняется»): saves really
## played by the bots' chain (tools/run_tests.sh: a new game → the credits) are kept per data version in
## res://tests/data/saves_ref/<story_version>/ — the morning of day two, the far pier, «День третий», «День четвёртый»,
## after the end. Every one of them, of every version, must go on loading: a player's save made with a released build
## has to open in every later one. A new data version (meta.json story_version — tools/validate_story.py asks for it
## when the names of flags, scenes, items or rooms change) needs its own set:
##   the chain with CHAIN_KEEP=1 (ONLY="walkthrough" CHAIN_OUT=… run_tests.gd → test_day2.gd → test_day3.gd), then
##   the five files from user://saves into a new folder here.
## Self-check — the same save pointing to a room that is gone does not load.
const REF_DIR := "res://tests/data/saves_ref"


func _test_reference_saves() -> void:
	var versions := DirAccess.get_directories_at(REF_DIR)
	_check(versions.has(String(sd.story_version)), "no reference saves for the current data version «%s» (%s has %s) — play the chain with CHAIN_KEEP=1 and put its five saves there" % [String(sd.story_version), REF_DIR, str(versions)])
	var n := 0
	var first_raw := ""
	for v in versions:
		var files := DirAccess.get_files_at("%s/%s" % [REF_DIR, v])
		_check(files.size() >= 5 or String(v) != String(sd.story_version), "data version «%s» has %d reference saves (five: the morning of day two, the far pier, days three and four, after the end)" % [v, files.size()])
		for f in files:
			if not String(f).ends_with(".json"):
				continue
			var raw := FileAccess.get_file_as_string("%s/%s/%s" % [REF_DIR, v, f])
			var d = JSON.parse_string(raw)
			_check(d is Dictionary, "%s/%s is not a save file" % [v, f])
			if not (d is Dictionary):
				continue
			if first_raw == "":
				first_raw = raw
			var slot := "test_ref_%d_%d" % [OS.get_process_id(), n]
			DirAccess.make_dir_recursive_absolute("user://saves")
			var w := FileAccess.open(gs.save_path(slot), FileAccess.WRITE)
			w.store_string(raw)
			w.close()
			gs.reset()
			var ok: bool = rm.load_game(slot)
			_check(ok, "%s/%s (saved in %s) does not load" % [v, f, String(d.get("current_room", ""))])
			if ok:
				await _frames(8)
				_check(String(gs.current_room) == String(d.get("current_room", "")) and rm.current_room != null, "%s/%s: loaded into «%s», saved in «%s»" % [v, f, String(gs.current_room), String(d.get("current_room", ""))])
				var lost: Array = []
				for fl in (d.get("flags", {}) as Dictionary).keys():
					if bool(d["flags"][fl]) and not gs.has_flag(String(fl)) and not (sd.get("flag_renames") is Dictionary and (sd.get("flag_renames") as Dictionary).has(String(fl))):
						lost.append(String(fl))
				_check(lost.is_empty(), "%s/%s: flags of the save lost on loading: %s" % [v, f, str(lost.slice(0, 8))])
				var bag: Array = []
				for it in d.get("inventory", []):
					bag.append(String(it))
				_check(gs.inventory == bag or Array(gs.inventory) == bag, "%s/%s: the bag %s, saved %s" % [v, f, str(gs.inventory), str(bag)])
				_check(String(gs.journal_goal) == String(d.get("journal_goal", "")), "%s/%s: the journal's goal «%s», saved «%s»" % [v, f, String(gs.journal_goal), String(d.get("journal_goal", ""))])
				if not gs.has_flag("game_finished"):
					await _frames(30)
					_check(sr.current_beat.is_empty() and not sr.is_staging(), "%s/%s: after loading something plays by itself (%s)" % [v, f, str(sr.current_beat).substr(0, 120)])
			gs.delete_save(slot)
			n += 1
	_check(n >= 5, "only %d reference saves read" % n)
	print("        reference saves: %d of %d data version(s) %s load as saved" % [n, versions.size(), str(versions)])
	# self-check: a save of a room that is gone is refused — a version that renamed a room would be caught here
	if first_raw != "":
		var bad: Dictionary = JSON.parse_string(first_raw)
		bad["current_room"] = "NO_SUCH_ROOM"
		var bslot := "test_ref_%d_bad" % OS.get_process_id()
		var bw := FileAccess.open(gs.save_path(bslot), FileAccess.WRITE)
		bw.store_string(JSON.stringify(bad))
		bw.close()
		gs.reset()
		_check(not rm.load_game(bslot), "self-check: a reference save pointing to a room that is gone loads — the test would not catch a renamed room")
		gs.delete_save(bslot)
	gs.reset()
	_reached_end = true


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _main_scenes() -> Array:
	var out: Array = []
	for id in sd.scene_order:
		if String(sd.scene(id).get("type", "")) == "main":
			out.append(id)
	return out


## The story up to (not including) scene `upto`: done_<scene> and the grants of every main scene before it.
func _flags_before(upto: String) -> void:
	gs.reset()
	for id in _main_scenes():
		if id == upto:
			return
		gs.flags["done_" + id] = true
		gs.flags["started_" + id] = true
		for f in sd.scene(id).get("grants", {}).get("flags", []):
			gs.flags[String(f)] = true


func _enter(room: String) -> void:
	var was: bool = rm.autosave_enabled
	rm.autosave_enabled = false
	rm.change_room(room, "")
	await _frames(3)
	rm.autosave_enabled = was


## Reads every text on screen.
func _finish() -> Array[String]:
	var seen: Array[String] = []
	var g := 0
	while g < 600 and (not sr.current_beat.is_empty() or sr.is_staging()):
		g += 1
		var b: Dictionary = sr.current_beat
		if not b.is_empty():
			if String(b.get("type", "")) == "options":
				var opts: Array = sr.current_options()
				sr.choose(String(opts[0].get("id", "")))
			else:
				seen.append("%s: %s" % [String(b.get("speaker", "")), String(b.get("text", ""))])
				sr.advance()
		await process_frame
	return seen


func _seconds(s: float) -> void:
	await create_timer(s).timeout


# --- G4 ------------------------------------------------------------------------------------

func _test_label() -> void:
	_flags_before("M16s")   # after the plate at the turn: the evening of day two
	await _enter("H2")
	_check(rm.save_game(MANUAL), "saved")
	var info: Dictionary = gs.save_info(MANUAL)
	_check(String(info.get("label", "")) == "День второй · Мастерская · вечер", "the slot line: «День второй · Мастерская · вечер» (%s)" % String(info.get("label", "")))
	_check(String(info.get("place_time", "")) == "Мастерская · вечер", "a checkpoint row (named by its day): «Мастерская · вечер» (%s)" % String(info.get("place_time", "")))
	_check(not String(info.get("label", "")).contains("H2"), "no room code in it")
	_check(gs.place_label() == "День второй · Мастерская · вечер", "the running game: %s" % gs.place_label())
	# Day one, the post office: «День первый · Почта Тамары · после полудня».
	gs.reset()
	await _enter("Z1")
	var parts: Dictionary = gs.place_parts("Z1", gs.flags)
	_check(String(parts["day"]) == "День первый" and String(parts["place"]) == "Почта Тамары" and String(parts["time"]) == "после полудня", "day one at the post office: %s" % str(parts))
	# An old save (written before G4: no label in it) — the line comes from its flags and room.
	var old := {"version": 2, "saved_at": "2026-10-22T10:00:00", "flags": {"done_N01": true, "done_M01": true}, "inventory": [],
		"current_room": "M1", "player_pos": {"x": 900, "y": 800}, "journal_goal": "", "journal_goal_scene": "", "counters": {}}
	var f := FileAccess.open(gs.save_path(MANUAL), FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	_check(String(gs.save_info(MANUAL).get("label", "")) == "День второй · Двор мельницы · утро", "an old save: %s" % String(gs.save_info(MANUAL).get("label", "")))
	_check(String(sd.text("@ui.autosave")) == "Автосохранение", "the autosave row is «Автосохранение»")
	_reached_end = true


# --- G5: the timer and the guard -------------------------------------------------------------

func _test_timer() -> void:
	_flags_before("M16s")
	await _enter("H2")
	gs.delete_save(SLOT)
	_check(rm.save_game(MANUAL), "a manual save")
	var manual_before := FileAccess.get_file_as_string(gs.save_path(MANUAL))
	_check(float(rm.autosave_interval_s) == 300.0, "the interval from data: 5 minutes (%.0f s)" % float(rm.autosave_interval_s))
	rm.autosave_interval_s = 1.0
	rm.play_since_autosave = 0.0
	rm.autosave_pending = false
	rm.autosave_enabled = true
	var n0: int = rm.autosaves_done
	await _seconds(1.4)
	_check(gs.has_save(SLOT) and int(rm.autosaves_done) == n0 + 1, "after the interval of play: an autosave (%d)" % (int(rm.autosaves_done) - n0))
	# A line on screen: the interval passes, nothing is written; read it — saved at once.
	gs.delete_save(SLOT)
	sr.narrate("Проверка: строка на экране.")
	await _seconds(1.5)
	_check(not gs.has_save(SLOT) and bool(rm.autosave_pending), "a line on screen: no autosave, it waits")
	await _finish()
	await _frames(2)
	_check(gs.has_save(SLOT), "the line read: the autosave written")
	# A story event during a line (RoomManager.autosave from a scene / close-up event) waits too.
	gs.delete_save(SLOT)
	rm.play_since_autosave = -1000.0
	sr.narrate("Ещё строка.")
	_check(not rm.autosave(), "an event autosave in a line is not written now")
	await _frames(3)
	_check(not gs.has_save(SLOT), "… not yet")
	await _finish()
	await _frames(2)
	_check(gs.has_save(SLOT), "… written once the line is gone")
	# A close-up (mechanic) open: nothing; closed: saved.
	gs.delete_save(SLOT)
	rm.play_since_autosave = 0.0
	sr.open_mechanic({"type": "photo", "photo": {"image": "res://assets/closeups/closeup_office_photo.png"}, "title": "Тест"}, "")
	await _seconds(1.5)
	_check(sr.mechanic_open and not gs.has_save(SLOT), "a close-up open: no autosave")
	sr.close_mechanic()
	await _frames(3)
	await _finish()
	await _frames(2)
	_check(gs.has_save(SLOT), "the close-up put away: saved")
	# An item close-up («Рассмотреть»): nothing either.
	gs.delete_save(SLOT)
	gs.add_item("pocket_watch")
	rm.play_since_autosave = 0.0
	sr.examine_item("pocket_watch")
	await _seconds(1.5)
	_check(sr.examined_item != "" and not gs.has_save(SLOT), "an item close-up open: no autosave")
	sr.close_examine()
	await _finish()
	await _frames(3)
	_check(gs.has_save(SLOT), "the item close-up put away: saved")
	_check(FileAccess.get_file_as_string(gs.save_path(MANUAL)) == manual_before, "the manual slot is never touched by an autosave")
	rm.autosave_enabled = false
	rm.autosave_interval_s = 300.0
	_reached_end = true


func _test_new_day() -> void:
	_flags_before("N01")
	for f in ["visited_H1", "house_unlocked", "stove_lit"]:
		gs.flags[f] = true
	await _enter("H1")
	await _finish()
	gs.delete_save(SLOT)
	rm.autosave_enabled = true
	rm.play_since_autosave = 0.0
	rm.autosave_interval_s = 300.0
	sr.call("_complete_scene", "N01")   # the night by the stove is over: day two
	await _finish()
	await _frames(3)
	var info: Dictionary = gs.save_info(SLOT)
	_check(String(info.get("label", "")).begins_with("День второй"), "the autosave on entering day two: %s" % String(info.get("label", "")))
	_check(gs.has_save(CP + "day2"), "and the day's checkpoint «День второй»")
	rm.autosave_enabled = false
	_reached_end = true


# --- G5: loading the autosave -------------------------------------------------------------------

func _test_load_no_repeat() -> void:
	# The first entry into the winter class says «Там зима…» once (on_enter once_flag); the autosave is made after it.
	_flags_before("M06")
	for f in ["house_unlocked", "door_school_installed"]:
		gs.flags[f] = true
	gs.flags.erase("o1_saw_winter")
	gs.delete_save(SLOT)
	rm.autosave_enabled = true
	rm.change_room("O1", "")
	await _frames(3)
	_check(not gs.has_save(SLOT) and not sr.current_beat.is_empty(), "entering: «Там зима» on screen, the autosave waits for it")
	var seen := await _finish()
	_check(seen.size() >= 1, "the first-entry line once (%s)" % str(seen))
	await _frames(3)
	_check(gs.has_save(SLOT) and gs.has_flag("o1_saw_winter"), "after the line: the autosave, the line marked as seen")
	var scene_flags := {}
	for k in gs.flags.keys():
		if String(k).begins_with("done_"):
			scene_flags[k] = true
	rm.autosave_enabled = false
	# Load it from the menu row «Автосохранение» (a real click on its button).
	gs.reset()
	await _enter("Z1")
	await _finish()
	ui.call("toggle_menu")
	await _frames(3)
	var pr: Dictionary = ui.call("probe_positions")
	var slots: Dictionary = pr.get("slots", {})
	_check(slots.has(SLOT) and bool(slots[SLOT].get("visible", false)) and String(slots[SLOT].get("text", "")).contains("Зимний класс"),
		"the menu: «Автосохранение» row with its line (%s)" % str(slots.get(SLOT, {})))
	var btn: Dictionary = pr.get("buttons", {}).get("Load" + SLOT, {})
	_check(not btn.is_empty(), "its «Загрузить» button")
	if not btn.is_empty():
		var at := Vector2(float(btn["x"]), float(btn["y"]))
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = root.get_final_transform() * at
			ev.global_position = ev.position
			Input.parse_input_event(ev)
			await _frames(1)
	await _frames(6)
	_check(gs.current_room == "O1" and rm.current_room != null and rm.current_room.room_id == "O1", "loaded into the class (%s)" % gs.current_room)
	_check(sr.current_beat.is_empty() and not sr.is_staging(), "nothing replays on loading: no «Там зима» again (%s)" % str(sr.current_beat))
	var lost := []
	for k in scene_flags.keys():
		if not gs.has_flag(String(k)):
			lost.append(k)
	_check(lost.is_empty(), "every done scene stays done (%s)" % str(lost))
	_check(not sr.is_busy(), "nothing blocks: the player can act")
	_reached_end = true


func _test_damaged_saves() -> void:
	var slot := SLOT + "_dmg"
	gs.delete_save(slot)
	gs.reset()
	gs.set_flag("done_M01", true)
	gs.set_flag("house_unlocked", true)
	gs.add_item("key_house")
	_check(rm.start_at("house"), "a game to save")
	await process_frame
	gs.set_flag("marker_first", true)
	_check(rm.save_game(slot), "first save")
	var path: String = gs.save_path(slot)
	var bak: String = gs.backup_path(slot)
	_check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "the file is in place, no temporary left")
	# ревью 01.11 (Б-7): the save names the story data it was written with; the menu's info carries it
	var written = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(written is Dictionary and String(written.get("story_version", "")) == sd.story_version and sd.story_version != "", "the save carries story_version %s" % str(written.get("story_version", "") if written is Dictionary else ""))
	_check(String(gs.save_info(slot).get("story_version", "")) == sd.story_version, "save_info shows it")
	var first := FileAccess.get_file_as_string(path)
	gs.set_flag("marker_second", true)
	_check(rm.save_game(slot) and FileAccess.file_exists(bak) and FileAccess.get_file_as_string(bak) == first, "the second save keeps the first as .bak")
	var second := FileAccess.get_file_as_string(path)
	# 1. a cut-off write: half a file — the backup is read instead, the game state untouched
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(second.left(second.length() / 2))
	f.close()
	var info: Dictionary = gs.save_info(slot)
	_check(not info.is_empty() and gs.has_save(slot), "a cut-off file: the slot still shows in the menu (from the backup): %s" % str(info.get("label", "")))
	gs.reset()
	gs.set_flag("marker_before_load", true)
	_check(gs.load(slot) and gs.has_flag("marker_first") and not gs.has_flag("marker_second") and not gs.has_flag("marker_before_load"), "a cut-off file: the backup (the first save) loads")
	# 2. a sound JSON with fields of the wrong kind: refused, the running state stays
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": gs.SAVE_VERSION, "flags": [], "inventory": [], "current_room": "H1"}))
	f.close()
	DirAccess.remove_absolute(bak)
	gs.reset()
	gs.set_flag("marker_before_load", true)
	_check(not gs.load(slot) and gs.has_flag("marker_before_load") and gs.flags.size() == 1, "flags not a dictionary: refused, nothing replaced")
	# 3. an unknown room (a renamed room, a hand-edited file): refused before the state changes
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": gs.SAVE_VERSION, "flags": {"done_M01": true}, "inventory": ["key_house", "key_house"], "current_room": "NO_SUCH_ROOM"}))
	f.close()
	_check(not gs.load(slot) and gs.has_flag("marker_before_load") and not gs.has_flag("done_M01"), "an unknown room: refused, nothing replaced")
	_check(not rm.load_game(slot) and gs.has_flag("marker_before_load"), "RoomManager.load_game refuses it too and keeps the game")
	# ревью 01.11 (В-18): the refusal is said to the player — the menu's load says why (@ui.load_failed)
	if ui != null:
		var hints: Array[String] = []
		var cb := func(t: String): hints.append(t)
		gs.hint_shown.connect(cb)
		ui.call("_do_load", slot)
		await process_frame
		await process_frame
		gs.hint_shown.disconnect(cb)
		_check(hints.has(sd.text("@ui.load_failed")) and gs.has_flag("marker_before_load"), "a damaged slot from the menu: «не прочиталось» in the hint, the game stays: %s" % str(hints))
	# 4. a doubled item in the file comes into the bag once
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": gs.SAVE_VERSION, "flags": {"done_M01": true}, "inventory": ["key_house", "key_house", "no_such_item"], "current_room": "H1", "player_pos": {"x": 900, "y": 800}}))
	f.close()
	_check(gs.load(slot) and gs.inventory.count("key_house") == 1, "a doubled item in the file comes in once (%s)" % str(gs.inventory))
	gs.delete_save(slot)
	_check(not FileAccess.file_exists(path) and not FileAccess.file_exists(bak), "delete removes the file and its backup")
	_reached_end = true

