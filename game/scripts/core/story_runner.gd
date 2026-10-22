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
## A hotspot with `view: {...}` (rooms data, e.g. the H3 mirror) shows a look-only close-up while its
## usual use/look text plays over it (CloseupView); the close-up holds the input until it is closed.
signal view_opened(spec: Dictionary)
signal view_closed()
## Scene staging (scenes data `stage`: a fade with sounds between lines — the boat shown at R1, the night by the
## stove): the screen overlay goes to `alpha` (1 — black, `dim` — dusk under the lines, 0 — clear) in `seconds`.
signal stage_fade(alpha: float, seconds: float)
## A sound of sfx.json `sounds` for a staging (SfxDirector plays it).
signal stage_sound_requested(sound_id: String)
## A scene's `checkpoint` save was written (slot, title) — «День второй» after the night by the stove.
signal checkpoint_saved(slot: String, title: String)
## A hotspot with `mechanic: {type, requires, events, ...}` (rooms data) opens an interactive close-up
## (MechanicView: the office mirror with the bell, the sluice, mother's mirror, the plate, the signal
## lantern). The close-up reports what the player did as named events; their effects are data
## (`events.<name>`: sets, text, close) and are applied here — the panels never decide story state.
signal mechanic_opened(spec: Dictionary)
signal mechanic_closed()
## A scene staging shows a frame (scenes data `stage[].frame`: a room file of data/story/rooms drawn over the
## world by FrameView — the council at the mill, the epilogue shots) or clears it ("" — back to the room).
## Emitted while the screen is black. `hold` — the frame stays after the scene (the last shot of the game).
signal frame_changed(frame_id: String, hold: bool)

const LOOP_FADE_SECONDS: float = 0.35

var selected_item: String = ""
var current_beat: Dictionary = {}
var active_scene: String = ""
var puzzle_open: bool = false
var puzzle_hotspot: Node2D = null
var puzzle: Dictionary = {}   # {spec, placed:{slot->piece}, mark:int, errors:int, solved:bool, message, message_key, message_serial, hint}
var view_open: bool = false
var view: Dictionary = {}     # the open look-only close-up: the hotspot's `view` spec + "hotspot" id
var mechanic_open: bool = false
var mechanic: Dictionary = {}  # the open interactive close-up: the hotspot's `mechanic` spec + "hotspot" id

var stage_dim: float = 0.0   # the overlay level a staging left on screen (dusk at night), 0 — none
var current_frame: String = ""   # the frame a staging put over the world (FrameView), "" — none
var frame_hold: bool = false     # the frame stays after its scene (the end of the game)

var _beats: Array[Dictionary] = []
## A close-up opened by a scene (scenes data `mechanics` [{at, spec, until}] — the windlass of the first span):
## the scene waits for it; closed with `until` set — the scene goes on, closed without — the scene stops (not
## done) and does not start again by itself until the player enters a room again.
var _mechanic_wait: Dictionary = {}
var _held_back: Dictionary = {}   # scene id → true: stopped this room visit, no auto restart
var _check_queued: bool = false
var _loop_running: bool = false
var _stage_running: bool = false
var _stage_serial: int = 0   # grows on reset/load: a staging in flight stops at its next await


func _ready() -> void:
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(_on_state_reset)
	GameState.state_loaded.connect(_on_state_loaded)


# --- State queries ----------------------------------------------------------

func is_busy() -> bool:
	return not current_beat.is_empty() or puzzle_open or view_open or mechanic_open or _loop_running or _stage_running


## A scene staging (fade, room change, sounds) is playing — no beat on screen, input held.
func is_staging() -> bool:
	return _stage_running


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
	if sc.is_empty() or is_done(scene_id) or active_scene == scene_id or _held_back.has(scene_id):
		return false
	# A reserve story (quests.json `reserve`: kept for later, not in the build) never starts by itself.
	if bool(sc.get("reserve", false)):
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
## A key whose entry carries `line` {speaker, text} is the words of a character next to Agata: it plays as
## that character's line (name shown, their voice — line_id "<speaker>:<key>"), not as narration.
func narrate_key(key_or_text: String) -> void:
	_push(_text_beat(key_or_text))


func _text_beat(key_or_text: String) -> Dictionary:
	var ln := StoryData.text_line(key_or_text)
	if not ln.is_empty():
		var sp := String(ln["speaker"])
		var key := text_key_of(key_or_text)
		return {"type": "line", "line_id": "%s:%s" % [sp, key], "speaker": sp,
			"speaker_name": StoryData.character_name(sp), "text": String(ln["text"]), "text_key": key}
	return _narration_beat(StoryData.text(key_or_text), text_key_of(key_or_text))


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
	if _stage_running:
		return  # the staging resumes the queue when it is over (a room change mid-staging must not skip lines)
	while not _beats.is_empty():
		var b: Dictionary = _beats.pop_front()
		# A line or staging shown only under some flags (scenes data `if` / `unless` / `switch` on a line or a
		# stage — the answer on the board for what Agata wrote, Pavel's word in the epilogue): decided when its
		# turn comes, so a choice made earlier in the same scene counts.
		if not beat_allowed(b):
			continue
		if b.get("type") == "mechanic":
			current_beat = {}
			if GameState.has_flag(String(b.get("until", ""))):
				continue   # already done (a load after it): the scene goes on
			# The rest of the scene waits aside: texts the close-up asks for play in between, in their order.
			_mechanic_wait = b.duplicate()
			_mechanic_wait["rest"] = _beats.duplicate()
			_beats.clear()
			beat_changed.emit()
			open_mechanic(b.get("spec", {}), "")
			return
		if b.get("type") == "call":
			current_beat = {}
			var fn: Callable = b["fn"]
			fn.call()
			continue
		if b.get("type") == "stage":
			current_beat = {}
			beat_changed.emit()
			_run_stage(b.get("spec", {}))
			return
		current_beat = b
		beat_changed.emit()
		return
	current_beat = {}
	beat_changed.emit()
	_queue_check()


## A beat's own conditions (copied from its line / stage in data): every `if` flag set, no `unless` flag set,
## at least one `if_any` flag set (the date on the board after any of Agata's inscriptions), and the Director's switch (`switch` "name" or "name=value", data/story/meta.json → switches) on.
func beat_allowed(b: Dictionary) -> bool:
	for f in b.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in b.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	if b.has("if_any"):
		var any_set := false
		for f in b["if_any"]:
			if GameState.has_flag(String(f)):
				any_set = true
		if not any_set:
			return false
	var sw := String(b.get("switch", ""))
	if sw != "" and not StoryData.switch_on(sw):
		return false
	return true


static func _conditions_of(src: Dictionary) -> Dictionary:
	var out := {}
	for k in ["if", "unless", "if_any", "switch"]:
		if src.has(k):
			out[k] = src[k]
	return out


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
	var stages: Array = sc.get("stage", [])
	var mechs: Array = sc.get("mechanics", [])
	for i in lines.size():
		var line: Dictionary = lines[i]
		# A scene's close-up comes before the stagings at the same line (the windlass, then the shot of the laid log).
		for mc in mechs:
			if int(mc.get("at", -1)) == i:
				beats.append({"type": "mechanic", "scene": scene_id, "spec": mc.get("spec", {}), "until": String(mc.get("until", ""))})
		for st in stages:
			if typeof(st.get("at")) != TYPE_STRING and int(st.get("at", -1)) == i:
				beats.append(_stage_beat(scene_id, st))
		var cond := _conditions_of(line)
		if line.has("context"):
			beats.append({"type": "options", "scene": scene_id, "prompt": "",
				"options": [{"id": "ask", "label": String(line["context"])}], "callback": Callable()})
		# A choice inside the conversation (M13: what Agata answers Pavel): `options` [{id, label, sets, text}] —
		# the chosen flag is set and the speaker says the chosen words (line_id <scene>_<index>_<option>).
		if line.has("options"):
			var opts: Array = []
			for o in line["options"]:
				opts.append({"id": String(o["id"]), "label": StoryData.text(String(o.get("label", o.get("text", o["id"])))), "sets": String(o.get("sets", ""))})
			var ob := {"type": "options", "scene": scene_id, "prompt": StoryData.text(String(line.get("prompt", ""))),
				"options": opts, "callback": _apply_line_option.bind(scene_id, i, line)}
			ob.merge(cond)
			beats.append(ob)
			continue
		var sp := String(line.get("speaker", ""))
		# line_id <scene>_<index>: the stable id of the recorded voice (VoiceDirector, assets/voice/ru).
		var lb: Dictionary
		if sp == "narrator":
			# What nobody says (the empty boat goes into the fog): a narration beat inside the scene.
			lb = {"type": "narration", "scene": scene_id, "line_id": "%s_%d" % [scene_id, i], "text": String(line.get("text", ""))}
		else:
			lb = {"type": "line", "scene": scene_id, "line_id": "%s_%d" % [scene_id, i], "speaker": sp,
				"speaker_name": StoryData.character_name(sp), "text": String(line.get("text", ""))}
		lb.merge(cond)
		beats.append(lb)
	for st in stages:
		if str(st.get("at", "")) == "end":
			beats.append(_stage_beat(scene_id, st))
	beats.append({"type": "call", "scene": scene_id, "fn": _complete_scene.bind(scene_id)})
	if active_scene == "":
		active_scene = scene_id
	for b in beats:
		_beats.append(b)
	if current_beat.is_empty():
		_next()
	return true


func _stage_beat(scene_id: String, st: Dictionary) -> Dictionary:
	var b := {"type": "stage", "scene": scene_id, "spec": st}
	b.merge(_conditions_of(st))
	return b


func _apply_line_option(option_id: String, scene_id: String, index: int, line: Dictionary) -> void:
	for o in line.get("options", []):
		if String(o.get("id", "")) != option_id:
			continue
		var f := String(o.get("sets", ""))
		if f != "":
			GameState.set_flag(f, true)
		var sp := String(line.get("speaker", "agata"))
		var t := String(o.get("text", ""))
		if t != "":
			_beats.push_front({"type": "line", "scene": scene_id, "line_id": "%s_%d_%s" % [scene_id, index, option_id], "speaker": sp,
				"speaker_name": StoryData.character_name(sp), "text": t})
		return


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
		_beats.push_front(_text_beat(String(room_spec["complete_text"])))
	if active_scene == scene_id:
		active_scene = ""
	if stage_dim > 0.0:   # a scene never leaves its dusk behind
		stage_dim = 0.0
		stage_fade.emit(0.0, 0.5)
	# … nor its frame, unless it is the last shot (scenes data `hold_frame`: the end of the game).
	if current_frame != "" and not frame_hold:
		set_frame("")
	scene_completed.emit(scene_id)
	RoomManager.autosave()
	# A scene's checkpoint (scenes data `checkpoint` {slot, title}): its own save slot with a title for the menu,
	# written after the scene's flags — loading it never replays the scene (N01 → «День второй»).
	var cp: Dictionary = sc.get("checkpoint", {})
	if not cp.is_empty() and String(cp.get("slot", "")) != "":
		var title := StoryData.text(String(cp.get("title", "")))
		var slot: String = RoomManager.checkpoint_prefix + String(cp["slot"])
		if RoomManager.save_game(slot, title):
			GameState.show_hint(StoryData.text("@ui.saved", {"slot": title}))
			checkpoint_saved.emit(slot, title)


# --- Staging (scenes data `stage`) ---------------------------------------------

## One staging: fade to black (`fade_out_s`), sounds at `at_s` from its start, an optional room change while
## black (`room`, `spawn`; no autosave and no door sound in between — an interrupted scene restarts where it
## began), `hold_s`, then back to `dim` (dusk under the next lines) in `fade_in_s`. The beat queue waits.
func _run_stage(spec: Dictionary) -> void:
	_stage_running = true
	var serial := _stage_serial
	var tree := get_tree()
	var fade_out := float(spec.get("fade_out_s", 0.6))
	stage_fade.emit(1.0, fade_out)
	for snd in spec.get("sounds", []):
		var sid := String(snd.get("id", ""))
		var at := float(snd.get("at_s", 0.0))
		tree.create_timer(at).timeout.connect(func():
			if serial == _stage_serial:
				stage_sound_requested.emit(sid))
	await tree.create_timer(fade_out).timeout
	if serial != _stage_serial:
		return
	if spec.has("room"):
		var keep_autosave: bool = RoomManager.autosave_enabled
		RoomManager.autosave_enabled = false
		if SfxDirector.has_method("suppress_next_door"):
			SfxDirector.suppress_next_door()
		RoomManager.change_room(String(spec["room"]), String(spec.get("spawn", "default")))
		RoomManager.autosave_enabled = keep_autosave
	# A frame over the world while black (`frame` — a room file drawn by FrameView; "" — back to the room;
	# `hold` — it stays after the scene: the last shot of the game).
	if spec.has("frame"):
		set_frame(String(spec["frame"]), bool(spec.get("hold", false)))
	# Flags that change the room while black (`sets` — the night in Olkhovka turns to morning): saved state, so a load
	# shows the same; the scene's own grants still come at its end.
	for f in spec.get("sets", []):
		GameState.set_flag(String(f), true)
	await tree.create_timer(float(spec.get("hold_s", 1.0))).timeout
	if serial != _stage_serial:
		return
	stage_dim = clampf(float(spec.get("dim", 0.0)), 0.0, 0.95)
	var fade_in := float(spec.get("fade_in_s", 0.6))
	stage_fade.emit(stage_dim, fade_in)
	await tree.create_timer(fade_in).timeout
	if serial != _stage_serial:
		return
	_stage_running = false
	_next()


## Puts a frame over the world (FrameView builds it) or clears it ("").
func set_frame(frame_id: String, hold: bool = false) -> void:
	if frame_id == current_frame and hold == frame_hold:
		return
	current_frame = frame_id
	frame_hold = hold and frame_id != ""
	frame_changed.emit(current_frame, frame_hold)


func _cancel_stage() -> void:
	_stage_serial += 1
	var had := _stage_running or stage_dim > 0.0
	_stage_running = false
	stage_dim = 0.0
	if had:
		stage_fade.emit(0.0, 0.0)


func grant_item(item_id: String) -> void:
	# An item is given once: has_<item> marks it as given and stays after the item is used up, so a scene's
	# grants never put a spent item back (M08 grants the chalk its desk already gave — after the board the
	# chalk stays there, not in the bag).
	if GameState.has_flag("has_" + item_id):
		return
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
	_held_back.clear()   # a scene stopped by closing its close-up may start again in the next room visit
	# Places the player has been to (the plan shows unvisited ones paler, hides some until a visit).
	if room_id != "" and not GameState.has_flag("visited_" + room_id):
		GameState.set_flag("visited_" + room_id, true)
	_run_on_enter(room_id)
	check_room_triggers()


## Rooms data `on_enter` [{text, once_flag, if?, unless?}]: a line on the first entry (O1: «Там зима. А у нас ещё
## октябрь»; H2 with the office mirror in the bag: where the stand is). The flag is part of the save, so a load
## never repeats it.
func _run_on_enter(room_id: String) -> void:
	for oe in StoryData.room(room_id).get("on_enter", []):
		var once := String(oe.get("once_flag", ""))
		if once != "" and GameState.has_flag(once):
			continue
		if not requires_met({"flags": oe.get("if", [])}):
			continue
		if (oe.get("unless", []) as Array).any(func(f): return GameState.has_flag(String(f))):
			continue
		if once != "":
			GameState.set_flag(once, true)
		narrate_key(String(oe.get("text", "")))


## What Agata says when an item is used on the wrong thing: items.json `wrong_target` {text, rooms?} — where the
## item goes (Director 23:53: «как поставить зеркало на стойку тети?»); the generic refusal only for items
## without it or outside its `rooms`. tools/validate_rooms.py requires it for every item that moves the story.
func item_refusal(item_id: String) -> String:
	var wt: Dictionary = StoryData.item(item_id).get("wrong_target", {})
	var rooms: Array = wt.get("rooms", [])
	if wt.has("text") and (rooms.is_empty() or rooms.has(current_room_id())):
		return String(wt["text"])
	return "@ui.item_no_effect"


func _on_flag_changed(_flag: String, _value: bool) -> void:
	_queue_check()


func _on_state_reset() -> void:
	_cancel_stage()
	_mechanic_wait = {}
	_held_back.clear()
	set_frame("")
	_beats.clear()
	current_beat = {}
	active_scene = ""
	selected_item = ""
	var had_puzzle := puzzle_open
	var had_view := view_open
	puzzle_open = false
	puzzle = {}
	view_open = false
	view = {}
	if had_puzzle:
		puzzle_closed.emit()
	if had_view:
		view_closed.emit()
	close_mechanic()
	beat_changed.emit()


## A loaded save rebuilds the room: a close-up left open would act on the previous room. Its progress
## (hinges in sockets, the threshold) is not part of a save — the required item stays in the bag
## until the scene that consumes it completes, so nothing is lost or given twice.
func _on_state_loaded(_slot: String) -> void:
	# A staging in flight belongs to the state that was just replaced: stop it and drop its scene's beats.
	if _stage_running or stage_dim > 0.0 or not _mechanic_wait.is_empty() or current_frame != "":
		_cancel_stage()
		_beats.clear()
		current_beat = {}
		active_scene = ""
		beat_changed.emit()
	_mechanic_wait = {}
	_held_back.clear()
	close_view()
	close_mechanic()
	# A frame belongs to the scene that showed it — except the last shot of a finished game (scenes data
	# `end_frame`): loading the save made after the end shows it again instead of an empty room.
	set_frame(end_frame_now(), true)
	if puzzle_open:
		puzzle_open = false
		puzzle_hotspot = null
		puzzle = {}
		puzzle_closed.emit()


## The last shot of a finished game: `end_frame` of a done scene (a frame id, or [{switch?, if?, frame}] — the
## first allowed), "" while the game is not over.
func end_frame_now() -> String:
	for id in StoryData.scene_order:
		var sc: Dictionary = StoryData.scene(id)
		if not sc.has("end_frame") or not is_done(id):
			continue
		var ef = sc["end_frame"]
		if ef is String:
			return String(ef)
		for e in ef:
			if beat_allowed(e):
				return String(e.get("frame", ""))
	return ""


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
		var scn := talk_scene(t)
		if scn != "" and can_start(scn):
			return "talk"
		if (scn != "" and not is_done(scn) and t.has("before_text")) or t.has("after_text") or t.has("by_flags"):
			return "talk_text"
	if d.has("mechanic") and requires_met(mechanic_spec(h).get("requires", {})):
		return "mechanic"
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
			narrate_key(item_refusal(item))
		return

	if d.has("panel"):
		var pn: Dictionary = d["panel"]
		for f in pn.get("sets", []):
			GameState.set_flag(String(f), true)
		panel_requested.emit(String(pn.get("id", "")), h)
		return

	if d.has("talk"):
		var t: Dictionary = d["talk"]
		var scn := talk_scene(t)
		if scn != "":
			if can_start(scn):
				start_scene(scn)
				return
			if not is_done(scn) and t.has("before_text"):
				narrate_key(_talk_before_text(t, scn))
				return
		# What the person says depends on how far things went (Pelageya at the turn: before the brace,
		# with the rope): `by_flags` [{if: [flags], text}] — the first entry whose flags all hold.
		for e in t.get("by_flags", []):
			if requires_met({"flags": e.get("if", [])}):
				narrate_key(String(e.get("text", "")))
				return
		if t.has("after_text"):
			narrate_key(String(t["after_text"]))
			return

	if d.has("mechanic"):
		var ms := mechanic_spec(h)
		if requires_met(ms.get("requires", {})):
			open_mechanic(ms, h.hotspot_id)
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

	# Look-only close-up (data `view`): opens first, the use/look text below plays over it. `if` / `unless`
	# flags gate it (O1 drawer: only while the three things are still in it).
	if d.has("view") and view_allowed(d["view"]):
		open_view(d["view"], h.hotspot_id)

	match _use_state(d):
		"ready":
			_run_action(h, d["use"], "")
			return
		"locked":
			if d["use"].has("fail_text"):
				narrate_key(String(d["use"]["fail_text"]))
				return
		"done":
			if d["use"].has("text_done"):
				narrate_key(String(d["use"]["text_done"]))
				return
	narrate_key(look)


## The scene a conversation leads to: `talk.scene`, or the first of `talk.scenes` not done yet (Pavel: first
## the story of the office, then the agreement once Agata has looked round the passage). "" when all done.
func talk_scene(t: Dictionary) -> String:
	if t.has("scenes"):
		for sc in t["scenes"]:
			if not is_done(String(sc)):
				return String(sc)
		return ""
	return String(t.get("scene", ""))


## `before_text` may be a map scene → text (what the person says while the next talk is not ready yet).
func _talk_before_text(t: Dictionary, scn: String) -> String:
	var bt = t.get("before_text", "")
	if bt is Dictionary:
		return String(bt.get(scn, bt.get("default", "@ui.nothing_here")))
	return String(bt)


func view_allowed(v: Dictionary) -> bool:
	for f in v.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in v.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


## Options whose `requires` do not hold are left out («Илюша, я нашла твой рисунок» before the drawing is
## found). `item_id` — the item in hand that opened the choice (chalk on the board): an option with
## `consumes_item` uses it up, the others leave it in the bag.
func _offer_choice(h: StoryHotspot, ch: Dictionary, item_id: String = "") -> void:
	var opts: Array = []
	for o in ch.get("options", []):
		if not requires_met(o.get("requires", {})):
			continue
		opts.append({"id": String(o["id"]), "label": StoryData.text(String(o.get("label", o["id"]))), "sets": String(o.get("sets", ""))})
	var pk := String(ch.get("prompt", ""))
	_push({"type": "options", "prompt": StoryData.text(pk), "prompt_key": text_key_of(pk), "options": opts,
		"callback": _apply_choice.bind(h, ch, item_id)})


func _apply_choice(option_id: String, _h: StoryHotspot, ch: Dictionary, item_id: String = "") -> void:
	var chosen: Dictionary = {}
	for o in ch.get("options", []):
		if String(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return
	if item_id != "" and bool(chosen.get("consumes_item", false)):
		GameState.remove_item(item_id)
	if bool(ch.get("exclusive", false)):
		for o in ch.get("options", []):
			var f := String(o.get("sets", ""))
			if f != "" and f != String(chosen.get("sets", "")) and GameState.has_flag(f):
				GameState.set_flag(f, false)
	if chosen.has("sets"):
		GameState.set_flag(String(chosen["sets"]), true)
	if chosen.has("text"):
		_beats.push_front(_text_beat(String(chosen["text"])))


func _run_action(h: StoryHotspot, act: Dictionary, item_id: String) -> void:
	# An item in hand that opens a choice (rooms data item_use.choice — chalk on the board: what to write).
	if act.has("choice"):
		var ch: Dictionary = act["choice"]
		if requires_met(ch.get("requires", {})):
			_offer_choice(h, ch, item_id)
		else:
			narrate_key(String(ch.get("fail_text", "@ui.item_no_effect")))
		return
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
	# `restores`: an item given before and left somewhere comes back into the bag (the mitten from the school
	# step) — the same item, not a second grant: only when it was given (has_<item>) and is not in the bag.
	for it in act.get("restores", []):
		var rid := String(it)
		if GameState.has_flag("has_" + rid) and not GameState.has_item(rid) and GameState.add_item(rid):
			item_received.emit(rid)
	if item_id != "" and bool(act.get("consumes", false)):
		GameState.remove_item(item_id)
	if act.has("text"):
		# one key or a list of keys read in turn (H2 bell: the tag, then Agata's thought)
		var t = act["text"]
		if t is Array:
			for k in t:
				narrate_key(String(k))
		else:
			narrate_key(String(t))
	# The item put in place opens the close-up at once (the clamp on mother's mirror, the brace on the plate).
	if bool(act.get("open_mechanic", false)) and h.data.has("mechanic"):
		var ms := mechanic_spec(h)
		if requires_met(ms.get("requires", {})):
			open_mechanic(ms, h.hotspot_id)


# --- Exits -------------------------------------------------------------------

func use_exit(e: StoryExit) -> void:
	if is_busy():
		return
	# An item in hand on an exit that takes one (data `item_use` of the exit — the house key on the locked
	# front door, Director 18.10): the same rule as on a hotspot. Other exits ignore the held item.
	if selected_item != "" and e.data.has("item_use"):
		var item := selected_item
		select_item("")
		var iu: Dictionary = e.data.get("item_use", {})
		if iu.has(item):
			_run_exit_item(e, iu[item], item)
		else:
			narrate_key(item_refusal(item))
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


## Exit `item_use` {sets, consumes, text, once_flag, enter}: the flags open the exit (its edge in
## locations.json requires them), a consumed item leaves the bag for good (the flag has_<item> stays, so it
## is never given again), `enter` walks through once the text is read. All of it is saved state: after a
## load the door stays open and the key stays used.
func _run_exit_item(e: StoryExit, act: Dictionary, item_id: String) -> void:
	var once := String(act.get("once_flag", ""))
	if once != "" and GameState.has_flag(once):
		narrate_key(String(act.get("text_done", "@ui.item_no_effect")))
		return
	for f in act.get("sets", []):
		GameState.set_flag(String(f), true)
	if bool(act.get("consumes", false)):
		GameState.remove_item(item_id)
	if act.has("text"):
		narrate_key(String(act["text"]))
	if bool(act.get("enter", false)) and e.is_open() and e.target_exists():
		_push({"type": "call", "fn": _enter_room.bind(e.target_room, e.target_spawn)})
	RoomManager.autosave()


func _enter_room(room_id: String, spawn_id: String) -> void:
	RoomManager.call_deferred("change_room", room_id, spawn_id)


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
	if slot_id != "" and placed.has(slot_id) and placed[slot_id] != piece_id:
		return  # a socket holds one hinge: an occupied one is not a target
	for s in placed.keys():
		if placed[s] == piece_id:
			placed.erase(s)
			break
	if slot_id != "":
		placed[slot_id] = piece_id
	_puzzle_touched()


## Which threshold notch sits under the door's mark: index into marks.positions, -1 = none aligned.
func puzzle_set_mark(index: int) -> void:
	if not puzzle_open or bool(puzzle.get("solved", false)):
		return
	puzzle["mark"] = index
	_puzzle_touched()


## Any change after a failed «close the door»: the leaf is back in the opening, worked on again.
func _puzzle_touched() -> void:
	if String(puzzle.get("view", "")) == "wall":
		puzzle["view"] = ""
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


# --- Look-only close-up (hotspot `view`, e.g. the H3 mirror) -------------------

func open_view(spec: Dictionary, hotspot_id: String = "") -> void:
	view = spec.duplicate()
	view["hotspot"] = hotspot_id
	view_open = true
	view_opened.emit(view)


func close_view() -> void:
	if not view_open:
		return
	view_open = false
	view = {}
	view_closed.emit()


# --- Interactive close-ups (hotspot `mechanic`) --------------------------------

## The hotspot's mechanic spec; `same_as` borrows another hotspot's of the same room (the H2 bell and the
## stand with the office mirror open one and the same close-up: the bell is rung while watching the glass).
func mechanic_spec(h: Node) -> Dictionary:
	if h == null:
		return {}
	var d: Dictionary = h.get("data")
	var ms: Dictionary = d.get("mechanic", {})
	if ms.has("same_as"):
		for other in StoryData.room(String(h.get("room_id"))).get("hotspots", []):
			if String(other.get("id", "")) == String(ms["same_as"]):
				var base: Dictionary = other.get("mechanic", {}).duplicate(true)
				base["opened_from"] = String(d.get("id", ""))
				return base
	return ms


func open_mechanic(spec: Dictionary, hotspot_id: String = "") -> void:
	if mechanic_open:
		return
	mechanic = spec.duplicate(true)
	mechanic["hotspot"] = hotspot_id
	mechanic_open = true
	mechanic_opened.emit(mechanic)


func close_mechanic() -> void:
	if not mechanic_open:
		return
	mechanic_open = false
	mechanic = {}
	mechanic_closed.emit()
	if not _mechanic_wait.is_empty():
		# A scene's close-up (`mechanics`): done — the rest of the scene goes on; put away before — the scene
		# stops here, stays not done and waits for the next room visit (no instant reopening).
		var w := _mechanic_wait
		_mechanic_wait = {}
		var rest: Array = w.get("rest", [])
		if GameState.has_flag(String(w.get("until", ""))):
			for b in rest:
				_beats.append(b)
		else:
			var sid := String(w.get("scene", ""))
			_held_back[sid] = true
			if active_scene == sid:
				active_scene = ""
			if stage_dim > 0.0 or current_frame != "":
				stage_dim = 0.0
				stage_fade.emit(0.0, 0.4)
				set_frame("")
		if current_beat.is_empty():
			_next()
		return
	if current_beat.is_empty():
		_queue_check()


## What the player did in the close-up (`events.<name>` in data): flags set (story state, saved), a text
## over the close-up, `close` puts the close-up away after the text. Returns false for an unknown event.
func mechanic_event(event_name: String) -> bool:
	if not mechanic_open:
		return false
	var ev: Dictionary = mechanic.get("events", {}).get(event_name, {})
	if ev.is_empty():
		return false
	for f in ev.get("sets", []):
		GameState.set_flag(String(f), true)
	if ev.has("text"):
		narrate_key(String(ev["text"]))
	if bool(ev.get("close", false)):
		if current_beat.is_empty():
			close_mechanic()
		else:
			_beats.append({"type": "call", "fn": close_mechanic})
	if not ev.get("sets", []).is_empty():
		RoomManager.autosave()
	return true


## A text from the close-up (its data key or plain text) in the dialogue box above it.
func mechanic_say(key_or_text: String) -> void:
	if key_or_text != "":
		narrate_key(key_or_text)


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
