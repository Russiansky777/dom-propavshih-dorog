extends SceneTree
## How long a room change takes (the build of the room and its first frames), every room twice (cold, warm).
## 31.10 (Director, стр. 16: «переходы между комнатами — задержка»).
##   godot --path game -s res://tests/probe_room_times.gd -- [room ...]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sd = root.get_node("StoryData")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var rooms: Array = Array(OS.get_cmdline_user_args())
	if rooms.is_empty():
		for r in sd.rooms.keys():
			if not bool(sd.rooms[r].get("frame", false)) and not String(r).begins_with("EP_") and not String(r).begins_with("F_"):
				rooms.append(r)
		rooms.sort()
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	for pass_i in 2:
		for rid in rooms:
			var t0 := Time.get_ticks_usec()
			rm.change_room(String(rid), "default")
			var t1 := Time.get_ticks_usec()
			await process_frame
			var t2 := Time.get_ticks_usec()
			await process_frame
			var t3 := Time.get_ticks_usec()
			print("ROOMTIME %s %s change %.0f ms, 1st frame %.0f ms, 2nd %.0f ms" % ["cold" if pass_i == 0 else "warm", rid, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	quit(0)
