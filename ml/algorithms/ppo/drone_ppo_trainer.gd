class_name DronePPOTrainer
extends DroneTrainingAlgorithm

const CHECKPOINT_SCHEMA_VERSION: int = 6
const ALGORITHM_NAME = "clipped_ppo_gae"
const DEFAULT_WORKER_COUNT = 8
const MAXIMUM_WORKER_COUNT = 48
const FEATURE_AUDIT_UPDATE_INTERVAL = 25
const FEATURE_AUDIT_MAXIMUM_SAMPLES = 128
const TRAINING_ALGORITHM_ID = "ppo_clip"
const ELITE_SELECTION_WEIGHT = 0.60
const OUTLIER_FENCE_MULTIPLIER = 1.5
const MINIMUM_CANDIDATE_TRANSITIONS_PER_WORKER = 4
const INITIAL_LOG_PROBABILITY_TOLERANCE = 0.00000001
const PPO_KL_STOP_MULTIPLIER = 1.5
const DEFAULT_CONFIG = {
	"learning_rate": 0.0003,
	"discount_factor": 0.99,
	"gae_lambda": 0.95,
	"clip_range": 0.2,
	"value_coefficient": 0.5,
	"entropy_coefficient": 0.01,
	"maximum_gradient_norm": 0.5,
	"update_epochs": 4,
	"minibatch_size": 64,
	"rollout_transitions": 512,
	"minimum_update_transitions": 64,
	"target_kl": 0.03,
	"control_interval_seconds": 0.05,
	"discount_reference_interval_seconds": 0.05,
	"optimizer_samples_per_frame": 16,
	"hidden_layer_width": DronePPOActorCritic.HIDDEN_SIZE,
	"hidden_layer_depth": DronePPOActorCritic.HIDDEN_LAYER_COUNT,
	"action_count": DronePPOActorCritic.ACTION_COUNT,
	# Fresh creator bodies can supply per-control startup targets. They affect only initialization;
	# trained/checkpointed weights remain the policy authority afterward.
	"initial_control_values": [],
}

#######################################################
# Collects synchronized on-policy quadrotor transitions and runs clipped PPO as an
# incremental minibatch job. A stable behavior-policy copy keeps action sampling coherent.
# The training room transfers complete update jobs to a private low-priority Thread, while
# the incremental API remains available for deterministic tests and non-threaded callers.
#######################################################

var config = DEFAULT_CONFIG.duplicate(true)
var body_interface_contract_data: Dictionary = {}
var body_feature_count: int = 0
var body_interface_signature: String = ""
var body_control_descriptors: Array[Dictionary] = []
var body_interface_locked: bool = false
var initialization_valid: bool = false
var actor_critic: DronePPOActorCritic
var behavior_actor_critic: DronePPOActorCritic
var rollout: Array[Dictionary] = []
var rollout_policy_revision = -1
var rollout_start_network_state: Dictionary = {}
var shuffle_rng = RandomNumberGenerator.new()
var random_seed = 4194301
var update_count = 0
var environment_steps = 0
var completed_episodes = 0
var best_episode_mean_reward = -INF
var best_network_state: Dictionary = {}
var best_candidate_score = -INF
var best_candidate_group_mean_reward = -INF
var best_candidate_support_reward = -INF
var best_candidate_worker_reward = -INF
var best_candidate_robust_worker_reward = -INF
var best_candidate_policy_update = 0
var best_candidate_environment_steps = 0
var best_candidate_completed_episodes = 0
var best_candidate_worker_count = 0
var best_candidate_transition_count = 0
var behavior_policy_update = 0
var optimizer_policy_revision = 0
var candidate_sequence = 0
# Training rollouts may nominate frozen candidates, but only a deterministic evaluation
# suite may promote one to the designated best checkpoint.
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

var update_in_progress = false
var update_rollout: Array[Dictionary] = []
var update_advantages = PackedFloat64Array()
var update_returns = PackedFloat64Array()
var update_indices: Array[int] = []
var update_epoch = 0
var update_batch_start = 0
var update_batch_cursor = 0
var update_batch_end = 0
var update_batch_count = 0
var update_epoch_kl_total = 0.0
var update_epoch_sample_count = 0
var update_metric_totals: Dictionary = {}
var update_metric_sample_count = 0
var update_optimizer_batches = 0
var update_early_stopped = false
var update_early_stop_reason = ""
var update_initial_log_probability_error_max = 0.0
var update_initial_approximate_kl = 0.0
var update_initial_clip_fraction = 0.0
var update_maximum_minibatch_kl = 0.0
var update_completed_minibatches = 0
var update_prepared: Dictionary = {}
var update_feature_audit: Dictionary = {}
var update_start_network_state: Dictionary = {}
var policy_sync_pending = false
var discarded_on_policy_transitions_since_update = 0
var background_thread: Thread
var background_job: RefCounted
var background_result_discarded = false
var background_started_usec = 0
var last_background_update_ms = 0.0


func _init(custom_config: Dictionary = {}, initialization_seed = 4194301) -> void:
	var requested_body_interface: Variant = custom_config.get("body_interface", {})
	body_interface_locked = requested_body_interface is Dictionary and _valid_body_interface_contract(
		requested_body_interface as Dictionary
	)
	if not body_interface_locked or not _configure_body_interface(requested_body_interface):
		last_error = "PPO model initialization requires an accepted body-interface manifest."
		return
	for key in custom_config:
		if config.has(key) and str(key) != "action_count":
			config[key] = custom_config[key]
	config["action_count"] = body_control_descriptors.size()
	_sanitize_config()
	random_seed = initialization_seed
	actor_critic = DronePPOActorCritic.new(
		random_seed,
		DronePPOObservationEncoder.SCHEMA_VERSION,
		int(config["hidden_layer_width"]),
		int(config["hidden_layer_depth"]),
		int(config["action_count"]),
		body_feature_count,
		body_control_descriptors,
		body_interface_signature,
		(config.get("initial_control_values", []) as Array)
	)
	behavior_actor_critic = DronePPOActorCritic.new(
		random_seed + 500003,
		DronePPOObservationEncoder.SCHEMA_VERSION,
		int(config["hidden_layer_width"]),
		int(config["hidden_layer_depth"]),
		int(config["action_count"]),
		body_feature_count,
		body_control_descriptors,
		body_interface_signature,
		(config.get("initial_control_values", []) as Array)
	)
	_sync_behavior_from_optimizer(true)
	shuffle_rng.seed = random_seed + 101
	initialization_valid = true


func is_initialized() -> bool:
	return initialization_valid and actor_critic != null and behavior_actor_critic != null


func algorithm_id() -> String:
	return TRAINING_ALGORITHM_ID


func algorithm_display_name() -> String:
	return "Clipped PPO + GAE"


func algorithm_short_name() -> String:
	return "PPO"


func default_worker_count() -> int:
	return DEFAULT_WORKER_COUNT


func maximum_worker_count() -> int:
	return MAXIMUM_WORKER_COUNT


func configuration_controls() -> Array[Dictionary]:
	return [
		{"key": "optimizer_samples_per_frame", "title": "Training work per cycle", "minimum": 1.0, "maximum": 512.0, "step": 1.0, "integer": true, "tooltip": "How many training examples PPO processes before briefly checking the game again.\n\n16 is responsive. Larger values reduce overhead but make pausing slower to react."},
		{"key": "learning_rate", "title": "Learning rate", "minimum": 0.000001, "maximum": 0.005, "step": 0.000001, "integer": false, "tooltip": "How large each learning correction is.\n\nToo high can destroy useful behaviour. Too low learns very slowly.\nDefault: 0.00030."},
		{"key": "discount_factor", "title": "Future reward importance", "minimum": 0.5, "maximum": 1.0, "step": 0.001, "integer": false, "tooltip": "How much PPO cares about rewards that happen later.\n\nHigher values suit flight and longer tasks. Lower values favour immediate reactions.\nDefault: 0.99."},
		{"key": "gae_lambda", "title": "Reward estimate smoothing", "minimum": 0.5, "maximum": 1.0, "step": 0.005, "integer": false, "tooltip": "Balances immediate evidence against longer reward patterns.\n\nHigher values look farther ahead but can be noisier.\nDefault: 0.95."},
		{"key": "clip_range", "title": "Maximum policy change", "minimum": 0.01, "maximum": 0.8, "step": 0.01, "integer": false, "tooltip": "Limits how far PPO may change the policy in one update.\n\nHigher values learn more aggressively and can damage a working model.\nDefault: 0.20."},
		{"key": "entropy_coefficient", "title": "Exploration strength", "minimum": 0.0, "maximum": 2.0, "step": 0.005, "integer": false, "tooltip": "Regularizes PPO's Gaussian policy before its commands are sigmoid-squashed into the physical 0..1 motor range.\n\nThis is latent-policy entropy, not literal motor-command entropy. Too low can cause repetitive behaviour. Too high can drown out the task reward.\nDefault: 0.01."},
		{"key": "value_coefficient", "title": "Reward-prediction strength", "minimum": 0.0, "maximum": 2.0, "step": 0.05, "integer": false, "tooltip": "Controls how strongly PPO trains its future-reward predictor.\n\nToo little gives poor guidance. Too much can dominate policy learning.\nDefault: 0.50."},
		{"key": "maximum_gradient_norm", "title": "Learning-spike limiter", "minimum": 0.05, "maximum": 5.0, "step": 0.05, "integer": false, "tooltip": "Limits unusually large learning corrections.\n\nThis helps one bad batch from damaging the whole model.\nDefault: 0.50."},
		{"key": "update_epochs", "title": "Passes per update", "minimum": 1.0, "maximum": 24.0, "step": 1.0, "integer": true, "tooltip": "How many times PPO studies the same collected experience.\n\nMore passes learn harder from each rollout but can overfit it.\nDefault: 4."},
		{"key": "minibatch_size", "title": "Decisions per learning step", "minimum": 8.0, "maximum": 1024.0, "step": 8.0, "integer": true, "tooltip": "How many decisions PPO studies together in one learning step.\n\nLarger batches are steadier but need more collected experience.\nDefault: 64."},
		{"key": "rollout_transitions", "title": "Decisions before learning", "minimum": 64.0, "maximum": 16384.0, "step": 64.0, "integer": true, "tooltip": "How many model decisions are collected before PPO learns.\n\nMore experience gives steadier updates but makes learning less immediate.\nDefault: 512."},
		{"key": "minimum_update_transitions", "title": "Minimum decisions for partial learning", "minimum": 8.0, "maximum": 2048.0, "step": 8.0, "integer": true, "tooltip": "Minimum experience needed to learn from a partly filled rollout at episode end.\n\nSmaller values use short episodes sooner but can be noisy.\nDefault: 64."},
		{"key": "target_kl", "title": "Emergency change limit", "minimum": 0.001, "maximum": 0.25, "step": 0.001, "integer": false, "tooltip": "Stops the current PPO update when the policy has already changed too much.\n\nLower values are safer. Higher values allow more aggressive updates.\nDefault: 0.03."},
	]


func config_values() -> Dictionary:
	return config


func set_config_value(key: String, value: Variant) -> bool:
	if key in ["hidden_layer_width", "hidden_layer_depth", "action_count", "initial_control_values"]:
		return false
	if not config.has(key):
		return false
	config[key] = value
	_sanitize_config()
	return true


func network_architecture() -> Dictionary:
	return {
		"hidden_layer_width": actor_critic.hidden_size,
		"hidden_layer_depth": actor_critic.hidden_layer_count,
		"action_count": actor_critic.action_count,
		"body_feature_count": actor_critic.body_feature_count,
		"body_interface_signature": actor_critic.body_interface_signature,
		"control_names": _control_names(actor_critic.control_descriptors),
	}


func body_interface_contract() -> Dictionary:
	return body_interface_contract_data.duplicate(true)


func encode_observation(observation: Dictionary, _worker_id: int = -1) -> Dictionary:
	# A resumed schema-v4 policy must continue receiving the exact feature semantics it
	# learned. New trainers use schema v5, but encoding follows the loaded behavior policy.
	var observation_schema = behavior_actor_critic.observation_schema_version
	var actor_input = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		observation_schema,
		behavior_actor_critic.body_feature_count
	)
	return {
		"observation": observation,
		"actor_input": actor_input,
		"critic_input": DronePPOObservationEncoder.encode_critic_from_actor_for_schema(
			actor_input,
			observation,
			observation_schema,
			behavior_actor_critic.body_feature_count
		),
	}


func sample_action(observation: Dictionary) -> Dictionary:
	var sample = behavior_actor_critic.sample_action(observation, false)
	if not sample.is_empty():
		sample["policy_revision"] = behavior_policy_update
	return sample


func sample_action_from_inputs(
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array,
	_worker_id: int = -1
) -> Dictionary:
	var sample = behavior_actor_critic.sample_action_from_inputs(
		observation,
		actor_input,
		critic_input,
		false
	)
	if not sample.is_empty():
		sample["policy_revision"] = behavior_policy_update
	return sample


func add_transition(
	worker_id: int,
	action_sample: Dictionary,
	reward: float,
	next_observation: Dictionary,
	terminated: bool,
	truncated: bool,
	next_critic_input: PackedFloat64Array = PackedFloat64Array(),
	next_value_override: float = NAN,
	_transition_metadata: Dictionary = {}
) -> bool:
	last_error = ""
	if (
		action_sample.is_empty()
		or not (action_sample.get("actor_input") is PackedFloat64Array)
		or not (action_sample.get("critic_input") is PackedFloat64Array)
		or not (action_sample.get("latent_action") is PackedFloat64Array)
		or not (action_sample.get("commands") is PackedFloat64Array)
		or not (action_sample.get("policy_revision") is int or action_sample.get("policy_revision") is float)
		or not is_finite(reward)
	):
		last_error = "The PPO transition contains an invalid action sample or reward."
		return false
	if terminated and truncated:
		last_error = "A PPO transition cannot be both terminated and truncated."
		return false
	var delta_seconds: float = RLTrainingMath.finite_float_or(
		_transition_metadata.get("delta_seconds", config.get("control_interval_seconds", 0.05)),
		NAN
	)
	if not is_finite(delta_seconds) or delta_seconds <= 0.0:
		last_error = "The PPO transition duration must be finite and positive."
		return false
	var safe_delta_seconds = maxf(delta_seconds, 0.000001)
	# A true terminal state has no bootstrap successor. Requiring a valid post-death
	# observation here can silently discard the final crash/death transition and its
	# strongest failure reward. Truncations remain bootstrap-eligible and therefore
	# still require a valid successor below.
	if not terminated and not DronePPOObservationEncoder.has_valid_propeller_topology(next_observation):
		last_error = "The PPO transition contains an invalid next observation."
		return false
	var observation_schema = behavior_actor_critic.observation_schema_version
	var expected_actor_count = DronePPOObservationEncoder.actor_feature_count_for_schema(
		observation_schema,
		behavior_actor_critic.body_feature_count
	)
	var expected_critic_count = DronePPOObservationEncoder.critic_feature_count_for_schema(
		observation_schema,
		behavior_actor_critic.body_feature_count
	)
	var actor_input: PackedFloat64Array = action_sample["actor_input"]
	var critic_input: PackedFloat64Array = action_sample["critic_input"]
	var latent_action: PackedFloat64Array = action_sample["latent_action"]
	var commands: PackedFloat64Array = action_sample["commands"]
	var old_log_probability: float = RLTrainingMath.finite_float_or(
		action_sample.get("log_probability", NAN),
		NAN
	)
	var old_value: float = RLTrainingMath.finite_float_or(
		action_sample.get("value", NAN),
		NAN
	)
	if (
		actor_input.size() != expected_actor_count
		or critic_input.size() != expected_critic_count
		or latent_action.size() != behavior_actor_critic.action_count
		or commands.size() != behavior_actor_critic.action_count
		or not DronePPOObservationEncoder.is_normalized_tensor(actor_input)
		or not DronePPOObservationEncoder.is_normalized_tensor(critic_input)
		or not _finite_packed(latent_action)
		or not _finite_packed(commands)
		or not is_finite(old_log_probability)
		or not is_finite(old_value)
	):
		last_error = (
			"The PPO transition tensors do not match loaded observation schema %d "
			+ "(actor %d/%d, critic %d/%d)."
		) % [
			observation_schema,
			actor_input.size(),
			expected_actor_count,
			critic_input.size(),
			expected_critic_count,
		]
		return false
	if not terminated:
		if next_critic_input.is_empty():
			next_critic_input = DronePPOObservationEncoder.encode_critic_for_schema(
				next_observation,
				observation_schema,
				behavior_actor_critic.body_feature_count
			)
		if (
			next_critic_input.size() != expected_critic_count
			or not DronePPOObservationEncoder.is_normalized_tensor(next_critic_input)
		):
			last_error = (
				"The PPO next-critic tensor does not match loaded observation schema %d "
				+ "(observed %d, expected %d)."
			) % [observation_schema, next_critic_input.size(), expected_critic_count]
			return false
	var sample_policy_revision: int = RLTrainingMath.finite_int_or(
		action_sample.get("policy_revision", -1),
		-1
	)
	# PPO is on-policy. A detached rollout may be optimized on another thread while the
	# visible drones continue flying under the frozen behavior policy, but those concurrent
	# decisions must not seed the next rollout. Retaining them used to force the next
	# optimizer job back to an older producer snapshot, creating two interleaved policy
	# lineages instead of cumulative updates.
	if update_in_progress:
		discarded_on_policy_transitions_since_update += 1
		environment_steps += 1
		return true
	if sample_policy_revision != behavior_policy_update:
		if sample_policy_revision < behavior_policy_update:
			# One held action can straddle the frame where a completed optimizer is adopted.
			# Count the environment step but do not learn from stale behavior data.
			discarded_on_policy_transitions_since_update += 1
			environment_steps += 1
			return true
		last_error = (
			"The PPO transition belongs to behavior policy %d, but policy %d is active."
			% [sample_policy_revision, behavior_policy_update]
		)
		return false
	if rollout.is_empty():
		rollout_policy_revision = sample_policy_revision
		# to_runtime_state() already owns fresh packed-array snapshots.
		rollout_start_network_state = behavior_actor_critic.to_runtime_state()
	elif rollout_policy_revision != sample_policy_revision:
		last_error = "The PPO rollout mixed multiple behavior-policy revisions."
		return false
	var next_value = 0.0
	if not terminated:
		next_value = (
			next_value_override
			if is_finite(next_value_override)
			else behavior_actor_critic.value_from_input(next_critic_input)
		)
	if not is_finite(next_value):
		last_error = "The PPO critic produced a non-finite bootstrap value."
		return false
	rollout.append({
		"worker_id": worker_id,
		# Encoders and samplers allocate these arrays for this decision and never mutate them
		# afterward. Transfer their references into the rollout instead of cloning four packed
		# arrays per worker and control step.
		"actor_input": actor_input,
		"critic_input": critic_input,
		"latent_action": latent_action,
		"commands": commands,
		"old_log_probability": old_log_probability,
		"old_value": old_value,
		"reward": reward,
		"next_value": next_value,
		"terminated": terminated,
		"truncated": truncated,
		"policy_revision": sample_policy_revision,
		"delta_seconds": safe_delta_seconds,
	})
	environment_steps += 1
	return true


func behavior_policy_revision() -> int:
	return behavior_policy_update


func can_update(force_partial_rollout = false) -> bool:
	if update_in_progress:
		return false
	var required = (
		int(config["minimum_update_transitions"])
		if force_partial_rollout
		else int(config["rollout_transitions"])
	)
	return rollout.size() >= maxi(required, 1)


func begin_update(force_partial_rollout = false) -> bool:
	last_error = ""
	if not can_update(force_partial_rollout):
		return false
	_consider_rollout_candidate(rollout)

	var detached_policy_revision = rollout_policy_revision
	var detached_network_state = rollout_start_network_state
	update_rollout = rollout
	rollout = []
	rollout_policy_revision = -1
	rollout_start_network_state = {}
	if detached_network_state.is_empty():
		last_error = "The PPO rollout has no producer-policy snapshot."
		_restore_detached_rollout(detached_policy_revision, detached_network_state)
		return false
	for transition in update_rollout:
		if int(transition.get("policy_revision", detached_policy_revision)) != detached_policy_revision:
			last_error = "The PPO optimizer received a mixed-policy rollout."
			_restore_detached_rollout(detached_policy_revision, detached_network_state)
			return false

	# A completed optimizer result may become the live behavior policy only after the old
	# rollout has been detached. Synchronize it before replacing the optimizer network with
	# the immutable producer snapshot used by this rollout.
	if policy_sync_pending:
		if not _sync_behavior_from_optimizer(true):
			last_error = "The optimized behavior policy could not be synchronized."
			_restore_detached_rollout(detached_policy_revision, detached_network_state)
			return false
		policy_sync_pending = false

	if not actor_critic.load_state(detached_network_state):
		last_error = "The PPO producer-policy snapshot is incompatible."
		_restore_detached_rollout(detached_policy_revision, detached_network_state)
		return false
	optimizer_policy_revision = detached_policy_revision
	var identity = _policy_divergence_metrics(update_rollout)
	update_initial_log_probability_error_max = float(identity.get("maximum_log_probability_error", INF))
	update_initial_approximate_kl = float(identity.get("approximate_kl", INF))
	update_initial_clip_fraction = float(identity.get("clip_fraction", 1.0))
	if (
		not is_finite(update_initial_log_probability_error_max)
		or update_initial_log_probability_error_max > INITIAL_LOG_PROBABILITY_TOLERANCE
	):
		last_error = (
			"The PPO rollout does not match producer policy revision %d "
			+ "(maximum log-probability error %.12f)."
		) % [detached_policy_revision, update_initial_log_probability_error_max]
		_restore_detached_rollout(detached_policy_revision, detached_network_state)
		return false

	update_prepared = _prepare_rollout(update_rollout)
	if update_prepared.is_empty():
		last_error = "The PPO rollout could not produce finite advantages."
		_restore_detached_rollout(detached_policy_revision, detached_network_state)
		return false
	update_feature_audit = last_metrics.get("feature_audit", {})
	if update_count == 0 or (update_count + 1) % FEATURE_AUDIT_UPDATE_INTERVAL == 0:
		var audit_rollout: Array[Dictionary] = []
		var audit_sample_count = mini(update_rollout.size(), FEATURE_AUDIT_MAXIMUM_SAMPLES)
		for audit_index in range(audit_sample_count):
			audit_rollout.append(update_rollout[audit_index])
		update_feature_audit = DronePPOFeatureAudit.analyze_rollout(
			audit_rollout,
			_actor_feature_names_for_body()
		)
	update_advantages = update_prepared["advantages"]
	update_returns = update_prepared["returns"]
	update_indices.clear()
	for index in range(update_rollout.size()):
		update_indices.append(index)

	update_metric_totals = _empty_metric_totals()
	update_metric_sample_count = 0
	update_optimizer_batches = 0
	update_completed_minibatches = 0
	update_early_stopped = false
	update_early_stop_reason = ""
	update_maximum_minibatch_kl = 0.0
	update_epoch = 0
	update_batch_start = 0
	update_batch_cursor = 0
	update_batch_end = 0
	update_batch_count = 0
	update_epoch_kl_total = 0.0
	update_epoch_sample_count = 0
	update_start_network_state = detached_network_state
	update_prepared["rollout_policy_revision"] = detached_policy_revision
	update_prepared["result_policy_revision"] = maxi(
		maxi(update_count + 1, optimizer_policy_revision + 1),
		behavior_policy_update + 1
	)
	_shuffle(update_indices)
	update_in_progress = true
	return true


func _restore_detached_rollout(
	policy_revision: int,
	network_state: Dictionary
) -> void:
	rollout = update_rollout
	update_rollout = []
	rollout_policy_revision = policy_revision
	rollout_start_network_state = network_state


func begin_background_update(force_partial_rollout = false) -> bool:
	last_error = ""
	if not can_update(force_partial_rollout):
		return false
	_consider_rollout_candidate(rollout)
	var detached_rollout: Array[Dictionary] = rollout
	var detached_policy_revision = rollout_policy_revision
	var detached_network_state = rollout_start_network_state
	if detached_network_state.is_empty():
		last_error = "The PPO rollout has no producer-policy snapshot."
		return false
	var job_config: Dictionary = config.duplicate(true)
	job_config["body_interface"] = body_interface_contract_data.duplicate(true)
	var payload = {
		"config": job_config,
		"random_seed": random_seed,
		"network_state": detached_network_state,
		"rollout": detached_rollout,
		"rollout_policy_revision": detached_policy_revision,
		"result_policy_revision": maxi(
			maxi(update_count + 1, optimizer_policy_revision + 1),
			behavior_policy_update + 1
		),
		"update_count": update_count,
		"environment_steps": environment_steps,
		"last_metrics": last_metrics.duplicate(true),
		"shuffle_rng_state": shuffle_rng.state,
		"force_partial": force_partial_rollout,
	}
	var next_job = DronePPOUpdateJob.new(payload)
	var next_thread = Thread.new()
	rollout = []
	rollout_policy_revision = -1
	rollout_start_network_state = {}
	var start_error = next_thread.start(Callable(next_job, "run"), Thread.PRIORITY_LOW)
	if start_error != OK:
		rollout = detached_rollout
		rollout_policy_revision = detached_policy_revision
		rollout_start_network_state = detached_network_state
		last_error = "Godot could not create the background PPO optimizer thread."
		return false

	background_job = next_job
	background_thread = next_thread
	background_result_discarded = false
	background_started_usec = Time.get_ticks_usec()
	update_in_progress = true

	if policy_sync_pending:
		if not _sync_behavior_from_optimizer(true):
			background_result_discarded = true
			last_error = "The optimized behavior policy could not be synchronized."
			return false
		policy_sync_pending = false
	return true


func poll_background_update() -> Dictionary:
	if background_thread == null or background_thread.is_alive():
		return {}
	var result_value: Variant = background_thread.wait_to_finish()
	background_thread = null
	background_job = null
	update_in_progress = false
	last_background_update_ms = maxf(
		float(Time.get_ticks_usec() - background_started_usec) / 1000.0,
		0.0
	)
	background_started_usec = 0
	var discard_result = background_result_discarded
	background_result_discarded = false
	if discard_result:
		return {}
	if not (result_value is Dictionary):
		last_error = "The background PPO optimizer returned no result."
		return {"error": last_error}
	var result: Dictionary = result_value
	if not bool(result.get("ok", false)):
		last_error = str(result.get(
			"error",
			"The background PPO optimizer failed."
		))
		return {"error": last_error}
	var network_value: Variant = result.get("network_state", {})
	if not (network_value is Dictionary) or not actor_critic.load_state(
		network_value as Dictionary
	):
		last_error = "The completed background PPO state was incompatible."
		return {"error": last_error}

	update_count = maxi(int(result.get("update_count", update_count + 1)), 0)
	optimizer_policy_revision = maxi(int(result.get(
		"optimizer_policy_revision",
		optimizer_policy_revision + 1
	)), 0)
	shuffle_rng.state = int(result.get("shuffle_rng_state", shuffle_rng.state))
	var metrics_value: Variant = result.get("metrics", {})
	last_metrics = (
		(metrics_value as Dictionary).duplicate(true)
		if metrics_value is Dictionary
		else {}
	)
	last_metrics["environment_steps"] = environment_steps
	last_metrics["optimizer_wall_time_ms"] = last_background_update_ms
	if not _sync_behavior_from_optimizer(true):
		last_error = "The completed PPO policy could not become the live behavior policy."
		return {"error": last_error}
	policy_sync_pending = false
	last_metrics["behavior_policy_revision"] = behavior_policy_update
	last_metrics["discarded_on_policy_transitions"] = (
		discarded_on_policy_transitions_since_update
	)
	discarded_on_policy_transitions_since_update = 0
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
	update_in_progress = false


func process_update(maximum_samples = -1) -> Dictionary:
	if not update_in_progress:
		return {}
	var allowed_samples = (
		maxi(int(config["optimizer_samples_per_frame"]), 1)
		if int(maximum_samples) < 0
		else maxi(int(maximum_samples), 1)
	)
	var processed_samples = 0
	while update_in_progress and processed_samples < allowed_samples:
		if update_batch_cursor >= update_batch_end:
			if update_batch_end > update_batch_start:
				_finish_current_minibatch()
				continue
			if update_batch_start >= update_indices.size():
				if _finish_epoch_or_update():
					break
				continue
			_begin_current_minibatch()
		var chunk_size = mini(
			allowed_samples - processed_samples,
			update_batch_end - update_batch_cursor
		)
		_process_current_minibatch_samples(chunk_size)
		processed_samples += chunk_size
		if update_batch_cursor >= update_batch_end:
			_finish_current_minibatch()
	if not update_in_progress:
		return last_metrics.duplicate(true)
	return {}


func update(force_partial_rollout = false) -> Dictionary:
	if not begin_update(force_partial_rollout):
		return {}
	while update_in_progress:
		process_update(1024)
	return last_metrics.duplicate(true)


func discard_incomplete_rollout() -> void:
	rollout.clear()
	rollout_policy_revision = -1
	rollout_start_network_state.clear()
	if background_thread != null:
		# Threads cannot be killed safely. The worker owns detached copies, so it can finish
		# without blocking the UI and its stale result will simply be ignored when joined.
		background_result_discarded = true
		policy_sync_pending = false
		return
	if update_in_progress:
		actor_critic.load_state(update_start_network_state)
	_clear_update_job()
	_sync_behavior_from_optimizer(true)
	policy_sync_pending = false


func record_completed_episode(mean_reward: float) -> void:
	completed_episodes += 1
	if mean_reward > best_episode_mean_reward:
		best_episode_mean_reward = mean_reward


func reset_episode_statistics() -> void:
	completed_episodes = 0
	discarded_on_policy_transitions_since_update = 0
	best_episode_mean_reward = -INF
	best_candidate_score = -INF
	best_candidate_group_mean_reward = -INF
	best_candidate_support_reward = -INF
	best_candidate_worker_reward = -INF
	best_candidate_robust_worker_reward = -INF
	best_candidate_policy_update = update_count
	best_candidate_environment_steps = environment_steps
	best_candidate_completed_episodes = completed_episodes
	best_candidate_worker_count = 0
	best_candidate_transition_count = 0
	best_network_state.clear()
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	promoted_training_summary.clear()
	best_evaluation.clear()
	best_evaluation_contract.clear()
	pending_promoted_candidate.clear()


func copy_policy_from(source: DroneTrainingAlgorithm) -> bool:
	var ppo_source = source as DronePPOTrainer
	if ppo_source == null:
		last_error = "No source PPO trainer was selected."
		return false
	if (
		actor_critic.action_count != ppo_source.actor_critic.action_count
		or actor_critic.body_feature_count != ppo_source.actor_critic.body_feature_count
		or actor_critic.body_interface_signature != ppo_source.actor_critic.body_interface_signature
	):
		last_error = "PPO policy body interface does not match this worker group's accepted hardware manifest."
		return false
	discard_incomplete_rollout()
	var source_state: Dictionary = ppo_source.stable_policy_state()
	if not actor_critic.load_state(source_state):
		last_error = "The selected PPO policy is incompatible."
		return false
	var behavior_rng_state = behavior_actor_critic.action_rng.state
	if not behavior_actor_critic.load_state(source_state):
		last_error = "The selected behavior policy could not be copied."
		return false
	behavior_actor_critic.action_rng.state = behavior_rng_state
	last_metrics = ppo_source.last_metrics.duplicate(true)
	update_count = ppo_source.update_count
	optimizer_policy_revision = ppo_source.optimizer_policy_revision
	environment_steps = ppo_source.environment_steps
	behavior_policy_update = optimizer_policy_revision
	reset_episode_statistics()
	last_error = ""
	return true


func perturb_policy(relative_strength: float, perturbation_seed: int) -> bool:
	last_error = ""
	discard_incomplete_rollout()
	var strength = clampf(relative_strength, 0.0, 0.5)
	if strength <= 0.0:
		return true
	if not actor_critic.perturb_weights(strength, perturbation_seed):
		last_error = "The PPO weight variation produced an invalid network."
		return false
	optimizer_policy_revision += 1
	if not behavior_actor_critic.load_state(actor_critic.to_runtime_state()):
		last_error = "The varied PPO policy could not be synchronized."
		return false
	behavior_policy_update = optimizer_policy_revision
	reset_episode_statistics()
	last_metrics.clear()
	rollout.clear()
	policy_sync_pending = false
	return true


func stable_policy_state() -> Dictionary:
	return behavior_actor_critic.to_state().duplicate(true)


func update_progress() -> float:
	if background_thread != null:
		return 0.0
	if not update_in_progress or update_indices.is_empty():
		return 0.0
	var total_work = (
		maxi(int(config["update_epochs"]), 1) * update_indices.size()
	)
	var current_position = (
		update_batch_cursor if update_batch_end > 0 else update_batch_start
	)
	var completed_work = update_epoch * update_indices.size() + current_position
	return clampf(float(completed_work) / float(maxi(total_work, 1)), 0.0, 1.0)


func status_text(is_training: bool) -> String:
	var phase = "paused"
	if background_thread != null:
		phase = "learning in background"
	elif update_in_progress:
		phase = "learning %d%%" % roundi(update_progress() * 100.0)
	elif is_training:
		phase = "collecting flight decisions %d/%d" % [
			rollout.size(),
			int(config["rollout_transitions"]),
		]
	var best_text = (
		"%+.3f/s" % best_candidate_score
		if is_finite(best_candidate_score)
		else "—"
	)
	return "%s · learning round %d · decisions %d · candidate gate %s" % [
		phase,
		update_count,
		environment_steps,
		best_text,
	]


func diagnostic_status_text() -> String:
	return DronePPOFeatureAudit.status_text(last_metrics.get("feature_audit", {}))


func to_checkpoint() -> Dictionary:
	return _checkpoint_with_network(stable_policy_state())


func to_best_checkpoint() -> Dictionary:
	if not has_best_checkpoint():
		return {}
	var checkpoint = _checkpoint_with_network(best_network_state, true)
	_apply_training_context_to_checkpoint(checkpoint, promoted_training_summary)
	return checkpoint


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
	var summary = promoted_training_summary.duplicate(true)
	if summary.is_empty():
		summary = {
			"selection_score": best_candidate_score if is_finite(best_candidate_score) else 0.0,
			"selection_method": "legacy_training_candidate_unverified",
			"exact_policy_match": true,
			"evaluation_verified": false,
		}
	else:
		summary["training_selection_score"] = RLTrainingMath.finite_float_or(
		summary.get("selection_score", 0.0), 0.0
	)
		summary["selection_score"] = RLTrainingMath.finite_float_or(
			best_evaluation.get("selection_score", summary.get("selection_score", 0.0)),
			RLTrainingMath.finite_float_or(summary.get("selection_score", 0.0), 0.0)
		)
		summary["selection_method"] = "deterministic_fixed_seed_suite_v2"
		summary["exact_policy_match"] = true
		summary["evaluation_verified"] = not best_evaluation.is_empty()
		summary["evaluation"] = best_evaluation.duplicate(true)
	return summary


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
	return RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1)


func discard_pending_evaluation_candidate(candidate_id: int) -> bool:
	if RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1) != candidate_id:
		return false
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	best_candidate_score = -INF
	return true


func record_deterministic_evaluation(
	candidate_id: int,
	evaluation_summary: Dictionary
) -> Dictionary:
	if RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1) != candidate_id:
		return {"promoted": false, "reason": "candidate_id_mismatch"}
	if candidate_network_state.is_empty():
		return {"promoted": false, "reason": "missing_candidate_network"}
	var expected_hash = str(pending_candidate.get("candidate_hash", ""))
	if (
		expected_hash.is_empty()
		or expected_hash != RLDeterministicEvaluator.candidate_hash(candidate_network_state)
	):
		return {"promoted": false, "reason": "candidate_network_hash_mismatch"}
	var evaluation_plan: Dictionary = pending_candidate.get("evaluation_plan", {})
	var validation = RLDeterministicEvaluationSuite.validate_summary_for_plan(
		evaluation_plan,
		evaluation_summary,
		expected_hash
	)
	if not bool(validation.get("valid", false)):
		return {
			"promoted": false,
			"reason": str(validation.get("reason", "invalid_evaluation_summary")),
		}
	var decision = RLDeterministicEvaluator.promotion_decision(
		evaluation_summary,
		best_evaluation
	)
	var promoted = bool(decision.get("promote", false))
	if promoted:
		best_network_state = candidate_network_state.duplicate(true)
		promoted_training_summary = candidate_training_summary.duplicate(true)
		best_evaluation = evaluation_summary.duplicate(true)
		best_evaluation_contract = (pending_candidate.get("evaluation_contract", {}) as Dictionary).duplicate(true)
		best_evaluation["candidate_hash"] = expected_hash
		pending_promoted_candidate = best_selection_summary()
		pending_promoted_candidate["candidate_id"] = candidate_id
		pending_promoted_candidate["candidate_hash"] = expected_hash
	var result = {
		"promoted": promoted,
		"reason": str(decision.get("reason", "unknown")),
		"candidate_id": candidate_id,
	}
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	# A rejected rollout score must not permanently block a lower-scoring but safer candidate.
	if not promoted:
		best_candidate_score = -INF
	return result


func record_deterministic_evaluation_records(
	candidate_id: int,
	records: Array[Dictionary]
) -> Dictionary:
	if RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1) != candidate_id:
		return {"promoted": false, "reason": "candidate_id_mismatch"}
	var plan: Dictionary = pending_candidate.get("evaluation_plan", {})
	var candidate_hash = str(pending_candidate.get("candidate_hash", ""))
	var summary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		records,
		candidate_hash
	)
	if summary.is_empty():
		return {"promoted": false, "reason": "invalid_evaluation_records"}
	return record_deterministic_evaluation(candidate_id, summary)


func record_best_deterministic_evaluation_records(
	evaluation_plan: Dictionary,
	records: Array[Dictionary]
) -> Dictionary:
	if best_network_state.is_empty():
		return {"recorded": false, "reason": "missing_best_network"}
	var best_hash: String = RLDeterministicEvaluator.candidate_hash(best_network_state)
	var summary: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		evaluation_plan,
		records,
		best_hash
	)
	if summary.is_empty():
		return {"recorded": false, "reason": "invalid_best_evaluation_records"}
	var validation: Dictionary = RLDeterministicEvaluationSuite.validate_summary_for_plan(
		evaluation_plan,
		summary,
		best_hash
	)
	if not bool(validation.get("valid", false)):
		return {
			"recorded": false,
			"reason": str(validation.get("reason", "invalid_best_evaluation")),
		}
	best_evaluation = summary.duplicate(true)
	best_evaluation["candidate_hash"] = best_hash
	# Best is commonly re-evaluated because a frozen pending Candidate introduced a new
	# environment contract. The live group may change again while that hidden suite is queued,
	# so provenance must come from the exact frozen contract whose hash appears in the plan.
	var plan_contract_hash: String = str(evaluation_plan.get("evaluation_contract_hash", ""))
	var pending_contract: Dictionary = pending_candidate.get("evaluation_contract", {})
	if (
		RLEvaluationContract.is_valid(pending_contract)
		and str(pending_contract.get("contract_hash", "")) == plan_contract_hash
	):
		best_evaluation_contract = pending_contract.duplicate(true)
	elif (
		RLEvaluationContract.is_valid(evaluation_contract_template)
		and str(evaluation_contract_template.get("contract_hash", "")) == plan_contract_hash
	):
		best_evaluation_contract = evaluation_contract_template.duplicate(true)
	else:
		best_evaluation_contract.clear()
	return {
		"recorded": true,
		"reason": "best_re_evaluated",
		"evaluation_contract_hash": str(summary.get("evaluation_contract_hash", "")),
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


func load_checkpoint(checkpoint: Dictionary) -> bool:
	last_error = ""
	var network_value: Variant = checkpoint.get("network", {})
	var config_value: Variant = checkpoint.get("config", {})
	var training_value: Variant = checkpoint.get("training", {})
	if (
		not (network_value is Dictionary)
		or not (config_value is Dictionary)
		or not (training_value is Dictionary)
	):
		last_error = "The PPO checkpoint has malformed network, config, or training state."
		return false
	var network: Dictionary = network_value
	var stored_config: Dictionary = config_value
	var training: Dictionary = training_value
	if (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1) != CHECKPOINT_SCHEMA_VERSION
		or str(checkpoint.get("algorithm", "")) != ALGORITHM_NAME
		or RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), -1) < 0
		or RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), -1) > DronePPOObservationEncoder.QUAD_PROPELLER_COUNT
		or not DronePPOObservationEncoder.is_trainable_schema(
			RLTrainingMath.finite_int_or(network.get("observation_schema_version", 0), -1)
		)
	):
		last_error = "The checkpoint schema or drone-body topology is incompatible."
		return false
	var staged_actor_critic: DronePPOActorCritic = DronePPOActorCritic.new()
	var staged_behavior_actor_critic: DronePPOActorCritic = DronePPOActorCritic.new()
	if not staged_actor_critic.load_state(network):
		last_error = "The checkpoint actor-critic network is incompatible."
		return false
	var checkpoint_body_value: Variant = checkpoint.get("body_interface", {})
	if not (
		checkpoint_body_value is Dictionary
		and _body_contract_matches_network(checkpoint_body_value as Dictionary, staged_actor_critic)
	):
		last_error = "The checkpoint body-interface manifest is missing or inconsistent with its network."
		return false
	if RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), -1) != _body_propeller_control_count(checkpoint_body_value as Dictionary):
		last_error = "The checkpoint propeller topology does not match its body-interface manifest."
		return false
	if (
		body_interface_locked
		and staged_actor_critic.body_interface_signature != body_interface_signature
	):
		last_error = "The checkpoint was finalized for a different body attachment manifest."
		return false
	if not staged_behavior_actor_critic.load_state(staged_actor_critic.to_runtime_state()):
		last_error = "The checkpoint behavior policy is incompatible."
		return false
	# Only a fully validated checkpoint is allowed to interrupt the current trainer. Otherwise
	# a typo/corrupt file would unnecessarily destroy an active rollout or optimizer job.
	shutdown_background_update()
	discard_incomplete_rollout()
	for key in stored_config:
		if config.has(key):
			config[key] = stored_config[key]
	_sanitize_config()
	config["hidden_layer_width"] = staged_actor_critic.hidden_size
	config["hidden_layer_depth"] = staged_actor_critic.hidden_layer_count
	config["action_count"] = staged_actor_critic.action_count
	body_feature_count = staged_actor_critic.body_feature_count
	body_interface_signature = staged_actor_critic.body_interface_signature
	body_control_descriptors = staged_actor_critic.control_descriptors.duplicate(true)
	body_interface_contract_data = (checkpoint_body_value as Dictionary).duplicate(true)
	body_interface_locked = true
	initialization_valid = true
	actor_critic = staged_actor_critic
	behavior_actor_critic = staged_behavior_actor_critic
	update_count = maxi(RLTrainingMath.finite_int_or(training.get("update_count", 0), 0), 0)
	optimizer_policy_revision = maxi(RLTrainingMath.finite_int_or(
		training.get("optimizer_policy_revision", update_count), update_count
	), 0)
	behavior_policy_update = maxi(RLTrainingMath.finite_int_or(
		training.get("behavior_policy_revision", optimizer_policy_revision),
		optimizer_policy_revision
	), 0)
	environment_steps = maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	completed_episodes = maxi(RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0), 0)
	var has_best_episode: bool = RLTrainingMath.bool_or(training.get("has_best_episode", false), false)
	best_episode_mean_reward = (
		RLTrainingMath.finite_float_or(training.get("best_episode_mean_reward"), -INF)
		if has_best_episode
		else -INF
	)
	best_network_state = {}
	var loaded_best: Variant = training.get("best_network_state", {})
	if has_best_episode and loaded_best is Dictionary and not (loaded_best as Dictionary).is_empty():
		var migrated_best = DronePPOActorCritic.new()
		if migrated_best.load_state(loaded_best as Dictionary):
			best_network_state = migrated_best.to_runtime_state()
	var candidate_value: Variant = training.get("best_candidate", {})
	var candidate: Dictionary = (
		(candidate_value as Dictionary).duplicate(true)
		if candidate_value is Dictionary
		else {}
	)
	var candidate_is_exact: bool = RLTrainingMath.bool_or(candidate.get("exact_policy_match", false), false)
	if candidate_is_exact and best_network_state.is_empty():
		var candidate_best: Variant = training.get("best_network_state", {})
		if candidate_best is Dictionary and not (candidate_best as Dictionary).is_empty():
			var migrated_candidate = DronePPOActorCritic.new()
			if migrated_candidate.load_state(candidate_best as Dictionary):
				best_network_state = migrated_candidate.to_runtime_state()
	best_candidate_score = (
		RLTrainingMath.finite_float_or(candidate.get("selection_score", -INF), -INF)
		if candidate_is_exact
		else -INF
	)
	best_candidate_group_mean_reward = RLTrainingMath.finite_float_or(
		candidate.get("group_mean_reward_per_second"),
		-INF
	)
	best_candidate_support_reward = RLTrainingMath.finite_float_or(
		candidate.get("support_reward_per_second"),
		best_candidate_group_mean_reward
	)
	best_candidate_worker_reward = RLTrainingMath.finite_float_or(
		candidate.get("best_worker_reward_per_second"),
		-INF
	)
	best_candidate_robust_worker_reward = RLTrainingMath.finite_float_or(
		candidate.get("robust_best_worker_reward_per_second"),
		-INF
	)
	best_candidate_policy_update = RLTrainingMath.finite_int_or(candidate.get("policy_update", update_count), update_count)
	best_candidate_environment_steps = maxi(RLTrainingMath.finite_int_or(
		candidate.get("environment_steps", environment_steps), environment_steps
	), 0)
	best_candidate_completed_episodes = maxi(RLTrainingMath.finite_int_or(
		candidate.get("completed_episodes", completed_episodes), completed_episodes
	), 0)
	best_candidate_worker_count = maxi(RLTrainingMath.finite_int_or(candidate.get("worker_count", 0), 0), 0)
	best_candidate_transition_count = maxi(RLTrainingMath.finite_int_or(candidate.get("transition_count", 0), 0), 0)
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
		var migrated_pending_candidate: DronePPOActorCritic = DronePPOActorCritic.new()
		if migrated_pending_candidate.load_state(loaded_candidate_network as Dictionary):
			candidate_network_state = migrated_pending_candidate.to_state()
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
	if not pending_candidate.is_empty():
		var pending_contract_value: Variant = pending_candidate.get("evaluation_contract", {})
		var pending_plan_value: Variant = pending_candidate.get("evaluation_plan", {})
		var pending_contract: Dictionary = (
			(pending_contract_value as Dictionary) if pending_contract_value is Dictionary else {}
		)
		var pending_plan: Dictionary = (
			(pending_plan_value as Dictionary) if pending_plan_value is Dictionary else {}
		)
		var pending_contract_valid: bool = (
			RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1) >= 0
			and not candidate_network_state.is_empty()
			and not str(pending_candidate.get("candidate_hash", "")).is_empty()
			and str(pending_candidate.get("candidate_hash", ""))
				== RLDeterministicEvaluator.candidate_hash(candidate_network_state)
			and RLEvaluationContract.is_valid(pending_contract, "drone")
			and str(pending_candidate.get("evaluation_contract_hash", ""))
				== str(pending_contract.get("contract_hash", ""))
			and str(pending_plan.get("evaluation_contract_hash", ""))
				== str(pending_contract.get("contract_hash", ""))
			and RLDeterministicEvaluationSuite.is_valid_plan(pending_plan, "drone")
		)
		if not pending_contract_valid:
			pending_candidate.clear()
			candidate_network_state.clear()
			candidate_training_summary.clear()
			best_candidate_score = -INF
			best_candidate_group_mean_reward = -INF
			best_candidate_support_reward = -INF
			best_candidate_worker_reward = -INF
			best_candidate_robust_worker_reward = -INF

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
	random_seed = RLTrainingMath.finite_int_or(training.get("random_seed", random_seed), random_seed)
	shuffle_rng.state = RLTrainingMath.finite_int_or(training.get("shuffle_rng_state", shuffle_rng.state), shuffle_rng.state)
	rollout.clear()
	discarded_on_policy_transitions_since_update = 0
	if background_thread == null:
		_clear_update_job()
	policy_sync_pending = false
	return actor_critic.is_finite_state() and behavior_actor_critic.is_finite_state()


func _begin_current_minibatch() -> void:
	update_batch_end = mini(
		update_batch_start + maxi(int(config["minibatch_size"]), 1),
		update_indices.size()
	)
	update_batch_cursor = update_batch_start
	update_batch_count = update_batch_end - update_batch_start
	actor_critic.clear_actor_gradients()
	actor_critic.clear_critic_gradients()


func _process_current_minibatch_samples(sample_count: int) -> void:
	var chunk_end = mini(update_batch_cursor + sample_count, update_batch_end)
	for shuffled_position in range(update_batch_cursor, chunk_end):
		var sample_index = update_indices[shuffled_position]
		var transition: Dictionary = update_rollout[sample_index]
		var actor_metrics: Dictionary = actor_critic.accumulate_actor_gradient(
			transition["actor_input"],
			transition["latent_action"],
			float(transition["old_log_probability"]),
			update_advantages[sample_index],
			float(config["clip_range"]),
			float(config["entropy_coefficient"])
		)
		var critic_metrics: Dictionary = actor_critic.accumulate_critic_gradient(
			transition["critic_input"],
			update_returns[sample_index],
			float(config["value_coefficient"])
		)
		if actor_metrics.is_empty() or critic_metrics.is_empty():
			continue
		for key in [
			"actor_loss", "entropy", "approximate_kl", "clip_fraction",
		]:
			update_metric_totals[key] += float(actor_metrics[key])
		update_metric_totals["value_loss"] += float(critic_metrics["value_loss"])
		update_epoch_kl_total += float(actor_metrics["approximate_kl"])
		update_epoch_sample_count += 1
		update_metric_sample_count += 1
	update_batch_cursor = chunk_end


func _finish_current_minibatch() -> void:
	update_metric_totals["actor_gradient_norm"] += (
		actor_critic.apply_actor_gradients(
			float(config["learning_rate"]),
			update_batch_count,
			float(config["maximum_gradient_norm"])
		)
	)
	update_metric_totals["critic_gradient_norm"] += (
		actor_critic.apply_critic_gradients(
			float(config["learning_rate"]),
			update_batch_count,
			float(config["maximum_gradient_norm"])
		)
	)
	update_optimizer_batches += 1
	update_completed_minibatches += 1
	var divergence = _policy_divergence_metrics(update_rollout)
	var post_minibatch_kl = float(divergence.get("approximate_kl", INF))
	if is_finite(post_minibatch_kl):
		update_maximum_minibatch_kl = maxf(update_maximum_minibatch_kl, post_minibatch_kl)
	update_batch_start = update_batch_end
	update_batch_cursor = 0
	update_batch_end = 0
	update_batch_count = 0
	if (
		float(config["target_kl"]) > 0.0
		and is_finite(post_minibatch_kl)
		and post_minibatch_kl > float(config["target_kl"]) * PPO_KL_STOP_MULTIPLIER
	):
		update_early_stopped = true
		update_early_stop_reason = "target_kl"
		_finalize_update()


func _finish_epoch_or_update() -> bool:
	if (
		update_epoch_sample_count > 0
		and update_epoch_kl_total / float(update_epoch_sample_count)
		> float(config["target_kl"]) * 1.5
	):
		update_early_stopped = true
		update_early_stop_reason = "target_kl_epoch"
		_finalize_update()
		return true
	update_epoch += 1
	if update_epoch >= maxi(int(config["update_epochs"]), 1):
		_finalize_update()
		return true
	_shuffle(update_indices)
	update_batch_start = 0
	update_batch_cursor = 0
	update_batch_end = 0
	update_batch_count = 0
	update_epoch_kl_total = 0.0
	update_epoch_sample_count = 0
	return false


func _finalize_update() -> void:
	update_count += 1
	optimizer_policy_revision = maxi(int(update_prepared.get(
		"result_policy_revision",
		update_count
	)), update_count)
	var transition_count = update_rollout.size()
	var exploration = actor_critic.exploration_statistics()
	var command_diagnostics = RLTrainingMath.bounded_command_diagnostics(
		update_rollout,
		0.0,
		1.0
	)
	last_metrics = {
		"algorithm": ALGORITHM_NAME,
		"update": update_count,
		"environment_steps": environment_steps,
		"rollout_transitions": transition_count,
		"actor_loss": _safe_average(
			float(update_metric_totals["actor_loss"]), update_metric_sample_count
		),
		"value_loss": _safe_average(
			float(update_metric_totals["value_loss"]), update_metric_sample_count
		),
		"entropy": _safe_average(
			float(update_metric_totals["entropy"]), update_metric_sample_count
		),
		"approximate_kl": _safe_average(
			float(update_metric_totals["approximate_kl"]), update_metric_sample_count
		),
		"clip_fraction": _safe_average(
			float(update_metric_totals["clip_fraction"]), update_metric_sample_count
		),
		"actor_gradient_norm": _safe_average(
			float(update_metric_totals["actor_gradient_norm"]),
			update_optimizer_batches
		),
		"critic_gradient_norm": _safe_average(
			float(update_metric_totals["critic_gradient_norm"]),
			update_optimizer_batches
		),
		"advantage_mean_before_normalization": update_prepared["advantage_mean"],
		"advantage_standard_deviation": update_prepared[
			"advantage_standard_deviation"
		],
		"return_statistics": update_prepared.get("return_statistics", {}).duplicate(true),
		"value_prediction_statistics": update_prepared.get("value_prediction_statistics", {}).duplicate(true),
		"explained_variance": float(update_prepared.get("explained_variance", 0.0)),
		"feature_audit": update_feature_audit,
		"rollout_policy_revision": int(update_prepared.get("rollout_policy_revision", -1)),
		"optimizer_policy_revision": optimizer_policy_revision,
		"initial_log_probability_error_max": update_initial_log_probability_error_max,
		"initial_approximate_kl": update_initial_approximate_kl,
		"initial_clip_fraction": update_initial_clip_fraction,
		"maximum_minibatch_kl": update_maximum_minibatch_kl,
		"completed_minibatches": update_completed_minibatches,
		"completed_epochs": update_epoch + 1,
		"early_stopped_for_kl": update_early_stopped,
		"early_stop_reason": update_early_stop_reason,
		"action_standard_deviation_mean": float(exploration.get("mean", 0.0)),
		"action_standard_deviation_minimum": float(exploration.get("minimum", 0.0)),
		"action_standard_deviation_maximum": float(exploration.get("maximum", 0.0)),
		"command_diagnostics": command_diagnostics,
		"discount_reference_interval_seconds": float(config.get("discount_reference_interval_seconds", 0.05)),
		"effective_gamma": RLTrainingMath.discount_for_delta(
			float(config["discount_factor"]),
			float(config.get("control_interval_seconds", 0.05)),
			float(config.get("discount_reference_interval_seconds", 0.05))
		),
		"discount_half_life_seconds": RLTrainingMath.half_life_seconds(
			float(config["discount_factor"]),
			float(config.get("discount_reference_interval_seconds", 0.05))
		),
		"gae_lambda_time_semantics": "real_time_reference_interval",
	}
	if not _sync_behavior_from_optimizer(true):
		last_error = "The optimized PPO policy could not become the live behavior policy."
		policy_sync_pending = true
	else:
		policy_sync_pending = false
		last_metrics["behavior_policy_revision"] = behavior_policy_update
		last_metrics["discarded_on_policy_transitions"] = (
			discarded_on_policy_transitions_since_update
		)
		discarded_on_policy_transitions_since_update = 0
	_clear_update_job()


func _clear_update_job() -> void:
	update_in_progress = false
	update_rollout.clear()
	update_advantages = PackedFloat64Array()
	update_returns = PackedFloat64Array()
	update_indices.clear()
	update_epoch = 0
	update_batch_start = 0
	update_batch_cursor = 0
	update_batch_end = 0
	update_batch_count = 0
	update_epoch_kl_total = 0.0
	update_epoch_sample_count = 0
	update_metric_totals.clear()
	update_metric_sample_count = 0
	update_optimizer_batches = 0
	update_completed_minibatches = 0
	update_early_stopped = false
	update_early_stop_reason = ""
	update_initial_log_probability_error_max = 0.0
	update_initial_approximate_kl = 0.0
	update_initial_clip_fraction = 0.0
	update_maximum_minibatch_kl = 0.0
	update_prepared.clear()
	update_feature_audit.clear()
	update_start_network_state.clear()


func _checkpoint_with_network(
	network_state: Dictionary,
	use_best_candidate_counters = false
) -> Dictionary:
	var checkpoint_update = (
		best_candidate_policy_update if bool(use_best_candidate_counters) else update_count
	)
	var checkpoint_steps = (
		best_candidate_environment_steps
		if bool(use_best_candidate_counters)
		else environment_steps
	)
	var checkpoint_episodes = (
		best_candidate_completed_episodes
		if bool(use_best_candidate_counters)
		else completed_episodes
	)
	return {
		"schema_version": CHECKPOINT_SCHEMA_VERSION,
		"algorithm": ALGORITHM_NAME,
		"training_algorithm_id": TRAINING_ALGORITHM_ID,
		"propeller_count": _body_propeller_control_count(body_interface_contract_data),
		"body_interface": body_interface_contract_data.duplicate(true),
		"config": config.duplicate(true),
		"discount_time_base": {
			"discount_key": "discount_factor",
			"reference_interval_seconds": float(config.get("discount_reference_interval_seconds", 0.05)),
			"lambda_semantics": "real_time_reference_interval",
		},
		"network": network_state.duplicate(true),
		"training": {
			"update_count": checkpoint_update,
			"optimizer_policy_revision": optimizer_policy_revision,
			"behavior_policy_revision": behavior_policy_update,
			"environment_steps": checkpoint_steps,
			"completed_episodes": checkpoint_episodes,
			"best_episode_mean_reward": (
				best_episode_mean_reward
				if is_finite(best_episode_mean_reward)
				else 0.0
			),
			"has_best_episode": is_finite(best_episode_mean_reward),
			"has_exact_best_policy": has_best_checkpoint(),
			"best_network_state": best_network_state.duplicate(true),
			"best_candidate": best_selection_summary(),
			"best_evaluation": best_evaluation.duplicate(true),
			"best_evaluation_contract": best_evaluation_contract.duplicate(true),
			"promoted_training_summary": promoted_training_summary.duplicate(true),
			"pending_evaluation_candidate": pending_candidate.duplicate(true),
			"candidate_network_state": candidate_network_state.duplicate(true),
			"candidate_training_summary": candidate_training_summary.duplicate(true),
			"candidate_sequence": candidate_sequence,
			"last_metrics": (
				{}
				if bool(use_best_candidate_counters)
				else last_metrics.duplicate(true)
			),
			"random_seed": random_seed,
			"shuffle_rng_state": shuffle_rng.state,
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


func _sync_behavior_from_optimizer(preserve_rng_state: bool) -> bool:
	var behavior_rng_state = behavior_actor_critic.action_rng.state
	if not behavior_actor_critic.copy_from(actor_critic):
		return false
	if preserve_rng_state:
		behavior_actor_critic.action_rng.state = behavior_rng_state
	behavior_policy_update = optimizer_policy_revision
	return true


func _consider_rollout_candidate(source_rollout: Array[Dictionary]) -> void:
	# A frozen candidate must remain byte-for-byte stable while the room evaluates it.
	# Keep training/optimizing, but do not replace the candidate out from under the fixed-seed suite.
	if not pending_candidate.is_empty():
		return
	if source_rollout.is_empty():
		return
	if not RLEvaluationContract.is_valid(evaluation_contract_template, "drone"):
		return
	var buckets: Dictionary = {}
	for transition in source_rollout:
		var worker_id = int(transition.get("worker_id", -1))
		if worker_id < 0:
			continue
		if not buckets.has(worker_id):
			buckets[worker_id] = {"reward": 0.0, "seconds": 0.0, "count": 0}
		var bucket: Dictionary = buckets[worker_id]
		bucket["reward"] = float(bucket["reward"]) + float(
			transition.get("reward", 0.0)
		)
		bucket["seconds"] = float(bucket["seconds"]) + float(transition.get(
			"delta_seconds",
			config.get("control_interval_seconds", 0.05)
		))
		bucket["count"] = int(bucket["count"]) + 1

	var worker_scores: Array[float] = []
	var included_transitions = 0
	for worker_id in buckets:
		var bucket: Dictionary = buckets[worker_id]
		var count = int(bucket.get("count", 0))
		if count < MINIMUM_CANDIDATE_TRANSITIONS_PER_WORKER:
			continue
		var elapsed_seconds = float(bucket.get("seconds", 0.0))
		if not is_finite(elapsed_seconds) or elapsed_seconds <= 0.0:
			continue
		var score = float(bucket.get("reward", 0.0)) / elapsed_seconds
		if is_finite(score):
			worker_scores.append(score)
			included_transitions += count
	if worker_scores.is_empty():
		return
	worker_scores.sort()
	var group_mean = 0.0
	for score in worker_scores:
		group_mean += score
	group_mean /= float(worker_scores.size())
	var best_worker = worker_scores[worker_scores.size() - 1]
	var first_quartile = _percentile(worker_scores, 0.25)
	var third_quartile = _percentile(worker_scores, 0.75)
	var outlier_fence = third_quartile + OUTLIER_FENCE_MULTIPLIER * maxf(
		third_quartile - first_quartile,
		0.0
	)
	var robust_best = minf(best_worker, outlier_fence)
	var support_score = _interquartile_mean(worker_scores)
	var selection_score = (
		ELITE_SELECTION_WEIGHT * robust_best
		+ (1.0 - ELITE_SELECTION_WEIGHT) * support_score
	)
	if not is_finite(selection_score) or selection_score <= best_candidate_score:
		return

	best_candidate_score = selection_score
	best_candidate_group_mean_reward = group_mean
	best_candidate_support_reward = support_score
	best_candidate_worker_reward = best_worker
	best_candidate_robust_worker_reward = robust_best
	best_candidate_policy_update = behavior_policy_update
	best_candidate_environment_steps = environment_steps
	best_candidate_completed_episodes = completed_episodes
	best_candidate_worker_count = worker_scores.size()
	best_candidate_transition_count = included_transitions
	candidate_network_state = behavior_actor_critic.to_state()
	candidate_training_summary = {
		"selection_score": best_candidate_score,
		"group_mean_reward_per_second": best_candidate_group_mean_reward,
		"support_reward_per_second": best_candidate_support_reward,
		"best_worker_reward_per_second": best_candidate_worker_reward,
		"robust_best_worker_reward_per_second": best_candidate_robust_worker_reward,
		"elite_weight": ELITE_SELECTION_WEIGHT,
		"policy_update": best_candidate_policy_update,
		"environment_steps": best_candidate_environment_steps,
		"completed_episodes": best_candidate_completed_episodes,
		"worker_count": best_candidate_worker_count,
		"transition_count": best_candidate_transition_count,
		"exact_policy_match": true,
		"selection_method": "robust_elite_rollout_candidate_v2",
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


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var position = clampf(fraction, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lower_index = floori(position)
	var upper_index = ceili(position)
	if lower_index == upper_index:
		return sorted_values[lower_index]
	return lerpf(
		sorted_values[lower_index],
		sorted_values[upper_index],
		position - float(lower_index)
	)


func _interquartile_mean(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	if sorted_values.size() < 4:
		var small_total = 0.0
		for value in sorted_values:
			small_total += value
		return small_total / float(sorted_values.size())
	var trim_count = floori(float(sorted_values.size()) * 0.25)
	var first_index = clampi(trim_count, 0, sorted_values.size() - 1)
	var end_index = clampi(
		sorted_values.size() - trim_count,
		first_index + 1,
		sorted_values.size()
	)
	var total = 0.0
	for index in range(first_index, end_index):
		total += sorted_values[index]
	return total / float(end_index - first_index)


func _policy_divergence_metrics(
	source_rollout: Array[Dictionary],
	maximum_samples: int = 64
) -> Dictionary:
	if source_rollout.is_empty():
		return {
			"maximum_log_probability_error": INF,
			"approximate_kl": INF,
			"clip_fraction": 1.0,
		}
	var count = mini(source_rollout.size(), maxi(maximum_samples, 1))
	var maximum_error = 0.0
	var kl_total = 0.0
	var clipped_count = 0
	for index in range(count):
		var transition: Dictionary = source_rollout[index]
		var current_log_probability = actor_critic.log_probability_from_input(
			transition.get("actor_input", PackedFloat64Array()),
			transition.get("latent_action", PackedFloat64Array())
		)
		var old_log_probability = float(transition.get("old_log_probability", NAN))
		if not is_finite(current_log_probability) or not is_finite(old_log_probability):
			return {
				"maximum_log_probability_error": INF,
				"approximate_kl": INF,
				"clip_fraction": 1.0,
			}
		var error = absf(current_log_probability - old_log_probability)
		maximum_error = maxf(maximum_error, error)
		kl_total += old_log_probability - current_log_probability
		var ratio = exp(clampf(current_log_probability - old_log_probability, -20.0, 20.0))
		if absf(ratio - 1.0) > float(config["clip_range"]):
			clipped_count += 1
	return {
		"maximum_log_probability_error": maximum_error,
		"approximate_kl": kl_total / float(count),
		"clip_fraction": float(clipped_count) / float(count),
	}


func _prepare_rollout(source_rollout: Array[Dictionary]) -> Dictionary:
	var advantages = PackedFloat64Array()
	var returns = PackedFloat64Array()
	var value_predictions = PackedFloat64Array()
	advantages.resize(source_rollout.size())
	returns.resize(source_rollout.size())
	value_predictions.resize(source_rollout.size())
	var discount_reference = float(config["discount_factor"])
	var discount_reference_interval = float(config.get(
		"discount_reference_interval_seconds",
		config.get("control_interval_seconds", 0.05)
	))
	var gae_lambda = float(config["gae_lambda"])
	# Rollouts are interleaved across workers. One reverse scan keeps only the next GAE
	# value per worker, avoiding a temporary index Array for every drone at update start.
	var next_advantage_by_worker: Dictionary = {}
	for transition_index in range(source_rollout.size() - 1, -1, -1):
		var transition: Dictionary = source_rollout[transition_index]
		var worker_id = int(transition["worker_id"])
		var terminated = bool(transition["terminated"])
		var truncated = bool(transition["truncated"])
		var bootstrap_mask = 0.0 if terminated else 1.0
		var gamma_delta = RLTrainingMath.discount_for_delta(
			discount_reference,
			float(transition.get("delta_seconds", config.get("control_interval_seconds", 0.05))),
			discount_reference_interval
		)
		var lambda_delta = RLTrainingMath.discount_for_delta(
			gae_lambda,
			float(transition.get("delta_seconds", config.get("control_interval_seconds", 0.05))),
			discount_reference_interval
		)
		var delta = (
			float(transition["reward"])
			+ gamma_delta * float(transition["next_value"]) * bootstrap_mask
			- float(transition["old_value"])
		)
		var advantage = delta
		if (
			not terminated
			and not truncated
			and next_advantage_by_worker.has(worker_id)
		):
			# Gamma and the GAE trace decay use the same real-time reference interval, so
			# changing a group's control rate does not silently change the estimator horizon.
			advantage += (
				gamma_delta
				* lambda_delta
				* float(next_advantage_by_worker[worker_id])
			)
		advantages[transition_index] = advantage
		returns[transition_index] = advantage + float(transition["old_value"])
		value_predictions[transition_index] = float(transition["old_value"])
		if (
			not is_finite(advantages[transition_index])
			or not is_finite(returns[transition_index])
			or not is_finite(value_predictions[transition_index])
		):
			return {}
		next_advantage_by_worker[worker_id] = advantage

	var mean = 0.0
	for advantage in advantages:
		mean += advantage
	mean /= float(maxi(advantages.size(), 1))
	var variance = 0.0
	for advantage in advantages:
		var difference = advantage - mean
		variance += difference * difference
	variance /= float(maxi(advantages.size(), 1))
	var standard_deviation = sqrt(variance + 0.00000001)
	for index in range(advantages.size()):
		advantages[index] = (advantages[index] - mean) / standard_deviation
		if not is_finite(advantages[index]) or not is_finite(returns[index]):
			return {}
	return {
		"advantages": advantages,
		"returns": returns,
		"value_predictions": value_predictions,
		"advantage_mean": mean,
		"advantage_standard_deviation": standard_deviation,
		"return_statistics": RLTrainingMath.finite_statistics(returns),
		"value_prediction_statistics": RLTrainingMath.finite_statistics(value_predictions),
		"explained_variance": RLTrainingMath.explained_variance(returns, value_predictions),
	}


func _shuffle(indices: Array[int]) -> void:
	for index in range(indices.size() - 1, 0, -1):
		var swap_index = shuffle_rng.randi_range(0, index)
		var temporary = indices[index]
		indices[index] = indices[swap_index]
		indices[swap_index] = temporary


func _finite_packed(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _safe_average(total: float, count: int) -> float:
	return total / float(count) if count > 0 else 0.0


func _empty_metric_totals() -> Dictionary:
	return {
		"actor_loss": 0.0,
		"value_loss": 0.0,
		"entropy": 0.0,
		"approximate_kl": 0.0,
		"clip_fraction": 0.0,
		"actor_gradient_norm": 0.0,
		"critic_gradient_norm": 0.0,
	}


func _actor_feature_names_for_body() -> Array[String]:
	var result: Array[String] = DronePPOObservationEncoder.feature_names_for_schema(
		actor_critic.observation_schema_version
	)
	if actor_critic.observation_schema_version < DronePPOObservationEncoder.BODY_INTERFACE_SCHEMA_VERSION:
		return result
	var observations: Array[Dictionary] = _dictionary_array(
		body_interface_contract_data.get("observations", [])
	)
	for index in range(observations.size()):
		result.append(str(observations[index].get("name", "body_%d" % index)))
	return result


func _configure_body_interface(value: Variant) -> bool:
	var contract: Dictionary = value.duplicate(true) if value is Dictionary else {}
	if not _valid_body_interface_contract(contract):
		body_interface_contract_data.clear()
		body_feature_count = 0
		body_interface_signature = ""
		body_control_descriptors.clear()
		config["action_count"] = 0
		return false
	body_interface_contract_data = contract.duplicate(true)
	body_feature_count = maxi(RLTrainingMath.finite_int_or(contract.get("observation_count", 0), 0), 0)
	body_interface_signature = str(contract.get("contract_signature", ""))
	body_control_descriptors = _dictionary_array(contract.get("controls", []))
	config["action_count"] = body_control_descriptors.size()
	return true

func _valid_body_interface_contract(contract: Dictionary) -> bool:
	var control_count: int = RLTrainingMath.finite_int_or(contract.get("control_count", -1), -1)
	var observation_count: int = RLTrainingMath.finite_int_or(contract.get("observation_count", -1), -1)
	var controls: Array[Dictionary] = _dictionary_array(contract.get("controls", []))
	var observations: Array[Dictionary] = _dictionary_array(contract.get("observations", []))
	if (
		RLTrainingMath.finite_int_or(contract.get("schema_version", -1), -1)
		!= MLBodyInterfaceManifest.SCHEMA_VERSION
		or control_count < DronePPOActorCritic.MINIMUM_ACTION_COUNT
		or control_count > DronePPOActorCritic.MAXIMUM_ACTION_COUNT
		or controls.size() != control_count
		or observation_count < 0
		or observations.size() != observation_count
		or str(contract.get("contract_signature", "")).is_empty()
	):
		return false
	for descriptor: Dictionary in controls:
		if not _valid_channel_descriptor(descriptor, true):
			return false
	for descriptor: Dictionary in observations:
		if not _valid_channel_descriptor(descriptor, false):
			return false
	return true


func _valid_channel_descriptor(descriptor: Dictionary, control: bool) -> bool:
	var minimum: float = RLTrainingMath.finite_float_or(descriptor.get("minimum", NAN), NAN)
	var maximum: float = RLTrainingMath.finite_float_or(descriptor.get("maximum", NAN), NAN)
	if str(descriptor.get("name", "")).strip_edges().is_empty() or not is_finite(minimum) or not is_finite(maximum) or maximum <= minimum:
		return false
	if control:
		var neutral: float = RLTrainingMath.finite_float_or(descriptor.get("neutral", NAN), NAN)
		return is_finite(neutral) and neutral >= minimum and neutral <= maximum
	return true


func _body_contract_matches_network(
	contract: Dictionary,
	network: DronePPOActorCritic
) -> bool:
	return (
		_valid_body_interface_contract(contract)
		and int(contract.get("control_count", -1)) == network.action_count
		and int(contract.get("observation_count", -1)) == network.body_feature_count
		and str(contract.get("contract_signature", "")) == network.body_interface_signature
		and _dictionary_array(contract.get("controls", [])) == network.control_descriptors
	)


static func _body_propeller_control_count(contract: Dictionary) -> int:
	var result: int = 0
	var controls_value: Variant = contract.get("controls", [])
	if not (controls_value is Array):
		return 0
	for control_value: Variant in controls_value:
		if control_value is Dictionary and str((control_value as Dictionary).get("kind", "")) == "propeller_throttle":
			result += 1
	return result


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


static func _control_names(descriptors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for index in range(descriptors.size()):
		result.append(str(descriptors[index].get("name", "control_%d" % index)))
	return result


func _sanitize_config() -> void:
	config["learning_rate"] = clampf(RLTrainingMath.finite_float_or(config.get("learning_rate"), DEFAULT_CONFIG["learning_rate"]), 0.000001, 0.1)
	config["discount_factor"] = clampf(RLTrainingMath.finite_float_or(config.get("discount_factor"), DEFAULT_CONFIG["discount_factor"]), 0.0, 1.0)
	config["gae_lambda"] = clampf(RLTrainingMath.finite_float_or(config.get("gae_lambda"), DEFAULT_CONFIG["gae_lambda"]), 0.0, 1.0)
	config["clip_range"] = clampf(RLTrainingMath.finite_float_or(config.get("clip_range"), DEFAULT_CONFIG["clip_range"]), 0.01, 1.0)
	config["value_coefficient"] = maxf(RLTrainingMath.finite_float_or(config.get("value_coefficient"), DEFAULT_CONFIG["value_coefficient"]), 0.0)
	config["entropy_coefficient"] = maxf(RLTrainingMath.finite_float_or(config.get("entropy_coefficient"), DEFAULT_CONFIG["entropy_coefficient"]), 0.0)
	config["maximum_gradient_norm"] = maxf(RLTrainingMath.finite_float_or(config.get("maximum_gradient_norm"), DEFAULT_CONFIG["maximum_gradient_norm"]), 0.0)
	config["update_epochs"] = maxi(RLTrainingMath.finite_int_or(config.get("update_epochs"), DEFAULT_CONFIG["update_epochs"]), 1)
	config["minibatch_size"] = maxi(RLTrainingMath.finite_int_or(config.get("minibatch_size"), DEFAULT_CONFIG["minibatch_size"]), 1)
	config["rollout_transitions"] = maxi(RLTrainingMath.finite_int_or(config.get("rollout_transitions"), DEFAULT_CONFIG["rollout_transitions"]), 1)
	config["minimum_update_transitions"] = clampi(
		RLTrainingMath.finite_int_or(config.get("minimum_update_transitions"), DEFAULT_CONFIG["minimum_update_transitions"]),
		1,
		int(config["rollout_transitions"])
	)
	config["target_kl"] = maxf(RLTrainingMath.finite_float_or(config.get("target_kl"), DEFAULT_CONFIG["target_kl"]), 0.000001)
	config["discount_reference_interval_seconds"] = clampf(
		RLTrainingMath.finite_float_or(config.get("discount_reference_interval_seconds"), DEFAULT_CONFIG["discount_reference_interval_seconds"]),
		0.001,
		1.0
	)
	config["control_interval_seconds"] = clampf(
		RLTrainingMath.finite_float_or(config.get("control_interval_seconds"), DEFAULT_CONFIG["control_interval_seconds"]),
		0.01,
		1.0
	)
	config["optimizer_samples_per_frame"] = clampi(
		RLTrainingMath.finite_int_or(config.get("optimizer_samples_per_frame"), DEFAULT_CONFIG["optimizer_samples_per_frame"]),
		1,
		512
	)
	config["hidden_layer_width"] = clampi(
		RLTrainingMath.finite_int_or(config.get("hidden_layer_width"), DEFAULT_CONFIG["hidden_layer_width"]),
		DronePPOMLP.MINIMUM_HIDDEN_WIDTH,
		DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
	)
	config["hidden_layer_depth"] = clampi(
		RLTrainingMath.finite_int_or(config.get("hidden_layer_depth"), DEFAULT_CONFIG["hidden_layer_depth"]),
		DronePPOMLP.MINIMUM_HIDDEN_DEPTH,
		DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	)
	config["action_count"] = clampi(
		body_control_descriptors.size() if not body_control_descriptors.is_empty() else RLTrainingMath.finite_int_or(
			config.get("action_count"), DEFAULT_CONFIG["action_count"]
		),
		DronePPOActorCritic.MINIMUM_ACTION_COUNT,
		DronePPOActorCritic.MAXIMUM_ACTION_COUNT
	)
