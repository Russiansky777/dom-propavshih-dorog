extends SceneTree
## Stopping as seen: from the moment the walk starts slowing (walk_w < 0.99) — how many times a drawn foot leaves the
## floor and is set down again until she stands still, over what time and distance; per walk. A person stops in about
## two steps (the last stride shorter, then the trailing foot closes up); many small quick steps read as fidgeting.
##   godot --path game -s res://tests/probe_stop_steps.gd

var _drawn: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	for k in 6:
		gs.reset()
		for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
			gs.set_flag(f, true)
		rm.change_room("Z2", "default", Vector2(500 + (k % 3) * 150, 860 + (k % 2) * 80))
		for i in 20:
			await process_frame
		var v: Actor3D = player.view3d
		v.seed_idle(60 + k)
		seed(60 + k)
		if not v.skeleton.skeleton_updated.is_connected(_on_upd.bind(v)):
			v.skeleton.skeleton_updated.connect(_on_upd.bind(v))
		var ang := PI * 0.5 + (k - 2.5) * 0.25
		player.yaw3d = ang
		player.yaw3d_target = ang
		for i in 30:
			await process_frame
		var kf: float = player.floor_foreshortening()
		player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * kf) * (500.0 + k * 40.0))
		var slowing := false
		var t := 0.0
		var after := 0.0
		var up: Array = [false, false]
		var lifts := 0
		var p0 := Vector2.ZERO
		var ppm_s: float = v.ppm * absf(player.scale.y)
		var events := ""
		while after < 1.5 and t < 8.0:
			await process_frame
			var d: float = player.get_process_delta_time()
			if not slowing and player.is_walking() and player.walk_w < 0.99 and player.walk_time > 0.6:
				slowing = true
				p0 = player.global_position
			if slowing:
				t += d
				if not player.is_walking():
					after += d
					if events.find("|still") < 0:
						events += " |still %.2f" % t
				var f: Array = _drawn if not _drawn.is_empty() else v.feet_model()
				for i in 2:
					var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
					var now_up: bool = h > 0.02
					if now_up and not up[i]:
						lifts += 1
						events += " %s↑%.2f%s" % ["L" if i == 0 else "R", t, ("(step)" if v._foot_step[i] != null else ("(lock)" if v._foot_lock[i] != null else ""))]
					elif not now_up and up[i]:
						events += " %s↓%.2f" % ["L" if i == 0 else "R", t]
					up[i] = now_up
		var dist: float = (player.global_position - p0).length() / ppm_s
		print("walk %d: slowing to still %.2f s over %.2f m, %d lifts:%s" % [k, t - after, dist, lifts, events])
	PS.forced_render = ""
	quit(0)


func _on_upd(v: Actor3D) -> void:
	_drawn = v.feet_model()
