class_name TurretModelRegistry
extends TrainingModelRegistryBase

const DEFAULT_ROOT_PATH: String = "user://ml_turret_models"

#######################################################
# Turret model-library contract. Shared immutable-version storage lives in
# TrainingModelRegistryBase; this class owns only turret identity/compatibility rules.
#######################################################


func _init(custom_root_path: String = DEFAULT_ROOT_PATH) -> void:
	super(custom_root_path)


func _artifact_type() -> String:
	return "trained_turret_policy"


func _body_profile_id() -> String:
	return TurretPhysicalBody3D.BODY_PROFILE_ID


func _default_model_name() -> String:
	return "Turret Model"


func _storage_key_fallback() -> String:
	return "turret-model"


func _body_label() -> String:
	return "turret"


func _is_compatible_checkpoint(checkpoint: Dictionary) -> bool:
	var metadata_matches: bool = (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1)
		== TurretPPOTrainer.CHECKPOINT_SCHEMA_VERSION
		and str(checkpoint.get("artifact_type", "")) == _artifact_type()
		and str(checkpoint.get("algorithm", "")) == TurretPPOTrainer.ALGORITHM_ID
		and str(checkpoint.get("body_profile_id", "")) == TurretPhysicalBody3D.BODY_PROFILE_ID
		and RLTrainingMath.finite_int_or(checkpoint.get("observation_schema_version", 0), -1)
		== TurretMLObservation.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(checkpoint.get("action_schema_version", 0), -1)
		== TurretMLAction.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(checkpoint.get("action_count", 0), -1)
		== TurretMLAction.ACTION_COUNT
		and RLTrainingMath.finite_int_or(checkpoint.get("feature_count", 0), -1)
		== TurretMLFeatureEncoder.FEATURE_COUNT
		and checkpoint.get("network", {}) is Dictionary
	)
	if not metadata_matches:
		return false
	var runtime_model: TurretPPOModel = TurretPPOModel.new()
	return runtime_model.load_checkpoint(
		checkpoint,
		str(checkpoint.get("hardware_signature", ""))
	)
