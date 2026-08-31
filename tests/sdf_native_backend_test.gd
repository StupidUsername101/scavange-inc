extends SceneTree

## Native/GDScript contract and geometry parity gate. The fallback remains the reference so a native
## optimization cannot silently change winding, crack ownership, or serialized world behavior.

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var kernel := SdfDualContouringMesher.create_native_kernel()
	_expect(kernel != null, "native SDF kernel is registered")
	if kernel == null:
		_finish()
		return
	var texture := DestructionMaterialRegistry.profile_for(&"metal")
	var volume := SparseSdfVolumeData.new().configure(
		Vector3(2.0, 2.0, 0.4), 0.08, 8, texture.material_index, 4.0
	)
	var scripted_volume := SparseSdfVolumeData.new().configure(
		Vector3(2.0, 2.0, 0.4), 0.08, 8, texture.material_index, 4.0
	)
	scripted_volume.prefer_native_backend = false
	var event := DamageEvent.from_dict({
		"event_id": 9821,
		"sequence": 9821,
		"source_kind": &"native_parity",
		"world_position": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, -1.0),
		"direction": Vector3(0.0, 0.0, 1.0),
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.06,
		"length": 0.7,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 0.7,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 9821,
	})
	var damage := volume.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		texture
	)
	var scripted_damage := scripted_volume.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		texture
	)
	if volume.checksum() != scripted_volume.checksum():
		_print_brick_difference(volume.changed_brick_states(), scripted_volume.changed_brick_states())
	_expect(
		volume.checksum() == scripted_volume.checksum()
		and volume.changed_brick_states() == scripted_volume.changed_brick_states(),
		"native packed-brick mutation is byte-identical to scripted reference"
	)
	_expect(
		int(damage.get("changed_samples", -1)) == int(scripted_damage.get("changed_samples", -2))
		and damage.get("changed_chunks", []) == scripted_damage.get("changed_chunks", [])
		and damage.get("changed_sample_minimum", Vector3i.ZERO)
			== scripted_damage.get("changed_sample_minimum", Vector3i.ONE)
		and damage.get("changed_sample_maximum", Vector3i.ZERO)
			== scripted_damage.get("changed_sample_maximum", Vector3i.ONE),
		"native mutation reports identical dirty chunks and surface bounds"
	)
	_test_mutation_profiles()
	_test_ambiguous_contour_parity(kernel)
	var changed_chunks: Array[Vector3i] = damage.get("changed_chunks", [])
	_expect(not changed_chunks.is_empty(), "parity fixture changes at least one chunk")
	if changed_chunks.is_empty():
		_finish()
		return
	var cached_snapshot := SdfDualContouringMesher.capture_chunk(volume, changed_chunks[0])
	volume.prefer_native_backend = false
	var portable_snapshot := SdfDualContouringMesher.capture_chunk(volume, changed_chunks[0])
	volume.prefer_native_backend = true
	_print_sample_difference(cached_snapshot, portable_snapshot)
	_expect(
		cached_snapshot.get("sample_distances", PackedFloat32Array())
		== portable_snapshot.get("sample_distances", PackedFloat32Array()),
		"persistent native field capture is sample-identical to sparse brick traversal"
	)
	for coordinate: Vector3i in changed_chunks:
		var snapshot := SdfDualContouringMesher.capture_chunk(volume, coordinate)
		var scripted := SdfDualContouringMesher.build_chunk_snapshot(snapshot)
		var native := kernel.call(&"build_chunk_snapshot", snapshot) as Dictionary
		_compare_chunk(scripted, native, coordinate, volume.voxel_size)
	var job := SdfChunkBuildJob.new().capture(volume, changed_chunks[0])
	_expect(job.uses_native_backend(), "production chunk jobs select native backend")
	job.execute()
	_expect(bool(job.result.get("native_backend", false)), "production result identifies native path")
	var fallback_job := SdfChunkBuildJob.new().capture(volume, changed_chunks[0])
	fallback_job.native_kernel = null
	fallback_job.execute()
	_expect(
		not bool(fallback_job.result.get("native_backend", false))
		and fallback_job.result.get("indices", PackedInt32Array())
			== job.result.get("indices", PackedInt32Array()),
		"missing platform binary falls back to identical scripted worker topology"
	)
	_finish()


func _test_ambiguous_contour_parity(kernel: Object) -> void:
	# Regression seed from randomized structural fuzzing: the original one-vertex cell collapsed two
	# contour cycles into a four-face branch. Exercise every chunk so the native fast path cannot pass
	# simple-hole parity while diverging on the topology that motivated manifold clustering.
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var volume := SparseSdfVolumeData.new().configure(
		Vector3(4.0, 3.0, 0.4), 0.08, 8, texture.material_index, 4.0
	)
	var random := RandomNumberGenerator.new()
	random.seed = 47097
	for impact_index: int in range(5):
		var x := random.randf_range(-0.86, 0.86)
		var y := random.randf_range(-0.86, 0.86)
		match impact_index:
			1: x = -0.36 + random.randf_range(-0.025, 0.025)
			2: x = 0.82 + random.randf_range(-0.02, 0.02)
			3: y = -0.36 + random.randf_range(-0.025, 0.025)
			4: y = 0.82 + random.randf_range(-0.02, 0.02)
		var direction := Vector3(
			random.randf_range(-0.18, 0.18),
			random.randf_range(-0.18, 0.18),
			1.0
		).normalized()
		var seed := 47097 + impact_index
		var event := DamageEvent.from_dict({
			"event_id": seed,
			"sequence": seed,
			"source_kind": &"ambiguous_contour_parity",
			"world_position": Vector3.ZERO,
			"normal": Vector3.FORWARD,
			"direction": direction,
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.05,
			"length": 0.75,
			"energy": 16.0,
			"impulse": 1.6,
			"penetration": 0.75,
			"damage_tags": PackedStringArray(["ballistic"]),
			"seed": seed,
		})
		volume.apply_damage_event(
			Vector3(x, y, -volume.half_extents.z),
			direction,
			Vector3.FORWARD,
			event,
			texture
		)
	var parity := true
	for z: int in range(volume.brick_counts.z):
		for y: int in range(volume.brick_counts.y):
			for x: int in range(volume.brick_counts.x):
				var coordinate := Vector3i(x, y, z)
				var snapshot := SdfDualContouringMesher.capture_chunk(volume, coordinate)
				var scripted := SdfDualContouringMesher.build_chunk_snapshot(snapshot)
				var native := kernel.call(&"build_chunk_snapshot", snapshot) as Dictionary
				parity = (
					scripted.get("indices", PackedInt32Array())
					== native.get("indices", PackedInt32Array())
					and scripted.get("vertices", PackedVector3Array()).size()
					== native.get("vertices", PackedVector3Array()).size()
					and parity
				)
	_expect(parity, "ambiguous overlapping-crater topology is identical in native and portable paths")


func _print_sample_difference(cached_snapshot: Dictionary, portable_snapshot: Dictionary) -> void:
	var cached: PackedFloat32Array = cached_snapshot.get(
		"sample_distances",
		PackedFloat32Array()
	)
	var portable: PackedFloat32Array = portable_snapshot.get(
		"sample_distances",
		PackedFloat32Array()
	)
	if cached == portable:
		return
	var side := int(cached_snapshot.get("sample_grid_size", 0))
	for index: int in range(mini(cached.size(), portable.size())):
		if cached[index] == portable[index]:
			continue
		var z: int = index / (side * side)
		var row_remainder := index - z * side * side
		var y: int = row_remainder / side
		var x := row_remainder - y * side
		var local_sample := Vector3i(x, y, z) - Vector3i.ONE * 2
		var global_sample: Vector3i = (
			cached_snapshot.get("chunk_global_cell_origin", Vector3i.ZERO) + local_sample
		)
		print(
			"CACHED SAMPLE DIFF index=", index,
			" local=", local_sample,
			" global=", global_sample,
			" cached=", cached[index],
			" portable=", portable[index]
		)
		return


func _test_mutation_profiles() -> void:
	var surfaces: Array[StringName] = [&"concrete", &"wood", &"stone", &"soil"]
	for surface: StringName in surfaces:
		var texture := DestructionMaterialRegistry.profile_for(surface)
		var native_volume := SparseSdfVolumeData.new().configure(
			Vector3(2.0, 2.0, 0.4), 0.08, 8, texture.material_index, 4.0
		)
		var scripted_volume := SparseSdfVolumeData.new().configure(
			Vector3(2.0, 2.0, 0.4), 0.08, 8, texture.material_index, 4.0
		)
		scripted_volume.prefer_native_backend = false
		var results_match := true
		for impact_index: int in range(2):
			var seed := 11000 + surfaces.find(surface) * 10 + impact_index
			var event := DamageEvent.from_dict({
				"event_id": seed,
				"sequence": seed,
				"source_kind": &"native_profile_parity",
				"world_position": Vector3.ZERO,
				"normal": Vector3(0.0, 0.0, -1.0),
				"direction": Vector3(0.0, 0.0, 1.0),
				"brush_kind": DamageEvent.BRUSH_CAPSULE,
				"radius": 0.06,
				"length": 0.75,
				"energy": 16.0,
				"impulse": 3.0,
				"penetration": 0.75,
				"damage_tags": PackedStringArray(["ballistic"]),
				"seed": seed,
			})
			var position := Vector3(-0.15 + impact_index * 0.3, 0.1, -0.2)
			native_volume.apply_damage_event(
				position, Vector3.BACK, Vector3.FORWARD, event, texture
			)
			scripted_volume.apply_damage_event(
				position, Vector3.BACK, Vector3.FORWARD, event, texture
			)
			var impact_matches := (
				native_volume.checksum() == scripted_volume.checksum()
				and native_volume.changed_brick_states() == scripted_volume.changed_brick_states()
			)
			if not impact_matches:
				print("PROFILE MUTATION DIFF surface=", surface, " impact=", impact_index)
				_print_brick_difference(
					native_volume.changed_brick_states(),
					scripted_volume.changed_brick_states()
				)
			results_match = impact_matches and results_match
		_expect(
			results_match,
			"%s multi-operation/repeated native mutation remains byte-identical" % surface
		)


func _compare_chunk(scripted: Dictionary, native: Dictionary, coordinate: Vector3i, voxel: float) -> void:
	var scripted_vertices: PackedVector3Array = scripted.get("vertices", PackedVector3Array())
	var native_vertices: PackedVector3Array = native.get("vertices", PackedVector3Array())
	var scripted_normals: PackedVector3Array = scripted.get("normals", PackedVector3Array())
	var native_normals: PackedVector3Array = native.get("normals", PackedVector3Array())
	var scripted_indices: PackedInt32Array = scripted.get("indices", PackedInt32Array())
	var native_indices: PackedInt32Array = native.get("indices", PackedInt32Array())
	var first_index_mismatch := -1
	if scripted_indices.size() == native_indices.size():
		for index: int in range(scripted_indices.size()):
			if scripted_indices[index] != native_indices[index]:
				first_index_mismatch = index
				break
	if first_index_mismatch >= 0:
		var diagnostic_start := maxi(first_index_mismatch - 5, 0)
		var diagnostic_end := mini(first_index_mismatch + 7, scripted_indices.size())
		print(
			"INDEX DIAGNOSTIC scripted=", scripted_indices.slice(diagnostic_start, diagnostic_end),
			" native=", native_indices.slice(diagnostic_start, diagnostic_end)
		)
	_expect(
		scripted_indices == native_indices,
		"chunk %s native topology and clockwise winding match reference (sizes=%d/%d first=%d)"
		% [coordinate, scripted_indices.size(), native_indices.size(), first_index_mismatch]
	)
	_expect(
		scripted_vertices.size() == native_vertices.size()
		and scripted_normals.size() == native_normals.size(),
		"chunk %s native packed attribute counts match reference" % coordinate
	)
	if scripted_vertices.size() != native_vertices.size():
		return
	var maximum_position_error := 0.0
	var minimum_normal_dot := 1.0
	for index: int in range(scripted_vertices.size()):
		maximum_position_error = maxf(
			maximum_position_error,
			scripted_vertices[index].distance_to(native_vertices[index])
		)
		minimum_normal_dot = minf(
			minimum_normal_dot,
			scripted_normals[index].dot(native_normals[index])
		)
	_expect(
		maximum_position_error <= voxel * 0.001 and minimum_normal_dot >= 0.999,
		"chunk %s native feature-point output matches reference (position=%f normal_dot=%f)"
		% [coordinate, maximum_position_error, minimum_normal_dot]
	)


func _print_brick_difference(native_states: Array[Dictionary], scripted_states: Array[Dictionary]) -> void:
	print("MUTATION CHECKSUM native/scripted state counts=", native_states.size(), "/", scripted_states.size())
	for state_index: int in range(mini(native_states.size(), scripted_states.size())):
		var native_state := native_states[state_index]
		var scripted_state := scripted_states[state_index]
		var native_bytes: PackedByteArray = native_state.get("distance_bytes", PackedByteArray())
		var scripted_bytes: PackedByteArray = scripted_state.get("distance_bytes", PackedByteArray())
		for byte_index: int in range(mini(native_bytes.size(), scripted_bytes.size())):
			if native_bytes[byte_index] != scripted_bytes[byte_index]:
				print(
					"first brick byte mismatch coordinate=", native_state.get("coordinate"),
					" byte=", byte_index,
					" native=", native_bytes[byte_index],
					" scripted=", scripted_bytes[byte_index]
				)
				return
func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	_failures += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("SDF NATIVE BACKEND TEST PASSED")
		quit(0)
	else:
		push_error("SDF NATIVE BACKEND TEST FAILED: %d failure(s)" % _failures)
		quit(1)
