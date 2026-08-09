class_name DronePPOModel
extends DroneMLModel

#######################################################
# Loads an immutable PPO checkpoint for deterministic in-game/evaluation inference.
#######################################################

var actor_critic = DronePPOActorCritic.new()
var valid = false
var last_error = ""
var control_interval_seconds = 0.05


func _init(checkpoint: Dictionary = {}) -> void:
	if checkpoint.is_empty():
		last_error = "The PPO checkpoint is empty."
		return
	var config_value: Variant = checkpoint.get("config", {})
	var config: Dictionary = config_value if config_value is Dictionary else {}
	control_interval_seconds = clampf(
		RLTrainingMath.finite_float_or(config.get("control_interval_seconds"), 0.05),
		0.01,
		1.0
	)
	var network_value: Variant = checkpoint.get("network", {})
	valid = network_value is Dictionary and actor_critic.load_state(network_value as Dictionary)
	if not valid:
		last_error = "The PPO checkpoint network is incompatible."


func predict_action(observation: Dictionary) -> Dictionary:
	if not valid:
		return {}
	# DroneMLController owns the control-rate timer and action hold. Sampling here only
	# when requested avoids a second timer, critic pass, and training-only sample data.
	return actor_critic.deterministic_action(observation)


func get_control_interval_seconds() -> float:
	return control_interval_seconds


func uses_compact_ppo_observation() -> bool:
	return true
