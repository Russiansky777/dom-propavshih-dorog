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
			_check(String(s.get("kind", "")) in ["art", "room", "title_card", "phrase", "daycard"], "%s/%s: unknown kind" % [p, s.get("id")])
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
			if s.get("kind") == "title_card":
				_check(tr.get_node_or_null("TitleCard") != null, "%s: no title card" % s["id"])
			if s.get("kind") == "art":
				_check(tr.get_node_or_null("Stage") != null and tr.get_node("Stage").get_child_count() >= 2, "%s: no layers" % s["id"])
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
