class_name EnemyWoundPresentation3D
extends Node3D

const SKIN_SHADER: Shader = preload("res://shaders/enemy_wound_skin.gdshader")
const ANATOMY := preload("res://scripts/enemies/enemy_destructible_anatomy.gd")
const SDF_INTERIOR_SURFACE_BUILDER := preload(
	"res://scripts/destruction/sdf_interior_surface_builder.gd"
)
const MAX_WOUNDS := 24

var character_skin: PlayerCharacterSkin
var anatomy_definition: EnemyDestructibleAnatomyDefinition
var target_revision := -1
var target_wounds: Array[Dictionary] = []
var target_part_presence := {
	ANATOMY.PART_HEAD: true,
	ANATOMY.PART_TORSO: true,
	ANATOMY.PART_LEFT_ARM: true,
	ANATOMY.PART_RIGHT_ARM: true,
	ANATOMY.PART_LEFT_LEG: true,
	ANATOMY.PART_RIGHT_LEG: true,
}
var skin_materials: Array[ShaderMaterial] = []
var part_surface_nodes: Dictionary = {}
var part_surface_fields: Dictionary = {}
var _visible_aperture_count := 0
var _tissue_material: StandardMaterial3D
var _configured_variant_path := ""


func configure(
	skin: PlayerCharacterSkin,
	profile: EnemyDestructibleAnatomyDefinition = null
) -> void:
	if (
		skin == character_skin
		and profile == anatomy_definition
		and not skin_materials.is_empty()
		and _configured_variant_path == skin.get_variant_path()
	):
		return
	character_skin = skin
	anatomy_definition = profile
	_configured_variant_path = skin.get_variant_path() if skin != null else ""
	_install_skin_materials()
	_configure_part_surfaces()


func apply_state(value: Dictionary) -> void:
	if value.is_empty():
		return
	if anatomy_definition == null:
		var profile_path := str(value.get("profile_path", ""))
		if not profile_path.is_empty() and ResourceLoader.exists(profile_path):
			anatomy_definition = load(profile_path) as EnemyDestructibleAnatomyDefinition
			_configure_part_surfaces()
	var next_revision := int(value.get("revision", target_revision))
	var replicated_presence: Variant = value.get("part_presence", {})
	if replicated_presence is Dictionary:
		for part_key: Variant in (replicated_presence as Dictionary).keys():
			target_part_presence[StringName(str(part_key))] = bool(
				(replicated_presence as Dictionary)[part_key]
			)
	target_part_presence[ANATOMY.PART_LEFT_ARM] = bool(
		value.get("left_arm", target_part_presence[ANATOMY.PART_LEFT_ARM])
	)
	target_part_presence[ANATOMY.PART_RIGHT_ARM] = bool(
		value.get("right_arm", target_part_presence[ANATOMY.PART_RIGHT_ARM])
	)
	target_part_presence[ANATOMY.PART_LEFT_LEG] = bool(
		value.get("left_leg", target_part_presence[ANATOMY.PART_LEFT_LEG])
	)
	target_part_presence[ANATOMY.PART_RIGHT_LEG] = bool(
		value.get("right_leg", target_part_presence[ANATOMY.PART_RIGHT_LEG])
	)
	if next_revision == target_revision:
		return
	target_revision = next_revision
	target_wounds.clear()
	var raw_wounds: Variant = value.get("wounds", [])
	if raw_wounds is Array:
		for wound_value: Variant in raw_wounds:
			if not wound_value is Dictionary or target_wounds.size() >= MAX_WOUNDS - 4:
				continue
			var wound := _sanitize_wound(wound_value)
			if not wound.is_empty():
				target_wounds.append(wound)
	_append_missing_limb_stumps()
	_rebuild_part_surfaces(value.get("deformation_events", []))


func update_presentation() -> void:
	if character_skin == null or not character_skin.is_usable():
		visible = false
		return
	visible = true
	character_skin.set_limb_presence(
		bool(target_part_presence[ANATOMY.PART_LEFT_ARM]),
		bool(target_part_presence[ANATOMY.PART_RIGHT_ARM]),
		bool(target_part_presence[ANATOMY.PART_LEFT_LEG]),
		bool(target_part_presence[ANATOMY.PART_RIGHT_LEG])
	)
	character_skin.set_head_presence(bool(target_part_presence[ANATOMY.PART_HEAD]))
	var entries := PackedVector4Array()
	var axes := PackedVector4Array()
	entries.resize(MAX_WOUNDS)
	axes.resize(MAX_WOUNDS)
	var visible_count := 0
	for wound_index: int in range(target_wounds.size()):
		var wound: Dictionary = target_wounds[wound_index]
		var part_id := StringName(str(wound.get("part", &"")))
		if not _part_is_present(part_id) and not bool(wound.get("stump", false)):
			continue
		var frame := _resolve_wound_world_frame(wound)
		var entry: Vector3 = frame["position"]
		var direction: Vector3 = frame["direction"]
		if direction.length_squared() <= 0.000001:
			direction = character_skin.global_basis.z
		direction = direction.normalized()
		var radius := float(wound.get("radius", 0.03))
		var depth := float(wound.get("depth", radius * 1.4))
		entries[visible_count] = Vector4(entry.x, entry.y, entry.z, radius)
		axes[visible_count] = Vector4(direction.x, direction.y, direction.z, depth)
		visible_count += 1
	for material: ShaderMaterial in skin_materials:
		material.set_shader_parameter(&"wound_count", visible_count)
		material.set_shader_parameter(&"wound_entries", entries)
		material.set_shader_parameter(&"wound_axes", axes)
	_visible_aperture_count = visible_count
	_update_part_surface_transforms()


func get_visible_wound_count() -> int:
	return _visible_aperture_count


func get_generated_tissue_triangle_count() -> int:
	var count := 0
	for node_value: Variant in part_surface_nodes.values():
		var node := node_value as MeshInstance3D
		if node == null or not node.mesh is ArrayMesh:
			continue
		var mesh := node.mesh as ArrayMesh
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			count += indices.size() / 3
	return count


func part_is_present(part_id: StringName) -> bool:
	return _part_is_present(part_id)


func _install_skin_materials() -> void:
	skin_materials.clear()
	if character_skin == null or not character_skin.is_usable():
		return
	for mesh_instance: MeshInstance3D in character_skin.skin_meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = SKIN_SHADER
			if source != null:
				material.set_shader_parameter(&"albedo_color", source.albedo_color)
				material.set_shader_parameter(&"albedo_texture", source.albedo_texture)
				material.set_shader_parameter(&"has_albedo_texture", source.albedo_texture != null)
				material.set_shader_parameter(&"material_roughness", source.roughness)
				material.set_shader_parameter(&"material_metallic", source.metallic)
			mesh_instance.set_surface_override_material(surface_index, material)
			skin_materials.append(material)


func _configure_part_surfaces() -> void:
	for node_value: Variant in part_surface_nodes.values():
		var old_node := node_value as MeshInstance3D
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()
	part_surface_nodes.clear()
	part_surface_fields.clear()
	if anatomy_definition == null:
		return
	_tissue_material = StandardMaterial3D.new()
	_tissue_material.albedo_color = Color.WHITE
	_tissue_material.vertex_color_use_as_albedo = true
	_tissue_material.vertex_color_is_srgb = false
	_tissue_material.roughness = anatomy_definition.damage_texture.roughness
	_tissue_material.metallic = anatomy_definition.damage_texture.metallic
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		var field := SparseSdfVolumeData.new().configure(
			part.sanitized_size(),
			anatomy_definition.voxel_size,
			anatomy_definition.brick_cells,
			anatomy_definition.damage_texture.material_index,
			4.0
		)
		part_surface_fields[part.part_id] = field
		var surface := MeshInstance3D.new()
		surface.name = "SdfTissue_%s" % part.part_id
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		surface.material_override = _tissue_material
		surface.visible = false
		add_child(surface)
		part_surface_nodes[part.part_id] = surface


func _rebuild_part_surfaces(raw_events: Variant) -> void:
	if anatomy_definition == null:
		return
	# Reconstruct from the immutable authored boxes on every authoritative revision. An enemy has only
	# a handful of tiny part fields; this avoids drift, event-order ambiguity, and host/client forks.
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		part_surface_fields[part.part_id] = SparseSdfVolumeData.new().configure(
			part.sanitized_size(),
			anatomy_definition.voxel_size,
			anatomy_definition.brick_cells,
			anatomy_definition.damage_texture.material_index,
			4.0
		)
		var reset_surface := part_surface_nodes.get(part.part_id) as MeshInstance3D
		if reset_surface != null:
			reset_surface.mesh = null
			reset_surface.visible = false
	var events: Array = raw_events if raw_events is Array else []
	if events.is_empty():
		events = _legacy_deformation_events_from_wounds()
	var changed_parts: Dictionary[StringName, bool] = {}
	for raw_event: Variant in events:
		if not raw_event is Dictionary:
			continue
		var event_state := raw_event as Dictionary
		var part_id := StringName(str(event_state.get("part", &"")))
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		if field == null:
			continue
		var damage_state: Variant = event_state.get("event", null)
		if not damage_state is Dictionary:
			continue
		var damage := DamageEvent.from_dict(damage_state)
		var local_position := damage.world_position
		var local_direction := damage.direction
		var local_normal := damage.normal
		var result := field.apply_damage_event(
			local_position,
			local_direction,
			local_normal,
			damage,
			anatomy_definition.damage_texture
		)
		if bool(result.get("geometry_changed", false)):
			changed_parts[part_id] = true
	for part_id: StringName in changed_parts.keys():
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		var surface := part_surface_nodes.get(part_id) as MeshInstance3D
		if field == null or surface == null:
			continue
		var build: Dictionary = SDF_INTERIOR_SURFACE_BUILDER.build(
			field,
			anatomy_definition.damage_texture
		)
		surface.mesh = build.get("mesh") as ArrayMesh
		surface.visible = surface.mesh != null and _part_is_present(part_id)


func _legacy_deformation_events_from_wounds() -> Array:
	# Compatibility for old captures and hand-authored tests. Live authority always supplies exact
	# canonical events; this path still uses the same SDF and mesher rather than reviving visual balls.
	var result: Array = []
	for wound: Dictionary in target_wounds:
		if bool(wound.get("stump", false)):
			continue
		var part_id := StringName(str(wound.get("part", &"")))
		var part := anatomy_definition.get_part(part_id)
		if part == null:
			continue
		var local_position: Vector3 = wound.get("local_position", part.local_center)
		var direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
		var field_position := local_position - part.local_center
		var radius := float(wound.get("radius", 0.03))
		var depth := float(wound.get("depth", radius * 1.4))
		result.append({
			"part": part_id,
			"event": {
				"event_id": int(wound.get("event_id", result.size() + 1)),
				"sequence": int(wound.get("event_id", result.size() + 1)),
				"source_kind": &"legacy_enemy_wound",
				"world_position": field_position,
				"normal": -direction,
				"direction": direction,
				"brush_kind": DamageEvent.BRUSH_CAPSULE,
				"radius": radius,
				"length": depth,
				"penetration": depth,
				"energy": maxf(anatomy_definition.damage_texture.geometry_threshold + 1.0, 8.0),
				"damage_tags": PackedStringArray([DamageEvent.TAG_BALLISTIC]),
				"seed": int(wound.get("event_id", result.size() + 1)),
			},
		})
	return result


func _update_part_surface_transforms() -> void:
	if anatomy_definition == null:
		return
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		var surface := part_surface_nodes.get(part.part_id) as MeshInstance3D
		if surface == null or surface.mesh == null:
			continue
		surface.global_transform = _profile_part_world_transform(part)
		surface.visible = _part_is_present(part.part_id)


func _profile_part_world_transform(part: EnemyAnatomyPartDefinition) -> Transform3D:
	var root_basis := character_skin.global_basis.orthonormalized()
	if part.presentation_start_bone.is_empty() or character_skin.skeleton == null:
		return Transform3D(
			root_basis,
			character_skin.global_transform * part.local_center
		)
	var start := _bone_world_origin(part.presentation_start_bone)
	if part.presentation_end_bone.is_empty():
		return Transform3D(
			root_basis,
			start + root_basis * (part.local_center - part.rest_axis_start)
		)
	var end := _bone_world_origin(part.presentation_end_bone)
	var rest_delta := part.rest_axis_end - part.rest_axis_start
	var current_delta := end - start
	if rest_delta.length_squared() <= 0.000001 or current_delta.length_squared() <= 0.000001:
		return Transform3D(
			root_basis,
			start + root_basis * (part.local_center - part.rest_axis_start)
		)
	var t := clampf(
		(part.local_center - part.rest_axis_start).dot(rest_delta) / rest_delta.length_squared(),
		0.0,
		1.0
	)
	var rest_axis_position := part.rest_axis_start + rest_delta * t
	var axis_mapping := (
		LimbKinematics.basis_from_y(current_delta)
		* LimbKinematics.basis_from_y(rest_delta).inverse()
	)
	return Transform3D(
		axis_mapping,
		start.lerp(end, t) + axis_mapping * (part.local_center - rest_axis_position)
	)


func _sanitize_wound(value: Dictionary) -> Dictionary:
	var part_id := StringName(str(value.get("part", &"")))
	if (
		part_id.is_empty()
		or (
			anatomy_definition != null
			and anatomy_definition.get_part(part_id) == null
		)
		or (
			anatomy_definition == null
			and not ANATOMY.PART_ORDER.has(part_id)
		)
	):
		return {}
	var local_position: Variant = value.get("local_position", null)
	var local_direction: Variant = value.get("local_direction", null)
	if not local_position is Vector3 or not local_direction is Vector3:
		return {}
	if not (local_position as Vector3).is_finite() or not (local_direction as Vector3).is_finite():
		return {}
	return {
		"event_id": maxi(int(value.get("event_id", 0)), 0),
		"part": part_id,
		"local_position": local_position,
		"local_direction": (local_direction as Vector3).normalized(),
		"radius": clampf(float(value.get("radius", 0.03)), 0.005, 0.3),
		"depth": clampf(float(value.get("depth", 0.05)), 0.005, 1.5),
		"stump": bool(value.get("stump", false)),
	}


func _append_missing_limb_stumps() -> void:
	if anatomy_definition != null:
		for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
			if (
				part == null
				or not part.severable
				or _part_is_present(part.part_id)
				or target_wounds.size() >= MAX_WOUNDS
			):
				continue
			target_wounds.append({
				"event_id": 0,
				"part": part.part_id,
				"local_position": part.stump_local_position,
				"local_direction": part.stump_inward_direction.normalized(),
				"radius": part.stump_radius,
				"depth": part.stump_radius * 1.8,
				"stump": true,
			})
		return
	var stump_layout := {
		ANATOMY.PART_LEFT_ARM: [Vector3(-0.32, 1.47, 0.0), 0.105],
		ANATOMY.PART_RIGHT_ARM: [Vector3(0.32, 1.47, 0.0), 0.105],
		ANATOMY.PART_LEFT_LEG: [Vector3(-0.17, 0.91, 0.0), 0.12],
		ANATOMY.PART_RIGHT_LEG: [Vector3(0.17, 0.91, 0.0), 0.12],
	}
	for part_id: StringName in stump_layout.keys():
		if _part_is_present(part_id) or target_wounds.size() >= MAX_WOUNDS:
			continue
		var descriptor: Array = stump_layout[part_id]
		target_wounds.append({
			"event_id": 0,
			"part": part_id,
			"local_position": descriptor[0],
			"local_direction": Vector3.UP if str(part_id).ends_with("leg") else (
				Vector3.RIGHT if part_id == ANATOMY.PART_LEFT_ARM else Vector3.LEFT
			),
			"radius": float(descriptor[1]),
			"depth": float(descriptor[1]) * 1.8,
			"stump": true,
		})


func _resolve_wound_world_frame(wound: Dictionary) -> Dictionary:
	var local_position: Vector3 = wound.get("local_position", Vector3.ZERO)
	var local_direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
	var part_id := StringName(str(wound.get("part", &"")))
	var part := (
		anatomy_definition.get_part(part_id)
		if anatomy_definition != null
		else null
	)
	if part != null:
		return _profile_wound_world_frame(local_position, local_direction, part)
	return _legacy_wound_world_frame(local_position, local_direction, part_id)


func _profile_wound_world_frame(
	local_position: Vector3,
	local_direction: Vector3,
	part: EnemyAnatomyPartDefinition
) -> Dictionary:
	var root_basis := character_skin.global_basis.orthonormalized()
	if (
		part.presentation_start_bone.is_empty()
		or character_skin.skeleton == null
	):
		return {
			"position": character_skin.global_transform * local_position,
			"direction": (root_basis * local_direction).normalized(),
		}
	var start := _bone_world_origin(part.presentation_start_bone)
	if part.presentation_end_bone.is_empty():
		return {
			"position": start + root_basis * (local_position - part.rest_axis_start),
			"direction": (root_basis * local_direction).normalized(),
		}
	var end := _bone_world_origin(part.presentation_end_bone)
	var rest_delta := part.rest_axis_end - part.rest_axis_start
	var current_delta := end - start
	if rest_delta.length_squared() <= 0.000001 or current_delta.length_squared() <= 0.000001:
		return {
			"position": start + root_basis * (local_position - part.rest_axis_start),
			"direction": (root_basis * local_direction).normalized(),
		}
	var t := clampf(
		(local_position - part.rest_axis_start).dot(rest_delta) / rest_delta.length_squared(),
		0.0,
		1.0
	)
	var rest_axis_position := part.rest_axis_start + rest_delta * t
	var rest_basis := LimbKinematics.basis_from_y(rest_delta)
	var current_basis := LimbKinematics.basis_from_y(current_delta)
	var axis_mapping := current_basis * rest_basis.inverse()
	return {
		"position": start.lerp(end, t) + axis_mapping * (local_position - rest_axis_position),
		"direction": (axis_mapping * local_direction).normalized(),
	}


func _legacy_wound_world_frame(
	local_position: Vector3,
	local_direction: Vector3,
	part_id: StringName
) -> Dictionary:
	var root_basis := character_skin.global_basis.orthonormalized()
	var position := character_skin.global_transform * local_position
	match part_id:
		ANATOMY.PART_HEAD:
			position = _bone_world_origin(&"mixamorig_Head") + root_basis * (
				local_position - Vector3(0.0, 1.66, 0.0)
			)
		ANATOMY.PART_TORSO:
			position = _bone_world_origin(&"mixamorig_Spine1") + root_basis * (
				local_position - Vector3(0.0, 1.18, 0.0)
			)
		ANATOMY.PART_LEFT_ARM:
			position = _limb_world_position(
				local_position,
				-0.38,
				&"mixamorig_LeftArm",
				&"mixamorig_LeftHand",
				1.53,
				1.00
			)
		ANATOMY.PART_RIGHT_ARM:
			position = _limb_world_position(
				local_position,
				0.38,
				&"mixamorig_RightArm",
				&"mixamorig_RightHand",
				1.53,
				1.00
			)
		ANATOMY.PART_LEFT_LEG:
			position = _limb_world_position(
				local_position,
				-0.17,
				&"mixamorig_LeftUpLeg",
				&"mixamorig_LeftFoot",
				0.92,
				0.05
			)
		ANATOMY.PART_RIGHT_LEG:
			position = _limb_world_position(
				local_position,
				0.17,
				&"mixamorig_RightUpLeg",
				&"mixamorig_RightFoot",
				0.92,
				0.05
			)
	return {
		"position": position,
		"direction": (root_basis * local_direction).normalized(),
	}


func _limb_world_position(
	local_position: Vector3,
	rest_x: float,
	start_bone: StringName,
	end_bone: StringName,
	rest_start_y: float,
	rest_end_y: float
) -> Vector3:
	var start := _bone_world_origin(start_bone)
	var end := _bone_world_origin(end_bone)
	var t := clampf(inverse_lerp(rest_start_y, rest_end_y, local_position.y), 0.0, 1.0)
	var root_basis := character_skin.global_basis.orthonormalized()
	return (
		start.lerp(end, t)
		+ root_basis.x * (local_position.x - rest_x)
		+ root_basis.z * local_position.z
	)


func _bone_world_origin(bone_name: StringName) -> Vector3:
	if character_skin == null or character_skin.skeleton == null:
		return global_position
	var bone_index := character_skin.skeleton.find_bone(bone_name)
	if bone_index < 0:
		return global_position
	return (
		character_skin.skeleton.global_transform
		* character_skin.skeleton.get_bone_global_pose(bone_index)
	).origin


func _part_is_present(part_id: StringName) -> bool:
	return not target_part_presence.has(part_id) or bool(target_part_presence[part_id])
