extends SceneTree
## The whole-game review of 10.11 (Director 13:00: «пройдёмся полностью по игре как тестировщик и обзорщик»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1011.gd
##   R-1 (Director 15:12: «Тихон и Дуня — можно поправить»): in M23d the narrator says «Потом перебирается поближе к
##       Агатиной лежанке и там укладывается», and Tikhon sat in the armchair to the end of the scene — the flag
##       tikhon_knows_dunya came only with the scene's grants. Now a short fade after the narrator's words sets it:
##       «Значит, вечер кончился» he says from the bench by the stove. The test plays the scene and looks where his
##       figure is at each line; self-check — the same scene without that staging is caught (he is still in the chair).
##   R-2 (Director 16:15: «Пелагея в кадре где лодку смолят снова стоит повёрнута вправо, а не влево»): EP_boat —
##       Pelageya faces left, Mitya faces her.
##   R-3 (16:15: «чтобы она доходила до начала лестницы и мама ждала там»): M19 — Nina waits at the foot of her porch
##       stairs, Agata runs up to there.
##   R-4 (16:15: «когда она говорит „тянут, вон тянут“ — развернуть её в сторону реки»): the line is said to the river.
##   R-5 (16:15: «Агата проходит сквозь Пелагею в этом же кадре»): M17 played as the player starts it (a click on
##       Pelageya): from the boat's return to the ribbon Agata never comes nearer than a figure's width to her; her
##       place then is her hotspot's state (the click and the obstacle at her feet are there too). Self-check — the
##       night's point (885, 800) is caught.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var sd: Node = null
var main_node: Node = null
var player: Node = null


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
	player = main_node.get_node("World/Player")
	player.set("walk_speed", 1600.0)
	player.set("speed_factor", 6.0)
	await _test("R-1 M23d: Tikhon moves to Agata's bench after the narrator's words, before «Значит, вечер кончился»; self-check — without the staging he is still in the chair", _test_tikhon_moves)
	await _test("R-2 the epilogue's boat: Pelageya faces left, Mitya faces her", _test_boat_facing)
	await _test("R-3 M19: Nina waits at the foot of her porch stairs, Agata runs up to there", _test_porch_stairs)
	await _test("R-4 M17: «Тянут. Вон, тянут!» is said to the river", _test_line_to_river)
	await _test("R-5 M17: Agata does not walk through Pelageya on her way to the ribbon; self-check — the night's place is caught", _test_ribbon_walk)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== review 10.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room: String, spawn: String = "default") -> void:
	rm.change_room(room, spawn)
	await physics_frame
	await physics_frame
	await _frames(3)


func _wait_idle() -> void:
	var frames := 0
	while (player.call("is_walking") or player.call("is_acting") or sr.get("_loop_running") or sr.call("is_staging")) and frames < 2400:
		await physics_frame
		frames += 1
	await _frames(2)


func _use(id: String) -> bool:
	var h: Node2D = rm.current_room.get_node_or_null("Hotspots/" + id) if rm.current_room != null else null
	if h == null or not h.visible:
		return false
	player.call("click_at", h.global_position)
	await _wait_idle()
	return true


## Everything the story gave before scene `upto` (flags of the scenes' grants and stagings).
func _flags_before(upto: String) -> void:
	gs.reset()
	sr.call("_on_state_reset")
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for st in sc.get("stage", []):
			for f in st.get("sets", []):
				gs.set_flag(String(f), true)


## Reads the queued beats out; for each spoken line — where Tikhon's figure is and whether he knows:
## [{text, knows, pos}].
func _read_out(pick: String) -> Array:
	var log: Array = []
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 4000:
		guard += 1
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			var id := pick
			if not opts.any(func(o): return String(o.get("id", "")) == pick):
				id = String(opts[0].get("id", "")) if not opts.is_empty() else ""
			sr.choose(id)
		else:
			await _frames(2)   # the figure follows the flag on the next frame
			var t: Node2D = sr.call("_actor_node", rm.current_room, "tikhon")
			log.append({"text": String(b.get("text", "")), "knows": gs.has_flag("tikhon_knows_dunya"),
				"pos": t.global_position if t != null else Vector2.INF})
			sr.advance()
		await process_frame
	await _frames(2)
	return log


func _play_m23d() -> Array:
	_flags_before("M23d")
	gs.set_flag("tikhon_knows_dunya", false)
	await _enter("H1")
	await _read_out("")          # whatever the room says on entering
	if not await _use("tikhon"):
		return []
	return await _read_out("nina")


static func _line(log: Array, begins: String) -> Dictionary:
	for e in log:
		if String(e["text"]).begins_with(begins):
			return e
	return {}


# --- R-1 ------------------------------------------------------------------------------------

func _test_tikhon_moves() -> void:
	var sc: Dictionary = sd.scene("M23d")
	var lines: Array = sc.get("mandatory_lines", [])
	var narr := -1
	for i in lines.size():
		if String(lines[i].get("text", "")).contains("перебирается"):
			narr = i
	_check(narr >= 0, "M23d has the narrator's line about Tikhon moving")
	var stage: Array = sc.get("stage", [])
	_check(stage.any(func(s): return typeof(s.get("at")) != TYPE_STRING and int(s.get("at", -1)) == narr + 1 and (s.get("sets", []) as Array).has("tikhon_knows_dunya")),
		"the staging right after the narrator's line sets tikhon_knows_dunya (line %d)" % (narr + 1))
	var log := await _play_m23d()
	var before := _line(log, "Долго Тихон молчит")
	var after := _line(log, "Значит, вечер кончился")
	_check(not before.is_empty() and not after.is_empty(), "the scene played: the narrator's line and Tikhon's answer were read (%d lines)" % log.size())
	if before.is_empty() or after.is_empty():
		return
	var chair: Vector2 = before["pos"]
	var bench: Vector2 = after["pos"]
	_check(not bool(before["knows"]), "while the narrator speaks Tikhon is still in the armchair (the flag is not set yet)")
	_check(bool(after["knows"]), "«Значит, вечер кончился» — the flag is set by then")
	# the armchair is low at the left (feet y ≈ 790…890 of the room), the bench by the stove higher (≈ 460…620)
	_check(chair.y - bench.y > 120.0, "Tikhon's figure is up on the bench when he answers: armchair %s → bench %s" % [str(chair), str(bench)])
	_check(gs.has_flag("done_M23d"), "the scene completes")
	# Self-check: the same scene without the staging — he answers from the armchair, and the measure sees it.
	var kept: Array = stage.duplicate()
	var cut: Array = stage.filter(func(s): return not (s.get("sets", []) as Array).has("tikhon_knows_dunya"))
	stage.clear()
	stage.append_array(cut)
	var log2 := await _play_m23d()
	stage.clear()
	stage.append_array(kept)
	var after2 := _line(log2, "Значит, вечер кончился")
	_check(not after2.is_empty() and not bool(after2["knows"]) and absf((after2["pos"] as Vector2).y - chair.y) < 40.0,
		"self-check: without the staging he is still in the armchair at his answer, and the check tells (%s)" % str(after2.get("pos", null)))


# --- R-2 … R-5 --------------------------------------------------------------------------------

func _room_hotspot(room_id: String, id: String) -> Dictionary:
	for h in sd.rooms.get(room_id, {}).get("hotspots", []):
		if String(h.get("id", "")) == id:
			return h
	return {}


static func _feet(h: Dictionary) -> Vector2:
	if h.has("feet"):
		return Vector2(float(h["feet"][0]), float(h["feet"][1]))
	var r: Array = h.get("rect", [0, 0, 0, 0])
	return Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]))


func _test_boat_facing() -> void:
	var pel := _room_hotspot("EP_boat", "pelageya")
	var mit := _room_hotspot("EP_boat", "mitya")
	_check(not pel.is_empty() and not mit.is_empty(), "EP_boat has both figures")
	if pel.is_empty() or mit.is_empty():
		return
	var pf := _feet(pel)
	var mf := _feet(mit)
	_check(float(pel["face"][0]) < pf.x - 100.0, "Pelageya looks left of where she stands (face %s, feet %s)" % [str(pel["face"]), str(pf)])
	_check(float(mit["face"][0]) < mf.x - 100.0 and absf(float(mit["face"][0]) - pf.x) < 60.0, "Mitya looks at her (face %s)" % str(mit["face"]))
	# self-check: the night's point (to Mitya, on her right) fails the same test
	_check(not (1217.0 < pf.x - 100.0), "self-check: the night's facing (to the right) would be caught")


func _test_porch_stairs() -> void:
	var nina := _room_hotspot("O4", "nina")
	var nf := _feet(nina)
	# the bottom step of her porch on the picture: x 1440–1530, y 630–670 (the gate's post, where she stood, is at 1385, 705)
	var foot := Rect2(1440, 630, 90, 40)
	_check(foot.has_point(nf), "Nina's feet at the foot of the stairs (%s)" % str(nf))
	_check(not foot.has_point(Vector2(1385, 705)), "self-check: the gate's post is not the foot of the stairs")
	var go := {}
	for st in sd.scene("M19").get("stage", []):
		if st.has("agata_go"):
			go = st["agata_go"]
	_check(not go.is_empty(), "M19 has Agata's run")
	if go.is_empty():
		return
	var to := Vector2(float(go["to"][0]), float(go["to"][1]))
	_check(to.distance_to(nf) < 110.0 and to.distance_to(nf) > 40.0, "Agata stops by her, not in her (%s, %.0f px from Nina)" % [str(to), to.distance_to(nf)])
	var poly := PackedVector2Array()
	for p in sd.rooms.get("O4", {}).get("walkable", []):
		poly.append(Vector2(float(p[0]), float(p[1])))
	_check(Geometry2D.is_point_in_polygon(to, poly), "the spot is on the street's floor")
	_check(Vector2(1305, 722).distance_to(nf) > 110.0, "self-check: the old spot (the gate) is too far from the stairs")


func _test_line_to_river() -> void:
	var pel := _feet(_room_hotspot("Z3", "pelageya"))
	var ln := {}
	for l in sd.scene("M17").get("mandatory_lines", []):
		if String(l.get("text", "")).begins_with("Тянут"):
			ln = l
	_check(not ln.is_empty(), "M17 has the line")
	var f: Array = ln.get("face", [])
	_check(f.size() >= 2 and float(f[1]) < pel.y - 200.0, "the line has a point out on the river to be said to (%s; she stands at %s)" % [str(f), str(pel)])
	_check(not ({} as Dictionary).has("face"), "self-check: a line without `face` is said to Agata")


## Plays M17 from the click on Pelageya; returns the nearest Agata's feet came to Pelageya's feet (px, floor-scaled:
## the vertical distance counts double — figures overlap by x) after the boat is back, and where Pelageya stood.
func _ribbon_walk() -> Dictionary:
	_flags_before("M17")
	gs.set_flag("m17_boat_hauled", false)
	await _enter("Z3", "from_R1")
	await _read_out("")
	if not await _use("pelageya"):
		return {}
	var nearest := 1e9
	var pel_at := Vector2.ZERO
	var back := false
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 20000:
		guard += 1
		var pel: Node2D = rm.current_room.get_node_or_null("npc_pelageya")
		if back and pel != null:
			var d: Vector2 = player.global_position - pel.global_position
			nearest = minf(nearest, Vector2(d.x, d.y * 2.0).length())
			pel_at = pel.global_position
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if String(b.get("text", "")).begins_with("Сама назад не пришла"):
			back = true
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [{}])[0].get("id", "")))
		else:
			sr.advance()
		await process_frame
	await _frames(2)
	return {"nearest": nearest, "pelageya": pel_at, "done": gs.has_flag("done_M17")}


func _test_ribbon_walk() -> void:
	var r := await _ribbon_walk()
	_check(not r.is_empty() and bool(r.get("done", false)), "M17 played from the click on Pelageya")
	if r.is_empty():
		return
	_check(float(r["nearest"]) > 150.0, "Agata keeps clear of Pelageya from the boat's return to the ribbon (nearest %.0f px)" % float(r["nearest"]))
	var st_feet := Vector2.ZERO
	for st in _room_hotspot("Z3", "pelageya").get("states", []):
		if (st.get("if", []) as Array).has("m17_boat_hauled"):
			st_feet = _feet(st)
	_check(st_feet != Vector2.ZERO and (r["pelageya"] as Vector2).distance_to(st_feet) < 12.0,
		"she stands where her hotspot's state has her (figure %s, state %s)" % [str(r["pelageya"]), str(st_feet)])
	# Self-check: the night's staging (she at 885, 800, on the way) — the same measure sees Agata walk through her.
	var sc: Dictionary = sd.scene("M17")
	var kept := {}
	for st in sc.get("stage", []):
		for g in st.get("npc_to", []):
			if String(g.get("id", "")) == "pelageya":
				kept = {"g": g, "to": g["to"], "st": st, "sets": st.get("sets", [])}
				g["to"] = [885, 800]
				st["sets"] = []
	var r2 := await _ribbon_walk()
	if not kept.is_empty():
		kept["g"]["to"] = kept["to"]
		kept["st"]["sets"] = kept["sets"]
	_check(not r2.is_empty() and float(r2["nearest"]) < 90.0, "self-check: with the night's place Agata walks through her, and the check tells (nearest %.0f px)" % float(r2.get("nearest", -1.0)))
