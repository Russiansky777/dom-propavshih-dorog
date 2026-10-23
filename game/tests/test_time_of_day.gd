extends SceneTree
## Time of day (F17, Director 23.10: «ещё раз подумать над временами дня, чтобы они скоординированно со
## сценарием и логикой сменялись»): data/story/time, game/scripts/core/time_of_day.gd, rooms/time_grade.gd.
##   godot --headless --path game -s res://tests/test_time_of_day.gd
## Checks:
##   - the whole main story in order (grants piled up as RoomManager.start_at does): every main scene starts in
##     exactly the state data/story/time/_index.json → scenes (Docs/TIME_OF_DAY.md) says; the state never runs
##     back, the day never goes down;
##   - virtual flags tod_<state> / tod_<phase> / tod_day<N> / tod_dark answer from the story, are never written
##     into the state or the save, and a save restores the time by itself;
##   - rooms: Z2 (no lights — the multiply polygon) and H1/Z3/R1 (lights — ambient sources) take the grade of
##     the state; painted states are left alone; the old «dusk» tints are replaced; lit windows by flags;
##   - a change in the room eases over fade_s, entering / loading shows the final look at once;
##   - the cut-off school keeps its own clock until the road returns; the journal shows the time.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var ui: Node = null
var TOD = null     # TimeOfDay (loaded at run time: autoloads do not exist yet when -s compiles)
var SLOT := "test_tod_%d" % OS.get_process_id()


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
	TOD = load("res://scripts/core/time_of_day.gd")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	ui = main_node.get_node("GameUi")
	await _test("Story order: every main scene starts in its one state (table = flags); time never runs back, days never go down", _test_story)
	await _test("Virtual flags tod_*: from the story, never stored; a save restores the time by itself", _test_virtual)
	await _test("Rooms: grade by state — polygon (Z2) / room light (H1, Z3, R1); painted states untouched; old dusk tints replaced; windows", _test_rooms)
	await _test("In the room a change eases over fade_s; entering and loading show the final look at once", _test_transitions)
	await _test("The cut-off school keeps its own clock; the journal shows the time", _test_local_and_journal)
	gs.reset()
	gs.delete_save(SLOT)
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== time of day: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room: String) -> void:
	sr.call("_on_state_reset")
	rm.change_room(room, "")
	await _frames(3)
	sr.call("_on_state_reset")
	await _frames(1)


func _main_scenes() -> Array:
	var out: Array = []
	for id in sd.scene_order:
		if String(sd.scene(id).get("type", "")) == "main":
			out.append(id)
	return out


## The story up to (not including) scene `upto`: done_<scene> and the grants of every main scene before it.
func _flags_before(upto: String) -> void:
	gs.reset()
	for id in _main_scenes():
		if id == upto:
			return
		gs.flags["done_" + id] = true
		for f in sd.scene(id).get("grants", {}).get("flags", []):
			gs.flags[String(f)] = true


func _state_index(st: String) -> int:
	var i := 0
	for s in TOD.states():
		if String(s.get("id", "")) == st:
			return i
		i += 1
	return -1


func _grade_node() -> Node:
	return rm.current_room.get_node_or_null("TimeOfDay")


func _light_source(id: String) -> Node:
	var l: Node = rm.current_room.get_node_or_null("Lighting")
	return l.get_node_or_null(id) if l != null else null


# --- 1. Story order ------------------------------------------------------------------------

func _test_story() -> void:
	var table: Dictionary = TOD.index().get("scenes", {})
	var prev := -1
	var prev_day := 0
	var mains := _main_scenes()
	_check(mains.size() >= 30, "the main story is there (%d scenes)" % mains.size())
	for id in mains:
		_flags_before(id)
		var st: String = TOD.current_state()
		_check(st != "", "%s: a state" % id)
		_check(String(table.get(id, "")) == st, "%s: table says %s, flags give %s" % [id, String(table.get(id, "—")), st])
		var i := _state_index(st)
		_check(i >= prev, "%s: time runs back (%s)" % [id, st])
		var day: int = TOD.day_of(st)
		_check(day >= prev_day, "%s: day %d after day %d" % [id, day, prev_day])
		prev = maxi(prev, i)
		prev_day = maxi(prev_day, day)
	for k in table.keys():
		if not String(k).begins_with("_"):
			_check(mains.has(String(k)), "table lists %s, not a main scene" % k)
	# Inside a day the phases go morning → midday → afternoon/day → dusk → evening → night.
	var order := {"morning": 0, "midday": 1, "afternoon": 2, "day": 2, "dusk": 3, "evening": 4, "night": 5}
	var pd := 0
	var pp := -1
	for s in TOD.states():
		if bool(s.get("room_only", false)):
			continue
		var d := int(s.get("day", 0))
		var p := int(order.get(String(s.get("phase", "")), -1))
		_check(p >= 0, "state %s: phase %s" % [s.get("id"), s.get("phase")])
		if d == pd:
			_check(p >= pp, "state %s: phase goes back inside day %d" % [s.get("id"), d])
		pd = d
		pp = p
	gs.reset()


# --- 2. Virtual flags ----------------------------------------------------------------------

func _test_virtual() -> void:
	_flags_before("M15s")   # after mother's mirror: dusk of day two
	_check(TOD.current_state() == "d2_dusk", "after M15а — d2_dusk (%s)" % TOD.current_state())
	for f in ["tod_d2_dusk", "tod_dusk", "tod_day2", "tod_dark"]:
		_check(gs.has_flag(f), "%s holds at dusk of day two" % f)
	for f in ["tod_d2_evening", "tod_morning", "tod_day1", "tod_day3", "tod_night"]:
		_check(not gs.has_flag(f), "%s does not hold at dusk of day two" % f)
	var d: Dictionary = gs.to_dict()
	for k in d.get("flags", {}).keys():
		_check(not String(k).begins_with("tod_"), "virtual flag %s written into the save" % k)
	_check(gs.save(SLOT, "tod"), "save")
	gs.reset()
	_check(TOD.current_state() == "d1_afternoon", "new game: d1_afternoon (%s)" % TOD.current_state())
	_check(gs.load(SLOT), "load")
	_check(TOD.current_state() == "d2_dusk", "load restores d2_dusk (%s)" % TOD.current_state())
	_flags_before("M01")
	_check(gs.has_flag("tod_afternoon") and gs.has_flag("tod_day1") and not gs.has_flag("tod_dark"), "arrival: afternoon of day one, not dark")
	_flags_before("M18p")
	_check(gs.has_flag("tod_night") and gs.has_flag("tod_dark") and gs.has_flag("tod_day2"), "the crossing: night of day two")
	_flags_before("M21")
	_check(gs.has_flag("tod_d3_morning") and not gs.has_flag("tod_dark"), "Nina's notebooks: morning of day three")
	var names: Array = TOD.virtual_flags()
	_check(names.has("tod_dark") and names.has("tod_d2_dusk") and names.has("tod_day4") and names.has("tod_evening"), "virtual_flags lists them (%d)" % names.size())
	gs.reset()


# --- 3. Rooms ---------------------------------------------------------------------------------

func _test_rooms() -> void:
	# Z2 — no lights: the multiply polygon.
	_flags_before("M02")
	gs.flags["house_unlocked"] = true
	await _enter("Z2")
	var tg: Node = _grade_node()
	_check(tg != null, "Z2: TimeOfDay node")
	if tg == null:
		return
	var p: Dictionary = tg.call("probe")
	_check(String(p["route"]) == "tint" and String(p["state"]) == "d1_afternoon", "Z2: tint route, d1_afternoon (%s)" % [p])
	var poly: Polygon2D = tg.get("tint")
	_check(poly != null and not poly.visible, "Z2 by day: as painted, the polygon off (no blend pass)")
	_check(rm.current_room.get_node_or_null("Effects/dusk") == null, "Z2: the old evening_dusk tint is replaced by the time of day")
	_check((p["windows_lit"] as Array).is_empty(), "Z2 by day: no lit windows (%s)" % [p["windows_lit"]])
	_flags_before("M15s")
	await _enter("Z2")
	tg = _grade_node()
	p = tg.call("probe")
	poly = tg.get("tint")
	_check(poly.visible and poly.color.is_equal_approx(Color.html("#8a90b4")), "Z2 at dusk: #8a90b4 (%s)" % poly.color.to_html(false))
	_check(poly.z_index == 4090 and not poly.z_as_relative, "Z2: the grade over the art and figures, under the drizzle and marks (z 4090)")
	var lit: Array = p["windows_lit"]
	_check(lit.has("far_1") and lit.has("mill_far") and lit.has("house_w2"), "Z2 at dusk: far windows and the aunt's (stove lit) glow (%s)" % [lit])
	_check(not lit.has("far_3"), "Z2: far_3 only at night")
	# G25 (Director 23.10: after the clamp the windows outside «естественнее и чуть дрожат, как в мастерской»): every
	# lit window breathes with the flame noise (LightFlicker) — within its amount, each on its own seed.
	var samples := {}
	for i in 40:
		await _frames(2)
		var fp: Dictionary = tg.call("flicker_probe")
		for k in fp:
			if not samples.has(k):
				samples[k] = []
			samples[k].append(float(fp[k]))
	_check(samples.has("house_w2") and samples.has("far_1") and samples.has("mill_far"), "G25: Z2's lit windows flicker (%s)" % [samples.keys()])
	var spec_w2: Dictionary = {}
	for w in TOD.room_data("Z2").get("windows", []):
		if String(w.get("id", "")) == "house_w2":
			spec_w2 = w
	if samples.has("house_w2") and not spec_w2.is_empty():
		var a: Array = samples["house_w2"]
		var base := float(spec_w2.get("alpha", 0.5))
		var amt := float(spec_w2.get("flicker", {}).get("amount", 0.0))
		_check(a.max() - a.min() > base * 0.02, "G25: the aunt's window is not a flat pane (alpha %.3f…%.3f)" % [a.min(), a.max()])
		_check(a.min() >= base * (1.0 - amt) - 0.01 and a.max() <= base * (1.0 + amt) + 0.01, "G25: and only slightly — within ±%d %% (%.3f…%.3f)" % [int(amt * 100), a.min(), a.max()])
	if samples.has("far_1") and samples.has("far_2"):
		_check(samples["far_1"] != samples["far_2"], "G25: the windows do not flicker in unison")
	for r in ["Z2", "Z4", "M1"]:
		for w in TOD.room_data(r).get("windows", []):
			if String(w.get("blend", "add")) == "add":
				_check(w.get("flicker", {}) is Dictionary and float(w.get("flicker", {}).get("amount", 0.0)) > 0.0, "G25: %s.%s has its flicker in data" % [r, String(w.get("id", ""))])
	_flags_before("M09")
	await _enter("Z2")
	poly = _grade_node().get("tint")
	_check(poly.visible and poly.color.is_equal_approx(Color.html("#dce1ec")), "Z2 in the morning: cooler (%s)" % poly.color.to_html(false))
	_check((_grade_node().call("probe")["windows_lit"] as Array).is_empty(), "Z2 in the morning: windows dark")
	_flags_before("M23a")
	await _enter("Z2")
	_check(not _grade_node().get("tint").visible, "Z2 on day three: no dusk left (the old tint stayed on evening_dusk)")
	# H1 — lights: ambient sources by state; night of day one is the scene's own staging.
	_flags_before("M06")
	gs.flags["house_unlocked"] = true
	await _enter("H1")
	tg = _grade_node()
	_check(String(tg.call("probe")["route"]) == "light", "H1: room light route")
	var s: Node = _light_source("tod_d1_dusk")
	_check(s != null, "H1: an ambient source for d1_dusk")
	if s != null:
		await _frames(4)
		_check(float(s.get("level")) > 0.99, "H1 at dusk: the source is on (%.2f)" % float(s.get("level")))
	_check(_light_source("tod_d1_night") == null, "H1: night of day one is painted by N01 (no source)")
	var morning: Node = _light_source("tod_d2_morning")
	_check(morning != null and float(morning.get("level")) < 0.01, "H1: the morning source is off at dusk")
	var stove: Node = _light_source("stove_fire")
	_check(stove != null, "H1: the stove fire is still its own light")
	gs.set_flag("h1_shutter_open", true)
	await _frames(3)
	var beam: Node = _light_source("window_beam")
	_check(beam != null and float(beam.get("target")) < 0.01, "H1 at dusk: no daylight beam from the window (lights unless tod_dark)")
	var panes: Array = tg.call("probe")["windows_lit"]
	_check(panes.has("pane_dusk") and not panes.has("pane_dark"), "H1 at dusk: the painted daylight in the glass dims (%s)" % [panes])
	var amb: CanvasItem = rm.current_room.get_node_or_null("Ambient")
	_check(amb == null or amb.modulate.is_equal_approx(TOD.tint_of(TOD.grade("H1", "d1_dusk"))), "H1: the living-world layer takes the dusk (%s)" % [amb.modulate.to_html(false) if amb != null else "-"])
	# Z3 / R1 — painted dusk: no source for d2_dusk; evening darker than the painting.
	_flags_before("M15s")
	await _enter("Z3")
	_check(_light_source("tod_d2_dusk") == null, "Z3: dusk is painted (water_low) — no grade")
	var ev: Node = _light_source("tod_d2_evening")
	_check(ev != null and float(ev.get("level")) < 0.01, "Z3: evening source exists, off at dusk")
	_flags_before("M16")
	await _enter("R1")
	await _frames(4)
	var rev: Node = _light_source("tod_d2_evening")
	_check(rev != null and float(rev.get("level")) > 0.99, "R1 at the three lights: evening darker than the painted dusk")
	_check(_light_source("tod_d2_dusk") == null, "R1: dusk is painted — no grade")
	var ramb: CanvasItem = rm.current_room.get_node_or_null("Ambient")
	_check(ramb != null and ramb.modulate.is_equal_approx(Color.html("#b6bace")), "R1 in the evening: the river and drizzle darken with the room (%s)" % [ramb.modulate.to_html(false) if ramb != null else "-"])
	# Frames are never toned.
	_check(String(TOD.room_class("EP_lesson")) == "frame" and TOD.grade("EP_lesson", "ep_morning").is_empty(), "epilogue frames: not toned")
	_check(String(TOD.room_class("O4")) == "cut_exterior" and TOD.grade("O4", "d2_night").is_empty(), "O4 night of day two: painted")
	_check(not TOD.grade("O4", "d3_evening").is_empty(), "O4 evening of day three: toned")
	gs.reset()


# --- 4. Transitions -------------------------------------------------------------------------

func _test_transitions() -> void:
	_flags_before("M15a")   # afternoon of day two
	gs.flags["house_unlocked"] = true
	await _enter("Z2")
	var tg: Node = _grade_node()
	var poly: Polygon2D = tg.get("tint")
	_check(not poly.visible, "Z2 in the afternoon: as painted")
	gs.set_flag("done_M15a", true)   # the mirror scene ends — dusk
	await _frames(3)
	_check(poly.visible and not poly.color.is_equal_approx(Color.html("#8a90b4")) and poly.color.r > 0.6, "dusk eases in, not at once (%s)" % poly.color.to_html(false))
	var fade := float(TOD.index().get("fade_s", 2.0))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int((fade + 0.6) * 1000.0):
		await process_frame
	_check(poly.color.is_equal_approx(Color.html("#8a90b4")), "after fade_s: dusk (%s)" % poly.color.to_html(false))
	_check((tg.call("probe")["windows_lit"] as Array).has("far_1"), "windows lit with the dusk")
	# Save at dusk, back to afternoon, load: dusk at once.
	_check(gs.save(SLOT, "tod"), "save at dusk")
	gs.set_flag("done_M15a", false)
	await _frames(2)
	_check(gs.load(SLOT), "load")
	await _frames(2)
	_check(poly.visible and poly.color.is_equal_approx(Color.html("#8a90b4")), "load: the final look at once (%s)" % poly.color.to_html(false))
	gs.reset()


# --- 5. Local clock and journal --------------------------------------------------------------

func _test_local_and_journal() -> void:
	_flags_before("M07")   # in the class, Zarechye at dusk
	gs.flags["door_school_installed"] = true
	await _enter("O1")
	var tg: Node = _grade_node()
	_check(tg != null and String(tg.call("probe")["state"]) == "class_own", "O1 before the road: its own clock")
	var poly: Polygon2D = tg.get("tint") if tg != null else null
	_check(poly == null or not poly.visible, "O1: the winter day as painted, no Zarechye dusk")
	var lab: String = TOD.label("O1")
	_check(lab.find(sd.text("@ui.time_d1_dusk")) >= 0 and lab.find(sd.text("@ui.time_class_own")) >= 0, "journal line in the class: «%s»" % lab)
	ui.call("toggle_journal")
	await _frames(2)
	var jl: Label = ui.get("journal_time_label")
	_check(jl != null and jl.visible and jl.text == lab, "journal shows «%s» (got «%s»)" % [lab, jl.text if jl != null else "—"])
	ui.call("toggle_journal")
	await _frames(1)
	_flags_before("M22")
	gs.flags["door_school_installed"] = true
	await _enter("O1")
	_check(String(_grade_node().call("probe")["state"]) == "d3_morning", "O1 once the road is back: the common time")
	_flags_before("M10")
	gs.flags["house_unlocked"] = true
	await _enter("H2")
	ui.call("toggle_journal")
	await _frames(2)
	jl = ui.get("journal_time_label")
	_check(jl.text == sd.text("@ui.time_d2_midday"), "journal in the workshop at the mirror: «%s»" % jl.text)
	ui.call("toggle_journal")
	gs.reset()
