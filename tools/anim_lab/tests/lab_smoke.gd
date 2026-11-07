extends SceneTree
## Проверка стенда: каждая фигура из lab/characters.json загружается, idle/talk/listen и разовые действия
## переключаются, камера обходит фигуру, при 0°/14° камера — игровая, режим «без поправок» собирается.
## С экраном пишет снимки в <out>/ (по умолчанию user://smoke); с --headless — только проверки (быстро).
##   godot --path . --fixed-fps 60 -s res://tests/lab_smoke.gd -- [out] [id,id]
##   godot --headless --path . --fixed-fps 60 -s res://tests/lab_smoke.gd

const DT := 1.0 / 60.0
var fails := 0
var shots := true


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


func _shot(out: String, tag: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, tag])


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 and a[0] != "" else ProjectSettings.globalize_path("user://smoke")
	var only: Array = String(a[1]).split(",") if a.size() > 1 else []
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute(out)
	var lab = load("res://lab/anim_lab.tscn").instantiate()
	root.add_child(lab)
	await _frames(30)
	_check(lab.IDS.size() > 0, "список персонажей: %s" % ", ".join(lab.IDS))
	for i in lab.IDS.size():
		var id: String = lab.IDS[i]
		if not only.is_empty() and not only.has(id):
			continue
		lab._switch(i)
		await _frames(10)
		_check(lab.live != null and lab.live.view != null, "%s загружен" % id)
		if lab.live == null:
			continue
		for st in ["idle", "talk", "listen"]:
			lab._set_state(st)
			await _frames(150)
			var w: float = lab.live.view.shown_act_w()
			var cl: Dictionary = lab.live.view.clips
			var listen_own: bool = st == "listen" and cl.has("listen") and cl["listen"] != cl.get("idle")
			if st == "talk" or listen_own:
				_check(w > 0.95, "%s: %s включает слой действия (вес %.2f)" % [id, st, w])
			else:
				_check(w < 0.05, "%s: %s — стойка без слоя действия (вес %.2f)" % [id, st, w])
			await _shot(out, "%s_%s_front" % [id, st])
		lab._set_state("talk")
		for yaw in [90.0, 180.0]:
			lab.cam_yaw = yaw
			lab._place_camera()
			await _frames(20)
			await _shot(out, "%s_talk_yaw%03d" % [id, int(yaw)])
		lab.cam_yaw = 90.0
		lab._place_camera()
		var ct: Transform3D = lab.live.view.camera.global_transform
		_check(absf(ct.origin.x) > 5.0, "%s: камера сбоку (x = %.2f м)" % [id, ct.origin.x])
		lab.cam_elev = 45.0
		lab._place_camera()
		await _frames(10)
		await _shot(out, "%s_talk_high" % id)
		lab._reset_view()
		var g: Transform3D = lab.live.view.camera.transform
		lab.live.view._place_camera()
		_check(g.is_equal_approx(lab.live.view.camera.transform), "%s: поворот 0°, высота 14° = игровая камера" % id)
		for clip in lab._extra:
			lab._set_state("idle")
			await _frames(40)
			lab._play_extra(clip)
			await _frames(60)
			_check(lab.live.once_busy() or lab.live.view.shown_act_w() > 0.5, "%s: действие %s идёт" % [id, clip])
			await _shot(out, "%s_%s" % [id, clip])
			var n := 0
			while lab.live.once_busy() and n < 1200:   # до конца действия (держащие позу — не дольше 20 с)
				await process_frame
				n += 1
		lab._set_state("idle")
	lab.raw = true
	lab._spawn()
	await _frames(20)
	_check(lab.live != null and lab.live.arm_body == null, "режим без поправок собирается (BodyClear нет)")
	lab._set_state("talk")
	await _frames(120)
	await _shot(out, "raw_talk")
	print("lab_smoke: %s%s" % ["OK" if fails == 0 else "ОШИБКИ: %d" % fails, (", снимки в " + out) if shots else ""])
	quit(0 if fails == 0 else 1)
