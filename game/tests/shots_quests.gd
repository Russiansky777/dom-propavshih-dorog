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
	"ep_lesson_A", "ep_dinner_B", "ep_boat_A"]
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


func _state(flags: Array, room: String, spawn: String = "default") -> void:
	sr.close_mechanic()
	sr.set_frame("")
	gs.reset()
	await process_frame
	for f in FREE + flags:
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


func _shot(n: String) -> void:
	match n:
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
