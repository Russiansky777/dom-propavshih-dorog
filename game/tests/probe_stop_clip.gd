extends SceneTree
## Frames for a clip of the live Agata walking and stopping (Director 01.11, morning page: «при остановке — семенит,
## доступает»): H1, standing → to the window → stop → back → stop. Needs a display (tools: /home/claude/work/runx.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 30 \
##     -s res://tests/probe_stop_clip.gd -- <out_dir> [<room> <x0> <y0> <x1> <y1>]
## Writes <out_dir>/f%04d.png, 600×600 crops following the figure; then ffmpeg them into a video.

var out_dir := "/tmp/stop_clip"
var n := 0


func _initialize() -> void:
	_run()


func _grab(player: Node2D) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var c := Vector2i(int(player.global_position.x), int(player.global_position.y) - 260)
	var r := Rect2i(c.x - 300, c.y - 300, 600, 600)
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var crop := img.get_region(r)
	crop.save_png(out_dir.path_join("f%04d.png" % n))
	n += 1


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var room := args[1] if args.size() > 1 else "H1"
	var p0 := Vector2(float(args[2]), float(args[3])) if args.size() > 3 else Vector2(560, 900)
	var p1 := Vector2(float(args[4]), float(args[5])) if args.size() > 5 else Vector2(1180, 880)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon", "stove_lit"]:
		gs.set_flag(f, true)
	rm.change_room(room, "default", p0)
	for i in 30:
		await process_frame
	var ui = main_node.get_node_or_null("GameUi")
	if ui != null:
		ui.visible = false
	for i in 30:
		await process_frame
		_grab(player)
	player.click_at(p1)
	var t := 0
	while (player.is_walking() or t < 10) and t < 400:
		t += 1
		await process_frame
		_grab(player)
	for i in 45:
		await process_frame
		_grab(player)
	player.click_at(p0)
	t = 0
	while (player.is_walking() or t < 10) and t < 400:
		t += 1
		await process_frame
		_grab(player)
	for i in 45:
		await process_frame
		_grab(player)
	print("frames: ", n)
	PS.forced_render = ""
	quit(0)
