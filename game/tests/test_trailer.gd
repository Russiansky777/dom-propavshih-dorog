extends SceneTree
## Headless test of the trailer shooting mode (TR1): the mode must not break the game.
##   godot --headless --path game -s res://tests/test_trailer.gd
##   1. every plan in res://data/trailer reads: shots with known kinds, durations, the frame count of each shot;
##      every resource a shot names exists (art, layers, depth, mask, music, ambience files);
##   2. each shot builds and runs a few frames without errors; the room shot starts its room in the given story
##      state, Agata walks, the camera stays inside the picture, autosave is off and no save slot is written;
##   3. the ease curves start and end at rest (no linear jerk at a cut).
## Exit code 0 only when every check passed.

const PLAN_DIR := "res://data/trailer"

var _results: Array = []
var _fails: Array[String] = []
var sd: Node = null
var rm: Node = null
var gs: Node = null
var _speak_seen: Array = []   # what the speak events of the plans did (printed once)


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	await fn.call()
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s" % ["PASS" if passed else "FAIL", test_name])
	for f in _fails:
		print("        - " + f)


func _plans() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(PLAN_DIR):
		if f.ends_with(".json"):
			out.append(PLAN_DIR + "/" + f)
	return out


func _run() -> void:
	await process_frame
	sd = root.get_node("StoryData")
	rm = root.get_node("RoomManager")
	gs = root.get_node("GameState")
	await _test("plans read, resources exist", _t_plans)
	await _test("every shot builds and runs", _t_shots)
	for rec in _speak_seen:
		print("  [speak] %s (%s): figure %s, jaw %s, puppet %s, speaking %s at %.2f of %.2f s" % [rec.get("line_id"), rec.get("speaker"),
			rec.get("found"), rec.get("has_jaw"), rec.get("has_puppet"), rec.get("speaking"), float(rec.get("t", 0)), float(rec.get("length", 0))])
	await _test("ease curves start and end at rest", _t_ease)
	var failed := _results.filter(func(r): return not r[1]).size()
	print("[trailer] %d/%d passed" % [_results.size() - failed, _results.size()])
	quit(1 if failed > 0 else 0)


func _t_plans() -> void:
	var plans := _plans()
	_check(not plans.is_empty(), "no plans in " + PLAN_DIR)
	for p in plans:
		var plan = JSON.parse_string(FileAccess.get_file_as_string(p))
		_check(plan is Dictionary, "%s: not JSON" % p)
		if not plan is Dictionary:
			continue
		var paths: Array = []
		var music = plan.get("audio", {}).get("music", "")
		if music is Array:
			for t in music:
				paths.append(t.get("file", ""))
		else:
			paths.append(music)
		for v in plan.get("audio", {}).get("voice", []):
			paths.append(v.get("file", ""))
		for a in plan.get("audio", {}).get("ambience", []):
			if a.has("file"):
				paths.append(a["file"])
		for s in plan.get("shots", []):
			_check(String(s.get("kind", "")) in ["art", "room", "title_card", "phrase", "daycard", "clip"], "%s/%s: unknown kind" % [p, s.get("id")])
			if s.get("kind") == "clip":
				# 14.11: a shot from a ready video (the crossing by fal) — the file is in the repository, outside the game;
				# its length against the shot is checked by tools/trailer_clip.py --check (run_tests.sh)
				var clip_path := ProjectSettings.globalize_path("res://").path_join("..").path_join(String(s.get("clip", {}).get("file", ""))).simplify_path()
				_check(String(s.get("clip", {}).get("file", "")) != "" and FileAccess.file_exists(clip_path), "%s/%s: no clip file %s" % [p, s.get("id"), clip_path])
				_check(not s.has("preroll_s"), "%s/%s: a clip shot has no preroll" % [p, s.get("id")])
			_check(float(s.get("duration", 0)) > 0.0, "%s/%s: no duration" % [p, s.get("id")])
			for k in ["art", "fx_mask", "depth_tex"]:
				if s.has(k):
					paths.append(s[k])
			for l in s.get("layers", []):
				if l.has("image"):
					paths.append(l["image"])
			if s.get("kind") == "room":
				_check(sd.has_room(String(s.get("room", ""))), "%s/%s: no room %s" % [p, s.get("id"), s.get("room")])
		for r in paths:
			_check(ResourceLoader.exists(String(r)), "%s: missing %s" % [p, r])


func _t_shots() -> void:
	var saves_before := _saves()
	for p in _plans():
		var plan = JSON.parse_string(FileAccess.get_file_as_string(p))
		for s in plan.get("shots", []):
			var tr: Node = load("res://scenes/trailer/Trailer.tscn").instantiate()
			tr.set("quit_at_end", false)
			var ok: bool = tr.call("load_plan", p, String(s["id"]))
			_check(ok, "%s/%s: load_plan failed %s" % [p, s["id"], tr.get("errors")])
			if not ok:
				tr.free()
				continue
			root.add_child(tr)
			var frames: int = tr.get("total_frames")
			_check(frames == int(round((float(s.get("preroll_s", 0.0)) + float(s["duration"]) + _tail(plan, s)) * int(plan.get("fps", 60)))),
				"%s/%s: frame count %d" % [p, s["id"], frames])
			var agata_to: bool = s.get("agata", {}).has("to")
			var wait := 30
			if agata_to:
				wait = maxi(30, int((float(s.get("preroll_s", 0.0)) + float(s["agata"].get("start_s", 0.0)) + 0.4) * int(plan.get("fps", 60))))
			for i in wait:
				await process_frame
			if s.get("kind") == "room":
				_check(rm.current_room != null and rm.current_room.room_id == String(s["room"]), "%s: room not started" % s["id"])
				_check(not rm.autosave_enabled, "%s: autosave left on" % s["id"])
				var pl: Node2D = rm.player
				if agata_to:
					_check(pl != null and bool(pl.call("is_walking")), "%s: Agata does not walk" % s["id"])
				var cam: Camera2D = tr.get_node_or_null("World/Camera")
				_check(cam != null and cam.is_current(), "%s: no camera" % s["id"])
				if cam != null:
					var half := Vector2(1920, 1080) / (2.0 * cam.zoom.x)
					_check(cam.position.x >= half.x - 0.5 and cam.position.x <= 1920 - half.x + 0.5 and cam.position.y >= half.y - 0.5 and cam.position.y <= 1080 - half.y + 0.5,
						"%s: camera shows past the room %s" % [s["id"], cam.position])
				for st in s.get("state", {}).get("flags", []):
					_check(gs.has_flag(String(st)), "%s: flag %s not set" % [s["id"], st])
			if s.get("kind") == "title_card" or (s.get("kind") == "art" and s.has("title")):
				_check(tr.get_node_or_null("TitleCard") != null, "%s: no title card" % s["id"])
			if s.get("kind") == "art" and s.has("title"):
				# 14.11: the name over the picture — above the picture's grade, the black a veil (clear at the start)
				var tc: CanvasLayer = tr.get_node_or_null("TitleCard")
				_check(tc != null and tc.layer > 100, "%s: the title over a picture stands above the grade (layer %s)" % [s["id"], tc.layer if tc != null else "-"])
				var veil: ColorRect = tc.get_child(0) as ColorRect if tc != null else null
				_check(veil != null and veil.color.a < 0.99, "%s: the picture under the title is not black" % s["id"])
			if s.get("kind") == "room":
				# 14.11: people turned to each other in a shot (`npc_face`, `agata.face`)
				for g in s.get("npc_face", []):
					var np: Node = rm.current_room.get_node_or_null("npc_" + String(g.get("id", ""))) if rm.current_room != null else null
					var want: Vector2 = Vector2(float(g["face"][0]), float(g["face"][1])) if g.get("face") is Array else (rm.player as Node2D).global_position
					# 15.11: she may be walking (the mill) — turned to her within a frame's step or two, not to where she began
					# (her start is 50 px behind by now: the run 43736902120 caught that)
					var tol := 12.0 if agata_to and not (g.get("face") is Array) else 2.0
					_check(np != null and (np.get("last_face_target") as Vector2).distance_to(want) < tol,
						"%s: %s is not turned to %s (turned to %s)" % [s["id"], g.get("id"), str(want), str(np.get("last_face_target") if np != null else "-")])
				if s.get("agata", {}).has("face") and not agata_to:
					var fp := Vector2(float(s["agata"]["face"][0]), float(s["agata"]["face"][1]))
					var pl2: Node2D = rm.player
					var dir := int(pl2.get("direction"))
					# her sheet's rows: 2 — to the right, 6 — to the left (probe_trailer_shot.gd prints them)
					_check((fp.x < pl2.global_position.x and dir in [5, 6, 7]) or (fp.x > pl2.global_position.x and dir in [1, 2, 3]),
						"%s: Agata does not look towards %s (direction %d)" % [s["id"], str(fp), dir])
			if s.get("kind") == "art":
				_check(tr.get_node_or_null("Stage") != null and tr.get_node("Stage").get_child_count() >= 2, "%s: no layers" % s["id"])
			# 15.11 (Director: «у Нины на видео нет движений мимики»): a line said in a shot moves its speaker's lips
			var speaks: Array = (s.get("ui", {}).get("events", []) as Array).filter(func(e): return String(e.get("do", "")) == "speak")
			for k in speaks.size():
				var e: Dictionary = speaks[k]
				var lid := String(tr.call("speak_line_id", e))
				_check(float(tr.call("voice_length", lid)) > 0.5, "%s: no recording of %s" % [s["id"], lid])
				var at_frame := int((float(s.get("preroll_s", 0.0)) + float(e.get("at_s", 0.0)) + 0.4) * int(plan.get("fps", 60)))
				while int(tr.get("frame")) < at_frame and int(tr.get("frame")) < frames - 1:
					await process_frame
				var pr: Array = tr.call("speaks_probe")
				var rec: Dictionary = pr[k] if k < pr.size() else {}
				_check(rec.get("line_id", "") == lid and bool(rec.get("found", false)), "%s: %s — the speaker's figure not found (%s)" % [s["id"], lid, str(rec)])
				_check((not bool(rec.get("has_jaw", false)) and not bool(rec.get("has_puppet", false))) or bool(rec.get("speaking", false)),
					"%s: %s — the lips do not move while the line is said (%s)" % [s["id"], lid, str(rec)])
				_speak_seen.append(rec)
			tr.queue_free()
			await process_frame
			if rm.current_room != null:
				rm.current_room.queue_free()
				rm.current_room = null
			for b in ["Music", "Voice"]:
				var bi := AudioServer.get_bus_index(b)
				if bi >= 0:
					AudioServer.set_bus_mute(bi, false)
			rm.autosave_enabled = true
	_check(_saves() == saves_before, "the trailer wrote a save: %s → %s" % [saves_before, _saves()])


func _tail(plan: Dictionary, s: Dictionary) -> float:
	var shots: Array = plan["shots"]
	var i := shots.find(s)
	return float(shots[i + 1].get("transition_in", {}).get("duration", 0.0)) if i + 1 < shots.size() else 0.0


func _saves() -> Dictionary:
	var out := {}
	var dir := "user://saves"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			out[f] = FileAccess.get_modified_time(dir + "/" + f)
	return out


func _t_ease() -> void:
	var tr_script: GDScript = load("res://scripts/trailer/trailer.gd")
	for k in ["sine_in_out", "smoother", "in_out_cubic"]:
		var a: float = tr_script.call("ease_curve", k, 0.0)
		var b: float = tr_script.call("ease_curve", k, 1.0)
		var s0: float = (tr_script.call("ease_curve", k, 0.01) as float) - a
		var s1: float = b - (tr_script.call("ease_curve", k, 0.99) as float)
		_check(is_equal_approx(a, 0.0) and is_equal_approx(b, 1.0), "%s: ends %f %f" % [k, a, b])
		_check(s0 < 0.002 and s1 < 0.002, "%s: starts or stops with speed (%f, %f)" % [k, s0, s1])
