extends SceneTree
## Headless checks of Agata in real 3D (actor data render "3d", game/scripts/actors/actor_3d.gd):
##   godot --headless --fixed-fps 60 --path game -s res://tests/test_agata_3d.gd   (game time 1/60 s per frame: same numbers on any machine)
## The Director's note 18.10: «живая, с человеческими движениями по всей оси, хороший айдл, не 8
## направлений, а как у людей; саму Агату не менять». Each defect class is a check:
##   - model: the same Meshy mesh/texture/skeleton (decimated for the web, ≤ 80k triangles), every clip
##     the game uses; the switch sprites ↔ 3D keeps place and state; sprites mode untouched;
##   - turning: any angle (≥ 40 distinct 5° yaw bins on a circle, not 8 rows), no jump between frames
##     (|Δyaw| ≤ cap), reaches the target;
##   - feet planted: while walking straight (4 directions + diagonal), the stance foot stays on the floor
##     within 1 cm per stance (root motion = the clip's own foot slide); walking speed from the clip;
##   - idle alive without jerks: 20 s of standing (variant crossfades included) — no bone jumps
##     (≤ 1.5 cm per 1/60 s), no turn of the hips over 25°, the head does move (breath, glances), feet
##     slide ≤ 4 cm over a crossfade;
##   - start/stop: speed ramps up and down (no 0 → full jump), the pose is continuous;
##   - actions open/pick/reach: the effect lands once, on the clip's key fraction; the last pose fades
##     into the idle; room change cancels without effect;
##   - drawing: the live figure is a child of the y-sorted figure (same z as the sprite; occluders
##     work the same), the sheet facade draws nothing, the contact shadow stays; footsteps fire on the
##     walk's contact frames.
## Exit code 0 only when every check passed.

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var sr: Node = null
var main_node: Node = null
var player = null
var PlayerScript = null          # loaded after the autoloads (player.gd uses StoryData)
var _completed: bool = false     # a test that dies on a script error never sets it → FAIL


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	# ONLY=<words> in the environment: just the tests whose name contains one of them (a quicker local run)
	var only := OS.get_environment("ONLY")
	if only != "":
		var hit := false
		for w in only.split(","):
			hit = hit or test_name.contains(w)
		if not hit:
			return
	_fails = []
	_completed = false
	var started := Time.get_ticks_msec()
	await fn.call()
	if not _completed:
		_fails.append("the test did not run to its end (script error above)")
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits `sec` seconds of game time (headless frames run faster than real time).
func _wait_s(sec: float) -> void:
	var t := 0.0
	var guard := 0
	while t < sec and guard < 100000:
		await process_frame
		t += player.get_process_delta_time()
		guard += 1


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	sr = root.get_node("StoryRunner")
	PlayerScript = load("res://scripts/actors/player.gd")
	PlayerScript.forced_render = "3d"
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await _frames(3)
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("Model: same Meshy mesh/texture/skeleton (v4, 150k–300k triangles), all clips; switch sprites ↔ 3D in place; sprites mode untouched", _test_model)
	await _test("Turning: any angle (not 8 rows), no jump between frames, reaches the target", _test_turning)
	await _test("Feet planted while walking: stance foot ≤ 1 cm per stance in 5 directions; speed from the clip", _test_feet_planted)
	await _test("Idle alive without jerks: 20 s with variant crossfades — no bone jumps, hips do not turn, head moves, feet stay", _test_idle)
	await _test("Start/stop: speed ramps up and down, pose continuous, arrives at the target", _test_start_stop)
	await _test("Actions open/pick/reach in 3D: once, on the key fraction; fade into idle; room change cancels", _test_actions)
	await _test("Drawing: live figure under the y-sorted node (same z, occluders as before), facade invisible, shadow kept, footsteps on contacts", _test_drawing)
	await _test("Talking (Director 30.10 «как живая»): her line → the talk gesture fades in over the stance, feet stay; line over → fades out; short line — none", _test_gesture)
	await _test("Talking to someone (Director 31.10, lines 30 and 45): her hands talk only in a conversation, not over a thing she found or her own thought", _test_gesture_addressed)
	await _test("Skirt (Director 30.10 «сгибы юбки не красиво»): on its own spring bones, not on the legs — no «trouser legs»; the knees push it, standing it settles", _test_skirt)
	await _test("Look (Director 30.10 «идеальная Агата»): a villager's line — her head turns to him (within the neck's limits), softly; line over — back", _test_look)
	await _test("Setting off (Director 30.10 «идеальная Агата»): the planted foot stays put as the stance blends into the stride (it skated 12–15 cm)", _test_set_off)
	await _test("Braid (Director 30.10, 23:22 «коса и сумка на пружинах»): on its own spring chain from the head — swings walking and turning, settles standing, stays clear of the back", _test_braid)
	await _test("Arm and bag (Director 31.10 «пересмотри и увидь сам»): the right hand and forearm stay out of the bag at her hip — standing, walking, talking, opening", _test_arm_bag)
	await _test("Feet hold the floor (Director 30.10 «идеальная Агата»): stopping and turning on the spot, a foot set down does not skate (14–21 cm before) — it stays or steps", _test_feet_hold)
	await _test("Boots (Director 31.10, 02:14 «сапоги с задёрнутыми носами»): a boot set down stands on its sole at the height it was made at, its toe not turned up", _test_boots)
	await _test("Stopping (Director 31.10, 15:04 «мельтешит в конце хода»): she stops in the steps a person stops in — the last one shorter, the other foot closing up — not a run of quick little steps", _test_stop_steps)
	await _test("Stopping (Director 01.11 «семенит, доступает»): the closing step at once and nothing after it; she rests on the end of her path", _test_stop_settles)
	await _test("Pick from the floor (Director 31.10, 17:45 and 18:32 «с пола заменить»): things on the floor and snow are taken with a bend down to the floor, not a crouch to table height; the thing is not lifted to the face (G1); the feet stay", _test_pick_floor)
	await _test("Corners near the end (Director 31.10, lines 8–9 «застревает и идёт на одном месте… от писем до стола»): a walk whose path turns a corner just before its end arrives — no walking on the spot against the counter, no stopping off past the corner", _test_walk_corners)
	await _test("Round the counter's corner (Director 01.11, line 2 «сначала письма, потом в центр снизу… в стол идёт, вместо того чтобы обойти угол»): letters ↔ the bottom of the screen — no walking on the spot at the front-left corner, the feet a body's depth in front of the counter", _test_walk_corner_front)
	await _test("Walk rhythm (Director 31.10, 02:14 «плывёт… равномерно, а не идёт»): the body is quickest between the steps and slowest over the planted foot, no lurch; the feet on the floor stay; arms swing by her sides; she looks ahead", _test_walk_rhythm)
	await _test("Right arm without jerks (Director 01.11, line 20 «правая рука иногда резко дёргается»): the arm kept out of the bag changes its way out softly — no jump", _test_arm_no_jerk)
	await _test("Short moves (Director 01.11, line 3 «мельтешит… куча перестановок ног»): 15–45 cm from standing is a step and the other foot closing up — two lifts, at the target", _test_short_moves)
	await _test("After arriving (Director 02.11, line 7 «переставляются зачем-то много раз после того, как она доходит»): a walk, then the turn to what she came to — the closing step and one step per foot to where the turn ends (≤ 4 lifts, 2,7 on average; 09.11, 22:18 «ноги перебираются слишком часто в конце движения»)", _test_after_arrive)
	await _test("Skirt with the legs (Director 01.11, line 3 «ботинки сами шагают… юбка не двигается»): walking, the hem goes with the shins — they do not step out from under it", _test_skirt_with_legs)
	PlayerScript.forced_render = ""
	gs.reset()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== Agata 3D: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _enter(room: String, pos: Vector2) -> void:
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	gs.add_item("key_house")
	rm.change_room(room, "default", pos)
	await _frames(1)
	player.seed_motion(1031)   # ревью 01.11 (В-8): the same random motion every run (tests seed the idle clips on top)
	await _frames(5)


# --- Model ---------------------------------------------------------------------------------------

func _test_model() -> void:
	await _enter("H1", Vector2(1200, 960))
	_check(player.is_3d(), "player is not in 3D mode (render forced 3d): %s" % (player.view3d.load_error if player.view3d else "no view"))
	if not player.is_3d():
		return
	var v: Actor3D = player.view3d
	var tris := v.triangle_count()
	# Director 30.10: the live model is the game's figure for Steam — v4, 250k triangles (web budget no longer applies).
	_check(tris > 150000 and tris <= 300000, "triangles %d: expected the v4 Meshy mesh decimated for Steam (150k..300k)" % tris)
	var skirt_bones := 0
	for i in v.skeleton.get_bone_count():
		var bn := v.skeleton.get_bone_name(i)
		if bn.begins_with("Skirt") or bn.begins_with("Braid") or bn.begins_with("Bag"):
			skirt_bones += 1   # the rig's own spring chains (tools/rig_skirt.py)
	_check(v.skeleton.get_bone_count() - skirt_bones == 24, "skeleton has %d bones besides the spring chains (skirt, braid, bag), Meshy rig has 24" % (v.skeleton.get_bone_count() - skirt_bones))
	for role in ["walk", "idle", "open", "pick", "pick_low", "reach"]:
		_check(v.clips.has(role), "clip for '%s' missing (rt3d.clips)" % role)
	_check(v.idle_pool.size() >= 3, "idle pool has %d variants (≥ 3 expected)" % v.idle_pool.size())
	var tex = v.material.get_shader_parameter("albedo_tex")
	_check(tex is Texture2D and (tex as Texture2D).get_width() == 4096, "albedo is not the model's 4K texture: %s" % str(tex))
	_check(v.stride_m > 0.9 and v.stride_m < 1.6, "walk stride per cycle %.3f m (clip Walking_Woman ≈ 1.1–1.3)" % v.stride_m)
	_check(v.contacts.size() == 2, "walk cycle contacts %s: two steps per cycle expected" % str(v.contacts))
	# Figure height on screen = the sprite figure's (same scene height).
	var head := v.bone_model("Head").y
	_check(absf(head * v.ppm * cos(deg_to_rad(v.elev_deg)) - 0.0) > 250.0, "head height on screen %.0f px at scale 1 — too small" % (head * v.ppm))
	# Switch to sprites and back: same place, sheet visible again, live view stopped.
	var pos: Vector2 = player.global_position
	player.set_render_mode("sprites")
	await _frames(2)
	_check(not player.is_3d() and player.sprite.material == null, "sprites mode: facade still hidden")
	_check(player.body3d == null or not player.body3d.visible, "sprites mode: live figure still visible")
	_check(v.render_target_update_mode == SubViewport.UPDATE_DISABLED, "sprites mode: the 3D view still renders")
	_check(player.global_position.distance_to(pos) < 0.5, "switch moved Agata")
	_check(String(player.sprite.animation).begins_with("idle_") and player.sprite.is_playing(), "sprites mode: idle sheet not playing (%s)" % player.sprite.animation)
	player.set_render_mode("3d")
	await _frames(2)
	_check(player.is_3d() and player.body3d.visible and player.sprite.material != null, "back to 3D failed")
	_completed = true

# --- Turning -------------------------------------------------------------------------------------

func _test_turning() -> void:
	await _enter("H1", Vector2(1200, 960))
	var bins := {}
	var max_jump := 0.0
	var prev: float = player.yaw3d
	var k: float = player.floor_foreshortening()
	for deg in range(0, 360, 20):
		var a := deg_to_rad(float(deg))
		var target: Vector2 = player.global_position + Vector2(sin(a), cos(a) * k) * 200.0  # floor direction a
		player.face_towards(target)
		var tt := 0.0
		while tt < 0.9:
			await process_frame
			tt += player.get_process_delta_time()
			var y: float = player.yaw3d
			max_jump = maxf(max_jump, absf(angle_difference(prev, y)))
			prev = y
			bins[int(floor(rad_to_deg(wrapf(y, 0.0, TAU)) / 5.0))] = true
		var err := absf(angle_difference(player.yaw3d, a))
		_check(err < deg_to_rad(4.0), "facing %d°: yaw %.1f° after 0.9 s" % [deg, rad_to_deg(player.yaw3d)])
	_check(bins.size() >= 40, "only %d distinct 5° yaw bins on a full circle (8 rows would give 8)" % bins.size())
	var cap := deg_to_rad(400.0) / 30.0  # per-frame cap at 30 fps (headless frames are faster)
	_check(max_jump <= cap, "yaw jumped %.1f° in one frame (cap %.1f°)" % [rad_to_deg(max_jump), rad_to_deg(cap)])
	_completed = true

# --- Feet planted --------------------------------------------------------------------------------

## Walks between two points and measures, in floor metres, the drift of each foot as drawn (after the IK: with the
## even walk the stride planting holds it, not the clip) while it stands flat — its ankle and ball both within 8 mm of
## the stride's floor: player floor position + yaw-rotated ankle.
func _walk_and_measure(room: String, a: Vector2, b: Vector2) -> Dictionary:
	await _enter(room, a)
	var v: Actor3D = player.view3d
	if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
		v.skeleton.skeleton_updated.connect(_on_skel_updated)
	_drawn_feet = []
	player.walk_to(b)
	var k: float = player.floor_foreshortening()
	var floor_pos := Vector2.ZERO   # integrated floor position (m)
	var last: Vector2 = player.global_position
	var flat_start: Array = [null, null]
	var worst := 0.0
	var worst_fwd := 0.0
	var worst_lat := 0.0
	var yaw_change := 0.0
	var stance_yaw: Array = [0.0, 0.0]
	var stance_scr: Array = [Vector2.ZERO, Vector2.ZERO]
	var worst_scr := 0.0
	var stances := 0
	var speeds: Array = []
	var guard := 0
	while player.is_walking() and guard < 2000:
		await process_frame
		guard += 1
		var p: Vector2 = player.global_position
		var s: float = absf(player.scale.y)
		var ppm_s: float = v.ppm * s
		var d := p - last
		floor_pos += Vector2(d.x / ppm_s, d.y / (ppm_s * k))
		last = p
		# full walking as shown (the weights pass through Actor3D's followers: the shown one lags the asked one)
		if player.walk_w < 0.97 or v.shown_w() < 0.97:
			flat_start = [null, null]
			continue
		var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
		for i in 2:
			var flat: bool = f[i * 2].y - float(v.stride_floor[i * 2]) < 0.008 and f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]) < 0.008
			if not flat:
				flat_start[i] = null
				continue
			var foot: Vector3 = Basis(Vector3.UP, player.yaw3d) * f[i * 2]
			var world := Vector3(floor_pos.x + foot.x, foot.y, floor_pos.y + foot.z)
			# as drawn: the planted foot's screen position (player on screen + camera projection of the foot)
			var scr: Vector2 = player.global_position + v.screen_of(Vector3(foot.x, 0.0, foot.z)) * s  # its floor contact point
			if flat_start[i] == null:
				flat_start[i] = world
				stance_scr[i] = scr
				stance_yaw[i] = player.yaw3d
				stances += 1
			else:
				var st: Vector3 = flat_start[i]
				var dv := Vector2(world.x - st.x, world.z - st.z)
				worst = maxf(worst, dv.length())
				var fwd := Vector2(sin(player.yaw3d), cos(player.yaw3d))
				worst_fwd = maxf(worst_fwd, absf(dv.dot(fwd)))
				worst_lat = maxf(worst_lat, absf(dv.cross(fwd)))
				yaw_change = maxf(yaw_change, absf(angle_difference(float(stance_yaw[i]), player.yaw3d)))
				worst_scr = maxf(worst_scr, scr.distance_to(stance_scr[i]) / maxf(s, 0.01))
		speeds.append(d.length() / maxf(player.get_process_delta_time(), 0.0001) / ppm_s)
	var off_end: float = player.global_position.distance_to(b)
	# where she comes to rest: after the last step the body still glides on over the front foot while the stance blends
	# in (player._stop_glide) — the walk's flag is already down then (CI 02.11: diagonal 11.9 px at the flag, the glide
	# still to come)
	var settle := 0
	while bool(player.get("_stop_glide")) and settle < 120:
		await process_frame
		settle += 1
	var off: float = player.global_position.distance_to(b)
	return {"worst_m": worst, "scr_px": worst_scr, "elev": v.elev_deg, "stretch": v.depth_stretch(), "k": k, "fwd_m": worst_fwd, "lat_m": worst_lat, "yaw_deg": rad_to_deg(yaw_change), "stances": stances, "arrived": off < 12.0, "off_px": off, "off_end_px": off_end, "frames": guard}


func _test_feet_planted() -> void:
	var legs := [["right", "Z2", Vector2(500, 900), Vector2(1450, 900)], ["left", "Z2", Vector2(1450, 900), Vector2(500, 900)],
		["towards viewer", "Z2", Vector2(960, 700), Vector2(960, 1030)], ["away", "Z2", Vector2(960, 1030), Vector2(960, 700)],
		["diagonal", "Z2", Vector2(600, 720), Vector2(1300, 1020)]]
	for leg in legs:
		var r: Dictionary = await _walk_and_measure(leg[1], leg[2], leg[3])
		print("        feet %s: stance drift max %.1f mm on the floor (along %.1f, across %.1f; body turned up to %.1f° in a stance), as drawn %.1f px (scale 1; camera %.1f°, depth ×%.2f, floor k %.2f) over %d stances, %d frames, %.1f px from the target at the last step, %.1f at rest" % [leg[0], r["worst_m"] * 1000.0, r["fwd_m"] * 1000.0, r["lat_m"] * 1000.0, r["yaw_deg"], r["scr_px"], r["elev"], r["stretch"], r["k"], r["stances"], r["frames"], float(r["off_end_px"]), float(r["off_px"])])
		if absf(sin(deg_to_rad(float(r["elev"]))) * float(r["stretch"]) - float(r["k"])) < 0.02:
			# camera at the room's own elevation: the drawn foot must stay put on screen too
			_check(float(r["scr_px"]) <= 3.0, "%s: drawn planted foot moved %.1f px on screen (≤ 3 px at scale 1)" % [leg[0], r["scr_px"]])
		# the walks to and from the viewer are short (≈ 1.8 s; the planned stop takes the last two steps): one flat stance
		_check(r["stances"] >= (1 if String(leg[0]) in ["towards viewer", "away"] else 2), "%s: only %d stances measured" % [leg[0], r["stances"]])
		_check(r["worst_m"] <= 0.010, "%s: stance foot slid %.1f mm (≤ 10 mm)" % [leg[0], r["worst_m"] * 1000.0])
		_check(r["arrived"], "%s: did not arrive (%.1f px from the target)" % [leg[0], float(r["off_px"])])
	# Self-check of the metric: the same walk with the figure sliding along the path at the clip's mean
	# speed (no root motion — what the sheets did) must be caught.
	player.root_motion_3d = false
	player.foot_lock_3d = false
	var bad: Dictionary = await _walk_and_measure("Z2", Vector2(500, 900), Vector2(1450, 900))
	player.root_motion_3d = true
	player.foot_lock_3d = true
	print("        self-check (constant speed, no root motion, no planting): stance drift %.1f mm" % (bad["worst_m"] * 1000.0))
	_check(bad["worst_m"] > 0.010, "self-check: constant-speed walking slid only %.1f mm — the metric would not catch skating" % (bad["worst_m"] * 1000.0))
	_completed = true

# --- Idle ----------------------------------------------------------------------------------------

func _test_idle() -> void:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	v.seed_idle(3)
	var bones := ["Head", "LeftHand", "RightHand", "Hips", "Spine02", "LeftFoot", "RightFoot"]
	var prev := {}
	var worst := {}
	var head_min := Vector3.INF
	var head_max := -Vector3.INF
	var yaw_min := INF
	var yaw_max := -INF
	var feet0: Array = []
	var foot_drift := 0.0
	var variants := {}
	var dt := 1.0 / 60.0
	for i in int(20.0 / dt):
		v.pose(dt, 0.0, 0.0, 0.0)
		variants[v.current_idle()] = true
		for b in bones:
			var p := v.bone_model(b)
			if prev.has(b):
				worst[b] = maxf(float(worst.get(b, 0.0)), p.distance_to(prev[b]))
			prev[b] = p
		var h := v.bone_model("Head")
		head_min = head_min.min(h)
		head_max = head_max.max(h)
		var hb := v.skeleton.find_bone("Hips")
		var q := v.skeleton.get_bone_global_pose(hb).basis
		var fwd := q * Vector3(0, 0, 1)
		var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
		yaw_min = minf(yaw_min, yaw)
		yaw_max = maxf(yaw_max, yaw)
		var f := v.feet_model()
		if feet0.is_empty():
			feet0 = f
		for j in [0, 2]:
			foot_drift = maxf(foot_drift, Vector2(f[j].x - feet0[j].x, f[j].z - feet0[j].z).length())
	var msg := ""
	for b in bones:
		msg += "%s %.1f " % [b, float(worst.get(b, 0.0)) * 1000.0]
		_check(float(worst.get(b, 0.0)) <= 0.015, "idle: %s jumped %.1f mm in 1/60 s (≤ 15 mm)" % [b, float(worst.get(b, 0.0)) * 1000.0])
	print("        idle: max step per 1/60 s (mm): %s; hips yaw %.1f..%.1f°; head range %s cm; foot drift %.1f cm; variants %s" % [msg, yaw_min, yaw_max, str(((head_max - head_min) * 100.0).snapped(Vector3(0.1, 0.1, 0.1))), foot_drift * 100.0, str(variants.keys())])
	_check(yaw_max - yaw_min <= 25.0, "idle: hips turned %.1f° (≤ 25°: no 90° turns)" % (yaw_max - yaw_min))
	_check((head_max - head_min).length() >= 0.01, "idle: the head is still (range %.1f mm) — not alive" % ((head_max - head_min).length() * 1000.0))
	_check(variants.size() >= 2, "idle: only %d variant(s) in 20 s" % variants.size())
	_check(foot_drift <= 0.04, "idle: a foot drifted %.1f cm over 20 s (≤ 4 cm; variants with far-apart stances?)" % (foot_drift * 100.0))
	_completed = true

# --- Start / stop --------------------------------------------------------------------------------

func _test_start_stop() -> void:
	await _enter("H1", Vector2(900, 960))
	player.view3d.seed_idle(5)
	var target := Vector2(1260, 960)
	player.walk_to(target)
	var speeds: Array = []
	var last: Vector2 = player.global_position
	var head_prev := Vector3.INF
	var head_jump := 0.0
	var guard := 0
	while player.is_walking() and guard < 1500:
		await process_frame
		guard += 1
		var dtt := maxf(player.get_process_delta_time(), 0.0001)
		speeds.append(player.global_position.distance_to(last) / dtt / absf(player.scale.y))
		last = player.global_position
		var h: Vector3 = player.view3d.bone_floor("Head")
		if head_prev != Vector3.INF:
			head_jump = maxf(head_jump, h.distance_to(head_prev))
		head_prev = h
	var cruise := 0.0
	for sp in speeds:
		cruise = maxf(cruise, float(sp))
	var first_moving := -1
	for i in speeds.size():
		if float(speeds[i]) > 0.5:
			first_moving = i
			break
	_check(first_moving >= 0, "never moved")
	if first_moving >= 0:
		_check(float(speeds[first_moving]) < cruise * 0.5, "start: first moving frame already at %.0f%% of cruise speed" % (100.0 * float(speeds[first_moving]) / maxf(cruise, 0.001)))
	var tail: Array = speeds.slice(maxi(speeds.size() - 3, 0))
	var tail_max := 0.0
	for sp in tail:
		tail_max = maxf(tail_max, float(sp))
	_check(tail_max < cruise * 0.5, "stop: last frames still at %.0f%% of cruise speed" % (100.0 * tail_max / maxf(cruise, 0.001)))
	_check(player.global_position.distance_to(target) <= 7.0, "stopped %.1f px from the target" % player.global_position.distance_to(target))
	_check(head_jump <= 0.03, "head jumped %.1f mm in a frame during start/stop" % (head_jump * 1000.0))
	# After stopping, the walk weight eases to 0 (no snap back to idle).
	var w0: float = player.walk_w
	await process_frame
	_check(player.walk_w <= w0, "walk weight rose after arrival")
	_completed = true

# --- Actions -------------------------------------------------------------------------------------

func _test_actions() -> void:
	await _enter("H1", Vector2(900, 900))
	var room = rm.current_room
	var shutter: Node2D = null
	for h in room.get_hotspots():
		if String(h.data.get("action_anim", "")) == "open" and String(h.hotspot_id).find("shutter") >= 0:
			shutter = h
	if shutter == null:
		for h in room.get_hotspots():
			if String(h.data.get("action_anim", "")) == "open":
				shutter = h
	_check(shutter != null, "no 'open' hotspot in H1")
	if shutter == null:
		return
	var fires0: int = player.action_fire_count
	var flags_before: Dictionary = gs.flags.duplicate()
	player.walk_to_and_interact(shutter)
	var guard := 0
	while player.is_walking() and guard < 1500:
		await process_frame
		guard += 1
	_check(player.is_acting(), "action did not start at the shutter (plan: %s)" % sr.planned_interaction(shutter))
	var fired_at := -1.0
	while player.is_acting() and guard < 3000:
		await process_frame
		guard += 1
		if fired_at < 0.0 and player.action_fire_count > fires0:
			fired_at = player._act_t / player._act_len
	_check(player.action_fire_count == fires0 + 1, "action fired %d times (once expected)" % (player.action_fire_count - fires0))
	var n: int = player.sprite.sprite_frames.get_frame_count(player.sheet.anim_name("open", 0))
	var key: float = float(player.sheet.action_key_frame("open")) / float(n)
	_check(fired_at >= key - 0.02 and fired_at <= key + 1.0 / float(n) + 0.02, "effect at %.3f of the clip, key fraction %.3f" % [fired_at, key])
	_check(gs.flags != flags_before, "the shutter's state did not change")
	_check(player._act_fading != "" or player._act_w < 0.05, "action ended without fading into idle")
	await _wait_s(0.6)
	_check(player._act_w <= 0.01, "action pose still blended in 0.6 s after the end (%.2f)" % player._act_w)
	# Room change mid-action: no effect.
	await _enter("H1", Vector2(900, 900))
	var stove: Node2D = null
	for h in rm.current_room.get_hotspots():
		if String(h.hotspot_id) == "stove":
			stove = h
	if stove != null:
		var lit0 := bool(gs.get_flag("stove_lit")) if gs.has_method("get_flag") else false
		player.walk_to_and_interact(stove)
		guard = 0
		while not player.is_acting() and guard < 1500:
			await process_frame
			guard += 1
		await _frames(2)
		rm.change_room("H1", "default", Vector2(1200, 960))
		await _frames(30)
		_check(not player.is_acting() and player._act_w == 0.0, "room change did not cancel the action")
		var lit1 := bool(gs.get_flag("stove_lit")) if gs.has_method("get_flag") else false
		_check(lit1 == lit0, "cancelled action still applied its effect")
	_completed = true

# --- Drawing -------------------------------------------------------------------------------------

func _test_drawing() -> void:
	await _enter("H1", Vector2(1200, 1000))
	var b: Sprite2D = player.body3d
	_check(b != null and b.visible and b.texture == player.view3d.get_texture(), "live figure sprite missing")
	_check(b.get_parent() == player.sprite and b.z_index == 0 and b.z_as_relative, "live figure not drawn at the player's z (y-sort)")
	_check(player.z_index == int(player.global_position.y), "player z %d ≠ y" % player.z_index)
	_check(player.sprite.material is ShaderMaterial, "facade (sheet sprite) is not hidden")
	var sh: Node = player.sprite.get_node_or_null("Shadow")
	_check(sh != null and (sh as CanvasItem).visible and (sh as CanvasItem).material == null, "contact shadow missing or hidden")
	# Feet of the live figure at the node origin: the pivot pixel of the texture lands on the feet.
	var off: Vector2 = b.offset * b.scale * player.sheet.sprite_scale()  # in the player's px: under the facade sprite (1/k, G56)
	var expect: Vector2 = -player.view3d.pivot * player.view3d.frame_px
	_check(off.distance_to(expect) < 1.0, "texture pivot %s ≠ %s" % [str(off), str(expect)])
	# The occluder in H1 (table, z 950): behind it above y 950, in front below — same rule as sprites.
	await _enter("H1", Vector2(1500, 900))
	_check(player.z_index < 950, "behind the table: z %d" % player.z_index)
	# Footsteps: SfxDirector counts steps on the facade's contact frames while walking.
	var sfx := root.get_node_or_null("SfxDirector")
	if sfx != null and sfx.get("step_count") != null:
		await _enter("Z2", Vector2(500, 900))
		var c0: int = int(sfx.get("step_count"))
		player.walk_to(Vector2(1450, 900))
		var guard := 0
		var cycles := 0.0
		var ph0: float = player.walk_phase
		while player.is_walking() and guard < 2000:
			await process_frame
			guard += 1
		cycles = player.walk_phase - ph0
		var steps: int = int(sfx.get("step_count")) - c0
		_check(steps >= int(cycles * 2.0) - 2 and steps <= int(cycles * 2.0) + 2, "footsteps %d for %.1f walk cycles (2 per cycle)" % [steps, cycles])
	_completed = true


# --- Talk gesture (rt3d.gesture) -----------------------------------------------------------------

func _test_gesture() -> void:
	await _enter("H1", Vector2(1200, 960))
	if not player.is_3d():
		_check(false, "not in 3D")
		return
	var v: Actor3D = player.view3d
	_check(v.clips.has("talk"), "talk clip resolved (rt3d.clips.talk)")
	await _wait_s(0.5)
	var feet0: Array = v.feet_model()
	sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "T_gesture", "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут."}
	await _wait_s(1.0)
	_check(player._gest_w > 0.6, "her line: the gesture is in (weight %.2f)" % player._gest_w)
	var feet1: Array = v.feet_model()
	var drift := maxf(Vector2(feet1[0].x - feet0[0].x, feet1[0].z - feet0[0].z).length(), Vector2(feet1[2].x - feet0[2].x, feet1[2].z - feet0[2].z).length())
	_check(drift < 0.04, "talking keeps the feet where they stood (%.1f cm)" % (drift * 100.0))
	sr.current_beat = {}
	await _wait_s(1.2)
	_check(player._gest_w <= 0.0, "line over: the gesture faded out (weight %.2f)" % player._gest_w)
	sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "T_short", "text": "Ой!"}
	await _wait_s(0.6)
	_check(player._gest_w <= 0.0, "a short line: no gesture (weight %.2f)" % player._gest_w)
	sr.current_beat = {"type": "line", "speaker": "tikhon", "line_id": "T_other", "text": "Кто там топчется?.. Сыро. Печь сперва затопи."}
	await _wait_s(0.6)
	_check(player._gest_w <= 0.0, "someone else's line: no gesture (weight %.2f)" % player._gest_w)
	sr.current_beat = {}
	_completed = true


# --- Skirt ---------------------------------------------------------------------------------------

var _skirt_rows: Array = []


func _on_skirt_updated() -> void:
	var v: Actor3D = player.view3d
	var sk := v.skeleton
	var row := {}
	# the spring's own part: where the joint is minus where the hips would carry it without springs (rests)
	var hips := sk.find_bone("Hips")
	for c in [0, 4]:
		var b := sk.find_bone("Skirt%d_2" % c)
		var carried: Transform3D = sk.get_bone_global_pose(hips) * sk.get_bone_rest(sk.find_bone("Skirt%d_0" % c)) \
			* sk.get_bone_rest(sk.find_bone("Skirt%d_1" % c)) * sk.get_bone_rest(b)
		row[c] = v._skel_to_turn() * sk.get_bone_global_pose(b).origin - v._skel_to_turn() * carried.origin
	_skirt_rows.append(row)


## The skirt (tools/rig_skirt.py, Actor3D._setup_skirt): (1) a spring per chain and pushers on thighs and shins at the
## legs; (2) the skin: outer skirt between 0.3 and 0.65 m hangs on its own bones — before, almost all of it followed
## one shin or thigh and a step split it into two «trouser legs»; (3) walking, the knees push the front and back of it
## (it moves against the hips), standing it settles back.
func _test_skirt() -> void:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	_check(v.skirt != null and v.skirt.setting_count == 8, "no spring skirt (rt3d.skirt / bones Skirt<c>_<k>)")
	if v.skirt == null:
		_completed = true
		return
	var pushers := 0
	for ch in v.skirt.get_children():
		if ch is SpringBoneCollisionCapsule3D:
			var cap := ch as SpringBoneCollisionCapsule3D
			var b := v.skeleton.find_bone(cap.bone_name)
			var mid: Vector3 = (v.skeleton.global_transform * v.skeleton.get_bone_global_pose(b)).origin
			_check(cap.global_position.distance_to(mid) < 0.3, "pusher on %s is %.2f m from its bone" % [cap.bone_name, cap.global_position.distance_to(mid)])
			pushers += 1
	_check(pushers == 4, "%d pushers on the legs (4 expected)" % pushers)
	# skin: outer skirt vertices at 0.3–0.65 m — weight on the leg bones
	var mi: MeshInstance3D = null
	for m in v.meshes:
		if mi == null or m.mesh.get_surface_count() > 0 and (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			mi = m
	var legs := ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]
	# the mesh's own space is the model in metres (feet at 0, as exported); the axis is the middle of the pelvis band
	var total := 0
	var on_legs := 0
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var ctr := Vector2.ZERO
		var nc := 0
		for q in verts:
			if q.y > 0.85 and q.y < 0.95:
				ctr += Vector2(q.x, q.z)
				nc += 1
		ctr /= maxf(float(nc), 1.0)
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			var q := verts[i]
			if q.y < 0.30 or q.y > 0.65 or Vector2(q.x, q.z).distance_to(ctr) < 0.17:
				continue
			total += 1
			var wl := 0.0
			for j in per:
				var bi := int(bones[i * per + j])
				var nm := String(mi.skin.get_bind_name(bi)) if mi.skin != null else v.skeleton.get_bone_name(bi)
				if nm == "" and mi.skin != null:
					nm = v.skeleton.get_bone_name(mi.skin.get_bind_bone(bi))
				if legs.has(nm):
					wl += float(weights[i * per + j])
			if wl > 0.5:
				on_legs += 1
	print("        skirt: %d outer vertices at 0.30–0.65 m, %d of them mostly on the legs" % [total, on_legs])
	_check(total > 1000, "only %d outer skirt vertices found at 0.30–0.65 m" % total)
	_check(on_legs <= total * 0.05, "%d of %d outer skirt vertices follow a leg (trouser legs)" % [on_legs, total])
	# springs: walking, the front/back hem joints move against the hips; standing, they settle
	_skirt_rows = []
	v.skeleton.skeleton_updated.connect(_on_skirt_updated)
	player.click_at(player.global_position + Vector2(-420, 0))
	await _wait_s(2.0)
	var walk_rows := _skirt_rows.duplicate()
	await _wait_s(3.0)
	_skirt_rows = []
	await _wait_s(1.0)
	v.skeleton.skeleton_updated.disconnect(_on_skirt_updated)
	var swing := 0.0
	for c in [0, 4]:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for r in walk_rows:
			lo = lo.min(r[c])
			hi = hi.max(r[c])
		swing = maxf(swing, (hi - lo).length())
	var settle := 0.0
	for c in [0, 4]:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for r in _skirt_rows:
			lo = lo.min(r[c])
			hi = hi.max(r[c])
		settle = maxf(settle, (hi - lo).length())
	print("        skirt: the springs swing the hem joints %.1f cm walking; standing, %.1f cm" % [swing * 100.0, settle * 100.0])
	# standing, the idle's own sway still moves it a little (1–3 cm); a skirt that keeps swinging goes far beyond
	_check(swing > 0.04, "walking, the springs do not swing the skirt (%.1f cm): no springs or no push" % (swing * 100.0))
	_check(settle < 0.04 and settle < swing * 0.5, "standing, the skirt keeps swinging (%.1f cm, walking %.1f cm)" % [settle * 100.0, swing * 100.0])
	_completed = true


# --- Look ----------------------------------------------------------------------------------------

var _head_now := Vector2.ZERO


## The head as drawn (after the modifiers: read when the skeleton has its final pose).
func _on_head_updated() -> void:
	_head_now = _head_dir_now(player.view3d)


func _head_dir(_v: Actor3D) -> Vector2:
	return _head_now


## Head forward on the floor (x right, z towards the viewer), from the posed head bone and the body yaw.
func _head_dir_now(v: Actor3D) -> Vector2:
	var b := v.skeleton.find_bone("Head")
	var hb: Basis = (Basis(Vector3.UP, v.get_yaw()) * v._skel_to_turn().basis * v.skeleton.get_bone_global_pose(b).basis).orthonormalized()
	var f := hb * Vector3.BACK
	return Vector2(f.x, f.z).normalized()


func _test_look() -> void:
	await _enter("Z2", Vector2(900, 900))
	var v: Actor3D = player.view3d
	# a villager standing to her right and a little back (a node with actor_id, as NpcActor; feet on the floor)
	var gd := GDScript.new()
	gd.source_code = "extends Node2D\nvar actor_id := \"look_test\"\n"
	gd.reload()
	var npc := Node2D.new()
	npc.set_script(gd)
	rm.current_room.add_child(npc)
	npc.global_position = player.global_position + Vector2(320, -40)
	_check(v.look != null, "no look-at on the head (rt3d.look)")
	if v.look == null or npc == null:
		_completed = true
		return
	# Agata faces 50° away from Pelageya
	v.skeleton.skeleton_updated.connect(_on_head_updated)
	var to_npc: Vector2 = npc.global_position - player.global_position
	var k: float = player.floor_foreshortening()
	var dir_floor := Vector2(to_npc.x, to_npc.y / k).normalized()
	var a_npc := atan2(dir_floor.x, dir_floor.y)
	player.yaw3d = a_npc + deg_to_rad(50.0)
	player.yaw3d_target = player.yaw3d
	# her stance gaze straight ahead (no glance aside during the measure)
	player._glance_a = 0.0
	player._glance_t = 1e9
	await _wait_s(1.0)
	var before := absf(rad_to_deg(dir_floor.angle_to(_head_dir(v))))
	sr.current_beat = {"type": "line", "speaker": String(npc.get("actor_id")), "line_id": "T_1", "text": "Погляди-ка!"}
	var max_step := 0.0
	var prev := _head_dir(v)
	for i in 90:
		await process_frame
		var hd := _head_dir(v)
		max_step = maxf(max_step, absf(rad_to_deg(prev.angle_to(hd))))
		prev = hd
	var during := absf(rad_to_deg(dir_floor.angle_to(_head_dir(v))))
	sr.current_beat = {}
	await _wait_s(2.0)
	var after := absf(rad_to_deg(dir_floor.angle_to(_head_dir(v))))
	print("        look: head off the villager %.0f° before his line, %.0f° while he speaks, %.0f° after; fastest %.1f°/frame (influence %.2f)" % [before, during, after, max_step, v.look.influence])
	# the head alone turns (no eyes in the rig): at 50° off it takes most of the way, not all
	_check(during < before * 0.65, "the villager's line: the head did not turn to him (%.0f° → %.0f°)" % [before, during])
	_check(max_step < 4.0, "the head turned %.1f° in a frame (soft turn expected)" % max_step)
	_check(after > during + 15.0, "line over: the head stays on him (%.0f°)" % after)
	player._glance_t = 0.0
	npc.queue_free()
	v.skeleton.skeleton_updated.disconnect(_on_head_updated)
	_completed = true


# --- Setting off -----------------------------------------------------------------------------------

## 12 walks from standing in Z2 (each facing its way): the slide of the lower (planted) foot on the floor in the
## first 0.8 s. With the planting off (self-check) the same starts must slide far more.
func _starts(plant: bool) -> Array:
	player.start_at_mid_stance = plant
	player.plant_on_start = plant
	player.foot_lock_3d = plant
	var tot := 0.0
	var worst := 0.0
	var n := 0
	for k in 12:
		await _enter("Z2", Vector2(700 + (k % 3) * 200, 850 + (k % 2) * 100))
		var v: Actor3D = player.view3d
		var ang := k * 0.52
		if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
			v.skeleton.skeleton_updated.connect(_on_skel_updated)
		_drawn_feet = []
		player.yaw3d = ang
		player.yaw3d_target = ang
		await _frames(40)
		var kf: float = player.floor_foreshortening()
		player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * kf) * 420.0)
		var ppm_s: float = v.ppm * absf(player.scale.y)
		var start: Vector2 = player.global_position
		var planted := {}
		var w_max := 0.0
		var t := 0.0
		while t < 0.8:
			await process_frame
			t += player.get_process_delta_time()
			var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()   # as drawn (the IK holding it)
			var p: Vector2 = player.global_position - start
			# the foot on the floor and its contact: the ankle while the heel is down, the ball once the heel is up (the
			# ankle then rolls forward over the ball, as it should)
			var hgt: Array = []
			for j in 4:
				hgt.append(f[j].y - float(v.stride_floor[j]))
			var side := 0 if minf(hgt[0], hgt[1]) <= minf(hgt[2], hgt[3]) else 1
			var c: int = side * 2 if hgt[side * 2] <= hgt[side * 2 + 1] + 0.004 else side * 2 + 1
			if float(hgt[c]) > 0.015:
				planted = {}   # both feet up off the floor (one lifting, the other being set down): none planted
				continue
			var foot: Vector3 = Basis(Vector3.UP, player.yaw3d) * f[c]
			var w := Vector2(p.x / ppm_s + foot.x, p.y / (ppm_s * kf) + foot.z)
			if not planted.has(c):
				planted = {c: w}
			w_max = maxf(w_max, (w - planted[c]).length())
		tot += w_max
		worst = maxf(worst, w_max)
		n += 1
	player.start_at_mid_stance = true
	player.plant_on_start = true
	player.foot_lock_3d = true
	return [tot / maxf(n, 1), worst]


func _test_set_off() -> void:
	var on: Array = await _starts(true)
	var off: Array = await _starts(false)
	print("        setting off: the planted foot slides %.0f mm (worst %.0f); without planting %.0f mm (worst %.0f)" % [on[0] * 1000.0, on[1] * 1000.0, off[0] * 1000.0, off[1] * 1000.0])
	_check(on[0] <= 0.05 and on[1] <= 0.08, "setting off, the planted foot slides %.0f mm on average (worst %.0f; ≤ 50 / 80)" % [on[0] * 1000.0, on[1] * 1000.0])
	_check(off[0] > on[0] * 2.0, "self-check: without planting the start slides only %.0f mm — the metric would not see skating" % (off[0] * 1000.0))
	_completed = true


# --- Feet hold the floor -----------------------------------------------------------------------------

var _drawn_feet: Array = []


func _on_skel_updated() -> void:
	_drawn_feet = player.view3d.feet_model()   # as drawn: after the modifiers (the foot locks)
	_drawn_arms = _arm_angles(player.view3d)


var _drawn_arms: Array = []


## Drawn arms, per side [elbow bend, the upper arm's spread out of the side plane, wrist bend], degrees.
func _arm_angles(v: Actor3D) -> Array:
	var out: Array = []
	var xf := v._skel_to_turn()
	var sk := v.skeleton
	for side in ["Left", "Right"]:
		var a: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "Arm")).origin
		var e: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).origin
		var h: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
		var fy: Vector3 = xf.basis * sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).basis * Vector3.UP
		var hy: Vector3 = xf.basis * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).basis * Vector3.UP
		var up := e - a
		out.append([rad_to_deg(up.angle_to(h - e)), rad_to_deg(atan2(absf(up.x), -up.y)), rad_to_deg(fy.angle_to(hy))])
	return out


## Each foot set down on the floor (ankle ≤ 2 cm above its stance height and ≤ 1.5 cm above the other foot): how
## far its point on the screen floor goes until it is lifted — the skating a viewer sees. Stopping (from the walk
## weight's fall) and a 150° turn on the spot, per walk; plus the IK holding its target (on the floor the locked
## foot stays at its spot; past the straight leg's reach it may only come up a little, like a heel, until it steps)
## and the feet back in the stance once she has settled.
func _feet_runs(locks: bool) -> Dictionary:
	player.foot_lock_3d = locks
	var res := {"stop": [], "turn": [], "miss": 0.0, "lift": 0.0, "off_stance": 0.0, "sep": INF}
	for k in 6:
		await _enter("Z2", Vector2(700 + (k % 3) * 200, 850 + (k % 2) * 100))
		var v: Actor3D = player.view3d
		# the same stance clips and glances every run (they change where the feet stand and how the steps go: unseeded,
		# the worst locked-foot miss went 9–16 mm from run to run)
		v.seed_idle(40 + k)
		seed(40 + k)
		if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
			v.skeleton.skeleton_updated.connect(_on_skel_updated)
		var ang := k * 1.05 + 0.3
		player.yaw3d = ang
		player.yaw3d_target = ang
		await _frames(40)
		var kf: float = player.floor_foreshortening()
		player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * kf) * 380.0)
		await _frames(40)
		for phase in ["stop", "turn"]:
			if phase == "turn":
				await _frames(30)
				player.face_towards(player.global_position + Vector2(sin(ang + 2.6), cos(ang + 2.6) * kf) * 200.0)
			var planted := {}
			var worst := 0.0
			var t := 0.0
			var after := 0.0
			while (phase == "stop" and (player.is_walking() or after < 0.6)) or (phase == "turn" and t < 1.2):
				await process_frame
				var d: float = player.get_process_delta_time()
				t += d
				if not player.is_walking():
					after += d
				var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
				var ppm_s: float = v.ppm * absf(player.scale.y)
				var yb := Basis(Vector3.UP, player.yaw3d)
				var counting: bool = phase == "turn" or player.walk_w < 0.97 or not player.is_walking()
				var low: float = minf(f[0].y, f[2].y)
				var both_down := 0
				for i in 2:
					var foot: Vector3 = yb * f[i * 2]
					var wp := Vector2(player.global_position.x + foot.x * ppm_s, player.global_position.y + foot.z * ppm_s * kf)
					var down: bool = foot.y <= float(v._foot_rest_h[i]) + 0.02 and foot.y <= low + 0.015
					if not down or not counting or not planted.has(i):
						planted[i] = wp
					if down:
						both_down += 1
					if down and counting:
						var dd: Vector2 = wp - planted[i]
						worst = maxf(worst, Vector2(dd.x / ppm_s, dd.y / (ppm_s * kf)).length())
					# a locked foot (the stride planting's own hold is measured by «Walk rhythm»: contacts on the floor)
					if locks and not v.foot_ik.is_empty() and v._foot_lock[i] != null and (v.foot_ik[i] as TwoBoneIK3D).influence >= 0.999:
						var tg: Vector3 = (v._foot_target[i] as Node3D).position
						res["miss"] = maxf(float(res["miss"]), Vector2(tg.x - foot.x, tg.z - foot.z).length())
						res["lift"] = maxf(float(res["lift"]), foot.y - tg.y)
				if both_down == 2 and phase == "turn":
					# both feet on the floor: not one on (or right behind) the other
					res["sep"] = minf(float(res["sep"]), Vector2(f[0].x - f[2].x, f[0].z - f[2].z).length())
			(res[phase] as Array).append(worst)
		# settled: each foot back where the stance has it
		await _frames(60)
		var fa: Array = v.feet_model()
		var fd: Array = _drawn_feet if not _drawn_feet.is_empty() else fa
		for i in 2:
			res["off_stance"] = maxf(float(res["off_stance"]), Vector2(fd[i * 2].x - fa[i * 2].x, fd[i * 2].z - fa[i * 2].z).length())
	player.foot_lock_3d = true
	return res


func _mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(a.size(), 1)


func _test_feet_hold() -> void:
	var on := await _feet_runs(true)
	var off := await _feet_runs(false)
	var s_on := _mean(on["stop"])
	var t_on := _mean(on["turn"])
	var s_off := _mean(off["stop"])
	var t_off := _mean(off["turn"])
	print("        stopping: a foot set down skates %.0f mm (worst %.0f), without the locks %.0f (worst %.0f); turning on the spot %.0f (worst %.0f), without %.0f (worst %.0f)" % [s_on * 1000.0, (on["stop"] as Array).max() * 1000.0, s_off * 1000.0, (off["stop"] as Array).max() * 1000.0, t_on * 1000.0, (on["turn"] as Array).max() * 1000.0, t_off * 1000.0, (off["turn"] as Array).max() * 1000.0])
	print("        a locked foot off its spot along the floor %.1f mm at most, up off it %.0f mm; settled, off the stance %.0f mm; feet apart turning, both down, at least %.0f mm (without the locks %.0f)" % [float(on["miss"]) * 1000.0, float(on["lift"]) * 1000.0, float(on["off_stance"]) * 1000.0, float(on["sep"]) * 1000.0, float(off["sep"]) * 1000.0])
	# bounds with room for the machine (CI 30.10, 789750e2: turning 56 mm, worst 127, where this machine gives 44 / 74 —
	# the navigation timing differs); the old skating was 140–210 mm on average, the self-check below holds it apart
	# the worst stop is one walk in six where a foot is let go as the stride lifts it and set down again (here 100–110,
	# the CI machine has given 1,7× this machine's worst) — still below the old skating's worst (200–285)
	_check(s_on <= 0.06 and (on["stop"] as Array).max() <= 0.18, "stopping, a foot set down skates %.0f mm on average (worst %.0f; ≤ 60 / 180)" % [s_on * 1000.0, (on["stop"] as Array).max() * 1000.0])
	_check(t_on <= 0.09 and (on["turn"] as Array).max() <= 0.16, "turning on the spot, a foot set down skates %.0f mm on average (worst %.0f; ≤ 90 / 160)" % [t_on * 1000.0, (on["turn"] as Array).max() * 1000.0])
	_check(s_off > s_on * 2.0 and t_off > t_on * 2.0, "self-check: without the locks the feet skate only %.0f / %.0f mm — the metric would not see skating" % [s_off * 1000.0, t_off * 1000.0])
	# ≤ 20 mm: stopping, a straightening leg lifts the heel and draws the foot a little before it steps; run to run the
	# worst is 9–16 mm here (31.10, the same seeds — the navigation's timing differs), the old drag was 140–210
	_check(float(on["miss"]) <= 0.02, "a locked foot is %.0f mm off its spot along the floor — dragged (≤ 20)" % (float(on["miss"]) * 1000.0))
	_check(float(on["lift"]) <= 0.05, "a locked foot comes %.0f mm up off the floor — the leg cannot reach and it does not step (≤ 50)" % (float(on["lift"]) * 1000.0))
	_check(float(on["sep"]) >= 0.09, "turning on the spot, the feet stand %.0f mm apart — one on the other, in one line (≥ 90)" % (float(on["sep"]) * 1000.0))
	# ≤ 90 mm (31.10, 15:04 «мельтешит в конце хода»): a foot within settle_m (8 cm) of the stance stays where it was set
	# down — a person does not shuffle into an exact stance; farther, it steps
	_check(float(on["off_stance"]) <= 0.09, "settled, a foot stays %.0f mm off where the stance has it (≤ 90)" % (float(on["off_stance"]) * 1000.0))
	_completed = true


# --- Braid -------------------------------------------------------------------------------------------

var _braid_rows: Array = []


## The braid tip's own spring part: where it is minus where the head would carry it without the spring (rests).
func _on_braid_updated() -> void:
	var v: Actor3D = player.view3d
	var sk := v.skeleton
	var head := sk.find_bone("Head")
	var carried: Transform3D = sk.get_bone_global_pose(head)
	for k in 3:
		carried = carried * sk.get_bone_rest(sk.find_bone("Braid%d" % k))
	var tip := sk.find_bone("Braid2")
	var spine := sk.find_bone("Spine01")
	var xf := v._skel_to_turn()
	var tip_now: Vector3 = xf * sk.get_bone_global_pose(tip).origin
	# clear of the back: the tip's distance from the Spine01 axis (as posed)
	var sp: Transform3D = sk.get_bone_global_pose(spine)
	var a: Vector3 = xf * sp.origin
	var up: Vector3 = (xf.basis * sp.basis * Vector3.UP).normalized()
	var d := tip_now - a
	var off := (d - up * d.dot(up)).length()
	_braid_rows.append([tip_now - xf * carried.origin, off])


func _test_braid() -> void:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	var sim: SpringBoneSimulator3D = v.springs.get("braid", null)
	_check(sim != null, "no spring braid (rt3d.springs braid / bones Braid0..2)")
	if sim == null:
		_completed = true
		return
	_braid_rows = []
	v.seed_idle(21)   # the same stance clips every run (a big weight shift in the standing window swung the tip 1.4 cm)
	seed(21)
	v.skeleton.skeleton_updated.connect(_on_braid_updated)
	await _wait_s(1.0)
	var rest_rows := _braid_rows.duplicate()
	_braid_rows = []
	player.click_at(player.global_position + Vector2(-420, 0))
	await _wait_s(2.0)
	var k: float = player.floor_foreshortening()
	player.face_towards(player.global_position + Vector2(0.5, 0.9 * k) * 200.0)
	await _wait_s(1.2)
	var move_rows := _braid_rows.duplicate()
	await _wait_s(2.5)
	_braid_rows = []
	await _wait_s(1.0)
	var still_rows := _braid_rows.duplicate()
	v.skeleton.skeleton_updated.disconnect(_on_braid_updated)
	var span := func(rows: Array) -> float:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for r in rows:
			lo = lo.min(r[0])
			hi = hi.max(r[0])
		return (hi - lo).length() if not rows.is_empty() else 0.0
	var swing: float = span.call(move_rows)
	var settle: float = span.call(still_rows)
	var clear := INF
	var rest_clear := INF
	for r in move_rows + still_rows:
		clear = minf(clear, float(r[1]))
	for r in rest_rows:
		rest_clear = minf(rest_clear, float(r[1]))
	var radius := 0.0
	for ch in sim.get_children():
		if ch is SpringBoneCollisionCapsule3D:
			radius = maxf(radius, (ch as SpringBoneCollisionCapsule3D).radius)
	print("        braid: the spring swings the tip %.1f cm walking and turning; standing, %.1f cm; tip from the spine axis %.1f cm at least (at rest %.1f, the back's pusher %.1f)" % [swing * 100.0, settle * 100.0, clear * 100.0, rest_clear * 100.0, radius * 100.0])
	# 01.11: the swing measures 2.0–3.3 cm from machine to machine (CI 41255626632: 2.0 moving, 1.5 standing; here 3.3 / 0.8)
	# — the spring is there in both; the thresholds take the CI figures in, a dead braid (no spring) still fails.
	_check(swing > 0.015, "walking and turning, the braid does not swing (%.1f cm): no spring" % (swing * 100.0))
	_check(settle < 0.03 and settle < swing * 0.8, "standing, the braid keeps swinging (%.1f cm, moving %.1f cm)" % [settle * 100.0, swing * 100.0])
	_check(clear >= radius, "the braid's tip goes into the back (%.1f cm from the spine axis, the back %.1f)" % [clear * 100.0, radius * 100.0])
	_completed = true


# --- Arm and bag ---------------------------------------------------------------------------------------

var _bag_rows: Array = []


func _on_bag_updated() -> void:
	var v: Actor3D = player.view3d
	var sk := v.skeleton
	var tm := v._skel_to_model()
	var hips: Transform3D = tm * sk.get_bone_global_pose(sk.find_bone("Hips"))
	var hand: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	var fore: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("RightForeArm")).origin
	_bag_rows.append([v.bag_depth(hand, hips), v.bag_depth(hand.lerp(fore, 0.5), hips)])


## Deepest the drawn right hand and forearm go into the bag's box over a stance, a walk, a talk gesture and «open».
func _bag_runs(on: bool) -> Array:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	v.arm_clear_on = on
	_bag_rows = []
	v.skeleton.skeleton_updated.connect(_on_bag_updated)
	await _wait_s(3.0)
	player.click_at(player.global_position + Vector2(-420, 0))
	await _wait_s(3.0)
	sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "P_1", "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут."}
	await _wait_s(4.5)
	sr.current_beat = {}
	await _wait_s(0.6)
	player._start_action("open", null)
	await _wait_s(4.0)
	v.skeleton.skeleton_updated.disconnect(_on_bag_updated)
	v.arm_clear_on = true
	var hand := 0.0
	var fore := 0.0
	for r in _bag_rows:
		hand = maxf(hand, float(r[0]))
		fore = maxf(fore, float(r[1]))
	return [hand, fore]


func _test_arm_bag() -> void:
	var v: Actor3D = player.view3d
	_check(v != null and v.arm_ik != null, "no arm clearance (rt3d.bag_clear)")
	if v == null or v.arm_ik == null:
		_completed = true
		return
	var on: Array = await _bag_runs(true)
	var off: Array = await _bag_runs(false)
	print("        arm and bag: the hand goes %.0f mm into the bag at most, the forearm %.0f; without the clearance %.0f / %.0f" % [float(on[0]) * 1000.0, float(on[1]) * 1000.0, float(off[0]) * 1000.0, float(off[1]) * 1000.0])
	_check(float(on[0]) <= 0.012, "the right hand goes %.0f mm into the bag (≤ 12)" % (float(on[0]) * 1000.0))
	_check(float(on[1]) <= 0.03, "the right forearm goes %.0f mm into the bag (≤ 30)" % (float(on[1]) * 1000.0))
	_check(float(off[0]) > 0.025, "self-check: without the clearance the hand goes only %.0f mm into the bag — the case is not reproduced" % (float(off[0]) * 1000.0))
	_completed = true


# --- Boots -------------------------------------------------------------------------------------------

var _boot_rows: Array = []


## As drawn (after the boot modifier): per foot the boot's pitch against its bind pose — the elevation of the
## ankle→ball line, degrees, + toe up — and the ankle's height above its bind height (m).
func _on_boot_updated() -> void:
	var v: Actor3D = player.view3d
	var sk := v.skeleton
	var xf := v._skel_to_turn()
	var row: Array = []
	for i in 2:
		var fb: int = v.foot_bones[i * 2]
		var tb: int = v.foot_bones[i * 2 + 1]
		var d: Vector3 = xf.basis * (sk.get_bone_global_pose(tb).origin - sk.get_bone_global_pose(fb).origin)
		var r: Vector3 = xf.basis * (sk.get_bone_global_rest(tb).origin - sk.get_bone_global_rest(fb).origin)
		var el := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		var el_r := rad_to_deg(atan2(r.y, Vector2(r.x, r.z).length()))
		var ank: float = (xf * sk.get_bone_global_pose(fb).origin).y - float(v._foot_bind_h[i])
		# set down: locked and not stepping (a settle step lifts the boot off the floor on purpose — CI 8bf352c6 caught
		# one mid-step: 51 mm up, 9.9°)
		row.append([el - el_r, ank, v._foot_lock[i] != null and v._foot_step[i] == null and float(v._foot_w[i]) >= 0.999])
	_boot_rows.append(row)


func _boot_stand(fix: bool) -> Array:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	v.boot.active = fix
	if not v.skeleton.skeleton_updated.is_connected(_on_boot_updated):
		v.skeleton.skeleton_updated.connect(_on_boot_updated)
	await _frames(60)
	_boot_rows = []
	await _frames(240)
	v.skeleton.skeleton_updated.disconnect(_on_boot_updated)
	v.boot.active = true
	var up := 0.0
	var high := 0.0
	var n := 0
	for row in _boot_rows:
		for i in 2:
			if not bool(row[i][2]):
				continue
			n += 1
			up = maxf(up, absf(float(row[i][0])))
			high = maxf(high, absf(float(row[i][1])))
	return [up, high, n]


func _test_boots() -> void:
	var v: Actor3D = player.view3d
	_check(v.boot != null, "no boot modifier (rt3d.feet.boot)")
	if v.boot == null:
		_completed = true
		return
	var on: Array = await _boot_stand(true)
	var off: Array = await _boot_stand(false)
	print("        standing, the boot off its bind pitch %.1f° at most, the ankle off its height in the boot %.0f mm; without the boot fix %.1f° (the toe turned up)" % [on[0], on[1] * 1000.0, off[0]])
	_check(int(on[2]) >= 200, "only %d set-down boot frames measured" % int(on[2]))
	_check(float(on[0]) <= 6.0, "standing, the boot is turned %.1f° off the pose it was made in (≤ 6°): its toe turns up or digs in" % on[0])
	_check(float(on[1]) <= 0.012, "standing, the ankle is %.0f mm off its height in the boot (≤ 12): the sole off the floor or in it" % (float(on[1]) * 1000.0))
	_check(float(off[0]) > float(on[0]) + 10.0, "self-check: without the boot fix the boot is off only %.1f° — the metric would not see the toe turned up" % off[0])
	_completed = true


# --- Walk rhythm -------------------------------------------------------------------------------------

## A steady walk across Z2: per frame the hips' speed on the floor (the figure's move + the hips inside it), the
## hips' height and the worst move of a drawn foot contact (ankle or ball within 1 cm of the floor), mm per frame.
func _rhythm_walk() -> Dictionary:
	await _enter("Z2", Vector2(400, 900))
	var v: Actor3D = player.view3d
	if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
		v.skeleton.skeleton_updated.connect(_on_skel_updated)
	_drawn_feet = []
	player.yaw3d = PI * 0.5
	player.yaw3d_target = PI * 0.5
	await _frames(30)
	player.click_at(player.global_position + Vector2(900, 0))
	var prev: Vector2 = player.global_position
	var prev_h := NAN
	var prev_c: Array = []
	var hs: Array = []
	var hz: Array = []
	var slips: Array = []
	var looked := 0
	var counted := 0
	var arms := [0.0, 0.0, 0.0]   # worst elbow, spread, wrist over both arms
	var sink := 0.0               # deepest a drawn ankle or ball goes below the stride's floor (m)
	for i in 150:
		await process_frame
		var ppm_s: float = v.ppm * absf(player.scale.y)
		var ox: float = (player.global_position - prev).x / ppm_s
		prev = player.global_position
		var hx: float = v.bone_floor("Hips").x
		var yb := Basis(Vector3.UP, v.get_yaw())
		var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
		var cs: Array = []
		var slip := 0.0
		for k in 2:
			var ha: float = f[k * 2].y - float(v.stride_floor[k * 2])
			var hb: float = f[k * 2 + 1].y - float(v.stride_floor[k * 2 + 1])
			var c: int = k * 2 if ha <= hb else k * 2 + 1
			cs.append([(yb * f[c]).x, minf(ha, hb) < 0.01, c])
			if i > 50 and player.walk_w > 0.99:
				sink = minf(sink, minf(ha, hb))
			if prev_c.size() == 2 and bool(cs[k][1]) and bool(prev_c[k][1]) and int(prev_c[k][2]) == c:
				slip = maxf(slip, absf(float(cs[k][0]) + ox - float(prev_c[k][0])) * 1000.0)
		prev_c = cs
		if i > 50 and player.walk_w > 0.99 and v.shown_w() > 0.99 and not is_nan(prev_h):
			hs.append(absf(hx + ox - prev_h) / maxf(player.get_process_delta_time(), 1e-4))
			hz.append(v.bone_model("Hips").y)
			slips.append(slip)
			counted += 1
			for side in _drawn_arms:
				for j in 3:
					arms[j] = maxf(float(arms[j]), float(side[j]))
			if v._look_on and v._look_w > 0.2:
				looked += 1
		prev_h = hx
	var lo: float = hz.min()
	var hi: float = hz.max()
	var low_sp := [0.0, 0]
	var high_sp := [0.0, 0]
	for k in hs.size():
		var u: float = (float(hz[k]) - lo) / maxf(hi - lo, 0.001)
		if u < 0.333:
			low_sp = [low_sp[0] + float(hs[k]), low_sp[1] + 1]
		elif u > 0.667:
			high_sp = [high_sp[0] + float(hs[k]), high_sp[1] + 1]
	slips.sort()
	return {"low": low_sp[0] / maxf(low_sp[1], 1), "high": high_sp[0] / maxf(high_sp[1], 1), "min": hs.min(), "max": hs.max(),
		"slip90": slips[int(slips.size() * 0.9)], "slip_max": slips.max(), "looked": float(looked) / maxf(counted, 1), "n": counted, "arms": arms, "sink": sink, "bob": hi - lo}


func _test_walk_rhythm() -> void:
	var v: Actor3D = player.view3d
	var r: Dictionary = await _rhythm_walk()
	# self-check: the figure moved by the clip's own stance foot, no stride planting (as before 31.10)
	var spec_walk: Dictionary = v.spec.get("walk", {})
	var spec_stride = v.spec.get("feet", {}).get("stride", {})
	spec_walk["root"] = "foot"
	v.spec["feet"]["stride"] = {}
	v.build_root_motion()
	if v.arm_tone != null:
		v.arm_tone.active = false
	var old: Dictionary = await _rhythm_walk()
	if v.arm_tone != null:
		v.arm_tone.active = true
	spec_walk["root"] = "even"
	v.spec["feet"]["stride"] = spec_stride
	v.build_root_motion()
	print("        hips on the floor: %.2f m/s low (between the steps), %.2f high (over the planted foot), %.2f–%.2f; drawn foot contacts move %.1f mm a frame (90%%), %.1f at most; looking ahead %.0f%% of %d frames" % [r["low"], r["high"], r["min"], r["max"], r["slip90"], r["slip_max"], 100.0 * float(r["looked"]), r["n"]])
	print("        before (root from the clip's stance foot): %.2f low, %.2f high, %.2f–%.2f" % [old["low"], old["high"], old["min"], old["max"]])
	_check(float(r["low"]) >= float(r["high"]) + 0.05, "the hips go %.2f m/s between the steps and %.2f over the planted foot — not a walking body's pace (quickest low, slowest high)" % [r["low"], r["high"]])
	_check(float(r["max"]) - float(r["min"]) <= 0.6, "the hips' speed swings %.2f–%.2f m/s within a step: a lurch" % [r["min"], r["max"]])
	_check(float(r["slip90"]) <= 1.5 and float(r["slip_max"]) <= 4.0, "a foot on the floor moves %.1f mm a frame (90%%; at most %.1f) — it skates (≤ 1.5 / 4)" % [r["slip90"], r["slip_max"]])
	print("        hips up and down %.1f cm a step (the clip's own %.1f); the feet at most %.1f mm into the floor" % [float(r["bob"]) * 100.0, float(old["bob"]) * 100.0, -float(r["sink"]) * 1000.0])
	_check(float(r["bob"]) >= 0.037, "the hips rise and fall only %.1f cm a step — a walking body's about 5 (≥ 3.7)" % (float(r["bob"]) * 100.0))
	_check(float(r["sink"]) >= -0.005, "a foot goes %.1f mm into the floor (≤ 5)" % (-float(r["sink"]) * 1000.0))
	_check(float(old["bob"]) < 0.035, "self-check: the clip's own hips go %.1f cm — the metric would not see the deeper step" % (float(old["bob"]) * 100.0))
	var am: Array = r["arms"]
	var ao: Array = old["arms"]
	print("        arms walking, at most: elbow %.0f°, spread %.0f°, wrist %.0f° (the clip's own: %.0f°, %.0f°, %.0f°)" % [am[0], am[1], am[2], ao[0], ao[1], ao[2]])
	_check(float(am[0]) <= 55.0 and float(am[1]) <= 28.0 and float(am[2]) <= 30.0, "walking, the arms bend the elbow to %.0f°, spread %.0f°, the wrist %.0f° — a doll's paw held out (≤ 55 / 28 / 30)" % [am[0], am[1], am[2]])
	_check(float(ao[0]) > 60.0 and float(ao[1]) > 30.0, "self-check: the clip's own arms bend only %.0f° and spread %.0f° — the metric would not see them" % [ao[0], ao[1]])
	_check(float(r["looked"]) >= 0.9, "walking with nothing to look at, she looks ahead only %.0f%% of the time (the clip's head is bowed to the floor)" % (100.0 * float(r["looked"])))
	_check(float(old["low"]) < float(old["high"]), "self-check: the old walk (root from the clip's foot) went %.2f low and %.2f high — the metric would not tell the pace apart" % [old["low"], old["high"]])
	_completed = true


# --- Stopping -----------------------------------------------------------------------------------------

## Six walks across Z2: from the moment the walk starts slowing until 1.5 s after she stands still, how many times a
## drawn foot leaves the floor (ankle and ball both over 2 cm above the stride's floor).
var _stop_late: Array = []   # per stop: the last moment (s after she stood still) a foot left the floor
var _stop_end: Array = []    # per stop: how far (px) from the end of her path she came to rest


func _stop_lifts(planned: bool) -> Array:
	var walk: Dictionary = player.view3d.spec.get("walk", {})
	var keep = walk.get("stop", "")
	if not planned:
		walk["stop"] = ""
	var out: Array = []
	_stop_late = []
	_stop_end = []
	for k in 6:
		await _enter("Z2", Vector2(500 + (k % 3) * 150, 860 + (k % 2) * 80))
		var v: Actor3D = player.view3d
		v.seed_idle(60 + k)
		seed(60 + k)
		if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
			v.skeleton.skeleton_updated.connect(_on_skel_updated)
		_drawn_feet = []
		var ang := PI * 0.5 + (k - 2.5) * 0.25
		player.yaw3d = ang
		player.yaw3d_target = ang
		await _frames(30)
		var kf: float = player.floor_foreshortening()
		player.click_at(player.global_position + Vector2(sin(ang), cos(ang) * kf) * (500.0 + k * 40.0))
		var slowing := false
		var after := 0.0
		var t := 0.0
		var up: Array = [false, false]
		var lifts := 0
		var first := true
		var late := -1.0
		var path_end: Vector2 = player.global_position
		var room0: String = rm.current_room.room_id
		while after < 1.5 and t < 8.0:
			await process_frame
			var d: float = player.get_process_delta_time()
			t += d
			if player.is_walking():
				var pth: PackedVector2Array = player.nav_agent.get_current_navigation_path()
				if pth.size() > 0:
					path_end = pth[pth.size() - 1]
			if not slowing and player.is_walking() and player.walk_w < 0.99 and player.walk_time > 0.6:
				slowing = true
			if not slowing:
				continue
			if not player.is_walking():
				after += d
			var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
			for i in 2:
				var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
				# up over 2.5 cm, down under 1.5 (no flicker at the line); a foot already in the air as the slowing
				# starts is that step, not a new one
				var now_up: bool = h > 0.025 or (up[i] and h > 0.015)
				if now_up and not up[i] and not first:
					lifts += 1
					if not player.is_walking():
						late = maxf(late, after)
				up[i] = now_up
			if first:
				lifts += int(up[0]) + int(up[1])
				first = false
		out.append(lifts)
		_stop_late.append(late)
		# a walk that is still going on as the watch ends (the click off the floor: a long way round) is no stop to measure
		# (walk 4 runs into the street's exit: the room changes under her — no stop to measure either)
		_stop_end.append(player.global_position.distance_to(path_end) if not player.is_walking() and rm.current_room.room_id == room0 else -1.0)
	walk["stop"] = keep
	return out


func _test_stop_steps() -> void:
	var on: Array = await _stop_lifts(true)
	var off: Array = await _stop_lifts(false)
	var so := on.duplicate()
	so.sort()
	var sf := off.duplicate()
	sf.sort()
	print("        stopping, feet lifted per stop: %s (median %d); easing the walk down as before: %s (median %d)" % [str(on), so[so.size() / 2], str(off), sf[sf.size() / 2]])
	# 01.11 (Director, morning page: «семенит, доступает»): a stop is its last one or two steps and the closing step of the
	# foot left behind — two or three lifts, never more, and nothing after (the closing step now starts the moment the
	# last step is down and lands in the stance; before, a settling step came a second later)
	var sum_on := 0
	var sum_off := 0
	for x in on:
		sum_on += int(x)
	for x in off:
		sum_off += int(x)
	_check(int(so[so.size() / 2]) <= 3 and int(so[so.size() - 1]) <= 3, "stopping takes %s steps (median ≤ 3, at most 3): quick little steps" % str(on))
	# self-check: the metric sees the fidgeting of the old stop — more steps in all than the new one and at least four in
	# a stop (31.10, K: the median alone moved with the tests run before it — 3 in the whole file, 4 alone)
	_check(sum_off > sum_on and int(sf[sf.size() - 1]) >= 4,
		"self-check: the old stop took only %s steps (the new %s) — the metric would not see the fidgeting" % [str(off), str(on)])
	_completed = true


## 01.11 (Director, morning page: «при остановке — семенит, доступает»): once she stands, the only foot still to move is
## the one closing up, and it sets off at once — no foot leaves the floor later than 0.12 s after the stop (before: a
## settling step 0.3–1.5 s later, from the stride planting's offset or a leg out of reach); and she comes to rest on the
## end of her path (the planned stop reckons with the follower's lag and the glide over the front foot).
func _test_stop_settles() -> void:
	var on: Array = await _stop_lifts(true)
	var late_max := -1.0
	for x in _stop_late:
		late_max = maxf(late_max, float(x))
	var end_max := 0.0
	for x in _stop_end:
		end_max = maxf(end_max, float(x))
	var measured := 0
	for x in _stop_end:
		if float(x) >= 0.0:
			measured += 1
	print("        stops %s; last lift after the stop: %s s; from the path's end: %s px" % [str(on), str(_stop_late.map(func(x): return snappedf(float(x), 0.01))), str(_stop_end.map(func(x): return snappedf(float(x), 0.1)))])
	_check(late_max <= 0.12, "a foot leaves the floor %.2f s after she stood still (≤ 0.12: the closing step starts at once, nothing after it): %s" % [late_max, str(_stop_late)])
	_check(measured >= 4 and end_max <= 6.0, "she comes to rest %.1f px from the end of her path (≤ 6; %d stops measured): %s" % [end_max, measured, str(_stop_end)])
	_completed = true


# --- Pick from the floor -------------------------------------------------------------------------------

var _pick_rows: Array = []


## As drawn (after the modifiers): the left hand's height above the floor (m) — the hand that takes the thing in both
## clips — the feet, and whether the action's effect has fired yet.
func _on_pick_updated() -> void:
	var v: Actor3D = player.view3d
	_pick_rows.append([v.bone_model("LeftHand").y, v.feet_model(), player._action_fired, player.is_acting()])


## One action from the stance at H1: [lowest hand (m), hand at the effect (m), highest hand after the lowest point until
## 0.6 s after the end (m), the most a foot moves along the floor (m), the action's length (s)].
func _pick_run(act: String) -> Array:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	await _frames(30)
	if not v.skeleton.skeleton_updated.is_connected(_on_pick_updated):
		v.skeleton.skeleton_updated.connect(_on_pick_updated)
	_pick_rows = []
	player._start_action(act, null)
	var len_s: float = player._act_len / maxf(player._act_speed, 0.01)
	var guard := 0
	while player.is_acting() and guard < 600:
		await process_frame
		guard += 1
	await _wait_s(0.6)
	v.skeleton.skeleton_updated.disconnect(_on_pick_updated)
	var low := 9.0
	var low_i := 0
	var at_fire := -1.0
	for i in _pick_rows.size():
		var h := float(_pick_rows[i][0])
		if h < low:
			low = h
			low_i = i
		if at_fire < 0.0 and bool(_pick_rows[i][2]):
			at_fire = h
	var high_after := 0.0
	for i in range(low_i, _pick_rows.size()):
		high_after = maxf(high_after, float(_pick_rows[i][0]))
	# A foot on the floor (ankle within 15 mm of its lowest) does not skate: its travel along the floor while set
	# down, per stint; a step (lifted, set down elsewhere — the clip steps forward to bend and back) is not skating.
	var slide := 0.0
	var steps := 0
	for k in [0, 2]:
		var floor_y := 9.0
		for r in _pick_rows:
			floor_y = minf(floor_y, float(((r[1] as Array)[k] as Vector3).y))
		var stint := 0.0
		var was_down := true
		for i in range(1, _pick_rows.size()):
			var a: Vector3 = (_pick_rows[i - 1][1] as Array)[k]
			var b: Vector3 = (_pick_rows[i][1] as Array)[k]
			var down := a.y <= floor_y + 0.015 and b.y <= floor_y + 0.015
			if down:
				stint += Vector2(b.x - a.x, b.z - a.z).length()
				slide = maxf(slide, stint)
			else:
				stint = 0.0
				if was_down:
					steps += 1
			was_down = down
	return [low, at_fire, high_after, slide, len_s, steps]


func _test_pick_floor() -> void:
	# Data: which things are taken from the floor.
	var sd = root.get_node("StoryData")
	var floor_things := {"O1": ["sack"], "O2": ["porch_step", "mitten", "mitten_path"], "O4": ["letters_bag"]}
	for rid in floor_things.keys():
		for h in sd.rooms[rid].get("hotspots", []):
			if (floor_things[rid] as Array).has(String(h.get("id", ""))):
				_check(String(h.get("action_anim", "")) == "pick_low", "%s.%s lies on the floor: action_anim '%s', pick_low expected" % [rid, h.get("id", ""), h.get("action_anim", "")])
	for h in sd.rooms["H1"].get("hotspots", []):
		if String(h.get("id", "")) == "scarf":
			_check(String(h.get("action_anim", "")) == "pick", "H1.scarf lies on the bench (knee height): keeps the crouch pick, got '%s'" % h.get("action_anim", ""))
	# The drawn figure plays the pick sheet for it, with the same key frame.
	var sheet = player.sheet
	_check(sheet.has_action("pick_low") and sheet.action_sequence("pick_low").size() == sheet.action_sequence("pick").size() and not sheet.action_loops("pick_low"),
		"sheet: pick_low should play the pick sheet once (same_as)")
	_check(sheet.action_key_frame("pick_low") == sheet.action_key_frame("pick"), "sheet: pick_low key frame %d, pick %d" % [sheet.action_key_frame("pick_low"), sheet.action_key_frame("pick")])
	if not player.is_3d():
		_completed = true
		return
	_check(String(player.view3d.clips.get("pick_low", "")) == "Female_Bend_Over_Pick_Up_Inspect", "rt3d.clips.pick_low: %s" % player.view3d.clips.get("pick_low", ""))
	# Bent to the floor the inside of the skirt shows between the legs: it was a flat blue-grey patch — the shader
	# flipped the back faces' normal that Godot had already turned to the viewer (debug render 31.10). The inside of
	# the clothes is lit as the inside: no second flip, inside_light.
	var code: String = (player.view3d.material.shader as Shader).code
	_check(not code.contains("n = -n") and code.contains("inside_light"), "shader: back faces must keep Godot's normal and be shaded as the inside (inside_light)")
	var low: Array = await _pick_run("pick_low")
	var old: Array = await _pick_run("pick")
	print("        floor pick: hand down to %.0f mm (at the effect %.0f), up to %.0f mm after; a set-down foot skates %.0f mm, %d lifts; %.2f s. Crouch pick: hand down to %.0f mm" % [
		float(low[0]) * 1000.0, float(low[1]) * 1000.0, float(low[2]) * 1000.0, float(low[3]) * 1000.0, int(low[5]), float(low[4]), float(old[0]) * 1000.0])
	_check(float(low[0]) <= 0.35, "the hand reaches down to %.0f mm — not to the floor (≤ 350)" % (float(low[0]) * 1000.0))
	_check(float(low[1]) >= 0.0 and float(low[1]) <= 0.40, "at the effect the hand is %.0f mm above the floor (≤ 400: the thing leaves the floor in her hand)" % (float(low[1]) * 1000.0))
	_check(float(low[2]) <= 1.10, "after taking it the hand rises to %.0f mm — lifts the thing to the face (G1: ≤ 1100)" % (float(low[2]) * 1000.0))
	_check(float(low[3]) <= 0.02, "a foot set down skates %.0f mm along the floor while she bends (≤ 20)" % (float(low[3]) * 1000.0))
	_check(float(low[4]) <= 3.0, "the floor pick takes %.2f s (≤ 3)" % float(low[4]))
	_check(float(old[0]) > 0.5, "self-check: the crouch pick also reaches %.0f mm — the metric would not tell a floor pick from it" % (float(old[0]) * 1000.0))
	_completed = true


# --- Corners near the end ---------------------------------------------------------------------------

## Walks between the post office's stands (Z1: behind the counter, in front of it, beside Tamara) as a player clicks
## them: each must arrive (within 60 px) without walking on the spot (walk weight up, the body under 25 px/s for 0.6 s).
## Returns [walks that failed, their words].
func _corner_walks() -> Array:
	await _enter("Z1", Vector2(250, 900))
	await _frames(30)
	var stands := [Vector2(740, 712), Vector2(840, 940), Vector2(1510, 800), Vector2(1260, 712), Vector2(740, 712), Vector2(1510, 800), Vector2(840, 940)]
	var bad := 0
	var words := ""
	var prev := Vector2(250, 900)
	for to in stands:
		player.walk_to(to)
		var t := 0.0
		var stall := 0.0
		var worst := 0.0
		var last: Vector2 = player.global_position
		while t < 10.0:
			await process_frame
			var d: float = player.get_process_delta_time()
			t += d
			var v: float = player.global_position.distance_to(last) / maxf(d, 0.001)
			last = player.global_position
			if player.is_walking() and float(player.walk_w) > 0.5 and v < 25.0:
				stall += d
				worst = maxf(worst, stall)
			else:
				stall = 0.0
			if t > 0.3 and not player.is_walking():
				break
		var left: float = player.global_position.distance_to(to)
		if left > 60.0 or worst >= 0.6:
			bad += 1
			words += " %s→%s: %.0f px short (stopped at %s), on the spot %.1f s;" % [str(prev), str(to), left, str(player.global_position.round()), worst]
		prev = to
		await _frames(20)
	return [bad, words]


func _test_walk_corners() -> void:
	if not player.is_3d():
		_completed = true
		return
	var on: Array = await _corner_walks()
	player.stop_straight_only = false
	player.stop_short_rescue = false   # the self-check reproduces the old fault: no walking the rest after a short stop
	var off: Array = await _corner_walks()
	player.stop_short_rescue = true
	player.stop_straight_only = true
	print("        corners: %d of 7 walks failed%s; with the stop planned before the corner: %d%s" % [on[0], on[1], off[0], off[1]])
	_check(int(on[0]) == 0, "walks near the counter's corners failed:%s" % on[1])
	_check(int(off[0]) > 0, "self-check: with the stop planned before the last corner every walk arrived — the case is not reproduced")
	_completed = true


## Director 01.11, line 2: the letters' stand (behind the counter) → points at the bottom of the screen and back. The path
## rounds the counter's front-left corner (a 130° turn): heading for a point past the corner she pushed into the counter
## and the floor held her — 8–9 s on the spot (probe zz_k1_walk, 01.11); in front of it the feet went 10–27 px from the
## front legs (y 890), the skirt into the counter. Unit check of the follower at that corner (deterministic) + the walks.
func _test_walk_corner_front() -> void:
	# the follower: approaching the corner along the front edge, the point she heads for is the corner, not past it
	var PL = load("res://scripts/actors/player.gd")
	var path := PackedVector2Array([Vector2(960, 1040), Vector2(417, 930), Vector2(567, 751), Vector2(740, 712)])
	var hole := PackedVector2Array([Vector2(567, 751), Vector2(1445, 751), Vector2(1602, 930), Vector2(417, 930)])
	var inner: PackedVector2Array = Geometry2D.offset_polygon(hole, -3.0)[0]   # the edge itself is floor
	for pos in [Vector2(470, 941), Vector2(440, 935), Vector2(425, 931)]:
		var pf: Array = PL.path_follow(path, pos, 0, 127.0)
		var c: Vector2 = pf[0]
		var crosses := false
		for k in 21:
			crosses = crosses or Geometry2D.is_point_in_polygon((pos as Vector2).lerp(c, float(k) / 20.0), inner)
		_check(not crosses, "from %s the follower heads for %s — across the counter's corner" % [str(pos), str(c.round())])
	var past: Array = PL.path_follow(path, Vector2(414, 931), 0, 127.0)
	_check((past[0] as Vector2).y < 900.0, "past the corner she heads on up the side, got %s" % str((past[0] as Vector2).round()))
	if not player.is_3d():
		_completed = true
		return
	await _enter("Z1", Vector2(740, 712))
	await _frames(30)
	var bad := ""
	var near := 999.0
	for to in [Vector2(960, 1040), Vector2(740, 712), Vector2(960, 1000), Vector2(740, 712), Vector2(800, 1000), Vector2(740, 712), Vector2(1100, 1050), Vector2(740, 712)]:
		player.walk_to(to)
		var t := 0.0
		var stall := 0.0
		var worst := 0.0
		var last: Vector2 = player.global_position
		while t < 10.0:
			await process_frame
			var d: float = player.get_process_delta_time()
			t += d
			var p: Vector2 = player.global_position
			var v: float = p.distance_to(last) / maxf(d, 0.001)
			last = p
			if p.y > 890.0 and p.x > 598.0 - 70.0 * absf(player.scale.y) and p.x < 1422.0 + 70.0 * absf(player.scale.y):
				near = minf(near, p.y - 890.0)
			if player.is_walking() and float(player.walk_w) > 0.5 and v < 25.0:
				stall += d
				worst = maxf(worst, stall)
			else:
				stall = 0.0
			if t > 0.3 and not player.is_walking():
				break
		var left: float = player.global_position.distance_to(to)
		if left > 60.0 or worst >= 0.6:
			bad += " →%s: %.0f px short, on the spot %.1f s;" % [str(to), left, worst]
		await _frames(20)
	print("        letters ↔ bottom: nearest to the counter's front legs %.0f px%s" % [near, bad])
	_check(bad == "", "walks round the counter's corner failed:%s" % bad)
	_check(near >= 30.0, "her feet came %.0f px to the counter's front legs (y 890) — the body goes into it" % near)
	_completed = true


# --- Talking to someone -----------------------------------------------------------------------------

func _test_gesture_addressed() -> void:
	var PL = load("res://scripts/actors/player.gd")
	var cases := [
		[{"type": "line", "speaker": "agata", "text_key": "H4.chest.open", "line_id": "agata:H4.chest.open"}, false, "the chest's text — her own words over what she found"],
		[{"type": "line", "speaker": "agata", "text_key": "M2.mirror.look", "line_id": "agata:M2.mirror.look"}, false, "a look at the office mirror"],
		[{"type": "line", "speaker": "agata", "text_key": "H1.tikhon.cream_2", "line_id": "agata:H1.tikhon.cream_2"}, true, "a line of the talk with Tikhon"],
		[{"type": "line", "speaker": "agata", "text_key": "O1d.ulyana.ttt_q", "line_id": "agata:O1d.ulyana.ttt_q"}, true, "asking Ulyana to play"],
		[{"type": "line", "speaker": "agata", "scene": "M01", "line_id": "M01_2"}, true, "the talk with Tamara (M01)"],
		[{"type": "line", "speaker": "agata", "scene": "M02", "line_id": "M02_0"}, true, "the talk with Pelageya (M02)"],
	]
	for c in cases:
		var got: bool = PL.gesture_addressed(c[0])
		_check(got == bool(c[1]), "%s: talking hands %s, expected %s" % [c[2], got, c[1]])
	# a scene of her own words only (no one else speaks) — none
	var own := ""
	for id in root.get_node("StoryData").scenes.keys():
		var only_her := true
		var lines: Array = root.get_node("StoryData").scenes[id].get("mandatory_lines", [])
		for ln in lines:
			var sp := String((ln as Dictionary).get("speaker", ""))
			if sp != "" and sp != "agata" and sp != "narrator":
				only_her = false
		if only_her and not lines.is_empty():
			own = String(id)
			break
	if own != "":
		_check(not PL.gesture_addressed({"type": "line", "speaker": "agata", "scene": own}), "%s has no one else speaking: no talking hands" % own)
	_completed = true


# --- 01.11 playthrough: the right arm, short moves, the skirt with the legs ------------------------------------------------

var _jerk_rows: Array = []


func _on_jerk_updated() -> void:
	var v: Actor3D = player.view3d
	var sk := v.skeleton
	var tm := v._skel_to_model()
	var chest: Vector3 = tm * sk.get_bone_global_pose(sk.find_bone("Spine02")).origin
	_jerk_rows.append([tm * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin - chest,
		tm * sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin - chest,
		tm * sk.get_bone_global_pose(sk.find_bone("RightForeArm")).origin - chest])


## Standing (stance variants crossfading) and talking: the largest second difference of each hand against the chest, mm
## per 1/60 s² — [right hand, left hand, right elbow].
func _jerk_run(soft: bool) -> Array:
	await _enter("H1", Vector2(1200, 960))
	var v: Actor3D = player.view3d
	v.seed_idle(5)
	v.arm_soft_switch = soft
	await _wait_s(1.0)   # past the room change (a cut: the pose may jump there, as it should)
	_jerk_rows = []
	v.skeleton.skeleton_updated.connect(_on_jerk_updated)
	await _wait_s(30.0)
	for k in 2:
		sr.current_beat = {"type": "line", "speaker": "agata", "line_id": "J_%d" % k, "to": "tikhon", "text": "Тихон, ты бы видел! У мамы там стрелки так и бегут, а у меня еле ползут, и всё тут."}
		await _wait_s(5.0)
		sr.current_beat = {}
		await _wait_s(1.0 + k * 0.7)
	v.skeleton.skeleton_updated.disconnect(_on_jerk_updated)
	v.arm_soft_switch = true
	var mx := [0.0, 0.0, 0.0]
	for i in range(1, _jerk_rows.size() - 1):
		for h in 3:
			var a: Vector3 = (_jerk_rows[i + 1][h] as Vector3) - 2.0 * (_jerk_rows[i][h] as Vector3) + (_jerk_rows[i - 1][h] as Vector3)
			mx[h] = maxf(mx[h], a.length() * 1000.0)
	return mx


## Director 01.11, line 20: «Агатина правая рука иногда резко дёргается, будто конец анимации и начало снова её, но места
## не сходятся». Not a clip's seam (the clips alone: the right hand ≤ 2.3 mm/frame² standing, ≤ 4.2 talking — like the
## left): the arm kept out of the bag chose the shorter way out — sideways or behind — and the choice flipped as the stance
## swayed the hand across the line where both were equal: the hand jumped 7–9 cm in one frame (87 mm/frame²). And the
## elbow: the hanging arm is nearly straight, the pushed target lay at its full length, and the two-bone solution swung
## the elbow 30–53 mm/frame² (the clip's own ≤ 4) — now a soft reach and the elbow's pole a little back.
func _test_arm_no_jerk() -> void:
	var on: Array = await _jerk_run(true)
	var off: Array = await _jerk_run(false)
	print("        right hand: max %.1f mm/frame² (left %.1f), right elbow %.1f; as before (the way out flipping, full reach): hand %.1f, elbow %.1f" % [float(on[0]), float(on[1]), float(on[2]), float(off[0]), float(off[2])])
	_check(float(on[0]) <= 8.0, "the right hand jerks: %.1f mm/frame² (≤ 8; the left hand %.1f)" % [float(on[0]), float(on[1])])
	_check(float(on[2]) <= 8.0, "the right elbow jerks: %.1f mm/frame² (≤ 8)" % float(on[2]))
	_check(float(off[0]) > 30.0 and float(off[2]) > 15.0, "self-check: as before the right hand jerks only %.1f mm/frame², the elbow %.1f — the case is not reproduced" % [float(off[0]), float(off[2])])
	_completed = true


## Short moves from standing, per move: [lifts of a drawn foot, last lift (s after the click), px from the target at rest].
func _short_moves(shuffle: bool) -> Array:
	var out: Array = []
	var cases := [[0.2, 0], [0.3, 90], [0.25, 180], [0.4, 135], [0.15, -45], [0.45, 0]]
	for ci in cases.size():
		var c: Array = cases[ci]
		await _enter("H1", Vector2(1100, 960))
		player.shuffle_on = shuffle
		var v: Actor3D = player.view3d
		v.seed_idle(60 + ci)
		if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
			v.skeleton.skeleton_updated.connect(_on_skel_updated)
		var face := PI * 0.5
		player.yaw3d = face
		player.yaw3d_target = face
		await _wait_s(1.5)
		_drawn_feet = []
		var ang := face + deg_to_rad(float(c[1]))
		var target: Vector2 = player.global_position + Vector2(sin(ang), cos(ang) * player.floor_foreshortening()) * float(c[0]) * v.ppm * absf(player.scale.y)
		player.click_at(target)
		var t := 0.0
		var up: Array = [false, false]
		var lifts := 0
		var last := 0.0
		var arrived_t := -1.0
		# until a second after she has arrived: the move's own steps (later, a stance variant's crossfade may step anyway)
		while t < 3.5 and (arrived_t < 0.0 or t < arrived_t + 1.0):
			await process_frame
			t += player.get_process_delta_time()
			if arrived_t < 0.0 and not player.is_walking():
				arrived_t = t
			var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
			for i in 2:
				var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
				var now_up: bool = h > 0.025 or (up[i] and h > 0.015)
				if now_up and not up[i]:
					lifts += 1
					last = t
				up[i] = now_up
		out.append([lifts, last, player.global_position.distance_to(target), player.is_walking()])
	player.shuffle_on = true
	return out


## Director 01.11, line 3: «АГАТА ТАКЖЕ МЕЛЬТЕШИТ!!! куча перестановок ног ненужных». A move of 15–45 cm from standing
## (a hotspot beside her, a correction) was walked with the walk clip whose weight never got to half: partial steps at
## the clip's cadence, the turn before it stepped on the spot — 5–8 lifts, the last up to 1.5 s after the click
## (tests/probe_short_moves.gd). Now a «переступ»: one foot to where it will stand, the other closes up — two lifts, there.
func _test_short_moves() -> void:
	var on: Array = await _short_moves(true)
	# as before: no «переступ», and (02.11, стр. 7) the walk's stepping still mixed into a standing turn over 50°
	var tk: Dictionary = player.get("_rt").get("turn", {})
	var fk: Dictionary = player.view3d.spec.get("feet", {})
	var keep_w := float(tk.get("step_weight", 0.0))
	var keep_st := float(fk.get("step_turn_m", 0.085))
	tk["step_weight"] = 0.3
	fk["step_turn_m"] = 0.035   # and the turn's own steps every 3,5 cm, as before 02.11
	var off: Array = await _short_moves(false)
	tk["step_weight"] = keep_w
	fk["step_turn_m"] = keep_st
	print("        short moves [lifts, last lift s, px off, walking]: %s; walked as before: %s" % [str(on.map(func(r): return [r[0], snappedf(r[1], 0.01), snappedf(r[2], 0.1), r[3]])), str(off.map(func(r): return r[0]))])
	var worst_off := 0
	for i in on.size():
		_check(int(on[i][0]) <= 2, "short move %d: %d lifts (≤ 2: a step and the other foot closing up)" % [i, int(on[i][0])])
		_check(float(on[i][1]) <= 1.0, "short move %d: a foot still lifts %.2f s after the click (≤ 1.0)" % [i, float(on[i][1])])
		_check(float(on[i][2]) <= 3.0 and not bool(on[i][3]), "short move %d: comes to rest %.1f px from the target (≤ 3), walking %s" % [i, float(on[i][2]), str(on[i][3])])
		worst_off = maxi(worst_off, int(off[i][0]))
	_check(worst_off >= 5, "self-check: walked as before, the short moves took at most %d lifts — the fidgeting is not reproduced" % worst_off)
	_completed = true


var _hem_rows: Array = []


func _on_hem_updated() -> void:
	_hem_rows.append(float(_ProbeSkirt.measure(player.view3d)[0]))


const _ProbeSkirt := preload("res://tests/probe_skirt_drive.gd")


## Walking 2.5 s (after the start): how far a shin's axis goes out of the ring of the hem points at the hem's height, m.
func _hem_run(drive: bool) -> float:
	await _enter("H1", Vector2(1500, 960))
	var v: Actor3D = player.view3d
	if v.skirt_drive != null:
		v.skirt_drive.on = drive
	_hem_rows = []
	player.click_at(player.global_position + Vector2(-700, 0))
	await _wait_s(0.6)
	v.skeleton.skeleton_updated.connect(_on_hem_updated)
	await _wait_s(1.6)
	v.skeleton.skeleton_updated.disconnect(_on_hem_updated)
	await _wait_s(2.0)
	if v.skirt_drive != null:
		v.skirt_drive.on = true
	var mx := 0.0
	for x in _hem_rows:
		mx = maxf(mx, float(x))
	return mx


## Vertices of the figure's mesh between lo and hi metres up with more than 0.3 of their weight on a shin bone.
func _shin_bound(v: Actor3D, lo: float, hi: float) -> int:
	var mi: MeshInstance3D = null
	for m in v.meshes:
		if mi == null or (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			mi = m
	var n := 0
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			if verts[i].y < lo or verts[i].y > hi:
				continue
			var w := 0.0
			for j in per:
				var nm := String(mi.skin.get_bind_name(int(bones[i * per + j])))
				if nm == "LeftLeg" or nm == "RightLeg":
					w += float(weights[i * per + j])
			if w > 0.3:
				n += 1
	return n


## Director 01.11, line 3: «ноги неестественно, будто 2 не связанных с юбкой ботинка сами шагают, а при шагании ноги
## выпирают будто штаны из-под юбки, а сама юбка не двигается». The springs' pushers on the shins moved the hem 2–7 cm:
## walking, a shin came 16–19 cm out of the hem ring (the boots stepping from under a still bell of a skirt, the hem
## pieces bound to the shins dragged after them). Now the skirt's chains are carried by the legs (SkirtDrive).
func _test_skirt_with_legs() -> void:
	var v: Actor3D = player.view3d
	_check(v != null and v.skirt_drive != null, "no skirt drive (rt3d.skirt.drive)")
	if v == null or v.skirt_drive == null:
		_completed = true
		return
	# the strips of the hem bound to the shins («штаны»): tools/rig_skirt.py bound the skirt within 15 cm of a shin and below
	# 0.40 m partly to it (419 vertices at 0.27–0.45 m mostly on a shin); since the drive carries the hem, only the cloth
	# at the boot tops is (tools/reweight_skirt_glb.py --leg_reach 0.06 --leg_top 0.26). Self-check: the count sees the
	# boot shafts below the hem (on the shins by design).
	var strips := _shin_bound(v, 0.27, 0.45)
	var shafts := _shin_bound(v, 0.15, 0.20)
	print("        skirt vertices at 0.27–0.45 m mostly on a shin: %d (before the re-weight 419); boot shafts at 0.15–0.20 m: %d" % [strips, shafts])
	_check(strips <= 20, "%d skirt vertices at 0.27–0.45 m follow a shin (≤ 20): trouser strips" % strips)
	_check(shafts > 1000, "self-check: only %d boot-shaft vertices found on the shins — the count does not work" % shafts)
	var on: float = await _hem_run(true)
	var off: float = await _hem_run(false)
	print("        walking, a shin goes %.1f cm out of the hem at most; without the drive %.1f cm" % [on * 100.0, off * 100.0])
	_check(on <= 0.05, "walking, a shin goes %.1f cm out of the skirt's hem (≤ 5): the boots step out from under a still skirt" % (on * 100.0))
	_check(off >= 0.10, "self-check: without the drive a shin goes only %.1f cm out of the hem — the case is not reproduced" % (off * 100.0))
	_completed = true


## Walks of 1,2–2,4 m, then the turn to the thing she came to (as a click on a hotspot does: Player.face_towards):
## per walk [lifts after arriving (closing step included), the last one s after arriving].
func _after_arrive_runs() -> Array:
	var out: Array = []
	var cases := [[1.6, 0, 90], [2.0, 45, 150], [1.2, -60, -90], [2.4, 180, 120], [1.8, 90, -150], [1.4, 30, 60]]
	for ci in cases.size():
		var c: Array = cases[ci]
		await _enter("H1", Vector2(1000, 940))
		var v: Actor3D = player.view3d
		v.seed_idle(80 + ci)
		if not v.skeleton.skeleton_updated.is_connected(_on_skel_updated):
			v.skeleton.skeleton_updated.connect(_on_skel_updated)
		await _wait_s(1.2)
		_drawn_feet = []
		var ang := deg_to_rad(float(c[1]))
		var target: Vector2 = player.global_position + Vector2(sin(ang), cos(ang) * player.floor_foreshortening()) * float(c[0]) * v.ppm * absf(player.scale.y)
		player.click_at(target)
		var t := 0.0
		var up: Array = [false, false]
		var lifts := 0
		var last := 0.0
		var arrived_t := -1.0
		var down_t: Array = [-9.0, -9.0]   # when each foot was last set down
		var again := 0                     # a foot lifted again within 0,3 s of its own set-down: the shuffle
		while t < 9.0 and (arrived_t < 0.0 or t < arrived_t + 3.0):
			await process_frame
			t += player.get_process_delta_time()
			if arrived_t < 0.0 and not player.is_walking():
				arrived_t = t
				var fa := float(player.yaw3d) + deg_to_rad(float(c[2]))
				player.face_towards(player.global_position + Vector2(sin(fa), cos(fa)) * 200.0)
			var f: Array = _drawn_feet if not _drawn_feet.is_empty() else v.feet_model()
			for i in 2:
				var h: float = minf(f[i * 2].y - float(v.stride_floor[i * 2]), f[i * 2 + 1].y - float(v.stride_floor[i * 2 + 1]))
				var now_up: bool = h > 0.025 or (up[i] and h > 0.015)
				if now_up and not up[i] and arrived_t >= 0.0:
					lifts += 1
					last = t - arrived_t
					if t - float(down_t[i]) < 0.3:
						again += 1
				if not now_up and up[i]:
					down_t[i] = t
				up[i] = now_up
		out.append([lifts, last, again])
	return out


func _test_after_arrive() -> void:
	var runs: Array = await _after_arrive_runs()
	var mean := 0.0
	var latest := 0.0
	for r in runs:
		mean += float(r[0]) / float(runs.size())
		latest = maxf(latest, float(r[1]))
	print("        after arriving [lifts, the last (s)]: %s (mean %.2f, the latest %.2f s)" % [str(runs.map(func(r): return [r[0], snappedf(r[1], 0.01)])), mean, latest])
	for i in runs.size():
		_check(int(runs[i][0]) <= 4, "walk %d: %d lifts after arriving, the last %.2f s after (≤ 4: the closing step and the turn's steps)" % [i + 1, int(runs[i][0]), float(runs[i][1])])
	_check(mean <= 2.7, "on average %.2f lifts after arriving (≤ 2,7)" % mean)
	# Director 09.11, 22:18 («ноги Агаты перебираются слишком часто в конце движения — именно и только ноги»): arriving
	# and turning to what she came to, the feet stepped «where the stance will be a moment later» — the same foot up to
	# three times in 0,8 s (probe_play `feet`: L closing, L, R, L on a 55° turn). With the turn's end known to the feet
	# (data feet.turn_to_end) each steps once, straight to where it will stand: 2,2–2,3 lifts on these six walks
	# against 2,5–2,7 without (the count wanders a little from run to run — the mean is what is held).
	# self-check: the feet not told where the turn ends — more lifts on the same walks
	var fk: Dictionary = player.view3d.spec.get("feet", {})
	var keep := bool(fk.get("turn_to_end", false))
	fk["turn_to_end"] = false
	var old: Array = await _after_arrive_runs()
	fk["turn_to_end"] = keep
	var old_mean := 0.0
	for r in old:
		old_mean += float(r[0]) / float(old.size())
	print("        the turn's end not known to the feet: %s (mean %.2f)" % [str(old.map(func(r): return [r[0], snappedf(r[1], 0.01)])), old_mean])
	_check(keep and old_mean > mean + 0.1, "self-check: without the turn's end the feet lift no more (%.2f against %.2f)" % [old_mean, mean])
	_completed = true
