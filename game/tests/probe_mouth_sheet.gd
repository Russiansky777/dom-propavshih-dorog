extends SceneTree
## The villagers' mouths close up — shut, half, fully open — front and three-quarter, one PNG each, for a contact sheet
## (Director 09.11, 21:56: «ты не видишь, что рот сделан плохо?»; 22:18: «рты открывающиеся и нормальные»). The figure
## alone, as the game builds it (NpcLive3D, every modifier), its own render camera zoomed on the head.
##   xvfb-run godot --fixed-fps 60 --path game -s res://tests/probe_mouth_sheet.gd -- <out dir> <id,id|all> [yaws=0,35] [opens=0,0.5,1] [px=360] [view_m=0.30]
## Files: <out>/<id>_<yaw>_<open×100>.png. Env MOUTH_DEBUG=1 — the shader's debug colours.

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


func _zoom_on_head(view, px: int, view_m: float, on_mouth := Vector3.INF) -> void:
	view.size = Vector2i(px, px)
	var cam: Camera3D = view.camera
	cam.size = view_m
	for i in 3:
		await process_frame
		var sk: Skeleton3D = view.skeleton
		var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
		var off := 0.10
		if on_mouth != Vector3.INF:   # the mouth in the middle of the tile (the lip line as measured, before the hand shift)
			p = on_mouth
			off = 0.0
		var at: Vector2 = cam.unproject_position(p)
		var c := Vector2(view.size) * 0.5
		var m_per_px := cam.size / float(view.size.y)
		cam.global_position += cam.global_transform.basis.x * (at.x - c.x) * m_per_px
		cam.global_position -= cam.global_transform.basis.y * (at.y - c.y + view.size.y * off) * m_per_px


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ids: Array = ALL if a.size() < 2 or a[1] == "all" else Array(String(a[1]).split(","))
	var yaws: Array = [0.0, 35.0]
	var opens: Array = [0.0, 0.5, 1.0]
	var px := 360
	var view_m := 0.30
	for i in range(2, a.size()):
		var kv := String(a[i]).split("=")
		if kv[0] == "yaws":
			yaws = []
			for y in kv[1].split(","):
				yaws.append(float(y))
		elif kv[0] == "opens":
			opens = []
			for o in kv[1].split(","):
				opens.append(float(o))
		elif kv[0] == "px":
			px = int(kv[1])
		elif kv[0] == "view_m":
			view_m = float(kv[1])
	DirAccess.make_dir_recursive_absolute(out)
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for yaw_deg in yaws:
			var n := _fake_npc()
			n.set("actor_id", id)
			var live = NL.new()
			n.add_child(live)
			if not live.setup(n, spec, 0.55):
				print("%s: not loaded" % id)
				n.queue_free()
				continue
			live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var yaw := deg_to_rad(yaw_deg)
			live.face(Vector2(sin(yaw), cos(yaw) * 0.55) * 100.0, 0.55, true)
			live.set_state("talk")
			var t := 0.0
			while t < 0.7:
				live.process(DT)
				await process_frame
				t += DT
			var jaw = live.get("jaw")
			if jaw == null:
				print("%s: no jaw" % id)
				n.queue_free()
				continue
			if OS.get_environment("MOUTH_DEBUG") != "":
				live.view.material.set_shader_parameter("debug_mouth", true)
			var centre := Vector3.INF
			if OS.get_environment("MOUTH_CENTRE") != "" and jaw.call("painted"):
				var sh: Vector3 = jaw.get("shift_mm")
				var mf: Transform3D = jaw.call("mouth_frame")
				var u: float = 1.0 / maxf(live.view.skeleton.global_transform.basis.get_scale().y, 1e-6) * 0.001
				centre = mf.origin - mf.basis.x * (sh.x * u) - mf.basis.y * (sh.y * u)
			await _zoom_on_head(live.view, px, view_m, centre)
			jaw.speaking_override = 1
			for o in opens:
				jaw.level_override = lerpf(jaw.db_closed, jaw.db_open, float(o)) if float(o) > 0.0 else -100.0
				for i in 16:
					await process_frame
				live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				live.view.get_texture().get_image().save_png("%s/%s_%02d_%03d.png" % [out, id, int(yaw_deg), int(float(o) * 100.0)])
			if yaw_deg == yaws[0]:
				print("  %s: jaw open %.2f, mouth %s" % [id, jaw.open, str(jaw.call("describe")) if jaw.has_method("describe") else "-"])
			n.queue_free()
			await process_frame
		print("shot ", id)
	quit(0)
