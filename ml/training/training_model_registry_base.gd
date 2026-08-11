class_name TrainingModelRegistryBase
extends RefCounted

const MANIFEST_FILE_NAME: String = "model.json"
const CHECKPOINT_FILE_NAME: String = "checkpoint.json"
const NEXT_VERSION_FILE_NAME: String = "next_version.txt"
const SCHEMA_VERSION: int = 1

#######################################################
# Shared immutable-version model-library storage. Body-family registries provide only artifact
# metadata and checkpoint compatibility; filesystem layout, monotonic versioning, rollback and
# manifest verification live here so those safety rules cannot drift between model families.
#######################################################

var root_path: String = ""
var last_error: String = ""


func _init(custom_root_path: String = "") -> void:
	root_path = custom_root_path.trim_suffix("/")


func save_checkpoint(model_name: String, checkpoint: Dictionary) -> Dictionary:
	last_error = ""
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The checkpoint is not a compatible %s model." % _body_label()
		return {}
	var stripped_name: String = model_name.strip_edges()
	var clean_name: String = stripped_name if not stripped_name.is_empty() else _default_model_name()
	var model_key: String = _key(clean_name)
	var family_path: String = root_path.path_join(model_key)
	var version: int = _next_version(family_path)
	var version_name: String = "v%04d" % version
	var version_path: String = family_path.path_join(version_name)
	var directory_error: int = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create the model folder."
		return {}
	if not TrainingFileIO.preserve_next_version_floor(
		family_path,
		NEXT_VERSION_FILE_NAME,
		version + 1
	):
		last_error = "Could not preserve the %s model version sequence." % _body_label()
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		return {}
	if not _write_json(version_path.path_join(CHECKPOINT_FILE_NAME), checkpoint):
		last_error = "Could not write the model checkpoint."
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		return {}
	var now: int = int(Time.get_unix_time_from_system() * 1000.0)
	var record: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"artifact_type": _artifact_type(),
		"body_profile_id": _body_profile_id(),
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
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		return {}
	record["storage_path"] = version_path
	var stored_record: Dictionary = _resolve(record)
	var stored_checkpoint: Dictionary = TrainingFileIO.read_json_dictionary(
		version_path.path_join(CHECKPOINT_FILE_NAME)
	)
	if stored_record.is_empty() or not _is_compatible_checkpoint(stored_checkpoint):
		last_error = "The model files were written but failed the save verification check."
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		return {}
	return stored_record


func overwrite_checkpoint(record_or_id: Variant, checkpoint: Dictionary) -> Dictionary:
	last_error = ""
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The replacement checkpoint is not a compatible %s model." % _body_label()
		return {}
	var record: Dictionary = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The rolling %s model version no longer exists." % _body_label()
		return {}
	if (
		str(record.get("algorithm", "")) != str(checkpoint.get("algorithm", ""))
		or str(record.get("hardware_signature", ""))
		!= str(checkpoint.get("hardware_signature", ""))
	):
		last_error = "The rolling version belongs to a different body or learning algorithm."
		return {}
	var version_path: String = str(record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The rolling %s model has no storage directory." % _body_label()
		return {}
	var checkpoint_path: String = version_path.path_join(str(record.get(
		"checkpoint_file",
		CHECKPOINT_FILE_NAME
	)))
	var previous_checkpoint: Dictionary = TrainingFileIO.read_json_dictionary(checkpoint_path)
	if previous_checkpoint.is_empty() or not _is_compatible_checkpoint(previous_checkpoint):
		last_error = "The rolling %s checkpoint could not be staged for rollback." % _body_label()
		return {}
	if not _write_json(checkpoint_path, checkpoint):
		last_error = "Could not overwrite the rolling %s checkpoint." % _body_label()
		return {}
	record["updated_unix_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	record["algorithm"] = str(checkpoint.get("algorithm", ""))
	record["hardware_signature"] = str(checkpoint.get("hardware_signature", ""))
	record["checkpoint_revision"] = maxi(
		RLTrainingMath.finite_int_or(record.get("checkpoint_revision", 1), 1),
		1
	) + 1
	if not _write_json(version_path.path_join(MANIFEST_FILE_NAME), record):
		if _write_json(checkpoint_path, previous_checkpoint):
			last_error = (
				"Could not update the rolling %s model manifest; the previous checkpoint was restored."
				% _body_label()
			)
		else:
			last_error = (
				"Rolling %s save failed and checkpoint rollback was incomplete; inspect this model version before using it."
				% _body_label()
			)
		return {}
	var stored_record: Dictionary = _resolve(record)
	var stored_checkpoint: Dictionary = TrainingFileIO.read_json_dictionary(checkpoint_path)
	if stored_record.is_empty() or not _is_compatible_checkpoint(stored_checkpoint):
		last_error = "The rolling model was written but failed the save verification check."
		return {}
	stored_record["overwritten_existing"] = true
	return stored_record


func list_models() -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	var root: DirAccess = DirAccess.open(root_path)
	if root == null:
		return result
	root.list_dir_begin()
	var family: String = root.get_next()
	while not family.is_empty():
		if root.current_is_dir():
			_collect_family(root_path.path_join(family), result)
		family = root.get_next()
	root.list_dir_end()
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (
			RLTrainingMath.finite_int_or(left.get("updated_unix_ms", 0), 0)
			> RLTrainingMath.finite_int_or(right.get("updated_unix_ms", 0), 0)
		)
	)
	return result


func get_version(version_id: String) -> Dictionary:
	return _resolve(version_id)


func load_checkpoint(record_or_id: Variant) -> Dictionary:
	last_error = ""
	var record: Dictionary = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The selected %s model no longer exists." % _body_label()
		return {}
	var checkpoint: Dictionary = TrainingFileIO.read_json_dictionary(
		str(record["storage_path"]).path_join(
			str(record.get("checkpoint_file", CHECKPOINT_FILE_NAME))
		)
	)
	if not _is_compatible_checkpoint(checkpoint):
		last_error = "The selected file is not a compatible %s checkpoint." % _body_label()
		return {}
	return checkpoint


func delete_model(record_or_id: Variant) -> bool:
	last_error = ""
	var record: Dictionary = _resolve(record_or_id)
	if record.is_empty():
		last_error = "The selected %s model no longer exists." % _body_label()
		return false
	var removed: bool = TrainingFileIO.remove_directory_recursive_absolute(
		ProjectSettings.globalize_path(str(record["storage_path"]))
	)
	if not removed:
		last_error = "Could not delete the selected %s model version." % _body_label()
	return removed


func display_name(record: Dictionary) -> String:
	return "%s %s" % [
		str(record.get("model_name", _default_model_name())),
		str(record.get("version_name", "v????")),
	]


func globalized_root_path() -> String:
	return ProjectSettings.globalize_path(root_path)


func _resolve(record_or_id: Variant) -> Dictionary:
	var version_id: String = (
		str((record_or_id as Dictionary).get("version_id", ""))
		if record_or_id is Dictionary
		else str(record_or_id)
	)
	var parts: PackedStringArray = version_id.split("/", false)
	if parts.size() != 2:
		return {}
	var model_key: String = str(parts[0])
	var version_name: String = str(parts[1])
	var version_number_text: String = version_name.trim_prefix("v")
	if (
		model_key.is_empty()
		or _key(model_key) != model_key
		or not version_name.begins_with("v")
		or not version_number_text.is_valid_int()
		or version_number_text.to_int() <= 0
	):
		return {}
	var version_path: String = root_path.path_join(model_key).path_join(version_name)
	var record: Dictionary = TrainingFileIO.read_json_dictionary(
		version_path.path_join(MANIFEST_FILE_NAME)
	)
	if (
		str(record.get("version_id", "")) != version_id
		or str(record.get("model_key", "")) != model_key
		or str(record.get("version_name", "")) != version_name
		or RLTrainingMath.finite_int_or(record.get("version", 0), -1)
		!= version_number_text.to_int()
		or str(record.get("artifact_type", "")) != _artifact_type()
		or str(record.get("body_profile_id", "")) != _body_profile_id()
		or str(record.get("checkpoint_file", CHECKPOINT_FILE_NAME))
		!= CHECKPOINT_FILE_NAME
	):
		return {}
	record["storage_path"] = version_path
	return record


func _collect_family(path: String, result: Array[Dictionary]) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			var version_path: String = path.path_join(entry)
			var record: Dictionary = TrainingFileIO.read_json_dictionary(
				version_path.path_join(MANIFEST_FILE_NAME)
			)
			var resolved: Dictionary = _resolve(record) if not record.is_empty() else {}
			if str(resolved.get("storage_path", "")) == version_path:
				result.append(resolved)
		entry = directory.get_next()
	directory.list_dir_end()


func _next_version(path: String) -> int:
	return TrainingFileIO.next_version_directory_number(path, NEXT_VERSION_FILE_NAME)


func _key(value: String) -> String:
	return TrainingFileIO.storage_key(value, _storage_key_fallback())


func _write_json(path: String, value: Dictionary) -> bool:
	var stored: Dictionary = value.duplicate(true)
	stored.erase("storage_path")
	return TrainingFileIO.write_text_atomic(
		path,
		JSON.stringify(stored, "\t", true, true)
	)


func _artifact_type() -> String:
	return ""


func _body_profile_id() -> String:
	return ""


func _default_model_name() -> String:
	return "Model"


func _storage_key_fallback() -> String:
	return "model"


func _body_label() -> String:
	return "training"


func _is_compatible_checkpoint(_checkpoint: Dictionary) -> bool:
	return false
