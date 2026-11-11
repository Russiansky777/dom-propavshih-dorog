extends SceneTree
## The villagers' mouths (Director 09.11, 21:21 «открытие рта при разговорах… давай делать»; 21:56 «ты не видишь, что
## рот сделан плохо?»; 22:18 «рты открывающиеся и нормальные»). Each of the nine, the figure as the game builds it:
##   JW-1 data: the jaw bone is not turned (max_deg 0 — turning it tore the lips into a jagged slit), the lip line of
##        the model is measured (data/actors_rest/mouth_<id>.json), the mouth is painted;
##   JW-2 the opening follows the voice: loud — open, a pause — shut, not her line — shut;
##   JW-3 as drawn: open, a mouth appears at the mouth and nowhere else (the middle of what changed is within
##        4 mm of the lip line's middle; it is of a mouth's size; darker than the face, red, not black — 11.11) — and
##        shut, nothing is painted;
##   JW-4 the Jaw bone is where the clip has it, mouth open or shut;
##   self-check: with the shape taken away the same measure sees no mouth; a black mouth is called black.
## Needs a display (the figures are rendered): xvfb-run godot --path game --display-driver x11 --rendering-driver
## opengl3 -s res://tests/test_jaw.gd; headless — the data and the opening only.

const DT := 1.0 / 60.0
const ALL := ["nina", "pelageya", "ilya", "ilya_wife", "ulyana", "mitya", "pavel", "tamara", "manager"]
const PX := 300
const VIEW_M := 0.10          # the tile is 10 cm: 3 px per mm

var _failed := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL  ", message)


func _fake_npc(id: String) -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set("sprite", sp)
	n.set("actor_id", id)
	var sh := GDScript.new()
	sh.source_code = "extends RefCounted\nvar texture_scale: float = 2.25\n"
	sh.reload()
	n.set("sheet", sh.new())
	root.add_child(n)
	return n


func _shot(view) -> Image:
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


## What changed between two tiles: [pixels, their middle (px), mean luminance in `b` over them].
## What changed from a to b: [pixels, their middle, b's mean luminance there, a's mean luminance there (the skin it
## covers), b's mean colour there].
func _diff(a: Image, b: Image) -> Array:
	var n := 0
	var mid := Vector2.ZERO
	var lum := 0.0
	var lum_a := 0.0
	var col := Color(0, 0, 0, 0)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.get_luminance() - cb.get_luminance()) > 0.12:
				n += 1
				mid += Vector2(x, y)
				lum += cb.get_luminance()
				lum_a += ca.get_luminance()
				col += cb
	var k := 1.0 / float(maxi(n, 1))
	return [n, mid * k, lum * k, lum_a * k, col * k]


## JW-3's colour: a mouth is darker than the face it opens in, red, and not black (Director 11.11, 12:02: «фон
## чёрный почему-то, поищи, как должен быть в реальности»). Empty — so; else what is wrong.
static func _mouth_colour_wrong(d: Array) -> String:
	var lum := float(d[2])
	var skin := float(d[3])
	var c: Color = d[4]
	if lum < 0.2:
		return "black (luminance %.2f < 0,2; the black mouth of 10.11 measured 0,10–0,15 here, the red one 0,33–0,42)" % lum
	if lum > skin * 0.8:
		return "not darker than the face (%.2f against the skin's %.2f)" % [lum, skin]
	if c.r < c.g * 1.3 or c.r < c.b * 1.3:
		return "not red (%.2f, %.2f, %.2f)" % [c.r, c.g, c.b]
	return ""


func _run() -> void:
	await process_frame
	var drawn := DisplayServer.get_name() != "headless"
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ALL:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var jd: Dictionary = spec.get("rt3d", {}).get("jaw", {})
		_check(not jd.is_empty() and float(jd.get("max_deg", 6.0)) == 0.0, "JW-1 %s: the jaw bone is turned (max_deg %s) — that tore the lips" % [id, str(jd.get("max_deg"))])
		var mf = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors_rest/mouth_%s.json" % id)) if FileAccess.file_exists("res://data/actors_rest/mouth_%s.json" % id) else null
		_check(mf is Dictionary and mf.has("at") and float(mf.get("half_w", 0.0)) > 0.0, "JW-1 %s: no measured lip line (data/actors_rest/mouth_%s.json; tools: tests/bake_mouth.gd)" % [id, id])
		var n := _fake_npc(id)
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			_check(false, "%s: the figure is not built" % id)
			n.queue_free()
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		live.face(Vector2(0.0, 100.0), 0.55, true)
		live.set_state("talk")
		var t := 0.0
		while t < 0.5:
			live.process(DT)
			await process_frame
			t += DT
		var jaw = live.get("jaw")
		_check(jaw != null and bool(jaw.call("painted")), "JW-1 %s: no painted mouth" % id)
		# the head still for the pictures: no breath, sway or glance between the two shots (the clip's clock stands
		# without NpcLive3D.process)
		var life = live.view.get("life")
		if life != null:
			(life as SkeletonModifier3D).active = false
		if jaw == null:
			n.queue_free()
			continue
		# JW-2: the opening by the voice
		jaw.speaking_override = 1
		jaw.level_override = jaw.db_open
		for i in 30:
			await process_frame
		var loud: float = jaw.open
		var q_open: Quaternion = live.view.skeleton.get_bone_pose_rotation(jaw.bone)
		var img_open: Image = null
		var img_shut: Image = null
		var img_none: Image = null
		var img_black: Image = null
		if drawn:
			# the mouth in the middle of a 10 cm tile
			live.view.size = Vector2i(PX, PX)
			var cam: Camera3D = live.view.camera
			cam.size = VIEW_M
			for i in 3:
				await process_frame
				var at: Vector2 = cam.unproject_position((jaw.call("mouth_frame") as Transform3D).origin)
				var m_per_px := cam.size / float(PX)
				cam.global_position += cam.global_transform.basis.x * (at.x - PX * 0.5) * m_per_px
				cam.global_position -= cam.global_transform.basis.y * (at.y - PX * 0.5) * m_per_px
			img_open = await _shot(live.view)
			# self-check: the shape taken away — nothing to see
			var keep = live.view.material.get_shader_parameter("mouth_shape")
			live.view.material.set_shader_parameter("mouth_shape", Vector4.ZERO)
			img_none = await _shot(live.view)
			live.view.material.set_shader_parameter("mouth_shape", keep)
			# self-check: the mouth as it was before 11.11 (black inside) — the colour measure calls it black
			var mat: ShaderMaterial = live.view.material
			var was := {}
			for u in ["mouth_color", "mouth_rim", "mouth_teeth", "mouth_tongue"]:
				was[u] = mat.get_shader_parameter(u)
				mat.set_shader_parameter(u, Color(0.03, 0.01, 0.01))
			img_black = await _shot(live.view)
			for u in was:
				mat.set_shader_parameter(u, was[u])
		jaw.level_override = -100.0
		for i in 40:
			await process_frame
		var quiet: float = jaw.open
		var q_shut: Quaternion = live.view.skeleton.get_bone_pose_rotation(jaw.bone)
		if drawn:
			img_shut = await _shot(live.view)
		jaw.level_override = jaw.db_open
		jaw.speaking_override = 0
		for i in 40:
			await process_frame
		var other: float = jaw.open
		_check(loud > 0.9 and quiet == 0.0 and other == 0.0, "JW-2 %s: the mouth by the voice — loud %.2f (> 0,9), a pause %.2f (0), not her line %.2f (0)" % [id, loud, quiet, other])
		_check(rad_to_deg(q_open.angle_to(q_shut)) < 0.2, "JW-4 %s: the jaw bone moved %.1f° with the mouth (the clip keeps it shut; turning it tears the lips)" % [id, rad_to_deg(q_open.angle_to(q_shut))])
		if drawn:
			var d: Array = _diff(img_shut, img_open)
			var mm := float(PX) / (VIEW_M * 1000.0)
			var off: Vector2 = ((d[1] as Vector2) - Vector2(PX, PX) * 0.5) / mm
			print("    %s: open — %d px changed (%.0f mm²), their middle %.1f mm right, %.1f mm below the lip line's middle, luminance %.2f (skin %.2f), colour %s" % [id, d[0], float(d[0]) / (mm * mm), off.x, off.y, d[2], d[3], str(d[4])])
			_check(int(d[0]) > int(40.0 * mm * mm) and int(d[0]) < int(400.0 * mm * mm), "JW-3 %s: open, %d px change (a mouth is 40–400 mm² = %d–%d px)" % [id, d[0], int(40.0 * mm * mm), int(400.0 * mm * mm)])
			_check(absf(off.x) < 4.0 and off.y > -2.0 and off.y < 5.0, "JW-3 %s: the dark shape is %.1f mm right, %.1f mm below the lip line's middle (within 4 across, 2 above … 5 below)" % [id, off.x, off.y])
			var wrong := _mouth_colour_wrong(d)
			_check(wrong == "", "JW-3 %s: inside the mouth — %s" % [id, wrong])
			var db: Array = _diff(img_shut, img_black)
			var black := _mouth_colour_wrong(db)
			_check(black.begins_with("black"), "self-check JW-3 %s: a black mouth is not taken for a right one (%s; luminance %.2f, colour %s)" % [id, black if black != "" else "passed", db[2], str(db[4])])
			var none: Array = _diff(img_shut, img_none)
			_check(int(none[0]) < int(4.0 * mm * mm), "self-check JW-3 %s: with the shape taken away %d px still change — the measure sees a mouth that is not painted" % [id, none[0]])
		n.queue_free()
		await process_frame
	print("==== jaw: %d checks, %d failed%s ====" % [_checks, _failed, "" if drawn else " (no display: nothing drawn, JW-3 skipped)"])
	quit(1 if _failed > 0 else 0)
