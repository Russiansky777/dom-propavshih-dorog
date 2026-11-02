extends SceneTree
## Frames of the villagers as NpcLive3D poses them (feet locks, calming, every modifier) through idle → talk → idle →
## listen, from the front-left and from the side, for an eye check of the Director's notes 01.11 (lines 6, 10, 52, 53,
## 55) and the before/after. Each frame: <out>/<id>_<state>_<t>_<view>.png; a contact sheet is made outside.
##   xvfb-run godot --fixed-fps 60 --path game -s res://tests/probe_villager_shots.gd -- <out dir> <id,id> [off=key,key]

const DT := 1.0 / 60.0
const SEQ := [["idle", 3.0, [2.9]], ["talk", 4.5, [0.25, 0.5, 1.2, 2.4, 4.2]], ["idle", 2.0, [1.9]], ["listen", 4.0, [1.0, 3.0]]]


func _initialize() -> void:
	_run()


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
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
	var ids: Array = String(a[1]).split(",")
	var off: Array = []
	if a.size() > 2 and String(a[2]).begins_with("off="):
		off = String(a[2]).substr(4).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		for yaw_deg in [25.0, 90.0]:
			var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
			for k in off:
				if k == "fb0111":   # the data as before the Director's notes 01.11 (lines 6, 10, 52, 53, 55)
					for kk in ["act_body", "arm_body", "pose_limit"]:
						(spec["rt3d"] as Dictionary).erase(kk)
					(spec["rt3d"]["feet"] as Dictionary).erase("boot")
					spec["rt3d"]["state_fade_s"] = 0.4
				(spec["rt3d"] as Dictionary).erase(k)
			var n := _fake_npc()
			var live = NL.new()
			n.add_child(live)
			if not live.setup(n, spec, 0.55):
				print("%s: not loaded" % id)
				n.queue_free()
				continue
			live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED   # drawn only for a shot (software GL)
			live.view.set_render_scale(1.5)
			var yaw := deg_to_rad(yaw_deg)
			live.face(Vector2(sin(yaw), cos(yaw) * 0.55), 0.55, true)
			for seg in SEQ:
				live.set_state(seg[0])
				var t := 0.0
				var shots: Array = (seg[2] as Array).duplicate()
				while t < float(seg[1]):
					live.process(DT)
					await process_frame
					t += DT
					if not shots.is_empty() and t >= float(shots[0]) - 1e-4:
						live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						var img: Image = live.view.get_texture().get_image()
						img.save_png("%s/%s_%s_%04.1f_%02d.png" % [out, id, seg[0], float(shots[0]), int(yaw_deg)])
						shots.pop_front()
			n.queue_free()
			await process_frame
	quit(0)
