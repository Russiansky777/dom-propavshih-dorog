extends SceneTree
## Director 01.11, стр. 41 (M15s, the brace): frames of the evening at the pier (R1) and at the turn (Z3) as the player
## sees them before the scene, under the narration's dusk (the stage `dim`) and after it (rendered; needs a display):
##   runx.sh -s res://tests/probe_light41.gd -- <out_dir> <tag>
## Writes <tag>_<moment>.png and <tag>_<moment>_bg.png (the same moment with the figures hidden — the background only).

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var out := ""
var tag := ""


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _figures(on: bool) -> void:
	var pl = rm.get("player")
	if pl != null:
		pl.visible = on
	var room = rm.current_room
	if room != null:
		for c in room.get_children():
			if String(c.name).begins_with("npc_"):
				c.visible = on


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, name])
	_figures(false)
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s_bg.png" % [out, tag, name])
	_figures(true)
	await _frames(1)
	print("SHOT ", name)


func _before(upto: String) -> void:
	for id in sd.scene_order:
		if id == upto:
			break
		var sc: Dictionary = sd.scene(id)
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
		for st in sc.get("stage", []):
			for f in st.get("sets", []):
				gs.set_flag(String(f), true)


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	out = a[0]
	tag = a[1]
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	await _frames(4)
	rm.autosave_enabled = false
	gs.reset()
	if a.size() > 2 and a[2] == "r3":
		# 02.11 (стр. 49, партия 15): Mitya's painted lantern at the far pier, evening before M18 — the engine glow on it
		_before("M18")
		rm.change_room("R3", "default")
		await _secs(2.5)
		await _shot("R3")
		print("DONE")
		quit(0)
		return
	if a.size() > 2 and a[2] == "states":
		# the same two places later the same evening (d2_evening before M16, d2_night before M18p)
		for st in [["M16", "evening"], ["M18p", "night"]]:
			gs.reset()
			_before(st[0])
			gs.set_flag("evening_dusk", true)
			for r in ["R1", "Z3"]:
				rm.change_room(r, "default")
				await _secs(2.5)
				await _shot("%s_%s" % [r, st[1]])
		print("DONE")
		quit(0)
		return
	_before("M15s")
	gs.set_flag("evening_dusk", true)
	# the pier at dusk, Agata come down from the street (as the player goes R1 → Z3)
	rm.change_room("R1", "default")
	await _secs(2.5)
	await _shot("R1")
	rm.change_room("Z3", "from_R1")
	await _secs(2.5)
	await _shot("Z3_pre")
	print("start ", sr.start_scene("M15s"), " busy ", sr.call("is_busy"))
	await _secs(1.0)
	sr.advance()   # «Села!» → Pelageya
	await _secs(0.6)
	# → the staging: she walks off, black, the room again under the narration's dusk
	var g0 := 0
	while float(sr.get("stage_dim")) <= 0.0 and g0 < 30:
		g0 += 1
		if not sr.call("is_staging"):
			sr.advance()
		await _secs(1.0)
	while sr.call("is_staging") and g0 < 60:
		g0 += 1
		await _secs(0.5)
	await _secs(1.2)
	print("dim ", sr.get("stage_dim"))
	await _shot("Z3_dim")
	sr.advance()   # the narration → the scene completes, the dusk lifts
	await _secs(2.5)
	var guard := 0
	while sr.call("is_busy") and guard < 20:
		guard += 1
		sr.advance()
		await _secs(0.5)
	await _secs(1.5)
	await _shot("Z3_post")
	print("DONE")
	quit(0)
