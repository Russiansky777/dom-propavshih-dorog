extends SceneTree
## Review 17.11: Q07 «Двадцать зарубок» and Q08 «Общий чай» brought the speakers into the room (Pelageya at the far
## pier; Tamara and Ulyana by the stove or in Mama's room). A picture of each line, of the room before and after —
## under a display (Xvfb) to see where they stand.
##   SHOTS_DIR=<dir> xvfb-run -a -s "-screen 0 1920x1080x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1920x1080 --path game -s res://tests/probe_guests_shots.gd
## PART=q07 | q08a | q08b (default all three).

var gs
var rm
var sr
var sd
var _n := 0
var _dir := ""


func _initialize() -> void:
	var wd := float(OS.get_environment("WATCHDOG")) if OS.get_environment("WATCHDOG") != "" else 1500.0
	create_timer(wd).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _shot(tag: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw   # (headless never draws: it would wait for ever)
	_n += 1
	var line := "%02d %-14s room %s scene %s beat «%s»" % [_n, tag, String(rm.current_room.room_id) if rm.current_room != null else "-",
		String(sr.active_scene), String(sr.current_beat.get("text", "")).left(50)]
	var figs: Array = []
	if rm.current_room != null:
		for c in rm.current_room.get_children():
			if String(c.name).begins_with("npc_") and (c as CanvasItem).is_visible_in_tree():
				figs.append("%s@%s a%.2f" % [String(c.name).substr(4), str((c as Node2D).global_position.round()), (c as CanvasItem).modulate.a])
	print(line + " | " + ", ".join(figs))
	if _dir != "" and DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_jpg("%s/g%02d_%s.jpg" % [_dir, _n, tag], 0.85)


func _hotspot(id: String) -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == id:
			return h
	return null


func _settle(n: int = 40) -> void:
	for i in n:
		await process_frame


## Plays what the click started, a picture at each line; `pick` — the option to take.
func _play(tag: String, pick: String) -> void:
	var last := ""
	for g in 6000:
		await process_frame
		var b: Dictionary = sr.current_beat
		if b.is_empty():
			if not sr.is_busy():
				break
			continue
		if sr.is_staging():
			continue
		if String(b.get("type", "")) == "options":
			await _settle(10)
			await _shot(tag + "_choice")
			sr.choose(pick)
			continue
		var key := String(b.get("text", ""))
		if key != last:
			last = key
			await _settle(45)
			await _shot(tag + "_line")
		await _settle(10)
		sr.advance()


func _start() -> Node:
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _settle(4)
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("freewalk", {}) as Dictionary).duplicate(true))
	for i in 900:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	return main_node


func _stop(main_node: Node) -> void:
	main_node.queue_free()
	await process_frame
	if rm.current_room != null:
		rm.current_room.queue_free()
		rm.current_room = null
	gs.reset()
	await _settle(4)


func _q07() -> void:
	var m: Node = await _start()
	gs.set_flag("q07_seen_board", true)
	rm.change_room("R3", "default")
	await _settle(60)
	await _shot("q07_before")
	var mitya := _hotspot("mitya")
	if mitya == null:
		print("no mitya at R3")
		await _stop(m)
		return
	sr.interact(mitya)
	await _play("q07", "board_mother")
	await _settle(60)
	await _shot("q07_after")
	await _stop(m)


func _q08(variant: String) -> void:
	var m: Node = await _start()
	for f in ["done_M23a", "done_M23b", "done_M23c", "started_M23c"]:
		gs.set_flag(f, true)
	rm.change_room("H1", "from_H3")
	await _settle(60)
	await _shot("q08%s_before" % variant.to_lower())
	var tc := _hotspot("tea_corner")
	if tc == null:
		print("no tea corner in H1")
		await _stop(m)
		return
	sr.interact(tc)
	await _play("q08" + variant.to_lower(), variant)
	await _settle(60)
	await _shot("q08%s_after" % variant.to_lower())
	await _stop(m)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	_dir = OS.get_environment("SHOTS_DIR")
	var part := OS.get_environment("PART")
	if part == "" or part == "q07":
		await _q07()
	if part == "" or part == "q08a":
		await _q08("A")
	if part == "" or part == "q08b":
		await _q08("B")
	quit(0)
