class_name DroneTrainingEpisode
extends RefCounted

const DEFAULT_DURATION_SECONDS = 20.0
const START_GRACE_SECONDS = 0.75
const GROUND_CRASH_CENTER_HEIGHT_M = 0.2
const ARENA_EDGE_MARGIN_M = 0.2
const DEFAULT_TERMINATION_OPTIONS: Dictionary = {
	"ground_contact": false,
}
const TERMINAL_FAILURE_PENALTY = -1.0
const EARLY_FAILURE_EXTRA_PENALTY = 2.0
const EARLY_FAILURE_PENALTY_WINDOW_SECONDS = 5.0
const TIMEOUT_SURVIVAL_BONUS_BASE = 0.05
const TIMEOUT_SURVIVAL_BONUS_PER_SECOND = 0.005
const TIMEOUT_SURVIVAL_BONUS_MAXIMUM = 0.20
const WALL_DEADLOCK_SECONDS = 3.0
const WALL_DEADLOCK_PROGRESS_DISTANCE_M = 0.6
const WALL_DEADLOCK_PROGRESS_DISTANCE_SQUARED = (
	WALL_DEADLOCK_PROGRESS_DISTANCE_M * WALL_DEADLOCK_PROGRESS_DISTANCE_M
)
const WALL_CONTACT_GRACE_SECONDS = 0.2

#######################################################
# Owns one comparable drone evaluation episode, including reward accumulation, timeout,
# destruction, wall-deadlock, power-loss, arena-boundary termination, and the optional legacy
# low-ground cutoff. Inverted orientation is intentionally never a terminal condition.
#######################################################

var reward_tracker = DroneTrainingReward.new()
var episode_number = 0
var episode_seed = 0
var duration_seconds = DEFAULT_DURATION_SECONDS
var elapsed_seconds = 0.0
var wall_deadlock_seconds = 0.0
var wall_contact_grace_remaining = 0.0
var wall_contact_progress_anchor = Vector3.ZERO
var wall_contact_session_active = false
var finished = false
var terminated = false
var truncated = false
var termination_reason = "running"
var end_on_ground_contact: bool = false
var latest_result: Dictionary = {}


func start(
	drone_position: Vector3,
	target_position: Vector3,
	target_radius: float,
	new_duration_seconds: float,
	new_episode_number: int,
	new_seed: int,
	reward_components: Dictionary = {},
	termination_options: Dictionary = {}
) -> void:
	episode_number = new_episode_number
	episode_seed = new_seed
	duration_seconds = maxf(
		RLTrainingMath.finite_float_or(new_duration_seconds, DEFAULT_DURATION_SECONDS),
		0.1
	)
	elapsed_seconds = 0.0
	wall_deadlock_seconds = 0.0
	wall_contact_grace_remaining = 0.0
	wall_contact_progress_anchor = drone_position
	wall_contact_session_active = false
	finished = false
	terminated = false
	truncated = false
	termination_reason = "running"
	configure_termination_options(termination_options)
	reward_tracker.configure_components(reward_components)
	reward_tracker.reset(
		drone_position,
		target_position,
		target_radius,
		duration_seconds
	)
	latest_result = _decorate_reward({})


func configure_termination_options(options: Dictionary) -> void:
	var sanitized: Dictionary = sanitize_termination_options(options)
	end_on_ground_contact = bool(sanitized["ground_contact"])


static func sanitize_termination_options(options: Variant) -> Dictionary:
	var source: Dictionary = options as Dictionary if options is Dictionary else {}
	return {
		"ground_contact": SafeVariant.strict_bool_or(
			source.get("ground_contact", DEFAULT_TERMINATION_OPTIONS["ground_contact"]),
			bool(DEFAULT_TERMINATION_OPTIONS["ground_contact"])
		),
	}


func termination_options() -> Dictionary:
	return {
		"ground_contact": end_on_ground_contact,
	}


func step(
	drone: ServerDrone,
	target_position: Vector3,
	target_radius: float,
	arena_size: Vector3,
	delta: float,
	obstacle_probe: Dictionary = {},
	combat_events: Dictionary = {},
	turret_threat_probe: Dictionary = {}
) -> Dictionary:
	if finished or not is_instance_valid(drone):
		return latest_result
	var safe_delta = maxf(RLTrainingMath.finite_float_or(delta, 0.0), 0.0)
	elapsed_seconds += safe_delta
	latest_result = reward_tracker.step(
		drone.global_position,
		target_position,
		target_radius,
		safe_delta,
		drone.get_ml_normalized_commands(),
		obstacle_probe,
		combat_events,
		turret_threat_probe
	)

	if elapsed_seconds >= START_GRACE_SECONDS:
		_update_wall_deadlock(drone, obstacle_probe, safe_delta)
		var failure = _failure_reason(drone, arena_size)
		if not failure.is_empty():
			finish(failure)
	if not finished and elapsed_seconds >= duration_seconds:
		finish("time_limit", true)
	latest_result = _decorate_reward(latest_result)
	return latest_result


func finish(reason: String, is_truncation = false) -> Dictionary:
	if finished:
		return latest_result
	finished = true
	terminated = not is_truncation
	truncated = is_truncation
	termination_reason = reason

	var failure_penalty = 0.0
	if terminated and reward_tracker.is_component_enabled("failure"):
		var early_failure_window = minf(
			EARLY_FAILURE_PENALTY_WINDOW_SECONDS,
			maxf(duration_seconds * 0.5, 0.1)
		)
		var early_failure_ratio = clampf(
			1.0 - elapsed_seconds / early_failure_window,
			0.0,
			1.0
		)
		# Deliberate immediate failure must not be cheaper than spending several seconds trying
		# to recover. The extra cost is concentrated in the first few seconds and then vanishes,
		# rather than distorting legitimate late failures throughout a long episode.
		failure_penalty = (
			TERMINAL_FAILURE_PENALTY
			- EARLY_FAILURE_EXTRA_PENALTY * early_failure_ratio
		) * reward_tracker.component_intensity("failure")
	var timeout_survival_bonus = 0.0
	if (
		is_truncation
		and reason == "time_limit"
		and reward_tracker.is_component_enabled("survival")
	):
		timeout_survival_bonus = minf(
			TIMEOUT_SURVIVAL_BONUS_BASE
			+ TIMEOUT_SURVIVAL_BONUS_PER_SECOND * duration_seconds,
			TIMEOUT_SURVIVAL_BONUS_MAXIMUM
		) * reward_tracker.component_intensity("survival")
	# Unreached trajectories keep their complete dense progress signal. The old flattening
	# collapsed useful partial flight and useless failure onto the same terminal score.
	var progress_correction = 0.0
	var episode_adjustment = (
		progress_correction + failure_penalty + timeout_survival_bonus
	)
	if not is_zero_approx(episode_adjustment):
		var previous_step_reward = float(latest_result.get("step_reward", 0.0))
		var transition_components = {
			"approach_reward": latest_result.get("approach_reward", 0.0),
			"progress_reward": latest_result.get("progress_reward", 0.0),
			"search_cost_reward": latest_result.get("search_cost_reward", 0.0),
			"radius_reward": latest_result.get("radius_reward", 0.0),
			"survival_reward": latest_result.get("survival_reward", 0.0),
			"ground_safety_reward": latest_result.get("ground_safety_reward", 0.0),
			"smoothness_reward": latest_result.get("smoothness_reward", 0.0),
			"action_abuse_reward": latest_result.get("action_abuse_reward", 0.0),
			"obstacle_reward": latest_result.get("obstacle_reward", 0.0),
			"turret_safety_reward": latest_result.get("turret_safety_reward", 0.0),
			"cosine_alignment": latest_result.get("cosine_alignment", 0.0),
			"normalized_approach": latest_result.get("normalized_approach", 0.0),
		}
		latest_result = reward_tracker.apply_episode_end_adjustments(
			progress_correction,
			failure_penalty,
			timeout_survival_bonus
		)
		latest_result["step_reward"] = previous_step_reward + episode_adjustment
		for key in [
			"approach_reward", "progress_reward", "search_cost_reward",
			"radius_reward", "survival_reward", "ground_safety_reward",
			"smoothness_reward", "action_abuse_reward", "obstacle_reward",
			"turret_safety_reward",
			"cosine_alignment", "normalized_approach",
		]:
			latest_result[key] = transition_components.get(key, 0.0)
		latest_result["approach_reward"] = (
			float(latest_result.get("approach_reward", 0.0))
			+ progress_correction
		)
	latest_result["unreached_target_progress_correction"] = progress_correction
	latest_result["failure_penalty"] = failure_penalty
	latest_result["timeout_survival_bonus"] = timeout_survival_bonus
	latest_result = _decorate_reward(latest_result)
	return latest_result


func _update_wall_deadlock(
	drone: ServerDrone,
	obstacle_probe: Dictionary,
	delta: float
) -> void:
	var touching_wall = bool(obstacle_probe.get("wall_contact", false))
	if touching_wall:
		wall_contact_grace_remaining = WALL_CONTACT_GRACE_SECONDS
		if not wall_contact_session_active:
			wall_contact_session_active = true
			wall_contact_progress_anchor = drone.global_position
			wall_deadlock_seconds = 0.0
			return

		# A drone sliding along a wall is still making physical progress and must not be
		# mistaken for the forward/backward oscillation of a true jam. Move the anchor
		# whenever it escapes the local contact pocket; only bounded contact accumulates.
		if (
			drone.global_position.distance_squared_to(wall_contact_progress_anchor)
			>= WALL_DEADLOCK_PROGRESS_DISTANCE_SQUARED
		):
			wall_contact_progress_anchor = drone.global_position
			wall_deadlock_seconds = 0.0
		else:
			wall_deadlock_seconds += delta
		return

	# Contact reporting is sampled at the obstacle-sensor cadence and may briefly omit a
	# contact while the solver changes which compound drone shape touches the wall. Preserve
	# the current contact session across that tiny reporting gap, but reset it as soon as the
	# drone has genuinely separated.
	wall_contact_grace_remaining = maxf(
		wall_contact_grace_remaining - delta,
		0.0
	)
	if wall_contact_grace_remaining <= 0.0:
		wall_deadlock_seconds = 0.0
		wall_contact_session_active = false
		wall_contact_progress_anchor = drone.global_position


func _failure_reason(drone: ServerDrone, arena_size: Vector3) -> String:
	if drone.current_health <= 0.0:
		return "destroyed"
	if end_on_ground_contact and drone.global_position.y <= GROUND_CRASH_CENTER_HEIGHT_M:
		return "ground_crash"
	if _is_outside_arena(drone.global_position, arena_size):
		return "left_arena"
	if wall_deadlock_seconds >= WALL_DEADLOCK_SECONDS:
		return "wall_deadlock"
	if not drone.activated:
		return "power_loss"
	return ""


func _is_outside_arena(position: Vector3, arena_size: Vector3) -> bool:
	var half_width = arena_size.x * 0.5 + ARENA_EDGE_MARGIN_M
	var half_depth = arena_size.z * 0.5 + ARENA_EDGE_MARGIN_M
	# Height is intentionally unbounded. Flying above walls can be a valid learned route,
	# and vertical excursions must not randomly terminate otherwise healthy episodes.
	return (
		absf(position.x) > half_width
		or absf(position.z) > half_depth
	)


func _decorate_reward(reward: Dictionary) -> Dictionary:
	var result = reward
	result["episode_number"] = episode_number
	result["episode_seed"] = episode_seed
	result["episode_elapsed_seconds"] = elapsed_seconds
	result["episode_duration_seconds"] = duration_seconds
	result["episode_progress"] = clampf(
		elapsed_seconds / maxf(duration_seconds, 0.1),
		0.0,
		1.0
	)
	result["episode_termination_options"] = termination_options()
	result["wall_deadlock_seconds"] = wall_deadlock_seconds
	result["wall_deadlock_limit_seconds"] = WALL_DEADLOCK_SECONDS
	result["wall_deadlock_progress_distance_m"] = WALL_DEADLOCK_PROGRESS_DISTANCE_M
	result["finished"] = finished
	result["terminated"] = terminated
	result["truncated"] = truncated
	result["termination_reason"] = termination_reason
	return result


static func all_finished(trials: Array[Dictionary]) -> bool:
	if trials.is_empty():
		return false
	for trial in trials:
		if not bool(trial.get("episode_finished", false)):
			return false
	return true


static func build_persistence_record(
	trial: Dictionary,
	target_behavior: String,
	target_speed: float,
	target_radius: float,
	target_position: Vector3
) -> Dictionary:
	var drone = trial.get("drone") as ServerDrone
	var result: Dictionary = trial.get("reward", {}).duplicate(true)
	var position = (
		drone.global_position if is_instance_valid(drone) else Vector3.ZERO
	)
	result["instance_id"] = int(trial.get("instance_id", -1))
	result["final_position_world"] = [position.x, position.y, position.z]
	result["target_behavior"] = target_behavior
	result["target_speed"] = target_speed
	result["target_hover_radius_m"] = target_radius
	result["target_final_position_world"] = [
		target_position.x,
		target_position.y,
		target_position.z,
	]
	return result
