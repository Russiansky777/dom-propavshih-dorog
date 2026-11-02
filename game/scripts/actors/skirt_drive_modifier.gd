extends SkeletonModifier3D
## The skirt goes with the legs (Director 01.11, line 3: «ноги… будто 2 не связанных с юбкой ботинка сами шагают, а при
## шагании ноги выпирают будто штаны из-под юбки, а сама юбка не двигается»). The skirt hangs on its own chains
## (tools/rig_skirt.py, Skirt<c>_<k>) swung by springs, and the springs' pushers on the shins moved the hem by only a few
## centimetres: walking, the skirt stayed a straight bell while the boots stepped 25–30 cm out from under it, the hem
## pieces bound to the shins dragged out after them like trouser legs (tests/probe_skirt_frames.gd).
## Here, after the springs: for each chain, where the shins are at the hem's height (each shin as a capsule of
## `leg_r_m`); a shin that has come out past the hem along the chain's own direction pushes the hem out to clear it —
## the whole chain turned about its root at the hips, as cloth is carried by a stepping knee and shin, on top of the
## springs' own swing (a pose turned before the simulator is not taken by it). Chains beside a leg are pushed fully, farther less
## (`spread_m`: the leg's sideways distance from the chain at which the push has faded).

var chains: Array = []           # per chain: [root bone, middle bone, last bone]
var shin_bones: Array = []       # [[left knee bone, left ankle bone], [right knee, right ankle]]
var hips_bone: int = -1
var units_per_m: float = 100.0   # skeleton units per metre
var leg_r_m: float = 0.075       # a shin with its boot and the skirt's own thickness
var spread_m: float = 0.16
var reach_k: float = 1.0         # share of the push taken (1 — the hem clears the shin)
var hem_len_k: float = 1.0       # the hem lies this many last-bone lengths below the last joint
var max_deg: float = 35.0
var push_m: Array = []           # this frame's push per chain (m; tests)
var on: bool = true
var up := Vector3.UP             # the body's up in skeleton space (at rest: ankles → hips)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or chains.is_empty() or hips_bone < 0 or not on:
		if push_m.size() != chains.size():
			push_m.resize(chains.size())
		push_m.fill(0.0)
		return
	var axis: Vector3 = sk.get_bone_global_pose(hips_bone).origin
	var u := units_per_m
	var shins: Array = []
	for s in shin_bones:
		shins.append([sk.get_bone_global_pose(int(s[0])).origin, sk.get_bone_global_pose(int(s[1])).origin])
	if push_m.size() != chains.size():
		push_m.resize(chains.size())
	for c in chains.size():
		var ch: Array = chains[c]
		var root_o: Vector3 = sk.get_bone_global_pose(int(ch[0])).origin
		var mid_o: Vector3 = sk.get_bone_global_pose(int(ch[1])).origin
		var last_o: Vector3 = sk.get_bone_global_pose(int(ch[2])).origin
		var hem: Vector3 = last_o + (last_o - mid_o) * hem_len_k
		var rel := hem - axis
		var n := rel - up * rel.dot(up)
		if n.length() < 1e-4:
			push_m[c] = 0.0
			continue
		var hem_out := n.length()
		n = n.normalized()
		var h := rel.dot(up)
		var push := 0.0
		for s in shins:
			var a: Vector3 = (s[0] as Vector3) - axis
			var b: Vector3 = (s[1] as Vector3) - axis
			var ha := a.dot(up)
			var hb := b.dot(up)
			# the shin's point at the hem's height (or its end nearest to it)
			var t := 0.0 if absf(ha - hb) < 1e-5 else clampf((ha - h) / (ha - hb), 0.0, 1.0)
			var p := a.lerp(b, t)
			var ph := p - up * p.dot(up)
			var along := ph.dot(n)
			var side := (ph - n * along).length() / u
			var k := 1.0 - smoothstep(spread_m * 0.5, spread_m, side)
			push = maxf(push, (along / u + leg_r_m - hem_out / u) * k)
		push = maxf(push, 0.0) * reach_k
		push_m[c] = push
		if push <= 1e-4:
			continue
		# turn the whole chain about its root so the hem goes out by `push` along n
		var from := hem - root_o
		var to := from + n * push * u
		var ang := from.angle_to(to)
		if ang < 1e-5:
			continue
		ang = minf(ang, deg_to_rad(max_deg))
		var ax := from.cross(to).normalized()
		var r := Basis(ax, ang)
		var g: Transform3D = sk.get_bone_global_pose(int(ch[0]))
		sk.set_bone_global_pose(int(ch[0]), Transform3D(r * g.basis, g.origin))
