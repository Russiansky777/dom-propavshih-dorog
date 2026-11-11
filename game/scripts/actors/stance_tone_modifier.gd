extends SkeletonModifier3D
## Standing arms at the sides, shoulders let down (Director 10.11, 16:15: «Пелагея какая-то скукоженная… пересмотреть их
## обоих руки, что они не вытянуты вперёд, уже говорили»). Measured in the stance as the game shows it
## (tests/probe_posture.gd): the villagers' upper arms hang 15–18° forward of straight down, Mitya's 26–28°; the forearms
## 30–44° forward; the hands 9–19 cm in front of the hips; Pelageya's and Mitya's shoulders stand 1,3–2,2 cm above the
## model's own bind pose. A relaxed arm hangs beside the thigh.
## Standing (weight = not walking, no one-shot action), after the clip and the breathing, before the joint limiter and
## the clothes' clearance (BodyClear still keeps the hands out of the skirt): the clavicles turn down by
## `shoulder_drop_deg`; a hanging upper arm is brought back to `upper_fwd_deg` forward of straight down; the elbow keeps
## `elbow_keep` of its bend. An arm lifted in a gesture does not hang and is left alone. Data rt3d.stance_tone.

var shoulder_bones: Array = []  # [left clavicle, right clavicle]
var arm_bones: Array = []       # [left upper arm, right upper arm]
var fore_bones: Array = []
var hand_bones: Array = []
var to_model := Basis.IDENTITY  # skeleton space → model space (x across: + her left, y up, z forward)
var weight: float = 0.0
var upper_fwd_deg: float = 6.0
var elbow_keep: float = 1.0
var shoulder_drop_deg: float = 0.0
## The hanging arm's sideways angle from straight down (frontal plane, + away from the body): shifted by
## `spread_add_deg`, then kept within [spread_min_deg, spread_max_deg]. Director 10.11, 17:28 («у Пелагеи руки
## проваливаются»): brought back to the side, the hand hangs by the hip, which is wider than the belly it hung in
## front of — the arm needs its room there (the first version also turned the arm in with the clavicle: her right
## arm went to −5°, into the skirt).
var spread_add_deg: float = 0.0
var spread_min_deg: float = -90.0
var spread_max_deg: float = 90.0
## Director 10.11, 22:15 («Павел… чуть сутулый»): standing, the upper chest straightens back by `chest_up_deg` (about
## the body's side axis, at the chest bone), the neck turns the same amount forward so the head keeps where it looked;
## the arms are set after it. 0 — as the clip has it.
var chest_bone: int = -1
var neck_bone: int = -1
var chest_up_deg: float = 0.0


## How much an upper arm hangs (0..1) from its direction in model space: fully within ~35° of straight down, not at
## all past ~55° (ArmRest.spread_of's measure).
static func hang_of(dm: Vector3) -> float:
	return smoothstep(0.57, 0.82, -dm.normalized().y)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or arm_bones.size() < 2 or weight <= 0.001:
		return
	var w := clampf(weight, 0.0, 1.0)
	var inv := to_model.inverse()
	var ax_fwd := (inv * Vector3(0, 0, 1)).normalized()
	var ax_side := (inv * Vector3(1, 0, 0)).normalized()
	if chest_bone >= 0 and absf(chest_up_deg) > 0.01:
		# + chest_up_deg: the chest goes back (its top away from the front), the head is turned back as it was
		var gc: Transform3D = sk.get_bone_global_pose(chest_bone)
		var head_before: Basis = sk.get_bone_global_pose(neck_bone).basis if neck_bone >= 0 else Basis.IDENTITY
		var qc := Quaternion(ax_side, -deg_to_rad(chest_up_deg) * w)
		sk.set_bone_global_pose(chest_bone, Transform3D(Basis(qc) * gc.basis, gc.origin))
		if neck_bone >= 0:
			var gn: Transform3D = sk.get_bone_global_pose(neck_bone)
			sk.set_bone_global_pose(neck_bone, Transform3D(head_before, gn.origin))
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		var a: int = arm_bones[i]
		var f: int = fore_bones[i]
		var h: int = hand_bones[i]
		if a < 0 or f < 0:
			continue
		var hang := hang_of(to_model * (sk.get_bone_global_pose(f).origin - sk.get_bone_global_pose(a).origin))
		if hang <= 0.001:
			continue
		# the clavicle down: about the body's forward axis, the arm's joint lower — the arm itself keeps its direction
		var s: int = shoulder_bones[i]
		if s >= 0 and absf(shoulder_drop_deg) > 0.01:
			var gs: Transform3D = sk.get_bone_global_pose(s)
			var qs := Quaternion(ax_fwd, -sgn * deg_to_rad(shoulder_drop_deg) * w * hang)
			sk.set_bone_global_pose(s, Transform3D(Basis(qs) * gs.basis, gs.origin))
			var g0: Transform3D = sk.get_bone_global_pose(a)
			sk.set_bone_global_pose(a, Transform3D(Basis(qs.inverse()) * g0.basis, g0.origin))
		# the upper arm back to the side: about the body's side axis
		var ga: Transform3D = sk.get_bone_global_pose(a)
		var dm: Vector3 = to_model * (sk.get_bone_global_pose(f).origin - ga.origin)
		var phi := atan2(dm.z, -dm.y)
		var target := deg_to_rad(upper_fwd_deg)
		if phi > target:
			var qa := Quaternion(ax_side, (phi - target) * w * hang)
			sk.set_bone_global_pose(a, Transform3D(Basis(qa) * ga.basis, ga.origin))
		# its sideways angle: shifted and kept in its room, about the body's forward axis
		ga = sk.get_bone_global_pose(a)
		dm = to_model * (sk.get_bone_global_pose(f).origin - ga.origin)
		var sp := atan2(sgn * dm.x, -dm.y)
		var sp_to := clampf(sp + deg_to_rad(spread_add_deg), deg_to_rad(spread_min_deg), deg_to_rad(spread_max_deg))
		if absf(sp_to - sp) > 0.0005:
			var qv := Quaternion(ax_fwd, sgn * (sp_to - sp) * w * hang)
			sk.set_bone_global_pose(a, Transform3D(Basis(qv) * ga.basis, ga.origin))
		# the elbow: part of its bend
		if h >= 0 and elbow_keep < 0.999:
			var p0: Vector3 = sk.get_bone_global_pose(a).origin
			var gf: Transform3D = sk.get_bone_global_pose(f)
			var ua := (gf.origin - p0).normalized()
			var fa := (sk.get_bone_global_pose(h).origin - gf.origin).normalized()
			var ang := ua.angle_to(fa)
			var axe := ua.cross(fa)
			if ang > 0.002 and axe.length_squared() > 1e-10:
				var qf := Quaternion(axe.normalized(), -ang * (1.0 - elbow_keep) * w * hang)
				sk.set_bone_global_pose(f, Transform3D(Basis(qf) * gf.basis, gf.origin))
