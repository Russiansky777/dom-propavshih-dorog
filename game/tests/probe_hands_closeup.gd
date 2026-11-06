extends SceneTree
## Close-up frames of a villager's hands as NpcLive3D poses them (Director 06.11, 15:56: «Павел слушает стало даже хуже,
## руки въезжают в тело, остальных тоже коробит»): one state (or a one-shot clip) from several sides, big, for an eye
## check of hands against the apron / coat / skirt. Each frame: <out>/<id>_<state>_<t>_<yaw>.png.
##   xvfb-run godot --fixed-fps 60 --path game -s res://tests/probe_hands_closeup.gd -- <out> <id> <state|clip:name> \
##       <yaw,yaw> <t,t> [scale=4] [off=key,key] [rt={"key": value}]

const DT := 1.0 / 60.0


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
	var id: String = a[1]
	var state: String = a[2]
	var yaws: Array = String(a[3]).split(",")
	var times: Array = String(a[4]).split(",")
	var sc := 4.0
	var off: Array = []
	var over := {}
	for k in range(5, a.size()):
		var s := String(a[k])
		if s.begins_with("rt="):   # rt={"act_body": {...}} — rt3d keys replaced (a try before the data)
			over = JSON.parse_string(s.substr(3))
		elif s.begins_with("off="):
			off = s.substr(4).split(",")
		elif s.begins_with("scale="):
			sc = float(s.substr(6))
	DirAccess.make_dir_recursive_absolute(out)
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for yv in yaws:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for k in off:
			(spec["rt3d"] as Dictionary).erase(k)
		for k in over.keys():
			if over[k] is Dictionary and spec["rt3d"].get(k) is Dictionary:
				(spec["rt3d"][k] as Dictionary).merge(over[k], true)
			else:
				spec["rt3d"][k] = over[k]
		spec["rt3d"]["min_render_scale"] = sc   # big, whatever the frame's on-screen size
		spec["rt3d"]["max_render_scale"] = sc
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			print("%s: not loaded" % id)
			quit(1)
			return
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		live.view.set_render_scale(sc)
		var yaw := deg_to_rad(float(yv))
		live.face(Vector2(sin(yaw), cos(yaw) * 0.55), 0.55, true)
		live.set_state("idle")
		for i in 60:
			live.process(DT)
			await process_frame
		if state.begins_with("clip:"):
			live.play_once(state.substr(5), true)
		else:
			live.set_state(state)
		var t := 0.0
		var shots: Array = times.duplicate()
		while not shots.is_empty():
			live.process(DT)
			await process_frame
			t += DT
			if t >= float(shots[0]) - 1e-4:
				live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img: Image = live.view.get_texture().get_image()
				img.save_png("%s/%s_%s_%04.1f_%03d.png" % [out, id, state.replace("clip:", ""), float(shots[0]), int(float(yv))])
				shots.pop_front()
		n.queue_free()
		await process_frame
	quit(0)
