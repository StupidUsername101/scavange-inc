class_name FourLimbMLObservation
extends RefCounted

const SCHEMA_VERSION = 14
const OBSTACLE_RAY_COUNT = 26
const OBSTACLE_RAY_MAXIMUM_DISTANCE_M = 12.0

#######################################################
# Validation helpers for the fixed four-limb observation contract.
#######################################################


static func is_valid(observation: Dictionary) -> bool:
	if (
		int(observation.get("schema_version", 0)) != SCHEMA_VERSION
		or str(observation.get("body_profile_id", "")) != FourLimbBodyDefinition.BODY_PROFILE_ID
		or not (observation.get("body", {}) is Dictionary)
		or not (observation.get("limbs", []) is Array)
		or not (observation.get("objective", {}) is Dictionary)
	):
		return false
	var limbs: Array = observation.get("limbs", [])
	if limbs.size() != FourLimbBodyDefinition.LIMB_SLOT_COUNT:
		return false
	if not _has_finite_body_state(observation.get("body", {})):
		return false
	for limb_index in range(limbs.size()):
		if not _has_finite_limb_state(limbs[limb_index], limb_index):
			return false
	var previous_action_age_value: Variant = observation.get("previous_action_age")
	if not _is_finite_number_value(previous_action_age_value):
		return false
	var previous_action_age = float(previous_action_age_value)
	if previous_action_age < 0.0:
		return false
	var objective: Dictionary = observation.get("objective", {})
	var target_position_value: Variant = objective.get("target_position_world")
	var target_velocity_value: Variant = objective.get("target_velocity_world")
	var target_radius_value: Variant = objective.get("target_radius")
	if (
		not (target_position_value is Vector3)
		or not (target_position_value as Vector3).is_finite()
		or not (target_velocity_value is Vector3)
		or not (target_velocity_value as Vector3).is_finite()
		or not _is_finite_number_value(target_radius_value)
		or float(target_radius_value) <= 0.0
	):
		return false
	for key in ["pickup_item_present", "pickup_item_held"]:
		if not _has_boolean(objective, key):
			return false
	for key in ["pickup_item_position_world", "pickup_item_velocity_world"]:
		if not _has_finite_vector(objective, key):
			return false
	if (
		not _has_finite_number(objective, "pickup_item_mass")
		or float(objective["pickup_item_mass"]) < 0.0
		or not _has_finite_number(objective, "pickup_item_reward_value")
		or float(objective["pickup_item_reward_value"]) < 0.0
		or not _has_nonnegative_integer(objective, "pickup_item_id")
	):
		return false
	var probe_value: Variant = objective.get("obstacle_probe", {})
	if not (probe_value is Dictionary):
		return false
	var probe: Dictionary = probe_value
	var ray_value: Variant = probe.get("ray_clearances_m", PackedFloat64Array())
	var ray_values = _packed_array(ray_value)
	if ray_values.size() != OBSTACLE_RAY_COUNT:
		return false
	for clearance in ray_values:
		if not is_finite(clearance) or clearance < 0.0:
			return false
	var ray_maximum_value: Variant = probe.get("ray_maximum_distance_m")
	if (
		not _is_finite_number_value(ray_maximum_value)
		or float(ray_maximum_value) <= 0.0
	):
		return false
	for key in [
		"nearest_distance_m",
		"maximum_distance_m",
		"closing_speed_mps",
		"target_path_clearance_m",
		"target_path_maximum_distance_m",
		"target_wall_top_relative_height_m",
		"maximum_contact_impulse",
	]:
		if not _has_finite_number(probe, key):
			return false
	for key in ["nearest_direction_world", "nearest_direction_yaw_local"]:
		if not _has_finite_vector(probe, key):
			return false
	for key in ["target_path_blocked", "wall_contact"]:
		if not _has_boolean(probe, key):
			return false
	var turret_value: Variant = objective.get("turret_threat_probe", {})
	if not (turret_value is Dictionary):
		return false
	var turret_probe: Dictionary = turret_value
	for key in ["present", "line_of_sight"]:
		if not _has_boolean(turret_probe, key):
			return false
	if not _has_finite_vector(turret_probe, "direction_local"):
		return false
	for key in [
		"distance_m", "maximum_distance_m", "aim_alignment",
		"cooldown_ready_ratio", "threat_level",
	]:
		if not _has_finite_number(turret_probe, key):
			return false
	if (
		float(turret_probe["distance_m"]) < 0.0
		or float(turret_probe["maximum_distance_m"]) <= 0.0
	):
		return false
	if not _has_nonnegative_integer(probe, "wall_contact_count"):
		return false
	if (
		float(probe["nearest_distance_m"]) < 0.0
		or float(probe["maximum_distance_m"]) <= 0.0
		or float(probe["target_path_clearance_m"]) < 0.0
		or float(probe["target_path_maximum_distance_m"]) <= 0.0
		or float(probe["maximum_contact_impulse"]) < 0.0
	):
		return false
	var attachment_features = _packed_array(
		observation.get("attachment_features", PackedFloat64Array())
	)
	var expected_attachment_features = (
		FourLimbBodyDefinition.ATTACHMENT_SLOT_COUNT
		* FourLimbAttachmentFeed.FEATURES_PER_SLOT
	)
	if attachment_features.size() != expected_attachment_features:
		return false
	for feature in attachment_features:
		if not is_finite(feature):
			return false
	return true


static func _has_finite_body_state(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var body: Dictionary = value
	var transform_value: Variant = body.get("transform_world")
	if not (transform_value is Transform3D):
		return false
	var transform: Transform3D = transform_value
	if not transform.origin.is_finite() or not transform.basis.is_finite():
		return false
	if not _has_finite_vector(body, "position_world"):
		return false
	var basis_value: Variant = body.get("basis_world")
	if not (basis_value is Basis) or not (basis_value as Basis).is_finite():
		return false
	for key in [
		"linear_velocity_world",
		"angular_velocity_world",
		"ground_normal_world",
	]:
		if not _has_finite_vector(body, key):
			return false
	for key in [
		"uprightness",
		"ground_clearance",
		"preferred_core_height",
		"preferred_ground_clearance",
		"ground_clearance_error",
		"health_ratio",
		"mass",
		"maximum_contact_impulse",
	]:
		if not _has_finite_number(body, key):
			return false
	for key in ["core_contact", "core_support_contact", "core_wall_contact"]:
		if not _has_boolean(body, key):
			return false
	for key in ["world_contact_count", "wall_contact_count"]:
		if not _has_nonnegative_integer(body, key):
			return false
	return (
		float(body["ground_clearance"]) >= 0.0
		and float(body["preferred_core_height"]) >= 0.0
		and float(body["preferred_ground_clearance"]) >= 0.0
		and float(body["health_ratio"]) >= 0.0
		and float(body["mass"]) > 0.0
		and float(body["maximum_contact_impulse"]) >= 0.0
	)


static func _has_finite_limb_state(value: Variant, expected_slot_index: int) -> bool:
	if not (value is Dictionary):
		return false
	var limb: Dictionary = value
	var slot_index_value: Variant = limb.get("slot_index")
	if typeof(slot_index_value) != TYPE_INT or int(slot_index_value) != expected_slot_index:
		return false
	for key in [
		"installed",
		"functional",
		"foot_contact",
		"wall_contact",
		"grip_present",
		"grip_requires_rearm",
		"grip_candidate_present",
		"grip_target_present",
		"grip_candidate_dynamic",
		"grip_candidate_climbable",
		"grip_candidate_carryable",
		"grip_attached",
		"grip_attached_dynamic",
		"grip_attached_climbable",
		"grip_attached_carryable",
	]:
		if not _has_boolean(limb, key):
			return false
	for key in [
		"hip_offset_local",
		"joint_angles",
		"joint_target_angles",
		"joint_target_errors",
		"joint_angular_velocities",
		"previous_commands",
		"commands",
		"applied_torque",
		"saturation",
		"foot_position_local",
		"foot_velocity_local",
		"foot_up_local",
		"ground_normal_local",
		"grip_target_offset_local",
		"grip_target_normal_local",
	]:
		if not _has_finite_vector(limb, key):
			return false
	for key in [
		"health_ratio",
		"actuator_effectiveness",
		"upper_length",
		"lower_length",
		"foot_clearance",
		"foot_slip_speed",
		"maximum_wall_contact_impulse",
		"grip_command",
		"grip_activation",
		"grip_candidate_distance",
		"grip_target_distance",
		"grip_candidate_target_mass",
		"grip_attached_target_mass",
		"grip_load_ratio",
	]:
		if not _has_finite_number(limb, key):
			return false
	for key in ["world_contact_count", "wall_contact_count", "grip_attached_target_id", "grip_pickup_sequence"]:
		if not _has_nonnegative_integer(limb, key):
			return false
	return (
		float(limb["health_ratio"]) >= 0.0
		and float(limb["actuator_effectiveness"]) >= 0.0
		and float(limb["upper_length"]) >= 0.0
		and float(limb["lower_length"]) >= 0.0
		and float(limb["foot_clearance"]) >= 0.0
		and float(limb["foot_slip_speed"]) >= 0.0
		and float(limb["maximum_wall_contact_impulse"]) >= 0.0
		and float(limb["grip_activation"]) >= 0.0
		and float(limb["grip_candidate_distance"]) >= 0.0
		and float(limb["grip_target_distance"]) >= 0.0
		and float(limb["grip_candidate_target_mass"]) >= 0.0
		and float(limb["grip_attached_target_mass"]) >= 0.0
		and float(limb["grip_load_ratio"]) >= 0.0
	)


static func _has_finite_vector(dictionary: Dictionary, key: String) -> bool:
	var value: Variant = dictionary.get(key)
	return value is Vector3 and (value as Vector3).is_finite()


static func _has_finite_number(dictionary: Dictionary, key: String) -> bool:
	return dictionary.has(key) and _is_finite_number_value(dictionary[key])


static func _has_nonnegative_integer(dictionary: Dictionary, key: String) -> bool:
	return (
		dictionary.has(key)
		and typeof(dictionary[key]) == TYPE_INT
		and int(dictionary[key]) >= 0
	)


static func _has_boolean(dictionary: Dictionary, key: String) -> bool:
	return dictionary.has(key) and typeof(dictionary[key]) == TYPE_BOOL


static func _is_finite_number_value(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
	)


static func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		return value as PackedFloat64Array
	var result = PackedFloat64Array()
	if value is PackedFloat32Array:
		for item in value:
			result.append(float(item))
	elif value is Array:
		for item: Variant in value:
			if not _is_finite_number_value(item):
				return PackedFloat64Array()
			result.append(float(item))
	return result


static func empty_obstacle_probe() -> Dictionary:
	var clearances = PackedFloat64Array()
	clearances.resize(OBSTACLE_RAY_COUNT)
	clearances.fill(OBSTACLE_RAY_MAXIMUM_DISTANCE_M)
	return {
		"nearest_direction_world": Vector3.ZERO,
		"nearest_direction_yaw_local": Vector3.ZERO,
		"nearest_distance_m": OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"maximum_distance_m": OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"closing_speed_mps": 0.0,
		"ray_clearances_m": clearances,
		"ray_maximum_distance_m": OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"target_path_blocked": false,
		"target_path_clearance_m": OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"target_path_maximum_distance_m": OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"target_wall_top_relative_height_m": 0.0,
		"wall_contact": false,
		"wall_contact_count": 0,
		"maximum_contact_impulse": 0.0,
	}
