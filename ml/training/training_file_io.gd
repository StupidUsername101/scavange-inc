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
