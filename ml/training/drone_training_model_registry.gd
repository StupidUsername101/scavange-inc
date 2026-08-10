class_name DroneTrainingModelRegistry
extends RefCounted

const DEFAULT_ROOT_PATH = "user://ml_models"
const MANIFEST_FILE_NAME = "model.json"
const PPO_CHECKPOINT_FILE_NAME = "checkpoint.json"
const RUN_DIRECTORY_NAME = "runs"
const NEXT_VERSION_FILE_NAME = "next-version.txt"
const USAGE_FILE_NAME = "usage.json"
const SCHEMA_VERSION = 1
const QUAD_PROPELLER_COUNT = 4

#######################################################
# Persists numbered training-model versions and separate per-episode result artifacts. Saves are
# append-only by default. A live worker group may explicitly own one rolling version and update that
# exact checkpoint in place to avoid version-folder spam; immutable mode remains the default.
#######################################################

var root_path: String
var last_error = ""
var run_sequence = 0


func _init(custom_root_path = DEFAULT_ROOT_PATH) -> void:
	root_path = str(custom_root_path).trim_suffix("/")


func ensure_initial_version(default_weights: Dictionary) -> Dictionary:
	for version in list_versions():
		if str(version.get("model_key", "")) == "model-x":
			return version
	return save_version("Model X", default_weights)


func save_version(
	model_name: String,
	weights: Dictionary,
	parent_version_id = ""
) -> Dictionary:
	last_error = ""
	var clean_name = model_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Model X"
	var model_key = _model_key(clean_name)
	var model_path = root_path.path_join(model_key)
	var version_number = _next_version_number(model_path)
	var version_name = "v%04d" % version_number
	var version_path = model_path.path_join(version_name)
	var manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	while FileAccess.file_exists(manifest_path):
		version_number += 1
		version_name = "v%04d" % version_number
		version_path = model_path.path_join(version_name)
		manifest_path = version_path.path_join(MANIFEST_FILE_NAME)

	var directory_error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create model version directory (%s)." % error_string(directory_error)
		return {}

	var created_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var created_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	var record = {
		"schema_version": SCHEMA_VERSION,
		"model_name": clean_name,
		"model_key": model_key,
		"version": version_number,
		"version_name": version_name,
		"version_id": "%s/%s" % [model_key, version_name],
		"artifact_type": "diagnostic_quadrotor_policy",
		"propeller_count": QUAD_PROPELLER_COUNT,
		"created_unix_ms": created_unix_ms,
		"created_utc": created_utc,
		"training_updated_unix_ms": 0,
		"training_updated_utc": "",
		"parent_version_id": parent_version_id,
		"weights": weights.duplicate(true),
	}
	if not _write_json_file(manifest_path, record):
		last_error = "Could not write model version atomically (%s)." % error_string(
			FileAccess.get_open_error()
		)
		return {}
	record["storage_path"] = version_path
	return record


func save_training_checkpoint(
	model_name: String,
	checkpoint: Dictionary,
	parent_version_id = "",
	checkpoint_kind = "current"
) -> Dictionary:
	last_error = ""
	var algorithm_descriptor = DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(
		checkpoint
	)
	var training_value: Variant = checkpoint.get("training", {})
	var training_environment_value: Variant = checkpoint.get("training_environment", {})
	var checkpoint_inspection: Dictionary = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	if (
		algorithm_descriptor.is_empty()
		or not bool(checkpoint_inspection.get("compatible", false))
		or not (training_value is Dictionary)
		or not (training_environment_value is Dictionary)
		or not (checkpoint.get("network", {}) is Dictionary)
		or DroneTrainingAlgorithmCatalog.create_runtime_model(checkpoint) == null
	):
		last_error = "The training checkpoint is incomplete, unknown or incompatible with its drone body."
		return {}
	var clean_name = model_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Model X"
	var model_key = _model_key(clean_name)
	var model_path = root_path.path_join(model_key)
	var version_number = _next_version_number(model_path)
	var version_name = "v%04d" % version_number
	var version_path = model_path.path_join(version_name)
	var manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	while FileAccess.file_exists(manifest_path):
		version_number += 1
		version_name = "v%04d" % version_number
		version_path = model_path.path_join(version_name)
		manifest_path = version_path.path_join(MANIFEST_FILE_NAME)

	var directory_error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create training version directory (%s)." % error_string(directory_error)
		return {}
	var checkpoint_path = version_path.path_join(PPO_CHECKPOINT_FILE_NAME)
	if not _write_json_file(checkpoint_path, checkpoint):
		var checkpoint_write_error = error_string(FileAccess.get_open_error())
		_remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path))
		last_error = "Could not write the training checkpoint (%s)." % checkpoint_write_error
		return {}

	var created_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var created_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	var training: Dictionary = training_value
	var best_candidate_value: Variant = training.get("best_candidate", {})
	var best_candidate: Dictionary = (
		(best_candidate_value as Dictionary).duplicate(true)
		if best_candidate_value is Dictionary else {}
	)
	var exact_candidate = RLTrainingMath.bool_or(
		best_candidate.get("exact_policy_match", false),
		false
	)
	var training_environment: Dictionary = training_environment_value
	var runtime_contract = _runtime_contract_for_checkpoint(checkpoint)
	var record = {
		"schema_version": SCHEMA_VERSION,
		"model_name": clean_name,
		"model_key": model_key,
		"version": version_number,
		"version_name": version_name,
		"version_id": "%s/%s" % [model_key, version_name],
		"artifact_type": str(algorithm_descriptor.get(
			"artifact_type",
			"trained_quadrotor_policy"
		)),
		"algorithm": str(checkpoint.get("algorithm", "")),
		"training_algorithm_id": str(algorithm_descriptor.get("id", "")),
		"training_algorithm_name": str(algorithm_descriptor.get(
			"display_name",
			"Learning algorithm"
		)),
		"propeller_count": RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), 0),
		"created_unix_ms": created_unix_ms,
		"created_utc": created_utc,
		"training_updated_unix_ms": created_unix_ms,
		"training_updated_utc": created_utc,
		"parent_version_id": parent_version_id,
		"weights": {},
		"checkpoint_file": PPO_CHECKPOINT_FILE_NAME,
		"training_update": maxi(RLTrainingMath.finite_int_or(training.get("update_count", 0), 0), 0),
		"environment_steps": maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0),
		"completed_episodes": maxi(RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0), 0),
		"has_best_episode": RLTrainingMath.bool_or(training.get("has_best_episode", false), false),
		"has_exact_best_policy": exact_candidate,
		"best_episode_mean_reward": RLTrainingMath.finite_float_or(training.get(
			"best_episode_mean_reward",
			0.0
		), 0.0),
		"best_candidate_score": RLTrainingMath.finite_float_or(best_candidate.get(
			"selection_score",
			0.0
		), 0.0),
		"best_candidate_group_mean_reward": RLTrainingMath.finite_float_or(best_candidate.get(
			"group_mean_reward_per_second",
			0.0
		), 0.0),
		"best_candidate_support_reward": RLTrainingMath.finite_float_or(best_candidate.get(
			"support_reward_per_second",
			0.0
		), 0.0),
		"best_candidate_worker_reward": RLTrainingMath.finite_float_or(best_candidate.get(
			"best_worker_reward_per_second",
			0.0
		), 0.0),
		"best_candidate_selection_method": str(best_candidate.get(
			"selection_method",
			""
		)),
		"checkpoint_kind": str(checkpoint_kind),
		"checkpoint_revision": 1,
		"training_environment": training_environment.duplicate(true),
		"runtime_contract": runtime_contract,
		"score_matches_checkpoint": (
			str(checkpoint_kind) in ["best", "auto_best"]
			and exact_candidate
		),
	}
	if not _write_json_file(manifest_path, record):
		var manifest_write_error = error_string(FileAccess.get_open_error())
		_remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path))
		last_error = "Could not write the training model manifest (%s)." % manifest_write_error
		return {}
	record["storage_path"] = version_path
	return record


func overwrite_training_checkpoint(
	version_record_or_id: Variant,
	checkpoint: Dictionary,
	checkpoint_kind = "current"
) -> Dictionary:
	last_error = ""
	var requested_version_id = (
		str((version_record_or_id as Dictionary).get("version_id", ""))
		if version_record_or_id is Dictionary
		else str(version_record_or_id)
	)
	var existing = get_version(requested_version_id)
	if existing.is_empty():
		last_error = "The rolling model version no longer exists."
		return {}
	var record: Dictionary = existing.duplicate(true)
	var algorithm_descriptor = DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(checkpoint)
	var training_value: Variant = checkpoint.get("training", {})
	var training_environment_value: Variant = checkpoint.get("training_environment", {})
	var checkpoint_inspection: Dictionary = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	if (
		algorithm_descriptor.is_empty()
		or not bool(checkpoint_inspection.get("compatible", false))
		or not (training_value is Dictionary)
		or not (training_environment_value is Dictionary)
		or not (checkpoint.get("network", {}) is Dictionary)
		or DroneTrainingAlgorithmCatalog.create_runtime_model(checkpoint) == null
	):
		last_error = "The replacement training checkpoint is incomplete or incompatible."
		return {}
	if (
		not DroneTrainingAlgorithmCatalog.is_training_checkpoint(record)
		or str(record.get("training_algorithm_id", "")) != str(algorithm_descriptor.get("id", ""))
	):
		last_error = "The rolling version belongs to a different learning algorithm."
		return {}
	var version_path = str(record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The rolling model version has no storage directory."
		return {}
	var run_path = version_path.path_join(RUN_DIRECTORY_NAME)
	var absolute_run_path = ProjectSettings.globalize_path(run_path)
	var run_backup_path = ""
	if DirAccess.dir_exists_absolute(absolute_run_path):
		run_backup_path = "%s.rollback-%d" % [absolute_run_path, Time.get_ticks_usec()]
		var run_backup_error = DirAccess.rename_absolute(absolute_run_path, run_backup_path)
		if run_backup_error != OK:
			last_error = "Could not stage the rolling evaluation results for replacement (%s)." % error_string(run_backup_error)
			return {}
	var checkpoint_path = version_path.path_join(str(record.get(
		"checkpoint_file",
		PPO_CHECKPOINT_FILE_NAME
	)))
	var previous_checkpoint = _read_json_dictionary(checkpoint_path)
	if previous_checkpoint.is_empty():
		_restore_directory_backup(absolute_run_path, run_backup_path)
		last_error = "The rolling model's previous checkpoint could not be staged for rollback."
		return {}
	if not _write_json_file(checkpoint_path, checkpoint):
		var checkpoint_write_error = error_string(FileAccess.get_open_error())
		var run_restored = _restore_directory_backup(absolute_run_path, run_backup_path)
		last_error = (
			"Could not overwrite the rolling training checkpoint (%s)." % checkpoint_write_error
			if run_restored
			else "Could not overwrite the rolling checkpoint and could not restore its previous evaluation directory."
		)
		return {}
	var now_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	var training: Dictionary = training_value
	var best_candidate_value: Variant = training.get("best_candidate", {})
	var best_candidate: Dictionary = (
		(best_candidate_value as Dictionary).duplicate(true)
		if best_candidate_value is Dictionary else {}
	)
	var exact_candidate = RLTrainingMath.bool_or(
		best_candidate.get("exact_policy_match", false),
		false
	)
	record["artifact_type"] = str(algorithm_descriptor.get(
		"artifact_type",
		"trained_quadrotor_policy"
	))
	record["algorithm"] = str(checkpoint.get("algorithm", ""))
	record["training_algorithm_id"] = str(algorithm_descriptor.get("id", ""))
	record["propeller_count"] = RLTrainingMath.finite_int_or(checkpoint.get("propeller_count", 0), 0)
	record["training_algorithm_name"] = str(algorithm_descriptor.get(
		"display_name",
		"Learning algorithm"
	))
	record["training_updated_unix_ms"] = now_unix_ms
	record["training_updated_utc"] = now_utc
	record["training_update"] = maxi(RLTrainingMath.finite_int_or(training.get("update_count", 0), 0), 0)
	record["environment_steps"] = maxi(RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0), 0)
	record["completed_episodes"] = maxi(RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0), 0)
	record["has_best_episode"] = RLTrainingMath.bool_or(training.get("has_best_episode", false), false)
	record["has_exact_best_policy"] = exact_candidate
	record["best_episode_mean_reward"] = RLTrainingMath.finite_float_or(
		training.get("best_episode_mean_reward", 0.0),
		0.0
	)
	record["best_candidate_score"] = RLTrainingMath.finite_float_or(best_candidate.get("selection_score", 0.0), 0.0)
	record["best_candidate_group_mean_reward"] = RLTrainingMath.finite_float_or(
		best_candidate.get("group_mean_reward_per_second", 0.0),
		0.0
	)
	record["best_candidate_support_reward"] = RLTrainingMath.finite_float_or(
		best_candidate.get("support_reward_per_second", 0.0),
		0.0
	)
	record["best_candidate_worker_reward"] = RLTrainingMath.finite_float_or(
		best_candidate.get("best_worker_reward_per_second", 0.0),
		0.0
	)
	record["best_candidate_selection_method"] = str(best_candidate.get(
		"selection_method",
		""
	))
	record["checkpoint_kind"] = str(checkpoint_kind)
	record["checkpoint_revision"] = maxi(RLTrainingMath.finite_int_or(record.get("checkpoint_revision", 1), 1), 1) + 1
	record["training_environment"] = (training_environment_value as Dictionary).duplicate(true)
	record["runtime_contract"] = _runtime_contract_for_checkpoint(checkpoint)
	record["score_matches_checkpoint"] = (
		str(checkpoint_kind) in ["best", "auto_best"]
		and exact_candidate
	)
	var manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	var stored_record = record.duplicate(true)
	stored_record.erase("storage_path")
	stored_record.erase("last_used_unix_ms")
	stored_record.erase("last_used_utc")
	stored_record.erase("use_count")
	if not _write_json_file(manifest_path, stored_record):
		var manifest_write_error = error_string(FileAccess.get_open_error())
		var checkpoint_restored = _write_json_file(checkpoint_path, previous_checkpoint)
		var run_restored = _restore_directory_backup(absolute_run_path, run_backup_path)
		if checkpoint_restored and run_restored:
			last_error = "Could not update the rolling training manifest (%s); the previous checkpoint and evaluation results were restored." % manifest_write_error
		else:
			last_error = "Rolling save failed while updating the manifest and rollback was incomplete; inspect this model version before using it."
		return {}
	if not run_backup_path.is_empty() and DirAccess.dir_exists_absolute(run_backup_path):
		var saved_last_error = last_error
		if not _remove_directory_recursive_absolute(run_backup_path):
			push_warning("Saved rolling checkpoint, but an old evaluation backup could not be removed: %s" % run_backup_path)
		last_error = saved_last_error
	record["overwritten_existing"] = true
	return record


func save_ppo_checkpoint(
	model_name: String,
	checkpoint: Dictionary,
	parent_version_id = "",
	checkpoint_kind = "current"
) -> Dictionary:
	# Compatibility alias for tests and older callers. New room code uses the generic
	# algorithm boundary while preserving the older PPO-specific method name.
	return save_training_checkpoint(
		model_name,
		checkpoint,
		parent_version_id,
		checkpoint_kind
	)


func load_training_checkpoint(version_record: Dictionary) -> Dictionary:
	last_error = ""
	var record = version_record
	if str(record.get("storage_path", "")).is_empty():
		record = get_version(str(record.get("version_id", "")))
	if DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(record).is_empty():
		last_error = "The selected model version is not a registered training checkpoint."
		return {}
	var version_path = str(record.get("storage_path", ""))
	var checkpoint_name = str(record.get(
		"checkpoint_file",
		PPO_CHECKPOINT_FILE_NAME
	))
	var checkpoint = _read_json_dictionary(version_path.path_join(checkpoint_name))
	if checkpoint.is_empty():
		last_error = "The selected training checkpoint could not be read."
	return checkpoint


func load_ppo_checkpoint(version_record: Dictionary) -> Dictionary:
	var checkpoint = load_training_checkpoint(version_record)
	if (
		not checkpoint.is_empty()
		and str(checkpoint.get("algorithm", "")) != DronePPOTrainer.ALGORITHM_NAME
	):
		last_error = "The selected checkpoint does not use PPO."
		return {}
	return checkpoint


func inspect_version(version_record: Dictionary) -> Dictionary:
	var result = {
		"compatible": false,
		"trainable": false,
		"compatibility_text": "This is not a registered training checkpoint.",
		"runtime_contract": _dictionary_copy(version_record.get("runtime_contract", {})),
		"training_environment": _dictionary_copy(
			version_record.get("training_environment", {})
		),
	}
	if not DroneTrainingAlgorithmCatalog.is_training_checkpoint(version_record):
		return result
	var checkpoint = load_training_checkpoint(version_record)
	if checkpoint.is_empty():
		result["compatibility_text"] = last_error
		return result
	var runtime_contract = _runtime_contract_for_checkpoint(checkpoint)
	var algorithm_inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(
		checkpoint
	)
	result["compatible"] = bool(algorithm_inspection.get("compatible", false))
	result["trainable"] = bool(algorithm_inspection.get("trainable", false))
	result["compatibility_text"] = str(algorithm_inspection.get(
		"compatibility_text",
		"Compatibility is unknown."
	))
	result["runtime_contract"] = runtime_contract
	result["training_environment"] = _dictionary_copy(
		checkpoint.get("training_environment", {})
	)
	return result


func list_versions() -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	var root = DirAccess.open(root_path)
	if root == null:
		return result
	root.list_dir_begin()
	var model_directory = root.get_next()
	while not model_directory.is_empty():
		if root.current_is_dir():
			_collect_model_versions(
				root_path.path_join(model_directory),
				result
			)
		model_directory = root.get_next()
	root.list_dir_end()
	result.sort_custom(_sort_versions)
	return result


func get_version(version_id: String) -> Dictionary:
	for record in list_versions():
		if str(record.get("version_id", "")) == version_id:
			return record
	return {}


func delete_version(version_record_or_id: Variant) -> bool:
	last_error = ""
	var version_id = (
		str(version_record_or_id.get("version_id", ""))
		if version_record_or_id is Dictionary
		else str(version_record_or_id)
	)
	var segments = version_id.split("/", false)
	var model_key = str(segments[0]) if segments.size() == 2 else ""
	var version_name = str(segments[1]) if segments.size() == 2 else ""
	var version_number_text = version_name.trim_prefix("v")
	if (
		segments.size() != 2
		or model_key.is_empty()
		or _model_key(model_key) != model_key
		or not version_name.begins_with("v")
		or version_number_text.is_empty()
		or not version_number_text.is_valid_int()
		or version_number_text.to_int() <= 0
	):
		last_error = "The selected model version has an invalid storage identity."
		return false
	var record = get_version(version_id)
	if record.is_empty():
		last_error = "The selected model version no longer exists."
		return false
	var expected_virtual_path = root_path.path_join(model_key).path_join(version_name)
	if str(record.get("storage_path", "")) != expected_virtual_path:
		last_error = "The selected model version resolved outside its expected directory."
		return false
	var model_virtual_path = root_path.path_join(model_key)
	if not _record_next_version_floor(
		model_virtual_path,
		RLTrainingMath.finite_int_or(record.get("version", version_number_text.to_int()), version_number_text.to_int()) + 1
	):
		return false
	var absolute_version_path = ProjectSettings.globalize_path(expected_virtual_path)
	if not _remove_directory_recursive_absolute(absolute_version_path):
		if last_error.is_empty():
			last_error = "The selected model version could not be deleted."
		return false
	var model_directory = DirAccess.open(model_virtual_path)
	if model_directory != null:
		model_directory.list_dir_begin()
		var first_entry = model_directory.get_next()
		model_directory.list_dir_end()
		if first_entry.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(model_virtual_path))
	return true


func mark_version_used(version_record_or_id: Variant) -> bool:
	last_error = ""
	var record = (
		version_record_or_id
		if version_record_or_id is Dictionary
		else get_version(str(version_record_or_id))
	)
	if not (record is Dictionary):
		last_error = "The selected model version is not registered."
		return false
	var version: Dictionary = record
	if version.is_empty():
		last_error = "The selected model version is not registered."
		return false
	var version_path = str(version.get("storage_path", ""))
	if version_path.is_empty():
		version = get_version(str(version.get("version_id", "")))
		version_path = str(version.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The selected model version has no storage path."
		return false
	var usage_path = version_path.path_join(USAGE_FILE_NAME)
	var usage = _read_json_dictionary(usage_path)
	var now_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	usage["last_used_unix_ms"] = now_unix_ms
	usage["last_used_utc"] = Time.get_datetime_string_from_system(true, false) + "Z"
	usage["use_count"] = maxi(RLTrainingMath.finite_int_or(usage.get("use_count", 0), 0), 0) + 1
	if not _write_json_file(usage_path, usage):
		last_error = "Could not update the model's last-used metadata."
		return false
	return true


func record_episode(version_record: Dictionary, result: Dictionary) -> String:
	last_error = ""
	var current_record = get_version(str(version_record.get("version_id", "")))
	if current_record.is_empty():
		last_error = "The model version is not registered."
		return ""
	var requested_revision = maxi(RLTrainingMath.finite_int_or(version_record.get("checkpoint_revision", 1), 1), 1)
	var current_revision = maxi(RLTrainingMath.finite_int_or(current_record.get("checkpoint_revision", 1), 1), 1)
	if requested_revision != current_revision:
		last_error = "This evaluator uses an older in-memory revision of a rolling checkpoint; its result was not attached to the newer weights."
		return ""
	var version_path = str(current_record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The model version has no storage directory."
		return ""

	var run_path = version_path.path_join(RUN_DIRECTORY_NAME)
	var directory_error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(run_path)
	)
	if directory_error != OK:
		last_error = "Could not create episode result directory (%s)." % error_string(directory_error)
		return ""

	var unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var run_id = "run-%013d-%04d" % [unix_ms, run_sequence]
	run_sequence += 1
	var result_path = run_path.path_join(run_id + ".json")
	while FileAccess.file_exists(result_path):
		run_id = "run-%013d-%04d" % [unix_ms, run_sequence]
		run_sequence += 1
		result_path = run_path.path_join(run_id + ".json")

	var stored_result = result.duplicate(true)
	stored_result["schema_version"] = SCHEMA_VERSION
	stored_result["run_id"] = run_id
	stored_result["model_version_id"] = version_record.get("version_id", "")
	stored_result["recorded_unix_ms"] = unix_ms
	stored_result["recorded_utc"] = Time.get_datetime_string_from_system(true, false) + "Z"
	var file = FileAccess.open(result_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not write episode result (%s)." % error_string(FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(stored_result, "\t", true, true))
	file.flush()
	file.close()
	return run_id


func color_for_version(version_record: Dictionary) -> Color:
	var weights: Dictionary = _dictionary_copy(version_record.get("weights", {}))
	var stable_identity = "%s|%s|%s" % [
		str(version_record.get("version_id", "")),
		str(version_record.get("artifact_type", "")),
		JSON.stringify(weights, "", true, true),
	]
	var hue = float(posmod(stable_identity.hash(), 10000)) / 10000.0
	return Color.from_hsv(hue, 0.7, 0.95)


func display_name(version_record: Dictionary) -> String:
	return "%s %s" % [
		str(version_record.get("model_name", "Model")),
		str(version_record.get("version_name", "v????")),
	]


func tooltip_for_version(version_record: Dictionary) -> String:
	if DroneTrainingAlgorithmCatalog.is_training_checkpoint(version_record):
		var training_environment: Dictionary = _dictionary_copy(
			version_record.get("training_environment", {})
		)
		var saved_reward_schema = RLTrainingMath.finite_int_or(
			training_environment.get("reward_schema_version", 1),
			1
		)
		var score_text = "No completed episode score was saved with this version."
		if saved_reward_schema != DroneTrainingReward.SCHEMA_VERSION:
			score_text = "Its score used older reward rules, so do not compare it directly with current scores. The model itself can still be loaded."
		elif RLTrainingMath.bool_or(version_record.get("score_matches_checkpoint", false), false):
			score_text = "Saved score: %+.3f per second\nBest worker: %+.3f · Group mean: %+.3f" % [
				RLTrainingMath.finite_float_or(version_record.get("best_candidate_score", 0.0), 0.0),
				RLTrainingMath.finite_float_or(version_record.get("best_candidate_worker_reward", 0.0), 0.0),
				RLTrainingMath.finite_float_or(version_record.get("best_candidate_group_mean_reward", 0.0), 0.0),
			]
		elif RLTrainingMath.bool_or(version_record.get("has_best_episode", false), false):
			score_text = "This save contains the live weights. Its old best score belonged to a different policy, so it is not shown as this version's score."
		return "%s\n\nTraining progress\nUpdate %d · %d collected decisions\n\nScore\n%s\n\nSelecting this row only inspects it. Nothing is loaded until you press a button." % [
			str(version_record.get("version_id", "")),
			maxi(RLTrainingMath.finite_int_or(version_record.get("training_update", 0), 0), 0),
			maxi(RLTrainingMath.finite_int_or(version_record.get("environment_steps", 0), 0), 0),
			score_text,
		]
	return "%s\n\nBaseline controller\nThis is the older hand-written controller, not a trained model.\n\nSelecting this row only inspects it." % [
		str(version_record.get("version_id", "")),
	]


func _runtime_contract_for_checkpoint(checkpoint: Dictionary) -> Dictionary:
	return DroneTrainingAlgorithmCatalog.runtime_contract(checkpoint)


func _collect_model_versions(
	model_path: String,
	result: Array[Dictionary]
) -> void:
	var directory = DirAccess.open(model_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var version_directory = directory.get_next()
	while not version_directory.is_empty():
		if directory.current_is_dir():
			var version_path = model_path.path_join(version_directory)
			var record = _read_record(
				version_path.path_join(MANIFEST_FILE_NAME)
			)
			if not record.is_empty():
				var usage = _read_json_dictionary(version_path.path_join(USAGE_FILE_NAME))
				if not usage.is_empty():
					record["last_used_unix_ms"] = maxi(RLTrainingMath.finite_int_or(usage.get("last_used_unix_ms", 0), 0), 0)
					record["last_used_utc"] = str(usage.get("last_used_utc", ""))
					record["use_count"] = maxi(RLTrainingMath.finite_int_or(usage.get("use_count", 0), 0), 0)
				record["storage_path"] = version_path
				result.append(record)
		version_directory = directory.get_next()
	directory.list_dir_end()


func _read_record(path: String) -> Dictionary:
	var record = _read_json_dictionary(path)
	if (
		str(record.get("version_id", "")).is_empty()
		or not (record.get("weights", {}) is Dictionary)
	):
		return {}
	return record


func _dictionary_copy(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json_file(path: String, value: Dictionary) -> bool:
	return _write_text_file_atomic(path, JSON.stringify(value, "\t", true, true))


func _write_text_file_atomic(path: String, content: String) -> bool:
	var absolute_path = ProjectSettings.globalize_path(path)
	var temporary_path = "%s.tmp-%d" % [absolute_path, Time.get_ticks_usec()]
	var backup_path = "%s.backup-%d" % [absolute_path, Time.get_ticks_usec()]
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	var had_existing = FileAccess.file_exists(absolute_path)
	if had_existing:
		var backup_error = DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
	var promote_error = DirAccess.rename_absolute(temporary_path, absolute_path)
	if promote_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temporary_path)
		return false
	if had_existing:
		DirAccess.remove_absolute(backup_path)
	return true


func _restore_directory_backup(original_path: String, backup_path: String) -> bool:
	if backup_path.is_empty() or not DirAccess.dir_exists_absolute(backup_path):
		return true
	if DirAccess.dir_exists_absolute(original_path):
		return false
	return DirAccess.rename_absolute(backup_path, original_path) == OK


func _remove_directory_recursive_absolute(absolute_path: String) -> bool:
	var directory = DirAccess.open(absolute_path)
	if directory == null:
		last_error = "Could not open the model version directory for deletion."
		return false
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path = absolute_path.path_join(entry)
			if directory.current_is_dir():
				if not _remove_directory_recursive_absolute(child_path):
					directory.list_dir_end()
					return false
			else:
				var remove_file_error = directory.remove(entry)
				if remove_file_error != OK:
					last_error = "Could not delete model file %s (%s)." % [
						entry,
						error_string(remove_file_error),
					]
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	var remove_directory_error = DirAccess.remove_absolute(absolute_path)
	if remove_directory_error != OK:
		last_error = "Could not delete model directory (%s)." % error_string(
			remove_directory_error
		)
		return false
	return true


func _next_version_number(model_path: String) -> int:
	var highest = 0
	var directory = DirAccess.open(model_path)
	if directory != null:
		directory.list_dir_begin()
		var entry = directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir() and entry.begins_with("v"):
				highest = maxi(highest, entry.trim_prefix("v").to_int())
			entry = directory.get_next()
		directory.list_dir_end()
	var stored_floor = 1
	var sequence_path = model_path.path_join(NEXT_VERSION_FILE_NAME)
	if FileAccess.file_exists(sequence_path):
		var sequence_text = FileAccess.get_file_as_string(sequence_path).strip_edges()
		if sequence_text.is_valid_int():
			stored_floor = maxi(sequence_text.to_int(), 1)
	return maxi(highest + 1, stored_floor)


func _record_next_version_floor(model_path: String, requested_floor: int) -> bool:
	var next_floor = maxi(requested_floor, _next_version_number(model_path))
	var sequence_path = model_path.path_join(NEXT_VERSION_FILE_NAME)
	if not _write_text_file_atomic(sequence_path, str(next_floor)):
		last_error = "Could not preserve the model family's version sequence atomically (%s)." % error_string(
			FileAccess.get_open_error()
		)
		return false
	return true


func _model_key(model_name: String) -> String:
	var result = ""
	var previous_was_separator = false
	var lowered = model_name.to_lower()
	for index in range(lowered.length()):
		var character = lowered.substr(index, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789".contains(character):
			result += character
			previous_was_separator = false
		elif not previous_was_separator and not result.is_empty():
			result += "-"
			previous_was_separator = true
	result = result.trim_suffix("-")
	return result if not result.is_empty() else "model"


func _sort_versions(a: Dictionary, b: Dictionary) -> bool:
	var a_name = str(a.get("model_name", "")).to_lower()
	var b_name = str(b.get("model_name", "")).to_lower()
	if a_name == b_name:
		return RLTrainingMath.finite_int_or(a.get("version", 0), 0) > RLTrainingMath.finite_int_or(b.get("version", 0), 0)
	return a_name < b_name
