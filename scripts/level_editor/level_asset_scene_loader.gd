class_name LevelAssetSceneLoader
extends RefCounted

## Loads ordinary imported scenes when available and falls back to Godot's
## runtime GLTF importer for source-vault GLBs hidden behind .gdignore. A small
## LRU keeps previewing and placing the same model from parsing it twice while
## avoiding a permanent cache of the complete commercial bundle.

const MAXIMUM_CACHED_SCENES := 24
const ASSET_CATALOG := preload("res://scripts/level_editor/level_asset_catalog.gd")

static var _scene_cache: Dictionary[String, PackedScene] = {}
static var _failed_paths: Dictionary[String, bool] = {}
static var _cache_order: Array[String] = []


static func instantiate(asset_path: String) -> Node3D:
	var packed_scene := packed_scene(asset_path)
	return packed_scene.instantiate() as Node3D if packed_scene != null else null


static func packed_scene(asset_path: String) -> PackedScene:
	if _scene_cache.has(asset_path):
		_touch_cache_entry(asset_path)
		return _scene_cache[asset_path]
	if _failed_paths.has(asset_path) or not ASSET_CATALOG.is_valid_asset_path(asset_path):
		return null

	var result := _load_imported_scene(asset_path)
	if result == null:
		result = _import_source_glb(asset_path)
	if result == null:
		_failed_paths[asset_path] = true
		return null
	_scene_cache[asset_path] = result
	_cache_order.append(asset_path)
	_trim_cache()
	return result


static func clear_cache() -> void:
	_scene_cache.clear()
	_failed_paths.clear()
	_cache_order.clear()


static func _load_imported_scene(asset_path: String) -> PackedScene:
	var import_sidecar := asset_path + ".import"
	if not FileAccess.file_exists(import_sidecar):
		return null
	var import_text := FileAccess.get_file_as_string(import_sidecar)
	if import_text.contains("valid=false") or not import_text.contains("type=\"PackedScene\""):
		return null
	return ResourceLoader.load(
		asset_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene


static func _import_source_glb(asset_path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var absolute_path := ProjectSettings.globalize_path(asset_path)
	var import_error := document.append_from_file(absolute_path, state)
	if import_error != OK:
		push_warning(
			"Level editor could not import %s: %s"
			% [asset_path, error_string(import_error)]
		)
		return null
	var generated := document.generate_scene(state)
	if generated == null:
		return null
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(generated)
	generated.free()
	if pack_error != OK:
		push_warning(
			"Level editor could not pack %s: %s"
			% [asset_path, error_string(pack_error)]
		)
		return null
	return packed_scene


static func _touch_cache_entry(asset_path: String) -> void:
	_cache_order.erase(asset_path)
	_cache_order.append(asset_path)


static func _trim_cache() -> void:
	while _cache_order.size() > MAXIMUM_CACHED_SCENES:
		var stale_path: String = _cache_order.pop_front()
		_scene_cache.erase(stale_path)
