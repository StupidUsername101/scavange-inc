class_name LimbsController3D
extends Node

# Neutral commands keep the full load-bearing passive spring. As an actuator deliberately moves
# away from rest on an axis that explicitly opts in, only the controller-side passive component
# yields; the native Jolt spring remains untouched inside the constraint solver. This prevents
# rest-pose hardening from overpowering a valid lift/fold command while preserving the exact passive
# standing baseline and leaving unrelated axes unchanged.
const MINIMUM_COMMANDED_EXPLICIT_PASSIVE_SCALE = 0.10

#######################################################
# Generic articulated-limb actuator layer, analogous to the drone flight controller. Policy
# outputs remain direct joint references. A bounded impedance layer converts those references to
# torque while every joint keeps an independent passive return-to-rest spring.
#######################################################


class JointRuntimeParameters:
	extends RefCounted

	var free_axis_mask: int = 0
	var actuated_axis_mask: int = 0
	var action_indices: Vector3i = Vector3i(-1, -1, -1)
	var command_lower_radians: Vector3 = Vector3.ZERO
	var command_upper_radians: Vector3 = Vector3.ZERO
	var lower_limit_radians: Vector3 = Vector3.ZERO
	var upper_limit_radians: Vector3 = Vector3.ZERO
	var passive_reference_spans: Vector3 = Vector3.ONE
	var passive_stiffness: Vector3 = Vector3.ZERO
	var passive_damping: Vector3 = Vector3.ZERO
	var maximum_passive_torque: Vector3 = Vector3.ZERO
	var passive_progressive_ratio: Vector3 = Vector3.ZERO
	var passive_progressive_onset_ratio: float = 0.0
	var native_fraction: float = 0.0
	var active_stiffness: Vector3 = Vector3.ZERO
	var active_damping: Vector3 = Vector3.ZERO
	var maximum_active_torque: Vector3 = Vector3.ZERO
	var commanded_passive_yield: Vector3 = Vector3.ZERO
	var target_response_radians_per_second: Vector3 = Vector3.ZERO
	var soft_limit_zone_radians: float = 0.0
	var soft_limit_stiffness: Vector3 = Vector3.ZERO
	var soft_limit_damping: Vector3 = Vector3.ZERO
	var maximum_soft_limit_torque: Vector3 = Vector3.ZERO


class JointRuntimeRecord:
	extends RefCounted

	var source_record: Dictionary = {}
	var parent: RigidBody3D
	var child: LimbSegment3D
	var rest_relative_basis: Basis = Basis.IDENTITY
	var joint_basis_parent: Basis = Basis.IDENTITY
	var parameters: JointRuntimeParameters

var core_body: RigidBody3D
var limbs: Array[GenericLimb3D] = []
var action_count := 0
var desired_commands := PackedFloat64Array()
var previous_commands := PackedFloat64Array()
var applied_torques := PackedFloat64Array()
var reserved_noop_action_indices := PackedInt32Array()
var action_mapping_valid := true
var active := false
var runtime_joint_records: Array[JointRuntimeRecord] = []
var runtime_end_effectors: Array[LimbEndEffector3D] = []


func configure(
	core: RigidBody3D,
	new_limbs: Array[GenericLimb3D],
	new_action_count: int = -1,
	new_reserved_noop_action_indices: PackedInt32Array = PackedInt32Array()
) -> void:
	core_body = core
	limbs = new_limbs
	action_count = (
		required_action_count_for_limbs(new_limbs)
		if new_action_count < 0
		else maxi(new_action_count, 0)
	)
	reserved_noop_action_indices = new_reserved_noop_action_indices.duplicate()
	action_mapping_valid = has_complete_action_mapping_for_limbs(
		new_limbs,
		action_count,
		reserved_noop_action_indices
	)
	desired_commands.resize(action_count)
	desired_commands.fill(0.0)
	previous_commands = desired_commands.duplicate()
	applied_torques.resize(action_count)
	applied_torques.fill(0.0)
	_build_runtime_records()
	_configure_grip_exclusions()
	set_physics_process(active)


static func required_action_count_for_limbs(chains: Array[GenericLimb3D]) -> int:
	var result := 0
	for limb: GenericLimb3D in chains:
		if is_instance_valid(limb) and limb.definition != null:
			result = maxi(result, limb.definition.required_action_count())
	return result


static func has_unique_action_mapping_for_limbs(chains: Array[GenericLimb3D]) -> bool:
	var seen: Dictionary[int, bool] = {}
	for limb: GenericLimb3D in chains:
		if not is_instance_valid(limb) or limb.definition == null:
			continue
		for segment: LimbSegmentDefinition in limb.definition.segments:
			if segment == null or segment.joint == null:
				continue
			for axis in range(3):
				var action_index := segment.joint.action_indices[axis]
				if action_index < 0:
					continue
				if seen.has(action_index):
					return false
				seen[action_index] = true
		var effector := limb.definition.end_effector
		if effector != null and effector.has_mapped_grip_action():
			if seen.has(effector.grip_action_index):
				return false
			seen[effector.grip_action_index] = true
	return true


static func has_complete_action_mapping_for_limbs(
	chains: Array[GenericLimb3D],
	expected_action_count: int,
	reserved_noop_indices: PackedInt32Array = PackedInt32Array()
) -> bool:
	if expected_action_count < 0:
		return false
	var seen: Dictionary[int, bool] = {}
	for action_index: int in reserved_noop_indices:
		if action_index < 0 or action_index >= expected_action_count or seen.has(action_index):
			return false
		seen[action_index] = true
	for limb: GenericLimb3D in chains:
		if not is_instance_valid(limb) or limb.definition == null:
			continue
		for segment: LimbSegmentDefinition in limb.definition.segments:
			if segment == null or segment.joint == null:
				continue
			for axis in range(3):
				var action_index := segment.joint.action_indices[axis]
				if action_index < 0:
					continue
				if action_index >= expected_action_count or seen.has(action_index):
					return false
				seen[action_index] = true
		var effector := limb.definition.end_effector
		if effector != null and effector.has_mapped_grip_action():
			var grip_index := effector.grip_action_index
			if grip_index >= expected_action_count or seen.has(grip_index):
				return false
			seen[grip_index] = true
	if seen.size() != expected_action_count:
		return false
	for action_index in range(expected_action_count):
		if not seen.has(action_index):
			return false
	return true


func set_active(value: bool) -> void:
	active = value
	set_physics_process(value)


func submit_commands(commands: PackedFloat64Array) -> bool:
	if not action_mapping_valid or commands.size() != action_count:
		return false
	for value in commands:
		if not is_finite(value):
			return false
	for index in range(action_count):
		previous_commands[index] = desired_commands[index]
		desired_commands[index] = clampf(commands[index], -1.0, 1.0)
	return true


func neutralize() -> void:
	for index in range(action_count):
		previous_commands[index] = desired_commands[index]
		desired_commands[index] = 0.0


func _physics_process(delta: float) -> void:
	step_controller(delta)


func step_controller(delta: float) -> void:
	if not active or not is_instance_valid(core_body):
		return
	applied_torques.fill(0.0)
	var safe_delta: float = maxf(delta, 0.0)
	for runtime_record: JointRuntimeRecord in runtime_joint_records:
		_apply_joint(runtime_record, safe_delta)
	for end_effector: LimbEndEffector3D in runtime_end_effectors:
		if is_instance_valid(end_effector):
			end_effector.step_command(safe_delta, desired_commands)


func _apply_joint(runtime_record: JointRuntimeRecord, delta: float) -> void:
	if runtime_record == null:
		return
	var parent: RigidBody3D = runtime_record.parent
	var child: LimbSegment3D = runtime_record.child
	var parameters: JointRuntimeParameters = runtime_record.parameters
	if not is_instance_valid(parent) or not is_instance_valid(child) or parameters == null:
		return

	# Passive elasticity is mechanical/tissue behavior: losing actuator effectiveness does not make
	# the limb a noodle. Physical damage weakens it; actuator damage only weakens policy authority.
	var passive_effectiveness := minf(_body_health_ratio(parent), child.health_ratio())
	var active_effectiveness := minf(_body_functional_ratio(parent), child.functional_ratio())
	if passive_effectiveness <= 0.0 and active_effectiveness <= 0.0:
		return

	var source_record: Dictionary = runtime_record.source_record
	var rest_relative: Basis = runtime_record.rest_relative_basis
	var joint_basis_parent: Basis = runtime_record.joint_basis_parent
	var parent_basis: Basis = parent.global_basis
	var parent_basis_inverse: Basis = parent_basis.inverse()
	var current_relative: Basis = (parent_basis_inverse * child.global_basis).orthonormalized()
	var current_angles := joint_angles(current_relative, rest_relative, joint_basis_parent)
	var target_angles: Vector3 = source_record.get("smoothed_target_angles", Vector3.ZERO)
	var desired_targets := Vector3.ZERO
	for axis in range(3):
		var axis_bit: int = 1 << axis
		if (parameters.actuated_axis_mask & axis_bit) == 0:
			continue
		var action_index: int = parameters.action_indices[axis]
		if action_index < 0 or action_index >= desired_commands.size():
			continue
		desired_targets[axis] = normalized_target(
			desired_commands[action_index],
			parameters.command_lower_radians[axis],
			parameters.command_upper_radians[axis]
		)
		target_angles[axis] = move_toward(
			target_angles[axis],
			desired_targets[axis],
			parameters.target_response_radians_per_second[axis] * delta
		)

	# Keep the known-good standing controller in physical rotation space. For a multi-axis joint,
	# the exact shortest relative rotation is not generally the component-wise difference between
	# two swing/twist coordinate vectors. Project the physical quaternion error onto the joint axes,
	# and expose those exact projected values as diagnostics below.
	var active_delta := rotation_from_joint_angles(target_angles, joint_basis_parent)
	var active_desired_relative := (active_delta * rest_relative).orthonormalized()
	var passive_error_parent := rotation_error_vector_parent(current_relative, rest_relative)
	var active_error_parent := rotation_error_vector_parent(
		current_relative,
		active_desired_relative
	)
	var relative_angular_world := child.angular_velocity - parent.angular_velocity
	var relative_angular_parent: Vector3 = parent_basis_inverse * relative_angular_world
	# joint_basis_parent is authored and stored orthonormalized when the rig is built.
	var axis_x_parent: Vector3 = joint_basis_parent.x
	var axis_y_parent: Vector3 = joint_basis_parent.y
	var axis_z_parent: Vector3 = joint_basis_parent.z
	var torque_parent := Vector3.ZERO
	var torque_joint := Vector3.ZERO
	var passive_torque_joint := Vector3.ZERO
	var active_torque_joint := Vector3.ZERO
	var limit_torque_joint := Vector3.ZERO
	var passive_stretch_ratio := Vector3.ZERO
	var passive_error_joint := Vector3.ZERO
	var active_error_joint := Vector3.ZERO
	for axis in range(3):
		var free_axis_bit: int = 1 << axis
		if (parameters.free_axis_mask & free_axis_bit) == 0:
			continue
		var axis_parent: Vector3 = axis_x_parent
		if axis == Vector3.AXIS_Y:
			axis_parent = axis_y_parent
		elif axis == Vector3.AXIS_Z:
			axis_parent = axis_z_parent
		var speed := relative_angular_parent.dot(axis_parent)
		var passive_error := passive_error_parent.dot(axis_parent)
		var active_error := active_error_parent.dot(axis_parent)
		passive_error_joint[axis] = passive_error
		active_error_joint[axis] = active_error
		var reference_span: float = parameters.passive_reference_spans[axis]
		passive_stretch_ratio[axis] = absf(passive_error) / maxf(reference_span, 0.0001)
		# The native Jolt spring owns a modest fraction of the linear impedance so support remains
		# inside the constraint solver. This explicit bounded component supplies the remainder and
		# all nonlinear hardening; the two portions add to one baseline spring instead of doubling it.
		var passive_component = hybrid_passive_component(
			passive_error,
			speed,
			parameters.passive_stiffness[axis],
			parameters.passive_damping[axis],
			parameters.maximum_passive_torque[axis],
			reference_span,
			parameters.passive_progressive_ratio[axis],
			parameters.passive_progressive_onset_ratio,
			parameters.native_fraction
		) * passive_effectiveness
		var active_component = 0.0
		if (parameters.actuated_axis_mask & free_axis_bit) != 0:
			# A passive rest spring should support an uncommanded leg, not make an explicitly
			# yield-enabled actuator range unreachable. Use the already rate-limited target rather
			# than the raw policy sample so exploration cannot suddenly remove support. A damaged
			# actuator cannot yield healthy passive tissue without supplying motor torque.
			var yield_permission: float = clampf(parameters.commanded_passive_yield[axis], 0.0, 1.0)
			if yield_permission > 0.0:
				var commanded_scale: float = commanded_passive_scale(target_angles[axis], reference_span)
				passive_component *= lerpf(
					1.0,
					commanded_scale,
					active_effectiveness * yield_permission
				)
			active_component = spring_damper_component(
				active_error,
				speed,
				parameters.active_stiffness[axis],
				parameters.active_damping[axis],
				parameters.maximum_active_torque[axis]
			) * active_effectiveness
		var limit_component := soft_limit_component(
			current_angles[axis],
			speed,
			parameters.lower_limit_radians[axis],
			parameters.upper_limit_radians[axis],
			parameters.soft_limit_zone_radians,
			parameters.soft_limit_stiffness[axis],
			parameters.soft_limit_damping[axis],
			parameters.maximum_soft_limit_torque[axis]
		) * passive_effectiveness
		var component = passive_component + active_component + limit_component
		torque_parent += axis_parent * component
		torque_joint[axis] = component
		passive_torque_joint[axis] = passive_component
		active_torque_joint[axis] = active_component
		limit_torque_joint[axis] = limit_component
		var action_index: int = parameters.action_indices[axis]
		if action_index >= 0 and action_index < applied_torques.size():
			applied_torques[action_index] = component

	var torque_world: Vector3 = parent_basis * torque_parent
	if torque_world.is_finite() and torque_world.length_squared() > 0.0000001:
		# Continuous forces are submitted every physics update. Equal and opposite torques preserve
		# momentum and make the joint behave like a real internal elastic element.
		child.apply_torque(torque_world)
		parent.apply_torque(-torque_world)
	source_record["smoothed_target_angles"] = target_angles
	source_record["current_angles"] = current_angles
	source_record["target_angles"] = target_angles
	source_record["target_error_angles"] = active_error_joint
	source_record["rest_error_angles"] = passive_error_joint
	source_record["passive_stretch_ratio"] = passive_stretch_ratio
	source_record["passive_torque_joint"] = passive_torque_joint
	source_record["active_torque_joint"] = active_torque_joint
	source_record["limit_torque_joint"] = limit_torque_joint
	source_record["applied_torque_joint"] = torque_joint


func _build_runtime_records() -> void:
	runtime_joint_records.clear()
	runtime_end_effectors.clear()
	for limb: GenericLimb3D in limbs:
		if not is_instance_valid(limb):
			continue
		for source_record: Dictionary in limb.joint_records:
			var definition: LimbJointDefinition = source_record.get("definition") as LimbJointDefinition
			var parent: RigidBody3D = source_record.get("parent") as RigidBody3D
			var child: LimbSegment3D = source_record.get("child") as LimbSegment3D
			if definition == null or not is_instance_valid(parent) or not is_instance_valid(child):
				continue
			var runtime_record: JointRuntimeRecord = JointRuntimeRecord.new()
			runtime_record.source_record = source_record
			runtime_record.parent = parent
			runtime_record.child = child
			runtime_record.rest_relative_basis = source_record.get(
				"rest_relative_basis", Basis.IDENTITY
			)
			runtime_record.joint_basis_parent = source_record.get(
				"joint_basis_parent", Basis.IDENTITY
			)
			runtime_record.parameters = _joint_runtime_parameters(definition)
			runtime_joint_records.append(runtime_record)
		if is_instance_valid(limb.end_effector):
			runtime_end_effectors.append(limb.end_effector)


static func _joint_runtime_parameters(definition: LimbJointDefinition) -> JointRuntimeParameters:
	var result: JointRuntimeParameters = JointRuntimeParameters.new()
	result.action_indices = definition.action_indices
	result.passive_stiffness = definition.passive_stiffness
	result.passive_damping = definition.passive_damping
	result.maximum_passive_torque = definition.maximum_passive_torque
	result.passive_progressive_ratio = definition.passive_progressive_ratio
	result.passive_progressive_onset_ratio = definition.passive_progressive_onset_ratio
	result.native_fraction = (
		definition.native_passive_fraction
		if definition.use_native_passive_spring
		else 0.0
	)
	result.active_stiffness = definition.active_stiffness
	result.active_damping = definition.active_damping
	result.maximum_active_torque = definition.maximum_active_torque
	result.commanded_passive_yield = definition.commanded_passive_yield
	for axis in range(3):
		result.target_response_radians_per_second[axis] = (
			definition.target_response_radians_per_second(axis)
		)
	result.soft_limit_zone_radians = deg_to_rad(definition.soft_limit_zone_degrees)
	result.soft_limit_stiffness = definition.soft_limit_stiffness
	result.soft_limit_damping = definition.soft_limit_damping
	result.maximum_soft_limit_torque = definition.maximum_soft_limit_torque
	for axis in range(3):
		var axis_bit: int = 1 << axis
		if definition.axis_is_free(axis):
			result.free_axis_mask |= axis_bit
		if definition.axis_is_actuated(axis):
			result.actuated_axis_mask |= axis_bit
		var command_limits: Vector2 = definition.command_limits_radians(axis)
		result.command_lower_radians[axis] = command_limits.x
		result.command_upper_radians[axis] = command_limits.y
		result.lower_limit_radians[axis] = deg_to_rad(definition.lower_limit_degrees[axis])
		result.upper_limit_radians[axis] = deg_to_rad(definition.upper_limit_degrees[axis])
		result.passive_reference_spans[axis] = definition.passive_reference_span_radians(axis)
	return result


func _configure_grip_exclusions() -> void:
	var exclusions: Array[RID] = []
	if is_instance_valid(core_body) and core_body.get_rid().is_valid():
		exclusions.append(core_body.get_rid())
	for limb: GenericLimb3D in limbs:
		if not is_instance_valid(limb):
			continue
		for rid: RID in limb.all_body_rids():
			if rid.is_valid() and not exclusions.has(rid):
				exclusions.append(rid)
	for limb: GenericLimb3D in limbs:
		if is_instance_valid(limb) and is_instance_valid(limb.end_effector):
			limb.end_effector.set_grip_excluded_rids(exclusions)


static func _body_health_ratio(body: RigidBody3D) -> float:
	if body is LimbSegment3D:
		return (body as LimbSegment3D).health_ratio()
	return 1.0 if is_instance_valid(body) else 0.0


static func _body_functional_ratio(body: RigidBody3D) -> float:
	if body is LimbSegment3D:
		return (body as LimbSegment3D).functional_ratio()
	return 1.0 if is_instance_valid(body) else 0.0


static func normalized_target(command: float, lower: float, upper: float) -> float:
	var value := clampf(command, -1.0, 1.0)
	return lerpf(0.0, upper, value) if value >= 0.0 else lerpf(0.0, lower, -value)


static func commanded_passive_scale(target_angle: float, reference_span: float) -> float:
	if not is_finite(target_angle) or not is_finite(reference_span):
		return 1.0
	var span: float = maxf(absf(reference_span), deg_to_rad(1.0))
	var command_fraction: float = clampf(absf(target_angle) / span, 0.0, 1.0)
	return lerpf(1.0, MINIMUM_COMMANDED_EXPLICIT_PASSIVE_SCALE, command_fraction)


static func spring_damper_component(
	angle_error: float,
	relative_speed: float,
	stiffness: float,
	damping: float,
	maximum_torque: float
) -> float:
	if (
		not is_finite(angle_error)
		or not is_finite(relative_speed)
		or not is_finite(stiffness)
		or not is_finite(damping)
		or not is_finite(maximum_torque)
		or maximum_torque <= 0.0
	):
		return 0.0
	return clampf(
		angle_error * maxf(stiffness, 0.0) - relative_speed * maxf(damping, 0.0),
		-maxf(maximum_torque, 0.0),
		maxf(maximum_torque, 0.0)
	)


static func hybrid_passive_component(
	angle_error: float,
	relative_speed: float,
	stiffness: float,
	damping: float,
	maximum_torque: float,
	reference_span: float,
	progressive_ratio: float,
	progressive_onset_ratio: float,
	native_fraction: float
) -> float:
	if not is_finite(reference_span) or not is_finite(progressive_ratio):
		return 0.0
	var span := maxf(absf(reference_span), deg_to_rad(1.0))
	var stretch_ratio := absf(angle_error) / span
	var onset := clampf(progressive_onset_ratio, 0.0, 0.95)
	var progressive_distance := clampf(
		(stretch_ratio - onset) / maxf(1.0 - onset, 0.05),
		0.0,
		2.0
	)
	var explicit_linear_fraction := 1.0 - clampf(native_fraction, 0.0, 1.0)
	var explicit_stiffness := maxf(stiffness, 0.0) * (
		explicit_linear_fraction
		+ maxf(progressive_ratio, 0.0) * progressive_distance * progressive_distance
	)
	return spring_damper_component(
		angle_error,
		relative_speed,
		explicit_stiffness,
		maxf(damping, 0.0) * explicit_linear_fraction,
		maximum_torque
	)


static func progressive_spring_damper_component(
	angle_error: float,
	relative_speed: float,
	stiffness: float,
	damping: float,
	maximum_torque: float,
	reference_span: float,
	progressive_ratio: float,
	progressive_onset_ratio: float
) -> float:
	if not is_finite(reference_span) or not is_finite(progressive_ratio):
		return 0.0
	var span := maxf(absf(reference_span), deg_to_rad(1.0))
	var stretch_ratio := absf(angle_error) / span
	var onset := clampf(progressive_onset_ratio, 0.0, 0.95)
	var progressive_distance := clampf(
		(stretch_ratio - onset) / maxf(1.0 - onset, 0.05),
		0.0,
		2.0
	)
	var stiffness_multiplier := 1.0 + maxf(progressive_ratio, 0.0) * (
		progressive_distance * progressive_distance
	)
	return spring_damper_component(
		angle_error,
		relative_speed,
		maxf(stiffness, 0.0) * stiffness_multiplier,
		damping,
		maximum_torque
	)


static func rotation_from_joint_angles(angles: Vector3, joint_basis_parent: Basis) -> Basis:
	# Match Jolt's SixDOF swing-twist decomposition: X is twist and Y/Z form swing. Building and
	# reading targets with the same decomposition avoids the old Euler-order disagreement.
	var twist := Quaternion(Vector3.RIGHT, angles.x)
	var swing_vector := Vector3(0.0, angles.y, angles.z)
	var swing := Quaternion.IDENTITY
	var swing_angle := swing_vector.length()
	if swing_angle > 0.000001:
		swing = Quaternion(swing_vector / swing_angle, swing_angle)
	var delta_joint := Basis((swing * twist).normalized())
	return (
		joint_basis_parent * delta_joint * joint_basis_parent.inverse()
	).orthonormalized()


static func rotation_error_vector_parent(current: Basis, desired: Basis) -> Vector3:
	if not current.is_finite() or not desired.is_finite():
		return Vector3.ZERO
	var error := (desired * current.inverse()).orthonormalized().get_rotation_quaternion().normalized()
	var angle := error.get_angle()
	var axis := error.get_axis()
	if angle > PI:
		angle = TAU - angle
		axis = -axis
	if angle <= 0.000001 or axis.length_squared() <= 0.000001:
		return Vector3.ZERO
	return axis.normalized() * angle


static func joint_angles(
	current_relative: Basis,
	rest_relative: Basis,
	joint_basis_parent: Basis
) -> Vector3:
	var delta_parent := (current_relative * rest_relative.inverse()).orthonormalized()
	var delta_joint := (
		joint_basis_parent.inverse() * delta_parent * joint_basis_parent
	).orthonormalized()
	var rotation := _shortest_quaternion(delta_joint.get_rotation_quaternion())
	var twist := Quaternion(rotation.x, 0.0, 0.0, rotation.w)
	if twist.length_squared() <= 0.0000001:
		twist = Quaternion.IDENTITY
	else:
		twist = _shortest_quaternion(twist.normalized())
	var swing := _shortest_quaternion((rotation * twist.inverse()).normalized())
	var twist_angle := wrapf(2.0 * atan2(twist.x, twist.w), -PI, PI)
	var swing_vector := Vector3.ZERO
	var swing_angle := swing.get_angle()
	var swing_axis := swing.get_axis()
	if swing_angle > PI:
		swing_angle = TAU - swing_angle
		swing_axis = -swing_axis
	if swing_angle > 0.000001 and swing_axis.length_squared() > 0.000001:
		swing_vector = swing_axis.normalized() * swing_angle
	return Vector3(
		twist_angle,
		wrapf(swing_vector.y, -PI, PI),
		wrapf(swing_vector.z, -PI, PI)
	)


static func _shortest_quaternion(value: Quaternion) -> Quaternion:
	var normalized := value.normalized()
	if normalized.w >= 0.0:
		return normalized
	return Quaternion(-normalized.x, -normalized.y, -normalized.z, -normalized.w)


static func soft_limit_component(
	angle: float,
	speed: float,
	lower: float,
	upper: float,
	zone: float,
	stiffness: float,
	damping: float,
	maximum_torque: float
) -> float:
	if maximum_torque <= 0.0:
		return 0.0
	var minimum := minf(lower, upper)
	var maximum := maxf(lower, upper)
	var safe_zone := minf(maxf(zone, 0.0), maxf(maximum - minimum, 0.0) * 0.45)
	var result := 0.0
	if angle > maximum - safe_zone:
		result -= (angle - (maximum - safe_zone)) * stiffness + maxf(speed, 0.0) * damping
	if angle < minimum + safe_zone:
		result += ((minimum + safe_zone) - angle) * stiffness + maxf(-speed, 0.0) * damping
	return clampf(result, -maximum_torque, maximum_torque)
