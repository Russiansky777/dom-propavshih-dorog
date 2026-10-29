extends SceneTree
## Batch I, task I-T2 — visual, staging, mechanics (Director's playthrough 25.10, Docs/FEEDBACK_DIRECTOR_2026-10-25_map.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_batch_i_t2.gd
##   1. Agata (lines 1, 27): a 180° turn takes a human 0.25–0.4 s through the rows in between — never a snap; the calm
##      idle (amplitude < 1, the loop starts and ends on one pose); the cross-fade copy keeps the room's tone;
##   2. villagers (Director 02:34 and 14:07): three states as data — idle / listen (turned to Agata) / talk; the same
##      human turn speed; a staging partner (M18: Pelageya and Mitya face each other, a line "to": "agata" turns back);
##   3. mechanics: the gallery side door «Отпереть дверь» until the first pass (34–35), Tikhon always (38), the hinges
##      from the bag (52), the Q06 workshop glows until the task starts, the mother's mirror empty while Nina is at
##      Dunya's (146), Pelageya at the turn is walked round (147), the windlass calls have voice lines (163–164);
##   4. visual and staging data: chalk writing on the board (138), the signal board on R1 (19), D2 arrows (20).
## Exit code 0 only when every check passed.

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
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	await _test("I-T2 Agata: 180° turn in 0.25–0.4 s through the rows between, calm idle without a seam, fade keeps the tone", _test_agata)
	await _test("I-T2 villagers: idle / listen / talk as data, human turn speed, the M18 partner", _test_npc_states)
	await _test("I-T2 mechanics: side door label, Tikhon always, hinges from the bag, Q06 glow, empty mirror, Pelageya walked round, windlass voice", _test_mechanics)
	await _test("I-T2 staging data: chalk on the board, the signal board on R1, D2 arrows, the bigger «Дождалась»", _test_data)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== batch I (I-T2): %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers -----------------------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _enter(room: String, spawn: String = "default") -> void:
	rm.change_room(room, spawn)
	await physics_frame
	await physics_frame
	await _frames(2)


func _drain() -> void:
	var guard := 0
	while (not sr.current_beat.is_empty() or sr.is_busy()) and guard < 200:
		guard += 1
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif not b.is_empty():
			sr.advance()
		await process_frame


func _hotspot(id: String) -> Node:
	for h in rm.current_room.get_hotspots():
		if h.hotspot_id == id:
			return h
	return null


func _exit_to(to: String) -> Node:
	for e in rm.current_room.get_exits():
		if String(e.get("target_room")) == to:
			return e
	return null


func _npc(id: String) -> Node2D:
	return rm.current_room.get_node_or_null("npc_" + id)


func _set_flags(flags: Array) -> void:
	for f in flags:
		gs.set_flag(String(f), true)


# --- 1. Agata ----------------------------------------------------------------------------

func _test_agata() -> void:
	gs.reset()
	await _enter("H1", "default")
	var player: Node2D = rm.player
	var dirs: int = int(player.sheet.directions)
	var t180: float = float(player.get("turn_step_s")) * float(dirs) * 0.5
	_check(t180 >= 0.25 and t180 <= 0.4, "180° in %.2f s (0.25–0.4, like a person)" % t180)
	_check(float(player.get("turn_blend_s")) > 0.0, "each row change of a turn is a short cross-fade")
	# A real half turn: the row on screen goes through the rows between and takes its time.
	var start: int = int(player.get("shown_dir"))
	var target: int = (start + dirs / 2) % dirs
	player.set("direction", target)
	var rows_seen := {start: true}
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while int(player.get("shown_dir")) != target and guard < 240:
		await process_frame
		rows_seen[int(player.get("shown_dir"))] = true
		guard += 1
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	_check(int(player.get("shown_dir")) == target, "the half turn finishes")
	_check(rows_seen.size() >= dirs / 2, "the turn shows the rows in between (%d rows seen)" % rows_seen.size())
	_check(took >= 0.2, "the half turn is not instant (%.2f s)" % took)
	# Calm idle: amplitude below 1, a longer period, the loop starts and ends on the same pose.
	var idle: Dictionary = player.sheet.actions.get("idle", {})
	_check(float(idle.get("amplitude", 1.0)) < 1.0 and float(idle.get("period_s", 0.0)) >= 4.0,
		"idle: calm breathing — amplitude %.2f, period %.1f s" % [float(idle.get("amplitude", 1.0)), float(idle.get("period_s", 0.0))])
	for r in dirs:
		var tl: Array = player.sheet.eased_timeline("idle", r)
		_check(not tl.is_empty() and int(tl[0][0]) == int(tl[tl.size() - 1][0]), "idle row %d: the loop starts and ends on one pose" % r)
	# Line 27: the frozen copy of a cross-fade takes the sprite's tone (no white flash in the dark house).
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	spr.self_modulate = Color(0.3, 0.3, 0.4)
	var fade = ActorCrossfade.begin(spr, 0.1)
	_check(fade != null and fade.self_modulate == spr.self_modulate, "the cross-fade copy keeps the room's tone")
	spr.self_modulate = Color.WHITE


# --- 2. Villagers ------------------------------------------------------------------------

func _test_npc_states() -> void:
	gs.reset()
	await _enter("Z1", "default")
	var t: Node2D = _npc("tamara")
	_check(t != null, "Tamara stands in Z1")
	if t == null:
		return
	for st in ["idle", "listen", "talk"]:
		_check((t.get("states") as Dictionary).has(st), "state «%s» from data" % st)
	var t180: float = float(t.get("turn_step_s")) * float(t.sheet.directions) * 0.5
	_check(t180 >= 0.25 and t180 <= 0.4, "villagers turn 180° in %.2f s (0.25–0.4)" % t180)
	# listen: turned to Agata, quiet (the idle clip until a model brings its own listen clip — I-T4)
	t.call("set_state", "listen")
	var want: int = t.sheet.direction_index(rm.player.global_position - t.global_position)
	_check(int(t.get("direction")) == want, "listen turns her to Agata (dir %d, want %d)" % [int(t.get("direction")), want])
	_check(String(t.call("state_action", "listen")) != "", "listen plays a clip (own or idle)")
	t.call("set_state", "talk")
	_check(bool(t.get("talking")), "talk while her line is up")
	t.call("set_state", "idle")
	_check(not bool(t.get("talking")), "back to idle")
	# The wanted state follows the beat: her own line — talk; a scene with her, someone else's line — listen.
	sr.start_scene("M01")
	await process_frame
	var seen := {}
	var guard := 0
	while not sr.current_beat.is_empty() and guard < 60:
		guard += 1
		seen[String(t.get("state"))] = true
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		else:
			sr.advance()
		await process_frame
	_check(seen.has("talk") and seen.has("listen"), "M01: Tamara talks on her lines and listens on Agata's (%s)" % str(seen.keys()))
	await _frames(3)
	_check(String(t.get("state")) == "idle", "after the scene she just stands")
	# M18: a staging partner — idle and listen face the partner; a line to Agata turns them to her.
	gs.reset()
	await _enter("R3", "default")
	var pel: Node2D = _npc("pelageya")
	var mit: Node2D = _npc("mitya")
	if pel != null and mit != null:
		pel.call("set_partner", mit)
		pel.call("set_state", "listen")
		_check(int(pel.get("direction")) == pel.sheet.direction_index(mit.global_position - pel.global_position),
			"M18: Pelageya listens facing Mitya, not Agata")
	var m18: Dictionary = sd.scene("M18")
	var faces := 0
	for st in m18.get("stage", []):
		for g in st.get("npc_go", []):
			if g.has("face"):
				faces += 1
	# J-D2 (29.10): they also step apart after the hug, still facing each other (two more npc_go with face)
	_check(faces >= 2, "M18: both walk up to each other and face each other (npc_go.face ×2 and more, got %d)" % faces)
	var to_agata := false
	for l in m18.get("mandatory_lines", []):
		if String(l.get("to", "")) == "agata":
			to_agata = true
	_check(to_agata, "M18: Mitya's words to Agata turn him to her (\"to\": \"agata\")")


# --- 3. Mechanics ------------------------------------------------------------------------

func _test_mechanics() -> void:
	# 34–35: the gallery side door.
	gs.reset()
	_set_flags(["done_M04"])
	await _enter("H3", "default")
	var side: Node = _exit_to("Z4")
	_check(side != null, "H3 has the side door to Z4")
	if side != null:
		_check(String(side.call("label_text")) == "Отпереть дверь", "before the first pass: «Отпереть дверь» (got «%s»)" % String(side.call("label_text")))
		gs.set_flag("side_door_passed", true)
		_check(String(side.call("label_text")) != "Отпереть дверь", "after it: the usual label")
	var z4_on_enter: Array = sd.room("Z4").get("on_enter", [])
	_check(z4_on_enter.size() > 0 and (z4_on_enter[0].get("if", []) as Array).has("side_door_passed"),
		"Z4: Agata's word in the lane after the first pass")
	# 52: the hinges — a click on the door only says what to do; the close-up opens from the item.
	gs.reset()
	_set_flags(["done_M04"])
	gs.add_item("door_hinges")
	await _enter("H3", "default")
	var door: Node = null
	for h in rm.current_room.get_hotspots():
		if (h.data as Dictionary).get("puzzle", {}).get("id", "") == "school_door_fit":
			door = h
	await _drain()
	var plan := String(sr.planned_interaction(door)) if door != null else "no door"
	_check(plan == "text", "a plain click on the door is a hint, not the close-up (got %s)" % plan)
	# 38: Tikhon can always be talked to.
	gs.reset()
	await _enter("H1", "default")
	var tik: Node = _hotspot("tikhon")
	_check(tik != null and tik.is_active(), "Tikhon is there from the first entry")
	# Q06: the workshop glows after the hook, until the task starts.
	gs.reset()
	_set_flags(["done_M22", "met_ilya"])
	await _enter("O4", "default")
	var ws: Node = _hotspot("ilya_workshop")
	_check(ws != null and bool(ws.call("beckon_on")), "Q06: the shed glows")
	await _frames(2)
	_check(ws != null and ws.get_node_or_null("Beckon") != null, "Q06: the glow is drawn")
	gs.set_flag("q06_started", true)
	if ws != null:
		ws.call("refresh")
	await _frames(2)
	_check(ws != null and not bool(ws.call("beckon_on")), "Q06: no glow once the task is started")
	# 146: the mother's mirror without her while she is at Dunya's.
	var mech: Dictionary = {}
	for h in sd.room("H2").get("hotspots", []):
		if (h as Dictionary).get("mechanic", {}).get("type", "") == "fast_mirror":
			mech = h["mechanic"]
	_check((mech.get("nina_away_if", []) as Array).has("nina_visited_house"), "the mother's mirror: Nina away after she visited the house")
	var panel = load("res://scripts/mechanics/fast_mirror_panel.gd").new()
	panel.set("spec", mech)
	gs.reset()
	_check(not bool(panel.call("nina_away")), "before: Nina in her room")
	gs.set_flag("nina_visited_house", true)
	_check(bool(panel.call("nina_away")), "after: the room in the glass is empty")
	panel.free()
	# 147: Pelageya at the turn is an obstacle at her feet.
	gs.reset()
	_set_flags(["evening_dusk"])
	await _enter("Z3", "default")
	var pel_h: Dictionary = {}
	for h in sd.room("Z3").get("hotspots", []):
		if String(h.get("id", "")) == "pelageya":
			pel_h = h
	var r: Array = pel_h.get("rect", [0, 0, 0, 0])
	var feet := Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]))
	var nav: NavigationRegion2D = rm.current_room.get_node_or_null("Walkable")
	var inside := false
	if nav != null:
		var np: NavigationPolygon = nav.navigation_polygon
		for i in np.get_polygon_count():
			var poly := PackedVector2Array()
			for vi in np.get_polygon(i):
				poly.append(np.vertices[vi])
			if Geometry2D.is_point_in_polygon(feet, poly):
				inside = true
	_check(nav != null and not inside, "Z3: the floor under Pelageya's feet is not walkable (Agata goes round)")
	# 163–164: the windlass calls and Ilya's answers have voice lines.
	var wl: Dictionary = {}
	for st in sd.scene("M25").get("mechanics", []):
		if String(st.get("spec", {}).get("type", "")) == "windlass":
			wl = st["spec"]
	for k in ["call_lower", "call_stop", "call_raise", "reply_lower", "reply_stop", "reply_raise"]:
		var key := String(wl.get("texts", {}).get("voice_" + k, ""))
		_check(key != "" and not sd.text_line(key).is_empty(), "windlass %s has a voice line (%s)" % [k, key])


# --- 4. Data -----------------------------------------------------------------------------

func _test_data() -> void:
	var m22: Dictionary = sd.scene("M22")
	var writes := 0
	for st in m22.get("stage", []):
		writes += (st.get("layer_write", []) as Array).size()
	_check(writes >= 4, "M22: Nina's answers and the date are written in (layer_write ×%d)" % writes)
	var mama: Dictionary = {}
	for l in sd.room("O1").get("layers", []):
		if String(l.get("id", "")) == "nina_answer_mama":
			mama = l
	_check(float(mama.get("scale", 1.0)) > 1.2, "«Дождалась» bigger (×%.1f)" % float(mama.get("scale", 1.0)))
	var board := false
	for l in sd.room("R1").get("layers", []):
		if String(l.get("id", "")) == "signal_board_text":
			board = true
	_check(board, "R1: the signal board has its lines on the background")
	for e in sd.room("R1").get("exits", []):
		if String(e.get("to", "")) == "Z3":
			_check(String(e.get("cue", "")) == "left", "D2: from the pier to the turn — the arrow points left")
	for e in sd.room("Z3").get("exits", []):
		if String(e.get("to", "")) == "R1":
			var rr: Array = e.get("rect", [0, 0, 0, 0])
			_check(float(rr[0]) > 960.0, "D2: back to the pier — on the right")
	# Chalk writing at run time: a layer just shown is revealed left to right.
	gs.reset()
	_set_flags(["board_mama"])
	await _enter("O1", "default")
	gs.set_flag("nina_answered_board", true)
	await _frames(2)
	sr.call("_stage_layer_write", [{"id": "nina_answer_mama", "x": [905, 1026], "s": 0.5}])
	var spr: Sprite2D = rm.current_room.get_node_or_null("Layers/nina_answer_mama/Image")
	_check(spr != null and spr.region_enabled and spr.region_rect.size.x < 1026.0, "the word starts hidden and is written in")
	var t0 := Time.get_ticks_msec()
	while spr != null and spr.region_enabled and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	_check(spr != null and not spr.region_enabled, "after the writing the layer is whole")
