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
