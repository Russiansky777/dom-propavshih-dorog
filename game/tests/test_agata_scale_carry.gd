extends SceneTree
## G56 + G10 (Director 23.10, Docs/FEEDBACK_DIRECTOR_2026-10-23b.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_agata_scale_carry.gd [-- --write-baseline]
##   - G56: Agata's sheets are rendered k× larger (sprites.json texture_scale); the sprite draws them at 1/k, so her
##     height on screen in every room is the one she had on the 384-px sheets (±1 px, tests/agata_height_baseline.json,
##     measured on rev 9 before the re-render); px per metre, the shadow and the stride stay in unit px;
##   - G10: the wet kerchief in H1 — pick at the bench (the bench goes bare, no flag yet) → walk to the hanger by the
##     door → reach → the kerchief on the left hook, the flag and the text (and M03 when due) once; a click on the way gives the same
##     result at once.
## --write-baseline: re-measure the baseline from the sheets in the game now (only on the old 384-px sheets).
## Exit code 0 only when every check passed.

const BASELINE := "res://tests/agata_height_baseline.json"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var main_node: Node = null
var player: Node2D = null


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
	gs.reset()
	if OS.get_cmdline_user_args().has("--write-baseline"):
		_write_baseline()
		quit(0)
		return
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = rm.player
	await _test("G56: Agata's height on screen in every room is the one of the 384-px sheets (±1 px); the sprite draws the k× sheet at 1/k", _test_height)
	await _test("G10: the kerchief — pick at the bench, walk to the hanger, reach; the flag, the layers and the line once, at the hook", _test_carry)
	await _test("G10: a click while the kerchief is carried gives the same result at once (on the way and at the hook)", _test_carry_cut)
	gs.reset()
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== G56 + G10: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


# --- G56 ---------------------------------------------------------------------------------------------------------

## Agata's standing height in texture px of her sheet: the pivot (soles) minus the top of the head in idle frame 0,
## averaged over the 8 rows. The top edge is where the rows' peak alpha crosses one half (interpolated between pixel
## centres): the same edge on a 384-px and on a k× render, whatever the anti-aliasing.
static func _texture_height(sheet) -> float:
	var act: Dictionary = sheet.actions[sheet.idle_action]
	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet.sheet_dir + "/" + String(act.get("sheet", "idle.png"))))
	img.convert(Image.FORMAT_RGBA8)
	var sum := 0.0
	for d in sheet.directions:
		var fr: Array = sheet.frame_rect(act, d, 0)
		var reg := Rect2i(fr[0])
		var oy := float((fr[1] as Rect2).position.y)
		var top := oy
		var prev := 0.0
		for y in reg.size.y:
			var amax := 0.0
			for x in reg.size.x:
				amax = maxf(amax, img.get_pixel(reg.position.x + x, reg.position.y + y).a)
			if amax >= 0.5:
				top = oy + float(y) - 0.5 + (0.5 - prev) / maxf(amax - prev, 0.001)
				break
			prev = amax
		sum += sheet.pivot.y * float(sheet.frame_h) - top
	return sum / float(sheet.directions)


static func _rooms_with_depth() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/story/rooms"):
		if not f.ends_with(".json") or f.begins_with("_"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/" + f))
		if d is Dictionary and d.has("depth") and not bool(d.get("frame", false)):
			out.append([String(d["id"]), float(d["depth"].get("scale_bottom", 1.0)), float(d["depth"].get("scale_top", 1.0))])
	return out


func _write_baseline() -> void:
	var sheet = load("res://scripts/actors/actor_sheet.gd").load_actor("agata")
	var h: float = _texture_height(sheet) / sheet.texture_scale
	var rooms := {}
	for r in _rooms_with_depth():
		rooms[r[0]] = {"scale_bottom": r[1], "scale_top": r[2], "height_bottom_px": snappedf(h * r[1], 0.01), "height_top_px": snappedf(h * r[2], 0.01)}
	var md5 := FileAccess.get_md5(sheet.sheet_dir + "/" + String(sheet.actions[sheet.idle_action].get("sheet", "idle.png")))
	var out := {"_comment": "G56: рост Агаты на экране до перерендера (листы 384 px, texture_scale %s): unit_height_px — от подошв до макушки в кадре стойки 0 (среднее по 8 строкам) при масштабе 1; высоты в комнатах — × scale_bottom / scale_top. Писать только со старых листов: godot -s res://tests/test_agata_scale_carry.gd -- --write-baseline" % str(sheet.texture_scale),
		"idle_md5": md5, "frame_h": sheet.frame_h, "unit_height_px": snappedf(h, 0.001), "rooms": rooms}
	var f := FileAccess.open(BASELINE, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ") + "\n")
	f.close()
	print("baseline written: unit height %.3f px, %d rooms" % [h, rooms.size()])


func _test_height() -> void:
	var base = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	_check(base is Dictionary, "no %s" % BASELINE)
	if not (base is Dictionary):
		return
	var sheet = player.sheet
	var k: float = sheet.texture_scale
	var h_tex: float = _texture_height(sheet)
	var h_unit: float = h_tex / k
	var h0: float = float(base["unit_height_px"])
	print("    sheet frame %d px, texture_scale %.4f; height %.2f texture px = %.3f unit px (baseline %.3f on %d-px frames)" % [sheet.frame_h, k, h_tex, h_unit, h0, int(base["frame_h"])])
	_check(absf(sheet.unit_frame_h() - 384.0) < 0.5, "the unit frame stays 384 px high (frame_h %d / k %.4f)" % [sheet.frame_h, k])
	_check(absf(sheet.px_per_meter(1.0) - 384.0 / sheet.character_height_m) < 0.5, "px per metre at scale 1 in unit px: %.1f" % sheet.px_per_meter(1.0))
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	_check(spr.scale.is_equal_approx(Vector2.ONE / k), "the sprite draws the sheet at 1/k: scale %s, k %.4f" % [str(spr.scale), k])
	var worst := 0.0
	var worst_room := ""
	for r in _rooms_with_depth():
		var id: String = r[0]
		var want: Dictionary = base["rooms"].get(id, {})
		_check(not want.is_empty(), "%s: no baseline height (new room with depth: re-measure on 384-px sheets)" % id)
		if want.is_empty():
			continue
		# data: the room's near and far scale
		for pair in [[float(r[1]), float(want["height_bottom_px"])], [float(r[2]), float(want["height_top_px"])]]:
			var d := absf(h_unit * float(pair[0]) - float(pair[1]))
			if d > worst:
				worst = d
				worst_room = id
		# the real figure: Agata standing in the room, her sprite's global scale × her height in texture px
		rm.change_room(id, "default")
		await physics_frame
		await _frames(2)
		var room: Node = rm.current_room
		var s: float = room.depth_scale(player.global_position.y)
		var on_screen: float = h_tex * spr.get_global_transform().get_scale().y
		var expect: float = h0 * s
		print("    %s: at y %.0f scale %.3f — %.1f px on screen (before: %.1f); near %.1f / far %.1f px" % [id, player.global_position.y, s, on_screen, expect, h_unit * float(r[1]), h_unit * float(r[2])])
		_check(absf(on_screen - expect) <= 1.0, "%s: Agata %.1f px high on screen, before the re-render %.1f (±1 px)" % [id, on_screen, expect])
		var shadow := spr.get_node_or_null("Shadow") as Node2D
		if shadow != null:
			var sw: float = (shadow as Sprite2D).texture.get_width() * shadow.get_global_transform().get_scale().x
			var sw_want: float = ActorShadow.size_at(sheet, s).x
			_check(absf(sw - sw_want) <= 1.0, "%s: contact shadow %.1f px wide, expected %.1f" % [id, sw, sw_want])
	print("    worst near/far difference from the baseline: %.2f px (%s)" % [worst, worst_room])
	_check(worst <= 1.0, "%s: height at the near/far edge differs from the 384-px sheets by %.2f px (> 1)" % [worst_room, worst])


# --- G10 ---------------------------------------------------------------------------------------------------------

func _enter_h1() -> Node:
	sr._on_state_reset()
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "h1_shutter_open"]:
		gs.set_flag(f, true)
	gs.add_item("key_house")
	rm.change_room("H1", "default", Vector2(900, 900))
	await physics_frame
	await _frames(3)
	player.speed_factor = 3.0
	return rm.current_room


func _drain() -> void:
	var n := 0
	while (not sr.current_beat.is_empty() or sr.is_staging()) and n < 4000:
		var b: Dictionary = sr.current_beat
		if b.get("type") == "options":
			var opts: Array = b.get("options", [])
			sr.choose(String(opts[0].get("id", "")) if not opts.is_empty() else "")
		elif not b.is_empty() and b.get("type") != "stage":
			sr.advance()
		await process_frame
		n += 1


func _layer(room: Node, id: String) -> CanvasItem:
	return room.find_child(id, true, false) as CanvasItem


func _test_carry() -> void:
	var room: Node = await _enter_h1()
	var scarf: Node2D = room.get_node("Hotspots/scarf")
	var carry: Dictionary = scarf.data.get("carry", {})
	_check(String(scarf.data.get("action_anim", "")) == "pick" and String(carry.get("action_anim", "")) == "reach", "data: pick at the bench, reach at the hook (%s)" % str(carry))
	var bench := _layer(room, "bench_bare")
	var hook := _layer(room, "hook_coat")
	_check(bench != null and hook != null and not bench.visible and not hook.visible, "before: the kerchief on the bench, the hook empty")
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	var fires0: int = player.action_fire_count
	var sets := [0]
	var on_flag := func(f, v): if f == "h1_scarf_removed" and v: sets[0] += 1
	gs.flag_changed.connect(on_flag)
	player.call("click_at", scarf.global_position)
	var stages: Array = []
	var bench_before_flag := false
	var hook_before_flag := false
	var flag_anim := ""
	var flag_frame := -1
	var flag_pos := Vector2.ZERO
	var n := 0
	while (player.call("is_acting") or player.call("is_walking")) and n < 6000:
		var st := String(player.call("carry_stage"))
		if st != "" and (stages.is_empty() or stages[-1] != st):
			stages.append(st)
		if not gs.has_flag("h1_scarf_removed"):
			bench_before_flag = bench_before_flag or bench.visible
			hook_before_flag = hook_before_flag or hook.visible
		elif flag_frame < 0:
			flag_anim = String(spr.animation)
			flag_frame = spr.frame
			flag_pos = player.global_position
		await process_frame
		n += 1
	gs.flag_changed.disconnect(on_flag)
	var to: Array = carry.get("to", [0, 0])
	print("    stages %s; flag at %s frame %d (reach key frame %d), Agata at %s (carry.to %s); fires %d" % [str(stages), flag_anim, flag_frame, player.sheet.action_key_frame("reach"), str(flag_pos.round()), str(to), player.action_fire_count - fires0])
	_check(stages == ["pick", "walk", "place"], "pick → walk → place, got %s" % str(stages))
	_check(bench_before_flag, "the bench is bare as soon as she has picked the kerchief up (before the flag)")
	_check(not hook_before_flag, "the hook stays empty until she reaches it")
	_check(flag_anim.begins_with("reach_") and flag_frame >= player.sheet.action_key_frame("reach") and flag_frame <= player.sheet.action_key_frame("reach") + 1, "the flag lands on the reach key frame at the hook (%s %d)" % [flag_anim, flag_frame])
	_check(flag_pos.distance_to(Vector2(float(to[0]), float(to[1]))) < 40.0, "she hangs it at the hanger (%s, carry.to %s)" % [str(flag_pos.round()), str(to)])
	_check(player.action_fire_count - fires0 == 1 and sets[0] == 1, "one interaction, the flag set once (fires %d, sets %d)" % [player.action_fire_count - fires0, sets[0]])
	_check(bench.visible and hook.visible and not scarf.visible, "after: the bench bare, the kerchief on the left hook, the hotspot gone")
	_check(not sr.current_beat.is_empty(), "the kerchief's line plays once it hangs")
	await _drain()
	_check(player.action_fire_count - fires0 == 1, "nothing fired again after the line")
	_check(String(player.call("carry_stage")) == "" and bench.visible and hook.visible, "nothing left forced: the layers stand by the flag")


func _test_carry_cut() -> void:
	for cut_at in ["walk", "place"]:
		var room: Node = await _enter_h1()
		var scarf: Node2D = room.get_node("Hotspots/scarf")
		var bench := _layer(room, "bench_bare")
		var hook := _layer(room, "hook_coat")
		var fires0: int = player.action_fire_count
		player.call("click_at", scarf.global_position)
		var n := 0
		while String(player.call("carry_stage")) != cut_at and n < 6000:
			await process_frame
			n += 1
		_check(String(player.call("carry_stage")) == cut_at, "%s: the carry reached the stage" % cut_at)
		_check(not gs.has_flag("h1_scarf_removed"), "%s: no flag before the click" % cut_at)
		player.call("click_at", Vector2(1500, 900))
		await _frames(2)
		print("    cut at %s: flag %s, fires %d, stage '%s', bench %s, hook %s, dialogue %s" % [cut_at, str(gs.has_flag("h1_scarf_removed")), player.action_fire_count - fires0, String(player.call("carry_stage")), str(bench.visible), str(hook.visible), str(not sr.current_beat.is_empty())])
		_check(gs.has_flag("h1_scarf_removed") and player.action_fire_count - fires0 == 1, "%s: the click gives the result at once, exactly once" % cut_at)
		_check(String(player.call("carry_stage")) == "" and bench.visible and hook.visible and not scarf.visible, "%s: the kerchief on the hook, the bench bare" % cut_at)
		await _drain()
		var m := 0
		while (player.call("is_acting") or player.call("is_walking")) and m < 3000:
			await process_frame
			m += 1
		_check(player.action_fire_count - fires0 == 1 and String(player.call("carry_stage")) == "", "%s: nothing fired twice, no carry left" % cut_at)
