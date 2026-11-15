extends SceneTree
## Scratch probe for a trailer shot: where Agata is through the shot (every quarter of a second), whether she walks,
## where she looks, and where the room's people stand — to set a shot's `agata.from` / `to` / `start_s` by numbers.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_trailer_shot.gd -- res://data/trailer/trailer_v3.json mill [more shots]
## Not a test: prints, exit code 0.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var plan_path := String(args[0]) if args.size() > 0 else "res://data/trailer/trailer_v3.json"
	var rm: Node = root.get_node("RoomManager")
	for i in range(1, args.size()):
		var shot_id := String(args[i])
		var tr: Node = load("res://scenes/trailer/Trailer.tscn").instantiate()
		tr.set("quit_at_end", false)
		if not bool(tr.call("load_plan", plan_path, shot_id)):
			print("probe: cannot load %s/%s: %s" % [plan_path, shot_id, tr.get("errors")])
			tr.free()
			continue
		root.add_child(tr)
		var fps: int = tr.get("fps")
		var pre: float = tr.get("preroll_s")
		var total: int = tr.get("total_frames")
		print("== %s: %d frames at %d fps, preroll %.2f s, visible %.2f s" % [shot_id, total, fps, pre, float(total) / fps - pre])
		var step := maxi(1, fps / 4)
		for f in total:
			await process_frame
			if f % step == 0 or f == total - 1:
				var t := float(f) / fps - pre
				var pl: Node2D = rm.player
				var line := "   t %5.2f" % t
				if pl != null and is_instance_valid(pl):
					line += "  agata (%4.0f, %4.0f) %s" % [pl.global_position.x, pl.global_position.y, "walks" if bool(pl.call("is_walking")) else "stands"]
					if pl.has_method("probe"):
						var pr: Dictionary = pl.call("probe")
						line += "  dir %s yaw %s" % [str(pr.get("direction", "")), str(pr.get("yaw_deg", pr.get("yaw", "")))]
				var cam: Camera2D = tr.get_node_or_null("World/Camera")
				if cam != null:
					line += "  cam (%4.0f, %4.0f) ×%.3f" % [cam.position.x, cam.position.y, cam.zoom.x]
				for sp in tr.call("speaks_probe"):
					var jm = null
					if String(sp["speaker"]) == "agata" and pl != null:
						jm = pl.get("jaw")
					elif rm.current_room != null and rm.current_room.get_node_or_null("npc_" + String(sp["speaker"])) != null:
						var lv = rm.current_room.get_node("npc_" + String(sp["speaker"])).get("live")
						jm = lv.get("jaw") if lv != null else null
					line += "  [%s %s open %.2f]" % [sp["line_id"], "speaks" if bool(sp["speaking"]) else "silent", float(jm.get("open")) if jm != null and jm.get("open") != null else -1.0]
				var mv = tr.get("_mech_view")
				if mv != null and mv.get("panel") != null and (mv.get("panel") as Node).has_method("probe"):
					var pr2: Dictionary = (mv.get("panel") as Node).call("probe")
					line += "  mech %s" % str({"phase": pr2.get("phase", ""), "route": pr2.get("route", ""), "found": pr2.get("found", "")})
				print(line)
		if rm.current_room != null:
			for n in rm.current_room.get_children():
				if String(n.name).begins_with("npc_"):
					print("   %s at (%4.0f, %4.0f), turned to %s, direction %s" % [n.name, (n as Node2D).global_position.x, (n as Node2D).global_position.y,
						str(n.get("last_face_target")), str(n.get("direction"))])
			if rm.player != null:
				print("   agata at the end (%4.0f, %4.0f), direction %s" % [rm.player.global_position.x, rm.player.global_position.y, str(rm.player.get("direction"))])
		tr.queue_free()
		await process_frame
		if rm.current_room != null:
			rm.current_room.queue_free()
			rm.current_room = null
		for b in ["Music", "Voice"]:
			var bi := AudioServer.get_bus_index(b)
			if bi >= 0:
				AudioServer.set_bus_mute(bi, false)
		rm.autosave_enabled = true
	quit(0)
