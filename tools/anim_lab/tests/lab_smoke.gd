extends SceneTree
## Проверка стенда: обе фигуры загружаются, idle/talk/listen и разовые действия переключаются, камера обходит фигуру,
## режим «без поправок» собирается. Снимки — в <out>/ (по умолчанию user://smoke).
##   godot --path . --fixed-fps 60 -s res://tests/lab_smoke.gd -- [out]

const DT := 1.0 / 60.0
var fails := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		push_error("lab_smoke: " + msg)
	else:
		print("ok: ", msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(lab, out: String, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, tag])


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else ProjectSettings.globalize_path("user://smoke")
	DirAccess.make_dir_recursive_absolute(out)
	var lab = load("res://lab/anim_lab.tscn").instantiate()
	root.add_child(lab)
	await _frames(30)
	for i in 2:
		lab._switch(i)
		await _frames(10)
		var id: String = lab.IDS[i]
		_check(lab.live != null and lab.live.view != null, "%s загружен" % id)
		if lab.live == null:
			continue
		for st in ["idle", "talk", "listen"]:
			lab._set_state(st)
			await _frames(150)
			var w: float = lab.live.view.shown_act_w()
			if st == "talk":
				_check(w > 0.95, "%s: talk включает слой действия (вес %.2f)" % [id, w])
			else:
				_check(w < 0.05, "%s: %s — стойка без слоя действия (вес %.2f)" % [id, st, w])
			await _shot(lab, out, "%s_%s_front" % [id, st])
		lab._set_state("talk")
		for yaw in [45.0, 90.0, 180.0, 270.0]:
			lab.cam_yaw = yaw
			lab._place_camera()
			await _frames(20)
			await _shot(lab, out, "%s_talk_yaw%03d" % [id, int(yaw)])
		var ct: Transform3D = lab.live.view.camera.global_transform
		_check(absf(ct.origin.x) > 5.0, "%s: камера сбоку (x = %.2f м)" % [id, ct.origin.x])
		lab.cam_elev = 45.0
		lab._place_camera()
		await _frames(10)
		await _shot(lab, out, "%s_talk_high" % id)
		lab._reset_view()
		var g: Transform3D = lab.live.view.camera.transform
		lab.live.view._place_camera()
		_check(g.is_equal_approx(lab.live.view.camera.transform), "%s: поворот 0°, высота 14° = игровая камера" % id)
		for clip in lab._extra:
			lab._set_state("idle")
			await _frames(30)
			lab._play_extra(clip)
			await _frames(60)
			_check(lab.live.once_busy() or lab.live.view.shown_act_w() > 0.5, "%s: действие %s идёт" % [id, clip])
			await _shot(lab, out, "%s_%s" % [id, clip])
			await _frames(400)
		lab._set_state("idle")
	lab.raw = true
	lab._spawn()
	await _frames(20)
	_check(lab.live != null and lab.live.arm_body == null, "режим без поправок собирается (BodyClear нет)")
	lab._set_state("talk")
	await _frames(120)
	await _shot(lab, out, "raw_talk")
	print("lab_smoke: %s, снимки в %s" % ["OK" if fails == 0 else "ОШИБКИ: %d" % fails, out])
	quit(0 if fails == 0 else 1)
