class_name TrainingFileIO
extends RefCounted

#######################################################
# Shared low-level persistence primitives for training registries. Keep atomic promotion/backup
# behavior in one place so model, map and reward-card stores cannot drift subtly over time.
#######################################################


static func read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func write_text_atomic(path: String, content: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var unique_suffix: int = Time.get_ticks_usec()
	var temporary_path: String = "%s.tmp-%d" % [absolute_path, unique_suffix]
	var backup_path: String = "%s.backup-%d" % [absolute_path, unique_suffix]
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	var had_existing: bool = FileAccess.file_exists(absolute_path)
	if had_existing:
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
	var promote_error: Error = DirAccess.rename_absolute(temporary_path, absolute_path)
	if promote_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temporary_path)
		return false
	if had_existing:
		DirAccess.remove_absolute(backup_path)
	return true


static func remove_directory_recursive_absolute(absolute_path: String) -> bool:
	var directory: DirAccess = DirAccess.open(absolute_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = absolute_path.path_join(entry)
			if directory.current_is_dir():
				if not remove_directory_recursive_absolute(child_path):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute_path) == OK


static func storage_key(value: String, fallback: String) -> String:
	var result: String = ""
	var separator: bool = false
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1).to_lower()
		if "abcdefghijklmnopqrstuvwxyz0123456789".contains(character):
			result += character
			separator = false
		elif not separator and not result.is_empty():
			result += "-"
			separator = true
	result = result.trim_suffix("-")
	return result if not result.is_empty() else fallback


static func next_version_directory_number(
	path: String,
	next_version_file_name: String = ""
) -> int:
	var highest: int = 0
	var directory: DirAccess = DirAccess.open(path)
	if directory != null:
		directory.list_dir_begin()
		var entry: String = directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir() and entry.begins_with("v"):
				var suffix: String = entry.trim_prefix("v")
				if suffix.is_valid_int():
					highest = maxi(highest, suffix.to_int())
			entry = directory.get_next()
		directory.list_dir_end()
	var result: int = highest + 1
	if not next_version_file_name.is_empty():
		var floor_path: String = path.path_join(next_version_file_name)
		if FileAccess.file_exists(floor_path):
			var floor_text: String = FileAccess.get_file_as_string(floor_path).strip_edges()
			if floor_text.is_valid_int():
				result = maxi(result, maxi(floor_text.to_int(), 1))
	return result


static func preserve_next_version_floor(
	path: String,
	next_version_file_name: String,
	requested_floor: int
) -> bool:
	if path.is_empty() or next_version_file_name.is_empty():
		return false
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path)
	)
	if directory_error != OK:
		return false
	var next_floor: int = maxi(
		requested_floor,
		next_version_directory_number(path, next_version_file_name)
	)
	return write_text_atomic(path.path_join(next_version_file_name), str(next_floor))
