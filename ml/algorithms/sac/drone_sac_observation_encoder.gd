class_name DroneSACObservationEncoder
extends RefCounted

const SCHEMA_VERSION = 6
const LEGACY_SCHEMA_VERSION = 4
const TARGET_FORWARD_FEATURE_INDEX = 2
const TARGET_RELATIVE_FORWARD_VELOCITY_FEATURE_INDEX = 5
const FORWARD_TILT_RATE_FEATURE_INDEX = 6
const RIGHT_TILT_RATE_FEATURE_INDEX = 8
const RIGHT_TILT_FEATURE_INDEX = 9
const FORWARD_TILT_FEATURE_INDEX = 11
const ROTOR_LEGACY_FRONT_MINUS_BACK_FEATURE_INDEX = 16
const ROTOR_LEGACY_RIGHT_MINUS_LEFT_FEATURE_INDEX = 17
const NEAREST_OBSTACLE_FORWARD_FEATURE_INDEX = 21
const TARGET_PRESENT_FEATURE_INDEX = DronePPOObservationEncoder.MAZE_ACTOR_FEATURE_COUNT
const TARGET_DIRECTION_FORWARD_FEATURE_INDEX = TARGET_PRESENT_FEATURE_INDEX + 3
const LEGACY_BASE_FEATURE_COUNT = DronePPOObservationEncoder.TARGET_ACTOR_FEATURE_COUNT
const TURRET_THREAT_FEATURE_COUNT = (
	DronePPOObservationEncoder.ACTOR_FEATURE_COUNT - LEGACY_BASE_FEATURE_COUNT
)
const LEGACY_ACTOR_FEATURE_COUNT = (
	LEGACY_BASE_FEATURE_COUNT + DroneSACNavigationMemory.FEATURE_COUNT
)
const ACTOR_FEATURE_COUNT = LEGACY_ACTOR_FEATURE_COUNT + TURRET_THREAT_FEATURE_COUNT
const LEGACY_CRITIC_FEATURE_COUNT = LEGACY_ACTOR_FEATURE_COUNT + 1
const CRITIC_FEATURE_COUNT = LEGACY_CRITIC_FEATURE_COUNT + TURRET_THREAT_FEATURE_COUNT
const ACTION_COUNT = 4
const LEGACY_Q_INPUT_COUNT = LEGACY_CRITIC_FEATURE_COUNT + ACTION_COUNT
const Q_INPUT_COUNT = LEGACY_Q_INPUT_COUNT + TURRET_THREAT_FEATURE_COUNT


static func encode_actor(
	observation: Dictionary,
	memory_features: PackedFloat64Array
) -> PackedFloat64Array:
	if memory_features.size() != DroneSACNavigationMemory.FEATURE_COUNT:
		return PackedFloat64Array()
	var base = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		DronePPOObservationEncoder.TURRET_MASK_SCHEMA_VERSION
	)
	if base.size() != DronePPOObservationEncoder.ACTOR_FEATURE_COUNT:
		return PackedFloat64Array()
	# PPO keeps Godot's raw local-Z convention and legacy rotor-mode labels for
	# checkpoint compatibility. SAC uses an intuitive positive-forward/right coordinate
	# convention for navigation observations. This does not change the raw-propeller
	# action contract; each actor output still controls exactly one rotor.
	base[TARGET_FORWARD_FEATURE_INDEX] = -base[TARGET_FORWARD_FEATURE_INDEX]
	base[TARGET_RELATIVE_FORWARD_VELOCITY_FEATURE_INDEX] = (
		-base[TARGET_RELATIVE_FORWARD_VELOCITY_FEATURE_INDEX]
	)
	base[FORWARD_TILT_RATE_FEATURE_INDEX] = -base[FORWARD_TILT_RATE_FEATURE_INDEX]
	base[RIGHT_TILT_RATE_FEATURE_INDEX] = -base[RIGHT_TILT_RATE_FEATURE_INDEX]
	base[RIGHT_TILT_FEATURE_INDEX] = -base[RIGHT_TILT_FEATURE_INDEX]
	base[NEAREST_OBSTACLE_FORWARD_FEATURE_INDEX] = (
		-base[NEAREST_OBSTACLE_FORWARD_FEATURE_INDEX]
	)
	base[TARGET_DIRECTION_FORWARD_FEATURE_INDEX] = (
		-base[TARGET_DIRECTION_FORWARD_FEATURE_INDEX]
	)
	var legacy_front_minus_back = base[ROTOR_LEGACY_FRONT_MINUS_BACK_FEATURE_INDEX]
	var legacy_right_minus_left = base[ROTOR_LEGACY_RIGHT_MINUS_LEFT_FEATURE_INDEX]
	base[ROTOR_LEGACY_FRONT_MINUS_BACK_FEATURE_INDEX] = -legacy_right_minus_left
	base[ROTOR_LEGACY_RIGHT_MINUS_LEFT_FEATURE_INDEX] = -legacy_front_minus_back
	var aligned_memory = memory_features.duplicate()
	aligned_memory[aligned_memory.size() - 1] = -aligned_memory[aligned_memory.size() - 1]
	# Preserve schema-4 columns exactly: target/navigation base, then memory. Turret
	# perception is appended after those columns so every old SAC network can migrate
	# with zero new first-layer weights and identical initial behavior.
	var result = _slice(base, 0, LEGACY_BASE_FEATURE_COUNT)
	result.append_array(aligned_memory)
	result.append_array(_slice(
		base,
		LEGACY_BASE_FEATURE_COUNT,
		TURRET_THREAT_FEATURE_COUNT
	))
	return result


static func encode_critic_from_actor(
	actor_input: PackedFloat64Array,
	observation: Dictionary
) -> PackedFloat64Array:
	if actor_input.size() != ACTOR_FEATURE_COUNT:
		return PackedFloat64Array()
	var result = _slice(actor_input, 0, LEGACY_ACTOR_FEATURE_COUNT)
	var objective: Dictionary = observation.get("objective", {})
	result.append(clampf(float(objective.get("episode_progress", 0.0)), 0.0, 1.0) * 2.0 - 1.0)
	result.append_array(_slice(
		actor_input,
		LEGACY_ACTOR_FEATURE_COUNT,
		TURRET_THREAT_FEATURE_COUNT
	))
	return result


static func q_input(
	critic_input: PackedFloat64Array,
	policy_actions: PackedFloat64Array
) -> PackedFloat64Array:
	if (
		critic_input.size() != CRITIC_FEATURE_COUNT
		or policy_actions.size() != ACTION_COUNT
		or not DronePPOObservationEncoder.is_normalized_tensor(policy_actions)
	):
		return PackedFloat64Array()
	var result = _slice(critic_input, 0, LEGACY_CRITIC_FEATURE_COUNT)
	for policy_action in policy_actions:
		result.append(clampf(float(policy_action), -1.0, 1.0))
	result.append_array(_slice(
		critic_input,
		LEGACY_CRITIC_FEATURE_COUNT,
		TURRET_THREAT_FEATURE_COUNT
	))
	return result


static func valid_tensors(
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array
) -> bool:
	return (
		actor_input.size() == ACTOR_FEATURE_COUNT
		and critic_input.size() == CRITIC_FEATURE_COUNT
		and DronePPOObservationEncoder.is_normalized_tensor(actor_input)
		and DronePPOObservationEncoder.is_normalized_tensor(critic_input)
	)


static func actor_feature_names() -> Array[String]:
	var base: Array[String] = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.duplicate()
	base[TARGET_FORWARD_FEATURE_INDEX] = "target_offset_local_forward"
	base[TARGET_RELATIVE_FORWARD_VELOCITY_FEATURE_INDEX] = "target_relative_velocity_local_forward"
	base[FORWARD_TILT_RATE_FEATURE_INDEX] = "body_forward_tilt_rate"
	base[RIGHT_TILT_RATE_FEATURE_INDEX] = "body_right_tilt_rate"
	base[RIGHT_TILT_FEATURE_INDEX] = "body_right_tilt"
	base[FORWARD_TILT_FEATURE_INDEX] = "body_forward_tilt"
	base[ROTOR_LEGACY_FRONT_MINUS_BACK_FEATURE_INDEX] = "rotor_move_right_feedback"
	base[ROTOR_LEGACY_RIGHT_MINUS_LEFT_FEATURE_INDEX] = "rotor_move_forward_feedback"
	base[NEAREST_OBSTACLE_FORWARD_FEATURE_INDEX] = "nearest_obstacle_direction_local_forward"
	base[TARGET_DIRECTION_FORWARD_FEATURE_INDEX] = "target_direction_local_forward"
	var result: Array[String] = []
	for index in range(LEGACY_BASE_FEATURE_COUNT):
		result.append(base[index])
	result.append("visit_density_current")
	for name in ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]:
		result.append("visit_density_near_%s" % name)
	for name in ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]:
		result.append("visit_density_far_%s" % name)
	result.append("least_visited_heading_local_x")
	result.append("least_visited_heading_local_forward")
	for index in range(LEGACY_BASE_FEATURE_COUNT, base.size()):
		result.append(base[index])
	return result


static func _slice(values: PackedFloat64Array, start: int, count: int) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(count)
	for index in range(count):
		result[index] = values[start + index]
	return result
