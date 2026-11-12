extends SceneTree
## Lips by sounds (Director 12.11, 21:40: «нужны губы как минимум») — frames for a video: a figure says a real line, its
## mouth led by the line's letters (LipsTable) and by the recording's own loudness, frame by frame; the same with the
## table off (the mouth by loudness alone, as before 12.11) for a «было / стало». The figure alone, as the game builds
## it (NpcLive3D, every modifier); a close-up of the face or the whole figure at the game's size.
##   xvfb-run godot --fixed-fps 30 --path game -s res://tests/probe_lips_reel.gd -- <out dir> <id> <line id> <levels.json>
##       [lang=ru] [mode=new|old] [shot=face|full] [px=480] [view_m=0.10] [yaw=18]   (px, view_m — the face shot)
## levels.json: {"fps": 30, "db": [peak level of the recording per frame, dB]} (scratch: made from the game's .ogg).
## Files: <out>/<id>_<mode>_<shot>_<frame>.jpg.

const LT := preload("res://scripts/audio/lips_table.gd")


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


## Centres the render camera on a point of the figure's world: the bone `bone`, or the mouth (`jaw` given).
func _aim(view, px: int, view_m: float, bone: String, off: float, jaw = null, passes: int = 3) -> void:
	view.size = Vector2i(px, px)
	var cam: Camera3D = view.camera
	cam.size = view_m
	for i in passes:
		if passes > 1:
			await process_frame
		var sk: Skeleton3D = view.skeleton
		var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin
		if jaw != null and bool(jaw.call("painted")):
			p = (jaw.call("mouth_frame") as Transform3D).origin
		var at: Vector2 = cam.unproject_position(p)
		var c := Vector2(view.size) * 0.5
		var m_per_px := cam.size / float(view.size.y)
		cam.global_position += cam.global_transform.basis.x * (at.x - c.x) * m_per_px
		cam.global_position -= cam.global_transform.basis.y * (at.y - c.y + view.size.y * off) * m_per_px


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var id: String = a[1]
	var line: String = a[2]
	var lv = JSON.parse_string(FileAccess.get_file_as_string(a[3]))
	var opt := {"lang": "ru", "mode": "new", "shot": "face", "px": "480", "view_m": "0.30", "yaw": "18"}
	for i in range(4, a.size()):
		var kv := String(a[i]).split("=")
		if kv.size() == 2:
			opt[kv[0]] = kv[1]
	var fps := float(lv.get("fps", 30))
	var dbs: Array = lv.get("db", [])
	DirAccess.make_dir_recursive_absolute(out)
	LT.enabled = String(opt["mode"]) != "old"
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var n := _fake_npc()
	n.set("actor_id", id)
	var live = NL.new()
	n.add_child(live)
	if not live.setup(n, spec, 0.55):
		print("%s: not loaded" % id)
		quit(1)
		return
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var yaw := deg_to_rad(float(opt["yaw"]))
	live.face(Vector2(sin(yaw), cos(yaw) * 0.55) * 100.0, 0.55, true)
	live.set_state("talk")
	var dt := 1.0 / fps
	var t := 0.0
	while t < 0.7:
		live.process(dt)
		await process_frame
		t += dt
	var jaw = live.get("jaw")
	if jaw == null:
		print("%s: no jaw" % id)
		quit(1)
		return
	var face := String(opt["shot"]) == "face"
	if face:
		await _aim(live.view, int(opt["px"]), float(opt["view_m"]), "Head", -0.08, jaw)
	# shot=full: the figure as the game itself renders it (its own camera and size) — the video shows it at the game's
	# scale (the sheet's texture_scale); a camera size set here is set back by the figure's own process
	jaw.speaking_override = 1
	jaw.lang_override = String(opt["lang"])
	print("%s «%s» (%s, %s, %s): table %s, %d frames" % [id, line, opt["lang"], opt["mode"], opt["shot"], "yes" if LT.has_line(String(opt["lang"]), line) else "NO", dbs.size()])
	for f in dbs.size():
		jaw.line_override = line
		jaw.time_override = float(f) / fps
		jaw.level_override = float(dbs[f])
		live.process(dt)
		await process_frame
		if face:   # the close-up follows the mouth: the head moves with the talk's gestures
			await _aim(live.view, int(opt["px"]), float(opt["view_m"]), "Head", -0.08, jaw, 1)
		live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		live.view.get_texture().get_image().save_jpg("%s/%s_%s_%s_%04d.jpg" % [out, id, opt["mode"], opt["shot"], f], 0.92)
	print("done ", id, " ", opt["mode"], " ", opt["shot"])
	quit(0)
