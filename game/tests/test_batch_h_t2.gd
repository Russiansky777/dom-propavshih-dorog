extends SceneTree
## Batch H, task T2 (Director's playtest 24.10, Docs/FEEDBACK_DIRECTOR_2026-10-24.md) — staging and mechanics:
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_h_t2.gd
##   - H17: the bed in the attic ends the day — «рано ложиться» with what is left while the day's deeds are not done
##     (no night starts), «пора спать» and the night once they are; after the sleep the time never goes back and the day
##     number grows by one; the windows of every room with a time file match the time of day (no lit panes by day,
##     no daylight panes at night); Pavel's «приходи утром» — the mill passage opens with the morning after the bed;
##   - G44: the bell clapper lies in the chest in the attic, the workshop crate has no label and no hotspot;
##   - H12/H13: the wet scarf lies over the shelf on the bench; the shelf shows once the scarf is gone; one place
##     (by the stove), the choice is «help Tikhon or not» — «not» leaves the shelf on the bench and the story open.
## Exit code 0 only when every check passed.

var TOD = null     # TimeOfDay (loaded at run time: autoloads do not exist yet when -s compiles)

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null


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
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	await _test("H17: the bed — «рано ложиться» with what is left before the day's deeds, no night starts", _test_bed_early)
	await _test("H17: the bed — «пора спать», the night of day one (N01) and the evening of day three (M24); time only goes on", _test_bed_sleep)
	await _test("H17: the windows of every room with a time file match the time of day", _test_windows)
	await _test("G44: the clapper in the attic chest; the workshop crate without a label", _test_clapper_chest)
	await _test("H12/H13: the scarf over the shelf on the bench; one place; help Tikhon or not", _test_shelf)
	await _test("H15/H24/H28/H37/H39: staging — Agata to the chosen cup; Pavel's door opens and shuts; Pavel faces the office door; Pelageya by Mitya; Agata runs to mum", _test_staging)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch H (T2): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


## Every main scene before `upto` done with its grants and its room conditions, + `extra`.
func _flags_before(upto: String, extra: Array = []) -> void:
	sr._on_state_reset()
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == upto:
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for rid in sd.scene_trigger_rooms(id):
			var cw = sd.room(rid).get("scenes", {}).get(id, {}).get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []):
					gs.set_flag(String(f), true)
	for f in ["house_unlocked", "house_open", "h1_shutter_open", "h1_scarf_removed"]:
		gs.set_flag(f, true)
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	sr._on_state_reset()
	await _frames(1)
	return rm.current_room


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _layer(id: String) -> Node:
	return rm.current_room.get_node_or_null("Layers/" + id) if rm.current_room != null else null


## Clicks through the beats on screen; `choices` — option ids in order (else the first). Returns "speaker:text" / "stage".
func _drain(choices: Array = []) -> Array:
	var seen: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and guard < 2400:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if seen.is_empty() or seen.back() != "stage":
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			if not choices.is_empty():
				pick = String(choices.pop_front())
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text", ""))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


func _state_index(st: String) -> int:
	var i := 0
	for s in TOD.states():
		if String(s.get("id", "")) == st:
			return i
		i += 1
	return -1


func _click_bed() -> Dictionary:
	var bed := _hotspot("bed")
	_check(bed != null and bed.visible, "the bed hotspot in the attic")
	if bed == null:
		return {}
	_check(sr.planned_interaction(bed) == "use", "the bed is a use, not a talk (cursor)")
	sr.interact(bed)
	await _frames(1)
	return sr.current_beat


# --- H17 ---------------------------------------------------------------------------------

func _test_bed_early() -> void:
	var cases := [
		["M05", [], "H4.bed.early_d1_door"],
		["M07", [], "H4.bed.early_d1_class"],
		["M09", [], "H4.bed.early_d2"],
		["M16", [], "H4.bed.early_d2"],
		["M23a", ["done_M23b"], "H4.bed.early_d3"],
	]
	for c in cases:
		_flags_before(String(c[0]), c[1])
		await _enter("H4", "from_H1")
		var st_before: String = TOD.current_state()
		var b: Dictionary = await _click_bed()
		_check(String(b.get("text_key", "")) == String(c[2]) and String(b.get("speaker", "")) == "agata",
			"before %s: Agata says «рано» (%s), got %s" % [c[0], c[2], str(b)])
		var seen := await _drain()
		_check(sr.active_scene == "" and not (gs.has_flag("done_N01") and String(c[0]) in ["M05", "M07"]) and not gs.has_flag("done_M24") and TOD.current_state() == st_before and seen.size() == 1,
			"before %s: no night, the time stays %s (%s)" % [c[0], st_before, str(seen)])
		if String(c[0]) == "M23a":
			var t := String(b.get("text", ""))
			_check(t.contains("письма Тамары") and t.contains("мама в доме тёти") and t.contains("сказать Тихону") and not t.contains("Павел"),
				"day three: what is left is named, the done deed is not: %s" % t)
	# Day one: Pavel's «приходи утром» — the passage of the mill opens with the morning after the bed (no own clock).
	var locs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/locations.json"))
	var found := false
	for e in locs.get("edges", []):
		if String(e.get("from", "")) == "M1" and String(e.get("to", "")) == "M2":
			found = (e.get("requires", []) as Array).has("done_N01")
	_check(found, "M1→M2 waits for the morning (done_N01 — the bed)")


func _test_bed_sleep() -> void:
	# Day one: back from the school.
	_flags_before("N01")
	rm.change_room("H3", "from_O1")
	await _frames(3)
	_check(String(sr.current_beat.get("text_key", "")) == "H3.night.to_bed", "the gallery: Agata says where the bed is (%s)" % str(sr.current_beat))
	await _drain()
	_check(not gs.has_flag("started_N01"), "the gallery: the night does not start by itself")
	await _enter("H4", "from_H1")
	var st0: String = TOD.current_state()
	_check(st0 == "d1_night", "day one: night before the bed (%s)" % st0)
	var b: Dictionary = await _click_bed()
	_check(String(b.get("text_key", "")) == "H4.bed.late_d1", "«пора спать» first: %s" % str(b))
	var seen := await _drain()
	_check(gs.has_flag("done_N01"), "N01 done after the bed: %s" % str(seen))
	var st1: String = TOD.current_state()
	_check(_state_index(st1) > _state_index(st0) and TOD.day_of(st1) == TOD.day_of(st0) + 1 and TOD.phase_of(st1) == "morning",
		"after the sleep: the next day's morning (%s → %s)" % [st0, st1])
	_check(rm.current_room.room_id == "H1", "the night is by the stove (mother's letter M19), room %s" % rm.current_room.room_id)
	await _enter("H4", "from_H1")
	b = await _click_bed()
	_check(String(b.get("text_key", "")) == "H4.bed.early_d2" and TOD.current_state() == st1, "the bed again in the morning: «рано», time stays")
	await _drain()
	# Day three: the four deeds done.
	_flags_before("M24")
	await _enter("H4", "from_H1")
	var st2: String = TOD.current_state()
	_check(st2 == "d3_evening", "day three: evening once the four deeds are done (%s)" % st2)
	b = await _click_bed()
	_check(String(b.get("text_key", "")) == "H4.bed.late_d3", "«пора спать» on day three: %s" % str(b))
	seen = await _drain()
	var st3: String = TOD.current_state()
	_check(gs.has_flag("done_M24") and gs.has_flag("morning_day4") and _state_index(st3) > _state_index(st2) and TOD.day_of(st3) == 4,
		"M24 → day four (%s → %s): %s" % [st2, st3, str(seen)])
	_check(rm.current_room.room_id == "H4", "morning of day four in the attic")
	b = await _click_bed()
	_check(String(b.get("text_key", "")) == "H4.bed.after_d4", "the bed on day four: «выспалась, ждут у поворота»: %s" % str(b))
	await _drain()
	# The prompt once the deeds are done (time state `bedtime`): on day three, after the last deed.
	_flags_before("M23d", [])
	gs.set_flag("done_M23d", true)
	sr._complete_scene("M23d")
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "H4.bed.bedtime_d3" and gs.journal_goal == sd.text("@ui.bedtime_d3_goal"),
		"the last deed of day three: «пора домой — спать», the journal points to the bed (%s / %s)" % [str(sr.current_beat), gs.journal_goal])
	await _drain()
	# Time never goes back along the whole story: every main scene's grants keep the state index non-decreasing.
	gs.reset()
	var last := 0
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		gs.flags["done_" + id] = true
		for f in sc.get("grants", {}).get("flags", []):
			gs.flags[String(f)] = true
		var i := _state_index(TOD.current_state())
		_check(i >= last, "after %s the time went back (%s)" % [id, TOD.current_state()])
		last = maxi(last, i)


func _test_windows() -> void:
	var day_phases := ["afternoon", "morning", "midday", "day"]
	for st in TOD.states():
		if bool(st.get("room_only", false)):
			continue
		var sid := String(st.get("id", ""))
		var phase := String(st.get("phase", ""))
		# the first scene that begins in this state
		var first := ""
		var scenes: Dictionary = TOD.index().get("scenes", {})
		for id in sd.scene_order:
			if String(scenes.get(id, "")) == sid:
				first = id
				break
		if first == "":
			continue
		_flags_before(first)
		_check(TOD.current_state() == sid, "flags before %s give %s (got %s)" % [first, sid, TOD.current_state()])
		for rid in ["H1", "H2", "M1", "Z2", "Z4"]:
			if TOD.room_state(rid) != sid:
				continue
			await _enter(rid)
			var tg: Node = rm.current_room.get_node_or_null("TimeOfDay")
			if tg == null:
				continue
			var lit: Array = tg.call("probe")["windows_lit"]
			if day_phases.has(phase):
				_check(lit.is_empty(), "%s %s (%s): no lit / darkened windows by day (%s)" % [rid, sid, phase, lit])
			if rid == "H1" and (phase == "evening" or phase == "night") and sid != "d1_night":
				_check(lit.has("pane_dark"), "H1 %s: the glass is dark (%s)" % [sid, lit])


# --- G44 -----------------------------------------------------------------------------------

func _test_clapper_chest() -> void:
	_flags_before("M05")
	await _enter("H2", "from_H1")
	_check(_hotspot("clapper_box") == null, "no clapper box in the workshop")
	_check(_layer("crate_blank") != null and _layer("crate_blank").visible, "the crate drawn without the label")
	await _enter("H4", "from_H1")
	_check(_layer("bed") != null and _layer("bed").visible, "the bed drawn in the attic")
	_check(not _layer("chest_open").visible and not _layer("chest_clapper").visible, "the chest closed")
	sr.interact(_hotspot("chest"))
	await _drain()
	_check(gs.has_item("bell_clapper") and gs.has_flag("attic_chest_open"), "the clapper from the chest")
	await _frames(2)
	_check(_layer("chest_open").visible and not _layer("chest_clapper").visible, "the chest open and empty")
	sr.interact(_hotspot("chest"))
	await _drain()
	_check(gs.inventory.count("bell_clapper") == 1, "given once")
	_check(String(sd.item("bell_clapper").get("source_hotspot", "")) == "H4.chest", "items.json: the clapper comes from H4.chest")


# --- H12/H13 -------------------------------------------------------------------------------

func _test_shelf() -> void:
	_flags_before("M03")
	gs.set_flag("h1_scarf_removed", false)
	await _enter("H1", "from_Z2")
	_check(_layer("scarf_over_shelf") != null and _layer("scarf_over_shelf").visible, "the scarf lies over the shelf on the bench")
	_check(not _layer("shelf_on_bench").visible and (_hotspot("shelf") == null or not _hotspot("shelf").visible), "the shelf is under the scarf: not shown, not clickable")
	_check(_layer("shelf_leaning") == null and _layer("shelf_table") == null, "the old leaning shelf and the place by the table are gone")
	gs.set_flag("h1_scarf_removed", true)
	gs.set_flag("met_tikhon", true)
	gs.set_flag("stove_lit", true)
	gs.set_flag("done_M03", true)
	await _enter("H1", "from_Z2")
	_check(_layer("shelf_on_bench").visible and _hotspot("shelf").visible, "the scarf gone — the shelf on the bench")
	sr.interact(_hotspot("shelf"))
	await _frames(1)
	var opts: Array = sr.current_options()
	var ids: Array = opts.map(func(o): return String(o.get("id", "")))
	_check(ids == ["A", "B"] and String(opts[0].get("label", "")).contains("у печи") and String(opts[1].get("label", "")) == "Не сейчас",
		"one place by the stove, or not: %s" % str(opts))
	var seen := await _drain(["B"])
	_check(gs.has_flag("q04_declined") and not gs.has_flag("done_Q04") and _layer("shelf_on_bench").visible, "«не сейчас»: the shelf stays on the bench, the story open (%s)" % str(seen))
	sr.interact(_hotspot("shelf"))
	await _frames(1)
	seen = await _drain(["A"])
	await _frames(2)
	_check(gs.has_flag("q04_corner_stove") and gs.has_flag("done_Q04") and not _layer("shelf_on_bench").visible and _layer("shelf_stove").visible,
		"changed her mind: the shelf by the stove (%s)" % str(seen))


# --- Staging -------------------------------------------------------------------------------

func _wait_until(cond: Callable, limit: int = 900) -> bool:
	var g := 0
	while not cond.call() and g < limit:
		g += 1
		await process_frame
	return cond.call()


## Advances the scene's beats until the current one is a line whose text begins with `prefix` (or the scene ends).
func _advance_to(prefix: String, limit: int = 3000) -> bool:
	var g := 0
	while g < limit:
		g += 1
		var b: Dictionary = sr.current_beat
		if not b.is_empty() and String(b.get("text", "")).begins_with(prefix):
			return true
		if b.is_empty() and not sr.is_staging() and sr.active_scene == "":
			return false
		if not b.is_empty() and not sr.is_staging():
			if b.get("type") == "options":
				sr.choose(String(b["options"][0]["id"]))
			else:
				sr.advance()
		await process_frame
	return false


func _npc(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("npc_" + id)


func _test_staging() -> void:
	var player: Node2D = rm.player
	# H15: the chosen cup — Agata walks to the table and turns to it.
	_flags_before("M04", ["met_tikhon", "stove_lit"])
	await _enter("H1", "from_Z2")
	sr.interact(_hotspot("cups"))
	await _frames(2)
	_check(String(sr.current_beat.get("type", "")) == "options", "the cups offer the choice")
	sr.choose("blue")
	var cup_to := Vector2(885, 790)
	await _drain()
	await _wait_until(func(): return not player.call("is_walking") and not player.call("is_acting"), 1200)
	_check(player.global_position.distance_to(cup_to) < 30.0, "H15: Agata at the table by the chosen cup (%s)" % str(player.global_position.round()))
	# H24: Pavel goes to the passage door — it opens, he goes in, it shuts.
	_flags_before("M09b")
	await _enter("M1", "default")
	sr.start_scene("M09b")
	var got_door := await _wait_until(func():
		if not sr.current_beat.is_empty() and not sr.is_staging():
			if sr.current_beat.get("type") == "options":
				sr.choose(String(sr.current_beat["options"][0]["id"]))
			else:
				sr.advance()
		return rm.current_room.get_node_or_null("StageDoor") != null, 3000)
	_check(got_door, "H24: the door of the passage swings open as Pavel walks up")
	if got_door:
		var door: Node = rm.current_room.get_node("StageDoor")
		await create_timer(0.9).timeout
		var leaf: Sprite2D = door.get_child(1)
		var full := 1920.0 / float((leaf.texture as AtlasTexture).atlas.get_width())
		_check(leaf.scale.x < full * 0.8, "H24: the leaf has turned on its hinge (scale %.2f of %.2f)" % [leaf.scale.x, full])
		await _wait_until(func(): return rm.current_room.room_id == "M2", 1200)
	await _drain()
	_check(rm.current_room.room_id == "M2" and gs.has_flag("pavel_blessed_mirror"), "after the door: the passage, Pavel inside")
	# H28: Pavel at the office door looks at it (left), not away.
	_flags_before("M10", ["pavel_blessed_mirror", "has_mirror_mill"])
	await _enter("M2", "from_M1")
	var pv := _npc("pavel")
	_check(pv != null, "Pavel in the passage")
	if pv != null:
		var want: int = pv.sheet.direction_index(Vector2(700, 560) - pv.global_position)
		_check(int(pv.get("direction")) == want, "H28: Pavel faces the office door (dir %d, want %d)" % [int(pv.get("direction")), want])
	# H37: Pelageya and Mitya close while she strokes his beard.
	_flags_before("M18", ["started_M18p"])
	await _enter("R3", "from_R2")
	sr.start_scene("M18")   # (entering started it; _enter cleared the queue — start it again from its first line)
	var at_beard := await _advance_to("Пелагея выбирается из лодки")
	await _wait_until(func(): return not sr.is_staging(), 600)
	var pe := _npc("pelageya")
	var mi := _npc("mitya")
	_check(at_beard and pe != null and mi != null and pe.global_position.distance_to(mi.global_position) < 110.0,
		"H37: Pelageya next to Mitya when she strokes his beard (%s / %s)" % [str(pe.global_position.round()) if pe else "-", str(mi.global_position.round()) if mi else "-"])
	await _drain()
	# H39: before «Мама.» Agata runs to her mother on the porch.
	_flags_before("M19")
	await _enter("O4", "from_R3")
	sr.start_scene("M19")
	var at_mama := await _advance_to("Мама.")
	_check(at_mama and player.global_position.distance_to(Vector2(1292, 716)) < 30.0, "H39: at «Мама.» Agata is at the porch by Nina (%s)" % str(player.global_position.round()))
	await _drain()
