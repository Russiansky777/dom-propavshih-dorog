extends SceneTree
## The whole-project review of 12.11 (Director 17:16: «Полное ревью ещё одно полностью игры сделай + определи чёткие
## шаги дальнейшие»; Docs/REVIEW_FULL_2026-11-12.md):
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_review_1211.gd
##   R12-1 (the first full CI run since 11.11, 43267144034: «agata gesture: LeftFoot jolted 14.2 mm per 1/60 s», «the
##       right hand jerks: 9.0 mm/frame²»): a gesture borrowed from another figure («рука к груди», «спокойный» — Agata's
##       and Nina's) takes everything below the waist from the figure's own stance clip, copied over the gesture's
##       length. The stance clip is not a loop of its own (in the stance its variants cross-fade), and copied from its
##       start again its end jumped to its start inside the gesture: as drawn, Agata's hips, head and hands went 5 cm
##       in three frames (17 mm a frame) once per stance length. Now the copy goes there and back. For every figure
##       whose data borrows clips, every borrowed clip: the hips' travel and the legs' turns it took from the stance
##       change per 1/60 s no more than in the stance clip itself. Self-check — the copy from the start again
##       (Actor3D.fill_pingpong off) is caught on Agata.

const DT := 1.0 / 60.0

var _results: Array = []
var _cur_ok := true
var _cur_msgs: Array = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_cur_ok = false
		_cur_msgs.append(msg)


func _report(name: String, t0: int) -> void:
	print(("PASS  " if _cur_ok else "FAIL  ") + name + "  (%d ms)" % (Time.get_ticks_msec() - t0))
	for m in _cur_msgs:
		print("        - " + str(m))
	_results.append([name, _cur_ok])
	_cur_ok = true
	_cur_msgs = []


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	await _test_borrowed_stance()
	_report("R12-1 Borrowed gestures (review 12.11): the stance under «рука к груди» and «спокойный» has no seam — hips and legs move no faster than in the stance clip itself", t0)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== review 12.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


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


## Below the waist — what a borrowed gesture leaves to the figure's own stance (Actor3D._borrow_clips).
func _below_waist(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe") or bone.begins_with("Skirt")


## Largest change per 1/60 s over the first `upto` seconds of a clip: [the hips' travel (clip units), a turn of a bone
## below the waist (°), where the travel's largest was (s)].
func _steps(a: Animation, upto: float) -> Array:
	var travel := 0.0
	var travel_at := 0.0
	var turn := 0.0
	for t in a.get_track_count():
		var ty := a.track_get_type(t)
		var bone := String(a.track_get_path(t).get_concatenated_subnames())
		if ty == Animation.TYPE_POSITION_3D:
			var prev: Vector3 = a.position_track_interpolate(t, 0.0)
			var x := DT
			while x <= upto + 1e-6:
				var p: Vector3 = a.position_track_interpolate(t, x)
				if (p - prev).length() > travel:
					travel = (p - prev).length()
					travel_at = x
				prev = p
				x += DT
		elif ty == Animation.TYPE_ROTATION_3D and _below_waist(bone):
			var prev_q: Quaternion = a.rotation_track_interpolate(t, 0.0)
			var x2 := DT
			while x2 <= upto + 1e-6:
				var q: Quaternion = a.rotation_track_interpolate(t, x2)
				turn = maxf(turn, rad_to_deg(prev_q.angle_to(q)))
				prev_q = q
				x2 += DT
	return [travel, turn, travel_at]


func _clip(anim: AnimationPlayer, bare: String) -> Animation:
	for n in anim.get_animation_list():
		if String(n).get_slice("/", String(n).get_slice_count("/") - 1) == bare:
			return anim.get_animation(n)
	return null


## Per borrowed clip of the figure `id`: [role, the clip's steps, the stance clip's own steps, m per clip unit].
func _measure(id: String) -> Array:
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var rt: Dictionary = spec.get("rt3d", {})
	var n := _fake_npc()
	var live = NL.new()
	n.add_child(live)
	var out: Array = []
	if not live.setup(n, spec, 0.55):
		_check(false, "%s: live model not loaded" % id)
		n.queue_free()
		await process_frame
		return out
	var anim: AnimationPlayer = live.view.anim
	var own := _clip(anim, String(rt.get("clips", {}).get("idle", "")))
	_check(own != null, "%s: no stance clip «%s»" % [id, String(rt.get("clips", {}).get("idle", ""))])
	var unit: float = live.view._skel_to_turn().basis.get_scale().y
	for e in rt.get("borrow_clips", []):
		var role := String(e.get("as", e.get("clip", "")))
		var a: Animation = anim.get_animation("borrow/" + role) if anim.has_animation("borrow/" + role) else null
		_check(a != null, "%s: the borrowed clip «%s» is not in the figure's player" % [id, role])
		if a != null and own != null:
			out.append([role, _steps(a, a.length), _steps(own, own.length), unit, a.length, own.length])
	n.queue_free()
	await process_frame
	return out


func _test_borrowed_stance() -> void:
	var ids: Array = []
	var dir := DirAccess.open("res://data/actors")
	for f in dir.get_files():
		if not String(f).ends_with(".json"):
			continue
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/" + f))
		if spec is Dictionary and not ((spec.get("rt3d", {}) as Dictionary).get("borrow_clips", []) as Array).is_empty():
			ids.append(String(f).get_basename())
	ids.sort()
	_check(ids.has("agata") and ids.has("nina"), "figures with borrowed clips: %s — Agata and Nina are expected among them" % str(ids))
	for id in ids:
		var rows: Array = await _measure(id)
		_check(not rows.is_empty(), "%s: no borrowed clip measured" % id)
		for r in rows:
			var b: Array = r[1]
			var o: Array = r[2]
			var mm := float(r[3]) * 1000.0
			print("        %s «%s» (%.1f s over a stance of %.1f s): hips %.1f mm a frame at most (the stance itself %.1f), legs %.1f° (the stance %.1f°)" % [id, r[0], float(r[4]), float(r[5]), float(b[0]) * mm, float(o[0]) * mm, float(b[1]), float(o[1])])
			_check(float(b[0]) <= float(o[0]) * 1.3 + 0.0002 / maxf(float(r[3]), 1e-6), "%s «%s»: the hips go %.1f mm in one frame at %.2f s (the stance clip itself — %.1f at most): a seam of the stance inside the gesture" % [id, r[0], float(b[0]) * mm, float(b[2]), float(o[0]) * mm])
			_check(float(b[1]) <= float(o[1]) * 1.3 + 0.2, "%s «%s»: a leg bone turns %.1f° in one frame (the stance clip itself — %.1f° at most)" % [id, r[0], float(b[1]), float(o[1])])
	# self-check: the copy from the start again, as before 12.11 — the seam is found on Agata (Nina's stance clip stands
	# almost still, its end meets its start: printed for the record, not asked for)
	Actor3D.fill_pingpong = false
	Actor3D._borrowed.clear()
	var before := {}
	for id in ids:
		before[id] = await _measure(id)
	Actor3D.fill_pingpong = true
	Actor3D._borrowed.clear()
	var seen := false
	var txt := ""
	for id in ids:
		for r in before[id]:
			var b: Array = r[1]
			var o: Array = r[2]
			txt += " %s «%s» %.1f mm (the stance %.1f);" % [id, r[0], float(b[0]) * float(r[3]) * 1000.0, float(o[0]) * float(r[3]) * 1000.0]
			if id == "agata" and float(b[0]) > float(o[0]) * 3.0 + 0.002 / maxf(float(r[3]), 1e-6):
				seen = true
	print("        as before (the stance from its start again), the hips a frame at most —" + txt)
	_check(seen, "self-check: with the stance copied from its start again no seam is found on Agata —%s — the case is not reproduced" % txt)
