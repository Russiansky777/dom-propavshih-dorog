extends SceneTree
## Director 15.11, 12:51 («у Нины на видео нет движений мимики»): in the trailer the voices were laid in at the
## assembly and in the render the figures stood silent. A `speak` event of a shot (game/scripts/trailer/trailer.gd)
## moves the speaker's lips by the letters of the recording, the game's own way:
##   TS-1 every `speak` of the plans has its recording, its speaker's figure is in the shot's room;
##   TS-2 while the line is said the mouth opens and shuts (Agata and Nina: JawModifier; Tikhon: the puppet's mouth),
##        after its recording the mouth is shut;
##   TS-3 self-check — the same moment with the line only shown (`line`, the way of the trailer until 15.11): the
##        mouth stays shut.
## The 3D figures have their lips only with a display:
##   godot --path game --display-driver x11 --rendering-driver opengl3 --fixed-fps 15 -s res://tests/test_trailer_speak.gd -- --fps=15
## (--fps=15: the film's clock at 15 frames a second — the same lips by the same letters, a quarter of the frames of
## the 60 fps plan; a shot is run only until its last line is over and 0.6 s more.)

const PLAN := "res://data/trailer/trailer_v3.json"

var _results: Array = []
var _fails: Array[String] = []
var rm: Node = null


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
	rm = root.get_node("RoomManager")
	if DisplayServer.get_name() == "headless":
		print("SKIP  trailer speak: no display (the 3D figures have no lips without one) — run under xvfb")
		quit(0)
		return
	await _test("TS-1 TS-2 a line said in a shot moves its speaker's lips, and they shut after it", _test_lips)
	await _test("TS-3 self-check: the line only shown (as until 15.11) — the mouth stays shut", _test_self_check)
	var failed := _results.count(false)
	print("==== trailer speak: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _plan() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PLAN))


## Runs a shot of the plan (its events replaced if asked) and samples, every frame, how open the speaker's mouth is
## (jaw `open`, or the puppet's mouth frame) inside and after each `speak`/`line` window: {id: {during: [..], after: [..]}}.
func _sample(shot_id: String, events_override = null) -> Dictionary:
	var plan := _plan()
	var tr: Node = load("res://scenes/trailer/Trailer.tscn").instantiate()
	tr.set("quit_at_end", false)
	if not bool(tr.call("load_plan", PLAN, shot_id)):
		_check(false, "%s: load_plan failed %s" % [shot_id, tr.get("errors")])
		tr.free()
		return {}
	var shot: Dictionary = tr.get("shot")
	if events_override != null:
		shot["ui"]["events"] = events_override
	root.add_child(tr)
	var fps: int = tr.get("fps")
	var pre: float = tr.get("preroll_s")
	var total: int = tr.get("total_frames")
	var windows: Array = []
	for e in shot.get("ui", {}).get("events", []):
		if String(e.get("do", "")) in ["speak", "line"]:
			var lid := String(tr.call("speak_line_id", e))
			windows.append({"lid": lid, "at": float(e["at_s"]), "len": float(tr.call("voice_length", lid)), "speaker": String(tr.call("speak_entry", e).get("speaker", ""))})
	var out := {}
	var stop_t := -pre
	for w in windows:
		out[w["lid"]] = {"during": [], "after": [], "speaker": w["speaker"], "len": w["len"]}
		stop_t = maxf(stop_t, float(w["at"]) + float(w["len"]) + 0.6)
	for f in total:
		if float(f) / fps - pre > stop_t:
			break
		await process_frame
		var t := float(f) / fps - pre
		for w in windows:
			var o := _openness(String(w["speaker"]))
			if t > float(w["at"]) + 0.1 and t < float(w["at"]) + float(w["len"]) - 0.1:
				(out[w["lid"]]["during"] as Array).append(o)
			elif t > float(w["at"]) + float(w["len"]) + 0.25:
				(out[w["lid"]]["after"] as Array).append(o)
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
	await process_frame
	return out


## 0…1 — how open the mouth is now; -1 — no figure.
func _openness(speaker: String) -> float:
	var room: Node = rm.current_room
	if speaker == "agata" and rm.player != null:
		var jm = rm.player.get("jaw")
		return float(jm.get("open")) if jm != null else -1.0
	if room == null:
		return -1.0
	if room.get_node_or_null("npc_" + speaker) != null:
		var live = room.get_node("npc_" + speaker).get("live")
		var jm = live.get("jaw") if live != null else null
		return float(jm.get("open")) if jm != null else -1.0
	if room.get_node_or_null("puppet_" + speaker) != null:
		return 1.0 if int(room.get_node("puppet_" + speaker).get("mouth_frame")) > 0 else 0.0
	return -1.0


func _test_lips() -> void:
	var seen := 0
	for s in _plan().get("shots", []):
		var speaks: Array = (s.get("ui", {}).get("events", []) as Array).filter(func(e): return String(e.get("do", "")) == "speak")
		if speaks.is_empty():
			continue
		var res: Dictionary = await _sample(String(s["id"]))
		for lid in res.keys():
			var r: Dictionary = res[lid]
			seen += 1
			var during: Array = r["during"]
			var after: Array = r["after"]
			_check(float(r["len"]) > 0.5, "%s: no recording of %s" % [s["id"], lid])
			_check(not during.is_empty() and float(during.min()) >= 0.0, "%s: %s — no figure of %s with a mouth" % [s["id"], lid, r["speaker"]])
			if during.is_empty():
				continue
			var opened := during.filter(func(o): return float(o) > 0.25).size()
			var shut := during.filter(func(o): return float(o) < 0.05).size()
			# a 3D mouth follows the letters and shuts on «м, б, п» and in pauses; the puppet's (Tikhon) cycles its
			# drawn mouths while the voice lasts, as in the game — for it «opens» is enough
			print("  [%s] %s (%s): open on %d of %d frames, shut on %d; after the line max %.2f" % [s["id"], lid, r["speaker"], opened, during.size(), shut,
				float(after.max()) if not after.is_empty() else 0.0])
			_check(opened >= during.size() / 5, "%s: %s — the mouth hardly opens (%d of %d frames)" % [s["id"], lid, opened, during.size()])
			_check(String(r["speaker"]) == "tikhon" or shut >= 1, "%s: %s — the mouth never shuts while the line is said (letters, pauses)" % [s["id"], lid])
			_check(after.is_empty() or float(after.max()) < 0.05, "%s: %s — the mouth still moves after the line (%.2f)" % [s["id"], lid, float(after.max()) if not after.is_empty() else 0.0])
	_check(seen >= 5, "speak events in the plan: %d (Agata and Tikhon in the cottage, Pavel at the mill, Agata and Nina in the class)" % seen)


func _test_self_check() -> void:
	# the class: Nina's line as a `line` event only — shown, not said
	var res: Dictionary = await _sample("olk_school", [{"at_s": 0.3, "do": "line", "scene": "M21b", "line": 4}])
	var r: Dictionary = res.get("M21b_4", {})
	var during: Array = r.get("during", [])
	_check(not during.is_empty() and float(during.max()) < 0.05, "self-check: shown only, Nina's mouth stays shut (max %.2f over %d frames)" % [float(during.max()) if not during.is_empty() else -1.0, during.size()])
