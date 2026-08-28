class_name LimbKinematics
extends RefCounted

## Allocation-light geometric helpers shared by authored limb previews and physical ML bodies.
##
## This module deliberately contains no gait, target selection, ground probing, or body movement.
## Learned workers own their actuator policy; this code only solves one requested two-segment pose.

const EPSILON := 0.000001
const REACH_MARGIN := 0.01


## Reusable output for presentation systems that solve the same limbs every frame. Callers own one
## instance per limb and avoid constructing a Dictionary and PackedVector3Array on every update.
## The older return-value APIs below remain intact for editor tools, tests, and ML setup paths.
class TwoBoneSolution:
	var hip := Vector3.ZERO
	var knee := Vector3.ZERO
	var tip := Vector3.ZERO
	var bend_direction := Vector3.RIGHT


static func solve_two_bone(
	hip: Vector3,
	requested_tip: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3
) -> PackedVector3Array:
	return solve_two_bone_continuous(
		hip,
		requested_tip,
		upper_length,
		lower_length,
		bend_hint,
		Vector3.ZERO,
		requested_tip - hip
	).get("points", PackedVector3Array())


## Solves the same pose while preserving the preceding bend hemisphere near singularities.
## The dictionary also exposes the selected bend direction so a caller can reuse it next frame.
static func solve_two_bone_continuous(
	hip: Vector3,
	requested_tip: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3,
	previous_bend: Vector3,
	fallback_direction: Vector3
) -> Dictionary:
	var solution := TwoBoneSolution.new()
	solve_two_bone_into(
		solution,
		hip,
		requested_tip,
		upper_length,
		lower_length,
		bend_hint,
		previous_bend,
		fallback_direction
	)
	return {
		"points": PackedVector3Array([
			solution.hip,
			solution.knee,
			solution.tip,
		]),
		"bend_direction": solution.bend_direction,
	}


## Allocation-free form of [method solve_two_bone_continuous]. The output object must be retained
## by the caller; its four fields are overwritten completely on every invocation.
static func solve_two_bone_into(
	output: TwoBoneSolution,
	hip: Vector3,
	requested_tip: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3,
	previous_bend: Vector3,
	fallback_direction: Vector3
) -> void:
	if output == null:
		return
	var upper := maxf(upper_length, 0.001)
	var lower := maxf(lower_length, 0.001)
	var offset := requested_tip - hip
	var raw_distance := offset.length()
	var direction := offset.normalized() if raw_distance > 0.0001 else Vector3.ZERO
	if direction.length_squared() <= EPSILON:
		direction = fallback_direction.normalized()
	if direction.length_squared() <= EPSILON:
		direction = Vector3.DOWN

	var maximum_reach := maxf(upper + lower - REACH_MARGIN, 0.001)
	var minimum_reach := minf(
		absf(upper - lower) + REACH_MARGIN,
		maximum_reach
	)
	var distance := clampf(raw_distance, minimum_reach, maximum_reach)
	var tip := hip + direction * distance
	var along := (
		upper * upper - lower * lower + distance * distance
	) / maxf(2.0 * distance, 0.001)
	var perpendicular_height := sqrt(
		maxf(upper * upper - along * along, 0.0)
	)

	var authored_perpendicular := _project_perpendicular(
		bend_hint,
		direction
	)
	var previous_perpendicular := _project_perpendicular(
		previous_bend,
		direction
	)
	var perpendicular := Vector3.ZERO

	if previous_perpendicular.length_squared() > EPSILON:
		previous_perpendicular = previous_perpendicular.normalized()
		if authored_perpendicular.length_squared() > EPSILON:
			authored_perpendicular = authored_perpendicular.normalized()
			if authored_perpendicular.dot(previous_perpendicular) < 0.0:
				authored_perpendicular = -authored_perpendicular
			perpendicular = (
				previous_perpendicular * 0.85
				+ authored_perpendicular * 0.15
			).normalized()
		else:
			perpendicular = previous_perpendicular
	elif authored_perpendicular.length_squared() > EPSILON:
		perpendicular = authored_perpendicular.normalized()
	else:
		perpendicular = _project_perpendicular(
			fallback_direction,
			direction
		)
		if perpendicular.length_squared() <= EPSILON:
			perpendicular = _least_parallel_axis(direction)
		perpendicular = _project_perpendicular(
			perpendicular,
			direction
		).normalized()

	output.hip = hip
	output.knee = (
		hip
		+ direction * along
		+ perpendicular * perpendicular_height
	)
	output.tip = tip
	output.bend_direction = perpendicular


## Produces a HingeJoint3D frame whose local Z axis follows the solved knee hinge.
static func create_knee_joint_basis(rest_points: PackedVector3Array) -> Basis:
	if rest_points.size() != 3:
		return Basis.IDENTITY
	var upper_direction := (rest_points[1] - rest_points[0]).normalized()
	var lower_direction := (rest_points[2] - rest_points[1]).normalized()
	var hinge_axis := upper_direction.cross(lower_direction)
	if hinge_axis.length_squared() <= EPSILON:
		hinge_axis = lower_direction.cross(Vector3.UP)
	if hinge_axis.length_squared() <= EPSILON:
		hinge_axis = lower_direction.cross(Vector3.RIGHT)
	var lower_basis := basis_from_y(lower_direction)
	var local_hinge_axis := (lower_basis.inverse() * hinge_axis).normalized()
	var local_x := Vector3.UP.cross(local_hinge_axis)
	if local_x.length_squared() <= EPSILON:
		return Basis.IDENTITY
	local_x = local_x.normalized()
	var local_y := local_hinge_axis.cross(local_x).normalized()
	return Basis(local_x, local_y, local_hinge_axis).orthonormalized()


static func basis_from_y(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	if y_axis.length_squared() <= EPSILON:
		y_axis = Vector3.UP
	var reference := (
		Vector3.FORWARD
		if absf(y_axis.dot(Vector3.FORWARD)) < 0.94
		else Vector3.RIGHT
	)
	var x_axis := y_axis.cross(reference).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


static func _project_perpendicular(vector: Vector3, direction: Vector3) -> Vector3:
	return vector - direction * vector.dot(direction)


static func _least_parallel_axis(direction: Vector3) -> Vector3:
	var x_alignment := absf(direction.dot(Vector3.RIGHT))
	var y_alignment := absf(direction.dot(Vector3.UP))
	var z_alignment := absf(direction.dot(Vector3.FORWARD))
	if x_alignment <= y_alignment and x_alignment <= z_alignment:
		return Vector3.RIGHT
	if y_alignment <= z_alignment:
		return Vector3.UP
	return Vector3.FORWARD
