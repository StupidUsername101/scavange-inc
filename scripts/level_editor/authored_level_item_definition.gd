class_name AuthoredLevelItemDefinition
extends ItemDefinition

## Runtime ItemDefinition for arbitrary level-editor GLBs. The compact descriptor
## is replicated with ServerItem state, so clients reconstruct the same visual
## without receiving the host's user:// level file or a generated Resource.

const ASSET_SCENE_LOADER := preload(
	"res://scripts/level_editor/level_asset_scene_loader.gd"
)
const MAXIMUM_CONVEX_SOURCE_POINTS := 4096

static var _collision_cache: Dictionary[String, Dictionary] = {}

var source_asset_path := ""
var authored_scale := Vector3.ONE
var source_placement_id := 0


func configure_from_network_descriptor(raw_descriptor: Dictionary) -> bool:
	var descriptor := sanitize_network_descriptor(raw_descriptor)
	if descriptor.is_empty():
		return false
	source_asset_path = str(descriptor["asset_path"])
	authored_scale = descriptor["scale"]
	source_placement_id = int(descriptor.get("placement_id", 0))
	display_name = str(descriptor["display_name"])
	mass = float(descriptor["mass_kg"])
	economy_category = int(descriptor["economy_category"])
	value_per_mass = float(descriptor["value_per_mass"])
	physical_surface = descriptor["physical_surface"]
	grippable = true
	grip_surface_tags = PackedStringArray(["carryable", "level_item"])
	return true


func configure_from_placement(
	raw_placement: Dictionary,
	build_collision := true
) -> bool:
	var placement := LevelEditorDocument.sanitize_placement(raw_placement)
	if placement.is_empty():
		return false
	var role: StringName = placement.get(
		"gameplay_role",
		LevelEditorDocument.PLACEMENT_ROLE_STATIC
	)
	if (
		role != LevelEditorDocument.PLACEMENT_ROLE_ITEM
		and role != LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
	):
		return false
	source_asset_path = str(placement["asset_path"])
	authored_scale = placement.get("scale", Vector3.ONE)
	source_placement_id = int(placement["id"])
	display_name = source_asset_path.get_file().get_basename().replace(
		"_",
		" "
	).capitalize()
	mass = float(placement.get("item_mass_kg", 1.0))
	economy_category = (
		EconomyCategory.VALUABLE
		if role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		else EconomyCategory.ITEM
	)
	value_per_mass = (
		float(placement.get("value_per_mass", 0.0))
		if economy_category == EconomyCategory.VALUABLE
		else 0.0
	)
	physical_surface = _surface_for_asset_path(source_asset_path)
	grippable = true
	grip_surface_tags = PackedStringArray(["carryable", "level_item"])
	if build_collision:
		_build_runtime_collision()
	return true


func instantiate_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoredLevelItemVisual"
	var visual := ASSET_SCENE_LOADER.instantiate(source_asset_path)
	if visual != null:
		root.add_child(visual)
	root.scale = authored_scale
	return root


func instantiate_visual_from_state(_state: Dictionary) -> Node3D:
	return instantiate_visual()


func to_network_descriptor() -> Dictionary:
	return {
		"asset_path": source_asset_path,
		"scale": authored_scale,
		"placement_id": source_placement_id,
		"display_name": display_name,
		"mass_kg": get_instance_mass({}),
		"economy_category": economy_category,
		"value_per_mass": get_instance_value_per_mass({}),
		"physical_surface": physical_surface,
	}


static func sanitize_network_descriptor(raw: Dictionary) -> Dictionary:
	var asset_path := str(raw.get("asset_path", "")).strip_edges()
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return {}
	var raw_scale: Variant = raw.get("scale", Vector3.ONE)
	var scale := raw_scale as Vector3 if raw_scale is Vector3 else Vector3.ONE
	if not scale.is_finite():
		scale = Vector3.ONE
	scale = Vector3(
		clampf(absf(scale.x), 0.001, 1000.0),
		clampf(absf(scale.y), 0.001, 1000.0),
		clampf(absf(scale.z), 0.001, 1000.0)
	)
	var category := clampi(
		int(raw.get("economy_category", EconomyCategory.ITEM)),
		EconomyCategory.ITEM,
		EconomyCategory.VALUABLE
	)
	return {
		"asset_path": asset_path,
		"scale": scale,
		"placement_id": maxi(int(raw.get("placement_id", 0)), 0),
		"display_name": str(raw.get(
			"display_name",
			asset_path.get_file().get_basename().replace("_", " ").capitalize()
		)).strip_edges().left(96),
		"mass_kg": clampf(
			SafeVariant.finite_float_or(raw.get("mass_kg"), 1.0),
			LevelEditorDocument.MINIMUM_ITEM_MASS_KG,
			LevelEditorDocument.MAXIMUM_ITEM_MASS_KG
		),
		"economy_category": category,
		"value_per_mass": (
			clampf(
				SafeVariant.finite_float_or(raw.get("value_per_mass"), 0.0),
				0.0,
				LevelEditorDocument.MAXIMUM_VALUE_PER_MASS
			)
			if category == EconomyCategory.VALUABLE
			else 0.0
		),
		"physical_surface": PhysicalSurface.normalize(
			raw.get("physical_surface", &"metal"),
			&"metal"
		),
	}


func _build_runtime_collision() -> void:
	var cache_key := "%s|%.5f|%.5f|%.5f" % [
		source_asset_path,
		authored_scale.x,
		authored_scale.y,
		authored_scale.z,
	]
	var cached: Dictionary = _collision_cache.get(cache_key, {})
	if not cached.is_empty():
		collision_shape = cached.get("shape") as Shape3D
		shape_position = cached.get("position", Vector3.ZERO)
		return
	var visual := ASSET_SCENE_LOADER.instantiate(source_asset_path)
	if visual == null:
		return
	var points := PackedVector3Array()
	_collect_mesh_points(visual, Transform3D.IDENTITY, points)
	var bounds := LevelAssetPlacement.calculate_visual_bounds(visual)
	visual.free()
	if points.size() >= 4:
		var sampled := _bounded_scaled_points(points)
		if sampled.size() >= 4:
			var convex := ConvexPolygonShape3D.new()
			convex.points = sampled
			collision_shape = convex
			shape_position = Vector3.ZERO
			_collision_cache[cache_key] = {
				"shape": collision_shape,
				"position": shape_position,
			}
			return
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(bounds.size.x * authored_scale.x, 0.02),
		maxf(bounds.size.y * authored_scale.y, 0.02),
		maxf(bounds.size.z * authored_scale.z, 0.02)
	)
	collision_shape = box
	shape_position = bounds.get_center() * authored_scale
	_collision_cache[cache_key] = {
		"shape": collision_shape,
		"position": shape_position,
	}


func _bounded_scaled_points(source: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	var stride := maxi(
		int(ceili(float(source.size()) / float(MAXIMUM_CONVEX_SOURCE_POINTS))),
		1
	)
	for index: int in range(0, source.size(), stride):
		result.append(source[index] * authored_scale)
	return result


static func _collect_mesh_points(
	node: Node,
	parent_transform: Transform3D,
	points: PackedVector3Array
) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for point: Vector3 in mesh_instance.mesh.get_faces():
				points.append(current_transform * point)
	for child: Node in node.get_children():
		_collect_mesh_points(child, current_transform, points)


static func _surface_for_asset_path(asset_path: String) -> StringName:
	var lower := asset_path.to_lower()
	if lower.contains("wood") or lower.contains("tree") or lower.contains("log"):
		return PhysicalSurface.WOOD
	if lower.contains("stone") or lower.contains("rock"):
		return PhysicalSurface.STONE
	if lower.contains("concrete") or lower.contains("bunker"):
		return PhysicalSurface.CONCRETE
	if (
		lower.contains("grass")
		or lower.contains("soil")
		or lower.contains("plant")
	):
		return PhysicalSurface.SOIL
	return PhysicalSurface.METAL
