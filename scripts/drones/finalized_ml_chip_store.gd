class_name FinalizedMLChipStore
extends RefCounted

const DEFAULT_ROOT_PATH: String = "user://finalized_ml_models"
const ROOT_PROJECT_SETTING: String = "scavange/ml/finalized_model_root"
const MANIFEST_FILE_NAME: String = "manifest.json"
const CHECKPOINT_FILE_NAME: String = "checkpoint.json"
const CHIP_FILE_NAME: String = "chip.tres"
const NEXT_VERSION_FILE_NAME: String = "next-version.txt"
const SCHEMA_VERSION: int = 1
const ARTIFACT_TYPE: String = "finalized_drone_ml_chip"
const PUBLIC_SNAPSHOT_SCHEMA_VERSION: int = 1

var root_path: String
var last_error: String = ""


func _init(custom_root_path: String = "") -> void:
	root_path = (
		custom_root_path.strip_edges()
		if not custom_root_path.strip_edges().is_empty()
		else configured_root_path()
	).trim_suffix("/")


static func configured_root_path() -> String:
	var configured: String = str(ProjectSettings.get_setting(
		ROOT_PROJECT_SETTING,
		DEFAULT_ROOT_PATH
	)).strip_edges().trim_suffix("/")
	return configured if not configured.is_empty() else DEFAULT_ROOT_PATH


func load_checkpoint(chip: DroneAIChipDefinition) -> Dictionary:
	last_error = ""
	if chip == null or not chip.has_finalized_model_contract():
		last_error = "This AI chip has no finalized model contract."
		return {}
	if not _path_is_inside_root(chip.finalized_manifest_path):
		last_error = "The finalized model manifest is outside the trusted export folder."
		return {}
	var artifact_path: String = chip.finalized_manifest_path.get_base_dir()
	var expected_checkpoint_path: String = artifact_path.path_join(CHECKPOINT_FILE_NAME)
	if (
		chip.finalized_manifest_path != artifact_path.path_join(MANIFEST_FILE_NAME)
		or chip.finalized_model_path != expected_checkpoint_path
	):
		last_error = "The AI chip points at an unexpected model file."
		return {}
	var manifest: Dictionary = _read_json_dictionary(chip.finalized_manifest_path)
	if not _manifest_matches_chip(manifest, chip):
		return {}
	var expected_hash: String = str(manifest.get("checkpoint_sha256", "")).strip_edges()
	var actual_hash: String = FileAccess.get_sha256(expected_checkpoint_path)
	if expected_hash.is_empty() or actual_hash.is_empty() or actual_hash != expected_hash:
		last_error = "The finalized model checkpoint failed its SHA-256 integrity check."
		return {}
	var checkpoint: Dictionary = _read_json_dictionary(expected_checkpoint_path)
	var checkpoint_body: Dictionary = SafeVariant.dictionary_copy(
		checkpoint.get("body_interface", {})
	)
	var game_export: Dictionary = SafeVariant.dictionary_copy(checkpoint.get("game_export", {}))
	if (
		checkpoint.is_empty()
		or str(checkpoint_body.get("contract_signature", "")) != chip.finalized_body_signature
		or str(checkpoint.get("training_algorithm_id", "")) != chip.finalized_algorithm_id
		or str(game_export.get("artifact_id", "")) != chip.finalized_model_id
		or str(game_export.get("artifact_type", "")) != ARTIFACT_TYPE
	):
		last_error = "The finalized checkpoint no longer matches its chip manifest."
		return {}
	return checkpoint


func discover_chips(validate_checkpoints: bool = true) -> Array[DroneAIChipDefinition]:
	var result: Array[DroneAIChipDefinition] = []
	for chip_path: String in ResourcePathDiscovery.collect(root_path, ["tres"]):
		if chip_path.get_file() != CHIP_FILE_NAME:
			continue
		var chip: DroneAIChipDefinition = ResourceLoader.load(
			chip_path,
			"",
			ResourceLoader.CACHE_MODE_REUSE
		) as DroneAIChipDefinition
		if (
			chip != null
			and chip.has_finalized_model_contract()
			and (not validate_checkpoints or not load_checkpoint(chip).is_empty())
		):
			result.append(chip)
	result.sort_custom(func(left: DroneAIChipDefinition, right: DroneAIChipDefinition) -> bool:
		return left.display_name.naturalnocasecmp_to(right.display_name) < 0
	)
	last_error = ""
	return result


static func public_chip_snapshot(chip: DroneAIChipDefinition) -> Dictionary:
	if chip == null or not chip.has_finalized_model_contract():
		return {}
	return {
		"schema_version": PUBLIC_SNAPSHOT_SCHEMA_VERSION,
		"display_name": chip.display_name,
		"quality": int(chip.quality),
		"visual_color": chip.visual_color,
		"mass": chip.get_mass(),
		"rated_voltage_v": chip.rated_voltage_v,
		"body_size": chip.body_size,
		"behavior_id": str(chip.behavior_id),
		"behavior_description": chip.behavior_description,
		"finalized_model_id": chip.finalized_model_id,
		"finalized_body_signature": chip.finalized_body_signature,
		"finalized_algorithm_id": chip.finalized_algorithm_id,
	}


static func chip_from_public_snapshot(snapshot: Dictionary) -> DroneAIChipDefinition:
	if (
		SafeVariant.integral_int_or(snapshot.get("schema_version", 0), -1)
		!= PUBLIC_SNAPSHOT_SCHEMA_VERSION
		or str(snapshot.get("behavior_id", "")) != "trained_ml_policy"
		or str(snapshot.get("finalized_model_id", "")).strip_edges().is_empty()
		or str(snapshot.get("finalized_body_signature", "")).strip_edges().is_empty()
		or str(snapshot.get("finalized_algorithm_id", "")).strip_edges().is_empty()
	):
		return null
	var chip: DroneAIChipDefinition = DroneAIChipDefinition.new()
	chip.display_name = str(snapshot.get("display_name", "Finalized Model Chip")).strip_edges()
	chip.quality = clampi(
		SafeVariant.integral_int_or(snapshot.get("quality", DronePartDefinition.Quality.INDUSTRIAL), DronePartDefinition.Quality.INDUSTRIAL),
		DronePartDefinition.Quality.SCRAP,
		DronePartDefinition.Quality.INDUSTRIAL
	)
	chip.visual_color = SafeVariant.color_strict_or(
		snapshot.get("visual_color"),
		Color("6f5dff")
	)
	chip.mass = maxf(SafeVariant.finite_float_or(snapshot.get("mass", 0.024), 0.024), 0.001)
	chip.rated_voltage_v = maxf(
		SafeVariant.finite_float_or(snapshot.get("rated_voltage_v", 12.0), 12.0),
		0.0
	)
	var safe_body_size: Vector3 = SafeVariant.vector3_strict_or(
		snapshot.get("body_size"),
		Vector3(0.2, 0.035, 0.15)
	)
	chip.body_size = Vector3(
		clampf(absf(safe_body_size.x), 0.005, 1.0),
		clampf(absf(safe_body_size.y), 0.005, 1.0),
		clampf(absf(safe_body_size.z), 0.005, 1.0)
	)
	chip.behavior_id = &"trained_ml_policy"
	chip.behavior_description = str(snapshot.get("behavior_description", ""))
	chip.finalized_model_id = str(snapshot.get("finalized_model_id", ""))
	chip.finalized_body_signature = str(snapshot.get("finalized_body_signature", ""))
	chip.finalized_algorithm_id = str(snapshot.get("finalized_algorithm_id", ""))
	return chip


func _manifest_matches_chip(
	manifest: Dictionary,
	chip: DroneAIChipDefinition
) -> bool:
	if (
		SafeVariant.integral_int_or(manifest.get("schema_version", 0), -1) != SCHEMA_VERSION
		or str(manifest.get("artifact_type", "")) != ARTIFACT_TYPE
		or str(manifest.get("artifact_id", "")) != chip.finalized_model_id
		or str(manifest.get("body_interface_signature", "")) != chip.finalized_body_signature
		or str(manifest.get("training_algorithm_id", "")) != chip.finalized_algorithm_id
		or str(manifest.get("checkpoint_file", "")) != CHECKPOINT_FILE_NAME
		or str(manifest.get("chip_file", "")) != CHIP_FILE_NAME
	):
		last_error = "The finalized model manifest does not match its AI chip."
		return false
	return true


func _path_is_inside_root(path: String) -> bool:
	return (
		not root_path.is_empty()
		and not path.contains("..")
		and path.begins_with(root_path + "/")
	)


static func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
