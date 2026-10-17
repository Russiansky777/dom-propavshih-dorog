extends Node
## Autoload `VoiceDirector`: the recorded voice of a scene line (bus Voice), data/story/voice.json.
##
##   - a line beat of StoryRunner carries `line_id` = <scene>_<index> (the index in the scene's
##     mandatory_lines / the quest's lines); when it appears, `<dir>/<line_id>.ogg` plays if the
##     manifest (`<dir>/manifest.json`, copied from assets/voice/ru by tools/sync_voice.sh) lists it,
##     it is not `stale` and its `text_sha1` equals the sha1 of the line on screen — a voice recorded
##     for an older text never plays under a newer subtitle; otherwise the line stays subtitles only;
##   - any beat change (the click «дальше», the scene end, a new game, a load) cuts the voice off;
##     the music ducking (MusicDirector, −duck_dialogue_db while a line is on screen) therefore covers
##     the whole time a voice sounds;
##   - speakers in `pan` whose hotspot (id == speaker) is visible in the current room are played by an
##     AudioStreamPlayer2D placed so its pan is the hotspot's offset from the screen centre (what the
##     player sees), scaled by `panning_strength`; Godot's 2D panner gives 0.5/0.5 at the centre
##     (l = 1 − pan, r = pan), so +6.02 dB brings a centred 2D voice to the level of the plain player;
##   - voice volume (menu «Голос», 0–100 %) — user://settings.cfg [audio] voice_volume, applied to the
##     Voice bus with the same curve as music and sounds (squared amplitude: 50 % ≈ −12 dB);
##   - web: a line shown before the first user gesture waits for MusicDirector.unlocked and starts
##     then if it is still on screen. One-shot voices use the platform default playback (web: Sample —
##     no 0.75 s stream buffer between the subtitle and the voice).
## Checks: tools/validate_voice.py, tests/test_voice.gd, tools/voice_web.mjs.

signal voice_started(line_id: String, speaker: String)
signal voice_stopped(line_id: String, reason: String)
signal voice_volume_changed(volume: float)

const CONFIG_PATH: String = "res://data/story/voice.json"
const BUS_NAME: String = "Voice"
const DEFAULT_DIR: String = "res://assets/voice/ru"
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_VOLUME: float = 1.0
const SILENCE_DB: float = -80.0
const SAVE_DELAY_S: float = 0.5
const MAX_EVENTS: int = 64
const WEB_STATE_INTERVAL_S: float = 0.25
## AudioStreamPlayer2D at the listener: AudioFrame(0.5, 0.5); ×2 (+6.02 dB) = AudioStreamPlayer's (1, 1).
const PAN_CENTRE_COMPENSATION_DB: float = 6.0206

# --- Data (voice.json, manifest) ---
var voice_dir: String = DEFAULT_DIR
var volume_db: float = 0.0
var pan_cfg: Dictionary = {}          # speaker -> {panning_strength}
var manifest: Dictionary = {}         # line id -> manifest entry
var config_errors: Array[String] = []

# --- State ---
var voice_volume: float = DEFAULT_VOLUME
var settings_path: String = DEFAULT_SETTINGS_PATH
var current_line: String = ""
var current_speaker: String = ""
var current_mode: String = ""         # "plain" | "panned"
var current_pan: float = 0.0          # the 2D panner's offset −0.5..0.5 (0 = centre) of the panned player
var plays: int = 0
var settings_saves: int = 0
var events: Array[Dictionary] = []    # {kind, line, speaker, reason?, mode?, ms}

var _streams: Dictionary = {}         # line id -> AudioStream (loaded on first use)
var _test_streams: Dictionary = {}    # line id -> AudioStream (tests: no file, no manifest check)
var _plain: AudioStreamPlayer
var _panned: AudioStreamPlayer2D
var _pan_source: Vector2 = Vector2.ZERO
var _pending: String = ""             # line waiting for the web audio unlock
var _save_timer: Timer
var _web_state_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	reload_config()
	_plain = AudioStreamPlayer.new()
	_plain.name = "Voice"
	_plain.bus = BUS_NAME
	add_child(_plain)
	_plain.finished.connect(_on_finished.bind("plain"))
	_panned = AudioStreamPlayer2D.new()
	_panned.name = "VoicePanned"
	_panned.bus = BUS_NAME
	_panned.attenuation = 0.0         # no distance loss: only the pan says where he is
	_panned.max_distance = 100000.0
	add_child(_panned)
	_panned.finished.connect(_on_finished.bind("panned"))
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	load_settings()
	StoryRunner.beat_changed.connect(_on_beat_changed)
	GameState.state_reset.connect(func(): stop("reset"))
	GameState.state_loaded.connect(func(_slot): stop("load"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _save_timer != null and not _save_timer.is_stopped():
			_save_timer.stop()
			save_settings()


func _ensure_bus() -> void:
	# default_bus_layout.tres declares it; this keeps the game working if the layout is missing.
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


# --- Configuration ----------------------------------------------------------------------

func reload_config() -> void:
	config_errors.clear()
	var data: Dictionary = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			data = parsed
		else:
			config_errors.append(CONFIG_PATH + " is not a JSON object")
	else:
		config_errors.append("missing " + CONFIG_PATH)
	voice_dir = String(data.get("dir", DEFAULT_DIR)).trim_suffix("/")
	volume_db = float(data.get("volume_db", 0.0))
	pan_cfg = {}
	for k in data.get("pan", {}).keys():
		if not String(k).begins_with("_"):
			pan_cfg[String(k)] = data["pan"][k]
	manifest = {}
	var mpath := voice_dir + "/manifest.json"
	if FileAccess.file_exists(mpath):
		var m = JSON.parse_string(FileAccess.get_file_as_string(mpath))
		if m is Dictionary:
			manifest = m.get("lines", {})
		else:
			config_errors.append(mpath + " is not a JSON object")
	# No manifest is not an error: before the first recording every line is subtitles only.
	_streams.clear()
	for e in config_errors:
		push_error("VoiceDirector: " + e)


## Test hook: a stream for `line_id` without a file or a manifest entry (null removes it).
func set_test_stream(line_id: String, stream: AudioStream) -> void:
	if stream == null:
		_test_streams.erase(line_id)
	else:
		_test_streams[line_id] = stream


## Why `line_id` with `text` would or would not sound: "ok" | "no_entry" | "stale" | "text_changed" | "no_file".
func line_status(line_id: String, text: String) -> String:
	if _test_streams.has(line_id):
		return "ok"
	var e: Dictionary = manifest.get(line_id, {})
	if e.is_empty():
		return "no_entry"
	if e.has("stale"):
		return "stale"
	if String(e.get("text_sha1", "")) != text.sha1_text():
		return "text_changed"
	if not ResourceLoader.exists(file_path(line_id)):
		return "no_file"
	return "ok"


func file_path(line_id: String) -> String:
	var e: Dictionary = manifest.get(line_id, {})
	return "%s/%s" % [voice_dir, String(e.get("file", line_id + ".ogg"))]


func stream_for(line_id: String, text: String) -> AudioStream:
	if _test_streams.has(line_id):
		return _test_streams[line_id]
	if line_status(line_id, text) != "ok":
		return null
	if not _streams.has(line_id):
		var s := load(file_path(line_id)) as AudioStream
		if s != null and "loop" in s:
			s.set("loop", false)
		_streams[line_id] = s
	return _streams[line_id]


# --- Playback -----------------------------------------------------------------------------

func _on_beat_changed() -> void:
	var b: Dictionary = StoryRunner.current_beat
	var lid := String(b.get("line_id", "")) if String(b.get("type", "")) == "line" else ""
	if lid != "" and lid == current_line and is_playing():
		return  # the same beat announced again
	_pending = ""
	if is_playing():
		stop("advance")
	if lid == "":
		return
	play_line(lid, String(b.get("speaker", "")), String(b.get("text", "")))


## Starts the voice of a line; returns "playing" | "waiting" (web, before the first click) or line_status().
func play_line(line_id: String, speaker: String, text: String) -> String:
	var st := line_status(line_id, text)
	if st != "ok":
		_event({"kind": "subtitles_only", "line": line_id, "speaker": speaker, "reason": st})
		if st == "text_changed" or st == "stale":
			push_warning("VoiceDirector: %s is recorded for another text (%s) — subtitles only" % [line_id, st])
		return st
	if not _audio_ready():
		_pending = line_id
		_event({"kind": "waiting", "line": line_id, "speaker": speaker})
		return "waiting"
	var s := stream_for(line_id, text)
	if s == null:
		return "no_file"
	_plain.stop()
	_panned.stop()
	current_line = line_id
	current_speaker = speaker
	var src := _speaker_source(speaker)
	if src != null:
		current_mode = "panned"
		_pan_source = src.global_position
		_place_panned()
		_panned.panning_strength = float(pan_cfg[speaker].get("panning_strength", 1.0))
		_panned.volume_db = volume_db + PAN_CENTRE_COMPENSATION_DB
		_panned.stream = s
		_panned.play()
		current_pan = expected_pan()
	else:
		current_mode = "plain"
		current_pan = 0.0
		_plain.volume_db = volume_db
		_plain.stream = s
		_plain.play()
	plays += 1
	_event({"kind": "start", "line": line_id, "speaker": speaker, "mode": current_mode, "pan": current_pan})
	voice_started.emit(line_id, speaker)
	_publish_web_state()
	return "playing"


func stop(reason: String = "stop") -> void:
	_pending = ""
	if not is_playing():
		return
	var lid := current_line
	_plain.stop()
	_panned.stop()
	_event({"kind": "stop", "line": lid, "speaker": current_speaker, "reason": reason})
	current_line = ""
	current_speaker = ""
	current_mode = ""
	voice_stopped.emit(lid, reason)
	_publish_web_state()


func is_playing() -> bool:
	return _plain.playing or _panned.playing


func _on_finished(which: String) -> void:
	if which != current_mode:
		return
	var lid := current_line
	_event({"kind": "finished", "line": lid, "speaker": current_speaker})
	current_line = ""
	current_speaker = ""
	current_mode = ""
	voice_stopped.emit(lid, "finished")
	_publish_web_state()


## The speaker's hotspot in the current room (id == speaker id), if he pans and is visible there.
func _speaker_source(speaker: String) -> Node2D:
	if not pan_cfg.has(speaker):
		return null
	var room = RoomManager.current_room
	if room == null or not is_instance_valid(room) or not room.has_method("get_hotspots"):
		return null
	for h in room.get_hotspots():
		if h.hotspot_id == speaker and h.is_visible_in_tree():
			return h
	return null


func _view_centre() -> Vector2:
	var vp := get_viewport()
	var r := vp.get_visible_rect()
	return vp.get_canvas_transform().affine_inverse() * (r.size * 0.5)


## The 2D player sits at listener + (source − screen centre): Godot pans by the offset from the
## listener (Agata — SfxDirector's AudioListener2D, the stove fire's reference), the voice should
## come from where he is on screen.
func _place_panned() -> void:
	var lis := get_viewport().get_audio_listener_2d()
	var base := lis.global_position if lis != null else _view_centre()
	_panned.global_position = base + (_pan_source - _view_centre())


## Godot's 2D panner for the current source: −0.5 (all left) .. 0.5 (all right), 0 = centre.
func expected_pan() -> float:
	var w := get_viewport().get_visible_rect().size.x
	if w <= 0.0:
		return 0.0
	var p := clampf((_pan_source.x - _view_centre().x) / w, -1.0, 1.0)
	p *= _panned.panning_strength * float(ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5)) * 0.5
	return clampf(p + 0.5, 0.0, 1.0) - 0.5


func _audio_ready() -> bool:
	var md := get_node_or_null("/root/MusicDirector")
	return md == null or bool(md.get("unlocked"))


func _process(delta: float) -> void:
	if _pending != "" and _audio_ready():
		var b: Dictionary = StoryRunner.current_beat
		var lid := _pending
		_pending = ""
		if String(b.get("line_id", "")) == lid:
			play_line(lid, String(b.get("speaker", "")), String(b.get("text", "")))
	if current_mode == "panned" and _panned.playing:
		_place_panned()   # the listener follows Agata
	if OS.has_feature("web"):
		_web_state_t -= delta
		if _web_state_t <= 0.0:
			_web_state_t = WEB_STATE_INTERVAL_S
			_publish_web_state()


func _event(ev: Dictionary) -> void:
	ev["ms"] = Time.get_ticks_msec()
	events.append(ev)
	if events.size() > MAX_EVENTS:
		events.pop_front()


# --- Voice volume setting -------------------------------------------------------------------

static func volume_to_db(v: float) -> float:
	## Same curve as the music and sound sliders (squared amplitude: 50 % ≈ −12 dB).
	return linear_to_db(v * v) if v > 0.0 else SILENCE_DB


func set_voice_volume(v: float, persist: bool = true) -> void:
	voice_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_to_db(voice_volume))
		AudioServer.set_bus_mute(idx, voice_volume <= 0.0)
	voice_volume_changed.emit(voice_volume)
	if persist and _save_timer != null and is_inside_tree():
		_save_timer.start(SAVE_DELAY_S)


func load_settings() -> void:
	var v := DEFAULT_VOLUME
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path) and cf.load(settings_path) == OK:
		v = float(cf.get_value("audio", "voice_volume", DEFAULT_VOLUME))
	set_voice_volume(v, false)


func save_settings() -> bool:
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path):
		cf.load(settings_path)  # keep the music and sound volumes
	cf.set_value("audio", "voice_volume", voice_volume)
	var err := cf.save(settings_path)
	if err == OK:
		settings_saves += 1
	else:
		push_error("VoiceDirector: cannot save %s (%s)" % [settings_path, error_string(err)])
	return err == OK


# --- State (tests, web probe) ---------------------------------------------------------------

func state() -> Dictionary:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	var p: Node = _panned if current_mode == "panned" else _plain
	var pos := 0.0
	var length := 0.0
	if is_playing():
		pos = p.get_playback_position()
		var s: AudioStream = p.get("stream")
		length = s.get_length() if s != null else 0.0
	return {"line": current_line, "speaker": current_speaker, "playing": is_playing(), "mode": current_mode,
		"pan": current_pan, "position": pos, "length": length, "plays": plays, "pending": _pending,
		"voice_volume": voice_volume, "settings_saves": settings_saves,
		"bus_volume_db": AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0,
		"bus_mute": AudioServer.is_bus_mute(idx) if idx >= 0 else false,
		"manifest_lines": manifest.size(), "events": events.slice(maxi(0, events.size() - 12)),
		"errors": config_errors}


func _publish_web_state() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.voiceState = %s;" % JSON.stringify(state()), true)
