extends SceneTree
## Frames of a villager standing alone (Actor3D's own picture, as NpcLive3D poses it and runs its feet), with the feet
## locks and the calming and without them (data as before 31.10) — for an eye check and a before/after video.
##   godot --path game -s res://tests/probe_npc_stand_shots.gd -- <out dir> <id> [seconds] [talk]   (needs a display)

func _initialize() -> void:
	_run()


func _shots(out: String, id: String, on: bool, secs: float, talk: bool) -> void:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if OS.get_environment("RT3D_DIR") != "":
		spec["rt3d"]["scene"] = "%s/%s/%s_rt.glb" % [OS.get_environment("RT3D_DIR"), id, id]
	if not on:
		spec["rt3d"].erase("feet")
		spec["rt3d"].erase("calm")
	var v := Actor3D.new()
	root.add_child(v)
	if not v.setup(spec):
		print("not loaded: ", v.load_error)
		return
	v.set_floor_k(0.55)
	v.set_render_scale(1.5)
	v.set_yaw(0.5)
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var dt := 1.0 / 30.0
	var t := 0.0
	var act_t := 0.0
	var n := 0
	DirAccess.make_dir_recursive_absolute(out)
	while t < secs:
		var lt: Array = [act_t, 0.0, 0.0]
		if talk:
			act_t += dt
			lt = Actor3D.loop_times(act_t, maxf(v.action_length("talk"), 0.1), 0.8)
		v.pose(dt, 0.0, 0.0, 1.0 if talk else 0.0, "talk" if talk else "", float(lt[0]), float(lt[1]), float(lt[2]))
		if not v.foot_ik.is_empty():
			v.feet_step(dt, Vector2(600, 800), Vector2(v.ppm, v.ppm * 0.55))
		await RenderingServer.frame_post_draw
		t += dt
		v.get_texture().get_image().save_png("%s/%04d.png" % [out, n])
		n += 1
	v.queue_free()
	await process_frame


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var id: String = a[1] if a.size() > 1 else "pelageya"
	var secs := float(a[2]) if a.size() > 2 else 8.0
	var talk := a.size() > 3 and a[3] == "talk"
	await _shots(out + "/after", id, true, secs, talk)
	await _shots(out + "/before", id, false, secs, talk)
	quit(0)
