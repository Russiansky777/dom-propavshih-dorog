extends SceneTree
## Headless test of the background music (data/story/music.json → MusicDirector autoload). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_music.gd
## The Dummy driver mixes in real time, so playback positions advance; the checks read the decks'
## state (theme, playing/paused, position, fade gain, volume_db), the Music bus and the settings
## file — not the sound. Behind it — the Director's task of 17.10 «фоновая музыка»:
##   - every in_scope room plays its music.json theme, every location has one, all six streams load
##     with the stream's own loop off (the director loops by crossfade);
##   - H1 → H2 (same theme): the same deck keeps playing, never restarted, position keeps growing;
##   - H3 → O1: equal-power crossfade home → school over crossfade_s, then home paused;
##   - seamless loop: loop_crossfade_s before the end the other deck starts the track from 0 and the
##     two cross; the outgoing deck stops at the end;
##   - scene event: M10 in H2 → «mirror» over «home» (ducked under its line), scene end → home resumes
##     on its own deck where it was paused (not restarted);
##   - finale (loop: false, until track_end): the epilogue M26 → finale not ducked, holds through all its shots and
##     the scene end, fades over end_fade_s at the end, then the room theme returns;
##   - dialogue ducking: scene lines lower by duck_dialogue_db over ≈0.4 s (gradual), narration does not;
##   - music volume: slider/setting → Music bus, kept in user:// settings (not in a save slot),
##     survives loading a save; 0 % mutes;
##   - web gating: while locked (no user gesture yet) nothing starts; the first click starts the theme.
## Exit code 0 only when every check passed. Autoloads are reached through the tree (see run_tests.gd).

const TEST_SETTINGS := "user://test_music_settings.cfg"
const SLOT := "test_music"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var md: Node = null
var main_node: Node = null
var _saved_settings_path: String = ""
var _saved_volume: float = 1.0


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
	_saved_settings_path = md.settings_path
	_saved_volume = md.music_volume
	md.settings_path = TEST_SETTINGS
	_delete(TEST_SETTINGS)
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	print("audio driver: %s, mix %d Hz" % [AudioServer.get_driver_name(), AudioServer.get_mix_rate()])
	await _test("music.json loads; every in_scope room → its theme; every location has one; streams loop=false", _test_rooms)
	await _test("H1 → H2 (same theme): same deck, no restart, position keeps growing", _test_same_theme)
	await _test("H3 → O1: equal-power crossfade home → school over crossfade_s, home paused after", _test_crossfade)
	await _test("Seamless loop: loop_crossfade_s before the end the track restarts on the other deck and crosses", _test_loop)
	await _test("Dialogue ducking: scene lines −duck_dialogue_db over ≈0.4 s, narration not ducked", _test_duck)
	await _test("Scene event M10 → mirror over home (ducked), scene end → home resumes on its deck", _test_scene_event)
	await _test("Finale M26 (epilogue): not ducked, holds through every shot and past scene end, fades at the end, room theme returns", _test_finale)
	await _test("Music volume: setting → Music bus, user:// settings (not the save slot), menu slider, 0 % mutes", _test_volume)
	await _test("Web gating: nothing starts before the first user input; the first click starts the theme", _test_gating)
	gs.reset()
	gs.delete_save(SLOT)
	_delete(TEST_SETTINGS)
	md.settings_path = _saved_settings_path
	md.set_music_volume(_saved_volume, false)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== music: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
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


func _deck(i: int) -> Dictionary:
	return md.deck_state(i)


func _active() -> Dictionary:
	var i: int = md.active_deck_index()
	return _deck(i) if i >= 0 else {}


## Waits until `theme` is the active deck at full gain and the other deck is silent.
func _wait_settled(theme: String, timeout: float = 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		var i: int = md.active_deck_index()
		if i >= 0:
			var a := _deck(i)
			var o := _deck(1 - i)
			if a["theme"] == theme and a["playing"] and float(a["gain"]) >= 0.999 and not o["playing"]:
				return true
		await process_frame
	return false


func _enter(room: String, theme: String) -> bool:
	sr.call("_on_state_reset")  # no dialogue left over from the previous test
	rm.change_room(room, "")
	await _frames(2)
	return await _wait_settled(theme, md.crossfade_s + 3.0)


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


# --- Tests ---------------------------------------------------------------------------------

func _test_rooms() -> void:
	_check(md.config_errors.is_empty(), "music.json errors: %s" % [md.config_errors])
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Voice") >= 0,
		"buses Music/SFX/Voice must exist")
	for t in md.themes.keys():
		var s: AudioStream = md.stream_for(t)
		_check(s != null, "theme %s: stream %s does not load" % [t, md.theme_path(t)])
		if s != null:
			_check(not bool(s.get("loop")), "theme %s: stream loop must be off (crossfade loops it)" % t)
			_check(s.get_length() > 2.0 * md.loop_crossfade_s, "theme %s: track shorter than two loop crossfades" % t)
	for loc in sd.locations.keys():
		_check(md.theme_for_room(loc) != "" and md.themes.has(md.theme_for_room(loc)), "location %s has no valid theme" % loc)
	for rid in sd.rooms_index.get("in_scope", []):
		var want: String = md.theme_for_room(rid)
		rm.change_room(rid, "")
		await _frames(2)
		var a := _active()
		_check(md.target_theme == want, "%s: target %s, expected %s" % [rid, md.target_theme, want])
		_check(not a.is_empty() and a["theme"] == want and a["playing"] and a["bus"] == "Music",
			"%s: active deck %s, expected %s playing on Music" % [rid, a, want])
		_check(a.get("playback_type", -1) == AudioServer.PLAYBACK_TYPE_STREAM, "%s: playback type must be STREAM" % rid)


func _test_same_theme() -> void:
	_check(await _enter("H1", "home"), "H1: home did not settle")
	var i: int = md.active_deck_index()
	var before := _deck(i)
	var other_starts: int = int(_deck(1 - i)["starts"])
	rm.change_room("H2", "")
	await _frames(2)
	_check(md.target_theme == "home", "H2: target %s" % md.target_theme)
	_check(md.active_deck_index() == i, "H2: active deck changed %d → %d" % [i, md.active_deck_index()])
	await _wait(0.8)
	var after := _deck(i)
	_check(after["playing"] and after["theme"] == "home", "H2: home deck stopped: %s" % [after])
	_check(int(after["starts"]) == int(before["starts"]), "H2: home restarted (%d → %d play calls)" % [before["starts"], after["starts"]])
	_check(float(after["position"]) > float(before["position"]) + 0.5,
		"H2: position must keep growing: %.2f → %.2f s" % [before["position"], after["position"]])
	_check(float(after["gain"]) >= 0.999, "H2: home must stay at full gain, got %.3f" % after["gain"])
	_check(int(_deck(1 - i)["starts"]) == other_starts and not _deck(1 - i)["playing"], "H2: the other deck must not start")


func _test_crossfade() -> void:
	_check(await _enter("H3", "home"), "H3: home did not settle")
	var h: int = md.active_deck_index()
	rm.change_room("O1", "")
	await _frames(2)
	var s: int = md.active_deck_index()
	_check(md.target_theme == "school", "O1: target %s, expected school" % md.target_theme)
	_check(s >= 0 and s != h and _deck(s)["theme"] == "school" and _deck(s)["playing"], "O1: school must start on the other deck")
	_check(_deck(h)["playing"] and float(_deck(h)["fade_to"]) == 0.0, "O1: home must be fading out")
	await _wait(md.crossfade_s * 0.5)
	var gi := float(_deck(s)["gain"])
	var go := float(_deck(h)["gain"])
	_check(gi > 0.3 and gi < 0.97 and go > 0.3 and go < 0.97, "mid-crossfade gains in %.2f / out %.2f" % [gi, go])
	_check(absf(gi * gi + go * go - 1.0) < 0.12, "equal power: in² + out² = %.2f" % (gi * gi + go * go))
	_check(float(_deck(s)["volume_db"]) < float(md.themes["school"]["volume_db"]) - 0.5, "mid-crossfade school must be below full volume")
	await _wait(md.crossfade_s * 0.5 + 0.5)
	_check(not _deck(h)["playing"] and _deck(h)["paused"], "after crossfade home must be paused: %s" % [_deck(h)])
	_check(float(_deck(s)["gain"]) >= 0.999, "after crossfade school at full gain")
	_check(absf(float(_deck(s)["volume_db"]) - float(md.themes["school"]["volume_db"])) < 0.1,
		"school volume_db %.2f, expected the theme's %.1f" % [_deck(s)["volume_db"], md.themes["school"]["volume_db"]])


func _test_loop() -> void:
	_check(await _enter("Z1", "roads"), "Z1: roads did not settle")
	var a: int = md.active_deck_index()
	var d: Dictionary = _deck(a)
	var length := float(d["length"])
	var passes: int = md.loop_passes
	var player: AudioStreamPlayer = md.get_child(a) as AudioStreamPlayer
	player.seek(length - md.loop_crossfade_s - 1.0)
	await _wait(0.5)
	_check(md.loop_passes == passes and md.active_deck_index() == a, "loop must not start before length − loop_crossfade_s")
	await _wait(1.0)
	var b: int = md.active_deck_index()
	_check(md.loop_passes == passes + 1, "loop pass must start at length − loop_crossfade_s")
	_check(b == 1 - a and _deck(b)["theme"] == "roads" and _deck(b)["playing"], "loop: the other deck must play roads")
	_check(float(_deck(b)["position"]) < 1.5, "loop: the new pass starts from the beginning (%.2f s)" % _deck(b)["position"])
	_check(_deck(a)["playing"], "loop: the old pass keeps sounding while they cross")
	await _wait(md.loop_crossfade_s * 0.5 - 0.5)
	var gi := float(_deck(b)["gain"])
	var go := float(_deck(a)["gain"])
	_check(gi > 0.2 and go > 0.2 and absf(gi * gi + go * go - 1.0) < 0.15, "loop crossfade gains in %.2f / out %.2f" % [gi, go])
	await _wait(md.loop_crossfade_s * 0.5 + 1.0)
	_check(not _deck(a)["playing"] and not _deck(a)["paused"], "loop: the old pass must be stopped at its end: %s" % [_deck(a)])
	_check(float(_deck(b)["gain"]) >= 0.999 and float(_deck(b)["position"]) > md.loop_crossfade_s - 0.5,
		"loop: new pass at full gain and running (%.2f s)" % _deck(b)["position"])


func _test_duck() -> void:
	_check(await _enter("Z1", "roads"), "Z1: roads did not settle")
	var full := float(md.themes["roads"]["volume_db"])
	sr.narrate("Проверка: осмотр не приглушает музыку.")
	await _wait(0.5)
	_check(not md.dialogue_active() and absf(md.duck_db_now) < 0.01, "narration must not duck (duck %.2f)" % md.duck_db_now)
	await _finish_dialogue()
	_check(sr.start_scene("M01"), "M01 must start in Z1")
	await _wait(0.12)
	_check(md.dialogue_active(), "a scene line is dialogue")
	_check(md.duck_db_now < -0.3 and md.duck_db_now > md.duck_dialogue_db + 0.5,
		"ducking must be gradual: %.2f dB after 0.12 s" % md.duck_db_now)
	await _wait(0.45)
	_check(absf(md.duck_db_now - md.duck_dialogue_db) < 0.05, "ducked to %.2f dB, expected %.1f" % [md.duck_db_now, md.duck_dialogue_db])
	_check(absf(float(_active()["volume_db"]) - (full + md.duck_dialogue_db)) < 0.1,
		"roads during dialogue %.2f dB, expected %.1f" % [_active()["volume_db"], full + md.duck_dialogue_db])
	await _finish_dialogue()
	await _wait(0.5)
	_check(absf(md.duck_db_now) < 0.01 and absf(float(_active()["volume_db"]) - full) < 0.1, "after the dialogue back to %.1f dB" % full)


func _test_scene_event() -> void:
	gs.reset()
	_check(await _enter("H2", "home"), "H2: home did not settle")
	var h: int = md.active_deck_index()
	var home_before := _deck(h)
	# M10's requirements (E2, block 2): the agreement with Pavel; the scene starts by data (rooms/H2.json:
	# complete_when office_mirror_clamped — the wedges of the office mirror on the stand «ЗМ»).
	gs.set_flag("seen_workshop")
	gs.set_flag("done_M09b")
	gs.set_flag("office_mirror_clamped")
	await _frames(3)
	if sr.active_scene != "M10":
		sr.start_scene("M10")
		await _frames(2)
	_check(sr.active_scene == "M10", "M10 must be running, active scene '%s'" % sr.active_scene)
	_check(md.target_theme == "mirror" and md.active_events.size() == 1, "M10: target %s, events %s" % [md.target_theme, md.state()["events"]])
	var m: int = md.active_deck_index()
	_check(m == 1 - h and _deck(m)["theme"] == "mirror" and float(_deck(m)["position"]) < 1.0, "M10: mirror must start from 0 on the other deck")
	await _wait(md.crossfade_s + 0.5)
	_check(_deck(h)["paused"], "M10: home must be paused under the event")
	_check(absf(float(_deck(m)["volume_db"]) - (float(md.themes["mirror"]["volume_db"]) + md.duck_dialogue_db)) < 0.15,
		"M10: mirror under the line ducked: %.2f dB" % _deck(m)["volume_db"])
	var p1 := float(_deck(h)["position"])
	await _wait(1.0)
	var home_paused_pos := float(_deck(h)["position"])
	_check(absf(home_paused_pos - p1) < 0.05, "M10: paused home position frozen (%.2f → %.2f)" % [p1, home_paused_pos])
	await _finish_dialogue()
	await _frames(2)
	_check(gs.has_flag("done_M10"), "M10 must complete")
	_check(md.target_theme == "home" and md.active_events.is_empty(), "after M10: target %s, events %s" % [md.target_theme, md.state()["events"]])
	_check(md.active_deck_index() == h, "after M10: home must come back on its own deck")
	await _wait(md.crossfade_s + 0.5)
	var home_after := _deck(h)
	_check(home_after["playing"] and int(home_after["starts"]) == int(home_before["starts"]),
		"after M10: home resumed, not restarted (%d → %d play calls)" % [home_before["starts"], home_after["starts"]])
	_check(float(home_after["position"]) > home_paused_pos + 1.0, "after M10: home position goes on from %.2f (now %.2f)" % [home_paused_pos, home_after["position"]])
	_check(not _deck(m)["playing"], "after M10: mirror faded out")


func _test_finale() -> void:
	gs.reset()
	_check(await _enter("Z3", "roads"), "Z3: roads did not settle")
	# The epilogue M26 (block 4, data/story/scenes/E5.json) starts by itself at the turn once the first span is laid.
	gs.set_flag("done_M25")
	await _frames(3)
	if sr.active_scene != "M26":
		sr.start_scene("M26")
		await _frames(2)
	_check(sr.active_scene == "M26", "M26 must be running, active scene '%s'" % sr.active_scene)
	_check(md.target_theme == "finale", "M26: target %s" % md.target_theme)
	var f: int = md.active_deck_index()
	var starts: int = int(_deck(f)["starts"])
	await _wait(md.crossfade_s + 0.5)
	while sr.is_staging():
		await process_frame
	await _frames(2)
	_check(md.dialogue_active(), "M26 line is dialogue")
	_check(absf(float(_deck(f)["volume_db"]) - float(md.themes["finale"]["volume_db"])) < 0.1,
		"finale is in duck_except: %.2f dB, expected %.1f" % [_deck(f)["volume_db"], md.themes["finale"]["volume_db"]])
	# Through every shot of the epilogue (stagings with frames) to its end.
	var guard := 0
	while not gs.has_flag("done_M26") and guard < 3000:
		guard += 1
		if sr.is_staging() or sr.current_beat.is_empty():
			await process_frame
			continue
		if String(sr.current_beat.get("type", "")) == "options":
			sr.choose(String(sr.current_options()[0]["id"]))
		else:
			sr.advance()
		await _frames(2)
	await _frames(4)
	_check(gs.has_flag("done_M26"), "M26 must complete")
	_check(md.target_theme == "finale" and md.active_deck_index() == f and int(_deck(f)["starts"]) == starts,
		"finale holds through all epilogue shots on the same deck without restart")
	var length := float(_deck(f)["length"])
	(md.get_child(f) as AudioStreamPlayer).seek(length - md.end_fade_s - 1.0)
	await _wait(1.6)
	_check(float(_deck(f)["fade_to"]) == 0.0 and float(_deck(f)["gain"]) < 0.95, "finale fades over its last end_fade_s (gain %.2f)" % _deck(f)["gain"])
	await _wait(md.end_fade_s + 0.5)
	_check(not _deck(f)["playing"], "finale must have ended")
	_check(md.active_events.is_empty() and md.target_theme == "roads", "after the finale: events %s, target %s" % [md.state()["events"], md.target_theme])
	_check(await _wait_settled("roads", md.crossfade_s + 2.0), "after the finale the room theme (roads) returns")


func _test_volume() -> void:
	gs.reset()
	_check(await _enter("Z1", "roads"), "Z1: roads did not settle")
	var bus: int = AudioServer.get_bus_index("Music")
	_delete(TEST_SETTINGS)
	md.set_music_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(bus) - md.volume_to_db(0.5)) < 0.01 and not AudioServer.is_bus_mute(bus),
		"50 %%: Music bus %.2f dB, expected %.2f" % [AudioServer.get_bus_volume_db(bus), md.volume_to_db(0.5)])
	_check(absf(md.volume_to_db(0.5) - linear_to_db(0.25)) < 0.01, "50 % is −12 dB (squared amplitude)")
	await _wait(md.SAVE_DELAY_S + 0.3)
	var cf := ConfigFile.new()
	_check(cf.load(TEST_SETTINGS) == OK and absf(float(cf.get_value("audio", "music_volume", -1.0)) - 0.5) < 0.001,
		"the setting must be saved to %s" % TEST_SETTINGS)
	md.set_music_volume(1.0, false)
	md.load_settings()
	_check(absf(md.music_volume - 0.5) < 0.001 and absf(AudioServer.get_bus_volume_db(bus) - md.volume_to_db(0.5)) < 0.01,
		"load_settings must restore 50 %% (got %.2f)" % md.music_volume)
	# Not part of a save slot: loading a game keeps the current volume.
	_check(rm.save_game(SLOT), "save slot")
	var saved_text := FileAccess.get_file_as_string(gs.save_path(SLOT))
	_check(saved_text.find("music") < 0, "the save slot must not contain music settings")
	md.set_music_volume(0.3, false)
	_check(rm.load_game(SLOT), "load slot")
	await _frames(2)
	_check(absf(md.music_volume - 0.3) < 0.001, "loading a save must not change the music volume (got %.2f)" % md.music_volume)
	# Menu slider (game_ui.gd): 40 % → MusicDirector 0.4 → bus.
	var ui: Node = main_node.get_node("GameUi")
	ui.call("toggle_menu")
	await _frames(2)
	var slider: HSlider = ui.get("music_slider")
	_check(slider != null and slider.is_visible_in_tree(), "menu must show the music slider")
	if slider != null:
		_check(absf(slider.value - 30.0) < 0.5, "slider shows the current volume (%.0f)" % slider.value)
		slider.value = 40
		await _frames(1)
		_check(absf(md.music_volume - 0.4) < 0.001 and absf(AudioServer.get_bus_volume_db(bus) - md.volume_to_db(0.4)) < 0.01,
			"slider 40 → volume %.2f, bus %.2f dB" % [md.music_volume, AudioServer.get_bus_volume_db(bus)])
		var probe: Dictionary = ui.call("probe_positions")
		_check(probe.has("music_slider") and float(probe["music_slider"].get("w", 0)) > 200, "probe publishes the slider rect")
		slider.value = 0
		await _frames(1)
		_check(AudioServer.is_bus_mute(bus), "0 % mutes the Music bus")
	ui.call("toggle_menu")
	md.set_music_volume(1.0, false)
	_check(not AudioServer.is_bus_mute(bus) and absf(AudioServer.get_bus_volume_db(bus)) < 0.01, "100 % → 0 dB, unmuted")


func _test_gating() -> void:
	gs.reset()
	_check(await _enter("Z1", "roads"), "Z1: roads did not settle")
	md.unlocked = false
	rm.change_room("O1", "")
	await _frames(2)
	await _wait(0.3)
	_check(md.target_theme == "school", "locked: the target still follows the room (%s)" % md.target_theme)
	var started := false
	for i in 2:
		if _deck(i)["theme"] == "school" and _deck(i)["playing"]:
			started = true
	_check(not started, "locked: school must not start before the first user input")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(960, 540)
	Input.parse_input_event(ev)
	await _frames(3)
	_check(md.unlocked, "the first click must unlock the music")
	_check(_active().get("theme", "") == "school" and _active().get("playing", false), "after the click school plays")
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)
