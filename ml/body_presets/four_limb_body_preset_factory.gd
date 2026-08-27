class_name FourLimbBodyPresetFactory
extends RefCounted

#######################################################
# The Four-Limb Walker anatomy is a model-creator preset, not a hidden default owned by the runtime
# definition class. Editing or constructing another body never causes this anatomy to reappear.
#######################################################

const PRESET_FOOT_SEPARATION_GAP_METERS = 0.003


static func create_compatibility_runtime_definition() -> FourLimbBodyDefinition:
	var definition = FourLimbBodyDefinition.new()
	# Keep every tuned Walker value in the named preset. FourLimbBodyDefinition itself now only
	# provides neutral safety baselines for malformed numeric input; constructing the compatibility
	# resource can no longer recreate this body accidentally.
	definition.core_size = Vector3(0.72, 0.28, 0.92)
	definition.core_mass = 3.2
	definition.core_maximum_health = 300.0
	definition.friction = 0.95
	definition.bounce = 0.01
	definition.linear_damp = 0.60
	definition.angular_damp = 1.20
	definition.hip_stiffness = 210.0
	definition.hip_damping = 22.0
	definition.maximum_hip_torque = 320.0
	definition.hip_horizontal_response_degrees_per_second = 190.0
	definition.knee_stiffness = 240.0
	definition.knee_damping = 24.0
	definition.maximum_knee_torque = 360.0
	definition.joint_limit_soft_zone_degrees = 8.0
	definition.joint_limit_stiffness = 260.0
	definition.joint_limit_damping = 20.0
	definition.maximum_joint_limit_torque = 520.0
	definition.passive_joint_stiffness = 130.0
	definition.passive_joint_damping = 18.0
	definition.maximum_passive_joint_torque = 420.0
	definition.passive_joint_progressive_onset_ratio = 0.40
	definition.passive_joint_progressive_ratio = 5.0
	definition.passive_joint_native_fraction = 0.35
	var limbs: Array[FourLimbSlotDefinition] = [
		_limb(
			"Front Right",
			Vector3(0.40, 0.0, -0.50),
			Vector3(1.05, -1.65, -1.15),
			Vector3(1.0, 0.30, -1.0)
		),
		_limb(
			"Rear Right",
			Vector3(0.40, 0.0, 0.50),
			Vector3(1.05, -1.65, 1.15),
			Vector3(1.0, 0.30, 1.0)
		),
		_limb(
			"Rear Left",
			Vector3(-0.40, 0.0, 0.50),
			Vector3(-1.05, -1.65, 1.15),
			Vector3(-1.0, 0.30, 1.0)
		),
		_limb(
			"Front Left",
			Vector3(-0.40, 0.0, -0.50),
			Vector3(-1.05, -1.65, -1.15),
			Vector3(-1.0, 0.30, -1.0)
		),
	]
	definition.limbs = limbs
	var attachment_slots: Array[FourLimbAttachmentSlotDefinition] = [
		_attachment("Top", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0))),
		_attachment("Left", Transform3D(Basis.IDENTITY, Vector3(-0.44, 0.0, 0.0))),
		_attachment("Right", Transform3D(Basis.IDENTITY, Vector3(0.44, 0.0, 0.0))),
		_attachment("Rear", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.58))),
	]
	definition.attachment_slots = attachment_slots
	definition.ensure_contract()
	return definition


static func _limb(
	name_value: String,
	hip: Vector3,
	foot: Vector3,
	bend_hint_value: Vector3
) -> FourLimbSlotDefinition:
	var limb = FourLimbSlotDefinition.new()
	limb.slot_name = name_value
	limb.hip_offset = hip
	limb.rest_foot_offset = foot
	limb.bend_hint = bend_hint_value.normalized()
	limb.upper_length = 1.05
	limb.lower_length = 1.10
	limb.segment_radius = 0.075
	limb.segment_mass = 0.38
	limb.maximum_health = 100.0
	limb.end_effector = _preset_grip_definition(name_value)
	_align_preset_foot_pad(limb)
	limb.hip_swing_span_degrees = 68.0
	limb.hip_elevation_upper_extension_degrees = 40.0
	limb.hip_twist_span_degrees = 72.0
	limb.knee_limit_lower_degrees = -8.0
	limb.knee_limit_upper_degrees = 72.0
	return limb


static func _preset_grip_definition(limb_name: String) -> LimbEndEffectorDefinition:
	var result = LimbEndEffectorDefinition.new()
	result.enabled = true
	result.effector_name = "%s Grip" % limb_name
	result.effector_type_id = &"generic_grip"
	result.geometry_type = LimbEndEffectorDefinition.GeometryType.BOX
	result.local_offset = Vector3.ZERO
	result.local_rotation_degrees = Vector3.ZERO
	result.box_size = Vector3(0.24, 0.06, 0.24)
	result.added_mass = 0.0
	result.maximum_health = 100.0
	result.friction = 1.0
	result.bounce = 0.0
	result.rough = true
	result.absorbent = false
	result.normal_stiffness = 0.0
	result.normal_damping = 0.0
	result.maximum_compression = 0.0
	result.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	result.grip_action_index = -1
	result.grip_activation_threshold = 0.55
	result.activation_response_per_second = 18.0
	result.grip_acquisition_radius = 0.24
	result.grip_detection_radius = 1.10
	result.candidate_refresh_seconds = 0.10
	result.grip_collision_mask = 1
	result.allow_static_grip = true
	result.allow_dynamic_grip = true
	result.maximum_held_mass = 25.0
	result.grip_stiffness = 1400.0
	result.grip_damping = 90.0
	result.grip_release_threshold = 0.30
	result.maximum_normal_holding_force = 420.0
	result.maximum_shear_holding_force = 360.0
	result.breakaway_load_ratio = 1.0
	result.breakaway_confirmation_seconds = 0.08
	result.energy_cost_per_second = 0.0
	result.compatible_surface_tags = PackedStringArray(["climbable", "carryable"])
	return result


static func _align_preset_foot_pad(limb: FourLimbSlotDefinition) -> void:
	if limb == null or limb.end_effector == null:
		return
	var points: PackedVector3Array = LimbKinematics.solve_two_bone(
		limb.hip_offset,
		limb.rest_foot_offset,
		limb.upper_length,
		limb.lower_length,
		limb.bend_hint
	)
	if points.size() != 3:
		return
	var lower_direction: Vector3 = (points[2] - points[1]).normalized()
	if lower_direction.length_squared() <= 0.000001:
		return
	var lower_basis: Basis = GenericLimb3D.basis_from_y(lower_direction)
	var pad_basis_lower_local: Basis = lower_basis.inverse().orthonormalized()
	var pad_euler: Vector3 = pad_basis_lower_local.get_euler()
	limb.end_effector.local_rotation_degrees = Vector3(
		rad_to_deg(pad_euler.x),
		rad_to_deg(pad_euler.y),
		rad_to_deg(pad_euler.z)
	)
	var proximal_support_radius: float = limb.end_effector.support_radius_along_parent_direction(
		Vector3.DOWN
	)
	limb.end_effector.local_offset = Vector3.UP * (
		proximal_support_radius + PRESET_FOOT_SEPARATION_GAP_METERS
	)


static func _attachment(
	name_value: String,
	offset: Transform3D
) -> FourLimbAttachmentSlotDefinition:
	var slot = FourLimbAttachmentSlotDefinition.new()
	slot.slot_name = name_value
	slot.core_offset = offset
	return slot
