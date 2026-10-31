extends SceneTree
## A menu panel as the player sees it (rendered; needs a display):
##   godot --path game -s res://tests/probe_menu_shot.gd -- <out.png> [mode: settings|load|save|all] [slow: 0|1]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 6:
		await process_frame
	root.get_node("RoomManager").autosave_enabled = false
	root.get_node("RoomManager").change_room("H1", "default")
	for i in 20:
		await process_frame
	if a.size() > 2:
		load("res://scripts/mechanics/timing_bar.gd").set("slow", a[2] == "1")
	var ui = main_node.get_node("GameUi")
	ui.call("open_menu_panel", a[1] if a.size() > 1 else "settings")
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	print("SHOT ", a[0])
	quit(0)
