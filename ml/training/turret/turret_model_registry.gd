class_name TurretModelRegistry
extends RefCounted

const DEFAULT_ROOT_PATH = "user://ml_turret_models"
const MANIFEST_FILE_NAME = "model.json"
const CHECKPOINT_FILE_NAME = "checkpoint.json"
const SCHEMA_VERSION = 1

#######################################################
# Separate model library for turret bodies. Drone and limb checkpoints cannot be selected
# for each other because their artifact/body contracts differ.
#######################################################

var root_path = DEFAULT_ROOT_PATH
var last_error = ""


func _init(custom_root_path: String = DEFAULT_ROOT_PATH) -> void:
	root_path = custom_root_path.trim_suffix("/")


func save_checkpoint(model_name: String, checkpoint: Dictionary) -> Dictionary:
	last_error = ""
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The checkpoint is not a compatible turret model."
		return {}
	var clean_name = model_name.strip_edges() if not model_name.strip_edges().is_empty() else "Turret Model"
	var model_key = _key(clean_name)
	var family_path = root_path.path_join(model_key)
	var version = _next_version(family_path)
	var version_name = "v%04d" % version
	var version_path = family_path.path_join(version_name)
	var directory_error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(version_path))
	if directory_error != OK:
		last_error = "Could not create the model folder."
		return {}
	if not _write_json(version_path.path_join(CHECKPOINT_FILE_NAME), checkpoint):
		last_error = "Could not write the model checkpoint."
		_remove_directory(ProjectSettings.globalize_path(version_path))
		return {}
	var now = int(Time.get_unix_time_from_system() * 1000.0)
	var record = {
		"schema_version": SCHEMA_VERSION,
		"artifact_type": "trained_turret_policy",
		"body_profile_id": TurretPhysicalBody3D.BODY_PROFILE_ID,
		"model_name": clean_name,
		"model_key": model_key,
		"version": version,
		"version_name": version_name,
		"version_id": "%s/%s" % [model_key, version_name],
		"created_unix_ms": now,
		"updated_unix_ms": now,
		"algorithm": str(checkpoint.get("algorithm", "")),
		"hardware_signature": str(checkpoint.get("hardware_signature", "")),
		"checkpoint_file": CHECKPOINT_FILE_NAME,
		"checkpoint_revision": 1,
	}
	if not _write_json(version_path.path_join(MANIFEST_FILE_NAME), record):
		last_error = "Could not write the model manifest."
		_remove_directory(ProjectSettings.globalize_path(version_path))
		return {}
	record["storage_path"] = version_path
	var stored_record = _resolve(record)
	var stored_checkpoint = TrainingFileIO.read_json_dictionary(
		version_path.path_join(CHECKPOINT_FILE_NAME)
	)
	if stored_record.is_empty() or not _is_compatible_checkpoint(stored_checkpoint):
		last_error = "The model files were written but failed the save verification check."
		_remove_directory(ProjectSettings.globalize_path(version_path))
		return {}
	return stored_record


func overwrite_checkpoint(record_or_id: Variant, checkpoint: Dictionary) -> Dictionary:
	last_error = ""
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The replacement checkpoint is not a compatible turret model."
		return {}
	var record = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The rolling turret model version no longer exists."
		return {}
	if (
		str(record.get("algorithm", "")) != str(checkpoint.get("algorithm", ""))
		or str(record.get("hardware_signature", ""))
		!= str(checkpoint.get("hardware_signature", ""))
	):
		last_error = "The rolling version belongs to a different turret loadout or learning algorithm."
		return {}
	var version_path = str(record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The rolling turret model has no storage directory."
		return {}
	var checkpoint_path = version_path.path_join(str(record.get(
		"checkpoint_file",
		CHECKPOINT_FILE_NAME
	)))
	var previous_checkpoint = TrainingFileIO.read_json_dictionary(checkpoint_path)
	if previous_checkpoint.is_empty() or not _is_compatible_checkpoint(previous_checkpoint):
		last_error = "The rolling turret checkpoint could not be staged for rollback."
		return {}
	if not _write_json(checkpoint_path, checkpoint):
		last_error = "Could not overwrite the rolling turret checkpoint."
		return {}
	record["updated_unix_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	record["algorithm"] = str(checkpoint.get("algorithm", ""))
	record["hardware_signature"] = str(checkpoint.get("hardware_signature", ""))
	record["checkpoint_revision"] = maxi(RLTrainingMath.finite_int_or(record.get("checkpoint_revision", 1), 1), 1) + 1
	if not _write_json(version_path.path_join(MANIFEST_FILE_NAME), record):
		if _write_json(checkpoint_path, previous_checkpoint):
			last_error = "Could not update the rolling turret model manifest; the previous checkpoint was restored."
		else:
			last_error = "Rolling turret save failed and checkpoint rollback was incomplete; inspect this model version before using it."
		return {}
	var stored_record = _resolve(record)
	var stored_checkpoint = TrainingFileIO.read_json_dictionary(checkpoint_path)
	if stored_record.is_empty() or not _is_compatible_checkpoint(stored_checkpoint):
		last_error = "The rolling model was written but failed the save verification check."
		return {}
	stored_record["overwritten_existing"] = true
	return stored_record


func list_models() -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	var root = DirAccess.open(root_path)
	if root == null:
		return result
	root.list_dir_begin()
	var family = root.get_next()
	while not family.is_empty():
		if root.current_is_dir():
			_collect_family(root_path.path_join(family), result)
		family = root.get_next()
	root.list_dir_end()
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return RLTrainingMath.finite_int_or(left.get("updated_unix_ms", 0), 0) > RLTrainingMath.finite_int_or(right.get("updated_unix_ms", 0), 0)
	)
	return result


func get_version(version_id: String) -> Dictionary:
	return _resolve(version_id)


func load_checkpoint(record_or_id: Variant) -> Dictionary:
	last_error = ""
	var record = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The selected turret model no longer exists."
		return {}
	var checkpoint = TrainingFileIO.read_json_dictionary(str(record["storage_path"]).path_join(str(record.get("checkpoint_file", CHECKPOINT_FILE_NAME))))
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The selected file is not a compatible turret checkpoint."
		return {}
	return checkpoint


func delete_model(record_or_id: Variant) -> bool:
	last_error = ""
	var record = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The selected turret model no longer exists."
		return false
	return _remove_directory(ProjectSettings.globalize_path(str(record["storage_path"])))


func display_name(record: Dictionary) -> String:
	return "%s %s" % [str(record.get("model_name", "Turret Model")), str(record.get("version_name", "v????"))]


func globalized_root_path() -> String:
	return ProjectSettings.globalize_path(root_path)


func _resolve(record_or_id: Variant) -> Dictionary:
	var version_id = (
		str((record_or_id as Dictionary).get("version_id", ""))
		if record_or_id is Dictionary
		else str(record_or_id)
	)
	var parts = version_id.split("/", false)
	if parts.size() != 2:
		return {}
	var model_key = str(parts[0])
	var version_name = str(parts[1])
	var version_number_text = version_name.trim_prefix("v")
	if (
		model_key.is_empty()
		or _key(model_key) != model_key
		or not version_name.begins_with("v")
		or not version_number_text.is_valid_int()
		or version_number_text.to_int() <= 0
	):
		return {}
	var version_path = root_path.path_join(model_key).path_join(version_name)
	var record = TrainingFileIO.read_json_dictionary(version_path.path_join(MANIFEST_FILE_NAME))
	if (
		str(record.get("version_id", "")) != version_id
		or str(record.get("artifact_type", "")) != "trained_turret_policy"
	):
		return {}
	record["storage_path"] = version_path
	return record


func _collect_family(path: String, result: Array[Dictionary]) -> void:
	var directory = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			var version_path = path.path_join(entry)
			var record = TrainingFileIO.read_json_dictionary(version_path.path_join(MANIFEST_FILE_NAME))
			if not record.is_empty() and str(record.get("artifact_type", "")) == "trained_turret_policy":
				record["storage_path"] = version_path
				result.append(record)
		entry = directory.get_next()
	directory.list_dir_end()


func _is_compatible_checkpoint(checkpoint: Dictionary) -> bool:
	var metadata_matches: bool = (
		RLTrainingMath.finite_int_or(checkpoint.get("schema_version", 0), -1) == TurretPPOTrainer.CHECKPOINT_SCHEMA_VERSION
		and str(checkpoint.get("artifact_type", "")) == "trained_turret_policy"
		and str(checkpoint.get("algorithm", "")) == TurretPPOTrainer.ALGORITHM_ID
		and str(checkpoint.get("body_profile_id", "")) == TurretPhysicalBody3D.BODY_PROFILE_ID
		and RLTrainingMath.finite_int_or(checkpoint.get("observation_schema_version", 0), -1) == TurretMLObservation.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(checkpoint.get("action_schema_version", 0), -1) == TurretMLAction.SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(checkpoint.get("action_count", 0), -1) == TurretMLAction.ACTION_COUNT
		and RLTrainingMath.finite_int_or(checkpoint.get("feature_count", 0), -1) == TurretMLFeatureEncoder.FEATURE_COUNT
		and checkpoint.get("network", {}) is Dictionary
	)
	if not metadata_matches:
		return false
	var runtime_model: TurretPPOModel = TurretPPOModel.new()
	return runtime_model.load_checkpoint(
		checkpoint,
		str(checkpoint.get("hardware_signature", ""))
	)


func _next_version(path: String) -> int:
	var highest = 0
	var directory = DirAccess.open(path)
	if directory != null:
		directory.list_dir_begin()
		var entry = directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir() and entry.begins_with("v"):
				highest = maxi(highest, entry.trim_prefix("v").to_int())
			entry = directory.get_next()
		directory.list_dir_end()
	return highest + 1


func _key(value: String) -> String:
	var result = ""
	var separator = false
	for index in range(value.length()):
		var character = value.substr(index, 1).to_lower()
		if "abcdefghijklmnopqrstuvwxyz0123456789".contains(character):
			result += character
			separator = false
		elif not separator and not result.is_empty():
			result += "-"
			separator = true
	return result.trim_suffix("-") if not result.trim_suffix("-").is_empty() else "turret-model"


func _write_json(path: String, value: Dictionary) -> bool:
	var stored = value.duplicate(true)
	stored.erase("storage_path")
	return TrainingFileIO.write_text_atomic(path, JSON.stringify(stored, "\t", true, true))


func _remove_directory(absolute_path: String) -> bool:
	var directory = DirAccess.open(absolute_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child = absolute_path.path_join(entry)
			if directory.current_is_dir():
				if not _remove_directory(child):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute_path) == OK
