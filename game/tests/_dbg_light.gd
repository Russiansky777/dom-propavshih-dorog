extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	rm.autosave_enabled = false
	gs.set_flag("stove_lit", true)
	rm.change_room("H1", "", Vector2(1000, 800))
	for i in 40:
		await process_frame
	var player = main_node.get_node("World/Player")
	var spr = player.get("sprite")
	print("sprite children: ", spr.get_children())
	for c in spr.get_children():
		print(c.name, " vis=", c.visible, " tr=", c.transform, " tex=", c.texture)
		if c.has_method("current"):
			print("  cur=", c.current(), " tgt=", c.target_params(spr.global_position), " mat alpha=", c.material.get_shader_parameter("alpha"))
	var lighting = rm.current_room.get_node_or_null("Lighting")
	print("lighting: ", lighting, " shadows=", lighting.shadows if lighting else null)
	quit(0)
