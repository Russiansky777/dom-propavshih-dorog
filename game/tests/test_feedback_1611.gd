extends SceneTree
## Director's notes of 16.11 (00:22–00:28) after the review before release (Docs/REVIEW_FULL_2026-11-15.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_1611.gd
##   F16-1 («Да, можем поправить строку эту»): the line of a thing picked from the bag said «…по месту, где его
##       применить» — «его» whatever the thing's gender («Скоба для плиты … его»). The line names no gender now.
##       Self-check — the old wording is caught by the same check.
##   F16-2 («подложку можем добавить где нужно»): the hints of the mini-games played over a whole picture (the windlass
##       over the snow, the crossing, the knot on the support, the lantern, the map's paper, the fishing in the room) lie
##       on a dark see-through plate (HintPlate): it stands right under the words, covers them whole, is no wider than
##       the words need (not the label's box), and goes when the words go. The words are measured here on their own —
##       by the font, not by the plate's measure. Self-checks — a plate left at a short line does not pass for a long
##       one; a mini-game on the dark backdrop (the noughts and crosses) has no plate.
##   F16-3 («Можно убрать кадр с ходиками, а добавить… рыбалку»): the film (trailer_v3) has no shot of mother's mirror,
##       opens with the game itself (a room), and has the fishing after the street of Olkhovka and before the map: the
##       mini-game is Mitya's own (the choice's, in the room), the float goes under at its second, the hand strikes with
##       a real press and the string is kept in the green to the shot's end. Self-check — the same shot without the
##       hand on the string loses the green.

const PLAN := "res://data/trailer/trailer_v3.json"

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
	await _test("F16-1 the line of a picked thing names no gender («его»); self-check — the old wording is caught", _test_selected_line)
	await _test("F16-2 the hints of the mini-games over a picture lie on a plate that covers the words and hugs them; self-checks — a stale plate, the dark backdrop", _test_hint_plates)
	await _test("F16-3 the film: no mother's mirror, the fishing after the street — bite, strike, the string in the green; self-check — no hand, no green", _test_film_fishing)
	var failed := _results.count(false)
	print("==== feedback 16.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


# --- F16-1 ---------------------------------------------------------------------------------------

## A word that agrees with one gender only, said of a thing whose name may be of any.
func _gendered(line: String) -> bool:
	for w in [" его ", " её ", " ее ", " него ", " неё ", " нему ", " ней "]:
		if (" " + line.to_lower() + " ").contains(w):
			return true
	return false


func _test_selected_line() -> void:
	var seen := 0
	for id in sd.items.keys():
		if not bool(sd.call("item_is_inventory", id)):
			continue
		var line := String(sd.call("text", "@ui.item_selected", {"item": sd.call("item_name", id)}))
		seen += 1
		_check(line.contains(String(sd.call("item_name", id))), "%s: the line names the thing («%s»)" % [id, line])
		_check(not _gendered(line), "%s: the line has a word of one gender («%s»)" % [id, line])
	_check(seen >= 10, "the bag's things were looked at (%d)" % seen)
	_check(_gendered("Выбрано: Скоба для плиты — щёлкнуть по месту, где его применить"), "self-check: the old wording is caught")


# --- F16-2 ---------------------------------------------------------------------------------------

## The mini-games played over a whole picture: [name, its data, flags, plates].
func _spec_room(room_id: String, hotspot: String, option: String = "") -> Dictionary:
	for h in sd.rooms[room_id].get("hotspots", []):
		if String(h.get("id", "")) != hotspot:
			continue
		if option == "":
			return (h.get("mechanic", {}) as Dictionary).duplicate(true)
		for o in h.get("choice", {}).get("options", []):
			if String(o.get("id", "")) == option:
				return (o.get("mechanic", {}) as Dictionary).duplicate(true)
	return {}


func _spec_scene(type: String) -> Dictionary:
	for id in sd.scenes.keys():
		for m in sd.scenes[id].get("mechanics", []):
			if String(m.get("spec", {}).get("type", "")) == type:
				return (m["spec"] as Dictionary).duplicate(true)
	return {}


## The words of a label measured by its font (not by HintPlate): their rectangle in the parent's coordinates.
func _words_by_font(l: Label) -> Rect2:
	if l.text.strip_edges() == "" or not l.visible:
		return Rect2()
	var font := l.get_theme_font(&"font")
	var fs := l.get_theme_font_size(&"font_size")
	var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, l.size.x, fs)
	var x := 0.0
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (l.size.x - sz.x) * 0.5
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = l.size.x - sz.x
	return Rect2(l.position + Vector2(x, 0.0) * l.scale, sz * l.scale)


## The plate against its labels: covers their words (measured by the font) and is no wider than they need.
func _fits(p: HintPlate, slack: float = 6.0) -> String:
	var r := Rect2()
	var any := false
	for l in p.labels:
		var w := _words_by_font(l)
		if w.size.x <= 0.0:
			continue
		r = r.merge(w) if any else w
		any = true
	if not any:
		return "" if not p.visible else "no words, yet the plate is seen"
	if not p.visible:
		return "words on screen, no plate"
	var pr := Rect2(p.position, p.size)
	if not pr.grow(slack).encloses(r):
		return "the plate %s does not cover the words %s" % [str(pr), str(r)]
	if pr.size.x > r.size.x + HintPlate.PAD.x * 2.0 + slack * 2.0 or pr.size.y > r.size.y + HintPlate.PAD.y * 2.0 + slack * 2.0 + 8.0:
		return "the plate %s is larger than the words %s need" % [str(pr.size), str(r.size)]
	return ""


func _test_hint_plates() -> void:
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var mv = main_node.get_node("MechanicView")
	var games := [
		["windlass", _spec_scene("windlass"), [], 1],
		["crossing", _spec_room("R2", "rope"), [], 1],
		["plate", _spec_room("Z3", "pier_plate"), ["skoba_on_plate"], 1],
		["lantern", _spec_room("R1", "lantern"), [], 1],   # three lines, one plate
		["map_route", _spec_room("O1", "village_map"), [], 2],   # the hint and the row of the way's three names
		["fishing", _spec_room("R3", "mitya", "fish"), [], 1],
	]
	var seen := 0
	for g in games:
		var gname := String(g[0])
		var spec: Dictionary = g[1]
		_check(not spec.is_empty() and String(spec.get("type", "")) == gname, "%s: its data found" % gname)
		if spec.is_empty():
			continue
		spec.erase("events")   # the test opens the picture, not the story
		for f in g[2]:
			gs.set_flag(String(f), true)
		sr.open_mechanic(spec, "test")
		for i in 6:
			await process_frame
		var pn: Node = mv.get("panel")
		var plates: Array = pn.find_children("*", "HintPlate", true, false) if pn != null else []
		_check(plates.size() == int(g[3]), "%s: %d plate(s) under its words (%d)" % [gname, int(g[3]), plates.size()])
		for p in plates:
			var hp := p as HintPlate
			var first: Label = hp.labels[0]
			_check(hp.get_parent() == first.get_parent() and hp.get_index() < first.get_index(), "%s: the plate stands under its words in the tree" % gname)
			_check(hp.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: the plate takes no clicks" % gname)
			var said := false
			for l in hp.labels:
				said = said or l.text.strip_edges() != ""
			_check(said, "%s: the words are there when the mini-game opens" % gname)
			var why := _fits(hp)
			_check(why == "", "%s: %s" % [gname, why])
			print("        %s: the plate %s under the words %s" % [gname, str(Rect2(hp.position, hp.size)), str(hp.words)])
			# the words change — the plate follows; the words go — the plate goes
			var keep: Array = []
			for l in hp.labels:
				keep.append(l.text)
			first.text = "Да."
			for i in 3:
				await process_frame
			why = _fits(hp)
			_check(why == "", "%s, a short line: %s" % [gname, why])
			for l in hp.labels:
				l.text = ""
			for i in 3:
				await process_frame
			_check(not hp.visible, "%s: no words — no plate" % gname)
			for i in hp.labels.size():
				hp.labels[i].text = keep[i]
			for i in 3:
				await process_frame
			if seen == 0 and p == plates[0]:
				# self-check: a plate that did not follow its words is caught
				first.text = "Да."
				for i in 3:
					await process_frame
				hp.set_process(false)
				first.text = String(keep[0]) + " " + String(keep[0])
				for i in 3:
					await process_frame
				_check(_fits(hp) != "", "self-check: a plate left at a short line does not pass for a long one")
				hp.set_process(true)
		seen += 1
		sr.close_mechanic()
		for f in g[2]:
			gs.set_flag(String(f), false)
		for i in 3:
			await process_frame
	_check(seen == games.size(), "all the mini-games over a picture were looked at (%d of %d)" % [seen, games.size()])
	# self-check: on the dark backdrop the words need no plate — the noughts and crosses have none
	var ttt := _spec_room("O1", "ulyana", "ttt")
	ttt.erase("events")
	sr.open_mechanic(ttt, "test")
	for i in 6:
		await process_frame
	var pt: Node = mv.get("panel")
	_check(pt != null and pt.find_children("*", "HintPlate", true, false).is_empty(), "self-check: the noughts and crosses (dark backdrop) have no plate")
	sr.close_mechanic()
	for i in 2:
		await process_frame
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await process_frame


# --- F16-3 ---------------------------------------------------------------------------------------

func _test_film_fishing() -> void:
	var plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	_check(plan is Dictionary, "the film's plan reads")
	if not plan is Dictionary:
		return
	var ids: Array = []
	for s in plan["shots"]:
		ids.append(String(s["id"]))
	for s in plan["shots"]:
		var by_mirror := false
		for e in s.get("ui", {}).get("events", []):
			by_mirror = by_mirror or (String(e.get("do", "")) == "mechanic" and String(e.get("hotspot", "")) == "bundle_nina")
		_check(not by_mirror, "%s: mother's mirror (the clocks) is not in the film" % s["id"])
	_check(not ids.has("mirror"), "no shot «mirror»")
	_check(String(plan["shots"][0].get("kind", "")) == "room", "the film opens with the game itself (a room), not a card")
	var fi := ids.find("fishing")
	_check(fi > 0 and ids[fi - 1] == "olk_street" and fi + 1 < ids.size() and ids[fi + 1] == "mg_map", "the fishing stands after the street and before the map (%s)" % str(ids))
	if fi < 0:
		return
	var total := 0.0
	for s in plan["shots"]:
		total += float(s["duration"])
	_check(total <= 60.0, "the film is no longer than a minute (%.1f s)" % total)
	var shot: Dictionary = plan["shots"][fi]
	var held := await _play_fishing(shot, true)
	_check(String(held.get("type", "")) == "fishing" and bool(held.get("in_room", false)), "the shot's mini-game is the fishing in the room (%s)" % str(held.get("type", "")))
	_check(String(held.get("phase_at_bite", "")) == "bite", "the float goes under at its second (phase «%s»)" % held.get("phase_at_bite", ""))
	_check(String(held.get("phase_end", "")) == "fight", "the strike began the fight and it lasts to the shot's end (phase «%s», ended «%s»)" % [held.get("phase_end", ""), held.get("last_end", "")])
	_check(float(held.get("in_green", 0.0)) >= 0.6, "the string is kept in the green most of the fight (%.0f %%)" % (float(held.get("in_green", 0.0)) * 100.0))
	_check(int(held.get("hand", 0)) > 30, "the hand works the string (%d frames)" % int(held.get("hand", 0)))
	var loose := await _play_fishing(shot, false)
	print("        the fishing shot: with the hand %s; without %s" % [str(held), str(loose)])
	_check(float(loose.get("in_green", 1.0)) < float(held.get("in_green", 0.0)) - 0.2 or String(loose.get("phase_end", "")) != "fight",
		"self-check: without the hand on the string the green is lost (%.0f %% against %.0f %%, phase «%s»)" % [float(loose.get("in_green", 0.0)) * 100.0, float(held.get("in_green", 0.0)) * 100.0, loose.get("phase_end", "")])


## Plays the fishing shot of the film to its end; `hand` false — without its `hold_line` event.
func _play_fishing(shot: Dictionary, hand: bool) -> Dictionary:
	var out := {}
	var tr: Node = load("res://scenes/trailer/Trailer.tscn").instantiate()
	tr.set("quit_at_end", false)
	if not bool(tr.call("load_plan", PLAN, String(shot["id"]))):
		_check(false, "the shot loads (%s)" % str(tr.get("errors")))
		tr.free()
		return out
	if not hand:
		var s2: Dictionary = (tr.get("shot") as Dictionary).duplicate(true)
		s2["ui"]["events"] = (s2["ui"]["events"] as Array).filter(func(e): return String(e.get("do", "")) != "hold_line")
		tr.set("shot", s2)
	var fps := int(tr.get("fps"))
	# the film's clock is a frame per frame; the mini-game's own is the engine's — here they go together, as in the render
	var max_fps_was := Engine.max_fps
	Engine.max_fps = fps
	root.add_child(tr)
	var frames: int = tr.get("total_frames")
	var pre := float(shot.get("preroll_s", 0.0))
	var bite_at := 0.0
	var strike_at := 0.0
	for e in shot["ui"]["events"]:
		if String(e.get("do", "")) == "panel" and String(e.get("call", "")) == "bite_now":
			bite_at = float(e["at_s"])
		if String(e.get("do", "")) == "down":
			strike_at = float(e["at_s"])
	var end_frame := int((pre + float(shot["duration"])) * fps) - 2
	var fight_n := 0
	var green_n := 0
	var mv = null
	while int(tr.get("frame")) < mini(end_frame, frames - 2):
		await process_frame
		mv = tr.get("_mech_view")
		var pn = mv.get("panel") if mv != null else null
		if pn == null or not is_instance_valid(pn):
			continue
		var t := float(int(tr.get("frame"))) / fps - pre
		out["type"] = String(pn.spec.get("type", ""))
		out["in_room"] = bool(pn.get("in_room"))
		if t >= bite_at + 0.1 and t < strike_at and not out.has("phase_at_bite"):
			out["phase_at_bite"] = String(pn.get("phase"))
		if String(pn.get("phase")) == "fight" and t > strike_at + 0.5:
			fight_n += 1
			var g: Vector2 = pn.get("green")
			var ten := float(pn.get("tension"))
			if ten >= g.x and ten <= g.y:
				green_n += 1
		out["phase_end"] = String(pn.get("phase"))
		out["last_end"] = String(pn.get("last_end"))
	out["in_green"] = float(green_n) / maxf(1.0, float(fight_n))
	out["hand"] = int(tr.get("line_held_frames"))
	Engine.max_fps = max_fps_was
	tr.queue_free()
	await process_frame
	if sr.mechanic_open:
		sr.close_mechanic()
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	for b in ["Music", "Voice"]:
		var bi := AudioServer.get_bus_index(b)
		if bi >= 0:
			AudioServer.set_bus_mute(bi, false)
	rm.autosave_enabled = true
	gs.reset()
	await process_frame
	return out
