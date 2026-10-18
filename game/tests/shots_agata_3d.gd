extends SceneTree
## Frames of Agata, sprites vs live 3D, in the real game (not a test; needs a display — tools/shots_agata_3d.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 --fixed-fps 30 \
##     -s res://tests/shots_agata_3d.gd -- <out_dir> <case> [<case> ...]
## Cases (each in both modes unless the name says otherwise; frames <out_dir>/<case>_<mode>_<NNN>.png,
## cropped around Agata, plus a full frame <case>_<mode>_full.png):
##   still   — H1, standing near (y 1000) and far (y 760): side by side
##   turn    — standing in H1, the target direction goes round in 15° steps (sprites: 8 rows)
##   walk    — Z2: walks right, towards the viewer, diagonal; a frame every 2 game frames
##   idle    — H1, 6 s standing, a frame every 3 game frames
##   startstop — H1: stand 0.5 s, walk 330 px, stop, stand 0.8 s
##   stove   — H1: click on the stove (action «open» at the oven door)
## --fixed-fps keeps game time exact however slow the software renderer is.

var gs: Node
var rm: Node
var main_node: Node
var player: Node2D
var out_dir := ""
var crop_size := Vector2i(560, 760)


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "/tmp/agata_shots"
	var cases: Array = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	for c in cases:
		var parts := String(c).split(":")
		var name := parts[0]
		var modes := ["sprites", "3d"] if parts.size() < 2 else [parts[1]]
		for m in modes:
			await call("_case_" + name, m)
	print("shots done → ", out_dir)
	quit(0)


func _enter(room: String, pos: Vector2, mode: String, flags: Array = []) -> void:
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"] + flags:
		gs.set_flag(f, true)
	gs.add_item("key_house")
	rm.change_room(room, "default", pos)
	await _frames(4)
	player.set_render_mode(mode)
	await _frames(20)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab(path: String, full: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	if full:
		img.save_png(path)
		return
	var feet: Vector2 = player.global_position
	var r := Rect2i(int(feet.x) - crop_size.x / 2, int(feet.y) - crop_size.y + 60, crop_size.x, crop_size.y)
	r.position.x = clampi(r.position.x, 0, 1920 - crop_size.x)
	r.position.y = clampi(r.position.y, 0, 1080 - crop_size.y)
	img.get_region(r).save_png(path)


func _p(case_name: String, mode: String, i: int) -> String:
	return out_dir.path_join("%s_%s_%03d.png" % [case_name, mode, i])


const BRIGHT := ["h1_shutter_open", "stove_lit"]  # H1 in daylight with the fire: the figure is readable


func _case_still(mode: String) -> void:
	await _enter("H1", Vector2(1200, 1000), mode, BRIGHT)
	await _grab(_p("still_near", mode, 0))
	await _grab(out_dir.path_join("still_near_%s_full.png" % mode), true)
	await _enter("H1", Vector2(1150, 760), mode, BRIGHT)
	await _grab(_p("still_far", mode, 0))


func _case_turn(mode: String) -> void:
	await _enter("H1", Vector2(1200, 960), mode, BRIGHT)
	var i := 0
	for deg in range(0, 375, 15):
		var a := deg_to_rad(90.0 + deg)  # 0 = towards the viewer, then counter-clockwise on screen
		player.face_towards(player.global_position + Vector2(cos(a), sin(a)) * 200.0)
		await _frames(6)
		await _grab(_p("turn", mode, i))
		i += 1


func _case_walk(mode: String) -> void:
	var legs := [["right", Vector2(500, 900), Vector2(1450, 900)], ["down", Vector2(960, 700), Vector2(960, 1030)],
		["diag", Vector2(600, 720), Vector2(1300, 1020)]]
	for leg in legs:
		await _enter("Z2", leg[1], mode)
		player.walk_to(leg[2])
		var i := 0
		while player.is_walking() and i < 400:
			await _frames(2)
			await _grab(_p("walk_" + String(leg[0]), mode, i))
			i += 1


func _case_idle(mode: String) -> void:
	await _enter("H1", Vector2(1200, 980), mode, BRIGHT)
	for i in 60:
		await _frames(3)
		await _grab(_p("idle", mode, i))


func _case_startstop(mode: String) -> void:
	await _enter("H1", Vector2(900, 960), mode, BRIGHT)
	var i := 0
	for k in 8:
		await _frames(2)
		await _grab(_p("startstop", mode, i))
		i += 1
	player.walk_to(Vector2(1230, 960))
	while player.is_walking() and i < 300:
		await _frames(2)
		await _grab(_p("startstop", mode, i))
		i += 1
	for k in 12:
		await _frames(2)
		await _grab(_p("startstop", mode, i))
		i += 1


func _case_stove(mode: String) -> void:
	await _enter("H1", Vector2(700, 900), mode)
	var room = rm.current_room
	var stove: Node2D = null
	for h in room.get_hotspots():
		if String(h.hotspot_id) == "stove":
			stove = h
	if stove == null:
		print("no stove hotspot")
		return
	player.walk_to_and_interact(stove)
	var i := 0
	while (player.is_walking() or player.is_acting()) and i < 400:
		await _frames(2)
		await _grab(_p("stove", mode, i))
		i += 1
	for k in 10:
		await _frames(2)
		await _grab(_p("stove", mode, i))
		i += 1


## Raw figure colours, before the room tone: the live viewport texture facing the camera vs the
## sheet's idle frame (row 0) — mean colour over opaque pixels (light calibration of actor_3d.gdshader).
func _case_calib(mode: String) -> void:
	if mode != "3d":
		return
	await _enter("H1", Vector2(1200, 980), "3d")
	player.yaw3d = 0.0
	player.yaw3d_target = 0.0
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img: Image = player.view3d.get_texture().get_image()
	img.save_png(out_dir.path_join("calib_3d_raw.png"))
	var sheet_img: Image = load("res://assets/characters/agata/idle.png").get_image()
	sheet_img.get_region(Rect2i(0, 0, 288, 384)).save_png(out_dir.path_join("calib_sheet_row0.png"))
	print("calib saved; render_scale ", player.view3d.render_scale, " size ", player.view3d.size)
	for probe in [["flat05", "debug_flat", 0.5], ["albedo", "debug_albedo", true]]:
		player.view3d.material.set_shader_parameter(probe[1], probe[2])
		await _frames(3)
		await RenderingServer.frame_post_draw
		player.view3d.get_texture().get_image().save_png(out_dir.path_join("calib_3d_%s.png" % probe[0]))
		player.view3d.material.set_shader_parameter(probe[1], -1.0 if probe[1] == "debug_flat" else false)
	var tex: Texture2D = player.view3d.material.get_shader_parameter("albedo_tex")
	if tex != null:
		tex.get_image().save_png(out_dir.path_join("calib_albedo_tex.png"))
