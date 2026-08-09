class_name DroneSACModel
extends DroneMLModel

var actor_critic = DroneSACActorCritic.new()
var navigation_memory = DroneSACNavigationMemory.new()
var valid = false
var last_error = ""
var control_interval_seconds = 0.05


func _init(checkpoint: Dictionary = {}) -> void:
	if checkpoint.is_empty():
		last_error = "The SAC + HER checkpoint is empty."
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
		last_error = "The SAC + HER checkpoint network is incompatible."


func predict_action(observation: Dictionary) -> Dictionary:
	if not valid:
		return {}
	var memory_features = navigation_memory.features_for(0, observation)
	var actor_input = DroneSACObservationEncoder.encode_actor(
		observation,
		memory_features
	)
	return actor_critic.deterministic_action(observation, actor_input)


func get_control_interval_seconds() -> float:
	return control_interval_seconds


func reset_episode_state(_seed: int = 0) -> void:
	navigation_memory.reset_all()


func uses_compact_ppo_observation() -> bool:
	return true
