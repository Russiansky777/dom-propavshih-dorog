extends SceneTree
## Hands that hold a moving thing (Director 10.11, 18:59, the windlass: «и руки нужно доделать»): HandHoldModifier.
##   godot --headless --fixed-fps 60 --audio-driver Dummy --path game -s res://tests/test_hand_hold.gd
##   HH-1 Ilya turns the crank: with both hands held to the left crank's grip, round the whole turn each hand's grip
##        point is on its place of the grip (within 2 cm on screen) — at the top, in front, at the bottom, behind;
##   HH-2 he leans and goes down only where the grip is too low to reach standing, and not past the limit; the feet
##        stay where they stand;
##   HH-3 let go, the hands leave the grip (back to the clip);
##   self-check — without the hold the same measure is far off.
## The crank's place and size against the figure are the game's own (the close-up of M25: Ilya's feet and height —
## the frame's data, rooms/F_span.json; the left crank's axle, the grip's round and the hands' places — WindlassSpin /
## windlass.json). At his old place (feet 1011, 813) the bottom of the turn was below his knee: FEET=1011,813 fails HH-2.
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


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL  " + what)


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
	live.play_once("crank_windlass", true, -1.0, true)
	var cm := 100.0 / screen_ppm    # cm per screen px
	var worst := 0.0
	var worst_free := 0.0
	var bends: Array = []
	var shot := 0
	for step in 9:
		spin.angle = WindlassSpin.REST + TAU * float(step) / 8.0
		var tr: Vector2 = place.call(spin.grip_point("l", 0.15))
		var tl: Vector2 = place.call(spin.grip_point("l", 0.6))
		# without the hold: how far the clip's own hands are (self-check's measure), then held
		if step == 0:
			for i in 40:
				live.process(DT)
				await process_frame
			worst_free = ((_seen["Right"] as Vector2) - tr).length() * cm
		for i in 45:
			live.hold_hand_at("Right", tr, 1.0)
			live.hold_hand_at("Left", tl, 1.0, true)
			live.process(DT)
			await process_frame
		var gr: Vector2 = _seen["Right"]
		var gl: Vector2 = _seen["Left"]
		var er := (gr - tr).length() * cm
		var el := (gl - tl).length() * cm
		worst = maxf(worst, maxf(er, el))
		bends.append(float(live.hand_hold.effort_now))
		print("  turn %d/8: right hand %.1f cm off, left %.1f cm; effort %.2f (lean %.0f°)" % [step, er, el, bends[-1], rad_to_deg(live.hand_hold.lean_now)])
		if out != "":
			DirAccess.make_dir_recursive_absolute(out)
			live.view.set_render_scale(4.0)
			live.view.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			live.view.get_texture().get_image().save_png("%s/hold_%d.png" % [out, shot])
			shot += 1
	_check(worst < 2.0, "HH-1 round the whole turn both hands are on the grip (worst %.1f cm)" % worst)
	_check(worst_free > 8.0, "self-check: without the hold the clip's hand is far from the grip (%.1f cm) — the measure tells" % worst_free)
	_check(float(bends[0]) < 0.05, "HH-2 with the grip at the top he stands as the clip has him (effort %.2f)" % float(bends[0]))
	_check(float(bends[4]) > 0.15, "HH-2 with the grip at the bottom he goes down to it (effort %.2f)" % float(bends[4]))
	var top_effort := 0.0
	for b in bends:
		top_effort = maxf(top_effort, float(b))
	_check(top_effort < 0.9, "HH-2 nowhere in the turn does it take all he has: the crank is within a working man's reach where he stands (most effort %.2f)" % top_effort)
	for i in 60:
		live.hold_hand_at("Right", Vector2.ZERO, 0.0)
		live.hold_hand_at("Left", Vector2.ZERO, 0.0)
		live.process(DT)
		await process_frame
	_check(not live.hand_hold.any_shown() and absf(live.hand_hold.effort_now) < 0.001, "HH-3 let go: the hold is off, he stands up")
	print("==== hand hold: %d checks, %d passed, %d failed ====" % [passes + fails, passes, fails])
	quit(0 if fails == 0 else 1)
