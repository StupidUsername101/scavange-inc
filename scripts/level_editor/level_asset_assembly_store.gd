class_name LevelAssetAssemblyStore
extends RefCounted

const FORMAT_NAME := "scavange_level_assemblies"
const FORMAT_VERSION := 2
const MINIMUM_SUPPORTED_VERSION := 1
const DEFAULT_PATH := "user://level_editor/assemblies.json"
const MAXIMUM_NAME_LENGTH := 64


static func load_definitions(path := DEFAULT_PATH) -> Dictionary[String, Dictionary]:
	var result: Dictionary[String, Dictionary] = {}
	if not FileAccess.file_exists(path):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return result
	var data := parsed as Dictionary
	if (
		str(data.get("format", "")) != FORMAT_NAME
		or int(data.get("version", 0)) < MINIMUM_SUPPORTED_VERSION
		or int(data.get("version", 0)) > FORMAT_VERSION
	):
		return result
	var raw_definitions: Variant = data.get("assemblies", [])
	if not raw_definitions is Array:
		return result
	for raw_definition: Variant in raw_definitions:
		if not raw_definition is Dictionary:
			continue
		var definition := sanitize_definition(raw_definition)
		var definition_id := str(definition.get("id", ""))
		if definition.is_empty() or result.has(definition_id):
			continue
		result[definition_id] = definition
	return result


static func save_definitions(
	definitions: Dictionary,
	path := DEFAULT_PATH
) -> Error:
	var serialized: Array[Dictionary] = []
	var ids := PackedStringArray()
	for id_value: Variant in definitions.keys():
		ids.append(str(id_value))
	ids.sort()
	for definition_id: String in ids:
		var raw: Variant = definitions.get(definition_id, {})
		if not raw is Dictionary:
			continue
		var definition := sanitize_definition(raw)
		if definition.is_empty():
			continue
		var serialized_parts: Array[Dictionary] = []
		for part: Dictionary in definition.get("parts", []):
			serialized_parts.append({
				"asset_path": part["asset_path"],
				"position": _vector3_to_array(part["position"]),
				"rotation": _vector3_to_array(part["rotation"]),
				"scale": _vector3_to_array(part["scale"]),
				"acoustic_boundary": bool(part.get("acoustic_boundary", true)),
				"gameplay_role": str(part.get(
					"gameplay_role",
					LevelEditorDocument.PLACEMENT_ROLE_STATIC
				)),
				"item_mass_kg": float(part.get("item_mass_kg", 1.0)),
				"value_per_mass": float(part.get("value_per_mass", 0.0)),
			})
		serialized.append({
			"id": definition["id"],
			"name": definition["name"],
			"parts": serialized_parts,
		})
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"assemblies": serialized,
	}, "  "))
	file.flush()
	return file.get_error()


static func create_definition(
	display_name: String,
	placement_snapshots: Array[Dictionary],
	world_pivot: Vector3,
	existing_ids: Dictionary = {}
) -> Dictionary:
	var clean_name := _sanitize_name(display_name)
	if clean_name.is_empty() or placement_snapshots.is_empty() or not world_pivot.is_finite():
		return {}
	var parts: Array[Dictionary] = []
	for snapshot: Dictionary in placement_snapshots:
		var safe := LevelEditorDocument.sanitize_placement(snapshot)
		if safe.is_empty():
			continue
		parts.append({
			"asset_path": safe["asset_path"],
			"position": (safe["position"] as Vector3) - world_pivot,
			"rotation": safe["rotation"],
			"scale": safe["scale"],
			"acoustic_boundary": bool(safe.get("acoustic_boundary", true)),
			"gameplay_role": safe.get(
				"gameplay_role",
				LevelEditorDocument.PLACEMENT_ROLE_STATIC
			),
			"item_mass_kg": float(safe.get("item_mass_kg", 1.0)),
			"value_per_mass": float(safe.get("value_per_mass", 0.0)),
		})
	if parts.is_empty():
		return {}
	var slug := clean_name.to_snake_case()
	if slug.is_empty():
		slug = "assembly"
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var suffix := 0
	var definition_id := "%s_%d" % [slug, stamp]
	while existing_ids.has(definition_id):
		suffix += 1
		definition_id = "%s_%d_%d" % [slug, stamp, suffix]
	return {
		"id": definition_id,
		"name": clean_name,
		"parts": parts,
	}


static func sanitize_definition(raw: Dictionary) -> Dictionary:
	var definition_id := str(raw.get("id", "")).strip_edges()
	var display_name := _sanitize_name(str(raw.get("name", "")))
	if definition_id.is_empty() or display_name.is_empty():
		return {}
	var parts: Array[Dictionary] = []
	var raw_parts: Variant = raw.get("parts", [])
	if not raw_parts is Array:
		return {}
	for raw_part: Variant in raw_parts:
		if not raw_part is Dictionary:
			continue
		var part := sanitize_part(raw_part)
		if not part.is_empty():
			parts.append(part)
	if parts.is_empty():
		return {}
	return {
		"id": definition_id.left(128),
		"name": display_name,
		"parts": parts,
	}


static func sanitize_part(raw: Dictionary) -> Dictionary:
	var asset_path := str(raw.get("asset_path", "")).strip_edges()
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
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
		"asset_path": asset_path,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"acoustic_boundary": bool(raw.get("acoustic_boundary", true)),
		"gameplay_role": LevelEditorDocument.sanitize_gameplay_role(raw.get(
			"gameplay_role",
			LevelEditorDocument.PLACEMENT_ROLE_STATIC
		)),
		"item_mass_kg": clampf(
			SafeVariant.finite_float_or(raw.get("item_mass_kg"), 1.0),
			LevelEditorDocument.MINIMUM_ITEM_MASS_KG,
			LevelEditorDocument.MAXIMUM_ITEM_MASS_KG
		),
		"value_per_mass": clampf(
			SafeVariant.finite_float_or(raw.get("value_per_mass"), 0.0),
			0.0,
			LevelEditorDocument.MAXIMUM_VALUE_PER_MASS
		),
	}


static func _sanitize_name(value: String) -> String:
	return value.strip_edges().replace("\n", " ").replace("\r", " ").left(
		MAXIMUM_NAME_LENGTH
	)


static func _finite_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	if value is Array and (value as Array).size() == 3:
		var result := Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
		if result.is_finite():
			return result
	return fallback


static func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
