extends SceneTree
## Group D of the Director's playthrough 01.11 (Docs/FEEDBACK_DIRECTOR_2026-11-01_map.md; «стр.» — a line of
## Docs/FEEDBACK_DIRECTOR_2026-11-01_raw.txt) — figure motion, the part done before the models' own pass:
##   стр. 56: Nina walks over to Tamara (M23a) half as fast as before — 2.6 → 5.2 s for the same way;
##   стр. 61, 68: a figure in a composed frame (the door, the workshop, the lesson, the council at the mill with the
##     manager) is not a still picture: it plays its sheet's clips (compose.anim, tools/make_frame_layers.py → atlas,
##     StateLayer, game/shaders/frame_anim.gdshader) — the rest clip all the time (the shown sheet frame changes), and
##     the one whose line is being said plays the talk clip (hands, head, mouth) — cells the rest clip never shows; the
##     others stay in their rest clip; when the line is over it goes back. A figure without a talk clip (Agata) moves
##     its head with the words (warp). Self-check: the old still / warp-only layer (no anim) fails these checks.
##   02.11 (the same lines, the talk clip itself; Docs/tasks/frame_talk_sheets.json): the villagers' sheet talk clip stood
##     in another stance (legs 10–12 cm forward, soles higher, torso leaning back) — on the rest → talk dissolve the legs
##     crossfaded (a step) and late in the gesture the body leaned. Now the talk clip of every frame figure keeps the legs
##     of its rest frame (lower third of the silhouette: IoU with the rest frame 0 ≥ LEGS_IOU_MIN in every talk cell),
##     starts in the rest pose (talk cell 0 ≈ rest cell 0) and does not lean: the talk action of the sheet is the clip
##     derived from the raw one (sprites.json actions.<talk>.derived, tools/render_sheet_clips.py: hips and legs of the
##     stance, spine 0.3 of the clip) and its measured torso tilt from the stance (hips → neck, in 3D) is ≤ TILT_MAX_DEG
##     (the raw clip's — 5–8°); Agata in the frames has her own talk clip (agata_frames) and gestures with her line
##     instead of the warp. Self-check: the old atlas cells (tests/fixtures/frame_talk_raw_pavel_anim.png — the raw talk
##     clip as it was in F_mill_manager) fail the legs check; the raw clip's own tilt (derived.source_torso_tilt_max_deg)
##     fails the tilt check.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_feedback_0111_d.gd
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var main_node: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	var only := OS.get_environment("ONLY")
	if only != "":
		var hit := false
		for w in only.split(","):
			hit = hit or test_name.contains(w)
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	await _test("стр. 56: Nina walks to Tamara in M23a half as fast (5.2 s, was 2.6)", _test_nina_pace)
	await _test("стр. 61, 68: frame figures play their sheet clips; the speaker plays the talk gesture, the others do not", _test_frame_life)
	await _test("02.11 frame talk clips: legs stay in the rest stance (no step on the dissolve), no lean, start in the rest pose", _test_talk_stance)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("==== Feedback 01.11 group D: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


static func nina_go_s(doc: Dictionary) -> float:
	for s in doc.get("scenes", []):
		if String(s.get("id", "")) != "M23a":
			continue
		for st in s.get("stage", []):
			for g in st.get("npc_go", []):
				if String(g.get("id", "")) == "nina" and String(g.get("face", "")) == "tamara":
					return float(g.get("s", 0.0))
	return -1.0


func _test_nina_pace() -> void:
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/scenes/E4.json"))
	var s := nina_go_s(doc)
	_check(s >= 5.0, "M23a: Nina's walk to Tamara takes %.1f s (the Director: half as fast as 2.6 s → 5.2)" % s)
	# self-check: the old staging is caught
	var old := {"scenes": [{"id": "M23a", "stage": [{"npc_go": [{"id": "nina", "to": [575, 790], "s": 2.6, "face": "tamara"}]}]}]}
	_check(nina_go_s(old) < 5.0, "self-check: the old 2.6 s walk is not caught")


func _life_layers(fv: Node) -> Dictionary:
	var out := {}
	if fv == null or fv.room == null:
		return out
	for l in fv.room.get_node("Layers").get_children():
		if l.get("life_mat") != null:
			out[String(l.get("life_char"))] = l
	return out


## The cells a layer shows over `seconds` (sampled every few frames); -1 — a still picture (no sheet clips).
func _sample_cells(layers: Array, seconds: float) -> Dictionary:
	var out := {}
	for l in layers:
		out[l] = []
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _frames(3)
		for l in layers:
			out[l].append(int(l.call("anim_cell")) if l.has_method("anim_cell") else -1)
	return out


## The figure plays its sheet: every sample is a sheet frame and at least `min_distinct` different frames were shown.
static func plays_sheet(cells: Array, min_distinct: int = 3) -> bool:
	var seen := {}
	for c in cells:
		if int(c) < 0:
			return false
		seen[int(c)] = true
	return seen.size() >= min_distinct


## Every sample lies in the clip [first, first + frames) of the atlas description `meta`.
static func all_in_clip(cells: Array, meta: Dictionary, role: String) -> bool:
	var cl: Dictionary = meta.get("clips", {}).get(role, {})
	if cl.is_empty() or cells.is_empty():
		return false
	for c in cells:
		if int(c) < int(cl["first"]) or int(c) >= int(cl["first"]) + int(cl["frames"]):
			return false
	return true


func _test_frame_life() -> void:
	var fv = main_node.find_child("FrameView", true, false)
	_check(fv != null, "no FrameView")
	if fv == null:
		return
	# every composed figure of every frame comes alive (the data say who is drawn: compose.char); one with clips
	# (compose.anim) plays its atlas, the still picture hidden
	var dir := DirAccess.open("res://data/story/rooms")
	var frames: Array = []
	for f in dir.get_files():
		if f.ends_with(".json") and (f.begins_with("F_") or f.begins_with("EP_")):
			frames.append(f.get_basename())
	frames.sort()
	var nina_frames: Array = []
	for fid in frames:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/%s.json" % fid))
		var chars: Array = []
		var animated: Array = []
		for l in doc.get("layers", []):
			var c = l.get("compose", {})
			if c is Dictionary and String(c.get("char", "")) != "" and not (l.get("life", true) is bool and not l.get("life", true)):
				chars.append(String(c["char"]))
				if c.has("anim"):
					animated.append(String(c["char"]))
		if chars.has("nina"):
			nina_frames.append(fid)
		sr.set_frame(fid, false)
		await _frames(2)
		var live := _life_layers(fv)
		for ch in chars:
			_check(live.has(ch), "%s: the figure %s is a still picture (no life)" % [fid, ch])
		for ch in animated:
			if live.has(ch):
				var l = live[ch]
				_check(not (l.get("anim") as Dictionary).is_empty(), "%s: %s has compose.anim but plays no atlas (tools/make_frame_layers.py)" % [fid, ch])
				var img := l.get_node_or_null("Image") as CanvasItem
				_check(img == null or not img.visible, "%s: %s — the still picture is drawn over the clip" % [fid, ch])
	# стр. 61: Nina in every frame she is in (the door, the workshop, the lesson) plays her rest clip — the shown
	# sheet frame changes over time
	_check(nina_frames.size() >= 3, "frames with Nina: %s (the door, the workshop, the lesson expected)" % [nina_frames])
	for fid in nina_frames:
		sr.set_frame(fid, false)
		await _frames(2)
		var live := _life_layers(fv)
		if not live.has("nina"):
			continue
		var smp := await _sample_cells([live["nina"]], 1.5)
		var cells: Array = smp[live["nina"]]
		_check(plays_sheet(cells), "%s: Nina is still — shown sheet frames %s" % [fid, _uniq(cells)])
		_check(all_in_clip(cells, live["nina"].anim, "rest"), "%s: no line of hers, but Nina is not in her rest clip" % fid)
	# стр. 68: the council at the mill (M23b) — whoever's line it is plays the talk clip, the others stay at rest
	sr.set_frame("F_mill_manager", false)
	await _frames(3)
	var live := _life_layers(fv)
	_check(live.size() == 4, "F_mill_manager: %d live figures (pavel, manager, ilya, agata expected)" % live.size())
	var all_l: Array = live.values()
	var quiet := await _sample_cells(all_l, 1.2)
	for ch in live:
		_check(plays_sheet(quiet[live[ch]]), "F_mill_manager: %s is still at rest — frames %s" % [ch, _uniq(quiet[live[ch]])])
	for speaker in ["manager", "pavel", "ilya"]:
		if not live.has(speaker):
			continue
		var m = live[speaker]
		_check(m.anim.get("clips", {}).has("talk"), "%s: no talk clip in the frame atlas" % speaker)
		# 02.11: the gesture is the stance-kept clip of the sheet (derived: legs of the stance, spine 0.3), not the raw
		# clip — for the manager too (manager_v2 talk2, no longer the v1 sheet's rare 16-frame Listening_Gesture)
		var tk: Dictionary = m.anim.get("clips", {}).get("talk", {})
		_check(not sheet_action(String(m.anim.get("sheet", "")), String(tk.get("action", ""))).get("derived", {}).is_empty(), "%s: the talk clip %s/%s is not the stance-kept one" % [speaker, m.anim.get("sheet"), tk.get("action")])
		_check(int(tk.get("frames", 0)) >= 24 and not bool(tk.get("blend", false)), "%s: the talk clip has %d frames%s — a rare gesture" % [speaker, int(tk.get("frames", 0)), " with dissolves" if bool(tk.get("blend", false)) else ""])
		sr.current_beat = {"type": "line", "speaker": speaker, "text": "Год рычаг провисел — проверка: эта реплика длинная, её говорят."}
		await create_timer(0.6).timeout   # anim_talk_in_s 0.25
		_check(m.life_talk > 0.9, "%s's own line: the talk clip has not come in (talk %.2f)" % [speaker, m.life_talk])
		var smp := await _sample_cells(all_l, 1.5)
		_check(all_in_clip(smp[m], m.anim, "talk") and plays_sheet(smp[m], 2), "%s's own line: he does not gesture — shown frames %s (talk clip %s)" % [speaker, _uniq(smp[m]), m.anim.get("clips", {}).get("talk", {})])
		for other in live:
			if other == speaker:
				continue
			_check(all_in_clip(smp[live[other]], live[other].anim, "rest") and float(live[other].life_talk) < 0.01, "%s gestures with %s's words — frames %s" % [other, speaker, _uniq(smp[live[other]])])
		sr.current_beat = {}
		await create_timer(1.0).timeout   # anim_talk_out_s 0.4
		var after := await _sample_cells([m], 0.5)
		_check(m.life_talk < 0.01 and all_in_clip(after[m], m.anim, "rest"), "%s: line over — still gesturing (talk %.2f, frames %s)" % [speaker, m.life_talk, _uniq(after[m])])
	# Agata (02.11: her own talk clip, agata_frames) gestures with her line like the others, the rest stay at rest
	if live.has("agata"):
		var a = live["agata"]
		_check(a.anim.get("clips", {}).has("talk"), "Agata: no talk clip in the frame atlas (agata_frames)")
		sr.current_beat = {"type": "line", "speaker": "agata", "text": "Помню, Павел. Наберём — только сперва мост поставить надо."}
		await create_timer(0.6).timeout
		var asmp := await _sample_cells(all_l, 1.5)
		_check(a.life_talk > 0.9 and all_in_clip(asmp[a], a.anim, "talk") and plays_sheet(asmp[a], 2), "Agata's own line: she does not gesture — shown frames %s (talk %.2f)" % [_uniq(asmp[a]), a.life_talk])
		for other in live:
			if other != "agata":
				_check(all_in_clip(asmp[live[other]], live[other].anim, "rest"), "%s gestures with Agata's words" % other)
		sr.current_beat = {}
		await create_timer(1.0).timeout
	# two figures do not move in step
	if live.has("manager") and live.has("pavel"):
		_check(absf(float(live["manager"]._anim_phase) - float(live["pavel"]._anim_phase)) > 0.05, "the manager and Pavel move in step")
	# self-check: the old layer — the same figure as a still picture with the warp only (no compose.anim) — fails
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/F_mill_manager.json"))
	var old_l: Dictionary = {}
	for l in doc["layers"]:
		if String(l.get("id", "")) == "manager":
			old_l = (l as Dictionary).duplicate(true)
	old_l["compose"].erase("anim")
	var old_layer = load("res://scripts/rooms/state_layer.gd").new()
	var spr := Sprite2D.new()
	spr.name = "Image"
	spr.texture = load(String(old_l["image"]))
	old_layer.add_child(spr)
	fv.room.get_node("Layers").add_child(old_layer)
	old_layer.setup(old_l)
	sr.current_beat = {"type": "line", "speaker": "manager", "text": "Проверка старого слоя."}
	var old_smp := await _sample_cells([old_layer], 0.8)
	_check(old_layer.life_mat != null, "self-check: the old warp layer was not built")
	_check(not plays_sheet(old_smp[old_layer]), "self-check: the old still/warp figure passes as playing its sheet")
	_check(not all_in_clip(old_smp[old_layer], live.get("manager", old_layer).anim, "talk"), "self-check: the old still/warp figure passes as gesturing")
	_check(not plays_sheet([5, 5, 5, 5]) and not plays_sheet([-1, -1, -1]), "self-check: a frozen frame passes as playing")
	# self-check: the manager's old talk clip (v1 sheet: 16 frames over 9 s with dissolves, raw Listening_Gesture) fails
	var old_tk := {"action": "talk", "frames": 16, "fps": 3.4, "blend": true}
	_check(not (int(old_tk["frames"]) >= 24 and not bool(old_tk["blend"])), "self-check: the v1 manager's rare gesture passes")
	_check(sheet_action("manager", "talk").get("derived", {}).is_empty(), "self-check: the v1 manager's raw clip passes as stance-kept")
	sr.current_beat = {}
	old_layer.queue_free()
	sr.set_frame("", false)
	await _frames(2)


const LEGS_IOU_MIN := 0.9
const START_IOU_MIN := 0.9
const TILT_MAX_DEG := 3.0
## Figures on sheets the 02.11 re-render did not reach (Docs/tasks/frame_talk_sheets.json): their talk legs are the
## stance already (the legs check holds), the lean is not measured — no derived clip. The manager (Лукич) is on
## manager_v2 since 02.11: listen (Pavel's, retargeted) and talk2 (Talk_with_Hands_Open, stance-kept) — checked.
const LEAN_OPEN := {"tamara": "лист tamara_v3 вне задания 02.11"}


## The sheet's description of an action (the game copy game/assets/characters/<set>/sprites.json; read as a file —
## the folder is not imported).
static func sheet_action(sheet_set: String, action: String) -> Dictionary:
	var sp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/%s/sprites.json" % sheet_set))
	if not (sp is Dictionary):
		return {}
	return (sp as Dictionary).get("actions", {}).get(action, {})


## Alpha masks (alpha >= 128) of atlas cells, sampled every `step` px: {w, h, m: PackedByteArray}.
static func _cell_mask(data: PackedByteArray, iw: int, meta: Dictionary, k: int, step: int) -> Dictionary:
	var cw := int(meta["cell"][0])
	var ch := int(meta["cell"][1])
	var cols := int(meta["cols"])
	var gap := int(meta["gap"])
	var x0 := (k % cols) * (cw + gap)
	var y0 := (k / cols) * (ch + gap)
	var w := cw / step
	var h := ch / step
	var m := PackedByteArray()
	m.resize(w * h)
	for y in h:
		var row := ((y0 + y * step) * iw + x0) * 4 + 3
		for x in w:
			m[y * w + x] = 1 if data[row + x * step * 4] >= 128 else 0
	return {"w": w, "h": h, "m": m}


static func _rows_box(mk: Dictionary) -> Vector2i:
	var w: int = mk["w"]
	var top := -1
	var bottom := -1
	for y in int(mk["h"]):
		for x in w:
			if mk["m"][y * w + x] == 1:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(top, bottom)


static func _band_mid_x(mk: Dictionary, y_from: int, y_to: int) -> float:
	var w: int = mk["w"]
	var lo := w
	var hi := -1
	for y in range(maxi(0, y_from), mini(int(mk["h"]), y_to)):
		for x in w:
			if mk["m"][y * w + x] == 1:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	return (lo + hi) / 2.0 if hi >= 0 else -1.0


static func _band_iou(a: Dictionary, b: Dictionary, y_from: int, y_to: int) -> float:
	var w: int = a["w"]
	var inter := 0
	var uni := 0
	for y in range(maxi(0, y_from), mini(int(a["h"]), y_to)):
		for x in w:
			var i := y * w + x
			var p: int = a["m"][i]
			var q: int = b["m"][i]
			inter += p & q
			uni += p | q
	return float(inter) / float(maxi(uni, 1))


## Talk clip vs the rest stance in a frame atlas (<image>_anim.png + its description): legs — the lower 35 % of the
## rest frame 0 silhouette, IoU of every talk cell with it (min); start — IoU of the whole talk cell 0 with rest cell 0;
## lean — the sideways shift of the head (top eighth) from the rest frame 0, share of the height (max).
static func talk_stance_metrics(img: Image, meta: Dictionary) -> Dictionary:
	var cl: Dictionary = meta.get("clips", {})
	if not cl.has("talk") or not cl.has("rest"):
		return {}
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var step := maxi(1, int(meta["cell"][1]) / 200)
	var r0 := _cell_mask(data, img.get_width(), meta, int(cl["rest"]["first"]), step)
	var rb := _rows_box(r0)
	var hgt := float(rb.y - rb.x)
	var legs_from := int(rb.y - 0.35 * hgt)
	var head_to := int(rb.x + hgt / 8.0)
	var head0 := _band_mid_x(r0, rb.x, head_to)
	var legs_min := 1.0
	var dx_max := 0.0
	var start := 0.0
	for i in int(cl["talk"]["frames"]):
		var t := _cell_mask(data, img.get_width(), meta, int(cl["talk"]["first"]) + i, step)
		legs_min = minf(legs_min, _band_iou(t, r0, legs_from, rb.y + 1))
		var tb := _rows_box(t)
		dx_max = maxf(dx_max, absf(_band_mid_x(t, tb.x, tb.x + int(hgt / 8.0)) - head0) / hgt)
		if i == 0:
			start = _band_iou(t, r0, 0, int(t["h"]))
	return {"legs_iou_min": legs_min, "head_dx_max": dx_max, "start_iou": start}


func _test_talk_stance() -> void:
	var dir := DirAccess.open("res://data/story/rooms")
	var seen := 0
	var agata_talk := 0
	for f in dir.get_files():
		if not (f.ends_with(".json") and (f.begins_with("F_") or f.begins_with("EP_"))):
			continue
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/" + f))
		for l in doc.get("layers", []):
			var c = l.get("compose", {})
			if not (c is Dictionary and c.has("anim") and c.has("char")):
				continue
			var ch := String(c["char"])
			var where := "%s.%s" % [doc.get("id", f), l.get("id", "")]
			if not (c["anim"] as Dictionary).has("talk"):
				_check(ch != "agata", "%s: Agata has no talk clip (agata_frames talk)" % where)
				continue
			var base := String(l["image"]).get_basename()
			var meta = JSON.parse_string(FileAccess.get_file_as_string(base + "_anim.json"))
			var img := Image.load_from_file(ProjectSettings.globalize_path(base + "_anim.png"))
			if meta == null or img == null:
				_check(false, "%s: no frame atlas %s_anim.png" % [where, base])
				continue
			var mt := talk_stance_metrics(img, meta)
			seen += 1
			agata_talk += 1 if ch == "agata" else 0
			print("        %s (%s): legs IoU min %.3f, start IoU %.3f" % [where, (meta["clips"]["talk"] as Dictionary).get("action", ""), mt["legs_iou_min"], mt["start_iou"]])
			_check(float(mt["legs_iou_min"]) >= LEGS_IOU_MIN, "%s: the legs of the talk clip are not the rest stance (IoU %.3f < %.2f) — they step on the dissolve" % [where, mt["legs_iou_min"], LEGS_IOU_MIN])
			if LEAN_OPEN.has(ch):
				continue
			_check(float(mt["start_iou"]) >= START_IOU_MIN, "%s: the talk clip does not start in the rest pose (IoU %.3f)" % [where, mt["start_iou"]])
			var der: Dictionary = sheet_action(String(meta.get("sheet", "")), String(meta["clips"]["talk"]["action"])).get("derived", {})
			_check(not der.is_empty(), "%s: the talk clip %s/%s is the raw clip (no derived: hips, legs and spine as in the clip)" % [where, meta.get("sheet"), meta["clips"]["talk"]["action"]])
			if not der.is_empty():
				_check(der.has("torso_tilt_max_deg") and float(der["torso_tilt_max_deg"]) <= TILT_MAX_DEG, "%s: the body leans in the talk clip (%s° > %.1f°)" % [where, der.get("torso_tilt_max_deg"), TILT_MAX_DEG])
				# self-check: the raw clip's own tilt fails the same bound
				_check(float(der.get("source_torso_tilt_max_deg", 0.0)) > TILT_MAX_DEG, "self-check: %s — the raw clip's tilt %s° passes the lean bound" % [where, der.get("source_torso_tilt_max_deg")])
	_check(seen >= 10, "frame figures with a talk clip: %d (≥ 10 expected)" % seen)
	_check(agata_talk >= 4, "Agata's talk clip in %d frames (the council, the gallery, the span, the lesson expected)" % agata_talk)
	# self-check: the raw talk clip as it was (F_mill_manager.pavel, commit 7ba00368) fails the legs and the lean checks
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/frame_talk_raw_pavel_anim.json"))
	var fimg := Image.load_from_file(ProjectSettings.globalize_path("res://tests/fixtures/frame_talk_raw_pavel_anim.png"))
	var old := talk_stance_metrics(fimg, fx)
	_check(not old.is_empty() and float(old["legs_iou_min"]) < LEGS_IOU_MIN, "self-check: the raw talk clip's legs pass as the stance (IoU %s)" % [old.get("legs_iou_min")])
	_check(not old.is_empty() and float(old["start_iou"]) < START_IOU_MIN, "self-check: the raw talk clip passes as starting in the rest pose (IoU %s)" % [old.get("start_iou")])


func _uniq(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if not out.has(c):
			out.append(c)
	return out
