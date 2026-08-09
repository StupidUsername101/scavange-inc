class_name DronePPOUpdateJob
extends RefCounted

#######################################################
# Owns one completely detached PPO update. The payload is transferred to this object before
# its Thread starts; no scene node, live trainer container, or behavior policy is touched by
# the worker. The main thread adopts only the finished immutable result.
#######################################################

var payload: Dictionary


func _init(update_payload: Dictionary) -> void:
	payload = update_payload


func run() -> Dictionary:
	var config_value: Variant = payload.get("config", {})
	if not (config_value is Dictionary):
		return _failure("The background PPO job received no valid configuration.")
	var source_rollout_value: Variant = payload.get("rollout", [])
	if not (source_rollout_value is Array):
		return _failure("The background PPO job received no rollout.")
	var source_rollout: Array = source_rollout_value
	if source_rollout.is_empty():
		return _failure("The background PPO rollout was empty.")

	# This trainer exists only on this worker thread. Creating a private optimizer avoids
	# locks around live action sampling, UI reads, pause/remove, and checkpoint operations.
	var worker = DronePPOTrainer.new(
		(config_value as Dictionary).duplicate(true),
		int(payload.get("random_seed", 4194301))
	)
	if not worker.is_initialized():
		return _failure(
			worker.last_error
			if not worker.last_error.is_empty()
			else "The background PPO job received no accepted body interface."
		)
	var network_value: Variant = payload.get("network_state", {})
	if not (network_value is Dictionary):
		return _failure("The background PPO job received no optimizer state.")
	if (
		not worker.actor_critic.load_state(network_value as Dictionary)
		or not worker.behavior_actor_critic.load_state(network_value as Dictionary)
	):
		return _failure("The background PPO producer-policy state was incompatible.")

	worker.update_count = maxi(int(payload.get("update_count", 0)), 0)
	worker.environment_steps = maxi(int(payload.get("environment_steps", 0)), 0)
	var previous_metrics: Variant = payload.get("last_metrics", {})
	if previous_metrics is Dictionary:
		worker.last_metrics = (previous_metrics as Dictionary).duplicate(true)
	worker.shuffle_rng.state = int(payload.get(
		"shuffle_rng_state",
		worker.shuffle_rng.state
	))
	var expected_policy_revision = int(payload.get(
		"rollout_policy_revision",
		worker.update_count
	))
	worker.behavior_policy_update = expected_policy_revision
	worker.optimizer_policy_revision = expected_policy_revision
	worker.rollout_policy_revision = expected_policy_revision
	worker.rollout_start_network_state = network_value as Dictionary
	for transition_value in source_rollout:
		if not (transition_value is Dictionary):
			continue
		# The rollout was detached from the live trainer before this thread started.
		# PPO treats transition payloads as immutable, so another recursive copy only
		# duplicates large packed tensors without adding thread safety.
		var transition: Dictionary = transition_value as Dictionary
		if int(transition.get("policy_revision", expected_policy_revision)) != expected_policy_revision:
			return _failure("The background PPO optimizer received a mixed-policy rollout.")
		worker.rollout.append(transition)
	if worker.rollout.is_empty():
		return _failure("The background PPO optimizer received no valid rollout transitions.")

	var force_partial = bool(payload.get("force_partial", false))
	if not worker.begin_update(force_partial):
		return _failure(
			worker.last_error
			if not worker.last_error.is_empty()
			else "The background PPO update could not start."
		)
	worker.update_prepared["result_policy_revision"] = maxi(int(payload.get(
		"result_policy_revision",
		worker.update_count + 1
	)), expected_policy_revision + 1)
	var chunk_size = maxi(
		int(worker.config.get("optimizer_samples_per_frame", 16)),
		1
	)
	while worker.update_in_progress:
		worker.process_update(chunk_size)
	if worker.last_metrics.is_empty() or not worker.actor_critic.is_finite_state():
		return _failure("The background PPO update produced an invalid result.")

	return {
		"ok": true,
		"network_state": worker.actor_critic.to_runtime_state(),
		"metrics": worker.last_metrics,
		"update_count": worker.update_count,
		"optimizer_policy_revision": worker.optimizer_policy_revision,
		"shuffle_rng_state": worker.shuffle_rng.state,
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
