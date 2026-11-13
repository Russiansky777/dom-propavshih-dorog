extends SceneTree
## 13.11: which villagers' feet outlines are squared to the floor's edge (RoomBuilder.foot_outline) — per room at four
## moments of the story: the outline's point count (12 — the ellipse alone; fewer — one point less per squared
## quarter) and whether a place Agata walks to kept the ellipse (squared on its own, but a stand falls in the corner).
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_feet_shapes.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sd = root.get_node("StoryData")
	var RB = load("res://scripts/rooms/room_builder.gd")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var seen := {}
	for upto in ["M02", "M17", "M21", ""]:
		gs.reset()
		for id in sd.scene_order:
			if id == upto:
				break
			var sc: Dictionary = sd.scene(id)
			if String(sc.get("type", "")) != "main":
				continue
			gs.set_flag("done_" + id, true)
			gs.set_flag("started_" + id, true)
			for f in sc.get("grants", {}).get("flags", []):
				gs.set_flag(String(f), true)
			for st in sc.get("stage", []):
				if not (st as Dictionary).has("if"):
					for f in (st as Dictionary).get("sets", []):
						gs.set_flag(String(f), true)
		for rid in sd.rooms.keys():
			var spec: Dictionary = sd.rooms[rid]
			if String(spec.get("background", {}).get("kind", "interior")) == "frame":
				continue
			rm.change_room(String(rid), "default")
			for i in 3:
				await process_frame
			var kind := String(spec.get("background", {}).get("kind", "interior"))
			RB.square_feet = true
			var sq: Array = RB.npc_footprints(rm.current_room, spec, kind, sd.rooms_index)
			for f in sq:
				var key := "%s %s @%s" % [rid, f[0], str(f[2])]
				if seen.has(key):
					continue
				var pts: int = (f[1] as PackedVector2Array).size()
				seen[key] = pts
				print("%s: %d points%s (half %s)" % [key, pts, "" if pts < 12 else " — the ellipse", str((f[3] as Vector2).round())])
	var squared := 0
	for k in seen:
		if int(seen[k]) < 12:
			squared += 1
	print("feet outlines: %d places, %d squared at the floor's edge" % [seen.size(), squared])
	quit(0)
