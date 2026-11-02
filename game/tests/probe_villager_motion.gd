extends SceneTree
## The villagers standing, talking and listening as NpcLive3D poses them in play (feet locks, calming, every modifier),
## measured frame by frame (Director 01.11, lines 6, 10, 52, 53, 55):
##   - foot pitch: the toe above / below the bind pose's foot line (deg, + = toe up) — «ступня задрана»;
##   - torso: lean of hips→neck forward / sideways (deg), the hips across (cm) and the fastest change of the lean when a
##     state changes (deg/s) — «изгиб разом выпирает», «тело кидает из стороны в сторону», «изгибается как цапля»;
##   - knees: the most bent (deg off straight);
##   - hands in the body: how deep the wrist / the hand's middle goes inside the body's hull at its height (cm, the
##     hull from the mesh's own bind pose, hips/spine/thigh vertices) — «руки проваливаются в тело»;
##   - steps: how many steps the feet take a minute standing (foot locks) — «мельтешит».
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_villager_motion.gd [-- id ... [off=key,key]]
## off=… drops data blocks first (e.g. off=arm_clear,pose_limit) — the «before».

const DT := 1.0 / 60.0

var _last: Dictionary = {}

var _seq := [["idle", 5.0], ["talk", 6.0], ["idle", 3.0], ["listen", 6.0], ["idle", 3.0], ["walk", 2.5], ["stop", 2.0], ["turn", 2.5]]


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


func _run() -> void:
	await process_frame
	var ids: Array = []
	var off: Array = []
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("off="):
			off = String(a).substr(4).split(",")
		else:
			ids.append(a)
	if ids.is_empty():
		ids = ["pavel", "pelageya", "nina", "ulyana", "mitya", "ilya", "ilya_wife", "tamara"]
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	for id in ids:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		for k in off:
			if k == "fb0111":   # the data as before the Director's notes 01.11 (lines 6, 10, 52, 53, 55)
				for kk in ["act_body", "arm_body", "pose_limit"]:
					(spec["rt3d"] as Dictionary).erase(kk)
				(spec["rt3d"]["feet"] as Dictionary).erase("boot")
				spec["rt3d"]["state_fade_s"] = 0.4
			(spec["rt3d"] as Dictionary).erase(k)
		for kv in OS.get_environment("PROBE_SET").split(",", false):   # rt3d overrides: key=value, feet.key=value
			var key := kv.get_slice("=", 0)
			var d: Dictionary = spec["rt3d"]
			if key.contains("."):
				d = d[key.get_slice(".", 0)]
				key = key.get_slice(".", 1)
			d[key] = float(kv.get_slice("=", 1))
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55):
			print("%s: not loaded" % id)
			n.queue_free()
			continue
		live.face(Vector2(0, 1), 0.55, true)
		var hull := BodyHull.new(live.view)
		var view: Actor3D = live.view
		view.skeleton.skeleton_updated.connect(func(): _last = Measure.of(view, hull))   # as drawn: after every modifier
		print("%s (off: %s) boot drop %.1f cm, ankles at rest %s" % [id, ",".join(off), view._boot_drop * 100.0, str(view._foot_rest_h)])
		for seg in _seq:
			if seg[0] == "turn":
				live.face(Vector2(-60, -100), 0.55)
			elif seg[0] == "walk":
				live.face(Vector2(1, 0), 0.55)
				live.walk(true, 80.0, 1.0)
			elif seg[0] == "stop":
				live.walk(false)
			else:
				live.set_state(seg[0])
			var st := {"pitch": [INF, -INF, INF, -INF], "lean_f": [INF, -INF], "lean_s": [INF, -INF], "hips_x": [INF, -INF],
				"lean_v": 0.0, "knee": 0.0, "flex": 0.0, "legs": [INF, -INF], "hh": [INF, -INF], "hand": [-INF, -INF], "steps": 0, "hip_v": 0.0}
			var t := 0.0
			var prev_lean := Vector2.INF
			var prev_hx := INF
			var stepping := [false, false]
			while t < float(seg[1]):
				if seg[0] == "walk":
					n.global_position += Vector2(80.0 * DT, 0.0)   # the staging carries her, as NpcActor.go_off
				live.process(DT)
				await process_frame
				t += DT
				var v: Actor3D = live.view
				if _last.is_empty():
					continue
				var m := _last
				for i in 2:
					st["pitch"][i * 2] = minf(st["pitch"][i * 2], m["pitch"][i])
					st["pitch"][i * 2 + 1] = maxf(st["pitch"][i * 2 + 1], m["pitch"][i])
					st["hand"][i] = maxf(st["hand"][i], m["hand"][i])
					var s_now: bool = v._foot_step[i] != null
					if s_now and not stepping[i]:
						st["steps"] += 1
					stepping[i] = s_now
				var lean: Vector2 = m["lean"]
				st["lean_f"] = [minf(st["lean_f"][0], lean.x), maxf(st["lean_f"][1], lean.x)]
				st["lean_s"] = [minf(st["lean_s"][0], lean.y), maxf(st["lean_s"][1], lean.y)]
				st["hips_x"] = [minf(st["hips_x"][0], m["hips_x"]), maxf(st["hips_x"][1], m["hips_x"])]
				if prev_lean != Vector2.INF:
					st["lean_v"] = maxf(st["lean_v"], (lean - prev_lean).length() / DT)
					st["hip_v"] = maxf(st["hip_v"], absf(m["hips_x"] - prev_hx) / DT)
				prev_lean = lean
				prev_hx = m["hips_x"]
				st["knee"] = maxf(st["knee"], m["knee"])
				st["flex"] = maxf(st["flex"], m["hipflex"])
				st["legs"] = [minf(st["legs"][0], m["legs"].x), maxf(st["legs"][1], m["legs"].x)]
				st["hh"] = [minf(st["hh"][0], m["hips_h"]), maxf(st["hh"][1], m["hips_h"])]
				if OS.get_environment("PROBE_TRACE") != "" and int(round(t / DT)) % int(OS.get_environment("PROBE_TRACE")) == 0:
					print("    %s %5.2f toe %+5.1f %+5.1f lean %+5.1f %+5.1f hips %+5.1f knee %3.0f hand %+5.1f %+5.1f step %s%s act %.2f %s" % [seg[0], t, m["pitch"][0], m["pitch"][1], lean.x, lean.y, m["hips_x"] * 100.0, m["knee"], m["hand"][0] * 100.0, m["hand"][1] * 100.0, "L" if stepping[0] else "-", "R" if stepping[1] else "-", v.shown_act_w(), str(v._foot_w)])
			print("  %-6s toe L %+.0f..%+.0f R %+.0f..%+.0f° | lean fwd %+.1f..%+.1f side %+.1f..%+.1f° (max %.0f°/s) | hips x %.1f cm (max %.0f cm/s) | knee %.0f° hip bend %.0f° legs fwd %+.1f..%+.1f° hips over ankles %.0f..%.0f cm | hand in body L %.1f R %.1f cm | steps %d" % [
				seg[0], st["pitch"][0], st["pitch"][1], st["pitch"][2], st["pitch"][3], st["lean_f"][0], st["lean_f"][1],
				st["lean_s"][0], st["lean_s"][1], st["lean_v"], (st["hips_x"][1] - st["hips_x"][0]) * 100.0, st["hip_v"] * 100.0,
				st["knee"], st["flex"], st["legs"][0], st["legs"][1], st["hh"][0] * 100.0, st["hh"][1] * 100.0, st["hand"][0] * 100.0, st["hand"][1] * 100.0, st["steps"]])
		n.queue_free()
		await process_frame
	quit(0)


## The body's hull at each height (bind pose, model frame relative to the hips at rest): per 1 cm of height, the
## farthest vertex in each 6° sector around the slab's middle. Vertices of the body only (dominant bone: hips, spine,
## thighs) — the arms, the head and the shins are not the body a hand sinks into.
class BodyHull:
	var bins := {}          # int(height cm) -> [centre Vector2, PackedFloat32Array(60) radii]
	var rest_hips := Transform3D.IDENTITY
	var hips := -1

	func _init(v: Actor3D) -> void:
		var sk := v.skeleton
		hips = sk.find_bone("Hips")
		var to_m := v._skel_to_turn()
		rest_hips = to_m * sk.get_bone_global_rest(hips)
		var body_bones := {}
		for nm in ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "RightUpLeg"]:
			body_bones[sk.find_bone(nm)] = true
		var pts: Array = []
		for mi in v.meshes:
			var skin: Skin = mi.skin
			if skin == null:
				continue
			var binds := []
			for j in skin.get_bind_count():
				var b := skin.get_bind_bone(j)
				if b < 0:
					b = sk.find_bone(skin.get_bind_name(j))
				binds.append([b, sk.get_bone_global_rest(b) * skin.get_bind_pose(j)])
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bi = arr[Mesh.ARRAY_BONES]
				var bw = arr[Mesh.ARRAY_WEIGHTS]
				if bi == null or bw == null:
					continue
				var per: int = bi.size() / vs.size()
				for k in vs.size():
					var best := -1
					var bwv := 0.0
					var p := Vector3.ZERO
					for c in per:
						var w: float = bw[k * per + c]
						if w <= 0.0:
							continue
						var e: Array = binds[int(bi[k * per + c])]
						p += (e[1] as Transform3D) * vs[k] * w
						if w > bwv:
							bwv = w
							best = int(e[0])
					if body_bones.has(best):
						pts.append(to_m * p)
		var acc := {}
		for p in pts:
			var key := int(floor(p.y * 100.0))
			if not acc.has(key):
				acc[key] = []
			acc[key].append(Vector2(p.x, p.z))
		for key in acc.keys():
			var c := Vector2.ZERO
			for q in acc[key]:
				c += q
			c /= float(acc[key].size())
			var r := PackedFloat32Array()
			r.resize(60)
			for q in acc[key]:
				var d: Vector2 = q - c
				var s := int(fposmod(atan2(d.y, d.x), TAU) / TAU * 60.0) % 60
				r[s] = maxf(r[s], d.length())
			bins[key] = [c, r]

	## How deep a point (model frame, metres) is inside the hull: > 0 inside, < 0 outside (m); -1 off the body's heights.
	func depth(p_rest: Vector3) -> float:
		var key := int(floor(p_rest.y * 100.0))
		var best := -1.0
		for kk in [key - 1, key, key + 1]:
			if not bins.has(kk):
				continue
			var c: Vector2 = bins[kk][0]
			var r: PackedFloat32Array = bins[kk][1]
			var d := Vector2(p_rest.x, p_rest.z) - c
			var s := int(fposmod(atan2(d.y, d.x), TAU) / TAU * 60.0) % 60
			var rr := maxf(maxf(r[s], r[(s + 1) % 60]), r[(s + 59) % 60])
			if rr <= 0.0:
				continue
			best = maxf(best, rr - d.length())
		return best


class Measure:
	static func of(v: Actor3D, hull: BodyHull) -> Dictionary:
		var out := {}
		var sk := v.skeleton
		var xf := v._skel_to_turn()
		var pos := func(nm: String) -> Vector3:
			return xf * sk.get_bone_global_pose(sk.find_bone(nm)).origin
		var rest := func(nm: String) -> Vector3:
			return xf * sk.get_bone_global_rest(sk.find_bone(nm)).origin
		var pitch: Array = []
		for side in ["Left", "Right"]:
			var d: Vector3 = pos.call(side + "ToeBase") - pos.call(side + "Foot")
			var d0: Vector3 = rest.call(side + "ToeBase") - rest.call(side + "Foot")
			var p := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
			var p0 := rad_to_deg(atan2(d0.y, Vector2(d0.x, d0.z).length()))
			pitch.append(p - p0)
		out["pitch"] = pitch
		var h: Vector3 = pos.call("Hips")
		var nk: Vector3 = pos.call("neck")
		var d := nk - h
		out["lean"] = Vector2(rad_to_deg(atan2(d.z, d.y)), rad_to_deg(atan2(d.x, d.y)))
		var fm: Vector3 = (pos.call("LeftFoot") + pos.call("RightFoot")) * 0.5
		out["hips_x"] = h.x - fm.x
		# the legs' slope: the hips over the ankles' middle, forward (+) / back, deg off vertical (heron: feet left behind)
		out["legs"] = Vector2(rad_to_deg(atan2(h.z - fm.z, h.y - fm.y)), rad_to_deg(atan2(h.x - fm.x, h.y - fm.y)))
		var knee := 0.0
		for side in ["Left", "Right"]:
			var a: Vector3 = pos.call(side + "UpLeg") - pos.call(side + "Leg")
			var b: Vector3 = pos.call(side + "Foot") - pos.call(side + "Leg")
			knee = maxf(knee, 180.0 - rad_to_deg(a.angle_to(b)))
		out["knee"] = knee
		# the bend at the hips (torso against the thighs, deg off straight) and the hips' height over the ankles
		var kn: Vector3 = (pos.call("LeftLeg") + pos.call("RightLeg")) * 0.5
		out["hipflex"] = 180.0 - rad_to_deg((nk - h).angle_to(kn - h))
		out["hips_h"] = h.y - minf(pos.call("LeftFoot").y, pos.call("RightFoot").y)
		# hands: the wrist and the middle of the hand (8 cm on along the forearm), in the hips' rest frame
		var hb := hull.hips
		var hips_now: Transform3D = xf * sk.get_bone_global_pose(hb)
		var to_rest := hull.rest_hips * hips_now.affine_inverse()
		var hand: Array = []
		for side in ["Left", "Right"]:
			var w: Vector3 = pos.call(side + "Hand")
			var f: Vector3 = pos.call(side + "ForeArm")
			var mid := w + (w - f).normalized() * 0.08
			var dd := maxf(hull.depth(to_rest * w), hull.depth(to_rest * mid))
			hand.append(dd)
		out["hand"] = hand
		return out
