extends SceneTree

## Focused micro-benchmark for the allocation-sensitive SDF path. Timings are diagnostic rather
## than hardware-dependent pass/fail limits; correctness tests remain the regression gate.

const SAMPLE_COUNT := 16


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var event := DamageEvent.from_dict({
		"event_id": 8101,
		"sequence": 8101,
		"source_kind": &"sdf_benchmark",
		"source_id": 1,
		"world_position": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, -1.0),
		"direction": Vector3(0.0, 0.0, 1.0),
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.05,
		"length": 0.75,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 0.75,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 8101,
	})
	var mutation_times := PackedInt64Array()
	var damaged_volume: SparseSdfVolumeData
	var damaged_chunk := Vector3i.ZERO
	for sample_index: int in range(SAMPLE_COUNT):
		var volume := _wall_volume(texture.material_index)
		var started_usec := Time.get_ticks_usec()
		var result := volume.apply_damage_event(
			Vector3(0.0, 0.0, -0.2),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			event,
			texture
		)
		mutation_times.append(Time.get_ticks_usec() - started_usec)
		if sample_index == SAMPLE_COUNT - 1:
			damaged_volume = volume
			var changed_chunks: Array[Vector3i] = result.get("changed_chunks", [])
			if not changed_chunks.is_empty():
				damaged_chunk = changed_chunks[0]
	if damaged_volume == null:
		push_error("SDF performance benchmark could not produce a damaged field")
		quit(1)
		return
	var repeated_volume := _large_wall_volume(texture.material_index)
	var repeated_positions: Array[Vector2] = [
		Vector2(-1.5, -1.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0), Vector2(1.5, -1.0),
		Vector2(-1.5, -0.33), Vector2(-0.5, -0.33), Vector2(0.5, -0.33), Vector2(1.5, -0.33),
		Vector2(-1.5, 0.33), Vector2(-0.5, 0.33), Vector2(0.5, 0.33), Vector2(1.5, 0.33),
		Vector2(-1.5, 1.0), Vector2(-0.5, 1.0), Vector2(0.5, 1.0), Vector2(1.5, 1.0),
	]
	var repeated_times := PackedInt64Array()
	for position_index: int in range(repeated_positions.size()):
		var point := repeated_positions[position_index]
		var repeated_started_usec := Time.get_ticks_usec()
		repeated_volume.apply_damage_event(
			Vector3(point.x, point.y, -0.2),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			event,
			texture
		)
		if position_index > 0:
			repeated_times.append(Time.get_ticks_usec() - repeated_started_usec)
	var scratch_state := repeated_volume.debug_state()
	if (
		int(scratch_state.get("operation_buffer_capacity", 0))
		!= SparseSdfVolumeData.MAX_DAMAGE_OPERATIONS
		or int(scratch_state.get("noise_lattice_growth_count", 999)) > 3
	):
		push_error("SDF persistent scratch buffers were not reused: %s" % [scratch_state])
		quit(1)
		return
	var capture_times := PackedInt64Array()
	var build_times := PackedInt64Array()
	var native_build_times := PackedInt64Array()
	var native_end_to_end_times := PackedInt64Array()
	var combined_times := PackedInt64Array()
	var pooled_mesh_times := PackedInt64Array()
	var snapshot := SdfDualContouringMesher.capture_chunk(damaged_volume, damaged_chunk)
	var pooled_snapshot: Dictionary = {}
	var pooled_result: Dictionary = {}
	var pooled_cell_indices := PackedInt32Array()
	var pooled_corner_distances := PackedFloat32Array()
	var triangle_count := 0
	var native_kernel := SdfDualContouringMesher.create_native_kernel()
	var native_snapshot: Dictionary = {}
	if native_kernel == null:
		push_error("SDF performance benchmark requires the native backend")
		quit(1)
		return
	for _sample_index: int in range(SAMPLE_COUNT):
		var capture_started_usec := Time.get_ticks_usec()
		var captured := SdfDualContouringMesher.capture_chunk(damaged_volume, damaged_chunk)
		capture_times.append(Time.get_ticks_usec() - capture_started_usec)
		var build_started_usec := Time.get_ticks_usec()
		var built := SdfDualContouringMesher.build_chunk_snapshot(snapshot)
		build_times.append(Time.get_ticks_usec() - build_started_usec)
		triangle_count = int(built.get("triangle_count", 0))
		var native_started_usec := Time.get_ticks_usec()
		var native_built: Dictionary = native_kernel.call(&"build_chunk_snapshot", snapshot)
		native_build_times.append(Time.get_ticks_usec() - native_started_usec)
		var reference_indices: PackedInt32Array = built.get("indices", PackedInt32Array())
		var native_indices: PackedInt32Array = native_built.get("indices", PackedInt32Array())
		if native_indices != reference_indices:
			var first_difference := -1
			for offset: int in range(mini(reference_indices.size(), native_indices.size())):
				if reference_indices[offset] != native_indices[offset]:
					first_difference = offset
					break
			push_error(
				"Native SDF benchmark topology diverged from reference (script=%d native=%d first=%d script_slice=%s native_slice=%s script_vertices=%s native_vertices=%s)"
				% [
					reference_indices.size(), native_indices.size(), first_difference,
					reference_indices.slice(maxi(0, first_difference - 8), first_difference + 12),
					native_indices.slice(maxi(0, first_difference - 8), first_difference + 12),
					built.get("vertices", PackedVector3Array()).slice(130, 150),
					native_built.get("vertices", PackedVector3Array()).slice(130, 150),
				]
			)
			quit(1)
			return
		var native_end_to_end_started_usec := Time.get_ticks_usec()
		native_snapshot = SdfDualContouringMesher.capture_chunk(
			damaged_volume,
			damaged_chunk,
			native_snapshot
		)
		native_kernel.call(&"build_chunk_snapshot", native_snapshot)
		if _sample_index > 0:
			native_end_to_end_times.append(
				Time.get_ticks_usec() - native_end_to_end_started_usec
			)
		var combined_started_usec := Time.get_ticks_usec()
		SdfDualContouringMesher.build_chunk_snapshot(captured)
		combined_times.append(Time.get_ticks_usec() - combined_started_usec)
		var pooled_started_usec := Time.get_ticks_usec()
		pooled_snapshot = SdfDualContouringMesher.capture_chunk(
			damaged_volume,
			damaged_chunk,
			pooled_snapshot
		)
		pooled_result = SdfDualContouringMesher.build_chunk_snapshot(
			pooled_snapshot,
			pooled_result,
			pooled_cell_indices,
			pooled_corner_distances
		)
		if _sample_index > 0:
			pooled_mesh_times.append(Time.get_ticks_usec() - pooled_started_usec)
	if triangle_count <= 0:
		push_error("SDF performance benchmark produced no contour triangles")
		quit(1)
		return
	print("SDF PERFORMANCE BENCHMARK")
	print("  first-hit mutation: ", _timing_summary(mutation_times))
	print("  warm mutation:      ", _timing_summary(repeated_times))
	print("  chunk capture:      ", _timing_summary(capture_times))
	print("  chunk mesh:         ", _timing_summary(build_times))
	print("  native chunk mesh:  ", _timing_summary(native_build_times))
	print("  native capture+mesh:", _timing_summary(native_end_to_end_times))
	print("  captured mesh:      ", _timing_summary(combined_times))
	print("  pooled remesh:      ", _timing_summary(pooled_mesh_times))
	print("  triangles:          ", triangle_count)
	print(
		"  persistent scratch: operations=%d noise_values=%d growths=%d"
		% [
			int(scratch_state.get("operation_buffer_capacity", 0)),
			int(scratch_state.get("noise_lattice_capacity", 0)),
			int(scratch_state.get("noise_lattice_growth_count", 0)),
		]
	)
	quit(0)


func _wall_volume(material_index: int) -> SparseSdfVolumeData:
	return SparseSdfVolumeData.new().configure(
		Vector3(2.0, 2.0, 0.4),
		0.08,
		8,
		material_index,
		4.0
	)


func _large_wall_volume(material_index: int) -> SparseSdfVolumeData:
	return SparseSdfVolumeData.new().configure(
		Vector3(4.0, 3.0, 0.4),
		0.08,
		8,
		material_index,
		4.0
	)


func _timing_summary(values: PackedInt64Array) -> String:
	var ordered := values.duplicate()
	ordered.sort()
	var p95_index := mini(ceili(float(ordered.size()) * 0.95) - 1, ordered.size() - 1)
	return "median=%dus p95=%dus min=%dus" % [ordered[ordered.size() / 2], ordered[p95_index], ordered[0]]
