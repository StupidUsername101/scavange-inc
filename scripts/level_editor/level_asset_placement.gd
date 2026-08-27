class_name LevelAssetPlacement
extends Node3D

const SELECTION_COLOR := Color(1.0, 0.68, 0.16, 0.88)
const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")

var placement_id := 0
var asset_path := ""
var local_bounds := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
var visual: Node3D
var selection_box: MeshInstance3D


func configure(next_id: int, next_asset_path: String) -> bool:
	placement_id = next_id
	asset_path = next_asset_path
	name = "Placement_%d" % placement_id
	visual = ASSET_SCENE_LOADER.instantiate(asset_path)
	if visual == null:
		return false
	visual.name = "AssetVisual"
	add_child(visual)
	local_bounds = calculate_visual_bounds(visual)
	_create_selection_box()
	return true


func set_selected(value: bool) -> void:
	if selection_box != null:
		selection_box.visible = value


func floor_offset() -> float:
	return -local_bounds.position.y


func snapshot() -> Dictionary:
	return {
		"id": placement_id,
		"asset_path": asset_path,
		"position": position,
		"rotation": rotation,
		"scale": scale,
	}


func apply_snapshot(value: Dictionary) -> void:
	var safe := LevelEditorDocument.sanitize_placement(value)
	if safe.is_empty() or int(safe.get("id", 0)) != placement_id:
		return
	position = safe["position"]
	rotation = safe["rotation"]
	scale = safe["scale"]


func ray_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := (inverse.basis * ray_direction).normalized()
	var hit: Variant = local_bounds.intersects_ray(local_origin, local_direction)
	if not hit is Vector3:
		return INF
	return ray_origin.distance_to(global_transform * (hit as Vector3))


func upward_surface_ray_distance(
	ray_origin: Vector3,
	ray_direction: Vector3,
	minimum_up_normal_y: float
) -> float:
	if ray_direction.length_squared() <= 0.000001:
		return INF
	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := inverse.basis * ray_direction.normalized()
	if local_direction.length_squared() <= 0.000001:
		return INF
	local_direction = local_direction.normalized()
	var hit: Variant = local_bounds.intersects_ray(local_origin, local_direction)
	if not hit is Vector3:
		return INF
	var local_hit := hit as Vector3
	var local_normal := _aabb_surface_normal(local_hit, local_bounds)
	var normal_basis := global_transform.basis.inverse().transposed()
	var world_normal := (normal_basis * local_normal).normalized()
	if not world_normal.is_finite() or world_normal.y < minimum_up_normal_y:
		return INF
	var world_hit := global_transform * local_hit
	var distance := (world_hit - ray_origin).dot(ray_direction.normalized())
	return distance if distance >= 0.0 and is_finite(distance) else INF


static func _aabb_surface_normal(point: Vector3, bounds: AABB) -> Vector3:
	var bounds_end := bounds.end
	var distance_min_x := absf(point.x - bounds.position.x)
	var distance_max_x := absf(point.x - bounds_end.x)
	var distance_min_y := absf(point.y - bounds.position.y)
	var distance_max_y := absf(point.y - bounds_end.y)
	var distance_min_z := absf(point.z - bounds.position.z)
	var distance_max_z := absf(point.z - bounds_end.z)
	var nearest_distance := distance_min_x
	var normal := Vector3.LEFT
	if distance_max_x < nearest_distance:
		nearest_distance = distance_max_x
		normal = Vector3.RIGHT
	if distance_min_y < nearest_distance:
		nearest_distance = distance_min_y
		normal = Vector3.DOWN
	if distance_max_y < nearest_distance:
		nearest_distance = distance_max_y
		normal = Vector3.UP
	if distance_min_z < nearest_distance:
		nearest_distance = distance_min_z
		normal = Vector3.FORWARD
	if distance_max_z < nearest_distance:
		normal = Vector3.BACK
	return normal


static func calculate_visual_bounds(root: Node3D) -> AABB:
	var state := {
		"found": false,
		"bounds": AABB(),
	}
	_collect_bounds(root, Transform3D.IDENTITY, state)
	if not bool(state.get("found", false)):
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	var bounds: AABB = state.get("bounds", AABB())
	if bounds.size.length_squared() <= 0.000001:
		return AABB(bounds.position - Vector3.ONE * 0.5, Vector3.ONE)
	return bounds


static func _collect_bounds(
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
			var transformed_bounds: AABB = current_transform * mesh_instance.get_aabb()
			if bool(state.get("found", false)):
				state["bounds"] = (state.get("bounds") as AABB).merge(transformed_bounds)
			else:
				state["bounds"] = transformed_bounds
				state["found"] = true
	for child: Node in node.get_children():
		_collect_bounds(child, current_transform, state)


func _create_selection_box() -> void:
	selection_box = MeshInstance3D.new()
	selection_box.name = "SelectionBounds"
	var half_size := (local_bounds.size + Vector3.ONE * 0.025) * 0.5
	var corners := PackedVector3Array([
		Vector3(-half_size.x, -half_size.y, -half_size.z),
		Vector3(half_size.x, -half_size.y, -half_size.z),
		Vector3(half_size.x, half_size.y, -half_size.z),
		Vector3(-half_size.x, half_size.y, -half_size.z),
		Vector3(-half_size.x, -half_size.y, half_size.z),
		Vector3(half_size.x, -half_size.y, half_size.z),
		Vector3(half_size.x, half_size.y, half_size.z),
		Vector3(-half_size.x, half_size.y, half_size.z),
	])
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SELECTION_COLOR
	material.no_depth_test = true
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Vector2i in [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]:
		lines.surface_add_vertex(corners[edge.x])
		lines.surface_add_vertex(corners[edge.y])
	lines.surface_end()
	selection_box.mesh = lines
	selection_box.position = local_bounds.get_center()
	selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	selection_box.visible = false
	add_child(selection_box)
