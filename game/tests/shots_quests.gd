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

const SHOTS := ["q02_O1_map", "q02_map_route", "q02_map_route_two", "q02_map_done", "q06_O4_workshop",
	"q06_bench_step1", "q06_bench_drag", "q06_bench_step2", "q06_bench_step3", "q06_bench_turn", "q06_bench_step5", "q06_bench_done",
	"q06_O4_shed_A", "q06_H2_bench_B",
	"ep_lesson_A", "ep_dinner_B", "ep_boat_A",
	# партия 8 in the old places
	"b8_O1_board", "b8_O1_board_here", "b8_H1_coat", "b8_O4_bag_board", "b8_O3_night", "b8_M1_board",
	"b8_M1_closeup", "b8_Z3_day", "b8_R2_day", "b8_R3_day", "b8_H2_glass", "b8_H2_glass_closeup", "b8_ep_lesson", "b8_ep_dinner",
	"b8_ep_beam_roads", "b8_examine_watch", "b8_examine_journal", "b8_examine_key",
	"j_view_H1_coat", "j_view_O3_letters", "j_view_O4_board",
	"j_ttt", "j_rhythm", "j_fish_wait", "j_fish_fight", "j_fish_caught", "j_signal_board", "j_tar"]
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
			await _state(["board_mama", "v03_marked", "nina_answered_board", "nina_wrote_date", "q09_original_in_classroom"], "O1", "from_O2")
		"b8_O1_board_here":
			await _state(["board_here", "nina_answered_board", "nina_wrote_date"], "O1", "from_O2")
		"b8_H1_coat":
			await _state(["done_M23c", "h1_scarf_removed", "h1_shutter_open"], "H1")
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
		"j_view_H1_coat", "j_view_O3_letters", "j_view_O4_board":   # стр. 80: whole close-ups in the carved frame
			var vs := {"j_view_H1_coat": [["done_M23c"], "H1", "nina_coat"], "j_view_O3_letters": [["done_M21"], "O3", "nina_letters"],
					"j_view_O4_board": [["done_M22"], "O4", "mitya_board"]}
			var v: Array = vs[n]
			await _state(v[0], v[1])
			var hv = rm.current_room.get_node_or_null("Hotspots/" + String(v[2]))
			if hv != null:
				sr.open_view(hv.data["view"], String(v[2]))
			await _frames(60)
		"j_ttt", "j_rhythm", "j_fish_wait", "j_fish_fight", "j_fish_caught":   # часть G: the games from the choices
			var gm := {"j_ttt": [["done_M03", "met_ulyana"], "O1", "ulyana", "tictactoe"], "j_rhythm": [["done_M03"], "H1", "tikhon", "rhythm"]}
			var g: Array = gm.get(n, [["done_M22", "met_mitya"], "O4", "mitya", "fishing"])
			await _state(g[0], g[1], "from_O2" if g[1] != "H1" else "default")
			var hm = rm.current_room.get_node_or_null("Hotspots/" + String(g[2]))
			var spec := {}
			if hm != null:
				for o in hm.data.get("choice", {}).get("options", []):
					if o.get("mechanic", {}).get("type", "") == g[3]:
						spec = o["mechanic"]
			sr.open_mechanic(spec, String(g[2]))
			await _frames(40)
			var pn = _panel()
			if pn != null:
				match n:
					"j_ttt":
						pn.call("play_cell", 4)
						await _frames(90)
						for c in [0, 2, 6, 8, 1, 3, 5, 7]:
							if pn.call("play_cell", c):
								break
						await _frames(90)
					"j_rhythm":
						var t0 := Time.get_ticks_msec()
						while String(pn.get("phase")) != "agata" and Time.get_ticks_msec() - t0 < 15000:
							await process_frame
						pn.call("tap")
						await _frames(30)
						pn.call("tap")
						await _frames(20)
					"j_fish_wait":
						await _frames(60)
					"j_fish_fight", "j_fish_caught":
						pn.set("phase", "bite")
						pn.set("phase_t", 0.0)
						pn.call("press", true)
						if n == "j_fish_fight":
							var g1: Array = pn.call("probe")["green"]
							var mid1 := (float(g1[0]) + float(g1[1])) * 0.5
							for f in 70:   # keep the string in the green a while — the fish is half way in
								pn.call("press", float(pn.call("probe")["tension"]) < mid1)
								await process_frame
						else:
							var g2: Array = pn.call("probe")["green"]
							var mid := (float(g2[0]) + float(g2[1])) * 0.5
							var t1 := Time.get_ticks_msec()
							while String(pn.call("probe")["phase"]) == "fight" and Time.get_ticks_msec() - t1 < 25000:
								pn.call("press", float(pn.call("probe")["tension"]) < mid)
								await process_frame
							await _frames(40)
		"j_signal_board":   # Р14, партия 10д: the painted board, the lines carved by the game
			await _state(["seen_ferry_instruction"], "R1", "default", false)
			var hs = rm.current_room.get_node_or_null("Hotspots/instruction")
			if hs != null:
				sr.open_view(hs.data["view"], "instruction")
			await _frames(60)
		"j_tar":   # Р5, партия 10д: the tar jar examined
			await _state(["has_tar"], "H2", "from_H1", false)
			await _examine("tar")
			await _frames(30)
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
		"q02_map_route":
			await _state(["q02_seen_map"], "O1", "from_O2")
			await _open("village_map")
		"q02_map_route_two":
			# H47: the school and Ulya's house shown — coloured, numbered; the garden next
			await _state(["q02_seen_map"], "O1", "from_O2")
			await _open("village_map")
			_panel().choose("school")
			_panel().choose("ilya_house")
			await _frames(40)
		"q02_map_done":
			await _state(["q02_seen_map"], "O1", "from_O2")
			await _open("village_map")
			for id in ["school", "ilya_house", "garden"]:
				_panel().choose(id)
			await _frames(70)
		"q06_O4_workshop":
			await _state([], "O4", "from_O2")
		"q06_bench_step1":
			await _state(["q06_started"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_drag":
			# H48: the key carried over the groove — lifted (shadow further), the place glowing
			await _state(["q06_started"], "O4", "from_O2")
			await _open("ilya_workshop")
			var p = _panel()
			var kn: Node2D = p.parts["key"]["node"]
			p.drag_id = "key"
			var to: Vector2 = p.call("_seat_of_step", "key")["pos"]
			kn.position = to + Vector2(-20, -26)
			p.call("_set_lift", "key", 1.0)
			p.over_target = true
			await _frames(20)
		"q06_bench_step2":
			await _state(["q06_started", "q06_fastening_fit"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_step3":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_turn":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in", "q06_screw_set"], "O4", "from_O2")
			await _open("ilya_workshop")
			var p2 = _panel()
			p2.turn_progress = 0.4
			p2.call("_apply_turn")
			p2.call("_draw_ring")
			await _frames(10)
		"q06_bench_step5":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in", "q06_screw_set", "q06_vise_tight"], "O4", "from_O2")
			await _open("ilya_workshop")
		"q06_bench_done":
			await _state(["q06_started", "q06_fastening_fit", "q06_stop_in", "q06_screw_set", "q06_vise_tight"], "O4", "from_O2")
			await _open("ilya_workshop")
			var p3 = _panel()
			p3.call("_apply", "board", p3.call("_xf", "board", "seat"))
			await _frames(10)
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
