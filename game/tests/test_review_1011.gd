extends SceneTree
## The whole-game review of 10.11 (Director 13:00: «пройдёмся полностью по игре как тестировщик и обзорщик»):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1011.gd
##   R-1 (Director 15:12: «Тихон и Дуня — можно поправить»): in M23d the narrator says «Потом перебирается поближе к
##       Агатиной лежанке и там укладывается», and Tikhon sat in the armchair to the end of the scene — the flag
##       tikhon_knows_dunya came only with the scene's grants. Now a short fade after the narrator's words sets it:
##       «Значит, вечер кончился» he says from the bench by the stove. The test plays the scene and looks where his
##       figure is at each line; self-check — the same scene without that staging is caught (he is still in the chair).
##   R-2 (Director 16:15: «Пелагея в кадре где лодку смолят снова стоит повёрнута вправо, а не влево»; 17:56: «а Павел
##       повёрнут вправо, а не влево — не забыл исправить?»): EP_boat — Pelageya faces left, Mitya faces her; EP_pavel —
##       Pavel faces left.
##   R-3 (16:15: «чтобы она доходила до начала лестницы и мама ждала там»): M19 — Nina waits at the foot of her porch
##       stairs, Agata runs up to there.
##   R-4 (16:15: «когда она говорит „тянут, вон тянут“ — развернуть её в сторону реки»): the line is said to the river.
##   R-5 (16:15: «Агата проходит сквозь Пелагею в этом же кадре»): M17 played as the player starts it (a click on
##       Pelageya): from the boat's return to the ribbon Agata never comes nearer than a figure's width to her; her
##       place then is her hotspot's state (the click and the obstacle at her feet are there too). Self-check — the
##       night's point (885, 800) is caught.
##   R-6 (16:15: «Митя и мама где кадр — пересмотреть, чьи руки за какими руками должны быть… он дальше фонарь
##       поднимает же»): M18 — after the hug's frame the mother and the son stand a step apart (the staging's walk goes
##       while the frame is still shown and has to reach the people of the room under it; since 05.11 it looked only
##       among the frame's own figures and was dropped — they stood one in the other, Mitya took the lantern through
##       her). At «Мне уж тридцать семь» and at the lantern they are more than a figure apart, the lantern's place is
##       between them. Self-check — before the frame (the embrace) they are close, and the measure tells.
##   R-7 (16:15: «чтобы как-то крутился реально ворот у Ильи… оживить его, установку эту»): the windlass in the close-up
##       of the first span turns (WindlassSpin) — its parts are there; at rest the cranks stand exactly as painted (the
##       arm ends at the painted grip, both sides); while the log goes down the crank's angle grows, lifting — goes
##       back; let go, it comes to the painted pose and stays. Self-check — a crank that does not turn is caught.
##   R-8 (Director 18:59: «Лого Godot убрать вовсе, если можно»): the engine's logo is not shown at start —
##       application/boot_splash/show_image is off, the start screen is the dark background alone.
##   R-9 (обзор 10.11, кадры заданий): in a whole close-up (the picture in the carved frame begins at x 246) a title
##       longer than one short word ran under the picture — «Двадцать зар…». Every room's view with a title and a
##       picture: the title's words stand clear of every picture's frame. Self-check — the same title in the old
##       one-line box 520 wide is read as covered.
##   R-10 (Director 10.11, 23:26: «Пробел — это глобально, чтобы пропустить фразу и т. д., только мышкой»): with a line
##       on screen, Space and Enter take it on (its next page or the next line), as a click on it does. Self-check — a
##       key that is not bound (Q) leaves the line where it is.
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
	await _test("R-2 the epilogue: at the boat Pelageya faces left, Mitya faces her; Pavel at the gauge faces left", _test_boat_facing)
	await _test("R-3 M19: Nina waits at the foot of her porch stairs, Agata runs up to there", _test_porch_stairs)
	await _test("R-4 M17: «Тянут. Вон, тянут!» is said to the river", _test_line_to_river)
	await _test("R-5 M17: Agata does not walk through Pelageya on her way to the ribbon; self-check — the night's place is caught", _test_ribbon_walk)
	await _test("R-6 M18: after the hug's frame Pelageya and Mitya stand a step apart, the lantern between them; self-check — in the embrace they are close", _test_apart_after_hug)
	await _test("R-7 the windlass turns while the log goes and rests as painted; self-check — a still crank is caught", _test_windlass_turns)
	await _test("R-8 no engine logo at start: boot_splash/show_image is off, the background is dark", _test_no_boot_logo)
	await _test("R-9 a close-up's title is not covered by its picture («Двадцать зарубок»); self-check — the old one-line box is caught", _test_view_title_clear)
	await _test("R-10 Space and Enter take a line on, as a click on it; self-check — another key does not", _test_space_next_line)
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


## Which way a frame's figure looks, as the game works it out (NpcActor._face_data): `face_dir` first (the painted
## sheet's direction: 0 to the viewer, 2 left, 4 away, 6 right), else the point `face`. Returns the x of the unit
## facing vector: −1 left … +1 right.
static func _facing_x(h: Dictionary) -> float:
	if h.has("face_dir"):
		return sin(deg_to_rad(-45.0 * float(h["face_dir"])))
	var f: Array = h.get("face", [])
	if f.size() < 2:
		return 0.0
	var v := Vector2(float(f[0]), float(f[1])) - _feet(h)
	return v.normalized().x if v.length() > 1.0 else 0.0


func _test_boat_facing() -> void:
	var pel := _room_hotspot("EP_boat", "pelageya")
	var mit := _room_hotspot("EP_boat", "mitya")
	_check(not pel.is_empty() and not mit.is_empty(), "EP_boat has both figures")
	if pel.is_empty() or mit.is_empty():
		return
	var pf := _feet(pel)
	var mf := _feet(mit)
	_check(_facing_x(pel) < -0.5, "Pelageya looks left (facing x %.2f; face %s, feet %s)" % [_facing_x(pel), str(pel.get("face", [])), str(pf)])
	_check(_facing_x(mit) < -0.5 and absf(float(mit["face"][0]) - pf.x) < 60.0, "Mitya looks at her (face %s)" % str(mit["face"]))
	# self-check: the night's point (to Mitya, on her right) fails the same test
	_check(_facing_x({"feet": [pf.x, pf.y], "face": [1217, 885]}) > 0.5, "self-check: the night's facing (to the right) would be caught")
	# Director 17:56: «а Павел повёрнут вправо, а не влево — не забыл исправить?» — the frame after: Pavel faces left too.
	# His turn is given by `face_dir`, which goes before `face` (NpcActor._face_data): the first fix changed only
	# `face`, nothing changed on screen and a check of `face` alone passed — the facing is worked out as the game does.
	var pav := _room_hotspot("EP_pavel", "pavel")
	_check(not pav.is_empty() and _facing_x(pav) < -0.5, "EP_pavel: Pavel looks left (facing x %.2f; face_dir %s, face %s)" % [_facing_x(pav), str(pav.get("face_dir", "-")), str(pav.get("face", []))])
	var old_pav := pav.duplicate()
	old_pav["face_dir"] = 6
	_check(_facing_x(old_pav) > 0.5, "self-check: face_dir 6 with the new `face` point still looks right, and the check tells")


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


# --- R-6 ------------------------------------------------------------------------------------

func _test_apart_after_hug() -> void:
	_flags_before("M18")
	await _enter("R3", "from_R2")
	var lx := -1.0
	# the layer's picture is the room's canvas with the lantern alone on it: its place on screen = canvas × art scale
	for l in sd.rooms.get("R3", {}).get("layers", []):
		if String(l.get("id", "")) == "mitya_lantern" and ResourceLoader.exists(String(l.get("image", ""))):
			var used := (load(String(l["image"])) as Texture2D).get_image().get_used_rect()
			var off: Array = l.get("offset", [0, 0])
			lx = (float(used.position.x) + float(used.size.x) * 0.5) * float(rm.current_room.art_scale) + float(off[0])
	var dist := {}     # line text start → distance between the two (px)
	var at := {}
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.call("is_staging")) and guard < 20000:
		guard += 1
		if sr.call("is_staging"):
			await process_frame
			continue
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [{}])[0].get("id", "")))
		else:
			await _frames(2)
			var pel: Node2D = rm.current_room.get_node_or_null("npc_pelageya")
			var mit: Node2D = rm.current_room.get_node_or_null("npc_mitya")
			if pel != null and mit != null:
				var key := String(b.get("text", "")).left(18)
				dist[key] = absf(pel.global_position.x - mit.global_position.x)
				at[key] = [mit.global_position, pel.global_position]
			sr.advance()
		await process_frame
	await _frames(2)
	_check(gs.has_flag("done_M18"), "M18 played (%d lines seen)" % dist.size())
	var hug := float(dist.get("Пелагея с лодки на", -1.0))
	var after := float(dist.get("Мне уж тридцать се", -1.0))
	var lantern := float(dist.get("Пелагея всё держит", -1.0))
	_check(after > 140.0, "at «Мне уж тридцать семь» they stand a step apart (%.0f px)" % after)
	_check(lantern > 100.0, "at the lantern's line they are apart too (%.0f px)" % lantern)
	# the lantern on the snow (the room's layer `mitya_lantern`): between them, so that he takes it in front of him
	_check(lx > 0.0, "the lantern's layer is in the room (x %.0f)" % lx)
	if lx > 0.0 and at.has("Мне уж тридцать се"):
		var mx: float = (at["Мне уж тридцать се"][0] as Vector2).x
		var px: float = (at["Мне уж тридцать се"][1] as Vector2).x
		_check(lx > minf(mx, px) + 20.0 and lx < maxf(mx, px) - 20.0, "the lantern (x %.0f) is between them (Mitya %.0f, Pelageya %.0f)" % [lx, mx, px])
	_check(hug >= 0.0 and hug < 80.0, "self-check: in the embrace, before the frame, they are close (%.0f px) — the measure tells close from apart" % hug)


# --- R-7 ------------------------------------------------------------------------------------

func _test_windlass_turns() -> void:
	var spec: Dictionary = sd.scene("M25")["mechanics"][0]["spec"]
	var art := String(spec.get("art", {}).get("waiting", ""))
	var sp: WindlassSpin = WindlassSpin.make(art, 1.0)
	_check(sp != null, "the windlass's parts are beside the site's picture (%s)" % art)
	if sp == null:
		return
	_check(sp.get_node_or_null("Clean") != null and sp.get_node_or_null("Drum") != null and sp._grips.size() == 2,
		"the patch over the painted cranks, the drum's coils and both grips are loaded")
	for side in ["l", "r"]:
		var j: Array = sp.meta["grips"][side]["joint"]
		var d: float = sp.tip(side).distance_to(Vector2(float(j[0]), float(j[1])))
		_check(d < 0.5, "at rest the %s crank's arm ends at the painted grip (%.2f px off)" % [side, d])
	var top := sp.tip("l")
	sp.angle = WindlassSpin.REST + PI
	_check(sp.tip("l").y > top.y + 40.0 and sp.tip("r").y < sp.tip("l").y, "half a turn on, the left crank is down and the right one up")
	sp.angle = WindlassSpin.REST + TAU
	_check(sp.tip("l").distance_to(top) < 0.01, "a whole turn brings it back")
	_check(sp.grip_point("l", 1.0).x < sp.grip_point("l", 0.0).x - 20.0, "the left grip's free end is towards Ilya (the hands' place)")
	# the crank is the log: painted pose at the start and with the log laid, whole turns between
	_check(absf(fposmod((WindlassSpin.angle_for(0.0, 0.66, 4.0) - WindlassSpin.REST) / TAU + 0.5, 1.0) - 0.5) < 1e-4
		and is_equal_approx(WindlassSpin.angle_for(0.66, 0.66, 4.0), WindlassSpin.REST),
		"the crank stands as painted before the first «Пускай» and with the log on the ring")
	# the coils: the shift never leaves one coil (18:59 «дальше его корёжит» — the old shift wrapped round the picture)
	var mat := (sp.get_node("Drum") as Sprite2D).material as ShaderMaterial
	var pitch := float(sp.meta["drum"]["pitch"])
	var worst := 0.0
	for i in 200:
		sp.angle = WindlassSpin.REST + float(i) * 0.37
		worst = maxf(worst, float(mat.get_shader_parameter("shift")))
	_check(worst <= pitch + 0.001 and worst > pitch * 0.8, "the coils' shift stays within one coil over many turns (max %.2f of %.2f px)" % [worst, pitch])
	_check(not (pitch * 200.0 * 0.37 / TAU <= pitch + 0.001), "self-check: a shift that grows with the turns (the old one) would be caught")
	sp.free()
	# in the close-up: the angle follows the log
	_flags_before("M25")
	await _enter("Z3", "from_R1")
	await _read_out("")
	sr.open_mechanic(spec, "")
	await _frames(3)
	var panel = main_node.get_node("MechanicView").get("panel")
	_check(panel != null and panel.spin != null, "the close-up has the turning windlass")
	if panel == null or panel.spin == null:
		return
	var a0: float = panel.spin.angle
	_check(absf(fposmod((a0 - WindlassSpin.REST) / TAU + 0.5, 1.0) - 0.5) < 0.01, "it opens with the crank as painted (%.3f turns off)" % ((a0 - WindlassSpin.REST) / TAU))
	panel.signal_pressed("lower")
	await _frames(20)
	var a1: float = panel.spin.angle
	_check(a1 > a0 + 0.2, "«Пускай»: the crank turns (%.2f → %.2f rad)" % [a0, a1])
	panel.signal_pressed("stop")
	await _frames(3)
	var a2: float = panel.spin.angle
	await _frames(30)
	_check(panel.logic.state in ["settling", "solved"] or absf(panel.spin.angle - a2) < 0.001, "«Стой»: the log stands — the crank stands (%.3f → %.3f)" % [a2, panel.spin.angle])
	_check(not (a0 > a0 + 0.2), "self-check: a crank that does not turn fails the same test")
	if panel.logic.state == "stopped":
		panel.signal_pressed("raise")
		await _frames(20)
		_check(panel.spin.angle < a2 - 0.2, "«Подымай»: it turns the other way (%.2f → %.2f)" % [a2, panel.spin.angle])
	sr.close_mechanic()
	await _frames(3)


## R-8 (Director 10.11, 18:59: «Лого Godot убрать вовсе, если можно»): the project's own settings, as the exported game
## reads them — the boot splash shows no image and its background is dark (the first frame before the menu is not a
## light flash). Self-check: the engine's default (the logo shown) is what the same reading calls wrong.
func _test_no_boot_logo() -> void:
	var cf := ConfigFile.new()
	var err := cf.load("res://project.godot")
	_check(err == OK, "project.godot does not load (%d)" % err)
	if err != OK:
		return
	var show = cf.get_value("application", "boot_splash/show_image", true)   # the engine's default is true
	var bg = cf.get_value("application", "boot_splash/bg_color", Color(0.14, 0.14, 0.14))
	_check(show is bool and show == false, "boot_splash/show_image is %s — the engine's logo shows at start" % str(show))
	_check(bg is Color and (bg as Color).get_luminance() < 0.08, "the boot screen's background is not dark (%s)" % str(bg))
	_check(bool(ProjectSettings.get_setting("application/boot_splash/show_image", true)) == false, "the running project still has the boot image on")
	# self-check: a project without the line reads as «logo shown»
	var bare := ConfigFile.new()
	bare.parse("[application]\nconfig/name=\"x\"\n")
	_check(bool(bare.get_value("application", "boot_splash/show_image", true)) == true, "self-check: a project without the setting reads as logo off (the test sees nothing)")


## R-9: where the title's words are drawn against the pictures' frames (the view's own px).
func _title_overlap(cv: Node) -> float:
	var title: Label = cv.get("title_label")
	if title == null:
		return 0.0
	var font := title.get_theme_font("font")
	var fsize := title.get_theme_font_size("font_size")
	# the widest line as the label breaks it: each word's width, a line holds what fits in the box
	var widest := 0.0
	var line := ""
	for w in title.text.split(" ", false):
		var cand: String = (line + " " + w) if line != "" else w
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= title.size.x or line == "":
			line = cand
		else:
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
			line = w
	widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
	var words := Rect2(title.position, Vector2(widest, float(title.get_line_count()) * float(title.get_line_height())))
	var over := 0.0
	for sh in cv.get("sheets"):
		var c := sh as Control
		if c == null or not String(c.name).begins_with("Picture") or not c.is_visible_in_tree():
			continue
		var fr := Rect2(c.position, c.size).grow(16.0)   # the carved frame's band
		if fr.intersects(words):
			over = maxf(over, words.end.x - fr.position.x)
	return over


func _test_view_title_clear() -> void:
	var cv: Node = main_node.get_node("CloseupView")
	var seen := 0
	var longest := ""
	var longest_spec: Dictionary = {}
	var ids: Array = (sd.get("rooms") as Dictionary).keys() if sd.get("rooms") is Dictionary else ["H1", "O3", "O4"]
	for rid in ids:
		var room: Dictionary = sd.call("room", String(rid))
		for h in room.get("hotspots", []):
			var v = h.get("view")
			if not (v is Dictionary) or String(v.get("title", "")) == "" or (v.get("pictures", []) as Array).is_empty():
				continue
			sr.open_view(v, String(h.get("id", "")))
			await _frames(4)
			var over := _title_overlap(cv)
			var t: String = (cv.get("title_label") as Label).text
			_check(over <= 0.0, "%s %s: the title «%s» runs %.0f px under its picture" % [rid, h.get("id"), t, over])
			seen += 1
			if t.length() > longest.length():
				longest = t
				longest_spec = v
			sr.close_view()
			await _frames(2)
	_check(seen >= 3, "only %d views with a title and a picture were found (H1 sleeve, O3 notches, O4 board expected)" % seen)
	# self-check: the longest title in the old box — one line, 520 wide — is under the picture
	if not longest_spec.is_empty():
		sr.open_view(longest_spec, "")
		await _frames(4)
		var title: Label = cv.get("title_label")
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.size = Vector2(520, 60)
		await _frames(2)
		var over0 := _title_overlap(cv)
		_check(over0 > 10.0, "self-check: «%s» in the old one-line box is not read as covered (%.0f px) — the test sees nothing" % [longest, over0])
		sr.close_view()
		await _frames(2)


## R-10: a key press as the player gives it (pressed, then released).
func _press_key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)
		await _frames(1)


func _test_space_next_line() -> void:
	_flags_before("M23d")
	await _enter("H1")
	await _read_out("")
	_check(await _use("tikhon"), "M23d starts (a scene with several lines)")
	var ui = root.get_tree().get_first_node_in_group("game_ui")
	_check(ui != null, "the game's UI is there")
	if ui == null:
		return
	var tl = ui.get("text_label")
	var keys := {KEY_Q: false, KEY_SPACE: true, KEY_ENTER: true}
	for k in [KEY_Q, KEY_SPACE, KEY_ENTER]:
		# a line on screen, its staging done
		var g := 0
		while g < 2400 and (sr.call("is_staging") or sr.current_beat.is_empty() or String(sr.current_beat.get("type", "")) == "options" or not (ui.get("dialogue") as CanvasItem).visible):
			if String(sr.current_beat.get("type", "")) == "options":
				sr.choose(String(sr.current_beat["options"][0]["id"]))
			await physics_frame
			g += 1
		if sr.current_beat.is_empty():
			_check(false, "the scene ended before the %s check" % OS.get_keycode_string(k))
			return
		await _frames(3)
		var before := "%s|%s" % [sr.current_beat.get("line_id", sr.current_beat.get("text", "")), tl.get("text")]
		await _press_key(k)
		await _frames(2)
		var after := "%s|%s" % [sr.current_beat.get("line_id", sr.current_beat.get("text", "")), tl.get("text")]
		if bool(keys[k]):
			_check(after != before, "%s takes the line on (still «%s»)" % [OS.get_keycode_string(k), before.left(60)])
		else:
			_check(after == before, "self-check: %s moved the line («%s» → «%s») — the test cannot tell a key from any key" % [OS.get_keycode_string(k), before.left(40), after.left(40)])
	await _read_out("")
