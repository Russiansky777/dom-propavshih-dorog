extends Node
## Autoload `SfxDirector`: sound effects and ambience driven by data/story/sfx.json (bus SFX).
##
##   - footsteps: on the walk sheet's foot-plant frames — the same contact frames and planted-foot
##     point that AmbientFootfall uses for splashes and prints (data/story/ambient/_index.json
##     footfall.<actor>), so a step sounds when the foot lands; the surface comes from the room
##     (`steps.rooms`) or a polygon in it (`steps.areas`); a random take (never the same twice in a
##     row) with a little pitch and volume spread;
##   - doors: an exit «FROM>TO» listed in `doors` plays its sound once per transition, when the new
##     room appears; the player belongs to this autoload, so the sound runs on through the room
##     change. Loading a save or a new game opens no door;
##   - bag: game_ui.gd `bag_sound_requested(kind)` → `bag.<kind>`;
##   - stove fire (`loops.stove_fire`): a loop at the stove mouth in H1 while its flags hold
##     (stove_lit), louder the closer Agata is (own distance curve), panned from her (AudioListener2D
##     follows her);
##   - rain (`loops.rain`): a loop in the drizzle rooms; inside the house and the post office it is
##     quieter and low-passed (bus SFX_Inside → SFX); elsewhere (the winter school) — none.
## Loops wait for the web audio unlock (MusicDirector.unlocked: first click) and use STREAM playback
## (bus effect, continuous gain); one-shots use the platform default (web: Sample — no 0.7 s stream
## buffer between a foot and its sound). Sound volume (menu «Звуки», 0–100 %) — user://settings.cfg
## [audio] sfx_volume, applied to the SFX bus. Checks: tools/validate_sfx.py, tests/test_sfx.gd.

signal sound_played(kind: String, sound_id: String, file: String)
signal sfx_volume_changed(volume: float)

const CONFIG_PATH: String = "res://data/story/sfx.json"
const SFX_DIR: String = "res://assets/sfx"
const BUS_NAME: String = "SFX"
const INSIDE_BUS: String = "SFX_Inside"
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_VOLUME: float = 1.0
const STEP_VOICES: int = 4
const SILENCE_DB: float = -80.0
const SAVE_DELAY_S: float = 0.5
const MAX_EVENTS: int = 64
const WEB_STATE_INTERVAL_S: float = 0.25

# --- Data (sfx.json) ---
var sounds: Dictionary = {}
var steps_cfg: Dictionary = {}
var doors: Dictionary = {}
var bag_map: Dictionary = {}
var loops: Dictionary = {}
var config_errors: Array[String] = []

# --- State ---
var current_room: String = ""
var sfx_volume: float = DEFAULT_VOLUME
var settings_path: String = DEFAULT_SETTINGS_PATH
var step_count: int = 0
var events: Array[Dictionary] = []   # last sounds: {kind, sound, file, room, surface?, frame?, pos?, ms}
var fire_gain_db: float = SILENCE_DB # target from the distance curve (tests)

var _suppress_door: bool = true      # the first room (boot / load / new game) opens no door
var _streams: Dictionary = {}        # file -> AudioStream
var _last_take: Dictionary = {}      # sound id -> last file index
var _rng := RandomNumberGenerator.new()
var _step_players: Array[AudioStreamPlayer] = []
var _step_i: int = 0
var _door_player: AudioStreamPlayer
var _bag_player: AudioStreamPlayer
var _closeup_player: AudioStreamPlayer
var _fire: AudioStreamPlayer2D
var _fire_gain: float = 0.0          # fade envelope 0..1
var _rain: AudioStreamPlayer
var _rain_gain: float = 0.0          # fade envelope 0..1
var _rain_mode: String = ""          # "outside" | "inside" | ""
var _listener: AudioListener2D
var _save_timer: Timer
var _web_state_t: float = 0.0

# Footsteps (bound to the player's sprite like AmbientFootfall; that file is not touched).
var _player: Node2D = null
var _sprite: AnimatedSprite2D = null
var _walk_action: String = "walk"
var _contact_frames: Array[int] = []
var _planted_foot_px: Array = []
var _last_frame: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	reload_config()
	_ensure_buses()
	for i in STEP_VOICES:
		_step_players.append(_one_shot_player("Step%d" % i))
	_door_player = _one_shot_player("Door")
	_bag_player = _one_shot_player("Bag")
	_closeup_player = _one_shot_player("Closeup")
	_listener = AudioListener2D.new()
	_listener.name = "Listener"
	add_child(_listener)
	_listener.make_current()
	_fire = AudioStreamPlayer2D.new()
	_fire.name = "StoveFire"
	_fire.bus = BUS_NAME
	_fire.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_fire.attenuation = 0.0          # loudness by distance is ours (fire_gain_db); Godot only pans
	_fire.max_distance = 100000.0
	_fire.volume_db = SILENCE_DB
	add_child(_fire)
	_rain = AudioStreamPlayer.new()
	_rain.name = "Rain"
	_rain.bus = BUS_NAME
	_rain.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_rain.volume_db = SILENCE_DB
	add_child(_rain)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	load_settings()
	RoomManager.room_changed.connect(_on_room_changed)
	StoryRunner.stage_sound_requested.connect(func(sid: String): play_sound(sid, "stage"))
	StoryRunner.synth_sound_requested.connect(play_synth)
	GameState.state_reset.connect(func(): _suppress_door = true)
	GameState.state_loaded.connect(func(_s): _suppress_door = true)
	get_tree().node_added.connect(_on_node_added)
	_connect_bag_sources(get_tree().root)
	if RoomManager.current_room != null and is_instance_valid(RoomManager.current_room):
		_on_room_changed(RoomManager.current_room.room_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _save_timer != null and not _save_timer.is_stopped():
			_save_timer.stop()
			save_settings()


func _one_shot_player(player_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = player_name
	p.bus = BUS_NAME
	add_child(p)
	return p


# --- Configuration ---------------------------------------------------------------------

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
	sounds = data.get("sounds", {})
	steps_cfg = data.get("steps", {})
	doors = _strip_comments(data.get("doors", {}))
	bag_map = _strip_comments(data.get("bag", {}))
	loops = data.get("loops", {})
	_streams.clear()
	for e in config_errors:
		push_error("SfxDirector: " + e)


static func _strip_comments(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		if not String(k).begins_with("_"):
			out[k] = d[k]
	return out


func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var idx := AudioServer.get_bus_index(INSIDE_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, INSIDE_BUS)
		AudioServer.set_bus_send(idx, BUS_NAME)
	var lp: AudioEffectLowPassFilter = null
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
			lp = AudioServer.get_bus_effect(idx, i)
	if lp == null:
		lp = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(idx, lp)
	lp.cutoff_hz = float(loops.get("rain", {}).get("inside_lowpass_hz", 900.0))


func stream_for(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var path := "%s/%s" % [SFX_DIR, file]
	var s: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	if s == null:
		push_error("SfxDirector: missing sound %s" % path)
	_streams[file] = s
	return s


# --- One-shots ---------------------------------------------------------------------------

## Plays one take of `sound_id` on `player`; returns the file played ("" if none).
func _play(player: AudioStreamPlayer, sound_id: String, kind: String, extra: Dictionary = {}) -> String:
	var spec: Dictionary = sounds.get(sound_id, {})
	var files: Array = spec.get("files", [])
	if files.is_empty():
		return ""
	var i := 0
	if files.size() > 1:
		i = _rng.randi_range(0, files.size() - 2)
		if i >= int(_last_take.get(sound_id, -1)):
			i += 1   # never the same take twice in a row
	_last_take[sound_id] = i
	var file := String(files[i])
	var s := stream_for(file)
	if s == null:
		return ""
	var pj := float(spec.get("pitch_jitter", 0.0))
	var vj := float(spec.get("volume_jitter_db", 0.0))
	player.stop()
	player.stream = s
	player.pitch_scale = 1.0 + (_rng.randf_range(-pj, pj) if pj > 0.0 else 0.0)
	player.volume_db = float(spec.get("volume_db", 0.0)) + (_rng.randf_range(-vj, vj) if vj > 0.0 else 0.0)
	player.play()
	var ev := {"kind": kind, "sound": sound_id, "file": file, "room": current_room, "ms": Time.get_ticks_msec(),
		"pitch": player.pitch_scale, "volume_db": player.volume_db}
	ev.merge(extra)
	events.append(ev)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	sound_played.emit(kind, sound_id, file)
	return file


func play_door(from_room: String, to_room: String) -> String:
	var sid := String(doors.get("%s>%s" % [from_room, to_room], ""))
	if sid == "":
		return ""
	return _play(_door_player, sid, "door", {"exit": "%s>%s" % [from_room, to_room]})


func play_bag(kind: String) -> String:
	var sid := String(bag_map.get(kind, ""))
	if sid == "":
		push_warning("SfxDirector: no bag sound for kind '%s' (sfx.json bag)" % kind)
		return ""
	return _play(_bag_player, sid, "bag", {"bag_kind": kind})


## A sound of sfx.json `sounds` by id for a close-up action (rooms data puzzle `sounds`: hinge taken,
## seated, returned; threshold moved; door closed). Unknown id: a warning, no sound.
func play_sound(sound_id: String, kind: String = "closeup") -> String:
	if not sounds.has(sound_id):
		push_warning("SfxDirector: no sound '%s' (sfx.json sounds)" % sound_id)
		return ""
	return _play(_closeup_player, sound_id, kind)


## A sound the engine makes (SynthSfx, the same as the close-ups: the mill bell rung in the room) on the
## close-up player, SFX bus.
func play_synth(sound_name: String) -> void:
	var synth = load("res://scripts/mechanics/synth_sfx.gd")
	_closeup_player.stream = synth.stream(sound_name)
	_closeup_player.play()
	sound_played.emit("synth", sound_name, "")


## The next room change opens no door (a scene staging moves Agata in the dark: the night by the stove).
func suppress_next_door() -> void:
	_suppress_door = true


func _on_node_added(n: Node) -> void:
	if n.has_signal("bag_sound_requested"):
		_connect_bag(n)


func _connect_bag_sources(n: Node) -> void:
	if n.has_signal("bag_sound_requested"):
		_connect_bag(n)
	for c in n.get_children():
		_connect_bag_sources(c)


func _connect_bag(n: Node) -> void:
	if not n.is_connected("bag_sound_requested", play_bag):
		n.connect("bag_sound_requested", play_bag)


# --- Rooms ------------------------------------------------------------------------------------

func _on_room_changed(room_id: String) -> void:
	var from := current_room
	current_room = room_id
	if _suppress_door:
		_suppress_door = false
	elif from != "" and from != room_id:
		play_door(from, room_id)
	_update_rain_mode()


func rain_mode_for(room_id: String) -> String:
	var r: Dictionary = loops.get("rain", {})
	if r.get("outside", []).has(room_id):
		return "outside"
	if r.get("inside", []).has(room_id):
		return "inside"
	return ""


func _update_rain_mode() -> void:
	var mode := rain_mode_for(current_room)
	if mode == _rain_mode:
		return
	_rain_mode = mode
	if mode != "":
		# Inside: the same rain through the wall — quieter and low-passed (switched with the room).
		_rain.bus = INSIDE_BUS if mode == "inside" else BUS_NAME


func surface_at(room_id: String, pos: Vector2) -> String:
	for a in steps_cfg.get("areas", {}).get(room_id, []):
		var pts := PackedVector2Array()
		for p in a.get("poly", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(pos, pts):
			return String(a.get("surface", ""))
	return String(steps_cfg.get("rooms", {}).get(room_id, steps_cfg.get("default_surface", "")))


# --- Footsteps --------------------------------------------------------------------------------

func _bind_player() -> void:
	var pv: Variant = RoomManager.player
	if pv == null or not is_instance_valid(pv) or not (pv is Node2D):
		return
	var p: Node2D = pv
	var spr := p.get("sprite") as AnimatedSprite2D
	var sheet = p.get("sheet")
	if spr == null or sheet == null:
		return
	var actor := String(p.get("actor_id")) if p.get("actor_id") != null else "agata"
	var ff: Dictionary = AmbientData.footfall(actor)
	if ff.is_empty():
		return
	_contact_frames.clear()
	for f in ff.get("contact_frames", []):
		_contact_frames.append(int(f))
	_planted_foot_px = ff.get("planted_foot_px", [])
	_walk_action = String(sheet.get("walk_action")) if sheet.get("walk_action") != null else "walk"
	_player = p
	_sprite = spr
	_last_frame = spr.frame
	spr.frame_changed.connect(_on_frame_changed)


func _on_frame_changed() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var f := _sprite.frame
	if f == _last_frame:
		return   # the same frame replayed (direction switch keeps the stride phase): not a new step
	_last_frame = f
	if not _player.has_method("is_walking") or not _player.call("is_walking"):
		return
	if not String(_sprite.animation).begins_with(_walk_action):
		return
	var k := _contact_frames.find(f)
	if k < 0:
		return
	var pos := _foot_position(k)
	var surface := surface_at(current_room, pos)
	var sid := String(steps_cfg.get("surfaces", {}).get(surface, ""))
	step_count += 1
	if sid != "":
		_play(_step_players[_step_i], sid, "step", {"surface": surface, "frame": f, "pos": pos})
		_step_i = (_step_i + 1) % _step_players.size()


## The planted foot: drawn feet + that foot's measured offset in the current direction row.
func _foot_position(k: int) -> Vector2:
	var base: Vector2 = _player.call("drawn_position") if _player.has_method("drawn_position") else _player.global_position
	var s := absf(_player.scale.y)
	var row := int(_player.get("direction")) if _player.get("direction") != null else 0
	if row >= 0 and row < _planted_foot_px.size() and k < _planted_foot_px[row].size():
		var o: Array = _planted_foot_px[row][k]
		return base + Vector2(float(o[0]), float(o[1])) * s
	return base


# --- Loops -------------------------------------------------------------------------------------

func _audio_ready() -> bool:
	var md := get_node_or_null("/root/MusicDirector")
	return md == null or bool(md.get("unlocked"))


func fire_should_play() -> bool:
	var f: Dictionary = loops.get("stove_fire", {})
	if f.is_empty() or current_room != String(f.get("room", "")):
		return false
	for fl in f.get("if", []):
		if not GameState.has_flag(String(fl)):
			return false
	return true


## Fire loudness at distance `d` px from the stove: 0 dB within near_px, far_db at far_px and beyond.
func fire_distance_db(d: float) -> float:
	var f: Dictionary = loops.get("stove_fire", {})
	var near := float(f.get("near_px", 250.0))
	var far := float(f.get("far_px", 1500.0))
	var t := clampf((d - near) / maxf(far - near, 1.0), 0.0, 1.0)
	return float(f.get("volume_db", 0.0)) + lerpf(0.0, float(f.get("far_db", -12.0)), t)


func _process(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite) or _player == null or not is_instance_valid(_player):
		_sprite = null
		_player = null
		_bind_player()
	var audio_ok := _audio_ready()
	if _player != null:
		_listener.global_position = _player.global_position
	# Stove fire.
	var f: Dictionary = loops.get("stove_fire", {})
	if not f.is_empty():
		var want := audio_ok and fire_should_play()
		var fade_s := maxf(float(f.get("fade_s", 1.0)), 0.05)
		_fire_gain = move_toward(_fire_gain, 1.0 if want else 0.0, delta / fade_s)
		if want and not _fire.playing:
			_fire.stream = stream_for(String(f.get("file", "")))
			_fire.global_position = Vector2(float(f["pos"][0]), float(f["pos"][1]))
			_fire.play()
		var d := _player.global_position.distance_to(_fire.global_position) if _player != null else 1e9
		fire_gain_db = fire_distance_db(d)
		if _fire.playing:
			_fire.volume_db = maxf(fire_gain_db + linear_to_db(maxf(_fire_gain, 0.0001)), SILENCE_DB)
			if _fire_gain <= 0.0 and not want:
				_fire.stop()
	# Rain.
	var r: Dictionary = loops.get("rain", {})
	if not r.is_empty():
		var want_r := audio_ok and _rain_mode != ""
		_rain_gain = move_toward(_rain_gain, 1.0 if want_r else 0.0, delta / maxf(float(r.get("fade_s", 1.0)), 0.05))
		if want_r and not _rain.playing:
			_rain.stream = stream_for(String(r.get("file", "")))
			_rain.play()
		if _rain.playing:
			var base := float(r.get("inside_db" if _rain_mode == "inside" else "outside_db", 0.0))
			_rain.volume_db = maxf(base + linear_to_db(maxf(_rain_gain, 0.0001)), SILENCE_DB)
			if _rain_gain <= 0.0 and not want_r:
				_rain.stop()
	if OS.has_feature("web"):
		_web_state_t -= delta
		if _web_state_t <= 0.0:
			_web_state_t = WEB_STATE_INTERVAL_S
			JavaScriptBridge.eval("window.sfxState = %s;" % JSON.stringify(state()), true)


# --- Sound volume setting -----------------------------------------------------------------------

func set_sfx_volume(v: float, persist: bool = true) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_to_db(sfx_volume))
		AudioServer.set_bus_mute(idx, sfx_volume <= 0.0)
	sfx_volume_changed.emit(sfx_volume)
	if persist and _save_timer != null and is_inside_tree():
		_save_timer.start(SAVE_DELAY_S)


static func volume_to_db(v: float) -> float:
	## Same curve as the music slider (squared amplitude: 50 % ≈ −12 dB).
	return linear_to_db(v * v) if v > 0.0 else SILENCE_DB


func load_settings() -> void:
	var v := DEFAULT_VOLUME
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path) and cf.load(settings_path) == OK:
		v = float(cf.get_value("audio", "sfx_volume", DEFAULT_VOLUME))
	set_sfx_volume(v, false)


func save_settings() -> bool:
	var cf := ConfigFile.new()
	if FileAccess.file_exists(settings_path):
		cf.load(settings_path)  # keep the music volume and anything else
	cf.set_value("audio", "sfx_volume", sfx_volume)
	var err := cf.save(settings_path)
	if err != OK:
		push_error("SfxDirector: cannot save %s (%s)" % [settings_path, error_string(err)])
	return err == OK


# --- State (tests, web probe) -------------------------------------------------------------------

func state() -> Dictionary:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	var last: Array = events.slice(maxi(0, events.size() - 12))
	var light: Array = []
	for e in last:
		light.append({"kind": e["kind"], "sound": e["sound"], "file": e["file"], "room": e["room"],
			"surface": e.get("surface", ""), "frame": e.get("frame", -1), "exit": e.get("exit", ""), "ms": e["ms"]})
	var counts := {}
	for e in events:
		var key := "%s:%s" % [e["kind"], e.get("exit", e.get("surface", e["sound"]))]
		counts[key] = int(counts.get(key, 0)) + 1
	return {"room": current_room, "steps": step_count, "events": light, "counts": counts, "sfx_volume": sfx_volume,
		"bus_volume_db": AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0,
		"fire": {"playing": _fire.playing, "volume_db": _fire.volume_db, "distance_db": fire_gain_db},
		"rain": {"playing": _rain.playing, "mode": _rain_mode, "bus": String(_rain.bus), "volume_db": _rain.volume_db},
		"errors": config_errors}
