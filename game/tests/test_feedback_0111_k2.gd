extends SceneTree
## Прохождение Директора 01.11, группа К2 + В (крупные планы, интерфейс, вода): строки 5, 8, 9, 15, 21, 23, 29, 31, 35,
## 45, 59, 71 и вода 7, 38, 39 (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md). Each check names the old value that failed it.
##   godot --headless --path game -s res://tests/test_feedback_0111_k2.gd   (ONLY=<substring> — matching tests)

var _results: Array = []
var _fails: Array[String] = []
var sd: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	var only := OS.get_environment("ONLY")
	if only != "" and not test_name.contains(only):
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
	sd = root.get_node("StoryData")
	await _test("стр. 8: text layers fit their rect (the signal board's carving no longer runs over the sky)", _test_text_layers_fit)
	await _test("стр. 9: signal board close-up — the sheet is the board's field, the title centred on it", _test_signal_board_centred)
	await _test("стр. 5: M1 sheet «Порядок на мельнице» bigger and centred on the yard board", _test_m1_sheet)
	await _test("стр. 15: bag — max at once over the game ≤ pockets", _test_bag_capacity)
	await _test("стр. 21: watch XII under the latch, hands count from the painted XII", _test_watch)
	await _test("стр. 23: door snow only behind windows", _test_door_snow)
	await _test("стр. 29: H4 fog veils the far bank", _test_h4_fog)
	await _test("стр. 31/35: examine crops: no wood or wall around the photo, drawing, plan and the office mirror", _test_examine_crops)
	await _test("стр. 35: mirror outline cuts the wall off the home mirror", _test_mirror_outline)
	await _test("стр. 45: lantern: no far caption", _test_lantern_caption)
	await _test("стр. 59: fishing — painted sprites, rod from the hand, «Ещё» beside «Хватит»", _test_fishing)
	await _test("стр. 71: windlass caption says what the plaques do", _test_windlass_caption)
	await _test("стр. 7: M1 water: no frame flip — the foam flows by the shader", _test_m1_water)
	await _test("стр. 38: sluice water alive (M4 flume, M1 race)", _test_sluice_water)
	await _test("стр. 39: shore laps (Z3 near water runs up and back, wet band)", _test_shore_laps)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("==== feedback 01.11 K2: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _room(id: String) -> Dictionary:
	return sd.room(id)


func _hotspot(room_id: String, id: String) -> Dictionary:
	for h in _room(room_id).get("hotspots", []):
		if String(h.get("id", "")) == id:
			return h
	return {}


func _ambient(room_id: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://data/story/ambient/%s.json" % room_id)
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func _water(room_id: String, id: String) -> Dictionary:
	for w in _ambient(room_id).get("water", []):
		if String(w.get("id", "")) == id:
			return w
	return {}


# --- tests -------------------------------------------------------------------------------------

func _test_text_layers_fit() -> void:
	for rid in sd.rooms.keys():
		for l in _room(String(rid)).get("layers", []):
			if l.has("image") or not l.has("text") or bool(l.get("wrap", true)):
				continue
			var r: Array = l.get("rect", [0, 0, 0, 0])
			var font: Font = UiTheme.font(String(l.get("font", "body_italic")))
			var fs := int(l.get("font_size", 16))
			for line in String(sd.text(String(l["text"]))).split("\n"):
				var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				# was: the K17 phrase in one line, ≈ 330 px in a 64 px rect
				_check(w <= float(r[2]) * 1.25 + 4.0, "%s/%s: line «%s» is %.0f px in a %d px rect" % [rid, l.get("id"), line, w, int(r[2])])


func _test_signal_board_centred() -> void:
	var v: Dictionary = _hotspot("R1", "instruction").get("view", {})
	var p: Dictionary = v.get("papers", [{}])[0]
	var r: Array = p.get("rect", [0, 0, 0, 0])
	var cx := float(r[0]) + float(r[2]) * 0.5
	# the board's smooth field on screen: x 494…1297 (centre 895.5); was rect [613, 266, 691, 559] → 958.5
	_check(absf(cx - 895.5) <= 3.0, "sheet centre x %.1f, board field centre 895.5" % cx)
	_check(float(r[0]) >= 490.0 and float(r[0]) + float(r[2]) <= 1300.0, "sheet inside the field: %s" % str(r))
	var t: Dictionary = p.get("blocks", [{}])[0]
	var tr: Array = t.get("rect", [0, 0, 0, 0])
	_check(String(t.get("align", "")) == "center" and absf(float(tr[0]) + float(tr[2]) * 0.5 - float(r[2]) * 0.5) <= 1.0, "title block centred on the sheet: %s" % str(tr))


func _test_m1_sheet() -> void:
	var l: Dictionary = {}
	for x in _room("M1").get("layers", []):
		if String(x.get("id", "")) == "schedule_sheet":
			l = x
	var sc := float(l.get("scale", 1.0))
	_check(sc >= 1.1, "the sheet is bigger (scale %.2f; was 1)" % sc)
	# the sheet's canvas centre (841.5, 316.5) after scale_pivot/offset vs the board field's centre (831.7, 321.7)
	var art := 1920.0 / 1672.0
	var off: Array = l.get("offset", [0, 0])
	var c := Vector2(841.5, 316.5) + Vector2(float(off[0]), float(off[1])) / art
	_check(c.distance_to(Vector2(831.7, 321.7)) <= 2.0, "sheet centre %s, field centre (831.7, 321.7)" % str(c))
	_check(123.0 * sc <= 157.0 and 65.0 * sc <= 90.0, "the sheet stays inside the field (×%.2f)" % sc)


## The most things in the bag at once along the story: each inventory item held from the main scene that grants it (or
## the scene that sets the flags its giver requires) until the scene by which its use must have happened (the scene of
## its item_use, or the first scene that grants/requires the flag the use sets). Mirrors /home/claude/work inv_sim.
func _test_bag_capacity() -> void:
	var order: Array[String] = []
	for id in sd.scene_order:
		if String(sd.scene(id).get("type", "")) == "main":
			order.append(String(id))
	var idx := {}
	for i in order.size():
		idx[order[i]] = i
	var set_by := {}
	var need_by := {}
	for s in order:
		var sc: Dictionary = sd.scene(s)
		var fl: Array = sc.get("grants", {}).get("flags", []).duplicate()
		fl.append("done_" + s)
		for f in fl:
			if not set_by.has(f):
				set_by[f] = idx[s]
			if not need_by.has(f):
				need_by[f] = idx[s]
		for f in sc.get("requires", {}).get("flags", []):
			if not need_by.has(f):
				need_by[f] = idx[s]
	for rid in sd.rooms.keys():
		var scs: Dictionary = _room(String(rid)).get("scenes", {})
		for sid in scs.keys():
			if not idx.has(sid):
				continue
			var cw = scs[sid].get("complete_when", [])
			for c in (cw if cw is Array else [cw]):
				for f in c.get("all", []) + c.get("any", []):
					if not set_by.has(f):
						set_by[f] = idx[sid]
					if not need_by.has(f):
						need_by[f] = idx[sid]
	var n := order.size()
	var inv: Array[String] = []
	for id in sd.items.keys():
		if bool(sd.items[id].get("inventory", false)):
			inv.append(String(id))
	var gain := {}
	var loss := {}
	for s in order:
		var sc: Dictionary = sd.scene(s)
		for it in sc.get("grants", {}).get("items", []):
			if inv.has(String(it)) and not gain.has(it):
				gain[it] = idx[s]
		for it in sc.get("consumes", []):
			loss[it] = mini(int(loss.get(it, n)), idx[s])
	for rid in sd.rooms.keys():
		var room: Dictionary = _room(String(rid))
		for h in room.get("hotspots", []) + room.get("exits", []):
			var u: Dictionary = h.get("use", {})
			for it in u.get("gives", []):
				if inv.has(String(it)) and not gain.has(it):
					var g := 0
					for f in u.get("requires", {}).get("flags", []):
						g = maxi(g, int(set_by.get(f, 0)))
					gain[it] = g
			var iu: Dictionary = h.get("item_use", {})
			for it in iu.keys():
				if not inv.has(String(it)) or not bool(iu[it].get("consumes", false)):
					continue
				var c := n
				if idx.has(String(iu[it].get("scene", ""))):
					c = mini(c, int(idx[String(iu[it]["scene"])]))
				var sets = iu[it].get("sets", [])
				for f in (sets if sets is Array else [sets]):
					if need_by.has(f):
						c = mini(c, int(need_by[f]))
				loss[it] = mini(int(loss.get(it, n)), c)
	var best := 0
	var at := ""
	var held_best: Array = []
	for i in n:
		var held: Array = []
		for it in inv:
			if int(gain.get(it, n)) <= i and int(loss.get(it, n)) > i:
				held.append(it)
		if held.size() > best:
			best = held.size()
			at = order[i]
			held_best = held
	print("        bag: at most %d at once (%s: %s), pockets %d" % [best, at, ", ".join(held_best), int(load("res://scripts/ui/inventory_bag.gd").get_script_constant_map()["SLOTS"])])
	_check(best >= 9, "the count sees the known peak (9 at M13; got %d)" % best)
	_check(best <= int(load("res://scripts/ui/inventory_bag.gd").get_script_constant_map()["SLOTS"]), "%d things at once (%s) > %d pockets (was 8)" % [best, at, int(load("res://scripts/ui/inventory_bag.gd").get_script_constant_map()["SLOTS"])])


func _test_watch() -> void:
	var w: Dictionary = sd.item("pocket_watch").get("examine", {}).get("watch", {})
	var twelve := float(w.get("dial_deg", 0.0)) + float(w.get("turn_deg", 0.0))
	# the dark latch on the case rim at 23.3° clockwise; the painted XII at 12.6° (was: hands from 0°, no turn)
	_check(absf(twelve - 23.3) <= 1.5, "XII drawn at %.1f°, the latch at 23.3°" % twelve)
	_check(absf(float(w.get("dial_deg", 0.0)) - 12.6) <= 1.5, "the hands count from the painted XII (dial_deg %.1f)" % float(w.get("dial_deg", 0.0)))
	var d := PocketWatchDial.new()
	d.configure(w)
	_check(absf(rad_to_deg(d.twelve_rad()) - twelve) < 0.01, "the dial takes it from the data")
	d.free()
	var m: Dictionary = _hotspot("H2", "bundle_nina").get("mechanic", {}).get("watch_dial", {})
	_check(is_equal_approx(float(m.get("turn_deg", 0.0)), float(w.get("turn_deg", -1.0))), "the same watch by mother's mirror is turned the same way")


func _test_door_snow() -> void:
	var wv: Dictionary = _hotspot("H3", "school_door").get("puzzle", {}).get("art", {}).get("winter_view", {})
	var win: Array = wv.get("windows", [])
	var reg: Array = wv.get("region", [0, 0, 1, 1])
	_check(win.size() >= 1, "window panes given (was: snow over the whole doorway)")
	var area := 0.0
	for r in win:
		_check(float(r[0]) >= 0 and float(r[1]) >= 0 and float(r[0]) + float(r[2]) <= float(reg[2]) and float(r[1]) + float(r[3]) <= float(reg[3]), "pane %s inside the crop" % str(r))
		_check(float(r[1]) + float(r[3]) <= float(reg[3]) * 0.5, "pane %s above the sill, not on the floor" % str(r))
		area += float(r[2]) * float(r[3])
	_check(area < float(reg[2]) * float(reg[3]) * 0.3, "snow on under 30 %% of the doorway")
	_check(not bool(wv.get("snow", {}).get("out", true)), "no flakes drifting out of the door (snow.out false)")


func _test_h4_fog() -> void:
	for f in _ambient("H4").get("fog", []):
		if String(f.get("id", "")).ends_with("_night"):
			continue
		var pr: Array = f.get("profile", [0, 0, 0, 0])
		# was density 0.62, core 350–372
		_check(float(f.get("density", 0.0)) >= 0.8, "%s: density %.2f" % [f.get("id"), float(f.get("density", 0.0))])
		_check(float(pr[1]) <= 340.0 and float(pr[2]) >= 378.0, "%s: core %s covers the far bank (y 340–378)" % [f.get("id"), str(pr)])


## Border pixels of the crop: paper is light (photo / drawing / plan); the office mirror's border is its dark frame, not
## the light plaster wall.
func _border_ok(path: String, rect: Rect2, paper: bool) -> float:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var good := 0
	var total := 0
	var r := Rect2i(rect)
	for i in 200:
		var t := float(i) / 199.0
		for p in [Vector2i(r.position.x + int(t * (r.size.x - 1)), r.position.y + 1), Vector2i(r.position.x + int(t * (r.size.x - 1)), r.end.y - 2),
				Vector2i(r.position.x + 1, r.position.y + int(t * (r.size.y - 1))), Vector2i(r.end.x - 2, r.position.y + int(t * (r.size.y - 1)))]:
			var c := img.get_pixelv(p)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			total += 1
			if paper and lum > 0.45:
				good += 1
			elif not paper and lum < 0.5:
				good += 1
	return float(good) / float(total)


func _test_examine_crops() -> void:
	for id in ["photo_bridge", "drawing_ilya", "plan_crossing", "mirror_mill"]:
		var ex: Dictionary = sd.item(id).get("examine", {})
		var path := String(ex.get("art", ""))
		var tex: Texture2D = load(path)
		var rect := Rect2(Vector2.ZERO, tex.get_size())
		if ex.has("crop"):   # the same rule as ItemExamine.crop_rect
			var c: Array = ex["crop"]
			rect = Rect2(float(c[0]) * tex.get_size().x, float(c[1]) * tex.get_size().y, float(c[2]) * tex.get_size().x, float(c[3]) * tex.get_size().y)
		elif ex.has("region"):
			var g: Array = ex["region"]
			rect = Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3]))
		var ok := _border_ok(path, rect, id != "mirror_mill")
		# was: the whole art — table wood on every side (≈ 0 % paper on the border)
		_check(ok >= 0.95, "%s: %.0f %% of the crop's border is the thing itself" % [id, ok * 100.0])


func _test_mirror_outline() -> void:
	var fr: Dictionary = _hotspot("H3", "mirror_home").get("view", {}).get("frame", {})
	var ol: Array = fr.get("outline", [])
	_check(ol.size() >= 4 and ol.size() <= 48, "the outline is given (%d points; was none — the wall faded out)" % ol.size())
	var mg: Array = fr.get("margin", [0, 0, 0, 0])
	var gl: Array = fr.get("glass", [0, 0])
	var cw := float(mg[0]) + float(gl[0]) + float(mg[2])
	var ch := float(mg[1]) + float(gl[1]) + float(mg[3])
	var poly := PackedVector2Array()
	for p in ol:
		poly.append(Vector2(float(p[0]), float(p[1])))
		_check(float(p[0]) >= 0 and float(p[0]) <= cw and float(p[1]) >= 0 and float(p[1]) <= ch, "point %s inside the canvas" % str(p))
	_check(Geometry2D.is_point_in_polygon(Vector2(float(mg[0]) + float(gl[0]) * 0.5, float(mg[1]) + float(gl[1]) * 0.5), poly), "the glass is inside the outline")
	_check(not Geometry2D.is_point_in_polygon(Vector2(4, 4), poly), "the wall corner is outside")


func _test_lantern_caption() -> void:
	var m: Dictionary = _hotspot("R1", "lantern").get("mechanic", {})
	_check(not m.is_empty(), "the lantern close-up is there")
	_check(not m.has("far_label_pos"), "no «Тот берег» caption (far_label_pos was [1250, 250])")


func _fishing_spec() -> Dictionary:
	for o in _hotspot("R3", "mitya").get("choice", {}).get("options", []):
		if o.get("mechanic", {}).get("type", "") == "fishing":
			return o["mechanic"]
	return {}


func _test_fishing() -> void:
	var sp := _fishing_spec()
	_check(not sp.is_empty(), "the fishing spec")
	var ag: Array = sp.get("again_at", [40, 250])
	# «Хватит» — MechanicView's own button at (1680, 990), 200 × 56; «Ещё» was at (40, 250)
	_check(absf(float(ag[1]) - 990.0) <= 4.0 and float(ag[0]) + 200.0 <= 1680.0 and 1680.0 - (float(ag[0]) + 200.0) <= 40.0, "«Ещё» %s right beside «Хватит»" % str(ag))
	var fl: Array = sp.get("float", [0, 0])
	_check(float(fl[0]) < 1400.0 and float(fl[0]) > 1280.0 and float(fl[1]) < 711.0, "Agata's float just past the stones, left of the jetty, above the boat layer (%s; was [1630, 643] — the line across Mitya)" % str(fl))
	var fp = load("res://scripts/mechanics/fishing_panel.gd").new()
	fp.spec = sp
	root.add_child(fp)
	fp.build()
	var tex: Dictionary = fp.get("_tex")
	for id in ["float", "float_tilted", "perch_caught", "perch_lying"]:
		_check(tex.has(id) and tex[id]["tex"] is Texture2D, "sprite %s loaded (was: shapes drawn by the engine)" % id)
	var tip: Vector2 = fp.rod_tip(Vector2(800, 540), Vector2(float(fl[0]), float(fl[1])), 220.0)
	var ang := rad_to_deg(atan2(-(tip.y - 540.0), tip.x - 800.0))
	_check(ang > 25.0 and ang < 55.0 and tip.distance_to(Vector2(800, 540)) > 200.0, "the rod held up towards the water (%.0f°, %.0f px)" % [ang, tip.distance_to(Vector2(800, 540))])
	fp.queue_free()
	var a3 = load("res://scripts/actors/actor_3d.gd")
	_check(a3 != null and (a3 as Script).get_script_method_list().any(func(m): return m.name == "bone_frame_px"), "Actor3D gives a bone's place in its frame (the rod from her hand)")


func _test_windlass_caption() -> void:
	var t := String(sd.text("@E5.windlass.label_board"))
	_check(t != "Дощечка Пелагеи" and t.contains("Илье"), "the caption says what the plaques do: «%s»" % t)


func _test_m1_water() -> void:
	for l in _room("M1").get("layers", []):
		if String(l.get("id", "")) == "wheel_water":
			_check(not l.has("frames"), "no 3-frame flip under the wheel (was water_1…3 at 7 fps)")
	var w := _water("M1", "wheel_foam")
	_check(String(w.get("source", "")) == "layer:wheel_water", "the foam is the water shader's (source layer:wheel_water)")
	var fl: Array = w.get("flow", [0, 0])
	_check(float(fl[0]) < -40.0, "it flows left with the race (%s)" % str(fl))
	_check(float(w.get("streaks", 0.0)) >= 0.5, "foam lines run")
	# no frame loop anywhere is a hard flip faster than the eye takes for motion
	for rid in sd.rooms.keys():
		for l in _room(String(rid)).get("layers", []):
			if l.has("frames"):
				_check(float(l.get("fps", 7.0)) <= 2.0, "%s/%s: a hard frame loop at %s fps" % [rid, l.get("id"), str(l.get("fps", 7.0))])


func _test_sluice_water() -> void:
	var h := _water("M4", "flume_held")
	var rp: Array = h.get("ripple_px", [0, 0])
	# was ripple [0.8, 1.6], tremble 0.8, sparkle 0.2, the lower third of the flume not covered
	_check(float(rp[1]) >= 3.0 and float(h.get("tremble_px", 0.0)) >= 1.5, "held water breathes: ripple %s, tremble %.1f" % [str(rp), float(h.get("tremble_px", 0.0))])
	_check(float(h.get("sparkle", 0.0)) >= 0.5 and float(h.get("streaks", 0.0)) >= 0.25, "glints and slow lines on it")
	var maxy := 0.0
	for p in h.get("polygon", []):
		maxy = maxf(maxy, float(p[1]))
	_check(maxy >= 1075.0, "the flume animated down to the frame's bottom (%.0f)" % maxy)
	var r := _water("M1", "race")
	_check(float(r.get("tremble_px", 0.0)) >= 1.8, "the mill race at the gate trembles (%.1f)" % float(r.get("tremble_px", 0.0)))


func _test_shore_laps() -> void:
	var w := _water("Z3", "near_water")
	# was lap 0.8 over 12 px — the edge moved 3–6 px
	_check(float(w.get("lap", 0.0)) >= 1.0 and float(w.get("lap_px", 0.0)) >= 20.0, "the wave runs up the bank ≥ 20 px (lap %.1f, %.0f px)" % [float(w.get("lap", 0.0)), float(w.get("lap_px", 0.0))])
	_check(float(w.get("lap_wet", 0.0)) > 0.0, "the bank stays wet behind it")
	var per := float(w.get("lap_period_s", 0.0))
	_check(per >= 3.0 and per <= 6.0, "a slow surf rhythm (%.1f s)" % per)
	var sh := FileAccess.get_file_as_string("res://shaders/ambient_water.gdshader")
	_check(sh.contains("lap_wet") and sh.contains("fract(t / max(lap_period"), "the shader runs the wave in and out (no seam: fract of a continuous time, smooth both ends)")
