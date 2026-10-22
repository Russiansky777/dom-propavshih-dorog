class_name AmbientProbe
extends RefCounted
## Web-only measurement hooks of the ambient layer, active only when the page URL contains
## `ambientprobe` (tools/ambient_fps.mjs). Players never get them. On window:
##   ambientGoto(room, spawn)  — RoomManager.change_room (to measure a street without playing to it)
##   ambientWalk(x, y)         — Agata walks there (footfall through puddles and mud)
##   ambientEnable(on)         — ambient layer on/off in the current and next rooms (FPS comparison)
##   ambientFlag(flag, on)     — set a story flag (H1: shutters open → beam dust)
##   ambientItem(id, on)       — put an item into the bag (on = true, default) or take it out: a playtest
##                               starting in the middle of the game gets the items of that point
##   ambientParts(rain, sway, water) — show only some parts (cost of each part, FPS)
##   ambientState              — JSON-able stats, refreshed every 0.25 s: room, counts, fps

static var _registered: bool = false
static var _cbs: Array = []
static var _timer: Timer = null


static func register() -> void:
	if _registered or not OS.has_feature("web"):
		return
	_registered = true
	var search = JavaScriptBridge.eval("window.location.search", true)
	if search == null or String(search).find("ambientprobe") < 0:
		return
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var goto_cb := JavaScriptBridge.create_callback(_goto)
	var walk_cb := JavaScriptBridge.create_callback(_walk)
	var en_cb := JavaScriptBridge.create_callback(_enable)
	var flag_cb := JavaScriptBridge.create_callback(_flag)
	var parts_cb := JavaScriptBridge.create_callback(_parts)
	var item_cb := JavaScriptBridge.create_callback(_item)
	_cbs = [goto_cb, walk_cb, en_cb, flag_cb, parts_cb, item_cb]
	win.ambientGoto = goto_cb
	win.ambientWalk = walk_cb
	win.ambientEnable = en_cb
	win.ambientFlag = flag_cb
	win.ambientParts = parts_cb
	win.ambientItem = item_cb
	var tree := Engine.get_main_loop() as SceneTree
	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.autostart = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_publish)
	tree.root.add_child.call_deferred(_timer)
	JavaScriptBridge.eval("window.ambientProbeReady = true;", true)


static func _rm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("RoomManager")


static func _goto(args: Array) -> void:
	var rm := _rm()
	if rm != null and args.size() > 0:
		rm.call("change_room", String(args[0]), String(args[1]) if args.size() > 1 and args[1] != null else "default")


static func _walk(args: Array) -> void:
	var rm := _rm()
	if rm == null or args.size() < 2:
		return
	var p = rm.get("player")
	if p != null and is_instance_valid(p):
		p.call("walk_to", Vector2(float(args[0]), float(args[1])))


static func _enable(args: Array) -> void:
	var on := bool(args[0]) if args.size() > 0 else true
	AmbientBuilder.enabled = on
	var rm := _rm()
	if rm == null:
		return
	var amb := AmbientBuilder.of(rm.get("current_room"))
	if amb != null:
		amb.set_active(on)


static func _flag(args: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var gs := tree.root.get_node_or_null("GameState")
	if gs != null and args.size() > 0:
		gs.call("set_flag", String(args[0]), bool(args[1]) if args.size() > 1 else true)


## The item goes into the bag the way the story gives it (has_<id> set too, so no scene gives it again);
## on = false takes it out (has_<id> stays: it was given).
static func _item(args: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var gs := tree.root.get_node_or_null("GameState")
	if gs == null or args.size() < 1 or args[0] == null:
		return
	var id := String(args[0])
	var on := bool(args[1]) if args.size() > 1 and args[1] != null else true
	if on:
		gs.call("add_item", id)
		gs.call("set_flag", "has_" + id, true)
	else:
		gs.call("remove_item", id)


static func _parts(args: Array) -> void:
	var rm := _rm()
	var amb := AmbientBuilder.of(rm.get("current_room")) if rm != null else null
	if amb == null:
		return
	var show := [bool(args[0]) if args.size() > 0 else true, bool(args[1]) if args.size() > 1 else true, bool(args[2]) if args.size() > 2 else true]
	if amb.rain != null:
		amb.rain.visible = show[0]
	for n in amb.sway:
		n.visible = show[1]
	for n in amb.water:
		n.visible = show[2]


static func _publish() -> void:
	var rm := _rm()
	var state := {"fps": Engine.get_frames_per_second(), "enabled": AmbientBuilder.enabled}
	if rm != null:
		var room: Node = rm.get("current_room")
		state["room"] = String(room.get("room_id")) if room != null else ""
		var amb := AmbientBuilder.of(room)
		if amb != null:
			state.merge(amb.stats())
			if amb.footfall != null:
				var ev: Array = []
				for e in amb.footfall.events:
					ev.append({"frame": e["frame"], "x": e["pos"].x, "y": e["pos"].y, "surface": e["surface"], "scale": e["scale"]})
				state["events"] = ev
		var p = rm.get("player")
		if p != null and is_instance_valid(p):
			state["player"] = {"x": p.global_position.x, "y": p.global_position.y, "walking": p.call("is_walking")}
	JavaScriptBridge.eval("window.ambientState = %s;" % JSON.stringify(state), true)
