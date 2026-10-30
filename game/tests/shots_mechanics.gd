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
	"examine_bag_badge", "fast_mirror", "fast_mirror_watch", "water_R2", "water_M4", "water_R1_dusk", "water_Z3",
	"lantern_half", "lantern_open", "plate_brace", "plate_knot0", "plate_knot1", "plate_knot2", "plate_tied", "office_hook_sway", "crossing_0", "crossing_5", "crossing_9",
	"windlass_wait", "windlass_zone", "windlass_bumped", "windlass_laid", "shuttle_back_5", "map_far_bank", "z3_day4_site",
	"npc_M2_from_M1", "npc_M3_from_M2", "npc_M3_gauge", "npc_R3_stopor", "npc_R3_lamp_post", "npc_Z3_pier_plate", "npc_Z3_from_R1"]

## Agata at an item stand or an entry point next to an NPC (validate_rooms 9b): flags that show the NPC, then
## "spawn:<id>" or "stand:<hotspot>"; she faces the NPC.
const NPC_SHOTS := {
	"npc_M2_from_M1": ["M2", "pavel", "spawn:from_M1", ["house_unlocked", "office_unbolted"]],
	"npc_M3_from_M2": ["M3", "pavel", "spawn:from_M2", ["house_unlocked", "office_unbolted", "office_door_opened"]],
	"npc_M3_gauge": ["M3", "pavel", "stand:gauge", ["house_unlocked", "office_unbolted", "office_door_opened"]],
	"npc_R3_stopor": ["R3", "mitya", "stand:stopor", ["house_unlocked", "ferry_verified", "done_M18"]],
	"npc_R3_lamp_post": ["R3", "mitya", "stand:lamp_post", ["house_unlocked", "ferry_verified", "done_M18"]],
	"npc_Z3_pier_plate": ["Z3", "pelageya", "stand:pier_plate", ["house_unlocked", "evening_dusk", "done_M15a"]],
	"npc_Z3_from_R1": ["Z3", "pelageya", "spawn:from_R1", ["house_unlocked", "evening_dusk", "done_M15a"]],
}


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
		"map_far_bank":
			# G2: the plan after the far bank — the batch-9 layer and the new plaques.
			var vis := ["house_unlocked", "seen_plan_zarechye", "visited_Z1", "visited_Z4", "visited_Z2", "visited_H1", "visited_Z3", "visited_R1",
				"visited_M1", "visited_R2", "visited_R3", "visited_O4", "visited_O3", "visited_O1"]
			await _state(vis, [], "R3")
			var mp = ui.get("map_view")
			mp.call("open_from", Rect2())
			for i in 90:
				await process_frame
		"z3_day4_site":
			# G47: the turn on day four with the site (the windlass close-up put away).
			rm.start_at("span")
			for i in 10:
				await process_frame
			sr.call("_on_state_reset")
			if sr.mechanic_open:
				sr.close_mechanic()
			sr.set_frame("")
			for i in 30:
				await process_frame
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
		"water_R2", "water_M4", "water_R1_dusk", "water_Z3":
			var rid := name.get_slice("_", 1)
			var fl := ["house_unlocked", "ferry_verified"]
			if name.ends_with("dusk"):
				fl.append("evening_dusk")
			await _state(fl, [], rid)
			await _frames(30)
			await _save(name + "_a")
			await create_timer(0.7).timeout
		"plate_brace", "plate_knot0", "plate_knot1", "plate_knot2", "plate_tied":
			var fl := ["house_unlocked", "evening_dusk", "done_M15a", "skoba_on_plate"]
			if name != "plate_brace":
				fl += ["plate_braced", "rope_brought", "done_M15s"]
			if name == "plate_tied":
				fl += ["rope_on_ring"]
			await _state(fl, [], "Z3")
			var h = rm.current_room.get_node_or_null("Hotspots/pier_plate")
			sr.open_mechanic(sr.mechanic_spec(h), "pier_plate")
			await _frames(3)
			var p = mv.panel
			if name == "plate_brace":
				p.blows = 1
				p.timing.logic.hits = 1
				p.timing.logic.phase = 0.21
				p._refresh()
			elif name.begins_with("plate_knot"):
				var st := int(name.right(1))
				p.knot.stroke = st
				p.knot.progress = p.knot.lengths[st] * 0.55
				p._refresh()
			await _frames(6)
		"lantern_half", "lantern_open":
			# H35: the shutter plate lifted by the mouse — half way (following the pointer) and up (the flash).
			await _state(["house_unlocked", "rope_on_ring", "road_held_both_ends", "done_M16s", "far_snow_seen", "r1_seen_lantern"], [], "R1")
			var h = rm.current_room.get_node_or_null("Hotspots/lantern")
			sr.open_mechanic(sr.mechanic_spec(h), "lantern")
			await _frames(3)
			while not sr.current_beat.is_empty():
				sr.advance()
				await process_frame
			var p = mv.panel
			if name == "lantern_half":
				p._set_lid(0.5)
			else:
				p.spec["open_s"] = 99.0   # hold it open for the frame
				p.flash()
				await _frames(20)
			await _frames(3)
		"office_hook_sway":
			await _state(["house_unlocked", "done_N01", "done_M09", "done_M09s", "done_M09b", "met_pavel", "office_mirror_mounted", "office_mirror_clamped",
				"done_M10", "bell_clapper_hung", "has_bell_clapper", "lantern_check_seen", "done_M11"], [], "H2")
			var h = rm.current_room.get_node_or_null("Hotspots/stand_zm")
			sr.open_mechanic(sr.mechanic_spec(h), "stand_zm")
			await _frames(3)
			while not sr.current_beat.is_empty():
				sr.advance()
				await process_frame
			var p = mv.panel
			p.hook.apply("one")
			for i in 90:
				await process_frame
		"crossing_0", "crossing_5", "crossing_9":
			await _state(["house_unlocked", "ferry_verified", "done_M17"], [], "R2")
			while not sr.current_beat.is_empty() or sr.is_staging():
				if not sr.current_beat.is_empty():
					sr.advance()
				await process_frame
			if not sr.mechanic_open:
				sr.open_mechanic(sd.scene("M18p")["mechanics"][0]["spec"], "")
			await _frames(3)
			var p = mv.panel
			p.pulls = int(name.right(1))
			p.progress = float(p.pulls) / float(p.pulls_total)
			p.rope_phase = 37.0
			for i in 40:
				await process_frame
		"windlass_wait", "windlass_zone", "windlass_bumped", "windlass_laid":
			# G46: the first span close-up — the chalk mark on the ring, the gauge, «Подымай» after a bump.
			await _state(["house_unlocked", "ferry_verified", "boat_shuttle_open"], [], "R1")
			sr.open_mechanic(sd.scene("M25")["mechanics"][0]["spec"], "")
			await _frames(3)
			var p = mv.panel
			match name:
				"windlass_zone":
					p.logic.pos = p.logic.rest - p.logic.tolerance * 0.5
					p.logic.state = "down"
					p.logic.speed = 0.0
				"windlass_bumped":
					p.logic.pos = p.logic.rest + p.logic.tolerance + p.logic.bump_over
					p.logic.state = "bumped"
					p.signal_pressed("lower")
				"windlass_laid":
					p.logic.pos = p.logic.rest
					p.logic.state = "solved"
			for i in 40:
				await process_frame
		"shuttle_back_5":
			# G43: from the far pier back to Pelageya's by the rope (day three on).
			await _state(["house_unlocked", "ferry_verified", "boat_shuttle_open", "done_M18p", "crossing_hauled", "done_M18"], [], "R3")
			var e = rm.current_room.get_node_or_null("Exits/to_R2")
			sr.use_exit(e)
			await _frames(3)
			var p = mv.panel
			p.pulls = 5
			p.progress = 0.5
			p.rope_phase = 37.0
			for i in 40:
				await process_frame
		_ when NPC_SHOTS.has(name):
			var c: Array = NPC_SHOTS[name]
			var where := String(c[2])
			await _state(c[3], [], String(c[0]))
			var pl = rm.player
			var npc = rm.current_room.get_node_or_null("Hotspots/" + String(c[1]))
			if where.begins_with("spawn:"):
				rm.change_room(String(c[0]), where.get_slice(":", 1))
				await _frames(4)
				pl = rm.player
			else:
				var h = rm.current_room.get_node_or_null("Hotspots/" + where.get_slice(":", 1))
				pl.call("enter_room", rm.current_room, h.call("get_stand_position"))
			npc = rm.current_room.get_node_or_null("Hotspots/" + String(c[1]))
			if npc != null:
				pl.call("face_towards", npc.global_position)
			print("mech npc: ", name, " agata ", pl.global_position, " npc ", npc.global_position if npc != null else Vector2.ZERO,
				" npc visible ", npc != null and npc.visible)
			for i in 40:
				await process_frame
		_:
			push_warning("shots_mechanics: unknown shot %s" % name)
			return
	await _save(name)
