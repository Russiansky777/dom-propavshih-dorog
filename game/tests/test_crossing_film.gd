extends SceneTree
## Director 14.11 (21:08 «а сделать в игре так, как на видео, мы можем?»; 21:15 «можно на повторные, но он с резким
## началом и концом ведь, тоже надо учитывать»): the repeated crossing (Pelageya ferries, `auto`) shows the boat's view
## as a film — data `film` of the crossing's mechanic (game/scripts/mechanics/crossing_panel.gd).
##   CF-1 every repeated crossing of the game names the film and the file is there; the crossing by hand (M18p) does not;
##   CF-2 it begins as the painting: the first drawn picture is the painted view (the film not in yet), and the film
##        comes in smoothly — its share never steps by more than the time allows — to the whole picture; the painted
##        rope and ring are gone by then, the boat's bob has stopped, the game's fog and snow are drawn over the film;
##   CF-3 it is alive: the picture half a second on is another one (the water runs), and it is not the painted view;
##   CF-4 the end: «crossed» comes while the film still runs, with time left for the black of the event (0.7 s);
##        a click skips to the shore as before;
##   CF-6 (found 14.11 while the film was put in) by day — no time-of-day flag of the evenings set, the rule of the
##        room's own day layer — the crossing shows the day painting of the boat (R2/day.png), the far pier of the day
##        where there is one, thin fog, and no film (there is none of the day view yet); in the evening — the evening
##        painting and the film. Before: the evening view between two rooms in daylight on days three and four.
##   CF-5 self-check — a film that jumps in (`in_s` near 0) is caught by CF-2's measure; with the films switched off
##        (the test's switch) the same crossing is the painted one: no film,
##        the rope drawn, and the picture is the painting's own; the crossing by hand gets no film even if its data named one.
## Video decodes only with a display:
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/test_crossing_film.gd

const BLACK_FADE_S := 0.7

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var sr: Node = null
var sd: Node = null


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
	if DisplayServer.get_name() == "headless":
		print("SKIP  crossing film: no display (video decodes only with one) — run under xvfb")
		quit(0)
		return
	await _test("CF-1 the repeated crossings name the film, the crossing by hand does not", _test_data)
	await _test("CF-2 CF-3 the film comes in from the painting, smoothly, and is alive", _test_start)
	await _test("CF-4 «crossed» comes over the running film; a click skips to the shore", _test_end)
	await _test("CF-5 self-check: films off — the painted crossing; by hand — never a film", _test_self_check)
	await _test("CF-6 by day the crossing is the day's painting (no evening view between two day rooms); self-check — in the evening it is the evening's", _test_day)
	var failed := _results.count(false)
	print("==== crossing film: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Every crossing mechanic of the rooms and scenes: [{where, spec}].
func _crossings() -> Array:
	var out: Array = []
	for rid in sd.rooms.keys():
		var room: Dictionary = sd.rooms[rid]
		for kind in ["hotspots", "exits"]:
			for h in room.get(kind, []):
				var m = (h as Dictionary).get("mechanic")
				if m is Dictionary and String(m.get("type", "")) == "crossing":
					out.append({"where": "%s/%s" % [rid, String(h.get("id", h.get("to", "")))], "spec": m})
	for s in sd.scenes_list() if sd.has_method("scenes_list") else []:
		pass
	return out


## The story as far as a start point (the main scenes done in order — the time of day follows them, it is not a
## flag one can set: game/scripts/core/time_of_day.gd).
func _story_to(point_id: String) -> void:
	gs.reset()
	var upto := String(sd.start_points.get(point_id, {}).get("done_through", ""))
	for id in sd.scene_order:
		if String(sd.scene(id).get("type", "")) != "main":
			continue
		gs.set_flag("started_" + String(id), true)
		gs.set_flag("done_" + String(id), true)
		if String(id) == upto:
			break


## The film is the evening view's: the tests of the film cross on the evening of day two (the lanterns' start point).
func _evening() -> void:
	_story_to("lights")


func _auto_spec() -> Dictionary:
	for c in _crossings():
		if bool(c["spec"].get("auto", false)):
			var s: Dictionary = (c["spec"] as Dictionary).duplicate(true)
			s.erase("events")   # the test stays in the boat: no travel, no black
			s.erase("requires")
			return s
	return {}


func _open(spec: Dictionary) -> Dictionary:
	var view := CanvasLayer.new()
	view.set_script(load("res://scripts/mechanics/mechanic_view.gd"))
	root.add_child(view)
	await _frames(2)
	sr.open_mechanic(spec, "rope")
	await _frames(1)
	return {"view": view, "panel": view.get("panel")}


func _close(o: Dictionary) -> void:
	sr.close_mechanic()
	await _frames(2)
	(o["view"] as Node).queue_free()
	await _frames(2)


## CF_SHOTS=<folder>: the pictures the checks look at are saved there whole (to see them with one's own eyes).
var _shot_n := 0


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if OS.get_environment("CF_SHOTS") != "":
		_shot_n += 1
		img.save_png(OS.get_environment("CF_SHOTS").path_join("cf_%02d.png" % _shot_n))
	img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	return img


## Mean difference of two small pictures over a part of them (0…1 of the height), per channel, of 255.
func _diff(a: Image, b: Image, y0 := 0.0, y1 := 1.0) -> float:
	var sum := 0.0
	var n := 0
	for y in range(int(a.get_height() * y0), int(a.get_height() * y1), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 3
	return sum / maxf(n, 1.0) * 255.0


func _test_data() -> void:
	var autos := 0
	for c in _crossings():
		var spec: Dictionary = c["spec"]
		if bool(spec.get("auto", false)):
			autos += 1
			var path := String(spec.get("film", {}).get("video", ""))
			_check(path != "" and ResourceLoader.exists(path), "%s: the repeated crossing names no film that exists (%s)" % [c["where"], path])
			var day: Dictionary = spec.get("day", {})
			var day_bg := String(day.get("art", {}).get("bg", ""))
			_check(day_bg.ends_with("R2/day.png") and ResourceLoader.exists(day_bg), "%s: no day painting for the crossing by day (%s)" % [c["where"], day_bg])
			var room_day: Array = []
			for l in sd.rooms["R2"].get("layers", []):
				if String(l.get("id", "")) == "day":
					room_day = l.get("unless", [])
			_check(day.get("unless", []) == room_day and not room_day.is_empty(), "%s: the day view follows the room's day layer (%s against %s)" % [c["where"], str(day.get("unless")), str(room_day)])
		else:
			_check(not spec.has("film"), "%s: a crossing by hand names a film" % c["where"])
	_check(autos >= 4, "repeated crossings in the rooms: %d (R2 two, R3, Z3)" % autos)
	var hand: Dictionary = {}
	for m in sd.scene("M18p").get("mechanics", []):
		if String((m as Dictionary).get("spec", {}).get("type", "")) == "crossing":
			hand = m["spec"]
	_check(not hand.is_empty() and not bool(hand.get("auto", false)) and not hand.has("film"), "M18p: the first crossing is by hand, without a film")


func _test_start() -> void:
	_evening()
	# the painted view of the same crossing, for comparison: films off, the first picture
	var script: Script = load("res://scripts/mechanics/crossing_panel.gd")
	script.set("films_enabled", false)
	var p0: Dictionary = await _open(_auto_spec())
	await _frames(2)
	var painted := await _grab()
	await _close(p0)
	script.set("films_enabled", true)
	var o: Dictionary = await _open(_auto_spec())
	var panel: Node = o["panel"]
	_check(panel != null and bool(panel.call("probe").get("film", false)), "the repeated crossing has its film")
	if panel == null or not bool(panel.call("probe").get("film", false)):
		await _close(o)
		return
	await _frames(1)
	var first := await _grab()
	var pr: Dictionary = panel.call("probe")
	_check(float(pr["film_alpha"]) < 0.2, "the first picture is drawn before the film is in (film share %.2f)" % float(pr["film_alpha"]))
	_check(_diff(first, painted) < 4.0, "the first picture is the painted view (differs by %.1f of 255)" % _diff(first, painted))
	# the film comes in: its share against its own time, frame by frame
	var came: Dictionary = await _come_in(panel)
	pr = panel.call("probe")
	_check(float(pr["film_alpha"]) >= 0.999, "the film is the whole picture in the end (share %.2f after %d frames)" % [float(pr["film_alpha"]), int(came["frames"])])
	_check(float(came["worst"]) <= 0.0 and not bool(came["went_back"]), "the film comes in smoothly (a stride %.3f over what its time allows; went back: %s)" % [float(came["worst"]), came["went_back"]])
	_check(float(came["took"]) >= 0.5, "the film takes its time to come in: %.2f s of the film's own time (0.6 in the data)" % float(came["took"]))
	_check(float(pr["rope_alpha"]) < 0.01, "the painted rope is gone under the film's own (alpha %.2f)" % float(pr["rope_alpha"]))
	_check(absf(float(pr["stage_y"])) < 0.01, "the boat's bob has stopped (the film rocks by itself): %.2f px" % float(pr["stage_y"]))
	var stage: Node = panel.get_node("Stage")
	_check(stage.get_node("Snow").get_index() > stage.get_node("Fog").get_index() and stage.get_node("Fog").get_index() > stage.get_node("Film").get_index()
			and stage.get_node("Film").get_index() > stage.get_node("ShoreBand").get_index(),
			"the film lies over the painting and under the game's fog and snow")
	# alive, and not the painting
	var a1 := await _grab()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await process_frame
	var a2 := await _grab()
	_check(_diff(a1, a2, 0.4, 1.0) > 0.8, "the water runs: half a second on the lower picture differs by %.2f of 255" % _diff(a1, a2, 0.4, 1.0))
	_check(bool(panel.call("probe")["film_playing"]), "the film is playing")
	await _close(o)


## Follows the film's share until it is the whole picture. The stride of the share is held against the FILM's own
## time between the same two readings (probe `film_t`), not against the wall clock: under Xvfb a slow frame is
## followed by a fast one, and the panel's step is the engine's delta of the frame before — on 14.11 the wall clock
## made a stride «0.125 over» out of that (run 43641370804). The smooth step over 0.6 s climbs 2.5 a second at its
## steepest; a film that jumps in (`in_s` near 0) takes a whole stride in one frame's time.
func _come_in(panel: Node) -> Dictionary:
	var pr: Dictionary = panel.call("probe")
	var last_a := float(pr["film_alpha"])
	var last_t := float(pr["film_t"])
	var t_first := -1.0
	var worst := -1.0
	var went_back := false
	var frames := 0
	while float(panel.call("probe")["film_alpha"]) < 0.999 and frames < 900:
		await process_frame
		frames += 1
		pr = panel.call("probe")
		var a := float(pr["film_alpha"])
		var ft := float(pr["film_t"])
		if t_first < 0.0 and ft > 0.0:
			t_first = last_t
		worst = maxf(worst, (a - last_a) - 2.6 * (ft - last_t) - 0.01)
		went_back = went_back or a < last_a - 0.0001
		last_a = a
		last_t = ft
	return {"worst": worst, "went_back": went_back, "frames": frames, "took": last_t - maxf(t_first, 0.0)}


func _test_end() -> void:
	_evening()
	var spec := _auto_spec()
	var o: Dictionary = await _open(spec)
	var panel: Node = o["panel"]
	# the wall clock only bounds the wait (a loaded machine under Xvfb draws a frame in most of a second); what is
	# checked is the game's own time — the film's position when «crossed» comes
	var t0 := Time.get_ticks_msec()
	while not bool(panel.call("probe")["crossed"]) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var pr: Dictionary = panel.call("probe")
	var length := float((panel.get("film") as VideoStreamPlayer).get_stream_length()) if panel.get("film") != null else 0.0
	_check(bool(pr["crossed"]), "the boat comes across by itself (%.1f s)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	# the crossing lasts pulls × pull_s and the hold whatever the frames are: «crossed» within a frame or two of that
	var want_s := int(spec.get("pulls", 10)) * float(spec.get("pull_s", 0.9)) + float(spec.get("arrive_hold_s", 0.8))
	_check(float(pr["film_t"]) <= want_s + 0.6, "the crossing took %.2f s of the game's time (pulls and hold: %.2f s)" % [float(pr["film_t"]), want_s])
	_check(bool(pr["film_playing"]) and not bool(pr["film_held"]), "«crossed» comes while the film runs (position %.2f s)" % float(pr["film_pos"]))
	_check(length <= 0.0 or float(pr["film_pos"]) + BLACK_FADE_S <= length, "the film has %.2f s left for the black's %.1f s (length %.2f, position %.2f)" % [length - float(pr["film_pos"]), BLACK_FADE_S, length, float(pr["film_pos"])])
	await _close(o)
	# a click: straight to the shore, as before
	o = await _open(spec)
	panel = o["panel"]
	await _frames(6)
	var before := int(panel.call("probe")["pulls"])
	panel.call("pull")
	await _frames(1)
	pr = panel.call("probe")
	_check(before < int(spec.get("pulls", 10)) and int(pr["pulls"]) == int(spec.get("pulls", 10)), "a click skips to the shore: pulls %d → %d of %d" % [before, int(pr["pulls"]), int(spec.get("pulls", 10))])
	t0 = Time.get_ticks_msec()
	while not bool(panel.call("probe")["crossed"]) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	_check(bool(panel.call("probe")["crossed"]), "after the click the boat is across")
	await _close(o)


func _test_self_check() -> void:
	_evening()
	var script: Script = load("res://scripts/mechanics/crossing_panel.gd")
	script.set("films_enabled", false)
	var o: Dictionary = await _open(_auto_spec())
	var panel: Node = o["panel"]
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200:
		await process_frame
	var pr: Dictionary = panel.call("probe")
	_check(not bool(pr["film"]) and float(pr["rope_alpha"]) > 0.99, "films off: no film, the painted rope drawn (film %s, rope %.2f)" % [pr["film"], float(pr["rope_alpha"])])
	_check(float(pr["band_scale"]) > 1.01, "films off: the painted far shore grows as before (%.3f)" % float(pr["band_scale"]))
	await _close(o)
	script.set("films_enabled", true)
	# a film that jumps in (no time to come in) is caught by the measure of CF-2
	var jump := _auto_spec()
	jump["film"]["in_s"] = 0.001
	o = await _open(jump)
	var came: Dictionary = await _come_in(o["panel"])
	_check(float(came["worst"]) > 0.0 and float(came["took"]) < 0.5, "a film that jumps in is caught (stride %.3f over, came in %.2f s)" % [float(came["worst"]), float(came["took"])])
	await _close(o)
	# by hand: a film in the data is not taken
	var hand := _auto_spec()
	hand["auto"] = false
	o = await _open(hand)
	await _frames(10)
	_check(not bool((o["panel"] as Node).call("probe")["film"]), "the crossing by hand takes no film")
	await _close(o)


func _test_day() -> void:
	# day three by day (the free day's start point): none of the flags the room's day layer names
	_story_to("freewalk")
	var spec := _auto_spec()
	_check(not (spec.get("day", {}).get("unless", []) as Array).any(func(fl): return gs.has_flag(String(fl))), "the free day of day three is a day for the room's day layer")
	var o: Dictionary = await _open(spec)
	var pr: Dictionary = (o["panel"] as Node).call("probe")
	_check(bool(pr["day"]) and String(pr["bg"]).ends_with("R2/day.png"), "by day the boat's view is the day painting (%s)" % String(pr["bg"]))
	_check(not bool(pr["film"]), "by day there is no film of the evening view")
	_check(float(pr["fog"]) < 0.2, "by day the fog is thin (%.2f)" % float(pr["fog"]))
	await _frames(3)
	var day_pic := await _grab()
	await _close(o)
	_evening()
	_check((spec.get("day", {}).get("unless", []) as Array).any(func(fl): return gs.has_flag(String(fl))), "the evening of day two is not a day for it")
	o = await _open(spec)
	pr = (o["panel"] as Node).call("probe")
	_check(not bool(pr["day"]) and String(pr["bg"]).ends_with("R2/bg.png") and bool(pr["film"]), "self-check: in the evening — the evening painting and the film (%s, film %s)" % [String(pr["bg"]), pr["film"]])
	await _frames(3)
	var eve_pic := await _grab()
	_check(_diff(day_pic, eve_pic, 0.0, 0.4) > 20.0, "the day's sky is not the evening's (the upper picture differs by %.1f of 255)" % _diff(day_pic, eve_pic, 0.0, 0.4))
	await _close(o)
