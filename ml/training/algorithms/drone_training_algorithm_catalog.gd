class_name DroneTrainingAlgorithmCatalog
extends RefCounted

const DEFAULT_ALGORITHM_ID = "ppo_clip"

const ALGORITHMS = {
	"ppo_clip": {
		"id": "ppo_clip",
		"display_name": "Clipped PPO + GAE",
		"short_name": "PPO",
		"checkpoint_algorithm": "clipped_ppo_gae",
		"artifact_type": "ppo_quadrotor_actor_critic",
		"description": "Learns from the newest completed rollout.\n\nPPO changes the policy cautiously and keeps some random propeller variation for exploration.",
		"supports_weight_branching": true,
		"runtime_model_class": "DronePPOModel",
	},
	"sac_her_maze": {
		"id": "sac_her_maze",
		"display_name": "Maze SAC + Hindsight Replay",
		"short_name": "SAC-HER",
		"checkpoint_algorithm": "soft_actor_critic_her",
		"artifact_type": "sac_her_maze_quadrotor",
		"description": "Reuses past experience and failed attempts.\n\nSAC-HER can vary exploration by situation and remembers recently visited maze cells while still controlling all four propellers directly.",
		"supports_weight_branching": true,
		"runtime_model_class": "DroneSACModel",
	},
}


static func descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for algorithm_key in ALGORITHMS:
		result.append((ALGORITHMS[algorithm_key] as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)
	return result


static func descriptor(algorithm_id: String) -> Dictionary:
	var value: Variant = ALGORITHMS.get(algorithm_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func descriptor_for_checkpoint(checkpoint: Dictionary) -> Dictionary:
	var explicit_id = str(checkpoint.get("training_algorithm_id", ""))
	if ALGORITHMS.has(explicit_id):
		return descriptor(explicit_id)
	var checkpoint_name = str(checkpoint.get("algorithm", ""))
	for candidate in ALGORITHMS.values():
		var candidate_descriptor: Dictionary = candidate
		if str(candidate_descriptor.get("checkpoint_algorithm", "")) == checkpoint_name:
			return candidate_descriptor.duplicate(true)
	return {}


static func is_training_checkpoint(checkpoint_or_record: Dictionary) -> bool:
	return not descriptor_for_checkpoint(checkpoint_or_record).is_empty()


static func create(
	algorithm_id: String,
	custom_config: Dictionary = {},
	initialization_seed: int = 4194301
) -> DroneTrainingAlgorithm:
	match algorithm_id:
		"ppo_clip":
			var trainer = DronePPOTrainer.new(custom_config, initialization_seed)
			return trainer if trainer.is_initialized() else null
		"sac_her_maze":
			return DroneSACTrainer.new(custom_config, initialization_seed)
	return null


static func create_runtime_model(checkpoint: Dictionary) -> DroneMLModel:
	match str(descriptor_for_checkpoint(checkpoint).get("id", "")):
		"ppo_clip":
			var model = DronePPOModel.new(checkpoint)
			return model if model.valid else null
		"sac_her_maze":
			var model = DroneSACModel.new(checkpoint)
			return model if model.valid else null
	return null


static func inspect_checkpoint(checkpoint: Dictionary) -> Dictionary:
	var result = {
		"compatible": false,
		"trainable": false,
		"compatibility_text": "This checkpoint uses an unknown learning algorithm.",
	}
	match str(descriptor_for_checkpoint(checkpoint).get("id", "")):
		"ppo_clip":
			var network: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("network", {}))
			var actor: Dictionary = SafeVariant.dictionary_copy(network.get("actor", {}))
			var critic: Dictionary = SafeVariant.dictionary_copy(network.get("critic", {}))
			var observation_schema: int = RLTrainingMath.finite_int_or(
				network.get("observation_schema_version", 0), -1
			)
			var hidden_width: int = RLTrainingMath.finite_int_or(
				network.get("hidden_size", 0), -1
			)
			var hidden_depth: int = RLTrainingMath.finite_int_or(
				network.get("hidden_layer_count", 0), -1
			)
			var network_action_count: int = RLTrainingMath.finite_int_or(
				network.get("action_count", 0), -1
			)
			var body_feature_count: int = RLTrainingMath.finite_int_or(
				network.get("body_feature_count", -1), -1
			)
			var body_signature: String = str(network.get("body_interface_signature", ""))
			var control_descriptors: Array[Dictionary] = SafeVariant.dictionary_array_copy(
				network.get("control_descriptors", [])
			)
			var body_contract: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("body_interface", {}))
			var compatible: bool = (
				RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1)
				== DronePPOTrainer.CHECKPOINT_SCHEMA_VERSION
				and str(checkpoint.get("algorithm", "")) == DronePPOTrainer.ALGORITHM_NAME
				and RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), -1)
				== _body_propeller_control_count(body_contract)
				and _body_propeller_control_count(body_contract) >= 0
				and _body_propeller_control_count(body_contract) <= DronePPOObservationEncoder.QUAD_PROPELLER_COUNT
				and RLTrainingMath.finite_int_or(network.get("schema_version", 0), -1)
				== DronePPOActorCritic.STATE_SCHEMA_VERSION
				and DronePPOObservationEncoder.is_trainable_schema(observation_schema)
				and network_action_count >= DronePPOActorCritic.MINIMUM_ACTION_COUNT
				and network_action_count <= DronePPOActorCritic.MAXIMUM_ACTION_COUNT
				and body_feature_count >= 0
				and not body_signature.is_empty()
				and control_descriptors.size() == network_action_count
				and _valid_body_contract(
					body_contract,
					network_action_count,
					body_feature_count,
					body_signature,
					control_descriptors
				)
				and _valid_hidden_architecture(hidden_width, hidden_depth)
				and _valid_mlp_contract(
					actor,
					DronePPOObservationEncoder.actor_feature_count_for_schema(
						observation_schema, body_feature_count
					),
					hidden_width,
					hidden_depth,
					network_action_count
				)
				and _valid_mlp_contract(
					critic,
					DronePPOObservationEncoder.critic_feature_count_for_schema(
						observation_schema, body_feature_count
					),
					hidden_width,
					hidden_depth,
					1
				)
			)
			result["compatible"] = compatible
			result["trainable"] = compatible
			result["compatibility_text"] = (
				"Ready for deterministic inference and continued PPO training."
				if compatible
				else "The PPO checkpoint architecture/schema does not match this build."
			)
		"sac_her_maze":
			var network: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("network", {}))
			var actor: Dictionary = SafeVariant.dictionary_copy(network.get("actor", {}))
			var q_one: Dictionary = SafeVariant.dictionary_copy(network.get("q_one", {}))
			var q_two: Dictionary = SafeVariant.dictionary_copy(network.get("q_two", {}))
			var target_q_one: Dictionary = SafeVariant.dictionary_copy(network.get("target_q_one", {}))
			var target_q_two: Dictionary = SafeVariant.dictionary_copy(network.get("target_q_two", {}))
			var hidden_width: int = RLTrainingMath.finite_int_or(
				network.get("hidden_size", 0), -1
			)
			var hidden_depth: int = RLTrainingMath.finite_int_or(
				network.get("hidden_layer_count", 0), -1
			)
			var compatible: bool = (
				RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1)
				== DroneSACTrainer.CHECKPOINT_SCHEMA_VERSION
				and str(checkpoint.get("algorithm", "")) == DroneSACTrainer.ALGORITHM_NAME
				and RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), -1)
				== DroneSACObservationEncoder.ACTION_COUNT
				and RLTrainingMath.finite_int_or(network.get("schema_version", 0), -1)
				== DroneSACActorCritic.STATE_SCHEMA_VERSION
				and RLTrainingMath.finite_int_or(network.get("observation_schema_version", 0), -1)
				== DroneSACObservationEncoder.SCHEMA_VERSION
				and RLTrainingMath.finite_int_or(network.get("action_count", 0), -1)
				== DroneSACObservationEncoder.ACTION_COUNT
				and str(network.get("action_semantics", "")) == DroneSACActorCritic.ACTION_SEMANTICS
				and str(network.get("policy_distribution_semantics", ""))
				== DroneSACActorCritic.POLICY_DISTRIBUTION_SEMANTICS
				and RLTrainingMath.finite_int_or(network.get("policy_output_count", 0), -1)
				== DroneSACActorCritic.POLICY_OUTPUT_COUNT
				and _valid_hidden_architecture(hidden_width, hidden_depth)
				and _valid_mlp_contract(
					actor,
					DroneSACObservationEncoder.ACTOR_FEATURE_COUNT,
					hidden_width,
					hidden_depth,
					DroneSACActorCritic.POLICY_OUTPUT_COUNT
				)
				and _valid_mlp_contract(q_one, DroneSACObservationEncoder.Q_INPUT_COUNT, hidden_width, hidden_depth, 1)
				and _valid_mlp_contract(q_two, DroneSACObservationEncoder.Q_INPUT_COUNT, hidden_width, hidden_depth, 1)
				and _valid_mlp_contract(target_q_one, DroneSACObservationEncoder.Q_INPUT_COUNT, hidden_width, hidden_depth, 1)
				and _valid_mlp_contract(target_q_two, DroneSACObservationEncoder.Q_INPUT_COUNT, hidden_width, hidden_depth, 1)
			)
			result["compatible"] = compatible
			result["trainable"] = compatible
			result["compatibility_text"] = (
				"Ready for deterministic inference and continued SAC-HER training. Replay memory starts empty after model-only loading."
				if compatible
				else "The SAC-HER checkpoint architecture/schema does not match this build."
			)
	return result


static func _body_propeller_control_count(contract: Dictionary) -> int:
	var result: int = 0
	var controls_value: Variant = contract.get("controls", [])
	if not (controls_value is Array):
		return 0
	for control_value: Variant in controls_value:
		if control_value is Dictionary and str((control_value as Dictionary).get("kind", "")) == "propeller_throttle":
			result += 1
	return result


static func _valid_hidden_architecture(hidden_width: int, hidden_depth: int) -> bool:
	return (
		hidden_width >= DronePPOMLP.MINIMUM_HIDDEN_WIDTH
		and hidden_width <= DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
		and hidden_depth >= DronePPOMLP.MINIMUM_HIDDEN_DEPTH
		and hidden_depth <= DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	)


static func _valid_mlp_contract(
	state: Dictionary,
	expected_input: int,
	expected_width: int,
	expected_depth: int,
	expected_output: int
) -> bool:
	return (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		== DronePPOMLP.STATE_SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(state.get("input_size", 0), -1) == expected_input
		and RLTrainingMath.finite_int_or(state.get("hidden_size", 0), -1) == expected_width
		and RLTrainingMath.finite_int_or(state.get("hidden_layer_count", 0), -1) == expected_depth
		and RLTrainingMath.finite_int_or(state.get("output_size", 0), -1) == expected_output
	)


static func runtime_contract(checkpoint: Dictionary) -> Dictionary:
	var descriptor_value = descriptor_for_checkpoint(checkpoint)
	match str(descriptor_value.get("id", "")):
		"ppo_clip":
			var network: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("network", {}))
			var actor: Dictionary = SafeVariant.dictionary_copy(network.get("actor", {}))
			var critic: Dictionary = SafeVariant.dictionary_copy(network.get("critic", {}))
			var config: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("config", {}))
			return {
				"runtime_model_class": str(descriptor_value.get(
					"runtime_model_class",
					"DroneMLModel"
				)),
				"training_algorithm_id": str(descriptor_value.get("id", "")),
				"intended_body_kind": "drone",
				"observation_schema_version": RLTrainingMath.finite_int_or(network.get(
					"observation_schema_version",
					0
				), -1),
				"actor_feature_count": RLTrainingMath.finite_int_or(actor.get("input_size", 0), -1),
				"critic_feature_count": RLTrainingMath.finite_int_or(critic.get("input_size", 0), -1),
				"action_count": RLTrainingMath.finite_int_or(network.get("action_count", 0), -1),
				"body_feature_count": RLTrainingMath.finite_int_or(network.get("body_feature_count", 0), -1),
				"body_interface_signature": str(network.get("body_interface_signature", "")),
				"control_descriptors": SafeVariant.dictionary_array_copy(network.get("control_descriptors", [])),
				"body_interface": SafeVariant.dictionary_copy(checkpoint.get("body_interface", {})),
				"hidden_size": RLTrainingMath.finite_int_or(network.get("hidden_size", 0), -1),
				"hidden_layer_count": RLTrainingMath.finite_int_or(network.get("hidden_layer_count", 0), -1),
				"control_interval_seconds": clampf(
					RLTrainingMath.finite_float_or(
						config.get("control_interval_seconds"),
						0.05
					),
					0.01,
					1.0
				),
			}
		"sac_her_maze":
			var network: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("network", {}))
			var actor: Dictionary = SafeVariant.dictionary_copy(network.get("actor", {}))
			var config: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("config", {}))
			var stored_actor_output_count = RLTrainingMath.finite_int_or(actor.get("output_size", 0), -1)
			var stored_distribution = str(network.get(
				"policy_distribution_semantics",
				"legacy_global_gaussian_v1"
			))
			return {
				"runtime_model_class": str(descriptor_value.get("runtime_model_class", "DroneMLModel")),
				"training_algorithm_id": str(descriptor_value.get("id", "")),
				"intended_body_kind": "drone",
				"observation_schema_version": RLTrainingMath.finite_int_or(network.get("observation_schema_version", 0), -1),
				"actor_feature_count": RLTrainingMath.finite_int_or(actor.get("input_size", 0), -1),
				"actor_output_count": DroneSACActorCritic.POLICY_OUTPUT_COUNT,
				"stored_actor_output_count": stored_actor_output_count,
				"critic_feature_count": DroneSACObservationEncoder.CRITIC_FEATURE_COUNT,
				"action_count": RLTrainingMath.finite_int_or(network.get("action_count", 0), -1),
				"hidden_size": RLTrainingMath.finite_int_or(network.get("hidden_size", 0), -1),
				"hidden_layer_count": RLTrainingMath.finite_int_or(network.get("hidden_layer_count", 0), -1),
				"action_semantics": str(network.get("action_semantics", "")),
				"policy_distribution_semantics": (
					DroneSACActorCritic.POLICY_DISTRIBUTION_SEMANTICS
				),
				"stored_policy_distribution_semantics": stored_distribution,
				"control_interval_seconds": clampf(
					RLTrainingMath.finite_float_or(config.get("control_interval_seconds"), 0.05),
					0.01,
					1.0
				),
			}
	return {}


static func _valid_body_contract(
	contract: Dictionary,
	expected_controls: int,
	expected_observations: int,
	expected_signature: String,
	expected_descriptors: Array[Dictionary]
) -> bool:
	return (
		RLTrainingMath.finite_int_or(contract.get("schema_version", -1), -1)
		== MLBodyInterfaceManifest.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(contract.get("control_count", -1), -1)
		== expected_controls
		and RLTrainingMath.finite_int_or(contract.get("observation_count", -1), -1)
		== expected_observations
		and str(contract.get("contract_signature", "")) == expected_signature
		and SafeVariant.dictionary_array_copy(contract.get("controls", [])) == expected_descriptors
	)


static func can_branch(source_id: String, target_id: String) -> bool:
	if source_id != target_id:
		return false
	return bool(descriptor(target_id).get("supports_weight_branching", false))
