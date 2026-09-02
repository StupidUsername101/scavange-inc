class_name LevelBuildingShellGenerator
extends RefCounted

const KIT_CATALOG := preload(
	"res://scripts/level_editor/level_building_kit_catalog.gd"
)

const MINIMUM_MODULE_SIZE := 0.05
const MAXIMUM_SEGMENTS_PER_EDGE := 128
const MAXIMUM_TILES_PER_AXIS := 64


static func generate(
	corner_a: Vector3,
	corner_b: Vector3,
	yaw: float,
	wall_path: String,
	wall_bounds: AABB,
	floor_path: String,
	floor_bounds: AABB,
	roof_path: String,
	roof_bounds: AABB,
	include_roof: bool,
	building_group_id: int,
	storey := 0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if (
		not corner_a.is_finite()
		or not corner_b.is_finite()
		or wall_path.is_empty()
		or wall_bounds.size.length_squared() <= 0.000001
	):
		return result
	var room_basis := Basis(Vector3.UP, yaw)
	var local_delta := room_basis.inverse() * (corner_b - corner_a)
	var wall_span := horizontal_span(wall_bounds)
	if wall_span < MINIMUM_MODULE_SIZE:
		return result
	var count_x := clampi(
		maxi(roundi(absf(local_delta.x) / wall_span), 1),
		1,
		MAXIMUM_SEGMENTS_PER_EDGE
	)
	var count_z := clampi(
		maxi(roundi(absf(local_delta.z) / wall_span), 1),
		1,
		MAXIMUM_SEGMENTS_PER_EDGE
	)
	var width := wall_span * count_x
	var depth := wall_span * count_z
	var sign_x := -1.0 if local_delta.x < 0.0 else 1.0
	var sign_z := -1.0 if local_delta.z < 0.0 else 1.0
	var center := corner_a + room_basis * Vector3(
		sign_x * width * 0.5,
		0.0,
		sign_z * depth * 0.5
	)
	var room_right := (room_basis * Vector3.RIGHT) * sign_x
	var room_back := (room_basis * Vector3.BACK) * sign_z
	var base_y := corner_a.y
	_append_wall_edge(
		result, center - room_back * depth * 0.5, room_right,
		count_x, wall_span, wall_path, wall_bounds, base_y,
		building_group_id, storey
	)
	_append_wall_edge(
		result, center + room_back * depth * 0.5, room_right,
		count_x, wall_span, wall_path, wall_bounds, base_y,
		building_group_id, storey
	)
	_append_wall_edge(
		result, center - room_right * width * 0.5, room_back,
		count_z, wall_span, wall_path, wall_bounds, base_y,
		building_group_id, storey
	)
	_append_wall_edge(
		result, center + room_right * width * 0.5, room_back,
		count_z, wall_span, wall_path, wall_bounds, base_y,
		building_group_id, storey
	)
	if not floor_path.is_empty() and floor_bounds.size.length_squared() > 0.000001:
		_append_planar_fill(
			result, center, room_right, room_back, width, depth, base_y,
			floor_path, floor_bounds, building_group_id, storey, false
		)
	if (
		include_roof
		and not roof_path.is_empty()
		and roof_bounds.size.length_squared() > 0.000001
	):
		_append_planar_fill(
			result, center, room_right, room_back, width, depth,
			base_y + wall_bounds.size.y, roof_path, roof_bounds,
			building_group_id, storey, true
		)
	return result


static func horizontal_span(bounds: AABB) -> float:
	return maxf(bounds.size.x, bounds.size.z)


static func horizontal_span_axis(bounds: AABB) -> Vector3:
	return Vector3.RIGHT if bounds.size.x >= bounds.size.z else Vector3.BACK


static func socket_anchors(
	transform: Transform3D,
	local_bounds: AABB,
	socket: StringName
) -> PackedVector3Array:
	var result := PackedVector3Array()
	var center := local_bounds.get_center()
	if socket == KIT_CATALOG.SOCKET_WALL_SEGMENT or socket == KIT_CATALOG.SOCKET_LINEAR:
		var axis := horizontal_span_axis(local_bounds)
		var half_span := horizontal_span(local_bounds) * 0.5
		result.append(transform * (center - axis * half_span))
		result.append(transform * (center + axis * half_span))
	elif socket == KIT_CATALOG.SOCKET_PLANAR:
		for x: float in [local_bounds.position.x, local_bounds.end.x]:
			for z: float in [local_bounds.position.z, local_bounds.end.z]:
				result.append(transform * Vector3(x, center.y, z))
	elif socket == KIT_CATALOG.SOCKET_VERTICAL:
		result.append(transform * Vector3(center.x, local_bounds.position.y, center.z))
		result.append(transform * Vector3(center.x, local_bounds.end.y, center.z))
	else:
		result.append(transform * center)
	return result


static func pose_with_base_center(
	asset_path: String,
	local_bounds: AABB,
	world_center: Vector3,
	world_direction: Vector3,
	scale := Vector3.ONE,
	building_group_id := 0,
	storey := 0
) -> Dictionary:
	var direction := world_direction
	direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	var yaw := _yaw_mapping_span_to_direction(local_bounds, direction)
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	var scaled_center := basis * Vector3(
		local_bounds.get_center().x,
		0.0,
		local_bounds.get_center().z
	)
	var origin := world_center - Vector3(scaled_center.x, 0.0, scaled_center.z)
	origin.y = world_center.y - local_bounds.position.y * scale.y
	return {
		"asset_path": asset_path,
		"position": origin,
		"rotation": Vector3(0.0, yaw, 0.0),
		"scale": scale,
		"acoustic_boundary": true,
		"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_STATIC,
		"item_mass_kg": 1.0,
		"value_per_mass": 0.0,
		"assembly_group_id": 0,
		"assembly_definition_id": "",
		"building_group_id": building_group_id,
		"building_storey": storey,
	}


static func _append_wall_edge(
	result: Array[Dictionary],
	edge_center: Vector3,
	direction: Vector3,
	count: int,
	span: float,
	asset_path: String,
	bounds: AABB,
	base_y: float,
	building_group_id: int,
	storey: int
) -> void:
	for index: int in range(count):
		var offset := (float(index) - float(count - 1) * 0.5) * span
		var segment_center := edge_center + direction * offset
		segment_center.y = base_y
		result.append(pose_with_base_center(
			asset_path,
			bounds,
			segment_center,
			direction,
			Vector3.ONE,
			building_group_id,
			storey
		))


static func _append_planar_fill(
	result: Array[Dictionary],
	center: Vector3,
	right: Vector3,
	back: Vector3,
	width: float,
	depth: float,
	base_y: float,
	asset_path: String,
	bounds: AABB,
	building_group_id: int,
	storey: int,
	is_roof: bool
) -> void:
	var source_x := maxf(bounds.size.x, MINIMUM_MODULE_SIZE)
	var source_z := maxf(bounds.size.z, MINIMUM_MODULE_SIZE)
	var count_x := clampi(maxi(roundi(width / source_x), 1), 1, MAXIMUM_TILES_PER_AXIS)
	var count_z := clampi(maxi(roundi(depth / source_z), 1), 1, MAXIMUM_TILES_PER_AXIS)
	var cell_x := width / float(count_x)
	var cell_z := depth / float(count_z)
	var scale := Vector3(cell_x / source_x, 1.0, cell_z / source_z)
	var yaw := atan2(-right.z, right.x)
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	var local_center := bounds.get_center()
	for x_index: int in range(count_x):
		for z_index: int in range(count_z):
			var tile_center := center
			tile_center += right * ((float(x_index) - float(count_x - 1) * 0.5) * cell_x)
			tile_center += back * ((float(z_index) - float(count_z - 1) * 0.5) * cell_z)
			var offset := basis * Vector3(local_center.x, 0.0, local_center.z)
			var origin := tile_center - Vector3(offset.x, 0.0, offset.z)
			origin.y = (
				base_y - bounds.position.y * scale.y
				if not is_roof
				else base_y - bounds.position.y * scale.y
			)
			result.append({
				"asset_path": asset_path,
				"position": origin,
				"rotation": Vector3(0.0, yaw, 0.0),
				"scale": scale,
				"acoustic_boundary": true,
				"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_STATIC,
				"item_mass_kg": 1.0,
				"value_per_mass": 0.0,
				"assembly_group_id": 0,
				"assembly_definition_id": "",
				"building_group_id": building_group_id,
				"building_storey": storey,
			})


static func _yaw_mapping_span_to_direction(bounds: AABB, direction: Vector3) -> float:
	if bounds.size.x >= bounds.size.z:
		return atan2(-direction.z, direction.x)
	return atan2(direction.x, direction.z)
