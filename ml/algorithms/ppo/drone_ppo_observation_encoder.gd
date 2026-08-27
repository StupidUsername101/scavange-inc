class_name DronePPOObservationEncoder
extends RefCounted

const SCHEMA_VERSION: int = 10
const TURRET_SCHEMA_VERSION: int = 7
const TURRET_MASK_SCHEMA_VERSION: int = 8
const MANIPULATOR_SCHEMA_VERSION: int = 9
const BODY_INTERFACE_SCHEMA_VERSION: int = 10
const TARGET_SCHEMA_VERSION: int = 6
const LEGACY_SCHEMA_VERSION: int = 3
const MAZE_SCHEMA_VERSION: int = 4
const HEADING_SCHEMA_VERSION: int = 5
const SUPPORTED_SCHEMA_VERSIONS: Array[int] = [
	LEGACY_SCHEMA_VERSION,
	MAZE_SCHEMA_VERSION,
	HEADING_SCHEMA_VERSION,
	TARGET_SCHEMA_VERSION,
	TURRET_SCHEMA_VERSION,
	TURRET_MASK_SCHEMA_VERSION,
	MANIPULATOR_SCHEMA_VERSION,
	SCHEMA_VERSION,
]
const TRAINABLE_SCHEMA_VERSIONS: Array[int] = [
	MAZE_SCHEMA_VERSION,
	HEADING_SCHEMA_VERSION,
	TARGET_SCHEMA_VERSION,
	TURRET_SCHEMA_VERSION,
	TURRET_MASK_SCHEMA_VERSION,
	MANIPULATOR_SCHEMA_VERSION,
	SCHEMA_VERSION,
]
const QUAD_PROPELLER_COUNT: int = 4
const LEGACY_ACTOR_FEATURE_COUNT: int = 24
const LEGACY_CRITIC_FEATURE_COUNT: int = 25
const MAZE_ACTOR_FEATURE_COUNT: int = 34
const MAZE_CRITIC_FEATURE_COUNT: int = 35
const TARGET_ACTOR_FEATURE_COUNT: int = 41
const TARGET_CRITIC_FEATURE_COUNT: int = 42
const TURRET_ACTOR_FEATURE_COUNT: int = 50
const TURRET_CRITIC_FEATURE_COUNT: int = 51
const MANIPULATOR_ACTOR_FEATURE_COUNT: int = 54
const MANIPULATOR_CRITIC_FEATURE_COUNT: int = 55
# Schema 10 has a dynamic body block appended to the stable 50 task/navigation features.
const ACTOR_FEATURE_COUNT: int = TURRET_ACTOR_FEATURE_COUNT
const CRITIC_FEATURE_COUNT: int = TURRET_CRITIC_FEATURE_COUNT
const TARGET_OFFSET_SCALE_M: float = 16.0
const RELATIVE_VELOCITY_SCALE_MPS: float = 10.0
const ANGULAR_VELOCITY_SCALE_RADPS: float = 8.0
const TARGET_RADIUS_SCALE_M: float = 4.0
const GROUND_CLEARANCE_SCALE_M: float = 12.0
const TARGET_WALL_HEIGHT_SCALE_M: float = 8.0
const TURRET_THREAT_DISTANCE_SCALE_M: float = 80.0
const MAXIMUM_ROTOR_THRUST_RATIO: float = 1.5
const MINIMUM_DENOMINATOR: float = 0.000001
const NORMALIZED_LIMIT: float = 1.0
const NORMALIZED_TOLERANCE: float = 0.000001

const LEGACY_ACTOR_FEATURE_NAMES: Array[String] = [
	"target_offset_local_x",
	"target_offset_local_y",
	"target_offset_local_z",
	"target_relative_velocity_local_x",
	"target_relative_velocity_local_y",
	"target_relative_velocity_local_z",
	"angular_velocity_local_x",
	"angular_velocity_local_y",
	"angular_velocity_local_z",
	"gravity_up_local_x",
	"gravity_up_local_y",
	"gravity_up_local_z",
	"target_hover_radius",
	"ground_clearance",
	"available_power_ratio",
	"rotor_collective_feedback",
	"rotor_roll_feedback",
	"rotor_pitch_feedback",
	"rotor_yaw_feedback",
	"nearest_obstacle_direction_local_x",
	"nearest_obstacle_direction_local_y",
	"nearest_obstacle_direction_local_z",
	"nearest_obstacle_clearance",
	"target_path_blocked",
]
const ACTOR_FEATURE_NAMES: Array[String] = [
	"target_offset_local_x",
	"target_offset_local_y",
	"target_offset_local_z",
	"target_relative_velocity_local_x",
	"target_relative_velocity_local_y",
	"target_relative_velocity_local_z",
	"angular_velocity_local_x",
	"angular_velocity_local_y",
	"angular_velocity_local_z",
	"gravity_up_local_x",
	"gravity_up_local_y",
	"gravity_up_local_z",
	"target_hover_radius",
	"ground_clearance",
	"available_power_ratio",
	"rotor_collective_feedback",
	"rotor_roll_feedback",
	"rotor_pitch_feedback",
	"rotor_yaw_feedback",
	"nearest_obstacle_direction_local_x",
	"nearest_obstacle_direction_local_y",
	"nearest_obstacle_direction_local_z",
	"nearest_obstacle_clearance",
	"target_path_blocked",
	"wall_clearance_front",
	"wall_clearance_front_right",
	"wall_clearance_right",
	"wall_clearance_back_right",
	"wall_clearance_back",
	"wall_clearance_back_left",
	"wall_clearance_left",
	"wall_clearance_front_left",
	"target_path_clearance",
	"target_wall_top_relative_height",
	"target_present",
	"target_direction_local_x",
	"target_direction_local_y",
	"target_direction_local_z",
	"target_distance",
	"target_boundary_error",
	"target_inside_radius",
	"turret_present",
	"turret_direction_local_x",
	"turret_direction_local_y",
	"turret_direction_local_z",
	"turret_distance",
	"turret_line_of_sight",
	"turret_aim_alignment",
	"turret_cooldown_ready",
	"turret_threat_level",
]
const LEGACY_CRITIC_FEATURE_NAMES: Array[String] = [
	"target_offset_local_x",
	"target_offset_local_y",
	"target_offset_local_z",
	"target_relative_velocity_local_x",
	"target_relative_velocity_local_y",
	"target_relative_velocity_local_z",
	"angular_velocity_local_x",
	"angular_velocity_local_y",
	"angular_velocity_local_z",
	"gravity_up_local_x",
	"gravity_up_local_y",
	"gravity_up_local_z",
	"target_hover_radius",
	"ground_clearance",
	"available_power_ratio",
	"rotor_collective_feedback",
	"rotor_roll_feedback",
	"rotor_pitch_feedback",
	"rotor_yaw_feedback",
	"nearest_obstacle_direction_local_x",
	"nearest_obstacle_direction_local_y",
	"nearest_obstacle_direction_local_z",
	"nearest_obstacle_clearance",
	"target_path_blocked",
	"episode_progress",
]
const CRITIC_FEATURE_NAMES: Array[String] = [
	"target_offset_local_x",
	"target_offset_local_y",
	"target_offset_local_z",
	"target_relative_velocity_local_x",
	"target_relative_velocity_local_y",
	"target_relative_velocity_local_z",
	"angular_velocity_local_x",
	"angular_velocity_local_y",
	"angular_velocity_local_z",
	"gravity_up_local_x",
	"gravity_up_local_y",
	"gravity_up_local_z",
	"target_hover_radius",
	"ground_clearance",
	"available_power_ratio",
	"rotor_collective_feedback",
	"rotor_roll_feedback",
	"rotor_pitch_feedback",
	"rotor_yaw_feedback",
	"nearest_obstacle_direction_local_x",
	"nearest_obstacle_direction_local_y",
	"nearest_obstacle_direction_local_z",
	"nearest_obstacle_clearance",
	"target_path_blocked",
	"wall_clearance_front",
	"wall_clearance_front_right",
	"wall_clearance_right",
	"wall_clearance_back_right",
	"wall_clearance_back",
	"wall_clearance_back_left",
	"wall_clearance_left",
	"wall_clearance_front_left",
	"target_path_clearance",
	"target_wall_top_relative_height",
	"target_present",
	"target_direction_local_x",
	"target_direction_local_y",
	"target_direction_local_z",
	"target_distance",
	"target_boundary_error",
	"target_inside_radius",
	"episode_progress",
	"turret_present",
	"turret_direction_local_x",
	"turret_direction_local_y",
	"turret_direction_local_z",
	"turret_distance",
	"turret_line_of_sight",
	"turret_aim_alignment",
	"turret_cooldown_ready",
	"turret_threat_level",
]
const LEGACY_MANIPULATOR_FEATURE_NAMES: Array[String] = [
	"manipulator_present",
	"manipulator_grip_activation",
	"manipulator_candidate_present",
	"manipulator_attached",
]

#######################################################
# Schema 4 appends maze navigation, schema 5 fixes heading coordinates, schema 6 appends
# the explicit target contract, schema 7 appends a distinct turret-threat contract, and
# schema 8 masks optional turret detail channels to neutral whenever no turret is present.
# Schema 9 is retained for the old one-grip shortcut. Schema 10 appends a dynamic body-manifest feature block whose length is frozen only when the body build is accepted.
# A disabled subsystem should not inject several saturated constants into a simple hover task.
#######################################################


static func encode_actor(observation: Dictionary) -> PackedFloat64Array:
	return encode_actor_for_schema(observation, SCHEMA_VERSION)


static func encode_actor_for_schema(
	observation: Dictionary,
	schema_version: int,
	expected_body_feature_count: int = -1
) -> PackedFloat64Array:
	if not supports_schema(schema_version):
		return PackedFloat64Array()
	var result: PackedFloat64Array = PackedFloat64Array()
	var body: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	var electrical: Dictionary = observation.get("electrical", {})
	var environment: Dictionary = observation.get("environment", {})
	var parts: Dictionary = observation.get("parts", {})
	var basis: Basis = body.get("basis_world", Basis.IDENTITY)
	var inverse_basis: Basis = body.get("inverse_basis_world", basis.inverse())
	var position: Vector3 = body.get("position_world", Vector3.ZERO)
	var target_value: Variant = objective.get("target_position_world")
	if schema_version >= TARGET_SCHEMA_VERSION and not (target_value is Vector3):
		target_value = objective.get("movement_target")
	var target_present = target_value is Vector3
	var target = position
	if target_present:
		target = target_value as Vector3
	var target_velocity_value: Variant = objective.get("target_velocity_world")
	if schema_version >= TARGET_SCHEMA_VERSION and not (target_velocity_value is Vector3):
		target_velocity_value = objective.get("movement_target_velocity")
	var target_velocity_world = Vector3.ZERO
	if target_velocity_value is Vector3:
		target_velocity_world = target_velocity_value as Vector3
	var linear_velocity_local: Vector3 = body.get(
		"linear_velocity_local",
		Vector3.ZERO
	)
	var linear_velocity_world: Vector3 = body.get(
		"linear_velocity_world",
		basis * linear_velocity_local
	)
	if schema_version >= TARGET_SCHEMA_VERSION and not target_present:
		# An absent objective should not masquerade as a stationary target that is moving
		# backwards at the drone's own velocity.
		target_velocity_world = linear_velocity_world
	var target_offset_world = target - position
	# Keep the complete 3D objective. In particular, target_offset_local.y and the vertical part of
	# target_relative_velocity_local are the drone's target-height and climb/descent information.
	var target_offset_local: Vector3 = inverse_basis * target_offset_world
	var target_distance = target_offset_world.length()
	var target_direction_local = (
		inverse_basis * (target_offset_world / target_distance)
		if target_present and target_distance > MINIMUM_DENOMINATOR
		else Vector3.ZERO
	)
	var target_relative_velocity_local: Vector3 = inverse_basis * (
		target_velocity_world - linear_velocity_world
	)
	var gravity_up_local: Vector3 = inverse_basis * Vector3.UP
	var target_radius = float(objective.get("target_hover_radius_m", 0.0))
	if schema_version >= TARGET_SCHEMA_VERSION:
		target_radius = maxf(target_radius, 0.0)

	_append_scaled_vector(result, target_offset_local, TARGET_OFFSET_SCALE_M)
	_append_scaled_vector(
		result,
		target_relative_velocity_local,
		RELATIVE_VELOCITY_SCALE_MPS
	)
	var angular_velocity_local: Vector3 = body.get(
		"angular_velocity_local",
		Vector3.ZERO
	)
	_append_scaled_vector(result, angular_velocity_local, ANGULAR_VELOCITY_SCALE_RADPS)
	_append_unit_vector(result, gravity_up_local)
	result.append(_unsigned_to_signed(
		target_radius,
		TARGET_RADIUS_SCALE_M
	))
	result.append(_unsigned_to_signed(
		float(environment.get("ground_clearance_m", 0.0)),
		GROUND_CLEARANCE_SCALE_M
	))

	var core: Dictionary = parts.get("core", {})
	var maximum_power: float = maxf(
		float(core.get("maximum_power_throughput_w", 0.0)),
		MINIMUM_DENOMINATOR
	)
	result.append(_unsigned_to_signed(
		float(electrical.get("available_power_w", 0.0)),
		maximum_power
	))
	_append_rotor_modes(result, observation.get("propellers", []))
	var obstacle_probe: Dictionary = objective.get("obstacle_probe", {})
	var nearest_obstacle_direction: Vector3 = obstacle_probe.get(
		"nearest_direction_local",
		Vector3.ZERO
	)
	if schema_version >= HEADING_SCHEMA_VERSION:
		nearest_obstacle_direction = obstacle_probe.get(
			"nearest_direction_yaw_local",
			nearest_obstacle_direction
		)
	_append_unit_vector(result, nearest_obstacle_direction)
	result.append(_unsigned_to_signed(
		float(obstacle_probe.get("nearest_distance_m", 0.0)),
		maxf(float(obstacle_probe.get("maximum_distance_m", 1.0)), MINIMUM_DENOMINATOR)
	))
	result.append(_unit_interval_to_signed(
		1.0 if bool(obstacle_probe.get("target_path_blocked", false)) else 0.0
	))

	if schema_version >= MAZE_SCHEMA_VERSION:
		_append_sector_clearances(result, obstacle_probe)
		result.append(_unsigned_to_signed(
			float(obstacle_probe.get("target_path_clearance_m", 0.0)),
			maxf(
				float(obstacle_probe.get("target_path_maximum_distance_m", 1.0)),
				MINIMUM_DENOMINATOR
			)
		))
		result.append(_scaled_signed(
			float(obstacle_probe.get("target_wall_top_relative_height_m", 0.0)),
			TARGET_WALL_HEIGHT_SCALE_M
		))

	if schema_version >= TARGET_SCHEMA_VERSION:
		result.append(_unit_interval_to_signed(1.0 if target_present else 0.0))
		_append_unit_vector(result, target_direction_local)
		result.append(_unsigned_to_signed(target_distance, TARGET_OFFSET_SCALE_M))
		result.append(_scaled_signed(
			target_distance - target_radius,
			TARGET_OFFSET_SCALE_M
		))
		result.append(_unit_interval_to_signed(
			1.0 if target_present and target_distance <= target_radius else 0.0
		))
	if schema_version >= TURRET_SCHEMA_VERSION:
		_append_turret_threat(
			result,
			objective.get("turret_threat_probe", {}),
			schema_version >= TURRET_MASK_SCHEMA_VERSION
		)
	if schema_version == MANIPULATOR_SCHEMA_VERSION:
		_append_manipulator_state(result, observation.get("manipulator", {}))
	elif schema_version >= BODY_INTERFACE_SCHEMA_VERSION:
		var body_features_value: Variant = observation.get("model_body_features", PackedFloat64Array())
		if body_features_value is PackedFloat64Array:
			var body_features64: PackedFloat64Array = body_features_value
			result.append_array(body_features64)
		elif body_features_value is PackedFloat32Array:
			var body_features32: PackedFloat32Array = body_features_value
			for value: float in body_features32:
				result.append(value)
		elif body_features_value is Array:
			var body_features_array: Array = body_features_value
			for value: Variant in body_features_array:
				result.append(float(value) if value is int or value is float else NAN)
		if expected_body_feature_count >= 0 and result.size() != TURRET_ACTOR_FEATURE_COUNT + expected_body_feature_count:
			return PackedFloat64Array()
	return result


static func encode_critic(observation: Dictionary) -> PackedFloat64Array:
	return encode_critic_for_schema(observation, SCHEMA_VERSION)


static func encode_critic_for_schema(
	observation: Dictionary,
	schema_version: int,
	expected_body_feature_count: int = -1
) -> PackedFloat64Array:
	var actor_features = encode_actor_for_schema(observation, schema_version, expected_body_feature_count)
	return encode_critic_from_actor_for_schema(
		actor_features,
		observation,
		schema_version,
		expected_body_feature_count
	)


static func encode_critic_from_actor(
	actor_features: PackedFloat64Array,
	observation: Dictionary
) -> PackedFloat64Array:
	return encode_critic_from_actor_for_schema(
		actor_features,
		observation,
		SCHEMA_VERSION
	)


static func encode_critic_from_actor_for_schema(
	actor_features: PackedFloat64Array,
	observation: Dictionary,
	schema_version: int,
	expected_body_feature_count: int = -1
) -> PackedFloat64Array:
	var body_feature_count: int = expected_body_feature_count
	if body_feature_count < 0 and schema_version >= BODY_INTERFACE_SCHEMA_VERSION:
		body_feature_count = maxi(actor_features.size() - TURRET_ACTOR_FEATURE_COUNT, 0)
	body_feature_count = maxi(body_feature_count, 0)
	if actor_features.size() != actor_feature_count_for_schema(schema_version, body_feature_count):
		return PackedFloat64Array()
	var objective: Dictionary = observation.get("objective", {})
	var episode_progress = _unit_interval_to_signed(
		float(objective.get("episode_progress", 0.0))
	)
	if schema_version >= TURRET_SCHEMA_VERSION:
		# Keep the complete schema-6 critic tensor as the first 42 columns. Turret
		# features are appended after episode progress so zero-column migration is exact.
		var result = _slice_packed(actor_features, 0, TARGET_ACTOR_FEATURE_COUNT)
		result.append(episode_progress)
		result.append_array(_slice_packed(
			actor_features,
			TARGET_ACTOR_FEATURE_COUNT,
			actor_feature_count_for_schema(schema_version, body_feature_count) - TARGET_ACTOR_FEATURE_COUNT
		))
		return result
	var result: PackedFloat64Array = actor_features.duplicate()
	result.append(episode_progress)
	return result


static func is_valid_quad_observation(observation: Dictionary) -> bool:
	if not has_valid_quad_topology(observation):
		return false
	var actor_features = encode_actor(observation)
	var body_feature_count: int = maxi(actor_features.size() - TURRET_ACTOR_FEATURE_COUNT, 0)
	var critic_features = encode_critic_from_actor_for_schema(
		actor_features,
		observation,
		SCHEMA_VERSION,
		body_feature_count
	)
	return are_valid_encoded_tensors(
		actor_features,
		critic_features,
		SCHEMA_VERSION,
		body_feature_count
	)


static func has_valid_propeller_topology(observation: Dictionary) -> bool:
	var propellers: Array = observation.get("propellers", [])
	for index: int in range(propellers.size()):
		if not (propellers[index] is Dictionary):
			return false
		var propeller: Dictionary = propellers[index]
		if int(propeller.get("slot_index", -1)) != index:
			return false
	return true


static func has_valid_quad_topology(observation: Dictionary) -> bool:
	# The policy owns four stable *slots*, not four guaranteed-working propellers. A damaged
	# or intentionally degraded drone must keep producing one command per slot so the remaining
	# motors can compensate. Missing hardware is represented by installed=false and zero realized
	# thrust; rejecting that observation here made every degraded-propeller evaluation (and any
	# live drone that lost a propeller) return an empty action.
	var propellers: Array = observation.get("propellers", [])
	if propellers.size() != QUAD_PROPELLER_COUNT:
		return false
	for index: int in range(QUAD_PROPELLER_COUNT):
		if not (propellers[index] is Dictionary):
			return false
		var propeller: Dictionary = propellers[index]
		if int(propeller.get("slot_index", -1)) != index:
			return false
	return true


static func are_valid_encoded_tensors(
	actor_features: PackedFloat64Array,
	critic_features: PackedFloat64Array,
	schema_version: int = SCHEMA_VERSION,
	body_feature_count: int = 0
) -> bool:
	return (
		supports_schema(schema_version)
		and actor_features.size() == actor_feature_count_for_schema(schema_version, body_feature_count)
		and critic_features.size() == critic_feature_count_for_schema(schema_version, body_feature_count)
		and (
			schema_version >= BODY_INTERFACE_SCHEMA_VERSION
			or feature_names_for_schema(schema_version).size()
			== actor_feature_count_for_schema(schema_version)
		)
		and (
			schema_version >= BODY_INTERFACE_SCHEMA_VERSION
			or critic_feature_names_for_schema(schema_version).size()
			== critic_feature_count_for_schema(schema_version)
		)
		and is_normalized_tensor(actor_features)
		and is_normalized_tensor(critic_features)
	)


static func supports_schema(schema_version: int) -> bool:
	return SUPPORTED_SCHEMA_VERSIONS.has(schema_version)


static func is_trainable_schema(schema_version: int) -> bool:
	return TRAINABLE_SCHEMA_VERSIONS.has(schema_version)


static func actor_feature_count_for_schema(schema_version: int, body_feature_count: int = 0) -> int:
	match schema_version:
		LEGACY_SCHEMA_VERSION:
			return LEGACY_ACTOR_FEATURE_COUNT
		MAZE_SCHEMA_VERSION, HEADING_SCHEMA_VERSION:
			return MAZE_ACTOR_FEATURE_COUNT
		TARGET_SCHEMA_VERSION:
			return TARGET_ACTOR_FEATURE_COUNT
		TURRET_SCHEMA_VERSION, TURRET_MASK_SCHEMA_VERSION:
			return TURRET_ACTOR_FEATURE_COUNT
		MANIPULATOR_SCHEMA_VERSION:
			return MANIPULATOR_ACTOR_FEATURE_COUNT
		SCHEMA_VERSION:
			return TURRET_ACTOR_FEATURE_COUNT + maxi(body_feature_count, 0)
	return 0


static func critic_feature_count_for_schema(schema_version: int, body_feature_count: int = 0) -> int:
	match schema_version:
		LEGACY_SCHEMA_VERSION:
			return LEGACY_CRITIC_FEATURE_COUNT
		MAZE_SCHEMA_VERSION, HEADING_SCHEMA_VERSION:
			return MAZE_CRITIC_FEATURE_COUNT
		TARGET_SCHEMA_VERSION:
			return TARGET_CRITIC_FEATURE_COUNT
		TURRET_SCHEMA_VERSION, TURRET_MASK_SCHEMA_VERSION:
			return TURRET_CRITIC_FEATURE_COUNT
		MANIPULATOR_SCHEMA_VERSION:
			return MANIPULATOR_CRITIC_FEATURE_COUNT
		SCHEMA_VERSION:
			return TURRET_CRITIC_FEATURE_COUNT + maxi(body_feature_count, 0)
	return 0

static func feature_names_for_schema(schema_version: int) -> Array[String]:
	match schema_version:
		LEGACY_SCHEMA_VERSION:
			return LEGACY_ACTOR_FEATURE_NAMES
		MAZE_SCHEMA_VERSION, HEADING_SCHEMA_VERSION:
			return _maze_actor_feature_names()
		TARGET_SCHEMA_VERSION:
			return _target_actor_feature_names()
		TURRET_SCHEMA_VERSION, TURRET_MASK_SCHEMA_VERSION:
			return _turret_actor_feature_names()
		MANIPULATOR_SCHEMA_VERSION:
			return _manipulator_actor_feature_names()
		SCHEMA_VERSION:
			return _turret_actor_feature_names()
	return []


static func critic_feature_names_for_schema(schema_version: int) -> Array[String]:
	match schema_version:
		LEGACY_SCHEMA_VERSION:
			return LEGACY_CRITIC_FEATURE_NAMES
		MAZE_SCHEMA_VERSION, HEADING_SCHEMA_VERSION:
			return _maze_critic_feature_names()
		TARGET_SCHEMA_VERSION:
			return _target_critic_feature_names()
		TURRET_SCHEMA_VERSION, TURRET_MASK_SCHEMA_VERSION:
			return _turret_critic_feature_names()
		MANIPULATOR_SCHEMA_VERSION:
			return _manipulator_critic_feature_names()
		SCHEMA_VERSION:
			return _turret_critic_feature_names()
	return []


static func _maze_actor_feature_names() -> Array[String]:
	var result: Array[String] = []
	for index in range(MAZE_ACTOR_FEATURE_COUNT):
		result.append(ACTOR_FEATURE_NAMES[index])
	return result


static func _maze_critic_feature_names() -> Array[String]:
	var result = _maze_actor_feature_names()
	result.append("episode_progress")
	return result


static func _target_actor_feature_names() -> Array[String]:
	var result: Array[String] = []
	for index in range(TARGET_ACTOR_FEATURE_COUNT):
		result.append(ACTOR_FEATURE_NAMES[index])
	return result


static func _target_critic_feature_names() -> Array[String]:
	var result = _target_actor_feature_names()
	result.append("episode_progress")
	return result


static func _turret_actor_feature_names() -> Array[String]:
	var result: Array[String] = []
	for index in range(TURRET_ACTOR_FEATURE_COUNT):
		result.append(ACTOR_FEATURE_NAMES[index])
	return result


static func _turret_critic_feature_names() -> Array[String]:
	var result: Array[String] = []
	for index in range(TARGET_ACTOR_FEATURE_COUNT):
		result.append(ACTOR_FEATURE_NAMES[index])
	result.append("episode_progress")
	for index in range(TARGET_ACTOR_FEATURE_COUNT, TURRET_ACTOR_FEATURE_COUNT):
		result.append(ACTOR_FEATURE_NAMES[index])
	return result


static func _manipulator_actor_feature_names() -> Array[String]:
	var result: Array[String] = _turret_actor_feature_names()
	result.append_array(LEGACY_MANIPULATOR_FEATURE_NAMES)
	return result


static func _manipulator_critic_feature_names() -> Array[String]:
	var result: Array[String] = _turret_critic_feature_names()
	result.append_array(LEGACY_MANIPULATOR_FEATURE_NAMES)
	return result


static func _append_manipulator_state(
	target: PackedFloat64Array,
	state_value: Variant
) -> void:
	var state: Dictionary = state_value if state_value is Dictionary else {}
	var present = bool(state.get("present", false))
	target.append(_unit_interval_to_signed(1.0 if present else 0.0))
	if not present:
		# Conditional details are neutral when the optional hardware is absent.
		for _index in range(3):
			target.append(0.0)
		return
	target.append(_unit_interval_to_signed(clampf(
		float(state.get("grip_activation", 0.0)), 0.0, 1.0
	)))
	target.append(_unit_interval_to_signed(
		1.0 if bool(state.get("candidate_present", false)) else 0.0
	))
	target.append(_unit_interval_to_signed(
		1.0 if bool(state.get("attached", false)) else 0.0
	))


static func _append_turret_threat(
	target: PackedFloat64Array,
	probe: Dictionary,
	neutralize_absent_details: bool
) -> void:
	var present = bool(probe.get("present", false))
	target.append(_unit_interval_to_signed(1.0 if present else 0.0))
	var direction: Vector3 = probe.get("direction_local", Vector3.ZERO)
	_append_unit_vector(target, direction if present else Vector3.ZERO)
	if not present and neutralize_absent_details:
		# Presence already carries the only meaningful information. Zero is the neutral value
		# for every conditional detail so ordinary no-turret flight does not spend capacity
		# learning around a block of permanent +/-1 inputs.
		for _index in range(5):
			target.append(0.0)
		return
	target.append(_unsigned_to_signed(
		float(probe.get("distance_m", TURRET_THREAT_DISTANCE_SCALE_M)),
		maxf(float(probe.get("maximum_distance_m", TURRET_THREAT_DISTANCE_SCALE_M)), 0.1)
	))
	target.append(_unit_interval_to_signed(
		1.0 if present and bool(probe.get("line_of_sight", false)) else 0.0
	))
	target.append(clampf(float(probe.get("aim_alignment", -1.0)), -1.0, 1.0))
	target.append(_unit_interval_to_signed(
		clampf(float(probe.get("cooldown_ready_ratio", 0.0)), 0.0, 1.0)
	))
	target.append(_unit_interval_to_signed(
		clampf(float(probe.get("threat_level", 0.0)), 0.0, 1.0)
	))


static func _slice_packed(
	values: PackedFloat64Array,
	start: int,
	count: int
) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(count)
	for index in range(count):
		result[index] = values[start + index]
	return result


static func is_normalized_tensor(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if (
			not is_finite(value)
			or value < -NORMALIZED_LIMIT - NORMALIZED_TOLERANCE
			or value > NORMALIZED_LIMIT + NORMALIZED_TOLERANCE
		):
			return false
	return true


static func _append_sector_clearances(
	target: PackedFloat64Array,
	obstacle_probe: Dictionary
) -> void:
	var values: Variant = obstacle_probe.get("sector_clearances_m", [])
	var maximum = maxf(
		float(obstacle_probe.get("sector_maximum_distance_m", 1.0)),
		MINIMUM_DENOMINATOR
	)
	var packed_values = PackedFloat64Array()
	var array_values: Array = []
	if values is PackedFloat64Array:
		packed_values = values
	elif values is Array:
		array_values = values
	for index in range(DroneTrainingObstacleSensor.SECTOR_COUNT):
		var clearance = maximum
		if index < packed_values.size():
			clearance = float(packed_values[index])
		elif index < array_values.size():
			clearance = float(array_values[index])
		target.append(_unsigned_to_signed(clearance, maximum))


static func _append_rotor_modes(target: PackedFloat64Array, propellers: Array) -> void:
	# Existing stock quads keep their exact historical feature semantics. Creator-authored layouts
	# may reorder the four rotors or point them along arbitrary Core surfaces, so those bodies use
	# geometry-aware force/torque aggregates instead of pretending slot 0 is always front-left.
	if _uses_legacy_quad_layout(propellers):
		var front_left: float = _normalized_rotor_thrust(propellers[0])
		var front_right: float = _normalized_rotor_thrust(propellers[1])
		var back_left: float = _normalized_rotor_thrust(propellers[2])
		var back_right: float = _normalized_rotor_thrust(propellers[3])
		var collective_quad: float = (front_left + front_right + back_left + back_right) * 0.25
		var roll_quad: float = (front_left + front_right - back_left - back_right) * 0.5
		var pitch_quad: float = (-front_left + front_right - back_left + back_right) * 0.5
		var yaw_quad: float = (front_left - front_right - back_left + back_right) * 0.5
		target.append(_unit_interval_to_signed(collective_quad))
		target.append(clampf(roll_quad, -1.0, 1.0))
		target.append(clampf(pitch_quad, -1.0, 1.0))
		target.append(clampf(yaw_quad, -1.0, 1.0))
		return
	if propellers.is_empty():
		target.append(-1.0)
		target.append(0.0)
		target.append(0.0)
		target.append(0.0)
		return
	var collective_up: float = 0.0
	var torque_sum: Vector3 = Vector3.ZERO
	var yaw_reaction: float = 0.0
	var lever_scale: float = 0.000001
	for propeller_value: Variant in propellers:
		var propeller: Dictionary = propeller_value as Dictionary
		var position: Vector3 = propeller.get("position_local", Vector3.ZERO)
		lever_scale = maxf(lever_scale, position.length())
	for propeller_value: Variant in propellers:
		var propeller: Dictionary = propeller_value as Dictionary
		var thrust: float = _normalized_rotor_thrust(propeller)
		var position: Vector3 = propeller.get("position_local", Vector3.ZERO)
		var lift_axis: Vector3 = propeller.get("lift_axis_local", Vector3.UP)
		if not lift_axis.is_finite() or lift_axis.length_squared() <= 0.000001:
			lift_axis = Vector3.UP
		lift_axis = lift_axis.normalized()
		var normalized_force: Vector3 = lift_axis * thrust
		collective_up += normalized_force.y
		torque_sum += position.cross(normalized_force) / lever_scale
		yaw_reaction += float(propeller.get("spin_direction", 0.0)) * thrust
	var count: float = float(propellers.size())
	# These four columns keep the same fixed tensor width, but for a custom body they now describe
	# the actual current body-space force/torque tendency rather than a fictional stock-X mixer.
	target.append(clampf(collective_up / count, -1.0, 1.0))
	target.append(clampf(torque_sum.x / count, -1.0, 1.0))
	target.append(clampf(torque_sum.z / count, -1.0, 1.0))
	target.append(clampf((torque_sum.y / count) + (yaw_reaction / count), -1.0, 1.0))


static func _uses_legacy_quad_layout(propellers: Array) -> bool:
	if propellers.size() != QUAD_PROPELLER_COUNT:
		return false
	# Schema-era observations/checkpoint tests created before free rotor placement have no geometry
	# keys at all. Treat that exact case as the historical stock quad rather than changing its inputs.
	var has_any_geometry: bool = false
	for propeller_value: Variant in propellers:
		if not (propeller_value is Dictionary):
			return false
		var geometry_probe: Dictionary = propeller_value as Dictionary
		if geometry_probe.has("position_local") or geometry_probe.has("lift_axis_local"):
			has_any_geometry = true
	if not has_any_geometry:
		return true
	var expected_x_signs: Array[int] = [-1, 1, -1, 1]
	var expected_z_signs: Array[int] = [-1, -1, 1, 1]
	for index: int in range(QUAD_PROPELLER_COUNT):
		if not (propellers[index] is Dictionary):
			return false
		var propeller: Dictionary = propellers[index]
		var position: Vector3 = propeller.get("position_local", Vector3.ZERO)
		var lift_axis: Vector3 = propeller.get("lift_axis_local", Vector3.UP)
		if not position.is_finite() or not lift_axis.is_finite():
			return false
		if absf(position.x) <= 0.000001 or absf(position.z) <= 0.000001:
			return false
		if (position.x < 0.0) != (expected_x_signs[index] < 0):
			return false
		if (position.z < 0.0) != (expected_z_signs[index] < 0):
			return false
		if lift_axis.normalized().dot(Vector3.UP) < 0.999:
			return false
	return true


static func _normalized_rotor_thrust(propeller: Dictionary) -> float:
	var maximum_thrust: float = maxf(
		float(propeller.get("maximum_static_thrust_n", 0.0)),
		MINIMUM_DENOMINATOR
	)
	return clampf(
		float(propeller.get("realized_thrust_n", 0.0))
		/ maximum_thrust
		/ MAXIMUM_ROTOR_THRUST_RATIO,
		0.0,
		1.0
	)


static func _append_scaled_vector(
	target: PackedFloat64Array,
	value: Vector3,
	scale: float
) -> void:
	target.append(_scaled_signed(value.x, scale))
	target.append(_scaled_signed(value.y, scale))
	target.append(_scaled_signed(value.z, scale))


static func _append_unit_vector(target: PackedFloat64Array, value: Vector3) -> void:
	var normalized: Vector3 = value.normalized()
	target.append(clampf(normalized.x, -1.0, 1.0))
	target.append(clampf(normalized.y, -1.0, 1.0))
	target.append(clampf(normalized.z, -1.0, 1.0))


static func _scaled_signed(value: float, scale: float) -> float:
	var safe_scale: float = maxf(absf(scale), MINIMUM_DENOMINATOR)
	return clampf(value / safe_scale, -1.0, 1.0)


static func _unsigned_to_signed(value: float, maximum: float) -> float:
	var safe_maximum: float = maxf(absf(maximum), MINIMUM_DENOMINATOR)
	return _unit_interval_to_signed(clampf(value / safe_maximum, 0.0, 1.0))


static func _unit_interval_to_signed(value: float) -> float:
	return clampf(value, 0.0, 1.0) * 2.0 - 1.0
