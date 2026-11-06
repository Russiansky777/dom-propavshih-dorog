extends SceneTree
## Proof of a hug with two live figures (block 3, 06.11): A and B face each other `gap_px` apart (screen), both play
## their hug clip held at `at` (share), drawn in 2D in depth order (B nearer). Frames over time → <out>/hug_<t>.png
##   xvfb-run godot --path game -s res://tests/probe_hug_pair.gd -- <out> <a> <clip_a> <b> <clip_b> <gap_px> [at=0.5]
const DT := 1.0 / 30.0

func _initialize() -> void:
	_run()

func _npc(id: String, pos: Vector2, face: Vector2) -> Array:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\n"
	s.reload()
	var n := Node2D.new(); n.set_script(s)
	var sp := Sprite2D.new(); n.add_child(sp); n.set("sprite", sp)
	var sh := GDScript.new(); sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"; sh.reload()
	n.set("sheet", sh.new()); n.position = pos
	root.add_child(n)
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var live = load("res://scripts/actors/npc_live_3d.gd").new()
	n.add_child(live)
	live.setup(n, spec, 0.55)
	live.face(face, 0.55, true)
	return [n, live]

func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var gap := float(a[5])
	var at := float(a[6]) if a.size() > 6 else 0.5
	DirAccess.make_dir_recursive_absolute(out)
	var bg := ColorRect.new(); bg.color = Color(0.25, 0.24, 0.23); bg.size = Vector2(1920, 1080); bg.z_index = -10
	root.add_child(bg)
	var A := _npc(a[1], Vector2(960 - gap * 0.5, 900), Vector2(1, -0.15))
	var B := _npc(a[3], Vector2(960 + gap * 0.5, 905), Vector2(-1, -0.15))
	A[0].z_index = 1; B[0].z_index = 2
	A[1].play_once(a[2], true, at); B[1].play_once(a[4], true, at)
	var t := 0.0
	var shots := [0.3, 1.0, 2.0, 3.0, 4.5]
	while t < 5.0:
		A[1].process(DT); B[1].process(DT)
		await process_frame
		t += DT
		if not shots.is_empty() and t >= shots[0]:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/hug_%04.1f.png" % [out, shots[0]])
			shots.pop_front()
	quit(0)
