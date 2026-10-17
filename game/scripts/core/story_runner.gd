extends Node
## Autoload `StoryRunner`: executes story scenes from data (scenes/*.json, quests.json, rooms/*.json).
##
## All story logic is generic: a scene starts when its `requires` hold, the player is in one of its
## locations and the room JSON's trigger condition is met (`complete_when` flags, `talk:` hotspot,
## `puzzle:` hotspot, or plain entry). Lines play as beats (click to advance), options are a generic
## list, grants/consumes apply on completion, the journal goal is the scene's `result`.
## No `if scene_id == ...` lives here.

signal beat_changed()
signal scene_started(scene_id: String)
signal scene_completed(scene_id: String)
signal item_selection_changed(item_id: String)
signal puzzle_opened()
signal puzzle_closed()
signal puzzle_state_changed()
signal loop_transition(spec: Dictionary)
signal hint_revealed(tier: int, text: String)
signal item_received(item_id: String)
## A hotspot with `panel: {id, sets}` (rooms data) asks the UI to open a panel (e.g. the Zarechye plan).
signal panel_requested(panel_id: String, source: Node)

const LOOP_FADE_SECONDS: float = 0.35

var selected_item: String = ""
var current_beat: Dictionary = {}
var active_scene: String = ""
var puzzle_open: bool = false
var puzzle_hotspot: Node2D = null
var puzzle: Dictionary = {}   # {spec, placed:{slot->piece}, mark:int, errors:int, solved:bool, message, message_key, message_serial, hint}

var _beats: Array[Dictionary] = []
var _check_queued: bool = false
var _loop_running: bool = false


func _ready() -> void:
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(_on_state_reset)


# --- State queries ----------------------------------------------------------

func is_busy() -> bool:
	return not current_beat.is_empty() or puzzle_open or _loop_running


func current_room_id() -> String:
	var r = RoomManager.current_room
	return r.room_id if r != null and is_instance_valid(r) else ""


func requires_met(req: Dictionary) -> bool:
	for f in req.get("flags", []):
		if not GameState.has_flag(String(f)):
			return false
	for it in req.get("items", []):
		var id := String(it)
		if StoryData.item_is_inventory(id):
			if not GameState.has_item(id):
				return false
		elif not GameState.has_flag("has_" + id):
			return false
	return true


func is_done(scene_id: String) -> bool:
	return GameState.has_flag("done_" + scene_id)


func can_start(scene_id: String) -> bool:
	var sc := StoryData.scene(scene_id)
	if sc.is_empty() or is_done(scene_id) or active_scene == scene_id:
		return false
	if _beats.any(func(b): return b.get("scene", "") == scene_id):
		return false
	return requires_met(sc.get("requires", {}))


func conditions_met(conds: Variant) -> bool:
	## `complete_when`: list of {all:[..]} / {any:[..]} / {any_n:n, flags:[..]}; a dict is one condition.
	var list: Array = conds if conds is Array else [conds]
	for c in list:
		if c.has("all"):
			for f in c["all"]:
				if not GameState.has_flag(String(f)):
					return false
		if c.has("any"):
			var ok := false
			for f in c["any"]:
				if GameState.has_flag(String(f)):
					ok = true
			if not ok:
				return false
		if c.has("any_n"):
			var n := 0
			for f in c.get("flags", []):
				if GameState.has_flag(String(f)):
					n += 1
			if n < int(c["any_n"]):
				return false
	return true


# --- Beats (dialogue / narration / options) ---------------------------------

## A narration beat (examine / action / closed exit text). `text_key` — the data/story/text key it came
## from (without "@"), so VoiceDirector can play the voice-over recorded for that key; "" for plain text.
func narrate(text: String, text_key: String = "") -> void:
	_push(_narration_beat(text, text_key))


## Narrates "@section.key" (resolved through StoryData.text, the key kept for the voice-over) or plain text.
func narrate_key(key_or_text: String) -> void:
	narrate(StoryData.text(key_or_text), text_key_of(key_or_text))


## "@H1.stove.look" -> "H1.stove.look"; plain text (no "@") -> "".
static func text_key_of(key_or_text: String) -> String:
	return key_or_text.substr(1) if key_or_text.begins_with("@") else ""


func _narration_beat(text: String, text_key: String = "") -> Dictionary:
	var b := {"type": "narration", "text": text}
	if text_key != "":
		b["text_key"] = text_key
	return b


func _push(beat: Dictionary) -> void:
	_beats.append(beat)
	if current_beat.is_empty():
		_next()


func _next() -> void:
	while not _beats.is_empty():
		var b: Dictionary = _beats.pop_front()
		if b.get("type") == "call":
			current_beat = {}
			var fn: Callable = b["fn"]
			fn.call()
			continue
		current_beat = b
		beat_changed.emit()
		return
	current_beat = {}
	beat_changed.emit()
	_queue_check()


## Click to continue (lines and narration). Options need `choose()`.
func advance() -> void:
	if current_beat.is_empty():
		return
	if current_beat.get("type") == "options":
		return
	_next()


func choose(option_id: String) -> bool:
	if current_beat.get("type") != "options":
		return false
	for o in current_beat.get("options", []):
		if String(o.get("id", "")) == option_id:
			var cb: Callable = current_beat.get("callback", Callable())
			current_beat = {}
			if cb.is_valid():
				cb.call(option_id)
			_next()
			return true
	return false


func current_options() -> Array:
	return current_beat.get("options", []) if current_beat.get("type") == "options" else []


# --- Scenes ------------------------------------------------------------------

func start_scene(scene_id: String) -> bool:
	if not can_start(scene_id):
		return false
	var sc := StoryData.scene(scene_id)
	GameState.set_flag("started_" + scene_id, true)
	scene_started.emit(scene_id)
	var beats: Array[Dictionary] = []
	var lines: Array = sc.get("mandatory_lines", [])
	for i in lines.size():
		var line: Dictionary = lines[i]
		if line.has("context"):
			beats.append({"type": "options", "scene": scene_id, "prompt": "",
				"options": [{"id": "ask", "label": String(line["context"])}], "callback": Callable()})
		# line_id <scene>_<index>: the stable id of the recorded voice (VoiceDirector, assets/voice/ru).
		beats.append({"type": "line", "scene": scene_id, "line_id": "%s_%d" % [scene_id, i], "speaker": String(line.get("speaker", "")),
			"speaker_name": StoryData.character_name(String(line.get("speaker", ""))), "text": String(line.get("text", ""))})
	beats.append({"type": "call", "scene": scene_id, "fn": _complete_scene.bind(scene_id)})
	if active_scene == "":
		active_scene = scene_id
	for b in beats:
		_beats.append(b)
	if current_beat.is_empty():
		_next()
	return true


func _complete_scene(scene_id: String) -> void:
	var sc := StoryData.scene(scene_id)
	var grants: Dictionary = sc.get("grants", {})
	for it in grants.get("items", []):
		grant_item(String(it))
	for f in grants.get("flags", []):
		GameState.set_flag(String(f), true)
	for it in sc.get("consumes", []):
		GameState.remove_item(String(it))
	GameState.set_flag("done_" + scene_id, true)
	# Цель журнала для игрока — поле goal (без кодов комнат/эпизодов); result — заметка сценария, запасной вариант.
	if String(sc.get("type", "")) == "main" and (sc.has("goal") or sc.has("result")):
		GameState.set_goal(String(sc.get("goal", sc.get("result", ""))), scene_id)
	var room_spec: Dictionary = StoryData.room(current_room_id()).get("scenes", {}).get(scene_id, {})
	if room_spec.has("complete_text"):
		var ck := String(room_spec["complete_text"])
		_beats.push_front(_narration_beat(StoryData.text(ck), text_key_of(ck)))
	if active_scene == scene_id:
		active_scene = ""
	scene_completed.emit(scene_id)
	RoomManager.autosave()


func grant_item(item_id: String) -> void:
	var added := false
	if StoryData.item_is_inventory(item_id):
		added = GameState.add_item(item_id)
	GameState.set_flag("has_" + item_id, true)
	if added:
		item_received.emit(item_id)
		GameState.show_hint(StoryData.text("@ui.got_item", {"item": StoryData.item_name(item_id)}))


## Called by RoomManager after the player is placed in a room.
func on_room_entered(room_id: String) -> void:
	select_item("")
	# Places the player has been to (the plan shows unvisited ones paler, hides some until a visit).
	if room_id != "" and not GameState.has_flag("visited_" + room_id):
		GameState.set_flag("visited_" + room_id, true)
	check_room_triggers()


func _on_flag_changed(_flag: String, _value: bool) -> void:
	_queue_check()


func _on_state_reset() -> void:
	_beats.clear()
	current_beat = {}
	active_scene = ""
	selected_item = ""
	puzzle_open = false
	puzzle = {}
	beat_changed.emit()


func _queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	check_room_triggers.call_deferred()


## Starts every scene of the current room whose requires + room condition hold.
func check_room_triggers() -> void:
	_check_queued = false
	var rid := current_room_id()
	if rid == "":
		return
	var spec: Dictionary = StoryData.room(rid)
	for id in StoryData.scenes_in(rid):
		if not can_start(id):
			continue
		var sspec: Dictionary = spec.get("scenes", {}).get(id, {})
		if sspec.is_empty() and not StoryData.scene_trigger_rooms(id).is_empty():
			continue  # declared in another of its rooms: never auto here
		var trig := String(sspec.get("trigger", ""))
		if trig.begins_with("talk:") or trig.begins_with("puzzle:"):
			continue
		if sspec.has("complete_when"):
			if not conditions_met(sspec["complete_when"]):
				continue
		elif trig != "" and trig != "enter":
			continue
		start_scene(id)


# --- Items -------------------------------------------------------------------

func select_item(item_id: String) -> void:
	if item_id != "" and not GameState.has_item(item_id):
		item_id = ""
	if selected_item == item_id:
		item_id = ""
	selected_item = item_id
	item_selection_changed.emit(selected_item)
	if selected_item != "":
		GameState.show_hint(StoryData.text("@ui.item_selected", {"item": StoryData.item_name(selected_item)}))


# --- Hotspot interaction -----------------------------------------------------

func _use_state(d: Dictionary) -> String:
	## "ready" | "done" | "locked" | "none"
	if not d.has("use"):
		return "none"
	var u: Dictionary = d["use"]
	var once := String(u.get("once_flag", ""))
	if once != "" and GameState.has_flag(once):
		return "done"
	if not requires_met(u.get("requires", {})):
		return "locked"
	return "ready"


## What a click on `h` would do right now, without doing it (mirrors interact()):
## "item_use" | "item_none" | "panel" | "talk" | "talk_text" | "puzzle" | "choice" | "use" | "text" | "busy".
## The player plays a hotspot's action animation (data action_anim) only for "use", "item_use" and
## "choice" — the interactions that change something; a look or a repeated click just shows text.
func planned_interaction(h: StoryHotspot) -> String:
	if is_busy():
		return "busy"
	var d := h.data
	if selected_item != "":
		return "item_use" if d.get("item_use", {}).has(selected_item) else "item_none"
	if d.has("panel"):
		return "panel"
	if d.has("talk"):
		var t: Dictionary = d["talk"]
		var scn := String(t.get("scene", ""))
		if scn != "" and can_start(scn):
			return "talk"
		if (scn != "" and not is_done(scn) and t.has("before_text")) or t.has("after_text"):
			return "talk_text"
	if d.has("puzzle"):
		var pz: Dictionary = d["puzzle"]
		var success_scene := String(pz.get("success", {}).get("scene", ""))
		if requires_met(pz.get("requires", {})) and (success_scene == "" or not is_done(success_scene)):
			return "puzzle"
		if _use_state(d) != "ready":
			return "text"
	if d.has("choice"):
		var ch: Dictionary = d["choice"]
		if requires_met(ch.get("requires", {})):
			var already := false
			if bool(ch.get("once_any", false)):
				for o in ch.get("options", []):
					if GameState.has_flag(String(o.get("sets", ""))):
						already = true
			if not already:
				return "choice"
		elif ch.has("fail_text"):
			return "text"
	return "use" if _use_state(d) == "ready" else "text"


func interact(h: StoryHotspot) -> void:
	if is_busy():
		return
	var d := h.data
	var look := String(d.get("look", "@ui.nothing_here"))

	if selected_item != "":
		var item := selected_item
		select_item("")
		var iu: Dictionary = d.get("item_use", {})
		if iu.has(item):
			_run_action(h, iu[item], item)
		else:
			narrate_key("@ui.item_no_effect")
		return

	if d.has("panel"):
		var pn: Dictionary = d["panel"]
		for f in pn.get("sets", []):
			GameState.set_flag(String(f), true)
		panel_requested.emit(String(pn.get("id", "")), h)
		return

	if d.has("talk"):
		var t: Dictionary = d["talk"]
		var scn := String(t.get("scene", ""))
		if scn != "":
			if can_start(scn):
				start_scene(scn)
				return
			if not is_done(scn) and t.has("before_text"):
				narrate_key(String(t["before_text"]))
				return
		if t.has("after_text"):
			narrate_key(String(t["after_text"]))
			return

	if d.has("puzzle"):
		var pz: Dictionary = d["puzzle"]
		var success_scene := String(pz.get("success", {}).get("scene", ""))
		if requires_met(pz.get("requires", {})) and (success_scene == "" or not is_done(success_scene)):
			open_puzzle(h)
			return
		if _use_state(d) != "ready":
			narrate_key(String(pz.get("fail_text", d.get("look", "@ui.nothing_here"))))
			return

	if d.has("choice"):
		var ch: Dictionary = d["choice"]
		if requires_met(ch.get("requires", {})):
			var already := false
			if bool(ch.get("once_any", false)):
				for o in ch.get("options", []):
					if GameState.has_flag(String(o.get("sets", ""))):
						already = true
			if not already:
				_offer_choice(h, ch)
				return
		elif ch.has("fail_text"):
			narrate_key(String(ch["fail_text"]))
			return

	match _use_state(d):
		"ready":
			_run_action(h, d["use"], "")
			return
		"locked":
			if d["use"].has("fail_text"):
				narrate_key(String(d["use"]["fail_text"]))
				return
	narrate_key(look)


func _offer_choice(h: StoryHotspot, ch: Dictionary) -> void:
	var opts: Array = []
	for o in ch.get("options", []):
		opts.append({"id": String(o["id"]), "label": StoryData.text(String(o.get("label", o["id"]))), "sets": String(o.get("sets", ""))})
	var pk := String(ch.get("prompt", ""))
	_push({"type": "options", "prompt": StoryData.text(pk), "prompt_key": text_key_of(pk), "options": opts,
		"callback": _apply_choice.bind(h, ch)})


func _apply_choice(option_id: String, _h: StoryHotspot, ch: Dictionary) -> void:
	var chosen: Dictionary = {}
	for o in ch.get("options", []):
		if String(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return
	if bool(ch.get("exclusive", false)):
		for o in ch.get("options", []):
			var f := String(o.get("sets", ""))
			if f != "" and f != String(chosen.get("sets", "")) and GameState.has_flag(f):
				GameState.set_flag(f, false)
	if chosen.has("sets"):
		GameState.set_flag(String(chosen["sets"]), true)
	if chosen.has("text"):
		var tk := String(chosen["text"])
		_beats.push_front(_narration_beat(StoryData.text(tk), text_key_of(tk)))


func _run_action(h: StoryHotspot, act: Dictionary, item_id: String) -> void:
	if bool(act.get("puzzle", false)):
		if h.data.has("puzzle") and requires_met(h.data["puzzle"].get("requires", {})):
			open_puzzle(h)
		else:
			narrate_key(String(h.data.get("puzzle", {}).get("fail_text", "@ui.item_no_effect")))
		return
	if not requires_met(act.get("requires", {})):
		narrate_key(String(act.get("fail_text", h.data.get("look", "@ui.nothing_here"))))
		return
	var once := String(act.get("once_flag", ""))
	if once != "" and GameState.has_flag(once):
		narrate_key(String(act.get("text_done", h.data.get("look", "@ui.nothing_here"))))
		return
	for f in act.get("sets", []):
		GameState.set_flag(String(f), true)
	for it in act.get("gives", []):
		grant_item(String(it))
	if item_id != "" and bool(act.get("consumes", false)):
		GameState.remove_item(item_id)
	if act.has("text"):
		narrate_key(String(act["text"]))


# --- Exits -------------------------------------------------------------------

func use_exit(e: StoryExit) -> void:
	if is_busy():
		return
	if not e.is_open():
		var oc: Dictionary = e.data.get("on_closed", {})
		if String(oc.get("type", "")) == "loop":
			_run_loop(e, oc)
			return
		narrate_key(String(e.data.get("closed_text", "@ui.closed_generic")))
		return
	if not e.target_exists():
		narrate_key(String(e.data.get("unbuilt_text", "@ui.not_built")))
		return
	RoomManager.call_deferred("change_room", e.target_room, e.target_spawn)


## Closed exit that loops back (O2 gate): fade, place the player at `spawn`, set flags, react.
func _run_loop(e: StoryExit, oc: Dictionary) -> void:
	_loop_running = true
	loop_transition.emit(oc)
	await get_tree().create_timer(LOOP_FADE_SECONDS).timeout
	var room := RoomManager.current_room
	if room != null and RoomManager.player != null:
		var spawn := room.get_spawn(String(oc.get("spawn", "default")))
		var pos: Vector2 = spawn.global_position if spawn != null else RoomManager.player.global_position
		RoomManager.player.call("enter_room", room, pos)
		GameState.player_pos = pos
	for f in oc.get("sets", []):
		GameState.set_flag(String(f), true)
	_loop_running = false
	var text_key := String(e.data.get("closed_text", "@ui.closed_generic"))
	narrate_key(text_key)


# --- Puzzle (match_marks) -----------------------------------------------------

func open_puzzle(h: StoryHotspot) -> void:
	var spec: Dictionary = h.data.get("puzzle", {})
	puzzle_hotspot = h
	puzzle = {"spec": spec, "placed": {}, "mark": -1, "solved": false,
		"errors": GameState.get_counter("puzzle_errors." + String(spec.get("id", "puzzle"))),
		"message": "", "message_key": "", "message_serial": 0, "hint": "", "view": ""}
	_set_puzzle_message(String(spec.get("intro", "")))
	puzzle_open = true
	puzzle_opened.emit()
	puzzle_state_changed.emit()


## The close-up's message (intro / error / success): text, its data key (VoiceDirector plays the voice-over)
## and a serial that grows with every new message — the same error twice is two messages.
func _set_puzzle_message(key_or_text: String) -> void:
	puzzle["message"] = StoryData.text(key_or_text)
	puzzle["message_key"] = text_key_of(key_or_text)
	puzzle["message_serial"] = int(puzzle.get("message_serial", 0)) + 1


func puzzle_place(piece_id: String, slot_id: String) -> void:
	if not puzzle_open or bool(puzzle.get("solved", false)):
		return
	var placed: Dictionary = puzzle["placed"]
	for s in placed.keys():
		if placed[s] == piece_id:
			placed.erase(s)
			break
	if slot_id != "":
		placed[slot_id] = piece_id
	puzzle_state_changed.emit()


func puzzle_set_mark(index: int) -> void:
	if not puzzle_open or bool(puzzle.get("solved", false)):
		return
	puzzle["mark"] = index
	puzzle_state_changed.emit()


func puzzle_piece_slot(piece_id: String) -> String:
	for s in puzzle.get("placed", {}).keys():
		if puzzle["placed"][s] == piece_id:
			return String(s)
	return ""


func puzzle_is_correct() -> bool:
	var spec: Dictionary = puzzle.get("spec", {})
	var placed: Dictionary = puzzle.get("placed", {})
	var pieces: Array = spec.get("pieces", [])
	if placed.size() != pieces.size():
		return false
	for s in spec.get("slots", []):
		var sid := String(s["id"])
		var correct := bool(s.get("correct", false))
		if correct != placed.has(sid):
			return false
	return int(puzzle.get("mark", -1)) == int(spec.get("marks", {}).get("correct", -1))


## "Close the door": evaluates the placement. Returns true on success.
func puzzle_check() -> bool:
	if not puzzle_open or bool(puzzle.get("solved", false)):
		return false
	var spec: Dictionary = puzzle["spec"]
	var pid := String(spec.get("id", "puzzle"))
	if puzzle_is_correct():
		puzzle["solved"] = true
		_set_puzzle_message(String(spec.get("success_text", "")))
		puzzle["view"] = String(spec.get("success", {}).get("view", ""))
		puzzle_state_changed.emit()
		var scn := String(spec.get("success", {}).get("scene", ""))
		if scn != "":
			start_scene(scn)
		return true
	var errors := GameState.inc_counter("puzzle_errors." + pid)
	puzzle["errors"] = errors
	_set_puzzle_message(String(spec.get("error_text", "")))
	puzzle["view"] = "wall"
	if errors >= int(spec.get("error_hint_after", 2)):
		var scn := String(spec.get("success", {}).get("scene", ""))
		var hints := StoryData.scene_hints(scn) if scn != "" else []
		if not hints.is_empty():
			puzzle["hint"] = hints[0]
	puzzle_state_changed.emit()
	return false


func close_puzzle() -> void:
	if not puzzle_open:
		return
	puzzle_open = false
	puzzle_hotspot = null
	puzzle_closed.emit()
	if current_beat.is_empty():
		_next()


# --- Hints and journal --------------------------------------------------------

## The scene the hints refer to: first undone main scene whose requires hold; else first undone main.
func hint_scene() -> String:
	var fallback := ""
	for id in StoryData.scene_order:
		var sc := StoryData.scene(id)
		if String(sc.get("type", "")) != "main" or is_done(id):
			continue
		if fallback == "":
			fallback = id
		if requires_met(sc.get("requires", {})):
			return id
	return fallback


## Reveals the next tier (1..3) for the current hint scene; tiers persist in GameState.counters.
func next_hint() -> Dictionary:
	var scn := hint_scene()
	var hints: Array[String] = StoryData.scene_hints(scn) if scn != "" else []
	if hints.is_empty():
		hints = [StoryData.text("@ui.hint_generic_1"), StoryData.text("@ui.hint_generic_2"), StoryData.text("@ui.hint_generic_3")]
	var key := "hint_tier." + scn
	var tier: int = mini(GameState.get_counter(key) + 1, 3)
	GameState.set_counter(key, tier)
	var text := hints[mini(tier, hints.size()) - 1]
	hint_revealed.emit(tier, text)
	return {"scene": scn, "tier": tier, "text": text}


func journal_goal() -> String:
	if GameState.journal_goal != "":
		return GameState.journal_goal
	return StoryData.text("@ui.goal_start")


## Known facts: descriptions (flags.json) of every set flag that has one, in the order they were set.
func journal_facts() -> Array[String]:
	var out: Array[String] = []
	for f in GameState.flags.keys():
		if not GameState.flags[f]:
			continue
		var d := StoryData.flag_description(String(f))
		if d != "":
			out.append(d)
	return out
