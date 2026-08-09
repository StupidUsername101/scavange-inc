class_name DroneMLModel
extends RefCounted

#######################################################
# Defines the deliberately empty algorithm boundary. A future trained model implements
# predict_action() without coupling its training framework to ServerDrone.
#######################################################


func predict_action(_observation: Dictionary) -> Dictionary:
	# Intentionally empty. Returning an empty action makes the controller fail safe
	# with zero rotor output until an algorithm or external trainer is connected.
	return {}


func get_control_interval_seconds() -> float:
	# Zero keeps the generic model contract frame-driven. Models that intentionally hold
	# actions can override this so the controller avoids building unused observations.
	return 0.0


func uses_compact_ppo_observation() -> bool:
	return false


func reset_episode_state(_seed: int = 0) -> void:
	# Stateless runtime models intentionally do nothing. Recurrent/navigation-memory models
	# override this so one evaluator episode cannot leak state into the next one.
	pass
