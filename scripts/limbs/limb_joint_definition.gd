@tool
class_name LimbJointDefinition
extends Resource

#######################################################
# One joint in a generic serial limb. The frame and rest pose are authored in creature/core-local
# space. Segment 0 connects to the core; every later segment connects to the preceding segment.
#
# Jolt's SixDOF decomposition treats joint-local X as twist. Joint-local Y and Z are the two swing
# axes. Generic limbs keep that convention instead of inventing a second axis interpretation.
#######################################################

@export var joint_name := "Joint"
@export var joint_basis_local := Basis.IDENTITY
@export var lower_limit_degrees := Vector3.ZERO
@export var upper_limit_degrees := Vector3.ZERO
# Hardware control capability is separate from the dense model action mapping. Existing resources
# that already carry action_indices remain valid; new body-creator parts should set controlled_axes
# and let the accepted body build assign indices deterministically.
@export var controlled_axes = Vector3i(0, 0, 0)
# Runtime/global action indices for joint-local X/Y/Z. -1 means not mapped in this assembled body.
@export var action_indices := Vector3i(-1, -1, -1)

@export_group("Passive elasticity")
# This permanent parallel spring is the rubber-noodle/rest-pose behavior. It exists even when no
# policy command is present. The explicit controller is authoritative because its target frame,
# torque cap, health scaling, and telemetry are deterministic across physics backends.
@export var passive_stiffness := Vector3(130.0, 130.0, 130.0)
@export var passive_damping := Vector3(18.0, 18.0, 18.0)
@export var maximum_passive_torque := Vector3(420.0, 420.0, 420.0)
# Optional per-axis reference span for passive hardening/yield. Zero derives the span from the hard
# limits as before. This lets an asymmetric recovery extension keep the established neutral support
# behavior instead of making the ordinary walking side of the joint artificially looser.
@export var passive_reference_span_degrees = Vector3.ZERO
# Past this fraction of the authored angular range, the spring becomes progressively harder. This
# makes the center compliant enough to move while preventing the policy from folding a limb flat.
@export_range(0.0, 0.95, 0.01) var passive_progressive_onset_ratio := 0.40
@export var passive_progressive_ratio := Vector3(5.0, 5.0, 5.0)
# Jolt's native angular spring provides part of the baseline elasticity inside the constraint
# solver. The explicit controller supplies the remaining bounded resistance and nonlinear hardening.
@export var use_native_passive_spring := true
# A modest portion of the linear spring lives inside Jolt's constraint solver. The remaining
# bounded linear resistance and all nonlinear hardening stay in LimbsController3D. This hybrid
# keeps the chain load-bearing even during hard contacts without giving up deterministic caps.
@export_range(0.0, 1.0, 0.01) var native_passive_fraction := 0.35

@export_group("Command authority")
@export var active_stiffness := Vector3(210.0, 210.0, 210.0)
@export var active_damping := Vector3(22.0, 22.0, 22.0)
@export var maximum_active_torque := Vector3(320.0, 320.0, 320.0)
# Per-axis permission for the explicit rest-pose spring to yield as a commanded target moves away
# from neutral. Zero preserves the old permanent-rest behavior; one allows the actuator to use the
# full generic yield curve. Native solver elasticity and soft/hard joint limits never yield here.
@export var commanded_passive_yield = Vector3.ZERO
@export_range(0.0, 1440.0, 1.0, "or_greater") var target_response_degrees_per_second := 260.0
# Optional per-axis override. Zero keeps the scalar legacy response for that axis. This lets a
# hardware profile calm one high-leverage axis without slowing useful lift/fold motion elsewhere.
@export var target_response_degrees_per_second_by_axis = Vector3.ZERO
# The policy target stays inside the hard solver stop. The separate soft-limit spring occupies the
# remaining band and prevents saturated actions from continuously hammering the constraint.
@export_range(0.0, 45.0, 0.25) var command_limit_margin_degrees := 4.0

@export_group("Soft limit guard")
@export_range(0.0, 45.0, 0.25) var soft_limit_zone_degrees := 8.0
@export var soft_limit_stiffness := Vector3(320.0, 320.0, 320.0)
@export var soft_limit_damping := Vector3(24.0, 24.0, 24.0)
@export var maximum_soft_limit_torque := Vector3(360.0, 360.0, 360.0)


func sanitize() -> void:
	joint_basis_local = joint_basis_local.orthonormalized()
	for axis in range(3):
		controlled_axes[axis] = 1 if controlled_axes[axis] != 0 or action_indices[axis] >= 0 else 0
		var lower := minf(lower_limit_degrees[axis], upper_limit_degrees[axis])
		var upper := maxf(lower_limit_degrees[axis], upper_limit_degrees[axis])
		lower_limit_degrees[axis] = clampf(lower, -179.0, 179.0)
		upper_limit_degrees[axis] = clampf(upper, -179.0, 179.0)
		passive_stiffness[axis] = maxf(passive_stiffness[axis], 0.0)
		passive_damping[axis] = maxf(passive_damping[axis], 0.0)
		maximum_passive_torque[axis] = maxf(maximum_passive_torque[axis], 0.0)
		passive_reference_span_degrees[axis] = maxf(
			passive_reference_span_degrees[axis],
			0.0
		)
		passive_progressive_ratio[axis] = maxf(passive_progressive_ratio[axis], 0.0)
		active_stiffness[axis] = maxf(active_stiffness[axis], 0.0)
		active_damping[axis] = maxf(active_damping[axis], 0.0)
		maximum_active_torque[axis] = maxf(maximum_active_torque[axis], 0.0)
		commanded_passive_yield[axis] = clampf(commanded_passive_yield[axis], 0.0, 1.0)
		target_response_degrees_per_second_by_axis[axis] = maxf(
			target_response_degrees_per_second_by_axis[axis],
			0.0
		)
		soft_limit_stiffness[axis] = maxf(soft_limit_stiffness[axis], 0.0)
		soft_limit_damping[axis] = maxf(soft_limit_damping[axis], 0.0)
		maximum_soft_limit_torque[axis] = maxf(maximum_soft_limit_torque[axis], 0.0)
	passive_progressive_onset_ratio = clampf(passive_progressive_onset_ratio, 0.0, 0.95)
	native_passive_fraction = clampf(native_passive_fraction, 0.0, 1.0)
	target_response_degrees_per_second = maxf(target_response_degrees_per_second, 0.0)
	soft_limit_zone_degrees = clampf(soft_limit_zone_degrees, 0.0, 45.0)
	command_limit_margin_degrees = clampf(command_limit_margin_degrees, 0.0, 45.0)


func axis_control_declared(axis: int) -> bool:
	return (
		axis >= 0
		and axis < 3
		and (controlled_axes[axis] != 0 or action_indices[axis] >= 0)
	)


func axis_is_actuated(axis: int) -> bool:
	return axis_control_declared(axis) and action_indices[axis] >= 0


func axis_is_free(axis: int) -> bool:
	return (
		axis >= 0
		and axis < 3
		and absf(upper_limit_degrees[axis] - lower_limit_degrees[axis]) > 0.001
	)


func command_limits_radians(axis: int) -> Vector2:
	if not axis_is_free(axis):
		return Vector2.ZERO
	var lower := deg_to_rad(lower_limit_degrees[axis])
	var upper := deg_to_rad(upper_limit_degrees[axis])
	var margin := deg_to_rad(command_limit_margin_degrees)
	margin = minf(margin, maxf(upper - lower, 0.0) * 0.45)
	var safe_lower := lower + margin
	var safe_upper := upper - margin
	# The action contract is centered on the authored zero/rest pose, even for asymmetric knees.
	return Vector2(minf(safe_lower, 0.0), maxf(safe_upper, 0.0))


func required_action_count() -> int:
	var result := 0
	for axis in range(3):
		result = maxi(result, action_indices[axis] + 1)
	return result


func passive_reference_span_radians(axis: int) -> float:
	if axis < 0 or axis >= 3:
		return 0.0
	if passive_reference_span_degrees[axis] > 0.0001:
		return maxf(deg_to_rad(passive_reference_span_degrees[axis]), deg_to_rad(1.0))
	return maxf(
		maxf(
			absf(deg_to_rad(lower_limit_degrees[axis])),
			absf(deg_to_rad(upper_limit_degrees[axis]))
		),
		deg_to_rad(1.0)
	)


func target_response_radians_per_second(axis: int) -> float:
	if axis < 0 or axis >= 3:
		return deg_to_rad(target_response_degrees_per_second)
	var override_degrees: float = target_response_degrees_per_second_by_axis[axis]
	var response_degrees: float = (
		override_degrees
		if override_degrees > 0.0001
		else target_response_degrees_per_second
	)
	return deg_to_rad(maxf(response_degrees, 0.0))
