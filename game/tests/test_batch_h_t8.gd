extends SceneTree
## Batch H, task T8 (Director 24.10, 16:28 — Docs/tasks/H_T8_boat_door_goals_art.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_h_t8.gd
##   1. H36: after the brace (M15s) Pelageya's boat is at the turn, tied by the plate under the rope; the empty boat (M17)
##      slides off along the rope there and «В лодку» (M18p) is there; the pier R1 is without a boat from then on. The
##      boat is in one place at a time, by the flags — and after a load;
##   2. Dunya's house opens only after the talk with Pelageya (M02): before it Agata says why, the key stays in the bag,
##      the journal leads to the pier; after it — open, and after a load. Every start point has M02 done; a day-two save
##      that skipped M02 (old rule) gets it;
##   3. the free day (M23a/b/d): the journal names only what is still to do.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var _layers_went: Array[String] = []


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
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	sr.layer_went.connect(func(id: String): _layers_went.append(id))
	await _test("T8 п.1 (H36): the boat by the flags — pier until the brace, then the turn; never in two places", _test_boat_places)
	await _test("T8 п.1 (H36): M17 at the turn — the boat slides off along the rope and comes back; «В лодку» there", _test_boat_m17_m18p)
	await _test("T8 п.1 (H36): the boat after a load — where the flags say", _test_boat_load)
	await _test("T8 п.2: the house — closed before Pelageya (M02), open after, and after a load; start points, old saves", _test_house)
	await _test("T8 п.3: the free day — the journal names only what is still to do", _test_free_day_goals)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch H (T8): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


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
	for f in extra:
		gs.set_flag(String(f), true)


func _enter(room_id: String, spawn: String = "default") -> Node:
	rm.change_room(room_id, spawn)
	await physics_frame
	await _frames(3)
	await _drain()   # first-entry thoughts (R1 at dusk: «Пелагеи на причале нет…»)
	return rm.current_room


func _hotspot(id: String) -> Node:
	return rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null


func _exit(to: String) -> Node:
	return rm.current_room.get_node_or_null("Exits/to_" + to) if rm.current_room != null else null


func _layer(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("Layers/" + id) as Node2D if rm.current_room != null else null


func _layer_on(id: String) -> bool:
	var l := _layer(id)
	return l != null and l.visible


func _drain() -> Array:
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while (not sr.current_beat.is_empty() or sr.is_staging() or sr.mechanic_open) and Time.get_ticks_msec() - t0 < 40000:
		if sr.mechanic_open:
			# A scene's close-up (the crossing of M18p): its events done by hand, then put away — the scene goes on.
			seen.append("mechanic")
			for ev in sr.mechanic.get("events", {}).values():
				for f in ev.get("sets", []):
					gs.set_flag(String(f), true)
			sr.close_mechanic()
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if seen.is_empty() or seen.back() != "stage":
				seen.append("stage")
			await process_frame
			continue
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var pick := String(opts[0].get("id", "")) if not opts.is_empty() else ""
			seen.append("options:" + pick)
			sr.choose(pick)
		else:
			seen.append("%s:%s" % [String(b.get("speaker", "")), String(b.get("text_key", b.get("text", "")))])
			sr.advance()
		await process_frame
	await _frames(2)
	return seen


## Where the boat is drawn now: "R1" — the painted one at the pier (no patch shown), "Z3" — a boat layer at the turn.
## Checks both rooms (the state is the same flags), so «two places at once» shows as ["R1", "Z3"].
func _boat_places() -> Array:
	var out: Array = []
	await _enter("R1")
	var patched := _layer_on("no_boat_dusk") or _layer_on("no_boat_day") or _layer_on("no_boat_d3_evening")
	if not patched:
		out.append("R1")
	var hs := _hotspot("boat")
	_check((hs != null and hs.visible) == not patched, "R1: the boat hotspot (%s) follows the painted boat (patched %s)" % [str(hs != null and hs.visible), str(patched)])
	await _enter("Z3")
	if _layer_on("boat_dusk") or _layer_on("boat_shuttle_dusk") or _layer_on("boat_day"):
		out.append("Z3")
	var ex := _exit("R2")
	_check((ex != null and ex.visible) == out.has("Z3"), "Z3: «В лодку» shown (%s) exactly when the boat is there (%s)" % [str(ex != null and ex.visible), str(out)])
	return out


# --- 1. The boat --------------------------------------------------------------------------------

func _test_boat_places() -> void:
	# Day one, before and after Pelageya: the boat at her pier; no «В лодку» exit at the pier any more (H36), the boat is
	# looked at — «сперва с лодочницей», then why there is no road (G17).
	_flags_before("M02")
	_check(await _boat_places() == ["R1"], "day one: the boat at the pier only")
	await _enter("R1")
	_check(_exit("R2") == null, "R1: no exit into the boat (it is at the turn once there is a road)")
	sr.interact(_hotspot("boat"))
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed_first", "before M02: «Сперва с лодочницей поговорю» (%s)" % str(sr.current_beat))
	await _drain()
	gs.set_flag("done_M02", true)
	sr.interact(_hotspot("boat"))
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed", "after M02: G17 — no road until the rope is on the plate (%s)" % str(sr.current_beat))
	await _drain()
	# Dusk of day two, before the brace: still at the pier (Pelageya waits at the turn without it).
	_flags_before("M15s")
	_check(gs.has_flag("evening_dusk") and not gs.has_flag("rope_brought"), "before M15s: dusk, the rope still on the stopper")
	_check(await _boat_places() == ["R1"], "before the brace: the boat at the pier only")
	# After the brace (M15s) — at the turn, tied by the plate; the pier without it.
	_flags_before("M15")
	_check(await _boat_places() == ["Z3"], "after M15s: the boat at the turn only")
	await _enter("Z3")
	var ex := _exit("R2")
	_check(ex != null and not ex.is_open(), "after M15s: «В лодку» at the turn, closed before the empty-boat check")
	sr.use_exit(ex)
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed", "before the knot: no road yet (%s)" % str(sr.current_beat))
	await _drain()
	gs.set_flag("done_M15", true)
	gs.set_flag("rope_on_ring", true)
	sr.use_exit(ex)
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "R1.exit_R2.closed_check", "after the knot: first the empty boat (%s)" % str(sr.current_beat))
	await _drain()
	# The lights answered (M16): Pelageya goes from the pier to the boat at the turn.
	_flags_before("M17")
	await _enter("R1")
	_check(_hotspot("pelageya") != null and not _hotspot("pelageya").visible, "after M16: Pelageya not at the pier")
	await _enter("Z3")
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "after M16: Pelageya at the turn, by the boat")
	_check(sd.scene("M16").get("goal", "").contains("поворот"), "M16 goal leads to the turn: %s" % sd.scene("M16").get("goal", ""))
	# Crossing (M18p started): the boat is on the river / at the far pier — neither at the turn nor at the pier.
	_flags_before("M18", ["started_M18p", "done_M18p"])
	_check(await _boat_places() == [], "after the crossing: the boat neither at the turn nor at the pier")
	# Day three, the boat goes both ways: at the turn again (day and evening), the pier still without it.
	_flags_before("M23a")
	_check(gs.has_flag("boat_shuttle_open") and gs.has_flag("tod_d3_day"), "day three: boat_shuttle_open, daytime")
	_check(await _boat_places() == ["Z3"], "day three: the boat at the turn only")
	await _enter("R1")
	_check(_layer_on("no_boat_day") and not _layer_on("no_boat_dusk") and not _layer_on("no_boat_d3_evening"), "day three: the day patch at the pier")
	_flags_before("M24")   # all four deeds of the free day done — the evening of day three
	_check(gs.has_flag("tod_d3_evening"), "evening of day three: tod_d3_evening")
	await _enter("R1")
	_check(_layer_on("no_boat_d3_evening") and not _layer_on("no_boat_day"), "evening of day three: the evening patch at the pier")
	_check(await _boat_places() == ["Z3"], "evening of day three: the boat at the turn only")
	await _enter("Z3")
	_check(_layer_on("boat_shuttle_dusk") and not _layer_on("boat_day"), "evening of day three: the dusk boat at the turn")
	# T9 (Director's decision 24.10, 22:26): on day three Pelageya waits by the boat at the turn, not at her pier.
	_check(_hotspot("pelageya") != null and _hotspot("pelageya").visible, "day three: Pelageya by the boat at the turn")
	await _enter("R1")
	_check(_hotspot("pelageya") == null or not _hotspot("pelageya").visible, "day three: Pelageya not at the pier")


func _test_boat_m17_m18p() -> void:
	_flags_before("M17")
	await _enter("Z3")
	_check(_layer_on("boat_dusk"), "before M17: the boat at the plate")
	_layers_went.clear()
	sr.interact(_hotspot("pelageya"))
	await _frames(1)
	_check(gs.has_flag("started_M17"), "M17 starts from Pelageya at the turn")
	# The empty boat slides off along the rope (layer_go), no fade at that beat.
	var t0 := Time.get_ticks_msec()
	var moved := false
	var min_alpha := 1.0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and Time.get_ticks_msec() - t0 < 40000:
		var bl := _layer("boat_dusk")
		if bl != null:
			moved = moved or bl.position.length() > 20.0
			min_alpha = minf(min_alpha, bl.modulate.a)
		if sr.current_beat.is_empty():
			await process_frame
			continue
		sr.advance()
		await process_frame
	await _frames(2)
	_check(_layers_went.has("boat_dusk"), "M17: the boat layer went (%s)" % str(_layers_went))
	_check(moved and min_alpha < 0.2, "M17: the boat slid away and faded into the fog (moved %s, min alpha %.2f)" % [str(moved), min_alpha])
	var bl2 := _layer("boat_dusk")
	_check(bl2 != null and bl2.visible and bl2.position == Vector2.ZERO and is_equal_approx(bl2.modulate.a, 1.0) and bl2.scale == Vector2.ONE, "after M17: hauled back to the plate")
	_check(gs.has_flag("done_M17") and gs.has_flag("ferry_verified") and gs.has_item("school_ribbon"), "M17 done: ribbon in the bag")
	_check(sd.scene("M17").get("locations", []) == ["Z3"], "M17 — at the turn")
	# «В лодку» at the turn — open now; M18p from there.
	var ex := _exit("R2")
	_check(ex != null and ex.visible and ex.is_open(), "«В лодку» at the turn is open after M17")
	sr.use_exit(ex)
	await _frames(6)
	_check(rm.current_room != null and rm.current_room.room_id == "R2", "into the boat from the turn → R2")
	_check(gs.has_flag("started_M18p"), "M18p starts")
	await _drain()
	_check(rm.current_room != null and rm.current_room.room_id == "R3", "M18p: at the far pier")
	_check(await _boat_places() == [], "after M18p: no boat at the turn or the pier")


func _test_boat_load() -> void:
	_flags_before("M15")
	await _enter("Z3")
	_check(rm.save_game("t8_boat"), "save after M15s")
	_flags_before("M02")
	await _enter("R1")
	_check(rm.load_game("t8_boat"), "load")
	await _frames(4)
	_check(rm.current_room.room_id == "Z3" and _layer_on("boat_dusk") and _exit("R2") != null and _exit("R2").visible, "after a load: the boat at the turn")
	await _enter("R1")
	_check(_layer_on("no_boat_dusk") and (_hotspot("boat") == null or not _hotspot("boat").visible), "after a load: the pier without the boat")
	# Day three save/load.
	_flags_before("M23a")
	await _enter("R1")
	_check(rm.save_game("t8_boat"), "save on day three")
	_flags_before("M02")
	_check(rm.load_game("t8_boat"), "load day three")
	await _frames(4)
	_check(_layer_on("no_boat_day"), "day three after a load: the pier without the boat")
	_check(await _boat_places() == ["Z3"], "day three after a load: the boat at the turn only")


# --- 2. The house after Pelageya ----------------------------------------------------------------

func _test_house() -> void:
	_flags_before("M02")
	gs.add_item("key_house")
	_check(sd.scene("M01").get("goal", "").contains("причал"), "M01 goal leads to the pier first: %s" % sd.scene("M01").get("goal", ""))
	await _enter("Z2")
	var door := _exit("H1")
	_check(door != null and not door.is_open(), "Z2: the house door closed")
	sr.use_exit(door)
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.not_yet" and String(sr.current_beat.get("speaker", "")) == "agata", "before M02: Agata — first the pier (%s)" % str(sr.current_beat))
	await _drain()
	sr.select_item("key_house")
	sr.use_exit(door)
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.not_yet", "before M02: the key on the door — first the pier (%s)" % str(sr.current_beat))
	await _drain()
	_check(gs.has_item("key_house") and not gs.has_flag("house_unlocked") and rm.current_room.room_id == "Z2", "before M02: the key stays in the bag, the door locked")
	# After the talk with Pelageya.
	gs.set_flag("done_M02", true)
	sr.use_exit(door)
	await _frames(1)
	_check(String(sr.current_beat.get("text_key", "")) == "Z2.exit_H1.closed", "after M02: «заперто, ключ в сумке» (%s)" % str(sr.current_beat))
	await _drain()
	sr.select_item("key_house")
	sr.use_exit(door)
	await _frames(1)
	await _drain()
	await _frames(6)
	_check(gs.has_flag("house_unlocked") and not gs.has_item("key_house"), "after M02: the key opens the door and stays in the lock")
	_check(rm.save_game("t8_house"), "save")
	_flags_before("M02")
	_check(rm.load_game("t8_house"), "load")
	await _enter("Z2")
	_check(_exit("H1").is_open(), "after a load: the house open")
	# Every start point of days one and two (and later) has the talk with Pelageya done.
	var m02_at: int = sd.scene_order.find("M02")
	for pid in sd.start_points.keys():
		if sd.scene_order.find(String(sd.start_points[pid].get("done_through", ""))) < m02_at:
			continue   # pier_first (T8): before the pier on purpose
		rm.start_at(String(pid))
		await _frames(1)
		_check(gs.has_flag("done_M02") and gs.has_flag("met_pelageya"), "start point %s: M02 done" % pid)
	# A day-two save made under the old rule (house opened, M02 skipped): M02 counts with its flags. Day one — untouched.
	var d := {"version": gs.SAVE_VERSION, "flags": {"done_M01": true, "house_unlocked": true, "done_N01": true}, "inventory": [], "current_room": "H1"}
	_check(gs.from_dict(d), "old day-two save loads")
	_check(gs.has_flag("done_M02") and gs.has_flag("met_pelageya") and gs.has_flag("knows_no_road"), "old day-two save: M02 counted")
	d = {"version": gs.SAVE_VERSION, "flags": {"done_M01": true, "house_unlocked": true}, "inventory": [], "current_room": "H1"}
	_check(gs.from_dict(d) and not gs.has_flag("done_M02"), "old day-one save: M02 still ahead (door open, the pier waits)")


# --- 3. The free day ----------------------------------------------------------------------------

func _test_free_day_goals() -> void:
	var names := {"done_M23a": ["Тамара с письмами"], "done_M23b": ["мельниц"], "done_M23c": ["мама в доме тёти"], "done_M23d": ["Тихону"]}
	var deeds := ["done_M23a", "done_M23b", "done_M23c", "done_M23d"]
	for scene_id in ["M23a", "M23b", "M23d"]:
		for mask in 16:
			var flags := {}
			for i in 4:
				flags[deeds[i]] = (mask >> i) & 1 == 1
			flags["done_" + scene_id] = true   # the scene whose goal it is — done
			if scene_id == "M23d":
				flags["done_M23c"] = true
			if flags["done_M23d"] and not flags["done_M23c"]:
				continue   # Tikhon learns after mama's visit
			gs.reset()
			for f in flags:
				gs.set_flag(String(f), bool(flags[f]))
			var g: String = sd.scene_goal(sd.scene(scene_id))
			for f in deeds:
				for w in names[f]:
					if bool(flags[f]):
						_check(not g.contains(w), "%s %s: done «%s» not named: %s" % [scene_id, str(flags), w, g])
			for f in ["done_M23a", "done_M23b", "done_M23c"]:
				if not bool(flags[f]):
					_check(g.contains(names[f][0]), "%s %s: still to do «%s» named: %s" % [scene_id, str(flags), names[f][0], g])
			var all_done := deeds.all(func(x): return bool(flags[x]))
			if all_done:
				_check(not g.contains("не сделано") and g.contains("Ольховка"), "%s: all done — one neutral goal: %s" % [scene_id, g])
	# In play: the goal the journal shows after the scene completes.
	_flags_before("M23a")
	gs.set_flag("done_M23b", true)
	sr._complete_scene("M23a")
	await _frames(1)
	_check(gs.journal_goal.begins_with("Письма розданы.") and gs.journal_goal.contains("мама в доме тёти") and not gs.journal_goal.contains("мельниц") and not gs.journal_goal.contains("Тамара с письмами"),
		"after M23a with the mill done — only mama left: %s" % gs.journal_goal)
