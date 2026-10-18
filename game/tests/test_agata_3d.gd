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
	await _test("Model: same Meshy mesh/texture/skeleton (≤ 80k triangles), all clips; switch sprites ↔ 3D in place; sprites mode untouched", _test_model)
	await _test("Turning: any angle (not 8 rows), no jump between frames, reaches the target", _test_turning)
	await _test("Feet planted while walking: stance foot ≤ 1 cm per stance in 5 directions; speed from the clip", _test_feet_planted)
	await _test("Idle alive without jerks: 20 s with variant crossfades — no bone jumps, hips do not turn, head moves, feet stay", _test_idle)
	await _test("Start/stop: speed ramps up and down, pose continuous, arrives at the target", _test_start_stop)
	await _test("Actions open/pick/reach in 3D: once, on the key fraction; fade into idle; room change cancels", _test_actions)
	await _test("Drawing: live figure under the y-sorted node (same z, occluders as before), facade invisible, shadow kept, footsteps on contacts", _test_drawing)
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
	await _frames(6)


# --- Model ---------------------------------------------------------------------------------------

func _test_model() -> void:
	await _enter("H1", Vector2(1200, 960))
	_check(player.is_3d(), "player is not in 3D mode (render forced 3d): %s" % (player.view3d.load_error if player.view3d else "no view"))
	if not player.is_3d():
		return
	var v: Actor3D = player.view3d
	var tris := v.triangle_count()
	_check(tris > 20000 and tris <= 80000, "triangles %d: expected the decimated Meshy mesh (20k..80k)" % tris)
	_check(v.skeleton.get_bone_count() == 24, "skeleton has %d bones, Meshy rig has 24" % v.skeleton.get_bone_count())
	for role in ["walk", "idle", "open", "pick", "reach"]:
		_check(v.clips.has(role), "clip for '%s' missing (rt3d.clips)" % role)
	_check(v.idle_pool.size() >= 3, "idle pool has %d variants (≥ 3 expected)" % v.idle_pool.size())
	var tex = v.material.get_shader_parameter("albedo_tex")
	_check(tex is Texture2D and (tex as Texture2D).get_width() == 2048, "albedo is not the model's 2K texture: %s" % str(tex))
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

## Walks between two points and measures, in floor metres, the drift of the stance foot during each
## stance (foot below the other, weight ≈ 1): player floor position + yaw-rotated foot position.
func _walk_and_measure(room: String, a: Vector2, b: Vector2) -> Dictionary:
	await _enter(room, a)
	var v: Actor3D = player.view3d
	player.walk_to(b)
	var k: float = player.floor_foreshortening()
	var floor_pos := Vector2.ZERO   # integrated floor position (m)
	var last: Vector2 = player.global_position
	var stance_side := -1
	var stance_start := Vector3.ZERO
	var worst := 0.0
	var worst_fwd := 0.0
	var worst_lat := 0.0
	var yaw_change := 0.0
	var stance_yaw := 0.0
	var stance_scr := Vector2.ZERO
	var worst_scr := 0.0
	var stances := 0
	var t := 0.0
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
		if player.walk_w < 0.97:
			stance_side = -1
			continue
		var f: Array = v.feet_model()
		var side := 0 if minf(f[0].y, f[1].y) <= minf(f[2].y, f[3].y) else 1
		var foot: Vector3 = Basis(Vector3.UP, player.yaw3d) * f[side * 2]
		var world := Vector3(floor_pos.x + foot.x, foot.y, floor_pos.y + foot.z)
		# as drawn: the planted foot's screen position (player on screen + camera projection of the foot)
		var scr: Vector2 = player.global_position + v.screen_of(Vector3(foot.x, 0.0, foot.z)) * s  # its floor contact point
		if side != stance_side:
			stance_side = side
			stance_start = world
			stance_scr = scr
			stance_yaw = player.yaw3d
			stances += 1
		else:
			var dv := Vector2(world.x - stance_start.x, world.z - stance_start.z)
			worst = maxf(worst, dv.length())
			var fwd := Vector2(sin(player.yaw3d), cos(player.yaw3d))
			worst_fwd = maxf(worst_fwd, absf(dv.dot(fwd)))
			worst_lat = maxf(worst_lat, absf(dv.cross(fwd)))
			yaw_change = maxf(yaw_change, absf(angle_difference(stance_yaw, player.yaw3d)))
			worst_scr = maxf(worst_scr, scr.distance_to(stance_scr) / maxf(s, 0.01))
		speeds.append(d.length() / maxf(player.get_process_delta_time(), 0.0001) / ppm_s)
	return {"worst_m": worst, "scr_px": worst_scr, "elev": v.elev_deg, "stretch": v.depth_stretch(), "k": k, "fwd_m": worst_fwd, "lat_m": worst_lat, "yaw_deg": rad_to_deg(yaw_change), "stances": stances, "arrived": player.global_position.distance_to(b) < 12.0, "frames": guard}


func _test_feet_planted() -> void:
	var legs := [["right", "Z2", Vector2(500, 900), Vector2(1450, 900)], ["left", "Z2", Vector2(1450, 900), Vector2(500, 900)],
		["towards viewer", "Z2", Vector2(960, 700), Vector2(960, 1030)], ["away", "Z2", Vector2(960, 1030), Vector2(960, 700)],
		["diagonal", "Z2", Vector2(600, 720), Vector2(1300, 1020)]]
	for leg in legs:
		var r: Dictionary = await _walk_and_measure(leg[1], leg[2], leg[3])
		print("        feet %s: stance drift max %.1f mm on the floor (along %.1f, across %.1f; body turned up to %.1f° in a stance), as drawn %.1f px (scale 1; camera %.1f°, depth ×%.2f, floor k %.2f) over %d stances, %d frames" % [leg[0], r["worst_m"] * 1000.0, r["fwd_m"] * 1000.0, r["lat_m"] * 1000.0, r["yaw_deg"], r["scr_px"], r["elev"], r["stretch"], r["k"], r["stances"], r["frames"]])
		if absf(sin(deg_to_rad(float(r["elev"]))) * float(r["stretch"]) - float(r["k"])) < 0.02:
			# camera at the room's own elevation: the drawn foot must stay put on screen too
			_check(float(r["scr_px"]) <= 3.0, "%s: drawn planted foot moved %.1f px on screen (≤ 3 px at scale 1)" % [leg[0], r["scr_px"]])
		_check(r["stances"] >= 2, "%s: only %d stances measured" % [leg[0], r["stances"]])
		_check(r["worst_m"] <= 0.010, "%s: stance foot slid %.1f mm (≤ 10 mm)" % [leg[0], r["worst_m"] * 1000.0])
		_check(r["arrived"], "%s: did not arrive" % leg[0])
	# Self-check of the metric: the same walk with the figure sliding along the path at the clip's mean
	# speed (no root motion — what the sheets did) must be caught.
	player.root_motion_3d = false
	var bad: Dictionary = await _walk_and_measure("Z2", Vector2(500, 900), Vector2(1450, 900))
	player.root_motion_3d = true
	print("        self-check (constant speed, no root motion): stance drift %.1f mm" % (bad["worst_m"] * 1000.0))
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
	var off: Vector2 = b.offset * b.scale
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
