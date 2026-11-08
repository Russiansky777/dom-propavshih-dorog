extends SkeletonModifier3D
## Reconstructed after workspace loss, from the last frozen pilot implementation.
## Default path is the previous hem-only drive; collision_sweep opts narrow NPC skirts in.
var chains: Array = []
var shin_bones: Array = []
var hips_bone: int = -1
var units_per_m: float = 100.0
var leg_r_m: float = 0.075
var spread_m: float = 0.16
var reach_k: float = 1.0
var hem_len_k: float = 1.0
var max_deg: float = 35.0
var push_m: Array = []
var on: bool = true
var up := Vector3.UP
var collision_sweep: bool = false
## Optional resolved [from_bone,to_bone,radius_m] for partial garments.
var collision_segments: Array = []
var sector_half_angle_deg: float = -1.0
var sweep_margin_m: float = 0.003
var sweep_gap_m: Array = []
var sweep_residual_m: Array = []
var sweep_angle_deg: Array = []
var sweep_required_angle_deg: Array = []
## Exponential release time constant; zero preserves the original immediate sweep.
var sweep_release_s: float = 0.0
## Axis range limits invisible shin regions; 0 starts at knee, 1 at ankle.
var sweep_start_ratio := Vector2.ZERO
## Radial inset only. Sector width remains determined by the chain count.
var sweep_inner_k: float = -1.0
var _sweep_previous_angles: Array = []
var _modifier_delta: float = 0.0

func _process_modification_with_delta(delta: float) -> void:
	_modifier_delta = maxf(delta,0.0)
	_process_modification()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or chains.is_empty() or hips_bone < 0 or not on:
		if push_m.size() != chains.size():
			push_m.resize(chains.size())
		push_m.fill(0.0)
		_sweep_previous_angles.clear()
		return
	var axis: Vector3 = sk.get_bone_global_pose(hips_bone).origin
	var u := units_per_m
	var shins: Array = []
	for s in shin_bones:
		shins.append([sk.get_bone_global_pose(int(s[0])).origin, sk.get_bone_global_pose(int(s[1])).origin])
	if push_m.size() != chains.size():
		push_m.resize(chains.size())
	if collision_sweep:
		if not collision_segments.is_empty():
			shins.clear()
			for segment in collision_segments:
				shins.append([sk.get_bone_global_pose(int(segment[0])).origin,sk.get_bone_global_pose(int(segment[1])).origin,float(segment[2])])
		_sweep_chains(sk, axis, shins)
		return
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

func _sector_half_angle() -> float:
	return PI/float(maxi(chains.size(),3)) if sector_half_angle_deg < 0.0 else deg_to_rad(clampf(sector_half_angle_deg,1.0,89.0))

func _sweep_gap(points: Array, axis: Vector3, n: Vector3, shins: Array, inner_k: float, capsule_frames: Array = [], stop_above: float = INF) -> float:
	var heights: Array = [(points[0] as Vector3).dot(up),(points[1] as Vector3).dot(up),(points[2] as Vector3).dot(up),(points[3] as Vector3).dot(up)]
	var highest: float = heights[0]
	var lowest: float = heights[3]
	var sector_sine := sin(_sector_half_angle())
	var gap := 0.0
	if capsule_frames.is_empty():
		capsule_frames = _capsule_frames(shins,axis,n)
	for frame in capsule_frames:
		var radius: float = frame[6]
		var ha: float = frame[4]
		var hb: float = frame[7]
		var radial_upper: float = maxf(float(frame[0]),float(frame[0])+float(frame[1]))+radius
		var levels: Array = [ha, hb, (ha + hb) * 0.5, heights[1], heights[2], lowest]
		# A cropped boot capsule can overlap only a small part of the cloth.
		# Fixed anatomical/control heights alone can miss that entire interval.
		var overlap_low := maxf(lowest,minf(ha,hb)-radius)
		var overlap_high := minf(highest,maxf(ha,hb)+radius)
		if overlap_high > overlap_low:
			for fraction in [0.0,0.25,0.5,0.75,1.0]:
				levels.append(lerpf(overlap_low,overlap_high,float(fraction)))
		for height in levels:
			var h: float = height
			if h >= highest - 1e-5 or h < lowest - 1e-5 or h > maxf(ha, hb) + radius or h < minf(ha, hb) - radius:
				continue
			var q: Vector3 = points[3]
			for segment in 3:
				var q0: Vector3 = points[segment]
				var q1: Vector3 = points[segment + 1]
				var h0: float = heights[segment]
				var h1: float = heights[segment+1]
				if h <= maxf(h0,h1) + 1e-5 and h >= minf(h0,h1) - 1e-5:
					var blend := 0.0 if absf(h0-h1) < 1e-5 else clampf((h0-h)/(h0-h1),0.0,1.0)
					q = q0.lerp(q1,blend)
					break
			var chain_radius := maxf((q-axis).dot(n)/units_per_m,0.0)
			var cloth_radius := chain_radius*inner_k
			# A capsule cannot exceed its endpoint radial bound plus its radius.
			# Skip only supports that cannot increase the current maximum gap.
			if radial_upper/units_per_m+sweep_margin_m-cloth_radius+1e-8 <= gap:
				continue
			var panel_half_width := chain_radius*sector_sine
			var support := _capsule_support_frame(frame,h,panel_half_width*units_per_m)
			if not is_finite(support):
				continue
			gap = maxf(gap,support/units_per_m+sweep_margin_m-cloth_radius)
			if gap > stop_above:
				return gap
	return maxf(gap,0.0)

func _capsule_projection(a: Vector3, b: Vector3, axis: Vector3, n: Vector3, radius: float) -> Array:
	var tangent := up.cross(n).normalized()
	var direction := b-a
	return [(a-axis).dot(n),direction.dot(n),(a-axis).dot(tangent),direction.dot(tangent),a.dot(up),direction.dot(up),radius,b.dot(up)]

func _capsule_frames(shins: Array, axis: Vector3, n: Vector3) -> Array:
	var out: Array = []
	for shin in shins:
		var radius := (float(shin[2]) if shin.size()>2 else leg_r_m)*units_per_m
		out.append(_capsule_projection(shin[0],shin[1],axis,n,radius))
	return out

func _capsule_plane_support(a: Vector3, b: Vector3, axis: Vector3, n: Vector3, height: float, half_width: float, radius: float) -> float:
	return _capsule_support_frame(_capsule_projection(a,b,axis,n,radius),height,half_width)

func _capsule_support_frame(frame: Array, height: float, half_width: float) -> float:
	# Exact concave support; projected axis terms are constant through bisection.
	var n0: float = frame[0]
	var nd: float = frame[1]
	var s0: float = frame[2]
	var sd: float = frame[3]
	var h0: float = float(frame[4])-height
	var hd: float = frame[5]
	var radius: float = frame[6]
	var cuts: Array = [0.0,1.0]
	if absf(sd) > 1e-12:
		for edge in [-half_width,half_width]:
			var t := (float(edge)-s0)/sd
			if t > 0.0 and t < 1.0:
				cuts.append(t)
	cuts.sort()
	var best := -INF
	for segment in cuts.size()-1:
		var lo: float = cuts[segment]
		var hi: float = cuts[segment+1]
		var side := s0+sd*(lo+hi)*0.5
		var d0 := 0.0
		var dd := 0.0
		if side < -half_width:
			d0 = -s0-half_width
			dd = -sd
		elif side > half_width:
			d0 = s0-half_width
			dd = sd
		var quadratic := hd*hd+dd*dd
		var mixed := h0*hd+d0*dd
		var constant := radius*radius-h0*h0-d0*d0
		# Exact tangent contacts can produce a few negative double-precision ulps.
		# Clamp only arithmetic roundoff relative to the squared geometric terms.
		var roundoff := maxf(radius*radius,h0*h0+d0*d0)*1e-12
		if quadratic <= 1e-20:
			if constant >= -roundoff:
				best = maxf(best,n0+nd*(hi if nd >= 0.0 else lo)+sqrt(maxf(constant,0.0)))
			continue
		var center := -mixed/quadratic
		var peak := constant+mixed*mixed/quadratic
		roundoff = maxf(roundoff,absf(mixed*mixed/quadratic)*1e-12)
		if peak < -roundoff:
			continue
		peak = maxf(peak,0.0)
		var span := sqrt(peak/quadratic)
		lo = maxf(lo,center-span)
		hi = minf(hi,center+span)
		if hi < lo:
			continue
		var optimum := center+nd*sqrt(peak)/(sqrt(quadratic)*sqrt(quadratic+nd*nd))
		# The objective is concave: clamping its stationary point includes a
		# boundary maximum, so separate endpoint evaluations are redundant.
		var t := clampf(optimum,lo,hi)
		var height_gap := h0+hd*t
		var side_gap := d0+dd*t
		var cross_sq := maxf(radius*radius-height_gap*height_gap-side_gap*side_gap,0.0)
		best = maxf(best,n0+nd*t+sqrt(cross_sq))
	return best

func _turned_points(points: Array, rotation: Basis) -> Array:
	var origin: Vector3 = points[0]
	var out: Array = [origin]
	for i in range(1,4):
		out.append(origin+rotation*((points[i] as Vector3)-origin))
	return out

func _release_angle(previous: float, required: float, delta: float) -> float:
	# Collision clearance is immediate. Only an inward release has temporal memory.
	if required >= previous or sweep_release_s <= 0.0:
		return required
	return required+(previous-required)*exp(-maxf(delta,0.0)/sweep_release_s)

func _sweep_shins(shins: Array) -> Array:
	var out: Array = []
	for i in shins.size():
		var a: Vector3 = shins[i][0]
		var b: Vector3 = shins[i][1]
		var start: float = sweep_start_ratio[i] if i<2 else 0.0
		var segment: Array = [a.lerp(b,clampf(start,0.0,1.0)),b]
		if shins[i].size()>2:segment.append(shins[i][2])
		out.append(segment)
	return out

func _sweep_chains(sk: Skeleton3D, axis: Vector3, shins: Array) -> void:
	var inner_k := cos(_sector_half_angle()) if sweep_inner_k < 0.0 else clampf(sweep_inner_k,0.1,1.0)
	shins = _sweep_shins(shins)
	if _sweep_previous_angles.size() != chains.size():
		_sweep_previous_angles.resize(chains.size())
		_sweep_previous_angles.fill(0.0)
	for values in [sweep_gap_m,sweep_residual_m,sweep_angle_deg,sweep_required_angle_deg]:
		values.resize(chains.size())
		values.fill(0.0)
	for c in chains.size():
		var chain: Array = chains[c]
		var origin := sk.get_bone_global_pose(int(chain[0])).origin
		var middle := sk.get_bone_global_pose(int(chain[1])).origin
		var last := sk.get_bone_global_pose(int(chain[2])).origin
		var hem := last+(last-middle)*hem_len_k
		var radial := hem-axis
		var n := (radial-up*radial.dot(up)).normalized()
		if n.length_squared() < 1e-8:
			push_m[c] = 0.0
			continue
		var points: Array = [origin,middle,last,hem]
		var capsule_frames := _capsule_frames(shins,axis,n)
		var gap := _sweep_gap(points,axis,n,shins,inner_k,capsule_frames)
		sweep_gap_m[c] = gap
		var rotation_axis := n.cross(up).normalized()
		var lo := 0.0
		var hi := 0.0
		if gap > 1e-4:
			hi = deg_to_rad(max_deg)
			for iteration in 10:
				var angle := (lo+hi)*0.5
				var candidate := _turned_points(points,Basis(rotation_axis,angle))
				if _sweep_gap(candidate,axis,n,shins,inner_k,capsule_frames,1e-4) > 1e-4:
					lo = angle
				else:
					hi = angle
		var required := hi*reach_k
		var applied := _release_angle(float(_sweep_previous_angles[c]),required,_modifier_delta)
		# The sector widens as it moves outward. A retained intermediate angle
		# can newly touch a neighbouring capsule although the unrotated sector is clear.
		# Never let release memory hold the cloth inside that contact interval.
		if applied > required and _sweep_gap(_turned_points(points,Basis(rotation_axis,applied)),axis,n,shins,inner_k,capsule_frames,1e-4) > 1e-4:
			lo = applied
			hi = deg_to_rad(max_deg)*reach_k
			for iteration in 10:
				var angle := (lo+hi)*0.5
				if _sweep_gap(_turned_points(points,Basis(rotation_axis,angle)),axis,n,shins,inner_k,capsule_frames,1e-4) > 1e-4:
					lo = angle
				else:
					hi = angle
			applied = maxf(applied,hi)
			required = maxf(required,hi)
		_sweep_previous_angles[c] = applied
		var rotation := Basis(rotation_axis,applied)
		sweep_required_angle_deg[c] = rad_to_deg(required)
		sweep_angle_deg[c] = rad_to_deg(applied)
		sweep_residual_m[c] = _sweep_gap(_turned_points(points,rotation),axis,n,shins,inner_k,capsule_frames)
		var moved_hem := origin+rotation*(hem-origin)
		push_m[c] = maxf((moved_hem-hem).dot(n)/units_per_m,0.0)
		var global_pose := sk.get_bone_global_pose(int(chain[0]))
		sk.set_bone_global_pose(int(chain[0]),Transform3D(rotation*global_pose.basis,global_pose.origin))
