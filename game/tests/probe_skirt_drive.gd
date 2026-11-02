extends SceneTree
## How far the legs step out from under the skirt (Director 01.11, line 3: «2 не связанных с юбкой ботинка сами шагают…
## юбка не двигается»): the live figure alone, walking on the spot; per drawn frame (after the springs) the ring of hem
## points (one per chain) and each shin at the hem's height — how far the shin's axis is outside the hem ring (cm, 0 —
## inside), and how far the hem points move against the hips. With the drive on and off.
##   godot --headless --fixed-fps 60 --path game -s res://tests/probe_skirt_drive.gd

var v: Actor3D
var rows: Array = []


func _initialize() -> void:
	_run()


static func outside_ring(p: Vector2, ring: Array) -> float:
	# distance of p outside a closed polygon given in order round the axis (0 when inside)
	var inside := false
	var n := ring.size()
	var best := INF
	for i in n:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return 0.0 if inside else best


## [max over the frames of the shins' distance outside the hem ring (m), the hem points' largest swing against the hips (m)]
static func measure(av: Actor3D) -> Array:
	var sk := av.skeleton
	var u := 1.0 / maxf(av._skel_to_model().basis.get_scale().x, 1e-6)
	var hips := sk.find_bone("Hips")
	var ank := (sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin + sk.get_bone_global_rest(sk.find_bone("RightFoot")).origin) * 0.5
	var up := (sk.get_bone_global_rest(hips).origin - ank).normalized()
	var ax := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var az := up.cross(ax).normalized()
	var o: Vector3 = sk.get_bone_global_pose(hips).origin
	var ring: Array = []
	var hh := 0.0
	var c := 0
	while sk.find_bone("Skirt%d_2" % c) >= 0:
		var m: Vector3 = sk.get_bone_global_pose(sk.find_bone("Skirt%d_1" % c)).origin
		var l: Vector3 = sk.get_bone_global_pose(sk.find_bone("Skirt%d_2" % c)).origin
		var hem := l + (l - m) - o
		ring.append(Vector2(hem.dot(ax), hem.dot(az)) / u)
		hh += hem.dot(up)
		c += 1
	hh /= maxf(c, 1)
	var out := 0.0
	for side in ["Left", "Right"]:
		var a: Vector3 = sk.get_bone_global_pose(sk.find_bone(side + "Leg")).origin - o
		var b: Vector3 = sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin - o
		var t := clampf((a.dot(up) - hh) / maxf(a.dot(up) - b.dot(up), 1e-5), 0.0, 1.0)
		var p := a.lerp(b, t)
		out = maxf(out, outside_ring(Vector2(p.dot(ax), p.dot(az)) / u, ring))
	return [out, ring]


var pmax := 0.0


func _on_upd() -> void:
	rows.append(measure(v))
	if v.skirt_drive != null:
		for x in v.skirt_drive.push_m:
			pmax = maxf(pmax, float(x))


func _run() -> void:
	await process_frame
	for drive in [true, false]:
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
		v = Actor3D.new()
		root.add_child(v)
		v.setup(spec)
		if v.skirt_drive != null:
			v.skirt_drive.on = drive
		v.skeleton.skeleton_updated.connect(_on_upd)
		var ph := 0.0
		var d := 1.0 / 60.0
		rows = []
		var walk_rows: Array = []
		var stop_rows: Array = []
		for i in 330:
			var w := 0.0
			if i >= 20 and i < 200:
				w = clampf((i - 20) / 20.0, 0.0, 1.0)
			elif i >= 200 and i < 224:
				w = 1.0 - (i - 200) / 24.0
			if w > 0.0:
				ph += d * (0.55 + 0.45 * w) / maxf(v.walk_len, 0.01)
			v.pose(d, fposmod(ph, 1.0), w, 0.0)
			await process_frame
			if rows.is_empty():
				continue
			if i >= 80 and i < 200:
				walk_rows.append(rows[-1])
			elif i >= 224:
				stop_rows.append(rows[-1])
		var out := 0.0
		var swing := 0.0
		var lo: Array = []
		var hi: Array = []
		for r in walk_rows:
			out = maxf(out, float(r[0]))
			for k in (r[1] as Array).size():
				if lo.size() <= k:
					lo.append(r[1][k])
					hi.append(r[1][k])
				lo[k] = (lo[k] as Vector2).min(r[1][k])
				hi[k] = (hi[k] as Vector2).max(r[1][k])
		for k in lo.size():
			swing = maxf(swing, ((hi[k] as Vector2) - (lo[k] as Vector2)).length())
		# after the stop: how much the hem still moves frame to frame (the «колбасит» at the end of a move)
		var jig := 0.0
		for j in range(1, stop_rows.size()):
			for k in (stop_rows[j][1] as Array).size():
				jig = maxf(jig, ((stop_rows[j][1][k] as Vector2) - (stop_rows[j - 1][1][k] as Vector2)).length())
		print("drive %s: walking, a shin goes %.1f cm out of the hem ring at most; hem points swing %.1f cm; after the stop the hem moves ≤ %.1f mm/frame; drive push ≤ %.1f cm" % [str(drive), out * 100.0, swing * 100.0, jig * 1000.0, pmax * 100.0])
		pmax = 0.0
		v.skeleton.skeleton_updated.disconnect(_on_upd)
		v.queue_free()
		await process_frame
	quit(0)
