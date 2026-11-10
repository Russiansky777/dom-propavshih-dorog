extends SceneTree
## The villagers standing and talking, front / three-quarter / side, one PNG each — for a contact sheet «before / after»
## (Director 09.11, 22:18: arms, the soldier-like stance). NpcLive3D as in the game (every modifier).
##   xvfb-run godot --fixed-fps 60 --path game -s res://tests/probe_stance_sheet.gd -- <out dir> <id,id|all> [yaws=0,35,90] [shots=idle:2.0,talk:1.2,talk:2.6]
## Files: <out>/<id>_<yaw>_<state>_<t>.png

const DT := 1.0 / 60.0
const ALL := ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ids: Array = ALL if a.size() < 2 or a[1] == "all" else Array(String(a[1]).split(","))
	var yaws: Array = [0.0, 35.0, 90.0]
	var shots: Array = [["idle", 2.0], ["talk", 1.2], ["talk", 2.6]]
	for i in range(2, a.size()):
		var kv := String(a[i]).split("=")
		if kv[0] == "yaws":
			yaws = []
			for y in kv[1].split(","):
				yaws.append(float(y))
		elif kv[0] == "shots":
			shots = []
			for sh in kv[1].split(","):
				shots.append([sh.get_slice(":", 0), float(sh.get_slice(":", 1))])
	DirAccess.make_dir_recursive_absolute(out)
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for yaw_deg in yaws:
			var n := _fake_npc()
			var live = NL.new()
			n.add_child(live)
			if not live.setup(n, spec, 0.55):
				print("%s: not loaded" % id)
				n.queue_free()
				continue
			live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var yaw := deg_to_rad(yaw_deg)
			live.face(Vector2(sin(yaw), cos(yaw) * 0.55) * 100.0, 0.55, true)   # (shorter than 1 px is ignored)
			var state := ""
			var t := 0.0
			for sh in shots:
				if String(sh[0]) != state:
					state = String(sh[0])
					if state.begins_with("walk"):
						# walk[<turn deg>]: sets off walking, turning by that much as she goes (as npc_go: face + walk);
						# speed 0.9 m/s at the room scale the probe's fake npc has
						var turn := float(state.trim_prefix("walk")) if state.length() > 4 else 0.0
						var y2 := yaw + deg_to_rad(turn)
						live.face(Vector2(sin(y2), cos(y2) * 0.55) * 100.0, 0.55, false)
						live.walk(true, 0.9 * live.view.ppm * 0.55, 0.55)
					elif state.begins_with("act_"):
						# a one-shot action (rt3d.clips role): act_write_board
						print("  %s %s: %.2f s" % [id, state, live.view.action_length(state.trim_prefix("act_"))])
						if OS.get_environment("ACT_ARM_DROP") != "":   # the acting arm lowered (+) or raised (−) by that many degrees
							live.set_act_arm({"side": "Right", "drop_deg": float(OS.get_environment("ACT_ARM_DROP"))}, state.trim_prefix("act_"))
						live.play_once(state.trim_prefix("act_"))
					else:
						live.set_state(state)
					t = 0.0
				while t < float(sh[1]):
					live.process(DT)
					await process_frame
					t += DT
				live.view.set_render_scale(float(OS.get_environment("STANCE_SCALE")) if OS.get_environment("STANCE_SCALE") != "" else 2.0)   # NpcLive3D.process sets its own each frame
				live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				live.view.get_texture().get_image().save_png("%s/%s_%02d_%s_%.1f.png" % [out, id, int(yaw_deg), state, float(sh[1])])
			n.queue_free()
			await process_frame
		print("shot ", id)
	quit(0)
