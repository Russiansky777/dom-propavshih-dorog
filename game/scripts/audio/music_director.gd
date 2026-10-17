extends Node
## Autoload `MusicDirector`: background music driven by data/story/music.json.
##
## Two AudioStreamPlayer decks on the "Music" bus:
##   - the room's theme (`rooms`); a room of another theme → equal-power crossfade `crossfade_s`,
##     a room of the same theme → the track keeps playing (no restart); a faded-out room theme is
##     paused, not stopped, and coming back to it (after an event or a quick there-and-back) resumes
##     it where it was — an event theme always starts from its beginning;
##   - seamless loop: `loop_crossfade_s` before the end the other deck starts the same track from the
##     beginning and the two cross. Suno tracks are not sample-accurate loops, so the stream's own
##     loop is never used (import loop=false, tools/sync_music.sh; forced off here as well);
##   - a theme with `loop: false` (finale) plays to its end — the last `end_fade_s` faded — and stops;
##   - events over the room theme (`events`): `scene:<id>` starts its theme on
##     StoryRunner.scene_started and releases it on scene_completed (`until: "scene_end"`, the default
##     for looping themes) or when the track has played out (`until: "track_end"`, the default for
##     non-looping ones); then the room theme returns. The newest active event wins;
##   - dialogue ducking: while a scene line or option is on screen every theme except `duck_except`
##     is lowered by `duck_dialogue_db`, eased over DUCK_FADE_S;
##   - music volume (menu slider 0–100 %) is a setting in user://settings.cfg [audio] music_volume —
##     not part of a save slot — applied to the Music bus.
## Web: the browser keeps the AudioContext suspended until the first user gesture; Godot resumes it
## from that input event, and the first theme starts only then (fade-in from silence).
## Playback type is STREAM everywhere: the web default «Sample» would decode a whole 2–3 minute
## track to PCM (~60 MB, seconds of main-thread work) the first time each theme plays. The single-
## threaded web build mixes stream playback on the main thread, so project.godot raises
## audio/driver/output_latency.web to 750 ms (a 32768-frame ring buffer, ≈0.7 s): a room build or a
## slow frame shorter than that does not interrupt the music; fades are heard up to that much later.

signal theme_changed(theme: String)
signal music_volume_changed(volume: float)

const CONFIG_PATH: String = "res://data/story/music.json"
const MUSIC_DIR: String = "res://assets/music"
const BUS_NAME: String = "Music"
const EXTRA_BUSES: Array[String] = ["SFX", "Voice"]
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_VOLUME: float = 1.0
const DUCK_FADE_S: float = 0.4
const SILENCE_DB: float = -80.0
const SAVE_DELAY_S: float = 0.5
const WEB_STATE_INTERVAL_S: float = 0.25
const UNTIL_VALUES: Array[String] = ["scene_end", "track_end"]


class Deck:
	extends RefCounted
	var player: AudioStreamPlayer
	var theme: String = ""
	var gain: float = 0.0        # fade envelope, linear 0..1
	var fade_from: float = 0.0
	var fade_to: float = 0.0
	var fade_s: float = 0.0
	var fade_t: float = 0.0
	var handed: bool = false     # loop crossfade / end fade already started for this pass
	var paused: bool = false     # faded out and paused at its position (resumable)
	var starts: int = 0          # play() calls (tests: «same theme → no restart»)

	func alive() -> bool:
		return player.playing or paused


# --- Data (music.json) ---
var themes: Dictionary = {}          # theme -> {file, loop, volume_db, ...}
var room_themes: Dictionary = {}     # room id -> theme
var events: Dictionary = {}          # "scene:<id>" -> {theme, until}
var crossfade_s: float = 2.5
var loop_crossfade_s: float = 4.0
var end_fade_s: float = 2.0
var duck_dialogue_db: float = -5.0
var duck_except: Array = []
var config_errors: Array[String] = []

# --- State ---
var room_theme: String = ""
var target_theme: String = ""
var active_events: Array[Dictionary] = []   # {key, theme, until}; the last one wins
var unlocked: bool = true
var music_volume: float = DEFAULT_VOLUME
var settings_path: String = DEFAULT_SETTINGS_PATH
var duck_db_now: float = 0.0
var loop_passes: int = 0
var settings_saves: int = 0

var _decks: Array[Deck] = []
var _active: Deck = null
var _streams: Dictionary = {}        # theme -> AudioStream (loaded on first use)
var _retarget_queued: bool = false
var _save_timer: Timer = null
var _web_state_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # music and its fades go on while the tree is paused
	_ensure_buses()
	reload_config()
	for deck_name in ["DeckA", "DeckB"]:
		var p := AudioStreamPlayer.new()
		p.name = deck_name
		p.bus = BUS_NAME
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		p.volume_db = SILENCE_DB
		add_child(p)
		var d := Deck.new()
		d.player = p
		p.finished.connect(_on_deck_finished.bind(d))
		_decks.append(d)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	load_settings()
	unlocked = not OS.has_feature("web")
	RoomManager.room_changed.connect(_on_room_changed)
	StoryRunner.scene_started.connect(_on_scene_started)
	StoryRunner.scene_completed.connect(_on_scene_completed)
	GameState.state_reset.connect(clear_events)
	GameState.state_loaded.connect(func(_slot): clear_events())
	if RoomManager.current_room != null and is_instance_valid(RoomManager.current_room):
		_on_room_changed(RoomManager.current_room.room_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _save_timer != null and not _save_timer.is_stopped():
			_save_timer.stop()
			save_settings()


# --- Configuration -------------------------------------------------------------------

func reload_config() -> void:
	config_errors.clear()
	var data: Dictionary = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		config_errors.append("missing " + CONFIG_PATH)
	else:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			data = parsed
		else:
			config_errors.append(CONFIG_PATH + " is not a JSON object")
	themes = data.get("themes", {})
	room_themes = data.get("rooms", {})
	crossfade_s = float(data.get("crossfade_s", 2.5))
	loop_crossfade_s = float(data.get("loop_crossfade_s", 4.0))
	end_fade_s = float(data.get("end_fade_s", 2.0))
	duck_dialogue_db = float(data.get("duck_dialogue_db", -5.0))
	duck_except = data.get("duck_except", [])
	events.clear()
	var raw_events: Dictionary = data.get("events", {})
	for k in raw_events.keys():
		var key := String(k)
		if key.begins_with("_"):
			continue
		var spec := event_spec(raw_events[k])
		if not themes.has(spec["theme"]):
			config_errors.append("event %s: unknown theme '%s'" % [key, spec["theme"]])
			continue
		if not UNTIL_VALUES.has(spec["until"]):
			config_errors.append("event %s: until must be one of %s" % [key, UNTIL_VALUES])
			continue
		events[key] = spec
	_streams.clear()
	for e in config_errors:
		push_error("MusicDirector: " + e)


## Normalises an `events` value: "theme" or {theme, until}; `until` defaults by the theme's loop.
func event_spec(value: Variant) -> Dictionary:
	var spec: Dictionary = {}
	if value is Dictionary:
		spec = {"theme": String(value.get("theme", "")), "until": String(value.get("until", ""))}
	else:
		spec = {"theme": String(value), "until": ""}
	if spec["until"] == "":
		spec["until"] = "scene_end" if is_loop(spec["theme"]) else "track_end"
	return spec


func is_loop(theme: String) -> bool:
	return bool(themes.get(theme, {}).get("loop", true))


func theme_for_room(room_id: String) -> String:
	return String(room_themes.get(room_id, ""))


func theme_path(theme: String) -> String:
	return "%s/%s" % [MUSIC_DIR, String(themes.get(theme, {}).get("file", ""))]


func stream_for(theme: String) -> AudioStream:
	if _streams.has(theme):
		return _streams[theme]
	var s: AudioStream = null
	var path := theme_path(theme)
	if themes.has(theme) and ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		push_error("MusicDirector: no stream for theme '%s' (%s)" % [theme, path])
	elif "loop" in s:
		s.set("loop", false)  # the director loops by crossfade
	_streams[theme] = s
	return s


func _ensure_buses() -> void:
	# default_bus_layout.tres declares them; this keeps the game working if the layout is missing.
	for bus in [BUS_NAME] + EXTRA_BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


# --- What should play ---------------------------------------------------------------

func wanted_theme() -> String:
	if not active_events.is_empty():
		return String(active_events.back()["theme"])
	return room_theme


func _on_room_changed(room_id: String) -> void:
	var t := theme_for_room(room_id)
	if t == "":
		# Probe fixtures (RoomHouse/RoomOffice) are not locations; a real location without a theme is
		# a data error caught by tools/validate_music.py.
		if StoryData.locations.has(room_id):
			push_warning("MusicDirector: room '%s' has no theme in music.json; music unchanged" % room_id)
		return
	room_theme = t
	_queue_retarget()


func _on_scene_started(scene_id: String) -> void:
	var key := "scene:" + scene_id
	if not events.has(key):
		return
	_remove_events(func(e): return e["key"] == key)
	var spec: Dictionary = events[key]
	active_events.append({"key": key, "theme": spec["theme"], "until": spec["until"]})
	_queue_retarget()


func _on_scene_completed(scene_id: String) -> void:
	var key := "scene:" + scene_id
	if _remove_events(func(e): return e["key"] == key and e["until"] == "scene_end"):
		_queue_retarget()


## New game / loaded save: no scene is running, the room theme rules.
func clear_events() -> void:
	active_events.clear()
	_queue_retarget()


func _remove_events(pred: Callable) -> bool:
	var kept: Array[Dictionary] = []
	for e in active_events:
		if not pred.call(e):
			kept.append(e)
	var removed := kept.size() != active_events.size()
	active_events = kept
	return removed


func _queue_retarget() -> void:
	# Deferred: a load (state_loaded → room_changed) or a scene chain (completed → next started)
	# within one frame resolves to one decision instead of a start and an immediate replacement.
	if _retarget_queued:
		return
	_retarget_queued = true
	retarget.call_deferred()


func retarget() -> void:
	_retarget_queued = false
	var want := wanted_theme()
	if want == target_theme:
		return
	target_theme = want
	theme_changed.emit(want)
	if unlocked:
		_switch_to(want, crossfade_s)


# --- Web: first user gesture ----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch:
		unlock()


## Starts the music held back until the AudioContext may play (web: first click or key).
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if target_theme != "":
		_switch_to(target_theme, crossfade_s)


# --- Decks ----------------------------------------------------------------------------

func _other(d: Deck) -> Deck:
	return _decks[1] if d == _decks[0] else _decks[0]


func _fade(d: Deck, to: float, seconds: float) -> void:
	d.fade_from = d.gain
	d.fade_to = to
	d.fade_s = maxf(seconds, 0.001)
	d.fade_t = 0.0
	if seconds <= 0.0:
		d.gain = to
		d.fade_t = d.fade_s


func _start_on(d: Deck, theme: String, fade_in_s: float) -> void:
	d.player.stop()
	d.player.stream_paused = false
	d.paused = false
	d.theme = theme
	d.player.stream = stream_for(theme)
	d.gain = 0.0
	d.handed = false
	d.player.volume_db = SILENCE_DB
	if d.player.stream == null:
		return
	d.starts += 1
	d.player.play(0.0)
	_fade(d, 1.0, fade_in_s)


func _resume(d: Deck) -> void:
	if not d.paused:
		return
	d.paused = false
	var length := d.player.stream.get_length() if d.player.stream != null else 0.0
	if is_loop(d.theme) and length > 0.0 and d.player.get_playback_position() > length - loop_crossfade_s - crossfade_s:
		# Too close to the loop point to fade in cleanly: start the pass over.
		d.player.stream_paused = false
		d.player.play(0.0)
		d.starts += 1
	else:
		d.player.stream_paused = false


func _switch_to(theme: String, fade_s: float) -> void:
	if theme == "" or stream_for(theme) == null:
		for d in _decks:
			if d.player.playing:
				_fade(d, 0.0, fade_s)
		_active = null
		return
	var a := _active
	var from_room := active_events.is_empty()
	if a != null and a.theme == theme and a.alive() and (a.player.playing or from_room):
		_resume(a)
		if a.fade_to < 1.0:
			_fade(a, 1.0, fade_s)
		return
	# The same theme on the other deck — still fading out after a quick there-and-back, or paused
	# (a room theme the player returns to): bring it back instead of restarting it.
	for d in _decks:
		if d != a and d.theme == theme and not d.handed and (d.player.playing or (d.paused and from_room)):
			_resume(d)
			if a != null and a.player.playing:
				_fade(a, 0.0, fade_s)
			_fade(d, 1.0, fade_s)
			_active = d
			return
	var free: Deck = _decks[0] if _decks[0].gain <= _decks[1].gain else _decks[1]
	for d in _decks:
		if not d.alive():
			free = d
			break
	_start_on(free, theme, fade_s)
	var other := _other(free)
	if other.player.playing:
		_fade(other, 0.0, fade_s)
	_active = free


func _on_deck_finished(d: Deck) -> void:
	var t := d.theme
	d.gain = 0.0
	d.fade_to = 0.0
	if t == "" or d != _active:
		return
	if is_loop(t):
		# The loop point was missed (a stall longer than the loop crossfade): start over at once.
		_start_on(d, t, 0.3)
		return
	_active = null
	# A non-looping theme has played out: its track_end events are over.
	_remove_events(func(e): return e["theme"] == t and e["until"] == "track_end")
	_queue_retarget()


func _process(delta: float) -> void:
	var duck_target := duck_dialogue_db if dialogue_active() else 0.0
	duck_db_now = move_toward(duck_db_now, duck_target, absf(duck_dialogue_db) / DUCK_FADE_S * delta)
	for d in _decks:
		_update_fade(d, delta)
	_update_loop()
	_apply_volumes()
	if OS.has_feature("web"):
		_web_state_t -= delta
		if _web_state_t <= 0.0:
			_web_state_t = WEB_STATE_INTERVAL_S
			_publish_web_state()


func _update_fade(d: Deck, delta: float) -> void:
	if d.fade_t < d.fade_s:
		d.fade_t = minf(d.fade_t + delta, d.fade_s)
		var p := d.fade_t / d.fade_s
		# Equal power: a rising sin and a falling cos sum to constant loudness.
		var shape := sin(p * PI * 0.5) if d.fade_to > d.fade_from else 1.0 - cos(p * PI * 0.5)
		d.gain = lerpf(d.fade_from, d.fade_to, shape)
		if d.fade_t >= d.fade_s:
			d.gain = d.fade_to
	if d != _active and d.player.playing and d.fade_to <= 0.0 and d.gain <= 0.0:
		if d.handed or not is_loop(d.theme):
			d.player.stop()  # the outgoing half of a loop pass / a played-out track: nothing to resume
		else:
			d.player.stream_paused = true
			d.paused = true


func _update_loop() -> void:
	var a := _active
	if a == null or a.handed or not a.player.playing or a.player.stream == null:
		return
	var length := a.player.stream.get_length()
	if length <= 0.0:
		return
	var pos := a.player.get_playback_position()
	if is_loop(a.theme):
		if pos >= length - loop_crossfade_s:
			a.handed = true
			var b := _other(a)
			_start_on(b, a.theme, loop_crossfade_s)
			_fade(a, 0.0, maxf(length - pos, 0.05))
			_active = b
			loop_passes += 1
	elif end_fade_s > 0.0 and pos >= length - end_fade_s:
		a.handed = true
		_fade(a, 0.0, maxf(length - pos, 0.05))


func _apply_volumes() -> void:
	for d in _decks:
		if not d.player.playing:
			continue
		d.player.volume_db = deck_volume_db(d)


func deck_volume_db(d: Deck) -> float:
	if d.gain <= 0.0001:
		return SILENCE_DB
	var db := float(themes.get(d.theme, {}).get("volume_db", 0.0)) + linear_to_db(d.gain)
	if not duck_except.has(d.theme):
		db += duck_db_now
	return maxf(db, SILENCE_DB)


## A scene line or option on screen (examine/narration texts outside scenes do not duck).
func dialogue_active() -> bool:
	var b: Dictionary = StoryRunner.current_beat
	if b.is_empty():
		return false
	return String(b.get("type", "")) == "line" or b.has("scene")


# --- Music volume setting ----------------------------------------------------------------

static func volume_to_db(v: float) -> float:
	## Slider 0..1 → bus dB; squared amplitude, closer to perceived loudness than linear (50 % ≈ −12 dB).
	return linear_to_db(v * v) if v > 0.0 else SILENCE_DB


func set_music_volume(v: float, persist: bool = true) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_to_db(music_volume))
		AudioServer.set_bus_mute(idx, music_volume <= 0.0)
	music_volume_changed.emit(music_volume)
	if persist and _save_timer != null and is_inside_tree():
		_save_timer.start(SAVE_DELAY_S)


func load_settings() -> void:
	var v := DEFAULT_VOLUME
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path) and cf.load(settings_path) == OK:
		v = float(cf.get_value("audio", "music_volume", DEFAULT_VOLUME))
	set_music_volume(v, false)


func save_settings() -> bool:
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path):
		cf.load(settings_path)  # keep other settings
	cf.set_value("audio", "music_volume", music_volume)
	var err := cf.save(settings_path)
	if err == OK:
		settings_saves += 1
	else:
		push_error("MusicDirector: cannot save %s (%s)" % [settings_path, error_string(err)])
	return err == OK


# --- State (tests, web probe) ------------------------------------------------------------

func active_deck_index() -> int:
	return _decks.find(_active)


func deck_state(i: int) -> Dictionary:
	var d := _decks[i]
	return {"theme": d.theme, "playing": d.player.playing, "paused": d.paused,
		"position": d.player.get_playback_position() if d.alive() else 0.0,
		"length": d.player.stream.get_length() if d.player.stream != null else 0.0,
		"gain": d.gain, "fade_to": d.fade_to, "volume_db": d.player.volume_db, "starts": d.starts,
		"bus": String(d.player.bus), "playback_type": int(d.player.playback_type)}


func state() -> Dictionary:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	var evs: Array = []
	for e in active_events:
		evs.append(e["key"])
	return {"unlocked": unlocked, "target": target_theme, "room_theme": room_theme, "events": evs,
		"active": _active.theme if _active != null else "", "active_deck": active_deck_index(),
		"duck_db": duck_db_now, "dialogue": dialogue_active(), "loop_passes": loop_passes,
		"music_volume": music_volume, "settings_saves": settings_saves, "bus_volume_db": AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0,
		"bus_mute": AudioServer.is_bus_mute(idx) if idx >= 0 else false,
		"decks": [deck_state(0), deck_state(1)], "output_latency": AudioServer.get_output_latency(),
		"errors": config_errors}


func _publish_web_state() -> void:
	JavaScriptBridge.eval("window.musicState = %s;" % JSON.stringify(state()), true)
