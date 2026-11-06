extends SceneTree
## Jitter of the villagers' live figures (Director 06.11, 12:30: «Митя и Пелагея постоянно дёргаются, мельтешат, будто
## залагивают»): per state and per one-shot action clip — the worst jolt (change of a bone's step per 1/60 s, mm, as
## test_motion_smooth) and how many frames jolt over 6 mm (a tremble, not one seam), and the foot-lock steps.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_action_jitter.gd -- id[,id] [clip,clip]
const DT := 1.0 / 60.0
const BONES := ["Hips", "Spine", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
const TREMBLE_MM := 6.0

func _initialize() -> void:
	_run()

func _fake() -> Node2D:
	var s := GDScript.new(); s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"; s.reload()
	var n := Node2D.new(); n.set_script(s)
	var sp := Sprite2D.new(); n.add_child(sp); n.set("sprite", sp)
	var sh := GDScript.new(); sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"; sh.reload()
	n.set("sheet", sh.new()); root.add_child(n)
	return n

static func measure(frames: Array) -> Array:
	var worst := 0.0
	var wb := ""
	var wi := 0
	var n := 0
	for i in range(2, frames.size()):
		var fm := 0.0
		for b in BONES:
			if not frames[i].has(b):
				continue
			var acc: Vector3 = frames[i][b] - 2.0 * frames[i - 1][b] + frames[i - 2][b]
			var mm := acc.length() * 1000.0
			if mm > fm:
				fm = mm
			if mm > worst:
				worst = mm
				wb = b
				wi = i
		if fm > TREMBLE_MM:
			n += 1
	return [worst, "%s at %.2f s" % [wb, wi * DT], n, frames.size()]

func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = String(a[0]).split(",")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var n := _fake()
		var live = load("res://scripts/actors/npc_live_3d.gd").new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		live.face(Vector2(0.4, 0.5), 0.55, true)
		var v: Actor3D = live.view
		var seq: Array = [["idle", 6.0], ["talk", 7.0], ["listen", 6.0]]
		var clips: Array = []
		if a.size() > 1:
			clips = String(a[1]).split(",")
		else:
			for c in (spec["rt3d"].get("clips", {}) as Dictionary).keys():
				if not (c in ["idle", "talk", "listen", "walk"]):
					clips.append(c)
		for c in clips:
			seq.append(["act:" + c, maxf(v.action_length(c), 1.0) + 1.5])
		print(id)
		for sq in seq:
			var name: String = sq[0]
			if name.begins_with("act:"):
				live.set_state("idle")
				for i in 30:
					live.process(DT)
				live.play_once(name.substr(4))
			else:
				live.set_state(name)
			var frames: Array = []
			var t := 0.0
			var steps := 0
			var was := [false, false]
			while t < float(sq[1]):
				live.process(DT)
				var f := {}
				for b in BONES:
					if v.skeleton.find_bone(b) >= 0:
						f[b] = v.turn.transform * v.bone_model(b)
				frames.append(f)
				for i in 2:
					var s_now: bool = v._foot_step[i] != null
					if s_now and not was[i]:
						steps += 1
					was[i] = s_now
				t += DT
			var m := measure(frames)
			print("  %-18s worst %5.1f mm (%s) | tremble frames %3d of %d | steps %d" % [name, m[0], m[1], m[2], m[3], steps])
		n.queue_free()
		await process_frame
	quit(0)
