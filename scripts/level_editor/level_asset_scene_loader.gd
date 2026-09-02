class_name LevelAssetSceneLoader
extends RefCounted

## Loads ordinary imported scenes when available and falls back to Godot's
## runtime GLTF importer for source-vault GLBs hidden behind .gdignore. A small
## LRU keeps previewing and placing the same model from parsing it twice while
## avoiding a permanent cache of the complete commercial bundle.

const MAXIMUM_CACHED_SCENES := 24
const ASSET_CATALOG := preload("res://scripts/level_editor/level_asset_catalog.gd")
const DETACHED_PIVOT_MINIMUM_GAP := 0.5
const DETACHED_PIVOT_RELATIVE_GAP := 0.5
const Z_UP_NATURE_SOURCE_SEGMENT := "/psx nature (tree branches separated)/"

static var _scene_cache: Dictionary[String, PackedScene] = {}
static var _failed_paths: Dictionary[String, bool] = {}
static var _cache_order: Array[String] = []


static func instantiate(asset_path: String) -> Node3D:
	var source_scene := packed_scene(asset_path)
	if source_scene == null:
		return null
	var instance := source_scene.instantiate() as Node3D
	if instance != null:
		_normalize_editor_instance(asset_path, instance)
	return instance


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


static func _normalize_editor_instance(asset_path: String, root: Node3D) -> void:
	# This optional Nature source set is exported in the author's Blender Z-up
	# layout, unlike the otherwise identical ready-to-use set. Preserve its
	# separately addressable meshes, but convert the root once for every editor
	# consumer (thumbnail, preview, picking, and final placement).
	if asset_path.to_lower().contains(Z_UP_NATURE_SOURCE_SEGMENT):
		root.transform = (
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
			* root.transform
		)

	var bounds := _visual_bounds(root)
	if not _has_detached_authoring_pivot(bounds):
		return
	# Some source GLBs retain their position in the artist's large collection
	# scene (up to 55 m away). Rebase only clearly detached pivots. Corner and
	# edge pivots used by modular construction pieces remain untouched.
	var center := bounds.get_center()
	root.position -= Vector3(center.x, bounds.position.y, center.z)


static func _has_detached_authoring_pivot(bounds: AABB) -> bool:
	if (
		not bounds.position.is_finite()
		or not bounds.size.is_finite()
		or bounds.size.length_squared() <= 0.000001
	):
		return false
	var end := bounds.end
	var nearest_to_origin := Vector3(
		clampf(0.0, bounds.position.x, end.x),
		clampf(0.0, bounds.position.y, end.y),
		clampf(0.0, bounds.position.z, end.z)
	)
	var allowed_gap := maxf(
		DETACHED_PIVOT_MINIMUM_GAP,
		bounds.size.length() * DETACHED_PIVOT_RELATIVE_GAP
	)
	return nearest_to_origin.length() > allowed_gap


static func _visual_bounds(root: Node3D) -> AABB:
	var state := {
		"found": false,
		"bounds": AABB(),
	}
	_collect_visual_bounds(root, Transform3D.IDENTITY, state)
	return state.get("bounds", AABB()) as AABB


static func _collect_visual_bounds(
	node: Node,
	parent_transform: Transform3D,
	state: Dictionary
) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var transformed_bounds := current_transform * mesh_instance.get_aabb()
			if bool(state.get("found", false)):
				state["bounds"] = (
					(state.get("bounds") as AABB).merge(transformed_bounds)
				)
			else:
				state["bounds"] = transformed_bounds
				state["found"] = true
	for child: Node in node.get_children():
		_collect_visual_bounds(child, current_transform, state)
