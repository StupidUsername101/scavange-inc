class_name FourLimbModelRegistry
extends TrainingModelRegistryBase

const DEFAULT_ROOT_PATH: String = "user://ml_four_limb_models"

#######################################################
# Four-limb model-library contract. Shared immutable-version storage lives in
# TrainingModelRegistryBase; this class owns only four-limb identity/compatibility rules.
#######################################################


func _init(custom_root_path: String = DEFAULT_ROOT_PATH) -> void:
	super(custom_root_path)


static func _supported_observation_contract(checkpoint: Dictionary) -> bool:
	var schema: int = RLTrainingMath.finite_int_or(
		checkpoint.get("observation_schema_version", 0),
		-1
	)
	var count: int = RLTrainingMath.finite_int_or(checkpoint.get("feature_count", 0), -1)
	return (
		schema == FourLimbMLObservation.SCHEMA_VERSION
		and count == FourLimbMLFeatureEncoder.FEATURE_COUNT
	)


func _artifact_type() -> String:
	return "trained_four_limb_policy"


func _body_profile_id() -> String:
	return FourLimbBodyDefinition.BODY_PROFILE_ID


func _default_model_name() -> String:
	return "Four Limb Model"


func _storage_key_fallback() -> String:
	return "four-limb-model"


func _body_label() -> String:
	return "four-limb"


func _is_compatible_checkpoint(checkpoint: Dictionary) -> bool:
	var metadata_matches: bool = (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1)
		== FourLimbPPOTrainer.CHECKPOINT_SCHEMA_VERSION
		and str(checkpoint.get("artifact_type", "")) == _artifact_type()
		and str(checkpoint.get("algorithm", "")) == FourLimbPPOTrainer.ALGORITHM_ID
		and str(checkpoint.get("body_profile_id", "")) == FourLimbBodyDefinition.BODY_PROFILE_ID
		and _supported_observation_contract(checkpoint)
		and RLTrainingMath.finite_int_or(checkpoint.get("action_schema_version", 0), -1)
		== FourLimbMLAction.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(checkpoint.get("action_count", 0), -1)
		== FourLimbMLAction.ACTION_COUNT
		and checkpoint.get("network", {}) is Dictionary
	)
	if not metadata_matches:
		return false
	var runtime_model: FourLimbPPOModel = FourLimbPPOModel.new()
	return runtime_model.load_checkpoint(
		checkpoint,
		str(checkpoint.get("hardware_signature", ""))
	)
