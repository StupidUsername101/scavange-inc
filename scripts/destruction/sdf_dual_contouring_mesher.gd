class_name SdfDualContouringMesher
extends RefCounted

## Uniform-grid Dual Contouring extractor. Each macro-chunk owns grid edges whose start coordinate
## lies in that chunk; an extra cell ring supplies the neighboring dual vertices. This deterministic
## ownership avoids cracks and duplicate faces without requiring shared mutable mesh buffers.

const CORNER_OFFSETS: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 1),
	Vector3i(0, 1, 1),
	Vector3i(1, 1, 1),
]
const EDGE_CORNERS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
	Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]
const QEF_REGULARIZATION := 0.001
const QEF_MIN_DETERMINANT := 0.000000001
const MIN_EDGE_DENOMINATOR := 0.0000001
const SAMPLE_CACHE_HALO := 2


static func build_chunk(
	volume: SparseSdfVolumeData,
	chunk_coordinate: Vector3i
) -> Dictionary:
	if volume == null or not volume.brick_is_valid(chunk_coordinate):
		return _empty_result(chunk_coordinate)
	return build_chunk_snapshot(capture_chunk(volume, chunk_coordinate))


static func capture_chunk(
	volume: SparseSdfVolumeData,
	chunk_coordinate: Vector3i
) -> Dictionary:
	if volume == null or not volume.brick_is_valid(chunk_coordinate):
		return {}
	var cells := volume.brick_cells
	var chunk_global_cell_origin := chunk_coordinate * cells
	# Cache a two-sample halo once. The previous prototype repeatedly traversed sparse dictionaries
	# for every cell corner and performed six trilinear SDF queries per Hermite normal. Central
	# differences over this lattice preserve the same deterministic field at a fraction of the work.
	var sample_grid_size := cells + SAMPLE_CACHE_HALO * 2 + 1
	var sample_distances := PackedFloat32Array()
	sample_distances.resize(sample_grid_size * sample_grid_size * sample_grid_size)
	for sample_z: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO + 1):
		for sample_y: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO + 1):
			for sample_x: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO + 1):
				var local_sample := Vector3i(sample_x, sample_y, sample_z)
				sample_distances[_sample_cache_index(local_sample, sample_grid_size)] = (
					volume.distance_at_global_sample(chunk_global_cell_origin + local_sample)
				)
	return {
		"chunk_coordinate": chunk_coordinate,
		"cells": cells,
		"voxel_size": volume.voxel_size,
		"field_origin": -volume.half_extents,
		"chunk_global_cell_origin": chunk_global_cell_origin,
		"sample_grid_size": sample_grid_size,
		"sample_distances": sample_distances,
		"source_signature": volume.chunk_sample_revision_signature(chunk_coordinate),
	}


static func build_chunk_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return _empty_result(Vector3i.ZERO)
	var chunk_coordinate: Vector3i = snapshot.get("chunk_coordinate", Vector3i.ZERO)
	var cells := int(snapshot.get("cells", 0))
	var voxel_size := float(snapshot.get("voxel_size", 0.0))
	var field_origin: Vector3 = snapshot.get("field_origin", Vector3.ZERO)
	var chunk_global_cell_origin: Vector3i = snapshot.get(
		"chunk_global_cell_origin",
		Vector3i.ZERO
	)
	var sample_grid_size := int(snapshot.get("sample_grid_size", 0))
	var sample_distances: PackedFloat32Array = snapshot.get(
		"sample_distances",
		PackedFloat32Array()
	)
	if cells <= 0 or voxel_size <= 0.0 or sample_grid_size <= 0 or sample_distances.is_empty():
		return _empty_result(chunk_coordinate)
	var extended_size := cells + 2
	var cell_indices := PackedInt32Array()
	cell_indices.resize(extended_size * extended_size * extended_size)
	cell_indices.fill(-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var corner_distances := PackedFloat32Array()
	corner_distances.resize(8)

	for local_z: int in range(-1, cells + 1):
		for local_y: int in range(-1, cells + 1):
			for local_x: int in range(-1, cells + 1):
				var global_cell := (
					chunk_global_cell_origin + Vector3i(local_x, local_y, local_z)
				)
				var negative_count := 0
				for corner_index: int in range(8):
					var distance := _cached_distance(
						sample_distances,
						sample_grid_size,
						Vector3i(local_x, local_y, local_z) + CORNER_OFFSETS[corner_index]
					)
					corner_distances[corner_index] = distance
					if distance < 0.0:
						negative_count += 1
				if negative_count == 0 or negative_count == 8:
					continue

				var a00 := 0.0
				var a01 := 0.0
				var a02 := 0.0
				var a11 := 0.0
				var a12 := 0.0
				var a22 := 0.0
				var b0 := 0.0
				var b1 := 0.0
				var b2 := 0.0
				var point_sum := Vector3.ZERO
				var normal_sum := Vector3.ZERO
				var intersection_count := 0
				for edge: Vector2i in EDGE_CORNERS:
					var first_distance := corner_distances[edge.x]
					var second_distance := corner_distances[edge.y]
					if (first_distance < 0.0) == (second_distance < 0.0):
						continue
					var denominator := first_distance - second_distance
					var t := (
						clampf(first_distance / denominator, 0.0, 1.0)
						if absf(denominator) > MIN_EDGE_DENOMINATOR
						else 0.5
					)
					var first_position := (
						field_origin + Vector3(global_cell + CORNER_OFFSETS[edge.x]) * voxel_size
					)
					var second_position := (
						field_origin + Vector3(global_cell + CORNER_OFFSETS[edge.y]) * voxel_size
					)
					var point := first_position.lerp(second_position, t)
					var first_local_sample := (
						Vector3i(local_x, local_y, local_z) + CORNER_OFFSETS[edge.x]
					)
					var second_local_sample := (
						Vector3i(local_x, local_y, local_z) + CORNER_OFFSETS[edge.y]
					)
					var normal := _cached_gradient(
						sample_distances,
						sample_grid_size,
						first_local_sample
					).lerp(
						_cached_gradient(
							sample_distances,
							sample_grid_size,
							second_local_sample
						),
						t
					)
					if normal.length_squared() > 0.000001:
						normal = normal.normalized()
					else:
						normal = Vector3.UP
					var plane_distance := normal.dot(point)
					a00 += normal.x * normal.x
					a01 += normal.x * normal.y
					a02 += normal.x * normal.z
					a11 += normal.y * normal.y
					a12 += normal.y * normal.z
					a22 += normal.z * normal.z
					b0 += normal.x * plane_distance
					b1 += normal.y * plane_distance
					b2 += normal.z * plane_distance
					point_sum += point
					normal_sum += normal
					intersection_count += 1

				if intersection_count <= 0:
					continue
				var centroid := point_sum / float(intersection_count)
				var regularization := QEF_REGULARIZATION * float(intersection_count)
				a00 += regularization
				a11 += regularization
				a22 += regularization
				b0 += centroid.x * regularization
				b1 += centroid.y * regularization
				b2 += centroid.z * regularization
				var matrix := Basis(
					Vector3(a00, a01, a02),
					Vector3(a01, a11, a12),
					Vector3(a02, a12, a22)
				)
				var vertex := centroid
				if absf(matrix.determinant()) > QEF_MIN_DETERMINANT:
					var solved := matrix.inverse() * Vector3(b0, b1, b2)
					if solved.is_finite():
						vertex = solved
				var cell_minimum := field_origin + Vector3(global_cell) * voxel_size
				var cell_maximum := cell_minimum + Vector3.ONE * voxel_size
				vertex = Vector3(
					clampf(vertex.x, cell_minimum.x, cell_maximum.x),
					clampf(vertex.y, cell_minimum.y, cell_maximum.y),
					clampf(vertex.z, cell_minimum.z, cell_maximum.z)
				)
				var vertex_normal := (
					normal_sum.normalized()
					if normal_sum.length_squared() > 0.000001
					else Vector3.UP
				)
				var stored_index := vertices.size()
				vertices.append(vertex)
				normals.append(vertex_normal)
				cell_indices[_extended_index(
					local_x + 1,
					local_y + 1,
					local_z + 1,
					extended_size
				)] = stored_index

	var indices := PackedInt32Array()
	for local_z: int in range(cells):
		for local_y: int in range(cells):
			for local_x: int in range(cells):
				var edge_start := (
					chunk_global_cell_origin + Vector3i(local_x, local_y, local_z)
				)
				_append_owned_edge_quad(
					indices,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i.RIGHT,
					[
						Vector3i(0, -1, -1),
						Vector3i(0, 0, -1),
						Vector3i(0, 0, 0),
						Vector3i(0, -1, 0),
					],
					sample_distances,
					sample_grid_size
				)
				_append_owned_edge_quad(
					indices,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i.UP,
					[
						Vector3i(-1, 0, -1),
						Vector3i(-1, 0, 0),
						Vector3i(0, 0, 0),
						Vector3i(0, 0, -1),
					],
					sample_distances,
					sample_grid_size
					)
				_append_owned_edge_quad(
					indices,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i(0, 0, 1),
					[
						Vector3i(-1, -1, 0),
						Vector3i(0, -1, 0),
						Vector3i(0, 0, 0),
						Vector3i(-1, 0, 0),
					],
					sample_distances,
					sample_grid_size
					)

	var compacted := _compact_indexed_geometry(vertices, normals, indices)
	vertices = compacted.get("vertices", PackedVector3Array())
	normals = compacted.get("normals", PackedVector3Array())
	indices = compacted.get("indices", PackedInt32Array())
	return {
		"chunk_coordinate": chunk_coordinate,
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"triangle_count": indices.size() / 3,
		"empty": indices.is_empty(),
	}


static func _compact_indexed_geometry(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array
) -> Dictionary:
	if vertices.is_empty() or indices.is_empty():
		return {
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"indices": PackedInt32Array(),
		}
	# Halo cells are necessary while faces are owned and stitched, but many of their dual vertices
	# never enter an owned triangle. Remap once on the worker so those temporary vertices do not
	# inflate the uploaded mesh, its bounds, surface-color allocation, or later collision work.
	var remap := PackedInt32Array()
	remap.resize(vertices.size())
	remap.fill(-1)
	var compact_vertices := PackedVector3Array()
	var compact_normals := PackedVector3Array()
	var compact_indices := PackedInt32Array()
	compact_indices.resize(indices.size())
	for index_offset: int in range(indices.size()):
		var source_index := indices[index_offset]
		var compact_index := remap[source_index]
		if compact_index < 0:
			compact_index = compact_vertices.size()
			remap[source_index] = compact_index
			compact_vertices.append(vertices[source_index])
			compact_normals.append(normals[source_index])
		compact_indices[index_offset] = compact_index
	return {
		"vertices": compact_vertices,
		"normals": compact_normals,
		"indices": compact_indices,
	}


static func create_array_mesh(result: Dictionary) -> ArrayMesh:
	var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
	var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
	if vertices.is_empty() or indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = result.get("normals", PackedVector3Array())
	var colors: PackedColorArray = result.get("colors", PackedColorArray())
	if colors.size() == vertices.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_collision_faces(result: Dictionary) -> PackedVector3Array:
	var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index: int in range(indices.size()):
		faces[index] = vertices[indices[index]]
	return faces


static func _append_owned_edge_quad(
	indices: PackedInt32Array,
	cell_indices: PackedInt32Array,
	extended_size: int,
	edge_start: Vector3i,
	chunk_global_cell_origin: Vector3i,
	edge_direction: Vector3i,
	adjacent_cell_offsets: Array[Vector3i],
	sample_distances: PackedFloat32Array,
	sample_grid_size: int
) -> void:
	var local_edge_start := edge_start - chunk_global_cell_origin
	var first_distance := _cached_distance(
		sample_distances,
		sample_grid_size,
		local_edge_start
	)
	var second_distance := _cached_distance(
		sample_distances,
		sample_grid_size,
		local_edge_start + edge_direction
	)
	if (first_distance < 0.0) == (second_distance < 0.0):
		return
	var quad := PackedInt32Array()
	quad.resize(4)
	for corner_index: int in range(4):
		var local_cell := edge_start + adjacent_cell_offsets[corner_index] - chunk_global_cell_origin
		var lookup := _extended_index(
			local_cell.x + 1,
			local_cell.y + 1,
			local_cell.z + 1,
			extended_size
		)
		if lookup < 0 or lookup >= cell_indices.size():
			return
		quad[corner_index] = cell_indices[lookup]
		if quad[corner_index] < 0:
			return
	# Godot renders clockwise triangle winding as the front face. The SDF gradient stored in the
	# vertex normals points from solid toward air, so the geometric cross product must point against
	# that authored normal. The previous order was mathematically CCW: collision existed, but the
	# untouched exterior of every rebuilt chunk was back-face culled while parts of the crater's
	# inside remained visible. That made a small bullet impact look as if the box had collapsed.
	if first_distance < 0.0:
		indices.append_array(PackedInt32Array([quad[0], quad[3], quad[2], quad[0], quad[2], quad[1]]))
	else:
		indices.append_array(PackedInt32Array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]))


static func _extended_index(x: int, y: int, z: int, size: int) -> int:
	return x + size * (y + size * z)


static func _sample_cache_index(local_sample: Vector3i, size: int) -> int:
	var offset := local_sample + Vector3i.ONE * SAMPLE_CACHE_HALO
	return offset.x + size * (offset.y + size * offset.z)


static func _cached_distance(
	distances: PackedFloat32Array,
	size: int,
	local_sample: Vector3i
) -> float:
	return distances[_sample_cache_index(local_sample, size)]


static func _cached_gradient(
	distances: PackedFloat32Array,
	size: int,
	local_sample: Vector3i
) -> Vector3:
	var gradient := Vector3(
		_cached_distance(distances, size, local_sample + Vector3i.RIGHT)
			- _cached_distance(distances, size, local_sample - Vector3i.RIGHT),
		_cached_distance(distances, size, local_sample + Vector3i.UP)
			- _cached_distance(distances, size, local_sample - Vector3i.UP),
		_cached_distance(distances, size, local_sample + Vector3i(0, 0, 1))
			- _cached_distance(distances, size, local_sample - Vector3i(0, 0, 1))
	)
	return gradient.normalized() if gradient.length_squared() > 0.000001 else Vector3.ZERO


static func _empty_result(chunk_coordinate: Vector3i) -> Dictionary:
	return {
		"chunk_coordinate": chunk_coordinate,
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
		"empty": true,
	}
