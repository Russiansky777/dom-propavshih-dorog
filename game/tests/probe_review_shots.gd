extends SceneTree
## Review frames of the live Agata (rendered; needs a display): every state she is seen in — walking across, towards
## and away from the viewer, on the diagonal, stopping, turning on the spot, the three actions, the talk gesture, the
## stance, looking at a villager — a full-figure crop every `every` frames, per scene in its own folder.
##   godot --path game -s res://tests/probe_review_shots.gd -- <out dir> [scene ...]

var out := ""
var every := 4
var player: Node2D = null


func _initialize() -> void:
	_run()


func _grab(dir: String, n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var ct := root.get_canvas_transform()
	var at: Vector2 = ct * player.global_position
	var ppm_s: float = player.view3d.ppm * absf(player.scale.y) * ct.get_scale().y
	var r := Rect2i(int(at.x - 0.6 * ppm_s), int(at.y - 1.95 * ppm_s), int(1.2 * ppm_s), int(2.1 * ppm_s))
	if OS.get_environment("FEET") != "":
		r = Rect2i(int(at.x - 0.45 * ppm_s), int(at.y - 0.55 * ppm_s), int(0.9 * ppm_s), int(0.7 * ppm_s))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	DirAccess.make_dir_recursive_absolute(out + "/" + dir)
	img.get_region(r).save_png("%s/%s/%03d.png" % [out, dir, n])


func _rec(dir: String, frames: int, at: Callable = Callable()) -> void:
	var n := 0
	for i in frames:
		if at.is_valid():
			at.call(i)
		if i % every == 0:
			await _grab(dir, n)
			n += 1
		else:
			await process_frame


func _place(room: String, pos: Vector2, yaw: float) -> void:
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
		gs.set_flag(f, true)
	rm.change_room(room, "default", pos)
	for i in 20:
		await process_frame
	player.yaw3d = yaw
	player.yaw3d_target = yaw
	for i in 30:
		await process_frame


## Skirt experiments (SKIRT=off, SKIRT_STIFF, SKIRT_GRAV, SKIRT_NOCOL=1).
func _skirt_env() -> void:
	var sk: SpringBoneSimulator3D = player.view3d.skirt
	if sk == null:
		return
	if OS.get_environment("SKIRT") == "off":
		sk.active = false
	for c in sk.setting_count:
		if OS.get_environment("SKIRT_STIFF") != "":
			sk.set_stiffness(c, float(OS.get_environment("SKIRT_STIFF")))
		if OS.get_environment("SKIRT_GRAV") != "":
			sk.set_gravity(c, sk.get_gravity(c) * float(OS.get_environment("SKIRT_GRAV")))
		if OS.get_environment("SKIRT_NOCOL") != "":
			sk.set_enable_all_child_collisions(c, false)
		if OS.get_environment("SKIRT_R") != "":
			sk.set_radius(c, sk.get_radius(c) * float(OS.get_environment("SKIRT_R")))
	if OS.get_environment("SKIRT_CAPR") != "":
		for cap in sk.get_children():
			if cap is SpringBoneCollisionCapsule3D:
				(cap as SpringBoneCollisionCapsule3D).radius *= float(OS.get_environment("SKIRT_CAPR"))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	if OS.get_environment("EVERY") != "":
		every = int(OS.get_environment("EVERY"))
	var only: Array = args.slice(1)
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	root.get_node("RoomManager").autosave_enabled = false
	player = main_node.get_node("World/Player")
	var kf := func() -> float: return player.floor_foreshortening()
	var scenes := {
		"walk_side": func():
			await _place("Z2", Vector2(500, 900), PI * 0.5)
			player.click_at(player.global_position + Vector2(700, 0))
			await _rec("walk_side", 170),
		"walk_towards": func():
			await _place("Z2", Vector2(900, 760), 0.0)
			player.click_at(player.global_position + Vector2(0, 300))
			await _rec("walk_towards", 170),
		"walk_away": func():
			await _place("Z2", Vector2(900, 1040), PI)
			player.click_at(player.global_position + Vector2(0, -300))
			await _rec("walk_away", 170),
		"walk_diag": func():
			await _place("Z2", Vector2(600, 800), 0.8)
			player.click_at(player.global_position + Vector2(500, 260))
			await _rec("walk_diag", 170),
		"turn_back": func():
			await _place("Z2", Vector2(900, 900), 0.3)
			player.face_towards(player.global_position + Vector2(sin(2.9), cos(2.9) * kf.call()) * 200.0)
			await _rec("turn_back", 80),
		"turn_90": func():
			await _place("Z2", Vector2(900, 900), 0.0)
			player.face_towards(player.global_position + Vector2(200, 0))
			await _rec("turn_90", 60),
		"act_open": func():
			await _place("H1", Vector2(1200, 960), 0.6)
			player._start_action("open", null)
			await _rec("act_open", 200),
		"act_pick": func():
			await _place("H1", Vector2(1200, 960), 0.6)
			_skirt_env()
			player._start_action(OS.get_environment("PICK_ACT") if OS.get_environment("PICK_ACT") != "" else "pick", null)
			await _rec("act_pick", int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 150),
		"act_reach": func():
			await _place("H1", Vector2(1200, 960), 0.6)
			player._start_action("reach", null)
			await _rec("act_reach", 150),
		"talk": func():
			await _place("H1", Vector2(1200, 960), 0.6)
			var sr = root.get_node("StoryRunner")
			sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_1", "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
			await _rec("talk", 240, func(i): if i == 200: sr.current_beat = {}),
		"idle": func():
			await _place("H1", Vector2(1200, 960), 0.4)
			every = 8
			await _rec("idle", 480)
			every = 4,
	}
	for k in scenes.keys():
		if only.is_empty() or only.has(k):
			await (scenes[k] as Callable).call()
	PS.forced_render = ""
	quit(0)
