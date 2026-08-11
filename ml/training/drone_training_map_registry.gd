class_name DroneTrainingMapRegistry
extends RefCounted

const DEFAULT_ROOT_PATH = "user://ml_training_maps"
const MANIFEST_FILE_NAME = "map.json"
const USAGE_FILE_NAME = "usage.json"
const NEXT_VERSION_FILE_NAME = "next-version.txt"
const SCHEMA_VERSION = 3

#######################################################
# Stores user-created training-room obstacle/item/delivery layouts independently from checkpoints.
# Nothing is created automatically; a map exists only after the user explicitly saves one.
#######################################################

var root_path: String
var last_error = ""


func _init(custom_root_path = DEFAULT_ROOT_PATH) -> void:
	root_path = str(custom_root_path).trim_suffix("/")


func save_map(
	map_name: String,
	obstacle_records: Array[Dictionary],
	item_records: Array[Dictionary] = [],
	delivery_destination_group_records: Array[Dictionary] = []
) -> Dictionary:
	last_error = ""
	var clean_name = map_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Training Map"
	var map_key = _map_key(clean_name)
	var family_path = root_path.path_join(map_key)
	var version_number = _next_version_number(family_path)
	var version_name = "v%04d" % version_number
	var version_path = family_path.path_join(version_name)
	var manifest_path = version_path.path_join(MANIFEST_FILE_NAME)
	while FileAccess.file_exists(manifest_path):
		version_number += 1
		version_name = "v%04d" % version_number
		version_path = family_path.path_join(version_name)
		manifest_path = version_path.path_join(MANIFEST_FILE_NAME)

	var directory_error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create the map directory (%s)." % error_string(directory_error)
		return {}

	var now_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	var record = {
		"schema_version": SCHEMA_VERSION,
		"map_name": clean_name,
		"map_key": map_key,
		"version": version_number,
		"version_name": version_name,
		"map_id": "%s/%s" % [map_key, version_name],
		"created_unix_ms": now_unix_ms,
		"created_utc": now_utc,
		"updated_unix_ms": now_unix_ms,
		"updated_utc": now_utc,
		"obstacle_count": obstacle_records.size(),
		"obstacles": obstacle_records.duplicate(true),
		"item_count": item_records.size(),
		"items": item_records.duplicate(true),
		"delivery_destination_group_count": delivery_destination_group_records.size(),
		"delivery_destination_groups": delivery_destination_group_records.duplicate(true),
	}
	if not _write_json_file(manifest_path, record):
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		last_error = "Could not write the map file atomically."
		return {}
	# Reserve the next immutable identity only after the map itself exists. Failed writes consume
	# nothing, while a successfully issued map ID cannot be silently reused after external removal.
	if not _record_next_version_floor(family_path, version_number + 1):
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(version_path)
		)
		return {}
	record["storage_path"] = version_path
	return record


func overwrite_map(
	map_record_or_id: Variant,
	obstacle_records: Array[Dictionary],
	item_records: Array[Dictionary] = [],
	delivery_destination_group_records: Array[Dictionary] = []
) -> Dictionary:
	last_error = ""
	var map_id = (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record = get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return {}
	var version_path = str(record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The selected map has no storage directory."
		return {}
	var now_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	record["updated_unix_ms"] = now_unix_ms
	record["updated_utc"] = now_utc
	record["obstacle_count"] = obstacle_records.size()
	record["obstacles"] = obstacle_records.duplicate(true)
	record["item_count"] = item_records.size()
	record["items"] = item_records.duplicate(true)
	record["delivery_destination_group_count"] = delivery_destination_group_records.size()
	record["delivery_destination_groups"] = delivery_destination_group_records.duplicate(true)
	record["schema_version"] = SCHEMA_VERSION
	if not _write_json_file(version_path.path_join(MANIFEST_FILE_NAME), record):
		last_error = "Could not update the selected map."
		return {}
	return record


func list_maps() -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	for map_id: String in TrainingFileIO.list_version_ids(root_path, "training-map"):
		var record: Dictionary = _resolve_map(map_id)
		if not record.is_empty():
			_apply_usage(record, str(record["storage_path"]))
			result.append(record)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_updated = SafeVariant.integral_int_or(
			left.get("updated_unix_ms", left.get("created_unix_ms", 0)),
			0
		)
		var right_updated = SafeVariant.integral_int_or(
			right.get("updated_unix_ms", right.get("created_unix_ms", 0)),
			0
		)
		if left_updated == right_updated:
			return str(left.get("map_id", "")) < str(right.get("map_id", ""))
		return left_updated > right_updated
	)
	return result


func get_map(map_id: String) -> Dictionary:
	var record: Dictionary = _resolve_map(map_id)
	if record.is_empty():
		return {}
	_apply_usage(record, str(record["storage_path"]))
	return record


func delete_map(map_record_or_id: Variant) -> bool:
	last_error = ""
	var map_id = (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record = get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return false
	var version_path = str(record.get("storage_path", ""))
	var family_path = version_path.get_base_dir()
	if not _record_next_version_floor(
		family_path,
		maxi(SafeVariant.integral_int_or(record.get("version", 0), 0), 0) + 1
	):
		return false
	if not _remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path)):
		return false
	# Keep the family directory and next-version.txt so deleted version numbers are never reused.
	return true


func mark_used(map_record_or_id: Variant) -> bool:
	last_error = ""
	var map_id = (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record = get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return false
	var usage_path: String = str(record.get("storage_path", "")).path_join(USAGE_FILE_NAME)
	if not TrainingFileIO.record_usage(usage_path):
		last_error = "Could not update the map's last-used time."
		return false
	return true


func display_name(record: Dictionary) -> String:
	return "%s %s" % [
		str(record.get("map_name", "Training Map")),
		str(record.get("version_name", "v????")),
	]


func globalized_root_path() -> String:
	return ProjectSettings.globalize_path(root_path)


func _resolve_map(map_record_or_id: Variant) -> Dictionary:
	var map_id: String = (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	# Preserve the registry's historical tolerance for surrounding whitespace/slashes while the
	# shared resolver still validates the normalized two-segment identity strictly.
	map_id = map_id.strip_edges().trim_prefix("/").trim_suffix("/")
	var record: Dictionary = TrainingFileIO.resolve_version_manifest(
		root_path,
		map_id,
		"training-map",
		MANIFEST_FILE_NAME,
		"map_id",
		"map_key"
	)
	if record.is_empty():
		return {}
	# Counts are denormalized display metadata. Re-derive them from readable payload arrays so a
	# stale/manual manifest edit cannot make the map browser describe different content than load.
	var obstacles: Variant = record.get("obstacles", [])
	record["obstacle_count"] = (obstacles as Array).size() if obstacles is Array else 0
	var items: Variant = record.get("items", [])
	record["item_count"] = (items as Array).size() if items is Array else 0
	var delivery_groups: Variant = record.get("delivery_destination_groups", [])
	record["delivery_destination_group_count"] = (
		(delivery_groups as Array).size()
		if delivery_groups is Array
		else 0
	)
	return record


func _apply_usage(record: Dictionary, version_path: String) -> void:
	var usage: Dictionary = TrainingFileIO.read_usage_metadata(
		version_path.path_join(USAGE_FILE_NAME)
	)
	record["last_used_unix_ms"] = int(usage.get("last_used_unix_ms", 0))
	record["last_used_utc"] = str(usage.get("last_used_utc", ""))
	record["use_count"] = int(usage.get("use_count", 0))


func _write_json_file(path: String, value: Dictionary) -> bool:
	var stored: Dictionary = value.duplicate(true)
	stored.erase("storage_path")
	if stored.has("map_id"):
		stored.erase("last_used_unix_ms")
		stored.erase("last_used_utc")
		stored.erase("use_count")
	return TrainingFileIO.write_json_dictionary_atomic(path, stored)


func _remove_directory_recursive_absolute(absolute_path: String) -> bool:
	if TrainingFileIO.remove_directory_recursive_absolute(absolute_path):
		return true
	last_error = "Could not delete the selected map directory."
	return false


func _next_version_number(family_path: String) -> int:
	return TrainingFileIO.next_version_directory_number(
		family_path,
		NEXT_VERSION_FILE_NAME
	)


func _record_next_version_floor(family_path: String, requested_floor: int) -> bool:
	if TrainingFileIO.preserve_next_version_floor(
		family_path,
		NEXT_VERSION_FILE_NAME,
		requested_floor
	):
		return true
	last_error = "Could not preserve the map version sequence."
	return false


func _map_key(map_name: String) -> String:
	return TrainingFileIO.storage_key(map_name, "training-map")
