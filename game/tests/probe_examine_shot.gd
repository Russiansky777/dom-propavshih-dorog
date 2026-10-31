extends SceneTree
## An item's close-up (examine) as the player sees it (rendered):
##   godot --path game -s res://tests/probe_examine_shot.gd -- <out.png> <item_id>

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	gs.reset()
	gs.add_item(a[1])
	rm.change_room("H1", "default")
	for i in 10:
		await process_frame
	sr.examine_opened.emit(a[1])
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	print("SHOT ", a[0])
	quit(0)
