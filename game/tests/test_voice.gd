extends SceneTree
## Headless test of the recorded voice (VoiceDirector, data/story/voice.json, assets/voice/ru → game/assets/voice/ru).
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_voice.gd
## The Dummy driver mixes in real time: players play, positions advance, streams finish, bus effects
## (AudioEffectCapture) receive frames. Behind it — the Director's task of 17.10 «озвучка реплик»:
##   - every manifest line loads, belongs to a real scene line with the same text (sha1) and is ≥ 0.2 s;
##   - a scene line with a file starts its voice on the Voice bus (line_id <scene>_<index> from the beat);
##     the music stays ducked while the voice sounds;
##   - the click «дальше» cuts the voice off and starts the next line's voice; the last click of a
##     scene stops it; a new game / a load stops it;
##   - a line without a file (or recorded for another text) stays subtitles only, without errors;
##   - voice volume: setting → Voice bus, user:// settings (not the save slot), menu slider «Голос», 0 % mutes;
##   - Tikhon (voice.json pan) speaks from his hotspot in H1: panned to the left, left channel louder;
##     Agata in the same room is not panned;
##   - web gating: a line shown before the first click waits and starts on the unlock.
## Exit code 0 only when every check passed.

const TEST_SETTINGS := "user://test_voice_settings.cfg"
const SLOT := "test_voice"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var md: Node = null
var vd: Node = null
var main_node: Node = null
var _saved_settings_path: String = ""
var _saved_volume: float = 1.0
var _test_tone: AudioStreamWAV = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
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
	md = root.get_node("MusicDirector")
	vd = root.get_node("VoiceDirector")
	_saved_settings_path = vd.settings_path
	_saved_volume = vd.voice_volume
	vd.settings_path = TEST_SETTINGS
	_delete(TEST_SETTINGS)
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	print("audio driver: %s, mix %d Hz; manifest lines: %d" % [AudioServer.get_driver_name(), AudioServer.get_mix_rate(), vd.manifest.size()])
	await _test("voice.json + manifest: Voice bus, every recorded line loads and matches its scene line (sha1)", _test_manifest)
	await _test("A line with a file plays on the Voice bus (beat line_id); music ducked while it sounds", _test_plays)
	await _test("Click «дальше» cuts the voice and starts the next one; scene end, new game and load stop it", _test_cut)
	await _test("No file / another text: subtitles only, no voice, no errors", _test_subtitles_only)
	await _test("Voice volume: setting → Voice bus, user:// settings (not the save slot), menu slider «Голос», 0 % mutes", _test_volume)
	await _test("Tikhon speaks from his hotspot in H1 (panned left, left channel louder); Agata not panned", _test_pan)
	await _test("Web gating: a line before the first click waits, starts on the unlock", _test_gating)
	vd.stop("test end")
	gs.reset()
	gs.delete_save(SLOT)
	_delete(TEST_SETTINGS)
	vd.settings_path = _saved_settings_path
	vd.set_voice_volume(_saved_volume, false)
	vd.reload_config()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== voice: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _enter(room: String) -> void:
	vd.stop("test")
	sr.call("_on_state_reset")
	rm.change_room(room, "")
	await _frames(3)


func _finish_dialogue() -> void:
	for i in 40:
		if sr.current_beat.is_empty():
			return
		if String(sr.current_beat.get("type", "")) == "options":
			var opts: Array = sr.current_options()
			sr.choose(String(opts[0]["id"]))
		else:
			sr.advance()
		await _frames(2)


## The scene line `line_id` as data/story has it: {speaker, text} or {}.
func _line(line_id: String) -> Dictionary:
	var k := line_id.rfind("_")
	var sc: Dictionary = sd.scene(line_id.substr(0, k))
	var lines: Array = sc.get("mandatory_lines", [])
	var i := int(line_id.substr(k + 1))
	return lines[i] if i >= 0 and i < lines.size() else {}


## A 4 s tone for lines that have no recording yet (the checks then test the director, not the file).
func _tone() -> AudioStreamWAV:
	if _test_tone == null:
		var rate := 22050
		var n := rate * 4
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			data.encode_s16(i * 2, int(sin(TAU * 220.0 * float(i) / rate) * 9000.0))
		_test_tone = AudioStreamWAV.new()
		_test_tone.format = AudioStreamWAV.FORMAT_16_BITS
		_test_tone.mix_rate = rate
		_test_tone.stereo = false
		_test_tone.data = data
	return _test_tone


## Real recording if the manifest has a valid one, else the test tone (reported once per line).
func _ensure_voice(line_id: String) -> bool:
	var ln := _line(line_id)
	if vd.line_status(line_id, String(ln.get("text", ""))) == "ok":
		return true
	print("        (note: %s has no recording here — test tone)" % line_id)
	vd.set_test_stream(line_id, _tone())
	return false


func _last_event(kind: String) -> Dictionary:
	for i in range(vd.events.size() - 1, -1, -1):
		if String(vd.events[i].get("kind", "")) == kind:
			return vd.events[i]
	return {}


func _voice_player() -> Node:
	return vd.get_node("VoicePanned") if vd.current_mode == "panned" else vd.get_node("Voice")


# --- Tests ---------------------------------------------------------------------------------

func _test_manifest() -> void:
	_check(vd.config_errors.is_empty(), "voice.json/manifest errors: %s" % [vd.config_errors])
	_check(AudioServer.get_bus_index("Voice") >= 0, "bus Voice must exist")
	_check((vd.get_node("Voice") as AudioStreamPlayer).bus == &"Voice" and (vd.get_node("VoicePanned") as AudioStreamPlayer2D).bus == &"Voice",
		"both voice players on the Voice bus")
	if vd.manifest.is_empty():
		print("        (note: no recordings in game/assets/voice/ru — every line is subtitles only)")
	for lid in vd.manifest.keys():
		var e: Dictionary = vd.manifest[lid]
		if e.has("stale"):
			continue
		var ln := _line(String(lid))
		_check(not ln.is_empty(), "%s: no such scene line" % lid)
		if ln.is_empty():
			continue
		_check(String(ln.get("speaker", "")) == String(e.get("speaker", "")), "%s: speaker %s vs manifest %s" % [lid, ln.get("speaker"), e.get("speaker")])
		_check(vd.line_status(String(lid), String(ln["text"])) == "ok", "%s: status %s" % [lid, vd.line_status(String(lid), String(ln["text"]))])
		var s: AudioStream = vd.stream_for(String(lid), String(ln["text"]))
		_check(s != null and s.get_length() > 0.2, "%s: stream %s does not load or is too short" % [lid, vd.file_path(String(lid))])
		if s != null and "loop" in s:
			_check(not bool(s.get("loop")), "%s: stream must not loop" % lid)


func _test_plays() -> void:
	gs.reset()
	await _enter("Z1")
	_ensure_voice("M01_0")
	_ensure_voice("M01_1")
	_check(sr.start_scene("M01"), "M01 must start in Z1")
	await _frames(2)
	_check(String(sr.current_beat.get("line_id", "")) == "M01_0", "first beat line_id M01_0, got '%s'" % sr.current_beat.get("line_id", ""))
	_check(vd.is_playing() and vd.current_line == "M01_0" and vd.current_mode == "plain", "M01_0 (Agata) must play: %s" % [vd.state()])
	_check(String(_voice_player().bus) == "Voice", "voice on the Voice bus")
	sr.advance()
	await _frames(2)
	_check(vd.is_playing() and vd.current_line == "M01_1" and vd.current_speaker == "tamara", "M01_1 (Tamara) must play: %s" % [vd.state()])
	await _wait(1.0)
	var st: Dictionary = vd.state()
	_check(st["playing"] and float(st["position"]) > 0.5, "after 1 s Tamara still speaks, position %.2f" % float(st["position"]))
	_check(md.dialogue_active() and absf(md.duck_db_now - md.duck_dialogue_db) < 0.05,
		"music ducked while the voice sounds: %.2f dB (expected %.1f)" % [md.duck_db_now, md.duck_dialogue_db])
	await _finish_dialogue()


func _test_cut() -> void:
	gs.reset()
	await _enter("Z1")
	for lid in ["M01_0", "M01_1", "M01_2"]:
		_ensure_voice(lid)
	sr.start_scene("M01")
	await _frames(2)
	sr.advance()   # → M01_1 (Tamara, the long one)
	await _frames(2)
	await _wait(0.5)
	_check(vd.current_line == "M01_1" and vd.is_playing(), "M01_1 playing before the click")
	var pos := float(vd.state()["position"])
	var length := float(vd.state()["length"])
	_check(pos < length - 0.5, "the click comes mid-line (%.2f of %.2f s)" % [pos, length])
	sr.advance()   # the click «дальше»
	await _frames(1)
	var ev := _last_event("stop")
	_check(String(ev.get("line", "")) == "M01_1" and String(ev.get("reason", "")) == "advance", "click must cut M01_1: %s" % [ev])
	_check(vd.current_line == "M01_2" and vd.is_playing(), "the next line's voice starts: %s" % [vd.state()])
	# The last click of the scene: the beat goes away, the voice with it.
	sr.advance()
	await _frames(2)
	_check(not vd.is_playing(), "after the last line no voice plays")
	await _finish_dialogue()
	_check(gs.has_flag("done_M01"), "M01 completed")
	# New game while a voice sounds.
	gs.reset()
	await _enter("Z1")
	_ensure_voice("M01_0")
	sr.start_scene("M01")
	await _frames(2)
	_check(vd.is_playing(), "M01_0 playing before the new game")
	gs.reset()
	await _frames(2)
	_check(not vd.is_playing(), "a new game stops the voice")
	# Load while a voice sounds.
	await _enter("Z1")
	_check(rm.save_game(SLOT), "save slot")
	sr.start_scene("M01")
	await _frames(2)
	_check(vd.is_playing(), "M01_0 playing before the load")
	_check(rm.load_game(SLOT), "load slot")
	await _frames(3)
	_check(not vd.is_playing() or String(sr.current_beat.get("line_id", "")) == vd.current_line,
		"a load stops the voice (or only the line on screen sounds): %s" % [vd.state()])
	await _finish_dialogue()


func _test_subtitles_only() -> void:
	var errors_before: int = vd.config_errors.size()
	# A line nobody recorded.
	var r: String = vd.play_line("M99_0", "agata", "Такой реплики нет.")
	_check(r == "no_entry" and not vd.is_playing(), "unknown line: %s, playing %s" % [r, vd.is_playing()])
	# A recorded line whose text has changed since: never plays under the new subtitle.
	if not vd.manifest.is_empty():
		var lid: String = vd.manifest.keys()[0]
		var ln := _line(lid)
		r = vd.play_line(lid, String(ln.get("speaker", "")), String(ln.get("text", "")) + " (изменено)")
		_check(r == "text_changed" and not vd.is_playing(), "changed text: %s" % r)
	# Through the runner: M01 with the manifest entry of M01_2 removed → M01_2 is subtitles only.
	gs.reset()
	await _enter("Z1")
	var saved: Dictionary = vd.manifest.duplicate(true)
	vd.manifest.erase("M01_2")
	vd.set_test_stream("M01_2", null)
	vd._streams.erase("M01_2")
	sr.start_scene("M01")
	await _frames(2)
	sr.advance()
	await _frames(2)
	sr.advance()
	await _frames(2)
	_check(String(sr.current_beat.get("line_id", "")) == "M01_2" and String(sr.current_beat.get("text", "")) != "",
		"M01_2 is on screen as a subtitle")
	_check(not vd.is_playing(), "M01_2 without a file: no voice (%s)" % [vd.state()])
	var ev := _last_event("subtitles_only")
	_check(String(ev.get("line", "")) == "M01_2" and String(ev.get("reason", "")) == "no_entry", "M01_2 logged as subtitles only: %s" % [ev])
	_check(vd.config_errors.size() == errors_before, "no errors added")
	await _finish_dialogue()
	vd.manifest = saved


func _test_volume() -> void:
	var bus: int = AudioServer.get_bus_index("Voice")
	_delete(TEST_SETTINGS)
	vd.set_voice_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(bus) - vd.volume_to_db(0.5)) < 0.01 and not AudioServer.is_bus_mute(bus),
		"50 %%: Voice bus %.2f dB, expected %.2f" % [AudioServer.get_bus_volume_db(bus), vd.volume_to_db(0.5)])
	_check(absf(vd.volume_to_db(0.5) - linear_to_db(0.25)) < 0.01, "50 % is −12 dB (squared amplitude), same curve as music")
	await _wait(vd.SAVE_DELAY_S + 0.3)
	var cf := ConfigFile.new()
	_check(cf.load(TEST_SETTINGS) == OK and absf(float(cf.get_value("audio", "voice_volume", -1.0)) - 0.5) < 0.001,
		"the setting must be saved to %s" % TEST_SETTINGS)
	vd.set_voice_volume(1.0, false)
	vd.load_settings()
	_check(absf(vd.voice_volume - 0.5) < 0.001, "load_settings must restore 50 %% (got %.2f)" % vd.voice_volume)
	await _enter("Z1")
	_check(rm.save_game(SLOT), "save slot")
	_check(FileAccess.get_file_as_string(gs.save_path(SLOT)).find("voice_volume") < 0, "the save slot must not contain the voice volume")
	vd.set_voice_volume(0.3, false)
	_check(rm.load_game(SLOT), "load slot")
	await _frames(2)
	_check(absf(vd.voice_volume - 0.3) < 0.001, "loading a save must not change the voice volume (got %.2f)" % vd.voice_volume)
	var ui: Node = main_node.get_node("GameUi")
	ui.call("toggle_menu")
	await _frames(2)
	var slider: HSlider = ui.get("voice_slider")
	_check(slider != null and slider.is_visible_in_tree(), "menu must show the «Голос» slider")
	if slider != null:
		_check(absf(slider.value - 30.0) < 0.5, "slider shows the current volume (%.0f)" % slider.value)
		var music: HSlider = ui.get("music_slider")
		var sfx: HSlider = ui.get("sfx_slider")
		_check(music != null and sfx != null and slider.get_parent().get_parent() == sfx.get_parent().get_parent(),
			"«Голос» sits with «Музыка» and «Звуки»")
		slider.value = 40
		await _frames(1)
		_check(absf(vd.voice_volume - 0.4) < 0.001 and absf(AudioServer.get_bus_volume_db(bus) - vd.volume_to_db(0.4)) < 0.01,
			"slider 40 → volume %.2f, bus %.2f dB" % [vd.voice_volume, AudioServer.get_bus_volume_db(bus)])
		var probe: Dictionary = ui.call("probe_positions")
		_check(probe.has("voice_slider") and float(probe["voice_slider"].get("w", 0)) > 200, "probe publishes the slider rect")
		slider.value = 0
		await _frames(1)
		_check(AudioServer.is_bus_mute(bus), "0 % mutes the Voice bus")
	ui.call("toggle_menu")
	vd.set_voice_volume(1.0, false)
	_check(not AudioServer.is_bus_mute(bus) and absf(AudioServer.get_bus_volume_db(bus)) < 0.01, "100 % → 0 dB, unmuted")


## RMS of the Voice bus per channel over `seconds` (AudioEffectCapture; {} if the driver gives no frames).
func _capture(seconds: float) -> Dictionary:
	var bus: int = AudioServer.get_bus_index("Voice")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(bus, cap)
	var idx: int = AudioServer.get_bus_effect_count(bus) - 1
	await _wait(seconds)
	var n := cap.get_frames_available()
	var out := {}
	if n > 0:
		var buf: PackedVector2Array = cap.get_buffer(n)
		var l := 0.0
		var r := 0.0
		for f in buf:
			l += f.x * f.x
			r += f.y * f.y
		out = {"frames": n, "l_db": linear_to_db(sqrt(l / n) + 1e-9), "r_db": linear_to_db(sqrt(r / n) + 1e-9)}
	AudioServer.remove_bus_effect(bus, idx)
	return out


func _test_pan() -> void:
	gs.reset()
	await _enter("H1")
	gs.set_flag("started_M03")   # Tikhon's hotspot is visible from M03 on (visible_if)
	await _frames(3)
	var hs: Node2D = null
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == "tikhon":
			hs = h
	_check(hs != null and hs.is_visible_in_tree(), "H1 has a visible tikhon hotspot")
	_ensure_voice("M03_0")
	_ensure_voice("M03_1")
	var t0: Dictionary = _line("M03_0")
	var r: String = vd.play_line("M03_0", "tikhon", String(t0.get("text", "")))
	await _frames(2)
	_check(r == "playing" and vd.current_mode == "panned", "Tikhon's line plays panned: %s %s" % [r, vd.state()])
	var strength := float(vd.pan_cfg.get("tikhon", {}).get("panning_strength", 1.0))
	if hs != null:
		var want := clampf((hs.global_position.x - 960.0) / 1920.0, -1.0, 1.0) * strength \
			* float(ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5)) * 0.5
		_check(absf(vd.current_pan - want) < 0.01 and vd.current_pan < -0.05,
			"pan from the hotspot (x %.0f): %.3f, expected %.3f (left)" % [hs.global_position.x, vd.current_pan, want])
	var lis: AudioListener2D = vd.get_viewport().get_audio_listener_2d()
	var p2d: AudioStreamPlayer2D = vd.get_node("VoicePanned")
	if lis != null:
		_check(p2d.global_position.x < lis.global_position.x, "the 2D voice sits left of the listener (Agata)")
	var c := await _capture(0.6)
	if c.is_empty():
		print("        (note: the audio driver gave no capture frames — channel levels not measured)")
	else:
		var diff := float(c["l_db"]) - float(c["r_db"])
		var want_db := linear_to_db((0.5 - vd.current_pan) / (0.5 + vd.current_pan))
		print("        Tikhon (pan %.3f): L %.1f dB, R %.1f dB, L−R %.1f dB (expected %.1f), %d frames" % [vd.current_pan, c["l_db"], c["r_db"], diff, want_db, c["frames"]])
		_check(diff > 1.5 and absf(diff - want_db) < 1.0, "left louder than right by %.1f dB (expected %.1f)" % [diff, want_db])
	vd.stop("test")
	var a1: Dictionary = _line("M03_1")
	r = vd.play_line("M03_1", "agata", String(a1.get("text", "")))
	await _frames(2)
	_check(r == "playing" and vd.current_mode == "plain", "Agata in H1 is not panned: %s" % vd.current_mode)
	var c2 := await _capture(0.4)
	if not c2.is_empty():
		print("        Agata (plain): L %.1f dB, R %.1f dB" % [c2["l_db"], c2["r_db"]])
		_check(absf(float(c2["l_db"]) - float(c2["r_db"])) < 0.5, "plain voice: equal channels (%.1f / %.1f dB)" % [c2["l_db"], c2["r_db"]])
	vd.stop("test")


func _test_gating() -> void:
	gs.reset()
	await _enter("Z1")
	_ensure_voice("M01_0")
	var was: bool = md.unlocked
	md.unlocked = false
	sr.start_scene("M01")
	await _frames(2)
	_check(not vd.is_playing() and vd.state()["pending"] == "M01_0", "locked: the line waits (%s)" % [vd.state()])
	md.unlock()
	await _frames(3)
	_check(vd.is_playing() and vd.current_line == "M01_0", "after the unlock M01_0 plays")
	md.unlocked = was
	await _finish_dialogue()
	for lid in ["M01_0", "M01_1", "M01_2", "M03_0", "M03_1"]:
		vd.set_test_stream(lid, null)
