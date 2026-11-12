extends SceneTree
## The baker of «arms along the body» (scripts/actors/arm_rest.gd; Director 09.11, 22:18): for each villager and each of
## its stance / talk / listen clips, how far each hanging upper arm can be turned in towards the body with the whole
## hand still clear of the clothes: the model's own body and clothes, skinned in the clip's pose, as points (BodyClear's
## hull is the farthest fold per sector — with it the hands stopped 8–12 cm off the skirt); the hand's surface keeps
## `gap_m` from them, the forearm may press `sink_m` into a jacket's side, the arm never closer to straight down than
## `min_deg`. Sampled every `step_s`, held at the least within ±`hold_s` (the turn is never more
## than the clothes allow a moment before or after), smoothed; written to res://data/actors_rest/<id>.json.
##   godot --headless --path game -s res://tests/bake_arm_rest.gd -- <id,id,…|all> [check]
## `check` — nothing is written: the fresh result is compared with the file (test_arm_rest uses it), exit 1 on a
## difference above 1°.

const ArmRest := preload("res://scripts/actors/arm_rest.gd")
const BodyClear := preload("res://scripts/actors/body_clear_modifier.gd")
const Pen := preload("res://tests/probe_hand_penetration.gd")
const ALL := ["pavel", "mitya", "pelageya", "nina", "ilya", "ilya_wife", "tamara", "ulyana", "manager"]
const STEP := 0.1
const CLOUD_EVERY := 0.5
const HAND_EVERY := 30
const HOLD := 0.3
const SIGMA := 0.25


func _initialize() -> void:
	_run()


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


## The body and clothes as points (not the arms, not the head) near where the hands hang. The models' meshes are
## decimated — a coat's flat front has vertices 3–5 cm apart, and a hand went through between them unnoticed (first
## bake 09.11: Mitya's hand 5 cm inside his coat with every vertex «clear») — so the points are spread over the
## TRIANGLES, no farther than `SPACING` apart at rest. Per mesh surface: [prepped entry, vertex ids used
## (PackedInt32Array), points as [ia, ib, ic (indices into that list), wa, wb, wc] flat in a PackedFloat32Array].
const SPACING := 0.01    # metres
const VOX := 0.02        # metres: the cells the points are kept in (a point's limit is never above it)

static func _candidates(sk: Skeleton3D, meshes: Array, prepped: Array, ax: Array, unit: float) -> Array:
	var hips := sk.find_bone("Hips")
	var hr := sk.get_bone_global_rest(hips)
	var rests: Array = []
	for b in sk.get_bone_count():
		rests.append(sk.get_bone_global_rest(b))
	# the index buffers, in the order Pen.prep made its entries
	var index_of: Array = []
	for mi in meshes:
		if (mi as MeshInstance3D).skin == null:
			continue
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null or vs.is_empty():
				continue
			index_of.append(arr[Mesh.ARRAY_INDEX])
	var out: Array = []
	for ei in prepped.size():
		var e: Array = prepped[ei]
		var cls: PackedByteArray = e[7]
		var idx = index_of[ei] if ei < index_of.size() else null
		if idx == null or (idx as PackedInt32Array).is_empty():
			continue
		var mats := {}
		var rest_pos := {}     # vertex id → rest position (skeleton space), only body vertices in the height band
		var in_band := func(k: int) -> bool:
			if cls[k] != 1:
				return false
			if not rest_pos.has(k):
				var p: Vector3 = Pen.skin_pt(e, k, rests, mats)[0]
				var h: float = (hr.affine_inverse() * p).dot(ax[0])
				rest_pos[k] = p if (h > -0.62 * unit and h < 0.44 * unit) else null
			return rest_pos[k] != null
		var slot := {}         # vertex id → index in `ids`
		var ids := PackedInt32Array()
		var pts := PackedFloat32Array()
		var ind: PackedInt32Array = idx
		for ti in range(0, ind.size(), 3):
			var ka := ind[ti]
			var kb := ind[ti + 1]
			var kc := ind[ti + 2]
			if not (in_band.call(ka) and in_band.call(kb) and in_band.call(kc)):
				continue
			var pa: Vector3 = rest_pos[ka]
			var pb: Vector3 = rest_pos[kb]
			var pc: Vector3 = rest_pos[kc]
			var edge := maxf(pa.distance_to(pb), maxf(pb.distance_to(pc), pc.distance_to(pa)))
			var n := clampi(int(ceil(edge / (SPACING * unit))), 1, 40)
			for k in [ka, kb, kc]:
				if not slot.has(k):
					slot[k] = ids.size()
					ids.append(k)
			# barycentric lattice; the corners and edges belong to the neighbours too — a few doubles do no harm
			for i in n + 1:
				for j in n + 1 - i:
					var wa := float(i) / n
					var wb := float(j) / n
					pts.append_array(PackedFloat32Array([float(slot[ka]), float(slot[kb]), float(slot[kc]), wa, wb, 1.0 - wa - wb]))
		out.append([e, ids, pts])
	return out


## The candidates at the pose `poses`: [cells Vector3i → Array of Vector3 (cells of VOX), near Vector3i → true — the
## cells with a point in them or next to them (a point outside `near` has nothing within VOX)].
static func _cloud(cand: Array, poses: Array, unit: float) -> Array:
	var cell := VOX * unit
	var grid := {}
	for ce in cand:
		var mats := {}
		var ids: PackedInt32Array = ce[1]
		var pos := PackedVector3Array()
		pos.resize(ids.size())
		for i in ids.size():
			pos[i] = Pen.skin_pt(ce[0], ids[i], poses, mats)[0]
		var pts: PackedFloat32Array = ce[2]
		for q in range(0, pts.size(), 6):
			var p: Vector3 = pos[int(pts[q])] * pts[q + 3] + pos[int(pts[q + 1])] * pts[q + 4] + pos[int(pts[q + 2])] * pts[q + 5]
			var key := Vector3i((p / cell).floor())
			if not grid.has(key):
				grid[key] = []   # an Array: a packed array taken out of a Dictionary is a copy — appending to it filled nothing (first bakes 09.11)
			(grid[key] as Array).append(p)
	var near := {}
	for key in grid.keys():
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					near[(key as Vector3i) + Vector3i(dx, dy, dz)] = true
	return [grid, near]


## Is anything of the cloud within `lim` (skeleton units, ≤ VOX) of p?
static func _touches(cloud: Array, p: Vector3, lim: float, cell: float) -> bool:
	var kc := Vector3i((p / cell).floor())
	if not (cloud[1] as Dictionary).has(kc):
		return false
	var grid: Dictionary = cloud[0]
	var l2 := lim * lim
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var kk := kc + Vector3i(dx, dy, dz)
				if not grid.has(kk):
					continue
				for q in (grid[kk] as Array):
					if p.distance_squared_to(q) < l2:
						return true
	return false


## One villager: {clips: {bare name: {step_s, L, R}}} and a line of numbers for the log.
static func bake_one(live, cfg: Dictionary) -> Dictionary:
	var gap := float(cfg.get("gap_m", 0.008))          # the hand's surface to the clothes
	var sink := float(cfg.get("sink_m", 0.015))        # the forearm may press this far into a jacket's or a shawl's side
	var min_rad := deg_to_rad(float(cfg.get("min_deg", 5.0)))
	var wrist_out := float(cfg.get("wrist_out_m", 0.04))   # the wrist at least this far outside the shoulder joint
	var view = live.view
	var sk: Skeleton3D = view.skeleton
	var bc = live.arm_body
	var ax := ArmRest.axes(sk)
	var hips := sk.find_bone("Hips")
	var unit: float = bc._unit
	var prepped: Array = Pen.prep(sk, view.meshes)
	var cand := _candidates(sk, view.meshes, prepped, ax, unit)
	var cell := VOX * unit
	# the hands' own vertices (every HAND_EVERY-th): 16 points on a hand missed fingers that were already in the cloth
	var hand_v: Array = [[], []]
	for ei in prepped.size():
		var cls: PackedByteArray = prepped[ei][7]
		var cnt := [0, 0]
		for k in cls.size():
			if cls[k] == 2 or cls[k] == 3:
				var sd := int(cls[k]) - 2
				cnt[sd] += 1
				if cnt[sd] % HAND_EVERY == 0:
					(hand_v[sd] as Array).append([ei, k])
	var names := {}
	# a villager's talk pool (rt3d.talk_pool, Director 10.11 22:30) is said like talk: its clips are rested too
	for role in cfg.get("roles", ["idle", "talk", "listen"]) + (live.rt.get("talk_pool", []) as Array):
		if view.clips.has(role):
			names[view.clips[role]] = true
	for e in view.idle_pool:
		names[e["name"]] = true
	var keep: Array = []
	for b in sk.get_bone_count():
		keep.append(sk.get_bone_pose_rotation(b))
	var out := {}
	var log := ""
	for nm in names.keys():
		var a: Animation = view.anim.get_animation(nm)
		if a == null:
			continue
		var tr := {}
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				tr[String(a.track_get_path(i).get_concatenated_subnames())] = i
		var n := int(ceil(a.length / STEP)) + 1
		var res := {"L": [], "R": []}
		var was := {"L": 0.0, "R": 0.0}
		var cloud: Array = []
		var cloud_t := -INF
		for k in n:
			var t := minf(k * STEP, a.length)
			BodyClear._pose_clip(sk, a, tr, t)
			var poses: Array = []
			for b in sk.get_bone_count():
				poses.append(sk.get_bone_global_pose(b))
			# the body and the clothes, in cells: built anew every CLOUD_EVERY s of the clip (the stance and the talk
			# clips move the trunk a fraction of a degree in that time; the clips' hips do not travel here)
			if cloud.is_empty() or t - cloud_t >= CLOUD_EVERY - 1e-4:
				cloud = _cloud(cand, poses, unit)
				cloud_t = t
			var hb := (poses[hips] as Transform3D).basis.orthonormalized()
			var axis: Vector3 = (hb * (ax[2] as Vector3)).normalized()
			for side in 2:
				var key := "L" if side == 0 else "R"
				var ids: Array = bc._arm[side]
				var sh: Vector3 = (poses[ids[0]] as Transform3D).origin
				var el: Vector3 = (poses[ids[1]] as Transform3D).origin
				var wr: Vector3 = (poses[ids[2]] as Transform3D).origin
				var sp := ArmRest.spread_of(hb.inverse() * (el - sh), ax, side == 0)
				was[key] += rad_to_deg(sp.x) / n
				var sgn := -1.0 if side == 0 else 1.0
				var most := maxf(0.0, sp.x - min_rad)
				# the arm's points and how near the clothes each may come (never above VOX)
				var f_lim := clampf(bc.fore_r - sink, gap, VOX) * unit
				var pts: Array = [[el.lerp(wr, 0.5), f_lim], [el.lerp(wr, 0.8), f_lim]]
				var mats_by := {}
				for hv in hand_v[side]:
					if not mats_by.has(hv[0]):
						mats_by[hv[0]] = {}
					pts.append([Pen.skin_pt(prepped[hv[0]], hv[1], poses, mats_by[hv[0]])[0], gap * unit])
				var phi := 0.0
				var got := 0.0
				var hit := false
				var out_w: Vector3 = (hb * (ax[1] as Vector3)).normalized() * (1.0 if side == 0 else -1.0)   # away from the body, this side
				while phi <= most + 1e-6 and not hit:
					var rot := Basis(axis, sgn * phi)
					# the wrist stays outside the shoulder's own line: a hand hanging in front of the thigh, inside the
					# shoulder, reads as hunched
					if (rot * (wr - sh)).dot(out_w) < wrist_out * unit:
						hit = true
						break
					for pt in pts:
						if _touches(cloud, sh + rot * ((pt[0] as Vector3) - sh), float(pt[1]), cell):
							hit = true
							break
					if not hit:
						got = phi
						phi += deg_to_rad(0.5)
				if hit:
					got = maxf(0.0, got - deg_to_rad(0.5))   # half a degree back from the last clear turn
				(res[key] as Array).append(rad_to_deg(got) * sp.y)
		var bare := String(nm).get_slice("/", String(nm).get_slice_count("/") - 1)
		var entry := {"step_s": STEP}
		for key in ["L", "R"]:
			var raw: Array = res[key]
			var held: Array = []
			var w := int(round(HOLD / STEP))
			for k in raw.size():
				var m := INF
				for j in range(maxi(0, k - w), mini(raw.size(), k + w + 1)):
					m = minf(m, float(raw[j]))
				held.append(m)
			var sm: Array = []
			var sw := int(ceil(3.0 * SIGMA / STEP))
			for k in held.size():
				var acc := 0.0
				var ws := 0.0
				for j in range(maxi(0, k - sw), mini(held.size(), k + sw + 1)):
					var g2 := exp(-0.5 * pow(float(j - k) * STEP / SIGMA, 2.0))
					acc += float(held[j]) * g2
					ws += g2
				# a weighted mean of what is clear nearby, never more than a degree above what is clear at this moment
				sm.append(snappedf(minf(acc / ws, float(held[k]) + 1.0), 0.01))
			entry[key] = sm
			var mean := 0.0
			for v in sm:
				mean += float(v) / sm.size()
			log += " %s %s %.0f°→%.0f°" % [bare.get_slice("_", 0), key, was[key], was[key] - mean]
		out[bare] = entry
	for b in sk.get_bone_count():
		sk.set_bone_pose_rotation(b, keep[b])
	return {"clips": out, "log": log}


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var ids: Array = ALL if a.is_empty() or a[0] == "all" else Array(String(a[0]).split(","))
	var check := a.size() > 1 and a[1] == "check"
	var NL = load("res://scripts/actors/npc_live_3d.gd")
	var bad := 0
	for id in ids:
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var cfg: Dictionary = (spec["rt3d"].get("arm_body", {}) as Dictionary).get("rest", {})
		if cfg.is_empty():
			print("%s: no rt3d.arm_body.rest — skipped" % id)
			continue
		var path := String(cfg.get("file", "res://data/actors_rest/%s.json" % id))
		# the clips as they are before the turn: the figure is built without it
		(spec["rt3d"]["arm_body"] as Dictionary).erase("rest")
		var n := _fake_npc()
		var live = NL.new()
		n.add_child(live)
		if not live.setup(n, spec, 0.55) or live.arm_body == null:
			print("%s: no live figure / BodyClear" % id)
			bad += 1
			continue
		live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var t0 := Time.get_ticks_msec()
		var r := bake_one(live, cfg)
		print("%-9s %d ms |%s" % [id, Time.get_ticks_msec() - t0, r["log"]])
		var doc := {"_comment": "Руки вдоль тела (scripts/actors/arm_rest.gd): на сколько градусов каждое плечо повёрнуто к телу в каждом клипе, по времени. Считает tests/bake_arm_rest.gd по оболочке одежды этой модели — руками не править; после смены модели или клипов пересчитать: tools/bake_arm_rest.sh.",
			"model": String(spec["rt3d"].get("scene", "")), "gap_m": float(cfg.get("gap_m", 0.008)), "sink_m": float(cfg.get("sink_m", 0.015)), "wrist_out_m": float(cfg.get("wrist_out_m", 0.04)), "min_deg": float(cfg.get("min_deg", 5.0)), "clips": r["clips"]}
		if check:
			var old = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			var worst := 0.0
			if old == null:
				worst = INF
			else:
				for cn in (r["clips"] as Dictionary).keys():
					for key in ["L", "R"]:
						var x: Array = r["clips"][cn][key]
						var y: Array = (old.get("clips", {}) as Dictionary).get(cn, {}).get(key, [])
						if x.size() != y.size():
							worst = INF
							continue
						for i in x.size():
							worst = maxf(worst, absf(float(x[i]) - float(y[i])))
			print("%-9s check: differs from %s by at most %.2f°" % [id, path, worst])
			if worst > 1.0:
				bad += 1
				# 12.11: the full run of 11.11 was red on Nina here and nobody saw it — the summary of a run lists
				# the lines that begin with FAIL
				print("FAIL  arm rest %s: the curves in %s differ from the model by %.2f° (> 1°) — re-bake: tools/bake_arm_rest.sh %s" % [id, path, worst, id])
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify(doc, " ") + "\n")
			f.close()
		n.queue_free()
		await process_frame
	quit(1 if bad > 0 else 0)
