extends SkeletonModifier3D
## Hands that hold a thing which moves (Director 10.11, 18:59, the windlass of the first span: «и руки нужно доделать» —
## the crank went round and Ilya's hands hovered above it in the small circle of his clip). Each held hand's grip point
## (Actor3D.hand_grip_local) is brought to a target given in skeleton space, by turning the upper arm and the forearm
## (two bones, the elbow kept back and down). Where the target is too low to reach standing, the body goes down to
## it as a working man's does — by one measure of «effort» (0..1), as little as brings every hand within reach:
## the trunk leans forward (mostly at the hips, the rest in the lower back), the hips go back under it and down, the
## knees give — the feet stay exactly where they stand.
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
var max_lean_deg: float = 65.0  # the trunk's lean at full effort
var hip_share: float = 0.7      # of the lean at the hips, the rest in the lower back
var hinge_k: float = 0.3       # the hips go back by this share of the trunk's forward reach
var squat_k: float = 0.08       # at full effort the hips are lower by this share of the leg's length
var reach_k: float = 0.97       # of the arm's length: never quite straight
var effort_now: float = 0.0     # 0..1, the last frame's (tests)
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
	# the body: the least effort that brings every goal within the arm's reach
	if spine >= 0 and hips >= 0 and legs.size() == 2:
		var f := _frame(sk, inv)
		var e := 0.0
		if not _reachable(sk, goals, f, 0.0):
			var lo := 0.0
			var hi := 1.0
			for i in 10:
				var mid := (lo + hi) * 0.5
				if _reachable(sk, goals, f, mid):
					hi = mid
				else:
					lo = mid
			e = hi
		effort_now = e
		if e > 0.0005:
			var p := _posture(f, e)
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
	# the arms: a few passes — the grip point turns with the forearm, each pass takes up what the last one left
	for side in goals:
		var b: Array = sides[side]
		var sgn := 1.0 if side == "Left" else -1.0
		var pole := (inv * Vector3(sgn * 0.35, -0.55, -0.75)).normalized()   # the elbow: back, down, a little out
		for pass_i in 4:
			var gh: Transform3D = sk.get_bone_global_pose(int(b[2]))
			var grip: Vector3 = gh * (grip_local.get(side, Vector3.ZERO) as Vector3)
			_reach(sk, int(b[0]), int(b[1]), int(b[2]), gh.origin + ((goals[side] as Vector3) - grip), pole, reach_k)


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


## The body's posture at effort `e` (0..1): the lean at the hips and in the lower back, the hips' shift back and down.
func _posture(f: Dictionary, e: float) -> Dictionary:
	var lean := deg_to_rad(max_lean_deg) * e
	var back := hinge_k * float(f["trunk"]) * sin(lean * hip_share)
	var down := squat_k * float(f["leg"]) * e
	return {"lean": lean, "qh": Quaternion(f["side"] as Vector3, lean * hip_share), "qs": Quaternion(f["side"] as Vector3, lean * (1.0 - hip_share)),
		"shift": (f["fwd"] as Vector3) * -back + (f["up"] as Vector3) * -down}


## Would every goal be within reach of its shoulder at effort `e`?
func _reachable(sk: Skeleton3D, goals: Dictionary, f: Dictionary, e: float) -> bool:
	var p := _posture(f, e)
	var qh: Quaternion = p["qh"]
	var qs: Quaternion = p["qs"]
	var q := qh * qs
	var hp: Vector3 = f["hip_pivot"]
	var sp: Vector3 = f["spine_pivot"]
	for side in goals:
		if bool(helping.get(side, false)):
			continue
		var b: Array = sides[side]
		var s0: Vector3 = sk.get_bone_global_pose(int(b[0])).origin
		var e0: Vector3 = sk.get_bone_global_pose(int(b[1])).origin
		var h0: Transform3D = sk.get_bone_global_pose(int(b[2]))
		var arm_len := (e0 - s0).length() + (h0.origin - e0).length()
		var s1: Vector3 = hp + (p["shift"] as Vector3) + qh * ((sp + qs * (s0 - sp)) - hp)
		# the wrist's goal: the grip's goal less the hand's own length to its grip (turned with the body)
		var wrist_goal: Vector3 = (goals[side] as Vector3) - q * (h0 * (grip_local.get(side, Vector3.ZERO) as Vector3) - h0.origin)
		if (wrist_goal - s1).length() > arm_len * reach_k:
			return false
	return true


## Two-bone reach: the end bone's origin to `goal`, the middle joint on the `pole` side; never straighter than `max_k`
## of the two bones' length.
func _reach(sk: Skeleton3D, a: int, f: int, h: int, goal: Vector3, pole: Vector3, max_k: float) -> void:
	var ga: Transform3D = sk.get_bone_global_pose(a)
	var s := ga.origin
	var e: Vector3 = sk.get_bone_global_pose(f).origin
	var hp: Vector3 = sk.get_bone_global_pose(h).origin
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
	var h2: Vector3 = sk.get_bone_global_pose(h).origin
	sk.set_bone_global_pose(f, Transform3D(Basis(Quaternion((h2 - gf.origin).normalized(), (g2 - gf.origin).normalized())) * gf.basis, gf.origin))
