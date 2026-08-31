class_name SdfStructuralFragmenter
extends RefCounted

## Localized structural connectivity pass. The damage bounds are expanded into a conservative
## working set; components reaching solid cells beyond that set are still supported, while enclosed
## face-connected components are detached. Edge/corner-only voxel contact has no supporting area,
## so it must not pin thin splinters to a wall after the surrounding material has broken away.

const SCAN_MARGIN_CELLS := 4
const MAX_SCAN_CELLS := 262144
# Fragment extraction uses the same cubic mesher as ordinary SDF bricks. A detached wall slab can
# be very wide and very thin, so feeding its longest dimension to that mesher would allocate a
# mostly-empty N^3 lattice. Keep each extraction tile bounded instead and merge the owned surfaces
# into one rigid fragment descriptor afterward.
const FRAGMENT_MESH_TILE_CELLS := 24
const FRAGMENT_SDF_PADDING_CELLS := 3
const MINIMUM_SUPPORT_RATIO := 0.035
const MAXIMUM_SUPPORT_RATIO := 0.22
const ANCHOR_NEGATIVE_X := 1 << 0
const ANCHOR_NEGATIVE_Y := 1 << 1
const ANCHOR_NEGATIVE_Z := 1 << 2
const ANCHOR_POSITIVE_X := 1 << 3
const ANCHOR_POSITIVE_Y := 1 << 4
const ANCHOR_POSITIVE_Z := 1 << 5
const ALL_ANCHOR_FACES := (1 << 6) - 1
const FACE_NEIGHBOR_OFFSETS: Array[Vector3i] = [
	Vector3i(-1, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, -1),
	Vector3i(0, 0, 1),
]
# Boundary packets predate the neighbor array and use min-X,min-Y,min-Z,max-X,max-Y,max-Z. Keep that
# stable network/native contract and explicitly map neighbor order (-X,+X,-Y,+Y,-Z,+Z) into it.
const FACE_NEIGHBOR_ANCHOR_INDICES := [0, 3, 1, 4, 2, 5]
const POSITIVE_FACE_NEIGHBOR_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, 1),
]


static func detach_components(
	field: SparseSdfVolumeData,
	changed_minimum: Vector3i,
	changed_maximum: Vector3i,
	texture: DestructionTextureDefinition
) -> Dictionary:
	if field == null or texture == null:
		return {}
	var total_started_usec := Time.get_ticks_usec()
	var logical_cells := Vector3i(
		maxi(ceili(field.size.x / field.voxel_size), 1),
		maxi(ceili(field.size.y / field.voxel_size), 1),
		maxi(ceili(field.size.z / field.voxel_size), 1)
	)
	var scan_minimum := _clamp_cell(
		changed_minimum - Vector3i.ONE * (SCAN_MARGIN_CELLS + 1),
		logical_cells
	)
	var scan_maximum := _clamp_cell(
		changed_maximum + Vector3i.ONE * SCAN_MARGIN_CELLS,
		logical_cells
	)
	var scan_size := scan_maximum - scan_minimum + Vector3i.ONE
	var scan_count := scan_size.x * scan_size.y * scan_size.z
	if scan_count <= 0 or scan_count > MAX_SCAN_CELLS:
		return {
			"scan_skipped": true,
			"scan_cells": scan_count,
			"fragments": [],
			"removed_samples": 0,
		}

	var authored_anchor_faces := clampi(
		field.structural_anchor_faces,
		0,
		ALL_ANCHOR_FACES
	)
	var boundary_anchors := _scan_boundary_anchors(
		scan_minimum,
		scan_maximum,
		logical_cells,
		authored_anchor_faces
	)
	var minimum_support_ratio := _minimum_support_ratio(texture)
	var mapping := _map_load_bearing_region(
		field,
		scan_minimum,
		scan_size,
		boundary_anchors,
		minimum_support_ratio
	)
	# A local scan edge means "unknown continuation", not an authored structural anchor. If the
	# load-bearing pass finds a narrow bond but both sides reach that edge, resolve the ambiguity
	# against the complete finite volume whenever it fits the structural budget. This is rare (only
	# after a bottleneck appears) and prevents a large slab from being pinned by an unseen ligament
	# just beyond the latest damage bounds.
	var full_scan_count := logical_cells.x * logical_cells.y * logical_cells.z
	var provisional_components: Array[Dictionary] = []
	for component_value: Variant in mapping.get("components", []):
		if component_value is Dictionary:
			provisional_components.append(component_value)
	var provisional_detached := select_detached_components(
		provisional_components,
		int(mapping.get("largest_component", -1))
	)
	var requires_global_resolution := int(mapping.get("weak_bond_count", 0)) > 0
	if (
		not requires_global_resolution
		and provisional_detached.is_empty()
		and provisional_components.size() > 1
	):
		# Load-bearing erosion may create several cores inside one genuinely connected object. Only a
		# second face-connectivity query can distinguish that healthy case from two severed pieces that
		# merely touch opposite edges of this local/unknown scan. The native path reuses its buffers.
		var face_mapping := _map_face_connected_region(
			field,
			scan_minimum,
			scan_size,
			boundary_anchors
		)
		requires_global_resolution = (
			(face_mapping.get("components", []) as Array).size() > 1
		)
	if (
		requires_global_resolution
		and provisional_detached.is_empty()
		and full_scan_count <= MAX_SCAN_CELLS
		and (scan_minimum != Vector3i.ZERO or scan_size != logical_cells)
	):
		scan_minimum = Vector3i.ZERO
		scan_size = logical_cells
		scan_count = full_scan_count
		mapping = _map_load_bearing_region(
			field,
			scan_minimum,
			scan_size,
			_full_volume_boundary_anchors(authored_anchor_faces),
			minimum_support_ratio
		)
	var mapping_usec := Time.get_ticks_usec() - total_started_usec
	var grouping_started_usec := Time.get_ticks_usec()
	var labels: PackedInt32Array = mapping.get("labels", PackedInt32Array())
	var components: Array[Dictionary] = []
	for component_value: Variant in mapping.get("components", []):
		if not component_value is Dictionary:
			continue
		var component := (component_value as Dictionary).duplicate(false)
		component["minimum"] = scan_minimum + Vector3i(component.get("minimum", Vector3i.ZERO))
		component["maximum"] = scan_minimum + Vector3i(component.get("maximum", Vector3i.ZERO))
		components.append(component)
	var largest_component := int(mapping.get("largest_component", -1))

	var candidates := select_detached_components(components, largest_component)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("cell_count", 0)) > int(right.get("cell_count", 0))
	)

	var detached_labels := PackedByteArray()
	detached_labels.resize(components.size())
	for candidate: Dictionary in candidates:
		detached_labels[int(candidate.get("id", -1))] = 1
	var cells_by_component: Dictionary[int, Array] = {}
	var all_detached_cells: Array[Vector3i] = []
	for local_index: int in range(scan_count):
		var label := labels[local_index]
		if label < 0 or detached_labels[label] == 0:
			continue
		var cell := scan_minimum + _local_from_flat(local_index, scan_size)
		all_detached_cells.append(cell)
		if not cells_by_component.has(label):
			cells_by_component[label] = []
		(cells_by_component[label] as Array).append(cell)
	var grouping_usec := Time.get_ticks_usec() - grouping_started_usec

	var fragments: Array[Dictionary] = []
	var cells_to_erase: Array[Vector3i] = []
	var fragment_mesh_failures := 0
	var physical_slots := maxi(texture.maximum_physical_fragments, 0)
	var mesh_started_usec := Time.get_ticks_usec()
	for candidate: Dictionary in candidates:
		var component_id := int(candidate.get("id", -1))
		var component_cells := cells_by_component.get(component_id, []) as Array
		var estimated_volume := float(component_cells.size()) * pow(field.voxel_size, 3.0)
		if component_cells.is_empty():
			continue
		if (
			fragments.size() >= physical_slots
			or estimated_volume < texture.minimum_fragment_volume
		):
			# These components are intentionally treated as non-physical rubble. They disappear from
			# the continuous wall field, whereas a component that qualified for physics but failed to
			# mesh must remain until a later structural pass can retry it.
			_append_component_cells(cells_to_erase, component_cells)
			continue
		var fragment := _build_fragment_mesh(
			field,
			component_cells,
			candidate.get("minimum", Vector3i.ZERO),
			candidate.get("maximum", Vector3i.ZERO)
		)
		if fragment.is_empty():
			fragment_mesh_failures += 1
			continue
		fragment["estimated_volume"] = estimated_volume
		fragment["source_component_id"] = component_id
		fragments.append(fragment)
		_append_component_cells(cells_to_erase, component_cells)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec

	var erase_started_usec := Time.get_ticks_usec()
	var removed_samples := field.erase_detached_cells(cells_to_erase)
	var erase_usec := Time.get_ticks_usec() - erase_started_usec
	return {
		"scan_skipped": false,
		"scan_cells": scan_count,
		"component_count": components.size(),
		"support_refined": bool(mapping.get("support_refined", false)),
		"weak_bond_count": int(mapping.get("weak_bond_count", 0)),
		"minimum_support_ratio": minimum_support_ratio,
		"detached_component_count": candidates.size(),
		"detached_cell_count": all_detached_cells.size(),
		"retained_detached_cell_count": all_detached_cells.size() - cells_to_erase.size(),
		"fragment_mesh_failures": fragment_mesh_failures,
		"removed_samples": removed_samples,
		"fragments": fragments,
		"mapping_usec": mapping_usec,
		"grouping_usec": grouping_usec,
		"mesh_usec": mesh_usec,
		"erase_usec": erase_usec,
		"total_usec": Time.get_ticks_usec() - total_started_usec,
	}


static func _minimum_support_ratio(texture: DestructionTextureDefinition) -> float:
	# The area required to carry a region decreases for strong/tough/ductile materials. Region load
	# itself is evaluated by the mapper from cell_count^(2/3), so scaling the object or changing voxel
	# resolution does not turn a one-cell ligament into infinite support.
	var structural_strength := clampf(
		texture.support_strength * 0.55
		+ texture.fracture_toughness * 0.35
		+ texture.ductility * 0.10,
		0.0,
		1.0
	)
	return clampf(
		lerpf(MAXIMUM_SUPPORT_RATIO, 0.055, structural_strength),
		MINIMUM_SUPPORT_RATIO,
		MAXIMUM_SUPPORT_RATIO
	)


static func _map_load_bearing_region(
	field: SparseSdfVolumeData,
	cell_minimum: Vector3i,
	cell_size: Vector3i,
	boundary_anchors: PackedByteArray,
	minimum_support_ratio: float
) -> Dictionary:
	var native_kernel := field.structural_native_kernel()
	if native_kernel != null and native_kernel.has_method(&"map_cached_load_bearing_components"):
		var cached := native_kernel.call(
			&"map_cached_load_bearing_components",
			cell_minimum,
			cell_size,
			boundary_anchors,
			minimum_support_ratio
		) as Dictionary
		if bool(cached.get("valid", false)):
			return cached
	var distances := _capture_sample_lattice(field, cell_minimum, cell_size)
	if native_kernel != null and native_kernel.has_method(&"map_load_bearing_components"):
		var captured := native_kernel.call(
			&"map_load_bearing_components",
			distances,
			cell_size,
			boundary_anchors,
			minimum_support_ratio
		) as Dictionary
		if bool(captured.get("valid", false)):
			return captured
	return _map_load_bearing_components_scripted(
		distances,
		cell_size,
		boundary_anchors,
		minimum_support_ratio
	)


static func _map_face_connected_region(
	field: SparseSdfVolumeData,
	cell_minimum: Vector3i,
	cell_size: Vector3i,
	boundary_anchors: PackedByteArray
) -> Dictionary:
	var native_kernel := field.structural_native_kernel()
	if native_kernel != null and native_kernel.has_method(&"map_cached_structural_components"):
		var cached := native_kernel.call(
			&"map_cached_structural_components",
			cell_minimum,
			cell_size,
			boundary_anchors
		) as Dictionary
		if bool(cached.get("valid", false)):
			return cached
	var distances := _capture_sample_lattice(field, cell_minimum, cell_size)
	if native_kernel != null and native_kernel.has_method(&"map_structural_components"):
		var captured := native_kernel.call(
			&"map_structural_components",
			distances,
			cell_size,
			boundary_anchors
		) as Dictionary
		if bool(captured.get("valid", false)):
			return captured
	return _map_components_scripted(distances, cell_size, boundary_anchors)


static func _scan_boundary_anchors(
	scan_minimum: Vector3i,
	scan_maximum: Vector3i,
	logical_cells: Vector3i,
	authored_anchor_faces: int
) -> PackedByteArray:
	return PackedByteArray([
		1 if scan_minimum.x > 0 or (authored_anchor_faces & ANCHOR_NEGATIVE_X) != 0 else 0,
		1 if scan_minimum.y > 0 or (authored_anchor_faces & ANCHOR_NEGATIVE_Y) != 0 else 0,
		1 if scan_minimum.z > 0 or (authored_anchor_faces & ANCHOR_NEGATIVE_Z) != 0 else 0,
		1 if scan_maximum.x < logical_cells.x - 1 or (authored_anchor_faces & ANCHOR_POSITIVE_X) != 0 else 0,
		1 if scan_maximum.y < logical_cells.y - 1 or (authored_anchor_faces & ANCHOR_POSITIVE_Y) != 0 else 0,
		1 if scan_maximum.z < logical_cells.z - 1 or (authored_anchor_faces & ANCHOR_POSITIVE_Z) != 0 else 0,
	])


static func _full_volume_boundary_anchors(authored_anchor_faces: int) -> PackedByteArray:
	return PackedByteArray([
		1 if (authored_anchor_faces & ANCHOR_NEGATIVE_X) != 0 else 0,
		1 if (authored_anchor_faces & ANCHOR_NEGATIVE_Y) != 0 else 0,
		1 if (authored_anchor_faces & ANCHOR_NEGATIVE_Z) != 0 else 0,
		1 if (authored_anchor_faces & ANCHOR_POSITIVE_X) != 0 else 0,
		1 if (authored_anchor_faces & ANCHOR_POSITIVE_Y) != 0 else 0,
		1 if (authored_anchor_faces & ANCHOR_POSITIVE_Z) != 0 else 0,
	])


static func select_detached_components(
	components: Array[Dictionary],
	largest_component: int
) -> Array[Dictionary]:
	# Real support beats size. The old unconditional "keep largest" fallback could preserve a large
	# severed slab when a smaller component in the localized scan was demonstrably connected to the
	# surrounding wall. Only use size when the scan contains no anchored component at all (normally
	# a full-volume scan whose edges coincide with the authored solid's outer boundary).
	var has_anchored_component := false
	for component: Dictionary in components:
		if bool(component.get("connects_outside", false)):
			has_anchored_component = true
			break
	var candidates: Array[Dictionary] = []
	for component: Dictionary in components:
		if bool(component.get("connects_outside", false)):
			continue
		if (
			not has_anchored_component
			and int(component.get("id", -1)) == largest_component
		):
			continue
		candidates.append(component)
	return candidates


static func _build_fragment_mesh(
	field: SparseSdfVolumeData,
	component_cells: Array,
	component_minimum: Vector3i,
	component_maximum: Vector3i,
	include_sdf_state := true
) -> Dictionary:
	var component_size := component_maximum - component_minimum + Vector3i.ONE
	if component_size.x <= 0 or component_size.y <= 0 or component_size.z <= 0:
		return {}
	var membership := PackedByteArray()
	membership.resize(component_size.x * component_size.y * component_size.z)
	for value: Variant in component_cells:
		var cell := value as Vector3i
		var local := cell - component_minimum
		membership[_flat_index(local, component_size)] = 1

	var padded_origin := component_minimum - Vector3i.ONE
	var padded_size := component_size + Vector3i.ONE * 2
	var tile_counts := Vector3i(
		ceili(float(padded_size.x) / float(FRAGMENT_MESH_TILE_CELLS)),
		ceili(float(padded_size.y) / float(FRAGMENT_MESH_TILE_CELLS)),
		ceili(float(padded_size.z) / float(FRAGMENT_MESH_TILE_CELLS))
	)
	var sample_grid_size := (
		FRAGMENT_MESH_TILE_CELLS
		+ SdfDualContouringMesher.SAMPLE_CACHE_HALO * 2
	)
	var sample_distances := PackedFloat32Array()
	var native_kernel := field.structural_native_kernel()
	var has_native_fragment_capture := (
		native_kernel != null
		and native_kernel.has_method(&"capture_cached_fragment_tile")
	)
	if not has_native_fragment_capture:
		sample_distances.resize(sample_grid_size * sample_grid_size * sample_grid_size)
	var reusable_snapshot: Dictionary = {}
	var tile_results: Array[Dictionary] = []
	var total_vertices := 0
	var total_indices := 0
	for tile_z: int in range(tile_counts.z):
		for tile_y: int in range(tile_counts.y):
			for tile_x: int in range(tile_counts.x):
				var tile_coordinate := Vector3i(tile_x, tile_y, tile_z)
				var tile_origin := (
					padded_origin + tile_coordinate * FRAGMENT_MESH_TILE_CELLS
				)
				var snapshot: Dictionary
				if has_native_fragment_capture:
					reusable_snapshot = native_kernel.call(
						&"capture_cached_fragment_tile",
						tile_origin,
						FRAGMENT_MESH_TILE_CELLS,
						component_minimum,
						component_size,
						membership,
						reusable_snapshot
					) as Dictionary
					snapshot = reusable_snapshot
				else:
					var write_index := 0
					for sample_z: int in range(
						-SdfDualContouringMesher.SAMPLE_CACHE_HALO,
						FRAGMENT_MESH_TILE_CELLS + SdfDualContouringMesher.SAMPLE_CACHE_HALO
					):
						for sample_y: int in range(
							-SdfDualContouringMesher.SAMPLE_CACHE_HALO,
							FRAGMENT_MESH_TILE_CELLS + SdfDualContouringMesher.SAMPLE_CACHE_HALO
						):
							for sample_x: int in range(
								-SdfDualContouringMesher.SAMPLE_CACHE_HALO,
								FRAGMENT_MESH_TILE_CELLS + SdfDualContouringMesher.SAMPLE_CACHE_HALO
							):
								var sample := tile_origin + Vector3i(sample_x, sample_y, sample_z)
								sample_distances[write_index] = (
									field.distance_at_global_sample(sample)
									if _sample_touches_component(
										sample,
										component_minimum,
										component_size,
										membership
									)
									else field.narrow_band
								)
								write_index += 1
					snapshot = {
						"chunk_coordinate": tile_coordinate,
						"cells": FRAGMENT_MESH_TILE_CELLS,
						"voxel_size": field.voxel_size,
						"field_origin": -field.half_extents,
						"field_half_extents": field.half_extents,
						"chunk_global_cell_origin": tile_origin,
						"sample_grid_size": sample_grid_size,
						"sample_distances": sample_distances,
						"source_signature": 0,
					}
				var result := (
					native_kernel.call(&"build_chunk_snapshot", snapshot) as Dictionary
					if native_kernel != null and native_kernel.has_method(&"build_chunk_snapshot")
					else SdfDualContouringMesher.build_chunk_snapshot(snapshot)
				)
				SdfDualContouringMesher.finalize_box_shell(result, snapshot)
				if bool(result.get("empty", true)):
					continue
				var tile_vertices: PackedVector3Array = result.get(
					"vertices", PackedVector3Array()
				)
				var tile_normals: PackedVector3Array = result.get(
					"normals", PackedVector3Array()
				)
				var tile_indices: PackedInt32Array = result.get(
					"indices", PackedInt32Array()
				)
				if (
					tile_vertices.is_empty()
					or tile_normals.size() != tile_vertices.size()
					or tile_indices.is_empty()
				):
					continue
				tile_results.append(result)
				total_vertices += tile_vertices.size()
				total_indices += tile_indices.size()

	if total_vertices <= 0 or total_indices <= 0:
		return {}
	# Merge once into exact-size packed arrays. Tiles partition primal-edge ownership, so adjoining
	# tiles meet at identical positions but never duplicate a triangle. Keeping their vertices split
	# is intentional: it avoids a global weld/remap allocation and does not affect the convex body.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var shell_masks := PackedByteArray()
	var indices := PackedInt32Array()
	vertices.resize(total_vertices)
	normals.resize(total_vertices)
	shell_masks.resize(total_vertices)
	indices.resize(total_indices)
	var vertex_write := 0
	var index_write := 0
	for result: Dictionary in tile_results:
		var tile_vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
		var tile_normals: PackedVector3Array = result.get("normals", PackedVector3Array())
		var tile_shell_masks: PackedByteArray = result.get("shell_masks", PackedByteArray())
		var tile_indices: PackedInt32Array = result.get("indices", PackedInt32Array())
		for local_index: int in range(tile_vertices.size()):
			vertices[vertex_write + local_index] = tile_vertices[local_index]
			normals[vertex_write + local_index] = tile_normals[local_index]
			shell_masks[vertex_write + local_index] = (
				tile_shell_masks[local_index]
				if tile_shell_masks.size() == tile_vertices.size()
				else 0
			)
		for local_index: int in range(tile_indices.size()):
			indices[index_write + local_index] = tile_indices[local_index] + vertex_write
		vertex_write += tile_vertices.size()
		index_write += tile_indices.size()
	var combined_result := {
		"vertices": vertices,
		"normals": normals,
		"shell_masks": shell_masks,
		"indices": indices,
		"triangle_count": indices.size() / 3,
		"empty": indices.is_empty(),
	}
	SdfDualContouringMesher.split_box_reference_surface_classes(combined_result)
	vertices = combined_result["vertices"] as PackedVector3Array
	normals = combined_result["normals"] as PackedVector3Array
	indices = combined_result["indices"] as PackedInt32Array
	var surface_classes := combined_result.get(
		"surface_classes", PackedByteArray()
	) as PackedByteArray
	# Keep the fragment body on a stable, grid-aligned crop. Re-centering from each regenerated mesh
	# would shift its rigid transform after every cut and make recursive fragment transforms drift.
	var field_origin_sample := component_minimum - Vector3i.ONE * FRAGMENT_SDF_PADDING_CELLS
	var field_cells := component_size + Vector3i.ONE * (FRAGMENT_SDF_PADDING_CELLS * 2)
	var center := (
		field.global_sample_position(field_origin_sample)
		+ Vector3(field_cells) * field.voxel_size * 0.5
	)
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index: int in range(vertices.size()):
		colors[index] = (
			Color.WHITE
			if index < surface_classes.size() and surface_classes[index] == 0
			else Color.BLACK
		)
		vertices[index] -= center
	var descriptor := {
		"local_center": center,
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"surface_mask": colors,
		"mesh_tile_count": tile_results.size(),
	}
	if include_sdf_state:
		var dense_sample_size := field_cells + Vector3i.ONE
		var fragment_distances := PackedFloat32Array()
		fragment_distances.resize(
			dense_sample_size.x * dense_sample_size.y * dense_sample_size.z
		)
		var distance_write := 0
		for sample_z: int in range(dense_sample_size.z):
			for sample_y: int in range(dense_sample_size.y):
				for sample_x: int in range(dense_sample_size.x):
					var source_sample := field_origin_sample + Vector3i(
						sample_x, sample_y, sample_z
					)
					fragment_distances[distance_write] = (
						field.distance_at_global_sample(source_sample)
						if _sample_touches_component(
							source_sample,
							component_minimum,
							component_size,
							membership
						)
						else field.narrow_band
					)
					distance_write += 1
		descriptor["sdf_state"] = {
			"size": Vector3(field_cells) * field.voxel_size,
			"voxel_size": field.voxel_size,
			"brick_cells": field.brick_cells,
			"material_index": field.material_index,
			"narrow_band_voxels": field.narrow_band / field.voxel_size,
			"dense_sample_size": dense_sample_size,
			"distances": fragment_distances,
		}
	return descriptor


static func build_complete_field_mesh(field: SparseSdfVolumeData) -> Dictionary:
	## Re-extract the material still owned by an already detached fragment. The fixed fragment field
	## remains centered on its rigid body; only child descriptors receive their own cropped fields.
	if field == null:
		return {}
	var logical_cells := Vector3i(
		maxi(ceili(field.size.x / field.voxel_size), 1),
		maxi(ceili(field.size.y / field.voxel_size), 1),
		maxi(ceili(field.size.z / field.voxel_size), 1)
	)
	var cells: Array[Vector3i] = []
	var minimum := logical_cells - Vector3i.ONE
	var maximum := Vector3i.ZERO
	for z: int in range(logical_cells.z):
		for y: int in range(logical_cells.y):
			for x: int in range(logical_cells.x):
				var cell := Vector3i(x, y, z)
				if not _cell_contains_matter(field, cell):
					continue
				cells.append(cell)
				minimum = Vector3i(
					mini(minimum.x, x), mini(minimum.y, y), mini(minimum.z, z)
				)
				maximum = Vector3i(
					maxi(maximum.x, x), maxi(maximum.y, y), maxi(maximum.z, z)
				)
	if cells.is_empty():
		return {}
	var descriptor := _build_fragment_mesh(field, cells, minimum, maximum, false)
	if descriptor.is_empty():
		return {}
	var offset: Vector3 = descriptor.get("local_center", Vector3.ZERO)
	var vertices: PackedVector3Array = descriptor.get("vertices", PackedVector3Array())
	for index: int in range(vertices.size()):
		vertices[index] += offset
	descriptor["vertices"] = vertices
	descriptor["local_center"] = Vector3.ZERO
	descriptor["estimated_volume"] = float(cells.size()) * pow(field.voxel_size, 3.0)
	# The parent keeps its existing fixed field; this re-cropped copy is only needed when it becomes
	# a new child through detach_components().
	descriptor.erase("sdf_state")
	return descriptor


static func _cell_contains_matter(field: SparseSdfVolumeData, cell: Vector3i) -> bool:
	for offset_z: int in range(2):
		for offset_y: int in range(2):
			for offset_x: int in range(2):
				if field.distance_at_global_sample(
					cell + Vector3i(offset_x, offset_y, offset_z)
				) < 0.0:
					return true
	return false


static func _append_component_cells(target: Array[Vector3i], source: Array) -> void:
	for value: Variant in source:
		target.append(value as Vector3i)


static func _sample_touches_component(
	sample: Vector3i,
	component_minimum: Vector3i,
	component_size: Vector3i,
	membership: PackedByteArray
) -> bool:
	for offset_z: int in range(0, 2):
		for offset_y: int in range(0, 2):
			for offset_x: int in range(0, 2):
				var local_cell := sample - Vector3i(offset_x, offset_y, offset_z) - component_minimum
				if (
					_local_is_inside(local_cell, component_size)
					and membership[_flat_index(local_cell, component_size)] != 0
				):
					return true
	return false


static func _capture_sample_lattice(
	field: SparseSdfVolumeData,
	scan_minimum: Vector3i,
	scan_size: Vector3i
) -> PackedFloat32Array:
	var sample_size := scan_size + Vector3i.ONE
	var distances := PackedFloat32Array()
	distances.resize(sample_size.x * sample_size.y * sample_size.z)
	var write_index := 0
	for sample_z: int in range(sample_size.z):
		for sample_y: int in range(sample_size.y):
			for sample_x: int in range(sample_size.x):
				distances[write_index] = field.distance_at_global_sample(
					scan_minimum + Vector3i(sample_x, sample_y, sample_z)
				)
				write_index += 1
	return distances


static func _map_components_scripted(
	distances: PackedFloat32Array,
	scan_size: Vector3i,
	boundary_anchors: PackedByteArray
) -> Dictionary:
	var solid := _solid_cells_from_distances(distances, scan_size)
	if solid.is_empty():
		return {}
	return _map_face_components_from_solid(solid, scan_size, boundary_anchors)


static func _map_load_bearing_components_scripted(
	distances: PackedFloat32Array,
	scan_size: Vector3i,
	boundary_anchors: PackedByteArray,
	minimum_support_ratio: float
) -> Dictionary:
	var solid := _solid_cells_from_distances(distances, scan_size)
	if solid.is_empty():
		return {}
	return _map_load_bearing_from_solid(
		solid,
		scan_size,
		boundary_anchors,
		minimum_support_ratio
	)


static func _solid_cells_from_distances(
	distances: PackedFloat32Array,
	scan_size: Vector3i
) -> PackedByteArray:
	var sample_size := scan_size + Vector3i.ONE
	if distances.size() != sample_size.x * sample_size.y * sample_size.z:
		return PackedByteArray()
	var solid := PackedByteArray()
	solid.resize(scan_size.x * scan_size.y * scan_size.z)
	solid.fill(0)
	for cell_z: int in range(scan_size.z):
		for cell_y: int in range(scan_size.y):
			for cell_x: int in range(scan_size.x):
				var sample_index := cell_x + sample_size.x * (
					cell_y + sample_size.y * cell_z
				)
				var next_y := sample_index + sample_size.x
				var next_z := sample_index + sample_size.x * sample_size.y
				# The contourer emits a dual vertex whenever a cell has at least one negative and one
				# positive corner. Classifying structure by the eight-corner average allowed a thin
				# negative sheet to be visible while being invisible to connectivity. Treat any matter
				# sample as occupied. Support traversal below still requires a shared cell face.
				var minimum_distance := minf(
					distances[sample_index],
					minf(
						distances[sample_index + 1],
						minf(
							distances[next_y],
							minf(
								distances[next_y + 1],
								minf(
									distances[next_z],
									minf(
										distances[next_z + 1],
										minf(
											distances[next_z + sample_size.x],
											distances[next_z + sample_size.x + 1]
										)
									)
								)
							)
						)
					)
				)
				if minimum_distance < 0.0:
					solid[cell_x + scan_size.x * (cell_y + scan_size.y * cell_z)] = 1
	return solid


static func _map_face_components_from_solid(
	solid: PackedByteArray,
	scan_size: Vector3i,
	boundary_anchors: PackedByteArray
) -> Dictionary:
	var scan_count := scan_size.x * scan_size.y * scan_size.z
	var labels := PackedInt32Array()
	labels.resize(scan_count)
	labels.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(scan_count)
	var components: Array[Dictionary] = []
	var largest_component := -1
	var largest_count := 0
	for start_index: int in range(scan_count):
		if solid[start_index] == 0 or labels[start_index] >= 0:
			continue
		var component_id := components.size()
		var head := 0
		var tail := 1
		queue[0] = start_index
		labels[start_index] = component_id
		var cell_count := 0
		var connects_outside := false
		var bounds_minimum := scan_size - Vector3i.ONE
		var bounds_maximum := Vector3i.ZERO
		while head < tail:
			var current_index := queue[head]
			head += 1
			var current_local := _local_from_flat(current_index, scan_size)
			connects_outside = connects_outside or (
				(current_local.x == 0 and boundary_anchors[0] != 0)
				or (current_local.y == 0 and boundary_anchors[1] != 0)
				or (current_local.z == 0 and boundary_anchors[2] != 0)
				or (current_local.x == scan_size.x - 1 and boundary_anchors[3] != 0)
				or (current_local.y == scan_size.y - 1 and boundary_anchors[4] != 0)
				or (current_local.z == scan_size.z - 1 and boundary_anchors[5] != 0)
			)
			cell_count += 1
			bounds_minimum = Vector3i(
				mini(bounds_minimum.x, current_local.x),
				mini(bounds_minimum.y, current_local.y),
				mini(bounds_minimum.z, current_local.z)
			)
			bounds_maximum = Vector3i(
				maxi(bounds_maximum.x, current_local.x),
				maxi(bounds_maximum.y, current_local.y),
				maxi(bounds_maximum.z, current_local.z)
			)
			for offset: Vector3i in FACE_NEIGHBOR_OFFSETS:
				var neighbor_local := current_local + offset
				if not _local_is_inside(neighbor_local, scan_size):
					continue
				var neighbor_index := _flat_index(neighbor_local, scan_size)
				if solid[neighbor_index] == 0 or labels[neighbor_index] >= 0:
					continue
				labels[neighbor_index] = component_id
				queue[tail] = neighbor_index
				tail += 1
		components.append({
			"id": component_id,
			"cell_count": cell_count,
			"connects_outside": connects_outside,
			"minimum": bounds_minimum,
			"maximum": bounds_maximum,
		})
		if cell_count > largest_count:
			largest_count = cell_count
			largest_component = component_id
	return {
		"valid": true,
		"labels": labels,
		"components": components,
		"largest_component": largest_component,
	}


static func _map_load_bearing_from_solid(
	solid: PackedByteArray,
	scan_size: Vector3i,
	boundary_anchors: PackedByteArray,
	minimum_support_ratio: float
) -> Dictionary:
	var scan_count := scan_size.x * scan_size.y * scan_size.z
	if solid.size() != scan_count or boundary_anchors.size() < 6:
		return {}
	# A one-cell morphological core pass turns narrow geometry into explicit bonds without deleting
	# it. Ordinary walls retain a core even when they are thin in world units; a one/two-voxel neck
	# does not. The original occupancy is then assigned back to the nearest core, so fragment meshes
	# still contain the complete surface rather than the eroded diagnostic shape.
	var core := PackedByteArray()
	core.resize(scan_count)
	for index: int in range(scan_count):
		if solid[index] == 0:
			continue
		var local := _local_from_flat(index, scan_size)
		var is_core := true
		for offset_index: int in range(FACE_NEIGHBOR_OFFSETS.size()):
			var neighbor := local + FACE_NEIGHBOR_OFFSETS[offset_index]
			if _local_is_inside(neighbor, scan_size):
				if solid[_flat_index(neighbor, scan_size)] == 0:
					is_core = false
					break
			elif boundary_anchors[FACE_NEIGHBOR_ANCHOR_INDICES[offset_index]] == 0:
				is_core = false
				break
		core[index] = 1 if is_core else 0

	var core_labels := PackedInt32Array()
	core_labels.resize(scan_count)
	core_labels.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(scan_count)
	var core_component_count := 0
	for start_index: int in range(scan_count):
		if core[start_index] == 0 or core_labels[start_index] >= 0:
			continue
		var head := 0
		var tail := 1
		queue[0] = start_index
		core_labels[start_index] = core_component_count
		while head < tail:
			var current_index := queue[head]
			head += 1
			var current := _local_from_flat(current_index, scan_size)
			for offset: Vector3i in FACE_NEIGHBOR_OFFSETS:
				var neighbor := current + offset
				if not _local_is_inside(neighbor, scan_size):
					continue
				var neighbor_index := _flat_index(neighbor, scan_size)
				if core[neighbor_index] == 0 or core_labels[neighbor_index] >= 0:
					continue
				core_labels[neighbor_index] = core_component_count
				queue[tail] = neighbor_index
				tail += 1
		core_component_count += 1
	if core_component_count <= 1:
		var ordinary := _map_face_components_from_solid(solid, scan_size, boundary_anchors)
		ordinary["support_refined"] = false
		ordinary["weak_bond_count"] = 0
		ordinary["core_component_count"] = core_component_count
		return ordinary

	# Multi-source flood assigns the un-eroded surface shell and ligament cells to their nearest core.
	# A deterministic flat-index seed order gives native/fallback/network parity at equidistant cells.
	var labels := core_labels.duplicate()
	var head := 0
	var tail := 0
	for index: int in range(scan_count):
		if core[index] != 0:
			queue[tail] = index
			tail += 1
	while head < tail:
		var current_index := queue[head]
		head += 1
		var current := _local_from_flat(current_index, scan_size)
		for offset: Vector3i in FACE_NEIGHBOR_OFFSETS:
			var neighbor := current + offset
			if not _local_is_inside(neighbor, scan_size):
				continue
			var neighbor_index := _flat_index(neighbor, scan_size)
			if solid[neighbor_index] == 0 or labels[neighbor_index] >= 0:
				continue
			labels[neighbor_index] = labels[current_index]
			queue[tail] = neighbor_index
			tail += 1

	# Disconnected pieces thinner than the erosion diameter have no core. They remain real regions and
	# are detached by the same support pass instead of disappearing from structural accounting.
	var region_count := core_component_count
	for start_index: int in range(scan_count):
		if solid[start_index] == 0 or labels[start_index] >= 0:
			continue
		head = 0
		tail = 1
		queue[0] = start_index
		labels[start_index] = region_count
		while head < tail:
			var current_index := queue[head]
			head += 1
			var current := _local_from_flat(current_index, scan_size)
			for offset: Vector3i in FACE_NEIGHBOR_OFFSETS:
				var neighbor := current + offset
				if not _local_is_inside(neighbor, scan_size):
					continue
				var neighbor_index := _flat_index(neighbor, scan_size)
				if solid[neighbor_index] == 0 or labels[neighbor_index] >= 0:
					continue
				labels[neighbor_index] = region_count
				queue[tail] = neighbor_index
				tail += 1
		region_count += 1

	var cell_counts := PackedInt32Array()
	cell_counts.resize(region_count)
	var directly_supported := PackedByteArray()
	directly_supported.resize(region_count)
	var minimums: Array[Vector3i] = []
	var maximums: Array[Vector3i] = []
	var adjacency: Array[Dictionary] = []
	for _region: int in range(region_count):
		minimums.append(scan_size - Vector3i.ONE)
		maximums.append(Vector3i.ZERO)
		adjacency.append({})
	for index: int in range(scan_count):
		var label := labels[index]
		if label < 0:
			continue
		var local := _local_from_flat(index, scan_size)
		cell_counts[label] += 1
		minimums[label] = Vector3i(
			mini(minimums[label].x, local.x),
			mini(minimums[label].y, local.y),
			mini(minimums[label].z, local.z)
		)
		maximums[label] = Vector3i(
			maxi(maximums[label].x, local.x),
			maxi(maximums[label].y, local.y),
			maxi(maximums[label].z, local.z)
		)
		if (
			(local.x == 0 and boundary_anchors[0] != 0)
			or (local.y == 0 and boundary_anchors[1] != 0)
			or (local.z == 0 and boundary_anchors[2] != 0)
			or (local.x == scan_size.x - 1 and boundary_anchors[3] != 0)
			or (local.y == scan_size.y - 1 and boundary_anchors[4] != 0)
			or (local.z == scan_size.z - 1 and boundary_anchors[5] != 0)
		):
			directly_supported[label] = 1
		for offset: Vector3i in POSITIVE_FACE_NEIGHBOR_OFFSETS:
			var neighbor := local + offset
			if not _local_is_inside(neighbor, scan_size):
				continue
			var neighbor_label := labels[_flat_index(neighbor, scan_size)]
			if neighbor_label < 0 or neighbor_label == label:
				continue
			adjacency[label][neighbor_label] = int(adjacency[label].get(neighbor_label, 0)) + 1
			adjacency[neighbor_label][label] = int(adjacency[neighbor_label].get(label, 0)) + 1

	var largest_component := -1
	var largest_count := 0
	var has_direct_support := false
	var required_faces := PackedInt32Array()
	required_faces.resize(region_count)
	var support_ratio_millionths := clampi(
		roundi(minimum_support_ratio * 1000000.0),
		1,
		1000000
	)
	for region_id: int in range(region_count):
		if cell_counts[region_id] > largest_count:
			largest_count = cell_counts[region_id]
			largest_component = region_id
		has_direct_support = has_direct_support or directly_supported[region_id] != 0
		var characteristic_area := _characteristic_cross_section_cells(cell_counts[region_id])
		required_faces[region_id] = maxi(1, (
			characteristic_area * support_ratio_millionths + 999999
		) / 1000000)
	if not has_direct_support and largest_component >= 0:
		directly_supported[largest_component] = 1

	var supported := directly_supported.duplicate()
	var support_budget := PackedInt32Array()
	support_budget.resize(region_count)
	for region_id: int in range(region_count):
		if supported[region_id] != 0:
			support_budget[region_id] = 0x3fffffff
	for _iteration: int in range(region_count):
		var progressed := false
		for region_id: int in range(region_count):
			if supported[region_id] != 0:
				continue
			var available_faces := 0
			for neighbor_value: Variant in adjacency[region_id]:
				var neighbor_id := int(neighbor_value)
				if supported[neighbor_id] == 0:
					continue
				available_faces += mini(
					int(adjacency[region_id][neighbor_id]),
					support_budget[neighbor_id]
				)
			if available_faces < required_faces[region_id]:
				continue
			supported[region_id] = 1
			support_budget[region_id] = maxi(
				available_faces - required_faces[region_id],
				0
			)
			progressed = true
		if not progressed:
			break

	var weak_bond_count := 0
	for region_id: int in range(region_count):
		for neighbor_value: Variant in adjacency[region_id]:
			var neighbor_id := int(neighbor_value)
			if neighbor_id <= region_id:
				continue
			if int(adjacency[region_id][neighbor_id]) < mini(
				required_faces[region_id],
				required_faces[neighbor_id]
			):
				weak_bond_count += 1

	var components: Array[Dictionary] = []
	for region_id: int in range(region_count):
		components.append({
			"id": region_id,
			"cell_count": cell_counts[region_id],
			"connects_outside": supported[region_id] != 0,
			"directly_anchored": directly_supported[region_id] != 0,
			"required_support_faces": required_faces[region_id],
			"minimum": minimums[region_id],
			"maximum": maximums[region_id],
		})
	return {
		"valid": true,
		"labels": labels,
		"components": components,
		"largest_component": largest_component,
		"support_refined": true,
		"weak_bond_count": weak_bond_count,
		"core_component_count": core_component_count,
	}


static func _characteristic_cross_section_cells(cell_count: int) -> int:
	# Exact integer ceil(cell_count^(2/3)). Avoiding platform libm at this authoritative threshold
	# keeps Linux/Windows and native/fallback clients on the same side of a bond decision.
	var target := cell_count * cell_count
	var low := 0
	var high := maxi(cell_count, 1)
	while low < high:
		var middle := (low + high) / 2
		if middle * middle * middle >= target:
			high = middle
		else:
			low = middle + 1
	return low


static func _clamp_cell(cell: Vector3i, logical_cells: Vector3i) -> Vector3i:
	return Vector3i(
		clampi(cell.x, 0, logical_cells.x - 1),
		clampi(cell.y, 0, logical_cells.y - 1),
		clampi(cell.z, 0, logical_cells.z - 1)
	)


static func _cell_is_inside(cell: Vector3i, logical_cells: Vector3i) -> bool:
	return _local_is_inside(cell, logical_cells)


static func _local_is_inside(local: Vector3i, size: Vector3i) -> bool:
	return (
		local.x >= 0 and local.y >= 0 and local.z >= 0
		and local.x < size.x and local.y < size.y and local.z < size.z
	)


static func _flat_index(local: Vector3i, size: Vector3i) -> int:
	return local.x + size.x * (local.y + size.y * local.z)


static func _local_from_flat(index: int, size: Vector3i) -> Vector3i:
	var layer := size.x * size.y
	var z := index / layer
	var remainder := index - z * layer
	var y := remainder / size.x
	return Vector3i(remainder - y * size.x, y, z)
