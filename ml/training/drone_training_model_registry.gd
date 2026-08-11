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
	var location: Dictionary = _create_version_location(model_name, "model version")
	if location.is_empty():
		return {}
	var clean_name: String = str(location["model_name"])
	var model_key: String = str(location["model_key"])
	var version_number: int = int(location["version"])
	var version_name: String = str(location["version_name"])
	var version_path: String = str(location["storage_path"])
	var manifest_path: String = version_path.path_join(MANIFEST_FILE_NAME)

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
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		last_error = "Could not write the model version atomically."
		return {}
	if not _record_next_version_floor(root_path.path_join(model_key), version_number + 1):
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
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
	var location: Dictionary = _create_version_location(model_name, "training version")
	if location.is_empty():
		return {}
	var clean_name: String = str(location["model_name"])
	var model_key: String = str(location["model_key"])
	var version_number: int = int(location["version"])
	var version_name: String = str(location["version_name"])
	var version_path: String = str(location["storage_path"])
	var manifest_path: String = version_path.path_join(MANIFEST_FILE_NAME)
	var checkpoint_path = version_path.path_join(PPO_CHECKPOINT_FILE_NAME)
	if not _write_json_file(checkpoint_path, checkpoint):
		_remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path))
		last_error = "Could not write the training checkpoint atomically."
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
		"created_unix_ms": created_unix_ms,
		"created_utc": created_utc,
		"parent_version_id": parent_version_id,
		"weights": {},
		"checkpoint_file": PPO_CHECKPOINT_FILE_NAME,
	}
	record.merge(_training_manifest_fields(
		checkpoint,
		algorithm_descriptor,
		checkpoint_kind,
		created_unix_ms,
		created_utc,
		1
	), true)
	if not _write_json_file(manifest_path, record):
		_remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path))
		last_error = "Could not write the training model manifest atomically."
		return {}
	if not _record_next_version_floor(root_path.path_join(model_key), version_number + 1):
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
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
	var previous_checkpoint = TrainingFileIO.read_json_dictionary(checkpoint_path)
	if previous_checkpoint.is_empty():
		_restore_directory_backup(absolute_run_path, run_backup_path)
		last_error = "The rolling model's previous checkpoint could not be staged for rollback."
		return {}
	if not _write_json_file(checkpoint_path, checkpoint):
		var run_restored = _restore_directory_backup(absolute_run_path, run_backup_path)
		last_error = (
			"Could not overwrite the rolling training checkpoint atomically."
			if run_restored
			else "Could not overwrite the rolling checkpoint and could not restore its previous evaluation directory."
		)
		return {}
	var now_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	var next_revision: int = maxi(
		RLTrainingMath.finite_int_or(record.get("checkpoint_revision", 1), 1),
		1
	) + 1
	record.merge(_training_manifest_fields(
		checkpoint,
		algorithm_descriptor,
		checkpoint_kind,
		now_unix_ms,
		now_utc,
		next_revision
	), true)
	var manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	var stored_record = record.duplicate(true)
	stored_record.erase("storage_path")
	stored_record.erase("last_used_unix_ms")
	stored_record.erase("last_used_utc")
	stored_record.erase("use_count")
	if not _write_json_file(manifest_path, stored_record):
		var checkpoint_restored = _write_json_file(checkpoint_path, previous_checkpoint)
		var run_restored = _restore_directory_backup(absolute_run_path, run_backup_path)
		if checkpoint_restored and run_restored:
			last_error = "Could not update the rolling training manifest atomically; the previous checkpoint and evaluation results were restored."
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
	var record: Dictionary = _resolve_version(version_record)
	if record.is_empty():
		last_error = "The selected model version is not registered."
		return {}
	if DroneTrainingAlgorithmCatalog.descriptor_for_checkpoint(record).is_empty():
		last_error = "The selected model version is not a registered training checkpoint."
		return {}
	var version_path = str(record.get("storage_path", ""))
	var checkpoint_name = str(record.get(
		"checkpoint_file",
		PPO_CHECKPOINT_FILE_NAME
	))
	var checkpoint = TrainingFileIO.read_json_dictionary(version_path.path_join(checkpoint_name))
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
	var record: Dictionary = _resolve_version(version_record)
	var result = {
		"compatible": false,
		"trainable": false,
		"compatibility_text": (
			"This model version is not registered."
			if record.is_empty()
			else "This is not a registered training checkpoint."
		),
		"runtime_contract": SafeVariant.dictionary_copy(record.get("runtime_contract", {})),
		"training_environment": SafeVariant.dictionary_copy(
			record.get("training_environment", {})
		),
	}
	if record.is_empty() or not DroneTrainingAlgorithmCatalog.is_training_checkpoint(record):
		return result
	var checkpoint = load_training_checkpoint(record)
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
	result["training_environment"] = SafeVariant.dictionary_copy(
		checkpoint.get("training_environment", {})
	)
	return result


func list_versions() -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	for version_id: String in TrainingFileIO.list_version_ids(root_path, "model"):
		var record: Dictionary = _resolve_version(version_id)
		if not record.is_empty():
			result.append(_with_usage_metadata(record))
	result.sort_custom(_sort_versions)
	return result


func get_version(version_id: String) -> Dictionary:
	return _with_usage_metadata(_resolve_version(version_id))


func delete_version(version_record_or_id: Variant) -> bool:
	last_error = ""
	var version_id = (
		str(version_record_or_id.get("version_id", ""))
		if version_record_or_id is Dictionary
		else str(version_record_or_id)
	)
	var identity: Dictionary = TrainingFileIO.parse_version_id(version_id, "model")
	if identity.is_empty():
		last_error = "The selected model version has an invalid storage identity."
		return false
	var model_key: String = str(identity["model_key"])
	var version_name: String = str(identity["version_name"])
	var version_number: int = int(identity["version"])
	var record: Dictionary = _resolve_version(version_id)
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
		version_number + 1
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
	var version: Dictionary = _resolve_version(version_record_or_id)
	if version.is_empty():
		last_error = "The selected model version is not registered."
		return false
	var version_path = str(version.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The selected model version has no storage path."
		return false
	var usage_path: String = version_path.path_join(USAGE_FILE_NAME)
	if not TrainingFileIO.record_usage(usage_path):
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
	stored_result["model_version_id"] = current_record.get("version_id", "")
	stored_result["recorded_unix_ms"] = unix_ms
	stored_result["recorded_utc"] = Time.get_datetime_string_from_system(true, false) + "Z"
	if not TrainingFileIO.write_json_dictionary_atomic(result_path, stored_result):
		last_error = "Could not write the episode result atomically."
		return ""
	return run_id


func color_for_version(version_record: Dictionary) -> Color:
	var weights: Dictionary = SafeVariant.dictionary_copy(version_record.get("weights", {}))
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
		var training_environment: Dictionary = SafeVariant.dictionary_copy(
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


func _create_version_location(model_name: String, directory_label: String) -> Dictionary:
	var clean_name: String = model_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Model X"
	var model_key: String = _model_key(clean_name)
	var model_path: String = root_path.path_join(model_key)
	var version_number: int = _next_version_number(model_path)
	var version_name: String = "v%04d" % version_number
	var version_path: String = model_path.path_join(version_name)
	var manifest_path: String = version_path.path_join(MANIFEST_FILE_NAME)
	while FileAccess.file_exists(manifest_path):
		version_number += 1
		version_name = "v%04d" % version_number
		version_path = model_path.path_join(version_name)
		manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create %s directory (%s)." % [
			directory_label,
			error_string(directory_error),
		]
		return {}
	return {
		"model_name": clean_name,
		"model_key": model_key,
		"version": version_number,
		"version_name": version_name,
		"version_id": "%s/%s" % [model_key, version_name],
		"storage_path": version_path,
	}


func _training_manifest_fields(
	checkpoint: Dictionary,
	algorithm_descriptor: Dictionary,
	checkpoint_kind: Variant,
	updated_unix_ms: int,
	updated_utc: String,
	checkpoint_revision: int
) -> Dictionary:
	var training_value: Variant = checkpoint.get("training", {})
	var training: Dictionary = (
		training_value as Dictionary
		if training_value is Dictionary
		else {}
	)
	var best_candidate_value: Variant = training.get("best_candidate", {})
	var best_candidate: Dictionary = (
		(best_candidate_value as Dictionary).duplicate(true)
		if best_candidate_value is Dictionary
		else {}
	)
	var exact_candidate: bool = RLTrainingMath.bool_or(
		best_candidate.get("exact_policy_match", false),
		false
	)
	var training_environment_value: Variant = checkpoint.get("training_environment", {})
	var training_environment: Dictionary = (
		(training_environment_value as Dictionary).duplicate(true)
		if training_environment_value is Dictionary
		else {}
	)
	return {
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
		"propeller_count": RLTrainingMath.finite_int_or(
			checkpoint.get("propeller_count", 0),
			0
		),
		"training_updated_unix_ms": updated_unix_ms,
		"training_updated_utc": updated_utc,
		"training_update": maxi(
			RLTrainingMath.finite_int_or(training.get("update_count", 0), 0),
			0
		),
		"environment_steps": maxi(
			RLTrainingMath.finite_int_or(training.get("environment_steps", 0), 0),
			0
		),
		"completed_episodes": maxi(
			RLTrainingMath.finite_int_or(training.get("completed_episodes", 0), 0),
			0
		),
		"has_best_episode": RLTrainingMath.bool_or(
			training.get("has_best_episode", false),
			false
		),
		"has_exact_best_policy": exact_candidate,
		"best_episode_mean_reward": RLTrainingMath.finite_float_or(
			training.get("best_episode_mean_reward", 0.0),
			0.0
		),
		"best_candidate_score": RLTrainingMath.finite_float_or(
			best_candidate.get("selection_score", 0.0),
			0.0
		),
		"best_candidate_group_mean_reward": RLTrainingMath.finite_float_or(
			best_candidate.get("group_mean_reward_per_second", 0.0),
			0.0
		),
		"best_candidate_support_reward": RLTrainingMath.finite_float_or(
			best_candidate.get("support_reward_per_second", 0.0),
			0.0
		),
		"best_candidate_worker_reward": RLTrainingMath.finite_float_or(
			best_candidate.get("best_worker_reward_per_second", 0.0),
			0.0
		),
		"best_candidate_selection_method": str(best_candidate.get(
			"selection_method",
			""
		)),
		"checkpoint_kind": str(checkpoint_kind),
		"checkpoint_revision": maxi(checkpoint_revision, 1),
		"training_environment": training_environment,
		"runtime_contract": _runtime_contract_for_checkpoint(checkpoint),
		"score_matches_checkpoint": (
			str(checkpoint_kind) in ["best", "auto_best"]
			and exact_candidate
		),
	}


func _runtime_contract_for_checkpoint(checkpoint: Dictionary) -> Dictionary:
	return DroneTrainingAlgorithmCatalog.runtime_contract(checkpoint)


func _resolve_version(record_or_id: Variant) -> Dictionary:
	var version_id: String = (
		str((record_or_id as Dictionary).get("version_id", ""))
		if record_or_id is Dictionary
		else str(record_or_id)
	)
	var record: Dictionary = TrainingFileIO.resolve_version_manifest(
		root_path,
		version_id,
		"model",
		MANIFEST_FILE_NAME
	)
	if record.is_empty() or not (record.get("weights", {}) is Dictionary):
		return {}
	if (
		DroneTrainingAlgorithmCatalog.is_training_checkpoint(record)
		and str(record.get("checkpoint_file", PPO_CHECKPOINT_FILE_NAME))
		!= PPO_CHECKPOINT_FILE_NAME
	):
		return {}
	return record


func _with_usage_metadata(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var result: Dictionary = record.duplicate(true)
	var version_path: String = str(result.get("storage_path", ""))
	if version_path.is_empty():
		return result
	var usage: Dictionary = TrainingFileIO.read_usage_metadata(
		version_path.path_join(USAGE_FILE_NAME)
	)
	if usage.is_empty():
		return result
	result.merge(usage, true)
	return result


func _write_json_file(path: String, value: Dictionary) -> bool:
	return TrainingFileIO.write_json_dictionary_atomic(path, value)


func _restore_directory_backup(original_path: String, backup_path: String) -> bool:
	if backup_path.is_empty() or not DirAccess.dir_exists_absolute(backup_path):
		return true
	if DirAccess.dir_exists_absolute(original_path):
		return false
	return DirAccess.rename_absolute(backup_path, original_path) == OK


func _remove_directory_recursive_absolute(absolute_path: String) -> bool:
	if TrainingFileIO.remove_directory_recursive_absolute(absolute_path):
		return true
	last_error = "Could not delete model directory %s." % absolute_path
	return false


func _next_version_number(model_path: String) -> int:
	return TrainingFileIO.next_version_directory_number(
		model_path,
		NEXT_VERSION_FILE_NAME
	)


func _record_next_version_floor(model_path: String, requested_floor: int) -> bool:
	if not TrainingFileIO.preserve_next_version_floor(
		model_path,
		NEXT_VERSION_FILE_NAME,
		requested_floor
	):
		last_error = "Could not preserve the model family's version sequence atomically."
		return false
	return true


func _model_key(model_name: String) -> String:
	return TrainingFileIO.storage_key(model_name, "model")


func _sort_versions(a: Dictionary, b: Dictionary) -> bool:
	var a_name = str(a.get("model_name", "")).to_lower()
	var b_name = str(b.get("model_name", "")).to_lower()
	if a_name == b_name:
		return RLTrainingMath.finite_int_or(a.get("version", 0), 0) > RLTrainingMath.finite_int_or(b.get("version", 0), 0)
	return a_name < b_name
