extends SceneTree
## The black between the first span (M25) and the epilogue's bridge shot (M26 EP_tamara), as a reader clicks
## (a line every 0.8 s): prints the stage alpha and the frame shown, sampled every 0.1 s, so the number of fades
## is counted, not guessed. 31.10 (Director, стр. 108: «перед сценой с мостом 2 фейда, сделать один»).
##   godot --fixed-fps 60 --path game -s res://tests/probe_fade_m25_m26.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var sr = root.get_node("StoryRunner")
	var sd = root.get_node("StoryData")
	var main_node = load("res://scenes/Main.tscn").instantiate()
	main_node.set("title_mode", "skip")
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var gui: Node = main_node.get_node("GameUi")
	gs.reset()
	for id in sd.scene_order:
		var sc: Dictionary = sd.scene(id)
		if String(sc.get("type", "")) != "main":
			continue
		if id == "M25":
			break
		gs.set_flag("done_" + id, true)
		gs.set_flag("started_" + id, true)
		for f in sc.get("grants", {}).get("flags", []):
			gs.set_flag(String(f), true)
	rm.change_room("Z3", "default")
	for i in 10:
		await process_frame
	if not sr.is_done("M25") and sr.current_beat.is_empty():
		sr.start_scene("M25")
	var t := 0.0
	var since := 0.0
	var log_on := false
	var last_s := -1.0
	var fades := 0
	var prev_a := 0.0
	var going_up := false
	while t < 60.0:
		await process_frame
		var d := 1.0 / 60.0
		t += d
		since += d
		var a := float(gui.call("stage_probe").get("alpha", 0.0))
		if log_on:
			if a > prev_a + 0.001 and not going_up and a > 0.3:
				pass
			if a > 0.9 and not going_up:
				going_up = true
				fades += 1
			elif a < 0.5 and going_up:
				going_up = false
			if t - last_s >= 0.1:
				last_s = t
				var lum := -1.0
				if DisplayServer.get_name() != "headless":
					var img: Image = root.get_texture().get_image()
					img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
					var sum := 0.0
					for yy in 8:
						for xx in 8:
							sum += img.get_pixel(xx, yy).get_luminance()
					lum = sum / 64.0
				print("t=%5.2f alpha=%.2f lum=%.3f frame=%s beat=%s scene=%s" % [t, a, lum, sr.current_frame, String(sr.current_beat.get("type", "")), sr.active_scene])
		prev_a = a
		if sr.mechanic_open:
			gs.set_flag("span_first_laid", true)
			sr.close_mechanic()
			log_on = true
			continue
		var b: Dictionary = sr.current_beat
		if b.is_empty() or since < 0.8:
			if sr.current_frame == "EP_tamara" and a < 0.05 and log_on:
				break
			continue
		since = 0.0
		if b.get("type") == "options":
			sr.choose(String(b.get("options", [])[0].get("id", "")))
		elif b.get("type") in ["line", "narration"]:
			sr.advance()
		if sr.current_frame == "EP_tamara" and a < 0.05 and log_on:
			break
	print("FADES to black after the log: %d" % fades)
	quit(0)
