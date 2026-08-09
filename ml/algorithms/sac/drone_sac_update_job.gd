class_name DroneSACUpdateJob
extends RefCounted

var payload: Dictionary


func _init(update_payload: Dictionary) -> void:
	payload = update_payload


func run() -> Dictionary:
	var network_state_value: Variant = payload.get("network_state", {})
	var batches_value: Variant = payload.get("batches", [])
	var config_value: Variant = payload.get("config", {})
	if not (network_state_value is Dictionary):
		return _failure("The background SAC job received no network state.")
	if not (batches_value is Array) or (batches_value as Array).is_empty():
		return _failure("The background SAC job received no replay batches.")
	if not (config_value is Dictionary):
		return _failure("The background SAC job received no configuration.")
	var learner: DroneSACActorCritic = DroneSACActorCritic.new(
		int(payload.get("random_seed", 7340033))
	)
	if not learner.load_state(network_state_value as Dictionary):
		return _failure("The background SAC network state was incompatible.")
	var metrics: Dictionary = learner.train_batches(
		batches_value as Array,
		config_value as Dictionary
	)
	if metrics.is_empty() or not learner.is_finite_state():
		return _failure("The background SAC update produced an invalid result.")
	return {
		"ok": true,
		"network_state": learner.to_state(true),
		"metrics": metrics,
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
