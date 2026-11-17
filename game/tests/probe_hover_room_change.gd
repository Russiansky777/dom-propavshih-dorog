extends SceneTree
## Review 17.11: a screenshot of the bots showed «Пелагея» over the fence of the Olkhovka street (O4) while M19's first
## words were on screen — the caption of Pelageya at the far pier (R3), where the mouse had been. Does the hover caption
## outlive a room change? The far pier on the evening of day two (start point olkhovka), the mouse on Pelageya, the
## room changes to O4 (as the story takes Agata there) — the caption, the room, busy/staging, frame by frame.
##   godot --headless --audio-driver Dummy --path game -s res://tests/probe_hover_room_change.gd

var gs
var rm
var sr
var sd


func _initialize() -> void:
	_run()


func _mouse(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = root.get_final_transform() * at
	m.global_position = m.position
	Input.warp_mouse(m.position)
	Input.parse_input_event(m)


func _ui() -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("ui/game_ui.gd"):
			return n
	return null


func _state(tag: String, ui: Node) -> void:
	var hl: Label = ui.get("hover_label")
	print("%-10s room %-3s busy %-5s staging %-5s beat %-5s caption %s «%s»" % [tag,
		String(rm.current_room.room_id) if rm.current_room != null else "-", str(sr.is_busy()), str(sr.is_staging()),
		str(not sr.current_beat.is_empty()), str(hl.visible), hl.text])


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
	rm.start_with((sd.start_points.get("olkhovka", {}) as Dictionary).duplicate(true))
	for i in 600:
		await process_frame
		if i > 30 and not sr.is_busy():
			break
	var ui := _ui()
	_mouse(Vector2(935, 545))   # Pelageya at the far pier (R3 hotspot [890, 425, 90, 240])
	for i in 10:
		await process_frame
	_state("R3 hover", ui)
	# the story takes Agata up to the street, the mouse stays where it was
	rm.change_room("O4", "default")
	for i in 40:
		await process_frame
		if i < 6 or i % 8 == 0:
			_state("O4 f%02d" % i, ui)
	quit(0)
