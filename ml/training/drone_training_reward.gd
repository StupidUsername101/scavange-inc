class_name DroneTrainingReward
extends RefCounted

const SCHEMA_VERSION = 6
const APPROACH_NORMALIZATION_DISTANCE_M = 10.0
const APPROACH_REWARD_WEIGHT = 1.0
const TARGET_SEARCH_COST_PER_SECOND = 0.01
const RADIUS_REWARD_PER_SECOND = 1.0
const ACTION_SMOOTHNESS_WEIGHT = 0.02
const SMOOTHNESS_REFERENCE_INTERVAL_SECONDS = 0.05
const ACTION_CHANGE_DEADBAND = 0.04
const ACTION_ABUSE_EXTREME_LOW = 0.02
const ACTION_ABUSE_EXTREME_HIGH = 0.98
const ACTION_ABUSE_SPREAD_START = 0.75
const ACTION_ABUSE_GRACE_SECONDS = 0.25
const ACTION_ABUSE_WEIGHT_PER_SECOND = 0.08
const SURVIVAL_REWARD_BUDGET_PER_SECOND = 0.01
const SURVIVAL_REWARD_MAX_PER_EPISODE = 0.20
const GROUND_SAFETY_HEIGHT_M = 2.0
const GROUND_CRITICAL_HEIGHT_M = 0.65
const GROUND_DESCENT_SPEED_SCALE_MPS = 2.5
const GROUND_DESCENT_WEIGHT_PER_SECOND = 0.30
const GROUND_PROXIMITY_WEIGHT_PER_SECOND = 0.04
const GROUND_CRITICAL_WEIGHT_PER_SECOND = 0.05
const OBSTACLE_DANGER_DISTANCE_M = 1.25
const OBSTACLE_CLOSING_SPEED_SCALE_MPS = 3.0
const OBSTACLE_PROXIMITY_WEIGHT_PER_SECOND = 0.25
const OBSTACLE_CONTACT_DISTANCE_M = 0.18
const OBSTACLE_CONTACT_RELEASE_DISTANCE_M = 0.3
const OBSTACLE_CONTACT_MINIMUM_SPEED_MPS = 0.25
const OBSTACLE_CONTACT_PENALTY = 0.15
const TURRET_HIT_PENALTY_PER_HIT = 0.65
const TURRET_DAMAGE_PENALTY_PER_POINT = 0.025
const TURRET_EXPOSURE_PENALTY_PER_SECOND = 0.08
const MIN_DIRECTION_LENGTH_SQUARED = 0.000001
const DEFAULT_COMPONENTS = {
	"approach": true,
	"radius": true,
	"survival": true,
	"ground_safety": true,
	"smoothness": true,
	"obstacle": true,
	"turret_safety": true,
	"failure": true,
}

#######################################################
# Scores target-directed drone movement and sustained presence inside the accepted hover
# radius. It exposes each normalized component separately for training diagnostics.
#######################################################

var initialized = false
var previous_drone_position = Vector3.ZERO
var previous_target_position = Vector3.ZERO
var previous_target_radius = 0.0
var episode_duration_seconds = 20.0
var total_reward = 0.0
var elapsed_seconds = 0.0
var time_inside_radius_seconds = 0.0
var previous_actions: Array[float] = []
var seconds_since_action_change = 0.0
var action_abuse_seconds = 0.0
var _latest_action_abuse_reward = 0.0
var obstacle_contact_active = false
var cumulative_approach_reward = 0.0
var cumulative_progress_reward = 0.0
var cumulative_search_cost_reward = 0.0
var cumulative_radius_reward = 0.0
var cumulative_survival_reward = 0.0
var cumulative_ground_safety_reward = 0.0
var cumulative_smoothness_reward = 0.0
var cumulative_action_abuse_reward = 0.0
var cumulative_obstacle_reward = 0.0
var cumulative_turret_safety_reward = 0.0
var _latest_turret_safety_reward = 0.0
var latest_result: Dictionary = {}
var enabled_components: Dictionary = DEFAULT_COMPONENTS.duplicate()
var component_intensities: Dictionary = {}


func configure_components(components: Dictionary) -> void:
	enabled_components = DEFAULT_COMPONENTS.duplicate()
	component_intensities.clear()
	for key in DEFAULT_COMPONENTS:
		component_intensities[key] = 1.0
		if not components.has(key):
			continue
		var configured_value = components[key]
		if configured_value is Dictionary:
			enabled_components[key] = bool(configured_value.get("enabled", true))
			component_intensities[key] = maxf(
				RLTrainingMath.finite_float_or(
					configured_value.get("intensity"),
					1.0
				),
				0.0
			)
		else:
			enabled_components[key] = bool(configured_value)


func is_component_enabled(component: String) -> bool:
	return bool(enabled_components.get(component, true))


func component_intensity(component: String) -> float:
	return maxf(
		RLTrainingMath.finite_float_or(component_intensities.get(component), 1.0),
		0.0
	)


func component_configuration() -> Dictionary:
	var result = {}
	for key in DEFAULT_COMPONENTS:
		result[key] = {
			"enabled": is_component_enabled(key),
			"intensity": component_intensity(key),
		}
	return result


func reset(
	drone_position: Vector3,
	target_position: Vector3,
	target_radius: float,
	new_episode_duration_seconds: float = 20.0
) -> void:
	initialized = true
	previous_drone_position = drone_position
	previous_target_position = target_position
	previous_target_radius = maxf(
		RLTrainingMath.finite_float_or(target_radius, 0.0),
		0.0
	)
	episode_duration_seconds = maxf(
		RLTrainingMath.finite_float_or(new_episode_duration_seconds, 20.0),
		0.1
	)
	total_reward = 0.0
	elapsed_seconds = 0.0
	time_inside_radius_seconds = 0.0
	previous_actions.clear()
	seconds_since_action_change = 0.0
	action_abuse_seconds = 0.0
	obstacle_contact_active = false
	cumulative_approach_reward = 0.0
	cumulative_progress_reward = 0.0
	cumulative_search_cost_reward = 0.0
	cumulative_radius_reward = 0.0
	cumulative_survival_reward = 0.0
	cumulative_ground_safety_reward = 0.0
	cumulative_smoothness_reward = 0.0
	cumulative_action_abuse_reward = 0.0
	cumulative_obstacle_reward = 0.0
	cumulative_turret_safety_reward = 0.0
	_latest_turret_safety_reward = 0.0
	latest_result.clear()


static func evaluate_goal_terms(
	previous_position_world: Vector3,
	next_position_world: Vector3,
	goal_position_world: Vector3,
	target_radius_m: float,
	delta_seconds: float,
	components: Dictionary
) -> Dictionary:
	var safe_radius = maxf(RLTrainingMath.finite_float_or(target_radius_m, 0.0), 0.0)
	var safe_delta = maxf(RLTrainingMath.finite_float_or(delta_seconds, 0.0), 0.0)
	var previous_distance = previous_position_world.distance_to(goal_position_world)
	var next_distance = next_position_world.distance_to(goal_position_world)
	var was_outside_radius = previous_distance > safe_radius
	var is_inside_radius = next_distance <= safe_radius
	var normalized_approach = 0.0
	var progress_reward = 0.0
	var search_cost_reward = 0.0
	if was_outside_radius or not is_inside_radius:
		normalized_approach = clampf(
			(previous_distance - next_distance) / APPROACH_NORMALIZATION_DISTANCE_M,
			-1.0,
			1.0
		)
		progress_reward = normalized_approach * APPROACH_REWARD_WEIGHT
		if not is_inside_radius:
			search_cost_reward = -TARGET_SEARCH_COST_PER_SECOND * safe_delta
	var approach_intensity = _configured_intensity(components, "approach")
	if _configured_enabled(components, "approach"):
		progress_reward *= approach_intensity
		search_cost_reward *= approach_intensity
	else:
		progress_reward = 0.0
		search_cost_reward = 0.0
	var radius_reward = (
		RADIUS_REWARD_PER_SECOND
		* safe_delta
		* _configured_intensity(components, "radius")
		if is_inside_radius and _configured_enabled(components, "radius")
		else 0.0
	)
	return {
		"approach_reward": progress_reward + search_cost_reward,
		"progress_reward": progress_reward,
		"search_cost_reward": search_cost_reward,
		"radius_reward": radius_reward,
		"normalized_approach": normalized_approach,
		"inside_radius": is_inside_radius,
		"distance_m": next_distance,
		"total": progress_reward + search_cost_reward + radius_reward,
	}


static func _configured_enabled(components: Dictionary, key: String) -> bool:
	if not components.has(key):
		return bool(DEFAULT_COMPONENTS.get(key, true))
	var value: Variant = components[key]
	return bool(value.get("enabled", true)) if value is Dictionary else bool(value)


static func _configured_intensity(components: Dictionary, key: String) -> float:
	if not components.has(key):
		return 1.0
	var value: Variant = components[key]
	return (
		maxf(RLTrainingMath.finite_float_or(value.get("intensity"), 1.0), 0.0)
		if value is Dictionary
		else 1.0
	)


func step(
	drone_position: Vector3,
	target_position: Vector3,
	target_radius: float,
	delta: float,
	normalized_actions: Array[float] = [],
	obstacle_probe: Dictionary = {},
	combat_events: Dictionary = {},
	turret_threat_probe: Dictionary = {}
) -> Dictionary:
	var safe_radius = maxf(RLTrainingMath.finite_float_or(target_radius, 0.0), 0.0)
	var safe_delta = maxf(RLTrainingMath.finite_float_or(delta, 0.0), 0.0)
	if not initialized:
		reset(drone_position, target_position, safe_radius)
		return _result(drone_position, target_position, safe_radius)

	var drone_motion = drone_position - previous_drone_position
	var previous_target_offset = (
		previous_target_position - previous_drone_position
	)
	var current_target_offset = target_position - previous_drone_position
	var previous_distance_to_current_target = current_target_offset.length()
	var current_distance = drone_position.distance_to(target_position)
	var was_outside_radius = (
		previous_target_offset.length_squared()
		> previous_target_radius * previous_target_radius
	)
	var is_inside_radius = current_distance <= safe_radius
	var cosine_alignment = _cosine_alignment(
		drone_motion,
		current_target_offset
	)
	# Measure the actual change in target distance instead of projecting path length onto
	# the target direction. The old projection gave a small positive score for every chord
	# of a circular or wiggling path, allowing motion with no net progress to farm reward.
	var distance_progress_m = previous_distance_to_current_target - current_distance
	var normalized_approach = 0.0
	var progress_reward = 0.0
	var search_cost_reward = 0.0
	if was_outside_radius or not is_inside_radius:
		normalized_approach = clampf(
			distance_progress_m / APPROACH_NORMALIZATION_DISTANCE_M,
			-1.0,
			1.0
		)
		progress_reward = normalized_approach * APPROACH_REWARD_WEIGHT
		if not is_inside_radius:
			# A small time cost prevents hovering far away from becoming a safe zero-reward
			# strategy. It is independent of route shape, so maze detours are not punished
			# merely for moving sideways around a wall.
			search_cost_reward = -TARGET_SEARCH_COST_PER_SECOND * safe_delta
	var approach_intensity = component_intensity("approach")
	if is_component_enabled("approach"):
		progress_reward *= approach_intensity
		search_cost_reward *= approach_intensity
	else:
		progress_reward = 0.0
		search_cost_reward = 0.0
	var approach_reward = progress_reward + search_cost_reward
	var radius_reward = (
		RADIUS_REWARD_PER_SECOND
		* safe_delta
		* component_intensity("radius")
		if is_inside_radius and is_component_enabled("radius")
		else 0.0
	)
	var survival_reward = (
		_survival_reward(safe_delta) * component_intensity("survival")
		if is_component_enabled("survival")
		else 0.0
	)
	var vertical_velocity_mps = (
		drone_motion.y / safe_delta if safe_delta > 0.0 else 0.0
	)
	var ground_safety_reward = (
		_ground_safety_reward(obstacle_probe, vertical_velocity_mps, safe_delta)
		* component_intensity("ground_safety")
		if is_component_enabled("ground_safety")
		else 0.0
	)
	var smoothness_reward = 0.0
	var action_abuse_reward = 0.0
	if is_component_enabled("smoothness"):
		var smoothness_intensity = component_intensity("smoothness")
		smoothness_reward = (
			_action_smoothness_reward(normalized_actions, safe_delta)
			* smoothness_intensity
		)
		action_abuse_reward = _latest_action_abuse_reward * smoothness_intensity
	else:
		_latest_action_abuse_reward = 0.0
		action_abuse_seconds = 0.0
	var obstacle_reward = (
		_obstacle_reward(obstacle_probe, safe_delta) * component_intensity("obstacle")
		if is_component_enabled("obstacle")
		else 0.0
	)
	if not is_component_enabled("obstacle"):
		obstacle_contact_active = false
	_latest_turret_safety_reward = (
		_turret_safety_reward(combat_events, turret_threat_probe, safe_delta)
		* component_intensity("turret_safety")
		if is_component_enabled("turret_safety")
		else 0.0
	)
	var step_reward = (
		approach_reward
		+ radius_reward
		+ survival_reward
		+ ground_safety_reward
		+ smoothness_reward
		+ obstacle_reward
		+ _latest_turret_safety_reward
	)
	total_reward += step_reward
	cumulative_approach_reward += approach_reward
	cumulative_progress_reward += progress_reward
	cumulative_search_cost_reward += search_cost_reward
	cumulative_radius_reward += radius_reward
	cumulative_survival_reward += survival_reward
	cumulative_ground_safety_reward += ground_safety_reward
	cumulative_smoothness_reward += smoothness_reward
	cumulative_action_abuse_reward += action_abuse_reward
	cumulative_obstacle_reward += obstacle_reward
	cumulative_turret_safety_reward += _latest_turret_safety_reward
	elapsed_seconds += safe_delta
	if is_inside_radius:
		time_inside_radius_seconds += safe_delta

	previous_drone_position = drone_position
	previous_target_position = target_position
	previous_target_radius = safe_radius
	return _result(
		drone_position,
		target_position,
		safe_radius,
		cosine_alignment,
		normalized_approach,
		approach_reward,
		progress_reward,
		search_cost_reward,
		radius_reward,
		survival_reward,
		ground_safety_reward,
		smoothness_reward,
		action_abuse_reward,
		obstacle_reward,
		step_reward,
		current_distance
	)


func apply_episode_end_adjustments(
	progress_correction: float,
	failure_penalty: float,
	timeout_survival_bonus: float = 0.0
) -> Dictionary:
	if (
		not is_finite(progress_correction)
		or not is_finite(failure_penalty)
		or not is_finite(timeout_survival_bonus)
	):
		return _result(
			previous_drone_position,
			previous_target_position,
			previous_target_radius
		)
	var total_adjustment = (
		progress_correction + failure_penalty + timeout_survival_bonus
	)
	total_reward += total_adjustment
	# Keep the tracker's cumulative component state authoritative. The positive raw progress
	# remains available separately for diagnostics, while the corrected approach curve reflects
	# the score that the optimizer actually received.
	cumulative_approach_reward += progress_correction
	cumulative_survival_reward += timeout_survival_bonus
	var result = _result(
		previous_drone_position,
		previous_target_position,
		previous_target_radius,
		0.0,
		0.0,
		progress_correction,
		0.0,
		0.0,
		0.0,
		timeout_survival_bonus,
		0.0,
		0.0,
		0.0,
		0.0,
		total_adjustment
	)
	if not is_zero_approx(failure_penalty):
		result["external_penalty"] = failure_penalty
	result["unreached_target_progress_correction"] = progress_correction
	result["failure_penalty"] = failure_penalty
	result["timeout_survival_bonus"] = timeout_survival_bonus
	return result


func _result(
	drone_position: Vector3,
	target_position: Vector3,
	target_radius: float,
	cosine_alignment = 0.0,
	normalized_approach = 0.0,
	approach_reward = 0.0,
	progress_reward = 0.0,
	search_cost_reward = 0.0,
	radius_reward = 0.0,
	survival_reward = 0.0,
	ground_safety_reward = 0.0,
	smoothness_reward = 0.0,
	action_abuse_reward = 0.0,
	obstacle_reward = 0.0,
	step_reward = 0.0,
	distance_override: float = NAN
) -> Dictionary:
	var distance = (
		distance_override
		if is_finite(distance_override)
		else drone_position.distance_to(target_position)
	)
	latest_result["reward_schema_version"] = SCHEMA_VERSION
	latest_result["step_reward"] = step_reward
	latest_result["total_reward"] = total_reward
	latest_result["mean_reward_per_second"] = (
		total_reward / elapsed_seconds if elapsed_seconds > 0.0 else 0.0
	)
	latest_result["approach_reward"] = approach_reward
	latest_result["progress_reward"] = progress_reward
	latest_result["search_cost_reward"] = search_cost_reward
	latest_result["radius_reward"] = radius_reward
	latest_result["survival_reward"] = survival_reward
	latest_result["ground_safety_reward"] = ground_safety_reward
	latest_result["smoothness_reward"] = smoothness_reward
	latest_result["action_abuse_reward"] = action_abuse_reward
	latest_result["obstacle_reward"] = obstacle_reward
	latest_result["turret_safety_reward"] = _latest_turret_safety_reward
	latest_result["cumulative_approach_reward"] = cumulative_approach_reward
	latest_result["cumulative_progress_reward"] = cumulative_progress_reward
	latest_result["cumulative_search_cost_reward"] = cumulative_search_cost_reward
	latest_result["cumulative_radius_reward"] = cumulative_radius_reward
	latest_result["cumulative_survival_reward"] = cumulative_survival_reward
	latest_result["cumulative_ground_safety_reward"] = cumulative_ground_safety_reward
	latest_result["cumulative_smoothness_reward"] = cumulative_smoothness_reward
	latest_result["cumulative_action_abuse_reward"] = cumulative_action_abuse_reward
	latest_result["cumulative_obstacle_reward"] = cumulative_obstacle_reward
	latest_result["cumulative_turret_safety_reward"] = cumulative_turret_safety_reward
	latest_result["cosine_alignment"] = cosine_alignment
	latest_result["normalized_approach"] = normalized_approach
	latest_result["distance_m"] = distance
	latest_result["distance_outside_radius_m"] = maxf(distance - target_radius, 0.0)
	latest_result["normalized_distance"] = clampf(
		distance / APPROACH_NORMALIZATION_DISTANCE_M,
		0.0,
		1.0
	)
	latest_result["inside_radius"] = distance <= target_radius
	latest_result["elapsed_seconds"] = elapsed_seconds
	latest_result["time_inside_radius_seconds"] = time_inside_radius_seconds
	latest_result["reached_target_radius"] = time_inside_radius_seconds > 0.0
	latest_result.erase("external_penalty")
	# Reuse one Dictionary: this runs once per physics tick per drone. Episode histories
	# deep-copy the final result before retaining it.
	return latest_result


func unreached_target_terminal_correction(_pending_failure_penalty: float) -> float:
	# Compatibility method retained for older callers and stored result readers. Unreached
	# trajectories now keep their complete dense learning signal; the old terminal flattening
	# made useful partial flights indistinguishable from useless ones.
	return 0.0


func unreached_target_progress_correction(
	_pending_failure_penalty: float = 0.0
) -> float:
	# Compatibility alias retained for episode/result consumers using the old field name.
	return unreached_target_terminal_correction(_pending_failure_penalty)


func _action_smoothness_reward(actions: Array[float], delta: float) -> float:
	_latest_action_abuse_reward = 0.0
	var safe_delta = maxf(delta, 0.0)
	seconds_since_action_change += safe_delta
	if actions.is_empty():
		action_abuse_seconds = 0.0
		return 0.0
	if previous_actions.size() != actions.size():
		previous_actions = actions.duplicate()
		seconds_since_action_change = 0.0
		_latest_action_abuse_reward = _action_abuse_reward(actions, safe_delta)
		return _latest_action_abuse_reward
	var squared_change = 0.0
	var raw_squared_change = 0.0
	for index in range(actions.size()):
		var difference = absf(actions[index] - previous_actions[index])
		raw_squared_change += difference * difference
		var excess_change = maxf(difference - ACTION_CHANGE_DEADBAND, 0.0)
		squared_change += excess_change * excess_change
	var change_reward = 0.0
	if squared_change > MIN_DIRECTION_LENGTH_SQUARED:
		var action_interval = maxf(seconds_since_action_change, safe_delta)
		var control_rate_scale = clampf(
			action_interval / SMOOTHNESS_REFERENCE_INTERVAL_SECONDS,
			0.0,
			1.0
		)
		change_reward = (
			-ACTION_SMOOTHNESS_WEIGHT
			* sqrt(squared_change)
			* control_rate_scale
		)
	if raw_squared_change > MIN_DIRECTION_LENGTH_SQUARED:
		previous_actions = actions.duplicate()
		seconds_since_action_change = 0.0
	_latest_action_abuse_reward = _action_abuse_reward(actions, safe_delta)
	return change_reward + _latest_action_abuse_reward


func _action_abuse_reward(actions: Array[float], delta: float) -> float:
	if actions.is_empty() or delta <= 0.0:
		action_abuse_seconds = 0.0
		return 0.0
	var minimum_action = INF
	var maximum_action = -INF
	var extreme_count = 0
	for action in actions:
		var value = clampf(float(action), 0.0, 1.0)
		minimum_action = minf(minimum_action, value)
		maximum_action = maxf(maximum_action, value)
		if value <= ACTION_ABUSE_EXTREME_LOW or value >= ACTION_ABUSE_EXTREME_HIGH:
			extreme_count += 1
	var extreme_ratio = float(extreme_count) / float(maxi(actions.size(), 1))
	var spread_ratio = clampf(
		(maximum_action - minimum_action - ACTION_ABUSE_SPREAD_START)
		/ maxf(1.0 - ACTION_ABUSE_SPREAD_START, 0.000001),
		0.0,
		1.0
	)
	var abuse_intensity = maxf(extreme_ratio, spread_ratio)
	if abuse_intensity <= 0.0:
		action_abuse_seconds = 0.0
		return 0.0
	action_abuse_seconds += delta
	if action_abuse_seconds <= ACTION_ABUSE_GRACE_SECONDS:
		return 0.0
	return -ACTION_ABUSE_WEIGHT_PER_SECOND * abuse_intensity * delta


func _survival_reward(delta: float) -> float:
	var reward_budget = minf(
		SURVIVAL_REWARD_BUDGET_PER_SECOND * episode_duration_seconds,
		SURVIVAL_REWARD_MAX_PER_EPISODE
	)
	if delta <= 0.0 or cumulative_survival_reward >= reward_budget:
		return 0.0
	# The per-second rate ramps linearly through the episode while the integrated reward is
	# bounded independently of episode duration. Surviving matters, but target hold remains
	# overwhelmingly more valuable than passive flight.
	var midpoint_progress = clampf(
		(elapsed_seconds + delta * 0.5) / episode_duration_seconds,
		0.0,
		1.0
	)
	var rate_per_second = (
		2.0 * reward_budget
		* midpoint_progress / episode_duration_seconds
	)
	return minf(
		rate_per_second * delta,
		reward_budget - cumulative_survival_reward
	)


func _ground_safety_reward(
	probe: Dictionary,
	vertical_velocity_mps: float,
	delta: float
) -> float:
	if probe.is_empty() or delta <= 0.0:
		return 0.0
	var clearance = maxf(float(probe.get("ground_clearance_m", INF)), 0.0)
	var danger = clampf(
		1.0 - clearance / GROUND_SAFETY_HEIGHT_M,
		0.0,
		1.0
	)
	var descent_ratio = clampf(
		maxf(-vertical_velocity_mps, 0.0) / GROUND_DESCENT_SPEED_SCALE_MPS,
		0.0,
		1.0
	)
	var proximity_penalty = (
		-GROUND_PROXIMITY_WEIGHT_PER_SECOND
		* danger * danger
		* delta
	)
	var descent_penalty = (
		-GROUND_DESCENT_WEIGHT_PER_SECOND
		* danger * danger
		* descent_ratio
		* delta
	)
	var critical_danger = clampf(
		1.0 - clearance / GROUND_CRITICAL_HEIGHT_M,
		0.0,
		1.0
	)
	var critical_penalty = (
		-GROUND_CRITICAL_WEIGHT_PER_SECOND
		* critical_danger * critical_danger
		* delta
	)
	return proximity_penalty + descent_penalty + critical_penalty


func _obstacle_reward(probe: Dictionary, delta: float) -> float:
	if probe.is_empty():
		obstacle_contact_active = false
		return 0.0
	var maximum_distance = maxf(
		float(probe.get("maximum_distance_m", OBSTACLE_DANGER_DISTANCE_M)),
		0.000001
	)
	var distance = clampf(
		float(probe.get("nearest_distance_m", maximum_distance)),
		0.0,
		maximum_distance
	)
	var closing_speed = maxf(float(probe.get("closing_speed_mps", 0.0)), 0.0)
	var danger = clampf(
		1.0 - distance / OBSTACLE_DANGER_DISTANCE_M,
		0.0,
		1.0
	)
	var closing_ratio = clampf(
		closing_speed / OBSTACLE_CLOSING_SPEED_SCALE_MPS,
		0.0,
		1.0
	)
	var reward = (
		-OBSTACLE_PROXIMITY_WEIGHT_PER_SECOND
		* danger * danger
		* closing_ratio
		* delta
	)
	var touching = (
		bool(probe.get("wall_contact", false))
		or (
			distance <= OBSTACLE_CONTACT_DISTANCE_M
			and closing_speed >= OBSTACLE_CONTACT_MINIMUM_SPEED_MPS
		)
	)
	if touching and not obstacle_contact_active:
		reward -= OBSTACLE_CONTACT_PENALTY
	if touching:
		obstacle_contact_active = true
	elif distance >= OBSTACLE_CONTACT_RELEASE_DISTANCE_M:
		# Clearance hysteresis prevents a one-frame contact-monitor gap from turning one
		# physical collision into several repeated contact penalties.
		obstacle_contact_active = false
	return reward


func _turret_safety_reward(
	combat_events: Dictionary,
	threat_probe: Dictionary,
	delta: float
) -> float:
	var hit_count = maxi(int(combat_events.get("hit_count", 0)), 0)
	var damage_taken = maxf(float(combat_events.get("damage_taken", 0.0)), 0.0)
	var threat_level = (
		clampf(float(threat_probe.get("threat_level", 0.0)), 0.0, 1.0)
		if bool(threat_probe.get("present", false))
		else 0.0
	)
	# Confirmed hits dominate the signal. The small continuous exposure term teaches evasive
	# positioning before a projectile arrives without overwhelming the navigation objective.
	return -(
		TURRET_HIT_PENALTY_PER_HIT * float(hit_count)
		+ TURRET_DAMAGE_PENALTY_PER_POINT * damage_taken
		+ TURRET_EXPOSURE_PENALTY_PER_SECOND * threat_level * maxf(delta, 0.0)
	)


func _cosine_alignment(
	motion: Vector3,
	target_offset: Vector3
) -> float:
	var motion_length_squared = motion.length_squared()
	var target_length_squared = target_offset.length_squared()
	if (
		motion_length_squared <= MIN_DIRECTION_LENGTH_SQUARED
		or target_length_squared <= MIN_DIRECTION_LENGTH_SQUARED
	):
		return 0.0
	return clampf(
		motion.dot(target_offset)
		/ sqrt(motion_length_squared * target_length_squared),
		-1.0,
		1.0
	)
