extends SceneTree
## Headless test of the sound effects (data/story/sfx.json → SfxDirector autoload). Usage:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_sfx.gd
## Reads SfxDirector events (kind, sound, file, frame, surface), its players and the buses — not the
## sound. Behind it — the Director's sound table of 17.10:
##   - every sound file loads; loops loop, one-shots do not; buses SFX and SFX_Inside (low-pass);
##   - steps: while Agata walks a step sounds on every foot-plant frame of the walk sheet and only
##     there — the same frames as AmbientFootfall's splashes/prints in Z2 (one step event per its
##     step); by the room surface: H1 (wood) → soft steps, Z2 (gravel) → gravel; R1 deck → wood;
##     takes vary (never the same twice in a row) with pitch/volume spread inside the data's bounds;
##   - doors: one door sound per transition through a door exit (H1 → H2 light door, Z2 → H1 heavy),
##     none for a street passage (Z4 → Z2), a loaded save or a new game; it keeps playing after the
##     room change;
##   - stove fire: only in H1 while stove_lit, fades in, louder near the stove than across the room,
##     stops when the stove is out or Agata leaves H1;
##   - rain: outside (Z2) on SFX at outside_db, inside (H1) on SFX_Inside (low-pass) at inside_db,
##     none in the school (O1);
##   - bag: game_ui.gd bag_sound_requested(receive/select/deselect) → bag sounds;
##   - sound volume: setting → SFX bus, user:// settings next to the music volume, menu slider.
## Exit code 0 only when every check passed. Autoloads are reached through the tree.

const TEST_SETTINGS := "user://test_sfx_settings.cfg"
const SLOT := "test_sfx"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sx: Node = null
var md: Node = null
var main_node: Node = null
var player: Node2D = null
var _saved_paths: Array = []


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
	sx = root.get_node("SfxDirector")
	md = root.get_node("MusicDirector")
	_saved_paths = [sx.settings_path, md.settings_path, sx.sfx_volume]
	sx.settings_path = TEST_SETTINGS
	md.settings_path = TEST_SETTINGS
	_delete(TEST_SETTINGS)
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("sfx.json loads; every sound file loads; loops loop, one-shots do not; SFX and SFX_Inside buses", _test_data)
	await _test("Steps: on the walk sheet's foot-plant frames only, by room surface (H1 wood, Z2 gravel = AmbientFootfall steps)", _test_steps)
	await _test("Doors: one sound per door transition, none for a street, a load or a new game; plays on through the change", _test_doors)
	await _test("Stove fire: only in H1 with stove_lit, fades in, louder near the stove, stops when out or away", _test_fire)
	await _test("Rain: outside on SFX, inside (house) quieter on the low-passed SFX_Inside, none in the school", _test_rain)
	await _test("Bag: game_ui bag_sound_requested(receive/select/deselect) → bag sounds", _test_bag)
	await _test("Sound volume: setting → SFX bus, user:// settings next to the music volume, menu slider", _test_volume)
	gs.reset()
	gs.delete_save(SLOT)
	_delete(TEST_SETTINGS)
	sx.settings_path = _saved_paths[0]
	md.settings_path = _saved_paths[1]
	sx.set_sfx_volume(float(_saved_paths[2]), false)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== sfx: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers ----------------------------------------------------------------------------------

func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _events(kind: String, since: int) -> Array:
	var out: Array = []
	for i in range(since, sx.events.size()):
		if sx.events[i]["kind"] == kind:
			out.append(sx.events[i])
	return out


func _enter(room: String) -> void:
	rm.change_room(room, "")
	for i in 4:
		await physics_frame


func _walk(from: Vector2, to: Vector2) -> void:
	player.call("enter_room", rm.current_room, from)
	for i in 4:
		await physics_frame
	player.call("walk_to", to)
	var frames := 0
	while player.call("is_walking") and frames < 900:
		await physics_frame
		frames += 1


func _contacts() -> Array[int]:
	var out: Array[int] = []
	for f in load("res://scripts/ambient/ambient_data.gd").footfall("agata").get("contact_frames", []):
		out.append(int(f))
	return out


# --- Tests -------------------------------------------------------------------------------------

func _test_data() -> void:
	_check(sx.config_errors.is_empty(), "sfx.json errors: %s" % [sx.config_errors])
	for sid in sx.sounds.keys():
		for f in sx.sounds[sid].get("files", []):
			var s: AudioStream = sx.stream_for(String(f))
			_check(s != null, "%s: %s does not load" % [sid, f])
			if s is AudioStreamWAV:
				_check((s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s: one-shot %s must not loop" % [sid, f])
	for lid in sx.loops.keys():
		var s: AudioStream = sx.stream_for(String(sx.loops[lid]["file"]))
		_check(s != null and bool(s.get("loop")), "loop %s: %s must load with loop=true" % [lid, sx.loops[lid]["file"]])
	var inside: int = AudioServer.get_bus_index("SFX_Inside")
	_check(AudioServer.get_bus_index("SFX") >= 0 and inside >= 0, "buses SFX and SFX_Inside must exist")
	if inside >= 0:
		_check(AudioServer.get_bus_send(inside) == &"SFX", "SFX_Inside must send to SFX")
		var lp := false
		for i in AudioServer.get_bus_effect_count(inside):
			var e := AudioServer.get_bus_effect(inside, i)
			if e is AudioEffectLowPassFilter and absf((e as AudioEffectLowPassFilter).cutoff_hz - float(sx.loops["rain"]["inside_lowpass_hz"])) < 1.0:
				lp = true
		_check(lp, "SFX_Inside must low-pass at loops.rain.inside_lowpass_hz")


func _test_steps() -> void:
	gs.reset()
	var contacts := _contacts()
	# H1: wooden floor → soft steps.
	await _enter("H1")
	var e0: int = sx.events.size()
	var n0: int = sx.step_count
	await _walk(Vector2(700, 990), Vector2(1600, 990))
	var steps := _events("step", e0)
	print("    H1 walk: %d steps" % steps.size())
	_check(steps.size() >= 3, "H1: expected ≥ 3 steps over 900 px, got %d" % steps.size())
	_check(sx.step_count - n0 == steps.size(), "every step plays a sound (%d steps, %d sounds)" % [sx.step_count - n0, steps.size()])
	var files := {}
	var prev := ""
	var repeats := 0
	for e in steps:
		_check(int(e["frame"]) in contacts, "H1: step on sheet frame %d, not a contact frame %s" % [int(e["frame"]), str(contacts)])
		_check(e["surface"] == "wood" and e["sound"] == "steps_soft", "H1: step %s/%s, expected wood/steps_soft" % [e["surface"], e["sound"]])
		var spec: Dictionary = sx.sounds["steps_soft"]
		_check(absf(float(e["pitch"]) - 1.0) <= float(spec["pitch_jitter"]) + 1e-4, "pitch %.3f outside the data's spread" % float(e["pitch"]))
		_check(absf(float(e["volume_db"]) - float(spec["volume_db"])) <= float(spec["volume_jitter_db"]) + 1e-4, "volume %.2f outside the spread" % float(e["volume_db"]))
		files[e["file"]] = true
		if e["file"] == prev:
			repeats += 1
		prev = e["file"]
	_check(repeats == 0, "the same take twice in a row %d time(s)" % repeats)
	_check(steps.size() < 3 or files.size() >= 2, "takes must vary (%d distinct of %d)" % [files.size(), steps.size()])
	# Standing still: no steps.
	var e1: int = sx.events.size()
	await _wait(0.8)
	_check(_events("step", e1).is_empty(), "no step sounds while standing")
	# Z2: gravel; the same frames as AmbientFootfall (splashes / prints) — one sound per its step.
	await _enter("Z2")
	var amb = load("res://scripts/ambient/ambient_builder.gd").of(rm.current_room)
	var ff = amb.footfall if amb != null else null
	_check(ff != null, "Z2 has no AmbientFootfall to compare with")
	var ff0: int = ff.steps if ff != null else 0
	var e2: int = sx.events.size()
	await _walk(Vector2(1200, 835), Vector2(1790, 862))
	var z2 := _events("step", e2)
	print("    Z2 walk: %d steps (AmbientFootfall %d)" % [z2.size(), (ff.steps - ff0) if ff != null else -1])
	_check(z2.size() >= 3, "Z2: expected ≥ 3 steps, got %d" % z2.size())
	if ff != null:
		_check(z2.size() == ff.steps - ff0, "Z2: %d step sounds, AmbientFootfall planted %d feet" % [z2.size(), ff.steps - ff0])
		var n: int = mini(z2.size(), ff.events.size())
		for i in n:
			var a: Dictionary = z2[z2.size() - n + i]
			var b: Dictionary = ff.events[ff.events.size() - n + i]
			_check(int(a["frame"]) == int(b["frame"]) and (a["pos"] as Vector2).distance_to(b["pos"]) < 0.5,
				"Z2 step %d: sound at frame %d %s, footfall at frame %d %s" % [i, a["frame"], a["pos"], b["frame"], b["pos"]])
	for e in z2:
		_check(e["surface"] == "gravel" and e["sound"] == "steps_gravel", "Z2: step %s/%s, expected gravel" % [e["surface"], e["sound"]])
	# R1: the pier deck is wood, the bank gravel (areas).
	_check(sx.surface_at("R1", Vector2(1200, 650)) == "wood" and sx.surface_at("R1", Vector2(900, 900)) == "gravel",
		"R1: deck must be wood, bank gravel (%s / %s)" % [sx.surface_at("R1", Vector2(1200, 650)), sx.surface_at("R1", Vector2(900, 900))])


func _test_doors() -> void:
	gs.reset()
	await _enter("H1")
	await _wait(0.2)
	var e0: int = sx.events.size()
	await _enter("H2")
	var d := _events("door", e0)
	_check(d.size() == 1 and d[0]["exit"] == "H1>H2" and d[0]["sound"] == "door_light", "H1 → H2: one light door, got %s" % [d])
	var dp: AudioStreamPlayer = sx.get_node("Door")
	await _wait(0.6)
	_check(dp.playing, "the door sound plays on after the room change")
	_check(_events("door", e0).size() == 1, "still exactly one door sound 0.6 s later")
	# Street passage: no door. Front door of the house: heavy.
	await _enter("Z4")   # H2 → Z4 is not adjacent (a direct jump in the test): no door entry
	var e1: int = sx.events.size()
	await _enter("Z2")
	_check(_events("door", e1).is_empty(), "Z4 → Z2 is a street: no door sound")
	var e2: int = sx.events.size()
	await _enter("H1")
	d = _events("door", e2)
	_check(d.size() == 1 and d[0]["sound"] == "door_heavy", "Z2 → H1: one heavy door, got %s" % [d])
	# A loaded save and a new game open no door (even when the rooms are door-adjacent).
	_check(rm.save_game(SLOT), "save slot")
	await _enter("H2")
	var e3: int = sx.events.size()
	_check(rm.load_game(SLOT), "load slot (H1)")
	await _frames(3)
	_check(_events("door", e3).is_empty(), "loading a save must not play a door: %s" % [_events("door", e3)])
	await _enter("Z1")
	var e4: int = sx.events.size()
	rm.new_game()   # starts in Z1 → … no transition
	await _frames(3)
	_check(_events("door", e4).is_empty(), "a new game must not play a door")


func _test_fire() -> void:
	gs.reset()
	await _enter("H1")
	var fire: AudioStreamPlayer2D = sx.get_node("StoveFire")
	await _wait(0.5)
	_check(not fire.playing, "stove out: no fire sound")
	gs.set_flag("stove_lit")
	await _frames(2)
	_check(fire.playing, "stove lit: the fire starts")
	await _wait(0.2)
	_check(fire.volume_db < sx.fire_gain_db - 1.0, "the fire fades in (%.1f dB vs %.1f)" % [fire.volume_db, sx.fire_gain_db])
	var spec: Dictionary = sx.loops["stove_fire"]
	await _wait(float(spec["fade_s"]) + 0.3)
	player.call("enter_room", rm.current_room, Vector2(330, 815))
	await _frames(3)
	var near: float = fire.volume_db
	player.call("enter_room", rm.current_room, Vector2(1750, 990))
	await _frames(3)
	var far: float = fire.volume_db
	_check(near > far + 3.0, "louder near the stove: near %.1f dB, far %.1f dB" % [near, far])
	_check(absf(near - sx.fire_distance_db(Vector2(330, 815).distance_to(Vector2(spec["pos"][0], spec["pos"][1])))) < 0.2, "near volume follows the distance curve")
	_check(fire.global_position == Vector2(spec["pos"][0], spec["pos"][1]), "the fire sounds from the stove mouth")
	# Leaving H1 stops it; coming back with the stove lit starts it again; putting it out stops it.
	await _enter("H2")
	await _wait(float(spec["fade_s"]) + 0.3)
	_check(not fire.playing, "away from H1: no fire")
	await _enter("H1")
	await _frames(2)
	_check(fire.playing, "back in H1 with the stove lit: fire again")
	gs.set_flag("stove_lit", false)
	await _wait(float(spec["fade_s"]) + 0.3)
	_check(not fire.playing, "stove out again: the fire stops")


func _test_rain() -> void:
	gs.reset()
	var rain: AudioStreamPlayer = sx.get_node("Rain")
	var spec: Dictionary = sx.loops["rain"]
	await _enter("Z2")
	await _wait(float(spec["fade_s"]) + 0.3)
	_check(rain.playing and rain.bus == &"SFX" and absf(rain.volume_db - float(spec["outside_db"])) < 0.2,
		"Z2: rain outside on SFX at %.1f dB (playing %s, bus %s, %.1f dB)" % [float(spec["outside_db"]), rain.playing, rain.bus, rain.volume_db])
	await _enter("H1")
	await _wait(0.2)
	_check(rain.playing and rain.bus == &"SFX_Inside" and absf(rain.volume_db - float(spec["inside_db"])) < 0.2,
		"H1: rain inside on SFX_Inside at %.1f dB (bus %s, %.1f dB)" % [float(spec["inside_db"]), rain.bus, rain.volume_db])
	gs.set_flag("o1_saw_winter", true)   # no first-entry line (rooms/O1.json on_enter): the menu below must open
	await _enter("O1")
	await _wait(float(spec["fade_s"]) + 0.3)
	_check(not rain.playing, "O1 (winter school): no rain")


func _test_bag() -> void:
	var ui: Node = main_node.get_node("GameUi")
	_check(ui.has_signal("bag_sound_requested"), "game_ui.gd must have bag_sound_requested")
	if not ui.has_signal("bag_sound_requested"):
		return
	for kind in ["receive", "select", "deselect"]:
		var e0: int = sx.events.size()
		ui.emit_signal("bag_sound_requested", kind)
		var b := _events("bag", e0)
		var want := String(sx.bag_map[kind])
		_check(b.size() == 1 and b[0]["sound"] == want, "bag %s → %s, got %s" % [kind, want, b])
	_check((sx.get_node("Bag") as AudioStreamPlayer).playing, "the bag sound plays")


func _test_volume() -> void:
	var bus: int = AudioServer.get_bus_index("SFX")
	_delete(TEST_SETTINGS)
	md.set_music_volume(0.8, false)
	md.save_settings()
	sx.set_sfx_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(bus) - sx.volume_to_db(0.5)) < 0.01, "50 %%: SFX bus %.2f dB" % AudioServer.get_bus_volume_db(bus))
	await _wait(sx.SAVE_DELAY_S + 0.3)
	var cf := ConfigFile.new()
	_check(cf.load(TEST_SETTINGS) == OK, "settings saved")
	_check(absf(float(cf.get_value("audio", "sfx_volume", -1.0)) - 0.5) < 0.001 and absf(float(cf.get_value("audio", "music_volume", -1.0)) - 0.8) < 0.001,
		"settings keep both: sfx 0.5 and music 0.8 (%s / %s)" % [cf.get_value("audio", "sfx_volume", null), cf.get_value("audio", "music_volume", null)])
	sx.set_sfx_volume(1.0, false)
	sx.load_settings()
	_check(absf(sx.sfx_volume - 0.5) < 0.001, "load_settings restores 50 %")
	var ui: Node = main_node.get_node("GameUi")
	ui.call("toggle_menu")
	await _frames(2)
	var slider: HSlider = ui.get("sfx_slider")
	_check(slider != null and slider.is_visible_in_tree(), "menu shows the «Звуки» slider")
	if slider != null:
		_check(absf(slider.value - 50.0) < 0.5, "slider shows the current volume (%.0f)" % slider.value)
		slider.value = 0
		await _frames(1)
		_check(AudioServer.is_bus_mute(bus) and sx.sfx_volume == 0.0, "0 % mutes the SFX bus")
		var probe: Dictionary = ui.call("probe_positions")
		_check(probe.has("sfx_slider"), "probe publishes the sound slider rect")
	ui.call("toggle_menu")
	sx.set_sfx_volume(1.0, false)
	md.set_music_volume(1.0, false)
