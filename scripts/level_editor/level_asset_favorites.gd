class_name LevelAssetFavorites
extends RefCounted

const DEFAULT_PATH := "user://level_editor_asset_favorites.cfg"
const SECTION := "asset_browser"
const KEY := "favorite_paths"


static func load_paths(path := DEFAULT_PATH) -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return result
	var stored: Variant = config.get_value(SECTION, KEY, PackedStringArray())
	if stored is PackedStringArray:
		for asset_path: String in stored:
			if not asset_path.is_empty():
				result[asset_path] = true
	elif stored is Array:
		for value: Variant in stored:
			var asset_path := str(value)
			if not asset_path.is_empty():
				result[asset_path] = true
	return result


static func save_paths(
	favorite_paths: Dictionary,
	path := DEFAULT_PATH
) -> Error:
	var sorted_paths := PackedStringArray()
	for asset_path_value: Variant in favorite_paths.keys():
		var asset_path := str(asset_path_value)
		if bool(favorite_paths.get(asset_path_value, false)) and not asset_path.is_empty():
			sorted_paths.append(asset_path)
	sorted_paths.sort()
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY, sorted_paths)
	return config.save(path)
