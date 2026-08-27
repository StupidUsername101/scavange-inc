class_name MLGameModelArtifact
extends RefCounted

const DEFAULT_ROOT_PATH: String = FinalizedMLChipStore.DEFAULT_ROOT_PATH
const MANIFEST_FILE_NAME: String = FinalizedMLChipStore.MANIFEST_FILE_NAME
const CHECKPOINT_FILE_NAME: String = FinalizedMLChipStore.CHECKPOINT_FILE_NAME
const CHIP_FILE_NAME: String = FinalizedMLChipStore.CHIP_FILE_NAME
const NEXT_VERSION_FILE_NAME: String = FinalizedMLChipStore.NEXT_VERSION_FILE_NAME
const SCHEMA_VERSION: int = FinalizedMLChipStore.SCHEMA_VERSION
const ARTIFACT_TYPE: String = FinalizedMLChipStore.ARTIFACT_TYPE
const ROOT_PROJECT_SETTING: String = FinalizedMLChipStore.ROOT_PROJECT_SETTING

var root_path: String
var last_error: String = ""


func _init(custom_root_path: String = "") -> void:
	root_path = (
		custom_root_path.strip_edges()
		if not custom_root_path.strip_edges().is_empty()
		else configured_root_path()
	).trim_suffix("/")


static func configured_root_path() -> String:
	return FinalizedMLChipStore.configured_root_path()


func finalize_drone_model(
	model_name: String,
	checkpoint: Dictionary,
	source_metadata: Dictionary = {}
) -> Dictionary:
	last_error = ""
	var inspection: Dictionary = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	if not bool(inspection.get("compatible", false)):
		last_error = str(inspection.get(
			"compatibility_text",
			"The selected policy is not a compatible gameplay drone model."
		))
		return {}
	if DroneTrainingAlgorithmCatalog.create_runtime_model(checkpoint) == null:
		last_error = "The selected checkpoint could not create a deterministic runtime model."
		return {}
	var body_interface: Dictionary = SafeVariant.dictionary_copy(
		checkpoint.get("body_interface", {})
	)
	var body_signature: String = str(body_interface.get("contract_signature", "")).strip_edges()
	var descriptor: Dictionary = DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(checkpoint)
	var algorithm_id: String = str(descriptor.get("id", "")).strip_edges()
	if body_signature.is_empty() or algorithm_id.is_empty():
		last_error = "The selected policy has no finalized body or algorithm identity."
		return {}

	var clean_name: String = model_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Finalized Drone Model"
	var model_key: String = TrainingFileIO.storage_key(clean_name, "drone-model")
	var family_path: String = root_path.path_join(model_key)
	var version: int = TrainingFileIO.next_version_directory_number(
		family_path,
		NEXT_VERSION_FILE_NAME
	)
	var version_name: String = "v%04d" % version
	var artifact_id: String = "%s/%s" % [model_key, version_name]
	var artifact_path: String = family_path.path_join(version_name)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_path)) != OK:
		last_error = "Could not create the finalized-model folder."
		return {}

	# Gameplay inference needs the immutable network/body/config contract, not replay buffers,
	# optimizer history, pending candidates, or a duplicate Best network inside training metadata.
	var exported_checkpoint: Dictionary = _runtime_checkpoint(checkpoint)
	exported_checkpoint["game_export"] = {
		"schema_version": SCHEMA_VERSION,
		"artifact_id": artifact_id,
		"artifact_type": ARTIFACT_TYPE,
		"model_name": clean_name,
		"body_interface_signature": body_signature,
		"training_algorithm_id": algorithm_id,
		"source": _safe_source_metadata(source_metadata),
	}
	var checkpoint_path: String = artifact_path.path_join(CHECKPOINT_FILE_NAME)
	if not TrainingFileIO.write_json_dictionary_atomic(checkpoint_path, exported_checkpoint):
		return _fail_and_remove(artifact_path, "Could not write the finalized model checkpoint.")
	var checkpoint_sha256: String = FileAccess.get_sha256(checkpoint_path)
	if checkpoint_sha256.is_empty():
		return _fail_and_remove(artifact_path, "Could not verify the finalized model checkpoint.")

	var manifest_path: String = artifact_path.path_join(MANIFEST_FILE_NAME)
	var chip_path: String = artifact_path.path_join(CHIP_FILE_NAME)
	var chip: DroneAIChipDefinition = _make_chip(
		clean_name,
		artifact_id,
		checkpoint_path,
		manifest_path,
		body_signature,
		algorithm_id
	)
	if ResourceSaver.save(
		chip,
		chip_path,
		ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
	) != OK:
		return _fail_and_remove(artifact_path, "Could not write the gameplay AI chip resource.")

	var created_unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var manifest: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"artifact_type": ARTIFACT_TYPE,
		"artifact_id": artifact_id,
		"model_name": clean_name,
		"model_key": model_key,
		"version": version,
		"version_name": version_name,
		"created_unix_ms": created_unix_ms,
		"created_utc": Time.get_datetime_string_from_system(true, false) + "Z",
		"body_interface_signature": body_signature,
		"training_algorithm_id": algorithm_id,
		"checkpoint_file": CHECKPOINT_FILE_NAME,
		"checkpoint_sha256": checkpoint_sha256,
		"chip_file": CHIP_FILE_NAME,
		"source": _safe_source_metadata(source_metadata),
	}
	if not TrainingFileIO.write_json_dictionary_atomic(manifest_path, manifest):
		return _fail_and_remove(artifact_path, "Could not write the finalized model manifest.")

	var stored_chip: DroneAIChipDefinition = ResourceLoader.load(
		chip_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as DroneAIChipDefinition
	if stored_chip == null or load_checkpoint(stored_chip).is_empty():
		var verification_error: String = last_error
		return _fail_and_remove(
			artifact_path,
			"The finalized model failed its read-back check%s" % (
				": %s" % verification_error if not verification_error.is_empty() else "."
			)
		)
	if not TrainingFileIO.preserve_next_version_floor(
		family_path,
		NEXT_VERSION_FILE_NAME,
		version + 1
	):
		return _fail_and_remove(
			artifact_path,
			"Could not preserve the finalized-model version sequence."
		)
	last_error = ""
	manifest["storage_path"] = artifact_path
	manifest["manifest_path"] = manifest_path
	manifest["checkpoint_path"] = checkpoint_path
	manifest["chip_path"] = chip_path
	return manifest


func load_checkpoint(chip: DroneAIChipDefinition) -> Dictionary:
	var chip_store: FinalizedMLChipStore = FinalizedMLChipStore.new(root_path)
	var checkpoint: Dictionary = chip_store.load_checkpoint(chip)
	if checkpoint.is_empty():
		last_error = chip_store.last_error
		return {}
	var inspection: Dictionary = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	if (
		not bool(inspection.get("compatible", false))
		or str(DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(checkpoint).get("id", ""))
		!= chip.finalized_algorithm_id
	):
		last_error = "The finalized checkpoint no longer matches its chip manifest."
		return {}
	return checkpoint


func runtime_model_for_chip(
	chip: DroneAIChipDefinition,
	expected_body_signature: String
) -> DroneMLModel:
	var checkpoint: Dictionary = load_checkpoint(chip)
	if checkpoint.is_empty():
		return null
	if chip.finalized_body_signature != expected_body_signature:
		last_error = "This model was trained for a different drone body contract."
		return null
	var model: DroneMLModel = DroneTrainingAlgorithmCatalog.create_runtime_model(checkpoint)
	if model == null:
		last_error = "The finalized weights could not create a deterministic runtime model."
	return model


func discover_chips() -> Array[DroneAIChipDefinition]:
	var result: Array[DroneAIChipDefinition] = []
	var chip_store: FinalizedMLChipStore = FinalizedMLChipStore.new(root_path)
	for chip: DroneAIChipDefinition in chip_store.discover_chips():
		if not load_checkpoint(chip).is_empty():
			result.append(chip)
	last_error = ""
	return result


static func public_chip_snapshot(chip: DroneAIChipDefinition) -> Dictionary:
	return FinalizedMLChipStore.public_chip_snapshot(chip)


static func chip_from_public_snapshot(snapshot: Dictionary) -> DroneAIChipDefinition:
	return FinalizedMLChipStore.chip_from_public_snapshot(snapshot)


func _make_chip(
	model_name: String,
	artifact_id: String,
	checkpoint_path: String,
	manifest_path: String,
	body_signature: String,
	algorithm_id: String
) -> DroneAIChipDefinition:
	var chip: DroneAIChipDefinition = DroneAIChipDefinition.new()
	chip.display_name = "%s Model Chip" % model_name
	chip.quality = DronePartDefinition.Quality.INDUSTRIAL
	chip.visual_color = Color("6f5dff")
	chip.mass = 0.024
	chip.rated_voltage_v = 12.0
	chip.behavior_id = &"trained_ml_policy"
	chip.behavior_description = "Server-authoritative deterministic policy exported from the ML Training Room."
	chip.processing_priority = 100
	chip.response_time = 0.05
	chip.processing_efficiency = 0.9
	chip.minimum_operating_power_ratio = 0.35
	chip.idle_power_draw = 1.5
	chip.active_power_draw = 6.0
	chip.damaging_spike_threshold = 1.4
	chip.surge_fragility = 0.65
	chip.finalized_model_id = artifact_id
	chip.finalized_model_path = checkpoint_path
	chip.finalized_manifest_path = manifest_path
	chip.finalized_body_signature = body_signature
	chip.finalized_algorithm_id = algorithm_id
	return chip


func _safe_source_metadata(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in [
		"group_id",
		"group_name",
		"policy_scope",
		"policy_update",
		"selection_score",
	]:
		var value: Variant = source.get(key)
		if value is String or value is int or value is float or value is bool:
			result[key] = value
	return result


func _runtime_checkpoint(checkpoint: Dictionary) -> Dictionary:
	var result: Dictionary = checkpoint.duplicate(true)
	var source_training: Dictionary = SafeVariant.dictionary_copy(
		checkpoint.get("training", {})
	)
	var runtime_training: Dictionary = {}
	for key: String in [
		"update_count",
		"environment_steps",
		"completed_episodes",
		"best_episode_mean_reward",
		"has_best_episode",
	]:
		var value: Variant = source_training.get(key)
		if value is int or value is float or value is bool:
			runtime_training[key] = value
	result["training"] = runtime_training
	for training_only_key: String in [
		"training_state",
		"training_environment",
		"current_room_evaluation_contract",
		"best_evaluation_contract",
	]:
		result.erase(training_only_key)
	return result


func _fail_and_remove(path: String, message: String) -> Dictionary:
	last_error = message
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute_path):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_path)
	return {}
