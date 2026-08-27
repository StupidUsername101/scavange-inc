class_name ModularStructureAssembler
extends RefCounted

## Shared assembly path for repeated level modules. It owns no probe logic: future acoustic
## analysis can consume the resulting baked world geometry without structure assets knowing about
## acoustics.


static func linear_module_descriptors(
	definition: ModularStructureDefinition,
	center: Vector3,
	floor_y: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if definition == null or not definition.is_valid():
		return result
	var bounds := definition.scaled_source_bounds()
	var size := bounds.size
	var first_min_z := center.z - definition.total_length() * 0.5
	var target_min_x := center.x - size.x * 0.5
	for module_index: int in range(definition.module_count):
		var target_min := Vector3(
			target_min_x,
			floor_y,
			first_min_z + float(module_index) * size.z
		)
		result.append({
			"name": StringName("%s%02d" % [definition.module_name_prefix, module_index]),
			"position": target_min - bounds.position,
			"rotation": Vector3.ZERO,
			"scale": definition.module_scale,
			"module_index": module_index,
		})
	return result


static func collision_descriptors(
	definition: ModularStructureDefinition,
	center: Vector3,
	floor_y: float
) -> Array[Dictionary]:
	if definition == null:
		return []
	match definition.collision_profile:
		ModularStructureDefinition.PROFILE_ARCHED_TUNNEL:
			return _arched_tunnel_collision_descriptors(definition, center, floor_y)
		_:
			push_warning(
				"Unsupported modular collision profile: %s"
				% definition.collision_profile
			)
			return []


static func instantiate_visual_chain(
	parent: Node3D,
	module_scene: PackedScene,
	descriptors: Array[Dictionary],
	container_name := &"ModularStructureVisuals"
) -> Node3D:
	if parent == null or module_scene == null:
		return null
	var container := Node3D.new()
	container.name = str(container_name)
	parent.add_child(container)
	for descriptor: Dictionary in descriptors:
		var instance := module_scene.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = str(descriptor.get("name", &"StructureModule"))
		instance.position = descriptor.get("position", Vector3.ZERO)
		instance.rotation = descriptor.get("rotation", Vector3.ZERO)
		instance.scale = descriptor.get("scale", Vector3.ONE)
		container.add_child(instance)
	return container


static func module_world_bounds(
	definition: ModularStructureDefinition,
	descriptor: Dictionary
) -> AABB:
	if definition == null:
		return AABB()
	var transform := Transform3D(
		Basis.from_euler(descriptor.get("rotation", Vector3.ZERO)).scaled(
			descriptor.get("scale", Vector3.ONE)
		),
		descriptor.get("position", Vector3.ZERO)
	)
	return transform * definition.source_bounds


static func assembly_world_bounds(
	definition: ModularStructureDefinition,
	center: Vector3,
	floor_y: float
) -> AABB:
	var descriptors := linear_module_descriptors(definition, center, floor_y)
	if descriptors.is_empty():
		return AABB()
	var result := module_world_bounds(definition, descriptors[0])
	for descriptor_index: int in range(1, descriptors.size()):
		result = result.merge(module_world_bounds(definition, descriptors[descriptor_index]))
	return result


static func _arched_tunnel_collision_descriptors(
	definition: ModularStructureDefinition,
	center: Vector3,
	floor_y: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not definition.is_valid():
		return result
	var size := definition.module_size()
	var thickness := minf(
		definition.shell_thickness,
		minf(size.x, size.y) * 0.45
	)
	var half_outer_width := size.x * 0.5
	var half_inner_width := half_outer_width - thickness
	var lower_wall_height := clampf(
		size.y * definition.lower_wall_height_ratio,
		thickness,
		size.y - thickness * 2.0
	)
	var wall_top := floor_y + lower_wall_height
	var roof_peak := floor_y + size.y - thickness
	var roof_delta := Vector2(half_inner_width, wall_top - roof_peak)
	var roof_length := roof_delta.length()
	var roof_angle := atan2(roof_delta.y, roof_delta.x)
	var modules := linear_module_descriptors(definition, center, floor_y)
	for module_index: int in range(modules.size()):
		var module_bounds := module_world_bounds(definition, modules[module_index])
		var module_center := module_bounds.get_center()
		var prefix := "%s%02d" % [definition.module_name_prefix, module_index]
		result.append(_box(
			prefix + "Floor",
			Vector3(module_center.x, floor_y - definition.floor_thickness * 0.5, module_center.z),
			Vector3(size.x, definition.floor_thickness, size.z),
			Vector3.ZERO,
			&"tunnel_floor"
		))
		for side: float in [-1.0, 1.0]:
			var suffix := "L" if side < 0.0 else "R"
			result.append(_box(
				prefix + "Wall" + suffix,
				Vector3(
					module_center.x + side * (half_outer_width - thickness * 0.5),
					floor_y + lower_wall_height * 0.5,
					module_center.z
				),
				Vector3(thickness, lower_wall_height, size.z),
				Vector3.ZERO,
				&"tunnel_wall"
			))
			result.append(_box(
				prefix + "Roof" + suffix,
				Vector3(
					module_center.x + side * half_inner_width * 0.5,
					(wall_top + roof_peak) * 0.5,
					module_center.z
				),
				Vector3(roof_length, thickness, size.z),
				Vector3(0.0, 0.0, side * roof_angle),
				StringName("tunnel_roof_%s" % suffix.to_lower())
			))
	return result


static func _box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material_id: StringName
) -> Dictionary:
	return {
		"name": StringName(node_name),
		"position": position,
		"size": size,
		"rotation": rotation,
		"material_id": material_id,
		"visual": false,
	}
