extends SceneTree
## Headless test of room lighting (data/story/lights/<LOC>.json → RoomLighting). Usage:
##   godot --headless --path game -s res://tests/test_lighting.gd
## Behind it — the Director's notes of 17.10 «свет, огонь и тени должны быть живыми»:
##   - every lights file builds: one LightSource per entry, the replaced particle «fire» of the H1
##     stove (rooms/H1.json effects[stove_fire]) is gone, nothing in Lighting can take a click;
##   - H1 shutters: closed → room darkened (ambient + window patch), no beam; opening fades to
##     daylight + beam over ≈0.8 s (not at once, not slower); a loaded save shows the final state
##     at once (no replayed transition);
##   - H1 stove: fire, its lights and the actor shadow only with stove_lit; the stove light flickers
##     (energy varies within ±amount) and the fire quad is unshaded/additive;
##   - actor shadows (`actor_light_shadow`): Agata gets one per shadow-casting source, child of her
##     sprite, behind the figure, showing the SAME frame texture as the sprite (also right after a
##     frame change), leaning AWAY from the source, fainter and longer farther away; they leave the
##     player when the room changes; NPCs (Tamara in Z1) get theirs from Z1's lamp;
##   - actor tone (coordinator 17.10: «Агата светлая, как вклеенная, в тёмной комнате»): the figure is
##     not lit per pixel but toned by the light at her feet × actor_tint — dark in the dark
##     H1, warmer by the fire, eased; a room without lighting gives her colours back. The rendered
##     check (brightness within ±15 % of the floor by her) is tools/measure_tone.py on Xvfb frames.
## Exit code 0 only when every check passed. A `-s` script is compiled before autoloads exist: they
## are reached through the tree, classes are loaded at runtime (see run_tests.gd).

const FADE_TOL := 0.2

var _results: Array = []
var _fails: Array[String] = []
var gs: Node = null
var rm: Node = null
var main_node: Node = null
var player: Node2D = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
	var passed := _fails.is_empty()
	_results.append([test_name, passed])
	print("%s  %s  (%d ms)" % ["PASS" if passed else "FAIL", test_name, Time.get_ticks_msec() - started])
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rm = root.get_node("RoomManager")
	gs.reset()
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")
	await _test("Lights data builds in every room; the H1 particle fire is replaced; no click targets", _test_build)
	await _test("H1 shutters: dark while closed, ≈0.8 s fade to daylight + beam, loaded save shows the final state", _test_shutters)
	await _test("H1 stove: fire, flickering light and shadows only with stove_lit", _test_stove)
	await _test("Actor light shadow: same frame as the sprite, behind it, away from the source, by distance", _test_actor_shadow)
	await _test("Actor light shadow: removed from Agata on room change; NPCs get theirs", _test_shadow_lifecycle)
	await _test("Actor tone: Agata darkened like the floor in the dark H1, warmer by the fire, never bleached or greyed, Tikhon alike", _test_actor_tone)
	gs.reset()
	gs.delete_save("test_lighting")
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
	load("res://scripts/lighting/light_source.gd").release_shared()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== lighting: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


func _enter(room_id: String, flags: Array, pos: Vector2) -> Node:
	gs.reset()
	for f in flags:
		gs.set_flag(String(f), true)
	rm.change_room(room_id, "", pos)
	await process_frame
	await process_frame
	return rm.current_room


func _lighting(room: Node):
	return room.get_node_or_null("Lighting") if room != null else null


## Waits `seconds` of the lighting node's own clock (game time).
func _wait_light(rl, seconds: float) -> void:
	var t0: float = rl.time_s
	var guard := 0
	while rl.time_s - t0 < seconds and guard < 2000:
		await process_frame
		guard += 1


func _test_build() -> void:
	var sd: Node = root.get_node("StoryData")
	var dir := DirAccess.open("res://data/story/lights")
	_check(dir != null, "res://data/story/lights is missing (tools/sync_story_data.sh)")
	if dir == null:
		return
	var files := dir.get_files()
	var built := 0
	for fname in files:
		if not fname.ends_with(".json"):
			continue
		var rid := fname.get_basename()
		_check(sd.has_room(rid), "lights/%s: no room %s" % [fname, rid])
		var room: Node = await _enter(rid, [], Vector2.INF)
		var rl = _lighting(room)
		_check(rl != null, "%s: Lighting node not built" % rid)
		if rl == null:
			continue
		built += 1
		var spec: Dictionary = rl.data
		_check(rl.sources.size() == spec.get("sources", []).size(), "%s: %d sources built, %d in data" % [rid, rl.sources.size(), spec.get("sources", []).size()])
		for eid in spec.get("suppress_effects", []):
			_check(room.get_node_or_null("Effects/" + String(eid)) == null, "%s: effect %s must be replaced by the lighting" % [rid, eid])
		# Nothing in the lighting can be picked: no physics objects, and Room.pick still finds hotspots.
		var stack: Array = [rl]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			_check(not (n is CollisionObject2D) and not (n is Control), "%s: %s in Lighting could take input" % [rid, n.get_path()])
			stack.append_array(n.get_children())
		# Godot's Light2D is not used (one cost 85–93 % fps in the WebGL measurement): the art takes the
		# room's light map instead.
		var lights := room.find_children("*", "Light2D", true, false)
		_check(lights.is_empty(), "%s: no Light2D in the room (found %d)" % [rid, lights.size()])
		if rl.light_map != null:
			var bg: CanvasItem = room.get_node_or_null("Background/Image")
			_check(bg != null and bg.material == rl.receive_material, "%s: the background takes the light map" % rid)
			_check(rl.light_map.size == Vector2i(480, 270), "%s: light map at 1/4 resolution, got %s" % [rid, str(rl.light_map.size)])
	_check(built > 0, "no lights files built")
	# H1: the stove hotspot is still clicked through the fire.
	var h1: Node = await _enter("H1", ["stove_lit"], Vector2(1200, 900))
	for i in 3:
		await physics_frame
	var hit: Node = h1.pick(Vector2(450, 250))
	_check(hit != null and String(hit.name) == "stove", "a click on the burning stove must still hit the stove hotspot, got %s" % (str(hit.name) if hit else "nothing"))


func _test_shutters() -> void:
	var room: Node = await _enter("H1", [], Vector2(1200, 900))
	var rl = _lighting(room)
	if rl == null:
		_check(false, "H1 has no Lighting")
		return
	var dark = rl.source("dark_closed")
	var patch = rl.source("window_patch_dark")
	var beam = rl.source("window_beam")
	_check(dark != null and patch != null and beam != null, "H1 must have dark_closed, window_patch_dark and window_beam")
	if dark == null or patch == null or beam == null:
		return
	_check(dark.presence() == 1.0 and patch.presence() == 1.0, "closed shutters: room darkened on entry (presence %.2f / %.2f)" % [dark.presence(), patch.presence()])
	_check(dark.lm != null and dark.lm_sub and dark.lm.visible and dark.lm_strength > 0.9, "darkness = subtracted from the light map at full strength, got %.2f" % dark.lm_strength)
	_check(beam.presence() == 0.0 and not beam.sprite.visible, "closed shutters: no window beam")
	var c: Color = dark.lm_color
	_check(c.r > 0.3 and c.g > 0.3 and c.b > 0.3, "closed shutters: the room is NOTICEABLY darker (subtract ≥ 0.3 per channel), got %s" % str(c))
	gs.set_flag("h1_shutter_open", true)
	await _wait_light(rl, 0.4)
	var mid: float = dark.level
	_check(mid > 0.5 - FADE_TOL - 0.1 and mid < 0.5 + FADE_TOL + 0.1, "0.4 s after opening the fade is half-way (level %.2f, expected ≈0.5)" % mid)
	_check(beam.level > 0.2 and beam.level < 0.8, "the beam fades in together (level %.2f)" % beam.level)
	await _wait_light(rl, 0.6)
	_check(dark.level == 0.0 and not dark.lm.visible, "1.0 s after opening: no darkness left (level %.2f)" % dark.level)
	_check(beam.level == 1.0 and beam.sprite.visible, "1.0 s after opening: the beam is on (level %.2f)" % beam.level)
	# Save in the open state; reload from a closed room: final state at once, no replayed fade.
	rm.save_game("test_lighting")
	room = await _enter("H1", [], Vector2(1200, 900))
	rl = _lighting(room)
	_check(rl.source("dark_closed").presence() == 1.0, "control: closed state before loading")
	rm.load_game("test_lighting")
	await process_frame
	rl = _lighting(rm.current_room)
	_check(rl.source("dark_closed").level == 0.0 and rl.source("window_beam").level == 1.0, "loaded save with open shutters: daylight immediately (dark %.2f, beam %.2f)" % [rl.source("dark_closed").level, rl.source("window_beam").level])
	# GameState.load on a live room (quick load) snaps too.
	gs.set_flag("h1_shutter_open", false)
	await process_frame
	_check(rl.source("dark_closed").level < 0.2, "a flag change fades (not a jump): level %.2f right after closing" % rl.source("dark_closed").level)
	gs.load("test_lighting")
	_check(rl.source("dark_closed").level == 0.0, "state_loaded snaps the live room to the save (level %.2f)" % rl.source("dark_closed").level)


func _test_stove() -> void:
	var room: Node = await _enter("H1", [], Vector2(1200, 900))
	var rl = _lighting(room)
	var fire = rl.source("stove_fire")
	var light = rl.source("stove_light")
	_check(fire != null and light != null, "H1 must have stove_fire and stove_light")
	if fire == null or light == null:
		return
	_check(not fire.sprite.visible and not light.lm.visible, "cold stove: no fire, no light")
	_check(rl.shadows_of(player).size() >= 1, "Agata carries the stove shadow node even while the stove is cold")
	for sh in rl.shadows_of(player):
		await process_frame
		_check(not sh.visible, "cold stove: no cast shadow")
	gs.set_flag("stove_lit", true)
	await _wait_light(rl, fire.fade_s + 0.15)
	_check(fire.sprite.visible and fire.presence() == 1.0, "lit stove: the fire burns")
	var mat: ShaderMaterial = fire.sprite.material
	_check(mat != null and mat.shader != null and mat.shader.code.contains("blend_add") and mat.shader.code.contains("unshaded"), "fire shader: additive and unshaded (the room's darkness does not dim it)")
	_check(light.lm != null and not light.lm_sub and light.lm.get_parent() != null and light.lm.get_parent().get_parent() == rl.light_map, "stove light: additive point in the room's light map")
	var lo := 99.0
	var hi := -1.0
	for i in 60:
		await process_frame
		lo = minf(lo, light.lm_strength)
		hi = maxf(hi, light.lm_strength)
	var amount: float = light.flicker_amount
	_check(hi - lo > 0.01, "the stove light flickers (energy %.3f..%.3f)" % [lo, hi])
	_check(lo >= light.energy * (1.0 - amount) - 0.001 and hi <= light.energy * (1.0 + amount) + 0.001, "flicker stays within ±%.2f of energy %.2f (%.3f..%.3f)" % [amount, light.energy, lo, hi])
	_check(fire.flicker == light.flicker, "fire and its light share one flicker group (they breathe together)")
	# energy_if: the dark room (closed shutters) gets the stronger stove light.
	_check(is_equal_approx(light.energy_target, 0.75), "closed shutters: stove light energy 0.75 (energy_if), got %.2f" % light.energy_target)


func _test_actor_shadow() -> void:
	var room: Node = await _enter("H1", ["stove_lit"], Vector2(1000, 800))
	var rl = _lighting(room)
	var sprite: AnimatedSprite2D = player.get("sprite")
	var shadows: Array = rl.shadows_of(player)
	_check(shadows.size() == rl.shadow_sources().size() and shadows.size() >= 1, "Agata: one light shadow per shadow-casting source (%d for %d)" % [shadows.size(), rl.shadow_sources().size()])
	if shadows.is_empty() or sprite == null:
		return
	var sh: Sprite2D = shadows[0]
	await _wait_light(rl, 0.7)
	_check(sh.get_parent() == sprite, "the light shadow is a child of the actor's sprite (follows foot lock and depth)")
	_check(sh.show_behind_parent, "the light shadow draws behind the figure")
	_check(sprite.get_node_or_null("Shadow") != null, "the contact ellipse stays")
	_check(sh.visible and float(sh.current()["alpha"]) > 0.05, "lit stove: the shadow is visible (alpha %.3f)" % float(sh.current()["alpha"]))
	var cur_tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_check(sh.texture == cur_tex, "the shadow shows the sprite's current frame")
	# Walk: on every frame change the shadow switches in the same frame (no blink).
	player.call("walk_to", Vector2(1500, 950))
	var mismatches := 0
	var changes := 0
	var last := sprite.frame
	for i in 90:
		await process_frame
		if sprite.frame != last:
			changes += 1
			last = sprite.frame
		if sh.texture != sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame):
			mismatches += 1
	_check(changes > 3, "control: the walk changed frames (%d)" % changes)
	_check(mismatches == 0, "the shadow lagged behind the sprite frame %d times during a walk" % mismatches)
	player.call("enter_room", room, Vector2(1000, 800))
	# Away from the source: the head end of the silhouette (local (0, −figure)) lands on the far side.
	var src = sh.source
	var floor_pt: Vector2 = src.shadow_floor()
	await _wait_light(rl, 0.5)
	var head_local := Vector2(0, sprite.offset.y)
	var head: Vector2 = sh.get_global_transform() * head_local
	var feet: Vector2 = sprite.global_position
	_check((head - feet).dot(feet - floor_pt) > 0.0, "the shadow leans AWAY from the stove (head %s, feet %s, source floor %s)" % [str(head.round()), str(feet.round()), str(floor_pt)])
	_check(head.y > feet.y - 2.0, "the shadow lies on the floor (head end not above the feet): %s vs %s" % [str(head.round()), str(feet.round())])
	var near_p: Array = sh.target_params(Vector2(600, 820))
	var far_p: Array = sh.target_params(Vector2(1700, 1000))
	_check(float(far_p[2]) < float(near_p[2]), "farther from the fire = fainter shadow (near %.3f, far %.3f)" % [float(near_p[2]), float(far_p[2])])
	_check(float(far_p[1]) > float(near_p[1]), "farther from the fire = longer shadow (near %.2f, far %.2f)" % [float(near_p[1]), float(far_p[1])])
	_check(float(sh.target_params(floor_pt)[2]) < 0.05, "(almost) no shadow right at the source: %.3f" % float(sh.target_params(floor_pt)[2]))
	var tr: Transform2D = sh.shadow_transform(float(near_p[0]), float(near_p[1]))
	_check(absf(tr.determinant()) > 0.05, "the silhouette never collapses to a line (det %.3f)" % tr.determinant())
	# Smooth: a jump of the target does not jump the shadow in one frame.
	var before: Dictionary = sh.current()
	player.call("enter_room", room, Vector2(1800, 1000))
	await process_frame
	var after: Dictionary = sh.current()
	_check(absf(float(after["alpha"]) - float(before["alpha"])) < 0.6 * absf(float(sh.target_params(sprite.global_position)[2]) - float(before["alpha"])) + 0.02, "the shadow eases to new values (no one-frame jump)")


func _test_shadow_lifecycle() -> void:
	var room: Node = await _enter("H1", ["stove_lit"], Vector2(1000, 800))
	var sprite: AnimatedSprite2D = player.get("sprite")
	var count_h1 := 0
	for c in sprite.get_children():
		if String(c.name).begins_with("LightShadow_"):
			count_h1 += 1
	_check(count_h1 >= 1, "H1: Agata has a light shadow")
	await _enter("H2", [], Vector2(500, 900))
	var names: Array = []
	for c in sprite.get_children():
		if String(c.name).begins_with("LightShadow_"):
			names.append(String(c.name))
	var rl2 = _lighting(rm.current_room)
	var expected: int = rl2.shadow_sources().size() if rl2 != null else 0
	_check(names.size() == expected, "after H1 → H2 Agata carries only H2's light shadows (%d expected, got %s)" % [expected, str(names)])
	_check(not names.has("LightShadow_stove_floor"), "the H1 stove shadow left Agata with the room")
	# A room without lights gives Agata her own colours and lighting back.
	await _enter("H3", [], Vector2.INF)
	await process_frame
	_check(sprite.self_modulate == Color.WHITE, "a room without lighting: Agata untoned (modulate %s)" % str(sprite.self_modulate))
	if FileAccess.file_exists("res://data/story/lights/Z1.json"):
		var z1: Node = await _enter("Z1", [], Vector2(300, 900))
		await process_frame
		var npcs: Array = load("res://scripts/actors/npc_actor.gd").all_in(z1)
		var rl = _lighting(z1)
		_check(npcs.size() >= 1, "Z1: Tamara is there")
		if npcs.size() >= 1 and rl != null:
			_check(rl.shadows_of(npcs[0]).size() == rl.shadow_sources().size(), "Z1: Tamara gets a light shadow from every casting source")
			_check(rl.shadows_of(player).size() == rl.shadow_sources().size(), "Z1: Agata too")


static func _lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


func _test_actor_tone() -> void:
	var room: Node = await _enter("H1", [], Vector2(1250, 900))
	var rl = _lighting(room)
	var sprite: AnimatedSprite2D = player.get("sprite")
	await _wait_light(rl, 0.3)
	var dark: Color = sprite.self_modulate
	var expect: Color = rl.actor_tone_at(sprite.global_position, 500.0)
	_check(_lum(dark) < 0.4, "closed shutters: Agata darkened with the room (tone %s)" % str(dark))
	_check(absf(_lum(dark) - _lum(expect)) < 0.03, "tone follows the light at her feet (%s vs %s)" % [str(dark), str(expect)])
	gs.set_flag("h1_shutter_open", true)
	await process_frame
	var step1: Color = sprite.self_modulate
	_check(_lum(step1) - _lum(dark) < 0.25, "opening: no jump of Agata's tone in one frame (%.3f → %.3f)" % [_lum(dark), _lum(step1)])
	await _wait_light(rl, 1.2)
	var day: Color = sprite.self_modulate
	_check(_lum(day) > 0.85, "daylight: Agata back to (about) her own colours (tone %s)" % str(day))
	# Warmth by the fire (closed shutters): redder than far from it.
	room = await _enter("H1", ["stove_lit"], Vector2(640, 800))
	rl = _lighting(room)
	await _wait_light(rl, 0.8)
	var near: Color = rl.actor_tone_at(Vector2(640, 800), 500.0)
	var far: Color = rl.actor_tone_at(Vector2(1700, 950), 500.0)
	_check((near.r - near.b) > (far.r - far.b) + 0.1, "by the fire Agata is warmer (R−B %.2f) than across the room (%.2f)" % [near.r - near.b, far.r - far.b])
	_check(_lum(near) > _lum(far), "by the fire Agata is brighter than across the dark room")
	# Coordinator 18.10: «Агата выбелена, серо-голубая» — the room's tone must not bleach or grey
	# the figures: never a cold cast beyond actor_max_cool, never brighter than actor_max_gain,
	# in every state of H1 and anywhere on its floor (the rendered check — coat saturation ≥ 80 % of
	# neutral light, brightness ±15 % of the floor — is tools/measure_tone.py on Xvfb frames).
	for flags in [[], ["stove_lit"], ["h1_shutter_open"], ["stove_lit", "h1_shutter_open"]]:
		room = await _enter("H1", flags, Vector2(1200, 900))
		rl = _lighting(room)
		var cap: float = float(rl.data.get("actor_max_gain", 1.05))
		var cool: float = float(rl.data.get("actor_max_cool", 0.04))
		var worst := ""
		for x in range(100, 1900, 200):
			for y in [720, 800, 900, 1040]:
				var t: Color = rl.actor_tone_at(Vector2(x, y), 500.0)
				if t.g > t.r * (1.0 + cool) + 0.0001 or t.b > t.r * (1.0 + cool) + 0.0001:
					worst = "cold tone %s at %s" % [str(t), str(Vector2(x, y))]
				if _lum(t) > cap + 0.0001:
					worst = "tone %s brighter than %.2f at %s" % [str(t), cap, str(Vector2(x, y))]
		_check(worst == "", "H1 %s: %s" % [str(flags), worst])
	# Daylight H1: warm (red over blue) — the brown coat stays brown.
	var day_t: Color = rl.actor_tone_at(Vector2(1100, 860), 500.0)
	_check(day_t.r > day_t.b + 0.1, "daylight H1 tone is warm (r %.2f, b %.2f)" % [day_t.r, day_t.b])
	# The puppet (Tikhon) follows the same tone (PuppetActor reads actor_tone_at).
	room = await _enter("H1", ["started_M03", "stove_lit", "h1_shutter_open"], Vector2(1200, 900))
	rl = _lighting(room)
	await _wait_light(rl, 0.8)
	var puppet: Node = null
	for c in room.get_children():
		if c.get_class() != "" and c.get_script() != null and String(c.get_script().resource_path).ends_with("puppet_actor.gd"):
			puppet = c
	if puppet != null and puppet.get("poly") != null:
		var want: Color = rl.actor_tone_at(puppet.global_position, float(puppet.call("figure_height_px")))
		var got: Color = puppet.get("poly").self_modulate
		_check(absf(got.r - want.r) < 0.03 and absf(got.g - want.g) < 0.03 and absf(got.b - want.b) < 0.03, "Tikhon is toned like Agata (%s vs %s)" % [str(got), str(want)])
		_check(got.g <= got.r * 1.05 and got.b <= got.r * 1.05, "Tikhon: no cold cast (%s)" % str(got))
