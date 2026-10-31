extends SkeletonModifier3D
## Boots that stand like boots (Director 31.10, 02:14: «сапоги с задёрнутыми носами»; «плывёт»): the clips were
## captured on a flat-footed body and put on a model in heeled leather boots. In the stance the ankle was 4 cm above
## its place in the boot (the soles 5–7 cm off the floor) and the foot turned up 26° against the toe joint, so the
## boot bent at the ball and its toe curled up; walking, the toe joint folded the stiff boot like a slipper. After
## the foot IK (which puts the ankle where it belongs): a boot set down takes the foot's pose it was made in (sole flat
## on the floor), turned only about the vertical as the clip turns it; and the toe joint keeps `toe_keep` of the
## clip's bend from its rest (a stiff boot), set down or not. Weights per foot from Actor3D (0..1 — set down).

var foot_bones: Array = []       # [left foot, right foot]
var toe_bones: Array = []
var rest_foot: Array = []        # skeleton-space rest Basis of each foot
var rest_heading: Array = []     # rest foot→toe direction on the floor (skeleton space, unit)
var rest_toe_rot: Array = []     # each toe bone's rest local rotation
var up := Vector3.UP             # the floor's up in skeleton space
var weights: Array = [0.0, 0.0]
var toe_keep: float = 0.35


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or foot_bones.size() < 2:
		return
	for i in 2:
		var f: int = foot_bones[i]
		var t: int = toe_bones[i]
		if t >= 0 and toe_keep < 1.0:
			var q: Quaternion = sk.get_bone_pose_rotation(t)
			sk.set_bone_pose_rotation(t, (rest_toe_rot[i] as Quaternion).slerp(q, toe_keep))
		var w: float = weights[i]
		if w <= 0.001 or f < 0 or t < 0:
			continue
		var g: Transform3D = sk.get_bone_global_pose(f)
		var toe_now: Vector3 = sk.get_bone_global_pose(t).origin - g.origin
		var h_now := (toe_now - up * toe_now.dot(up))
		if h_now.length() < 1e-5:
			continue
		var h_rest: Vector3 = rest_heading[i]
		var ang := h_rest.signed_angle_to(h_now.normalized(), up)
		var want := Basis(up, ang) * (rest_foot[i] as Basis)
		var qa := Quaternion(g.basis.orthonormalized())
		var qb := Quaternion(want.orthonormalized())
		var s := g.basis.get_scale()
		var nb := Basis(qa.slerp(qb, clampf(w, 0.0, 1.0))).scaled(s)
		sk.set_bone_global_pose(f, Transform3D(nb, g.origin))
