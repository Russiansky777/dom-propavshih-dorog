extends SceneTree
## Frames of the title screen and the pause menu from the real game (not a test; needs a display — Xvfb):
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --display-driver x11 --rendering-driver opengl3 \
##     --resolution 1920x1080 -s res://tests/shots_menus.gd -- <out_dir>
## Writes menu_title.png, menu_title_hover.png, menu_pause.png, menu_pause_hover.png, menu_pause_save.png,
## menu_pause_settings.png (1920×1080).


func _initialize() -> void:
	_run()


func _shot(out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("menu frame: ", out_dir.path_join(name))


func _wait(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../build/shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	root.get_node("GameState").reset()
	var rm = root.get_node("RoomManager")
	rm.autosave_enabled = false
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "show")
	root.add_child(main_node)
	var title = main_node.get_node("Title")
	var pause = main_node.get_node("Pause")
	await _wait(1.5)
	await _shot(out_dir, "menu_title.png")
	(title.get("buttons")["new_game"] as Button).mouse_entered.emit()
	await _wait(0.6)
	await _shot(out_dir, "menu_title_hover.png")
	title.call("activate", "new_game")
	rm.autosave_enabled = false
	var gui0 = main_node.get_node_or_null("GameUi")
	if gui0 != null and gui0.get("intro_card") != null:
		gui0.get("intro_card").call("finish_now")   # J (Р13): the shot is of the room, not of the intro
	await _wait(2.5)
	var sr = root.get_node("StoryRunner")
	var g := 0
	while not sr.current_beat.is_empty() and g < 50:
		sr.advance()
		g += 1
		await process_frame
	await _wait(0.5)
	pause.call("open")
	await _wait(0.6)
	await _shot(out_dir, "menu_pause.png")
	(pause.get("buttons")["main_menu"] as Button).mouse_entered.emit()
	await _wait(0.2)
	await _shot(out_dir, "menu_pause_hover.png")
	pause.call("activate", "save")
	await _wait(0.4)
	await _shot(out_dir, "menu_pause_save.png")
	main_node.get_node("GameUi").call("close_menu_panel")
	pause.call("activate", "settings")
	await _wait(0.4)
	await _shot(out_dir, "menu_pause_settings.png")
	quit(0)
