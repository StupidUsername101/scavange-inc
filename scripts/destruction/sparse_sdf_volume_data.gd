class_name SparseSdfVolumeData
extends RefCounted

## Sparse copy-on-first-edit SDF state for one finite destructible volume. The immutable base is an
## analytic box in the first vertical slice; imported-mesh bake providers can implement the same
## global-sample contract later without changing damage, meshing, replication, or collision code.

const MIN_VOXEL_SIZE := 0.005
const MAX_BRICK_CELLS := 48
const MIN_BRICK_CELLS := 4
const MAX_CRACK_OPERATIONS := 12

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

var _bricks: Dictionary[Vector3i, SparseSdfBrick] = {}


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
	return self


func bounds() -> AABB:
	return AABB(-half_extents, size)


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
	var distances := PackedFloat32Array()
	distances.resize(brick.sample_count())
	var index := 0
	var global_origin := brick_coordinate * brick_cells
	for z: int in range(brick.samples_per_axis):
		for y: int in range(brick.samples_per_axis):
			for x: int in range(brick.samples_per_axis):
				distances[index] = base_distance(
					global_sample_position(global_origin + Vector3i(x, y, z))
				)
				index += 1
	brick.initialize_from_distances(distances)
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
		var accumulated := _apply_accumulated_damage(
			local_position,
			event,
			texture,
			normalized_energy
		)
		if not bool(accumulated.get("changed", false)):
			return {
				"changed": false,
				"reason": &"below_geometry_threshold",
				"normalized_energy": normalized_energy,
			}
		var accumulated_chunks: Array[Vector3i] = accumulated.get("changed_chunks", [])
		if int(accumulated.get("peak_damage", 0)) < 255:
			revision += 1
			_stamp_changed_bricks(accumulated_chunks)
			return {
				"changed": true,
				"geometry_changed": false,
				"revision": revision,
				"changed_chunks": accumulated_chunks,
				"changed_samples": int(accumulated.get("changed_samples", 0)),
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
	var operations := _build_operations(
		local_position,
		direction,
		local_normal,
		event,
		texture,
		normalized_energy
	)
	var changed_set: Dictionary[Vector3i, bool] = {}
	for coordinate: Vector3i in prechanged_chunks:
		changed_set[coordinate] = true
	var operation_result := _apply_operations(operations, texture, event.seed, changed_set)
	var changed_samples := int(operation_result.get("changed_samples", 0))
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
	revision += 1
	var changed_chunks: Array[Vector3i] = []
	for coordinate: Vector3i in changed_set.keys():
		changed_chunks.append(coordinate)
	changed_chunks.sort_custom(_vector3i_less)
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
		"changed_sample_bounds": operation_result.get("changed_sample_bounds", {}),
		"operation_count": operations.size(),
		"normalized_energy": normalized_energy,
		"perforated": perforated,
		"aperture_radius": aperture_radius,
	}


func expanded_chunk_ring(coordinates: Array[Vector3i], radius := 1) -> Array[Vector3i]:
	var unique: Dictionary[Vector3i, bool] = {}
	var safe_radius := clampi(radius, 0, 2)
	for center: Vector3i in coordinates:
		for z: int in range(-safe_radius, safe_radius + 1):
			for y: int in range(-safe_radius, safe_radius + 1):
				for x: int in range(-safe_radius, safe_radius + 1):
					var coordinate := center + Vector3i(x, y, z)
					if brick_is_valid(coordinate):
						unique[coordinate] = true
	var result: Array[Vector3i] = []
	for coordinate: Vector3i in unique.keys():
		result.append(coordinate)
	result.sort_custom(_vector3i_less)
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
	return true


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
		var state := brick.encoded_state()
		sample_bytes += (state["distance_bytes"] as PackedByteArray).size()
		sample_bytes += (state["damage_bytes"] as PackedByteArray).size()
		if brick.has_damage_channel():
			damage_bricks += 1
	return {
		"revision": revision,
		"brick_count": _bricks.size(),
		"brick_counts": brick_counts,
		"sample_bytes": sample_bytes,
		"damage_bricks": damage_bricks,
		"checksum": checksum(),
	}


func _build_operations(
	position: Vector3,
	direction: Vector3,
	normal: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition,
	normalized_energy: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var radius := texture.response_radius(event.radius, event.energy)
	var entry_depth := maxf(radius * texture.entry_depth_scale, voxel_size)
	var entry_start := position - direction * minf(radius * 0.25, voxel_size)
	var entry_end := position + direction * entry_depth
	result.append({
		"kind": &"tapered_capsule",
		"start": entry_start,
		"end": entry_end,
		"start_radius": radius,
		"end_radius": radius * maxf(texture.channel_radius_scale, 0.1),
	})

	if texture.perforates(event.energy):
		var penetration_depth := maxf(
			maxf(event.penetration, radius * 3.0) * texture.penetration_depth_scale,
			voxel_size * 2.0
		)
		var channel_radius := maxf(radius * texture.channel_radius_scale, voxel_size * 0.45)
		var channel_end := position + direction * penetration_depth
		result.append({
			"kind": &"capsule",
			"start": position,
			"end": channel_end,
			"radius": channel_radius,
		})
		var exit_distance := _find_exit_distance(position, direction, penetration_depth)
		if exit_distance >= 0.0 and texture.exit_spall_radius_scale > 0.0:
			var exit_position := position + direction * exit_distance
			var spall_depth := maxf(radius * texture.exit_spall_depth_scale, voxel_size)
			result.append({
				"kind": &"tapered_capsule",
				"start": exit_position - direction * spall_depth,
				"end": exit_position + direction * voxel_size,
				"start_radius": channel_radius,
				"end_radius": radius * texture.exit_spall_radius_scale,
			})
	elif texture.ductility >= 0.4 and texture.dent_depth_scale > 0.0:
		var dent_depth := maxf(radius * texture.dent_depth_scale * normalized_energy, voxel_size * 0.25)
		result[0]["end"] = position + direction * minf(dent_depth, radius * 0.9)
		result[0]["end_radius"] = radius * 0.35

	_append_crack_operations(result, position, normal, radius, event.seed, texture)
	return result


func _append_crack_operations(
	operations: Array[Dictionary],
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
		operations.append({
			"kind": &"capsule",
			"start": embedded_start,
			"end": embedded_start + tangent * crack_length,
			"radius": width,
		})


func _apply_operations(
	operations: Array[Dictionary],
	texture: DestructionTextureDefinition,
	seed: int,
	changed_set: Dictionary[Vector3i, bool]
) -> Dictionary:
	if operations.is_empty():
		return {"changed_samples": 0, "changed_sample_bounds": {}}
	# Boolean subtraction by the union of all cutters is max(base, -min(cutter distances)). Fusing
	# the brushes means each touched sample and packed distance is read/written once, even when a
	# brittle material authors several crack capsules.
	var operation_bounds: Array[AABB] = []
	var operation_kinds := PackedInt32Array()
	var operation_starts := PackedVector3Array()
	var operation_ends := PackedVector3Array()
	var characteristic_radii := PackedFloat32Array()
	var secondary_radii := PackedFloat32Array()
	var maximum_cutter_radius := 0.0
	var changed_sample_bounds: Dictionary[Vector3i, PackedInt32Array] = {}
	# Dual Contouring consumes one cell of sign samples plus one additional sample for central-difference
	# normals. Distance edits deeper than this cannot affect current topology or its Hermite data, even
	# though they remain stored for later damage. Excluding them keeps remeshing tied to the visible cut.
	var mesh_influence_band := voxel_size * 2.5
	var combined_bounds := _operation_bounds(operations[0]).grow(narrow_band + voxel_size)
	for operation: Dictionary in operations:
		var bounds_for_operation := _operation_bounds(operation).grow(narrow_band + voxel_size)
		operation_bounds.append(bounds_for_operation)
		var kind := StringName(operation.get("kind", &"sphere"))
		match kind:
			&"capsule":
				operation_kinds.append(1)
				operation_starts.append(operation.get("start", Vector3.ZERO))
				operation_ends.append(operation.get("end", Vector3.ZERO))
				characteristic_radii.append(float(operation.get("radius", 0.0)))
				secondary_radii.append(float(operation.get("radius", 0.0)))
			&"tapered_capsule":
				operation_kinds.append(2)
				operation_starts.append(operation.get("start", Vector3.ZERO))
				operation_ends.append(operation.get("end", Vector3.ZERO))
				characteristic_radii.append(float(operation.get("start_radius", 0.0)))
				secondary_radii.append(float(operation.get("end_radius", 0.0)))
			_:
				operation_kinds.append(0)
				operation_starts.append(operation.get("center", Vector3.ZERO))
				operation_ends.append(operation.get("center", Vector3.ZERO))
				characteristic_radii.append(float(operation.get("radius", 0.0)))
				secondary_radii.append(float(operation.get("radius", 0.0)))
		maximum_cutter_radius = maxf(
			maximum_cutter_radius,
			maxf(characteristic_radii[-1], secondary_radii[-1])
		)
		combined_bounds = combined_bounds.merge(bounds_for_operation)
	var minimum_brick := _brick_for_local_position(combined_bounds.position)
	var maximum_brick := _brick_for_local_position(combined_bounds.end)
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
					ceili((combined_bounds.position.x + half_extents.x) / voxel_size),
					ceili((combined_bounds.position.y + half_extents.y) / voxel_size),
					ceili((combined_bounds.position.z + half_extents.z) / voxel_size)
				) - global_origin
				var grid_maximum := Vector3i(
					floori((combined_bounds.end.x + half_extents.x) / voxel_size),
					floori((combined_bounds.end.y + half_extents.y) / voxel_size),
					floori((combined_bounds.end.z + half_extents.z) / voxel_size)
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
					for sample_y: int in range(grid_minimum.y, grid_maximum.y + 1):
						for sample_x: int in range(grid_minimum.x, grid_maximum.x + 1):
							var sample_coordinate := global_origin + Vector3i(sample_x, sample_y, sample_z)
							var sample_position := global_sample_position(sample_coordinate)
							var previous := (
								brick.get_distance(sample_x, sample_y, sample_z)
								if brick != null
								else base_distance(sample_position)
							)
							# A cutter cannot increase empty-space distance beyond its own radius. This rejects
							# most samples outside a thin wall before any brush/noise evaluation.
							if previous >= maximum_cutter_radius:
								continue
							var cutter_distance := INF
							var warp_noise := 0.0
							if texture.spatial_warp > 0.0:
								warp_noise = (
									SdfMath.deterministic_signed_noise(
										sample_position,
										texture.spatial_warp_frequency,
										seed
									)
									* texture.spatial_warp
								)
							for operation_index: int in range(operations.size()):
								if not operation_bounds[operation_index].has_point(sample_position):
									continue
								var characteristic_radius := maxf(
									characteristic_radii[operation_index],
									secondary_radii[operation_index]
								)
								var brush_distance := 0.0
								match operation_kinds[operation_index]:
									1:
										brush_distance = SdfMath.capsule(
											sample_position,
											operation_starts[operation_index],
											operation_ends[operation_index],
											characteristic_radii[operation_index]
										)
									2:
										brush_distance = SdfMath.tapered_capsule(
											sample_position,
											operation_starts[operation_index],
											operation_ends[operation_index],
											characteristic_radii[operation_index],
											secondary_radii[operation_index]
										)
									_:
										brush_distance = SdfMath.sphere(
											sample_position,
											operation_starts[operation_index],
											characteristic_radii[operation_index]
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
							if brick != null and brick.set_distance(sample_x, sample_y, sample_z, next):
								brick_changed = true
								changed_samples += 1
								if (
									(previous < 0.0) != (next < 0.0)
									or minf(absf(previous), absf(next)) <= mesh_influence_band
								):
									_include_changed_sample(
										changed_sample_bounds,
										coordinate,
										sample_coordinate
									)
				if brick_changed:
					changed_set[coordinate] = true
	return {
		"changed_samples": changed_samples,
		"changed_sample_bounds": changed_sample_bounds,
	}


static func _include_changed_sample(
	bounds_by_chunk: Dictionary[Vector3i, PackedInt32Array],
	coordinate: Vector3i,
	sample: Vector3i
) -> void:
	var bounds: PackedInt32Array = bounds_by_chunk.get(coordinate, PackedInt32Array())
	if bounds.is_empty():
		bounds = PackedInt32Array([sample.x, sample.y, sample.z, sample.x, sample.y, sample.z])
	else:
		bounds[0] = mini(bounds[0], sample.x)
		bounds[1] = mini(bounds[1], sample.y)
		bounds[2] = mini(bounds[2], sample.z)
		bounds[3] = maxi(bounds[3], sample.x)
		bounds[4] = maxi(bounds[4], sample.y)
		bounds[5] = maxi(bounds[5], sample.z)
	bounds_by_chunk[coordinate] = bounds


func _apply_accumulated_damage(
	position: Vector3,
	event: DamageEvent,
	texture: DestructionTextureDefinition,
	normalized_energy: float
) -> Dictionary:
	if texture.damage_accumulation <= 0.0 or normalized_energy <= 0.0:
		return {"changed": false}
	var radius := maxf(event.radius * texture.entry_radius_scale, voxel_size)
	var operation := {
		"kind": &"sphere",
		"center": position,
		"radius": radius,
	}
	var operation_bounds := _operation_bounds(operation).grow(voxel_size)
	var minimum_brick := _brick_for_local_position(operation_bounds.position)
	var maximum_brick := _brick_for_local_position(operation_bounds.end)
	var amount := clampi(roundi(normalized_energy * texture.damage_accumulation * 32.0), 1, 255)
	var changed_set: Dictionary[Vector3i, bool] = {}
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
					for sample_y: int in range(brick.samples_per_axis):
						for sample_x: int in range(brick.samples_per_axis):
							var sample_position := global_sample_position(
								global_origin + Vector3i(sample_x, sample_y, sample_z)
							)
							if SdfMath.sphere(sample_position, position, radius) <= 0.0:
								var previous := brick.get_damage(sample_x, sample_y, sample_z)
								var next := brick.add_damage(sample_x, sample_y, sample_z, amount)
								peak_damage = maxi(peak_damage, next)
								if next != previous:
									changed_samples += 1
									changed_set[coordinate] = true
	var changed_chunks: Array[Vector3i] = []
	for coordinate: Vector3i in changed_set.keys():
		changed_chunks.append(coordinate)
	changed_chunks.sort_custom(_vector3i_less)
	return {
		"changed": changed_samples > 0,
		"changed_samples": changed_samples,
		"changed_chunks": changed_chunks,
		"peak_damage": peak_damage,
	}


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
	for z: int in range(minimum_brick.z, maximum_brick.z + 1):
		for y: int in range(minimum_brick.y, maximum_brick.y + 1):
			for x: int in range(minimum_brick.x, maximum_brick.x + 1):
				var coordinate := Vector3i(x, y, z)
				var brick := _bricks.get(coordinate) as SparseSdfBrick
				if brick == null or not brick.has_damage_channel():
					continue
				var global_origin := coordinate * brick_cells
				for sample_z: int in range(brick.samples_per_axis):
					for sample_y: int in range(brick.samples_per_axis):
						for sample_x: int in range(brick.samples_per_axis):
							var sample_position := global_sample_position(
								global_origin + Vector3i(sample_x, sample_y, sample_z)
							)
							if SdfMath.sphere(sample_position, position, radius) <= 0.0:
								brick.set_damage(sample_x, sample_y, sample_z, 0)


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


func _operation_bounds(operation: Dictionary) -> AABB:
	var kind := StringName(operation.get("kind", &"sphere"))
	if kind == &"capsule" or kind == &"tapered_capsule":
		var start: Vector3 = operation.get("start", Vector3.ZERO)
		var end: Vector3 = operation.get("end", Vector3.ZERO)
		var radius := _operation_radius(operation)
		var minimum := Vector3(
			minf(start.x, end.x),
			minf(start.y, end.y),
			minf(start.z, end.z)
		) - Vector3.ONE * radius
		var maximum := Vector3(
			maxf(start.x, end.x),
			maxf(start.y, end.y),
			maxf(start.z, end.z)
		) + Vector3.ONE * radius
		return AABB(minimum, maximum - minimum)
	var center: Vector3 = operation.get("center", Vector3.ZERO)
	var sphere_radius := _operation_radius(operation)
	return AABB(center - Vector3.ONE * sphere_radius, Vector3.ONE * sphere_radius * 2.0)


func _operation_radius(operation: Dictionary) -> float:
	return maxf(
		float(operation.get("radius", 0.0)),
		maxf(
			float(operation.get("start_radius", 0.0)),
			float(operation.get("end_radius", 0.0))
		)
	)


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
