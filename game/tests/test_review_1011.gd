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
##   R-11 (Director 10.11: «упрощение игры в клиньях в момент игры куда-то делось»): in the office mirror's close-up,
##       while the wedges' bar runs, an «Облегчить» switch is visible on screen; switched, the bar's green widens at once.
##   R-12 (Director 10.11: «когда легло и „на торце резать“ сцена — Агата телепортируется»): where a scene cuts from one
##       frame to another of the same picture (M25: the windlass → the log laid), every figure in both stands where it
##       stood (≤ 4 px); a move is a walk in the staging. Self-check — Agata's place in the second frame before 10.11
##       (1385, 890 against 775, 892) is caught.
##   R-13 (Director 10.11: «у двери, когда мы взяли петли, но не нажимали на рисунок… добавить фразу, что нужно на чертёж
##       посмотреть»): the hinges used on the school door with no drawing in the bag — the line about the drawing on the
##       workshop wall (H3.puzzle.need_drawing); with neither — the common «Родные петли нужны да рисунок…».
##   R-14 (Director 10.11, 21:50: «в начале после выхода с почты — подсвечивать мерцая немножко первую стрелку вниз, если
##       юзер тупит допустим 10 секунд»): in the lane (Z4) after the post office, before the street was ever seen, the
##       mark «На улицу» starts flickering after 10 s with no click and flickers on (its drawn alpha swings by > 0.15,
##       brighter than idle); a key or click starts the count again; a dialogue pauses it; once the street was visited —
##       no flicker. Self-check — the same mark without the nudge data stays calm after the same wait.
##   R-15 (Director 10.11, 22:25: «после повешения каната на плиту Пелагея говорит на фоне плиты, странно, может убрать
##       автоматически после натягивания»; 23:26 «ну наверное так да»): the knot tied — the painted knot is seen a moment,
##       then the close-up goes black and is put away by itself; M15's first line («Канат натянулся ровно…») comes in the
##       room. Self-check — without `close_black` on the event the line comes over the close-up.
##   R-16 (Director 10.11, 22:21: «перетаскивать добавить возможность предметы в игре, если не сложно»): the hinges pressed
##       in their pocket, carried with the button held onto the school door and let go there — used on the door (Agata
##       says R-13's line about the drawing); carried to empty floor — back in the bag, nothing said; a press let go
##       without carrying is the click it always was (the item stays in hand). Self-check — a «drag» of 5 px is a click.
##   R-17 (Director 10.11, 22:47: «после сцены с управляющим все пропали, а Агаты положение изменилось»; 23:26 «после
##       мельницы все остаются, если это ничего не нарушает»): after the council's frame (M23b) Pavel, the manager and
##       Ilya stand in the mill yard where the frame had them (≤ 6 px), Agata where she stood in it; they are not
##       clicked (no caption, no line); Agata leaves the yard — back there, they are gone. Self-check — the same yard
##       before the council: none of the three.
##   R-18 (Director 10.11, 22:15: «Павел, выходя из конторы, становится чуть больше двери»): in the office the depth is
##       measured by the door's leaf (y 163–668, 505 px), not with the lintel board above it (550): Pavel in the doorway
##       where M13 takes him is lower than the leaf, Agata at the threshold 0.85–0.95 of it. Self-check — the old depth
##       (1.504 … 2.826) makes Pavel taller than the door.
##   R-19 (Director 10.11, 22:15: «рычаг не снимает в конторе — добавить анимацию»; 23:40: «хотя бы тянуться может в ту
##       сторону тогда»): at M13's end Agata takes the clamp from the desk with her reach, then walks along the back wall as
##       near the lever as the floor goes (≤ x 660) and reaches towards it, turned left; the lever leaves the wall as she
##       reaches — before the scene gives the things to the bag. Self-check — before that the lever is on the wall.
##   R-20 (Director 10.11, 22:26: «после того как 3 раза в фонарь позвонили, то 2 раза „Закрыть“ надо жать, и фейдаут
##       между этим будто бы лишний»): three flashes answered — the lantern's close-up goes away by itself (no
##       «Закрыть»), Pelageya's «Ответили!» comes on the pier. Self-check — without `close` on the event she speaks over
##       the close-up.
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
	# ONLY=R-13,R-14 — run just these (local checks; the full run takes all)
	var only := OS.get_environment("ONLY")
	if only != "":
		var hit := false
		for p in only.split(","):
			if test_name.begins_with(p.strip_edges() + " "):
				hit = true
		if not hit:
			return
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
	await _test("R-11 the wedges: «Облегчить» is on screen while the bar runs and eases the bar at once", _test_wedges_ease)
	await _test("R-12 a cut between two frames of one picture keeps the people where they stood; self-check — Agata's old place at the log is caught", _test_cut_keeps_places)
	await _test("R-13 the hinges at the school door without Dunya's drawing: Agata says to look at the drawing first; self-check — with nothing in the bag the common line", _test_hinges_need_drawing)
	await _test("R-15 the knot tied: the plate's close-up goes black and away by itself, M15 is spoken in the room; self-check — without close_black it is spoken over the close-up", _test_plate_closes)
	await _test("R-16 an item dragged from the bag onto the school door is used there, onto empty floor goes back; a press is still a click; self-check — 5 px is a click", _test_drag_item)
	await _test("R-17 after the council the people stay in the mill yard where the frame had them, Agata too; not clicked; gone once she leaves; self-check — none before the council", _test_council_stays)
	await _test("R-18 the office: Pavel in the doorway is lower than the door's leaf, Agata at the threshold 0.85–0.95 of it; self-check — the old depth makes him taller", _test_pavel_door)
	await _test("R-19 the office lever: Agata goes as near as the floor lets her and reaches to it, the lever leaves the wall with her reach; self-check — on the wall before", _test_lever_reach)
	await _test("R-20 three lights answered: the lantern's close-up goes by itself, Pelageya speaks on the pier; self-check — without close she speaks over it", _test_lights_close)
	await _test("R-14 the lane after the post office: the arrow down flickers after 10 s with no click; a click resets it; not once the street was seen; self-check — no data, no flicker", _test_idle_nudge)
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


func _test_wedges_ease() -> void:
	_flags_before("M10")
	gs.set_flag("office_mirror_mounted", true)
	gs.set_flag("office_mirror_clamped", false)
	await _enter("H2")
	await _read_out("")
	var h = rm.current_room.get_node_or_null("Hotspots/stand_zm")
	_check(h != null, "the stand «ЗМ» is in the workshop")
	if h == null:
		return
	var TB: GDScript = load("res://scripts/mechanics/timing_bar.gd")
	var was_slow: bool = bool(TB.get("slow"))
	TB.call("set_slow", false)
	sr.open_mechanic(sr.mechanic_spec(h), "stand_zm")
	await _frames(20)
	var mv = main_node.get_node("MechanicView")
	var panel = mv.get("panel") if mv != null else null
	_check(panel != null and panel.get("wedge_timing") != null and (panel.get("wedge_timing") as CanvasItem).is_visible_in_tree(), "the wedges' bar is up (frame not clamped yet)")
	if panel == null or panel.get("wedge_timing") == null:
		TB.call("set_slow", was_slow)
		return
	# whatever «Облегчить» switch is on screen now
	var shown: Array = []
	for n in panel.find_children("*", "CheckButton", true, false):
		var cb := n as CheckButton
		var r := cb.get_global_rect()
		if cb.is_visible_in_tree() and r.size.x > 10.0 and Rect2(0, 0, 1920, 1080).encloses(r):
			shown.append(cb)
	_check(shown.size() == 1, "one «Облегчить» on screen while the bar runs (%d)" % shown.size())
	if shown.size() >= 1:
		var bar = panel.get("wedge_timing")
		var g0: float = float(bar.logic.green_k)
		(shown[0] as CheckButton).button_pressed = true
		await _frames(3)
		_check(float(bar.logic.green_k) > g0 + 0.01, "switched on, the bar's green widens at once (%.2f → %.2f)" % [g0, float(bar.logic.green_k)])
		(shown[0] as CheckButton).button_pressed = false
		await _frames(2)
	sr.close_mechanic()
	await _frames(3)
	TB.call("set_slow", was_slow)


func _frame_feet(fid: String) -> Dictionary:
	var out := {}
	for h in sd.rooms.get(fid, {}).get("hotspots", []):
		if String(h.get("kind", "")) == "npc" and h.has("feet"):
			out[String(h["id"])] = Vector2(float(h["feet"][0]), float(h["feet"][1]))
	return out


## Pairs [scene, frame before, frame after] joined by a cut, the two frames of one picture.
func _cut_pairs() -> Array:
	var out: Array = []
	for sid in sd.scene_order:
		var prev := ""
		for st in sd.scene(String(sid)).get("stage", []):
			if not st.has("frame"):
				continue
			var cur := String(st["frame"])
			if cur != "" and prev != "" and bool(st.get("cut", false)) \
					and String(sd.rooms.get(prev, {}).get("background", {}).get("image", "")) == String(sd.rooms.get(cur, {}).get("background", {}).get("image", "-")):
				out.append([String(sid), prev, cur])
			prev = cur
	return out


func _test_cut_keeps_places() -> void:
	var pairs := _cut_pairs()
	_check(pairs.any(func(p): return p[1] == "F_span" and p[2] == "F_span_done"), "M25's cut from the windlass to the laid log is found (%s)" % str(pairs))
	for p in pairs:
		var a := _frame_feet(String(p[1]))
		var b := _frame_feet(String(p[2]))
		for id in a:
			if b.has(id):
				var d: float = (a[id] as Vector2).distance_to(b[id])
				_check(d <= 4.0, "%s: %s jumps %.0f px at the cut %s → %s" % [p[0], id, d, p[1], p[2]])
	# self-check: the second frame as it was before 10.11
	var before := _frame_feet("F_span")
	var old_place := Vector2(1385, 890)
	_check((before.get("agata", Vector2.ZERO) as Vector2).distance_to(old_place) > 4.0, "self-check: Agata's old place in the laid-log frame would be read as a jump")


## Every line shown after a click on the school door (with the item in hand, if any), read to the end.
func _door_lines(item: String) -> Array:
	await _wait_idle()   # a click while she still acts (the last use's gesture) is ignored, as in the game
	if item != "":
		sr.select_item(item)
	var h: Node2D = rm.current_room.get_node_or_null("Hotspots/school_door")
	if h == null:
		return []
	player.call("click_at", h.global_position)
	var seen: Array = []
	var g := 0
	while g < 900:
		g += 1
		await physics_frame
		if not sr.current_beat.is_empty():
			seen.append(String(sr.current_beat.get("text", "")))
			sr.advance()
		elif g > 120 and not player.call("is_walking") and not sr.call("is_staging"):
			break
	if sr.puzzle_open:
		sr.close_puzzle()
	if sr.selected_item != "":
		sr.select_item(sr.selected_item)   # put it back
	return seen


func _test_hinges_need_drawing() -> void:
	_flags_before("M05")
	gs.remove_item("door_drawing")
	gs.add_item("door_hinges")
	await _enter("H3")
	await _read_out("")
	var want: String = sd.text("@H3.puzzle.need_drawing")
	var common: String = sd.text("@H3.puzzle.need")
	var with_hinges := await _door_lines("door_hinges")
	_check(with_hinges.has(want), "hinges in hand, no drawing: «%s» (got %s)" % [want.left(40), str(with_hinges)])
	gs.remove_item("door_hinges")
	var with_none := await _door_lines("")
	_check(with_none.has(common) and not with_none.has(want), "self-check: nothing in the bag — the common line (got %s)" % str(with_none))


## The mark of the Z4 → Z2 exit (the lane → the street) in the room now on screen.
func _street_cue() -> Node2D:
	if rm.current_room == null:
		return null
	for e in rm.current_room.get_exits():
		if String(e.get("target_room")) == "Z2":
			return e.get("cue")
	return null


## The mark's drawn alpha over `s` seconds of game time: [min, max].
func _alpha_range(cue: Node2D, s: float) -> Array:
	var lo := 9.0
	var hi := -9.0
	var t := 0.0
	while t < s:
		await process_frame
		t += cue.get_process_delta_time()
		var a: float = cue.call("look")["alpha"]
		lo = minf(lo, a)
		hi = maxf(hi, a)
	return [lo, hi]


## Waits `s` seconds of game time (the frames' own deltas: fixed fps or the clock); returns the time waited.
func _game_wait(node: Node, s: float) -> float:
	var t := 0.0
	while t < s:
		await process_frame
		t += node.get_process_delta_time()
	return t


func _test_idle_nudge() -> void:
	_flags_before("M02")
	gs.set_flag("visited_Z2", false)
	await _enter("Z4", "from_Z1")
	await _read_out("")
	var cue := _street_cue()
	_check(cue != null, "Z4 has the mark «На улицу» (Z2)")
	if cue == null:
		return
	_check(is_equal_approx(float(cue.get("nudge_after_s")), 10.0), "the nudge waits 10 s (data: %s)" % str(cue.get("nudge_after_s")))
	# the count runs with time: half a second on the clock — about half a second counted
	cue.set("_idle_s", 0.0)
	var dt: float = await _game_wait(cue, 0.5)
	var counted := float(cue.get("_idle_s"))
	_check(absf(counted - dt) < 0.1, "the idle count follows game time (%.2f s counted in %.2f s)" % [counted, dt])
	_check(not bool(cue.call("is_nudging")), "before 10 s — no flicker")
	var calm: Array = await _alpha_range(cue, 1.2)
	# 10 s with no click (the clock is jumped to 9.8 s: the count itself was checked above)
	cue.set("_idle_s", 9.8)
	await _game_wait(cue, 0.4)
	_check(bool(cue.call("is_nudging")), "after 10 s with no click — the mark flickers (idle %.1f s)" % float(cue.get("_idle_s")))
	var g := 0
	while float(cue.call("nudge_k")) < 0.99 and g < 600:
		await process_frame
		g += 1
	var fl: Array = await _alpha_range(cue, 1.3)
	# calm, the mark breathes 0.58…0.74 (alpha ±11 %); nudging it flickers up to full and back
	_check(fl[1] > 0.9 and fl[1] - fl[0] > 0.2, "the flicker shows: drawn alpha %.2f…%.2f" % [fl[0], fl[1]])
	_check(fl[1] > calm[1] + 0.1, "brighter than calm (calm max %.2f, flicker max %.2f)" % [calm[1], fl[1]])
	# a key (Q does nothing in the game) — the count starts again
	await _press_key(KEY_Q)
	_check(not bool(cue.call("is_nudging")) and float(cue.get("_idle_s")) < 1.0, "a key resets the count (idle %.2f s)" % float(cue.get("_idle_s")))
	# a dialogue pauses the count
	_check(await _use("post_sign"), "the post's sign is looked at (a line on screen)")
	var g0 := 0
	while not bool(sr.call("is_busy")) and g0 < 600:
		await process_frame
		g0 += 1
	await _frames(3)
	cue.set("_idle_s", 5.0)
	await _game_wait(cue, 0.5)
	_check(bool(sr.call("is_busy")) and float(cue.get("_idle_s")) < 5.05, "under a line on screen the count stands (%.2f s, busy %s)" % [float(cue.get("_idle_s")), str(sr.call("is_busy"))])
	await _read_out("")
	await _frames(5)
	# once the street was seen — no flicker
	gs.set_flag("visited_Z2", true)
	cue.set("_idle_s", 30.0)
	await _frames(10)
	_check(not bool(cue.call("is_nudging")), "the street already seen — no flicker")
	# self-check: the same mark without the nudge data stays calm after the same wait
	gs.set_flag("visited_Z2", false)
	cue.set("nudge_after_s", -1.0)
	cue.set("_idle_s", 30.0)
	g = 0
	while float(cue.call("nudge_k")) > 0.0 and g < 600:
		await process_frame
		g += 1
	var still: Array = await _alpha_range(cue, 1.3)
	_check(not bool(cue.call("is_nudging")) and still[1] < 0.8, "self-check: no data — the test sees no flicker (alpha %.2f…%.2f)" % [still[0], still[1]])


## The knot tied on the plate's close-up (`keep` false — the event without its close_black): [the close-up still open at
## M15's first line, the darkest black seen, seconds from the knot to the black starting].
func _tie_and_watch(keep: bool) -> Array:
	_flags_before("M15")
	for f in ["house_unlocked", "evening_dusk", "done_M15a", "skoba_on_plate", "plate_braced", "rope_brought", "done_M15s"]:
		gs.set_flag(f, true)
	gs.set_flag("rope_on_ring", false)
	await _enter("Z3")
	await _read_out("")
	var h = rm.current_room.get_node_or_null("Hotspots/pier_plate")
	if h == null:
		return [true, 0.0, 0.0]
	sr.open_mechanic(sr.mechanic_spec(h), "pier_plate")
	await _frames(3)
	if not keep:
		(sr.mechanic["events"]["tied"] as Dictionary).erase("close_black")
	var mv = main_node.get_node_or_null("MechanicView")
	var panel = mv.get("panel") if mv != null else null
	if panel == null:
		return [true, 0.0, 0.0]
	panel.call("event", "tied")
	var t := 0.0
	var darkest := 0.0
	var black_at := -1.0
	var open_at_line := true
	var g := 0
	while g < 900:
		await process_frame
		g += 1
		t += sr.get_process_delta_time()   # the panel itself is freed when the close-up goes away
		var dim := float(sr.get("stage_dim"))
		darkest = maxf(darkest, dim)
		if black_at < 0.0 and dim > 0.1:
			black_at = t
		var b: Dictionary = sr.current_beat
		# M15 opens with the narrator («Канат натянулся ровно…»): a narration beat, not a line
		if String(b.get("scene", "")) == "M15" and String(b.get("type", "")) in ["line", "narration"] and not bool(sr.call("is_staging")):
			open_at_line = bool(sr.mechanic_open)
			break
	await _read_out("")
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(3)
	return [open_at_line, darkest, black_at]


func _test_plate_closes() -> void:
	var r: Array = await _tie_and_watch(true)
	_check(not bool(r[0]), "M15's first line comes with the plate's close-up put away")
	_check(float(r[1]) > 0.9, "through a black (darkest %.2f)" % float(r[1]))
	_check(float(r[2]) >= 0.7, "the painted knot is seen a moment before the black (%.2f s)" % float(r[2]))
	var self_r: Array = await _tie_and_watch(false)
	_check(bool(self_r[0]), "self-check: without close_black the line comes over the close-up — the test tells the two apart")


func _mouse(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	if pressed:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)
	await _frames(1)


func _motion(pos: Vector2, held: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(ev)
	await _frames(1)


## The item pressed in its pocket, carried to `to` (screen) in steps, let go there. Then the lines said (read out).
func _drag(item: String, to: Vector2) -> Array:
	var ui = root.get_tree().get_first_node_in_group("game_ui")
	var slot = ui.get("bag").call("slot_of", item) if ui != null else null
	if slot == null:
		return ["<no slot>"]
	var from: Vector2 = (slot as Control).get_global_rect().get_center() + Vector2(-8, -8)   # off the magnifier corner
	await _mouse(from, MOUSE_BUTTON_LEFT, true)
	for k in range(1, 9):
		await _motion(from.lerp(to, float(k) / 8.0), true)
	await _mouse(to, MOUSE_BUTTON_LEFT, false)
	var seen: Array = []
	var g := 0
	while g < 900:
		g += 1
		await physics_frame
		if not sr.current_beat.is_empty():
			seen.append(String(sr.current_beat.get("text", "")))
			sr.advance()
		elif g > 120 and not player.call("is_walking") and not sr.call("is_staging"):
			break
	if sr.puzzle_open:
		sr.close_puzzle()
	return seen


func _test_drag_item() -> void:
	_flags_before("M05")
	gs.remove_item("door_drawing")
	gs.add_item("door_hinges")
	await _enter("H3")
	await _read_out("")
	sr.select_item("")
	var want: String = sd.text("@H3.puzzle.need_drawing")
	var door: Node2D = rm.current_room.get_node_or_null("Hotspots/school_door")
	_check(door != null, "the school door in the gallery")
	if door == null:
		return
	var door_screen: Vector2 = rm.current_room.get_viewport().get_canvas_transform() * door.global_position
	await _wait_idle()
	var on_door := await _drag("door_hinges", door_screen)
	_check(on_door.has(want), "dragged onto the door: used there — «%s» (got %s)" % [want.left(40), str(on_door)])
	if sr.selected_item != "":
		sr.select_item("")
	# empty floor: back in the bag, nothing said
	await _wait_idle()
	var floor_pt := Vector2(960, 1040)
	var picked = rm.current_room.call("pick", rm.current_room.get_viewport().get_canvas_transform().affine_inverse() * floor_pt)
	_check(picked == null, "the floor point (960, 1040) is no place or person (%s)" % str(picked))
	var on_floor := await _drag("door_hinges", floor_pt)
	_check(on_floor.is_empty() and sr.selected_item == "" and gs.has_item("door_hinges"), "dropped on empty floor — back in the bag, nothing said (held «%s», said %s)" % [sr.selected_item, str(on_floor)])
	# a press let go where it was — the click it always was: the item in hand
	var ui = root.get_tree().get_first_node_in_group("game_ui")
	var slot: Control = ui.get("bag").call("slot_of", "door_hinges")
	var c := slot.get_global_rect().get_center() + Vector2(-8, -8)
	await _mouse(c, MOUSE_BUTTON_LEFT, true)
	await _mouse(c, MOUSE_BUTTON_LEFT, false)
	_check(sr.selected_item == "door_hinges", "a press without carrying: the hinges in hand (held «%s»)" % sr.selected_item)
	sr.select_item("")
	# self-check: 5 px is no drag — a click, the item stays in hand, nothing used
	await _mouse(c, MOUSE_BUTTON_LEFT, true)
	await _motion(c + Vector2(5, 0), true)
	await _mouse(c + Vector2(5, 0), MOUSE_BUTTON_LEFT, false)
	await _frames(10)
	_check(sr.selected_item == "door_hinges" and not bool(player.call("is_walking")), "self-check: 5 px — a click, not a drag (held «%s»)" % sr.selected_item)
	sr.select_item("")


## The council's people in the yard now: id → their figure (visible) or null.
func _yard_people() -> Dictionary:
	var out := {}
	for id in ["pavel", "manager", "ilya"]:
		var n := rm.current_room.get_node_or_null("npc_" + id) as Node2D
		out[id] = n if n != null and n.is_visible_in_tree() and n.modulate.a > 0.5 else null
	return out


func _test_council_stays() -> void:
	_flags_before("M23b")
	await _enter("M1", "from_Z2")
	var before := _yard_people()
	_check(sr.active_scene == "M23b" or String(sr.current_beat.get("scene", "")) == "M23b", "M23b begins on entering the yard (scene %s)" % sr.active_scene)
	await _read_out("")
	await _wait_idle()
	await _frames(10)
	var frame: Dictionary = sd.room("F_mill_manager")
	var feet := {}
	for h in frame.get("hotspots", []):
		feet[String(h.get("id", ""))] = Vector2(float(h["feet"][0]), float(h["feet"][1]))
	var now := _yard_people()
	for id in ["pavel", "manager", "ilya"]:
		var n: Node2D = now[id]
		_check(n != null, "%s stands in the yard after the council" % id)
		if n == null:
			continue
		var off: Vector2 = n.get("sheet").feet_offset if n.get("sheet") != null else Vector2.ZERO
		var at: Vector2 = n.global_position - off
		_check(at.distance_to(feet[id]) <= 6.0, "%s where the frame had him: %s (frame %s)" % [id, str(at.round()), str(feet[id])])
		var picked = rm.current_room.call("pick", at + Vector2(0, -120))
		_check(picked == null or String(picked.name) != id, "%s is not clicked (picked %s)" % [id, str(picked.name) if picked != null else "nothing"])
	_check(player.global_position.distance_to(feet["agata"]) <= 6.0, "Agata where she stood in the frame: %s (frame %s)" % [str(player.global_position.round()), str(feet["agata"])])
	# she leaves the yard (to the street) and comes back — they have gone
	var ex: Node = null
	for e in rm.current_room.get_exits():
		if String(e.get("target_room")) == "Z2":
			ex = e
	_check(ex != null, "the yard's way to the street")
	if ex != null:
		sr.call("use_exit", ex)
		await _frames(20)
		await _enter("M1", "from_Z2")
		await _read_out("")
		var after := _yard_people()
		_check(after["pavel"] == null and after["manager"] == null and after["ilya"] == null, "back in the yard after leaving: nobody of the council (%s)" % str(after))
	_check(before["pavel"] == null and before["manager"] == null and before["ilya"] == null, "self-check: before the council none of them in the yard (%s)" % str(before))




func _test_pavel_door() -> void:
	_flags_before("M13")
	await _enter("M3")
	await _read_out("")
	var room = rm.current_room
	var pv := room.get_node_or_null("npc_pavel") as Node2D
	_check(pv != null, "Pavel in the office")
	if pv == null:
		return
	var ref: Dictionary = (sd.room("M3").get("height_refs", []) as Array)[0]
	var leaf := float(ref["px"])
	_check(leaf <= 510.0, "the door's height is the leaf's (%.0f px; with the lintel board it was 550)" % leaf)
	var to := Vector2.ZERO
	for st in sd.scene("M13").get("stage", []):
		for g in st.get("npc_go", []):
			if String(g.get("id", "")) == "pavel":
				to = Vector2(float(g["to"][0]), float(g["to"][1]))
	var sh = pv.get("sheet")
	var per := float(sh.scale_factor) * float(sh.figure_height_px)
	var h := float(room.depth_scale_at(to)) * per
	_check(to != Vector2.ZERO and h < leaf, "Pavel in the doorway (%s) %.0f px — lower than the leaf %.0f" % [str(to), h, leaf])
	var ag := float(room.depth_scale_at(Vector2(to.x, float(ref["y"])))) * float(player.get("sheet").figure_height_px) if player.get("sheet") != null else 0.0
	_check(ag >= 0.85 * leaf and ag <= 0.95 * leaf, "Agata at the threshold %.0f px — 0.85–0.95 of the leaf %.0f" % [ag, leaf])
	# self-check: the depth as it was (1.504 at y 690 … 2.826 at y 1070) — Pavel taller than the door
	var old_s := 1.504 + (to.y - 690.0) / 380.0 * (2.826 - 1.504)
	_check(maxf(old_s, 1.504) * per > leaf, "self-check: the old depth gives Pavel %.0f px — taller than the leaf, the test tells" % (maxf(old_s, 1.504) * per))


func _test_lever_reach() -> void:
	_flags_before("M13")
	await _enter("M3")
	await _read_out("")
	var lever: CanvasItem = rm.current_room.get_node_or_null("Layers/sluice_lever")
	_check(lever != null and lever.visible, "self-check: the lever on the wall before M13's end")
	sr.start_scene("M13")
	var at_reach := Vector2.INF
	var bag_then := true
	var g := 0
	while g < 6000:
		g += 1
		await physics_frame
		if at_reach == Vector2.INF and gs.has_flag("m13_lever_reached"):
			at_reach = player.global_position
			bag_then = gs.has_item("key_sluice")
		var b: Dictionary = sr.current_beat
		if not b.is_empty() and not bool(sr.call("is_staging")):
			if String(b.get("type", "")) == "options":
				sr.choose(String(b["options"][0]["id"]))
			else:
				sr.advance()
		elif b.is_empty() and not bool(sr.call("is_staging")) and gs.has_flag("done_M13") and not bool(player.call("is_acting")) and not bool(player.call("is_walking")):
			break
	_check(at_reach != Vector2.INF, "the lever is reached at M13's end (m13_lever_reached)")
	_check(at_reach.x <= 660.0 and at_reach.y <= 690.0, "she reaches from as near as the floor lets her: %s (≤ x 660, by the door to the passage)" % str(at_reach.round()))
	_check(not bag_then, "the lever leaves the wall with her reach, before the bag gets it")
	_check(lever != null and is_instance_valid(lever) and not lever.visible and gs.has_item("key_sluice"), "after the scene: the wall empty, the lever in the bag")


## The three flashes on the lantern's close-up (`keep` false — the event without its `close`): whether the close-up is
## still open at M16's first words.
func _flash_and_watch(keep: bool) -> bool:
	_flags_before("M16")
	await _enter("R1")
	await _read_out("")
	var h = rm.current_room.get_node_or_null("Hotspots/lantern")
	if h == null:
		_check(false, "the lantern on the pier")
		return true
	sr.open_mechanic(sr.mechanic_spec(h), "lantern")
	await _frames(3)
	if not keep:
		(sr.mechanic["events"]["answered"] as Dictionary).erase("close")
	var mv = main_node.get_node_or_null("MechanicView")
	var panel = mv.get("panel") if mv != null else null
	if panel == null:
		_check(false, "the lantern's close-up is open")
		return true
	for i in 3:
		panel.call("flash")
		var t := 0.0
		while t < 0.8:
			await process_frame
			t += sr.get_process_delta_time()
	var open_at := true
	var g := 0
	while g < 900:
		await process_frame
		g += 1
		var b: Dictionary = sr.current_beat
		if String(b.get("scene", "")) == "M16" and String(b.get("type", "")) in ["line", "narration"] and not bool(sr.call("is_staging")):
			open_at = bool(sr.mechanic_open)
			break
	_check(g < 900, "M16 begins after the answer (%d frames)" % g)
	await _read_out("")
	if sr.mechanic_open:
		sr.close_mechanic()
	await _frames(3)
	return open_at


func _test_lights_close() -> void:
	_check(not await _flash_and_watch(true), "Pelageya's «Ответили!» comes with the lantern's close-up put away (no «Закрыть»)")
	_check(await _flash_and_watch(false), "self-check: without close on the event she speaks over the close-up — the test tells the two apart")

