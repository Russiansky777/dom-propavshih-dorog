class_name NpcProbe
extends RefCounted
## I-T4b: web-only hooks for frames of the villagers in their rooms, active only when the page URL contains
## `npcprobe` (tools/i_t4b_web.mjs). Players never get them. On window:
##   npcShow(id)            — fresh state, the first room where `id` stands as an npc hotspot, the villager shown
##   npcSet(id, state, dir) — idle / listen / talk (as in a conversation) or walk (the walk cycle in place, row dir)
##   npcInfo                — JSON, refreshed every 0.25 s: room, villager's feet on the canvas, viewport size, sheet dir

static var _registered: bool = false
static var _cbs: Array = []


static func register() -> void:
	if _registered or not OS.has_feature("web"):
		return
	_registered = true
	var search = JavaScriptBridge.eval("window.location.search", true)
	if search == null or String(search).find("npcprobe") < 0:
		return
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var show_cb := JavaScriptBridge.create_callback(_show_room)
	var set_cb := JavaScriptBridge.create_callback(_set_state)
	_cbs = [show_cb, set_cb]
	win.npcShow = show_cb
	win.npcSet = set_cb
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_publish)
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(timer)
	JavaScriptBridge.eval("window.npcProbeReady = true;", true)


static func _node(n: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null(n)


static func _room_of(id: String) -> String:
	var d := DirAccess.open("res://data/story/rooms")
	if d == null:
		return ""
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


static func _npc(id: String) -> Node2D:
	return (Engine.get_main_loop() as SceneTree).root.find_child("npc_" + id, true, false) as Node2D


static func _show_room(args: Array) -> void:
	var rm := _node("RoomManager")
	var gs := _node("GameState")
	if rm == null or gs == null or args.size() < 1:
		return
	var id := String(args[0])
	var rid := _room_of(id)
	if rid == "":
		return
	gs.call("reset")
	gs.call("set_flag", "done_M01", true)
	rm.set("autosave_enabled", false)
	rm.call("change_room", rid, "default")


static func _set_state(args: Array) -> void:
	if args.size() < 2:
		return
	var npc := _npc(String(args[0]))
	if npc == null:
		return
	npc.get("hotspot").visible = true
	npc.visible = true
	npc.modulate.a = 1.0
	var st := String(args[1])
	if st == "walk":
		var sheet = npc.get("sheet")
		if sheet == null or not sheet.has_action(sheet.walk_action):
			return
		var d := int(args[2]) if args.size() > 2 and args[2] != null else 2
		npc.set("direction", d)
		npc.set("shown_dir", d)
		npc.call("_play", sheet.anim_name(sheet.walk_action, d))
		return
	npc.call("set_state", st)


static func _publish() -> void:
	var rm := _node("RoomManager")
	var info := {}
	if rm != null:
		var room: Node = rm.get("current_room")
		info["room"] = String(room.get("room_id")) if room != null else ""
	var tree := Engine.get_main_loop() as SceneTree
	var vp := tree.root.get_viewport()
	info["viewport"] = [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y]
	var npcs := {}
	for n in tree.root.find_children("npc_*", "", true, false):
		if n is Node2D and n.get("sheet") != null:
			var p: Vector2 = vp.get_canvas_transform() * (n as Node2D).global_position
			var sh = n.get("sheet")
			npcs[String(n.name).trim_prefix("npc_")] = {"x": p.x, "y": p.y, "scale": (n as Node2D).scale.x,
				"visible": (n as Node2D).visible, "sheet_dir": String(sh.sheet_dir), "texture_scale": sh.texture_scale,
				"anim": String(n.get("sprite").animation) if n.get("sprite") != null else ""}
	info["npcs"] = npcs
	JavaScriptBridge.eval("window.npcInfo = %s;" % JSON.stringify(info), true)
