class_name TurretPPOModel
extends RefCounted

#######################################################
# Deterministic runtime model used by gameplay bodies. It shares the exact encoder/action
# contract used during training.
#######################################################

var actor_critic = TurretPPOActorCritic.new()
var loaded = false
var hardware_signature = ""


func predict_action(observation: Dictionary) -> Dictionary:
	return actor_critic.deterministic_action(observation) if loaded else {}


func load_network_state(state: Dictionary, signature: String = "") -> bool:
	loaded = actor_critic.load_state(state)
	hardware_signature = signature if loaded else ""
	return loaded


func is_compatible_with_hardware(signature: String) -> bool:
	return loaded and (
		hardware_signature.is_empty()
		or hardware_signature == signature
	)


func load_checkpoint(checkpoint: Dictionary, expected_hardware_signature: String = "") -> bool:
	if (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1) != TurretPPOTrainer.CHECKPOINT_SCHEMA_VERSION
		or str(checkpoint.get("artifact_type", "")) != "trained_turret_policy"
		or str(checkpoint.get("algorithm", "")) != TurretPPOTrainer.ALGORITHM_ID
		or str(checkpoint.get("body_profile_id", "")) != TurretPhysicalBody3D.BODY_PROFILE_ID
		or RLTrainingMath.finite_int_or(checkpoint.get("observation_schema_version", 0), -1) != TurretMLObservation.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(checkpoint.get("action_schema_version", 0), -1) != TurretMLAction.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(checkpoint.get("action_count", 0), -1) != TurretMLAction.ACTION_COUNT
		or RLTrainingMath.finite_int_or(checkpoint.get("feature_count", 0), -1) != TurretMLFeatureEncoder.FEATURE_COUNT
		or not (checkpoint.get("network", {}) is Dictionary)
	):
		return false
	var checkpoint_signature = str(checkpoint.get("hardware_signature", ""))
	if (
		not expected_hardware_signature.is_empty()
		and checkpoint_signature != expected_hardware_signature
	):
		return false
	return load_network_state(checkpoint.get("network", {}), checkpoint_signature)
