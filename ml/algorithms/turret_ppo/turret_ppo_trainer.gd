class_name TurretPPOTrainer
extends RefCounted

const CHECKPOINT_SCHEMA_VERSION = 3
const ALGORITHM_ID = "turret_ppo"
const FEATURE_AUDIT_UPDATE_INTERVAL = 10
const FEATURE_AUDIT_MAXIMUM_SAMPLES = 128
const INITIAL_LOG_PROBABILITY_TOLERANCE = 0.00000001
const PPO_KL_STOP_MULTIPLIER = 1.5
const DEFAULT_CONFIG = {
	"learning_rate": 0.0003,
	"gamma": 0.995,
	"gae_lambda": 0.95,
	"clip_range": 0.2,
	"entropy_coefficient": 0.008,
	"value_coefficient": 0.5,
	"maximum_gradient_norm": 0.5,
	"rollout_size": 512,
	"minimum_update_transitions": 64,
	"epochs": 4,
	"batch_size": 64,
	"target_kl": 0.03,
	"control_interval_seconds": 0.05,
	"discount_reference_interval_seconds": 0.05,
	"hidden_layer_width": TurretPPOActorCritic.HIDDEN_SIZE,
	"hidden_layer_depth": TurretPPOActorCritic.HIDDEN_LAYER_COUNT,
}

#######################################################
# PPO trainer for the physical turret body. It follows the drone trainer's split-policy
# architecture: a stable behavior policy controls bodies while a detached optimizer policy
# learns on a low-priority thread. Bodies keep simulating during optimization; physical steps
# are counted but stale on-policy samples are discarded until the learned policy is installed.
#######################################################

var config = DEFAULT_CONFIG.duplicate(true)
var actor_critic: TurretPPOActorCritic
var behavior_actor_critic: TurretPPOActorCritic
var rollout: Array[Dictionary] = []
var rollout_policy_revision = -1
var rollout_start_network_state: Dictionary = {}
var skipped_transitions_during_update = 0
var random_seed = 7340033
var shuffle_rng = RandomNumberGenerator.new()
var update_count = 0
var behavior_policy_update = 0
var optimizer_policy_revision = 0
var environment_steps = 0
var completed_episodes = 0
var last_metrics: Dictionary = {}
var best_episode_score = -INF
# Training performance only nominates a frozen producer-policy candidate. The designated
# best network changes only after an external deterministic fixed-seed evaluation.
var best_network_state: Dictionary = {}
var candidate_nomination_score = -INF
var candidate_sequence = 0
var pending_candidate: Dictionary = {}
var candidate_network_state: Dictionary = {}
var candidate_training_summary: Dictionary = {}
var promoted_training_summary: Dictionary = {}
var best_evaluation: Dictionary = {}
var best_evaluation_contract: Dictionary = {}
var evaluation_contract_template: Dictionary = {}
var pending_promoted_candidate: Dictionary = {}
var last_error = ""
var background_thread: Thread
var background_job: TurretPPOUpdateJob
var background_result_discarded = false
var background_started_usec = 0
var last_background_update_ms = 0.0


func _init(
	seed_value: int = 7340033,
	network_config: Dictionary = {}
) -> void:
	random_seed = seed_value
	for key: String in ["hidden_layer_width", "hidden_layer_depth"]:
		if network_config.has(key):
			config[key] = network_config[key]
	_sanitize_config()
	actor_critic = TurretPPOActorCritic.new(
		random_seed,
		int(config["hidden_layer_width"]),
		int(config["hidden_layer_depth"])
	)
	behavior_actor_critic = TurretPPOActorCritic.new(
		random_seed + 500003,
		int(config["hidden_layer_width"]),
		int(config["hidden_layer_depth"])
	)
	_sync_behavior_from_optimizer(true)
	shuffle_rng.seed = random_seed + 11


func algorithm_display_name() -> String:
	return "Clipped PPO + GAE"


func config_values() -> Dictionary:
	return config.duplicate(true)


func configuration_controls() -> Array[Dictionary]:
	return PPOTrainingConfigSupport.body_configuration_controls(
		"physical turret commands"
	)

func set_config_value(key: String, value: Variant) -> bool:
	last_error = ""
	if key == "hidden_layer_width" or key == "hidden_layer_depth":
		last_error = "Network depth and width are fixed when the model is created."
		return false
	if not config.has(key):
		last_error = "Unknown turret PPO setting '%s'." % key
		return false
	config[key] = value
	_sanitize_config()
	return true


func network_architecture() -> Dictionary:
	return {
		"hidden_layer_width": actor_critic.hidden_size,
		"hidden_layer_depth": actor_critic.hidden_layer_count,
	}


func sample_action(observation: Dictionary, deterministic: bool = false) -> Dictionary:
	var sample = behavior_actor_critic.sample_action(observation, deterministic)
	if not sample.is_empty():
		sample["policy_revision"] = behavior_policy_update
	return sample


func sample_runtime_action(observation: Dictionary, deterministic: bool = false) -> Dictionary:
	var sample = behavior_actor_critic.sample_runtime_action(observation, deterministic)
	if not sample.is_empty():
		sample["policy_revision"] = behavior_policy_update
	return sample


func stable_policy_state() -> Dictionary:
	return behavior_actor_critic.to_state().duplicate(true)


func perturb_policy(relative_strength: float, perturbation_seed: int) -> bool:
	last_error = ""
	shutdown_background_update()
	discard_incomplete_rollout()
	var strength = clampf(relative_strength, 0.0, 0.5)
	if strength <= 0.0:
		return true
	if not actor_critic.perturb_weights(strength, perturbation_seed):
		last_error = "The turret branch variation produced an invalid network."
		return false
	optimizer_policy_revision = maxi(optimizer_policy_revision + 1, update_count + 1)
	if not _sync_behavior_from_optimizer(false):
		last_error = "The varied turret behavior policy could not be synchronized."
		return false
	reset_episode_statistics()
	last_metrics.clear()
	rollout.clear()
	rollout_policy_revision = -1
	rollout_start_network_state.clear()
	return true


func add_transition(
	worker_id: int,
	action_sample: Dictionary,
	reward: float,
	next_observation: Dictionary,
	terminated: bool,
	truncated: bool,
	delta_seconds: float = 0.05,
	precomputed_next_input: PackedFloat64Array = PackedFloat64Array(),
	precomputed_next_value: float = NAN
) -> bool:
	last_error = ""
	if (
		action_sample.is_empty()
		or not is_finite(reward)
		or not (action_sample.get("actor_input") is PackedFloat64Array)
		or not (action_sample.get("critic_input") is PackedFloat64Array)
		or not (action_sample.get("latent_action") is PackedFloat64Array)
		or not (action_sample.get("commands") is PackedFloat64Array)
		or not (action_sample.get("policy_revision") is int or action_sample.get("policy_revision") is float)
	):
		last_error = "The turret PPO transition contains an invalid sample or reward."
		return false
	if terminated and truncated:
		last_error = "A turret PPO transition cannot be both terminated and truncated."
		return false
	_sanitize_config()
	# PPO is on-policy. Bodies may keep moving while the detached optimizer works, but samples
	# produced during that time still belong to the policy that generated the previous rollout.
	# Dropping those samples is preferable to silently training a newer network against stale
	# log probabilities.
	if has_background_update():
		skipped_transitions_during_update += 1
		# This physical interaction still happened even though on-policy PPO must discard it.
		# Keep environment-step telemetry/checkpoint counters comparable with drone PPO.
		environment_steps += 1
		return true
	var sample_policy_revision: int = RLTrainingMath.finite_int_or(
		action_sample.get("policy_revision", -1),
		-1
	)
	if sample_policy_revision != behavior_policy_update:
		if sample_policy_revision >= 0 and sample_policy_revision < behavior_policy_update:
			# A held action can straddle the frame where a completed detached optimizer is
			# adopted. Settle its complete physical interval, then discard the stale PPO
			# sample instead of contaminating the newly active rollout.
			skipped_transitions_during_update += 1
			environment_steps += 1
			return true
		last_error = (
			"The turret PPO transition belongs to behavior policy %d, but policy %d is active."
			% [sample_policy_revision, behavior_policy_update]
		)
		return false
	if rollout.is_empty():
		rollout_policy_revision = sample_policy_revision
		rollout_start_network_state = behavior_actor_critic.to_runtime_state()
	elif rollout_policy_revision != sample_policy_revision:
		last_error = "The turret PPO rollout mixed multiple behavior-policy revisions."
		return false
	var next_input: PackedFloat64Array = precomputed_next_input
	var next_value: float = 0.0
	# Natural terminal states never bootstrap. Accepting them without a fabricated
	# successor preserves the final failure transition even when the body is already
	# destroyed or its terminal observation can no longer be encoded.
	if not terminated:
		if next_input.is_empty():
			next_input = TurretMLFeatureEncoder.encode(next_observation)
		if not TurretMLFeatureEncoder.is_normalized(next_input):
			last_error = "The turret PPO transition contains an invalid next observation tensor."
			return false
		next_value = (
			precomputed_next_value
			if is_finite(precomputed_next_value)
			else behavior_actor_critic.value_from_input(next_input)
		)
	var actor_input: PackedFloat64Array = action_sample.get(
		"actor_input", PackedFloat64Array()
	)
	var critic_input: PackedFloat64Array = action_sample.get(
		"critic_input", PackedFloat64Array()
	)
	var latent_action: PackedFloat64Array = action_sample.get(
		"latent_action", PackedFloat64Array()
	)
	var commands: PackedFloat64Array = action_sample.get(
		"commands", PackedFloat64Array()
	)
	var old_log_probability: float = RLTrainingMath.finite_float_or(
		action_sample.get("log_probability", NAN),
		NAN
	)
	var old_value: float = RLTrainingMath.finite_float_or(
		action_sample.get("value", NAN),
		NAN
	)
	var safe_delta_seconds = maxf(delta_seconds, 0.000001)
	if (
		actor_input.size() != TurretMLFeatureEncoder.FEATURE_COUNT
		or critic_input.size() != TurretMLFeatureEncoder.FEATURE_COUNT
		or latent_action.size() != TurretMLAction.ACTION_COUNT
		or commands.size() != TurretMLAction.ACTION_COUNT
		or not TurretMLFeatureEncoder.is_normalized(actor_input)
		or not TurretMLFeatureEncoder.is_normalized(critic_input)
		or not RLTrainingMath.packed_all_finite(latent_action)
		or not RLTrainingMath.packed_all_in_range(commands, -1.000001, 1.000001)
		or not is_finite(old_log_probability)
		or not is_finite(old_value)
		or not is_finite(next_value)
		or not is_finite(delta_seconds)
		or delta_seconds <= 0.0
	):
		last_error = "The turret PPO transition contains invalid or non-finite tensors."
		return false
	rollout.append({
		"worker_id": worker_id,
		"actor_input": actor_input,
		"critic_input": critic_input,
		"latent_action": latent_action,
		"commands": commands,
		"old_log_probability": old_log_probability,
		"value": old_value,
		"reward": reward,
		"next_value": next_value,
		"terminated": terminated,
		"truncated": truncated,
		"policy_revision": sample_policy_revision,
		"delta_seconds": safe_delta_seconds,
	})
	environment_steps += 1
	return true


func can_update(force_partial: bool = false) -> bool:
	_sanitize_config()
	if has_background_update():
		return false
	var required = (
		int(config["minimum_update_transitions"])
		if force_partial
		else int(config["rollout_size"])
	)
	return rollout.size() >= maxi(required, 1)


func discard_incomplete_rollout() -> void:
	# Worker-count and configuration restarts must not leave fragments from the previous
	# physical population in the next on-policy PPO batch. This mirrors the drone
	# trainer contract used by the shared room.
	rollout.clear()
	rollout_policy_revision = -1
	rollout_start_network_state.clear()


func discard_worker_transitions(worker_id: int) -> void:
	if rollout.is_empty():
		return
	var retained: Array[Dictionary] = []
	for transition: Dictionary in rollout:
		if RLTrainingMath.finite_int_or(transition.get("worker_id", -1), -1) != worker_id:
			retained.append(transition)
	rollout = retained
	if rollout.is_empty():
		rollout_policy_revision = -1
		rollout_start_network_state.clear()


func update_if_ready(force_partial: bool = false) -> Dictionary:
	last_error = ""
	if not can_update(force_partial):
		return {}
	_consider_rollout_candidate(rollout, rollout_start_network_state)
	if (
		rollout_start_network_state.is_empty()
		or not actor_critic.load_state(rollout_start_network_state)
	):
		last_error = "The turret rollout has no compatible producer-policy snapshot."
		return {"error": last_error}
	var identity = _policy_divergence_metrics(rollout)
	var initial_log_probability_error_max = float(identity.get(
		"maximum_log_probability_error",
		INF
	))
	var initial_approximate_kl = float(identity.get("approximate_kl", INF))
	var initial_clip_fraction = float(identity.get("clip_fraction", 1.0))
	if (
		not is_finite(initial_log_probability_error_max)
		or initial_log_probability_error_max > INITIAL_LOG_PROBABILITY_TOLERANCE
	):
		last_error = (
			"The turret rollout does not match producer policy revision %d "
			+ "(maximum log-probability error %.12f)."
		) % [rollout_policy_revision, initial_log_probability_error_max]
		return {"error": last_error}
	var advantages_and_returns = RLTrainingMath.generalized_advantage_estimates(
		rollout,
		float(config["gamma"]),
		float(config["gae_lambda"]),
		float(config.get("discount_reference_interval_seconds", 0.05)),
		float(config.get("control_interval_seconds", 0.05)),
		"value"
	)
	if advantages_and_returns.is_empty():
		last_error = "The turret rollout could not be converted into learning targets."
		return {"error": last_error}
	var advantages: PackedFloat64Array = advantages_and_returns["advantages"]
	var returns: PackedFloat64Array = advantages_and_returns["returns"]
	var value_predictions: PackedFloat64Array = advantages_and_returns["value_predictions"]
	var reward_statistics = RLTrainingMath.finite_transition_statistics(
		rollout,
		"reward",
		0.0
	)
	var return_statistics = RLTrainingMath.finite_statistics(returns)
	var value_prediction_statistics = RLTrainingMath.finite_statistics(value_predictions)
	var explained_variance = RLTrainingMath.explained_variance(returns, value_predictions)
	var advantage_statistics: Dictionary = RLTrainingMath.finite_statistics(advantages)
	var feature_audit = _feature_audit_for_rollout(rollout)
	var actor_parameters_before = actor_critic.actor.parameters.duplicate()
	var log_standard_deviation_before = actor_critic.log_standard_deviation.duplicate()
	RLTrainingMath.normalize_in_place(advantages)
	var indices: Array[int] = []
	indices.resize(rollout.size())
	for index: int in range(indices.size()):
		indices[index] = index
	var actor_loss_total = 0.0
	var value_loss_total = 0.0
	var entropy_total = 0.0
	var kl_total = 0.0
	var clip_total = 0.0
	var sample_total = 0
	var actor_gradient_total = 0.0
	var critic_gradient_total = 0.0
	var completed_epochs = 0
	var optimizer_batch_count = 0
	var maximum_minibatch_kl = 0.0
	var early_stopped = false
	var early_stop_reason = ""
	for _epoch in range(int(config["epochs"])):
		RLTrainingMath.shuffle_indices_in_place(indices, shuffle_rng)
		var epoch_kl_total = 0.0
		var epoch_sample_total = 0
		var batch_start = 0
		while batch_start < indices.size():
			var batch_end = mini(batch_start + int(config["batch_size"]), indices.size())
			actor_critic.clear_actor_gradients()
			actor_critic.clear_critic_gradients()
			for shuffled_index in range(batch_start, batch_end):
				var transition_index = indices[shuffled_index]
				var transition = rollout[transition_index]
				var actor_metrics = actor_critic.accumulate_actor_gradient(
					transition["actor_input"],
					transition["latent_action"],
					float(transition["old_log_probability"]),
					advantages[transition_index],
					float(config["clip_range"]),
					float(config["entropy_coefficient"])
				)
				var critic_metrics = actor_critic.accumulate_critic_gradient(
					transition["critic_input"],
					returns[transition_index],
					float(config["value_coefficient"])
				)
				var sample_kl = float(actor_metrics.get("approximate_kl", 0.0))
				actor_loss_total += float(actor_metrics.get("actor_loss", 0.0))
				value_loss_total += float(critic_metrics.get("value_loss", 0.0))
				entropy_total += float(actor_metrics.get("entropy", 0.0))
				kl_total += sample_kl
				clip_total += float(actor_metrics.get("clip_fraction", 0.0))
				epoch_kl_total += sample_kl
				sample_total += 1
				epoch_sample_total += 1
			var batch_count = maxi(batch_end - batch_start, 1)
			actor_gradient_total += actor_critic.apply_actor_gradients(
				float(config["learning_rate"]),
				batch_count,
				float(config["maximum_gradient_norm"])
			)
			critic_gradient_total += actor_critic.apply_critic_gradients(
				float(config["learning_rate"]),
				batch_count,
				float(config["maximum_gradient_norm"])
			)
			optimizer_batch_count += 1
			var post_batch_divergence = _policy_divergence_metrics(rollout)
			var post_batch_kl = float(post_batch_divergence.get("approximate_kl", INF))
			if is_finite(post_batch_kl):
				maximum_minibatch_kl = maxf(maximum_minibatch_kl, post_batch_kl)
			batch_start = batch_end
			if (
				float(config["target_kl"]) > 0.0
				and is_finite(post_batch_kl)
				and post_batch_kl > float(config["target_kl"]) * PPO_KL_STOP_MULTIPLIER
			):
				early_stopped = true
				early_stop_reason = "target_kl"
				break
		completed_epochs += 1
		if early_stopped:
			break
		var epoch_mean_kl = epoch_kl_total / float(maxi(epoch_sample_total, 1))
		if (
			float(config["target_kl"]) > 0.0
			and epoch_mean_kl > float(config["target_kl"]) * 1.5
		):
			early_stopped = true
			early_stop_reason = "target_kl_epoch"
			break
	update_count += 1
	optimizer_policy_revision = maxi(optimizer_policy_revision + 1, update_count)
	var command_diagnostics = RLTrainingMath.bounded_command_diagnostics(
		rollout,
		-1.0,
		1.0
	)
	last_metrics = {
		"update_count": update_count,
		"environment_steps": environment_steps,
		"rollout_samples": rollout.size(),
		"actor_loss": actor_loss_total / float(maxi(sample_total, 1)),
		"value_loss": value_loss_total / float(maxi(sample_total, 1)),
		"entropy": entropy_total / float(maxi(sample_total, 1)),
		"approximate_kl": kl_total / float(maxi(sample_total, 1)),
		"clip_fraction": clip_total / float(maxi(sample_total, 1)),
		"actor_gradient_norm_mean_pre_clip": actor_gradient_total / float(maxi(optimizer_batch_count, 1)),
		"critic_gradient_norm_mean_pre_clip": critic_gradient_total / float(maxi(optimizer_batch_count, 1)),
		"actor_gradient_norm": actor_gradient_total / float(maxi(optimizer_batch_count, 1)),
		"critic_gradient_norm": critic_gradient_total / float(maxi(optimizer_batch_count, 1)),
		"initial_log_probability_error_max": initial_log_probability_error_max,
		"initial_approximate_kl": initial_approximate_kl,
		"initial_clip_fraction": initial_clip_fraction,
		"maximum_minibatch_kl": maximum_minibatch_kl,
		"completed_minibatches": optimizer_batch_count,
		"completed_epochs": completed_epochs,
		"early_stopped": early_stopped,
		"early_stop_reason": early_stop_reason,
		"exploration": actor_critic.exploration_statistics(),
		"command_diagnostics": command_diagnostics,
		"rollout_policy_revision": rollout_policy_revision,
		"optimizer_policy_revision": optimizer_policy_revision,
		"skipped_transitions_during_update": skipped_transitions_during_update,
		"mean_transition_reward": float(reward_statistics.get("mean", 0.0)),
		"transition_reward_standard_deviation": float(reward_statistics.get("standard_deviation", 0.0)),
		"advantage_standard_deviation_before_normalization": float(advantage_statistics.get("standard_deviation", 0.0)),
		"return_statistics": return_statistics,
		"value_prediction_statistics": value_prediction_statistics,
		"explained_variance": explained_variance,
		"policy_parameter_delta_rms": PPOTrainingDiagnostics.parameter_delta_rms(
			actor_parameters_before,
			actor_critic.actor.parameters,
			log_standard_deviation_before,
			actor_critic.log_standard_deviation
		),
		"feature_audit": feature_audit,
		"effective_gamma": RLTrainingMath.discount_for_delta(
			float(config["gamma"]),
			float(config.get("control_interval_seconds", 0.05)),
			float(config.get("discount_reference_interval_seconds", 0.05))
		),
		"discount_half_life_seconds": RLTrainingMath.half_life_seconds(
			float(config["gamma"]),
			float(config.get("discount_reference_interval_seconds", 0.05))
		),
		"discount_reference_interval_seconds": float(config.get(
			"discount_reference_interval_seconds", 0.05
		)),
		"gae_lambda_time_semantics": "real_time_reference_interval",
	}
	rollout.clear()
	rollout_start_network_state.clear()
	skipped_transitions_during_update = 0
	_sync_behavior_from_optimizer(true)
	rollout_policy_revision = -1
	return last_metrics.duplicate(true)


func begin_background_update(force_partial: bool = false) -> bool:
	last_error = ""
	if not can_update(force_partial):
		return false
	var detached_rollout: Array[Dictionary] = rollout
	var detached_policy_revision = rollout_policy_revision
	var detached_network_state = rollout_start_network_state
	if detached_network_state.is_empty():
		last_error = "The rollout has no producer-policy snapshot."
		return false
	_consider_rollout_candidate(detached_rollout, detached_network_state)
	var feature_audit_value: Variant = last_metrics.get("feature_audit", {})
	var last_feature_audit: Dictionary = (
		(feature_audit_value as Dictionary).duplicate(true)
		if feature_audit_value is Dictionary
		else {}
	)
	var payload = {
		"config": config.duplicate(true),
		"random_seed": random_seed,
		# Immutable snapshot captured when the first transition entered this rollout.
		"network_state": detached_network_state,
		"rollout": detached_rollout,
		"rollout_policy_revision": detached_policy_revision,
		"result_policy_revision": maxi(optimizer_policy_revision + 1, update_count + 1),
		"update_count": update_count,
		"environment_steps": environment_steps,
		"completed_episodes": completed_episodes,
		"shuffle_rng_state": shuffle_rng.state,
		"force_partial": force_partial,
		"last_feature_audit": last_feature_audit,
	}
	var next_job = TurretPPOUpdateJob.new(payload)
	var next_thread = Thread.new()
	rollout = []
	rollout_policy_revision = -1
	rollout_start_network_state = {}
	var start_error = next_thread.start(Callable(next_job, "run"), Thread.PRIORITY_LOW)
	if start_error != OK:
		rollout = detached_rollout
		rollout_policy_revision = detached_policy_revision
		rollout_start_network_state = detached_network_state
		last_error = "Godot could not create the turret optimizer thread."
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
	var discard_result = background_result_discarded
	background_result_discarded = false
	if discard_result:
		return {}
	if not (result_value is Dictionary):
		last_error = "The turret optimizer returned no result."
		return {"error": last_error}
	var result: Dictionary = result_value
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "The turret optimizer failed."))
		return {"error": last_error}
	var network_value: Variant = result.get("network_state", {})
	if not (network_value is Dictionary) or not actor_critic.load_state(
		network_value as Dictionary
	):
		last_error = "The completed turret optimizer state was incompatible."
		return {"error": last_error}
	update_count = maxi(int(result.get("update_count", update_count + 1)), 0)
	optimizer_policy_revision = maxi(int(result.get(
		"optimizer_policy_revision",
		maxi(optimizer_policy_revision + 1, update_count)
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
	last_metrics["skipped_transitions_during_update"] = skipped_transitions_during_update
	# Install the learned policy immediately when the worker thread completes. The coordinator
	# polls at the start of a physics tick and resamples every active body before more transitions
	# are collected, so no action/reward pair straddles two policy revisions.
	rollout.clear()
	if not _sync_behavior_from_optimizer(true):
		last_error = "The completed turret behavior policy could not be synchronized."
		return {"error": last_error}
	rollout_policy_revision = -1
	skipped_transitions_during_update = 0
	last_error = ""
	return last_metrics.duplicate(true)


func diagnostic_status_text() -> String:
	return TurretPPOFeatureAudit.status_text(last_metrics.get("feature_audit", {}))


func _feature_audit_for_rollout(source: Array[Dictionary]) -> Dictionary:
	var existing: Dictionary = last_metrics.get("feature_audit", {})
	if update_count > 0 and (update_count + 1) % FEATURE_AUDIT_UPDATE_INTERVAL != 0:
		return existing.duplicate(true)
	var samples: Array[Dictionary] = []
	var sample_count = mini(source.size(), FEATURE_AUDIT_MAXIMUM_SAMPLES)
	if sample_count == source.size():
		samples.assign(source)
	elif sample_count > 0:
		# Spread the diagnostic across the complete rollout instead of over-representing its first
		# few workers/seconds. This remains deterministic and does not touch optimizer sampling.
		for sample_index: int in range(sample_count):
			var source_index = int(round(
				float(sample_index) * float(source.size() - 1) / float(maxi(sample_count - 1, 1))
			))
			samples.append(source[source_index])
	return TurretPPOFeatureAudit.analyze_rollout(
		samples,
		TurretMLFeatureEncoder.feature_names()
	)


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


func record_completed_episode(score: float) -> void:
	completed_episodes += 1
	if is_finite(score):
		best_episode_score = maxf(best_episode_score, score)


func reset_episode_statistics() -> void:
	completed_episodes = 0
	best_episode_score = -INF
	best_network_state.clear()
	candidate_nomination_score = -INF
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	promoted_training_summary.clear()
	best_evaluation.clear()
	best_evaluation_contract.clear()
	pending_promoted_candidate.clear()
	last_metrics = {}


func deterministic_model() -> TurretPPOModel:
	var model = TurretPPOModel.new()
	model.load_network_state(stable_policy_state())
	return model


func to_checkpoint(
	hardware_signature: String,
	reward_config: Dictionary = {},
	use_best_policy: bool = false
) -> Dictionary:
	if use_best_policy and best_network_state.is_empty():
		last_error = "No deterministically evaluated turret checkpoint is available yet."
		return {}
	var checkpoint_network = (
		best_network_state.duplicate(true)
		if use_best_policy
		else stable_policy_state()
	)
	var checkpoint = _checkpoint_with_network(checkpoint_network, hardware_signature, reward_config)
	if use_best_policy:
		_apply_training_context_to_checkpoint(checkpoint, promoted_training_summary)
		checkpoint["checkpoint_scope"] = "evaluated_best"
	else:
		checkpoint["checkpoint_scope"] = "current_policy"
	return checkpoint


func _checkpoint_with_network(
	network_state: Dictionary,
	hardware_signature: String,
	reward_config: Dictionary
) -> Dictionary:
	return {
		"schema_version": CHECKPOINT_SCHEMA_VERSION,
		"artifact_type": "trained_turret_policy",
		"algorithm": ALGORITHM_ID,
		"body_profile_id": TurretPhysicalBody3D.BODY_PROFILE_ID,
		"observation_schema_version": TurretMLObservation.SCHEMA_VERSION,
		"action_schema_version": TurretMLAction.SCHEMA_VERSION,
		"action_count": TurretMLAction.ACTION_COUNT,
		"feature_count": TurretMLFeatureEncoder.FEATURE_COUNT,
		"network": network_state.duplicate(true),
		"discount_time_base": {
			"discount_key": "gamma",
			"reference_interval_seconds": float(config.get("discount_reference_interval_seconds", 0.05)),
			"lambda_semantics": "real_time_reference_interval",
		},
		"hardware_signature": hardware_signature,
		"training": {
			"config": config.duplicate(true),
			"random_seed": random_seed,
			"shuffle_rng_state": shuffle_rng.state,
			"behavior_action_rng_state": behavior_actor_critic.action_rng.state,
			"update_count": update_count,
			"optimizer_policy_revision": optimizer_policy_revision,
			"behavior_policy_revision": behavior_policy_update,
			"behavior_policy_update": behavior_policy_update,
			"environment_steps": environment_steps,
			"completed_episodes": completed_episodes,
			"has_best_episode_score": is_finite(best_episode_score),
			"best_episode_score": best_episode_score if is_finite(best_episode_score) else 0.0,
			"best_network": best_network_state.duplicate(true),
			"has_candidate_nomination_score": is_finite(candidate_nomination_score),
			"candidate_nomination_score": candidate_nomination_score if is_finite(candidate_nomination_score) else 0.0,
			"candidate_sequence": candidate_sequence,
			"pending_evaluation_candidate": pending_candidate.duplicate(true),
			"candidate_network_state": candidate_network_state.duplicate(true),
			"candidate_training_summary": candidate_training_summary.duplicate(true),
			"promoted_training_summary": promoted_training_summary.duplicate(true),
			"best_evaluation": best_evaluation.duplicate(true),
			"best_evaluation_contract": best_evaluation_contract.duplicate(true),
			"last_metrics": last_metrics.duplicate(true),
			"resume_mode": "clean_rollout_boundary",
		},
		"reward_cards": reward_config.duplicate(true),
	}


func has_best_checkpoint() -> bool:
	return not best_network_state.is_empty()


func set_evaluation_contract(contract: Dictionary) -> bool:
	if not RLEvaluationContract.is_valid(contract, "turret"):
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
		best_episode_score,
		false
	)

func candidate_checkpoint(
	hardware_signature: String,
	reward_config: Dictionary = {}
) -> Dictionary:
	if candidate_network_state.is_empty() or pending_candidate.is_empty():
		return {}
	var checkpoint = _checkpoint_with_network(candidate_network_state, hardware_signature, reward_config)
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
	candidate_nomination_score = -INF
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
	else:
		candidate_nomination_score = -INF
	pending_candidate.clear()
	candidate_network_state.clear()
	candidate_training_summary.clear()
	return {
		"promoted": promoted,
		"reason": str(evaluation_result.get("reason", "unknown")),
		"evaluation": verified_summary,
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
		"turret"
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


func _apply_training_context_to_checkpoint(checkpoint: Dictionary, summary: Dictionary) -> void:
	if checkpoint.is_empty() or summary.is_empty():
		return
	var training: Dictionary = checkpoint.get("training", {}).duplicate(true)
	training["update_count"] = int(summary.get("policy_update", update_count))
	training["optimizer_policy_revision"] = int(summary.get("optimizer_policy_revision", training.get("optimizer_policy_revision", optimizer_policy_revision)))
	training["behavior_policy_revision"] = int(summary.get("behavior_policy_revision", training.get("behavior_policy_revision", behavior_policy_update)))
	training["behavior_policy_update"] = int(training["behavior_policy_revision"])
	training["environment_steps"] = int(summary.get("environment_steps", environment_steps))
	training["completed_episodes"] = int(summary.get("completed_episodes", completed_episodes))
	training["selection_summary"] = summary.duplicate(true)
	checkpoint["training"] = training


func load_checkpoint(checkpoint: Dictionary, expected_hardware_signature: String = "") -> bool:
	last_error = ""
	var training_value: Variant = checkpoint.get("training", {})
	if (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1) != CHECKPOINT_SCHEMA_VERSION
		or str(checkpoint.get("artifact_type", "")) != "trained_turret_policy"
		or str(checkpoint.get("algorithm", "")) != ALGORITHM_ID
		or str(checkpoint.get("body_profile_id", "")) != TurretPhysicalBody3D.BODY_PROFILE_ID
		or RLTrainingMath.finite_int_or(checkpoint.get("observation_schema_version", 0), -1) != TurretMLObservation.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(checkpoint.get("action_schema_version", 0), -1) != TurretMLAction.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(checkpoint.get("action_count", 0), -1) != TurretMLAction.ACTION_COUNT
		or RLTrainingMath.finite_int_or(checkpoint.get("feature_count", 0), -1) != TurretMLFeatureEncoder.FEATURE_COUNT
		or not (checkpoint.get("network", {}) is Dictionary)
		or not (training_value is Dictionary)
		or not ((training_value as Dictionary).get("config", {}) is Dictionary)
	):
		last_error = "This checkpoint does not match the current turret PPO architecture."
		return false
	if (
		not expected_hardware_signature.is_empty()
		and str(checkpoint.get("hardware_signature", "")) != expected_hardware_signature
	):
		last_error = "This model was trained for a different turret anatomy."
		return false
	var staged_actor_critic: TurretPPOActorCritic = TurretPPOActorCritic.new()
	var staged_behavior_actor_critic: TurretPPOActorCritic = TurretPPOActorCritic.new()
	if not staged_actor_critic.load_state(checkpoint.get("network", {})):
		last_error = "The turret network state could not be loaded."
		return false
	if not staged_behavior_actor_critic.load_state(staged_actor_critic.to_runtime_state()):
		last_error = "The loaded turret behavior policy could not be synchronized."
		return false
	shutdown_background_update()
	actor_critic = staged_actor_critic
	behavior_actor_critic = staged_behavior_actor_critic
	var training: Dictionary = training_value
	var loaded_config: Dictionary = training.get("config", {})
	for key: Variant in loaded_config:
		if config.has(key):
			config[key] = loaded_config[key]
	_sanitize_config()
	config["hidden_layer_width"] = staged_actor_critic.hidden_size
	config["hidden_layer_depth"] = staged_actor_critic.hidden_layer_count
	random_seed = RLTrainingMath.finite_int_or(
		training.get("random_seed", random_seed), random_seed
	)
	shuffle_rng.state = RLTrainingMath.finite_int_or(
		training.get("shuffle_rng_state", shuffle_rng.state), shuffle_rng.state
	)
	behavior_actor_critic.action_rng.state = RLTrainingMath.finite_int_or(
		training.get("behavior_action_rng_state", behavior_actor_critic.action_rng.state),
		behavior_actor_critic.action_rng.state
	)
	update_count = maxi(RLTrainingMath.finite_int_or(training.get("update_count", 0), 0), 0)
	optimizer_policy_revision = maxi(RLTrainingMath.finite_int_or(
		training.get("optimizer_policy_revision", update_count), update_count
	), 0)
	behavior_policy_update = maxi(RLTrainingMath.finite_int_or(
		training.get(
			"behavior_policy_revision",
			training.get("behavior_policy_update", optimizer_policy_revision)
		),
		optimizer_policy_revision
	), 0)
	environment_steps = maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	completed_episodes = maxi(RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0), 0)
	best_episode_score = (
		RLTrainingMath.finite_float_or(training.get("best_episode_score", -INF), -INF)
		if RLTrainingMath.bool_or(training.get("has_best_episode_score", false), false)
		else -INF
	)
	best_network_state = {}
	var loaded_best: Variant = training.get("best_network", {})
	if loaded_best is Dictionary and not (loaded_best as Dictionary).is_empty():
		var migrated_best: TurretPPOActorCritic = TurretPPOActorCritic.new()
		if migrated_best.load_state(loaded_best as Dictionary):
			best_network_state = migrated_best.to_state()
	candidate_nomination_score = (
		RLTrainingMath.finite_float_or(training.get("candidate_nomination_score", -INF), -INF)
		if RLTrainingMath.bool_or(training.get("has_candidate_nomination_score", false), false)
		else -INF
	)
	candidate_sequence = maxi(RLTrainingMath.finite_int_or(training.get("candidate_sequence", 0), 0), 0)
	pending_candidate = (
		(training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
		if training.get("pending_evaluation_candidate", {}) is Dictionary else {}
	)
	candidate_network_state = {}
	var loaded_candidate_network: Variant = training.get("candidate_network_state", {})
	if loaded_candidate_network is Dictionary and not (loaded_candidate_network as Dictionary).is_empty():
		var migrated_candidate: TurretPPOActorCritic = TurretPPOActorCritic.new()
		if migrated_candidate.load_state(loaded_candidate_network as Dictionary):
			candidate_network_state = migrated_candidate.to_state()
	candidate_training_summary = (
		(training.get("candidate_training_summary", {}) as Dictionary).duplicate(true)
		if training.get("candidate_training_summary", {}) is Dictionary else {}
	)
	promoted_training_summary = (
		(training.get("promoted_training_summary", {}) as Dictionary).duplicate(true)
		if training.get("promoted_training_summary", {}) is Dictionary else {}
	)
	best_evaluation = (
		(training.get("best_evaluation", {}) as Dictionary).duplicate(true)
		if training.get("best_evaluation", {}) is Dictionary else {}
	)
	best_evaluation_contract = (
		(training.get("best_evaluation_contract", {}) as Dictionary).duplicate(true)
		if training.get("best_evaluation_contract", {}) is Dictionary else {}
	)
	pending_promoted_candidate.clear()
	# Pending candidates are resumable only when their frozen evaluation contract is present.
	# Older checkpoints remain loadable, but their pre-contract pending candidate must not enter
	# the fixed-seed queue under whatever room settings happen to be active after loading.
	if (
		not pending_candidate.is_empty()
		and not RLTrainingCandidateSupport.is_resumable_candidate(
			pending_candidate,
			candidate_network_state,
			"turret"
		)
	):
		pending_candidate.clear()
		candidate_network_state.clear()
		candidate_training_summary.clear()
		candidate_nomination_score = -INF

	if best_network_state.is_empty():
		best_evaluation.clear()
		best_evaluation_contract.clear()
		promoted_training_summary.clear()

	var evaluated_best_is_verified: bool = (
		not best_network_state.is_empty()
		and RLDeterministicEvaluationSuite.is_complete_summary(best_evaluation)
		and str(best_evaluation.get("candidate_hash", ""))
			== RLDeterministicEvaluator.candidate_hash(best_network_state)
		and RLEvaluationContract.is_valid(best_evaluation_contract, "turret")
		and str(best_evaluation.get("evaluation_contract_hash", ""))
			== str(best_evaluation_contract.get("contract_hash", ""))
	)
	if not best_network_state.is_empty() and not evaluated_best_is_verified:
		# Keep the legacy Best network itself. The scheduler will re-evaluate it under the next
		# frozen Candidate contract before comparing scores. Converting it into a contract-less
		# pending candidate would either fail the evaluator or silently late-bind a new task.
		best_evaluation.clear()
		best_evaluation_contract.clear()

	last_metrics = (
		(training.get("last_metrics", {}) as Dictionary).duplicate(true)
		if training.get("last_metrics", {}) is Dictionary
		else {}
	)
	if last_metrics.has("feature_audit") and not last_metrics["feature_audit"] is Dictionary:
		last_metrics.erase("feature_audit")
	rollout.clear()
	rollout_policy_revision = -1
	rollout_start_network_state.clear()
	return true


func _consider_rollout_candidate(
	source_rollout: Array[Dictionary],
	producer_network_state: Dictionary
) -> void:
	if source_rollout.is_empty() or producer_network_state.is_empty():
		return
	if not RLEvaluationContract.is_valid(evaluation_contract_template, "turret"):
		return
	var worker_totals: Dictionary = {}
	var worker_seconds: Dictionary = {}
	for transition in source_rollout:
		var worker_id = int(transition.get("worker_id", 0))
		worker_totals[worker_id] = float(worker_totals.get(worker_id, 0.0)) + float(transition.get("reward", 0.0))
		worker_seconds[worker_id] = float(worker_seconds.get(worker_id, 0.0)) + maxf(
			float(transition.get("delta_seconds", config.get("control_interval_seconds", 0.05))),
			0.000001
		)
	var worker_scores: Array[float] = []
	for worker_id in worker_totals:
		worker_scores.append(float(worker_totals[worker_id]) / maxf(float(worker_seconds.get(worker_id, 0.0)), 0.000001))
	if worker_scores.is_empty():
		return
	worker_scores.sort()
	var total = 0.0
	for score in worker_scores:
		total += score
	var group_mean = total / float(worker_scores.size())
	var support_index = clampi(floori(float(worker_scores.size() - 1) * 0.25), 0, worker_scores.size() - 1)
	var support_score = worker_scores[support_index]
	var best_worker_score = worker_scores[worker_scores.size() - 1]
	var robust_best_index = clampi(floori(float(worker_scores.size() - 1) * 0.75), 0, worker_scores.size() - 1)
	var robust_best_score = worker_scores[robust_best_index]
	var selection_score = group_mean * 0.70 + support_score * 0.30
	if not is_finite(selection_score) or selection_score <= candidate_nomination_score:
		return
	candidate_nomination_score = selection_score
	candidate_network_state = producer_network_state.duplicate(true)
	candidate_training_summary = {
		"selection_score": selection_score,
		"group_mean_reward_per_second": group_mean,
		"support_reward_per_second": support_score,
		"best_worker_reward_per_second": best_worker_score,
		"robust_best_worker_reward_per_second": robust_best_score,
		"policy_update": rollout_policy_revision,
		"optimizer_policy_revision": optimizer_policy_revision,
		"behavior_policy_revision": rollout_policy_revision,
		"environment_steps": environment_steps,
		"completed_episodes": completed_episodes,
		"worker_count": worker_scores.size(),
		"transition_count": source_rollout.size(),
		"exact_policy_match": true,
		"selection_method": "frozen_rollout_robust_candidate_v1",
	}
	candidate_sequence += 1
	pending_candidate = candidate_training_summary.duplicate(true)
	pending_candidate["candidate_id"] = candidate_sequence
	pending_candidate["candidate_hash"] = RLDeterministicEvaluator.candidate_hash(candidate_network_state)
	pending_candidate["evaluation_status"] = "awaiting_deterministic_suite"
	pending_candidate["evaluation_contract"] = evaluation_contract_template.duplicate(true)
	pending_candidate["evaluation_contract_hash"] = str(evaluation_contract_template.get("contract_hash", ""))
	pending_candidate["evaluation_plan"] = RLDeterministicEvaluationSuite.plan_for_contract("turret", evaluation_contract_template)


func _sync_behavior_from_optimizer(preserve_rng: bool) -> bool:
	var rng_state = behavior_actor_critic.action_rng.state
	if not behavior_actor_critic.load_state(actor_critic.to_runtime_state()):
		return false
	if preserve_rng:
		behavior_actor_critic.action_rng.state = rng_state
	behavior_policy_update = optimizer_policy_revision
	return true


func _policy_divergence_metrics(
	source_rollout: Array[Dictionary],
	maximum_samples: int = 64
) -> Dictionary:
	return PPOTrainingDiagnostics.policy_divergence_metrics(
		source_rollout,
		Callable(actor_critic, "log_probability_from_input"),
		float(config["clip_range"]),
		maximum_samples
	)

func _sanitize_config() -> void:
	PPOTrainingConfigSupport.sanitize_body_config(config, DEFAULT_CONFIG)
