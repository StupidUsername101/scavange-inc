class_name FourLimbMLFeatureEncoder
extends RefCounted

const SCHEMA_VERSION = 14
const ATTACHMENT_FEATURE_COUNT = (
	FourLimbBodyDefinition.ATTACHMENT_SLOT_COUNT
	* FourLimbAttachmentFeed.FEATURES_PER_SLOT
)
const GLOBAL_FEATURE_COUNT = 75
const LIMB_FEATURE_COUNT = 67
const BASE_FEATURE_COUNT = (
	GLOBAL_FEATURE_COUNT
	+ ATTACHMENT_FEATURE_COUNT
	+ FourLimbBodyDefinition.LIMB_SLOT_COUNT * LIMB_FEATURE_COUNT
)
const TURRET_THREAT_FEATURE_COUNT = 9
const FEATURE_COUNT = BASE_FEATURE_COUNT + TURRET_THREAT_FEATURE_COUNT

#######################################################
# Converts rich body diagnostics into one fixed normalized tensor. Four stable limb slots and
# four fixed attachment feeds keep the runtime layout deterministic across damage and equipment.
# Schema changes are allowed to invalidate older learned models when a better physical signal is
# available. The encoded joint command is the target currently held by the actuator, keeping the
# physical state Markov between policy decisions.
#######################################################


static func encode(
	observation: Dictionary,
	assume_validated_snapshot: bool = false
) -> PackedFloat64Array:
	if not assume_validated_snapshot and not FourLimbMLObservation.is_valid(observation):
		return PackedFloat64Array()
	var body: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	var body_transform: Transform3D = body.get("transform_world", Transform3D.IDENTITY)
	var body_basis = body_transform.basis.orthonormalized()
	var inverse_basis = body_basis.inverse()
	var body_position = body_transform.origin
	var target_position: Vector3 = objective.get("target_position_world", body_position)
	var target_velocity: Vector3 = objective.get("target_velocity_world", Vector3.ZERO)
	var target_radius = maxf(float(objective.get("target_radius", 1.0)), 0.05)
	# Use a yaw-only frame so body roll/pitch does not rotate the navigation axes. Its Y axis is
	# still world-up: schema 14 therefore exposes the complete target-height error and vertical
	# target-relative velocity while keeping horizontal ground-task distance semantics explicit.
	var forward_world = -body_basis.z
	forward_world.y = 0.0
	if forward_world.length_squared() <= 0.000001:
		forward_world = Vector3.FORWARD
	else:
		forward_world = forward_world.normalized()
	var right_world = forward_world.cross(Vector3.UP).normalized()
	var yaw_basis = Basis(right_world, Vector3.UP, -forward_world).orthonormalized()
	var yaw_inverse_basis = yaw_basis.inverse()
	var target_offset_world = target_position - body_position
	var target_offset_local = yaw_inverse_basis * target_offset_world
	var horizontal_target_offset_world = target_offset_world
	horizontal_target_offset_world.y = 0.0
	var horizontal_target_distance = horizontal_target_offset_world.length()
	var target_distance_3d = target_offset_world.length()
	var target_direction_local = (
		target_offset_local / target_distance_3d
		if target_distance_3d > 0.0001
		else Vector3.ZERO
	)
	var core_velocity_world: Vector3 = body.get("linear_velocity_world", Vector3.ZERO)
	var core_angular_world: Vector3 = body.get("angular_velocity_world", Vector3.ZERO)
	var core_velocity_local = inverse_basis * core_velocity_world
	var core_angular_local = inverse_basis * core_angular_world
	var target_relative_velocity_local = yaw_inverse_basis * (
		target_velocity - core_velocity_world
	)
	var pickup_present: bool = bool(objective.get("pickup_item_present", false))
	var pickup_position: Vector3 = objective.get("pickup_item_position_world", body_position)
	var pickup_velocity: Vector3 = objective.get("pickup_item_velocity_world", Vector3.ZERO)
	var pickup_offset_local = yaw_inverse_basis * (pickup_position - body_position)
	var pickup_distance: float = (pickup_position - body_position).length() if pickup_present else 0.0
	var pickup_relative_velocity_local = yaw_inverse_basis * (pickup_velocity - core_velocity_world)
	var world_up_local = inverse_basis * Vector3.UP
	var ground_clearance = float(body.get("ground_clearance", 0.0))
	var preferred_ground_clearance = maxf(
		float(body.get("preferred_ground_clearance", ground_clearance)),
		0.0
	)

	var result = PackedFloat64Array()
	result.resize(FEATURE_COUNT)
	var cursor = 0
	# Schema 14 keeps explicit sole orientation so plantar alignment is directly observable while making
	# the grip-target vector surface-to-surface: it is the candidate/attachment offset from the physical
	# terminal support point instead of an absolute core-local point. Keep the unit
	# direction and inside-radius state: they preserve useful information when the raw offset is
	# clipped and avoid forcing the policy to approximate normalization/comparison.
	cursor = _append_vector(result, cursor, target_offset_local, 25.0)
	cursor = _append_vector(result, cursor, target_direction_local, 1.0)
	cursor = _append(result, cursor, horizontal_target_distance / 25.0)
	cursor = _append(result, cursor, target_distance_3d / 25.0)
	cursor = _append_vector(result, cursor, target_relative_velocity_local, 10.0)
	cursor = _append(result, cursor, target_radius / 10.0)
	cursor = _append(
		result,
		cursor,
		1.0 if target_distance_3d <= target_radius else 0.0
	)
	cursor = _append_vector(result, cursor, core_velocity_local, 10.0)
	cursor = _append_vector(result, cursor, core_angular_local, 12.0)
	# world_up_local.y is exactly the chassis uprightness scalar below. Keep X/Z tilt plus the
	# named uprightness cue instead of feeding the same linear value twice.
	cursor = _append(result, cursor, world_up_local.x)
	cursor = _append(result, cursor, world_up_local.z)
	cursor = _append(result, cursor, ground_clearance / 4.0)
	cursor = _append(result, cursor, preferred_ground_clearance / 4.0)
	# The clearance error is an exact subtraction of the two preceding inputs and is omitted.
	# Schema 7 dedicated this existing scalar to load-bearing chassis contact. Wall brushes remain
	# available through the obstacle/contact feed and must not be confused with crawling on the core.
	cursor = _append(
		result,
		cursor,
		1.0 if bool(body.get("core_support_contact", false)) else 0.0
	)
	cursor = _append(result, cursor, float(body.get("uprightness", 0.0)))
	cursor = _append(result, cursor, float(body.get("health_ratio", 0.0)))
	cursor = _append(result, cursor, float(observation.get("previous_action_age", 0.0)) / 1.0)
	cursor = _append(result, cursor, float(body.get("mass", 0.0)) / 40.0)
	cursor = _append(result, cursor, 1.0 if pickup_present else 0.0)
	cursor = _append_vector(result, cursor, pickup_offset_local if pickup_present else Vector3.ZERO, 12.0)
	cursor = _append(result, cursor, pickup_distance / 12.0)
	cursor = _append_vector(result, cursor, pickup_relative_velocity_local if pickup_present else Vector3.ZERO, 10.0)
	cursor = _append(result, cursor, float(objective.get("pickup_item_mass", 0.0)) / 25.0)
	var pickup_reward_value: float = maxf(
		float(objective.get("pickup_item_reward_value", 0.0)),
		0.0
	)
	# Reward value is user-authored and intentionally has no hard UI ceiling. A bounded rational
	# transform preserves ordering above ordinary values instead of making every value > 10 look
	# identical after the final feature clamp. Value 5 maps to 0.5.
	cursor = _append(
		result,
		cursor,
		pickup_reward_value / (pickup_reward_value + 5.0) if pickup_reward_value > 0.0 else 0.0
	)
	cursor = _append(result, cursor, 1.0 if bool(objective.get("pickup_item_held", false)) else 0.0)

	var obstacle_probe: Dictionary = objective.get("obstacle_probe", {})
	cursor = _append_vector(
		result,
		cursor,
		obstacle_probe.get("nearest_direction_yaw_local", Vector3.ZERO),
		1.0
	)
	cursor = _append_clearance(
		result,
		cursor,
		float(obstacle_probe.get("nearest_distance_m", 0.0)),
		float(obstacle_probe.get("maximum_distance_m", 1.0))
	)
	cursor = _append(
		result,
		cursor,
		float(obstacle_probe.get("closing_speed_mps", 0.0)) / 10.0
	)
	cursor = _append(
		result,
		cursor,
		1.0 if bool(obstacle_probe.get("wall_contact", false)) else 0.0
	)
	cursor = _append(
		result,
		cursor,
		float(obstacle_probe.get("maximum_contact_impulse", 0.0)) / 120.0
	)
	cursor = _append(
		result,
		cursor,
		1.0 if bool(obstacle_probe.get("target_path_blocked", false)) else 0.0
	)
	cursor = _append_clearance(
		result,
		cursor,
		float(obstacle_probe.get("target_path_clearance_m", 0.0)),
		float(obstacle_probe.get("target_path_maximum_distance_m", 1.0))
	)
	cursor = _append(
		result,
		cursor,
		float(obstacle_probe.get("target_wall_top_relative_height_m", 0.0)) / 8.0
	)
	var ray_clearances = _packed_array(
		obstacle_probe.get("ray_clearances_m", PackedFloat64Array())
	)
	var ray_maximum = float(obstacle_probe.get(
		"ray_maximum_distance_m",
		FourLimbMLObservation.OBSTACLE_RAY_MAXIMUM_DISTANCE_M
	))
	for ray_index in range(FourLimbMLObservation.OBSTACLE_RAY_COUNT):
		cursor = _append_clearance(
			result,
			cursor,
			ray_clearances[ray_index] if ray_index < ray_clearances.size() else ray_maximum,
			ray_maximum
		)


	var attachments = _packed_array(observation.get("attachment_features", PackedFloat64Array()))
	for index in range(ATTACHMENT_FEATURE_COUNT):
		cursor = _append(
			result,
			cursor,
			attachments[index] if index < attachments.size() else 0.0
		)

	var limbs: Array = observation.get("limbs", [])
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var limb: Dictionary = limbs[limb_index] if limb_index < limbs.size() else {}
		cursor = _append_limb(result, cursor, limb)

	# Turret perception follows the complete current body/attachment/limb state. Old limb tensor
	# layouts are intentionally not preserved when a better physical observation is available.
	var turret_probe: Dictionary = objective.get("turret_threat_probe", {})
	var turret_present: bool = bool(turret_probe.get("present", false))
	cursor = _append(result, cursor, 1.0 if turret_present else 0.0)
	cursor = _append_vector(
		result, cursor,
		turret_probe.get("direction_local", Vector3.ZERO) if turret_present else Vector3.ZERO,
		1.0
	)
	cursor = _append(
		result, cursor,
		float(turret_probe.get("distance_m", 80.0))
		/ maxf(float(turret_probe.get("maximum_distance_m", 80.0)), 0.1)
	)
	cursor = _append(
		result, cursor,
		1.0 if turret_present and bool(turret_probe.get("line_of_sight", false)) else 0.0
	)
	cursor = _append(result, cursor, float(turret_probe.get("aim_alignment", -1.0)))
	cursor = _append(result, cursor, float(turret_probe.get("cooldown_ready_ratio", 0.0)))
	cursor = _append(result, cursor, float(turret_probe.get("threat_level", 0.0)))
	if cursor != FEATURE_COUNT:
		push_error("Four-limb feature encoder wrote %d values instead of %d." % [cursor, FEATURE_COUNT])
		return PackedFloat64Array()
	return result


static func feature_names() -> Array[String]:
	var result: Array[String] = [
		"target_offset_yaw_local_x",
		"target_height_offset_world_y",
		"target_offset_yaw_local_z",
		"target_direction_yaw_local_x",
		"target_direction_world_y",
		"target_direction_yaw_local_z",
		"target_horizontal_distance",
		"target_distance_3d",
		"target_relative_velocity_yaw_local_x",
		"target_relative_velocity_world_y",
		"target_relative_velocity_yaw_local_z",
		"target_radius",
		"inside_target_radius_3d",
		"core_velocity_local_x",
		"core_velocity_local_y",
		"core_velocity_local_z",
		"core_angular_velocity_local_x",
		"core_angular_velocity_local_y",
		"core_angular_velocity_local_z",
		"world_up_local_x",
		"world_up_local_z",
		"ground_clearance",
		"preferred_ground_clearance",
		"core_support_contact",
		"uprightness",
		"body_health_ratio",
		"previous_action_age",
		"body_mass",
		"pickup_item_present",
		"pickup_item_offset_yaw_local_x",
		"pickup_item_height_offset_world_y",
		"pickup_item_offset_yaw_local_z",
		"pickup_item_distance_3d",
		"pickup_item_relative_velocity_yaw_local_x",
		"pickup_item_relative_velocity_world_y",
		"pickup_item_relative_velocity_yaw_local_z",
		"pickup_item_mass",
		"pickup_item_reward_value",
		"pickup_item_held",
		"nearest_obstacle_direction_yaw_local_x",
		"nearest_obstacle_direction_yaw_local_y",
		"nearest_obstacle_direction_yaw_local_z",
		"nearest_obstacle_clearance",
		"obstacle_closing_speed",
		"wall_contact",
		"maximum_contact_impulse",
		"target_path_blocked",
		"target_path_clearance",
		"target_wall_top_relative_height",
	]
	for ray_index in range(FourLimbMLObservation.OBSTACLE_RAY_COUNT):
		result.append("obstacle_ray_clearance_%02d" % ray_index)
	for slot_index in range(FourLimbBodyDefinition.ATTACHMENT_SLOT_COUNT):
		for feature_index in range(FourLimbAttachmentFeed.FEATURES_PER_SLOT):
			result.append("attachment_%d_feature_%02d" % [slot_index, feature_index])
	var limb_fields: Array[String] = [
		"installed", "functional", "health_ratio", "actuator_effectiveness",
		"hip_offset_x", "hip_offset_y", "hip_offset_z", "upper_length", "lower_length",
		"joint_angle_elevation", "joint_angle_horizontal_sweep", "joint_angle_knee",
		"joint_target_elevation", "joint_target_horizontal_sweep", "joint_target_knee",
		"joint_speed_elevation", "joint_speed_horizontal_sweep", "joint_speed_knee",
		"command_elevation", "command_horizontal_sweep", "command_knee",
		"torque_elevation", "torque_horizontal_sweep", "torque_knee",
		"saturation_elevation", "saturation_horizontal_sweep", "saturation_knee",
		"foot_position_x", "foot_position_y", "foot_position_z",
		"foot_velocity_x", "foot_velocity_y", "foot_velocity_z",
		"foot_up_x", "foot_up_y", "foot_up_z",
		"foot_contact", "ground_normal_x", "ground_normal_y", "ground_normal_z",
		"foot_clearance", "foot_slip_speed", "wall_contact",
		"maximum_wall_contact_impulse", "world_contact_count",
		"grip_present", "grip_command", "grip_activation", "grip_requires_rearm",
		"grip_target_present",
		"grip_target_offset_x", "grip_target_offset_y", "grip_target_offset_z",
		"grip_target_normal_x", "grip_target_normal_y", "grip_target_normal_z",
		"grip_target_distance", "grip_candidate_dynamic",
		"grip_candidate_target_mass", "grip_candidate_climbable",
		"grip_candidate_carryable", "grip_attached", "grip_attached_dynamic",
		"grip_attached_target_mass", "grip_attached_climbable",
		"grip_attached_carryable", "grip_load_ratio",
	]
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		for field_name in limb_fields:
			result.append("limb_%d_%s" % [limb_index, field_name])
	result.append_array([
		"turret_present",
		"turret_direction_local_x",
		"turret_direction_local_y",
		"turret_direction_local_z",
		"turret_distance_normalized",
		"turret_line_of_sight",
		"turret_aim_alignment",
		"turret_cooldown_ready",
		"turret_threat_level",
	])
	if result.size() != FEATURE_COUNT:
		push_error("Four-limb feature-name table contains %d names instead of %d." % [result.size(), FEATURE_COUNT])
		return []
	return result


static func is_normalized(features: PackedFloat64Array) -> bool:
	if features.size() != FEATURE_COUNT:
		return false
	for value in features:
		if not is_finite(value) or value < -1.00001 or value > 1.00001:
			return false
	return true


static func _append_limb(
	result: PackedFloat64Array,
	cursor: int,
	limb: Dictionary
) -> int:
	cursor = _append(result, cursor, 1.0 if bool(limb.get("installed", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("functional", false)) else 0.0)
	cursor = _append(result, cursor, float(limb.get("health_ratio", 0.0)))
	cursor = _append(result, cursor, float(limb.get("actuator_effectiveness", 0.0)))
	cursor = _append_vector(result, cursor, limb.get("hip_offset_local", Vector3.ZERO), 3.0)
	cursor = _append(result, cursor, float(limb.get("upper_length", 0.0)) / 3.0)
	cursor = _append(result, cursor, float(limb.get("lower_length", 0.0)) / 3.0)
	cursor = _append_vector(result, cursor, limb.get("joint_angles", Vector3.ZERO), PI)
	cursor = _append_vector(result, cursor, limb.get("joint_target_angles", Vector3.ZERO), PI)
	# target - measured is exact algebraic duplication of the two vectors above.
	cursor = _append_vector(result, cursor, limb.get("joint_angular_velocities", Vector3.ZERO), 15.0)
	cursor = _append_vector(result, cursor, limb.get("commands", Vector3.ZERO), 1.0)
	cursor = _append_vector(result, cursor, limb.get("applied_torque", Vector3.ZERO), 150.0)
	cursor = _append_vector(result, cursor, limb.get("saturation", Vector3.ZERO), 1.0)
	cursor = _append_vector(result, cursor, limb.get("foot_position_local", Vector3.ZERO), 3.0)
	cursor = _append_vector(result, cursor, limb.get("foot_velocity_local", Vector3.ZERO), 10.0)
	cursor = _append_vector(result, cursor, limb.get("foot_up_local", Vector3.UP), 1.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("foot_contact", false)) else 0.0)
	cursor = _append_vector(result, cursor, limb.get("ground_normal_local", Vector3.UP), 1.0)
	cursor = _append(result, cursor, float(limb.get("foot_clearance", 0.0)) / 2.0)
	cursor = _append(result, cursor, float(limb.get("foot_slip_speed", 0.0)) / 6.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("wall_contact", false)) else 0.0)
	cursor = _append(
		result,
		cursor,
		float(limb.get("maximum_wall_contact_impulse", 0.0)) / 120.0
	)
	cursor = _append(result, cursor, float(limb.get("world_contact_count", 0)) / 8.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_present", false)) else 0.0)
	cursor = _append(result, cursor, float(limb.get("grip_command", 0.0)))
	cursor = _append(result, cursor, float(limb.get("grip_activation", 0.0)))
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_requires_rearm", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_target_present", false)) else 0.0)
	var end_effector: Dictionary = limb.get("end_effector", {})
	var grip_detection_radius: float = maxf(
		float(end_effector.get("grip_detection_radius", 1.10)),
		float(end_effector.get("grip_acquisition_radius", 0.24))
	)
	cursor = _append_vector(
		result,
		cursor,
		limb.get("grip_target_offset_local", Vector3.ZERO),
		grip_detection_radius
	)
	cursor = _append_vector(result, cursor, limb.get("grip_target_normal_local", Vector3.UP), 1.0)
	var encoded_grip_distance: float = (
		float(limb.get("grip_target_distance", grip_detection_radius))
		if bool(limb.get("grip_target_present", false))
		else grip_detection_radius
	)
	cursor = _append(
		result,
		cursor,
		encoded_grip_distance / grip_detection_radius
	)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_candidate_dynamic", false)) else 0.0)
	cursor = _append(result, cursor, float(limb.get("grip_candidate_target_mass", 0.0)) / 25.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_candidate_climbable", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_candidate_carryable", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_attached", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_attached_dynamic", false)) else 0.0)
	cursor = _append(result, cursor, float(limb.get("grip_attached_target_mass", 0.0)) / 25.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_attached_climbable", false)) else 0.0)
	cursor = _append(result, cursor, 1.0 if bool(limb.get("grip_attached_carryable", false)) else 0.0)
	cursor = _append(result, cursor, float(limb.get("grip_load_ratio", 0.0)))
	return cursor


static func _append_clearance(
	result: PackedFloat64Array,
	cursor: int,
	distance_m: float,
	maximum_distance_m: float
) -> int:
	var maximum = maxf(maximum_distance_m, 0.000001)
	var normalized = clampf(distance_m / maximum, 0.0, 1.0)
	# -1 means touching a wall and +1 means the complete ray is clear.
	return _append(result, cursor, normalized * 2.0 - 1.0)


static func _append_vector(
	result: PackedFloat64Array,
	cursor: int,
	value: Vector3,
	scale: float
) -> int:
	var divisor = maxf(absf(scale), 0.000001)
	cursor = _append(result, cursor, value.x / divisor)
	cursor = _append(result, cursor, value.y / divisor)
	cursor = _append(result, cursor, value.z / divisor)
	return cursor


static func _append(
	result: PackedFloat64Array,
	cursor: int,
	value: float
) -> int:
	if cursor < 0 or cursor >= result.size():
		push_error(
			"Four-limb feature encoder attempted to write index %d into a %d-value tensor." % [
				cursor,
				result.size(),
			]
		)
		return cursor + 1
	result[cursor] = clampf(value, -1.0, 1.0) if is_finite(value) else 0.0
	return cursor + 1


static func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		return value as PackedFloat64Array
	var result = PackedFloat64Array()
	if value is PackedFloat32Array:
		for item in value:
			result.append(float(item))
	elif value is Array:
		for item: Variant in value:
			result.append(float(item))
	return result
