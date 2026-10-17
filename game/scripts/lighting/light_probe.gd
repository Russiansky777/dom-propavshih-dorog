class_name LightProbe
extends RefCounted
## Web-only measurement hooks of the room lighting, active only when the page URL contains
## `lightprobe` (tools/light_fps.mjs). Players never get them. On window:
##   lightGoto(room, "f1,f2", x, y) — fresh state with these flags, enter the room, Agata at (x, y)
##   lightEnable(on)                — lighting on/off (the room is re-entered at the same spot)
##   lightWalk(x, y)                — Agata walks there (cast shadows while moving)
##   lightOnly("id1,id2")           — keep only these sources on (cost of each source)
##   lightState                     — JSON, refreshed every 0.25 s: room, fps, sources and their
##                                    levels, cast shadows attached, Agata's tone

static var _registered: bool = false
static var _cbs: Array = []


static func register() -> void:
	if _registered or not OS.has_feature("web"):
		return
	_registered = true
	var search = JavaScriptBridge.eval("window.location.search", true)
	if search == null or String(search).find("lightprobe") < 0:
		return
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var goto_cb := JavaScriptBridge.create_callback(_goto)
	var en_cb := JavaScriptBridge.create_callback(_enable)
	var walk_cb := JavaScriptBridge.create_callback(_walk)
	var only_cb := JavaScriptBridge.create_callback(_only)
	_cbs = [goto_cb, en_cb, walk_cb, only_cb]
	win.lightOnly = only_cb
	win.lightGoto = goto_cb
	win.lightEnable = en_cb
	win.lightWalk = walk_cb
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_publish)
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(timer)
	JavaScriptBridge.eval("window.lightProbeReady = true;", true)


static func _node(n: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null(n)


static func _goto(args: Array) -> void:
	var rm := _node("RoomManager")
	var gs := _node("GameState")
	if rm == null or gs == null or args.size() < 1:
		return
	gs.call("reset")
	if args.size() > 1 and args[1] != null:
		for f in String(args[1]).split(",", false):
			gs.call("set_flag", f.strip_edges(), true)
	var pos := Vector2(float(args[2]), float(args[3])) if args.size() > 3 else Vector2.INF
	rm.call("change_room", String(args[0]), "" if pos != Vector2.INF else "default", pos)


static func _enable(args: Array) -> void:
	RoomLighting.enabled = bool(args[0]) if args.size() > 0 else true
	var rm := _node("RoomManager")
	if rm == null:
		return
	var room: Node = rm.get("current_room")
	var p = rm.get("player")
	if room != null and p != null:
		rm.call("change_room", String(room.get("room_id")), "", p.global_position)


## lightOnly("id1,id2"): every other source of the current room is switched off (cost per source).
static func _only(args: Array) -> void:
	var rm := _node("RoomManager")
	if rm == null:
		return
	var room: Node = rm.get("current_room")
	var rl: RoomLighting = room.get_node_or_null("Lighting") as RoomLighting if room != null else null
	if rl == null:
		return
	var keep := String(args[0]).split(",", false) if args.size() > 0 and args[0] != null else PackedStringArray()
	for s in rl.sources:
		if not keep.has(s.source_id):
			s.set_process(false)
			s.data["if"] = ["__probe_off__"]
			s.refresh(true)


static func _walk(args: Array) -> void:
	var rm := _node("RoomManager")
	if rm == null or args.size() < 2:
		return
	var p = rm.get("player")
	if p != null and is_instance_valid(p):
		p.call("walk_to", Vector2(float(args[0]), float(args[1])))


static func _publish() -> void:
	var rm := _node("RoomManager")
	var state := {"fps": Engine.get_frames_per_second(), "enabled": RoomLighting.enabled}
	if rm != null:
		var room: Node = rm.get("current_room")
		state["room"] = String(room.get("room_id")) if room != null else ""
		var rl: RoomLighting = room.get_node_or_null("Lighting") as RoomLighting if room != null else null
		if rl != null:
			var src := {}
			for s in rl.sources:
				src[s.source_id] = {"type": s.kind, "level": snappedf(s.level, 0.01), "strength": snappedf(s.lm_strength, 0.001) if s.lm != null else null}
			state["sources"] = src
			state["shadows"] = rl.shadows.size()
		var p = rm.get("player")
		if p != null and is_instance_valid(p):
			var spr = p.get("sprite")
			state["player"] = {"x": p.global_position.x, "y": p.global_position.y, "walking": p.call("is_walking"),
				"tone": [snappedf(spr.self_modulate.r, 0.01), snappedf(spr.self_modulate.g, 0.01), snappedf(spr.self_modulate.b, 0.01)] if spr is CanvasItem else null}
	JavaScriptBridge.eval("window.lightState = %s;" % JSON.stringify(state), true)
