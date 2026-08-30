extends SceneTree

## Headless mathematical and replay coverage for the universal destruction core. This deliberately
## does not instantiate the game world, so failures identify field/material/meshing contracts before
## projectile, networking, acoustics, or scene ownership can obscure them.

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_damage_event_contract()
	_test_sparse_brick_encoding()
	_test_material_responses_and_replay()
	_test_replicated_damage_accumulation()
	_test_dual_contouring_output()
	_finish()


func _test_damage_event_contract() -> void:
	var event := DamageEvent.from_dict({
		"event_id": 42,
		"sequence": 9,
		"source_kind": &"projectile",
		"source_id": 7,
		"world_position": Vector3(1.23456, 2.34567, 3.45678),
		"normal": Vector3(0.0, 0.0, -8.0),
		"direction": Vector3(0.0, 0.0, 4.0),
		"brush_kind": &"capsule",
		"radius": 0.18,
		"length": 0.7,
		"energy": 5.0,
		"impulse": 2.0,
		"penetration": 0.8,
		"damage_tags": PackedStringArray(["ballistic", "ballistic"]),
		"seed": 123,
		"timestamp_tick": 300,
	})
	var packet := event.to_dict(true)
	var decoded := DamageEvent.from_dict(packet)
	_expect(event.is_valid(), "finite normalized damage event is valid")
	_expect(
		event.normal.is_equal_approx(Vector3(0.0, 0.0, -1.0))
		and event.direction.is_equal_approx(Vector3(0.0, 0.0, 1.0))
		and event.damage_tags.size() == 1,
		"damage event normalizes directions and deduplicates tags"
	)
	_expect(
		decoded.world_position.is_equal_approx(Vector3(1.235, 2.346, 3.457))
		and decoded.sequence == event.sequence
		and decoded.seed == event.seed,
		"network event quantization preserves stable identity and millimetre position"
	)
	_expect(
		DamageEvent.deterministic_seed(&"wall", 4, 7, 11)
		== DamageEvent.deterministic_seed(&"wall", 4, 7, 11),
		"event seed derivation is deterministic"
	)


func _test_sparse_brick_encoding() -> void:
	var brick := SparseSdfBrick.new().configure(Vector3i(1, 2, 3), 4, 0.05, 0.2, 2)
	var values := PackedFloat32Array()
	values.resize(brick.sample_count())
	values.fill(0.2)
	brick.initialize_from_distances(values)
	_expect(
		(brick.encoded_state()["distance_bytes"] as PackedByteArray).is_empty(),
		"uniform narrow-band bricks store one constant instead of a dense sample array"
	)
	_expect(
		brick.set_distance(2, 2, 2, -0.071)
		and absf(brick.get_distance(2, 2, 2) + 0.071) < 0.00002,
		"signed 16-bit packing preserves a changed sample within its quantization step"
	)
	var encoded := brick.encoded_state()
	var restored := SparseSdfBrick.from_encoded_state(encoded)
	_expect(
		restored.checksum() == brick.checksum()
		and is_equal_approx(restored.get_distance(2, 2, 2), brick.get_distance(2, 2, 2)),
		"brick checkpoint round-trip preserves distances and checksum"
	)


func _test_material_responses_and_replay() -> void:
	var event := _impact_event(2.0, 0.18, 0.8, 991)
	var concrete_texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var metal_texture := DestructionMaterialRegistry.profile_for(&"metal")
	var concrete := _wall_volume(concrete_texture.material_index)
	var concrete_replay := _wall_volume(concrete_texture.material_index)
	var metal := _wall_volume(metal_texture.material_index)
	var concrete_result := concrete.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		concrete_texture
	)
	var replay_result := concrete_replay.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		concrete_texture
	)
	var metal_result := metal.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		metal_texture
	)
	_expect(
		bool(concrete_result.get("changed", false))
		and bool(metal_result.get("changed", false)),
		"concrete and metal accept a geometry-producing impact"
	)
	_expect(
		int(concrete_result.get("changed_samples", 0))
		> int(metal_result.get("changed_samples", 0))
		and not bool(metal_result.get("perforated", true)),
		"equal-energy concrete loses a broader brittle volume while metal produces a smaller dent"
	)
	_expect(
		bool(replay_result.get("changed", false))
		and concrete.checksum() == concrete_replay.checksum(),
		"the same material event produces an identical sparse-field checksum"
	)

	var checkpoint := concrete.changed_brick_states()
	var restored := _wall_volume(concrete_texture.material_index)
	_expect(
		restored.apply_checkpoint(concrete.revision, checkpoint)
		and restored.checksum() == concrete.checksum(),
		"changed-brick checkpoint restores the authoritative revision exactly"
	)

	var perforated := _wall_volume(metal_texture.material_index)
	var high_energy := _impact_event(14.0, 0.14, 1.0, 1234)
	var perforation_result := perforated.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		high_energy,
		metal_texture
	)
	_expect(
		bool(perforation_result.get("perforated", false))
		and perforated.sample_distance(Vector3(0.0, 0.0, 0.18)) > 0.0,
		"high-energy metal impact opens a channel through the thin test wall"
	)


func _test_dual_contouring_output() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var volume := _wall_volume(texture.material_index)
	var event := _impact_event(8.0, 0.20, 0.9, 77)
	var result := volume.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		texture
	)
	var changed_chunks: Array[Vector3i] = result.get("changed_chunks", [])
	var render_chunks := volume.expanded_chunk_ring(changed_chunks, 1)
	var triangle_count := 0
	var finite_vertices := true
	var valid_topology := true
	var generated_bounds := AABB()
	var has_generated_bounds := false
	var front_shell_vertices := 0
	var back_shell_vertices := 0
	var expected_shell_depth := volume.half_extents.z - volume.voxel_size * 1.5
	var aligned_triangle_normals := 0
	var opposed_triangle_normals := 0
	var empty_render_chunks := 0
	for coordinate: Vector3i in render_chunks:
		var mesh_result := SdfDualContouringMesher.build_chunk(volume, coordinate)
		var vertices: PackedVector3Array = mesh_result.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = mesh_result.get("indices", PackedInt32Array())
		var normals: PackedVector3Array = mesh_result.get("normals", PackedVector3Array())
		if bool(mesh_result.get("empty", true)):
			empty_render_chunks += 1
		triangle_count += int(mesh_result.get("triangle_count", 0))
		valid_topology = valid_topology and indices.size() % 3 == 0
		for triangle_offset: int in range(0, indices.size(), 3):
			var first_index := indices[triangle_offset]
			var second_index := indices[triangle_offset + 1]
			var third_index := indices[triangle_offset + 2]
			var face_normal := (
				(vertices[second_index] - vertices[first_index]).cross(
					vertices[third_index] - vertices[first_index]
				)
			)
			var authored_normal := (
				normals[first_index] + normals[second_index] + normals[third_index]
			)
			if face_normal.dot(authored_normal) >= 0.0:
				aligned_triangle_normals += 1
			else:
				opposed_triangle_normals += 1
		for vertex: Vector3 in vertices:
			finite_vertices = finite_vertices and vertex.is_finite()
			if not has_generated_bounds:
				generated_bounds = AABB(vertex, Vector3.ZERO)
				has_generated_bounds = true
			else:
				generated_bounds = generated_bounds.expand(vertex)
			if vertex.z >= expected_shell_depth:
				front_shell_vertices += 1
			if vertex.z <= -expected_shell_depth:
				back_shell_vertices += 1
	var state := volume.debug_state()
	_expect(
		triangle_count > 0 and valid_topology and finite_vertices,
		"dual contouring emits finite triangle topology for all affected chunks"
	)
	_expect(
		has_generated_bounds
		and generated_bounds.size.x >= volume.brick_extent * 2.5
		and generated_bounds.size.y >= volume.brick_extent * 2.5
		and generated_bounds.size.z >= volume.size.z * 0.75
		and front_shell_vertices > 8
		and back_shell_vertices > 8,
		"remeshing a bullet impact retains the surrounding wall shell on both exterior faces"
	)
	_expect(
		opposed_triangle_normals > aligned_triangle_normals * 8,
		"generated triangle winding is clockwise relative to the SDF exterior normals"
	)
	_expect(
		empty_render_chunks == 0,
		"every hidden base chunk has replacement shell topology"
	)
	_expect(
		int(state.get("brick_count", 0)) < (
			volume.brick_counts.x * volume.brick_counts.y * volume.brick_counts.z
		),
		"an impact allocates fewer bricks than the complete finite volume"
	)


func _test_replicated_damage_accumulation() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var authority := _wall_volume(texture.material_index)
	var replay := _wall_volume(texture.material_index)
	var event := _impact_event(0.20, 0.16, 0.0, 811)
	var first := authority.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		texture
	)
	var first_replay := replay.apply_damage_event(
		Vector3(0.0, 0.0, -0.2),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		event,
		texture
	)
	_expect(
		bool(first.get("changed", false))
		and not bool(first.get("geometry_changed", true))
		and authority.revision == 1
		and authority.checksum() == replay.checksum()
		and bool(first_replay.get("changed", false)),
		"sub-threshold material fatigue advances and replays revision without remeshing"
	)
	var promoted := false
	for _impact: int in range(100):
		var result := authority.apply_damage_event(
			Vector3(0.0, 0.0, -0.2),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			event,
			texture
		)
		replay.apply_damage_event(
			Vector3(0.0, 0.0, -0.2),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			event,
			texture
		)
		if bool(result.get("geometry_changed", false)):
			promoted = true
			break
	_expect(
		promoted
		and authority.checksum() == replay.checksum()
		and authority.sample_distance(Vector3(0.0, 0.0, -0.18)) > -0.02,
		"repeated weak impacts deterministically promote saturated fatigue into a surface mark"
	)


func _wall_volume(material_index: int) -> SparseSdfVolumeData:
	return SparseSdfVolumeData.new().configure(
		Vector3(4.0, 3.0, 0.4),
		0.08,
		8,
		material_index,
		4.0
	)


func _impact_event(
	energy: float,
	radius: float,
	penetration: float,
	seed: int
) -> DamageEvent:
	return DamageEvent.from_dict({
		"event_id": seed,
		"sequence": seed,
		"source_kind": &"test_projectile",
		"source_id": 1,
		"world_position": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, -1.0),
		"direction": Vector3(0.0, 0.0, 1.0),
		"brush_kind": &"capsule",
		"radius": radius,
		"length": penetration,
		"energy": energy,
		"impulse": energy * 0.1,
		"penetration": penetration,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": seed,
		"timestamp_tick": 1,
	})


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("Universal destruction assertion failed: " + message)


func _finish() -> void:
	if failure_count == 0:
		print("Universal destruction system tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Universal destruction system tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)
