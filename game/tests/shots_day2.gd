extends SceneTree
## Frames of day two from the real game (not a test; needs a display — tools/shots_day2.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_day2.gd -- <out_dir> [name ...]
## Rooms M1–M4, R2, R3 and the close-ups (the office mirror with the lantern light and the hook, the sluice,
## mother's mirror, the plate with the brace and the rope, the three lights, the photo in the passage),
## each in the story state it is seen in. Saved as <out_dir>/day2_<name>.png (1920x1080).

var gs: Node
var rm: Node
var sr: Node
var sd: Node
var main_node: Node
var player: Node2D
var mv: Node
var out_dir := ""

const SHOTS := ["M1", "M2", "M3", "M4", "R2", "R3", "Z3_evening", "R1_dusk", "R1_answered", "H2_mirror", "office_mirror", "office_hook", "sluice", "fast_mirror", "plate", "plate_rope", "plate_tied", "lantern", "photo"]


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
	player = main_node.get_node("World/Player")
	mv = main_node.get_node("MechanicView")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for n in names:
		await _shot(String(n))
	gs.reset()
	quit(0)


func _flags(list: Array) -> void:
	for f in list:
		gs.set_flag(String(f), true)


func _day(level: int) -> void:
	gs.reset()
	await process_frame
	var steps := [
		["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "done_M07", "done_M08", "done_N01", "night_day1", "house_unlocked", "house_open", "met_tikhon", "door_school_installed", "seen_bell", "seen_workshop", "knows_crossing_plan"],
		["done_N01", "done_M09", "met_pavel"],
		["done_M09s", "seen_office_door", "seen_office_photo", "seen_shift_schedule", "done_M09b", "has_mirror_mill"],
		["office_mirror_mounted", "office_mirror_clamped", "done_M10", "bell_clapper_hung", "has_bell_clapper", "lantern_check_seen", "done_M11"],
		["office_unbolted", "done_M12", "office_shelf_lifted", "done_M13a"],
		["done_M13", "has_key_sluice", "has_journal_manager", "has_clamp", "sluice_key_inserted"],
		["sluice_opened", "pond_lowered", "done_M14"],
		["nina_mirror_clamped", "nina_time_compared", "evening_dusk", "done_M15a", "has_brace_plate", "skoba_on_plate"],
		["plate_braced", "rope_brought", "done_M15s", "rope_on_ring", "done_M15"],
		["three_lights_sent", "far_lights_answered", "road_held_both_ends", "done_M16", "ferry_verified", "done_M17", "has_school_ribbon"],
	]
	for i in mini(level + 1, steps.size()):
		_flags(steps[i])


func _room(rid: String, at := Vector2.INF) -> void:
	rm.change_room(rid, "default")
	for i in 10:
		await physics_frame
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	if at != Vector2.INF:
		player.call("walk_to", at)
		var frames := 0
		while player.call("is_walking") and frames < 1500:
			await physics_frame
			frames += 1


func _open(hotspot: String) -> void:
	var h = rm.current_room.get_node_or_null("Hotspots/" + hotspot)
	if h == null:
		push_error("shots_day2: no hotspot " + hotspot)
		return
	sr.open_mechanic(sr.mechanic_spec(h), hotspot)
	await process_frame
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame


func _shot(name: String) -> void:
	sr.close_mechanic()
	match name:
		"M1":
			await _day(0)
			await _room("M1", Vector2(820, 760))
		"M2":
			await _day(1)
			await _room("M2", Vector2(1150, 860))
		"M3":
			await _day(4)
			await _room("M3", Vector2(1100, 860))
		"M4":
			await _day(5)
			await _room("M4", Vector2(950, 820))
		"R2":
			await _day(9)
			_flags(["done_M18p"])
			await _room("R2", Vector2(900, 990))
		"R3":
			await _day(9)
			_flags(["done_M18p", "done_M18", "met_mitya"])
			await _room("R3", Vector2(1000, 920))
		"Z3_evening":
			await _day(7)
			await _room("Z3", Vector2(1000, 860))
		"R1_dusk":
			await _day(8)
			await _room("R1", Vector2(900, 900))
		"H2_mirror":
			await _day(3)
			gs.set_flag("has_brace_plate", false)
			await _room("H2", Vector2(820, 880))
		"plate_tied":
			await _day(8)
			await _room("Z3")
			await _open("pier_plate")
		"R1_answered":
			await _day(9)
			await _room("R1", Vector2(900, 900))
		"office_mirror":
			await _day(2)
			_flags(["office_mirror_mounted", "office_mirror_clamped", "bell_clapper_hung", "lantern_check_seen"])
			await _room("H2")
			await _open("stand_zm")
			var p = mv.panel
			p.office.light_on = true
			p.office.hook_visible = false
			p.office.refresh()
		"office_hook":
			await _day(3)
			await _room("H2")
			await _open("stand_zm")
			var p = mv.panel
			p.hook.apply("one")
			for i in 40:
				p.hook.step(0.1)
			p.hook.apply("two")
			p.office.hook_frac = p.hook.pos
			p._set_status()
			p.office.refresh()
		"sluice":
			await _day(5)
			gs.set_counter("mech.sluice.notch", 1)
			await _room("M4")
			await _open("gate")
			mv.panel.logic.level = 0.86
		"fast_mirror":
			await _day(6)
			_flags(["nina_mirror_clamped"])
			await _room("H2")
			await _open("bundle_nina")
			mv.panel.fclock.advance(40.0)
		"plate":
			await _day(7)
			await _room("Z3")
			await _open("pier_plate")
		"plate_rope":
			await _day(7)
			_flags(["plate_braced", "rope_brought", "done_M15s"])
			await _room("Z3")
			await _open("pier_plate")
		"lantern":
			await _day(9)
			await _room("R1")
			await _open("lantern")
		"photo":
			await _day(1)
			await _room("M2")
			await _open("photo")
	for i in 90:
		await process_frame
	while not sr.current_beat.is_empty():
		sr.advance()
		await process_frame
	root.warp_mouse(Vector2(4, 1076))
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join("day2_%s.png" % name)
	img.save_png(path)
	print("day2 frame %s → %s" % [name, path])
