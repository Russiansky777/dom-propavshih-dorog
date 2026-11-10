extends SkeletonModifier3D
## Hands that hold a thing which moves (Director 10.11, 18:59, the windlass of the first span: «и руки нужно доделать» —
## the crank went round and Ilya's hands hovered above it in the small circle of his clip). Each held hand's grip point
## (Actor3D.hand_grip_local) is brought to a target given in skeleton space, by turning the upper arm and the forearm
## (two bones, the elbow kept back and down). Where the target is too low to reach standing, the body goes down to
## it as a working man's does — by one measure of «effort» (0..1), as little as brings every hand within reach:
## the trunk leans forward (mostly at the hips, the rest in the lower back), the hips go back under it and down, the
## knees give — the feet stay exactly where they stand.
## While a hand holds he stands in a working stance (`work_lean_deg`, `work_squat`: the trunk inclined, the knees given)
## — 10.11, the windlass in the game: its crank goes round from 0,63 m to 1,27 m above his feet, 0,3–0,45 m in front;
## standing upright he reached the top half with his arms alone and then bowed 52° and back within an eighth of a turn
## (0,2 s), every turn. From the working stance the whole round is within his arms' reach, and the back follows the
## hands: the lower the leading hand's place under the shoulder, the more he leans and gives in the knees
## (`sway_lean_deg`, `sway_squat`) — a smooth sway in time with the thing he turns, not a clip's own swing.
## Last of the skeleton's modifiers (after the clothes' clearance and the feet): the hand is where the thing is.
## `targets` / `want` are set every frame by the owner (NpcLive3D.hold_hand_at); the weight eases in and out here.

const EASE_PER_S := 3.5

var sides: Dictionary = {}      # side → [arm bone, forearm bone, hand bone]
var grip_local: Dictionary = {} # side → Vector3: the grip point in the hand bone's own frame
var targets: Dictionary = {}    # side → Vector3 (skeleton space): where the grip point must be
var want: Dictionary = {}       # side → 0..1: wanted weight
var helping: Dictionary = {}    # side → true: this hand helps — the body does not go down for it (it reaches as far
                                # as the posture the leading hand asked for lets it)
var weights: Dictionary = {}    # side → 0..1: shown weight (eased)
var spine: int = -1
var hips: int = -1
var legs: Array = []            # [[upper leg, lower leg, foot], …] left, right
var to_model := Basis.IDENTITY  # skeleton space → model space (x across: + her left, y up, z forward)
var work_lean_deg: float = 8.0  # the working stance (while a hand that does not merely help holds): the trunk's lean…
var work_squat: float = 0.06    # …and the hips lower by this share of the leg's length
var sway_lean_deg: float = 16.0 # more lean with the leading hand an arm's length under the shoulder (none with it level)…
var sway_squat: float = 0.08    # …and the hips lower by this share of the leg's length more
                                # (10.11, tried on the windlass: 18° + 10° and 12 % + 4 % — a man crouching all the
                                # turn, the hand at the top of it right under his chin)
var max_lean_deg: float = 65.0  # the trunk's lean at full effort
var hip_share: float = 0.7      # of the lean at the hips, the rest in the lower back
var hinge_k: float = 0.3       # the hips go back by this share of the trunk's forward reach
var squat_k: float = 0.08       # at full effort the hips are lower by this share of the leg's length
var reach_k: float = 0.97       # of the arm's length: never quite straight
var effort_now: float = 0.0     # 0..1 over the working stance, the last frame's (tests)
var stance_now: float = 0.0     # 0..1: how much of the working stance is on (tests)
var low_now: float = 0.0        # 0..1: how low the leading hand's place is under its shoulder (tests)
var lean_now: float = 0.0       # rad (tests)


func setup(sk: Skeleton3D, p_to_model: Basis) -> void:
	to_model = p_to_model
	for side in ["Left", "Right"]:
		var a := sk.find_bone(side + "Arm")
		var f := sk.find_bone(side + "ForeArm")
		var h := sk.find_bone(side + "Hand")
		if a >= 0 and f >= 0 and h >= 0:
			sides[side] = [a, f, h]
		var u := sk.find_bone(side + "UpLeg")
		var l := sk.find_bone(side + "Leg")
		var ft := sk.find_bone(side + "Foot")
		if u >= 0 and l >= 0 and ft >= 0:
			legs.append([u, l, ft])
	for nm in ["Spine", "Spine01", "Spine1", "Spine02"]:
		if spine < 0:
			spine = sk.find_bone(nm)
	hips = sk.find_bone("Hips")


func hold(side: String, target: Vector3, weight: float, helps: bool = false) -> void:
	targets[side] = target
	want[side] = clampf(weight, 0.0, 1.0)
	helping[side] = helps


func any_shown() -> bool:
	for s in weights:
		if float(weights[s]) > 0.001:
			return true
	return false


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var top := 0.0
	for side in sides:
		var w := move_toward(float(weights.get(side, 0.0)), float(want.get(side, 0.0)), delta * EASE_PER_S)
		weights[side] = w
		top = maxf(top, w)
	effort_now = 0.0
	lean_now = 0.0
	stance_now = 0.0
	low_now = 0.0
	if top <= 0.001:
		return
	var inv := to_model.inverse()
	# where each grip point has to be (eased from where it is)
	var goals: Dictionary = {}
	for side in sides:
		var w := _smooth(float(weights[side]))
		if w <= 0.001 or not targets.has(side):
			continue
		var gh: Transform3D = sk.get_bone_global_pose(int(sides[side][2]))
		var grip: Vector3 = gh * (grip_local.get(side, Vector3.ZERO) as Vector3)
		goals[side] = grip.lerp(targets[side] as Vector3, w)
	if goals.is_empty():
		return
	# the body: the working stance (as much as the leading hands hold), and over it the least effort that brings every
	# goal within the arm's reach
	if spine >= 0 and hips >= 0 and legs.size() == 2:
		var f := _frame(sk, inv)
		var st := 0.0
		var low := 0.0
		for side in goals:
			if not bool(helping.get(side, false)):
				st = maxf(st, _smooth(float(weights[side])))
				var bs: Array = sides[side]
				var sh: Vector3 = sk.get_bone_global_pose(int(bs[0])).origin
				var arm: float = (sk.get_bone_global_pose(int(bs[1])).origin - sh).length() + (sk.get_bone_global_pose(int(bs[2])).origin - sk.get_bone_global_pose(int(bs[1])).origin).length()
				low = maxf(low, clampf((sh - (goals[side] as Vector3)).dot(f["up"] as Vector3) / maxf(arm, 1e-5), 0.0, 1.0))
		low = _smooth(low)
		stance_now = st
		low_now = low
		var e := 0.0
		if not _reachable(sk, goals, f, 0.0, st, low):
			var lo := 0.0
			var hi := 1.0
			for i in 10:
				var mid := (lo + hi) * 0.5
				if _reachable(sk, goals, f, mid, st, low):
					hi = mid
				else:
					lo = mid
			e = hi
		effort_now = e
		if e > 0.0005 or st > 0.0005:
			var p := _posture(f, e, st, low)
			lean_now = float(p["lean"])
			var feet_were: Array = []
			var legs_were: Array = []
			for lg in legs:
				legs_were.append(sk.get_bone_global_pose(int(lg[0])))
				feet_were.append(sk.get_bone_global_pose(int(lg[2])))
			var gh0: Transform3D = sk.get_bone_global_pose(hips)
			var qh: Quaternion = p["qh"]
			var hp: Vector3 = f["hip_pivot"]
			sk.set_bone_global_pose(hips, Transform3D(Basis(qh) * gh0.basis, hp + (p["shift"] as Vector3) + qh * (gh0.origin - hp)))
			var knee_pole := (inv * Vector3(0.0, 0.1, 1.0)).normalized()
			for i in legs.size():
				var lg: Array = legs[i]
				var lw: Transform3D = legs_were[i]
				sk.set_bone_global_pose(int(lg[0]), Transform3D(lw.basis, lw.origin + (p["shift"] as Vector3)))
				_reach(sk, int(lg[0]), int(lg[1]), int(lg[2]), (feet_were[i] as Transform3D).origin, knee_pole, 0.9995)
				sk.set_bone_global_pose(int(lg[2]), feet_were[i])   # the foot stands as it stood
			var gs: Transform3D = sk.get_bone_global_pose(spine)
			sk.set_bone_global_pose(spine, Transform3D(Basis(p["qs"] as Quaternion) * gs.basis, gs.origin))
	# the arms: the upper arm and the forearm with the hand as it is on it — the chain ends in the grip point itself
	# (10.11: it ended in the wrist and the grip point, 13 cm on, was brought up in passes; with the goal near the
	# shoulder — the top of the turn from the working stance — the passes did not meet: the hand stood 15 cm off)
	for side in goals:
		var b: Array = sides[side]
		var sgn := 1.0 if side == "Left" else -1.0
		# the elbow: down, a touch out and back (10.11: «back» first — with the grip near the chest, at the top of the
		# turn, the far arm's elbow stood out behind the back like a wing)
		var pole := (inv * Vector3(sgn * 0.25, -1.0, -0.15)).normalized()
		_reach(sk, int(b[0]), int(b[1]), int(b[2]), goals[side] as Vector3, pole, reach_k, grip_local.get(side, Vector3.ZERO) as Vector3)


static func _smooth(w: float) -> float:
	return w * w * (3.0 - 2.0 * w)


## What the posture is measured from, as the clip has posed the body this frame (skeleton space).
func _frame(sk: Skeleton3D, inv: Basis) -> Dictionary:
	var hip_pivot: Vector3 = (sk.get_bone_global_pose(int(legs[0][0])).origin + sk.get_bone_global_pose(int(legs[1][0])).origin) * 0.5
	var sh := Vector3.ZERO
	var n := 0
	for side in sides:
		sh += sk.get_bone_global_pose(int(sides[side][0])).origin
		n += 1
	var lg: Array = legs[0]
	var leg_len: float = (sk.get_bone_global_pose(int(lg[1])).origin - sk.get_bone_global_pose(int(lg[0])).origin).length() \
		+ (sk.get_bone_global_pose(int(lg[2])).origin - sk.get_bone_global_pose(int(lg[1])).origin).length()
	return {"hip_pivot": hip_pivot, "spine_pivot": sk.get_bone_global_pose(spine).origin,
		"trunk": ((sh / float(maxi(n, 1))) - hip_pivot).length(), "leg": leg_len,
		"side": (inv * Vector3(1, 0, 0)).normalized(), "up": (inv * Vector3(0, 1, 0)).normalized(), "fwd": (inv * Vector3(0, 0, 1)).normalized()}


## The body's posture with `st` (0..1) of the working stance, the leading hand `low` (0..1) under its shoulder and
## effort `e` (0..1) over them: the lean at the hips and in the lower back, the hips' shift back and down.
func _posture(f: Dictionary, e: float, st: float, low: float) -> Dictionary:
	var base := (work_lean_deg + sway_lean_deg * low) * st
	var lean := deg_to_rad(base) + deg_to_rad(maxf(max_lean_deg - base, 0.0)) * e
	var back := hinge_k * float(f["trunk"]) * sin(lean * hip_share)
	var down := ((work_squat + sway_squat * low) * st + squat_k * e) * float(f["leg"])
	return {"lean": lean, "qh": Quaternion(f["side"] as Vector3, lean * hip_share), "qs": Quaternion(f["side"] as Vector3, lean * (1.0 - hip_share)),
		"shift": (f["fwd"] as Vector3) * -back + (f["up"] as Vector3) * -down}


## Would every goal be within reach of its shoulder at effort `e` over the working stance (`st`, `low`)?
func _reachable(sk: Skeleton3D, goals: Dictionary, f: Dictionary, e: float, st: float, low: float) -> bool:
	var p := _posture(f, e, st, low)
	var qh: Quaternion = p["qh"]
	var qs: Quaternion = p["qs"]
	var hp: Vector3 = f["hip_pivot"]
	var sp: Vector3 = f["spine_pivot"]
	for side in goals:
		if bool(helping.get(side, false)):
			continue
		var b: Array = sides[side]
		var s0: Vector3 = sk.get_bone_global_pose(int(b[0])).origin
		var e0: Vector3 = sk.get_bone_global_pose(int(b[1])).origin
		var g0: Vector3 = sk.get_bone_global_pose(int(b[2])) * (grip_local.get(side, Vector3.ZERO) as Vector3)
		var arm_len := (e0 - s0).length() + (g0 - e0).length()   # shoulder — elbow — grip point (the hand as it is on the forearm)
		var s1: Vector3 = hp + (p["shift"] as Vector3) + qh * ((sp + qs * (s0 - sp)) - hp)
		if ((goals[side] as Vector3) - s1).length() > arm_len * reach_k:
			return false
	return true


## Two-bone reach: the chain's end — the point `tip_local` of the end bone `h` (its origin by default), carried by the
## middle bone as it is — to `goal`, the middle joint on the `pole` side; never straighter than `max_k` of the chain.
func _reach(sk: Skeleton3D, a: int, f: int, h: int, goal: Vector3, pole: Vector3, max_k: float, tip_local: Vector3 = Vector3.ZERO) -> void:
	var ga: Transform3D = sk.get_bone_global_pose(a)
	var s := ga.origin
	var e: Vector3 = sk.get_bone_global_pose(f).origin
	var hp: Vector3 = sk.get_bone_global_pose(h) * tip_local
	var l1 := (e - s).length()
	var l2 := (hp - e).length()
	if l1 < 1e-5 or l2 < 1e-5:
		return
	var to := goal - s
	var d := clampf(to.length(), absf(l1 - l2) + 0.0005, (l1 + l2) * max_k)
	var dir := to.normalized() if to.length() > 1e-6 else Vector3.DOWN
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 1e-4:
		pp = (e - s) - dir * (e - s).dot(dir)
	if pp.length() < 1e-4:
		return
	pp = pp.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var y := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var e2 := s + dir * x + pp * y
	var g2 := s + dir * d
	sk.set_bone_global_pose(a, Transform3D(Basis(Quaternion((e - s).normalized(), (e2 - s).normalized())) * ga.basis, s))
	var gf: Transform3D = sk.get_bone_global_pose(f)
	var h2: Vector3 = sk.get_bone_global_pose(h) * tip_local
	sk.set_bone_global_pose(f, Transform3D(Basis(Quaternion((h2 - gf.origin).normalized(), (g2 - gf.origin).normalized())) * gf.basis, gf.origin))
