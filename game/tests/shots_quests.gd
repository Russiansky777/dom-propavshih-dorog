extends SceneTree
## Frames of the optional stories Q02 «На карте вырос сад» and Q06 «Второй верстак» (Director 23.10 11:51) from the
## real game — not a test, needs a display (tools/shots_quests.sh):
##   godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/shots_quests.gd -- <out_dir> [name ...]
## Saved as <out_dir>/q_<name>.png (1920x1080). Until the art of партия 8б comes, they show the engine's stand-ins.

var gs: Node
var rm: Node
var sr: Node
var main_node: Node
var mv: Node
var out_dir := ""

const SHOTS := ["q02_O1_map", "q02_map_look", "q02_O4_ulyana", "q02_map_trace", "q02_map_trace_line", "q06_O4_workshop",
	"q06_bench_step1", "q06_bench_step3", "q06_bench_step4", "q06_O4_shed_A", "q06_H2_bench_B",
	"ep_lesson_A", "ep_dinner_B", "ep_boat_A",
	# партия 8 in the old places
	"b8_O1_board", "b8_O1_board_here", "b8_S1_sign_removed", "b8_H1_coat", "b8_O4_bag_board", "b8_O3_night", "b8_M1_board",
	"b8_M1_closeup", "b8_Z3_day", "b8_R2_day", "b8_R3_day", "b8_H2_glass", "b8_H2_glass_closeup", "b8_ep_lesson", "b8_ep_dinner",
	"b8_ep_beam_roads", "b8_examine_watch", "b8_examine_journal", "b8_examine_key"]
const FREE := ["house_unlocked", "house_open", "done_M21b", "done_M22", "met_ilya", "met_ulyana", "met_nina", "morning_day3", "free_walk_day3", "school_path_open"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../Docs/evidence/M3")
	var names: Array = args.slice(1) if args.size() > 1 else SHOTS
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(2)
	rm.autosave_enabled = false
	mv = main_node.get_node("MechanicView")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for n in names:
		await _shot(String(n))
	gs.reset()
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _state(flags: Array, room: String, spawn: String = "default", free: bool = true) -> void:
	sr.close_mechanic()
	sr.close_view()
	sr.close_examine()
	sr.set_frame("")
	gs.reset()
	await process_frame
	for f in (FREE if free else []) + flags:
		gs.set_flag(String(f), true)
	rm.change_room(room, spawn)
	await _frames(6)
	var g := 0
	while not sr.current_beat.is_empty() and g < 50:
		sr.advance()
		await process_frame
		g += 1
	await _frames(4)


func _open(hotspot: String) -> void:
	var h = rm.current_room.get_node_or_null("Hotspots/" + hotspot)
	sr.open_mechanic(sr.mechanic_spec(h), hotspot)
	await _frames(70)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join("q_%s.png" % name))
	print("quest frame %s" % name)


func _panel():
	return mv.get("panel")


func _examine(item: String) -> void:
	gs.add_item(item)
	gs.set_flag("has_" + item, true)
	await process_frame
	sr.examine_item(item)
	await _frames(20)


func _shot(n: String) -> void:
	match n:
		"b8_O1_board":
			await _state(["board_mama", "v03_marked", "nina_answered_board", "q09_original_in_classroom"], "O1", "from_O2")
		"b8_O1_board_here":
			await _state(["board_here", "nina_answered_board"], "O1", "from_O2")
		"b8_S1_sign_removed":
			await _state(["lower_street_returned", "q09_original_in_classroom"], "S1")
		"b8_H1_coat":
			await _state(["done_M23c"], "H1")
		"b8_O4_bag_board":
			await _state(["done_M23a"], "O4", "from_O2")
		"b8_O3_night":
			await _state(["house_unlocked", "done_M17", "done_M18", "done_M19", "met_nina"], "O3", "default", false)
		"b8_M1_board":
			await _state(["house_unlocked", "done_N01", "done_M09", "met_pavel"], "M1", "default", false)
		"b8_M1_closeup":
			await _state(["house_unlocked", "done_N01", "done_M09", "met_pavel"], "M1", "default", false)
			var h = rm.current_room.get_node_or_null("Hotspots/schedule")
			sr.open_view(h.data["view"], "schedule")
			await _frames(60)
		"b8_Z3_day":
			await _state(["evening_dusk", "done_M15a", "done_M15", "done_M17", "done_M18", "done_M19", "done_M20"], "Z3")
		"b8_R2_day":
			await _state(["evening_dusk", "done_M18", "done_M20"], "R2")
		"b8_R3_day":
			await _state(["evening_dusk", "done_M18", "done_M20"], "R3")
		"b8_H2_glass":
			await _state(["office_mirror_mounted"], "H2", "from_H1")
		"b8_H2_glass_closeup":
			await _state(["office_mirror_mounted", "office_mirror_clamped"], "H2", "from_H1")
			await _open("stand_zm")
		"b8_ep_lesson":
			await _state([], "Z3")
			sr.set_frame("EP_lesson")
			await _frames(30)
		"b8_ep_dinner":
			await _state(["v01_cup_blue"], "Z3")
			sr.set_frame("EP_dinner")
			await _frames(30)
		"b8_ep_beam_roads":
			await _state(["beam_roads"], "Z3")
			sr.set_frame("EP_beam")
			await _frames(30)
		"b8_examine_watch":
			await _state([], "O1", "from_O2")   # (H1 with the free-day flags plays M23c)
			await _examine("pocket_watch")
		"b8_examine_journal":
			await _state([], "O1", "from_O2")   # (H1 with the free-day flags plays M23c)
			await _examine("journal_manager")
		"b8_examine_key":
			await _state([], "O1", "from_O2")   # (H1 with the free-day flags plays M23c)
			await _examine("key_house")
		"q02_O1_map":
			await _state([], "O1", "from_O2")
		"q02_map_look":
			await _state(["q02_seen_map"], "O1", "from_O2")
			await _open("village_map")
		"q02_O4_ulyana":
			await _state(["q02_seen_map"], "O4", "from_O2")
		"q02_map_trace":
			await _state(["q02_seen_map", "q02_asked_ulyana"], "O1", "from_O2")
			await _open("village_map")
		"q02_map_trace_line":
			await _state(["q02_seen_map", "q02_asked_ulyana"], "O1", "from_O2")
			await _open("village_map")
			var p = _panel()
			# draw the rows and half the path, as a player would (the pencil logic, no input needed for a frame)
			var path: KnotPath = p.path
			path.grab(path.end_point())
			for i in range(1, path.strokes[0].size()):
				var a: Vector2 = path.strokes[0][i - 1]
				var b: Vector2 = path.strokes[0][i]
				for k in 12:
					var r := path.drag(a.lerp(b, float(k + 1) / 12.0))
					if r != "move":
						p.call("_after", r)
			path.grab(path.end_point())
			var s1: PackedVector2Array = path.strokes[1]
			for k in 10:
				path.drag(s1[0].lerp(s1[1], float(k + 1) / 10.0))
			p.call("_draw_pencil")
			await _frames(4)
		"q06_O4_workshop":
			await _state([], "O4", "from_O2")
		"q06_bench_step1":
			await _state(["q06_started"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_step3":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_step4":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in", "q06_vise_tight"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_O4_shed_A":
			await _state(["q06_started", "q06_bench_built", "q06_table_at_ilya", "done_Q06"], "O4", "from_O2")
		"q06_H2_bench_B":
			await _state(["q06_started", "q06_bench_built", "q06_table_at_agata", "done_Q06"], "H2", "from_H1")
		"ep_lesson_A":
			await _state(["q02_old_under_new"], "Z3")
			sr.set_frame("EP_lesson")
			await _frames(30)
		"ep_dinner_B":
			await _state(["q02_new_primary", "q06_table_at_agata", "v01_photo_table"], "Z3")
			sr.set_frame("EP_dinner")
			await _frames(30)
		"ep_boat_A":
			await _state(["q06_table_at_ilya"], "Z3")
			sr.set_frame("EP_boat")
			await _frames(30)
	await _save(n)
