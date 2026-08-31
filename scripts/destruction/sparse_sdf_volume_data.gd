class_name SparseSdfVolumeData
extends RefCounted

## Sparse copy-on-first-edit SDF state for one finite destructible volume. The immutable base is an
## analytic box in the first vertical slice; imported-mesh bake providers can implement the same
## global-sample contract later without changing damage, meshing, replication, or collision code.

const MIN_VOXEL_SIZE := 0.005
const MAX_BRICK_CELLS := 48
const MIN_BRICK_CELLS := 4
const MAX_CRACK_OPERATIONS := 12
const MAX_DAMAGE_OPERATIONS := MAX_CRACK_OPERATIONS + 3
const OPERATION_SPHERE := 0
const OPERATION_CAPSULE := 1
const OPERATION_TAPERED_CAPSULE := 2
const MAX_CACHED_NOISE_LATTICE_VALUES := 8192

var size := Vector3.ONE
var half_extents := Vector3.ONE * 0.5
var voxel_size := 0.05
var brick_cells := 16
var brick_extent := 0.8
var narrow_band := 0.2
var brick_counts := Vector3i.ONE
var total_cells := Vector3i.ONE
var material_index := 1
var revision := 0
var prefer_native_backend := true

var _bricks: Dictionary[Vector3i, SparseSdfBrick] = {}
var _operation_count := 0
var _operation_kinds := PackedByteArray()
var _operation_starts := PackedVector3Array()
var _operation_ends := PackedVector3Array()
var _operation_first_radii := PackedFloat32Array()
var _operation_second_radii := PackedFloat32Array()
var _operation_bounds: Array[AABB] = []
var _operation_combined_bounds := AABB()
var _operation_maximum_radius := 0.0
var _changed_chunk_stamps := PackedInt32Array()
var _ring_chunk_stamps := PackedInt32Array()
var _changed_chunks_buffer: Array[Vector3i] = []
var _change_collection_stamp := 0
var _ring_collection_stamp := 0
var _last_change_has_sample_bounds := false
var _last_changed_sample_minimum := Vector3i.ZERO
var _last_changed_sample_maximum := Vector3i.ZERO
var _last_accumulated_changed_samples := 0
var _last_accumulated_peak_damage := 0
var _noise_lattice_values := PackedFloat32Array()
var _noise_lattice_origin := Vector3i.ZERO
var _noise_lattice_size := Vector3i.ZERO
var _noise_lattice_frequency := 1.0
var _noise_lattice_valid := false
var _noise_lattice_growth_count := 0
var _native_kernel: Object
var _native_mutation_request: Dictionary = {}
var _native_brick_request: Dictionary = {}
var _fragment_scan_regions: Array[Dictionary] = []
## Structural attachment faces in local volume space. Standing volumes are grounded on -Y by
## default; authored ceiling/side-mounted volumes can replace this mask through DestructibleVolume3D.
var structural_anchor_faces := 1 << 1


func configure(
	new_size: Vector3,
	new_voxel_size: float,
	new_brick_cells: int,
	new_material_index: int,
	narrow_band_voxels := 4.0
) -> SparseSdfVolumeData:
	size = Vector3(
		maxf(absf(new_size.x), MIN_VOXEL_SIZE),
		maxf(absf(new_size.y), MIN_VOXEL_SIZE),
		maxf(absf(new_size.z), MIN_VOXEL_SIZE)
	)
	half_extents = size * 0.5
	voxel_size = maxf(new_voxel_size, MIN_VOXEL_SIZE)
	brick_cells = clampi(new_brick_cells, MIN_BRICK_CELLS, MAX_BRICK_CELLS)
	brick_extent = voxel_size * float(brick_cells)
	narrow_band = maxf(voxel_size * maxf(narrow_band_voxels, 2.0), voxel_size * 2.0)
	brick_counts = Vector3i(
		maxi(ceili(size.x / brick_extent), 1),
		maxi(ceili(size.y / brick_extent), 1),
		maxi(ceili(size.z / brick_extent), 1)
	)
	total_cells = brick_counts * brick_cells
	material_index = clampi(new_material_index, 1, 255)
	revision = 0
	_bricks.clear()
	_initialize_operation_buffer()
	_changed_chunk_stamps.resize(brick_counts.x * brick_counts.y * brick_counts.z)
	_changed_chunk_stamps.fill(0)
	_ring_chunk_stamps.resize(_changed_chunk_stamps.size())
	_ring_chunk_stamps.fill(0)
	_changed_chunks_buffer.clear()
	_change_collection_stamp = 0
	_ring_collection_stamp = 0
	_noise_lattice_values.resize(0)
	_noise_lattice_valid = false
	_noise_lattice_growth_count = 0
	_fragment_scan_regions.clear()
	_native_kernel = (
		SdfDualContouringMesher.create_native_kernel()
		if prefer_native_backend
		else null
	)
	_synchronize_native_dense_field()
	return self


func initialize_from_dense_samples(
	dense_sample_size: Vector3i,
	distances: PackedFloat32Array
) -> bool:
	## Replace the analytic base with a complete, cropped sample field. Detached fragments use this
	## path so an extracted island retains the exact SDF that produced its mesh and can be cut again.
	## Every storage brick is materialized, including the positive padding outside the logical crop;
	## native and scripted mutation therefore never fall back to the original analytic box.
	if (
		dense_sample_size.x < 2
		or dense_sample_size.y < 2
		or dense_sample_size.z < 2
		or distances.size()
		!= dense_sample_size.x * dense_sample_size.y * dense_sample_size.z
	):
		return false
	_bricks.clear()
	var samples_per_axis := brick_cells + 1
	var brick_values := PackedFloat32Array()
	brick_values.resize(samples_per_axis * samples_per_axis * samples_per_axis)
	for brick_z: int in range(brick_counts.z):
		for brick_y: int in range(brick_counts.y):
			for brick_x: int in range(brick_counts.x):
				var coordinate := Vector3i(brick_x, brick_y, brick_z)
				var global_origin := coordinate * brick_cells
				var write_index := 0
				for sample_z: int in range(samples_per_axis):
					var global_z := global_origin.z + sample_z
					for sample_y: int in range(samples_per_axis):
						var global_y := global_origin.y + sample_y
						for sample_x: int in range(samples_per_axis):
							var global_x := global_origin.x + sample_x
							brick_values[write_index] = (
								distances[global_x + dense_sample_size.x * (
									global_y + dense_sample_size.y * global_z
								)]
								if global_x < dense_sample_size.x
								and global_y < dense_sample_size.y
								and global_z < dense_sample_size.z
								else narrow_band
							)
							write_index += 1
				var brick := SparseSdfBrick.new().configure(
					coordinate,
					brick_cells,
					voxel_size,
					narrow_band,
					material_index
				)
				brick.initialize_from_distances(brick_values)
				_bricks[coordinate] = brick
	revision = 0
	_fragment_scan_regions.clear()
	structural_anchor_faces = 0
	_synchronize_native_dense_field()
	return true


func bounds() -> AABB:
	return AABB(-half_extents, size)


func structural_native_kernel() -> Object:
	if prefer_native_backend and _native_kernel != null and is_instance_valid(_native_kernel):
		return _native_kernel
	return null


func base_distance(local_position: Vector3) -> float:
	return SdfMath.box(local_position, half_extents)


func sample_distance(local_position: Vector3) -> float:
	var grid_position := (local_position + half_extents) / voxel_size
	var minimum := Vector3i(floori(grid_position.x), floori(grid_position.y), floori(grid_position.z))
	var fraction := grid_position - Vector3(minimum)
	var d000 := distance_at_global_sample(minimum)
	var d100 := distance_at_global_sample(minimum + Vector3i.RIGHT)
	var d010 := distance_at_global_sample(minimum + Vector3i.UP)
	var d110 := distance_at_global_sample(minimum + Vector3i(1, 1, 0))
	var d001 := distance_at_global_sample(minimum + Vector3i(0, 0, 1))
	var d101 := distance_at_global_sample(minimum + Vector3i(1, 0, 1))
	var d011 := distance_at_global_sample(minimum + Vector3i(0, 1, 1))
	var d111 := distance_at_global_sample(minimum + Vector3i.ONE)
	var d00 := lerpf(d000, d100, fraction.x)
	var d10 := lerpf(d010, d110, fraction.x)
	var d01 := lerpf(d001, d101, fraction.x)
	var d11 := lerpf(d011, d111, fraction.x)
	return lerpf(lerpf(d00, d10, fraction.y), lerpf(d01, d11, fraction.y), fraction.z)


func sample_gradient(local_position: Vector3) -> Vector3:
	var epsilon := voxel_size * 0.5
	var gradient := Vector3(
		sample_distance(local_position + Vector3(epsilon, 0.0, 0.0))
			- sample_distance(local_position - Vector3(epsilon, 0.0, 0.0)),
		sample_distance(local_position + Vector3(0.0, epsilon, 0.0))
			- sample_distance(local_position - Vector3(0.0, epsilon, 0.0)),
		sample_distance(local_position + Vector3(0.0, 0.0, epsilon))
			- sample_distance(local_position - Vector3(0.0, 0.0, epsilon))
	)
	return gradient.normalized() if gradient.length_squared() > 0.000001 else Vector3.UP


func distance_at_global_sample(sample_coordinate: Vector3i) -> float:
	if not _global_sample_is_inside_storage(sample_coordinate):
		return base_distance(global_sample_position(sample_coordinate))
	var brick_coordinate := brick_for_global_sample(sample_coordinate)
	var brick := _bricks.get(brick_coordinate) as SparseSdfBrick
	if brick == null:
		return base_distance(global_sample_position(sample_coordinate))
	var local_sample := sample_coordinate - brick_coordinate * brick_cells
	return brick.get_distance(local_sample.x, local_sample.y, local_sample.z)


func global_sample_position(sample_coordinate: Vector3i) -> Vector3:
	return -half_extents + Vector3(sample_coordinate) * voxel_size


func brick_for_global_sample(sample_coordinate: Vector3i) -> Vector3i:
	return Vector3i(
		clampi(floori(float(sample_coordinate.x) / float(brick_cells)), 0, brick_counts.x - 1),
		clampi(floori(float(sample_coordinate.y) / float(brick_cells)), 0, brick_counts.y - 1),
		clampi(floori(float(sample_coordinate.z) / float(brick_cells)), 0, brick_counts.z - 1)
	)


func brick_origin(brick_coordinate: Vector3i) -> Vector3:
	return -half_extents + Vector3(brick_coordinate * brick_cells) * voxel_size


func brick_is_valid(brick_coordinate: Vector3i) -> bool:
	return (
		brick_coordinate.x >= 0
		and brick_coordinate.y >= 0
		and brick_coordinate.z >= 0
		and brick_coordinate.x < brick_counts.x
		and brick_coordinate.y < brick_counts.y
		and brick_coordinate.z < brick_counts.z
	)


func chunk_sample_revision_signature(chunk_coordinate: Vector3i) -> int:
	# The mesher samples a two-cell halo, which can cross at most one neighboring brick. Hashing
	# those revisions lets worker results survive unrelated edits without ever committing stale
	# geometry beside a newer cut.
	var value := 2166136261
	for z: int in range(-1, 2):
		for y: int in range(-1, 2):
			for x: int in range(-1, 2):
				var coordinate := chunk_coordinate + Vector3i(x, y, z)
				if not brick_is_valid(coordinate):
					continue
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				value = _checksum_step(value, brick.revision if brick != null else 0)
	return value & 0x7fffffff


func ensure_brick(brick_coordinate: Vector3i) -> SparseSdfBrick:
	if not brick_is_valid(brick_coordinate):
		return null
	var existing := _bricks.get(brick_coordinate) as SparseSdfBrick
	if existing != null:
		return existing
	var brick := SparseSdfBrick.new().configure(
		brick_coordinate,
		brick_cells,
		voxel_size,
		narrow_band,
		material_index
	)
	var global_origin := brick_coordinate * brick_cells
	brick.initialize_from_box_samples(global_origin, -half_extents, half_extents)
	_bricks[brick_coordinate] = brick
	return brick


func apply_damage_event(
	local_position: Vector3,
	local_direction: Vector3,
	local_normal: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition
) -> Dictionary:
	if event == null or texture == null or not event.is_valid():
		return {"changed": false, "reason": &"invalid"}
	texture.sanitize()
	var normalized_energy := texture.normalized_energy(event.energy)
	if normalized_energy < texture.geometry_threshold:
		var accumulated_changed := _apply_accumulated_damage(
			local_position,
			event,
			texture,
			normalized_energy
		)
		if not accumulated_changed:
			return {
				"changed": false,
				"reason": &"below_geometry_threshold",
				"normalized_energy": normalized_energy,
			}
		var accumulated_chunks: Array[Vector3i] = _changed_chunks_buffer.duplicate()
		if _last_accumulated_peak_damage < 255:
			revision += 1
			_stamp_changed_bricks(accumulated_chunks)
			return {
				"changed": true,
				"geometry_changed": false,
				"revision": revision,
				"changed_chunks": accumulated_chunks,
				"changed_samples": _last_accumulated_changed_samples,
				"operation_count": 0,
				"normalized_energy": normalized_energy,
				"perforated": false,
				"reason": &"damage_accumulated",
			}
		# Saturated local damage promotes the event to the profile's geometry threshold. It remains a
		# surface crater/dent; a series of weak taps cannot magically acquire penetration energy.
		var promoted_packet := event.to_dict(false)
		promoted_packet["energy"] = texture.energy_resistance * texture.geometry_threshold
		var promoted_event := DamageEvent.from_dict(promoted_packet)
		var promoted_result := _apply_geometry_event(
			local_position,
			local_direction,
			local_normal,
			promoted_event,
			texture,
			texture.geometry_threshold,
			accumulated_chunks
		)
		if bool(promoted_result.get("changed", false)):
			_clear_accumulated_damage(local_position, event, texture)
		return promoted_result
	return _apply_geometry_event(
		local_position,
		local_direction,
		local_normal,
		event,
		texture,
		normalized_energy
	)


func _apply_geometry_event(
	local_position: Vector3,
	local_direction: Vector3,
	local_normal: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition,
	normalized_energy: float,
	prechanged_chunks: Array[Vector3i] = []
) -> Dictionary:
	var direction := (
		local_direction.normalized()
		if local_direction.length_squared() > 0.000001
		else -local_normal.normalized()
	)
	_build_operations(
		local_position,
		direction,
		local_normal,
		event,
		texture,
		normalized_energy
	)
	_begin_changed_chunk_collection(prechanged_chunks)
	var changed_samples := _apply_operations(texture, event.seed)
	if changed_samples <= 0:
		if not prechanged_chunks.is_empty():
			revision += 1
			_stamp_changed_bricks(prechanged_chunks)
			return {
				"changed": true,
				"geometry_changed": false,
				"revision": revision,
				"changed_chunks": prechanged_chunks,
				"changed_samples": 0,
				"operation_count": 0,
				"normalized_energy": normalized_energy,
				"perforated": false,
				"reason": &"damage_accumulated",
			}
		return {
			"changed": false,
			"reason": &"no_surface_change",
			"normalized_energy": normalized_energy,
		}
	var structural_region := _merge_fragment_scan_region(
		_last_changed_sample_minimum,
		_last_changed_sample_maximum
	)
	var fragmentation := SdfStructuralFragmenter.detach_components(
		self,
		structural_region.get("minimum", _last_changed_sample_minimum),
		structural_region.get("maximum", _last_changed_sample_maximum),
		texture
	)
	changed_samples += int(fragmentation.get("removed_samples", 0))
	revision += 1
	var changed_chunks: Array[Vector3i] = _changed_chunks_buffer.duplicate()
	_stamp_changed_bricks(changed_chunks)
	var perforated := texture.perforates(event.energy)
	var aperture_radius := (
		texture.response_radius(event.radius, event.energy) * texture.channel_radius_scale
		if perforated
		else 0.0
	)
	return {
		"changed": true,
		"geometry_changed": true,
		"revision": revision,
		"changed_chunks": changed_chunks,
		"changed_samples": changed_samples,
		"has_changed_sample_bounds": _last_change_has_sample_bounds,
		"changed_sample_minimum": _last_changed_sample_minimum,
		"changed_sample_maximum": _last_changed_sample_maximum,
		"operation_count": _operation_count,
		"normalized_energy": normalized_energy,
		"perforated": perforated,
		"aperture_radius": aperture_radius,
		"detached_fragments": fragmentation.get("fragments", []),
		"detached_component_count": int(fragmentation.get("detached_component_count", 0)),
		"fragment_scan_cells": int(fragmentation.get("scan_cells", 0)),
		"fragment_mesh_failures": int(fragmentation.get("fragment_mesh_failures", 0)),
		"fragment_mapping_usec": int(fragmentation.get("mapping_usec", 0)),
		"fragment_grouping_usec": int(fragmentation.get("grouping_usec", 0)),
		"fragment_mesh_usec": int(fragmentation.get("mesh_usec", 0)),
		"fragment_erase_usec": int(fragmentation.get("erase_usec", 0)),
		"fragment_total_usec": int(fragmentation.get("total_usec", 0)),
		"retained_detached_cell_count": int(
			fragmentation.get("retained_detached_cell_count", 0)
		),
	}


func erase_detached_cells(cells: Array[Vector3i]) -> int:
	if cells.is_empty():
		return 0
	if (
		_native_kernel != null
		and is_instance_valid(_native_kernel)
		and _native_kernel.has_method(&"erase_cached_cells")
	):
		var native_result := _native_kernel.call(
			&"erase_cached_cells",
			cells,
			changed_brick_states()
		) as Dictionary
		if bool(native_result.get("valid", false)):
			var changed := int(native_result.get("changed_samples", 0))
			for packet_value: Variant in native_result.get("bricks", []):
				if not packet_value is Dictionary:
					continue
				var packet := packet_value as Dictionary
				var coordinate: Vector3i = packet.get("coordinate", Vector3i(-1, -1, -1))
				if not brick_is_valid(coordinate):
					continue
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				if brick == null:
					# The native packet contains the complete post-erasure brick. Do not initialize an
					# analytic brick sample-by-sample merely to overwrite every byte immediately after.
					brick = SparseSdfBrick.new().configure(
						coordinate,
						brick_cells,
						voxel_size,
						narrow_band,
						material_index
					)
					_bricks[coordinate] = brick
				if not brick.replace_distance_storage(
					bool(packet.get("uniform", false)),
					int(packet.get("uniform_raw", SparseSdfBrick.MAX_RAW)),
					packet.get("distance_bytes", PackedByteArray())
				):
					return 0
				_mark_changed_chunk(coordinate)
			if bool(native_result.get("has_changed_sample_bounds", false)):
				_include_changed_sample(native_result.get("changed_sample_minimum", Vector3i.ZERO))
				_include_changed_sample(native_result.get("changed_sample_maximum", Vector3i.ZERO))
			return changed
	var unique_samples: Dictionary[Vector3i, bool] = {}
	for cell: Vector3i in cells:
		for offset_z: int in range(0, 2):
			for offset_y: int in range(0, 2):
				for offset_x: int in range(0, 2):
					unique_samples[cell + Vector3i(offset_x, offset_y, offset_z)] = true
	var changed := 0
	for sample: Vector3i in unique_samples.keys():
		if not _global_sample_is_inside_storage(sample):
			continue
		var brick_coordinate := brick_for_global_sample(sample)
		var brick := ensure_brick(brick_coordinate)
		if brick == null:
			continue
		var local_sample := sample - brick_coordinate * brick_cells
		if brick.set_distance(local_sample.x, local_sample.y, local_sample.z, narrow_band):
			changed += 1
			_mark_changed_chunk(brick_coordinate)
			_include_changed_sample(sample)
	return changed


func fragment_scan_region_states() -> Array[Dictionary]:
	return _fragment_scan_regions.duplicate(true)


func restore_fragment_scan_regions(states: Array) -> void:
	_fragment_scan_regions.clear()
	for value: Variant in states:
		if not value is Dictionary:
			continue
		var minimum: Variant = value.get("minimum", null)
		var maximum: Variant = value.get("maximum", null)
		if minimum is Vector3i and maximum is Vector3i:
			_fragment_scan_regions.append({"minimum": minimum, "maximum": maximum})


func _merge_fragment_scan_region(minimum: Vector3i, maximum: Vector3i) -> Dictionary:
	var merged_minimum := minimum
	var merged_maximum := maximum
	var merge_distance := SdfStructuralFragmenter.SCAN_MARGIN_CELLS * 2
	var write_index := 0
	for region: Dictionary in _fragment_scan_regions:
		var region_minimum: Vector3i = region.get("minimum", minimum)
		var region_maximum: Vector3i = region.get("maximum", maximum)
		var separated := (
			merged_maximum.x + merge_distance < region_minimum.x
			or region_maximum.x + merge_distance < merged_minimum.x
			or merged_maximum.y + merge_distance < region_minimum.y
			or region_maximum.y + merge_distance < merged_minimum.y
			or merged_maximum.z + merge_distance < region_minimum.z
			or region_maximum.z + merge_distance < merged_minimum.z
		)
		if separated:
			_fragment_scan_regions[write_index] = region
			write_index += 1
			continue
		merged_minimum = Vector3i(
			mini(merged_minimum.x, region_minimum.x),
			mini(merged_minimum.y, region_minimum.y),
			mini(merged_minimum.z, region_minimum.z)
		)
		merged_maximum = Vector3i(
			maxi(merged_maximum.x, region_maximum.x),
			maxi(merged_maximum.y, region_maximum.y),
			maxi(merged_maximum.z, region_maximum.z)
		)
	_fragment_scan_regions.resize(write_index)
	var merged := {"minimum": merged_minimum, "maximum": merged_maximum}
	_fragment_scan_regions.append(merged)
	return merged


func expanded_chunk_ring(coordinates: Array[Vector3i], radius := 1) -> Array[Vector3i]:
	_ring_collection_stamp += 1
	if _ring_collection_stamp >= 0x7fffffff:
		_ring_chunk_stamps.fill(0)
		_ring_collection_stamp = 1
	var safe_radius := clampi(radius, 0, 2)
	var result: Array[Vector3i] = []
	for center: Vector3i in coordinates:
		for z: int in range(-safe_radius, safe_radius + 1):
			for y: int in range(-safe_radius, safe_radius + 1):
				for x: int in range(-safe_radius, safe_radius + 1):
					var coordinate := center + Vector3i(x, y, z)
					if not brick_is_valid(coordinate):
						continue
					var flat_index := coordinate.x + brick_counts.x * (
						coordinate.y + brick_counts.y * coordinate.z
					)
					if _ring_chunk_stamps[flat_index] == _ring_collection_stamp:
						continue
					_ring_chunk_stamps[flat_index] = _ring_collection_stamp
					result.append(coordinate)
	return result


func changed_brick_states() -> Array[Dictionary]:
	var coordinates: Array[Vector3i] = []
	for coordinate: Vector3i in _bricks.keys():
		coordinates.append(coordinate)
	coordinates.sort_custom(_vector3i_less)
	var result: Array[Dictionary] = []
	for coordinate: Vector3i in coordinates:
		var brick := _bricks[coordinate] as SparseSdfBrick
		result.append(brick.encoded_state())
	return result


func apply_checkpoint(checkpoint_revision: int, states: Array) -> bool:
	var replacements: Dictionary[Vector3i, SparseSdfBrick] = {}
	for raw_state: Variant in states:
		if not raw_state is Dictionary:
			return false
		var brick := SparseSdfBrick.from_encoded_state(raw_state)
		if not brick_is_valid(brick.coordinate):
			return false
		replacements[brick.coordinate] = brick
	_bricks = replacements
	revision = maxi(checkpoint_revision, 0)
	_synchronize_native_dense_field()
	return true


func synchronize_native_dense_field() -> bool:
	return _synchronize_native_dense_field()


func _synchronize_native_dense_field() -> bool:
	if (
		_native_kernel == null
		or not is_instance_valid(_native_kernel)
		or not _native_kernel.has_method(&"synchronize_dense_field")
	):
		return false
	return bool(_native_kernel.call(
		&"synchronize_dense_field",
		changed_brick_states(),
		half_extents,
		voxel_size,
		total_cells,
		brick_cells,
		narrow_band
	))


func checksum() -> int:
	var value := 2166136261
	value = _checksum_step(value, revision)
	var coordinates: Array[Vector3i] = []
	for coordinate: Vector3i in _bricks.keys():
		coordinates.append(coordinate)
	coordinates.sort_custom(_vector3i_less)
	for coordinate: Vector3i in coordinates:
		value = _checksum_step(value, (_bricks[coordinate] as SparseSdfBrick).checksum())
	return value & 0x7fffffff


func debug_state() -> Dictionary:
	var sample_bytes := 0
	var damage_bricks := 0
	for brick: SparseSdfBrick in _bricks.values():
		sample_bytes += brick.storage_byte_count()
		if brick.has_damage_channel():
			damage_bricks += 1
	var native_ready := (
		prefer_native_backend
		and _native_kernel != null
		and is_instance_valid(_native_kernel)
	)
	var native_scratch: Dictionary = (
		_native_kernel.call(&"scratch_state") as Dictionary
		if native_ready
		else {}
	)
	return {
		"revision": revision,
		"brick_count": _bricks.size(),
		"brick_counts": brick_counts,
		"sample_bytes": sample_bytes,
		"damage_bricks": damage_bricks,
		"checksum": checksum(),
		"operation_buffer_capacity": _operation_kinds.size(),
		"noise_lattice_capacity": _noise_lattice_values.size(),
		"noise_lattice_growth_count": _noise_lattice_growth_count,
		"native_backend": native_ready,
		"native_scratch": native_scratch,
	}


func _build_operations(
	position: Vector3,
	direction: Vector3,
	normal: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition,
	normalized_energy: float
) -> void:
	_reset_operation_buffer()
	var radius := texture.response_radius(event.radius, event.energy)
	var entry_depth := maxf(radius * texture.entry_depth_scale, voxel_size)
	var entry_start := position - direction * minf(radius * 0.25, voxel_size)
	var entry_end := position + direction * entry_depth
	var entry_end_radius := radius * maxf(texture.channel_radius_scale, 0.1)
	var perforates := texture.perforates(event.energy)
	if not perforates and texture.ductility >= 0.4 and texture.dent_depth_scale > 0.0:
		var dent_depth := maxf(radius * texture.dent_depth_scale * normalized_energy, voxel_size * 0.25)
		entry_end = position + direction * minf(dent_depth, radius * 0.9)
		entry_end_radius = radius * 0.35
	_append_operation(
		OPERATION_TAPERED_CAPSULE,
		entry_start,
		entry_end,
		radius,
		entry_end_radius
	)

	if perforates:
		var penetration_depth := maxf(
			maxf(event.penetration, radius * 3.0) * texture.penetration_depth_scale,
			voxel_size * 2.0
		)
		var channel_radius := maxf(radius * texture.channel_radius_scale, voxel_size * 0.45)
		var channel_end := position + direction * penetration_depth
		_append_operation(
			OPERATION_CAPSULE,
			position,
			channel_end,
			channel_radius,
			channel_radius
		)
		var exit_distance := _find_exit_distance(position, direction, penetration_depth)
		if exit_distance >= 0.0 and texture.exit_spall_radius_scale > 0.0:
			var exit_position := position + direction * exit_distance
			var spall_depth := maxf(radius * texture.exit_spall_depth_scale, voxel_size)
			_append_operation(
				OPERATION_TAPERED_CAPSULE,
				exit_position - direction * spall_depth,
				exit_position + direction * voxel_size,
				channel_radius,
				radius * texture.exit_spall_radius_scale
			)

	_append_crack_operations(position, normal, radius, event.seed, texture)


func _append_crack_operations(
	position: Vector3,
	normal: Vector3,
	radius: float,
	seed: int,
	texture: DestructionTextureDefinition
) -> void:
	var count := mini(texture.crack_count, MAX_CRACK_OPERATIONS)
	if count <= 0 or texture.crack_length_scale <= 0.0 or texture.crack_width_scale <= 0.0:
		return
	var authored_width := radius * texture.crack_width_scale
	if authored_width < voxel_size * texture.minimum_geometric_feature_voxels:
		# Features below the sample lattice belong to the decal/presentation layer. Inflating every
		# bullet crack to a resolvable trench both looks wrong and multiplies hot-path brush work.
		return
	var safe_normal := normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
	var basis := SdfMath.orthogonal_basis(safe_normal)
	var grain_tangent := texture.grain_axis - safe_normal * texture.grain_axis.dot(safe_normal)
	if grain_tangent.length_squared() > 0.000001:
		grain_tangent = grain_tangent.normalized()
	for crack_index: int in range(count):
		var angle_noise := _unit_hash(seed, crack_index * 7 + 1)
		var angle := TAU * (float(crack_index) + angle_noise * 0.65) / float(count)
		var tangent := (basis.x * cos(angle) + basis.y * sin(angle)).normalized()
		if texture.anisotropy > 0.0 and grain_tangent.length_squared() > 0.000001:
			var aligned := grain_tangent * (1.0 if tangent.dot(grain_tangent) >= 0.0 else -1.0)
			tangent = tangent.slerp(aligned, texture.anisotropy).normalized()
		var length_scale := lerpf(0.65, 1.35, _unit_hash(seed, crack_index * 7 + 2))
		var crack_length := radius * texture.crack_length_scale * length_scale
		var width := authored_width
		var embedded_start := position - safe_normal * width * 0.75
		_append_operation(
			OPERATION_CAPSULE,
			embedded_start,
			embedded_start + tangent * crack_length,
			width,
			width
		)


func _initialize_operation_buffer() -> void:
	_operation_kinds.resize(MAX_DAMAGE_OPERATIONS)
	_operation_starts.resize(MAX_DAMAGE_OPERATIONS)
	_operation_ends.resize(MAX_DAMAGE_OPERATIONS)
	_operation_first_radii.resize(MAX_DAMAGE_OPERATIONS)
	_operation_second_radii.resize(MAX_DAMAGE_OPERATIONS)
	_operation_bounds.resize(MAX_DAMAGE_OPERATIONS)
	_reset_operation_buffer()


func _reset_operation_buffer() -> void:
	_operation_count = 0
	_operation_combined_bounds = AABB()
	_operation_maximum_radius = 0.0


func _append_operation(
	kind: int,
	start: Vector3,
	end: Vector3,
	first_radius: float,
	second_radius: float
) -> void:
	if _operation_count >= MAX_DAMAGE_OPERATIONS:
		return
	var index := _operation_count
	var safe_first_radius := maxf(first_radius, 0.0)
	var safe_second_radius := maxf(second_radius, 0.0)
	var maximum_radius := maxf(safe_first_radius, safe_second_radius)
	_operation_kinds[index] = kind
	_operation_starts[index] = start
	_operation_ends[index] = end
	_operation_first_radii[index] = safe_first_radius
	_operation_second_radii[index] = safe_second_radius
	var minimum := Vector3(
		minf(start.x, end.x),
		minf(start.y, end.y),
		minf(start.z, end.z)
	) - Vector3.ONE * maximum_radius
	var maximum := Vector3(
		maxf(start.x, end.x),
		maxf(start.y, end.y),
		maxf(start.z, end.z)
	) + Vector3.ONE * maximum_radius
	var bounds := AABB(minimum, maximum - minimum).grow(narrow_band + voxel_size)
	_operation_bounds[index] = bounds
	_operation_combined_bounds = (
		bounds
		if index == 0
		else _operation_combined_bounds.merge(bounds)
	)
	_operation_maximum_radius = maxf(_operation_maximum_radius, maximum_radius)
	_operation_count += 1


func _apply_operations(
	texture: DestructionTextureDefinition,
	seed: int
) -> int:
	if _operation_count <= 0:
		return 0
	# Boolean subtraction by the union of all cutters is max(base, -min(cutter distances)). Fusing
	# the brushes means each touched sample and packed distance is read/written once, even when a
	# brittle material authors several crack capsules.
	# Dual Contouring consumes one cell of sign samples plus one additional sample for central-difference
	# normals. Distance edits deeper than this cannot affect current topology or its Hermite data, even
	# though they remain stored for later damage. Excluding them keeps remeshing tied to the visible cut.
	var mesh_influence_band := voxel_size * 2.5
	_prepare_noise_lattice(texture, seed)
	if (
		prefer_native_backend
		and _native_kernel != null
		and is_instance_valid(_native_kernel)
		and (texture.spatial_warp <= 0.0 or _noise_lattice_valid)
	):
		var native_changed := _apply_operations_native(texture)
		if native_changed >= 0:
			return native_changed
	var minimum_brick := _brick_for_local_position(_operation_combined_bounds.position)
	var maximum_brick := _brick_for_local_position(_operation_combined_bounds.end)
	var changed_samples := 0
	for z: int in range(minimum_brick.z, maximum_brick.z + 1):
		for y: int in range(minimum_brick.y, maximum_brick.y + 1):
			for x: int in range(minimum_brick.x, maximum_brick.x + 1):
				var coordinate := Vector3i(x, y, z)
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				var brick_changed := false
				var global_origin := coordinate * brick_cells
				var samples_per_axis := brick_cells + 1
				var grid_minimum := Vector3i(
					ceili((_operation_combined_bounds.position.x + half_extents.x) / voxel_size),
					ceili((_operation_combined_bounds.position.y + half_extents.y) / voxel_size),
					ceili((_operation_combined_bounds.position.z + half_extents.z) / voxel_size)
				) - global_origin
				var grid_maximum := Vector3i(
					floori((_operation_combined_bounds.end.x + half_extents.x) / voxel_size),
					floori((_operation_combined_bounds.end.y + half_extents.y) / voxel_size),
					floori((_operation_combined_bounds.end.z + half_extents.z) / voxel_size)
				) - global_origin
				grid_minimum = Vector3i(
					clampi(grid_minimum.x, 0, samples_per_axis - 1),
					clampi(grid_minimum.y, 0, samples_per_axis - 1),
					clampi(grid_minimum.z, 0, samples_per_axis - 1)
				)
				grid_maximum = Vector3i(
					clampi(grid_maximum.x, 0, samples_per_axis - 1),
					clampi(grid_maximum.y, 0, samples_per_axis - 1),
					clampi(grid_maximum.z, 0, samples_per_axis - 1)
				)
				for sample_z: int in range(grid_minimum.z, grid_maximum.z + 1):
					var global_z := global_origin.z + sample_z
					var position_z := -half_extents.z + float(global_z) * voxel_size
					for sample_y: int in range(grid_minimum.y, grid_maximum.y + 1):
						var global_y := global_origin.y + sample_y
						var position_y := -half_extents.y + float(global_y) * voxel_size
						var linear_index := (
							grid_minimum.x
							+ samples_per_axis * (sample_y + samples_per_axis * sample_z)
						)
						var position_x := (
							-half_extents.x + float(global_origin.x + grid_minimum.x) * voxel_size
						)
						for sample_x: int in range(grid_minimum.x, grid_maximum.x + 1):
							var current_linear_index := linear_index
							linear_index += 1
							var global_x := global_origin.x + sample_x
							var sample_position := Vector3(position_x, position_y, position_z)
							position_x += voxel_size
							var previous := (
								brick.get_distance_at_index(current_linear_index)
								if brick != null
								else base_distance(sample_position)
							)
							# A cutter cannot increase empty-space distance beyond its own radius. This rejects
							# most samples outside a thin wall before any brush/noise evaluation.
							if previous >= _operation_maximum_radius:
								continue
							var cutter_distance := INF
							var warp_noise := 0.0
							if texture.spatial_warp > 0.0:
								warp_noise = _sample_spatial_noise(
									sample_position,
									texture.spatial_warp_frequency,
									seed
								) * texture.spatial_warp
							for operation_index: int in range(_operation_count):
								if not _operation_bounds[operation_index].has_point(sample_position):
									continue
								var characteristic_radius := maxf(
									_operation_first_radii[operation_index],
									_operation_second_radii[operation_index]
								)
								var brush_distance := 0.0
								match int(_operation_kinds[operation_index]):
									1:
										brush_distance = SdfMath.capsule(
											sample_position,
											_operation_starts[operation_index],
											_operation_ends[operation_index],
											_operation_first_radii[operation_index]
										)
									2:
										brush_distance = SdfMath.tapered_capsule(
											sample_position,
											_operation_starts[operation_index],
											_operation_ends[operation_index],
											_operation_first_radii[operation_index],
											_operation_second_radii[operation_index]
										)
									_:
										brush_distance = SdfMath.sphere(
											sample_position,
											_operation_starts[operation_index],
											_operation_first_radii[operation_index]
										)
								if warp_noise != 0.0 and characteristic_radius > 0.0:
									brush_distance -= warp_noise * characteristic_radius
								cutter_distance = minf(cutter_distance, brush_distance)
							if cutter_distance > narrow_band:
								continue
							var next := SdfMath.subtract(previous, cutter_distance)
							if is_equal_approx(next, previous):
								continue
							if brick == null:
								brick = ensure_brick(coordinate)
							if brick != null and brick.set_distance_at_index(current_linear_index, next):
								brick_changed = true
								changed_samples += 1
								if (
									(previous < 0.0) != (next < 0.0)
									or minf(absf(previous), absf(next)) <= mesh_influence_band
								):
									_include_changed_sample(Vector3i(global_x, global_y, global_z))
				if brick_changed:
					_mark_changed_chunk(coordinate)
	return changed_samples


func _apply_operations_native(texture: DestructionTextureDefinition) -> int:
	_native_mutation_request["half_extents"] = half_extents
	_native_mutation_request["voxel_size"] = voxel_size
	_native_mutation_request["narrow_band"] = narrow_band
	_native_mutation_request["brick_cells"] = brick_cells
	_native_mutation_request["combined_minimum"] = _operation_combined_bounds.position
	_native_mutation_request["combined_maximum"] = _operation_combined_bounds.end
	_native_mutation_request["maximum_radius"] = _operation_maximum_radius
	_native_mutation_request["operation_count"] = _operation_count
	_native_mutation_request["operation_kinds"] = _operation_kinds
	_native_mutation_request["operation_starts"] = _operation_starts
	_native_mutation_request["operation_ends"] = _operation_ends
	_native_mutation_request["operation_first_radii"] = _operation_first_radii
	_native_mutation_request["operation_second_radii"] = _operation_second_radii
	_native_mutation_request["spatial_warp"] = texture.spatial_warp
	_native_mutation_request["noise_frequency"] = _noise_lattice_frequency
	_native_mutation_request["noise_origin"] = _noise_lattice_origin
	_native_mutation_request["noise_size"] = _noise_lattice_size
	_native_mutation_request["noise_values"] = _noise_lattice_values
	var began: bool = _native_kernel.call(&"begin_brush_union", _native_mutation_request)
	if not began:
		return -1
	var minimum_brick := _brick_for_local_position(_operation_combined_bounds.position)
	var maximum_brick := _brick_for_local_position(_operation_combined_bounds.end)
	var changed_samples := 0
	for z: int in range(minimum_brick.z, maximum_brick.z + 1):
		for y: int in range(minimum_brick.y, maximum_brick.y + 1):
			for x: int in range(minimum_brick.x, maximum_brick.x + 1):
				var coordinate := Vector3i(x, y, z)
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				_native_brick_request["coordinate"] = coordinate
				_native_brick_request["exists"] = brick != null
				_native_brick_request["uniform"] = (
					brick.native_is_uniform() if brick != null else true
				)
				_native_brick_request["uniform_raw"] = (
					brick.native_uniform_raw() if brick != null else SparseSdfBrick.MAX_RAW
				)
				_native_brick_request["distance_bytes"] = (
					brick.native_distance_bytes() if brick != null else PackedByteArray()
				)
				var native_result: Dictionary = _native_kernel.call(
					&"apply_brush_union_to_brick",
					_native_brick_request
				)
				if not bool(native_result.get("valid", false)):
					# begin_brush_union validates the entire immutable event contract. Reaching this
					# branch means corrupt brick state; do not mix native and scripted writes silently.
					push_error("Native SDF mutation rejected brick %s" % coordinate)
					return changed_samples
				if not bool(native_result.get("changed", false)):
					continue
				if brick == null:
					brick = SparseSdfBrick.new().configure(
						coordinate,
						brick_cells,
						voxel_size,
						narrow_band,
						material_index
					)
					_bricks[coordinate] = brick
				var distances: PackedByteArray = native_result.get(
					"distance_bytes",
					PackedByteArray()
				)
				if not brick.replace_native_distances(
					distances,
					int(native_result.get("uniform_raw", SparseSdfBrick.MAX_RAW))
				):
					push_error("Native SDF mutation returned invalid packed brick %s" % coordinate)
					return changed_samples
				changed_samples += int(native_result.get("changed_samples", 0))
				if bool(native_result.get("has_changed_sample_bounds", false)):
					_include_changed_sample(native_result.get(
						"changed_sample_minimum",
						Vector3i.ZERO
					))
					_include_changed_sample(native_result.get(
						"changed_sample_maximum",
						Vector3i.ZERO
					))
				_mark_changed_chunk(coordinate)
	return changed_samples


func _prepare_noise_lattice(texture: DestructionTextureDefinition, seed: int) -> void:
	_noise_lattice_valid = false
	if texture.spatial_warp <= 0.0:
		return
	var frequency := maxf(texture.spatial_warp_frequency, 0.0001)
	var scaled_minimum := _operation_combined_bounds.position * frequency
	var scaled_maximum := _operation_combined_bounds.end * frequency
	var minimum := Vector3i(
		floori(scaled_minimum.x),
		floori(scaled_minimum.y),
		floori(scaled_minimum.z)
	)
	var maximum := Vector3i(
		floori(scaled_maximum.x) + 1,
		floori(scaled_maximum.y) + 1,
		floori(scaled_maximum.z) + 1
	)
	var lattice_size := maximum - minimum + Vector3i.ONE
	var value_count := lattice_size.x * lattice_size.y * lattice_size.z
	if value_count <= 0 or value_count > MAX_CACHED_NOISE_LATTICE_VALUES:
		return
	if _noise_lattice_values.size() < value_count:
		_noise_lattice_values.resize(value_count)
		_noise_lattice_growth_count += 1
	_noise_lattice_origin = minimum
	_noise_lattice_size = lattice_size
	_noise_lattice_frequency = frequency
	var write_index := 0
	for z: int in range(lattice_size.z):
		for y: int in range(lattice_size.y):
			for x: int in range(lattice_size.x):
				_noise_lattice_values[write_index] = SdfMath.deterministic_lattice_noise(
					minimum.x + x,
					minimum.y + y,
					minimum.z + z,
					seed
				)
				write_index += 1
	_noise_lattice_valid = true


func _sample_spatial_noise(point: Vector3, frequency: float, seed: int) -> float:
	if not _noise_lattice_valid:
		return SdfMath.deterministic_signed_noise(point, frequency, seed)
	var scaled := point * _noise_lattice_frequency
	var lattice_x := floori(scaled.x)
	var lattice_y := floori(scaled.y)
	var lattice_z := floori(scaled.z)
	var local_x := lattice_x - _noise_lattice_origin.x
	var local_y := lattice_y - _noise_lattice_origin.y
	var local_z := lattice_z - _noise_lattice_origin.z
	if (
		local_x < 0
		or local_y < 0
		or local_z < 0
		or local_x + 1 >= _noise_lattice_size.x
		or local_y + 1 >= _noise_lattice_size.y
		or local_z + 1 >= _noise_lattice_size.z
	):
		return SdfMath.deterministic_signed_noise(point, frequency, seed)
	var stride_y := _noise_lattice_size.x
	var stride_z := stride_y * _noise_lattice_size.y
	var base_index := local_x + stride_y * local_y + stride_z * local_z
	var tx := SdfMath.quintic_fade(scaled.x - float(lattice_x))
	var ty := SdfMath.quintic_fade(scaled.y - float(lattice_y))
	var tz := SdfMath.quintic_fade(scaled.z - float(lattice_z))
	var x00 := lerpf(
		_noise_lattice_values[base_index],
		_noise_lattice_values[base_index + 1],
		tx
	)
	var x10 := lerpf(
		_noise_lattice_values[base_index + stride_y],
		_noise_lattice_values[base_index + stride_y + 1],
		tx
	)
	var x01 := lerpf(
		_noise_lattice_values[base_index + stride_z],
		_noise_lattice_values[base_index + stride_z + 1],
		tx
	)
	var x11 := lerpf(
		_noise_lattice_values[base_index + stride_z + stride_y],
		_noise_lattice_values[base_index + stride_z + stride_y + 1],
		tx
	)
	return lerpf(lerpf(x00, x10, ty), lerpf(x01, x11, ty), tz)


func _include_changed_sample(sample: Vector3i) -> void:
	if not _last_change_has_sample_bounds:
		_last_change_has_sample_bounds = true
		_last_changed_sample_minimum = sample
		_last_changed_sample_maximum = sample
		return
	_last_changed_sample_minimum = Vector3i(
		mini(_last_changed_sample_minimum.x, sample.x),
		mini(_last_changed_sample_minimum.y, sample.y),
		mini(_last_changed_sample_minimum.z, sample.z)
	)
	_last_changed_sample_maximum = Vector3i(
		maxi(_last_changed_sample_maximum.x, sample.x),
		maxi(_last_changed_sample_maximum.y, sample.y),
		maxi(_last_changed_sample_maximum.z, sample.z)
	)


func _begin_changed_chunk_collection(prechanged_chunks: Array[Vector3i] = []) -> void:
	_change_collection_stamp += 1
	if _change_collection_stamp >= 0x7fffffff:
		_changed_chunk_stamps.fill(0)
		_change_collection_stamp = 1
	_changed_chunks_buffer.clear()
	_last_change_has_sample_bounds = false
	for coordinate: Vector3i in prechanged_chunks:
		_mark_changed_chunk(coordinate)


func _mark_changed_chunk(coordinate: Vector3i) -> void:
	var flat_index := coordinate.x + brick_counts.x * (
		coordinate.y + brick_counts.y * coordinate.z
	)
	if flat_index < 0 or flat_index >= _changed_chunk_stamps.size():
		return
	if _changed_chunk_stamps[flat_index] == _change_collection_stamp:
		return
	_changed_chunk_stamps[flat_index] = _change_collection_stamp
	_changed_chunks_buffer.append(coordinate)


func _apply_accumulated_damage(
	position: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition,
	normalized_energy: float
) -> bool:
	_begin_changed_chunk_collection()
	_last_accumulated_changed_samples = 0
	_last_accumulated_peak_damage = 0
	if texture.damage_accumulation <= 0.0 or normalized_energy <= 0.0:
		return false
	var radius := maxf(event.radius * texture.entry_radius_scale, voxel_size)
	var operation_bounds := AABB(
		position - Vector3.ONE * radius,
		Vector3.ONE * radius * 2.0
	).grow(voxel_size)
	var minimum_brick := _brick_for_local_position(operation_bounds.position)
	var maximum_brick := _brick_for_local_position(operation_bounds.end)
	var amount := clampi(roundi(normalized_energy * texture.damage_accumulation * 32.0), 1, 255)
	var radius_squared := radius * radius
	var changed_samples := 0
	var peak_damage := 0
	for z: int in range(minimum_brick.z, maximum_brick.z + 1):
		for y: int in range(minimum_brick.y, maximum_brick.y + 1):
			for x: int in range(minimum_brick.x, maximum_brick.x + 1):
				var coordinate := Vector3i(x, y, z)
				var brick := ensure_brick(coordinate)
				if brick == null:
					continue
				var global_origin := coordinate * brick_cells
				for sample_z: int in range(brick.samples_per_axis):
					var position_z := (
						-half_extents.z + float(global_origin.z + sample_z) * voxel_size
					)
					for sample_y: int in range(brick.samples_per_axis):
						var position_y := (
							-half_extents.y + float(global_origin.y + sample_y) * voxel_size
						)
						var linear_index := brick.samples_per_axis * (
							sample_y + brick.samples_per_axis * sample_z
						)
						var position_x := -half_extents.x + float(global_origin.x) * voxel_size
						for sample_x: int in range(brick.samples_per_axis):
							var current_linear_index := linear_index
							linear_index += 1
							var sample_position := Vector3(position_x, position_y, position_z)
							position_x += voxel_size
							if sample_position.distance_squared_to(position) <= radius_squared:
								var previous := brick.get_damage_at_index(current_linear_index)
								var next := brick.add_damage_at_index(current_linear_index, amount)
								peak_damage = maxi(peak_damage, next)
								if next != previous:
									changed_samples += 1
									_mark_changed_chunk(coordinate)
	_last_accumulated_changed_samples = changed_samples
	_last_accumulated_peak_damage = peak_damage
	return changed_samples > 0


func _clear_accumulated_damage(
	position: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition
) -> void:
	var radius := maxf(event.radius * texture.entry_radius_scale, voxel_size)
	var bounds_to_clear := AABB(
		position - Vector3.ONE * radius,
		Vector3.ONE * radius * 2.0
	).grow(voxel_size)
	var minimum_brick := _brick_for_local_position(bounds_to_clear.position)
	var maximum_brick := _brick_for_local_position(bounds_to_clear.end)
	var radius_squared := radius * radius
	for z: int in range(minimum_brick.z, maximum_brick.z + 1):
		for y: int in range(minimum_brick.y, maximum_brick.y + 1):
			for x: int in range(minimum_brick.x, maximum_brick.x + 1):
				var coordinate := Vector3i(x, y, z)
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				if brick == null or not brick.has_damage_channel():
					continue
				var global_origin := coordinate * brick_cells
				for sample_z: int in range(brick.samples_per_axis):
					var position_z := (
						-half_extents.z + float(global_origin.z + sample_z) * voxel_size
					)
					for sample_y: int in range(brick.samples_per_axis):
						var position_y := (
							-half_extents.y + float(global_origin.y + sample_y) * voxel_size
						)
						var linear_index := brick.samples_per_axis * (
							sample_y + brick.samples_per_axis * sample_z
						)
						var position_x := -half_extents.x + float(global_origin.x) * voxel_size
						for sample_x: int in range(brick.samples_per_axis):
							var current_linear_index := linear_index
							linear_index += 1
							var sample_position := Vector3(position_x, position_y, position_z)
							position_x += voxel_size
							if sample_position.distance_squared_to(position) <= radius_squared:
								brick.set_damage_at_index(current_linear_index, 0)


func _stamp_changed_bricks(coordinates: Array[Vector3i]) -> void:
	for coordinate: Vector3i in coordinates:
		var brick := _bricks.get(coordinate) as SparseSdfBrick
		if brick != null:
			brick.revision = revision


func _find_exit_distance(position: Vector3, direction: Vector3, maximum_distance: float) -> float:
	var step := maxf(voxel_size * 0.5, 0.005)
	var entered_solid := base_distance(position + direction * step) <= 0.0
	var distance := step
	while distance <= maximum_distance:
		var current_solid := sample_distance(position + direction * distance) <= 0.0
		if entered_solid and not current_solid:
			return distance
		entered_solid = entered_solid or current_solid
		distance += step
	return -1.0


func _brick_for_local_position(local_position: Vector3) -> Vector3i:
	var grid_position := (local_position + half_extents) / brick_extent
	return Vector3i(
		clampi(floori(grid_position.x), 0, brick_counts.x - 1),
		clampi(floori(grid_position.y), 0, brick_counts.y - 1),
		clampi(floori(grid_position.z), 0, brick_counts.z - 1)
	)


func _global_sample_is_inside_storage(coordinate: Vector3i) -> bool:
	return (
		coordinate.x >= 0
		and coordinate.y >= 0
		and coordinate.z >= 0
		and coordinate.x <= total_cells.x
		and coordinate.y <= total_cells.y
		and coordinate.z <= total_cells.z
	)


static func _unit_hash(seed: int, index: int) -> float:
	var value := seed ^ (index * 0x45d9f3b)
	value = ((value >> 16) ^ value) * 0x45d9f3b
	value = ((value >> 16) ^ value) * 0x45d9f3b
	value = (value >> 16) ^ value
	return float(value & 0xffff) / 65535.0


static func _vector3i_less(left: Vector3i, right: Vector3i) -> bool:
	if left.z != right.z:
		return left.z < right.z
	if left.y != right.y:
		return left.y < right.y
	return left.x < right.x


static func _checksum_step(state: int, value: int) -> int:
	return ((state ^ value) * 16777619) & 0xffffffff
