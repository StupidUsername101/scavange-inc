class_name LevelAssetAssemblyPreview
extends Node3D

var definition_id := ""
var local_bounds := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
var parts: Array[LevelAssetPlacement] = []


func configure(definition_value: Dictionary) -> bool:
	var definition := LevelAssetAssemblyStore.sanitize_definition(definition_value)
	if definition.is_empty():
		return false
	definition_id = str(definition.get("id", ""))
	var found_bounds := false
	for part_value: Dictionary in definition.get("parts", []):
		var part := LevelAssetPlacement.new()
		add_child(part)
		if not part.configure(0, str(part_value.get("asset_path", ""))):
			remove_child(part)
			part.free()
			continue
		part.position = part_value.get("position", Vector3.ZERO)
		part.rotation = part_value.get("rotation", Vector3.ZERO)
		part.scale = part_value.get("scale", Vector3.ONE)
		part.acoustic_boundary = bool(part_value.get("acoustic_boundary", true))
		part.gameplay_role = part_value.get(
			"gameplay_role",
			LevelEditorDocument.PLACEMENT_ROLE_STATIC
		)
		part.item_mass_kg = float(part_value.get("item_mass_kg", 1.0))
		part.value_per_mass = float(part_value.get("value_per_mass", 0.0))
		part.process_mode = Node.PROCESS_MODE_DISABLED
		part.set_selected(true)
		parts.append(part)
		var part_bounds := part.transform * part.local_bounds
		local_bounds = local_bounds.merge(part_bounds) if found_bounds else part_bounds
		found_bounds = true
	return found_bounds


func surface_support_distance(world_normal: Vector3) -> float:
	if world_normal.length_squared() <= 0.000001:
		return 0.0
	var normal := world_normal.normalized()
	var bounds_end := local_bounds.end
	var minimum_projection := INF
	for x: float in [local_bounds.position.x, bounds_end.x]:
		for y: float in [local_bounds.position.y, bounds_end.y]:
			for z: float in [local_bounds.position.z, bounds_end.z]:
				var relative_corner := transform.basis * Vector3(x, y, z)
				minimum_projection = minf(
					minimum_projection,
					relative_corner.dot(normal)
				)
	return -minimum_projection if is_finite(minimum_projection) else 0.0
