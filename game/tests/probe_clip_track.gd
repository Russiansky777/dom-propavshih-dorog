extends SceneTree
## A clip's course over time: hips height, the lower hand's height and reach forward, the knees' bend — to pick the part
## of a clip an action plays (where the hand is lowest, how long the way down and up takes).
##   godot --headless --path game -s res://tests/probe_clip_track.gd -- <actor id> <clip name> [step s]

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % a[0]))
	var v := Actor3D.new()
	root.add_child(v)
	v.setup(spec)
	if v.life != null:
		v.life.active = false
	var nm := ""
	for an in v.anim.get_animation_list():
		if String(an).ends_with(a[1]):
			nm = an
	var L := v.anim.get_animation(nm).length
	var step := float(a[2]) if a.size() > 2 else 0.2
	var bt := v.tree.tree_root as AnimationNodeBlendTree
	(bt.get_node("idle_a") as AnimationNodeAnimation).animation = nm
	var t := 0.0
	while t <= L:
		v.tree.set("parameters/idle_a_seek/seek_request", minf(t, L - 0.001))
		v.tree.set("parameters/idle_mix/blend_amount", 0.0)
		v.tree.set("parameters/loco/blend_amount", 0.0)
		v.tree.set("parameters/actb/blend_amount", 0.0)
		v.model.position = Vector3.ZERO
		v.tree.advance(0.0)
		var h := v.bone_model("Hips")
		var lh := v.bone_model("LeftHand")
		var rh := v.bone_model("RightHand")
		var hand := lh if lh.y < rh.y else rh
		var k := [v.bone_model("LeftUpLeg"), v.bone_model("LeftLeg"), v.bone_model("LeftFoot")]
		var knee := rad_to_deg(((k[1] as Vector3) - (k[0] as Vector3)).angle_to((k[2] as Vector3) - (k[1] as Vector3)))
		var head := v.bone_model("Head")
		print("%5.2f hips %3.0f cm  hand %s %3.0f cm, fwd %+3.0f, side %+3.0f  knee %3.0f°  head %3.0f cm" % [t, h.y * 100, "L" if lh.y < rh.y else "R", hand.y * 100, hand.z * 100, hand.x * 100, knee, head.y * 100])
		t += step
	quit(0)
