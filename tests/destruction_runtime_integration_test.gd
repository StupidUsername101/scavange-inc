extends SceneTree

## Runtime seam coverage for the opt-in destruction slice: node construction, authoritative event
## canonicalization, chunk mesh/collision replacement, replay, checkpoint recovery, spatial bounds,
## and the real projectile adapter. The mathematical field has its own faster unit test.

var assertion_count := 0
var failure_count := 0
var test_root: Node3D
var committed_event: DamageEvent


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	test_root.name = "DestructionRuntimeTest"
	root.add_child(test_root)
	await process_frame
	await _test_volume_replay_and_collision_swap()
	_test_spatial_bounds_registration()
	_test_local_acoustic_invalidation()
	await _test_projectile_routing()
	await _test_service_pistol_routing()
	await _test_live_server_world_pistol_routing()
	_finish()


func _test_volume_replay_and_collision_swap() -> void:
	var server_volume := _make_volume(&"runtime_replay_wall", Vector3(-2.0, 1.5, -4.0), true, true)
	var client_volume := _make_volume(&"runtime_replay_wall", Vector3(-2.0, 1.5, -4.0), false, false)
	server_volume.damage_committed.connect(_capture_committed_event)
	await physics_frame
	_expect(
		int(server_volume.debug_state().get("generated_bodies", -1)) == 0
		and server_volume.get_child_count() > 0,
		"an untouched runtime volume starts with cheap base chunks"
	)

	var world_hit := server_volume.to_global(Vector3(0.0, 0.0, 0.2))
	var authored_event := DamageEvent.from_dict({
		"event_id": 1001,
		"sequence": 12,
		"source_kind": &"runtime_test",
		"source_id": 44,
		"world_position": world_hit + Vector3(0.00041, 0.00039, 0.00037),
		"normal": Vector3(0.0, 0.0, 1.0),
		"direction": Vector3(0.0, 0.0, -1.0),
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": BallisticProjectileDefinition.DEFAULT_DESTRUCTION_RADIUS,
		"length": 1.0,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 1.0,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 991,
	})
	var result := server_volume.apply_authoritative_damage_event(authored_event)
	_expect(
		bool(result.get("changed", false))
		and server_volume.field.revision == 1
		and committed_event != null,
		"an authoritative event commits one sparse-field revision"
	)
	_expect(
		committed_event.world_position == DamageEvent.from_dict(
			authored_event.to_dict(true)
		).world_position
		and committed_event.seed == DamageEvent.deterministic_seed(
			server_volume.volume_id,
			authored_event.sequence,
			authored_event.source_id,
			authored_event.seed
		),
		"authority evaluates the same quantized, volume-seeded event sent to clients"
	)
	var pass_through := ServerProjectile.new()
	test_root.add_child(pass_through)
	_configure_test_projectile(pass_through, 1002, Vector3(-2.0, 1.5, 0.0))
	pass_through.server_physics_tick(0.1)
	_expect(
		not pass_through.resolved and pass_through.global_position.z < -6.0,
		"a following swept projectile rejects stale box collision over an immediate SDF hole"
	)
	pass_through.queue_free()

	for _frame: int in range(180):
		var pending_state := server_volume.debug_state()
		if (
			int(pending_state.get("queued_chunks", 0)) == 0
			and int(pending_state.get("active_chunk_jobs", 0)) == 0
		):
			break
		await process_frame
	await physics_frame
	var runtime_state := server_volume.debug_state()
	print("Destruction runtime metrics: ", runtime_state)
	_expect(
		int(runtime_state.get("rebuild_count", 0)) > 0
		and int(runtime_state.get("generated_visuals", 0)) > 0
		and int(runtime_state.get("generated_bodies", 0)) > 0,
		"edited chunks replace their box render and collision with generated SDF topology"
	)
	_expect(
		int(runtime_state.get("generated_visuals", 0))
		< int(runtime_state.get("rebuild_count", 0))
		and int(runtime_state.get("generated_bodies", 0))
		== int(runtime_state.get("generated_visuals", 0)),
		"unchanged seam-ring chunks retain their compact base render and collision"
	)
	_expect(
		_generated_surface_preserves_authored_material(server_volume),
		"generated concrete keeps the base material's sRGB, roughness, and metallic contract"
	)
	_expect(
		int(runtime_state.get("committed_events", 0)) == 1
		and int(runtime_state.get("event_apply_max_usec", 0)) > 0
		and int(runtime_state.get("rebuild_max_usec", 0)) > 0
		and int(runtime_state.get("maximum_queue_depth", 0)) > 0,
		"runtime diagnostics expose event, remesh, and backlog costs instead of hiding degradation"
	)
	_expect(
		server_volume.field.sample_distance(Vector3.ZERO) > 0.0,
		"the high-energy impact leaves an actual air channel through the wall"
	)
	var intact_shell_query := PhysicsRayQueryParameters3D.create(
		server_volume.to_global(Vector3(0.52, 0.0, 1.0)),
		server_volume.to_global(Vector3(0.52, 0.0, -1.0))
	)
	intact_shell_query.collide_with_areas = false
	var intact_shell_hit := server_volume.get_world_3d().direct_space_state.intersect_ray(
		intact_shell_query
	)
	var intact_shell_collider := intact_shell_hit.get("collider") as Node
	_expect(
		not intact_shell_hit.is_empty()
		and intact_shell_collider != null
		and intact_shell_collider.has_method("apply_damage_event"),
		"generated clockwise shell faces remain solid away from the bullet channel"
	)

	var replay_result := client_volume.apply_replicated_damage_event(committed_event, 0)
	client_volume.flush_pending_rebuilds()
	_expect(
		bool(replay_result.get("changed", false))
		and client_volume.field.checksum() == server_volume.field.checksum(),
		"client replay produces the authoritative sparse-field checksum"
	)
	var duplicate_result := client_volume.apply_replicated_damage_event(committed_event, 0)
	_expect(
		StringName(duplicate_result.get("reason", &"")) == &"revision_gap"
		and client_volume.field.revision == 1,
		"duplicate or out-of-order edits fail closed and request checkpoint recovery"
	)
	var checkpoint_volume := _make_volume(
		&"runtime_replay_wall",
		Vector3(-2.0, 1.5, -4.0),
		false,
		false
	)
	_expect(
		checkpoint_volume.apply_checkpoint(server_volume.checkpoint())
		and checkpoint_volume.field.checksum() == server_volume.field.checksum(),
		"a late client can restore the volume from a changed-brick checkpoint"
	)
	var incompatible_volume := DestructibleVolume3D.new()
	incompatible_volume.volume_id = &"runtime_replay_wall"
	incompatible_volume.authoritative = false
	incompatible_volume.create_collision = false
	incompatible_volume.volume_size = Vector3(2.0, 2.0, 0.4)
	incompatible_volume.voxel_size = 0.10
	incompatible_volume.brick_cells = 8
	test_root.add_child(incompatible_volume)
	incompatible_volume.initialize_volume()
	_expect(
		not incompatible_volume.apply_checkpoint(server_volume.checkpoint()),
		"a mismatched bake hash rejects incompatible brick coordinates instead of corrupting geometry"
	)
	var save_path := "/tmp/scavange_destruction_runtime_%d.sdfsave" % OS.get_process_id()
	var snapshot := DestructionCheckpointStore.snapshot_for_volumes(
		[server_volume],
		&"runtime_test"
	)
	var save_error := DestructionCheckpointStore.save_snapshot(save_path, snapshot)
	var loaded := DestructionCheckpointStore.load_snapshot(save_path)
	var saved_volume := _make_volume(
		&"runtime_replay_wall",
		Vector3(-2.0, 1.5, -4.0),
		false,
		false
	)
	var restore_result := DestructionCheckpointStore.apply_snapshot(
		loaded,
		{&"runtime_replay_wall": saved_volume}
	)
	_expect(
		save_error == OK
		and bool(restore_result.get("ok", false))
		and saved_volume.field.checksum() == server_volume.field.checksum(),
		"versioned compressed persistence restores only changed bricks with integrity checking"
	)
	DirAccess.remove_absolute(save_path)


func _test_spatial_bounds_registration() -> void:
	var spatial_hash := ServerSpatialHash3D.new(1.0)
	var body := Node3D.new()
	test_root.add_child(body)
	spatial_hash.register_bounds(
		&"destructible:test",
		body,
		&"destructible",
		1,
		AABB(Vector3(-2.2, 0.0, -0.2), Vector3(4.4, 2.0, 0.4))
	)
	var left := spatial_hash.query_keys_uncached(
		Vector3(-2.0, 1.0, 0.0),
		0.1,
		[&"destructible"]
	)
	var right := spatial_hash.query_keys_uncached(
		Vector3(2.0, 1.0, 0.0),
		0.1,
		[&"destructible"]
	)
	var debug := spatial_hash.get_debug_state()
	_expect(
		left == [&"destructible:test"]
		and right == [&"destructible:test"]
		and int(debug.get("bounded_cell_memberships", 0)) > 1,
		"one structure record spans spatial-hash cells without becoming per-piece entities"
	)


func _test_projectile_routing() -> void:
	var volume := _make_volume(&"runtime_projectile_wall", Vector3(2.0, 1.5, -4.0), true, true)
	await physics_frame
	var projectile := ServerProjectile.new()
	test_root.add_child(projectile)
	_configure_test_projectile(projectile, 2001, Vector3(2.0, 1.5, 0.0))
	projectile.server_physics_tick(0.1)
	_expect(
		projectile.resolved and volume.field.revision == 1,
		"the real swept projectile routes a material event through the collision adapter"
	)


func _test_service_pistol_routing() -> void:
	var field_scene := load(
		"res://scenes/server/destruction_field_test.tscn"
	) as PackedScene
	var field_instance := field_scene.instantiate() as Node3D
	field_instance.position = Vector3(10.0, 0.0, -4.0)
	test_root.add_child(field_instance)
	var concrete_wall := field_instance.get_node_or_null(
		"ConcreteWall"
	) as DestructibleVolume3D
	var metal_wall := field_instance.get_node_or_null(
		"MetalWall"
	) as DestructibleVolume3D
	var profiles := _service_pistol_profiles()
	await physics_frame
	var projectile := ServerProjectile.new()
	test_root.add_child(projectile)
	var metal_projectile := ServerProjectile.new()
	test_root.add_child(metal_projectile)
	if concrete_wall != null and not profiles.is_empty():
		projectile.configure(
			3001,
			profiles[0],
			concrete_wall.global_position + Vector3(0.0, 0.0, 2.0),
			Vector3(0.0, 0.0, -1.0),
			Vector3.ZERO,
			[],
			&"player",
			8,
			0
		)
		projectile.server_physics_tick(0.1)
	if metal_wall != null and not profiles.is_empty():
		metal_projectile.configure(
			3002,
			profiles[0],
			metal_wall.global_position + Vector3(0.0, 0.0, 2.0),
			Vector3(0.0, 0.0, -1.0),
			Vector3.ZERO,
			[],
			&"player",
			8,
			0
		)
		metal_projectile.server_physics_tick(0.1)
	_expect(
		concrete_wall != null
		and metal_wall != null
		and not profiles.is_empty()
		and is_equal_approx(float(profiles[0].get("destruction_energy", 0.0)), 16.0)
		and is_equal_approx(float(profiles[0].get("destruction_radius", 0.0)), 0.05)
		and is_equal_approx(float(profiles[0].get("penetration_depth", 0.0)), 0.75)
		and projectile.resolved
		and metal_projectile.resolved
		and concrete_wall.field.revision == 1
		and metal_wall.field.revision == 1,
		"the shipped service pistol applies its destruction profile to concrete and metal"
	)
	if concrete_wall != null:
		concrete_wall.flush_pending_rebuilds()
	if metal_wall != null:
		metal_wall.flush_pending_rebuilds()
	_expect(
		_generated_surface_preserves_authored_material(concrete_wall)
		and _generated_surface_preserves_authored_material(metal_wall),
		"rebuilt concrete and metal preserve their authored material appearance"
	)
	projectile.queue_free()
	metal_projectile.queue_free()
	field_instance.queue_free()
	await process_frame


func _test_live_server_world_pistol_routing() -> void:
	var server := root.get_node_or_null("/root/Server")
	var client := root.get_node_or_null("/root/Client")
	if server == null or client == null:
		_expect(false, "the live network autoloads are available for pistol destruction routing")
		return
	server.call("spawn_server_world")
	var volumes: Dictionary = server.get("destructible_volumes_by_id")
	var concrete_wall := volumes.get(
		&"destruction_test_concrete"
	) as DestructibleVolume3D
	var client_world := load(
		"res://scenes/proxy/destruction_field_test.tscn"
	).instantiate() as Node3D
	if concrete_wall != null:
		client_world.global_transform = concrete_wall.get_parent_node_3d().global_transform
	root.add_child(client_world)
	client.set("client_world", client_world)
	client.call("_index_client_destructible_volumes")
	await physics_frame
	var client_volumes: Dictionary = client.get("destructible_volumes_by_id")
	var client_concrete_wall := client_volumes.get(
		&"destruction_test_concrete"
	) as DestructibleVolume3D
	var profiles := _service_pistol_profiles()
	var projectile: ServerProjectile
	if concrete_wall != null and not profiles.is_empty():
		projectile = server.call(
			"spawn_ballistic_projectile",
			profiles[0],
			concrete_wall.global_position + Vector3(0.0, 0.0, 2.0),
			Vector3(0.0, 0.0, -1.0),
			Vector3.ZERO,
			[],
			&"player",
			8,
			null,
			0
		) as ServerProjectile
	var projectile_resolved := false
	if projectile != null:
		projectile.server_physics_tick(0.1)
		projectile_resolved = projectile.resolved
	await process_frame
	_expect(
		concrete_wall != null
		and projectile_resolved
		and concrete_wall.field.revision == 1,
		"the live server world registers its field wall and accepts a shipped pistol projectile"
	)
	_expect(
		client_concrete_wall != null
		and client_concrete_wall.field.revision == concrete_wall.field.revision
		and client_concrete_wall.field.checksum() == concrete_wall.field.checksum(),
		"the listen-host presentation replays the pistol edit instead of leaving an opaque proxy wall"
	)
	if concrete_wall != null:
		concrete_wall.flush_pending_rebuilds()
	if client_concrete_wall != null:
		client_concrete_wall.flush_pending_rebuilds()
	client.set("client_world", null)
	client.set("destructible_volumes_by_id", {})
	client_world.queue_free()
	server.call("_clear_runtime_session")
	for _cleanup_frame: int in range(3):
		await process_frame


func _service_pistol_profiles() -> Array[Dictionary]:
	var pistol := load(
		"res://resources/items/guns/basic_service_pistol.tres"
	) as GunItemDefinition
	if pistol == null:
		return []
	return pistol.get_build(
		pistol.make_default_instance_state()
	).get_ballistic_profiles()


func _generated_surface_preserves_authored_material(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
	var profile := DestructionMaterialRegistry.profile_for(volume.physical_surface)
	var base_material := volume.get("_surface_material") as StandardMaterial3D
	var generated_material := volume.get("_generated_surface_material") as StandardMaterial3D
	if (
		base_material == null
		or generated_material == null
		or not _colors_match_packed(base_material.albedo_color, profile.exterior_color)
		or not is_equal_approx(base_material.roughness, profile.roughness)
		or not is_equal_approx(base_material.metallic, profile.metallic)
		or not generated_material.vertex_color_use_as_albedo
		or not generated_material.vertex_color_is_srgb
		or not is_equal_approx(generated_material.roughness, profile.roughness)
		or not is_equal_approx(generated_material.metallic, profile.metallic)
	):
		return false
	var found_generated_surface := false
	var found_exterior_color := false
	for child: Node in volume.get_children():
		var visual := child as MeshInstance3D
		if visual == null or not visual.name.begins_with("GeneratedVisual_"):
			continue
		var mesh := visual.mesh as ArrayMesh
		if mesh == null:
			return false
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.size() != vertices.size():
				return false
			found_generated_surface = true
			for color: Color in colors:
				if _colors_match_packed(color, profile.exterior_color):
					found_exterior_color = true
				elif not _colors_match_packed(color, profile.interior_color):
					return false
	return found_generated_surface and found_exterior_color


func _colors_match_packed(left: Color, right: Color) -> bool:
	# ArrayMesh stores this channel as normalized 8-bit color data unless a higher-precision custom
	# format is requested. One quantization step is presentation-equivalent to the authored Color.
	const PACKED_COLOR_TOLERANCE := 1.0 / 255.0 + 0.00001
	return (
		absf(left.r - right.r) <= PACKED_COLOR_TOLERANCE
		and absf(left.g - right.g) <= PACKED_COLOR_TOLERANCE
		and absf(left.b - right.b) <= PACKED_COLOR_TOLERANCE
		and absf(left.a - right.a) <= PACKED_COLOR_TOLERANCE
	)


func _test_local_acoustic_invalidation() -> void:
	var service := ServerAcousticService.new()
	test_root.add_child(service)
	var paths: Dictionary = service.get("_direct_paths_by_source")
	paths[Vector2i(1, 8)] = {
		"listener_position": Vector3(-2.0, 1.0, 0.0),
		"source_position": Vector3(2.0, 1.0, 0.0),
	}
	paths[Vector2i(2, 9)] = {
		"listener_position": Vector3(20.0, 1.0, 0.0),
		"source_position": Vector3(24.0, 1.0, 0.0),
	}
	service.invalidate_aabb(AABB(Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 2.0, 0.5)))
	var state := service.get_debug_state()
	_expect(
		int(state.get("local_geometry_invalidation_count", 0)) == 1
		and int(state.get("local_geometry_invalidated_path_count", 0)) == 1
		and int(state.get("cached_direct_paths", 0)) == 1
		and not bool(service.get("_rebuild_pending")),
		"a wall edit invalidates intersecting acoustic paths locally without rebaking the world"
	)


func _configure_test_projectile(
	projectile: ServerProjectile,
	projectile_id: int,
	origin: Vector3
) -> void:
	projectile.configure(
		projectile_id,
		{
			"muzzle_velocity": 80.0,
			"gravity_scale": 0.0,
			"maximum_range": 20.0,
			"damage": 16.0,
			"destruction_energy": 16.0,
			"destruction_radius": BallisticProjectileDefinition.DEFAULT_DESTRUCTION_RADIUS,
			"penetration_depth": 1.0,
			"impact_impulse": 2.0,
			"damage_tags": PackedStringArray(["ballistic"]),
		},
		origin,
		Vector3(0.0, 0.0, -1.0),
		Vector3.ZERO,
		[],
		&"runtime_test",
		3,
		0
	)


func _make_volume(
	volume_id: StringName,
	position: Vector3,
	authoritative: bool,
	create_collision: bool
) -> DestructibleVolume3D:
	var volume := DestructibleVolume3D.new()
	volume.name = str(volume_id)
	volume.volume_id = volume_id
	volume.position = position
	volume.authoritative = authoritative
	volume.create_collision = create_collision
	volume.physical_surface = &"concrete"
	volume.volume_size = Vector3(2.0, 2.0, 0.4)
	volume.voxel_size = 0.08
	volume.brick_cells = 8
	volume.remesh_neighbor_ring = 1
	test_root.add_child(volume)
	volume.initialize_volume()
	return volume


func _capture_committed_event(event: DamageEvent, _result: Dictionary) -> void:
	committed_event = event


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", label)
		return
	failure_count += 1
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print(
		"Destruction runtime integration: %d assertions, %d failures"
		% [assertion_count, failure_count]
	)
	quit(1 if failure_count > 0 else 0)
