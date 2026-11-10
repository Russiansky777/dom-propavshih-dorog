extends SceneTree
## Hands that hold a moving thing (Director 10.11, 18:59, the windlass: «и руки нужно доделать»): HandHoldModifier.
##   godot --headless --fixed-fps 60 --audio-driver Dummy --path game -s res://tests/test_hand_hold.gd
##   HH-1 Ilya turns the crank: with both hands held to the left crank's grip, round the whole turn each hand's grip
##        point is on its place of the grip (within 2 cm on screen) — at the top, in front, at the bottom, behind;
##   HH-2 holding the crank he stands in a working stance (leaning to it, the knees given) and his back follows the
##        hands — more lean with the grip low — without bowing: the lean changes by less than 20° over the turn and
##        the crank never asks more than the stance gives; self-check — upright, with no working stance, the same
##        crank makes him bow deep at the bottom of every turn (what the game showed first), and the measure says so;
##   HH-3 let go, the hands leave the grip (back to the clip);
##   self-check — without the hold the same measure is far off.
## The crank's place and size against the figure are the game's own (the close-up of M25: Ilya's feet and height —
## the frame's data, rooms/F_span.json; the left crank's axle, the grip's round and the hands' places — WindlassSpin /
## windlass.json). FEET=x,y tries another place; HH_TUNE="work_lean_deg=…,…" other measures; HH_DEBUG=1 prints the arm.
## With OUT=<dir> under a display (xvfb, x11) it also saves the figure at eight places of the turn.

const DT := 1.0 / 60.0
var FIG_PX := 224.0              # Ilya's height on screen in the close-up — read from the frame's data (F_span)
var FEET := Vector2(1011, 813)   # his feet there

var fails := 0
var passes := 0
var _live = null
var _seen := {}       # side → the hand's grip point on screen as posed by the modifiers (read at skeleton_updated:
                      # after the update the skeleton goes back to the clip's pose, a later read sees no hold)


func _on_skeleton_updated() -> void:
	if _live == null or _live.body == null:
		return
	for side in ["Left", "Right"]:
		_seen[side] = _live.body.global_transform * (_live.view.hand_grip_frame_px(side) + _live.body.offset)
	if _live.hand_hold != null:   # HH_DEBUG: the right arm as posed
		var sk: Skeleton3D = _live.view.skeleton
		var b: Array = _live.hand_hold.sides.get("Right", [])
		if b.size() == 3:
			_seen["arm3"] = [sk.get_bone_global_pose(int(b[0])).origin, sk.get_bone_global_pose(int(b[1])).origin, sk.get_bone_global_pose(int(b[2])).origin,
				sk.get_bone_global_pose(int(b[2])) * (_live.hand_hold.grip_local["Right"] as Vector3)]


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL  " + what)


const BOW_MAX := 20.0   # degrees the trunk's lean may change over one turn


func feet_m_of(live) -> Vector3:
	var sk: Skeleton3D = live.view.skeleton
	return (sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin + sk.get_bone_global_rest(sk.find_bone("RightFoot")).origin) * 0.5


## One turn of the crank in eight steps with both hands held: how far the hands are from their places on the grip
## (cm, worst), the trunk's lean at each step (degrees), the most effort and the stance's share.
func _turn(live, spin: WindlassSpin, place: Callable, cm: float, out: String, feet_m: Vector3, height_m: float, tune: bool = false) -> Dictionary:
	var worst := 0.0
	var leans: Array = []
	var effort := 0.0
	var stance := 0.0
	var shot := 0
	for step in 9:
		spin.angle = WindlassSpin.REST + TAU * float(step) / 8.0
		var tr: Vector2 = place.call(spin.grip_point("l", 0.15))
		var tl: Vector2 = place.call(spin.grip_point("l", 0.6))
		for i in 45:
			live.hold_hand_at("Right", tr, 1.0)
			live.hold_hand_at("Left", tl, 1.0, true)
			if tune and i == 0 and OS.get_environment("HH_TUNE") != "":   # a try at other measures: HH_TUNE="hinge_k=0.1,squat_k=0.15"
				for kv in OS.get_environment("HH_TUNE").split(","):
					live.hand_hold.set(kv.get_slice("=", 0), float(kv.get_slice("=", 1)))
			live.process(DT)
			await process_frame
		if OS.get_environment("HH_DEBUG") != "":
			var hh = live.hand_hold
			var sk: Skeleton3D = live.view.skeleton
			var tm: Basis = hh.to_model
			var unit: float = (sk.get_bone_global_rest(sk.find_bone("Head")).origin - feet_m).length() / (height_m * 0.93)   # skeleton units per metre
			var a3: Array = _seen.get("arm3", [])
			if a3.size() == 4:
				var mm := func(v: Vector3) -> String: return str((tm * (v - feet_m) / unit).snapped(Vector3(0.01, 0.01, 0.01)))
				print("    [m from the feet: x across, y up, z forward] as posed: shoulder %s elbow %s wrist %s grip %s; grip's place %s; shoulder→place %.2f m" % [mm.call(a3[0]), mm.call(a3[1]), mm.call(a3[2]), mm.call(a3[3]),
					mm.call(hh.targets["Right"]), ((hh.targets["Right"] as Vector3) - (a3[0] as Vector3)).length() / unit])
		var gr: Vector2 = _seen["Right"]
		var gl: Vector2 = _seen["Left"]
		var er := (gr - tr).length() * cm
		var el := (gl - tl).length() * cm
		worst = maxf(worst, maxf(er, el))
		leans.append(rad_to_deg(float(live.hand_hold.lean_now)))
		effort = maxf(effort, float(live.hand_hold.effort_now))
		stance = float(live.hand_hold.stance_now)
		print("  turn %d/8: right hand %.1f cm off, left %.1f cm; lean %.0f° (effort %.2f)" % [step, er, el, leans[-1], float(live.hand_hold.effort_now)])
		if out != "":
			DirAccess.make_dir_recursive_absolute(out)
			live.view.set_render_scale(4.0)
			live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			live.view.get_texture().get_image().save_png("%s/hold_%d.png" % [out, shot])
			shot += 1
	return {"worst": worst, "leans": leans, "effort": effort, "stance": stance}


func _fake_npc() -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar sprite: Sprite2D = null\nvar sheet = null\nvar actor_id := \"\"\n"
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


func _run() -> void:
	await process_frame
	var out := OS.get_environment("OUT")
	var frame = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rooms/F_span.json"))
	for h in frame.get("hotspots", []):
		if String(h.get("id", "")) == "ilya":
			FEET = Vector2(float(h["feet"][0]), float(h["feet"][1]))
			FIG_PX = float(h["figure_h"])
	if OS.get_environment("FEET") != "":   # a try at another place: FEET=x,y
		FEET = Vector2(float(OS.get_environment("FEET").get_slice(",", 0)), float(OS.get_environment("FEET").get_slice(",", 1)))
	print("  Ilya in the frame: feet %s, %d px tall" % [str(FEET), int(FIG_PX)])
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/ilya.json"))
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var n := _fake_npc()
	n.set("actor_id", "ilya")
	n.position = Vector2(400, 600)
	var live = NL.new()
	n.add_child(live)
	if not live.setup(n, spec, 0.55):
		print("FAIL  ilya not loaded")
		quit(1)
		return
	if out == "":
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_live = live
	live.view.skeleton.skeleton_updated.connect(_on_skeleton_updated)
	live.face(Vector2(1.0, -0.12) * 100.0, 0.55, true)   # to the crank: right, a touch away (data live_face)
	var spin: WindlassSpin = WindlassSpin.make("res://assets/rooms/F_span/beam_waiting.png", 1920.0 / 1672.0)
	_check(spin != null, "the windlass's parts load")
	if spin == null:
		quit(1)
		return
	for i in 30:
		live.process(DT)
		await process_frame
	# the figure's size on screen here: feet (the node) to the head bone, against the same in the close-up
	var body: Sprite2D = live.body
	var head_y: float = (body.global_transform * (live.view.bone_frame_px("Head") + body.offset)).y
	var hips_y: float = (body.global_transform * (live.view.bone_frame_px("Hips") + body.offset)).y
	var texture_ppm: float = float(live.view.size.y) / live.view.camera.size
	var screen_ppm: float = absf(body.global_transform.get_scale().y) * texture_ppm
	var height_m: float = (n.global_position.y - head_y) / screen_ppm / 0.93   # the head bone is ≈ 0.93 of the height
	var k: float = (height_m * screen_ppm) / FIG_PX     # the close-up's px → this figure's px
	print("  figure here: %.2f m, %.1f px/m; close-up px × %.3f" % [height_m, screen_ppm, k])
	_check(height_m > 1.5 and height_m < 2.1 and hips_y < n.global_position.y, "the figure stands on its feet at the node, of a man's height (%.2f m)" % height_m)
	var place := func(p: Vector2) -> Vector2:
		return n.global_position + (p - FEET) * k
	# he stands in his own stance: the mini-game plays no clip over it while the hands are held (windlass_panel.tick)
	var cm := 100.0 / screen_ppm    # cm per screen px
	# without the hold: how far the stance's own hand is from the grip (the self-check's measure)
	spin.angle = WindlassSpin.REST
	for i in 40:
		live.process(DT)
		await process_frame
	var worst_free: float = ((_seen["Right"] as Vector2) - (place.call(spin.grip_point("l", 0.15)) as Vector2)).length() * cm
	var r: Dictionary = await _turn(live, spin, place, cm, out, feet_m_of(live), height_m, true)
	var leans: Array = r["leans"]
	_check(float(r["worst"]) < 2.0, "HH-1 round the whole turn both hands are on the grip (worst %.1f cm)" % float(r["worst"]))
	_check(worst_free > 8.0, "self-check: without the hold the stance's hand is far from the grip (%.1f cm) — the measure tells" % worst_free)
	# HH-2: the working stance — he leans to the crank all the turn and the back follows the hands, with no bow
	var lean_top: float = leans[0]
	var lean_most: float = leans.max()
	var lean_least: float = leans.min()
	_check(float(r["stance"]) > 0.95 and lean_least > 5.0, "HH-2 holding the crank he stands in the working stance, leaning to it all the turn (stance %.2f, least lean %.0f°)" % [float(r["stance"]), lean_least])
	_check(lean_most - lean_top > 4.0 and leans.find(lean_most) in [2, 3, 4, 5, 6], "HH-2 his back follows the hands: more lean with the grip low (%.0f° at the top, %.0f° at the most, turn %d/8)" % [lean_top, lean_most, leans.find(lean_most)])
	_check(lean_most - lean_least < BOW_MAX, "HH-2 he does not bow: the lean changes by %.0f° over the turn (< %.0f°)" % [lean_most - lean_least, BOW_MAX])
	_check(float(r["effort"]) < 0.3, "HH-2 nowhere in the turn does the crank ask more than the stance gives: it is within a working man's reach where he stands (most effort %.2f)" % float(r["effort"]))
	# self-check: upright, with no working stance, the same crank makes him bow deep at the bottom of every turn
	# (what the game showed first, 10.11) — the «does not bow» measure catches it
	var hh = live.hand_hold
	var kept := {"work_lean_deg": hh.work_lean_deg, "work_squat": hh.work_squat, "sway_lean_deg": hh.sway_lean_deg, "sway_squat": hh.sway_squat}
	for key in kept:
		hh.set(key, 0.0)
	var r0: Dictionary = await _turn(live, spin, place, cm, "", feet_m_of(live), height_m)
	for key in kept:
		hh.set(key, kept[key])
	var leans0: Array = r0["leans"]
	_check(float(leans0.max()) - float(leans0.min()) > BOW_MAX, "self-check: without the working stance he bows %.0f° at the bottom of the turn — the measure tells" % (float(leans0.max()) - float(leans0.min())))
	for i in 60:
		live.hold_hand_at("Right", Vector2.ZERO, 0.0)
		live.hold_hand_at("Left", Vector2.ZERO, 0.0)
		live.process(DT)
		await process_frame
	_check(not live.hand_hold.any_shown() and absf(live.hand_hold.effort_now) < 0.001, "HH-3 let go: the hold is off, he stands up")
	print("==== hand hold: %d checks, %d passed, %d failed ====" % [passes + fails, passes, fails])
	quit(0 if fails == 0 else 1)
