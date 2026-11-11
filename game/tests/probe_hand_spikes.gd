extends SceneTree
## Hands jerking (Director 06.11, 15:08: «руки иногда дёргаются»): per frame the hands' jolt (mm per 1/60 s², as
## test_motion_smooth) through idle → talk → idle → listen → idle; prints spikes over `thr` with time and state, and
## repeats with data blocks off (arm_body, life, act_body…) to find which one makes them.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_hand_spikes.gd -- id [thr=4] [off=a,b]
const DT := 1.0 / 60.0
func _initialize() -> void:
	_run()
func _fake() -> Node2D:
	var s := GDScript.new(); s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"; s.reload()
	var n := Node2D.new(); n.set_script(s)
	var sp := Sprite2D.new(); n.add_child(sp); n.set("sprite", sp)
	var sh := GDScript.new(); sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"; sh.reload()
	n.set("sheet", sh.new()); root.add_child(n)
	return n
func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var thr := float(a[1]) if a.size() > 1 else 4.0
	var off: Array = String(a[2]).substr(4).split(",") if a.size() > 2 else []
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	for k in off:
		(spec["rt3d"] as Dictionary).erase(k)
	# PROBE_POOL=talk,talk_calm — the talk pool (11.11: with two the first «talk» after «talk» is the second one)
	if OS.get_environment("PROBE_POOL") != "":
		spec["rt3d"]["talk_pool"] = Array(OS.get_environment("PROBE_POOL").split(","))
	var n := _fake()
	var live = load("res://scripts/actors/npc_live_3d.gd").new()
	n.add_child(live)
	live.setup(n, spec, 0.55)
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live.face(Vector2(0.4, 0.5), 0.55, true)
	var v: Actor3D = live.view
	var seq := [["idle", 4.0], ["talk", 12.0], ["idle", 3.0], ["listen", 10.0], ["idle", 3.0]]
	var hist: Array = []
	var t := 0.0
	var spikes := 0
	var worst := 0.0
	for sq in seq:
		live.set_state(sq[0])
		var u := 0.0
		while u < float(sq[1]):
			live.process(DT)
			var p := [v.turn.transform * v.bone_model("LeftHand"), v.turn.transform * v.bone_model("RightHand"), v.turn.transform * v.bone_model("LeftForeArm"), v.turn.transform * v.bone_model("RightForeArm"), v.turn.transform * v.bone_model("LeftArm"), v.turn.transform * v.bone_model("Spine02"), v.turn.transform * v.bone_model("Hips")]
			hist.append(p)
			if hist.size() >= 3:
				for i in 4:
					var acc: Vector3 = hist[-1][i] - 2.0 * hist[-2][i] + hist[-3][i]
					var mm := acc.length() * 1000.0
					worst = maxf(worst, mm)
					if mm > thr:
						spikes += 1
						if spikes <= 25:
							var more := ""
							for j in range(4, 7):
								var aj: Vector3 = hist[-1][j] - 2.0 * hist[-2][j] + hist[-3][j]
								more += " %s %.1f" % [["LeftArm", "Spine02", "Hips"][j - 4], aj.length() * 1000.0]
							print("  t %6.2f %-6s %-12s %5.1f mm  act %s t %.2f |%s" % [t, sq[0], ["LeftHand", "RightHand", "LeftForeArm", "RightForeArm"][i], mm, live.act_name, live.act_t, more])
			u += DT
			t += DT
	# the gesture's size: how far the hands travel during the talk (path length, m) — the smoothing must keep it
	var path := 0.0
	var i0 := int(4.0 / DT)
	for k in range(i0 + 1, i0 + int(12.0 / DT)):
		for hnd in 2:
			path += (hist[k][hnd] - hist[k - 1][hnd]).length()
	print("%s off=%s: spikes > %.1f mm: %d, worst %.1f | hands' path in the talk %.2f m" % [id, off, thr, spikes, worst, path])
	quit(0)
