extends SceneTree
## Frames of the shared mechanics (Director's notes 23.10, F4–F9, F12, F14) from the real game — not a test,
## needs a display (tools/shots_mechanics.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_mechanics.gd -- <out_dir> [name ...]
## Saved as <out_dir>/mech_<name>.png (1920x1080).

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node
var mv: Node
var ui: Node
var out_dir := ""

const SHOTS := ["examine_photo", "examine_plan", "examine_journal", "examine_watch", "examine_key_sluice", "examine_mirror",
	"examine_bag_badge", "fast_mirror", "fast_mirror_watch"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M2")
	var names: Array = args.slice(1) if args.size() > 1 else SHOTS
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	sd = root.get_node("StoryData")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	mv = main_node.get_node("MechanicView")
	ui = main_node.get_node("GameUi")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for n in names:
		await _shot(String(n))
	gs.reset()
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _state(flags: Array, items: Array, room: String = "H2") -> void:
	sr.close_examine()
	sr.close_mechanic()
	gs.reset()
	await process_frame
	for f in flags:
		gs.set_flag(String(f), true)
	for it in items:
		gs.add_item(String(it))
		gs.set_flag("has_" + String(it), true)
	rm.change_room(room, "default")
	await _frames(4)
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("mech_%s.png" % name)
	img.save_png(path)
	print("mech frame: ", path)


func _examine(id: String, items: Array) -> void:
	await _state(["house_unlocked"], items, "H1")
	sr.examine_item(id)
	await _frames(20)


func _mirror(hold_s: float) -> void:
	await _state(["done_M14", "nina_mirror_clamped", "house_unlocked", "h2_bundle_unwrapped"], ["pocket_watch", "journal_manager"])
	var h = rm.current_room.get_node_or_null("Hotspots/bundle_nina")
	sr.open_mechanic(sr.mechanic_spec(h), "bundle_nina")
	await _frames(3)
	var p = mv.panel
	p.fclock.advance(37.0)
	if hold_s > 0.0:
		p.hold_watch()
		while not sr.current_beat.is_empty():
			sr.advance()
			await process_frame
		p.hold_s = hold_s
		p.hold_start_nina = p.fclock.nina_elapsed_minutes() - hold_s * 20.0 / 60.0
		p.watch.seconds += hold_s
	await _frames(6)


func _shot(name: String) -> void:
	match name:
		"examine_photo":
			await _examine("photo_bridge", ["photo_bridge", "drawing_ilya", "plan_crossing"])
		"examine_plan":
			await _examine("plan_crossing", ["photo_bridge", "drawing_ilya", "plan_crossing"])
		"examine_journal":
			await _examine("journal_manager", ["journal_manager", "key_sluice", "clamp"])
		"examine_watch":
			await _examine("pocket_watch", ["pocket_watch", "mitten"])
		"examine_key_sluice":
			await _examine("key_sluice", ["journal_manager", "key_sluice", "clamp"])
		"examine_mirror":
			await _examine("mirror_mill", ["mirror_mill", "pocket_watch"])
		"examine_bag_badge":
			await _state(["house_unlocked"], ["pocket_watch", "photo_bridge", "plan_crossing", "drawing_ilya", "brace_plate"], "H1")
			var bag = ui.get("bag")
			bag.refresh()
			await _frames(2)
			var s = bag.slot_of("photo_bridge")
			s.hovered = true
			bag.call("_on_slot_hover", s)
			await _frames(4)
		"fast_mirror":
			await _mirror(0.0)
		"fast_mirror_watch":
			await _mirror(7.0)
		_:
			push_warning("shots_mechanics: unknown shot %s" % name)
			return
	await _save(name)
