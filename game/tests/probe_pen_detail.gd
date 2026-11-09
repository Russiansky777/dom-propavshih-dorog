extends "res://tests/probe_sway.gd"
## Where exactly a hand is «behind the clothes» by the penetration probe's own measure: the deepest hand vertex, the body
## vertex nearest to it and that one's normal — all in the hips' frame, cm (x to the left arm, y up, z forward).
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_pen_detail.gd -- <id> <state> <t> [L|R]

const Pen := preload("res://tests/probe_hand_penetration.gd")


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var st: String = a[1]
	var at := float(a[2])
	var side := 1 if a.size() < 4 or a[3] == "R" else 0
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	for opt in OS.get_environment("PEN_OPT").split(",", false):
		if opt == "nosway":
			for k in ["sway_cm", "sway_fore_cm", "sway_roll_deg", "sway_yaw_deg", "arm_swing_deg"]:
				(spec["rt3d"]["life"] as Dictionary).erase(k)
		elif opt == "nolife":
			spec["rt3d"]["life"] = {"breath_deg": 0.0, "head_drift_deg": 0.0, "glance_deg": 0.0}
		elif opt == "norest":
			(spec["rt3d"]["arm_body"] as Dictionary).erase("rest")
	var n := _fake_npc()
	var live = NL.new()
	n.add_child(live)
	live.setup(n, spec, 0.55)
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sk: Skeleton3D = live.view.skeleton
	var g := Grab.new()
	sk.add_child(g)
	var unit: float = live.view.life.unit
	live.set_state(st)
	var t := 0.0
	while t < at:
		live.process(DT)
		await process_frame
		t += DT
	var prepped: Array = Pen.prep(sk, live.view.meshes)
	var cell := 0.03 * unit
	var grid := {}
	var hands: Array = []
	for e in prepped:
		var mats := {}
		var cls: PackedByteArray = e[7]
		for k in cls.size():
			var c := cls[k]
			if c == 0:
				continue
			var r := Pen.skin_pt(e, k, g.out, mats)
			if c == 1:
				var key := Vector3i((r[0] as Vector3) / cell)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(r)
			elif c == 2 + side:
				hands.append(r[0])
	var hips: Transform3D = g.out[sk.find_bone("Hips")]
	var hinv := Transform3D(hips.basis.orthonormalized(), hips.origin).affine_inverse()
	var worst := -INF
	var info := ""
	var behind := 0
	for h in hands:
		var key := Vector3i((h as Vector3) / cell)
		var bd := INF
		var bn := Vector3.ZERO
		var bp := Vector3.ZERO
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var kk := key + Vector3i(dx, dy, dz)
					if not grid.has(kk):
						continue
					for r in grid[kk]:
						var d: float = (h as Vector3).distance_squared_to(r[0])
						if d < bd:
							bd = d
							bp = r[0]
							bn = r[1]
		if bd == INF:
			continue
		var dep: float = -((h as Vector3) - bp).dot(bn) / unit * 100.0
		if dep > 0.2:
			behind += 1
		if dep > worst:
			worst = dep
			var hh: Vector3 = hinv * (h as Vector3) / unit * 100.0
			var bb: Vector3 = hinv * bp / unit * 100.0
			var nn: Vector3 = hips.basis.orthonormalized().inverse() * bn
			info = "hand vertex (%.0f, %.0f, %.0f), nearest body vertex (%.0f, %.0f, %.0f) %.1f cm away, its normal (%.2f, %.2f, %.2f)" % [hh.x, hh.y, hh.z, bb.x, bb.y, bb.z, sqrt(bd) / unit * 100.0, nn.x, nn.y, nn.z]
	print("%s %s %.2f s %s hand: %d vertices, %d behind; deepest %.1f cm — %s" % [id, st, at, "R" if side == 1 else "L", hands.size(), behind, worst, info])
	quit(0)
