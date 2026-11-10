extends RefCounted
## Arms along the body (Director 09.11, 22:18: «руки у них не вдоль, а будто в воздухе под углом… как Агаты рука
## нормально лежит, а у Нины торчит… у многих»): the villagers' stance and talk clips hold the upper arms 14–26° out
## from straight down (tests/probe_villager_arm_spread.gd; a relaxed arm hangs at 5–12°), the hands 8–15 cm off the
## clothes. Each hanging arm is turned in towards the body, about the body's forward axis through the shoulder, as far
## as the hand and the forearm stay clear of the clothes (BodyClear's hull of this very model, with a gap) — the arm
## lies along the body, as far in as this body lets it.
##
## How far in, per clip and side over time, is measured once by the baker (tests/bake_arm_rest.gd → data
## res://data/actors_rest/<id>.json: {clips: {<clip>: {step_s, L: [deg…], R: [deg…]}}}) — a second or more of hull
## look-ups per figure is no work for a room's loading. Here the curve is only applied to the clip's keys (per figure:
## Actor3D copies the model's clips for each one). An arm lifted in a gesture is not «hanging» and is left alone (the
## baker weighs the turn by how much the arm points down).
##
## Tests: tests/test_villagers_v3.gd V3-13 (the arms hang closer than the clips have them), V3-7 (the hands stay out of
## the clothes); tools/bake_arm_rest.sh all check (the data matches the model; tools/run_tests.sh).

const META := "arms_rested"


## The body's own axes in the hips' local frame, from the rest pose: [up (to the head), out_l (to the left arm), fwd].
static func axes(sk: Skeleton3D) -> Array:
	var hips := sk.find_bone("Hips")
	var head := sk.find_bone("Head")
	var la := sk.find_bone("LeftArm")
	if hips < 0 or head < 0 or la < 0:
		return []
	var hr := sk.get_bone_global_rest(hips)
	var up: Vector3 = (hr.affine_inverse() * sk.get_bone_global_rest(head).origin).normalized()
	var lp: Vector3 = hr.affine_inverse() * sk.get_bone_global_rest(la).origin
	var out_l: Vector3 = (lp - up * lp.dot(up)).normalized()
	return [up, out_l, out_l.cross(up).normalized()]   # fwd: out_l × up (x × y = z — the toes' side on these rigs)


## The frontal angle of an upper arm (rad, from straight down, + away from the body) and how much it hangs (0..1), from
## its direction in the hips' local frame.
static func spread_of(d: Vector3, ax: Array, left: bool) -> Vector2:
	var up: Vector3 = ax[0]
	var out: Vector3 = (ax[1] as Vector3) if left else -(ax[1] as Vector3)
	var fwd: Vector3 = ax[2]
	var dn := d.normalized()
	var dp := dn - fwd * dn.dot(fwd)
	var sa := atan2(dp.dot(out), -dp.dot(up))
	# hanging: within ~35° of straight down fully, not at all past ~55°
	var hang := smoothstep(0.57, 0.82, -dn.dot(up))
	return Vector2(sa, hang)


## The curve's value at time t (deg), linear between its samples; the clip loops or holds — the ends are held.
static func at(curve: Array, step: float, t: float) -> float:
	if curve.is_empty():
		return 0.0
	var u := clampf(t / maxf(step, 1e-4), 0.0, float(curve.size() - 1))
	var i := int(floor(u))
	var j := mini(i + 1, curve.size() - 1)
	return lerpf(float(curve[i]), float(curve[j]), u - float(i))


## Turns the upper arms in by the baked curves, in the figure's own copies of the clips. `data` — the actor's rest file
## ({clips: {name: {step_s, L, R}}}); the clip names there are bare (no library prefix).
static func apply(sk: Skeleton3D, anim: AnimationPlayer, data: Dictionary, scale: float = 1.0) -> int:
	var ax := axes(sk)
	if ax.is_empty() or anim == null:
		return 0
	var fwd: Vector3 = ax[2]
	var hips := sk.find_bone("Hips")
	var done := 0
	var by_clip: Dictionary = data.get("clips", {})
	for nm in anim.get_animation_list():
		var bare := String(nm).get_slice("/", String(nm).get_slice_count("/") - 1)
		if not by_clip.has(bare):
			continue
		var a := anim.get_animation(nm)
		if a == null or a.has_meta(META):
			continue
		a.set_meta(META, true)
		var c: Dictionary = by_clip[bare]
		var step := float(c.get("step_s", 0.1))
		var tr := {}
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				tr[String(a.track_get_path(i).get_concatenated_subnames())] = i
		for side in ["Left", "Right"]:
			var curve: Array = c.get("L" if side == "Left" else "R", [])
			var arm := sk.find_bone(side + "Arm")
			if curve.is_empty() or arm < 0 or not tr.has(side + "Arm"):
				continue
			var chain: Array = []   # the arm's parents below the hips, hips' child first
			var b := sk.get_bone_parent(arm)
			while b >= 0 and b != hips:
				chain.push_front(b)
				b = sk.get_bone_parent(b)
			var sgn := -1.0 if side == "Left" else 1.0   # about the forward axis: − brings the left arm in, + the right
			var ti: int = tr[side + "Arm"]
			for key in a.track_get_key_count(ti):
				var t := a.track_get_key_time(ti, key)
				var deg := at(curve, step, t) * scale
				if absf(deg) < 0.01:
					continue
				var qp := Quaternion.IDENTITY
				for cb in chain:
					var bn := sk.get_bone_name(cb)
					var ql: Quaternion = a.rotation_track_interpolate(tr[bn], t) if tr.has(bn) else sk.get_bone_rest(cb).basis.get_rotation_quaternion()
					qp = qp * ql
				var qa: Quaternion = a.track_get_key_value(ti, key)
				var turn := Quaternion(fwd, sgn * deg_to_rad(deg))
				a.track_set_key_value(ti, key, (qp.inverse() * turn * qp * qa).normalized())
		done += 1
	return done
