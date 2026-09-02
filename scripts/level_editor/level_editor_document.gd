class_name LevelEditorDocument
extends RefCounted

const LIGHT_AUTHORING := preload(
	"res://scripts/level_editor/level_light_authoring.gd"
)
const FORMAT_NAME := "scavange_level"
const FORMAT_VERSION := 7
const MINIMUM_SUPPORTED_VERSION := 1
const DEFAULT_DIRECTORY := "user://levels"
const DEFAULT_FILE_NAME := "untitled_level.json"
const PLACEMENT_ROLE_STATIC := &"static"
const PLACEMENT_ROLE_ITEM := &"item"
const PLACEMENT_ROLE_VALUABLE := &"valuable"
const MINIMUM_ITEM_MASS_KG := 0.01
const MAXIMUM_ITEM_MASS_KG := 100000.0
const MAXIMUM_VALUE_PER_MASS := 1000000000.0

var level_name := "Untitled Level"
var placements: Array[Dictionary] = []
var acoustic_probes: Array[Dictionary] = []
var acoustic_portals: Array[Dictionary] = []
var sound_systems: Array[Dictionary] = []
var authored_lights: Array[Dictionary] = []
var next_placement_id := 1
var next_acoustic_id := 1
var next_assembly_group_id := 1
var next_building_group_id := 1
var next_sound_system_id := 1
var next_light_id := 1


func clear() -> void:
	level_name = "Untitled Level"
	placements.clear()
	acoustic_probes.clear()
	acoustic_portals.clear()
	sound_systems.clear()
	authored_lights.clear()
	next_placement_id = 1
	next_acoustic_id = 1
	next_assembly_group_id = 1
	next_building_group_id = 1
	next_sound_system_id = 1
	next_light_id = 1


func allocate_placement_id() -> int:
	var result := next_placement_id
	next_placement_id += 1
	return result


func allocate_acoustic_id() -> int:
	var result := next_acoustic_id
	next_acoustic_id += 1
	return result


func allocate_assembly_group_id() -> int:
	var result := next_assembly_group_id
	next_assembly_group_id += 1
	return result


func allocate_building_group_id() -> int:
	var result := next_building_group_id
	next_building_group_id += 1
	return result


func allocate_sound_system_id() -> int:
	var result := next_sound_system_id
	next_sound_system_id += 1
	return result


func allocate_light_id() -> int:
	var result := next_light_id
	next_light_id += 1
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
			"acoustic_boundary": bool(safe.get("acoustic_boundary", true)),
			"gameplay_role": str(safe.get("gameplay_role", PLACEMENT_ROLE_STATIC)),
			"item_mass_kg": float(safe.get("item_mass_kg", 1.0)),
			"value_per_mass": float(safe.get("value_per_mass", 0.0)),
			"assembly_group_id": int(safe.get("assembly_group_id", 0)),
			"assembly_definition_id": str(
				safe.get("assembly_definition_id", "")
			),
			"building_group_id": int(safe.get("building_group_id", 0)),
			"building_storey": int(safe.get("building_storey", 0)),
		})
	var serialized_probes: Array[Dictionary] = []
	for raw_probe: Dictionary in acoustic_probes:
		var probe := LevelAcousticAuthoring.sanitize_probe(raw_probe)
		if probe.is_empty():
			continue
		probe["position"] = _vector3_to_array(probe["position"])
		serialized_probes.append(probe)
	var serialized_portals: Array[Dictionary] = []
	for raw_portal: Dictionary in acoustic_portals:
		var portal := LevelAcousticAuthoring.sanitize_portal(raw_portal)
		if not portal.is_empty():
			serialized_portals.append(portal)
	var serialized_sound_systems: Array[Dictionary] = []
	for raw_system: Dictionary in sound_systems:
		var system := LevelSpeakerSystemAuthoring.serialize_system(raw_system)
		if not system.is_empty():
			serialized_sound_systems.append(system)
	var serialized_lights: Array[Dictionary] = []
	for raw_light: Dictionary in authored_lights:
		var light: Dictionary = LIGHT_AUTHORING.serialize_descriptor(raw_light)
		if not light.is_empty():
			serialized_lights.append(light)
	return {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"name": level_name.strip_edges(),
		"next_placement_id": next_placement_id,
		"next_acoustic_id": next_acoustic_id,
		"next_assembly_group_id": next_assembly_group_id,
		"next_building_group_id": next_building_group_id,
		"next_sound_system_id": next_sound_system_id,
		"next_light_id": next_light_id,
		"placements": serialized_placements,
		"acoustic_probes": serialized_probes,
		"acoustic_portals": serialized_portals,
		"sound_systems": serialized_sound_systems,
		"authored_lights": serialized_lights,
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
	var version := int(data.get("version", 0))
	if (
		str(data.get("format", "")) != FORMAT_NAME
		or version < MINIMUM_SUPPORTED_VERSION
		or version > FORMAT_VERSION
	):
		return null
	var document := LevelEditorDocument.new()
	document.level_name = str(data.get("name", "Untitled Level")).strip_edges()
	if document.level_name.is_empty():
		document.level_name = "Untitled Level"
	var maximum_id := 0
	var maximum_assembly_group_id := 0
	var maximum_building_group_id := 0
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
			maximum_assembly_group_id = maxi(
				maximum_assembly_group_id,
				int(placement.get("assembly_group_id", 0))
			)
			maximum_building_group_id = maxi(
				maximum_building_group_id,
				int(placement.get("building_group_id", 0))
			)
	document.next_placement_id = maxi(
		int(data.get("next_placement_id", maximum_id + 1)),
		maximum_id + 1
	)
	document.next_assembly_group_id = maxi(
		int(data.get(
			"next_assembly_group_id",
			maximum_assembly_group_id + 1
		)),
		maximum_assembly_group_id + 1
	)
	document.next_building_group_id = maxi(
		int(data.get(
			"next_building_group_id",
			maximum_building_group_id + 1
		)),
		maximum_building_group_id + 1
	)
	var maximum_acoustic_id := 0
	var live_probe_ids: Dictionary[int, bool] = {}
	var raw_probes: Variant = data.get("acoustic_probes", [])
	if raw_probes is Array:
		for raw_probe: Variant in raw_probes:
			if not raw_probe is Dictionary:
				continue
			var probe := LevelAcousticAuthoring.sanitize_probe(raw_probe)
			var probe_id := int(probe.get("id", 0))
			if probe.is_empty() or live_probe_ids.has(probe_id):
				continue
			live_probe_ids[probe_id] = true
			document.acoustic_probes.append(probe)
			maximum_acoustic_id = maxi(maximum_acoustic_id, probe_id)
	var live_portal_ids: Dictionary[int, bool] = {}
	var raw_portals: Variant = data.get("acoustic_portals", [])
	if raw_portals is Array:
		for raw_portal: Variant in raw_portals:
			if not raw_portal is Dictionary:
				continue
			var portal := LevelAcousticAuthoring.sanitize_portal(raw_portal)
			var portal_id := int(portal.get("id", 0))
			if (
				portal.is_empty()
				or live_portal_ids.has(portal_id)
				or not live_probe_ids.has(int(portal.get("probe_a_id", 0)))
				or not live_probe_ids.has(int(portal.get("probe_b_id", 0)))
			):
				continue
			live_portal_ids[portal_id] = true
			document.acoustic_portals.append(portal)
			maximum_acoustic_id = maxi(maximum_acoustic_id, portal_id)
	document.next_acoustic_id = maxi(
		int(data.get("next_acoustic_id", maximum_acoustic_id + 1)),
		maximum_acoustic_id + 1
	)
	var maximum_sound_system_id := 0
	var live_sound_system_ids: Dictionary[int, bool] = {}
	var live_contact_ids: Dictionary[String, bool] = {}
	var raw_sound_systems: Variant = data.get("sound_systems", [])
	if raw_sound_systems is Array:
		for raw_system: Variant in raw_sound_systems:
			if not raw_system is Dictionary:
				continue
			var system := LevelSpeakerSystemAuthoring.sanitize_system(raw_system)
			var system_id := int(system.get("id", 0))
			var contact_id := str(system.get("contact_id", ""))
			if (
				system.is_empty()
				or live_sound_system_ids.has(system_id)
				or live_contact_ids.has(contact_id)
			):
				continue
			live_sound_system_ids[system_id] = true
			live_contact_ids[contact_id] = true
			document.sound_systems.append(system)
			maximum_sound_system_id = maxi(maximum_sound_system_id, system_id)
	document.next_sound_system_id = maxi(
		int(data.get(
			"next_sound_system_id",
			maximum_sound_system_id + 1
		)),
		maximum_sound_system_id + 1
	)
	var maximum_light_id := 0
	var live_light_ids: Dictionary[int, bool] = {}
	var raw_lights: Variant = data.get("authored_lights", [])
	if raw_lights is Array:
		for raw_light: Variant in raw_lights:
			if not raw_light is Dictionary:
				continue
			var light: Dictionary = LIGHT_AUTHORING.sanitize_descriptor(raw_light)
			var light_id := int(light.get("id", 0))
			if light.is_empty() or live_light_ids.has(light_id):
				continue
			live_light_ids[light_id] = true
			document.authored_lights.append(light)
			maximum_light_id = maxi(maximum_light_id, light_id)
	document.next_light_id = maxi(
		int(data.get("next_light_id", maximum_light_id + 1)),
		maximum_light_id + 1
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
		"acoustic_boundary": bool(raw.get("acoustic_boundary", true)),
		"gameplay_role": sanitize_gameplay_role(raw.get(
			"gameplay_role",
			PLACEMENT_ROLE_STATIC
		)),
		"item_mass_kg": clampf(
			SafeVariant.finite_float_or(raw.get("item_mass_kg"), 1.0),
			MINIMUM_ITEM_MASS_KG,
			MAXIMUM_ITEM_MASS_KG
		),
		"value_per_mass": clampf(
			SafeVariant.finite_float_or(raw.get("value_per_mass"), 0.0),
			0.0,
			MAXIMUM_VALUE_PER_MASS
		),
		"assembly_group_id": maxi(int(raw.get("assembly_group_id", 0)), 0),
		"assembly_definition_id": str(
			raw.get("assembly_definition_id", "")
		).strip_edges().left(128),
		"building_group_id": maxi(int(raw.get("building_group_id", 0)), 0),
		"building_storey": maxi(int(raw.get("building_storey", 0)), 0),
	}


static func sanitize_gameplay_role(value: Variant) -> StringName:
	var role := StringName(str(value).strip_edges().to_lower())
	if role == PLACEMENT_ROLE_ITEM or role == PLACEMENT_ROLE_VALUABLE:
		return role
	return PLACEMENT_ROLE_STATIC


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
