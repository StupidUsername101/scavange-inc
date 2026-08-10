@tool
class_name DroneCoreEditableMeshDefinition
extends Resource

#######################################################
# Serialized, creator-authored topology for an editable drone Core. The topology deliberately keeps
# logical polygon faces separate from the triangulated render mesh so later tools can subdivide faces
# or edges without reverse-engineering topology from render triangles.
#######################################################

const MINIMUM_AXIS_SIZE: float = 0.05
const MINIMUM_FACE_SCALE: float = 0.20
const MAXIMUM_FACE_SCALE: float = 5.0
const RAY_EPSILON: float = 0.000001

@export var vertices: PackedVector3Array = PackedVector3Array()
@export var face_offsets: PackedInt32Array = PackedInt32Array()
@export var face_vertex_indices: PackedInt32Array = PackedInt32Array()


func has_geometry() -> bool:
	if vertices.size() < 4 or face_offsets.size() < 2:
		return false
	if face_offsets[0] != 0 or face_offsets[face_offsets.size() - 1] != face_vertex_indices.size():
		return false
	for face_index: int in range(face_count()):
		if _face_end(face_index) - _face_start(face_index) < 3:
			return false
		for cursor: int in range(_face_start(face_index), _face_end(face_index)):
			var vertex_index: int = face_vertex_indices[cursor]
			if vertex_index < 0 or vertex_index >= vertices.size():
				return false
	return true


func ensure_box(size_value: Vector3) -> void:
	if has_geometry():
		return
	configure_box(size_value)


func configure_box(size_value: Vector3) -> void:
	var size: Vector3 = Vector3(
		maxf(absf(size_value.x), MINIMUM_AXIS_SIZE),
		maxf(absf(size_value.y), MINIMUM_AXIS_SIZE),
		maxf(absf(size_value.z), MINIMUM_AXIS_SIZE)
	)
	var half: Vector3 = size * 0.5
	vertices = PackedVector3Array([
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	])
	# Six logical quads with outward winding: back, front, left, right, bottom, top.
	face_offsets = PackedInt32Array([0, 4, 8, 12, 16, 20, 24])
	face_vertex_indices = PackedInt32Array([
		0, 3, 2, 1,
		4, 5, 6, 7,
		0, 4, 7, 3,
		1, 2, 6, 5,
		0, 1, 5, 4,
		3, 7, 6, 2,
	])


func face_count() -> int:
	return maxi(face_offsets.size() - 1, 0)


func face_indices(face_index: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if face_index < 0 or face_index >= face_count():
		return result
	for cursor: int in range(_face_start(face_index), _face_end(face_index)):
		result.append(face_vertex_indices[cursor])
	return result


func triangulated_indices() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for face_index: int in range(face_count()):
		var indices: PackedInt32Array = face_indices(face_index)
		if indices.size() < 3:
			continue
		for corner: int in range(1, indices.size() - 1):
			result.append(indices[0])
			result.append(indices[corner])
			result.append(indices[corner + 1])
	return result


func edge_vertex_pairs() -> PackedInt32Array:
	# Unique undirected logical edges, encoded as [a0, b0, a1, b1, ...]. Keeping this
	# derivable from polygon topology means future edge selection/subdivision does not depend on
	# render-triangle diagonals introduced by triangulation.
	var result: PackedInt32Array = PackedInt32Array()
	var seen: Dictionary = {}
	for face_index: int in range(face_count()):
		var indices: PackedInt32Array = face_indices(face_index)
		if indices.size() < 2:
			continue
		for corner: int in range(indices.size()):
			var vertex_a: int = indices[corner]
			var vertex_b: int = indices[(corner + 1) % indices.size()]
			var minimum_index: int = mini(vertex_a, vertex_b)
			var maximum_index: int = maxi(vertex_a, vertex_b)
			var key: String = "%d:%d" % [minimum_index, maximum_index]
			if seen.has(key):
				continue
			seen[key] = true
			result.append(minimum_index)
			result.append(maximum_index)
	return result


func edge_count() -> int:
	return int(edge_vertex_pairs().size() / 2)


func face_center(face_index: int) -> Vector3:
	var indices: PackedInt32Array = face_indices(face_index)
	if indices.is_empty():
		return Vector3.ZERO
	var center: Vector3 = Vector3.ZERO
	for vertex_index: int in indices:
		center += vertices[vertex_index]
	return center / float(indices.size())


func face_normal(face_index: int) -> Vector3:
	var indices: PackedInt32Array = face_indices(face_index)
	if indices.size() < 3:
		return Vector3.ZERO
	var origin: Vector3 = vertices[indices[0]]
	for corner: int in range(1, indices.size() - 1):
		var edge_a: Vector3 = vertices[indices[corner]] - origin
		var edge_b: Vector3 = vertices[indices[corner + 1]] - origin
		var normal: Vector3 = edge_a.cross(edge_b)
		if normal.length_squared() > RAY_EPSILON:
			return normal.normalized()
	return Vector3.ZERO


func scale_face(face_index: int, factor_value: float) -> bool:
	if face_index < 0 or face_index >= face_count():
		return false
	var factor: float = clampf(factor_value, MINIMUM_FACE_SCALE, MAXIMUM_FACE_SCALE)
	var indices: PackedInt32Array = face_indices(face_index)
	if indices.size() < 3:
		return false
	var center: Vector3 = face_center(face_index)
	for vertex_index: int in indices:
		vertices[vertex_index] = center + (vertices[vertex_index] - center) * factor
	return true


func set_bounds_size(size_value: Vector3) -> bool:
	if not has_geometry():
		configure_box(size_value)
		return true
	var current_size: Vector3 = bounds_size()
	var target_size: Vector3 = Vector3(
		maxf(absf(size_value.x), MINIMUM_AXIS_SIZE),
		maxf(absf(size_value.y), MINIMUM_AXIS_SIZE),
		maxf(absf(size_value.z), MINIMUM_AXIS_SIZE)
	)
	var scale_factor: Vector3 = Vector3(
		target_size.x / maxf(current_size.x, MINIMUM_AXIS_SIZE),
		target_size.y / maxf(current_size.y, MINIMUM_AXIS_SIZE),
		target_size.z / maxf(current_size.z, MINIMUM_AXIS_SIZE)
	)
	for vertex_index: int in range(vertices.size()):
		var vertex: Vector3 = vertices[vertex_index]
		vertices[vertex_index] = Vector3(
			vertex.x * scale_factor.x,
			vertex.y * scale_factor.y,
			vertex.z * scale_factor.z
		)
	return true


func bounds() -> AABB:
	if vertices.is_empty():
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var minimum: Vector3 = vertices[0]
	var maximum: Vector3 = vertices[0]
	for vertex_index: int in range(1, vertices.size()):
		var vertex: Vector3 = vertices[vertex_index]
		minimum.x = minf(minimum.x, vertex.x)
		minimum.y = minf(minimum.y, vertex.y)
		minimum.z = minf(minimum.z, vertex.z)
		maximum.x = maxf(maximum.x, vertex.x)
		maximum.y = maxf(maximum.y, vertex.y)
		maximum.z = maxf(maximum.z, vertex.z)
	return AABB(minimum, maximum - minimum)


func bounds_size() -> Vector3:
	return bounds().size


func ray_hit(origin: Vector3, direction_value: Vector3) -> Dictionary:
	if not has_geometry():
		return {}
	var direction: Vector3 = direction_value.normalized()
	if direction.length_squared() <= RAY_EPSILON:
		return {}
	var best_distance: float = INF
	var best_hit: Dictionary = {}
	for face_index: int in range(face_count()):
		var indices: PackedInt32Array = face_indices(face_index)
		if indices.size() < 3:
			continue
		var first_vertex: Vector3 = vertices[indices[0]]
		for corner: int in range(1, indices.size() - 1):
			var triangle_b: Vector3 = vertices[indices[corner]]
			var triangle_c: Vector3 = vertices[indices[corner + 1]]
			var hit_distance: float = _ray_triangle_distance(
				origin,
				direction,
				first_vertex,
				triangle_b,
				triangle_c
			)
			if hit_distance >= 0.0 and hit_distance < best_distance:
				var triangle_normal: Vector3 = (triangle_b - first_vertex).cross(
					triangle_c - first_vertex
				).normalized()
				best_distance = hit_distance
				best_hit = {
					"distance": hit_distance,
					"point": origin + direction * hit_distance,
					"normal": triangle_normal,
					"face_index": face_index,
				}
	return best_hit


func point_is_on_face(point: Vector3, face_index: int, tolerance: float = 0.015) -> bool:
	var indices: PackedInt32Array = face_indices(face_index)
	if indices.size() < 3:
		return false
	var normal: Vector3 = face_normal(face_index)
	if normal.length_squared() <= RAY_EPSILON:
		return false
	var plane_distance: float = absf(normal.dot(point - vertices[indices[0]]))
	if plane_distance > tolerance:
		return false
	var first_vertex: Vector3 = vertices[indices[0]]
	for corner: int in range(1, indices.size() - 1):
		if _point_in_triangle(
			point,
			first_vertex,
			vertices[indices[corner]],
			vertices[indices[corner + 1]],
			normal,
			tolerance
		):
			return true
	return false


func _face_start(face_index: int) -> int:
	return face_offsets[face_index]


func _face_end(face_index: int) -> int:
	return face_offsets[face_index + 1]


func _ray_triangle_distance(
	origin: Vector3,
	direction: Vector3,
	vertex_a: Vector3,
	vertex_b: Vector3,
	vertex_c: Vector3
) -> float:
	var edge_ab: Vector3 = vertex_b - vertex_a
	var edge_ac: Vector3 = vertex_c - vertex_a
	var perpendicular: Vector3 = direction.cross(edge_ac)
	var determinant: float = edge_ab.dot(perpendicular)
	if absf(determinant) <= RAY_EPSILON:
		return -1.0
	var inverse_determinant: float = 1.0 / determinant
	var offset: Vector3 = origin - vertex_a
	var u: float = offset.dot(perpendicular) * inverse_determinant
	if u < 0.0 or u > 1.0:
		return -1.0
	var q: Vector3 = offset.cross(edge_ab)
	var v: float = direction.dot(q) * inverse_determinant
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var distance: float = edge_ac.dot(q) * inverse_determinant
	return distance if distance >= 0.0 else -1.0


func _point_in_triangle(
	point: Vector3,
	vertex_a: Vector3,
	vertex_b: Vector3,
	vertex_c: Vector3,
	normal: Vector3,
	tolerance: float
) -> bool:
	var edge_ab: Vector3 = vertex_b - vertex_a
	var edge_bc: Vector3 = vertex_c - vertex_b
	var edge_ca: Vector3 = vertex_a - vertex_c
	var cross_a: float = normal.dot(edge_ab.cross(point - vertex_a))
	var cross_b: float = normal.dot(edge_bc.cross(point - vertex_b))
	var cross_c: float = normal.dot(edge_ca.cross(point - vertex_c))
	return cross_a >= -tolerance and cross_b >= -tolerance and cross_c >= -tolerance
