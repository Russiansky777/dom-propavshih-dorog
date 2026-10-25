extends SceneTree
## I-T4: кадры жителей v2 в их комнатах из настоящей игры (не тест; нужен дисплей — tools/shots_npc_v2.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_npc_v2.gd -- <out_dir> [id ...]
## Для каждого жителя — первая комната, где он стоит хотспотом npc (данные rooms/*.json); житель показывается
## (scene_only тоже), состояния idle / listen / talk по очереди; из кадра 1920x1080 вырезается фигура.
## Итог: <out_dir>/npc_v2_<id>.png — три фигуры в ряд (стоит / слушает / говорит, у «говорит» — два кадра: рот).

const IDS := ["nina", "ilya", "ilya_wife", "ulyana", "mitya", "pelageya", "pavel", "tamara"]


func _initialize() -> void:
	_run()


func _room_of(id: String) -> String:
	var d := DirAccess.open("res://data/story/rooms")
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/" + f))
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		for h in spec.get("hotspots", []):
			if typeof(h) == TYPE_DICTIONARY and String(h.get("id", "")) == id and String(h.get("kind", "")) == "npc":
				return f.get_basename()
	return ""


func _grab(npc: Node2D) -> Image:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var p: Vector2 = root.get_viewport().get_canvas_transform() * npc.global_position
	var w := 700
	var h := 980
	var x := clampi(int(p.x) - w / 2, 0, img.get_width() - w)
	var y := clampi(int(p.y) + 40 - h, 0, img.get_height() - h)
	return img.get_region(Rect2i(x, y, w, h))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/i_t4")
	var ids: Array = args.slice(1) if args.size() > 1 else IDS
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(out_dir)
	for id in ids:
		var rid := _room_of(String(id))
		if rid == "":
			print("npc_v2 shot %s: no room" % id)
			continue
		gs.set_flag("done_M01", true)
		rm.change_room(rid, "default")
		for i in 20:
			await physics_frame
		var npc := root.find_child("npc_" + String(id), true, false) as Node2D
		if npc == null:
			print("npc_v2 shot %s: no actor in %s" % [id, rid])
			continue
		npc.hotspot.visible = true
		npc.visible = true
		npc.modulate.a = 1.0
		var row: Array = []
		for st in ["idle", "listen", "talk", "talk"]:
			npc.set_state(st)
			for i in (30 if row.size() < 3 else 4):
				await process_frame
			row.append(await _grab(npc))
		var sheet := Image.create(700 * row.size(), 980, false, row[0].get_format())
		for i in row.size():
			sheet.blit_rect(row[i], Rect2i(0, 0, 700, 980), Vector2i(700 * i, 0))
		var path := out_dir.path_join("npc_v2_%s.png" % id)
		sheet.save_png(path)
		print("npc_v2 shot %s in %s → %s" % [id, rid, path])
	gs.reset()
	quit(0)
