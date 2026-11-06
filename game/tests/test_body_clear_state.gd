extends SceneTree
## Regression checks for repeated skeleton passes and the diagnostic clearing switch (06.11, 21:16: the reviewing AI).
## godot --headless --path game -s res://tests/test_body_clear_state.gd


class TestClear extends "res://scripts/actors/body_clear_modifier.gd":
	# Keep a known penetration and target so the emergency catch path is exercised independently of mesh geometry.
	func _want(_sk: Skeleton3D, _i: int, _g: Transform3D) -> Array:
		return [Vector3(0, 0, 0.3) if enabled else Vector3.ZERO, 3.0]

	func _points(_sk: Skeleton3D, _i: int) -> Array:
		return [[Vector3.ZERO, 0.0]]

	func depth_at(_sk: Skeleton3D, _p: Vector3) -> Array:
		return [3.0, Vector3.RIGHT]


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var sk := Skeleton3D.new()
	root.add_child(sk)
	for bone_name in ["ArmL", "ForeL", "HandL", "ArmR", "ForeR", "HandR"]:
		sk.add_bone(bone_name)
	var bc := TestClear.new()
	sk.add_child(bc)
	bc._arm = [[0, 1, 2], [3, 4, 5]]
	bc._unit = 100.0
	bc.snap = false
	var initial_rotation := Vector3(0, 0, 0.1)
	var initial_velocity := Vector3(0, 0, 0.2)
	bc._rot = [initial_rotation, initial_rotation]
	bc._rot_v = [initial_velocity, initial_velocity]
	bc._process_modification_with_delta(0.0)
	for side in 2:
		_check((bc._rot[side] as Vector3).is_equal_approx(initial_rotation), "Zero-time pass changed the clearing rotation")
		_check((bc._rot_v[side] as Vector3).is_equal_approx(initial_velocity), "Zero-time pass changed the clearing velocity")

	# SkeletonModifier3D restores the input pose between passes. Recreate that boundary for these direct calls.
	sk.reset_bone_poses()
	bc._rot = [initial_rotation, initial_rotation]
	bc._rot_v = [initial_velocity, initial_velocity]
	bc._process_modification_with_delta(1.0 / 60.0)
	for side in 2:
		_check(is_equal_approx((bc._rot[side] as Vector3).length(), deg_to_rad(bc.max_deg)), "Timed catch did not reach its capped target")
		_check((bc._rot_v[side] as Vector3).is_zero_approx(), "Timed catch retained stale velocity")

	bc.enabled = false
	bc._rot = [initial_rotation, initial_rotation]
	bc._rot_v = [initial_velocity, initial_velocity]
	sk.reset_bone_poses()
	bc._process_modification_with_delta(0.0)
	for side in 2:
		_check((bc._rot[side] as Vector3).is_zero_approx(), "Disabled clearing retained a rotation")
		_check((bc._rot_v[side] as Vector3).is_zero_approx(), "Disabled clearing retained velocity")
		_check(sk.get_bone_pose_rotation(bc._arm[side][0]).is_equal_approx(Quaternion.IDENTITY), "Disabled clearing changed the skeleton")
		_check(is_equal_approx(bc.depth_m[side], 0.03), "Disabled clearing lost the input penetration diagnostic")
		_check(is_equal_approx(bc.shown_m[side], 0.03), "Disabled clearing lost the output penetration diagnostic")

	# Explicit placement still initializes the correction even without a time step.
	bc.enabled = true
	bc.snap = true
	sk.reset_bone_poses()
	bc._process_modification_with_delta(0.0)
	_check(is_equal_approx((bc._rot[0] as Vector3).length(), deg_to_rad(bc.max_deg)), "Explicit snap stopped initializing the correction")
	if failures.is_empty():
		print("PASS BodyClear zero-time, catch velocity, disabled diagnostics and placement snap")
	else:
		for message in failures:
			push_error(message)
	quit(0 if failures.is_empty() else 1)
