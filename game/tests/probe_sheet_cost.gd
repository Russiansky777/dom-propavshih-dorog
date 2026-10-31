extends SceneTree
## Where ActorSheet.load_actor spends its time (31.10, стр. 16: transitions slower): JSON vs frames vs textures.

func _initialize() -> void:
	var AS = load("res://scripts/actors/actor_sheet.gd")
	for id in ["ilya_wife", "nina", "pelageya", "ilya_wife"]:
		var t0 := Time.get_ticks_usec()
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var dir := String(spec.get("sheet_dir", "res://assets/characters/" + id))
		var t1 := Time.get_ticks_usec()
		var sp = JSON.parse_string(FileAccess.get_file_as_string(dir + "/sprites.json"))
		var t2 := Time.get_ticks_usec()
		var n := 0
		for a in sp.get("actions", {}).values():
			n += (a.get("atlas", {}) as Dictionary).get("rects", []).size()
		var t3 := Time.get_ticks_usec()
		var sh = AS.load_actor(id)
		var t4 := Time.get_ticks_usec()
		print("SHEET %s json %.0f ms (%d rects, %d KB) | load_actor %.0f ms | frames %d anims" % [id, (t2 - t1) / 1000.0, n,
			FileAccess.get_file_as_bytes(dir + "/sprites.json").size() / 1024, (t4 - t3) / 1000.0, sh.frames.get_animation_names().size() if sh.frames else 0])
	quit(0)
