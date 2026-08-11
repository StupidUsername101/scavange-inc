class_name DroneSACTrainer
extends DroneTrainingAlgorithm

const CHECKPOINT_SCHEMA_VERSION = 8
const FULL_TRAINING_STATE_SCHEMA_VERSION = 3
const LEGACY_GLOBAL_VARIANCE_CHECKPOINT_SCHEMA_VERSION = 4
const ALGORITHM_NAME = "soft_actor_critic_her"
const TRAINING_ALGORITHM_ID = "sac_her_maze"
const DEFAULT_WORKER_COUNT = 12
const MAXIMUM_WORKER_COUNT = 48
const WARMUP_HOLD_MINIMUM_DECISIONS = 6
const WARMUP_HOLD_MAXIMUM_DECISIONS = 14
const WARMUP_COLLECTIVE_DEVIATION = 0.035
const WARMUP_HORIZONTAL_DEVIATION = 0.05
const WARMUP_YAW_DEVIATION = 0.03
const WARMUP_COMMAND_MINIMUM = 0.38
const WARMUP_COMMAND_MAXIMUM = 0.98
const WARMUP_GROUND_LIFT_BIAS_MAX = 0.06
const WARMUP_GROUND_ATTITUDE_MINIMUM_SCALE = 0.30
const MINIMUM_CRITIC_UPDATES_BEFORE_POLICY_CONTROL = 4
const MINIMUM_POLICY_TRANSITIONS_BEFORE_ACTOR_UPDATES = 512
const HER_REWARD_IDENTITY_CHECK_INTERVAL = 256
const EXPLORATION_BOUNDARY_STOP_M = 2.0
const EXPLORATION_BOUNDARY_FULL_M = 6.0
const DEFAULT_CONFIG = {
	"learning_rate": 0.0003,
	"discount_factor": 0.995,
	"entropy_temperature": 0.002,
	"automatic_entropy_temperature": false,
	"target_entropy": 4.0,
	"entropy_temperature_learning_rate": 0.0003,
	"target_update_rate": 0.005,
	"maximum_gradient_norm": 1.0,
	"batch_size": 64,
	"replay_capacity": 50000,
	"learning_starts": 2048,
	"warmup_exploration_steps": 2048,
	"update_interval_transitions": 64,
	"gradient_steps_per_update": 8,
	"hindsight_goals_per_transition": 1,
	"exploration_bonus": 0.01,
	"exploration_cell_cooldown_seconds": 120.0,
	"blocked_detour_relief": 1.0,
	"control_interval_seconds": 0.05,
	"discount_reference_interval_seconds": 0.05,
	"hidden_layer_width": DroneSACActorCritic.HIDDEN_SIZE,
	"hidden_layer_depth": DroneSACActorCritic.HIDDEN_LAYER_COUNT,
}

var config = DEFAULT_CONFIG.duplicate(true)
var actor_critic: DroneSACActorCritic
var navigation_memory = DroneSACNavigationMemory.new()
var replay_buffer: Array[Dictionary] = []
var replay_write_index = 0
var next_logical_transition_id = 0
var real_replay_count = 0
var hindsight_replay_count = 0
var sampled_real_count = 0
var sampled_hindsight_count = 0
var her_disabled_reason = ""
var episode_transitions: Dictionary = {}
var replay_rng = RandomNumberGenerator.new()
var warmup_rng = RandomNumberGenerator.new()
var warmup_controls: Dictionary = {}
# Per-worker, per-episode timestamps for scout-reward eligibility. Navigation-memory
# visit counts remain actor observations; this separate timed memory prevents a drone from
# repeatedly circling through the same handful of cells to farm intrinsic reward.
var exploration_cell_last_visit_seconds: Dictionary = {}
var exploration_elapsed_seconds: Dictionary = {}
var random_seed = 7340033
var transitions_since_update = 0
var update_count = 0
var environment_steps = 0
var environment_steps_since_replay_reset = 0
var policy_environment_steps_since_replay_reset = 0
var structured_warmup_environment_steps_since_replay_reset = 0
var completed_episodes = 0
var best_episode_mean_reward = -INF
var best_network_state: Dictionary = {}
var candidate_sequence = 0
var pending_candidate: Dictionary = {}
var candidate_network_state: Dictionary = {}
var candidate_training_summary: Dictionary = {}
var promoted_training_summary: Dictionary = {}
var best_evaluation: Dictionary = {}
var best_evaluation_contract: Dictionary = {}
var evaluation_contract_template: Dictionary = {}
var pending_promoted_candidate: Dictionary = {}
var last_metrics: Dictionary = {}
var last_error = ""
var background_thread: Thread
var background_job: RefCounted
var background_result_discarded = false
var background_started_usec = 0
var last_background_update_ms = 0.0


func _init(custom_config: Dictionary = {}, initialization_seed: int = 7340033) -> void:
	for key in custom_config:
		if config.has(key):
			config[key] = custom_config[key]
	_sanitize_config()
	random_seed = initialization_seed
	actor_critic = DroneSACActorCritic.new(
		random_seed,
		int(config["hidden_layer_width"]),
		int(config["hidden_layer_depth"])
	)
	actor_critic.configure_entropy_temperature(float(config["entropy_temperature"]), true)
	replay_rng.seed = random_seed + 101
	warmup_rng.seed = random_seed + 211


func algorithm_id() -> String:
	return TRAINING_ALGORITHM_ID


func algorithm_display_name() -> String:
	return "Maze SAC + Hindsight Replay"


func algorithm_short_name() -> String:
	return "SAC-HER"


func default_worker_count() -> int:
	return DEFAULT_WORKER_COUNT


func maximum_worker_count() -> int:
	return MAXIMUM_WORKER_COUNT


func configuration_controls() -> Array[Dictionary]:
	return [
		{"key": "learning_rate", "title": "Learning rate", "minimum": 0.000001, "maximum": 0.005, "step": 0.000001, "integer": false, "tooltip": "How large each learning correction is.\n\nToo high can destroy useful behaviour. Too low learns very slowly.\nDefault: 0.00030."},
		{"key": "discount_factor", "title": "Future reward importance", "minimum": 0.8, "maximum": 1.0, "step": 0.001, "integer": false, "tooltip": "How much the model cares about rewards that happen later.\n\nMaze navigation needs a high value so long detours are still worth learning.\nDefault: 0.995."},
		{"key": "entropy_temperature", "title": "Exploration strength", "minimum": 0.0, "maximum": 0.05, "step": 0.0005, "integer": false, "tooltip": "How strongly SAC is encouraged to keep trying different propeller actions.\n\nHigher values explore more. Very low values can make a bad habit become almost permanent.\nDefault: 0.002."},
		{"key": "automatic_entropy_temperature", "title": "Learn exploration strength automatically", "minimum": 0.0, "maximum": 1.0, "step": 1.0, "integer": true, "tooltip": "0 keeps a fixed exploration strength. 1 learns the strength from observed policy entropy."},
		{"key": "target_entropy", "title": "Target latent entropy", "minimum": 0.1, "maximum": 12.0, "step": 0.1, "integer": false, "tooltip": "Positive entropy target used when automatic exploration-strength learning is enabled. The default equals the four raw propeller actions."},
		{"key": "entropy_temperature_learning_rate", "title": "Exploration-strength learning rate", "minimum": 0.000001, "maximum": 0.01, "step": 0.000001, "integer": false, "tooltip": "Separate Adam learning rate for SAC log alpha."},
		{"key": "target_update_rate", "title": "Stable predictor tracking", "minimum": 0.0005, "maximum": 0.05, "step": 0.0005, "integer": false, "tooltip": "How quickly the slow reward-prediction copies follow the actively learned copies.\n\nLower is steadier. Higher reacts faster but can become unstable.\nDefault: 0.005."},
		{"key": "maximum_gradient_norm", "title": "Learning-spike limiter", "minimum": 0.05, "maximum": 5.0, "step": 0.05, "integer": false, "tooltip": "Limits unusually large learning corrections.\n\nThis helps one bad batch from damaging the whole model.\nDefault: 1.0."},
		{"key": "batch_size", "title": "Past decisions per learning step", "minimum": 16.0, "maximum": 512.0, "step": 16.0, "integer": true, "tooltip": "How many past decisions SAC studies together in one learning step.\n\nLarger batches are steadier but use more CPU and memory.\nDefault: 64."},
		{"key": "replay_capacity", "title": "Stored past decisions", "minimum": 2048.0, "maximum": 200000.0, "step": 2048.0, "integer": true, "tooltip": "Maximum number of past decisions kept for reuse.\n\nWhen full, the oldest memories are replaced first.\nDefault: 50000."},
		{"key": "learning_starts", "title": "Experience before learning", "minimum": 128.0, "maximum": 20000.0, "step": 128.0, "integer": true, "tooltip": "How much experience is collected before SAC starts learning.\n\nMore experience gives the first updates a less biased sample.\nDefault: 2048."},
		{"key": "warmup_exploration_steps", "title": "Structured warm-up steps", "minimum": 0.0, "maximum": 20000.0, "step": 128.0, "integer": true, "tooltip": "How long the built-in safe exploration pattern collects starting experience.\n\nAfter warm-up, the learned policy still controls all four propellers directly.\nDefault: 2048 steps."},
		{"key": "update_interval_transitions", "title": "New decisions before learning", "minimum": 16.0, "maximum": 2048.0, "step": 16.0, "integer": true, "tooltip": "How many new decisions must arrive before SAC learns again.\n\nLower values update more often.\nDefault: 64."},
		{"key": "gradient_steps_per_update", "title": "Past-experience passes", "minimum": 1.0, "maximum": 32.0, "step": 1.0, "integer": true, "tooltip": "How many replay batches SAC studies each time learning starts.\n\nToo many passes on a small memory can reinforce early mistakes.\nDefault: 8."},
		{"key": "hindsight_goals_per_transition", "title": "Hindsight goals", "minimum": 0.0, "maximum": 8.0, "step": 1.0, "integer": true, "tooltip": "How many achieved future positions are reused as pretend goals.\n\nThis lets failed runs still teach the model what it successfully reached.\nDefault: 1."},
		{"key": "exploration_bonus", "title": "Unvisited-corridor bonus", "minimum": 0.0, "maximum": 0.1, "step": 0.001, "integer": false, "tooltip": "Small reward for entering a cell this drone has not visited recently.\n\nRepeating the same loop pays nothing until the cooldown expires.\nDefault: 0.01."},
		{"key": "exploration_cell_cooldown_seconds", "title": "Scout cell cooldown", "minimum": 1.0, "maximum": 600.0, "step": 1.0, "integer": false, "tooltip": "How long a visited cell stays marked for this drone.\n\nThe timer uses simulated time and resets when a new episode begins.\nDefault: 120 seconds."},
		{"key": "blocked_detour_relief", "title": "Blocked detour relief", "minimum": 0.0, "maximum": 1.0, "step": 0.05, "integer": false, "tooltip": "Reduces the punishment for temporarily moving away when a wall blocks the direct route.\n\n1.0 can cancel the full direct-distance penalty during a detour.\nDefault: 1.0."},
	]


func config_values() -> Dictionary:
	return config


func set_config_value(key: String, value: Variant) -> bool:
	if key == "hidden_layer_width" or key == "hidden_layer_depth":
		return false
	if not config.has(key):
		return false
	config[key] = value
	_sanitize_config()
	_trim_replay_to_capacity()
	return true


func network_architecture() -> Dictionary:
	return {
		"hidden_layer_width": actor_critic.hidden_size,
		"hidden_layer_depth": actor_critic.hidden_layer_count,
	}


func encode_observation(observation: Dictionary, worker_id: int = -1) -> Dictionary:
	var memory_features = navigation_memory.features_for(worker_id, observation)
	var actor_input = DroneSACObservationEncoder.encode_actor(observation, memory_features)
	var critic_input = DroneSACObservationEncoder.encode_critic_from_actor(
		actor_input,
		observation
	)
	return {
		"observation": observation,
		"memory_features": memory_features,
		"actor_input": actor_input,
		"critic_input": critic_input,
	}


func sample_action(observation: Dictionary) -> Dictionary:
	var encoded = encode_observation(observation, -1)
	return sample_action_from_inputs(
		observation,
		encoded.get("actor_input", PackedFloat64Array()),
		encoded.get("critic_input", PackedFloat64Array()),
		-1
	)


func sample_action_from_inputs(
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array,
	worker_id: int = -1
) -> Dictionary:
	if _should_use_structured_warmup():
		return _sample_structured_warmup_action(
			worker_id,
			observation,
			actor_input,
			critic_input
		)
	warmup_controls.erase(worker_id)
	return actor_critic.sample_action_from_inputs(
		observation,
		actor_input,
		critic_input,
		false
	)


func add_transition(
	worker_id: int,
	action_sample: Dictionary,
	reward: float,
	next_observation: Dictionary,
	terminated: bool,
	truncated: bool,
	next_critic_input: PackedFloat64Array = PackedFloat64Array(),
	_next_value_override: float = NAN,
	transition_metadata: Dictionary = {}
) -> bool:
	last_error = ""
	if (
		action_sample.is_empty()
		or not is_finite(reward)
		or not (action_sample.get("actor_input") is PackedFloat64Array)
		or not (action_sample.get("critic_input") is PackedFloat64Array)
		or not (action_sample.get("policy_actions") is PackedFloat64Array)
		or not (action_sample.get("commands") is PackedFloat64Array)
		or not (action_sample.get("observation") is Dictionary)
	):
		last_error = "The SAC transition contains an invalid action sample or reward."
		return false
	if terminated and truncated:
		last_error = "A SAC transition cannot be both terminated and truncated."
		return false
	var delta_seconds: float = RLTrainingMath.finite_float_or(
		transition_metadata.get("delta_seconds", config.get("control_interval_seconds", 0.05)),
		NAN
	)
	if not is_finite(delta_seconds) or delta_seconds <= 0.0:
		last_error = "The SAC transition duration must be finite and positive."
		return false
	var safe_delta_seconds = maxf(delta_seconds, 0.000001)
	var actor_input: PackedFloat64Array = action_sample["actor_input"]
	var critic_input: PackedFloat64Array = action_sample["critic_input"]
	var policy_actions: PackedFloat64Array = action_sample["policy_actions"]
	var commands: PackedFloat64Array = action_sample["commands"]
	var successor_observation_valid: bool = (
		DronePPOObservationEncoder.has_valid_quad_topology(next_observation)
	)
	# True terminal transitions never bootstrap. Preserve their failure signal even if the
	# destroyed/unstable body cannot produce a valid successor tensor. Truncations and all
	# continuing transitions still require a real successor because their Bellman target does.
	if not terminated and not successor_observation_valid:
		last_error = "The SAC transition contains an invalid next observation."
		return false
	var next_actor_input: PackedFloat64Array = PackedFloat64Array()
	if next_critic_input.is_empty() and successor_observation_valid:
		var next_memory: PackedFloat64Array = navigation_memory.features_for(
			worker_id,
			next_observation
		)
		var next_actor: PackedFloat64Array = DroneSACObservationEncoder.encode_actor(
			next_observation,
			next_memory
		)
		next_critic_input = DroneSACObservationEncoder.encode_critic_from_actor(
			next_actor,
			next_observation
		)
	if not next_critic_input.is_empty():
		next_actor_input = _actor_prefix(next_critic_input)
	var next_tensors_valid: bool = (
		DroneSACObservationEncoder.valid_tensors(next_actor_input, next_critic_input)
	)
	var omitted_terminal_successor: bool = (
		terminated and next_actor_input.is_empty() and next_critic_input.is_empty()
	)
	if (
		not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
		or (not omitted_terminal_successor and not next_tensors_valid)
		or policy_actions.size() != DroneSACObservationEncoder.ACTION_COUNT
		or not DronePPOObservationEncoder.is_normalized_tensor(policy_actions)
		or commands.size() != DroneSACObservationEncoder.ACTION_COUNT
		or not RLTrainingMath.packed_all_finite(commands)
	):
		last_error = "The SAC transition contains invalid normalized tensors."
		return false
	var old_observation: Dictionary = action_sample["observation"]
	var memory_features: PackedFloat64Array = action_sample.get(
		"memory_features",
		_actor_memory_suffix(actor_input)
	)
	var next_memory_features: PackedFloat64Array = (
		_actor_memory_suffix(next_actor_input)
		if not next_actor_input.is_empty()
		else PackedFloat64Array()
	)
	var blocked_detour_reward: float = 0.0
	var exploration_reward: float = 0.0
	if successor_observation_valid:
		blocked_detour_reward = _blocked_detour_relief(old_observation, next_observation)
		exploration_reward = _exploration_bonus(
			worker_id,
			old_observation,
			next_observation,
			safe_delta_seconds
		)
	var shaped_reward = reward + blocked_detour_reward + exploration_reward
	if not is_finite(shaped_reward):
		last_error = "The SAC transition produced a non-finite shaped reward."
		return false
	var reward_trace = transition_metadata.duplicate(false)
	if terminated and not successor_observation_valid:
		# HER needs a genuine achieved successor state. The real terminal transition remains
		# trainable, but this one frame must not fabricate a hindsight goal.
		reward_trace.clear()
	var has_goal_reward_trace = (
		str(reward_trace.get("goal_schema", "")) == "stationary_position_v1"
	)
	if not reward_trace.is_empty():
		reward_trace["delta_seconds"] = safe_delta_seconds
	if has_goal_reward_trace:
		var algorithm_shaping: Dictionary = reward_trace.get(
			"algorithm_shaping",
			{}
		).duplicate(false)
		algorithm_shaping["blocked_detour_relief"] = blocked_detour_reward
		algorithm_shaping["exploration_bonus"] = exploration_reward
		reward_trace["algorithm_shaping"] = algorithm_shaping
		reward_trace["production_interval_total"] = float(reward_trace.get(
			"original_total",
			reward
		))
		reward_trace["original_total"] = shaped_reward
		reward_trace["source_terminated"] = terminated
		reward_trace["source_truncated"] = truncated
		# Exact reward replay is a safety assertion, not training work. Run it immediately
		# once and periodically afterwards; the deterministic HER regression suite checks
		# every component directly without charging every live transition for the replay.
		if environment_steps % HER_REWARD_IDENTITY_CHECK_INTERVAL == 0:
			var original_goal = _original_goal_from_trace(reward_trace)
			var identity = _relabel_interval_reward(
				reward_trace,
				old_observation,
				next_observation,
				original_goal
			)
			var identity_error = absf(
				float(identity.get("reward", INF)) - shaped_reward
			)
			if not is_finite(identity_error) or identity_error > 0.000000001:
				last_error = (
					"SAC-HER reward trace identity failed (error %.12f)."
				) % identity_error
				return false
	elif requires_goal_relabel_reward_trace() and not (terminated and not successor_observation_valid):
		her_disabled_reason = "HER requires a stationary_position_v1 goal trace."
	var transition = {
		"actor_input": actor_input,
		"critic_input": critic_input,
		"policy_actions": policy_actions,
		"commands": commands,
		"reward": shaped_reward,
		"next_actor_input": next_actor_input,
		"next_critic_input": next_critic_input,
		"terminated": terminated,
		"truncated": truncated,
		"done": terminated,
		"delta_seconds": safe_delta_seconds,
		"hindsight": false,
		"origin": "real",
		"behavior_source": str(action_sample.get("behavior_source", "policy")),
	}
	_add_replay_transition(transition)
	var worker_episode: Array = episode_transitions.get(worker_id, [])
	if has_goal_reward_trace:
		var episode_transition = transition.duplicate(false)
		episode_transition["observation"] = old_observation
		episode_transition["next_observation"] = next_observation
		episode_transition["memory_features"] = memory_features
		episode_transition["next_memory_features"] = next_memory_features
		episode_transition["reward_trace"] = reward_trace
		worker_episode.append(episode_transition)
		episode_transitions[worker_id] = worker_episode
	environment_steps += 1
	environment_steps_since_replay_reset += 1
	var behavior_source: String = str(action_sample.get("behavior_source", "policy"))
	if behavior_source == "structured_warmup":
		structured_warmup_environment_steps_since_replay_reset += 1
	else:
		policy_environment_steps_since_replay_reset += 1
	transitions_since_update += 1
	if terminated or truncated:
		if not worker_episode.is_empty():
			_add_hindsight_episode(worker_episode)
		episode_transitions.erase(worker_id)
		navigation_memory.reset(worker_id)
		_reset_exploration_memory(worker_id)
		warmup_controls.erase(worker_id)
	return true


func requires_goal_relabel_reward_trace() -> bool:
	return int(config.get("hindsight_goals_per_transition", 0)) > 0


func behavior_policy_revision() -> int:
	return update_count


func can_update(force_partial_rollout = false) -> bool:
	if has_background_update():
		return false
	if environment_steps_since_replay_reset < int(config["learning_starts"]):
		return false
	return (
		bool(force_partial_rollout) and transitions_since_update > 0
		or transitions_since_update >= int(config["update_interval_transitions"])
	)


func begin_background_update(force_partial_rollout = false) -> bool:
	last_error = ""
	if not can_update(force_partial_rollout):
		return false
	var batches: Array = []
	sampled_real_count = 0
	sampled_hindsight_count = 0
	for _step in range(int(config["gradient_steps_per_update"])):
		var batch = _sample_replay_batch(int(config["batch_size"]))
		if batch.is_empty():
			break
		batches.append(batch)
	if batches.is_empty():
		last_error = "SAC could not sample a replay batch."
		return false
	var optimizer_config: Dictionary = config.duplicate(true)
	optimizer_config["train_actor"] = _actor_updates_enabled()
	var payload = {
		"config": optimizer_config,
		"random_seed": random_seed + update_count * 17,
		"network_state": actor_critic.to_state(true),
		"batches": batches,
	}
	var next_job = DroneSACUpdateJob.new(payload)
	var next_thread = Thread.new()
	var previous_pending = transitions_since_update
	transitions_since_update = 0
	var start_error = next_thread.start(Callable(next_job, "run"), Thread.PRIORITY_LOW)
	if start_error != OK:
		transitions_since_update = previous_pending
		last_error = "Godot could not create the background SAC optimizer thread."
		return false
	background_job = next_job
	background_thread = next_thread
	background_result_discarded = false
	background_started_usec = Time.get_ticks_usec()
	return true


func poll_background_update() -> Dictionary:
	if background_thread == null or background_thread.is_alive():
		return {}
	var result_value: Variant = background_thread.wait_to_finish()
	background_thread = null
	background_job = null
	last_background_update_ms = maxf(
		float(Time.get_ticks_usec() - background_started_usec) / 1000.0,
		0.0
	)
	background_started_usec = 0
	var discard = background_result_discarded
	background_result_discarded = false
	if discard:
		return {}
	if not (result_value is Dictionary):
		last_error = "The background SAC optimizer returned no result."
		return {"error": last_error}
	var result: Dictionary = result_value
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "The background SAC optimizer failed."))
		return {"error": last_error}
	var behavior_rng_state = actor_critic.action_rng.state
	if not actor_critic.load_state(result.get("network_state", {})):
		last_error = "The completed background SAC state was incompatible."
		return {"error": last_error}
	# The optimizer samples its own target/policy actions. Do not rewind the live behavior
	# stream to the detached worker's RNG state after the room sampled actions concurrently.
	actor_critic.action_rng.state = behavior_rng_state
	update_count += 1
	var metrics_value: Variant = result.get("metrics", {})
	last_metrics = (
		(metrics_value as Dictionary).duplicate(true)
		if metrics_value is Dictionary
		else {}
	)
	last_metrics["update"] = update_count
	last_metrics["update_count"] = update_count
	last_metrics["environment_steps"] = environment_steps
	last_metrics["environment_steps_since_replay_reset"] = environment_steps_since_replay_reset
	last_metrics["policy_environment_steps_since_replay_reset"] = policy_environment_steps_since_replay_reset
	last_metrics["structured_warmup_environment_steps_since_replay_reset"] = structured_warmup_environment_steps_since_replay_reset
	last_metrics["actor_updated"] = float(last_metrics.get("actor_update_fraction", 0.0)) > 0.5
	last_metrics["actor_updates_enabled"] = _actor_updates_enabled()
	last_metrics["completed_episodes"] = completed_episodes
	last_metrics["replay_size"] = replay_buffer.size()
	last_metrics["replay_capacity"] = int(config["replay_capacity"])
	last_metrics["replay_write_index"] = replay_write_index
	last_metrics["real_replay_count"] = real_replay_count
	last_metrics["hindsight_replay_count"] = hindsight_replay_count
	last_metrics["sampled_real_count"] = sampled_real_count
	last_metrics["sampled_hindsight_count"] = sampled_hindsight_count
	last_metrics["her_disabled_reason"] = her_disabled_reason
	var chronological = _replay_in_chronological_order()
	last_metrics["oldest_logical_transition_id"] = (
		int((chronological[0] as Dictionary).get("logical_transition_id", -1))
		if not chronological.is_empty()
		else -1
	)
	last_metrics["newest_logical_transition_id"] = (
		int((chronological[chronological.size() - 1] as Dictionary).get(
			"logical_transition_id",
			-1
		))
		if not chronological.is_empty()
		else -1
	)
	last_metrics["optimizer_wall_time_ms"] = last_background_update_ms
	last_error = ""
	return last_metrics.duplicate(true)


func has_background_update() -> bool:
	return background_thread != null


func shutdown_background_update() -> void:
	background_result_discarded = true
	if background_thread != null and background_thread.is_started():
		background_thread.wait_to_finish()
	background_thread = null
	background_job = null
	background_started_usec = 0
	background_result_discarded = false


func discard_incomplete_rollout() -> void:
	# Replay is intentionally retained: unlike PPO, SAC remains valid off-policy. Only partial
	# episode bookkeeping and navigation memory must be reset at an environment boundary.
	episode_transitions.clear()
	navigation_memory.reset_all()
	warmup_controls.clear()
	exploration_cell_last_visit_seconds.clear()
	exploration_elapsed_seconds.clear()


func record_completed_episode(mean_reward: float) -> void:
	completed_episodes += 1
	# The evaluator owns the currently frozen candidate until it is accepted or rejected.
	# Continued SAC updates may improve the live policy, but must not invalidate an in-flight suite.
	if not pending_candidate.is_empty():
		return
	if not RLEvaluationContract.is_valid(evaluation_contract_template, "drone"):
		return
	if not is_finite(mean_reward) or mean_reward <= best_episode_mean_reward:
		return
	best_episode_mean_reward = mean_reward
	candidate_network_state = actor_critic.to_state(false)
	candidate_training_summary = {
		"selection_score": mean_reward,
		"group_mean_reward_per_second": mean_reward,
		"support_reward_per_second": mean_reward,
		"best_worker_reward_per_second": mean_reward,
		"robust_best_worker_reward_per_second": mean_reward,
		"policy_update": update_count,
		"environment_steps": environment_steps,
		"completed_episodes": completed_episodes,
		"worker_count": 1,
		"transition_count": replay_buffer.size(),
		"exact_policy_match": false,
		"selection_method": "sac_online_episode_candidate_v2",
	}
	candidate_sequence += 1
	pending_candidate = candidate_training_summary.duplicate(true)
	pending_candidate["candidate_id"] = candidate_sequence
	pending_candidate["candidate_hash"] = RLDeterministicEvaluator.candidate_hash(
		candidate_network_state
	)
	pending_candidate["evaluation_status"] = "awaiting_deterministic_suite"
	pending_candidate["evaluation_contract"] = evaluation_contract_template.duplicate(true)
	pending_candidate["evaluation_contract_hash"] = str(evaluation_contract_template.get("contract_hash", ""))
	pending_candidate["evaluation_plan"] = RLDeterministicEvaluationSuite.plan_for_contract("drone", evaluation_contract_template)


func reset_episode_statistics() -> void:
	completed_episodes = 0
	best_episode_mean_reward = -INF
	best_network_state.clear()
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	promoted_training_summary.clear()
	best_evaluation.clear()
	best_evaluation_contract.clear()
	pending_promoted_candidate.clear()


func copy_policy_from(source: DroneTrainingAlgorithm) -> bool:
	last_error = ""
	var sac_source = source as DroneSACTrainer
	if sac_source == null:
		last_error = "SAC-HER policies can only branch from another SAC-HER group."
		return false
	shutdown_background_update()
	var behavior_rng_state = actor_critic.action_rng.state
	if not actor_critic.copy_from(sac_source.actor_critic):
		last_error = "The SAC-HER source network could not be copied."
		return false
	actor_critic.action_rng.state = behavior_rng_state
	config = sac_source.config.duplicate(true)
	_clear_replay()
	transitions_since_update = 0
	episode_transitions.clear()
	navigation_memory.reset_all()
	warmup_controls.clear()
	update_count = sac_source.update_count
	return true


func perturb_policy(relative_strength: float, perturbation_seed: int) -> bool:
	last_error = ""
	if not actor_critic.perturb_weights(relative_strength, perturbation_seed):
		last_error = "The SAC-HER policy variation produced invalid parameters."
		return false
	_clear_replay()
	transitions_since_update = 0
	episode_transitions.clear()
	navigation_memory.reset_all()
	warmup_controls.clear()
	return true


func status_text(is_training: bool) -> String:
	if has_background_update():
		return "SAC-HER learning round %d is studying stored decisions in the background." % (update_count + 1)
	if _should_use_structured_warmup():
		return "SAC-HER critic bootstrap: %d / %d warm-up decisions · %d / %d critic rounds." % [
			environment_steps,
			int(config["warmup_exploration_steps"]),
			update_count,
			MINIMUM_CRITIC_UPDATES_BEFORE_POLICY_CONTROL,
		]
	if not _actor_updates_enabled():
		return "SAC-HER policy settling: %d / %d policy-controlled decisions before actor learning." % [
			policy_environment_steps_since_replay_reset,
			MINIMUM_POLICY_TRANSITIONS_BEFORE_ACTOR_UPDATES,
		]
	if environment_steps_since_replay_reset < int(config["learning_starts"]):
		return "SAC-HER is collecting real experience before learning: %d / %d decisions." % [
			environment_steps_since_replay_reset,
			int(config["learning_starts"]),
		]
	if is_training:
		return "SAC-HER learning round %d · %d stored decisions · %d new decisions." % [
			update_count,
			replay_buffer.size(),
			transitions_since_update,
		]
	return "SAC-HER paused with %d stored decisions." % replay_buffer.size()


func diagnostic_status_text() -> String:
	if last_metrics.is_empty():
		return (
			"SAC-HER is ready.\n"
			+ "It can reuse old experience, learn from safe points reached during failed episodes, "
			+ "and change its exploration depending on the situation."
		)
	var actor_phase: String = (
		"enabled"
		if _actor_updates_enabled()
		else (
			"critic bootstrap"
			if _should_use_structured_warmup()
			else "collecting policy experience"
		)
	)
	return (
		"Stored decisions: %d\n"
		+ "Actor optimizer: %s\n"
		+ "Policy learning error: %.4f\n"
		+ "Twin-Q critic errors: %.4f / %.4f\n"
		+ "Critic gradient norm: %.4f\n"
		+ "Current action randomness: %.3f\n"
		+ "Average propeller variation: %.3f"
	) % [
		replay_buffer.size(),
		actor_phase,
		float(last_metrics.get("actor_loss", 0.0)),
		float(last_metrics.get("q_one_loss", 0.0)),
		float(last_metrics.get("q_two_loss", 0.0)),
		float(last_metrics.get("critic_gradient_norm", 0.0)),
		float(last_metrics.get("entropy", 0.0)),
		float(last_metrics.get("action_standard_deviation_mean", 0.0)),
	]


func to_checkpoint() -> Dictionary:
	var checkpoint = _checkpoint_with_network(actor_critic.to_state(false), false)
	checkpoint["checkpoint_scope"] = "model_only"
	return checkpoint


func to_training_checkpoint() -> Dictionary:
	var checkpoint = _checkpoint_with_network(actor_critic.to_state(false), false)
	checkpoint["checkpoint_scope"] = "full_training"
	checkpoint["training_state"] = {
		"schema_version": FULL_TRAINING_STATE_SCHEMA_VERSION,
		"replay_buffer": RLTrainingVariantCodec.encode(replay_buffer),
		"replay_write_index": replay_write_index,
		"next_logical_transition_id": next_logical_transition_id,
		"replay_rng_state": replay_rng.state,
		"warmup_rng_state": warmup_rng.state,
		"environment_steps_since_replay_reset": environment_steps_since_replay_reset,
		"policy_environment_steps_since_replay_reset": policy_environment_steps_since_replay_reset,
		"structured_warmup_environment_steps_since_replay_reset": structured_warmup_environment_steps_since_replay_reset,
		"transitions_since_update": transitions_since_update,
		# Episode-local state is deliberately not serialized. A training checkpoint does not
		# contain the matching physics-world snapshot, so restoring worker-ID keyed navigation,
		# HER episode traces, exploration clocks, or warm-up controls onto freshly spawned drones
		# would splice two unrelated episodes together. Replay and optimizer continuation are durable.
	}
	return checkpoint


func load_training_checkpoint(checkpoint: Dictionary) -> bool:
	if str(checkpoint.get("checkpoint_scope", "")) != "full_training":
		last_error = "The selected SAC checkpoint does not contain full replay continuation state."
		return false
	var state_value: Variant = checkpoint.get("training_state", {})
	if not (state_value is Dictionary):
		last_error = "The SAC full checkpoint has no training state."
		return false
	var training_state: Dictionary = state_value
	if RLTrainingMath.finite_int_or(training_state.get("schema_version", 0), -1) != FULL_TRAINING_STATE_SCHEMA_VERSION:
		last_error = "The SAC full training-state schema is unsupported."
		return false
	# Validate all continuation-only state before committing the model/config. Otherwise a
	# checkpoint with a valid network but corrupt replay can report failure after already
	# replacing the live trainer, which makes recovery and UI error handling unsafe.
	var staged_config: Dictionary = config.duplicate(true)
	var loaded_config_value: Variant = checkpoint.get("config", {})
	if loaded_config_value is Dictionary:
		var loaded_config: Dictionary = loaded_config_value
		for key in loaded_config:
			if staged_config.has(key):
				staged_config[key] = loaded_config[key]
	_sanitize_config_dictionary(staged_config)
	var decoded_replay: Variant = RLTrainingVariantCodec.decode(
		training_state.get("replay_buffer", [])
	)
	if not (decoded_replay is Array):
		last_error = "The SAC full checkpoint replay could not be decoded."
		return false
	var restored_replay: Array[Dictionary] = []
	for transition_value in decoded_replay:
		if not (transition_value is Dictionary):
			last_error = "The SAC full checkpoint contains a non-dictionary replay entry."
			return false
		var transition: Dictionary = transition_value
		if not _valid_replay_transition(transition):
			last_error = "The SAC full checkpoint contains an incompatible or non-finite replay entry."
			return false
		restored_replay.append(transition.duplicate(true))
	if restored_replay.size() > int(staged_config["replay_capacity"]):
		last_error = "The SAC full checkpoint replay exceeds the configured capacity."
		return false
	var restored_write_index: int = RLTrainingMath.finite_int_or(training_state.get("replay_write_index", 0), -1)
	if (
		restored_write_index < 0
		or (not restored_replay.is_empty() and restored_write_index >= restored_replay.size())
		or (
			restored_replay.size() < int(staged_config["replay_capacity"])
			and restored_write_index != 0
		)
	):
		last_error = "The SAC full checkpoint replay write index is invalid."
		return false
	# No in-flight worker state is restored without a matching simulation snapshot.
	if not load_checkpoint(checkpoint):
		return false
	replay_buffer = restored_replay
	replay_write_index = restored_write_index
	next_logical_transition_id = maxi(
		RLTrainingMath.finite_int_or(
			training_state.get("next_logical_transition_id", 0),
			_maximum_replay_logical_id() + 1
		),
		_maximum_replay_logical_id() + 1
	)
	replay_rng.state = RLTrainingMath.finite_int_or(training_state.get("replay_rng_state", replay_rng.state), replay_rng.state)
	warmup_rng.state = RLTrainingMath.finite_int_or(training_state.get("warmup_rng_state", warmup_rng.state), warmup_rng.state)
	_recount_replay_origins()
	environment_steps_since_replay_reset = maxi(RLTrainingMath.finite_int_or(
		training_state.get("environment_steps_since_replay_reset", real_replay_count), real_replay_count
	), 0)
	policy_environment_steps_since_replay_reset = maxi(RLTrainingMath.finite_int_or(
		training_state.get("policy_environment_steps_since_replay_reset", 0), 0
	), 0)
	structured_warmup_environment_steps_since_replay_reset = maxi(RLTrainingMath.finite_int_or(
		training_state.get("structured_warmup_environment_steps_since_replay_reset", 0), 0
	), 0)
	transitions_since_update = maxi(RLTrainingMath.finite_int_or(training_state.get("transitions_since_update", 0), 0), 0)
	# load_checkpoint() already cleared all episode-local worker state. Keep it cleared: the
	# restored replay belongs to past completed/partial experience, while new bodies begin fresh.
	last_metrics["resume_mode"] = "full_training_replay_only"
	last_metrics["replay_restored"] = true
	return true


func to_best_checkpoint() -> Dictionary:
	if best_network_state.is_empty():
		return {}
	var checkpoint = _checkpoint_with_network(best_network_state, true)
	_apply_training_context_to_checkpoint(checkpoint, promoted_training_summary)
	return checkpoint


func load_checkpoint(checkpoint: Dictionary) -> bool:
	last_error = ""
	var checkpoint_schema: int = RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1)
	var network_value: Variant = checkpoint.get("network", {})
	var config_value: Variant = checkpoint.get("config", {})
	var training_value: Variant = checkpoint.get("training", {})
	if (
		checkpoint_schema != CHECKPOINT_SCHEMA_VERSION
		or str(checkpoint.get("algorithm", "")) != ALGORITHM_NAME
		or str(checkpoint.get("training_algorithm_id", "")) != TRAINING_ALGORITHM_ID
		or not (network_value is Dictionary)
		or not (config_value is Dictionary)
		or not (training_value is Dictionary)
	):
		last_error = "The SAC-HER checkpoint metadata is incompatible."
		return false
	var staged_actor_critic: DroneSACActorCritic = DroneSACActorCritic.new(random_seed + 29)
	if not staged_actor_critic.load_state(network_value as Dictionary):
		last_error = "The SAC-HER checkpoint network is incompatible."
		return false
	shutdown_background_update()
	var loaded_config: Dictionary = config_value
	for key in loaded_config:
		if config.has(key):
			config[key] = loaded_config[key]
	_sanitize_config()
	config["hidden_layer_width"] = staged_actor_critic.hidden_size
	config["hidden_layer_depth"] = staged_actor_critic.hidden_layer_count
	actor_critic = staged_actor_critic
	# Current checkpoints persist the entropy-temperature optimizer state. If a future
	# current-schema artifact omits it, fall back to the configured coefficient cleanly.
	if not actor_critic.entropy_temperature_state_loaded:
		actor_critic.configure_entropy_temperature(float(config["entropy_temperature"]), true)
	var training: Dictionary = training_value
	random_seed = RLTrainingMath.finite_int_or(training.get("random_seed", random_seed), random_seed)
	replay_rng.seed = random_seed + 101 + maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	warmup_rng.seed = random_seed + 211 + maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	update_count = maxi(RLTrainingMath.finite_int_or(training.get("update_count", 0), 0), 0)
	environment_steps = maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	completed_episodes = maxi(RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0), 0)
	best_episode_mean_reward = (
		RLTrainingMath.finite_float_or(training.get("best_episode_mean_reward", -INF), -INF)
		if RLTrainingMath.bool_or(training.get("has_best_episode", false), false)
		else -INF
	)
	var loaded_best: Variant = training.get("best_network_state", {})
	best_network_state = {}
	if loaded_best is Dictionary and not (loaded_best as Dictionary).is_empty():
		var converted_best = DroneSACActorCritic.new(random_seed + 17)
		if converted_best.load_state(loaded_best as Dictionary):
			best_network_state = converted_best.to_state(false)
	best_evaluation = (
		(training.get("best_evaluation", {}) as Dictionary).duplicate(true)
		if training.get("best_evaluation", {}) is Dictionary
		else {}
	)
	best_evaluation_contract = (
		(training.get("best_evaluation_contract", {}) as Dictionary).duplicate(true)
		if training.get("best_evaluation_contract", {}) is Dictionary else {}
	)
	promoted_training_summary = (
		(training.get("promoted_training_summary", {}) as Dictionary).duplicate(true)
		if training.get("promoted_training_summary", {}) is Dictionary
		else {}
	)
	var loaded_pending: Variant = training.get("pending_evaluation_candidate", {})
	var loaded_candidate_network: Variant = training.get("candidate_network_state", {})
	var loaded_candidate_summary: Variant = training.get("candidate_training_summary", {})
	pending_candidate = (loaded_pending as Dictionary).duplicate(true) if loaded_pending is Dictionary else {}
	candidate_network_state = {}
	if loaded_candidate_network is Dictionary and not (loaded_candidate_network as Dictionary).is_empty():
		var migrated_pending_candidate: DroneSACActorCritic = DroneSACActorCritic.new(random_seed + 19)
		if migrated_pending_candidate.load_state(loaded_candidate_network as Dictionary):
			candidate_network_state = migrated_pending_candidate.to_state(false)
	candidate_training_summary = (
		(loaded_candidate_summary as Dictionary).duplicate(true)
		if loaded_candidate_summary is Dictionary
		else {}
	)
	candidate_sequence = maxi(RLTrainingMath.finite_int_or(training.get("candidate_sequence", candidate_sequence), candidate_sequence), 0)
	pending_promoted_candidate.clear()
	# Pending candidates are resumable only when their frozen evaluation contract is present.
	# Older checkpoints remain loadable, but their pre-contract pending candidate must not enter
	# the fixed-seed queue under whatever room settings happen to be active after loading.
	if (
		not pending_candidate.is_empty()
		and not RLTrainingCandidateSupport.is_resumable_candidate(
			pending_candidate,
			candidate_network_state,
			"drone"
		)
	):
		pending_candidate.clear()
		candidate_network_state.clear()
		candidate_training_summary.clear()
		best_episode_mean_reward = -INF

	if best_network_state.is_empty():
		best_evaluation.clear()
		best_evaluation_contract.clear()
		promoted_training_summary.clear()

	var evaluated_best_is_verified: bool = (
		not best_network_state.is_empty()
		and RLDeterministicEvaluationSuite.is_complete_summary(best_evaluation)
		and str(best_evaluation.get("candidate_hash", ""))
			== RLDeterministicEvaluator.candidate_hash(best_network_state)
		and RLEvaluationContract.is_valid(best_evaluation_contract, "drone")
		and str(best_evaluation.get("evaluation_contract_hash", ""))
			== str(best_evaluation_contract.get("contract_hash", ""))
	)
	if not best_network_state.is_empty() and not evaluated_best_is_verified:
		# Keep the legacy Best network itself. The scheduler will re-evaluate it under the next
		# frozen Candidate contract before comparing scores. Converting it into a contract-less
		# pending candidate would either fail the evaluator or silently late-bind a new task.
		best_evaluation.clear()
		best_evaluation_contract.clear()

	var loaded_metrics: Variant = training.get("last_metrics", {})
	last_metrics = (
		(loaded_metrics as Dictionary).duplicate(true)
		if loaded_metrics is Dictionary
		else {}
	)
	_clear_replay()
	transitions_since_update = 0
	episode_transitions.clear()
	navigation_memory.reset_all()
	warmup_controls.clear()
	exploration_cell_last_visit_seconds.clear()
	exploration_elapsed_seconds.clear()
	last_metrics["resume_mode"] = "networks_only_warmup_reset"
	last_metrics["replay_restored"] = false
	return true


func has_best_checkpoint() -> bool:
	return not best_network_state.is_empty()


func set_evaluation_contract(contract: Dictionary) -> bool:
	if not RLEvaluationContract.is_valid(contract, "drone"):
		evaluation_contract_template.clear()
		return false
	evaluation_contract_template = contract.duplicate(true)
	return true


func evaluation_contract() -> Dictionary:
	return evaluation_contract_template.duplicate(true)


func best_selection_summary() -> Dictionary:
	if not has_best_checkpoint():
		return {}
	return RLTrainingCandidateSupport.best_selection_summary(
		promoted_training_summary,
		best_evaluation,
		best_episode_mean_reward,
		false
	)

func candidate_checkpoint() -> Dictionary:
	if candidate_network_state.is_empty() or pending_candidate.is_empty():
		return {}
	var checkpoint = _checkpoint_with_network(candidate_network_state, false)
	_apply_training_context_to_checkpoint(checkpoint, candidate_training_summary)
	checkpoint["checkpoint_scope"] = "evaluation_candidate"
	checkpoint["candidate"] = pending_candidate.duplicate(true)
	return checkpoint


func pending_evaluation_candidate() -> Dictionary:
	return pending_candidate.duplicate(true)


func pending_evaluation_candidate_id() -> int:
	return RLTrainingCandidateSupport.pending_candidate_id(pending_candidate)

func discard_pending_evaluation_candidate(candidate_id: int) -> bool:
	if RLTrainingCandidateSupport.pending_candidate_id(pending_candidate) != candidate_id:
		return false
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	best_episode_mean_reward = -INF
	return true

func record_deterministic_evaluation(
	candidate_id: int,
	evaluation_summary: Dictionary
) -> Dictionary:
	var evaluation_result: Dictionary = RLTrainingCandidateSupport.evaluate_candidate_summary(
		pending_candidate,
		candidate_network_state,
		candidate_id,
		evaluation_summary,
		best_evaluation
	)
	if not bool(evaluation_result.get("valid", false)):
		return {
			"promoted": false,
			"reason": str(evaluation_result.get("reason", "invalid_evaluation_summary")),
		}
	var promoted: bool = bool(evaluation_result.get("promoted", false))
	var expected_hash: String = str(evaluation_result.get("candidate_hash", ""))
	var verified_summary: Dictionary = (
		(evaluation_result.get("evaluation", {}) as Dictionary).duplicate(true)
		if evaluation_result.get("evaluation", {}) is Dictionary
		else {}
	)
	if promoted:
		best_network_state = candidate_network_state.duplicate(true)
		promoted_training_summary = candidate_training_summary.duplicate(true)
		best_evaluation = verified_summary.duplicate(true)
		var contract_value: Variant = pending_candidate.get("evaluation_contract", {})
		best_evaluation_contract = (
			(contract_value as Dictionary).duplicate(true)
			if contract_value is Dictionary
			else {}
		)
		pending_promoted_candidate = best_selection_summary()
		pending_promoted_candidate["candidate_id"] = candidate_id
		pending_promoted_candidate["candidate_hash"] = expected_hash
	if not promoted:
		best_episode_mean_reward = -INF
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	return {
		"promoted": promoted,
		"reason": str(evaluation_result.get("reason", "unknown")),
		"candidate_id": candidate_id,
	}

func record_deterministic_evaluation_records(
	candidate_id: int,
	records: Array[Dictionary]
) -> Dictionary:
	var aggregate_result: Dictionary = RLTrainingCandidateSupport.aggregate_candidate_records(
		pending_candidate,
		candidate_id,
		records
	)
	if not bool(aggregate_result.get("valid", false)):
		return {
			"promoted": false,
			"reason": str(aggregate_result.get("reason", "invalid_evaluation_records")),
		}
	var summary_value: Variant = aggregate_result.get("summary", {})
	if not (summary_value is Dictionary):
		return {"promoted": false, "reason": "invalid_evaluation_records"}
	return record_deterministic_evaluation(candidate_id, summary_value as Dictionary)

func record_best_deterministic_evaluation_records(
	evaluation_plan: Dictionary,
	records: Array[Dictionary]
) -> Dictionary:
	var evaluation_result: Dictionary = RLTrainingCandidateSupport.evaluate_best_records(
		best_network_state,
		evaluation_plan,
		records,
		pending_candidate,
		evaluation_contract_template,
		"drone"
	)
	if not bool(evaluation_result.get("recorded", false)):
		return {
			"recorded": false,
			"reason": str(evaluation_result.get("reason", "invalid_best_evaluation")),
		}
	var evaluation_value: Variant = evaluation_result.get("evaluation", {})
	best_evaluation = (
		(evaluation_value as Dictionary).duplicate(true)
		if evaluation_value is Dictionary
		else {}
	)
	var contract_value: Variant = evaluation_result.get("evaluation_contract", {})
	best_evaluation_contract = (
		(contract_value as Dictionary).duplicate(true)
		if contract_value is Dictionary
		else {}
	)
	return {
		"recorded": true,
		"reason": "best_re_evaluated",
		"evaluation_contract_hash": str(
			evaluation_result.get("evaluation_contract_hash", "")
		),
	}

func best_evaluation_summary() -> Dictionary:
	return best_evaluation.duplicate(true)


func best_evaluation_contract_snapshot() -> Dictionary:
	return best_evaluation_contract.duplicate(true)


func pending_auto_save_candidate() -> Dictionary:
	return pending_promoted_candidate.duplicate(true)


func acknowledge_auto_save_candidate(candidate_id: int) -> void:
	if int(pending_promoted_candidate.get("candidate_id", -1)) == candidate_id:
		pending_promoted_candidate.clear()


func update_count_value() -> int:
	return update_count


func environment_step_count() -> int:
	return environment_steps


func completed_episode_count() -> int:
	return completed_episodes


func last_metrics_value() -> Dictionary:
	return last_metrics


func last_error_text() -> String:
	return last_error


func last_background_update_milliseconds() -> float:
	return last_background_update_ms


func _should_use_structured_warmup() -> bool:
	return (
		environment_steps < int(config["warmup_exploration_steps"])
		or update_count < MINIMUM_CRITIC_UPDATES_BEFORE_POLICY_CONTROL
	)


func _actor_updates_enabled() -> bool:
	# Structured warm-up deliberately explores a narrow, physically coherent hover envelope.
	# Bootstrap Q on that data, then let the initialized hover policy collect its own experience
	# before Q-gradients may move the actor. Otherwise an untested actor can exploit Q
	# extrapolation and take control only after it has already learned destructive commands.
	return (
		not _should_use_structured_warmup()
		and policy_environment_steps_since_replay_reset
		>= MINIMUM_POLICY_TRANSITIONS_BEFORE_ACTOR_UPDATES
	)


func _sample_structured_warmup_action(
	worker_id: int,
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array
) -> Dictionary:
	var state: Dictionary = warmup_controls.get(worker_id, {})
	var remaining = int(state.get("remaining", 0))
	if state.is_empty() or remaining <= 0:
		state = _new_warmup_control_state()
	else:
		state["remaining"] = remaining - 1
	warmup_controls[worker_id] = state
	var collective = float(state.get("collective", DroneSACActorCritic.HOVER_COMMAND))
	var move_right = float(state.get("move_right", 0.0))
	var move_forward = float(state.get("move_forward", 0.0))
	var yaw = float(state.get("yaw", 0.0))
	var environment: Dictionary = observation.get("environment", {})
	var ground_clearance = maxf(float(environment.get("ground_clearance_m", INF)), 0.0)
	var ground_danger = (
		clampf(
			1.0 - ground_clearance / DroneTrainingReward.GROUND_SAFETY_HEIGHT_M,
			0.0,
			1.0
		)
		if is_finite(ground_clearance)
		else 0.0
	)
	# Structured warm-up exists to seed replay with physically coherent experience, not to
	# repeatedly demonstrate near-ground crashes. Close to the floor, bias collective lift
	# upward and temporarily shrink attitude excursions. Once clear, the original exploration
	# distribution is restored exactly. The learned actor still owns four raw propellers.
	collective = maxf(
		collective + WARMUP_GROUND_LIFT_BIAS_MAX * ground_danger,
		DroneSACActorCritic.HOVER_COMMAND + 0.025 * ground_danger
	)
	var attitude_scale = lerpf(
		1.0,
		WARMUP_GROUND_ATTITUDE_MINIMUM_SCALE,
		ground_danger
	)
	move_right *= attitude_scale
	move_forward *= attitude_scale
	yaw *= attitude_scale
	# This mixer is used only to collect coherent warm-up experience. The SAC actor,
	# replay buffer and Q critics use four independent raw propeller channels.
	var commands = PackedFloat64Array([
		collective + move_right - move_forward + yaw,
		collective - move_right - move_forward - yaw,
		collective + move_right + move_forward - yaw,
		collective - move_right + move_forward + yaw,
	])
	for index in range(commands.size()):
		commands[index] = clampf(
			commands[index],
			WARMUP_COMMAND_MINIMUM,
			WARMUP_COMMAND_MAXIMUM
		)
	return actor_critic.action_sample_from_commands(
		observation,
		actor_input,
		critic_input,
		commands,
		"structured_warmup"
	)


func _new_warmup_control_state() -> Dictionary:
	var move_right = clampf(
		warmup_rng.randfn(0.0, WARMUP_HORIZONTAL_DEVIATION),
		-0.09,
		0.09
	)
	var move_forward = clampf(
		warmup_rng.randfn(0.0, WARMUP_HORIZONTAL_DEVIATION),
		-0.09,
		0.09
	)
	var yaw = clampf(
		warmup_rng.randfn(0.0, WARMUP_YAW_DEVIATION),
		-0.06,
		0.06
	)
	if warmup_rng.randf() < 0.18:
		move_right = 0.0
		move_forward = 0.0
		yaw = 0.0
	return {
		"remaining": warmup_rng.randi_range(
			WARMUP_HOLD_MINIMUM_DECISIONS,
			WARMUP_HOLD_MAXIMUM_DECISIONS
		),
		"collective": clampf(
			DroneSACActorCritic.HOVER_COMMAND
			+ warmup_rng.randfn(0.0, WARMUP_COLLECTIVE_DEVIATION),
			0.64,
			0.82
		),
		"move_right": move_right,
		"move_forward": move_forward,
		"yaw": yaw,
	}


func _add_replay_transition(transition: Dictionary) -> void:
	var stored = transition.duplicate(false)
	stored["logical_transition_id"] = int(stored.get(
		"logical_transition_id",
		next_logical_transition_id
	))
	next_logical_transition_id = maxi(
		next_logical_transition_id,
		int(stored["logical_transition_id"]) + 1
	)
	stored["origin"] = "hindsight" if bool(stored.get("hindsight", false)) else "real"
	var capacity = int(config["replay_capacity"])
	if replay_buffer.size() < capacity:
		replay_buffer.append(stored)
		_increment_replay_origin(stored, 1)
		return
	var removed: Dictionary = replay_buffer[replay_write_index]
	_increment_replay_origin(removed, -1)
	replay_buffer[replay_write_index] = stored
	_increment_replay_origin(stored, 1)
	replay_write_index = (replay_write_index + 1) % capacity


func _increment_replay_origin(transition: Dictionary, amount: int) -> void:
	if bool(transition.get("hindsight", false)):
		hindsight_replay_count = maxi(hindsight_replay_count + amount, 0)
	else:
		real_replay_count = maxi(real_replay_count + amount, 0)


func _sample_replay_batch(requested_size: int) -> Array:
	var result: Array = []
	if replay_buffer.is_empty():
		return result
	var count = mini(maxi(requested_size, 1), replay_buffer.size())
	for _index in range(count):
		var sample_index = replay_rng.randi_range(0, replay_buffer.size() - 1)
		# Replay entries are immutable after insertion. The background learner reads them while
		# the ring buffer may replace slots, but existing Dictionary references remain valid.
		var sample: Dictionary = replay_buffer[sample_index]
		result.append(sample)
		if bool(sample.get("hindsight", false)):
			sampled_hindsight_count += 1
		else:
			sampled_real_count += 1
	return result


func _add_hindsight_episode(episode: Array) -> void:
	var goals_per_transition = int(config["hindsight_goals_per_transition"])
	if goals_per_transition <= 0 or episode.size() < 2:
		return
	var safe_future_indices: Array[int] = []
	for future_index in range(episode.size()):
		var future: Dictionary = episode[future_index]
		var future_observation: Dictionary = future.get("next_observation", {})
		if _safe_hindsight_goal(future_observation):
			safe_future_indices.append(future_index)
	if safe_future_indices.is_empty():
		return
	var first_safe_position = 0
	for transition_index in range(episode.size()):
		while (
			first_safe_position < safe_future_indices.size()
			and safe_future_indices[first_safe_position] <= transition_index
		):
			first_safe_position += 1
		if first_safe_position >= safe_future_indices.size():
			break
		var source: Dictionary = episode[transition_index]
		var reward_trace: Dictionary = source.get("reward_trace", {})
		if str(reward_trace.get("goal_schema", "")) != "stationary_position_v1":
			her_disabled_reason = "HER skipped: this environment does not expose stationary_position_v1 goals."
			continue
		for goal_sample in range(goals_per_transition):
			var future_list_position = (
				safe_future_indices.size() - 1
				if goal_sample == 0
				else replay_rng.randi_range(
					first_safe_position,
					safe_future_indices.size() - 1
				)
			)
			var future_index = safe_future_indices[future_list_position]
			var future: Dictionary = episode[future_index]
			var future_observation: Dictionary = future.get("next_observation", {})
			var goal_position: Vector3 = (future_observation.get("body", {}) as Dictionary).get(
				"position_world",
				Vector3.ZERO
			)
			var source_objective: Dictionary = (
				source.get("observation", {}) as Dictionary
			).get("objective", {})
			var goal_radius = maxf(float(source_objective.get(
				"target_hover_radius_m",
				1.0
			)), 0.1)
			var substituted_goal = {
				"position_world": goal_position,
				"target_radius_m": goal_radius,
			}
			var old_observation = _relabel_goal(
				source.get("observation", {}),
				goal_position,
				goal_radius
			)
			var next_observation = _relabel_goal(
				source.get("next_observation", {}),
				goal_position,
				goal_radius
			)
			var actor_input = DroneSACObservationEncoder.encode_actor(
				old_observation,
				source.get("memory_features", PackedFloat64Array())
			)
			var critic_input = DroneSACObservationEncoder.encode_critic_from_actor(
				actor_input,
				old_observation
			)
			var next_actor_input = DroneSACObservationEncoder.encode_actor(
				next_observation,
				source.get("next_memory_features", PackedFloat64Array())
			)
			var next_critic_input = DroneSACObservationEncoder.encode_critic_from_actor(
				next_actor_input,
				next_observation
			)
			if (
				not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
				or not DroneSACObservationEncoder.valid_tensors(next_actor_input, next_critic_input)
			):
				continue
			var relabel_result = _relabel_interval_reward(
				reward_trace,
				old_observation,
				next_observation,
				substituted_goal
			)
			if not bool(relabel_result.get("valid", false)):
				continue
			var source_policy_actions: PackedFloat64Array = source.get(
				"policy_actions",
				PackedFloat64Array()
			)
			var source_commands: PackedFloat64Array = source.get(
				"commands",
				PackedFloat64Array()
			)
			if (
				source_policy_actions.size() != DroneSACObservationEncoder.ACTION_COUNT
				or source_commands.size() != DroneSACObservationEncoder.ACTION_COUNT
			):
				continue
			_add_replay_transition({
				"actor_input": actor_input,
				"critic_input": critic_input,
				"policy_actions": source_policy_actions,
				"commands": source_commands,
				"reward": float(relabel_result["reward"]),
				"next_actor_input": next_actor_input,
				"next_critic_input": next_critic_input,
				# Goal achievement does not terminate the live tracking task. Only a genuine
				# source environment termination disables value bootstrap.
				"terminated": bool(source.get("terminated", false)),
				"truncated": bool(source.get("truncated", false)),
				"done": bool(source.get("terminated", false)),
				"delta_seconds": maxf(float(reward_trace.get(
					"delta_seconds",
					config.get("control_interval_seconds", 0.05)
				)), 0.000001),
				"hindsight": true,
				"origin": "hindsight",
				# Hindsight changes only the goal/reward. The action was generated by the
				# same behavior source as its real transition and full-state replay validation
				# must preserve that provenance.
				"behavior_source": str(source.get("behavior_source", "policy")),
			})


func _original_goal_from_trace(trace: Dictionary) -> Dictionary:
	var compact_position: Variant = trace.get("target_position_world")
	if compact_position is Vector3:
		return {
			"position_world": compact_position,
			"target_radius_m": maxf(float(trace.get("target_radius_m", 1.0)), 0.0),
		}
	var frames: Array = trace.get("frames", [])
	if frames.is_empty() or not (frames[0] is Dictionary):
		return {}
	var first_frame: Dictionary = frames[0]
	var position_value: Variant = first_frame.get("target_position_world")
	if not (position_value is Vector3):
		return {}
	return {
		"position_world": position_value,
		"target_radius_m": maxf(float(first_frame.get("target_radius_m", 1.0)), 0.0),
	}


func _relabel_interval_reward(
	trace: Dictionary,
	old_observation: Dictionary,
	next_observation: Dictionary,
	substituted_goal: Dictionary
) -> Dictionary:
	if (
		int(trace.get("schema_version", 0)) != 1
		or str(trace.get("goal_schema", "")) != "stationary_position_v1"
	):
		return {"valid": false, "error": "unsupported_goal_schema"}
	var goal_position_value: Variant = substituted_goal.get("position_world")
	if not (goal_position_value is Vector3):
		return {"valid": false, "error": "missing_goal_position"}
	var goal_position: Vector3 = goal_position_value
	var goal_radius = maxf(float(substituted_goal.get("target_radius_m", 1.0)), 0.0)
	var components = {
		"approach_reward": 0.0,
		"radius_reward": 0.0,
		"survival_reward": 0.0,
		"ground_safety_reward": 0.0,
		"smoothness_reward": 0.0,
		"action_abuse_reward": 0.0,
		"obstacle_reward": 0.0,
		"turret_safety_reward": 0.0,
		"progress_correction": 0.0,
		"failure_penalty": 0.0,
		"timeout_survival_bonus": 0.0,
		"blocked_detour_relief": 0.0,
		"exploration_bonus": 0.0,
	}
	var component_config: Dictionary = trace.get("reward_components", {})
	var compact_previous: PackedVector3Array = trace.get(
		"frame_previous_positions",
		PackedVector3Array()
	)
	var compact_next: PackedVector3Array = trace.get(
		"frame_next_positions",
		PackedVector3Array()
	)
	var compact_deltas: PackedFloat64Array = trace.get(
		"frame_delta_seconds",
		PackedFloat64Array()
	)
	var compact_components: PackedFloat64Array = trace.get(
		"frame_reward_components",
		PackedFloat64Array()
	)
	if not compact_previous.is_empty():
		var compact_count = compact_previous.size()
		if (
			compact_next.size() != compact_count
			or compact_deltas.size() != compact_count
			or compact_components.size() != compact_count * 6
		):
			return {"valid": false, "error": "invalid_compact_reward_trace"}
		for frame_index in range(compact_count):
			var goal_terms = DroneTrainingReward.evaluate_goal_terms(
				compact_previous[frame_index],
				compact_next[frame_index],
				goal_position,
				goal_radius,
				compact_deltas[frame_index],
				component_config
			)
			var component_offset = frame_index * 6
			components["approach_reward"] += float(goal_terms.get("approach_reward", 0.0))
			components["radius_reward"] += float(goal_terms.get("radius_reward", 0.0))
			components["survival_reward"] += compact_components[component_offset]
			components["ground_safety_reward"] += compact_components[component_offset + 1]
			components["smoothness_reward"] += compact_components[component_offset + 2]
			# action_abuse_reward is diagnostic and already included in smoothness_reward.
			components["action_abuse_reward"] += compact_components[component_offset + 3]
			components["obstacle_reward"] += compact_components[component_offset + 4]
			components["turret_safety_reward"] += compact_components[component_offset + 5]
	else:
		var frames: Array = trace.get("frames", [])
		for frame_value in frames:
			if not (frame_value is Dictionary):
				return {"valid": false, "error": "invalid_reward_frame"}
			var frame: Dictionary = frame_value
			var previous_value: Variant = frame.get("previous_position_world")
			var next_value: Variant = frame.get("next_position_world")
			if not (previous_value is Vector3) or not (next_value is Vector3):
				return {"valid": false, "error": "invalid_reward_position"}
			var goal_terms = DroneTrainingReward.evaluate_goal_terms(
				previous_value,
				next_value,
				goal_position,
				goal_radius,
				float(frame.get("delta_seconds", 0.0)),
				component_config
			)
			components["approach_reward"] += float(goal_terms.get("approach_reward", 0.0))
			components["radius_reward"] += float(goal_terms.get("radius_reward", 0.0))
			components["survival_reward"] += float(frame.get("survival_reward", 0.0))
			components["ground_safety_reward"] += float(frame.get("ground_safety_reward", 0.0))
			components["smoothness_reward"] += float(frame.get("smoothness_reward", 0.0))
			components["action_abuse_reward"] += float(frame.get("action_abuse_reward", 0.0))
			components["obstacle_reward"] += float(frame.get("obstacle_reward", 0.0))
			components["turret_safety_reward"] += float(frame.get("turret_safety_reward", 0.0))
	var terminal: Dictionary = trace.get("terminal_adjustments", {})
	components["progress_correction"] = float(terminal.get("progress_correction", 0.0))
	components["failure_penalty"] = float(terminal.get("failure_penalty", 0.0))
	components["timeout_survival_bonus"] = float(terminal.get("timeout_survival_bonus", 0.0))
	var shaping: Dictionary = trace.get("algorithm_shaping", {})
	var original_goal = _original_goal_from_trace(trace)
	var original_goal_position: Vector3 = original_goal.get(
		"position_world",
		Vector3(INF, INF, INF)
	)
	var same_goal = (
		not original_goal.is_empty()
		and original_goal_position.is_equal_approx(goal_position)
		and is_equal_approx(float(original_goal.get("target_radius_m", 0.0)), goal_radius)
	)
	if same_goal:
		# Preserve the exact production value for the identity path. The captured target-ray
		# geometry is authoritative for the original goal; sector reconstruction is only needed
		# after the goal changes.
		components["blocked_detour_relief"] = float(shaping.get(
			"blocked_detour_relief",
			0.0
		))
	else:
		var relabelled_old = _relabel_goal(old_observation, goal_position, goal_radius)
		var relabelled_next = _relabel_goal(next_observation, goal_position, goal_radius)
		components["blocked_detour_relief"] = _blocked_detour_relief(
			relabelled_old,
			relabelled_next
		)
	components["exploration_bonus"] = float(shaping.get("exploration_bonus", 0.0))
	var total = 0.0
	for key in [
		"approach_reward", "radius_reward", "survival_reward",
		"ground_safety_reward", "smoothness_reward", "obstacle_reward",
		"turret_safety_reward", "progress_correction", "failure_penalty",
		"timeout_survival_bonus", "blocked_detour_relief", "exploration_bonus",
	]:
		total += float(components[key])
	if not is_finite(total):
		return {"valid": false, "error": "non_finite_reward"}
	return {
		"valid": true,
		"reward": total,
		"components": components,
		"done": bool(trace.get("source_terminated", false)),
		"terminated": bool(trace.get("source_terminated", false)),
		"truncated": bool(trace.get("source_truncated", false)),
	}


func _relabel_goal(
	observation_value: Variant,
	goal_position: Vector3,
	goal_radius: float = NAN
) -> Dictionary:
	if not (observation_value is Dictionary):
		return {}
	# HER changes only the objective and its goal-ray summary. Preserve the immutable body,
	# environment, hardware, and packed sensor branches instead of recursively cloning them.
	var observation: Dictionary = (observation_value as Dictionary).duplicate(false)
	var objective: Dictionary = observation.get("objective", {}).duplicate(false)
	var effective_goal_radius = goal_radius
	if not is_finite(effective_goal_radius):
		effective_goal_radius = float(objective.get("target_hover_radius_m", 1.0))
	objective["target_position_world"] = goal_position
	objective["target_velocity_world"] = Vector3.ZERO
	objective["target_hover_radius_m"] = maxf(effective_goal_radius, 0.1)
	var probe_value: Variant = objective.get("obstacle_probe", {})
	if probe_value is Dictionary:
		objective["obstacle_probe"] = _relabelled_goal_probe(
			observation,
			probe_value as Dictionary,
			goal_position
		)
	observation["objective"] = objective
	return observation


func _relabelled_goal_probe(
	observation: Dictionary,
	probe_source: Dictionary,
	goal_position: Vector3
) -> Dictionary:
	var probe = probe_source.duplicate(false)
	var body: Dictionary = observation.get("body", {})
	var position: Vector3 = body.get("position_world", Vector3.ZERO)
	var offset = goal_position - position
	var target_distance = offset.length()
	var horizontal_offset = Vector3(offset.x, 0.0, offset.z)
	var horizontal_distance = horizontal_offset.length()
	var sector_maximum = maxf(
		float(probe.get("sector_maximum_distance_m", 12.0)),
		0.001
	)
	var clearance = target_distance
	var sector_clearances = _packed_numeric_array(
		probe.get("sector_clearances_m", PackedFloat64Array())
	)
	if (
		horizontal_distance > 0.000001
		and sector_clearances.size() >= DroneSACNavigationMemory.SECTOR_COUNT
	):
		var basis: Basis = body.get("basis_world", Basis.IDENTITY)
		var forward = Vector3(-basis.z.x, 0.0, -basis.z.z)
		var right = Vector3(basis.x.x, 0.0, basis.x.z)
		if forward.length_squared() <= 0.000001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()
		if right.length_squared() <= 0.000001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		var direction = horizontal_offset / horizontal_distance
		var local_x = direction.dot(right)
		var local_z = -direction.dot(forward)
		var clockwise_angle = fposmod(atan2(local_x, -local_z), TAU)
		var sector = posmod(
			roundi(clockwise_angle * float(DroneSACNavigationMemory.SECTOR_COUNT) / TAU),
			DroneSACNavigationMemory.SECTOR_COUNT
		)
		var sampled_clearance = clampf(
			float(sector_clearances[sector]),
			0.0,
			sector_maximum
		)
		# A sector at its maximum means "no wall observed", not "a wall at the lidar range".
		if sampled_clearance + 0.001 < sector_maximum:
			clearance = minf(sampled_clearance, target_distance)
	probe["target_path_maximum_distance_m"] = maxf(target_distance, 0.001)
	probe["target_path_clearance_m"] = clearance
	probe["target_path_blocked"] = (
		horizontal_distance > 0.35
		and clearance + 0.35 < horizontal_distance
	)
	# Sector lidar has no wall-top identity. Zero is the neutral normalized height instead of
	# incorrectly reusing the old target ray's wall height.
	probe["target_wall_top_relative_height_m"] = 0.0
	return probe


func _packed_numeric_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		var packed: PackedFloat64Array = value
		return packed
	var result = PackedFloat64Array()
	if not (value is Array):
		return result
	for item in value:
		if not (item is int or item is float):
			return PackedFloat64Array()
		result.append(float(item))
	return result


func _safe_hindsight_goal(observation: Dictionary) -> bool:
	if observation.is_empty():
		return false
	var environment: Dictionary = observation.get("environment", {})
	var objective: Dictionary = observation.get("objective", {})
	var probe: Dictionary = objective.get("obstacle_probe", {})
	var boundary_clearance = float(probe.get("arena_boundary_clearance_m", INF))
	# Hindsight goals should represent states worth deliberately returning to. The old 0.5 m
	# threshold admitted the final pre-crash frame of a ground-suicide trajectory; because HER
	# preferentially samples the latest safe future state, that could manufacture many replay
	# goals just above the floor. Use the same clearance contract as the live ground-safety
	# reward so failure-adjacent states cannot become desirable goals.
	return (
		float(environment.get("ground_clearance_m", 0.0))
		>= DroneTrainingReward.GROUND_SAFETY_HEIGHT_M
		and not bool(probe.get("wall_contact", false))
		and (
			not is_finite(boundary_clearance)
			or boundary_clearance > EXPLORATION_BOUNDARY_STOP_M
		)
	)


func _blocked_detour_relief(
	old_observation: Dictionary,
	next_observation: Dictionary
) -> float:
	var old_objective: Dictionary = old_observation.get("objective", {})
	var probe: Dictionary = old_objective.get("obstacle_probe", {})
	if not bool(probe.get("target_path_blocked", false)):
		return 0.0
	var old_body: Dictionary = old_observation.get("body", {})
	var next_body: Dictionary = next_observation.get("body", {})
	var old_position: Vector3 = old_body.get("position_world", Vector3.ZERO)
	var next_position: Vector3 = next_body.get("position_world", old_position)
	var target: Vector3 = old_objective.get("target_position_world", old_position)
	var distance_increase = maxf(
		next_position.distance_to(target) - old_position.distance_to(target),
		0.0
	)
	return (
		minf(distance_increase / 10.0, 0.1)
		* float(config["blocked_detour_relief"])
		* _arena_boundary_shaping_scale(old_observation, next_observation)
	)


func _exploration_bonus(
	worker_id: int,
	observation: Dictionary,
	next_observation: Dictionary,
	delta_seconds: float = 0.05
) -> float:
	var body: Dictionary = observation.get("body", {})
	var next_body: Dictionary = next_observation.get("body", {})
	var position: Vector3 = body.get("position_world", Vector3.ZERO)
	var next_position: Vector3 = next_body.get("position_world", position)
	var cell_size = DroneSACNavigationMemory.CELL_SIZE_M
	var cell = Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))
	var next_cell = Vector2i(
		floori(next_position.x / cell_size),
		floori(next_position.z / cell_size)
	)
	var elapsed = float(exploration_elapsed_seconds.get(worker_id, 0.0))
	elapsed += delta_seconds
	exploration_elapsed_seconds[worker_id] = elapsed

	var visited: Dictionary = exploration_cell_last_visit_seconds.get(worker_id, {})
	var cell_key = _exploration_cell_key(cell)
	var next_cell_key = _exploration_cell_key(next_cell)
	# Register the starting cell before evaluating the destination. Without this, the first
	# return to the spawn cell would incorrectly count as exploration. Repeated same-cell
	# decisions refresh the timestamp, so the cooldown begins when the drone actually leaves.
	if not visited.has(cell_key):
		visited[cell_key] = elapsed - delta_seconds
	var cooldown = float(config["exploration_cell_cooldown_seconds"])
	var last_visit = float(visited.get(next_cell_key, -INF))
	var rewardable = (
		not visited.has(next_cell_key)
		or elapsed - last_visit >= cooldown
	)
	visited[next_cell_key] = elapsed
	exploration_cell_last_visit_seconds[worker_id] = visited
	if cell == next_cell or not rewardable:
		return 0.0

	var probe: Dictionary = (observation.get("objective", {}) as Dictionary).get(
		"obstacle_probe",
		{}
	)
	var next_probe: Dictionary = (
		(next_observation.get("objective", {}) as Dictionary).get(
			"obstacle_probe",
			{}
		)
	)
	var blocked = (
		bool(probe.get("target_path_blocked", false))
		or bool(next_probe.get("target_path_blocked", false))
	)
	var blocked_scale = 1.0 if blocked else 0.2
	return (
		float(config["exploration_bonus"])
		* blocked_scale
		* _arena_boundary_shaping_scale(observation, next_observation)
	)


func _arena_boundary_shaping_scale(
	observation: Dictionary,
	next_observation: Dictionary
) -> float:
	var probe: Dictionary = (observation.get("objective", {}) as Dictionary).get(
		"obstacle_probe",
		{}
	)
	var next_probe: Dictionary = (
		(next_observation.get("objective", {}) as Dictionary).get(
			"obstacle_probe",
			{}
		)
	)
	var boundary_clearance = minf(
		float(probe.get("arena_boundary_clearance_m", INF)),
		float(next_probe.get("arena_boundary_clearance_m", INF))
	)
	if not is_finite(boundary_clearance):
		return 1.0
	return clampf(
		(boundary_clearance - EXPLORATION_BOUNDARY_STOP_M)
		/ maxf(EXPLORATION_BOUNDARY_FULL_M - EXPLORATION_BOUNDARY_STOP_M, 0.001),
		0.0,
		1.0
	)


func _exploration_cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _reset_exploration_memory(worker_id: int) -> void:
	exploration_cell_last_visit_seconds.erase(worker_id)
	exploration_elapsed_seconds.erase(worker_id)


func _actor_prefix(critic_input: PackedFloat64Array) -> PackedFloat64Array:
	if critic_input.size() != DroneSACObservationEncoder.CRITIC_FEATURE_COUNT:
		return PackedFloat64Array()
	var result = PackedFloat64Array()
	for index in range(DroneSACObservationEncoder.LEGACY_ACTOR_FEATURE_COUNT):
		result.append(critic_input[index])
	for index in range(DroneSACObservationEncoder.TURRET_THREAT_FEATURE_COUNT):
		result.append(critic_input[
			DroneSACObservationEncoder.LEGACY_CRITIC_FEATURE_COUNT + index
		])
	return result


func _actor_memory_suffix(actor_input: PackedFloat64Array) -> PackedFloat64Array:
	if actor_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT:
		return PackedFloat64Array()
	var result = PackedFloat64Array()
	result.resize(DroneSACNavigationMemory.FEATURE_COUNT)
	for index in range(result.size()):
		result[index] = actor_input[
			DroneSACObservationEncoder.LEGACY_BASE_FEATURE_COUNT + index
		]
	# encode_actor exposes the final local-Z memory component as positive-forward.
	# Replay/HER stores raw navigation-memory coordinates, so invert that transform here.
	if not result.is_empty():
		result[result.size() - 1] = -result[result.size() - 1]
	return result


func _replay_in_chronological_order() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	if replay_buffer.is_empty():
		return ordered
	if replay_write_index <= 0:
		for transition in replay_buffer:
			ordered.append((transition as Dictionary).duplicate(true))
		return ordered
	for offset in range(replay_buffer.size()):
		var index = (replay_write_index + offset) % replay_buffer.size()
		ordered.append((replay_buffer[index] as Dictionary).duplicate(true))
	return ordered


func _recount_replay_origins() -> void:
	real_replay_count = 0
	hindsight_replay_count = 0
	for transition in replay_buffer:
		_increment_replay_origin(transition, 1)


func _clear_replay(reset_warmup_gate = true) -> void:
	replay_buffer.clear()
	replay_write_index = 0
	real_replay_count = 0
	hindsight_replay_count = 0
	sampled_real_count = 0
	sampled_hindsight_count = 0
	if reset_warmup_gate:
		environment_steps_since_replay_reset = 0
		policy_environment_steps_since_replay_reset = 0
		structured_warmup_environment_steps_since_replay_reset = 0


func _trim_replay_to_capacity() -> void:
	var capacity = int(config["replay_capacity"])
	var ordered = _replay_in_chronological_order()
	var first = maxi(ordered.size() - capacity, 0)
	var trimmed: Array[Dictionary] = []
	for index in range(first, ordered.size()):
		trimmed.append(ordered[index].duplicate(true))
	replay_buffer = trimmed
	# When full, index zero is the oldest and therefore the next overwrite location. When
	# not full, writes append and the index remains dormant until capacity is reached.
	replay_write_index = 0
	_recount_replay_origins()


func _valid_replay_transition(transition: Dictionary) -> bool:
	var actor_input_value: Variant = transition.get("actor_input", null)
	var critic_input_value: Variant = transition.get("critic_input", null)
	var next_actor_input_value: Variant = transition.get("next_actor_input", null)
	var next_critic_input_value: Variant = transition.get("next_critic_input", null)
	var policy_actions_value: Variant = transition.get("policy_actions", null)
	var commands_value: Variant = transition.get("commands", null)
	if (
		not (actor_input_value is PackedFloat64Array)
		or not (critic_input_value is PackedFloat64Array)
		or not (next_actor_input_value is PackedFloat64Array)
		or not (next_critic_input_value is PackedFloat64Array)
		or not (policy_actions_value is PackedFloat64Array)
		or not (commands_value is PackedFloat64Array)
	):
		return false
	var terminated_value: Variant = transition.get("terminated", null)
	var truncated_value: Variant = transition.get("truncated", null)
	var done_value: Variant = transition.get("done", null)
	var hindsight_value: Variant = transition.get("hindsight", null)
	if (
		not (terminated_value is bool)
		or not (truncated_value is bool)
		or not (done_value is bool)
		or not (hindsight_value is bool)
	):
		return false
	var behavior_source_value: Variant = transition.get("behavior_source", null)
	var origin_value: Variant = transition.get("origin", null)
	if not (behavior_source_value is String) or not (origin_value is String):
		return false
	var logical_id_value: Variant = transition.get("logical_transition_id", null)
	if not (logical_id_value is int or logical_id_value is float):
		return false
	var logical_transition_id: int = RLTrainingMath.finite_int_or(logical_id_value, -1)
	if logical_transition_id < 0:
		return false
	var actor_input: PackedFloat64Array = actor_input_value
	var critic_input: PackedFloat64Array = critic_input_value
	var next_actor_input: PackedFloat64Array = next_actor_input_value
	var next_critic_input: PackedFloat64Array = next_critic_input_value
	var policy_actions: PackedFloat64Array = policy_actions_value
	var commands: PackedFloat64Array = commands_value
	var behavior_source: String = behavior_source_value
	var terminated: bool = terminated_value
	var truncated: bool = truncated_value
	var done: bool = done_value
	var hindsight: bool = hindsight_value
	var expected_origin: String = "hindsight" if hindsight else "real"
	var reward: float = RLTrainingMath.finite_float_or(transition.get("reward", NAN), NAN)
	var delta_seconds: float = RLTrainingMath.finite_float_or(
		transition.get("delta_seconds", NAN),
		NAN
	)
	var omitted_terminal_successor: bool = (
		terminated and next_actor_input.is_empty() and next_critic_input.is_empty()
	)
	if (
		terminated and truncated
		or done != terminated
		or str(origin_value) != expected_origin
		or not (behavior_source in ["structured_warmup", "policy"])
		or not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
		or (
			not omitted_terminal_successor
			and not DroneSACObservationEncoder.valid_tensors(next_actor_input, next_critic_input)
		)
		or policy_actions.size() != DroneSACObservationEncoder.ACTION_COUNT
		or commands.size() != DroneSACObservationEncoder.ACTION_COUNT
		or not DronePPOObservationEncoder.is_normalized_tensor(policy_actions)
		or not RLTrainingMath.packed_all_finite(commands)
		or not is_finite(reward)
		or not is_finite(delta_seconds)
		or delta_seconds <= 0.0
	):
		return false
	return true


func _maximum_replay_logical_id() -> int:
	var maximum = -1
	for transition in replay_buffer:
		maximum = maxi(
			maximum,
			RLTrainingMath.finite_int_or(transition.get("logical_transition_id", -1), -1)
		)
	return maximum


func _checkpoint_with_network(
	network_state: Dictionary,
	use_best_counters: bool
) -> Dictionary:
	return {
		"schema_version": CHECKPOINT_SCHEMA_VERSION,
		"algorithm": ALGORITHM_NAME,
		"training_algorithm_id": TRAINING_ALGORITHM_ID,
		"propeller_count": DroneSACObservationEncoder.ACTION_COUNT,
		"config": config.duplicate(true),
		"discount_time_base": {
			"discount_key": "discount_factor",
			"reference_interval_seconds": float(config.get("discount_reference_interval_seconds", 0.05)),
			"lambda_semantics": "not_applicable",
		},
		"network": network_state.duplicate(true),
		"training": {
			"update_count": update_count,
			"environment_steps": environment_steps,
			"completed_episodes": completed_episodes,
			"best_episode_mean_reward": (
				best_episode_mean_reward if is_finite(best_episode_mean_reward) else 0.0
			),
			"has_best_episode": is_finite(best_episode_mean_reward),
			"has_exact_best_policy": false,
			"best_network_state": best_network_state.duplicate(true),
			"best_candidate": best_selection_summary(),
			"best_evaluation": best_evaluation.duplicate(true),
			"best_evaluation_contract": best_evaluation_contract.duplicate(true),
			"promoted_training_summary": promoted_training_summary.duplicate(true),
			"pending_evaluation_candidate": pending_candidate.duplicate(true),
			"candidate_network_state": candidate_network_state.duplicate(true),
			"candidate_training_summary": candidate_training_summary.duplicate(true),
			"candidate_sequence": candidate_sequence,
			"last_metrics": {} if use_best_counters else last_metrics.duplicate(true),
			"random_seed": random_seed,
		},
	}


func _apply_training_context_to_checkpoint(
	checkpoint: Dictionary,
	context: Dictionary
) -> void:
	if checkpoint.is_empty() or context.is_empty():
		return
	var training: Dictionary = checkpoint.get("training", {}).duplicate(true)
	training["update_count"] = int(context.get("policy_update", training.get("update_count", 0)))
	training["environment_steps"] = int(context.get(
		"environment_steps",
		training.get("environment_steps", 0)
	))
	training["completed_episodes"] = int(context.get(
		"completed_episodes",
		training.get("completed_episodes", 0)
	))
	checkpoint["training"] = training


func _sanitize_config() -> void:
	_sanitize_config_dictionary(config)


func _sanitize_config_dictionary(target_config: Dictionary) -> void:
	target_config["learning_rate"] = clampf(RLTrainingMath.finite_float_or(target_config.get("learning_rate"), DEFAULT_CONFIG["learning_rate"]), 0.000001, 0.1)
	target_config["discount_factor"] = clampf(RLTrainingMath.finite_float_or(target_config.get("discount_factor"), DEFAULT_CONFIG["discount_factor"]), 0.0, 1.0)
	target_config["entropy_temperature"] = clampf(RLTrainingMath.finite_float_or(target_config.get("entropy_temperature"), DEFAULT_CONFIG["entropy_temperature"]), 0.0, 0.05)
	target_config["automatic_entropy_temperature"] = RLTrainingMath.bool_or(target_config.get("automatic_entropy_temperature"), DEFAULT_CONFIG["automatic_entropy_temperature"])
	target_config["target_entropy"] = clampf(RLTrainingMath.finite_float_or(target_config.get("target_entropy"), DEFAULT_CONFIG["target_entropy"]), 0.0, 64.0)
	target_config["entropy_temperature_learning_rate"] = clampf(
		RLTrainingMath.finite_float_or(target_config.get("entropy_temperature_learning_rate"), DEFAULT_CONFIG["entropy_temperature_learning_rate"]),
		0.0000001,
		0.1
	)
	target_config["target_update_rate"] = clampf(RLTrainingMath.finite_float_or(target_config.get("target_update_rate"), DEFAULT_CONFIG["target_update_rate"]), 0.00001, 1.0)
	target_config["maximum_gradient_norm"] = maxf(RLTrainingMath.finite_float_or(target_config.get("maximum_gradient_norm"), DEFAULT_CONFIG["maximum_gradient_norm"]), 0.0)
	target_config["batch_size"] = maxi(RLTrainingMath.finite_int_or(target_config.get("batch_size"), DEFAULT_CONFIG["batch_size"]), 1)
	target_config["replay_capacity"] = maxi(RLTrainingMath.finite_int_or(target_config.get("replay_capacity"), DEFAULT_CONFIG["replay_capacity"]), int(target_config["batch_size"]))
	target_config["learning_starts"] = clampi(
		RLTrainingMath.finite_int_or(target_config.get("learning_starts"), DEFAULT_CONFIG["learning_starts"]),
		int(target_config["batch_size"]),
		int(target_config["replay_capacity"])
	)
	target_config["warmup_exploration_steps"] = clampi(
		RLTrainingMath.finite_int_or(target_config.get("warmup_exploration_steps"), DEFAULT_CONFIG["warmup_exploration_steps"]),
		0,
		int(target_config["replay_capacity"])
	)
	target_config["update_interval_transitions"] = maxi(RLTrainingMath.finite_int_or(target_config.get("update_interval_transitions"), DEFAULT_CONFIG["update_interval_transitions"]), 1)
	target_config["gradient_steps_per_update"] = clampi(RLTrainingMath.finite_int_or(target_config.get("gradient_steps_per_update"), DEFAULT_CONFIG["gradient_steps_per_update"]), 1, 64)
	target_config["hindsight_goals_per_transition"] = clampi(RLTrainingMath.finite_int_or(target_config.get("hindsight_goals_per_transition"), DEFAULT_CONFIG["hindsight_goals_per_transition"]), 0, 16)
	target_config["exploration_bonus"] = clampf(RLTrainingMath.finite_float_or(target_config.get("exploration_bonus"), DEFAULT_CONFIG["exploration_bonus"]), 0.0, 1.0)
	target_config["exploration_cell_cooldown_seconds"] = clampf(
		RLTrainingMath.finite_float_or(target_config.get("exploration_cell_cooldown_seconds"), DEFAULT_CONFIG["exploration_cell_cooldown_seconds"]),
		1.0,
		600.0
	)
	target_config["blocked_detour_relief"] = clampf(RLTrainingMath.finite_float_or(target_config.get("blocked_detour_relief"), DEFAULT_CONFIG["blocked_detour_relief"]), 0.0, 1.0)
	target_config["discount_reference_interval_seconds"] = clampf(
		RLTrainingMath.finite_float_or(target_config.get("discount_reference_interval_seconds"), DEFAULT_CONFIG["discount_reference_interval_seconds"]),
		0.001,
		1.0
	)
	target_config["control_interval_seconds"] = clampf(RLTrainingMath.finite_float_or(target_config.get("control_interval_seconds"), DEFAULT_CONFIG["control_interval_seconds"]), 0.01, 1.0)
	target_config["hidden_layer_width"] = clampi(
		RLTrainingMath.finite_int_or(target_config.get("hidden_layer_width"), DEFAULT_CONFIG["hidden_layer_width"]),
		DronePPOMLP.MINIMUM_HIDDEN_WIDTH,
		DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
	)
	target_config["hidden_layer_depth"] = clampi(
		RLTrainingMath.finite_int_or(target_config.get("hidden_layer_depth"), DEFAULT_CONFIG["hidden_layer_depth"]),
		DronePPOMLP.MINIMUM_HIDDEN_DEPTH,
		DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	)
