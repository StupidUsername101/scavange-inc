class_name DroneTrainingAlgorithm
extends RefCounted

#######################################################
# Stable training-room boundary for learning algorithms. The room owns lifecycle,
# simulation and UI; implementations own action sampling, experience, optimization and
# checkpoint state. New algorithms can be added without teaching the room their math.
#######################################################


func algorithm_id() -> String:
	return ""


func algorithm_display_name() -> String:
	return "Unknown algorithm"


func algorithm_short_name() -> String:
	return algorithm_display_name()


func default_worker_count() -> int:
	return 1


func maximum_worker_count() -> int:
	return 1


func configuration_controls() -> Array[Dictionary]:
	return []


func config_values() -> Dictionary:
	return {}


func network_architecture() -> Dictionary:
	return {}


func set_config_value(_key: String, _value: Variant) -> bool:
	return false


func encode_observation(observation: Dictionary, _worker_id: int = -1) -> Dictionary:
	return {"observation": observation}


func sample_action(_observation: Dictionary) -> Dictionary:
	return {}


func sample_action_from_inputs(
	_observation: Dictionary,
	_actor_input: PackedFloat64Array,
	_critic_input: PackedFloat64Array,
	_worker_id: int = -1
) -> Dictionary:
	return {}


func add_transition(
	_worker_id: int,
	_action_sample: Dictionary,
	_reward: float,
	_next_observation: Dictionary,
	_terminated: bool,
	_truncated: bool,
	_next_critic_input: PackedFloat64Array = PackedFloat64Array(),
	_next_value_override: float = NAN,
	_transition_metadata: Dictionary = {}
) -> bool:
	return false


func requires_goal_relabel_reward_trace() -> bool:
	# Most algorithms need only the transition duration. SAC overrides this while HER is
	# enabled so the room can avoid constructing per-physics-frame metadata for PPO.
	return false


func behavior_policy_revision() -> int:
	return 0


func can_update(_force_partial_rollout = false) -> bool:
	return false


func begin_background_update(_force_partial_rollout = false) -> bool:
	return false


func poll_background_update() -> Dictionary:
	return {}


func has_background_update() -> bool:
	return false


func shutdown_background_update() -> void:
	pass


func discard_incomplete_rollout() -> void:
	pass


func record_completed_episode(_mean_reward: float) -> void:
	pass


func reset_episode_statistics() -> void:
	pass


func copy_policy_from(_source: DroneTrainingAlgorithm) -> bool:
	return false


func perturb_policy(_relative_strength: float, _perturbation_seed: int) -> bool:
	return false


func status_text(_is_training: bool) -> String:
	return algorithm_display_name()


func diagnostic_status_text() -> String:
	return "No learner-specific diagnostics are available yet."


func to_checkpoint() -> Dictionary:
	return {}


func to_best_checkpoint() -> Dictionary:
	return {}


func to_training_checkpoint() -> Dictionary:
	# Algorithms without replay/optimizer continuation may use their ordinary checkpoint.
	return to_checkpoint()


func load_training_checkpoint(checkpoint: Dictionary) -> bool:
	return load_checkpoint(checkpoint)


func set_evaluation_contract(_contract: Dictionary) -> bool:
	return false


func evaluation_contract() -> Dictionary:
	return {}


func candidate_checkpoint() -> Dictionary:
	return {}


func pending_evaluation_candidate() -> Dictionary:
	return {}


func pending_evaluation_candidate_id() -> int:
	return -1


func discard_pending_evaluation_candidate(_candidate_id: int) -> bool:
	return false


func record_deterministic_evaluation(
	_candidate_id: int,
	_evaluation_summary: Dictionary
) -> Dictionary:
	return {"promoted": false, "reason": "unsupported"}


func record_deterministic_evaluation_records(
	_candidate_id: int,
	_records: Array[Dictionary]
) -> Dictionary:
	return {"promoted": false, "reason": "unsupported"}


func record_best_deterministic_evaluation_records(
	_evaluation_plan: Dictionary,
	_records: Array[Dictionary]
) -> Dictionary:
	return {"recorded": false, "reason": "unsupported"}


func best_evaluation_summary() -> Dictionary:
	return {}


func best_evaluation_contract_snapshot() -> Dictionary:
	return {}


func load_checkpoint(_checkpoint: Dictionary) -> bool:
	return false


func has_best_checkpoint() -> bool:
	return false


func best_selection_summary() -> Dictionary:
	return {}


func pending_auto_save_candidate() -> Dictionary:
	return {}


func acknowledge_auto_save_candidate(_candidate_id: int) -> void:
	pass


func update_count_value() -> int:
	return 0


func environment_step_count() -> int:
	return 0


func completed_episode_count() -> int:
	return 0


func last_metrics_value() -> Dictionary:
	return {}


func last_error_text() -> String:
	return ""


func last_background_update_milliseconds() -> float:
	return 0.0
