extends SkeletonModifier3D
## Arms that swing like a walking girl's, not a doll's (Director 31.10, 02:14 «движения как живые максимально»): the
## walk clip (Walking_Woman) carries the swinging arm out from the body (30–34° in the frontal plane at the forward
## swing, against 11–14° standing), bends the elbow up to 74° — the forearm comes up nearly level, a paw held out — and
## flicks the hand back at the wrist (up to 39°). Measured arm swing in walking bends the elbow through about 30°
## (29.7 ± 10.2°, Clin Shoulder Elb 2023). Walking (weight = the shown walk), after the clip and the breathing, before
## the joint limiter and the arm IK: the upper arm is brought in towards the side (keeping `abd_keep` of its spread
## over the standing one), the elbow and the wrist keep `elbow_keep` / `wrist_keep` of their bend from the bind pose
## (arms down, elbows 24–27° bent). Data rt3d.walk.arm_tone.

var arm_bones: Array = []       # [left upper arm, right upper arm]
var fore_bones: Array = []
var hand_bones: Array = []
var rest_fore: Array = []       # bind local rotations (Quaternion)
var rest_hand: Array = []
var to_model := Basis.IDENTITY  # skeleton space → model space (x across: + her left, y up, z forward)
var abd_ref: Array = [0.2, 0.2] # standing spread of each upper arm in the frontal plane (rad)
var weight: float = 0.0
var elbow_keep: float = 0.55
var wrist_keep: float = 0.5
var abd_keep: float = 0.5


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or arm_bones.size() < 2 or weight <= 0.001:
		return
	var w := clampf(weight, 0.0, 1.0)
	for i in 2:
		var a: int = arm_bones[i]
		var f: int = fore_bones[i]
		var h: int = hand_bones[i]
		if a < 0 or f < 0:
			continue
		# the upper arm in towards the side: only its spread out of the body's side plane, its swing kept
		var g: Transform3D = sk.get_bone_global_pose(a)
		var d: Vector3 = sk.get_bone_global_pose(f).origin - g.origin
		var dm := to_model * d
		var sgn := 1.0 if i == 0 else -1.0
		var rxy := Vector2(dm.x, dm.y).length()
		if rxy > 1e-5:
			var phi := atan2(sgn * dm.x, -dm.y)
			var ref: float = abd_ref[i]
			if phi > ref:
				var keep := lerpf(1.0, abd_keep, w)
				var phi2 := ref + (phi - ref) * keep
				var dm2 := Vector3(sgn * rxy * sin(phi2), -rxy * cos(phi2), dm.z)
				var d2 := to_model.inverse() * dm2
				var q := Quaternion(d.normalized(), d2.normalized())
				var s := g.basis.get_scale()
				var nb := Basis(q * Quaternion(g.basis.orthonormalized())).scaled(s)
				sk.set_bone_global_pose(a, Transform3D(nb, g.origin))
		# the elbow and the wrist: part of their bend from the bind pose
		sk.set_bone_pose_rotation(f, (rest_fore[i] as Quaternion).slerp(sk.get_bone_pose_rotation(f), lerpf(1.0, elbow_keep, w)))
		if h >= 0:
			sk.set_bone_pose_rotation(h, (rest_hand[i] as Quaternion).slerp(sk.get_bone_pose_rotation(h), lerpf(1.0, wrist_keep, w)))
