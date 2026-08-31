class_name DestructionMeshAudit
extends RefCounted

## Test-only geometry oracle for destruction traces. Shipping code deliberately does not call this:
## its dictionaries, positional weld map, and O(n^2) self-intersection fallback are intended for
## deterministic fixtures and CI, not the frame loop.

const DEFAULT_WELD_EPSILON := 0.00001
const AREA_EPSILON_SQUARED := 0.00000000000001
const NORMAL_EPSILON_SQUARED := 0.00000001


static func clone_result(result: Dictionary) -> Dictionary:
	var clone := result.duplicate(false)
	for key: StringName in [
		&"vertices", &"normals", &"indices", &"shell_masks", &"colors",
		&"postprocess_remap", &"postprocess_valence",
	]:
		if result.has(key):
			var value: Variant = result[key]
			if value is PackedVector3Array:
				clone[key] = (value as PackedVector3Array).duplicate()
			elif value is PackedInt32Array:
				clone[key] = (value as PackedInt32Array).duplicate()
			elif value is PackedByteArray:
				clone[key] = (value as PackedByteArray).duplicate()
			elif value is PackedColorArray:
				clone[key] = (value as PackedColorArray).duplicate()
	return clone


static func audit_results(
	results: Array,
	field: SparseSdfVolumeData = null,
	weld_epsilon := DEFAULT_WELD_EPSILON,
	check_self_intersection := false
) -> Dictionary:
	var weld := maxf(weld_epsilon, 0.0000001)
	var position_to_id: Dictionary[Vector3i, int] = {}
	var id_positions: Array[Vector3] = []
	var id_normals: Array[Vector3] = []
	var id_normal_counts := PackedInt32Array()
	var triangles: Array[Vector3i] = []
	var triangle_sources: Array[Vector2i] = []
	var triangle_authored_normals: Array[Vector3] = []
	var invalid_indices := 0
	var non_finite_vertices := 0
	var non_finite_normals := 0
	var maximum_vertex_surface_error := 0.0

	for result_index: int in range(results.size()):
		var result: Dictionary = results[result_index]
		var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
		var local_ids := PackedInt32Array()
		local_ids.resize(vertices.size())
		for vertex_index: int in range(vertices.size()):
			var vertex := vertices[vertex_index]
			if not vertex.is_finite():
				non_finite_vertices += 1
				local_ids[vertex_index] = -1
				continue
			var key := Vector3i(
				roundi(vertex.x / weld),
				roundi(vertex.y / weld),
				roundi(vertex.z / weld)
			)
			var canonical_id := int(position_to_id.get(key, -1))
			if canonical_id < 0:
				canonical_id = id_positions.size()
				position_to_id[key] = canonical_id
				id_positions.append(vertex)
				id_normals.append(Vector3.ZERO)
				id_normal_counts.resize(id_positions.size())
			local_ids[vertex_index] = canonical_id
			if vertex_index < normals.size():
				var normal := normals[vertex_index]
				if normal.is_finite():
					id_normals[canonical_id] += normal
					id_normal_counts[canonical_id] += 1
				else:
					non_finite_normals += 1
			if field != null:
				maximum_vertex_surface_error = maxf(
					maximum_vertex_surface_error,
					absf(field.sample_distance(vertex))
				)
		if indices.size() % 3 != 0:
			invalid_indices += indices.size() % 3
		for offset: int in range(0, indices.size() - 2, 3):
			var first := indices[offset]
			var second := indices[offset + 1]
			var third := indices[offset + 2]
			if (
				first < 0 or first >= local_ids.size()
				or second < 0 or second >= local_ids.size()
				or third < 0 or third >= local_ids.size()
				or local_ids[first] < 0 or local_ids[second] < 0 or local_ids[third] < 0
			):
				invalid_indices += 1
				continue
			triangles.append(Vector3i(local_ids[first], local_ids[second], local_ids[third]))
			triangle_sources.append(Vector2i(result_index, offset / 3))
			triangle_authored_normals.append(
				normals[first] + normals[second] + normals[third]
				if normals.size() == vertices.size()
				else Vector3.ZERO
			)

	var edge_counts: Dictionary[Vector2i, int] = {}
	var face_counts: Dictionary[String, int] = {}
	var adjacency: Array[Dictionary] = []
	adjacency.resize(id_positions.size())
	for vertex_id: int in range(adjacency.size()):
		adjacency[vertex_id] = {}
	var degenerate_triangles := 0
	var duplicate_faces := 0
	var reversed_duplicate_faces := 0
	var wrong_winding := 0
	var extreme_aspect_triangles := 0
	var minimum_quality := 1.0
	var maximum_centroid_surface_error := 0.0
	var maximum_normal_angle_degrees := 0.0
	var total_area := 0.0
	var signed_volume := 0.0
	for triangle_index: int in range(triangles.size()):
		var triangle := triangles[triangle_index]
		var first := id_positions[triangle.x]
		var second := id_positions[triangle.y]
		var third := id_positions[triangle.z]
		var first_edge := second - first
		var second_edge := third - second
		var third_edge := first - third
		var face_cross := first_edge.cross(-third_edge)
		var area_squared := face_cross.length_squared() * 0.25
		if (
			triangle.x == triangle.y or triangle.y == triangle.z or triangle.z == triangle.x
			or area_squared <= AREA_EPSILON_SQUARED
		):
			degenerate_triangles += 1
			continue
		var edge_sum := (
			first_edge.length_squared()
			+ second_edge.length_squared()
			+ third_edge.length_squared()
		)
		var quality := 2.0 * sqrt(3.0) * face_cross.length() / maxf(edge_sum, 0.000000001)
		minimum_quality = minf(minimum_quality, quality)
		if quality < 0.01:
			extreme_aspect_triangles += 1
		total_area += face_cross.length() * 0.5
		signed_volume += first.dot(second.cross(third)) / 6.0
		var authored := triangle_authored_normals[triangle_index]
		if authored.length_squared() > NORMAL_EPSILON_SQUARED:
			if face_cross.dot(authored) >= 0.0:
				wrong_winding += 1
			var normal_dot := clampf(
				(-face_cross.normalized()).dot(authored.normalized()), -1.0, 1.0
			)
			maximum_normal_angle_degrees = maxf(
				maximum_normal_angle_degrees,
				rad_to_deg(acos(normal_dot))
			)
		if field != null:
			maximum_centroid_surface_error = maxf(
				maximum_centroid_surface_error,
				absf(field.sample_distance((first + second + third) / 3.0))
			)
		_register_edge(triangle.x, triangle.y, edge_counts, adjacency)
		_register_edge(triangle.y, triangle.z, edge_counts, adjacency)
		_register_edge(triangle.z, triangle.x, edge_counts, adjacency)
		var sorted_ids := PackedInt32Array([triangle.x, triangle.y, triangle.z])
		sorted_ids.sort()
		var face_key := "%d:%d:%d" % [sorted_ids[0], sorted_ids[1], sorted_ids[2]]
		var orientation := _triangle_orientation_class(triangle, sorted_ids)
		var old_orientation := int(face_counts.get(face_key, 0))
		if old_orientation != 0:
			duplicate_faces += 1
			if old_orientation != orientation:
				reversed_duplicate_faces += 1
		else:
			face_counts[face_key] = orientation

	var boundary_edges := 0
	var non_manifold_edges := 0
	var edge_incidence_histogram: Dictionary[int, int] = {}
	for edge: Vector2i in edge_counts:
		var count := int(edge_counts[edge])
		edge_incidence_histogram[count] = int(edge_incidence_histogram.get(count, 0)) + 1
		if count == 1:
			boundary_edges += 1
		elif count != 2:
			non_manifold_edges += 1

	var component_count := 0
	var component_vertex_counts := PackedInt32Array()
	var visited := PackedByteArray()
	visited.resize(adjacency.size())
	for start: int in range(adjacency.size()):
		if visited[start] != 0 or adjacency[start].is_empty():
			continue
		component_count += 1
		var count := 0
		var pending: Array[int] = [start]
		visited[start] = 1
		while not pending.is_empty():
			var current: int = pending.pop_back()
			count += 1
			for neighbor: int in adjacency[current]:
				if visited[neighbor] != 0:
					continue
				visited[neighbor] = 1
				pending.append(neighbor)
		component_vertex_counts.append(count)

	var self_intersections := 0
	if check_self_intersection:
		self_intersections = _count_triangle_intersections(id_positions, triangles)
	return {
		"vertex_count": id_positions.size(),
		"triangle_count": triangles.size(),
		"invalid_indices": invalid_indices,
		"non_finite_vertices": non_finite_vertices,
		"non_finite_normals": non_finite_normals,
		"degenerate_triangles": degenerate_triangles,
		"duplicate_faces": duplicate_faces,
		"reversed_duplicate_faces": reversed_duplicate_faces,
		"boundary_edges": boundary_edges,
		"non_manifold_edges": non_manifold_edges,
		"edge_incidence_histogram": edge_incidence_histogram,
		"component_count": component_count,
		"component_vertex_counts": component_vertex_counts,
		"wrong_winding": wrong_winding,
		"extreme_aspect_triangles": extreme_aspect_triangles,
		"minimum_triangle_quality": minimum_quality if not triangles.is_empty() else 0.0,
		"maximum_vertex_surface_error": maximum_vertex_surface_error,
		"maximum_centroid_surface_error": maximum_centroid_surface_error,
		"maximum_normal_angle_degrees": maximum_normal_angle_degrees,
		"self_intersections": self_intersections,
		"surface_area": total_area,
		"signed_volume": signed_volume,
	}


static func is_closed_valid(audit: Dictionary) -> bool:
	return (
		int(audit.get("triangle_count", 0)) > 0
		and int(audit.get("invalid_indices", 0)) == 0
		and int(audit.get("non_finite_vertices", 0)) == 0
		and int(audit.get("non_finite_normals", 0)) == 0
		and int(audit.get("degenerate_triangles", 0)) == 0
		and int(audit.get("duplicate_faces", 0)) == 0
		and int(audit.get("boundary_edges", 0)) == 0
		and int(audit.get("non_manifold_edges", 0)) == 0
		and int(audit.get("wrong_winding", 0)) == 0
		and int(audit.get("self_intersections", 0)) == 0
	)


static func write_trace(
	path_without_extension: String,
	metadata: Dictionary,
	stages: Dictionary[StringName, Array]
) -> Error:
	var summary := metadata.duplicate(true)
	summary["stages"] = {}
	for stage_name: StringName in stages:
		var results: Array[Dictionary] = []
		for value: Variant in stages[stage_name]:
			if value is Dictionary:
				results.append(value)
		(summary["stages"] as Dictionary)[str(stage_name)] = audit_results(results)
		var obj_error := _write_obj("%s-%s.obj" % [path_without_extension, stage_name], results)
		if obj_error != OK:
			return obj_error
	var json_file := FileAccess.open(path_without_extension + ".json", FileAccess.WRITE)
	if json_file == null:
		return FileAccess.get_open_error()
	json_file.store_string(JSON.stringify(summary, "\t", false, true))
	return OK


static func _write_obj(path: String, results: Array[Dictionary]) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var vertex_base := 1
	for result_index: int in range(results.size()):
		var result: Dictionary = results[result_index]
		var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
		file.store_line("o chunk_%d" % result_index)
		for vertex: Vector3 in vertices:
			file.store_line("v %.9f %.9f %.9f" % [vertex.x, vertex.y, vertex.z])
		for offset: int in range(0, indices.size() - 2, 3):
			# Reverse Godot's clockwise front-face order for conventional OBJ viewers.
			file.store_line("f %d %d %d" % [
				vertex_base + indices[offset],
				vertex_base + indices[offset + 2],
				vertex_base + indices[offset + 1],
			])
		vertex_base += vertices.size()
	return OK


static func _register_edge(
	first: int,
	second: int,
	edge_counts: Dictionary[Vector2i, int],
	adjacency: Array[Dictionary]
) -> void:
	var edge := Vector2i(mini(first, second), maxi(first, second))
	edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
	adjacency[first][second] = true
	adjacency[second][first] = true


static func _triangle_orientation_class(triangle: Vector3i, sorted_ids: PackedInt32Array) -> int:
	var permutation := PackedInt32Array([
		sorted_ids.find(triangle.x),
		sorted_ids.find(triangle.y),
		sorted_ids.find(triangle.z),
	])
	var inversions := 0
	for first: int in range(2):
		for second: int in range(first + 1, 3):
			if permutation[first] > permutation[second]:
				inversions += 1
	return 1 if inversions % 2 == 0 else -1


static func _count_triangle_intersections(
	positions: Array[Vector3],
	triangles: Array[Vector3i]
) -> int:
	# Fixtures stay deliberately small. AABB rejection keeps this cheap while the exact predicate is
	# independently cross-checked against CGAL for any dumped failure trace.
	var count := 0
	for first_index: int in range(triangles.size()):
		var first := triangles[first_index]
		var first_aabb := _triangle_aabb(
			positions[first.x], positions[first.y], positions[first.z]
		)
		for second_index: int in range(first_index + 1, triangles.size()):
			var second := triangles[second_index]
			if _triangles_share_vertex(first, second):
				continue
			var second_aabb := _triangle_aabb(
				positions[second.x], positions[second.y], positions[second.z]
			)
			if not first_aabb.intersects(second_aabb):
				continue
			if _triangles_intersect(
				positions[first.x], positions[first.y], positions[first.z],
				positions[second.x], positions[second.y], positions[second.z]
			):
				count += 1
	return count


static func _triangles_share_vertex(first: Vector3i, second: Vector3i) -> bool:
	return (
		first.x == second.x or first.x == second.y or first.x == second.z
		or first.y == second.x or first.y == second.y or first.y == second.z
		or first.z == second.x or first.z == second.y or first.z == second.z
	)


static func _triangle_aabb(first: Vector3, second: Vector3, third: Vector3) -> AABB:
	return AABB(first, Vector3.ZERO).expand(second).expand(third).grow(0.0000001)


static func _triangles_intersect(
	a0: Vector3, a1: Vector3, a2: Vector3,
	b0: Vector3, b1: Vector3, b2: Vector3
) -> bool:
	return (
		_segment_hits_triangle(a0, a1, b0, b1, b2)
		or _segment_hits_triangle(a1, a2, b0, b1, b2)
		or _segment_hits_triangle(a2, a0, b0, b1, b2)
		or _segment_hits_triangle(b0, b1, a0, a1, a2)
		or _segment_hits_triangle(b1, b2, a0, a1, a2)
		or _segment_hits_triangle(b2, b0, a0, a1, a2)
	)


static func _segment_hits_triangle(
	start: Vector3,
	finish: Vector3,
	first: Vector3,
	second: Vector3,
	third: Vector3
) -> bool:
	# Moller-Trumbore on a closed segment. Coplanar overlap is intentionally delegated to the CGAL
	# confirmation path; the destruction fixtures primarily need to catch crossing contour flaps.
	var direction := finish - start
	var edge_one := second - first
	var edge_two := third - first
	var p := direction.cross(edge_two)
	var determinant := edge_one.dot(p)
	if absf(determinant) <= 0.00000001:
		return false
	var inverse := 1.0 / determinant
	var translated := start - first
	var u := translated.dot(p) * inverse
	if u <= 0.000001 or u >= 0.999999:
		return false
	var q := translated.cross(edge_one)
	var v := direction.dot(q) * inverse
	if v <= 0.000001 or u + v >= 0.999999:
		return false
	var t := edge_two.dot(q) * inverse
	return t > 0.000001 and t < 0.999999
