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
##   CF-5 self-check — with the films switched off (the test's switch) the same crossing is the painted one: no film,
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
		else:
			_check(not spec.has("film"), "%s: a crossing by hand names a film" % c["where"])
	_check(autos >= 4, "repeated crossings in the rooms: %d (R2 two, R3, Z3)" % autos)
	var hand: Dictionary = {}
	for m in sd.scene("M18p").get("mechanics", []):
		if String((m as Dictionary).get("spec", {}).get("type", "")) == "crossing":
			hand = m["spec"]
	_check(not hand.is_empty() and not bool(hand.get("auto", false)) and not hand.has("film"), "M18p: the first crossing is by hand, without a film")


func _test_start() -> void:
	gs.reset()
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
	# the film comes in: its share against the time, frame by frame
	var last_a := float(pr["film_alpha"])
	var last_ms := Time.get_ticks_msec()
	var worst := 0.0
	var went_back := false
	var waited := 0
	while float(panel.call("probe")["film_alpha"]) < 0.999 and waited < 600:
		await process_frame
		waited += 1
		var a := float(panel.call("probe")["film_alpha"])
		var now := Time.get_ticks_msec()
		var dt := maxf(float(now - last_ms) / 1000.0, 1.0 / 240.0)
		# the smooth step over 0.6 s climbs 2.5 a second at its steepest; a slow frame may take a longer stride
		worst = maxf(worst, (a - last_a) - 2.6 * dt - 0.03)
		went_back = went_back or a < last_a - 0.0001
		last_a = a
		last_ms = now
	pr = panel.call("probe")
	_check(float(pr["film_alpha"]) >= 0.999, "the film is the whole picture in the end (share %.2f after %d frames)" % [float(pr["film_alpha"]), waited])
	_check(worst <= 0.0 and not went_back, "the film comes in smoothly (a stride %.3f over what the time allows; went back: %s)" % [worst, went_back])
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


func _test_end() -> void:
	gs.reset()
	var spec := _auto_spec()
	var o: Dictionary = await _open(spec)
	var panel: Node = o["panel"]
	var t0 := Time.get_ticks_msec()
	while not bool(panel.call("probe")["crossed"]) and Time.get_ticks_msec() - t0 < 9000:
		await process_frame
	var pr: Dictionary = panel.call("probe")
	var length := float((panel.get("film") as VideoStreamPlayer).get_stream_length()) if panel.get("film") != null else 0.0
	_check(bool(pr["crossed"]), "the boat comes across by itself (%.1f s)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	_check(bool(pr["film_playing"]) and not bool(pr["film_held"]), "«crossed» comes while the film runs (position %.2f s)" % float(pr["film_pos"]))
	_check(length <= 0.0 or float(pr["film_pos"]) + BLACK_FADE_S <= length, "the film has %.2f s left for the black's %.1f s (length %.2f, position %.2f)" % [length - float(pr["film_pos"]), BLACK_FADE_S, length, float(pr["film_pos"])])
	await _close(o)
	# a click: straight to the shore, as before
	o = await _open(spec)
	panel = o["panel"]
	await _frames(20)
	panel.call("pull")
	t0 = Time.get_ticks_msec()
	while not bool(panel.call("probe")["crossed"]) and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	_check(bool(panel.call("probe")["crossed"]) and Time.get_ticks_msec() - t0 < 2000, "a click skips to the shore (%.1f s)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	await _close(o)


func _test_self_check() -> void:
	gs.reset()
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
	# by hand: a film in the data is not taken
	var hand := _auto_spec()
	hand["auto"] = false
	o = await _open(hand)
	await _frames(10)
	_check(not bool((o["panel"] as Node).call("probe")["film"]), "the crossing by hand takes no film")
	await _close(o)
