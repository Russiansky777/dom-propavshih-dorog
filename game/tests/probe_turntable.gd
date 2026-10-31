extends SceneTree
## A GLB on a turntable, frames to PNG (rendered; needs a display). Agata v5 candidates for the Director (31.10).
##   godot --path game -s res://tests/probe_turntable.gd -- <model.glb> <out_dir> [frames=48] [anim=1]
## The model is read at run time (GLTFDocument), lit like a soft overcast day, the camera at eye height, 14° down.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var path := a[0]
	var out := a[1]
	var n := int(a[2]) if a.size() > 2 else 48
	var play_anim := a.size() > 3 and a[3] == "1"
	DirAccess.make_dir_recursive_absolute(out)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		print("TURN cannot read ", path)
		quit(1)
		return
	var model: Node3D = doc.generate_scene(st)
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 960)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.85, 0.83)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.86)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	await process_frame
	# bounds → frame the figure
	var aabb := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	var h := aabb.size.y
	var c := aabb.get_center()
	model.position = Vector3(-c.x, -aabb.position.y, -c.z)
	if h < 0.3:
		# a rigged game model (skinned mesh in bind space, armature scaled): feet at the origin, 1.65 m
		h = 1.65
		model.position = Vector3.ZERO
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.12
	vp.add_child(cam)
	await process_frame
	var el := deg_to_rad(14.0)
	var d := 6.0
	cam.look_at_from_position(Vector3(0, h * 0.52 + d * sin(el), d * cos(el)), Vector3(0, h * 0.52, 0))
	if play_anim:
		var ap := model.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var p := ap[0] as AnimationPlayer
			var lst := p.get_animation_list()
			print("TURN anims ", lst)
	for i in n:
		pivot.rotation.y = TAU * float(i) / float(n)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/f%03d.png" % [out, i])
	print("TURN done ", out, " h=", h)
	quit(0)
