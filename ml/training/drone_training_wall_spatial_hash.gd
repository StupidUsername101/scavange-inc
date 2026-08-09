class_name DroneTrainingWallSpatialHash
extends RefCounted

const DEFAULT_CELL_SIZE_M := 6.0
const MINIMUM_CELL_SIZE_M := 0.5
const MINIMUM_DIRECTION_LENGTH_SQUARED := 0.000001
const RAY_EPSILON := 0.000001
const MAXIMUM_QUERY_CACHE_ENTRIES := 512
const MAXIMUM_INDEXED_CELLS_PER_OBSTACLE := 4096

#######################################################
# Extent-aware static broad phase for editable training obstacles. Physics stays authoritative
# for collisions; this index accelerates the policy's lidar and direct-target wall checks for
# boxes, cylinders, spheres, and capsules.
#######################################################

var cell_size_m := DEFAULT_CELL_SIZE_M
var _records_by_instance_id: Dictionary = {}
var _wall_instance_ids: Dictionary = {}
var _instance_ids_by_cell: Dictionary = {}
var _global_instance_ids: Dictionary = {}
var _records_by_bounds_cache: Dictionary = {}
var query_count := 0
var candidate_count := 0
var exact_test_count := 0
var query_cache_hit_count := 0


func _init(configured_cell_size_m := DEFAULT_CELL_SIZE_M) -> void:
	cell_size_m = maxf(configured_cell_size_m, MINIMUM_CELL_SIZE_M)


func rebuild(walls: Array[Node3D]) -> void:
	_records_by_instance_id.clear()
	_wall_instance_ids.clear()
	_instance_ids_by_cell.clear()
	_global_instance_ids.clear()
	_records_by_bounds_cache.clear()
	for wall in walls:
		_register_wall(wall)


func clear() -> void:
	_records_by_instance_id.clear()
	_wall_instance_ids.clear()
	_instance_ids_by_cell.clear()
	_global_instance_ids.clear()
	_records_by_bounds_cache.clear()


func wall_count() -> int:
	return _wall_instance_ids.size()


func query_nearby(center: Vector3, radius_m: float) -> Array[Dictionary]:
	var safe_radius := maxf(radius_m, 0.0)
	return _records_for_bounds(
		center.x - safe_radius,
		center.x + safe_radius,
		center.z - safe_radius,
		center.z + safe_radius
	)


func query_segment(
	from: Vector3,
	to: Vector3,
	horizontal_margin_m := 0.0
) -> Array[Dictionary]:
	var margin := maxf(horizontal_margin_m, 0.0)
	return _records_for_bounds(
		minf(from.x, to.x) - margin,
		maxf(from.x, to.x) + margin,
		minf(from.z, to.z) - margin,
		maxf(from.z, to.z) + margin
	)


func raycast_records(
	records: Array[Dictionary],
	origin: Vector3,
	world_direction: Vector3,
	maximum_distance_m: float,
	local_inflation: Vector3 = Vector3.ZERO
) -> Dictionary:
	if (
		world_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED
		or maximum_distance_m <= 0.0
	):
		return {}
	var direction := world_direction.normalized()
	var nearest_distance := maximum_distance_m + 1.0
	var nearest_record: Dictionary = {}
	for record in records:
		exact_test_count += 1
		var distance := _ray_shape_distance(
			record,
			origin,
			direction,
			maximum_distance_m,
			local_inflation
		)
		if distance >= 0.0 and distance < nearest_distance:
			nearest_distance = distance
			nearest_record = record
	if nearest_record.is_empty():
		return {}
	return {
		"distance_m": nearest_distance,
		"position": origin + direction * nearest_distance,
		"body": nearest_record.get("body"),
		"record": nearest_record,
		"wall_top_world_y": float(nearest_record.get(
			"maximum_world_y",
			origin.y
		)),
	}


func raycast_distance_records(
	records: Array[Dictionary],
	origin: Vector3,
	world_direction: Vector3,
	maximum_distance_m: float,
	local_inflation: Vector3 = Vector3.ZERO
) -> float:
	if (
		world_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED
		or maximum_distance_m <= 0.0
	):
		return -1.0
	var direction := world_direction.normalized()
	var nearest_distance := maximum_distance_m + 1.0
	for record in records:
		exact_test_count += 1
		var distance := _ray_shape_distance(
			record,
			origin,
			direction,
			maximum_distance_m,
			local_inflation
		)
		if distance >= 0.0 and distance < nearest_distance:
			nearest_distance = distance
	return nearest_distance if nearest_distance <= maximum_distance_m else -1.0


func raycast_distances_records(
	records: Array[Dictionary],
	origin: Vector3,
	world_directions: PackedVector3Array,
	maximum_distances_m: PackedFloat64Array,
	local_inflation: Vector3 = Vector3.ZERO
) -> PackedFloat64Array:
	return _raycast_distances_records_internal(
		records,
		origin,
		world_directions,
		maximum_distances_m,
		-1.0,
		local_inflation
	)


func raycast_distances_records_uniform(
	records: Array[Dictionary],
	origin: Vector3,
	world_directions: PackedVector3Array,
	maximum_distance_m: float,
	local_inflation: Vector3 = Vector3.ZERO
) -> PackedFloat64Array:
	return _raycast_distances_records_internal(
		records,
		origin,
		world_directions,
		PackedFloat64Array(),
		maxf(maximum_distance_m, 0.0),
		local_inflation
	)


func _raycast_distances_records_internal(
	records: Array[Dictionary],
	origin: Vector3,
	world_directions: PackedVector3Array,
	maximum_distances_m: PackedFloat64Array,
	uniform_maximum_distance_m: float,
	local_inflation: Vector3
) -> PackedFloat64Array:
	var uses_uniform_maximum: bool = uniform_maximum_distance_m >= 0.0
	var ray_count: int = (
		world_directions.size()
		if uses_uniform_maximum
		else mini(world_directions.size(), maximum_distances_m.size())
	)
	var result := PackedFloat64Array()
	result.resize(ray_count)
	result.fill(-1.0)
	if ray_count <= 0:
		return result
	var normalized_directions := PackedVector3Array()
	var ray_minimums := PackedVector3Array()
	var ray_maximums := PackedVector3Array()
	normalized_directions.resize(ray_count)
	ray_minimums.resize(ray_count)
	ray_maximums.resize(ray_count)
	var safe_inflation := Vector3(
		maxf(local_inflation.x, 0.0),
		maxf(local_inflation.y, 0.0),
		maxf(local_inflation.z, 0.0)
	)
	var broad_phase_padding := Vector3.ONE * safe_inflation.length()
	for ray_index in range(ray_count):
		var direction := world_directions[ray_index]
		var normalized := (
			direction.normalized()
			if direction.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED
			else Vector3.ZERO
		)
		normalized_directions[ray_index] = normalized
		var maximum_distance_m: float = (
			uniform_maximum_distance_m
			if uses_uniform_maximum
			else maximum_distances_m[ray_index]
		)
		var ray_end := origin + normalized * maxf(
			maximum_distance_m,
			0.0
		)
		ray_minimums[ray_index] = Vector3(
			minf(origin.x, ray_end.x),
			minf(origin.y, ray_end.y),
			minf(origin.z, ray_end.z)
		) - broad_phase_padding
		ray_maximums[ray_index] = Vector3(
			maxf(origin.x, ray_end.x),
			maxf(origin.y, ray_end.y),
			maxf(origin.z, ray_end.z)
		) + broad_phase_padding
	for record in records:
		var world_aabb: AABB = record.get("world_aabb", AABB())
		var wall_minimum := world_aabb.position
		var wall_maximum := world_aabb.position + world_aabb.size
		for ray_index in range(ray_count):
			var maximum_distance_m: float = (
				uniform_maximum_distance_m
				if uses_uniform_maximum
				else maximum_distances_m[ray_index]
			)
			var direction := normalized_directions[ray_index]
			if maximum_distance_m <= 0.0 or direction == Vector3.ZERO:
				continue
			var ray_minimum := ray_minimums[ray_index]
			var ray_maximum := ray_maximums[ray_index]
			if (
				wall_maximum.x < ray_minimum.x
				or wall_minimum.x > ray_maximum.x
				or wall_maximum.y < ray_minimum.y
				or wall_minimum.y > ray_maximum.y
				or wall_maximum.z < ray_minimum.z
				or wall_minimum.z > ray_maximum.z
			):
				continue
			exact_test_count += 1
			var distance := _ray_shape_distance(
				record,
				origin,
				direction,
				maximum_distance_m,
				safe_inflation
			)
			if distance < 0.0:
				continue
			if result[ray_index] < 0.0 or distance < result[ray_index]:
				result[ray_index] = distance
	return result


func debug_state() -> Dictionary:
	return {
		"wall_count": _wall_instance_ids.size(),
		"collision_shape_count": _records_by_instance_id.size(),
		"occupied_cell_count": _instance_ids_by_cell.size(),
		"global_obstacle_count": _global_instance_ids.size(),
		"query_count": query_count,
		"candidate_count": candidate_count,
		"exact_test_count": exact_test_count,
		"query_cache_hits": query_cache_hit_count,
	}


func _register_wall(wall: Node3D) -> void:
	if not is_instance_valid(wall):
		return
	for child in wall.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		var shape_kind := DroneTrainingObstacleShape.kind_from_shape(collision.shape)
		var dimensions := DroneTrainingObstacleShape.dimensions_from_shape(
			collision.shape
		)
		var transform := collision.global_transform
		var half_extents := DroneTrainingObstacleShape.local_half_extents(
			shape_kind,
			dimensions
		)
		var world_aabb := DroneTrainingObstacleShape.world_aabb(
			shape_kind,
			dimensions,
			transform
		)
		var wall_instance_id: int = wall.get_instance_id()
		var instance_id: int = collision.get_instance_id()
		_wall_instance_ids[wall_instance_id] = true
		var record := {
			"body": wall,
			"collision": collision,
			"transform": transform,
			"inverse_transform": transform.affine_inverse(),
			"shape_kind": shape_kind,
			"dimensions": dimensions,
			"half_extents": half_extents,
			"world_aabb": world_aabb,
			"maximum_world_y": world_aabb.position.y + world_aabb.size.y,
		}
		_records_by_instance_id[instance_id] = record
		var minimum_cell := _cell_for_position(world_aabb.position)
		var maximum_cell := _cell_for_position(world_aabb.position + world_aabb.size)
		var cell_span_x := maximum_cell.x - minimum_cell.x + 1
		var cell_span_z := maximum_cell.y - minimum_cell.y + 1
		# Unrestricted obstacle dimensions must not turn one giant primitive into millions of
		# hash entries. Oversized records stay in one global candidate set and still receive
		# exact shape tests after the ordinary local-cell candidates are gathered.
		if (
			cell_span_x <= 0
			or cell_span_z <= 0
			or cell_span_x > MAXIMUM_INDEXED_CELLS_PER_OBSTACLE
			or cell_span_z > MAXIMUM_INDEXED_CELLS_PER_OBSTACLE
			or cell_span_x * cell_span_z > MAXIMUM_INDEXED_CELLS_PER_OBSTACLE
		):
			_global_instance_ids[instance_id] = true
			continue
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			for cell_z in range(minimum_cell.y, maximum_cell.y + 1):
				var cell := Vector2i(cell_x, cell_z)
				var ids: Dictionary = _instance_ids_by_cell.get(cell, {})
				ids[instance_id] = true
				_instance_ids_by_cell[cell] = ids


func _records_for_bounds(
	minimum_x: float,
	maximum_x: float,
	minimum_z: float,
	maximum_z: float
) -> Array[Dictionary]:
	query_count += 1
	var minimum_cell := _cell_for_position(Vector3(minimum_x, 0.0, minimum_z))
	var maximum_cell := _cell_for_position(Vector3(maximum_x, 0.0, maximum_z))
	var cache_key := Vector4i(
		minimum_cell.x,
		minimum_cell.y,
		maximum_cell.x,
		maximum_cell.y
	)
	var cached_value: Variant = _records_by_bounds_cache.get(cache_key)
	if cached_value is Array:
		query_cache_hit_count += 1
		var cached_records: Array = cached_value
		candidate_count += cached_records.size()
		return cached_records
	var unique_ids: Dictionary = _global_instance_ids.duplicate()
	for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
		for cell_z in range(minimum_cell.y, maximum_cell.y + 1):
			var ids: Dictionary = _instance_ids_by_cell.get(
				Vector2i(cell_x, cell_z),
				{}
			)
			for instance_id in ids:
				unique_ids[instance_id] = true
	var result: Array[Dictionary] = []
	for instance_id in unique_ids:
		var record: Dictionary = _records_by_instance_id.get(instance_id, {})
		var body := record.get("body") as Node3D
		if not record.is_empty() and is_instance_valid(body):
			result.append(record)
	if _records_by_bounds_cache.size() >= MAXIMUM_QUERY_CACHE_ENTRIES:
		_records_by_bounds_cache.clear()
	_records_by_bounds_cache[cache_key] = result
	candidate_count += result.size()
	return result


func _cell_for_position(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / cell_size_m),
		floori(position.z / cell_size_m)
	)


func _ray_shape_distance(
	record: Dictionary,
	origin: Vector3,
	world_direction: Vector3,
	maximum_distance_m: float,
	local_inflation: Vector3
) -> float:
	var inverse_transform: Transform3D = record.get(
		"inverse_transform",
		Transform3D.IDENTITY
	)
	var local_origin := inverse_transform * origin
	var local_direction := inverse_transform.basis * world_direction
	var kind := int(record.get(
		"shape_kind",
		DroneTrainingObstacleShape.Kind.BOX
	))
	var dimensions: Dictionary = record.get("dimensions", {})
	var inflation := Vector3(
		maxf(local_inflation.x, 0.0),
		maxf(local_inflation.y, 0.0),
		maxf(local_inflation.z, 0.0)
	)
	match kind:
		DroneTrainingObstacleShape.Kind.CYLINDER:
			return _ray_local_cylinder_distance(
				local_origin,
				local_direction,
				float(dimensions.get("radius", 1.0)) + maxf(inflation.x, inflation.z),
				float(dimensions.get("height", 1.0)) * 0.5 + inflation.y,
				maximum_distance_m
			)
		DroneTrainingObstacleShape.Kind.SPHERE:
			return _ray_local_sphere_distance(
				local_origin,
				local_direction,
				float(dimensions.get("radius", 1.0)) + inflation.length(),
				maximum_distance_m
			)
		DroneTrainingObstacleShape.Kind.CAPSULE:
			return _ray_local_capsule_distance(
				local_origin,
				local_direction,
				float(dimensions.get("radius", 1.0)) + maxf(inflation.x, inflation.z),
				float(dimensions.get("height", 2.0)) * 0.5 + inflation.y,
				maximum_distance_m
			)
	var half_size := DroneTrainingObstacleShape.local_half_extents(kind, dimensions)
	half_size += inflation
	return _ray_local_box_distance(
		local_origin,
		local_direction,
		half_size,
		maximum_distance_m
	)


func _ray_local_box_distance(
	local_origin: Vector3,
	local_direction: Vector3,
	half_size: Vector3,
	maximum_distance_m: float
) -> float:
	var minimum_t := 0.0
	var maximum_t := maximum_distance_m
	for axis in range(3):
		var origin_axis := local_origin[axis]
		var direction_axis := local_direction[axis]
		var half_axis := half_size[axis]
		if absf(direction_axis) <= RAY_EPSILON:
			if origin_axis < -half_axis or origin_axis > half_axis:
				return -1.0
			continue
		var inverse_axis := 1.0 / direction_axis
		var first_t := (-half_axis - origin_axis) * inverse_axis
		var second_t := (half_axis - origin_axis) * inverse_axis
		if first_t > second_t:
			var swap := first_t
			first_t = second_t
			second_t = swap
		minimum_t = maxf(minimum_t, first_t)
		maximum_t = minf(maximum_t, second_t)
		if minimum_t > maximum_t:
			return -1.0
	if maximum_t < 0.0 or minimum_t > maximum_distance_m:
		return -1.0
	return clampf(maxf(minimum_t, 0.0), 0.0, maximum_distance_m)


func _ray_local_sphere_distance(
	origin: Vector3,
	direction: Vector3,
	radius: float,
	maximum_distance_m: float
) -> float:
	if origin.length_squared() <= radius * radius:
		return 0.0
	var a := direction.dot(direction)
	if a <= RAY_EPSILON:
		return -1.0
	var b := 2.0 * origin.dot(direction)
	var c := origin.dot(origin) - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var denominator := 2.0 * a
	var first := (-b - root) / denominator
	var second := (-b + root) / denominator
	var result := INF
	if first >= 0.0:
		result = first
	elif second >= 0.0:
		result = second
	return result if result <= maximum_distance_m else -1.0


func _ray_local_cylinder_distance(
	origin: Vector3,
	direction: Vector3,
	radius: float,
	half_height: float,
	maximum_distance_m: float
) -> float:
	if (
		origin.x * origin.x + origin.z * origin.z <= radius * radius
		and absf(origin.y) <= half_height
	):
		return 0.0
	var result := INF
	var a := direction.x * direction.x + direction.z * direction.z
	if a > RAY_EPSILON:
		var b := 2.0 * (origin.x * direction.x + origin.z * direction.z)
		var c := origin.x * origin.x + origin.z * origin.z - radius * radius
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			for candidate in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
				if candidate < 0.0 or candidate > maximum_distance_m:
					continue
				var candidate_y = origin.y + direction.y * candidate
				if absf(candidate_y) <= half_height:
					result = minf(result, candidate)
	if absf(direction.y) > RAY_EPSILON:
		for cap_y in [-half_height, half_height]:
			var candidate = (cap_y - origin.y) / direction.y
			if candidate < 0.0 or candidate > maximum_distance_m:
				continue
			var x = origin.x + direction.x * candidate
			var z = origin.z + direction.z * candidate
			if x * x + z * z <= radius * radius:
				result = minf(result, candidate)
	return result if is_finite(result) else -1.0


func _ray_local_capsule_distance(
	origin: Vector3,
	direction: Vector3,
	radius: float,
	half_height: float,
	maximum_distance_m: float
) -> float:
	var body_half_height := maxf(half_height - radius, 0.0)
	var result := _ray_local_cylinder_distance(
		origin,
		direction,
		radius,
		body_half_height,
		maximum_distance_m
	)
	for center_y in [-body_half_height, body_half_height]:
		var sphere_distance := _ray_local_sphere_distance(
			origin - Vector3(0.0, center_y, 0.0),
			direction,
			radius,
			maximum_distance_m
		)
		if sphere_distance >= 0.0 and (result < 0.0 or sphere_distance < result):
			result = sphere_distance
	return result
