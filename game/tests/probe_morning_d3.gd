extends SceneTree
## Review 17.11: in the bots' screenshots of the morning of day three (M21 «Что смогла Дуня») the horenka shows only
## Agata while Nina speaks. N02 sends Nina out of the room with a fade (npc_go … fade); the note says «Нина утром снова
## здесь (M21)». Is she? From bedtime2 (the evening of day two): the bed → N02 → the morning → M21, Nina's figure
## (NpcActor on the hotspot nina): in the tree, visible, its alpha and position, line by line.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_morning_d3.gd

var gs
var rm
var sr
var sd


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func(): print("watchdog"); quit(1))
	_run()


func _nina() -> Node:
	if rm.current_room == null:
		return null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == "nina":
			return h
	return null


func _figure_state(tag: String) -> void:
	var h := _nina()
	var s := "%-16s room %s beat «%s»" % [tag, String(rm.current_room.room_id) if rm.current_room != null else "-",
		String(sr.current_beat.get("text", "")).left(40)]
	var hv := (h as CanvasItem).is_visible_in_tree() if h != null and h is CanvasItem else false
	var fig: Node = rm.current_room.get_node_or_null("npc_nina") if rm.current_room != null else null
	if fig == null:
		print(s + " | hotspot visible %s | no figure npc_nina" % str(hv))
		return
	var ci := fig as CanvasItem
	print(s + " | hotspot visible %s | figure visible %s alpha %.2f at %s" % [str(hv), str(ci.is_visible_in_tree()),
		ci.modulate.a, str((fig as Node2D).global_position)])


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_with((sd.start_points.get("bedtime2", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	_figure_state("evening")
	# to bed, as the player does: the bed's hotspot
	var bed: Node = null
	for h in rm.current_room.find_children("*", "", true, false):
		if h.get("hotspot_id") != null and String(h.get("hotspot_id")) == "bed":
			bed = h
	if bed == null:
		print("no bed hotspot"); quit(1); return
	sr.interact(bed)
	var last := ""
	var g := 0
	while g < 6000:
		g += 1
		await process_frame
		var key := String(sr.active_scene) + "|" + String(sr.current_beat.get("text", ""))
		if key != last:
			last = key
			_figure_state(String(sr.active_scene) if sr.active_scene != "" else "-")
		if gs.has_flag("done_M21"):
			break
		# the morning: the goal says «Расспросить маму» — the player clicks Mama (M21 is her talk)
		if gs.has_flag("morning_day3") and not gs.has_flag("started_M21") and sr.current_beat.is_empty() and not sr.is_busy():
			_figure_state("morning, idle")
			var hn := _nina()
			if hn != null:
				sr.interact(hn)
			continue
		if not sr.current_beat.is_empty() and not sr.is_staging():
			for i in 20:
				await process_frame
			sr.advance()
	_figure_state("after M21")
	quit(0)
