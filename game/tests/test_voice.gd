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
## Voice-over (the Director's task of 18.10, voice «ZAKADR», voice.json → narration):
##   - every narration entry of the manifest is a data/story/text key the rules voice, with that text (sha1);
##   - an examine with a file sounds in the narrator's voice on the Voice bus and ducks the music; the menu
##     slider «Голос» (the Voice bus) covers it; the click «дальше» cuts it, the next look plays its own;
##   - labels, interface texts, options, puzzle captions, plain text never sound — even with a stream;
##     the question of a choice (prompt) is voiced, its options are not;
##   - the close-up: intro / error / success are voiced once per message, a piece moved does not restart
##     it; the scene line that starts on success waits until the close-up closes, then plays;
##   - bag: the item's line after the pointer rests ≈0.6 s on its pocket (not before), leaving fades it out,
##     the same item at most once per 30 s, receiving a batch of items voices nothing;
##   - Agata's first-person thoughts (voice.json → narration.by_speaker.agata, acceptance item 75): read in
##     Agata's voice (id agata:<key>), never by the narrator — without her file only subtitles; the narrator's
##     recording stays a spare: taking the key out of the list brings it back;
##   - a character's words next to Agata (text entry `line` — Tamara and Pelageya when talked to again, Tikhon
##     after V01; the Director's note of 18.10, 01:52): a line beat with the speaker's name and the direct
##     speech, in that character's voice (id <speaker>:<key>, Tikhon panned from his hotspot), never the narrator.
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
	await _test("Voice-over: an examine with a file sounds in the narrator's voice (Voice bus, slider «Голос»), ducks the music", _test_narration_plays)
	await _test("Voice-over: the click «дальше» cuts it, the next look plays its own; a choice's question is voiced", _test_narration_cut)
	await _test("Voice-over: labels, interface, options, puzzle captions and plain text never sound (even with a stream)", _test_narration_skips)
	await _test("Voice-over in the close-up: intro / error / success once each; the success scene line waits for the close", _test_narration_puzzle)
	await _test("Bag: the item's line after a ≈0.6 s rest on its pocket, fades out on leaving, once per 30 s, not on receiving", _test_item_hover)
	await _test("Agata's thoughts: her voice (agata:<key>), never the narrator; no file — subtitles; the narrator's spare returns by data", _test_thoughts)
	await _test("A character's words next to Agata: his/her line (name, direct speech, own voice), not the narrator — Tamara, Pelageya, Tikhon", _test_character_lines)
	await _test("Scene lines of the narrator (M15s_2) sound in the narrator's voice; a choice in a conversation (M13): question voiced, the chosen words play as <scene>_<index>_<option>", _test_scene_narrator_and_choice)
	await _test("H4/H14: «О чём спросить …» is voiced on its first showing, then at most once per 5 min of play; the subtitle stays", _test_ask_prompt_once)
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


## The scene line `line_id` as data/story has it: {speaker, text} or {}. A choice inside a conversation
## (M13_1_family): <scene>_<index>_<option> — the option's words, said by the line's speaker (Agata).
func _line(line_id: String) -> Dictionary:
	var parts := line_id.split("_")
	if parts.size() < 2:
		return {}
	var sc: Dictionary = sd.scene(parts[0])
	var lines: Array = sc.get("mandatory_lines", sc.get("lines", []))
	if not parts[1].is_valid_int():
		return {}
	var i := int(parts[1])
	if i < 0 or i >= lines.size():
		return {}
	var ln: Dictionary = lines[i]
	if parts.size() == 2:
		return ln
	if parts[2].begins_with("then") and parts[2].substr(4).is_valid_int():
		# a follow-up line (`then`: an optional story's trace in the epilogue), line_id <scene>_<index>_then<k>
		var th: Array = ln.get("then", [])
		var k := int(parts[2].substr(4))
		if k >= 0 and k < th.size():
			var sub: Dictionary = th[k]
			return {"speaker": String(sub.get("speaker", "narrator")), "text": String(sub.get("text", ""))}
		return {}
	for o in ln.get("options", []):
		if String(o.get("id", "")) == parts[2]:
			return {"speaker": String(ln.get("speaker", "agata")), "text": String(o.get("text", ""))}
	return {}


## Sets the flags / items a scene requires, so it can start outside the walkthrough (the voice is under test).
func _force_requires(scene_id: String) -> void:
	var req: Dictionary = sd.scene(scene_id).get("requires", {})
	for f in req.get("flags", []):
		gs.set_flag(String(f), true)
	for it in req.get("items", []):
		if sd.item_is_inventory(String(it)):
			gs.add_item(String(it))
		else:
			gs.set_flag("has_" + String(it), true)


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

## voice.json → narration.character_lines.subdir (folder of a character's words next to Agata).
func _character_lines_subdir() -> String:
	var vj = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/voice.json"))
	if vj is Dictionary:
		return String(vj.get("narration", {}).get("character_lines", {}).get("subdir", "character_lines"))
	return "character_lines"


func _test_manifest() -> void:
	_check(vd.config_errors.is_empty(), "voice.json/manifest errors: %s" % [vd.config_errors])
	_check(AudioServer.get_bus_index("Voice") >= 0, "bus Voice must exist")
	_check((vd.get_node("Voice") as AudioStreamPlayer).bus == &"Voice" and (vd.get_node("VoicePanned") as AudioStreamPlayer2D).bus == &"Voice",
		"both voice players on the Voice bus")
	if vd.manifest.is_empty():
		print("        (note: no recordings in game/assets/voice/ru — every line is subtitles only)")
	var narrated := 0
	var outdated: Array[String] = []   # text changed after the recording: the game is silent, the pipeline re-records
	for lid in vd.manifest.keys():
		var e: Dictionary = vd.manifest[lid]
		if e.has("stale"):
			continue
		if String(e.get("kind", "")) == "narration":
			narrated += 1
			var id := String(lid)
			var key := String(e.get("key", id))
			var want_sp: String = id.get_slice(":", 0) if id.contains(":") else vd.narr_speaker
			if not sd.texts.has(key):
				# the key was removed from the texts (block 1, 22.10: item.invoice_chalk, item.photo_school_pier) — never
				# shown, so never played; the pipeline marks it stale (validate_voice.py: a warning, not an error)
				outdated.append(id)
				continue
			_check(vd.is_narration_key(key), "%s: the voice.json rules do not voice this key" % key)
			_check(String(e.get("speaker", "")) == want_sp, "%s: speaker %s, expected %s" % [id, e.get("speaker"), want_sp])
			var t: String = sd.text("@" + key)
			var sub := String(vd.narr_subdirs.get(want_sp, "?"))
			if bool(e.get("as_line", false)):
				# a character's words next to Agata (text entry `line`): the line's own text, folder character_lines
				t = String(sd.text_line("@" + key).get("text", t))
				sub = _character_lines_subdir()
			if sd.texts.has(key) and vd.line_status(id, t) == "text_changed":
				outdated.append(id)   # a text edit must not fail the build — only keep the game silent
				_check(vd.stream_for(id, t) == null and ResourceLoader.exists(vd.file_path(id)), "%s: outdated → no stream (silent), file kept" % id)
				continue
			_check(vd.line_status(id, t) == "ok", "%s: status %s" % [id, vd.line_status(id, t)])
			var ns: AudioStream = vd.stream_for(id, t)
			_check(ns != null and ns.get_length() > 0.2, "%s: stream %s does not load or is too short" % [id, vd.file_path(id)])
			_check(vd.file_path(id) == "%s/%s/%s.ogg" % [vd.voice_dir, sub, key], "%s: file %s, expected %s/%s.ogg" % [id, vd.file_path(id), sub, key])
			continue
		var ln := _line(String(lid))
		_check(not ln.is_empty(), "%s: no such scene line" % lid)
		if ln.is_empty():
			continue
		# A text edit (or lines re-ordered by it — the line id is <scene>_<index>) keeps the game silent on that
		# line and must not fail the build; the speaker is checked for recordings that still match their text.
		if vd.line_status(String(lid), String(ln["text"])) == "text_changed":
			outdated.append(String(lid))
			_check(vd.stream_for(String(lid), String(ln["text"])) == null, "%s: outdated → silent" % lid)
			continue
		_check(String(ln.get("speaker", "")) == String(e.get("speaker", "")), "%s: speaker %s vs manifest %s" % [lid, ln.get("speaker"), e.get("speaker")])
		_check(vd.line_status(String(lid), String(ln["text"])) == "ok", "%s: status %s" % [lid, vd.line_status(String(lid), String(ln["text"]))])
		var s: AudioStream = vd.stream_for(String(lid), String(ln["text"]))
		_check(s != null and s.get_length() > 0.2, "%s: stream %s does not load or is too short" % [lid, vd.file_path(String(lid))])
		if s != null and "loop" in s:
			_check(not bool(s.get("loop")), "%s: stream must not loop" % lid)
	print("        voice-over entries: %d (narrator %s)" % [narrated, vd.narr_speaker])
	if not outdated.is_empty():
		print("        WARNING: %d recording(s) outdated (text changed after recording; the game is silent, re-record — pipeline/voice/README.md): %s"
			% [outdated.size(), ", ".join(outdated)])
	_check(not vd.narr_skip_sections.is_empty() and not vd.narr_skip_fields.is_empty(), "voice.json narration: the not-voiced categories are listed")


func _test_plays() -> void:
	gs.reset()
	await _enter("Z1")
	_ensure_voice("M01_0")
	_ensure_voice("M01_1")
	_check(sr.start_scene("M01"), "M01 must start in Z1")
	await _frames(2)
	_check(String(sr.current_beat.get("line_id", "")) == "M01_0", "first beat line_id M01_0, got '%s'" % sr.current_beat.get("line_id", ""))
	# M01 by the final scenario (22.10): Tamara recognises Agata first (M01_0), Agata answers (M01_1).
	_check(vd.is_playing() and vd.current_line == "M01_0" and vd.current_mode == "plain" and vd.current_speaker == "tamara", "M01_0 (Tamara) must play: %s" % [vd.state()])
	_check(String(_voice_player().bus) == "Voice", "voice on the Voice bus")
	sr.advance()
	await _frames(2)
	_check(vd.is_playing() and vd.current_line == "M01_1" and vd.current_speaker == "agata", "M01_1 (Agata) must play: %s" % [vd.state()])
	await _wait(1.0)
	var st: Dictionary = vd.state()
	_check(st["playing"] and float(st["position"]) > 0.5, "after 1 s Agata still speaks, position %.2f" % float(st["position"]))
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
	sr.advance()   # → M01_1
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
	# The last click of the scene: the beat goes away, the voice with it (M01 is 9 lines since 22.10 — click to the last).
	var lines: Array = sd.scene("M01").get("mandatory_lines", [])
	var last_id := "M01_%d" % (lines.size() - 1)
	for i in 20:
		if String(sr.current_beat.get("line_id", "")) == last_id or sr.current_beat.is_empty():
			break
		sr.advance()
		await _frames(2)
	_ensure_voice(last_id)
	_check(String(sr.current_beat.get("line_id", "")) == last_id, "reached the last line %s" % last_id)
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
	# Test tones of the earlier tests (lines re-recorded after a text edit have none) must not answer for the
	# recordings here: only the manifest decides below.
	for lid in ["M01_0", "M01_1", "M01_2", "M03_0", "M03_1"]:
		vd.set_test_stream(lid, null)
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
	# A voice-over recorded for an older text: silent as well (narrator and Agata's thoughts alike).
	for nid in vd.manifest.keys():
		var ne: Dictionary = vd.manifest[nid]
		if String(ne.get("kind", "")) != "narration" or ne.has("stale"):
			continue
		var nkey := String(ne.get("key", nid))
		var nr: String = vd.play_line(String(nid), String(ne.get("speaker", "")), sd.text("@" + nkey) + " (изменено)", "narration")
		_check(nr == "text_changed" and not vd.is_playing(), "%s with another text: %s, playing %s" % [nid, nr, vd.is_playing()])
		if String(nid).contains(":"):
			break   # one of the character's thoughts is enough (the loop meets narrator ids first)
	# Through the runner: a look whose text was edited after the recording — the subtitle, no voice.
	gs.reset()
	await _enter("Z1")
	var lk := "Z1.letters.look"
	if vd.manifest.has(lk):
		var orig: Dictionary = sd.texts[lk].duplicate(true)
		sd.texts[lk]["text"] = String(orig["text"]) + " Правка текста."
		vd.set_test_stream(lk, null)
		sr.narrate_key("@" + lk)
		await _frames(2)
		_check(String(sr.current_beat.get("text", "")).ends_with("Правка текста.") and not vd.is_playing(),
			"an edited look shows the new subtitle and stays silent: %s" % [vd.state()])
		var tev := _last_event("subtitles_only")
		_check(String(tev.get("line", "")) == lk and String(tev.get("reason", "")) == "text_changed", "logged as text_changed: %s" % [tev])
		await _finish_dialogue()
		sd.texts[lk] = orig
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


# --- Voice-over -------------------------------------------------------------------------------

func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == id:
			return h
	return null


## The manifest id the game plays for a voice-over key: the key (narrator) or "<speaker>:<key>".
func _vid(key: String) -> String:
	return String(vd.narration_voice(key)["id"])


## The recording for a voice-over key (under the voice the data gives it), or the test tone.
func _ensure_key(key: String) -> bool:
	var id := _vid(key)
	if vd.line_status(id, sd.text("@" + key)) == "ok":
		return true
	print("        (note: %s has no recording here — test tone)" % id)
	vd.set_test_stream(id, _tone())
	return false


func _drop_key(key: String) -> void:
	vd.set_test_stream(_vid(key), null)


func _starts_since(n0: int, kind: String = "") -> Array:
	var out: Array = []
	for i in range(n0, vd.events.size()):
		var ev: Dictionary = vd.events[i]
		if String(ev.get("kind", "")) == "start" and (kind == "" or String(ev.get("voice", "")) == kind):
			out.append(ev)
	return out


func _test_narration_plays() -> void:
	gs.reset()
	await _enter("Z1")
	_ensure_key("Z1.letters.look")
	var h := _hotspot("letters")
	_check(h != null, "Z1 has the letters hotspot")
	if h == null:
		return
	sr.interact(h)
	await _frames(2)
	_check(String(sr.current_beat.get("type", "")) == "narration" and String(sr.current_beat.get("text_key", "")) == "Z1.letters.look",
		"the look is a narration beat with its key: %s" % [sr.current_beat])
	_check(vd.is_playing() and vd.current_line == "Z1.letters.look" and vd.current_kind == "narration" and vd.current_speaker == vd.narr_speaker,
		"the narrator reads Z1.letters.look: %s" % [vd.state()])
	_check(String(_voice_player().bus) == "Voice", "the voice-over is on the Voice bus (slider «Голос»)")
	await _wait(0.6)
	_check(md.dialogue_active() and absf(md.duck_db_now - md.duck_dialogue_db) < 0.05,
		"music ducked under the voice-over: %.2f dB (expected %.1f)" % [md.duck_db_now, md.duck_dialogue_db])
	# Slider «Голос»: the same bus — 0 % mutes the narrator as well.
	var bus: int = AudioServer.get_bus_index("Voice")
	vd.set_voice_volume(0.0, false)
	_check(AudioServer.is_bus_mute(bus) and vd.is_playing(), "«Голос» 0 %: the bus carrying the narrator is muted")
	vd.set_voice_volume(1.0, false)
	_check(not AudioServer.is_bus_mute(bus), "«Голос» back to 100 %")
	await _finish_dialogue()
	_check(not vd.is_playing(), "after the click the narrator is silent")
	await _wait(0.6)
	_check(not md.dialogue_active() and absf(md.duck_db_now) < 0.05, "music back after the voice-over (%.2f dB)" % md.duck_db_now)


func _test_narration_cut() -> void:
	gs.reset()
	await _enter("Z1")
	_ensure_key("Z1.drawings.use")
	_ensure_key("Z1.letters.look")
	sr.interact(_hotspot("drawings"))   # the action (compare the drawings): Z1.drawings.use
	await _frames(2)
	_check(vd.current_line == "Z1.drawings.use" and vd.is_playing(), "Z1.drawings.use plays: %s" % [vd.state()])
	await _wait(0.4)
	sr.advance()   # the click «дальше»
	await _frames(1)
	var ev := _last_event("stop")
	_check(String(ev.get("line", "")) == "Z1.drawings.use" and String(ev.get("reason", "")) == "advance", "the click cuts the narrator: %s" % [ev])
	_check(not vd.is_playing(), "nothing sounds after the click")
	# The next look plays its own line from the start.
	sr.interact(_hotspot("letters"))
	await _frames(2)
	_check(vd.current_line == "Z1.letters.look" and vd.is_playing() and float(vd.state()["position"]) < 0.5,
		"the next look plays its own line: %s" % [vd.state()])
	await _finish_dialogue()
	# A choice: its question is voiced, the options are buttons (never voiced).
	gs.reset()
	await _enter("H1")
	_ensure_key("H1.cups.prompt")
	var n0: int = vd.events.size()
	sr.interact(_hotspot("cups"))
	await _frames(2)
	_check(String(sr.current_beat.get("type", "")) == "options" and String(sr.current_beat.get("prompt_key", "")) == "H1.cups.prompt",
		"the cups offer a choice with its prompt key: %s" % [sr.current_beat.get("prompt_key", "")])
	_check(vd.current_line == _vid("H1.cups.prompt") and vd.current_kind == "narration" and vd.current_speaker == "agata",
		"the question of the choice («…будет моей?») is voiced by Agata: %s" % [vd.state()])
	for ev2 in _starts_since(n0):
		_check(String(ev2.get("line", "")).find(".opt_") < 0, "an option label must never sound: %s" % [ev2])
	var opts: Array = sr.current_options()
	sr.choose(String(opts[0]["id"]))
	await _frames(2)
	_check(not vd.is_playing() or vd.current_line != _vid("H1.cups.prompt"), "choosing cuts the question")
	await _finish_dialogue()
	for k in ["H1.cups.prompt", "Z1.drawings.use", "Z1.letters.look"]:
		_drop_key(k)


func _test_narration_skips() -> void:
	gs.reset()
	await _enter("Z1")
	for key in ["Z1.letters.label", "Z1.exit_Z4.label", "H1.stove.label_lit", "H1.photo.opt_table", "H3.puzzle.slot_top",
			"H3.puzzle.marks", "H3.puzzle.drawing", "H3.puzzle.title", "H3.puzzle.hinge", "H3.puzzle.check",
			"ui.nothing_here", "ui.item_no_effect", "ui.closed_generic", "ui.not_built", "ui.hint_generic_1", "ui.got_item",
			"ui.bag_take", "map.here"]:
		_check(not vd.is_narration_key(key), "%s must not be voiced" % key)
		_check(not vd.manifest.has(key), "%s must not be recorded" % key)
	for key in ["Z1.letters.look", "H1.stove.use", "Z1.exit_Z4.closed", "H1.v01.done", "H3.puzzle.intro", "H3.puzzle.error",
			"H3.puzzle.success", "H3.puzzle.need", "O2.exit_O4.loop", "O1.board.chalk", "O2.porch_step.mitten", "H1.shelf.look_done",
			"H1.cups.prompt", "item.key_house"]:
		_check(vd.is_narration_key(key), "%s must be voiced" % key)
	# Even with a stream, an interface / label narration stays subtitles only.
	for key in ["ui.nothing_here", "Z1.letters.label"]:
		vd.set_test_stream(key, _tone())
		sr.narrate(sd.text("@" + key), key)
		await _frames(2)
		_check(not vd.is_playing(), "%s on screen: no voice (%s)" % [key, vd.state()])
		var ev := _last_event("subtitles_only")
		_check(String(ev.get("line", "")) == key and String(ev.get("reason", "")) == "not_voiced", "%s logged as not voiced: %s" % [key, ev])
		await _finish_dialogue()
		vd.set_test_stream(key, null)
	# A click on a hotspot without a look of its own falls back to ui.nothing_here — silent.
	sr.narrate_key("@ui.item_no_effect")
	await _frames(2)
	_check(not vd.is_playing(), "ui.item_no_effect: no voice")
	await _finish_dialogue()
	# Plain text (no key) never sounds.
	sr.narrate("Проверка: простой текст без ключа.")
	await _frames(2)
	_check(not vd.is_playing(), "plain narration: no voice")
	await _finish_dialogue()
	# Hovering a hotspot shows its label: no beat, no voice.
	var n0: int = vd.events.size()
	var ui: Node = main_node.get_node("GameUi")
	ui.call("_set_hover", _hotspot("letters"))
	await _frames(3)
	_check(_starts_since(n0).is_empty(), "a hotspot label on hover never sounds")
	ui.call("_set_hover", null)


func _test_narration_puzzle() -> void:
	gs.reset()
	gs.set_flag("house_open", true)   # the gallery seen before (C12: its first entry draws the side bolt with a line)
	await _enter("H3")
	gs.set_flag("done_M04")
	gs.add_item("door_hinges")
	await _frames(2)
	for k in ["H3.puzzle.intro", "H3.puzzle.error", "H3.puzzle.success"]:
		_ensure_key(k)
	_ensure_voice("M05_0")
	var h := _hotspot("school_door")
	_check(h != null, "H3 has the school door")
	if h == null:
		return
	sr.open_puzzle(h)
	await _frames(2)
	_check(vd.current_line == "H3.puzzle.intro" and vd.current_kind == "puzzle" and vd.is_playing(), "the close-up's intro is voiced: %s" % [vd.state()])
	var plays0: int = vd.plays
	sr.puzzle_place("hinge_1", "top")
	await _frames(2)
	_check(vd.plays == plays0 and vd.current_line == "H3.puzzle.intro", "moving a piece does not restart the intro")
	sr.puzzle_place("hinge_2", "middle")
	sr.puzzle_set_mark(0)
	_check(not sr.puzzle_check(), "wrong placement fails")
	await _frames(2)
	_check(vd.current_line == "H3.puzzle.error" and vd.is_playing(), "the error message is voiced (cuts the intro): %s" % [vd.state()])
	_check(not sr.puzzle_check(), "second wrong attempt")
	await _frames(2)
	_check(vd.plays == plays0 + 2 and vd.current_line == "H3.puzzle.error", "the second error is a new message: voiced again (plays %d)" % (vd.plays - plays0))
	sr.puzzle_place("hinge_2", "bottom")
	sr.puzzle_place("hinge_3", "middle")   # three hinges (Director 18.10)
	sr.puzzle_set_mark(2)
	_check(sr.puzzle_check(), "correct placement succeeds")
	await _frames(2)
	_check(vd.current_line == "H3.puzzle.success" and vd.is_playing(), "the success message is voiced: %s" % [vd.state()])
	_check(String(sr.current_beat.get("line_id", "")) == "M05_0", "M05 starts at once (its line under the close-up)")
	_check(String(vd.state()["after_puzzle"]) == "M05_0", "M05_0 waits for the close-up to close: %s" % [vd.state()])
	await _wait(2.6)
	if vd.is_speaking_kind("puzzle"):
		_check(sr.puzzle_open, "the close-up stays while the success voice-over sounds (auto-close waits)")
	sr.close_puzzle()
	await _frames(2)
	_check(vd.current_line == "M05_0" and vd.current_kind == "line" and vd.is_playing(), "after the close M05_0 plays: %s" % [vd.state()])
	var ev := _last_event("stop")
	_check(String(ev.get("line", "")) != "H3.puzzle.success" or String(ev.get("reason", "")) in ["puzzle_closed", "finished"],
		"the success voice ended by the close or by itself: %s" % [ev])
	await _finish_dialogue()
	for k in ["H3.puzzle.intro", "H3.puzzle.error", "H3.puzzle.success"]:
		_drop_key(k)
	vd.set_test_stream("M05_0", null)


func _move_mouse(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	await _frames(3)


func _test_item_hover() -> void:
	gs.reset()
	await _enter("Z1")
	var ui: Node = main_node.get_node("GameUi")
	var bag = ui.get("bag")
	for id in ["key_house", "letter_tamara"]:
		gs.add_item(id)
		_ensure_key("item." + id)
	bag.cancel_flights()
	bag.refresh()
	await _frames(2)
	var away := Vector2(960, 600)
	await _move_mouse(away)
	var s: Control = bag.slot_of("letter_tamara")
	_check(s != null, "letter_tamara has a pocket")
	if s == null:
		return
	var at := s.get_global_rect().get_center()
	await _move_mouse(at)
	_check(bag.tooltip.visible and bag.hover_item() == "letter_tamara", "pointer on the pocket: tooltip open")
	await _wait(0.3)
	_check(not vd.is_playing(), "not before the dwell (0.3 s of %.1f)" % vd.item_dwell_s)
	await _wait(vd.item_dwell_s - 0.3 + 0.25)
	_check(vd.is_playing() and vd.current_line == _vid("item.letter_tamara") and vd.current_kind == "item"
		and vd.current_speaker == String(vd.narration_voice("item.letter_tamara")["speaker"]),
		"after the dwell the item's line plays in its voice (%s): %s" % [vd.narration_voice("item.letter_tamara")["speaker"], vd.state()])
	_check(String(_voice_player().bus) == "Voice", "item line on the Voice bus")
	await _wait(0.4)
	_check(vd.is_playing(), "still speaking while the pointer rests")
	await _move_mouse(away)
	_check(vd.is_fading() or not vd.is_playing(), "leaving the pocket fades it out: %s" % [vd.state()])
	await _wait(vd.item_fade_s + 0.2)
	_check(not vd.is_playing(), "faded out and stopped")
	var ev := _last_event("stop")
	_check(String(ev.get("line", "")) == _vid("item.letter_tamara") and String(ev.get("reason", "")) == "hover_end", "stopped by leaving: %s" % [ev])
	# Again within 30 s: tooltip yes, voice no.
	await _move_mouse(at)
	await _wait(vd.item_dwell_s + 0.3)
	_check(bag.tooltip.visible and not vd.is_playing(), "the same item again within %.0f s: no voice" % vd.item_repeat_s)
	var skip := _last_event("item_skip")
	_check(String(skip.get("line", "")) == _vid("item.letter_tamara") and String(skip.get("reason", "")) == "cooldown", "logged as cooldown: %s" % [skip])
	# Another item is not held back by the first one's cooldown.
	await _move_mouse(away)
	var s2: Control = bag.slot_of("key_house")
	await _move_mouse(s2.get_global_rect().get_center())
	await _wait(vd.item_dwell_s + 0.25)
	_check(vd.current_line == _vid("item.key_house") and vd.is_playing(), "another item speaks: %s" % [vd.state()])
	await _move_mouse(away)
	await _wait(vd.item_fade_s + 0.2)
	# 30 s later the first item speaks again.
	vd.item_last_ms["letter_tamara"] = int(vd.item_last_ms["letter_tamara"]) - int(vd.item_repeat_s * 1000.0) - 1000
	await _move_mouse(at)
	await _wait(vd.item_dwell_s + 0.25)
	_check(vd.current_line == _vid("item.letter_tamara") and vd.is_playing(), "after %.0f s the item speaks again: %s" % [vd.item_repeat_s, vd.state()])
	await _move_mouse(away)
	await _wait(vd.item_fade_s + 0.2)
	# Receiving a batch with the pointer resting on the bag: icons fly into the pockets, nothing is voiced.
	vd.item_last_ms.clear()
	var empty_slot: Control = bag.slots[3]
	await _move_mouse(empty_slot.get_global_rect().get_center())
	var n0: int = vd.events.size()
	for id in ["pocket_watch", "mitten", "door_hinges", "chalk"]:
		_ensure_key("item." + id)
		sr.grant_item(id)
	await _wait(2.0)
	_check(_starts_since(n0, "item").is_empty(), "receiving 4 items voices none of them: %s" % [_starts_since(n0, "item")])
	_check(not vd.is_playing(), "nothing speaks after the batch")
	await _move_mouse(away)
	# While a look is on screen the bag pocket is under the modal: no item voice either.
	for id in ["key_house", "letter_tamara", "pocket_watch", "mitten", "door_hinges", "chalk"]:
		_drop_key("item." + id)


func _test_thoughts() -> void:
	# Every key the data gives Agata is hers, and none of them falls back to the narrator.
	var owned: Array = vd.narr_owner.keys()
	_check(owned.size() >= 20, "voice.json gives Agata her first-person thoughts (%d keys)" % owned.size())
	for k in ["Z1.exit_Z4.closed", "O1.bird_drawing.prompt", "H1.cups.prompt", "item.key_house", "O2.tree.look", "H1.photo.look"]:
		_check(String(vd.narr_owner.get(k, "")) == "agata" and _vid(k) == "agata:" + k, "%s is Agata's thought (id %s)" % [k, _vid(k)])
	for k in ["Z1.letters.look", "H3.puzzle.success", "item.door_hinges"]:
		_check(_vid(k) == k, "%s stays with the narrator" % k)
	# A closed exit before Tamara: «Я ещё не поговорила с Тамарой» — Agata's voice, not the baritone.
	gs.reset()
	await _enter("Z1")
	_ensure_key("Z1.exit_Z4.closed")
	var ex: Node = null
	for e in rm.current_room.get_exits():
		if String(e.data.get("closed_text", "")) == "@Z1.exit_Z4.closed":
			ex = e
	_check(ex != null and not ex.is_open(), "Z1 has the closed street exit")
	if ex != null:
		sr.use_exit(ex)
		await _frames(2)
		_check(String(sr.current_beat.get("text_key", "")) == "Z1.exit_Z4.closed", "the closed exit narrates its key")
		_check(vd.is_playing() and vd.current_line == "agata:Z1.exit_Z4.closed" and vd.current_speaker == "agata"
			and vd.current_mode == "plain" and vd.current_kind == "narration", "Agata reads her thought: %s" % [vd.state()])
		_check(md.dialogue_active(), "the music ducks under her thought as under the narrator")
		await _finish_dialogue()
	# The narrator's recording of the same key is still a valid spare in the manifest …
	var text: String = sd.text("@Z1.exit_Z4.closed")
	if vd.manifest.has("Z1.exit_Z4.closed"):
		var spare: String = vd.line_status("Z1.exit_Z4.closed", text)
		_check(spare == "ok" or spare == "text_changed", "the narrator's spare recording stays in the manifest (%s)" % spare)
		if spare == "text_changed":
			print("        (note: the narrator's spare of Z1.exit_Z4.closed is outdated — text edited)")
	# … and taking the key out of Agata's list (a data change) brings it back.
	_ensure_voice_key_narrator("Z1.exit_Z4.closed")
	vd.narr_owner.erase("Z1.exit_Z4.closed")
	sr.narrate_key("@Z1.exit_Z4.closed")
	await _frames(2)
	_check(vd.current_line == "Z1.exit_Z4.closed" and vd.current_speaker == vd.narr_speaker, "without the assignment the narrator reads it: %s" % [vd.state()])
	await _finish_dialogue()
	vd.reload_config()
	_check(_vid("Z1.exit_Z4.closed") == "agata:Z1.exit_Z4.closed", "reloaded data: Agata's again")
	# No file of Agata's (H1.photo.look is held back): subtitles only, the narrator's «Наш…» never plays.
	var n0: int = vd.events.size()
	sr.narrate_key("@H1.photo.look")
	await _frames(2)
	_check(not vd.is_playing(), "H1.photo.look without Agata's file: no voice (%s)" % [vd.state()])
	var ev := _last_event("subtitles_only")
	_check(String(ev.get("line", "")) == "agata:H1.photo.look", "logged under Agata's id: %s" % [ev])
	_check(_starts_since(n0).is_empty(), "no fallback to the narrator")
	await _finish_dialogue()
	_drop_key("Z1.exit_Z4.closed")
	vd.set_test_stream("Z1.exit_Z4.closed", null)


## The narrator's own recording of `key` (or a tone under the narrator's id) — for the switch-back check.
func _ensure_voice_key_narrator(key: String) -> void:
	if vd.line_status(key, sd.text("@" + key)) != "ok":
		vd.set_test_stream(key, _tone())


## The character line `<speaker>:<key>` with its recording, or a test tone.
func _ensure_text_line(key: String) -> String:
	var ln: Dictionary = sd.text_line("@" + key)
	var id := "%s:%s" % [String(ln.get("speaker", "")), key]
	if vd.line_status(id, String(ln.get("text", ""))) != "ok":
		print("        (note: %s has no recording here — test tone)" % id)
		vd.set_test_stream(id, _tone())
	return id


func _check_line_beat(key: String, speaker: String, panned: bool) -> void:
	var ln: Dictionary = sd.text_line("@" + key)
	var b: Dictionary = sr.current_beat
	_check(String(b.get("type", "")) == "line" and String(b.get("speaker", "")) == speaker
		and String(b.get("speaker_name", "")) == sd.character_name(speaker) and String(b.get("text", "")) == String(ln.get("text", "")),
		"%s is %s's line with the name and the direct speech: %s" % [key, speaker, b])
	_check(String(b.get("text", "")).find("—") < 0 or String(b.get("text", "")).find("говорит") < 0, "%s: no author's remark in the line" % key)
	var ui: Node = main_node.get_node("GameUi")
	var lbl: Label = ui.get("speaker_label")
	_check(lbl.visible and lbl.text == sd.character_name(speaker), "the dialogue box shows the speaker «%s» (%s)" % [lbl.text, lbl.visible])
	_check(vd.is_playing() and vd.current_line == "%s:%s" % [speaker, key] and vd.current_speaker == speaker and vd.current_kind == "line",
		"%s speaks it in her/his own voice: %s" % [speaker, vd.state()])
	_check((vd.current_mode == "panned") == panned, "%s: mode %s (panned expected %s)" % [key, vd.current_mode, panned])


func _test_character_lines() -> void:
	var keys := ["Z1.tamara.after", "R1.pelageya.after", "H1.v01.done"]
	for k in keys:
		_check(not sd.text_line("@" + k).is_empty(), "%s carries a character line in data" % k)
	# Tamara, talked to again after M01.
	gs.reset()
	await _enter("Z1")
	gs.set_flag("done_M01")
	await _frames(2)
	var tid := _ensure_text_line("Z1.tamara.after")
	var n0: int = vd.events.size()
	sr.interact(_hotspot("tamara"))
	await _frames(2)
	# Polish 22.10 (B11, B14, B16): after M01 Tamara answers questions; «Пойду» ends with her line.
	if String(sr.current_beat.get("type", "")) == "options":
		sr.choose("leave")
		await _frames(2)
	_check_line_beat("Z1.tamara.after", "tamara", false)
	for ev in _starts_since(n0):
		_check(String(ev.get("speaker", "")) != vd.narr_speaker, "the narrator never reads Tamara's words: %s" % [ev])
	_check(md.dialogue_active(), "music ducked under her line")
	sr.advance()
	await _frames(1)
	_check(not vd.is_playing(), "the click cuts her line")
	await _finish_dialogue()
	vd.set_test_stream(tid, null)
	# Pelageya on the pier after M02.
	gs.reset()
	await _enter("R1")
	gs.set_flag("done_M01")
	gs.set_flag("done_M02")
	await _frames(2)
	var pid := _ensure_text_line("R1.pelageya.after")
	sr.interact(_hotspot("pelageya"))
	await _frames(2)
	# Polish 22.10 (D23): after M02 Pelageya answers questions; «Пока ничего» ends with her line.
	if String(sr.current_beat.get("type", "")) == "options":
		sr.choose("leave")
		await _frames(2)
	_check_line_beat("R1.pelageya.after", "pelageya", false)
	await _finish_dialogue()
	vd.set_test_stream(pid, null)
	# Tikhon when the cups and the photo are placed (V01 completes): his voice from the stove side.
	gs.reset()
	await _enter("H1")
	gs.set_flag("started_M03")
	gs.set_flag("met_tikhon")
	await _frames(2)
	var kid := _ensure_text_line("H1.v01.done")
	gs.set_flag("v01_cup_blue")
	gs.set_flag("v01_photo_table")
	await _frames(4)
	_check(gs.has_flag("done_V01"), "V01 completes")
	_check_line_beat("H1.v01.done", "tikhon", true)
	await _finish_dialogue()
	vd.set_test_stream(kid, null)
	# The narrator's recordings of the old texts stay in the manifest as spares.
	for k in keys:
		if vd.manifest.has(k):
			var st: String = vd.line_status(k, sd.text("@" + k))
			_check(st == "ok" or st == "text_changed" or st == "stale", "%s: the narrator's spare is kept (%s)" % [k, st])


## Defects of 23.10 (full voice-over): a narrator line inside a scene (mandatory_lines speaker "narrator") is a
## narration beat with a line_id and no text key — it was never voiced; the question of a choice inside a
## conversation (M13: what Agata answers Pavel) had no prompt_key — never voiced; the chosen words have their own
## id <scene>_<index>_<option> (the pipeline did not know it and sent the empty line text to synthesis).
func _test_scene_narrator_and_choice() -> void:
	gs.reset()
	await _enter("Z1")
	# 1. the narrator's scene line
	var lid := "M15s_2"
	var ln := _line(lid)
	_check(String(ln.get("speaker", "")) == "narrator", "%s is the narrator's scene line: %s" % [lid, ln])
	var bv: Dictionary = vd.beat_voice({"type": "narration", "scene": "M15s", "line_id": lid, "text": String(ln.get("text", ""))})
	_check(String(bv.get("id", "")) == lid and String(bv.get("speaker", "")) == vd.narr_speaker and String(bv.get("kind", "")) == "line",
		"the narration beat of a scene line is voiced by its line id in the narrator's voice: %s" % [bv])
	_ensure_voice(lid)
	_force_requires("M15s")
	var started: bool = sr.start_scene("M15s")
	_check(started, "M15s starts (requires forced)")
	# lines before it are clicked through; the staging between them (the boat to the pier: fade, hold, fade) runs by itself
	for i in 120:
		if String(sr.current_beat.get("line_id", "")) == lid:
			break
		var t := String(sr.current_beat.get("type", ""))
		if t == "options":
			sr.choose(String(sr.current_options()[0]["id"]))
		elif t == "line" or t == "narration":
			sr.advance()
		await _wait(0.1)
	_check(String(sr.current_beat.get("line_id", "")) == lid and String(sr.current_beat.get("type", "")) == "narration",
		"the beat on screen is the narration %s: %s" % [lid, sr.current_beat])
	_check(vd.is_playing() and vd.current_line == lid and vd.current_speaker == vd.narr_speaker,
		"%s plays in the narrator's voice: %s" % [lid, vd.state()])
	await _wait(0.4)
	_check(md.dialogue_active() and absf(md.duck_db_now - md.duck_dialogue_db) < 0.05, "music ducked under the scene narration (%.2f dB)" % md.duck_db_now)
	await _finish_dialogue()
	# 2. the choice inside the conversation with Pavel
	gs.reset()
	await _enter("Z1")
	var m13: Array = sd.scene("M13").get("mandatory_lines", [])
	var ci := -1
	for i in m13.size():
		if (m13[i] as Dictionary).has("options"):
			ci = i
			break
	_check(ci >= 0, "M13 has a choice line")
	if ci < 0:
		return
	var pk := String(m13[ci].get("prompt", "")).trim_prefix("@")
	_ensure_key(pk)
	var opt_id := String(m13[ci]["options"][1]["id"])
	var opt_lid := "M13_%d_%s" % [ci, opt_id]
	_check(String(_line(opt_lid).get("text", "")) != "", "%s: the option's words" % opt_lid)
	_ensure_voice(opt_lid)
	_force_requires("M13")
	_check(sr.start_scene("M13"), "M13 starts (requires forced)")
	for i in 120:
		var t := String(sr.current_beat.get("type", ""))
		if t == "options":
			break
		if t == "line" or t == "narration":
			sr.advance()
		await _wait(0.1)
	await _frames(2)
	_check(String(sr.current_beat.get("type", "")) == "options" and String(sr.current_beat.get("prompt_key", "")) == pk,
		"the choice beat carries its question's key %s: %s" % [pk, sr.current_beat])
	_check(vd.is_playing() and vd.current_line == _vid(pk) and vd.current_kind == "narration",
		"the question %s is voiced: %s" % [pk, vd.state()])
	sr.choose(opt_id)
	await _frames(2)
	_check(String(sr.current_beat.get("line_id", "")) == opt_lid, "the chosen words are the line %s: %s" % [opt_lid, sr.current_beat])
	_check(vd.is_playing() and vd.current_line == opt_lid and vd.current_speaker == "agata",
		"%s plays in Agata's voice: %s" % [opt_lid, vd.state()])
	await _finish_dialogue()


## H4/H14 (Director 24.10: «О чём спросить Пелагею» sounded at every click through the answers): voice.json →
## narration.ask_prompts — the question of a conversation is voiced the first time, then not again within
## repeat_after_s (300 s) of play time; another character's question has its own clock; other choices are not limited.
func _test_ask_prompt_once() -> void:
	gs.reset()
	await _enter("R1")
	_check(vd.ask_keys.has("R1.pelageya.prompt") and vd.ask_keys.has("H1.tikhon.prompt") and absf(vd.ask_repeat_s - 300.0) < 0.01,
		"voice.json ask_prompts: the NPC questions, 300 s: %s, %.0f" % [vd.ask_keys, vd.ask_repeat_s])
	for k in ["R1.pelageya.prompt", "Z1.tamara.prompt", "H1.cups.prompt"]:
		_ensure_key(k)
	var ask := func(key: String) -> void:
		sr.current_beat = {"type": "options", "prompt": sd.text("@" + key), "prompt_key": key, "options": [{"id": "x", "label": "x"}]}
		vd._on_beat_changed()
	var clear := func() -> void:
		sr.current_beat = {}
		vd._on_beat_changed()
	ask.call("R1.pelageya.prompt")
	_check(vd.is_playing() and vd.current_line == _vid("R1.pelageya.prompt"), "first showing: the question is voiced: %s" % [vd.state()])
	clear.call()
	vd.play_time_s += 30.0
	ask.call("R1.pelageya.prompt")
	_check(not vd.is_playing(), "shown again 30 s later: no voice: %s" % [vd.state()])
	var ev := _last_event("subtitles_only")
	_check(String(ev.get("reason", "")) == "ask_repeat", "the repeat is subtitles only (reason ask_repeat): %s" % [ev])
	_check(String(sr.current_beat.get("prompt", "")) != "", "the subtitle (prompt text) is still on screen")
	clear.call()
	ask.call("Z1.tamara.prompt")
	_check(vd.is_playing() and vd.current_line == _vid("Z1.tamara.prompt"), "another character's question has its own clock: %s" % [vd.state()])
	clear.call()
	for i in 2:
		ask.call("H1.cups.prompt")
		_check(vd.is_playing() and vd.current_line == _vid("H1.cups.prompt"), "a choice that is not a conversation question is voiced every time (%d)" % i)
		clear.call()
	paused = true
	var t0: float = vd.play_time_s
	await _frames(5)
	_check(absf(vd.play_time_s - t0) < 0.001, "pause does not count as play time")
	paused = false
	vd.play_time_s += vd.ask_repeat_s
	ask.call("R1.pelageya.prompt")
	_check(vd.is_playing() and vd.current_line == _vid("R1.pelageya.prompt"), "after 5 minutes of play the question is voiced again: %s" % [vd.state()])
	clear.call()
	vd.play_time_s += 1.0
	gs.reset()
	ask.call("R1.pelageya.prompt")
	_check(vd.is_playing(), "a new game: its first showing is voiced again")
	clear.call()
	for k in ["R1.pelageya.prompt", "Z1.tamara.prompt", "H1.cups.prompt"]:
		_drop_key(k)
