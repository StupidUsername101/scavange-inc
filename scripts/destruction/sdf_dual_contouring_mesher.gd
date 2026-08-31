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
# Cyclic corners and corresponding boundary edges for each cube face. Two crossings connect
# directly. Four crossings are the marching-squares saddle and are paired using the bilinear
# asymptotic decider, which is identical from either neighboring cell/chunk.
const FACE_CORNERS: Array[Vector4i] = [
	Vector4i(0, 1, 3, 2),
	Vector4i(4, 5, 7, 6),
	Vector4i(0, 1, 5, 4),
	Vector4i(2, 3, 7, 6),
	Vector4i(0, 2, 6, 4),
	Vector4i(1, 3, 7, 5),
]
const FACE_EDGES: Array[Vector4i] = [
	Vector4i(0, 5, 1, 4),
	Vector4i(2, 7, 3, 6),
	Vector4i(0, 9, 2, 8),
	Vector4i(1, 11, 3, 10),
	Vector4i(4, 10, 6, 8),
	Vector4i(5, 11, 7, 9),
]
const MIN_EDGE_DENOMINATOR := 0.0000001
const MIN_CONTOUR_TRIANGLE_QUALITY := 0.0
const MIN_PRESENTED_TRIANGLE_QUALITY := 0.01
const TRIANGULATION_QUALITY_TIE_EPSILON := 0.0001
const SAMPLE_CACHE_HALO := 2
const BOX_SHELL_INTERSECTION_TOLERANCE_VOXELS := 0.02
const X_EDGE_CELL_OFFSETS: Array[Vector3i] = [
	Vector3i(0, -1, -1),
	Vector3i(0, 0, -1),
	Vector3i(0, 0, 0),
	Vector3i(0, -1, 0),
]
const Y_EDGE_CELL_OFFSETS: Array[Vector3i] = [
	Vector3i(-1, 0, -1),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 0),
	Vector3i(0, 0, -1),
]
const Z_EDGE_CELL_OFFSETS: Array[Vector3i] = [
	Vector3i(-1, -1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 0),
	Vector3i(-1, 0, 0),
]
# The local cube edge represented by each adjacent cell around an owned primal edge. Keeping this
# relation explicit lets an ambiguous cell select the contour component connected to that edge
# instead of forcing every surface sheet in the cell through one shared vertex.
const X_EDGE_LOCAL_SLOTS: Array[int] = [3, 2, 0, 1]
const Y_EDGE_LOCAL_SLOTS: Array[int] = [7, 5, 4, 6]
const Z_EDGE_LOCAL_SLOTS: Array[int] = [11, 10, 8, 9]
const CELL_EDGE_SLOT_COUNT := 12


static func create_native_kernel() -> Object:
	# Resolve by ClassDB rather than a statically named type so source-only checkouts and platforms
	# without a matching extension binary keep parsing and use the deterministic GDScript fallback.
	if not ClassDB.class_exists(&"SdfNativeKernel"):
		return null
	var instance: Object = ClassDB.instantiate(&"SdfNativeKernel")
	if instance == null or not instance.has_method(&"build_chunk_snapshot"):
		return null
	return instance


static func build_chunk(
	volume: SparseSdfVolumeData,
	chunk_coordinate: Vector3i
) -> Dictionary:
	if volume == null or not volume.brick_is_valid(chunk_coordinate):
		return _empty_result(chunk_coordinate)
	var snapshot := capture_chunk(volume, chunk_coordinate)
	return finalize_box_shell(build_chunk_snapshot(snapshot), snapshot)


static func capture_chunk(
	volume: SparseSdfVolumeData,
	chunk_coordinate: Vector3i,
	reuse_snapshot: Dictionary = {}
) -> Dictionary:
	if volume == null or not volume.brick_is_valid(chunk_coordinate):
		return {}
	var cells := volume.brick_cells
	var source_signature := volume.chunk_sample_revision_signature(chunk_coordinate)
	var native_kernel := volume.structural_native_kernel()
	if native_kernel != null and native_kernel.has_method(&"capture_cached_chunk"):
		var native_snapshot: Dictionary = native_kernel.call(
			&"capture_cached_chunk",
			chunk_coordinate,
			cells,
			source_signature,
			reuse_snapshot
		) as Dictionary
		if bool(native_snapshot.get("valid", false)):
			native_snapshot.erase("valid")
			return native_snapshot
	var chunk_global_cell_origin := chunk_coordinate * cells
	# Cache a two-sample halo once. The previous prototype repeatedly traversed sparse dictionaries
	# for every cell corner and performed six trilinear SDF queries per Hermite normal. Central
	# differences over this lattice preserve the same deterministic field at a fraction of the work.
	# Owned edges start in [0, cells - 1]. Their adjacent dual cells therefore span [-1, cells - 1],
	# and central-difference gradients need samples through [-2, cells + 1]. The positive side is one
	# sample shorter than the negative side; capturing the unused cells+2 plane made neighboring
	# chunks rebuild for edits they never read.
	var sample_grid_size := cells + SAMPLE_CACHE_HALO * 2
	var sample_distances := (
		reuse_snapshot["sample_distances"] as PackedFloat32Array
		if reuse_snapshot.has("sample_distances")
		else PackedFloat32Array()
	)
	sample_distances.resize(sample_grid_size * sample_grid_size * sample_grid_size)
	var write_index := 0
	for sample_z: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO):
		for sample_y: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO):
			for sample_x: int in range(-SAMPLE_CACHE_HALO, cells + SAMPLE_CACHE_HALO):
				sample_distances[write_index] = volume.distance_at_global_sample(
					chunk_global_cell_origin + Vector3i(sample_x, sample_y, sample_z)
				)
				write_index += 1
	reuse_snapshot["chunk_coordinate"] = chunk_coordinate
	reuse_snapshot["cells"] = cells
	reuse_snapshot["voxel_size"] = volume.voxel_size
	reuse_snapshot["field_origin"] = -volume.half_extents
	reuse_snapshot["field_half_extents"] = volume.half_extents
	reuse_snapshot["chunk_global_cell_origin"] = chunk_global_cell_origin
	reuse_snapshot["sample_grid_size"] = sample_grid_size
	reuse_snapshot["sample_distances"] = sample_distances
	reuse_snapshot["source_signature"] = source_signature
	return reuse_snapshot


static func build_chunk_snapshot(
	snapshot: Dictionary,
	reuse_result: Dictionary = {},
	reuse_cell_indices: PackedInt32Array = PackedInt32Array(),
	reuse_corner_distances: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
	if snapshot.is_empty():
		return _empty_result(Vector3i.ZERO, reuse_result)
	var chunk_coordinate: Vector3i = snapshot.get("chunk_coordinate", Vector3i.ZERO)
	var cells := int(snapshot.get("cells", 0))
	var voxel_size := float(snapshot.get("voxel_size", 0.0))
	var field_origin: Vector3 = snapshot.get("field_origin", Vector3.ZERO)
	var field_half_extents: Vector3 = snapshot.get("field_half_extents", Vector3.ZERO)
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
		return _empty_result(chunk_coordinate, reuse_result)
	var extended_size := cells + 1
	var cell_indices := reuse_cell_indices
	cell_indices.resize(extended_size * extended_size * extended_size * CELL_EDGE_SLOT_COUNT)
	cell_indices.fill(-1)
	var vertices := (
		reuse_result["vertices"] as PackedVector3Array
		if reuse_result.has("vertices")
		else PackedVector3Array()
	)
	var normals := (
		reuse_result["normals"] as PackedVector3Array
		if reuse_result.has("normals")
		else PackedVector3Array()
	)
	var indices := (
		reuse_result["indices"] as PackedInt32Array
		if reuse_result.has("indices")
		else PackedInt32Array()
	)
	var shell_masks := (
		reuse_result["shell_masks"] as PackedByteArray
		if reuse_result.has("shell_masks")
		else PackedByteArray()
	)
	vertices.resize(0)
	normals.resize(0)
	indices.resize(0)
	shell_masks.resize(0)
	var corner_distances := reuse_corner_distances
	corner_distances.resize(8)
	# Fixed-size scratch is reused for every cell. A cell can have several disconnected contour
	# components (the alternating-sign case is the important one), but never more than its 12 crossed
	# cube edges. Face connectivity yields the actual contour cycles and avoids both possible failures
	# of sign-only grouping: merging separate sheets through one vertex or splitting a saddle into an
	# open sheet. This is the uniform-grid topology partition used by manifold dual contouring.
	var edge_parents := PackedInt32Array()
	edge_parents.resize(CELL_EDGE_SLOT_COUNT)
	var edge_groups := PackedInt32Array()
	edge_groups.resize(CELL_EDGE_SLOT_COUNT)
	var group_roots := PackedInt32Array()
	group_roots.resize(CELL_EDGE_SLOT_COUNT)
	var group_counts := PackedInt32Array()
	group_counts.resize(CELL_EDGE_SLOT_COUNT)
	var group_point_sums := PackedVector3Array()
	group_point_sums.resize(CELL_EDGE_SLOT_COUNT)
	var group_normal_sums := PackedVector3Array()
	group_normal_sums.resize(CELL_EDGE_SLOT_COUNT)
	var group_shell_masks := PackedByteArray()
	group_shell_masks.resize(CELL_EDGE_SLOT_COUNT)
	var group_vertex_indices := PackedInt32Array()
	group_vertex_indices.resize(CELL_EDGE_SLOT_COUNT)

	for local_z: int in range(-1, cells):
		for local_y: int in range(-1, cells):
			for local_x: int in range(-1, cells):
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

				for edge_index: int in range(CELL_EDGE_SLOT_COUNT):
					edge_parents[edge_index] = edge_index
				for face_index: int in range(FACE_CORNERS.size()):
					var face_corners := FACE_CORNERS[face_index]
					var face_edges := FACE_EDGES[face_index]
					var crossing_first := -1
					var crossing_second := -1
					var crossing_count := 0
					for face_edge_index: int in range(4):
						var edge_index := face_edges[face_edge_index]
						var edge := EDGE_CORNERS[edge_index]
						if (
							(corner_distances[edge.x] < 0.0)
							== (corner_distances[edge.y] < 0.0)
						):
							continue
						if crossing_count == 0:
							crossing_first = edge_index
						elif crossing_count == 1:
							crossing_second = edge_index
						crossing_count += 1
					if crossing_count == 2:
						_union_corner_components(edge_parents, crossing_first, crossing_second)
					elif crossing_count == 4:
						# Bilinear asymptotic decider. Averaging the four corners is not enough: unequal
						# magnitudes can put the saddle on the opposite side of the zero contour and make two
						# neighboring arcs collapse onto the same dual edge.
						var saddle_determinant := (
							corner_distances[face_corners.x] * corner_distances[face_corners.z]
							- corner_distances[face_corners.y] * corner_distances[face_corners.w]
						)
						if saddle_determinant >= 0.0:
							_union_corner_components(edge_parents, face_edges.x, face_edges.y)
							_union_corner_components(edge_parents, face_edges.z, face_edges.w)
						else:
							_union_corner_components(edge_parents, face_edges.x, face_edges.w)
							_union_corner_components(edge_parents, face_edges.y, face_edges.z)
				edge_groups.fill(-1)
				var group_count := 0
				for edge_index: int in range(CELL_EDGE_SLOT_COUNT):
					var edge := EDGE_CORNERS[edge_index]
					var first_distance := corner_distances[edge.x]
					var second_distance := corner_distances[edge.y]
					if (first_distance < 0.0) == (second_distance < 0.0):
						continue
					var component_root := _corner_component_root(edge_parents, edge_index)
					var group_index := -1
					for candidate: int in range(group_count):
						if group_roots[candidate] == component_root:
							group_index = candidate
							break
					if group_index < 0:
						group_index = group_count
						group_count += 1
						group_roots[group_index] = component_root
						group_counts[group_index] = 0
						group_point_sums[group_index] = Vector3.ZERO
						group_normal_sums[group_index] = Vector3.ZERO
						group_shell_masks[group_index] = 0
					edge_groups[edge_index] = group_index
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
					group_shell_masks[group_index] |= _box_shell_mask(
						point,
						field_half_extents,
						voxel_size * BOX_SHELL_INTERSECTION_TOLERANCE_VOXELS
					)
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
					group_point_sums[group_index] += point
					group_normal_sums[group_index] += normal
					group_counts[group_index] += 1

				for group_index: int in range(group_count):
					var intersection_count := group_counts[group_index]
					if intersection_count <= 0:
						continue
					var shell_mask := int(group_shell_masks[group_index])
					var vertex := group_point_sums[group_index] / float(intersection_count)
					vertex = _snap_vertex_to_box_shell(vertex, field_half_extents, shell_mask)
					var normal_sum := group_normal_sums[group_index]
					var vertex_normal := (
						normal_sum.normalized()
						if normal_sum.length_squared() > 0.000001
						else Vector3.UP
					)
					group_vertex_indices[group_index] = vertices.size()
					vertices.append(vertex)
					normals.append(vertex_normal)
					shell_masks.append(shell_mask)
				var cell_lookup := _extended_index(
					local_x + 1,
					local_y + 1,
					local_z + 1,
					extended_size
				) * CELL_EDGE_SLOT_COUNT
				for edge_index: int in range(CELL_EDGE_SLOT_COUNT):
					var group_index := edge_groups[edge_index]
					if group_index >= 0:
						cell_indices[cell_lookup + edge_index] = group_vertex_indices[group_index]

	for local_z: int in range(cells):
		for local_y: int in range(cells):
			for local_x: int in range(cells):
				var edge_start := (
					chunk_global_cell_origin + Vector3i(local_x, local_y, local_z)
				)
				_append_owned_edge_quad(
					indices,
					vertices,
					normals,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i.RIGHT,
					X_EDGE_CELL_OFFSETS,
					X_EDGE_LOCAL_SLOTS,
					sample_distances,
					sample_grid_size
				)
				_append_owned_edge_quad(
					indices,
					vertices,
					normals,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i.UP,
					Y_EDGE_CELL_OFFSETS,
					Y_EDGE_LOCAL_SLOTS,
					sample_distances,
					sample_grid_size
					)
				_append_owned_edge_quad(
					indices,
					vertices,
					normals,
					cell_indices,
					extended_size,
					edge_start,
					chunk_global_cell_origin,
					Vector3i(0, 0, 1),
					Z_EDGE_CELL_OFFSETS,
					Z_EDGE_LOCAL_SLOTS,
					sample_distances,
					sample_grid_size
					)

	_compact_indexed_geometry_in_place(vertices, normals, indices, cell_indices, shell_masks)
	reuse_result["chunk_coordinate"] = chunk_coordinate
	reuse_result["vertices"] = vertices
	reuse_result["normals"] = normals
	reuse_result["indices"] = indices
	reuse_result["shell_masks"] = shell_masks
	reuse_result["triangle_count"] = indices.size() / 3
	reuse_result["empty"] = indices.is_empty()
	return reuse_result


static func _compact_indexed_geometry_in_place(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	cell_indices: PackedInt32Array,
	shell_masks: PackedByteArray = PackedByteArray()
) -> void:
	if vertices.is_empty() or indices.is_empty():
		vertices.resize(0)
		normals.resize(0)
		indices.resize(0)
		return
	# Halo cells are necessary while faces are owned and stitched, but many of their dual vertices
	# never enter an owned triangle. Reuse the now-dead cell lookup as the referenced/remap buffer,
	# compact vertices in ascending source order (which is safe in-place), and rewrite the existing
	# index array. The old path allocated three complete output arrays plus a remap per rebuilt chunk.
	cell_indices.fill(-1)
	for source_index: int in indices:
		cell_indices[source_index] = 0
	var write_index := 0
	for source_index: int in range(vertices.size()):
		if cell_indices[source_index] < 0:
			continue
		cell_indices[source_index] = write_index
		if write_index != source_index:
			vertices[write_index] = vertices[source_index]
			normals[write_index] = normals[source_index]
			if shell_masks.size() == vertices.size():
				shell_masks[write_index] = shell_masks[source_index]
		write_index += 1
	for index_offset: int in range(indices.size()):
		indices[index_offset] = cell_indices[indices[index_offset]]
	vertices.resize(write_index)
	normals.resize(write_index)
	if not shell_masks.is_empty():
		shell_masks.resize(write_index)


static func finalize_box_shell(result: Dictionary, snapshot: Dictionary) -> Dictionary:
	# One dual vertex normally serves every face meeting its cell. That is correct for a rounded
	# impact cavity, but it interpolates both position and lighting across the immutable box corners.
	# Extraction tags only genuine analytic-box intersections. Split those vertices per wall face so
	# untouched planes stay exactly planar and hard-shaded while the damaged interior remains smooth.
	if (
		bool(result.get("empty", true))
		or not result.has("vertices")
		or not result.has("normals")
		or not result.has("indices")
		or not result.has("shell_masks")
	):
		return result
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	var indices: PackedInt32Array = result["indices"]
	var shell_masks: PackedByteArray = result["shell_masks"]
	var source_vertex_count := vertices.size()
	if (
		source_vertex_count == 0
		or normals.size() != source_vertex_count
		or shell_masks.size() != source_vertex_count
		or indices.size() % 3 != 0
	):
		return result
	var face_vertex_remap := PackedInt32Array()
	face_vertex_remap.resize(source_vertex_count * 6)
	face_vertex_remap.fill(-1)
	for triangle_offset: int in range(0, indices.size(), 3):
		var first := indices[triangle_offset]
		var second := indices[triangle_offset + 1]
		var third := indices[triangle_offset + 2]
		if (
			first < 0 or first >= source_vertex_count
			or second < 0 or second >= source_vertex_count
			or third < 0 or third >= source_vertex_count
		):
			continue
		var common_mask := int(shell_masks[first]) & int(shell_masks[second]) & int(shell_masks[third])
		if common_mask == 0:
			continue
		var face_slot := _first_shell_face_slot(common_mask)
		var face_normal := _box_shell_normal(face_slot)
		# The contour was originally wound against interpolated SDF gradients. Replacing those gradients
		# with an exact analytic wall normal can expose the rare nearly-tangent triangle whose old average
		# pointed the other way. Revalidate winding at the same point we harden the normal.
		var geometric_normal := (vertices[second] - vertices[first]).cross(
			vertices[third] - vertices[first]
		)
		if geometric_normal.dot(face_normal) >= 0.0:
			var swap := indices[triangle_offset + 1]
			indices[triangle_offset + 1] = indices[triangle_offset + 2]
			indices[triangle_offset + 2] = swap
		for corner_offset: int in range(3):
			var source_index := indices[triangle_offset + corner_offset]
			var remap_index := source_index * 6 + face_slot
			var hard_index := face_vertex_remap[remap_index]
			if hard_index < 0:
				hard_index = vertices.size()
				face_vertex_remap[remap_index] = hard_index
				vertices.append(vertices[source_index])
				normals.append(face_normal)
				shell_masks.append(1 << face_slot)
			indices[triangle_offset + corner_offset] = hard_index
	# Remove source vertices used only by replaced shell triangles. Reuse one compact integer buffer;
	# this happens on the chunk worker, not on the frame that accepted the bullet.
	var compact_remap := PackedInt32Array()
	compact_remap.resize(vertices.size())
	_compact_indexed_geometry_in_place(
		vertices,
		normals,
		indices,
		compact_remap,
		shell_masks
	)
	result["vertices"] = vertices
	result["normals"] = normals
	result["indices"] = indices
	result["shell_masks"] = shell_masks
	result["triangle_count"] = indices.size() / 3
	result["empty"] = indices.is_empty()
	return result


static func split_box_reference_surface_classes(result: Dictionary) -> Dictionary:
	# Classify complete polygons against the immutable analytic shell. A contour vertex can sit on the
	# cut rim and serve both an exterior box face and an interior fracture face; duplicate that vertex
	# by class so material interpolation and later normal changes cannot cross the semantic boundary.
	if (
		bool(result.get("empty", true))
		or not result.has("vertices")
		or not result.has("normals")
		or not result.has("indices")
		or not result.has("shell_masks")
	):
		return result
	var source_vertices: PackedVector3Array = result["vertices"]
	var source_normals: PackedVector3Array = result["normals"]
	var source_indices: PackedInt32Array = result["indices"]
	var source_shell_masks: PackedByteArray = result["shell_masks"]
	if (
		source_vertices.is_empty()
		or source_normals.size() != source_vertices.size()
		or source_shell_masks.size() != source_vertices.size()
		or source_indices.size() % 3 != 0
	):
		return result
	var class_remap := PackedInt32Array()
	class_remap.resize(source_vertices.size() * 2)
	class_remap.fill(-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var shell_masks := PackedByteArray()
	var surface_classes := PackedByteArray()
	var indices := PackedInt32Array()
	indices.resize(source_indices.size())
	for triangle_offset: int in range(0, source_indices.size(), 3):
		var first := source_indices[triangle_offset]
		var second := source_indices[triangle_offset + 1]
		var third := source_indices[triangle_offset + 2]
		var common_shell_mask := (
			int(source_shell_masks[first])
			& int(source_shell_masks[second])
			& int(source_shell_masks[third])
		)
		var surface_class := 0 if common_shell_mask != 0 else 1
		for corner_offset: int in range(3):
			var source_index := source_indices[triangle_offset + corner_offset]
			var remap_offset := source_index * 2 + surface_class
			var destination_index := class_remap[remap_offset]
			if destination_index < 0:
				destination_index = vertices.size()
				class_remap[remap_offset] = destination_index
				vertices.append(source_vertices[source_index])
				normals.append(source_normals[source_index])
				shell_masks.append(source_shell_masks[source_index])
				surface_classes.append(surface_class)
			indices[triangle_offset + corner_offset] = destination_index
	result["vertices"] = vertices
	result["normals"] = normals
	result["indices"] = indices
	result["shell_masks"] = shell_masks
	result["surface_classes"] = surface_classes
	result["triangle_count"] = indices.size() / 3
	return result


static func _box_shell_mask(point: Vector3, half_extents: Vector3, tolerance: float) -> int:
	if half_extents.length_squared() <= 0.0:
		return 0
	var mask := 0
	if absf(point.x + half_extents.x) <= tolerance:
		mask |= 1 << 0
	if absf(point.x - half_extents.x) <= tolerance:
		mask |= 1 << 1
	if absf(point.y + half_extents.y) <= tolerance:
		mask |= 1 << 2
	if absf(point.y - half_extents.y) <= tolerance:
		mask |= 1 << 3
	if absf(point.z + half_extents.z) <= tolerance:
		mask |= 1 << 4
	if absf(point.z - half_extents.z) <= tolerance:
		mask |= 1 << 5
	return mask


static func _snap_vertex_to_box_shell(
	vertex: Vector3,
	half_extents: Vector3,
	mask: int
) -> Vector3:
	if mask & (1 << 0):
		vertex.x = -half_extents.x
	elif mask & (1 << 1):
		vertex.x = half_extents.x
	if mask & (1 << 2):
		vertex.y = -half_extents.y
	elif mask & (1 << 3):
		vertex.y = half_extents.y
	if mask & (1 << 4):
		vertex.z = -half_extents.z
	elif mask & (1 << 5):
		vertex.z = half_extents.z
	return vertex


static func _first_shell_face_slot(mask: int) -> int:
	for slot: int in range(6):
		if mask & (1 << slot):
			return slot
	return 0


static func _box_shell_normal(slot: int) -> Vector3:
	match slot:
		0: return Vector3.LEFT
		1: return Vector3.RIGHT
		2: return Vector3.DOWN
		3: return Vector3.UP
		4: return Vector3.FORWARD
		_: return Vector3.BACK


static func create_array_mesh(result: Dictionary, reuse_mesh: ArrayMesh = null) -> ArrayMesh:
	if not result.has("indices") or not result.has("vertices"):
		return null
	var indices: PackedInt32Array = result["indices"]
	var vertices: PackedVector3Array = result["vertices"]
	if vertices.is_empty() or indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = result["normals"] if result.has("normals") else null
	var colors := (
		result["colors"] as PackedColorArray
		if result.has("colors")
		else PackedColorArray()
	)
	if colors.size() == vertices.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := reuse_mesh if reuse_mesh != null else ArrayMesh.new()
	if mesh.get_surface_count() > 0:
		mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_collision_faces(
	result: Dictionary,
	reuse_faces: PackedVector3Array = PackedVector3Array()
) -> PackedVector3Array:
	if not result.has("vertices") or not result.has("indices"):
		reuse_faces.resize(0)
		return reuse_faces
	var vertices: PackedVector3Array = result["vertices"]
	var indices: PackedInt32Array = result["indices"]
	var faces := reuse_faces
	faces.resize(indices.size())
	for index: int in range(indices.size()):
		faces[index] = vertices[indices[index]]
	return faces


static func legacy_sanitize_after_vertex_edit_for_test(result: Dictionary) -> Dictionary:
	# Regression oracle only. Production no longer mutates extracted seam vertices, so it must never
	# need this topology-changing cleanup. The artifact pipeline deliberately applies the removed
	# legacy mutation and this sanitizer to prove why that architecture cannot return.
	if not result.has("vertices") or not result.has("indices"):
		return result
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = result["indices"]
	if vertices.is_empty() or normals.size() != vertices.size() or indices.size() % 3 != 0:
		indices.resize(0)
		result["indices"] = indices
		result["triangle_count"] = 0
		result["empty"] = true
		return result
	var remap := (
		result["postprocess_remap"] as PackedInt32Array
		if result.has("postprocess_remap")
		else PackedInt32Array()
	)
	var valence := (
		result["postprocess_valence"] as PackedInt32Array
		if result.has("postprocess_valence")
		else PackedInt32Array()
	)
	remap.resize(vertices.size())
	valence.resize(vertices.size())
	valence.fill(0)
	for vertex_index: int in range(vertices.size()):
		remap[vertex_index] = vertex_index
	for vertex_index: int in indices:
		if vertex_index >= 0 and vertex_index < vertices.size():
			valence[vertex_index] += 1
	var collapsed_edges := 0
	for read_offset: int in range(0, indices.size(), 3):
		var first := indices[read_offset]
		var second := indices[read_offset + 1]
		var third := indices[read_offset + 2]
		if (
			first < 0 or first >= vertices.size()
			or second < 0 or second >= vertices.size()
			or third < 0 or third >= vertices.size()
			or _triangle_quality(vertices, first, second, third)
			>= MIN_PRESENTED_TRIANGLE_QUALITY
		):
			continue
		# Collapse the shortest edge rather than deleting the sliver. Every adjacent triangle observes
		# the same remap, so the closed contour remains closed. Prefer the higher-valence endpoint: it
		# is the stable wall/rim vertex, while the low-valence endpoint is normally the needle tip.
		var collapse_first := first
		var collapse_second := second
		var shortest := vertices[first].distance_squared_to(vertices[second])
		var second_length := vertices[second].distance_squared_to(vertices[third])
		if second_length < shortest:
			shortest = second_length
			collapse_first = second
			collapse_second = third
		var third_length := vertices[third].distance_squared_to(vertices[first])
		if third_length < shortest:
			collapse_first = third
			collapse_second = first
		var first_root := _remap_root(remap, collapse_first)
		var second_root := _remap_root(remap, collapse_second)
		if first_root == second_root:
			continue
		var keep := first_root
		var discard := second_root
		if valence[discard] > valence[keep]:
			keep = second_root
			discard = first_root
		remap[discard] = keep
		valence[keep] += valence[discard]
		collapsed_edges += 1
	for vertex_index: int in range(vertices.size()):
		remap[vertex_index] = _remap_root(remap, vertex_index)
	var write_offset := 0
	var removed_count := 0
	var rewound_count := 0
	for read_offset: int in range(0, indices.size(), 3):
		var first := remap[indices[read_offset]]
		var second := remap[indices[read_offset + 1]]
		var third := remap[indices[read_offset + 2]]
		if (
			first == second or second == third or third == first
			or _triangle_quality(vertices, first, second, third) <= MIN_CONTOUR_TRIANGLE_QUALITY
		):
			removed_count += 1
			continue
		var face_normal := (vertices[second] - vertices[first]).cross(
			vertices[third] - vertices[first]
		)
		var authored_normal := normals[first] + normals[second] + normals[third]
		if face_normal.dot(authored_normal) >= 0.0:
			var swap := second
			second = third
			third = swap
			rewound_count += 1
		indices[write_offset] = first
		indices[write_offset + 1] = second
		indices[write_offset + 2] = third
		write_offset += 3
	indices.resize(write_offset)
	_compact_indexed_geometry_in_place(vertices, normals, indices, remap)
	result["vertices"] = vertices
	result["normals"] = normals
	result["indices"] = indices
	result["postprocess_remap"] = remap
	result["postprocess_valence"] = valence
	result["triangle_count"] = indices.size() / 3
	result["empty"] = indices.is_empty()
	result["removed_runtime_slivers"] = removed_count
	result["collapsed_runtime_edges"] = collapsed_edges
	result["rewound_runtime_triangles"] = rewound_count
	return result


static func _remap_root(remap: PackedInt32Array, vertex_index: int) -> int:
	var root := vertex_index
	while remap[root] != root:
		root = remap[root]
	while remap[vertex_index] != vertex_index:
		var parent := remap[vertex_index]
		remap[vertex_index] = root
		vertex_index = parent
	return root


static func _corner_component_root(parents: PackedInt32Array, corner_index: int) -> int:
	var root := corner_index
	while parents[root] != root:
		root = parents[root]
	while parents[corner_index] != corner_index:
		var parent := parents[corner_index]
		parents[corner_index] = root
		corner_index = parent
	return root


static func _union_corner_components(parents: PackedInt32Array, first: int, second: int) -> void:
	var first_root := _corner_component_root(parents, first)
	var second_root := _corner_component_root(parents, second)
	if first_root == second_root:
		return
	# Stable roots keep native/script output deterministic and make recorded destruction events
	# reproduce the same contour topology on every peer.
	if first_root < second_root:
		parents[second_root] = first_root
	else:
		parents[first_root] = second_root


static func _append_owned_edge_quad(
	indices: PackedInt32Array,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	cell_indices: PackedInt32Array,
	extended_size: int,
	edge_start: Vector3i,
	chunk_global_cell_origin: Vector3i,
	edge_direction: Vector3i,
	adjacent_cell_offsets: Array[Vector3i],
	adjacent_edge_slots: Array[int],
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
	var quad0 := -1
	var quad1 := -1
	var quad2 := -1
	var quad3 := -1
	for corner_index: int in range(4):
		var local_cell := edge_start + adjacent_cell_offsets[corner_index] - chunk_global_cell_origin
		var cell_lookup := _extended_index(
			local_cell.x + 1,
			local_cell.y + 1,
			local_cell.z + 1,
			extended_size
		)
		var lookup := cell_lookup * CELL_EDGE_SLOT_COUNT + adjacent_edge_slots[corner_index]
		if lookup < 0 or lookup >= cell_indices.size():
			return
		var vertex_index := cell_indices[lookup]
		if vertex_index < 0:
			return
		match corner_index:
			0: quad0 = vertex_index
			1: quad1 = vertex_index
			2: quad2 = vertex_index
			_: quad3 = vertex_index
	# Godot renders clockwise triangle winding as the front face. The SDF gradient stored in the
	# vertex normals points from solid toward air, so the geometric cross product must point against
	# that authored normal. The previous order was mathematically CCW: collision existed, but the
	# untouched exterior of every rebuilt chunk was back-face culled while parts of the crater's
	# inside remained visible. That made a small bullet impact look as if the box had collapsed.
	# A dual quad can be non-planar around a strongly curved cut. Always splitting it across 0--2
	# produces a long folded triangle in exactly the high-warp cases where the surface needs the
	# opposite diagonal. Pick the shorter geometric diagonal, preserving the same boundary and
	# winding. Besides removing those contour flaps, individual appends avoid a PackedInt32Array
	# allocation for every sign-changing grid edge.
	var zero_two_length := vertices[quad0].distance_squared_to(vertices[quad2])
	var one_three_length := vertices[quad1].distance_squared_to(vertices[quad3])
	# Near-square quads otherwise choose a different diagonal from sub-ULP QEF differences between
	# scripting/native implementations or CPU families. Bias ties to 0--2; genuinely shorter folds
	# still win. Normal alignment is deliberately not a diagonal tie-breaker: interpolated gradients
	# can differ by an ULP across runtimes even on a perfectly planar quad. Every emitted triangle is
	# independently wound against its actual authored normal below.
	var diagonal_tie_epsilon := maxf(maxf(zero_two_length, one_three_length), 0.00000001) * 0.00001
	var use_zero_two := zero_two_length <= one_three_length + diagonal_tie_epsilon
	# Maximize the worst triangle instead of relying on diagonal length alone. A clamped QEF vertex
	# can lie almost on one quad edge; the shorter diagonal can then cut off a needle-thin contour
	# sliver even though the opposite diagonal represents the same four boundary samples cleanly.
	# This is the actual source of the detached-looking wedges seen around high-energy impacts.
	var zero_two_quality := minf(
		_triangle_quality(vertices, quad0, quad2, quad3),
		_triangle_quality(vertices, quad0, quad1, quad2)
	)
	var one_three_quality := minf(
		_triangle_quality(vertices, quad0, quad1, quad3),
		_triangle_quality(vertices, quad1, quad2, quad3)
	)
	if absf(zero_two_quality - one_three_quality) > TRIANGULATION_QUALITY_TIE_EPSILON:
		use_zero_two = zero_two_quality > one_three_quality
	if first_distance < 0.0:
		if use_zero_two:
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad3, quad2
			)
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad2, quad1
			)
		else:
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad3, quad1
			)
			_append_contour_triangle(
				indices, vertices, normals, quad3, quad2, quad1
			)
	else:
		if use_zero_two:
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad1, quad2
			)
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad2, quad3
			)
		else:
			_append_contour_triangle(
				indices, vertices, normals, quad0, quad1, quad3
			)
			_append_contour_triangle(
				indices, vertices, normals, quad1, quad2, quad3
			)


static func _triangle_alignment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	first: int,
	second: int,
	third: int
) -> float:
	var face_normal := (vertices[second] - vertices[first]).cross(
		vertices[third] - vertices[first]
	)
	var authored_normal := normals[first] + normals[second] + normals[third]
	var denominator := face_normal.length_squared() * authored_normal.length_squared()
	if denominator <= 0.000000001:
		return 0.0
	# Godot's visible face is clockwise, while cross() describes mathematical CCW winding.
	# Therefore a usable contour triangle has a cross product opposed to the outward SDF normal.
	# Do not square this cosine: doing so made an inside-out triangle score exactly as highly as a
	# correctly oriented one. On a warped dual quad the diagonal chooser could consequently select a
	# fold, after which changing its index winding only made the spatially folded flap front-facing.
	return clampf(
		-face_normal.dot(authored_normal) / sqrt(denominator),
		-1.0,
		1.0
	)


static func _triangle_quality(
	vertices: PackedVector3Array,
	first: int,
	second: int,
	third: int
) -> float:
	var first_edge := vertices[second] - vertices[first]
	var second_edge := vertices[third] - vertices[second]
	var third_edge := vertices[first] - vertices[third]
	var edge_sum := (
		first_edge.length_squared()
		+ second_edge.length_squared()
		+ third_edge.length_squared()
	)
	if edge_sum <= 0.000000001:
		return 0.0
	# Scale-independent mean-ratio quality: zero for a sliver and one for an equilateral triangle.
	return clampf(
		2.0 * sqrt(3.0) * first_edge.cross(-third_edge).length() / edge_sum,
		0.0,
		1.0
	)


static func _append_contour_triangle(
	indices: PackedInt32Array,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	first: int,
	second: int,
	third: int
) -> void:
	# Godot's rendered front is clockwise. A strongly folded quad can reverse one geometric
	# triangle even when its topological boundary order is correct; orient that triangle from the
	# actual sampled SDF normal so back-face culling never turns it into a visible hole. The expensive
	# four-way diagonal scoring is reserved for strongly curved quads, but final winding is always
	# verified because even a locally aligned normal field can contain a geometrically folded face.
	var face_normal := (vertices[second] - vertices[first]).cross(
		vertices[third] - vertices[first]
	)
	var authored_normal := normals[first] + normals[second] + normals[third]
	# A sub-percent sliver carries no meaningful sampled area. Keeping it creates a long isolated
	# shard after rasterization; dropping it is the geometric collapse of an already coincident quad
	# corner, not a visual band-aid. The companion triangle still covers the non-degenerate quad area.
	if _triangle_quality(vertices, first, second, third) < MIN_CONTOUR_TRIANGLE_QUALITY:
		return
	if face_normal.dot(authored_normal) >= 0.0:
		var swap := second
		second = third
		third = swap
	indices.append(first)
	indices.append(second)
	indices.append(third)


static func _extended_index(x: int, y: int, z: int, size: int) -> int:
	return x + size * (y + size * z)


static func _sample_cache_index(local_sample: Vector3i, size: int) -> int:
	return (
		local_sample.x + SAMPLE_CACHE_HALO
		+ size * (
			local_sample.y + SAMPLE_CACHE_HALO
			+ size * (local_sample.z + SAMPLE_CACHE_HALO)
		)
	)


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


static func _empty_result(
	chunk_coordinate: Vector3i,
	reuse_result: Dictionary = {}
) -> Dictionary:
	var vertices := (
		reuse_result["vertices"] as PackedVector3Array
		if reuse_result.has("vertices")
		else PackedVector3Array()
	)
	var normals := (
		reuse_result["normals"] as PackedVector3Array
		if reuse_result.has("normals")
		else PackedVector3Array()
	)
	var indices := (
		reuse_result["indices"] as PackedInt32Array
		if reuse_result.has("indices")
		else PackedInt32Array()
	)
	var shell_masks := (
		reuse_result["shell_masks"] as PackedByteArray
		if reuse_result.has("shell_masks")
		else PackedByteArray()
	)
	vertices.resize(0)
	normals.resize(0)
	indices.resize(0)
	shell_masks.resize(0)
	reuse_result["chunk_coordinate"] = chunk_coordinate
	reuse_result["vertices"] = vertices
	reuse_result["normals"] = normals
	reuse_result["indices"] = indices
	reuse_result["shell_masks"] = shell_masks
	reuse_result["triangle_count"] = 0
	reuse_result["empty"] = true
	return reuse_result
