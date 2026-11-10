extends SkeletonModifier3D
## An acting arm lowered or raised (Director 09.11, 22:18: «она пишет невпопад… должна во время анимации написания на
## доске и в том же месте»): the write_board clip holds the chalk at head height (1.4 m), and Nina's answer on the
## board is at chest height (1.0 m), the date above her head (1.7 m) — one clip, three heights. While that one-shot
## action is shown, the upper arm of `side` is turned towards straight down by `drop_deg` (in the plane of the arm —
## shoulder to wrist — and the vertical; − raises it), weighted by how much the action is shown — it comes and goes
## with the clip. NpcLive3D.set_act_arm (stage data npc_act[].arm {side, drop_deg}); before BodyClear in the
## skeleton's modifiers.

const ArmRest := preload("res://scripts/actors/arm_rest.gd")

var bone: int = -1
var hand: int = -1
var hips: int = -1
var up_local := Vector3.UP       # the body's up in the hips' own frame
var angle: float = 0.0
var weight: float = 0.0
var clip: String = ""            # the action it belongs to (NpcLive3D)


func setup(sk: Skeleton3D, side: String, drop_deg: float, for_clip: String) -> bool:
	bone = sk.find_bone(side + "Arm")
	hand = sk.find_bone(side + "Hand")
	hips = sk.find_bone("Hips")
	var ax := ArmRest.axes(sk)
	if bone < 0 or hand < 0 or hips < 0 or ax.is_empty():
		bone = -1
		return false
	up_local = ax[0]
	angle = deg_to_rad(drop_deg)
	clip = for_clip
	return true


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or bone < 0 or absf(angle * weight) < 1e-4:
		return
	var g := sk.get_bone_global_pose(bone)
	var d: Vector3 = sk.get_bone_global_pose(hand).origin - g.origin
	var down: Vector3 = -(sk.get_bone_global_pose(hips).basis.orthonormalized() * up_local)
	var axis := d.cross(down)
	if axis.length() < 1e-5:
		return   # the arm hangs straight down already (or points straight up)
	sk.set_bone_global_pose(bone, Transform3D(Basis(axis.normalized(), angle * clampf(weight, 0.0, 1.0)) * g.basis, g.origin))
