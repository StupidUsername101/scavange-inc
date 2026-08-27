class_name LevelEditorDocument
extends RefCounted

const FORMAT_NAME := "scavange_level"
const FORMAT_VERSION := 1
const DEFAULT_DIRECTORY := "user://levels"
const DEFAULT_FILE_NAME := "untitled_level.json"

var level_name := "Untitled Level"
var placements: Array[Dictionary] = []
var next_placement_id := 1


func clear() -> void:
	level_name = "Untitled Level"
	placements.clear()
	next_placement_id = 1


func allocate_placement_id() -> int:
	var result := next_placement_id
	next_placement_id += 1
	return result


func to_dictionary() -> Dictionary:
	var serialized_placements: Array[Dictionary] = []
	for placement: Dictionary in placements:
		var safe := sanitize_placement(placement)
		if safe.is_empty():
			continue
		serialized_placements.append({
			"id": safe["id"],
			"asset_path": safe["asset_path"],
			"position": _vector3_to_array(safe["position"]),
			"rotation": _vector3_to_array(safe["rotation"]),
			"scale": _vector3_to_array(safe["scale"]),
		})
	return {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"name": level_name.strip_edges(),
		"next_placement_id": next_placement_id,
		"placements": serialized_placements,
	}


func save_to_path(path: String) -> Error:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	file.flush()
	return file.get_error()


static func load_from_path(path: String) -> LevelEditorDocument:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return null
	var data: Dictionary = parsed
	if (
		str(data.get("format", "")) != FORMAT_NAME
		or int(data.get("version", 0)) != FORMAT_VERSION
	):
		return null
	var document := LevelEditorDocument.new()
	document.level_name = str(data.get("name", "Untitled Level")).strip_edges()
	if document.level_name.is_empty():
		document.level_name = "Untitled Level"
	var maximum_id := 0
	var live_ids: Dictionary[int, bool] = {}
	var raw_placements: Variant = data.get("placements", [])
	if raw_placements is Array:
		for raw_placement: Variant in raw_placements:
			if not raw_placement is Dictionary:
				continue
			var placement := sanitize_placement(raw_placement)
			var placement_id := int(placement.get("id", 0))
			if placement.is_empty() or live_ids.has(placement_id):
				continue
			live_ids[placement_id] = true
			document.placements.append(placement)
			maximum_id = maxi(maximum_id, placement_id)
	document.next_placement_id = maxi(
		int(data.get("next_placement_id", maximum_id + 1)),
		maximum_id + 1
	)
	return document


static func sanitize_placement(raw: Dictionary) -> Dictionary:
	var asset_path := str(raw.get("asset_path", "")).strip_edges()
	var placement_id := int(raw.get("id", 0))
	if placement_id <= 0 or not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return {}
	var position := _finite_vector3(raw.get("position", Vector3.ZERO), Vector3.ZERO)
	var rotation := _finite_vector3(raw.get("rotation", Vector3.ZERO), Vector3.ZERO)
	var scale := _finite_vector3(raw.get("scale", Vector3.ONE), Vector3.ONE)
	scale = Vector3(
		clampf(absf(scale.x), 0.001, 1000.0),
		clampf(absf(scale.y), 0.001, 1000.0),
		clampf(absf(scale.z), 0.001, 1000.0)
	)
	return {
		"id": placement_id,
		"asset_path": asset_path,
		"position": position,
		"rotation": rotation,
		"scale": scale,
	}


static func _finite_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		var result := Vector3(
			SafeVariant.finite_float_or(array[0], fallback.x),
			SafeVariant.finite_float_or(array[1], fallback.y),
			SafeVariant.finite_float_or(array[2], fallback.z)
		)
		return result if result.is_finite() else fallback
	return fallback


static func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
