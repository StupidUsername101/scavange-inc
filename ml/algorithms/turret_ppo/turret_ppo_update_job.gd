class_name TurretPPOUpdateJob
extends RefCounted

#######################################################
# Runs one detached turret PPO update on a private worker thread. The live trainer and
# physical bodies are never touched from the worker thread.
#######################################################

var payload: Dictionary


func _init(update_payload: Dictionary) -> void:
	payload = update_payload


func run() -> Dictionary:
	var config_value: Variant = payload.get("config", {})
	var rollout_value: Variant = payload.get("rollout", [])
	var network_value: Variant = payload.get("network_state", {})
	if not (config_value is Dictionary):
		return _failure("The turret optimizer received no valid configuration.")
	if not (rollout_value is Array) or (rollout_value as Array).is_empty():
		return _failure("The turret optimizer received no rollout samples.")
	if not (network_value is Dictionary):
		return _failure("The turret optimizer received no network state.")

	var worker = TurretPPOTrainer.new(int(payload.get("random_seed", 7340033)))
	worker.config = (config_value as Dictionary).duplicate(true)
	worker._sanitize_config()
	if (
		not worker.actor_critic.load_state(network_value as Dictionary)
		or not worker.behavior_actor_critic.load_state(network_value as Dictionary)
	):
		return _failure("The turret optimizer network state was incompatible.")
	worker.update_count = maxi(int(payload.get("update_count", 0)), 0)
	worker.environment_steps = maxi(int(payload.get("environment_steps", 0)), 0)
	worker.completed_episodes = maxi(int(payload.get("completed_episodes", 0)), 0)
	var previous_audit: Variant = payload.get("last_feature_audit", {})
	if previous_audit is Dictionary and not (previous_audit as Dictionary).is_empty():
		worker.last_metrics["feature_audit"] = (previous_audit as Dictionary).duplicate(true)
	worker.shuffle_rng.state = int(payload.get("shuffle_rng_state", worker.shuffle_rng.state))
	var expected_policy_revision = int(payload.get(
		"rollout_policy_revision",
		worker.update_count
	))
	for transition_value: Variant in (rollout_value as Array):
		if transition_value is Dictionary:
			# The live trainer transfers ownership of this rollout before the thread starts.
			# Optimizer code reads transition payloads but never mutates them.
			var transition: Dictionary = transition_value as Dictionary
			if int(transition.get("policy_revision", expected_policy_revision)) != expected_policy_revision:
				return _failure("The turret optimizer received a mixed-policy rollout.")
			worker.rollout.append(transition)
	if worker.rollout.is_empty():
		return _failure("The turret optimizer received no valid rollout transitions.")
	worker.behavior_policy_update = expected_policy_revision
	worker.optimizer_policy_revision = expected_policy_revision
	worker.rollout_policy_revision = expected_policy_revision
	worker.rollout_start_network_state = network_value as Dictionary

	var metrics = worker.update_if_ready(bool(payload.get("force_partial", false)))
	if metrics.is_empty() or metrics.has("error"):
		return _failure(str(metrics.get(
			"error",
			worker.last_error if not worker.last_error.is_empty() else "The turret PPO update failed."
		)))
	return {
		"ok": true,
		"network_state": worker.actor_critic.to_runtime_state(),
		"metrics": metrics,
		"update_count": worker.update_count,
		"optimizer_policy_revision": worker.optimizer_policy_revision,
		"shuffle_rng_state": worker.shuffle_rng.state,
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
