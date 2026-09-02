class_name LevelRuntimeSelection
extends RefCounted

const CONFIG_PATH := "user://level_editor/active_level.cfg"
const SECTION := "runtime"
const KEY_PATH := "level_path"


static func set_active_level(path: String) -> Error:
	var safe_path := path.strip_edges().simplify_path()
	var level_root := LevelEditorDocument.DEFAULT_DIRECTORY.simplify_path() + "/"
	if not safe_path.begins_with(level_root) or not FileAccess.file_exists(safe_path):
		return ERR_INVALID_PARAMETER
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_PATH, safe_path)
	return config.save(CONFIG_PATH)


static func active_level_path() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return ""
	var path := str(config.get_value(SECTION, KEY_PATH, "")).strip_edges().simplify_path()
	var level_root := LevelEditorDocument.DEFAULT_DIRECTORY.simplify_path() + "/"
	if not path.begins_with(level_root) or not FileAccess.file_exists(path):
		return ""
	return path
