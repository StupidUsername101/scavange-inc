class_name LevelAssetPlacement
extends Node3D

const SELECTION_COLOR := Color(1.0, 0.68, 0.16, 0.88)
const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")

static var _surface_bvh_cache: Dictionary[String, TriangleMesh] = {}
static var _local_bounds_cache: Dictionary[String, AABB] = {}

var placement_id := 0
var asset_path := ""
var assembly_group_id := 0
var assembly_definition_id := ""
var building_group_id := 0
var building_storey := 0
var local_bounds := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
var acoustic_boundary := true
var gameplay_role := LevelEditorDocument.PLACEMENT_ROLE_STATIC
var item_mass_kg := 1.0
var value_per_mass := 0.0
var visual: Node3D
var selection_box: MeshInstance3D
var surface_bvh: TriangleMesh


func configure(next_id: int, next_asset_path: String) -> bool:
	placement_id = next_id
	asset_path = next_asset_path
	name = "Placement_%d" % placement_id
	visual = ASSET_SCENE_LOADER.instantiate(asset_path)
	if visual == null:
		return false
	visual.name = "AssetVisual"
	add_child(visual)
	if _local_bounds_cache.has(asset_path):
		local_bounds = _local_bounds_cache[asset_path]
	else:
		local_bounds = calculate_visual_bounds(visual)
		_local_bounds_cache[asset_path] = local_bounds
	surface_bvh = _surface_bvh_for_asset(asset_path, visual)
	_create_selection_box()
	return true


static func asset_bounds(path: String) -> AABB:
	if _local_bounds_cache.has(path):
		return _local_bounds_cache[path]
	var asset_visual := ASSET_SCENE_LOADER.instantiate(path)
	if asset_visual == null:
		return AABB()
	var bounds := calculate_visual_bounds(asset_visual)
	asset_visual.free()
	if bounds.size.length_squared() > 0.000001:
		_local_bounds_cache[path] = bounds
	return bounds


func set_selected(value: bool) -> void:
	if selection_box != null:
		selection_box.visible = value


func snapshot() -> Dictionary:
	return {
		"id": placement_id,
		"asset_path": asset_path,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"acoustic_boundary": acoustic_boundary,
		"gameplay_role": gameplay_role,
		"item_mass_kg": item_mass_kg,
		"value_per_mass": value_per_mass,
		"assembly_group_id": assembly_group_id,
		"assembly_definition_id": assembly_definition_id,
		"building_group_id": building_group_id,
		"building_storey": building_storey,
	}


func apply_snapshot(value: Dictionary) -> void:
	var safe := LevelEditorDocument.sanitize_placement(value)
	if safe.is_empty() or int(safe.get("id", 0)) != placement_id:
		return
	position = safe["position"]
	rotation = safe["rotation"]
	scale = safe["scale"]
	acoustic_boundary = bool(safe.get("acoustic_boundary", true))
	gameplay_role = safe.get(
		"gameplay_role",
		LevelEditorDocument.PLACEMENT_ROLE_STATIC
	)
	item_mass_kg = float(safe.get("item_mass_kg", 1.0))
	value_per_mass = float(safe.get("value_per_mass", 0.0))
	assembly_group_id = int(safe.get("assembly_group_id", 0))
	assembly_definition_id = str(safe.get("assembly_definition_id", ""))
	building_group_id = int(safe.get("building_group_id", 0))
	building_storey = int(safe.get("building_storey", 0))


func ray_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	var hit := surface_ray_hit(ray_origin, ray_direction)
	if hit.normal.length_squared() <= 0.000001 or not is_finite(hit.d):
		return INF
	return hit.d


func surface_ray_hit(ray_origin: Vector3, ray_direction: Vector3) -> Plane:
	if ray_direction.length_squared() <= 0.000001:
		return Plane(Vector3.ZERO, INF)
	var normalized_direction := ray_direction.normalized()
	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := inverse.basis * normalized_direction
	if local_direction.length_squared() <= 0.000001:
		return Plane(Vector3.ZERO, INF)
	local_direction = local_direction.normalized()
	# The AABB is only a cheap broad phase. Treating it as the actual surface
	# seals doors, arches, tunnels, shelves, and every other concave asset.
	var bounds_hit: Variant = local_bounds.intersects_ray(
		local_origin,
		local_direction
	)
	if not bounds_hit is Vector3:
		return Plane(Vector3.ZERO, INF)
	var local_hit := bounds_hit as Vector3
	var local_normal := _aabb_surface_normal(local_hit, local_bounds)
	if surface_bvh != null:
		var triangle_hit := surface_bvh.intersect_ray(
			local_origin,
			local_direction
		)
		if triangle_hit.is_empty():
			return Plane(Vector3.ZERO, INF)
		local_hit = triangle_hit.get("position", Vector3.INF)
		local_normal = triangle_hit.get("normal", Vector3.ZERO)
		if (
			not local_hit.is_finite()
			or not local_normal.is_finite()
			or local_normal.length_squared() <= 0.000001
		):
			return Plane(Vector3.ZERO, INF)
	var normal_basis := global_transform.basis.inverse().transposed()
	var world_normal := (normal_basis * local_normal).normalized()
	if not world_normal.is_finite():
		return Plane(Vector3.ZERO, INF)
	if world_normal.dot(normalized_direction) > 0.0:
		world_normal = -world_normal
	var world_hit := global_transform * local_hit
	var distance := (world_hit - ray_origin).dot(normalized_direction)
	if distance < 0.0 or not is_finite(distance):
		return Plane(Vector3.ZERO, INF)
	# Plane is used as a compact value result here: normal stores the hit normal,
	# d stores distance along the normalized ray. This avoids a Dictionary
	# allocation for every placed asset on every pointer-motion event.
	return Plane(world_normal, distance)


static func _surface_bvh_for_asset(
	path: String,
	visual_root: Node3D
) -> TriangleMesh:
	if _surface_bvh_cache.has(path):
		return _surface_bvh_cache[path]
	var faces := PackedVector3Array()
	_collect_mesh_faces(visual_root, Transform3D.IDENTITY, faces)
	if faces.size() < 3:
		return null
	var triangle_mesh := TriangleMesh.new()
	if not triangle_mesh.create_from_faces(faces):
		return null
	_surface_bvh_cache[path] = triangle_mesh
	return triangle_mesh


static func _collect_mesh_faces(
	node: Node,
	parent_transform: Transform3D,
	faces: PackedVector3Array
) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_faces := mesh_instance.mesh.get_faces()
			for face_vertex: Vector3 in mesh_faces:
				faces.append(current_transform * face_vertex)
	for child: Node in node.get_children():
		_collect_mesh_faces(child, current_transform, faces)


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
