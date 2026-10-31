extends SceneTree
## Title «Продолжить» after the saves are deleted in «Загрузить» (31.10, Director line 4: «При нажатии продолжить и
## отсутствии сохранений — в недопиленную рыбу игры пускает… Перед этим сохранения удалял»).

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	# a save to delete later: a real game state in slot 1 and the autosave
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "show")
	root.add_child(main_node)
	for i in 6:
		await process_frame
	var title = main_node.get("title")
	var ui = main_node.get("game_ui")
	print("PROBE title open %s, continue slot '%s', order %s" % [title.is_open(), title.continue_slot, str(title.order)])
	var slots: Array = title.call("default_slots")
	print("PROBE saves present: %s" % str(slots.filter(func(s): return gs.has_save(String(s)))))
	# delete every save through the panel, as the Director did
	title.activate("load")
	for i in 4:
		await process_frame
	for s in slots:
		if gs.has_save(String(s)):
			gs.delete_save(String(s))
	ui.call("_refresh_slots")
	print("PROBE after delete: saves %s; panel open %s" % [str(slots.filter(func(s): return gs.has_save(String(s)))), ui.call("menu_panel_open")])
	ui.call("close_menu_panel")
	for i in 4:
		await process_frame
	print("PROBE title open %s, order %s, continue slot '%s'" % [title.is_open(), str(title.order), title.continue_slot])
	title.activate("continue")
	for i in 30:
		await process_frame
	print("PROBE after continue: title open %s, room %s, story busy %s, flags %d" % [title.is_open(), rm.current_room.get("room_id") if rm.current_room != null else "none", root.get_node("StoryRunner").is_busy(), gs.flags.size()])
	quit(0)
