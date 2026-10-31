extends SceneTree
## Walks between the hotspots' stand points of a room (or every room) — the live figure, as the player clicks —
## and reports walks that stall: the figure walks (walk weight up) but the body hardly moves for a while (walking on
## the spot), or the walk does not arrive in time. 31.10 (Director, lines 8–9: «застревает и идёт на одном месте…
## от писем до стола… от листов до плана Заречья… пройтись по всем багам»).
##   godot --path game -s res://tests/probe_walk_tour.gd -- [room ...]   (no room — every room of data/story/rooms)

const STALL_S := 0.6        # this long walking with the body moving under STALL_PX_S → «on the spot»
const STALL_PX_S := 25.0    # px per second (scale 1): a step is ~100 px/s at the slowest
const TIMEOUT_S := 12.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sd = root.get_node("StoryData")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = OS.get_environment("RENDER") if OS.get_environment("RENDER") != "" else "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	var rooms: Array = Array(OS.get_cmdline_user_args())
	if rooms.is_empty():
		rooms = sd.rooms.keys()
		rooms.sort()
	var bad := 0
	var walks := 0
	for rid in rooms:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "house_open", "done_M03", "met_tikhon"]:
			gs.set_flag(f, true)
		rm.change_room(String(rid), "default", Vector2(-1, -1))
		for i in 30:
			await process_frame
		if rm.current_room == null or String(rm.current_room.get("room_id")) != String(rid):
			print("TOUR %s: not entered" % rid)
			continue
		var stands: Array = []
		for h in sd.rooms[rid].get("hotspots", []):
			var st = h.get("stand", null)
			if st is Array and st.size() >= 2:
				stands.append([String(h.get("id", "")), Vector2(float(st[0]), float(st[1]))])
		if stands.size() < 2:
			continue
		# a tour: each stand in order, then back across (every neighbour pair both ways, and the far pairs)
		var order: Array = []
		for i in stands.size():
			order.append(i)
		for i in range(stands.size() - 2, -1, -1):
			order.append(i)
		for i in range(0, stands.size(), 2):
			order.append((i + stands.size() / 2) % stands.size())
		# to the first stand as a player would (a walk, not a jump — a jump leaves the navigation agent behind)
		player.walk_to(stands[0][1])
		var w0 := 0.0
		while w0 < TIMEOUT_S:
			await process_frame
			w0 += player.get_process_delta_time()
			if w0 > 0.5 and not player.is_walking():
				break
		for i in 20:
			await process_frame
		var prev := 0
		for idx in order.slice(1):
			var from_id: String = stands[prev][0]
			var to: Vector2 = stands[idx][1]
			prev = idx
			if player.global_position.distance_to(to) < 30.0:
				continue
			walks += 1
			player.walk_to(to)
			var t := 0.0
			var stall_t := 0.0
			var worst_stall := 0.0
			var last := player.global_position
			var started := false
			while t < TIMEOUT_S:
				await process_frame
				var d: float = player.get_process_delta_time()
				t += d
				var moved: float = player.global_position.distance_to(last) / maxf(d, 0.001) / maxf(absf(player.scale.y), 0.05)
				last = player.global_position
				if player.is_walking():
					started = true
					if float(player.walk_w) > 0.5 and moved < STALL_PX_S:
						stall_t += d
						worst_stall = maxf(worst_stall, stall_t)
					else:
						stall_t = 0.0
				elif started:
					break
			var after := 0.0
			var turn_steps := 0.0
			while after < 1.5:
				await process_frame
				var d2: float = player.get_process_delta_time()
				after += d2
				if float(player.get("_turn_step_w")) > 0.2:
					turn_steps += d2
			if turn_steps > 0.8:
				print("TOUR %s: %s → %s: steps on the spot turning for %.2f s after arriving" % [rid, from_id, stands[idx][0], turn_steps])
			var left := player.global_position.distance_to(to)
			var arrived: bool = not player.is_walking() and left < 60.0
			if worst_stall >= STALL_S or t >= TIMEOUT_S or not arrived:
				bad += 1
				print("TOUR %s: %s → %s (%s): %s; walked %.1f s, on the spot up to %.2f s, %.0f px short" % [rid, from_id, stands[idx][0], str(to),
					"STALL" if worst_stall >= STALL_S else ("TIMEOUT" if t >= TIMEOUT_S else "SHORT"), t, worst_stall, left])
	print("TOUR done: %d walks in %d rooms, %d bad" % [walks, rooms.size(), bad])
	quit(0)
