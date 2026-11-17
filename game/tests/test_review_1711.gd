extends SceneTree
## The review before release, 17.11 (Director: «полный ультимативный ревью перед релизом»).
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1711.gd
##   R17-1 The morning of day three: N02 walks Nina out of the horenka at night (npc_go with a fade); in the morning the
##       room is the same, not rebuilt — she stayed invisible by the door while M21 had her speak and her caption
##       «Нина» hung over an empty floor. From bedtime2 by the bed: in the morning Nina stands in her place, in sight,
##       before M21 and through its lines (N02's `npc_back`). Self-check — the same night without `npc_back`: she is
##       out of sight in the morning, and the check says so.
##   R17-2 The rule of tests/ghost_watch.gd (a clickable villager is a visible one; the bot walkthroughs run it all the
##       way): a shown hotspot over a figure at alpha 0 that is not walking is caught; a walking or visible one, or one
##       whose hotspot is hidden, is not.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node
var sr: Node
var sd: Node
var rm: Node


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
	_results.append(passed)
	print(("PASS  " if passed else "FAIL  ") + test_name + "  (%d ms)" % (Time.get_ticks_msec() - started))
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	rm = root.get_node("RoomManager")
	await _test("R17-1 the morning of day three: Nina in her place and in sight before and through M21 (N02 npc_back); self-check — without it she is gone and it is seen", _test_morning_nina)
	await _test("R17-2 the ghost rule: clickable and out of sight is caught; walking, visible or hidden is not", _test_ghost_rule)
	var failed := _results.count(false)
	print("==== review 17.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _hotspot(id: String) -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id:
			return h
	return null


## The night from bedtime2 to the morning by the bed, then Mama clicked (M21 is her talk) and its lines run; returns
## Nina's figure as it was in the morning before M21 and the worst alpha seen while M21 spoke.
func _night_and_morning() -> Dictionary:
	var out := {"morning_alpha": -1.0, "morning_pos": Vector2.ZERO, "home": Vector2.ZERO, "m21_min_alpha": 2.0, "m21_lines": 0}
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("bedtime2", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	var fig: Node2D = rm.current_room.get_node_or_null("npc_nina") as Node2D if rm.current_room != null else null
	var bed := _hotspot("bed")
	if fig == null or bed == null:
		_fails.append("bedtime2: no Nina figure (%s) or no bed (%s)" % [str(fig), str(bed)])
		main_node.queue_free()
		return out
	out["home"] = fig.global_position
	sr.interact(bed)
	var g := 0
	while g < 8000:
		g += 1
		await process_frame
		if gs.has_flag("done_M21"):
			break
		if gs.has_flag("morning_day3") and not gs.has_flag("started_M21") and sr.current_beat.is_empty() and not sr.is_busy():
			fig = rm.current_room.get_node_or_null("npc_nina") as Node2D
			if fig != null and float(out["morning_alpha"]) < 0.0:
				out["morning_alpha"] = fig.modulate.a
				out["morning_pos"] = fig.global_position
			var hn := _hotspot("nina")
			if hn != null:
				sr.interact(hn)
			continue
		if sr.active_scene == "M21" and not sr.current_beat.is_empty():
			fig = rm.current_room.get_node_or_null("npc_nina") as Node2D
			if fig != null:
				out["m21_min_alpha"] = minf(float(out["m21_min_alpha"]), fig.modulate.a)
				out["m21_lines"] = int(out["m21_lines"]) + 1
		if not sr.current_beat.is_empty() and not sr.is_staging():
			for i in 12:
				await process_frame
			sr.advance()
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await process_frame
	return out


func _test_morning_nina() -> void:
	var r: Dictionary = await _night_and_morning()
	_check(float(r["morning_alpha"]) > 0.95, "in the morning Nina is out of sight (alpha %.2f)" % float(r["morning_alpha"]))
	_check((r["morning_pos"] as Vector2).distance_to(r["home"]) < 2.0,
		"in the morning Nina is not in her place: %s, her place %s" % [str(r["morning_pos"]), str(r["home"])])
	_check(int(r["m21_lines"]) >= 3 and float(r["m21_min_alpha"]) > 0.95,
		"M21: %d lines, Nina's alpha down to %.2f while she spoke" % [int(r["m21_lines"]), float(r["m21_min_alpha"])])
	# self-check: the night as it was before the review — no npc_back — and the morning has no Nina in sight
	var n02: Dictionary = sd.scene("N02")
	var last: Dictionary = (n02.get("stage", []) as Array).back()
	var keep = last.get("npc_back", null)
	last.erase("npc_back")
	var bad: Dictionary = await _night_and_morning()
	if keep != null:
		last["npc_back"] = keep
	_check(float(bad["morning_alpha"]) < 0.05, "self-check: without npc_back Nina was still seen in the morning (alpha %.2f)" % float(bad["morning_alpha"]))


func _test_ghost_rule() -> void:
	var rule = load("res://tests/ghost_watch.gd")
	_check(rule.out_of_sight_but_clickable(0.0, false, true), "a shown hotspot over an invisible standing figure is not caught")
	_check(not rule.out_of_sight_but_clickable(0.0, true, true), "a figure walking off (fading) is caught")
	_check(not rule.out_of_sight_but_clickable(1.0, false, true), "a visible figure is caught")
	_check(not rule.out_of_sight_but_clickable(0.0, false, false), "a figure whose hotspot is hidden is caught")
