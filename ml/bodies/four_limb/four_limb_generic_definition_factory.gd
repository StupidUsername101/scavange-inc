class_name FourLimbGenericDefinitionFactory
extends RefCounted

const LIMB_TEMPLATE_PATH: String = (
	"res://resources/ml_body_presets/four_limb_walker/generic_limb_template/generic_limb.tres"
)
const LIMB_TEMPLATE: GenericLimbDefinition = preload(
	"res://resources/ml_body_presets/four_limb_walker/generic_limb_template/generic_limb.tres"
)

#######################################################
# Converts saved four-limb compatibility resources into the ordinary generic limb contract used
# everywhere else. Stock limb/joint capability data lives in .tres resources; this adapter only
# applies per-leg geometry/tuning from the selected saved body preset and assigns runtime indices.
#######################################################


static func create_limb_definition(
	body_definition: FourLimbBodyDefinition,
	slot: FourLimbSlotDefinition,
	limb_index: int,
	action_offset: int = 0
) -> GenericLimbDefinition:
	if body_definition == null or slot == null or not slot.installed:
		return null
	var points: PackedVector3Array = LimbKinematics.solve_two_bone(
		slot.hip_offset,
		slot.rest_foot_offset,
		slot.upper_length,
		slot.lower_length,
		slot.bend_hint
	)
	if points.size() != 3:
		return null
	return create_limb_definition_from_points(
		body_definition,
		slot,
		limb_index,
		points,
		action_offset
	)


static func create_limb_definition_from_points(
	body_definition: FourLimbBodyDefinition,
	slot: FourLimbSlotDefinition,
	limb_index: int,
	points: PackedVector3Array,
	action_offset: int = 0
) -> GenericLimbDefinition:
	if body_definition == null or slot == null or points.size() != 3:
		return null
	var result: GenericLimbDefinition = (
		MLBodyPartContract.deep_duplicate_resource(LIMB_TEMPLATE) as GenericLimbDefinition
	)
	if result == null or result.segments.size() != 2:
		return null
	# Keep the snapshot backing path inherited from LIMB_TEMPLATE. The FourLimbSlotDefinition is
	# authoring input, not a reconstructible GenericLimbDefinition resource. Pointing at the slot
	# .tres makes snapshot restore load the wrong script/class.
	result.limb_name = "limb_%02d" % limb_index
	result.installed = slot.installed
	result.mount_offset_local = slot.hip_offset
	var upper_direction: Vector3 = (points[1] - points[0]).normalized()
	var lower_direction: Vector3 = (points[2] - points[1]).normalized()
	var lower_basis: Basis = GenericLimb3D.basis_from_y(lower_direction)
	var local_knee_basis: Basis = LimbKinematics.create_knee_joint_basis(points)
	var knee_basis_core: Basis = (lower_basis * local_knee_basis).orthonormalized()

	var upper_segment: LimbSegmentDefinition = result.segments[0]
	var lower_segment: LimbSegmentDefinition = result.segments[1]
	if upper_segment == null or lower_segment == null:
		return null
	var hip_joint: LimbJointDefinition = upper_segment.joint
	var knee_joint: LimbJointDefinition = lower_segment.joint
	if hip_joint == null or knee_joint == null:
		return null

	hip_joint.joint_name = "Hip"
	hip_joint.joint_basis_local = hip_joint_basis_for_slot(slot, upper_direction)
	hip_joint.lower_limit_degrees = Vector3(
		-slot.hip_twist_span_degrees,
		0.0,
		-slot.hip_swing_span_degrees
	)
	hip_joint.upper_limit_degrees = Vector3(
		slot.hip_twist_span_degrees,
		0.0,
		slot.hip_swing_span_degrees + slot.hip_elevation_upper_extension_degrees
	)
	# Preserve the established local order: elevation, horizontal sweep, knee, grip. Capability
	# itself comes from the saved joint template; only this compatibility profile's old packed
	# action addresses are assigned here for its fixed trainer.
	hip_joint.action_indices = Vector3i(action_offset + 1, -1, action_offset)
	hip_joint.passive_reference_span_degrees.z = slot.hip_swing_span_degrees
	hip_joint.passive_stiffness = Vector3(
		body_definition.passive_joint_stiffness,
		0.0,
		body_definition.passive_joint_stiffness
	)
	hip_joint.passive_damping = Vector3(
		body_definition.passive_joint_damping,
		0.0,
		body_definition.passive_joint_damping
	)
	hip_joint.maximum_passive_torque = Vector3(
		body_definition.maximum_passive_joint_torque,
		0.0,
		body_definition.maximum_passive_joint_torque
	)
	hip_joint.passive_progressive_ratio = Vector3(
		body_definition.passive_joint_progressive_ratio,
		0.0,
		body_definition.passive_joint_progressive_ratio
	)
	hip_joint.passive_progressive_onset_ratio = body_definition.passive_joint_progressive_onset_ratio
	hip_joint.native_passive_fraction = body_definition.passive_joint_native_fraction
	hip_joint.active_stiffness = Vector3(
		body_definition.hip_stiffness,
		0.0,
		body_definition.hip_stiffness
	)
	hip_joint.active_damping = Vector3(
		body_definition.hip_damping,
		0.0,
		body_definition.hip_damping
	)
	hip_joint.maximum_active_torque = Vector3(
		body_definition.maximum_hip_torque,
		0.0,
		body_definition.maximum_hip_torque
	)
	hip_joint.target_response_degrees_per_second_by_axis.x = (
		body_definition.hip_horizontal_response_degrees_per_second
	)
	_configure_soft_limits(hip_joint, body_definition)

	upper_segment.segment_name = "Upper"
	upper_segment.rest_direction_local = upper_direction
	upper_segment.length = slot.upper_length
	upper_segment.radius = slot.segment_radius
	upper_segment.mass = slot.segment_mass
	upper_segment.maximum_health = slot.maximum_health
	upper_segment.friction = body_definition.friction
	upper_segment.bounce = body_definition.bounce

	knee_joint.joint_name = "Knee"
	knee_joint.joint_basis_local = knee_basis_core
	knee_joint.lower_limit_degrees = Vector3(0.0, 0.0, slot.knee_limit_lower_degrees)
	knee_joint.upper_limit_degrees = Vector3(0.0, 0.0, slot.knee_limit_upper_degrees)
	knee_joint.action_indices = Vector3i(-1, -1, action_offset + 2)
	knee_joint.passive_stiffness = Vector3(0.0, 0.0, body_definition.passive_joint_stiffness)
	knee_joint.passive_damping = Vector3(0.0, 0.0, body_definition.passive_joint_damping)
	knee_joint.maximum_passive_torque = Vector3(0.0, 0.0, body_definition.maximum_passive_joint_torque)
	knee_joint.passive_progressive_ratio = Vector3(0.0, 0.0, body_definition.passive_joint_progressive_ratio)
	knee_joint.passive_progressive_onset_ratio = body_definition.passive_joint_progressive_onset_ratio
	knee_joint.native_passive_fraction = body_definition.passive_joint_native_fraction
	knee_joint.active_stiffness = Vector3(0.0, 0.0, body_definition.knee_stiffness)
	knee_joint.active_damping = Vector3(0.0, 0.0, body_definition.knee_damping)
	knee_joint.maximum_active_torque = Vector3(0.0, 0.0, body_definition.maximum_knee_torque)
	_configure_soft_limits(knee_joint, body_definition)

	lower_segment.segment_name = "Lower"
	lower_segment.rest_direction_local = lower_direction
	lower_segment.length = slot.lower_length
	lower_segment.radius = slot.segment_radius
	lower_segment.mass = slot.segment_mass
	lower_segment.maximum_health = slot.maximum_health
	lower_segment.friction = body_definition.friction
	lower_segment.bounce = body_definition.bounce
	lower_segment.rough = (
		slot.end_effector != null
		and slot.end_effector.enabled
		and slot.end_effector.effector_type_id == &"generic_grip"
		and slot.end_effector.geometry_type == LimbEndEffectorDefinition.GeometryType.NONE
	)
	result.end_effector = (
		MLBodyPartContract.deep_duplicate_resource(slot.end_effector) as LimbEndEffectorDefinition
		if slot.end_effector != null
		else null
	)
	if (
		result.end_effector != null
		and result.end_effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED
	):
		result.end_effector.grip_action_index = action_offset + 3
	result.sanitize()
	return result


static func hip_joint_basis_for_slot(
	slot: FourLimbSlotDefinition,
	upper_direction: Vector3
) -> Basis:
	var radial = Vector3.ZERO
	if slot != null:
		radial = slot.rest_foot_offset - slot.hip_offset
	radial.y = 0.0
	if radial.length_squared() <= 0.000001:
		radial = upper_direction
		radial.y = 0.0
	if radial.length_squared() <= 0.000001:
		radial = Vector3.FORWARD
	radial = radial.normalized()
	var yaw_axis = Vector3.UP
	var pitch_axis: Vector3 = radial.cross(yaw_axis).normalized()
	if pitch_axis.length_squared() <= 0.000001:
		pitch_axis = Vector3.RIGHT
	var locked_axis: Vector3 = pitch_axis.cross(yaw_axis).normalized()
	return Basis(yaw_axis, locked_axis, pitch_axis).orthonormalized()


static func _configure_soft_limits(
	joint: LimbJointDefinition,
	body_definition: FourLimbBodyDefinition
) -> void:
	joint.command_limit_margin_degrees = body_definition.joint_limit_soft_zone_degrees * 0.55
	joint.soft_limit_zone_degrees = body_definition.joint_limit_soft_zone_degrees
	joint.soft_limit_stiffness = Vector3.ONE * body_definition.joint_limit_stiffness
	joint.soft_limit_damping = Vector3.ONE * body_definition.joint_limit_damping
	joint.maximum_soft_limit_torque = Vector3.ONE * body_definition.maximum_joint_limit_torque
