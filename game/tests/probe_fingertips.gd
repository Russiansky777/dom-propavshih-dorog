extends SceneTree
## Fingertips in the body (Director 02.11, line 12: «пальцы Павла в теле»; line 3: Pelageya's hands): how deep the
## hand's farthest point goes inside the body's hull, standing, talking and listening, with BodyClear's fingertip
## check on (data tip_r_m) and off.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_fingertips.gd -- id[,id]

const DT := 1.0 / 60.0
const SEQ := [["idle", 4.0], ["talk", 6.0], ["idle", 2.0], ["listen", 5.0]]


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


## Deepest fingertip / hand-middle per side over the sequence (cm; < 0 outside).
static func measure(tree: SceneTree, id: String, tip_on: bool) -> Dictionary:
	return {}


func _run() -> void:
	await process_frame
	var ids: Array = String(OS.get_cmdline_user_args()[0]).split(",")
	for id in ids:
		for on in [false, true]:
			var r: Dictionary = await run_one(self, id, on)
			print("%s tip %s: fingertip L %.1f R %.1f cm | checked points (with thickness) L %.1f R %.1f cm" % [id, "on " if on else "off", r["tip"][0], r["tip"][1], r["mid"][0], r["mid"][1]])
	quit(0)


static func run_one(tree: SceneTree, id: String, on: bool) -> Dictionary:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var ab: Dictionary = spec["rt3d"].get("arm_body", {})
	if not on:
		ab.erase("tip_r_m")
		ab.erase("shell")   # the hand's surface points (06.11, 15:56) cover the fingertip too
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
	tree.root.add_child(n)
	var live = load("res://scripts/actors/npc_live_3d.gd").new()
	n.add_child(live)
	var out := {"tip": [-99.0, -99.0], "mid": [-99.0, -99.0], "frames": 0}
	if not live.setup(n, spec, 0.55):
		n.queue_free()
		return out
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live.face(Vector2(0.4, 0.5), 0.55, true)
	var bc = live.arm_body
	for seg in SEQ:
		live.set_state(seg[0])
		var t := 0.0
		while t < float(seg[1]):
			live.process(DT)
			await tree.process_frame
			t += DT
			if bc == null:
				continue
			out["frames"] = int(out["frames"]) + 1
			for i in 2:
				out["tip"][i] = maxf(float(out["tip"][i]), float(bc.tip_m[i]) * 100.0)
				out["mid"][i] = maxf(float(out["mid"][i]), float(bc.shown_m[i]) * 100.0)
	n.queue_free()
	await tree.process_frame
	return out
