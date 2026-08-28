extends SceneTree

const EPSILON := 0.001

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_segment_lengths_and_reach_clamp()
	_test_authored_bend_and_continuity()
	_test_reusable_solution_output()
	_test_knee_joint_frame()
	_test_degenerate_pose_remains_finite()
	if failure_count == 0:
		print("Limb kinematics tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Limb kinematics tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_segment_lengths_and_reach_clamp() -> void:
	var hip := Vector3(0.0, 1.0, 0.0)
	var points := LimbKinematics.solve_two_bone(
		hip,
		Vector3(1.3, 0.0, 0.45),
		1.2,
		1.05,
		Vector3.UP
	)
	_expect(points.size() == 3, "solver returns hip, knee, and tip")
	_expect(
		absf(points[0].distance_to(points[1]) - 1.2) < EPSILON,
		"upper segment length is preserved"
	)
	_expect(
		absf(points[1].distance_to(points[2]) - 1.05) < EPSILON,
		"lower segment length is preserved"
	)
	var unreachable := LimbKinematics.solve_two_bone(
		Vector3.ZERO,
		Vector3(100.0, 0.0, 0.0),
		1.0,
		1.0,
		Vector3.UP
	)
	_expect(
		unreachable[2].length() < 2.0,
		"an unreachable tip is clamped inside total limb reach"
	)


func _test_authored_bend_and_continuity() -> void:
	var first := LimbKinematics.solve_two_bone_continuous(
		Vector3.ZERO,
		Vector3(0.02, -1.9, 0.0),
		1.0,
		1.0,
		Vector3.RIGHT,
		Vector3.RIGHT,
		Vector3.DOWN
	)
	var first_bend: Vector3 = first.get("bend_direction", Vector3.ZERO)
	var second := LimbKinematics.solve_two_bone_continuous(
		Vector3.ZERO,
		Vector3(-0.02, -1.9, 0.0),
		1.0,
		1.0,
		Vector3.LEFT,
		first_bend,
		Vector3.DOWN
	)
	var second_bend: Vector3 = second.get("bend_direction", Vector3.ZERO)
	_expect(
		first_bend.dot(Vector3.RIGHT) > 0.99,
		"authored bend selects the requested knee hemisphere"
	)
	_expect(
		first_bend.dot(second_bend) > 0.95,
		"previous bend prevents a near-singular knee hemisphere flip"
	)


func _test_knee_joint_frame() -> void:
	var points := LimbKinematics.solve_two_bone(
		Vector3.ZERO,
		Vector3(0.6, -1.4, 0.35),
		1.0,
		0.9,
		Vector3.RIGHT
	)
	var frame := LimbKinematics.create_knee_joint_basis(points)
	_expect(
		absf(frame.determinant() - 1.0) < 0.0001,
		"knee hinge frame is orthonormal"
	)
	_expect(
		absf(frame.x.dot(frame.z)) < 0.0001
		and absf(frame.y.dot(frame.z)) < 0.0001,
		"hinge axis is perpendicular to both local frame axes"
	)


func _test_reusable_solution_output() -> void:
	var output := LimbKinematics.TwoBoneSolution.new()
	LimbKinematics.solve_two_bone_into(
		output,
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.3, 0.1, -0.2),
		0.7,
		0.65,
		Vector3.FORWARD,
		Vector3.FORWARD,
		Vector3.DOWN
	)
	var first_identity := output
	var first_bend := output.bend_direction
	LimbKinematics.solve_two_bone_into(
		output,
		Vector3(0.0, 1.0, 0.0),
		Vector3(-0.2, 0.05, -0.25),
		0.7,
		0.65,
		Vector3.FORWARD,
		first_bend,
		Vector3.DOWN
	)
	_expect(
		output == first_identity
		and absf(output.hip.distance_to(output.knee) - 0.7) < EPSILON
		and absf(output.knee.distance_to(output.tip) - 0.65) < EPSILON,
		"reusable two-bone output is overwritten in place without changing solver geometry"
	)


func _test_degenerate_pose_remains_finite() -> void:
	var points := LimbKinematics.solve_two_bone(
		Vector3.ZERO,
		Vector3.ZERO,
		0.0,
		0.0,
		Vector3.ZERO
	)
	_expect(points.size() == 3, "degenerate input still returns a complete pose")
	for point: Vector3 in points:
		_expect(_is_finite_vector(point), "degenerate pose coordinates remain finite")


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % description)
		return
	failure_count += 1
	push_error("[FAIL] %s" % description)
