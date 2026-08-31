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
	_test_spatial_warp_continuity()
	_test_contour_triangle_orientation_score()
	_test_high_warp_contour_quality()
	_test_production_metal_perforation_quality()
	_test_production_profile_artifact_stress()
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


func _test_spatial_warp_continuity() -> void:
	var frequency := 7.0
	var boundary := 1.0 / frequency
	var epsilon := 0.00001
	var left := SdfMath.deterministic_signed_noise(
		Vector3(boundary - epsilon, 0.037, -0.091),
		frequency,
		771
	)
	var right := SdfMath.deterministic_signed_noise(
		Vector3(boundary + epsilon, 0.037, -0.091),
		frequency,
		771
	)
	var deterministic_repeat := SdfMath.deterministic_signed_noise(
		Vector3(boundary - epsilon, 0.037, -0.091),
		frequency,
		771
	)
	_expect(
		absf(left - right) < 0.001 and is_equal_approx(left, deterministic_repeat),
		"spatial destruction warp stays deterministic and continuous across lattice cells"
	)


func _test_contour_triangle_orientation_score() -> void:
	var vertices := PackedVector3Array([
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.UP,
	])
	var normals := PackedVector3Array([
		Vector3.BACK,
		Vector3.BACK,
		Vector3.BACK,
	])
	var clockwise_score := SdfDualContouringMesher._triangle_alignment(
		vertices,
		normals,
		0,
		2,
		1
	)
	var inside_out_score := SdfDualContouringMesher._triangle_alignment(
		vertices,
		normals,
		0,
		1,
		2
	)
	_expect(
		clockwise_score > 0.99 and inside_out_score < -0.99,
		"dual-quad scoring rejects an inside-out fold instead of treating orientation as quality"
	)


func _test_high_warp_contour_quality() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete").duplicate(true)
	texture.spatial_warp = 0.8
	texture.crack_count = 0
	texture.sanitize()
	var volume := _wall_volume(texture.material_index)
	var impact_points: Array[Vector2] = [
		Vector2(-0.35, 0.22),
		Vector2(0.25, 0.30),
		Vector2(-0.12, -0.30),
		Vector2(0.40, -0.15),
	]
	var every_impact_changed := true
	for impact_index: int in range(impact_points.size()):
		var point := impact_points[impact_index]
		var event := _impact_event(16.0, 0.05, 0.75, 1701 + impact_index)
		var result := volume.apply_damage_event(
			Vector3(point.x, point.y, -0.2),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			event,
			texture
		)
		every_impact_changed = bool(result.get("changed", false)) and every_impact_changed
	var topology := _full_volume_topology(volume)
	_expect(
			every_impact_changed
			and int(topology.get("triangle_count", 0)) > 0
			and int(topology.get("component_count", 0)) >= 1
		and int(topology.get("non_manifold_edges", 1)) == 0
		and int(topology.get("wrong_winding", 1)) == 0
		and bool(topology.get("local_edges", false)),
		"repeated maximum-warp impacts remain closed local contours without branched or open sheets: %s"
		% [topology]
	)


func _test_production_metal_perforation_quality() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"metal")
	var volume := SparseSdfVolumeData.new().configure(
		Vector3(4.0, 3.0, 0.45),
		0.06,
		12,
		texture.material_index,
		4.0
	)
	# This covers the shipped wall's resolution and the isolated/nearby/boundary perforations visible
	# in the field test. It is intentionally not a toy one-hole contour.
	var impact_points: Array[Vector2] = [
		Vector2(-1.55, 1.12),
		Vector2(-0.78, 0.70),
		Vector2(0.36, 1.00),
		Vector2(1.38, 0.64),
		Vector2(-1.78, -0.18),
		Vector2(-0.92, -0.75),
		Vector2(0.12, -0.92),
		Vector2(0.82, -0.64),
		Vector2(1.50, -0.10),
		Vector2(1.75, 1.36),
	]
	var every_impact_changed := true
	for impact_index: int in range(impact_points.size()):
		var point := impact_points[impact_index]
		var result := volume.apply_damage_event(
			Vector3(point.x, point.y, -volume.half_extents.z),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			_impact_event(16.0, 0.05, 0.75, 2900 + impact_index),
			texture
		)
		every_impact_changed = every_impact_changed and bool(result.get("changed", false))
	var topology := _full_volume_topology(volume)
	_expect(
		every_impact_changed
		and int(topology.get("triangle_count", 0)) > 0
		and int(topology.get("component_count", 0)) == 1
		and int(topology.get("non_manifold_edges", 1)) == 0
		and int(topology.get("wrong_winding", 1)) == 0
		and int(topology.get("degenerate_triangles", 1)) == 0
		and bool(topology.get("local_edges", false))
		and float(topology.get("maximum_surface_error", INF)) <= volume.voxel_size * 1.25,
		"production-resolution repeated metal perforations remain a closed local contour without flaps: %s"
		% [topology]
	)


func _test_production_profile_artifact_stress() -> void:
	# These are the shipped structural destruction profiles. Soil is granular/terrain data and is not
	# currently attached to a destructible structure; it needs a terrain-specific topology contract
	# rather than pretending a thin wall is representative of it.
	var surfaces: Array[StringName] = [&"concrete", &"metal", &"wood", &"stone"]
	var first_failure: Dictionary = {}
	var checked_fixtures := 0
	for surface: StringName in surfaces:
		var texture := DestructionMaterialRegistry.profile_for(surface)
		for fixture_index: int in range(8):
			var fixture_seed := 47000 + surfaces.find(surface) * 1000 + fixture_index * 97
			var random := RandomNumberGenerator.new()
			random.seed = fixture_seed
			var volume := _wall_volume(texture.material_index)
			var changed := true
			for impact_index: int in range(5):
				var x := random.randf_range(-0.86, 0.86)
				var y := random.randf_range(-0.86, 0.86)
				match impact_index:
					1:
						x = -0.36 + random.randf_range(-0.025, 0.025)
					2:
						x = 0.82 + random.randf_range(-0.02, 0.02)
					3:
						y = -0.36 + random.randf_range(-0.025, 0.025)
					4:
						y = 0.82 + random.randf_range(-0.02, 0.02)
				var direction := Vector3(
					random.randf_range(-0.18, 0.18),
					random.randf_range(-0.18, 0.18),
					1.0
				).normalized()
				var result := volume.apply_damage_event(
					Vector3(x, y, -volume.half_extents.z),
					direction,
					Vector3.FORWARD,
					_impact_event(16.0, 0.05, 0.75, fixture_seed + impact_index),
					texture
				)
				changed = changed and bool(result.get("changed", false))
			var topology := _full_volume_topology(volume)
			checked_fixtures += 1
			if (
				not changed
				or int(topology.get("component_count", 0)) != 1
				or int(topology.get("non_manifold_edges", 0)) != 0
				or int(topology.get("wrong_winding", 0)) != 0
				or int(topology.get("degenerate_triangles", 0)) != 0
				or not bool(topology.get("local_edges", false))
			):
				first_failure = {
					"surface": surface,
					"seed": fixture_seed,
					"topology": topology,
				}
				break
		if not first_failure.is_empty():
			break
	_expect(
		first_failure.is_empty(),
		"production destruction profiles survive %d randomized seam/edge/grazing fixtures without artifact topology: %s"
		% [checked_fixtures, first_failure]
	)


func _full_volume_topology(volume: SparseSdfVolumeData) -> Dictionary:
	var position_to_id: Dictionary[Vector3i, int] = {}
	var id_to_position: Dictionary[int, Vector3] = {}
	var adjacency: Dictionary[int, Dictionary] = {}
	var edge_counts: Dictionary[Vector2i, int] = {}
	var edge_incidents: Dictionary[Vector2i, Array] = {}
	var next_vertex_id := 0
	var triangle_count := 0
	var wrong_winding := 0
	var wrong_winding_samples: Array[Dictionary] = []
	var degenerate_triangles := 0
	var local_edges := true
	var maximum_surface_error := 0.0
	var quantization := maxf(volume.voxel_size * 0.0001, 0.000001)
	var maximum_edge_squared := pow(volume.voxel_size * 3.01, 2.0)
	for z: int in range(volume.brick_counts.z):
		for y: int in range(volume.brick_counts.y):
			for x: int in range(volume.brick_counts.x):
				var mesh_result := SdfDualContouringMesher.build_chunk(
					volume,
					Vector3i(x, y, z)
				)
				var vertices: PackedVector3Array = mesh_result.get(
					"vertices",
					PackedVector3Array()
				)
				var indices: PackedInt32Array = mesh_result.get(
					"indices",
					PackedInt32Array()
				)
				var normals: PackedVector3Array = mesh_result.get(
					"normals",
					PackedVector3Array()
				)
				var local_ids := PackedInt32Array()
				local_ids.resize(vertices.size())
				for local_index: int in range(vertices.size()):
					var vertex := vertices[local_index]
					var key := Vector3i(
						roundi(vertex.x / quantization),
						roundi(vertex.y / quantization),
						roundi(vertex.z / quantization)
					)
					var vertex_id: int = position_to_id.get(key, -1)
					if vertex_id < 0:
						vertex_id = next_vertex_id
						next_vertex_id += 1
						position_to_id[key] = vertex_id
						id_to_position[vertex_id] = vertex
						adjacency[vertex_id] = {}
					local_ids[local_index] = vertex_id
				for index_offset: int in range(0, indices.size(), 3):
					triangle_count += 1
					var local_a := indices[index_offset]
					var local_b := indices[index_offset + 1]
					var local_c := indices[index_offset + 2]
					if (
						local_ids[local_a] == local_ids[local_b]
						or local_ids[local_b] == local_ids[local_c]
						or local_ids[local_c] == local_ids[local_a]
					):
						degenerate_triangles += 1
					var face_normal := (
						(vertices[local_b] - vertices[local_a]).cross(
							vertices[local_c] - vertices[local_a]
						)
					)
					var authored_normal := normals[local_a] + normals[local_b] + normals[local_c]
					if (
						face_normal.length_squared() > 0.0000000001
						and authored_normal.length_squared() > 0.000001
						and face_normal.dot(authored_normal) >= 0.0
					):
						wrong_winding += 1
						if wrong_winding_samples.size() < 8:
							wrong_winding_samples.append({
								"chunk": Vector3i(x, y, z),
								"triangle": PackedVector3Array([
									vertices[local_a], vertices[local_b], vertices[local_c]
								]),
								"normals": PackedVector3Array([
									normals[local_a], normals[local_b], normals[local_c]
								]),
								"dot": face_normal.dot(authored_normal),
							})
					var triangle_centroid := (
						vertices[local_a] + vertices[local_b] + vertices[local_c]
					) / 3.0
					maximum_surface_error = maxf(
						maximum_surface_error,
						absf(volume.sample_distance(triangle_centroid))
					)
					local_edges = (
						vertices[local_a].distance_squared_to(vertices[local_b])
						<= maximum_edge_squared
						and vertices[local_b].distance_squared_to(vertices[local_c])
						<= maximum_edge_squared
						and vertices[local_c].distance_squared_to(vertices[local_a])
						<= maximum_edge_squared
						and local_edges
					)
					_register_topology_edge(local_ids[local_a], local_ids[local_b], adjacency, edge_counts)
					_register_topology_edge(local_ids[local_b], local_ids[local_c], adjacency, edge_counts)
					_register_topology_edge(local_ids[local_c], local_ids[local_a], adjacency, edge_counts)
					var incident := {
						"chunk": Vector3i(x, y, z),
						"local_indices": Vector3i(local_a, local_b, local_c),
						"triangle": PackedVector3Array([
							vertices[local_a], vertices[local_b], vertices[local_c]
						]),
					}
					_register_edge_incident(local_ids[local_a], local_ids[local_b], incident, edge_incidents)
					_register_edge_incident(local_ids[local_b], local_ids[local_c], incident, edge_incidents)
					_register_edge_incident(local_ids[local_c], local_ids[local_a], incident, edge_incidents)
	var non_manifold_edges := 0
	var non_manifold_samples: Array[Dictionary] = []
	var edge_count_histogram: Dictionary[int, int] = {}
	for edge_value: Variant in edge_counts.keys():
		var edge := edge_value as Vector2i
		var count := int(edge_counts[edge])
		edge_count_histogram[count] = edge_count_histogram.get(count, 0) + 1
		if count != 2:
			non_manifold_edges += 1
			if non_manifold_samples.size() < 16:
				non_manifold_samples.append({
					"count": count,
					"first": id_to_position.get(edge.x, Vector3.ZERO),
					"second": id_to_position.get(edge.y, Vector3.ZERO),
					"incidents": edge_incidents.get(edge, []),
				})
	var component_count := 0
	var component_vertex_counts := PackedInt32Array()
	var visited: Dictionary[int, bool] = {}
	for start: int in adjacency.keys():
		if visited.has(start):
			continue
		component_count += 1
		var component_vertex_count := 0
		var pending: Array[int] = [start]
		visited[start] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			component_vertex_count += 1
			var neighbors: Dictionary = adjacency[current]
			for neighbor: int in neighbors.keys():
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				pending.append(neighbor)
		component_vertex_counts.append(component_vertex_count)
	return {
		"triangle_count": triangle_count,
		"component_count": component_count,
		"component_vertex_counts": component_vertex_counts,
		"non_manifold_edges": non_manifold_edges,
		"non_manifold_samples": non_manifold_samples,
		"edge_count_histogram": edge_count_histogram,
		"degenerate_triangles": degenerate_triangles,
		"wrong_winding": wrong_winding,
		"wrong_winding_samples": wrong_winding_samples,
		"local_edges": local_edges,
		"maximum_surface_error": maximum_surface_error,
	}


func _register_topology_edge(
	first: int,
	second: int,
	adjacency: Dictionary[int, Dictionary],
	edge_counts: Dictionary[Vector2i, int]
) -> void:
	var minimum := mini(first, second)
	var maximum := maxi(first, second)
	var edge := Vector2i(minimum, maximum)
	edge_counts[edge] = edge_counts.get(edge, 0) + 1
	adjacency[first][second] = true
	adjacency[second][first] = true


func _register_edge_incident(
	first: int,
	second: int,
	incident: Dictionary,
	edge_incidents: Dictionary[Vector2i, Array]
) -> void:
	var edge := Vector2i(mini(first, second), maxi(first, second))
	if not edge_incidents.has(edge):
		edge_incidents[edge] = []
	edge_incidents[edge].append(incident)


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
