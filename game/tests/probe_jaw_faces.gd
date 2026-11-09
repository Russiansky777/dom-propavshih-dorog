extends SceneTree
## Faces close up with the jaw shut / half / fully open (Director 09.11, 21:21 — the mouth by the voice), in the game
## itself: a start point's room, every live villager there with a jaw; its own render camera zoomed on the head.
##   xvfb-run godot --path game --display-driver x11 --rendering-driver opengl3 -s res://tests/probe_jaw_faces.gd -- \
##       <out_dir> <start_point> [max_deg,max_deg,…]
## Writes <out>/<id>_<deg>_<open>.png.


func _initialize() -> void:
	_run()


func _zoom_on_head(view) -> void:
	view.size = Vector2i(420, 420)
	var cam: Camera3D = view.camera
	cam.size = 0.32
	for i in 4:
		await process_frame
		var sk: Skeleton3D = view.skeleton
		var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
		var px: Vector2 = cam.unproject_position(p)
		var c := Vector2(view.size) * 0.5
		var m_per_px := cam.size / float(view.size.y)
		cam.global_position += cam.global_transform.basis.x * (px.x - c.x) * m_per_px
		cam.global_position -= cam.global_transform.basis.y * (px.y - c.y + view.size.y * 0.08) * m_per_px


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var sp: String = a[1]
	var degs: Array = []
	for s in (a[2] if a.size() > 2 else "6").split(","):
		degs.append(float(s))
	var rm = root.get_node("RoomManager")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	rm.start_at(sp)
	for i in 40:
		await process_frame
	for n in root.find_children("*", "Node2D", true, false):
		var live = n.get("live")
		if live == null or not (live is Object) or live.get("jaw") == null:
			continue
		var id := String(n.get("actor_id"))
		if OS.get_environment("ONLY_ID") != "" and not OS.get_environment("ONLY_ID").split(",").has(id):
			continue
		var jaw = live.jaw
		await _zoom_on_head(live.view)
		if OS.get_environment("CAVITY_GREEN") != "":
			for mi in live.view.meshes:
				print("  mesh %s surfaces %d override %s mat0 %s" % [mi.name, mi.mesh.get_surface_count(), mi.material_override, mi.get_active_material(0).resource_name if mi.get_active_material(0) else "-"])
				if String(mi.name).contains("cavity"):
					var gm := StandardMaterial3D.new()
					gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					gm.albedo_color = Color(0, 1, 0)
					gm.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.material_override = gm
		jaw.speaking_override = 1
		if OS.get_environment("DEBUG_MOUTH") != "":
			live.view.material.set_shader_parameter("debug_mouth", true)
		for deg in degs:
			jaw.max_deg = deg
			for o in [0.0, 0.5, 1.0]:
				jaw.level_override = lerpf(jaw.db_closed, jaw.db_open, o) if o > 0.0 else -100.0
				for i in 20:
					await process_frame
				await RenderingServer.frame_post_draw
				live.view.get_texture().get_image().save_png("%s/%s_%02d_%d.png" % [out, id, int(deg), int(o * 100)])
				print("%s max %.0f° open %.2f (shown %.2f)" % [id, deg, o, jaw.open])
		jaw.speaking_override = -1
		jaw.level_override = NAN
	quit(0)
