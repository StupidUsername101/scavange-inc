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
	var clean_name := map_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Training Map"
	var map_key := _map_key(clean_name)
	var family_path := root_path.path_join(map_key)
	var version_number := _next_version_number(family_path)
	var version_name := "v%04d" % version_number
	var version_path := family_path.path_join(version_name)
	var manifest_path := version_path.path_join(MANIFEST_FILE_NAME)
	while FileAccess.file_exists(manifest_path):
		version_number += 1
		version_name = "v%04d" % version_number
		version_path = family_path.path_join(version_name)
		manifest_path = version_path.path_join(MANIFEST_FILE_NAME)

	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(version_path)
	)
	if directory_error != OK:
		last_error = "Could not create the map directory (%s)." % error_string(directory_error)
		return {}

	var now_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc := Time.get_datetime_string_from_system(true, false) + "Z"
	var record := {
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
		last_error = "Could not write the map file (%s)." % error_string(FileAccess.get_open_error())
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
	var map_id := (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record := get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return {}
	var version_path := str(record.get("storage_path", ""))
	if version_path.is_empty():
		last_error = "The selected map has no storage directory."
		return {}
	var now_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var now_utc := Time.get_datetime_string_from_system(true, false) + "Z"
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
	var root := DirAccess.open(root_path)
	if root == null:
		return result
	root.list_dir_begin()
	var family_name := root.get_next()
	while not family_name.is_empty():
		if root.current_is_dir():
			_collect_family(root_path.path_join(family_name), result)
		family_name = root.get_next()
	root.list_dir_end()
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_updated = RLTrainingMath.finite_int_or(
			left.get("updated_unix_ms", left.get("created_unix_ms", 0)),
			0
		)
		var right_updated = RLTrainingMath.finite_int_or(
			right.get("updated_unix_ms", right.get("created_unix_ms", 0)),
			0
		)
		if left_updated == right_updated:
			return str(left.get("map_id", "")) < str(right.get("map_id", ""))
		return left_updated > right_updated
	)
	return result


func get_map(map_id: String) -> Dictionary:
	var clean_id := map_id.strip_edges().trim_prefix("/").trim_suffix("/")
	if clean_id.is_empty() or clean_id.contains(".."):
		return {}
	var record: Dictionary = TrainingFileIO.read_json_dictionary(
		root_path.path_join(clean_id).path_join(MANIFEST_FILE_NAME)
	)
	if str(record.get("map_id", "")) != clean_id:
		return {}
	var version_path := root_path.path_join(clean_id)
	_apply_usage(record, version_path)
	record["storage_path"] = version_path
	return record


func delete_map(map_record_or_id: Variant) -> bool:
	last_error = ""
	var map_id := (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record := get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return false
	var version_path := str(record.get("storage_path", ""))
	var family_path := version_path.get_base_dir()
	if not _record_next_version_floor(
		family_path,
		maxi(RLTrainingMath.finite_int_or(record.get("version", 0), 0), 0) + 1
	):
		return false
	if not _remove_directory_recursive_absolute(ProjectSettings.globalize_path(version_path)):
		return false
	var family_directory := DirAccess.open(family_path)
	if family_directory != null:
		var has_content := false
		family_directory.list_dir_begin()
		var entry := family_directory.get_next()
		while not entry.is_empty():
			if entry != "." and entry != ".." and entry != NEXT_VERSION_FILE_NAME:
				has_content = true
				break
			entry = family_directory.get_next()
		family_directory.list_dir_end()
		if not has_content:
			# Keep next-version.txt so deleted version numbers are never silently reused.
			pass
	return true


func mark_used(map_record_or_id: Variant) -> bool:
	last_error = ""
	var map_id := (
		str((map_record_or_id as Dictionary).get("map_id", ""))
		if map_record_or_id is Dictionary
		else str(map_record_or_id)
	)
	var record := get_map(map_id)
	if record.is_empty():
		last_error = "The selected map no longer exists."
		return false
	var usage_path := str(record.get("storage_path", "")).path_join(USAGE_FILE_NAME)
	var usage: Dictionary = TrainingFileIO.read_json_dictionary(usage_path)
	usage["last_used_unix_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	usage["last_used_utc"] = Time.get_datetime_string_from_system(true, false) + "Z"
	usage["use_count"] = maxi(RLTrainingMath.finite_int_or(usage.get("use_count", 0), 0), 0) + 1
	if not _write_json_file(usage_path, usage):
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


func _collect_family(family_path: String, result: Array[Dictionary]) -> void:
	var directory := DirAccess.open(family_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var version_name := directory.get_next()
	while not version_name.is_empty():
		if directory.current_is_dir():
			var version_path := family_path.path_join(version_name)
			var record: Dictionary = TrainingFileIO.read_json_dictionary(version_path.path_join(MANIFEST_FILE_NAME))
			if not record.is_empty() and not str(record.get("map_id", "")).is_empty():
				_apply_usage(record, version_path)
				record["storage_path"] = version_path
				result.append(record)
		version_name = directory.get_next()
	directory.list_dir_end()


func _apply_usage(record: Dictionary, version_path: String) -> void:
	var usage = TrainingFileIO.read_json_dictionary(version_path.path_join(USAGE_FILE_NAME))
	record["last_used_unix_ms"] = maxi(
		RLTrainingMath.finite_int_or(usage.get("last_used_unix_ms", 0), 0),
		0
	)
	record["last_used_utc"] = str(usage.get("last_used_utc", ""))
	record["use_count"] = maxi(RLTrainingMath.finite_int_or(usage.get("use_count", 0), 0), 0)


func _write_json_file(path: String, value: Dictionary) -> bool:
	var stored = value.duplicate(true)
	stored.erase("storage_path")
	if stored.has("map_id"):
		stored.erase("last_used_unix_ms")
		stored.erase("last_used_utc")
		stored.erase("use_count")
	return TrainingFileIO.write_text_atomic(path, JSON.stringify(stored, "\t", true, true))


func _remove_directory_recursive_absolute(absolute_path: String) -> bool:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		last_error = "Could not open the map directory for deletion."
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := absolute_path.path_join(entry)
			if directory.current_is_dir():
				if not _remove_directory_recursive_absolute(child_path):
					directory.list_dir_end()
					return false
			else:
				var remove_file_error := directory.remove(entry)
				if remove_file_error != OK:
					last_error = "Could not delete map file %s (%s)." % [entry, error_string(remove_file_error)]
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	var remove_directory_error := DirAccess.remove_absolute(absolute_path)
	if remove_directory_error != OK:
		last_error = "Could not delete the map directory (%s)." % error_string(remove_directory_error)
		return false
	return true


func _next_version_number(family_path: String) -> int:
	var highest := 0
	var directory := DirAccess.open(family_path)
	if directory != null:
		directory.list_dir_begin()
		var entry := directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir() and entry.begins_with("v"):
				highest = maxi(highest, entry.trim_prefix("v").to_int())
			entry = directory.get_next()
		directory.list_dir_end()
	var stored_floor := 1
	var sequence_path := family_path.path_join(NEXT_VERSION_FILE_NAME)
	if FileAccess.file_exists(sequence_path):
		var sequence_text := FileAccess.get_file_as_string(sequence_path).strip_edges()
		if sequence_text.is_valid_int():
			stored_floor = maxi(sequence_text.to_int(), 1)
	return maxi(highest + 1, stored_floor)


func _record_next_version_floor(family_path: String, requested_floor: int) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(family_path))
	if directory_error != OK:
		last_error = "Could not preserve the map version sequence."
		return false
	var sequence_path := family_path.path_join(NEXT_VERSION_FILE_NAME)
	var sequence_value = str(maxi(requested_floor, _next_version_number(family_path)))
	if not TrainingFileIO.write_text_atomic(sequence_path, sequence_value):
		last_error = "Could not preserve the map version sequence."
		return false
	return true


func _map_key(map_name: String) -> String:
	return TrainingFileIO.storage_key(map_name, "training-map")
