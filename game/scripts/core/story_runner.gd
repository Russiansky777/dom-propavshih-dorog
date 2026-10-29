extends Node
## Autoload `StoryRunner`: executes story scenes from data (scenes/*.json, quests.json, rooms/*.json).
##
## All story logic is generic: a scene starts when its `requires` hold, the player is in one of its
## locations and the room JSON's trigger condition is met (`complete_when` flags, `talk:` hotspot,
## `puzzle:` hotspot, or plain entry). Lines play as beats (click to advance), options are a generic
## list, grants/consumes apply on completion, the journal goal is the scene's `result`.
## No `if scene_id == ...` lives here.

## A villager walked off in a staging (stage[].npc_go) — tests and probes.
signal npc_went(npc_id: String)
## Rooms data on_enter `reveal`: these hotspots are lit for a moment (GameUi → HotspotReveal), I-T1.
signal hotspots_beckoned(ids: Array)
## A room layer moved off in a staging (stage[].layer_go — the empty boat along the rope, H36) — tests and probes.
signal layer_went(layer_id: String)
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
## A sound made by the engine (SynthSfx: the mill bell rung in the room before the office mirror is up).
signal synth_sound_requested(sound_name: String)
## T6 (Director 24.10): the change of day — «День второй» in the title screen's gold over black (DayCard). `own_black`:
## the card brings its own black (a new game); else it plays over a staging's black.
signal day_card_requested(text_key: String, own_black: bool)
## Р13 (Director 29.10): a new game opens with the intro cards (IntroCard; data/story/menu.json → intro.keys).
signal intro_requested(keys: Array)
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
## «Рассмотреть» (Director 23.10, F9): an item from the bag up close (ItemExamine) — items.json `examine`; Agata's
## line about it plays in the dialogue box over the picture. UI only: nothing in the story state changes.
signal examine_opened(item_id: String)
signal examine_closed()

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
var examined_item: String = ""   # the bag item looked at up close ("" — none)

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
	# `not_flags`: flags that must NOT be set (I-T1: Tikhon's day topics; I-T2: his shelf request until it hangs).
	for f in req.get("not_flags", []):
		if GameState.has_flag(String(f)):
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
	## `complete_when`: list of {all:[..]} / {any:[..]} / {any_n:n, flags:[..]} / {or:[cond, …]}; a dict is one condition.
	## `or` holds when any of its conditions does (G15: two traces in the class — or the teacher's drawer).
	var list: Array = conds if conds is Array else [conds]
	for c in list:
		if c.has("or"):
			var any_ok := false
			for sub in c["or"]:
				if conditions_met([sub]):
					any_ok = true
					break
			if not any_ok:
				return false
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
			if typeof(mc.get("at")) != TYPE_STRING and int(mc.get("at", -1)) == i:
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
			# prompt_key: the question is voiced like a room choice's (VoiceDirector, voice.json → narration).
			var ob := {"type": "options", "scene": scene_id, "prompt": StoryData.text(String(line.get("prompt", ""))),
				"prompt_key": text_key_of(String(line.get("prompt", ""))),
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
			if line.has("to"):
				lb["to"] = String(line["to"])  # I-T2: whom the speaker turns to (NpcActor partner)
		lb.merge(cond)
		beats.append(lb)
		# Follow-up lines (`then`: [{speaker, text, if/unless}]) — shown right after this one, each by its own
		# conditions (an optional story's trace in the epilogue). They take no position in mandatory_lines, so adding
		# one never shifts the recorded voices <scene>_<index> after it; line_id <scene>_<index>_then<k>.
		var then_lines: Array = line.get("then", [])
		for k in then_lines.size():
			var sub: Dictionary = then_lines[k]
			var ssp := String(sub.get("speaker", "narrator"))
			var sid := "%s_%d_then%d" % [scene_id, i, k]
			var sb: Dictionary
			if ssp == "narrator":
				sb = {"type": "narration", "scene": scene_id, "line_id": sid, "text": String(sub.get("text", ""))}
			else:
				sb = {"type": "line", "scene": scene_id, "line_id": sid, "speaker": ssp,
					"speaker_name": StoryData.character_name(ssp), "text": String(sub.get("text", ""))}
			sb.merge(_conditions_of(sub))
			beats.append(sb)
	# A close-up after the last line (`at: "end"` — the crossing: Agata hauls the boat once Pelageya has spoken),
	# before the closing stagings.
	for mc in mechs:
		if str(mc.get("at", "")) == "end":
			beats.append({"type": "mechanic", "scene": scene_id, "spec": mc.get("spec", {}), "until": String(mc.get("until", ""))})
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
		GameState.set_goal(StoryData.scene_goal(sc), scene_id)
	_bedtime_check()
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
## `cut: true` — a cut, no black at all: the room / frame / flags change at once (G42, Director 23.10: the turn on
## day four faded to black and showed the empty shore before Ilya and Pelageya «appeared»; the laid log vanished
## for a fade between the close-up and its frame).
func _run_stage(spec: Dictionary) -> void:
	# Timers below stop with the tree (create_timer(…, false)): the pause menu holds a staging where it is.
	_stage_running = true
	# H39 (Director 24.10: «перед „мама“ Агата должна побежать к маме и обнять»): `agata_go` {to, face, action, run} —
	# Agata runs there by herself (speed × run), turns to `face` and plays `action`; a staging with only that has no fade.
	if spec.has("agata_go"):
		var ag_serial := _stage_serial
		await _stage_agata_go(spec["agata_go"])
		if ag_serial != _stage_serial:
			return
		if not spec.has("fade_out_s") and not spec.has("room") and not spec.has("npc_go"):
			_stage_running = false
			_next()
			return
	# A villager walks off first (`npc_go`), then the fade (G18, G29: no more «does nothing, then a cut»).
	var go_serial := _stage_serial
	var go_s := maxf(_stage_npc_go(spec), _stage_layer_go(spec))
	if go_s > 0.0:
		await get_tree().create_timer(go_s).timeout
		if go_serial != _stage_serial:
			return
	# H36: a picture that moves by itself (`layer_go` — the empty boat off along the rope) needs no fade of its own.
	if spec.has("layer_go") and not spec.has("fade_out_s") and not spec.has("room") and not spec.has("cut"):
		_stage_running = false
		_next()
		return
	if bool(spec.get("cut", false)):
		for snd in spec.get("sounds", []):
			stage_sound_requested.emit(String(snd.get("id", "")))
		_stage_apply(spec)
		stage_dim = clampf(float(spec.get("dim", 0.0)), 0.0, 0.95)
		stage_fade.emit(stage_dim, 0.0)
		_stage_running = false
		_next()
		return
	var serial := _stage_serial
	var tree := get_tree()
	var fade_out := float(spec.get("fade_out_s", 0.6))
	stage_fade.emit(1.0, fade_out)
	for snd in spec.get("sounds", []):
		var sid := String(snd.get("id", ""))
		var at := float(snd.get("at_s", 0.0))
		tree.create_timer(at, false).timeout.connect(func():
			if serial == _stage_serial:
				stage_sound_requested.emit(sid))
	await tree.create_timer(fade_out, false).timeout
	if serial != _stage_serial:
		return
	_stage_apply(spec)
	# T6: a change of day (`day_card`: a text key) — the words come up on the black, which holds until they are gone.
	var hold := float(spec.get("hold_s", 1.0))
	if spec.has("day_card") and play_day_card(String(spec["day_card"])):
		hold = maxf(hold, DayCard.seconds() + 0.3)
	await tree.create_timer(hold, false).timeout
	if serial != _stage_serial:
		return
	stage_dim = clampf(float(spec.get("dim", 0.0)), 0.0, 0.95)
	var fade_in := float(spec.get("fade_in_s", 0.6))
	stage_fade.emit(stage_dim, fade_in)
	await tree.create_timer(fade_in, false).timeout
	if serial != _stage_serial:
		return
	_stage_running = false
	_next()


func _stage_agata_go(ag: Dictionary) -> void:
	var pl: Node2D = RoomManager.player
	if pl == null or not pl.has_method("perform_at"):
		return
	var to: Array = ag.get("to", [0, 0])
	var fc: Array = ag.get("face", to)
	var keep: float = float(pl.get("speed_factor"))
	pl.set("speed_factor", keep * float(ag.get("run", 1.0)))
	pl.call("perform_at", Vector2(float(to[0]), float(to[1])), Vector2(float(fc[0]), float(fc[1])), String(ag.get("action", "")))
	var t := 0.0
	while t < 8.0 and (bool(pl.call("is_walking")) or bool(pl.call("is_acting"))):
		await get_tree().process_frame
		t += get_process_delta_time()
	pl.set("speed_factor", keep)


## `npc_go` [{id, to: [x, y], s, fade}]: before the fade, villagers in the room walk off (NpcActor.go_off) — toward a
## door, easing with the depth and fading out. Returns the longest of their seconds (0 — nobody to move).
func _stage_npc_go(spec: Dictionary) -> float:
	var longest := 0.0
	var room := RoomManager.current_room
	if room == null:
		return 0.0
	for g in spec.get("npc_go", []):
		var npc := room.get_node_or_null("npc_" + String(g.get("id", "")))
		if npc != null and npc.has_method("go_off") and (npc as CanvasItem).visible:
			var to: Array = g.get("to", [0, 0])
			npc_went.emit(String(g.get("id", "")))
			var secs := float(g.get("s", 1.2))
			longest = maxf(longest, float(npc.call("go_off", Vector2(float(to[0]), float(to[1])), secs, bool(g.get("fade", true)), room)))
			if g.has("door"):
				longest = maxf(longest, _stage_door(room, g["door"], secs))
			# I-T2 (lines 128–129): `face` "<id>" — on arrival the villager turns to that one and keeps to them.
			var other := room.get_node_or_null("npc_" + String(g.get("face", ""))) as Node2D
			if other != null and npc.has_method("set_partner"):
				get_tree().create_timer(secs).timeout.connect(func():
					if is_instance_valid(npc) and is_instance_valid(other):
						npc.call("set_partner", other))
	return longest


## H36 (Director 24.10: «лодка на кольце скользит по канату и уходит в туман»): `layer_go` [{id, by: [dx, dy], scale,
## pivot: [x, y], fade, s}] — a state layer of the room (rooms data `layers[].id`, if shown now) slides by `by` screen px,
## shrinks to `scale` about `pivot` (screen px) and fades out (`fade`, default true) in `s` seconds. `layer_reset` [ids]
## in a later staging puts it back while black (the boat hauled home). A rebuilt room (load, re-entry) draws the layer
## in place anyway. Returns the longest of the seconds (0 — nothing to move).
func _stage_layer_go(spec: Dictionary) -> float:
	var longest := 0.0
	var room := RoomManager.current_room
	if room == null:
		return 0.0
	for g in spec.get("layer_go", []):
		var node := room.get_node_or_null("Layers/" + String(g.get("id", ""))) as Node2D
		if node == null or not node.visible:
			continue
		var secs := float(g.get("s", 2.0))
		var k := float(g.get("scale", 1.0))
		var pv: Array = g.get("pivot", [0, 0])
		var by: Array = g.get("by", [0, 0])
		var to := Vector2(float(pv[0]), float(pv[1])) * (1.0 - k) + Vector2(float(by[0]), float(by[1]))
		layer_went.emit(String(g.get("id", "")))
		var tw := node.create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "position", to, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(node, "scale", Vector2(k, k), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if bool(g.get("fade", true)):
			tw.tween_property(node, "modulate:a", 0.0, secs * 0.6).set_delay(secs * 0.4)
		longest = maxf(longest, secs)
	return longest


func _stage_layer_reset(spec: Dictionary) -> void:
	var room := RoomManager.current_room
	if room == null:
		return
	for id in spec.get("layer_reset", []):
		var node := room.get_node_or_null("Layers/" + String(id)) as Node2D
		if node != null:
			node.position = Vector2.ZERO
			node.scale = Vector2.ONE
			node.modulate.a = 1.0


## H24 (Director 24.10: «движение Павла в дом непонятное, дверь не открывается и не закрывается»): the painted door
## of npc_go `door` {rect: [x, y, w, h] on screen, hinge: "left" | "right"} swings open while the villager walks up,
## he goes into the dark doorway, and it swings shut behind him. The leaf is the door cut from the room's own
## background (no new art), turning on its hinge (narrowing, darker); the doorway behind it is dark. Returns the
## seconds until it is shut.
func _stage_door(room: Node, door: Dictionary, walk_s: float) -> float:
	var r: Array = door.get("rect", [])
	var bg_path := String(StoryData.room(current_room_id()).get("background", {}).get("image", ""))
	# `image`: the picture the leaf is cut from when the room is shown over its background by a full-scene layer
	# (J, стр. 149: Nina's door in Olkhovka at night — the night picture, not the daylight one).
	if door.has("image"):
		bg_path = String(door["image"])
	if r.size() < 4 or bg_path == "" or not ResourceLoader.exists(bg_path):
		return 0.0
	var tex: Texture2D = load(bg_path)
	var k := float(tex.get_width()) / 1920.0
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var hinge_left := String(door.get("hinge", "left")) == "left"
	var root := Node2D.new()
	root.name = "StageDoor"
	root.z_index = clampi(int(rect.end.y) - 40, 0, 4096)   # under the villager who walks in (z = his feet y)
	room.add_child(root)
	var hole := ColorRect.new()
	hole.color = Color(String(door.get("dark", "#0e0a07")))
	hole.position = rect.position
	hole.size = rect.size
	hole.modulate.a = 0.0
	root.add_child(hole)
	var leaf := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(rect.position * k, rect.size * k)
	leaf.texture = at
	leaf.centered = false
	leaf.scale = Vector2(1.0 / k, 1.0 / k)
	if hinge_left:
		leaf.position = rect.position
	else:
		leaf.offset = Vector2(-at.region.size.x, 0.0)
		leaf.position = Vector2(rect.end.x, rect.position.y)
	root.add_child(leaf)
	var open_at := walk_s * 0.25
	var open_s := 0.45
	var shut_at := walk_s + 0.15
	var tw := root.create_tween()
	tw.tween_interval(open_at)
	tw.tween_property(hole, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(leaf, "scale:x", 0.22 / k, open_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(leaf, "modulate", Color(0.55, 0.5, 0.46), open_s)
	tw.tween_interval(maxf(0.0, shut_at - open_at - open_s))
	tw.tween_property(leaf, "scale:x", 1.0 / k, open_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(leaf, "modulate", Color(1, 1, 1), open_s)
	tw.tween_property(hole, "modulate:a", 0.0, 0.05)
	tw.tween_callback(root.queue_free)
	return shut_at + open_s


## What a staging changes while the screen is black (or at once, for a cut): the room, the frame, flags.
func _stage_apply(spec: Dictionary) -> void:
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
	_stage_layer_reset(spec)
	if spec.has("layer_write"):
		call_deferred("_stage_layer_write", spec["layer_write"])


## I-T2 (Director, line 138: «когда мать пишет на доске — нужна анимация»): `layer_write` [{id, x: [x0, x1], s}] — a
## layer just shown by the staging's `sets` is written in, left to right across its letters (x0..x1 in the layer's
## own pixels) in `s` seconds, as chalk; hidden layers (the other answers) are skipped. A rebuilt room shows it whole.
var layers_written: Array[String] = []   # tests


func _stage_layer_write(list: Array) -> void:
	var room := RoomManager.current_room
	if room == null:
		return
	for g in list:
		var node := room.get_node_or_null("Layers/" + String(g.get("id", ""))) as CanvasItem
		var spr := node.get_node_or_null("Image") as Sprite2D if node != null else null
		if spr == null or not node.visible or spr.texture == null:
			continue
		var full: Vector2 = spr.texture.get_size()
		var xs: Array = g.get("x", [0, full.x])
		layers_written.append(String(g.get("id", "")))
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, float(xs[0]), full.y)
		var tw := spr.create_tween()
		tw.tween_method(func(w: float): spr.region_rect = Rect2(0, 0, w, full.y), float(xs[0]), float(xs[1]),
			float(g.get("s", 1.5))).set_delay(float(g.get("delay", 0.0)))
		tw.tween_callback(func(): spr.region_enabled = false)


## T6: shows the change-of-day card `key` once: the flag day_card_<key> is part of the save, so neither a load nor
## a scene restarted after an interruption shows it again. false — already shown.
func play_day_card(key: String, own_black: bool = false) -> bool:
	var flag := "day_card_" + key.trim_prefix("@").replace(".", "_")
	if key == "" or GameState.has_flag(flag):
		return false
	GameState.set_flag(flag, true)
	day_card_requested.emit(key, own_black)
	return true


## A new game opens with the intro (Р13: cards on black with the voice-over, menu.json → intro.keys; once — the flag
## intro_seen is part of the save), then «День первый» (menu.json → day_card.first): IntroCard calls this again when
## its last card is gone.
func play_first_day_card() -> void:
	var intro: Array = MenuConfig.section("intro").get("keys", [])
	if not intro.is_empty() and not GameState.has_flag("intro_seen"):
		GameState.set_flag("intro_seen", true)
		intro_requested.emit(intro)
		return
	play_day_card(String(MenuConfig.section("day_card").get("first", "")), true)


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


## Rooms data `on_enter` [{text, then?, once_flag, if?, unless?}]: a line on the first entry (O1: «Там зима. А у нас ещё
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
		# `spawn`: only when the player came in through that door (I-T1: the dark house from the porch, not a load).
		if oe.has("spawn") and String(oe["spawn"]) != RoomManager.last_spawn:
			continue
		if once != "":
			GameState.set_flag(once, true)
		# `reveal`: hotspot ids lit for a moment, as by the reveal key (I-T1: Ilya's workshop on the first visit after
		# Nina's word about it — Q06 was never found).
		if oe.has("reveal"):
			hotspots_beckoned.emit(oe["reveal"])
		if String(oe.get("text", "")) == "":
			continue
		narrate_key(String(oe.get("text", "")))
		# `then`: more text keys right after it — a short exchange on entry (H33: Tikhon after the mother's mirror).
		for k in oe.get("then", []):
			narrate_key(String(k))


## What Agata says when an item is used on the wrong thing: items.json `wrong_target` {text, rooms?} — where the
## item goes (Director 23:53: «как поставить зеркало на стойку тети?»); the generic refusal only for items
## without it or outside its `rooms`. tools/validate_rooms.py requires it for every item that moves the story.
## `states` [{if?, unless?, text}] — the first that holds says its text instead (I-T5: the brace — «при такой воде до
## плиты не достать» while the plate is under water, «там и поставлю» once it is out at dusk).
func item_refusal(item_id: String) -> String:
	var wt: Dictionary = StoryData.item(item_id).get("wrong_target", {})
	var rooms: Array = wt.get("rooms", [])
	if wt.has("text") and (rooms.is_empty() or rooms.has(current_room_id())):
		for st in wt.get("states", []):
			if requires_met({"flags": st.get("if", []), "not_flags": st.get("unless", [])}):
				return String(st.get("text", wt["text"]))
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
	close_examine()
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
	close_examine()
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
	if d.has("sleep"):
		return "use"
	if d.has("talk"):
		var t: Dictionary = d["talk"]
		var scn := talk_scene(t)
		if scn != "" and can_start(scn):
			return "talk"
		if (scn != "" and not is_done(scn) and t.has("before_text")) or t.has("after_text") or t.has("by_flags"):
			return "talk_text"
	if d.has("mechanic") and mechanic_available(mechanic_spec(h)):
		return "mechanic"
	if d.has("puzzle"):
		var pz: Dictionary = d["puzzle"]
		var success_scene := String(pz.get("success", {}).get("scene", ""))
		if requires_met(pz.get("requires", {})) and (success_scene == "" or not is_done(success_scene)):
			return "text" if pz.has("by_item_text") else "puzzle"
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
	if _use_state(d) != "ready" and not _use_when(d).is_empty():
		return "use"
	return "use" if _use_state(d) == "ready" else "text"


## A hotspot's use by state once its `use` is not ready (data `use_when`: [{if, unless, …action}] — the first
## entry whose `if` flags all hold and no `unless` flag holds runs as an action): the mill bell with its
## clapper hung rings far away at the mill before the office mirror is on the stand (Director 23.10). {} when none.
func _use_when(d: Dictionary) -> Dictionary:
	for e in d.get("use_when", []):
		var ok := true
		for f in e.get("if", []):
			if not GameState.has_flag(String(f)):
				ok = false
		for f in e.get("unless", []):
			if GameState.has_flag(String(f)):
				ok = false
		if ok:
			return e
	return {}


func interact(h: StoryHotspot) -> void:
	if is_busy():
		return
	var d := h.data
	# A state may say its own look (rooms data `states[].look` — G14: the stove after the shelf is hung no longer talks
	# of the mount sockets; G9: the leaning shelf while the wet towel is on the bench) and its own refusal of a choice
	# (`states[].fail_text`).
	var hst := h.current_state()
	var look := String(hst.get("look", d.get("look", "@ui.nothing_here")))

	if selected_item != "":
		var item := selected_item
		select_item("")
		var iu: Dictionary = d.get("item_use", {})
		if iu.has(item):
			_run_action(h, iu[item], item)
		else:
			narrate_key(item_refusal(item))
		return

	if d.has("sleep"):
		_sleep(d["sleep"])
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
		# `intro` [{if, unless, text}]: what the person says first, before the questions (I-T1, Director 25.10:
		# Tikhon asks for his shelf at every talk until it hangs) — the first entry that holds; the choice follows.
		for e in t.get("intro", []):
			if requires_met({"flags": e.get("if", []), "not_flags": e.get("unless", [])}):
				narrate_key(String(e.get("text", "")))
				break

	if d.has("mechanic"):
		var ms := mechanic_spec(h)
		if mechanic_available(ms):
			open_mechanic(ms, h.hotspot_id)
			return

	if d.has("puzzle"):
		var pz: Dictionary = d["puzzle"]
		var success_scene := String(pz.get("success", {}).get("scene", ""))
		if requires_met(pz.get("requires", {})) and (success_scene == "" or not is_done(success_scene)):
			# I-T2 (Director, line 52: «петли мышкой применить, как и ключ»): puzzle `by_item_text` — a plain click
			# only says what to do; the close-up opens from the item in hand (item_use {puzzle: true}).
			if pz.has("by_item_text"):
				narrate_key(String(pz["by_item_text"]))
				return
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
		elif ch.has("fail_text") or hst.has("fail_text"):
			narrate_key(String(hst.get("fail_text", ch.get("fail_text", ""))))
			return

	# Look-only close-up (data `view`): opens first, the use/look text below plays over it. `if` / `unless`
	# flags gate it (O1 drawer: only while the three things are still in it).
	if d.has("view") and view_allowed(d["view"]):
		open_view(d["view"], h.hotspot_id)

	if _use_state(d) != "ready":
		var uw := _use_when(d)
		if not uw.is_empty():
			_run_action(h, uw, "")
			return
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


## H17 (Director 24.10: «не понятно, когда новый день»): the bed ends the day. rooms data `sleep` {scenes, late, early}:
## the first of `scenes` that can start begins after Agata's «пора спать» (`late`: scene → text); none can — the
## first `early` entry whose `if` / `unless` flags hold: «рано ложиться» with what is left (`left` [{unless, text}]
## joined into {left}).
func _sleep(sl: Dictionary) -> void:
	for sc in sl.get("scenes", []):
		var scn := String(sc)
		if can_start(scn):
			var late: Dictionary = sl.get("late", {})
			if late.has(scn):
				narrate_key(String(late[scn]))
			start_scene(scn)
			return
	# J (Директор 29.10, стр. 178: «Рано ещё спать. Надо… — не озвучено»): an entry with `say_head` is spoken as
	# separate recorded lines — the head («Рано ещё спать.») and each deed still left (its `say` key) — instead of one
	# composed sentence that cannot be recorded ahead.
	var e := sleep_early_entry(sl)
	if not e.is_empty() and e.has("say_head"):
		narrate_key(String(e["say_head"]))
		for l in e.get("left", []):
			if not GameState.has_flag(String(l.get("unless", ""))) and l.has("say"):
				narrate_key(String(l["say"]))
		return
	_push(sleep_early_beat(sl))


## The `early` entry that holds now ({} — none).
func sleep_early_entry(sl: Dictionary) -> Dictionary:
	for e in sl.get("early", []):
		if not requires_met({"flags": e.get("if", [])}):
			continue
		if (e.get("unless", []) as Array).any(func(f): return GameState.has_flag(String(f))):
			continue
		return e
	return {}


## The «рано ложиться» beat for the state now (tests read its text too).
func sleep_early_beat(sl: Dictionary) -> Dictionary:
	for e in sl.get("early", []):
		if not requires_met({"flags": e.get("if", [])}):
			continue
		if (e.get("unless", []) as Array).any(func(f): return GameState.has_flag(String(f))):
			continue
		var left: Array[String] = []
		for l in e.get("left", []):
			if not GameState.has_flag(String(l.get("unless", ""))):
				left.append(StoryData.text(String(l.get("text", ""))))
		var b := _text_beat(String(e.get("text", "")))
		# I-T5: «Надо ещё повидать Тамару…, зайти к Павлу… и поговорить с Тихоном…» — the last deed joined by `left_last`.
		var joined := ""
		if left.size() > 1:
			joined = String(e.get("left_sep", ", ")).join(left.slice(0, left.size() - 1)) + String(e.get("left_last", ", ")) + left.back()
		elif left.size() == 1:
			joined = left[0]
		b["text"] = String(b["text"]).replace("{left}", joined)
		return b
	return _text_beat("@ui.nothing_here")


## H17: a time state's `bedtime` {if?, text?, goal?} (data/story/time/_index.json) — the day's deeds are done: Agata
## says it is late (once: flag bedtime_<state> in the save) and the journal points to the bed.
func _bedtime_check() -> void:
	var st := TimeOfDay.current_state()
	var bt: Dictionary = TimeOfDay.state_spec(st).get("bedtime", {})
	if bt.is_empty() or GameState.has_flag("bedtime_" + st):
		return
	# `if`: flags the day's last deed sets inside the state (day two: the talk with Ilya, M20, ends the night).
	if not requires_met({"flags": bt.get("if", [])}):
		return
	GameState.set_flag("bedtime_" + st, true)
	if bt.has("goal"):
		GameState.set_goal(StoryData.text(String(bt["goal"])))
	if bt.has("text"):
		narrate_key(String(bt["text"]))


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
	_push(_choice_beat(h, ch, item_id))


func _choice_beat(h: StoryHotspot, ch: Dictionary, item_id: String = "") -> Dictionary:
	var opts: Array = []
	for o in ch.get("options", []):
		if not requires_met(o.get("requires", {})):
			continue
		opts.append({"id": String(o["id"]), "label": StoryData.text(String(o.get("label", o["id"]))), "sets": String(o.get("sets", ""))})
	var pk := String(ch.get("prompt", ""))
	return {"type": "options", "prompt": StoryData.text(pk), "prompt_key": text_key_of(pk), "options": opts,
		"callback": _apply_choice.bind(h, ch, item_id)}


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
	# `agata_go` {to, face, action}: Agata walks there and touches the thing (H15: the chosen cup on the table).
	var ag: Dictionary = chosen.get("agata_go", {})
	if not ag.is_empty() and RoomManager.player != null and RoomManager.player.has_method("perform_at"):
		var to: Array = ag.get("to", [0, 0])
		var fc: Array = ag.get("face", to)
		RoomManager.player.call("perform_at", Vector2(float(to[0]), float(to[1])), Vector2(float(fc[0]), float(fc[1])), String(ag.get("action", "reach")))
	# `also`: flags the option sets besides its own (G37: any drawing on the bird is also «Agata marked it», v03_marked).
	for f in chosen.get("also", []):
		GameState.set_flag(String(f), true)
	# The option's words (`text`), then `then` — more text keys in order (H43: Ulyana answers, Agata answers back).
	var said: Array = []
	if chosen.has("text"):
		said.append(String(chosen["text"]))
	for k in chosen.get("then", []):
		said.append(String(k))
	for i in range(said.size() - 1, -1, -1):
		_beats.push_front(_text_beat(String(said[i])))


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
	# `goal`: the journal's goal changes with the action (J, Р5: the lever in the rusted winch — «принести дёготь»;
	# the tar taken — «к затвору»): a text key, like a scene's goal.
	if act.has("goal"):
		GameState.set_goal(StoryData.text(String(act["goal"])))
	if act.has("synth_sound"):
		synth_sound_requested.emit(String(act["synth_sound"]))
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
		if mechanic_available(ms):
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
		# `unless` flags end the loop (T9, R36: once the rope is on the ring, M15, the school path no longer turns
		# back — the closed exit then says the state's `closed_text`: Agata herself goes to the crossing first).
		var loop_over: bool = (oc.get("unless", []) as Array).any(func(f): return GameState.has_flag(String(f)))
		if String(oc.get("type", "")) == "loop" and not loop_over:
			_run_loop(e, oc)
			return
		# The closed text may follow the state (data exit `states` [{if, closed_text}]: «В лодку» after the knot —
		# first the empty-boat check, no more «вернёт сюда же»; ИИ-разбор логики M2 п. 3).
		narrate_key(String(e.current_state().get("closed_text", e.data.get("closed_text", "@ui.closed_generic"))))
		return
	if not e.target_exists():
		narrate_key(String(e.data.get("unbuilt_text", "@ui.not_built")))
		return
	# An exit that is travelled by hand (data exit `mechanic` with its `requires` — the boat along the rope once it
	# goes both ways, G43): the close-up opens here, and its event takes the player across (`events.<name>.room`).
	if e.data.has("mechanic") and mechanic_available(e.data["mechanic"]):
		open_mechanic(e.data["mechanic"], "exit_" + e.target_room)
		return
	# I-T2 (Director, lines 34–35): exit `on_pass` {sets} — flags set when Agata walks through (the gallery side door:
	# «Отпереть дверь» until the first pass, then her line in the lane, then the usual label).
	for f in (e.data.get("on_pass", {}) as Dictionary).get("sets", []):
		GameState.set_flag(String(f), true)
	RoomManager.call_deferred("change_room", e.target_room, e.target_spawn)


## Exit `item_use` {sets, consumes, text, once_flag, enter, requires, fail_text}: the flags open the exit (its edge in
## locations.json requires them), a consumed item leaves the bag for good (the flag has_<item> stays, so it
## is never given again), `enter` walks through once the text is read. All of it is saved state: after a
## load the door stays open and the key stays used.
func _run_exit_item(e: StoryExit, act: Dictionary, item_id: String) -> void:
	var once := String(act.get("once_flag", ""))
	if once != "" and GameState.has_flag(once):
		narrate_key(String(act.get("text_done", "@ui.item_no_effect")))
		return
	# T8 (Director 24.10: the house opens only after Pelageya, M02): `requires` {flags} not met — `fail_text`, the item
	# stays in the bag and nothing is set.
	if act.has("requires") and not requires_met(act["requires"]):
		narrate_key(String(act.get("fail_text", "@ui.item_no_effect")))
		return
	for f in act.get("sets", []):
		GameState.set_flag(String(f), true)
	if bool(act.get("consumes", false)):
		GameState.remove_item(item_id)
	if act.has("text"):
		narrate_key(String(act["text"]))
	# `then`: more text keys right after it (I-T1, Director 25.10: «Теперь и отсюда в дом заходить смогу»).
	for k in act.get("then", []):
		narrate_key(String(k))
	if bool(act.get("enter", false)) and e.is_open() and e.target_exists():
		_push({"type": "call", "fn": _enter_room.bind(e.target_room, e.target_spawn)})
	RoomManager.autosave()


func _enter_room(room_id: String, spawn_id: String) -> void:
	RoomManager.call_deferred("change_room", room_id, spawn_id)


## Closed exit that loops back (O2 gate): fade, place the player at `spawn`, set flags, react.
func _run_loop(e: StoryExit, oc: Dictionary) -> void:
	_loop_running = true
	loop_transition.emit(oc)
	await get_tree().create_timer(LOOP_FADE_SECONDS, false).timeout
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


## J-A1 (Директор 29.10, стр. 47: «Видно, либо петли, либо порог… — исправить фразу»): the error says what is wrong —
## the hinges (`error_text_pieces`: not all in, or in a wrong socket) or the threshold (`error_text_mark`); without
## those texts — the common `error_text`.
func _puzzle_error_text(spec: Dictionary) -> String:
	var placed: Dictionary = puzzle.get("placed", {})
	var pieces_ok: bool = placed.size() == (spec.get("pieces", []) as Array).size()
	for s in spec.get("slots", []):
		if bool(s.get("correct", false)) != placed.has(String(s["id"])):
			pieces_ok = false
	var key := "error_text_pieces" if not pieces_ok else "error_text_mark"
	return String(spec.get(key, spec.get("error_text", "")))


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
	_set_puzzle_message(_puzzle_error_text(spec))
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

## A close-up can be opened: its `requires` hold and none of its `unless` flags is set (the H1 shutter: no latch
## close-up once the shutter is open — a click is then just a look).
func mechanic_available(ms: Dictionary) -> bool:
	if not requires_met(ms.get("requires", {})):
		return false
	for f in ms.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


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
				# J-A5 (Директор 29.10, стр. 112: «кликаю на колокол — даёт ту же картинку, что и стекло»): the borrowing
				# hotspot adds its own `unless` — after the office is open the bell no longer opens the mirror's close-up.
				for f in ms.get("unless", []):
					var un: Array = base.get("unless", [])
					if not un.has(f):
						un.append(f)
					base["unless"] = un
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


## What the player did in the close-up (`events.<name>` in data): flags set (story state, saved), a text (or a
## list of texts read in turn) over the close-up, `close` puts the close-up away after the text, `then_choice` —
## then the choice of the hotspot that opened it comes at once (Q02/Q06: the second bench built — where it
## stands), not on a second click. Returns false for an unknown event.
func mechanic_event(event_name: String) -> bool:
	if not mechanic_open:
		return false
	var ev: Dictionary = mechanic.get("events", {}).get(event_name, {})
	if ev.is_empty():
		return false
	var hotspot_id := String(mechanic.get("hotspot", ""))
	for f in ev.get("sets", []):
		GameState.set_flag(String(f), true)
	if ev.has("text"):
		var t = ev["text"]
		for k in (t if t is Array else [t]):
			narrate_key(String(k))
	if bool(ev.get("close", false)):
		if current_beat.is_empty():
			close_mechanic()
		else:
			_beats.append({"type": "call", "fn": close_mechanic})
	# `room` (+ `spawn`): the close-up took the player somewhere — the boat crossed by the rope (G43).
	if ev.has("room"):
		var go := _enter_room.bind(String(ev["room"]), String(ev.get("spawn", "default")))
		if current_beat.is_empty() and not mechanic_open:
			go.call()
		else:
			_beats.append({"type": "call", "fn": go})
	if bool(ev.get("then_choice", false)):
		var cb := _hotspot_choice_beat(hotspot_id)
		if not cb.is_empty():
			_beats.append(cb)
			if current_beat.is_empty():
				_next()
	if not ev.get("sets", []).is_empty():
		RoomManager.autosave()
	return true


## The choice of hotspot `hotspot_id` of the current room as a beat, if it can be made now (its requires hold and,
## with `once_any`, nothing is chosen yet); {} otherwise.
func _hotspot_choice_beat(hotspot_id: String) -> Dictionary:
	var room := RoomManager.current_room
	if room == null or hotspot_id == "":
		return {}
	var h := room.get_node_or_null("Hotspots/" + hotspot_id) as StoryHotspot
	if h == null or not h.data.has("choice"):
		return {}
	var ch: Dictionary = h.data["choice"]
	if not requires_met(ch.get("requires", {})):
		return {}
	if bool(ch.get("once_any", false)):
		for o in ch.get("options", []):
			if GameState.has_flag(String(o.get("sets", ""))):
				return {}
	return _choice_beat(h, ch)


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


# --- «Рассмотреть»: an item from the bag up close -----------------------------------------------

## items.json `examine` of the item ({} — none).
func examine_spec(item_id: String) -> Dictionary:
	var e = StoryData.item(item_id).get("examine", {})
	return e if e is Dictionary else {}


## Opens the close-up of a bag item and plays Agata's line about it. Not while a text is being read (the box
## takes the clicks then) or a staging runs; the item stays where it is (in the bag — a held item is put back).
func examine_item(item_id: String) -> bool:
	if item_id == "" or not GameState.has_item(item_id) or not current_beat.is_empty() or _stage_running:
		return false
	if selected_item != "":
		select_item("")
	examined_item = item_id
	examine_opened.emit(item_id)
	var t := String(examine_spec(item_id).get("text", ""))
	if t != "":
		var b := _text_beat(t)
		b["examine"] = item_id   # Agata's line about this thing: it goes when the close-up is put away (G55)
		_push(b)
	return true


## Puts the item close-up away. G55 (Director 23.10: the first «Закрыть» only turned Agata's line, the second closed):
## her line about the thing, if it is still on screen, goes with the close-up — the voice stops on the beat change.
func close_examine() -> void:
	if examined_item == "":
		return
	var own_line := String(current_beat.get("examine", "")) != ""
	examined_item = ""
	examine_closed.emit()
	if own_line:
		_next()
