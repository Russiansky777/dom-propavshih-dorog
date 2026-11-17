extends SceneTree
## The review before release, 17.11 (Director: «полный ультимативный ревью перед релизом»).
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1711.gd
##   R17-1 The morning of day three: N02 walks Nina out of the horenka at night (npc_go with a fade); in the morning the
##       room is the same, not rebuilt — she stayed invisible by the door while M21 had her speak and her caption
##       «Нина» hung over an empty floor. From bedtime2 by the bed: in the morning Nina stands in her place, in sight,
##       before M21 and through its lines (N02's `npc_back`). Self-check — the same night without `npc_back`: she is
##       out of sight in the morning, and the check says so.
##   R17-2 The rule of tests/ghost_watch.gd (a clickable villager is a visible one; the bot walkthroughs run it all the
##       way): a shown hotspot over a figure at alpha 0 that is not walking is caught; a walking or visible one, or one
##       whose hotspot is hidden, is not.
##   R17-3 The photo in the mill passage: its caption above the line box on every line said over it (ru, en).
##   R17-4 A room change takes the old room's hover caption away at once (GameUi.drop_hover).
##   R17-5 The speaker rule of ghost_watch.gd: a villager who speaks is in sight (Q07 Pelageya, Q08 the guests).
##   R17-6 A body turn settles at any frame length (Actor3D.turn_step in slices).
##   R17-7 M21b: Agata reads the village list over it, then the talk goes on in the room (scenes data close_view).
##   R17-8 Director 17.11 (evening) «Ленту — можно, давай сделаем да»: Mama takes the ribbon in Dunya's house too.
##   R17-9 Director 17.11 «надписи приняты»: close-up titles on one line above their pictures (the big ones lower).
##   R17-10 Director 17.11 «давай озвучим ок»: the epilogue's trace of Mama's ribbon (M26 №16 `then`, ru and en voice).
##       Written ahead of the line: the Director picks one of two recorded variants by ear; `_test_epilogue_ribbon` joins
##       `_run` in the same commit as the line and its recordings (until then it would only say the line is missing).
##   Every one with its self-check.

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
	await _test("R17-1 the morning of day three: Nina in her place and in sight before and through M21 (N02 npc_back); self-check — without it she is gone and it is seen", _test_morning_nina)
	await _test("R17-2 the ghost rule: clickable and out of sight is caught; walking, visible or hidden is not", _test_ghost_rule)
	await _test("R17-3 the photo in the mill passage: its caption clear of the line box through the lines said over it (ru, en); self-check — the layout until 17.11 is caught", _test_photo_caption)
	await _test("R17-4 a room change takes the old room's caption away at once; self-check — without it the caption stays over the new room", _test_hover_drop)
	await _test("R17-5 the speaker rule (ghost_watch.gd): a speaker with a figure in sight passes; a faded, hidden or absent one, or Agata hidden, is caught", _test_speaker_rule)
	await _test("R17-6 a body turn settles at any frame length (villagers; Agata running); self-check — the unsliced step at a long frame swings", _test_turn_settles)
	await _test("R17-7 M21b: Agata reads the village list over it, then the talk with Mama goes on in the room, not over the paper; self-check — without the scene's close_view it stays over it", _test_m21b_room)
	await _test("R17-8 Mama's ribbon in Dunya's house (the free day): a real click with it on Mama braids it — the close-up, the trace, the ribbon gone; self-check — without the house's item_use it stays in the bag", _test_ribbon_h1)
	await _test("R17-9 Director 17.11 «надписи приняты»: every close-up's title on one line, clear of its picture, the picture clear of the buttons (ru, en, every page); self-check — the old place of the picture (y 130) wraps the title", _test_titles_one_line)
	var failed := _results.count(false)
	print("==== review 17.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _hotspot(id: String) -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id:
			return h
	return null


## The night from bedtime2 to the morning by the bed, then Mama clicked (M21 is her talk) and its lines run; returns
## Nina's figure as it was in the morning before M21 and the worst alpha seen while M21 spoke.
func _night_and_morning() -> Dictionary:
	var out := {"morning_alpha": -1.0, "morning_pos": Vector2.ZERO, "home": Vector2.ZERO, "m21_min_alpha": 2.0, "m21_lines": 0}
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("bedtime2", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	var fig: Node2D = rm.current_room.get_node_or_null("npc_nina") as Node2D if rm.current_room != null else null
	var bed := _hotspot("bed")
	if fig == null or bed == null:
		_fails.append("bedtime2: no Nina figure (%s) or no bed (%s)" % [str(fig), str(bed)])
		main_node.queue_free()
		return out
	out["home"] = fig.global_position
	sr.interact(bed)
	var g := 0
	while g < 8000:
		g += 1
		await process_frame
		if gs.has_flag("done_M21"):
			break
		if gs.has_flag("morning_day3") and not gs.has_flag("started_M21") and sr.current_beat.is_empty() and not sr.is_busy():
			fig = rm.current_room.get_node_or_null("npc_nina") as Node2D
			if fig != null and float(out["morning_alpha"]) < 0.0:
				out["morning_alpha"] = fig.modulate.a
				out["morning_pos"] = fig.global_position
			var hn := _hotspot("nina")
			if hn != null:
				sr.interact(hn)
			continue
		if sr.active_scene == "M21" and not sr.current_beat.is_empty():
			fig = rm.current_room.get_node_or_null("npc_nina") as Node2D
			if fig != null:
				out["m21_min_alpha"] = minf(float(out["m21_min_alpha"]), fig.modulate.a)
				out["m21_lines"] = int(out["m21_lines"]) + 1
		if not sr.current_beat.is_empty() and not sr.is_staging():
			for i in 12:
				await process_frame
			sr.advance()
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await process_frame
	return out


func _test_morning_nina() -> void:
	var r: Dictionary = await _night_and_morning()
	_check(float(r["morning_alpha"]) > 0.95, "in the morning Nina is out of sight (alpha %.2f)" % float(r["morning_alpha"]))
	_check((r["morning_pos"] as Vector2).distance_to(r["home"]) < 2.0,
		"in the morning Nina is not in her place: %s, her place %s" % [str(r["morning_pos"]), str(r["home"])])
	_check(int(r["m21_lines"]) >= 3 and float(r["m21_min_alpha"]) > 0.95,
		"M21: %d lines, Nina's alpha down to %.2f while she spoke" % [int(r["m21_lines"]), float(r["m21_min_alpha"])])
	# self-check: the night as it was before the review — no npc_back — and the morning has no Nina in sight
	var n02: Dictionary = sd.scene("N02")
	var last: Dictionary = (n02.get("stage", []) as Array).back()
	var keep = last.get("npc_back", null)
	last.erase("npc_back")
	var bad: Dictionary = await _night_and_morning()
	if keep != null:
		last["npc_back"] = keep
	_check(float(bad["morning_alpha"]) < 0.05, "self-check: without npc_back Nina was still seen in the morning (alpha %.2f)" % float(bad["morning_alpha"]))


func _ui() -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("ui/game_ui.gd"):
			return n
	return null


func _set_subs(v: String) -> void:
	var ls = load("res://scripts/core/language_settings.gd")
	ls.set_subtitles(v)
	sd.call("reload")
	root.get_node("VoiceDirector").call("reload_config")


func _start(point: String) -> Node:
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get(point, {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	return main_node


func _stop(main_node: Node) -> void:
	if sr.mechanic_open:
		sr.close_mechanic()
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await process_frame


## The lowest corner of the photo's caption on screen (the photo lies turned a little), -1 — none shown.
func _caption_bottom() -> float:
	for c in root.find_children("Caption", "Label", true, false):
		var cap := c as Control
		if cap.get_parent() != null and String(cap.get_parent().name) == "Photo" and cap.is_visible_in_tree() and cap.text != "":
			var xf := cap.get_global_transform()
			var low := -INF
			for p in [Vector2.ZERO, Vector2(cap.size.x, 0.0), Vector2(0.0, cap.size.y), cap.size]:
				low = maxf(low, (xf * p).y)
			return low
	return -1.0


## The photo in the mill passage clicked the first time on day two (M09 done — M09s follows over it): for every page of
## every line said while it is open, the line box's top and the caption's lowest corner. `layout` — the photo's data
## put in place for this run (the self-check's old layout). Returns {"lines", "air" (the least box top − caption
## bottom), "worst"}.
func _photo_lines(lang: String, layout: Dictionary = {}) -> Dictionary:
	var out := {"lines": 0, "air": INF, "worst": ""}
	_set_subs(lang)
	var spec: Dictionary = {}
	for h in (sd.rooms["M2"]["hotspots"] as Array):
		if String((h as Dictionary).get("id", "")) == "photo":
			spec = h["mechanic"]["photo"]
	for k in layout.keys():
		spec[k] = layout[k]
	var main_node: Node = await _start("day2")
	# M09 done, the office door and the board «Порядок на мельнице» looked at: the photo is the last look — M09s plays
	# over it (rooms M1/M2 `complete_when`), as on day two
	for f in ["done_M09", "seen_office_door", "seen_shift_schedule"]:
		gs.set_flag(f, true)
	rm.change_room("M2", "from_M1")
	for i in 30:
		await process_frame
	var ph := _hotspot("photo")
	var ui := _ui()
	if ph == null or ui == null:
		_fails.append("no photo hotspot in M2 (%s) or no game UI (%s)" % [str(ph), str(ui)])
		await _stop(main_node)
		return out
	sr.interact(ph)
	var last := ""
	var g := 0
	while g < 4000:
		g += 1
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if gs.has_flag("done_M09s"):
				break   # the photo stays open after the lines (a click puts it away): all said over it is measured
			continue
		if sr.is_staging():
			continue
		var said: bool = String(b.get("type", "")) in ["line", "narration"]
		if sr.mechanic_open and said:
			var key := "%s|%d" % [String(b.get("text", "")), int(ui.get("dialogue_page"))]
			if key != last:
				last = key
				for i in 4:
					await process_frame
				var top: float = (ui.get("dialogue") as Control).get_global_rect().position.y
				var cb := _caption_bottom()
				if cb > 0.0:
					out["lines"] = int(out["lines"]) + 1
					if top - cb < float(out["air"]):
						out["air"] = top - cb
						out["worst"] = "«%s» (page %d): the line box from y %.0f, the caption down to %.0f" % [String(b.get("text", "")).left(40),
							int(ui.get("dialogue_page")) + 1, top, cb]
		for i in 6:
			await process_frame
		if said:
			ui.call("_next_line")
		else:
			sr.advance()
	await _stop(main_node)
	_set_subs("ru")
	return out


func _test_photo_caption() -> void:
	var spec: Dictionary = {}
	for h in (sd.rooms["M2"]["hotspots"] as Array):
		if String((h as Dictionary).get("id", "")) == "photo":
			spec = h["mechanic"]["photo"]
	var keep := {"pos": spec.get("pos"), "scale": spec.get("scale")}
	for lang in ["ru", "en"]:
		var r: Dictionary = await _photo_lines(lang)
		_check(int(r["lines"]) >= 2, "%s: %d lines seen over the photo (the narration and Agata's at least)" % [lang, int(r["lines"])])
		_check(float(r["air"]) >= 4.0, "%s: the caption under the line box — %s" % [lang, String(r["worst"])])
	# self-check: the layout until 17.11 — the caption ran under the box (the bots' screenshot 0022/0023 of day two)
	var bad: Dictionary = await _photo_lines("ru", {"pos": [274, 130], "scale": 0.82})
	_check(float(bad["air"]) < 0.0, "self-check: the old layout (274, 130; ×0.82) was not caught: air %.0f" % float(bad["air"]))
	for k in keep.keys():
		spec[k] = keep[k]


func _mouse(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = root.get_final_transform() * at
	m.global_position = m.position
	Input.warp_mouse(m.position)
	Input.parse_input_event(m)


## The caption over Pelageya at the far pier, then the story takes Agata to the street: is the caption shown right
## after the room change (before any frame of the new room)? `drop` false — the drop on room_changed taken away.
func _caption_after_change(drop: bool) -> Dictionary:
	var main_node: Node = await _start("olkhovka")
	var ui := _ui()
	var out := {"before": false, "after": true}
	if ui == null:
		_fails.append("no game UI")
		await _stop(main_node)
		return out
	var cb := Callable(ui, "drop_hover")
	if not drop and rm.room_changed.is_connected(cb):
		rm.room_changed.disconnect(cb)
	_mouse(Vector2(935, 545))   # Pelageya at the far pier (R3 hotspot [890, 425, 90, 240])
	for i in 12:
		await process_frame
	var hl: Label = ui.get("hover_label")
	out["before"] = hl.visible and hl.text != ""
	rm.change_room("O4", "default")
	out["after"] = hl.visible
	if not drop and not rm.room_changed.is_connected(cb):
		rm.room_changed.connect(cb)
	await _stop(main_node)
	return out


func _test_hover_drop() -> void:
	var r: Dictionary = await _caption_after_change(true)
	_check(bool(r["before"]), "the caption over Pelageya was not shown before the change (nothing to check)")
	_check(not bool(r["after"]), "right after the room change the far pier's caption is still over the street")
	var bad: Dictionary = await _caption_after_change(false)
	_check(bool(bad["before"]) and bool(bad["after"]), "self-check: without the drop the old caption was not seen over the new room (before %s, after %s)" % [str(bad["before"]), str(bad["after"])])


func _test_speaker_rule() -> void:
	var rule = load("res://tests/ghost_watch.gd")
	var place := Node2D.new()
	root.add_child(place)
	var hs := GDScript.new()
	hs.source_code = "extends Node2D\nvar hotspot_id := \"\"\n"
	hs.reload()
	var fig := Node2D.new()
	fig.name = "npc_tamara"
	place.add_child(fig)
	var pl := Node2D.new()
	place.add_child(pl)
	_check(rule.speaker_in_sight(place, "tamara", pl), "a villager in sight is not seen")
	fig.modulate.a = 0.0
	_check(not rule.speaker_in_sight(place, "tamara", pl), "a villager faded out (alpha 0) passes as in sight")
	fig.modulate.a = 1.0
	fig.visible = false
	_check(not rule.speaker_in_sight(place, "tamara", pl), "a hidden villager passes as in sight")
	_check(not rule.speaker_in_sight(place, "ulyana", pl), "a villager with no figure passes as in sight")
	_check(rule.speaker_in_sight(place, "agata", pl), "Agata (the player) in sight is not seen")
	pl.visible = false
	_check(not rule.speaker_in_sight(place, "agata", pl), "Agata hidden passes as in sight")
	var painted := Node2D.new()
	painted.set_script(hs)
	painted.set("hotspot_id", "manager")
	var img := Sprite2D.new()
	img.name = "Image"
	painted.add_child(img)
	place.add_child(painted)
	_check(rule.speaker_in_sight(place, "manager", null), "a painted figure (the hotspot's picture) is not seen")
	img.visible = false
	_check(not rule.speaker_in_sight(place, "manager", null), "a hotspot with its picture hidden passes as in sight")
	# where it judges: Agata shown — yes; no Agata and no villager's hotspot (the boat's view, a picture frame) — no
	pl.visible = true
	_check(rule.shows_people(place, pl), "a room with Agata in it is not judged")
	_check(not rule.shows_people(place, null), "a place with neither Agata nor a villager's hotspot is judged")
	place.queue_free()
	await process_frame


## A turn from `from_deg` to `to_deg` at frames of `dt` seconds for 12 s: the worst miss in the last 6 (degrees).
func _turn_miss(sliced: bool, dt: float, from_deg: float, to_deg: float, ease: float, cap_deg: float, accel_deg: float) -> float:
	var st := Vector4(deg_to_rad(from_deg), 0.0, 0.0, 0.0)
	var tgt := deg_to_rad(to_deg)
	var t := 0.0
	var miss := 0.0
	while t < 12.0:
		if sliced:
			st = Actor3D.turn_step(st, tgt, dt, deg_to_rad(cap_deg), ease, deg_to_rad(accel_deg))
		else:
			st = Actor3D.turn_step_slice(st, tgt, dt, deg_to_rad(cap_deg), ease, deg_to_rad(accel_deg))
		t += dt
		if t > 6.0:
			miss = maxf(miss, absf(rad_to_deg(angle_difference(st.x, tgt))))
	return miss


func _test_turn_settles() -> void:
	# villagers (NpcLive3D defaults: 240°/s, ease 7, 1100°/s²) — the council at the mill: from facing the camera to Pavel's
	# 92°, Ilya's −106°; Agata running (player.gd: 400°/s, ease 9, 1500°/s², ×speed 2)
	var kinds := [["villager", 7.0, 240.0, 1100.0], ["Agata running", 18.0, 800.0, 6000.0]]
	for k in kinds:
		for dt in [1.0 / 60.0, 1.0 / 30.0, 8.0 / 60.0, 0.3, 0.53, 1.0]:
			for to in [92.0, -106.0, 179.0]:
				var m := _turn_miss(true, dt, 0.0, to, float(k[1]), float(k[2]), float(k[3]))
				_check(m < 1.0, "%s, frames of %.3f s, 0° → %.0f°: still %.1f° off after 6 s" % [String(k[0]), dt, to, m])
	# the same frames of 30 a second turn as before (one slice) — the motion of the game is unchanged
	var a := Vector4(0.3, 1.2, 1.0, 0.0)
	var b1 := Actor3D.turn_step(a, 1.6, 1.0 / 30.0, deg_to_rad(240.0), 7.0, deg_to_rad(1100.0))
	var b2 := Actor3D.turn_step_slice(a, 1.6, 1.0 / 30.0, deg_to_rad(240.0), 7.0, deg_to_rad(1100.0))
	_check(b1.is_equal_approx(b2), "a frame of 1/30 s is not one slice: %s vs %s" % [str(b1), str(b2)])
	# self-check: the bots' frame (time scale 4 on a slow display) with the step until 17.11 — the villager swings
	var bad := _turn_miss(false, 0.53, 0.0, 92.0, 7.0, 240.0, 1100.0)
	_check(bad > 20.0, "self-check: the unsliced step at frames of 0.53 s settled (%.1f° off) — the check would not see the swing" % bad)


## The morning of day three in Mama's room, M21 talked, the notebooks read: the village list clicked — its words, then
## M21b. Returns {"nina_lines": Nina's lines of M21b seen, "over_paper": how many of them were said with a close-up open}.
func _m21b_lines() -> Dictionary:
	var out := {"nina_lines": 0, "over_paper": 0, "list_read_open": false}
	var main_node: Node = await _start("day3")
	for f in ["started_M21", "done_M21", "o3_read_notebooks"]:
		gs.set_flag(f, true)
	var vl := _hotspot("village_list")
	if vl == null:
		_fails.append("no village list in Mama's room (%s)" % (String(rm.current_room.room_id) if rm.current_room != null else "-"))
		await _stop(main_node)
		return out
	sr.interact(vl)
	var last := ""
	for g in 4000:
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if gs.has_flag("done_M21b"):
				break
			continue
		if sr.is_staging():
			continue
		var key := String(b.get("text", ""))
		if key != last:
			last = key
			# Agata reads the list aloud («Живых двадцать два…») — over the list itself, it is still open
			if String(b.get("text_key", "")) == "O3.village_list.use" or key.begins_with("Живых двадцать два"):
				for i in 3:
					await process_frame
				out["list_read_open"] = sr.view_open
			if String(sr.active_scene) == "M21b" and String(b.get("speaker", "")) == "nina":
				for i in 3:
					await process_frame
				out["nina_lines"] = int(out["nina_lines"]) + 1
				if sr.view_open:
					out["over_paper"] = int(out["over_paper"]) + 1
		for i in 6:
			await process_frame
		sr.advance()
	await _stop(main_node)
	return out


func _test_m21b_room() -> void:
	var r: Dictionary = await _m21b_lines()
	_check(int(r["nina_lines"]) >= 3, "M21b: %d lines of Mama seen (three at least)" % int(r["nina_lines"]))
	_check(int(r["over_paper"]) == 0, "M21b: %d of Mama's lines said over the village list" % int(r["over_paper"]))
	_check(bool(r["list_read_open"]), "the list was put away before Agata read it aloud («Живых двадцать два…» over the room)")
	# self-check: the scene as it was — no close_view — and the paper stays over the talk
	var sc: Dictionary = sd.scene("M21b")
	var keep = sc.get("close_view", null)
	sc.erase("close_view")
	var bad: Dictionary = await _m21b_lines()
	if keep != null:
		sc["close_view"] = keep
	_check(int(bad["over_paper"]) >= 3, "self-check: without close_view Mama's lines were not seen over the paper (%d of %d)" % [int(bad["over_paper"]), int(bad["nina_lines"])])
	# self-check 2: the list put away as the scene starts (the first try of 17.11 — before Agata's reading of it)
	var early := func(_id: String) -> void:
		sr.close_view()
	sr.scene_started.connect(early)
	var too_soon: Dictionary = await _m21b_lines()
	sr.scene_started.disconnect(early)
	_check(not bool(too_soon["list_read_open"]), "self-check: the list closed as the scene starts was not caught (Agata's reading still seen over it)")


func _click(at: Vector2) -> void:
	var win := root.get_final_transform() * at
	var m := InputEventMouseMotion.new()
	m.position = win
	m.global_position = win
	Input.parse_input_event(m)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = win
		ev.global_position = win
		Input.parse_input_event(ev)
		await process_frame


## The free day in Dunya's house (Mama is there from M22 on; in her room no more after M21b): the ribbon picked in the
## bag and a real click on Mama. `with_use` false — the house's item_use taken away (the data until the evening of 17.11).
func _ribbon_h1(with_use: bool) -> Dictionary:
	var out := {"in_bag_before": false, "braided": false, "in_bag_after": true, "view": ""}
	var main_node: Node = await _start("freewalk")
	for f in ["started_M23c", "done_M23c"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "from_H3")
	for i in 40:
		await process_frame
	for i in 900:   # whatever the house plays on entry
		if not sr.is_busy():
			break
		if not sr.current_beat.is_empty() and not sr.is_staging() and String(sr.current_beat.get("type", "")) != "options":
			sr.advance()
		await process_frame
	out["in_bag_before"] = gs.has_item("school_ribbon")
	var h := _hotspot("nina")
	if h == null:
		_fails.append("no Mama (hotspot nina) in Dunya's house on the free day")
		await _stop(main_node)
		return out
	var hd: Dictionary = h.get("data")
	var uses: Dictionary = hd.get("item_use", {})
	var keep = uses.get("school_ribbon", null)
	if not with_use:
		uses.erase("school_ribbon")
	sr.select_item("school_ribbon")
	var r: Array = hd.get("rect", [1342, 280, 125, 476])
	await _click(Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0))
	for i in 900:
		if gs.has_flag("ribbon_braided") or not sr.current_beat.is_empty():
			break
		await process_frame
	for i in 6:
		await process_frame
	out["braided"] = gs.has_flag("ribbon_braided")
	out["in_bag_after"] = gs.has_item("school_ribbon")
	out["view"] = String(sr.view.get("id", "")) if sr.view_open else ""
	if keep != null:
		uses["school_ribbon"] = keep
	sr.close_view()
	await _stop(main_node)
	return out


func _test_ribbon_h1() -> void:
	var r: Dictionary = await _ribbon_h1(true)
	_check(bool(r["in_bag_before"]), "the free day: the ribbon is not in the bag (start point freewalk)")
	_check(bool(r["braided"]), "a click with the ribbon on Mama in Dunya's house did not braid it")
	_check(not bool(r["in_bag_after"]), "the ribbon is still in the bag after Mama braided it")
	_check(String(r["view"]) == "ribbon_braid", "the close-up of the braiding did not open (%s)" % String(r["view"]))
	var bad: Dictionary = await _ribbon_h1(false)
	_check(not bool(bad["braided"]) and bool(bad["in_bag_after"]), "self-check: without the house's item_use the ribbon was braided anyway (%s)" % str(bad))


## Every close-up of the rooms' data with a title (a hotspot's view, an item's view on a hotspot, each page), opened as
## the game opens it: [{where, spec}].
func _titled_views() -> Array:
	var out: Array = []
	for rid in (sd.rooms as Dictionary).keys():
		for h in (sd.room(String(rid)).get("hotspots", []) as Array):
			var found: Array = []
			if h.get("view") is Dictionary:
				found.append(["%s.%s" % [rid, h.get("id")], h["view"]])
			var uses = h.get("item_use", {})
			if uses is Dictionary:
				for it in (uses as Dictionary).keys():
					var a = uses[it]
					if a is Dictionary and a.get("view") is Dictionary:
						found.append(["%s.%s+%s" % [rid, h.get("id"), it], a["view"]])
			for f in found:
				var v: Dictionary = f[1]
				var titled := String(v.get("title", "")) != ""
				for pg in v.get("pages", []):
					titled = titled or String((pg as Dictionary).get("title", "")) != ""
				if titled:
					out.append({"where": String(f[0]), "spec": v})
	return out


## The close-up open: per page, the title's lines, where its words run against the pictures' frames, the lowest frame.
func _title_layout(cv: Node, spec: Dictionary) -> Array:
	var rows: Array = []
	sr.open_view(spec, "")
	for i in 4:
		await process_frame
	var n: int = maxi(1, (spec.get("pages", []) as Array).size())
	for pi in n:
		if not (spec.get("pages", []) as Array).is_empty():
			cv.call("_show_page", pi)
			for i in 3:
				await process_frame
		var title: Label = cv.get("title_label")
		if title == null or title.text == "":
			continue
		var font := title.get_theme_font("font")
		var fsize := title.get_theme_font_size("font_size")
		var words := Rect2(title.position, Vector2(font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x,
			float(title.get_line_count()) * float(title.get_line_height())))
		var under := 0.0
		var lowest := 0.0
		for sh in cv.get("sheets"):
			var c := sh as Control
			if c == null or not String(c.name).begins_with("Picture") or not c.is_visible_in_tree():
				continue
			var fr := Rect2(c.position + (c.get_parent() as Control).position if c.get_parent() is Control else c.position, c.size).grow(16.0)
			if fr.intersects(words):
				under = maxf(under, minf(words.end.y, fr.end.y) - maxf(words.position.y, fr.position.y))
			lowest = maxf(lowest, fr.end.y)
		rows.append({"page": pi, "title": title.text, "lines": title.get_line_count(), "under": under, "lowest": lowest})
	sr.close_view()
	for i in 2:
		await process_frame
	return rows


func _test_titles_one_line() -> void:
	var main_node: Node = await _start("freewalk")
	var cv: Node = main_node.get_node_or_null("CloseupView")
	if cv == null:
		_fails.append("no CloseupView in the game scene")
		await _stop(main_node)
		return
	var seen := 0
	for lang in ["ru", "en"]:
		_set_subs(lang)
		for v in _titled_views():
			for row in await _title_layout(cv, v["spec"]):
				seen += 1
				_check(int(row["lines"]) == 1, "%s %s page %d: «%s» on %d lines" % [lang, v["where"], int(row["page"]), row["title"], int(row["lines"])])
				_check(float(row["under"]) <= 0.0, "%s %s page %d: «%s» runs %.0f px under its picture" % [lang, v["where"], int(row["page"]), row["title"], float(row["under"])])
				_check(float(row["lowest"]) <= 1004.0, "%s %s page %d: the picture's frame comes down to y %.0f — on the buttons (1010)" % [lang, v["where"], int(row["page"]), float(row["lowest"])])
	_set_subs("ru")
	_check(seen >= 20, "only %d titled close-up pages were seen" % seen)
	# self-check: Mitya's board with its picture where it stood until 17.11 (y 130) — the title wraps into two lines
	var board: Dictionary = {}
	for v in _titled_views():
		if String(v["where"]).begins_with("O4.mitya_board"):
			board = (v["spec"] as Dictionary).duplicate(true)
	if board.is_empty():
		_fails.append("self-check: no Mitya's board close-up in O4")
	else:
		(board["pictures"][0] as Dictionary)["rect"] = [260, 130, 1400, 0]
		var bad: Array = await _title_layout(cv, board)
		_check(not bad.is_empty() and int(bad[0]["lines"]) >= 2, "self-check: with the picture at y 130 the title did not wrap (%s)" % str(bad))
	await _stop(main_node)


func _test_ghost_rule() -> void:
	var rule = load("res://tests/ghost_watch.gd")
	_check(rule.out_of_sight_but_clickable(0.0, false, true), "a shown hotspot over an invisible standing figure is not caught")
	_check(not rule.out_of_sight_but_clickable(0.0, true, true), "a figure walking off (fading) is caught")
	_check(not rule.out_of_sight_but_clickable(1.0, false, true), "a visible figure is caught")
	_check(not rule.out_of_sight_but_clickable(0.0, false, false), "a figure whose hotspot is hidden is caught")


## The lines a scene shows under these flags (beat_allowed, as in the game), each with its voice id — in the order
## StoryRunner.start_scene gives them (a line, then its `then` follow-ups): [[line_id, speaker, text], …].
func _scene_beats(scene_id: String, flags: Array) -> Array:
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	var out: Array = []
	var lines: Array = sd.scene(scene_id).get("mandatory_lines", [])
	for i in lines.size():
		var ln: Dictionary = lines[i]
		if ln.has("options"):
			continue
		if String(ln.get("text", "")).strip_edges() != "" and sr.beat_allowed(ln):
			out.append(["%s_%d" % [scene_id, i], String(ln.get("speaker", "")), String(ln.get("text", ""))])
		var th: Array = ln.get("then", [])
		for k in th.size():
			if sr.beat_allowed(th[k]):
				out.append(["%s_%d_then%d" % [scene_id, i, k], String(th[k].get("speaker", "narrator")), String(th[k].get("text", ""))])
	gs.reset()
	return out


func _set_lang(v: String) -> void:
	var ls = load("res://scripts/core/language_settings.gd")
	ls.set_voice(v)
	ls.set_subtitles(v)
	sd.call("reload")
	root.get_node("VoiceDirector").call("reload_config")


## Director 17.11 «давай озвучим ок»: the epilogue keeps a trace of Mama's ribbon — a follow-up (`then`) of the dinner
## line M26 №16 under ribbon_braided, so no recorded position M26_<n> shifts; shown only when Mama braided the ribbon,
## right after the dinner line; voiced by the narrator in ru and en (VoiceDirector.line_status «ok»: the manifest has
## M26_16_then<k> of the line's current words and its file is there). Self-check — the same follow-up without its `if`
## would show without the ribbon.
func _test_epilogue_ribbon() -> void:
	var lines: Array = sd.scene("M26").get("mandatory_lines", [])
	_check(lines.size() == 38, "M26 keeps its 38 positions (%d) — the ribbon is a follow-up, not a line of its own" % lines.size())
	if lines.size() <= 16:
		return
	var dinner: Dictionary = lines[16]
	_check(String(dinner.get("text", "")).begins_with("Вечером ужинают"), "M26 №16 is the dinner line: «%s»" % String(dinner.get("text", "")).left(40))
	var th: Array = dinner.get("then", [])
	var k := -1
	for j in th.size():
		if (th[j].get("if", []) as Array).has("ribbon_braided"):
			_check(k == -1, "two follow-ups of the dinner under ribbon_braided")
			k = j
	_check(k >= 0, "no follow-up of the dinner line under ribbon_braided")
	if k < 0:
		return
	var sub: Dictionary = th[k]
	var lid := "M26_16_then%d" % k
	var text := String(sub.get("text", ""))
	_check(String(sub.get("speaker", "narrator")) == "narrator" and text.contains("лент"), "the follow-up is the narrator's, about the ribbon: «%s»" % text)
	var ids_with: Array = _scene_beats("M26", ["ribbon_braided"]).map(func(b): return b[0])
	var ids_without: Array = _scene_beats("M26", []).map(func(b): return b[0])
	var at := ids_with.find(lid)
	_check(at > 0 and String(ids_with[at - 1]) == "M26_16", "with the ribbon braided the line comes right after the dinner: %s" % str(ids_with.slice(maxi(at - 2, 0), at + 2)))
	_check(not ids_without.has(lid), "without the ribbon braided the epilogue has no ribbon line")
	_check(ids_with.size() == ids_without.size() + 1, "the ribbon adds this one line and changes nothing else (%d / %d)" % [ids_with.size(), ids_without.size()])
	# voiced, ru and en
	var vd: Node = root.get_node("VoiceDirector")
	for lang in ["ru", "en"]:
		_set_lang(lang)
		var t_lang := String(((sd.scene("M26").get("mandatory_lines", [])[16] as Dictionary).get("then", [])[k] as Dictionary).get("text", ""))
		_check(t_lang != "" and (lang == "ru") == (t_lang == text), "%s: the line's words «%s»" % [lang, t_lang])
		var st := String(vd.call("line_status", lid, t_lang))
		_check(st == "ok", "%s: the recording of %s is «%s», not ok" % [lang, lid, st])
		var e: Dictionary = (vd.get("manifest") as Dictionary).get(lid, {})
		_check(String(e.get("speaker", "")) == "narrator", "%s: %s is read by «%s», not the narrator" % [lang, lid, String(e.get("speaker", ""))])
	_set_lang("ru")
	# self-check: the same follow-up without its `if` would be shown without the ribbon — the check above sees the flag
	var bare: Dictionary = sub.duplicate(true)
	bare.erase("if")
	gs.reset()
	_check(sr.beat_allowed(bare), "self-check: without its `if` the follow-up is still not shown — the check above proves nothing")
	_check(not sr.beat_allowed(sub), "self-check: with nothing set the ribbon line is shown")
