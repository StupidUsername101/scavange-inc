extends SceneTree

## Runtime seam coverage for the opt-in destruction slice: node construction, authoritative event
## canonicalization, chunk mesh/collision replacement, replay, checkpoint recovery, spatial bounds,
## and the real projectile adapter. The mathematical field has its own faster unit test.

const MeshAudit := preload("res://tests/helpers/destruction_mesh_audit.gd")

var assertion_count := 0
var failure_count := 0
var test_root: Node3D
var committed_event: DamageEvent
var live_committed_event: DamageEvent
var live_committed_result: Dictionary = {}
var locked_body_rebuild_volume: DestructibleVolume3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	test_root.name = "DestructionRuntimeTest"
	root.add_child(test_root)
	await process_frame
	await _test_volume_replay_and_collision_swap()
	await _test_repeated_impact_seams()
	await _test_analytic_shell_chunk_seam_symmetry()
	await _test_analytic_shell_feature_preservation()
	await _test_collision_body_self_retirement()
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
		_generated_surface_warmup_matches_runtime_layout(server_volume),
		"world loading registers the generated color-stream pipeline before the first impact"
	)
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
	var changed_chunks: Array[Vector3i] = result.get("changed_chunks", [])
	var remesh_chunks: Array[Vector3i] = result.get("remesh_chunks", [])
	var conservative_ring := server_volume.field.expanded_chunk_ring(changed_chunks, 1)
	_expect(
		bool(result.get("changed", false))
		and server_volume.field.revision == 1
		and committed_event != null,
		"an authoritative event commits one sparse-field revision"
	)
	_expect(
		not remesh_chunks.is_empty()
		and remesh_chunks.size() == (
			server_volume.field.brick_counts.x
			* server_volume.field.brick_counts.y
			* server_volume.field.brick_counts.z
		)
		and remesh_chunks.size() >= conservative_ring.size(),
		"a volume's first edit stages one complete global-lattice surface instead of a mixed box seam"
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
		int(runtime_state.get("rebuild_count", 0)) == remesh_chunks.size()
		and int(runtime_state.get("generated_visuals", 0))
		== int(runtime_state.get("rebuild_count", 0))
		and int(runtime_state.get("generated_bodies", 0))
		== int(runtime_state.get("generated_visuals", 0))
		and bool(runtime_state.get("generated_surface_active", false))
		and not bool(runtime_state.get("full_surface_transition_pending", true)),
		"the staged surface commits atomically with matching generated render and collision chunks"
	)
	_expect(
		_generated_surface_preserves_authored_material(server_volume),
		"generated concrete keeps the base material's sRGB, roughness, and metallic contract"
	)
	_expect(
		_generated_surface_is_atomic_and_complete(server_volume),
		"the committed edited volume has no remaining generated/BoxMesh presentation seam"
	)
	_expect(
		_generated_meshes_have_no_unreferenced_halo(server_volume),
		"temporary contour halo vertices are removed before render and collision upload"
	)
	_expect(
		_generated_meshes_have_stable_triangles(server_volume),
		"presented SDF patches contain no detached slivers or inside-out impact triangles"
	)
	_expect(
		_seam_rays_hit_intact_wall(server_volume),
		"dense rays on both sides of generated/generated chunk seams find continuous collision"
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
		and client_volume.field.checksum() == server_volume.field.checksum()
		and int(client_volume.debug_state().get("generated_visuals", 0)) > 0,
		"client replay produces and renders the authoritative sparse-field topology"
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
	checkpoint_volume.flush_pending_rebuilds()
	_expect(
		int(checkpoint_volume.debug_state().get("generated_visuals", 0)) > 0,
		"a late checkpoint rebuilds visible client topology instead of only restoring field bytes"
	)
	var recovery_volume := _make_volume(
		&"runtime_replay_wall",
		Vector3(-2.0, 1.5, -4.0),
		false,
		false
	)
	recovery_volume.apply_replicated_damage_event(committed_event, 0)
	recovery_volume.flush_pending_rebuilds()
	var divergent_packet := committed_event.to_dict(false)
	divergent_packet["event_id"] = 1003
	divergent_packet["sequence"] = 13
	divergent_packet["world_position"] = committed_event.world_position + Vector3(0.3, 0.0, 0.0)
	var divergent_event := DamageEvent.from_dict(divergent_packet)
	var divergent_result := recovery_volume.apply_replicated_damage_event(divergent_event, 1)
	await process_frame
	var divergent_state := recovery_volume.debug_state()
	_expect(
		bool(divergent_result.get("changed", false))
		and (
			int(divergent_state.get("active_chunk_jobs", 0))
			+ int(divergent_state.get("queued_chunks", 0))
		) > 0,
		"the recovery regression stages divergent client topology work"
	)
	_expect(
		recovery_volume.apply_checkpoint(server_volume.checkpoint()),
		"checkpoint recovery accepts authority while divergent client topology work is active"
	)
	recovery_volume.flush_pending_rebuilds()
	_expect(
		recovery_volume.field.revision == server_volume.field.revision
		and recovery_volume.field.checksum() == server_volume.field.checksum()
		and int(recovery_volume.debug_state().get("generated_visuals", 0)) > 0,
		"checkpoint recovery discards stale workers and replaces divergent generated presentation"
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


func _test_repeated_impact_seams() -> void:
	var volume := DestructibleVolume3D.new()
	volume.name = "RepeatedImpactWall"
	volume.volume_id = &"repeated_impact_wall"
	volume.position = Vector3(18.0, 1.5, -4.0)
	volume.authoritative = true
	volume.create_collision = true
	volume.physical_surface = &"concrete"
	volume.volume_size = Vector3(4.0, 3.0, 0.45)
	volume.voxel_size = 0.06
	volume.brick_cells = 12
	volume.remesh_neighbor_ring = 1
	test_root.add_child(volume)
	volume.initialize_volume()
	await physics_frame
	var impact_points: Array[Vector2] = [
		Vector2(-0.72, -0.42),
		Vector2(0.0, 0.0),
		Vector2(0.68, 0.46),
	]
	var all_impacts_changed := true
	for impact_index: int in range(impact_points.size()):
		var point := impact_points[impact_index]
		var event := DamageEvent.from_dict({
			"event_id": 4100 + impact_index,
			"sequence": 4100 + impact_index,
			"source_kind": &"repeated_seam_test",
			"source_id": 4,
			"world_position": volume.to_global(Vector3(point.x, point.y, 0.225)),
			"normal": Vector3(0.0, 0.0, 1.0),
			"direction": Vector3(0.0, 0.0, -1.0),
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.05,
			"length": 0.75,
			"energy": 16.0,
			"impulse": 3.0,
			"penetration": 0.75,
			"damage_tags": PackedStringArray(["ballistic"]),
			"seed": 900 + impact_index,
		})
		all_impacts_changed = (
			bool(volume.apply_authoritative_damage_event(event).get("changed", false))
			and all_impacts_changed
		)
		volume.flush_pending_rebuilds()
		await physics_frame
	var joins_base := _generated_surface_is_atomic_and_complete(volume)
	var compact_meshes := _generated_meshes_have_no_unreferenced_halo(volume)
	var collision_seams := _seam_rays_hit_intact_wall(volume)
	_expect(
		all_impacts_changed and joins_base and compact_meshes and collision_seams,
		"several spaced impacts retain seamless render and collision patch unions"
	)
	volume.queue_free()
	await process_frame


func _test_analytic_shell_feature_preservation() -> void:
	var volume := _make_volume(
		&"sharp_shell_wall",
		Vector3(26.0, 2.0, -4.0),
		true,
		false
	)
	await physics_frame
	var event := DamageEvent.from_dict({
		"event_id": 4199,
		"sequence": 4199,
		"source_kind": &"sharp_shell_test",
		"source_id": 4,
		"world_position": volume.to_global(Vector3(-0.76, 0.76, 0.2)),
		"normal": Vector3.BACK,
		"direction": Vector3.FORWARD,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.05,
		"length": 0.75,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 0.75,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 4199,
	})
	var result := volume.apply_authoritative_damage_event(event)
	volume.flush_pending_rebuilds()
	_expect(
		bool(result.get("changed", false))
		and _generated_box_shell_is_exact_and_hard(volume),
		"a remeshed outer wall corner retains exact planes and per-face hard normals"
	)
	volume.queue_free()
	await process_frame


func _test_analytic_shell_chunk_seam_symmetry() -> void:
	var volume := _make_volume(
		&"symmetric_shell_seam_wall",
		Vector3(24.0, 2.0, -4.0),
		true,
		false
	)
	await physics_frame
	var event := DamageEvent.from_dict({
		"event_id": 4188,
		"sequence": 4188,
		"source_kind": &"global_chunk_ownership_test",
		"source_id": 4,
		"world_position": volume.to_global(Vector3(0.0, 0.0, 0.2)),
		"normal": Vector3.BACK,
		"direction": Vector3.FORWARD,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.05,
		"length": 0.75,
		"energy": 16.0,
		"impulse": 0.0,
		"penetration": 0.75,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 4188,
	})
	volume.apply_authoritative_damage_event(event)
	volume.flush_pending_rebuilds()
	var final_results := _generated_mesh_results(volume)
	var audit := MeshAudit.audit_results(
		final_results,
		volume.field,
		volume.voxel_size * 0.0001,
		false
	)
	_expect(
		MeshAudit.is_closed_valid(audit)
		and _generated_surface_is_atomic_and_complete(volume),
		"global chunk ownership remains closed without any post-extraction seam mutation: %s"
		% audit
	)
	volume.queue_free()
	await process_frame


func _test_collision_body_self_retirement() -> void:
	var volume := _make_volume(
		&"locked_body_retirement_wall",
		Vector3(30.0, 2.0, -4.0),
		true,
		true
	)
	await physics_frame
	var first_event := DamageEvent.from_dict({
		"event_id": 4250,
		"sequence": 4250,
		"source_kind": &"locked_body_setup",
		"source_id": 4,
		"world_position": volume.to_global(Vector3(0.0, 0.0, 0.2)),
		"normal": Vector3.BACK,
		"direction": Vector3.FORWARD,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.06,
		"length": 0.75,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 0.75,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 4250,
	})
	volume.apply_replicated_damage_event(first_event, volume.field.revision)
	volume.flush_pending_rebuilds()
	var generated_bodies: Dictionary = volume.get("_generated_bodies")
	var hit_body: DestructibleCollisionBody3D
	if not generated_bodies.is_empty():
		hit_body = generated_bodies.values()[0] as DestructibleCollisionBody3D
	if hit_body == null:
		_expect(false, "the lock-reentry fixture creates a generated collision adapter")
		volume.queue_free()
		await process_frame
		return
	var coordinate := hit_body.chunk_coordinate
	var local_hit := volume.field.brick_origin(coordinate) + Vector3(
		volume.field.brick_extent * 0.2,
		volume.field.brick_extent * 0.2,
		volume.field.half_extents.z
	)
	var second_event := DamageEvent.from_dict({
		"event_id": 4251,
		"sequence": 4251,
		"source_kind": &"locked_body_reentry",
		"source_id": 4,
		"world_position": volume.to_global(local_hit),
		"normal": Vector3.BACK,
		"direction": Vector3.FORWARD,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.06,
		"length": 0.75,
		"energy": 16.0,
		"impulse": 3.0,
		"penetration": 0.75,
		"damage_tags": PackedStringArray(["ballistic"]),
		"seed": 4251,
	})
	locked_body_rebuild_volume = volume
	volume.damage_committed.connect(
		_flush_locked_body_rebuild,
		CONNECT_ONE_SHOT
	)
	# Object.call() deliberately reproduces the projectile adapter's call lock. The synchronous
	# flush inside damage_committed must retire this exact body without Object.free() re-entrancy.
	var reentry_result: Dictionary = hit_body.call(&"apply_damage_event", second_event) as Dictionary
	generated_bodies = volume.get("_generated_bodies")
	var replacement := generated_bodies.get(coordinate) as DestructibleCollisionBody3D
	if (
		not bool(reentry_result.get("changed", false))
		or not hit_body.is_queued_for_deletion()
		or replacement == hit_body
	):
		print(
			"LOCKED BODY RETIREMENT DIAGNOSTIC changed=",
			bool(reentry_result.get("changed", false)),
			" reason=", reentry_result.get("reason", &""),
			" queued=", hit_body.is_queued_for_deletion(),
			" coordinate=", coordinate,
			" replacement_same=", replacement == hit_body,
			" remesh=", reentry_result.get("remesh_chunks", [])
		)
	_expect(
		bool(reentry_result.get("changed", false))
		and hit_body.is_queued_for_deletion()
		and replacement != hit_body,
		"a hit collision body can rebuild and retire itself safely while call-locked"
	)
	locked_body_rebuild_volume = null
	volume.queue_free()
	await process_frame


func _flush_locked_body_rebuild(_event: DamageEvent, _result: Dictionary) -> void:
	if locked_body_rebuild_volume != null:
		locked_body_rebuild_volume.flush_pending_rebuilds()


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
	var pristine_checkpoint := concrete_wall.checkpoint() if concrete_wall != null else {}
	var client_runtime_script := load("res://scripts/client/client.gd") as GDScript
	var event_replica_client: Node = client_runtime_script.new()
	event_replica_client.name = "RemoteDestructionEventClient"
	test_root.add_child(event_replica_client)
	var event_replica_world := load(
		"res://scenes/proxy/destruction_field_test.tscn"
	).instantiate() as Node3D
	if concrete_wall != null:
		event_replica_world.global_transform = concrete_wall.get_parent_node_3d().global_transform
	event_replica_client.add_child(event_replica_world)
	event_replica_client.set("client_world", event_replica_world)
	event_replica_client.call("_index_client_destructible_volumes")
	var event_replica_volumes: Dictionary = event_replica_client.get(
		"destructible_volumes_by_id"
	)
	var event_replica_wall := event_replica_volumes.get(
		&"destruction_test_concrete"
	) as DestructibleVolume3D
	live_committed_event = null
	live_committed_result.clear()
	if concrete_wall != null:
		concrete_wall.damage_committed.connect(_capture_live_committed_event)
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
	var event_packet: Dictionary = {}
	if concrete_wall != null and live_committed_event != null:
		event_packet = {
			"volume_id": concrete_wall.volume_id,
			"bake_hash": concrete_wall.bake_hash(),
			"from_revision": int(live_committed_result.get("from_revision", 0)),
			"to_revision": concrete_wall.field.revision,
			"checksum": concrete_wall.field.checksum(),
			"event": live_committed_event.to_dict(true),
		}
		event_packet = bytes_to_var(var_to_bytes(event_packet)) as Dictionary
		event_replica_client.call("on_destruction_event_received", event_packet)
	# A joining peer can receive the reliable checkpoint before its world RPC on another channel.
	# Exercise that real pending-state path with a separate client runtime.
	var late_replica_client: Node = client_runtime_script.new()
	late_replica_client.name = "LateDestructionCheckpointClient"
	test_root.add_child(late_replica_client)
	if concrete_wall != null:
		var serialized_checkpoint := bytes_to_var(
			var_to_bytes(concrete_wall.checkpoint())
		) as Dictionary
		late_replica_client.call(
			"on_destruction_checkpoint_received",
			serialized_checkpoint
		)
	var late_replica_world := load(
		"res://scenes/proxy/destruction_field_test.tscn"
	).instantiate() as Node3D
	if concrete_wall != null:
		late_replica_world.global_transform = concrete_wall.get_parent_node_3d().global_transform
	late_replica_client.add_child(late_replica_world)
	late_replica_client.set("client_world", late_replica_world)
	late_replica_client.call("_index_client_destructible_volumes")
	late_replica_client.call("_apply_pending_destruction_state")
	var late_replica_volumes: Dictionary = late_replica_client.get(
		"destructible_volumes_by_id"
	)
	var late_replica_wall := late_replica_volumes.get(
		&"destruction_test_concrete"
	) as DestructibleVolume3D
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
	# Initial checkpoints and event traffic share a reliable destruction channel, and host rendering
	# uses call_local. Lock that RPC contract so a harmless-looking annotation edit cannot silently
	# make destruction host-only.
	var client_script := client.get_script() as Script
	var rpc_config: Dictionary = client_script.get_rpc_config()
	var event_rpc: Dictionary = rpc_config.get("on_destruction_event_received", {})
	var checkpoint_rpc: Dictionary = rpc_config.get("on_destruction_checkpoint_received", {})
	_expect(
		bool(event_rpc.get("call_local", false))
		and int(event_rpc.get("channel", -1)) == 3
		and int(event_rpc.get("transfer_mode", -1))
		== MultiplayerPeer.TRANSFER_MODE_RELIABLE
		and int(event_rpc.get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_AUTHORITY
		and bool(checkpoint_rpc.get("call_local", false))
		and int(checkpoint_rpc.get("channel", -1)) == 3
		and int(checkpoint_rpc.get("transfer_mode", -1))
		== MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"destruction events and recovery checkpoints are reliable for remote peers and local hosts"
	)
	# A delayed initial checkpoint must never roll a live client backward after it has replayed newer
	# events. This was capable of restoring field bytes while leaving a stale generated mesh visible.
	if not pristine_checkpoint.is_empty():
		client.call("on_destruction_checkpoint_received", pristine_checkpoint)
	if concrete_wall != null:
		concrete_wall.flush_pending_rebuilds()
	if client_concrete_wall != null:
		client_concrete_wall.flush_pending_rebuilds()
	if event_replica_wall != null:
		event_replica_wall.flush_pending_rebuilds()
	if late_replica_wall != null:
		late_replica_wall.flush_pending_rebuilds()
	var authority_checksum := concrete_wall.field.checksum() if concrete_wall != null else -1
	print("Destruction replication metrics: ", {
		"authority_checksum": authority_checksum,
		"host": _replica_summary(client_concrete_wall),
		"event_client": _replica_summary(event_replica_wall),
		"late_client": _replica_summary(late_replica_wall),
	})
	_expect(
		not event_packet.is_empty()
		and client_concrete_wall != null
		and event_replica_wall != null
		and late_replica_wall != null
		and client_concrete_wall.field.checksum() == authority_checksum
		and event_replica_wall.field.checksum() == authority_checksum
		and late_replica_wall.field.checksum() == authority_checksum
		and int(client_concrete_wall.debug_state().get("generated_visuals", 0)) > 0
		and int(event_replica_wall.debug_state().get("generated_visuals", 0)) > 0
		and int(late_replica_wall.debug_state().get("generated_visuals", 0)) > 0,
		"host, event-driven clients, and late-join clients render the same SDF revision"
	)
	client.set("client_world", null)
	client.set("destructible_volumes_by_id", {})
	client_world.queue_free()
	event_replica_client.queue_free()
	late_replica_client.queue_free()
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
		or generated_material.vertex_color_is_srgb
		or not _colors_match_packed(generated_material.albedo_color, profile.exterior_color)
		or not is_equal_approx(generated_material.roughness, profile.roughness)
		or not is_equal_approx(generated_material.metallic, profile.metallic)
	):
		return false
	var found_generated_surface := false
	var found_exterior_color := false
	var exterior := profile.exterior_color
	var interior_modulation := Color(
		profile.interior_color.r / maxf(exterior.r, 0.000001),
		profile.interior_color.g / maxf(exterior.g, 0.000001),
		profile.interior_color.b / maxf(exterior.b, 0.000001),
		profile.interior_color.a / maxf(exterior.a, 0.000001)
	)
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
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if colors.size() != vertices.size():
				return false
			found_generated_surface = true
			for color: Color in colors:
				if _colors_match_packed(color, Color.WHITE):
					found_exterior_color = true
				elif not _colors_match_packed(color, interior_modulation):
					return false
			# Exterior and fracture vertices may occupy the same position, but never the same
			# polygon. Otherwise GPU interpolation recreates the dark wedges this test guards.
			for triangle_offset: int in range(0, indices.size(), 3):
				var exterior_corner_count := 0
				for corner_offset: int in range(3):
					if _colors_match_packed(
						colors[indices[triangle_offset + corner_offset]], Color.WHITE
					):
						exterior_corner_count += 1
				if exterior_corner_count != 0 and exterior_corner_count != 3:
					return false
	return found_generated_surface and found_exterior_color


func _generated_surface_warmup_matches_runtime_layout(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
	var warmup := volume.get_node_or_null(
		NodePath(str(DestructibleVolume3D.RUNTIME_WARMUP_NAME))
	) as MeshInstance3D
	if warmup == null or warmup.visible or warmup.mesh == null:
		return false
	var mesh := warmup.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 1:
		return false
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return (
		vertices.size() == 3
		and normals.size() == vertices.size()
		and colors.size() == vertices.size()
		and indices == PackedInt32Array([0, 1, 2])
		and warmup.material_override
		== (volume.get("_generated_surface_material") as StandardMaterial3D)
	)


func _generated_meshes_have_stable_triangles(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
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
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if normals.size() != vertices.size() or indices.size() % 3 != 0:
				return false
			for offset: int in range(0, indices.size(), 3):
				var first := indices[offset]
				var second := indices[offset + 1]
				var third := indices[offset + 2]
				if (
					first < 0 or first >= vertices.size()
					or second < 0 or second >= vertices.size()
					or third < 0 or third >= vertices.size()
					or first == second or second == third or third == first
				):
					return false
				var first_edge := vertices[second] - vertices[first]
				var second_edge := vertices[third] - vertices[second]
				var third_edge := vertices[first] - vertices[third]
				var face := first_edge.cross(-third_edge)
				var edge_sum := (
					first_edge.length_squared()
					+ second_edge.length_squared()
					+ third_edge.length_squared()
				)
				if edge_sum <= 0.000000001:
					return false
				var quality := 2.0 * sqrt(3.0) * face.length() / edge_sum
				var authored := normals[first] + normals[second] + normals[third]
				if (
					quality < SdfDualContouringMesher.MIN_PRESENTED_TRIANGLE_QUALITY * 0.99
					or face.dot(authored) >= 0.0
				):
					return false
	return true


func _generated_box_shell_is_exact_and_hard(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
	var tolerance := maxf(volume.voxel_size * 0.005, 0.00001)
	var half := volume.field.half_extents
	var found_shell_triangles := 0
	var found_hard_corner := false
	var planes: Array[Dictionary] = [
		{"axis": 0, "coordinate": -half.x, "normal": Vector3.LEFT},
		{"axis": 0, "coordinate": half.x, "normal": Vector3.RIGHT},
		{"axis": 1, "coordinate": -half.y, "normal": Vector3.DOWN},
		{"axis": 1, "coordinate": half.y, "normal": Vector3.UP},
		{"axis": 2, "coordinate": -half.z, "normal": Vector3.FORWARD},
		{"axis": 2, "coordinate": half.z, "normal": Vector3.BACK},
	]
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
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for vertex: Vector3 in vertices:
				found_hard_corner = found_hard_corner or (
					absf(vertex.x + half.x) <= tolerance
					and absf(vertex.y - half.y) <= tolerance
				)
			for offset: int in range(0, indices.size(), 3):
				var first := indices[offset]
				var second := indices[offset + 1]
				var third := indices[offset + 2]
				for plane: Dictionary in planes:
					var axis := int(plane["axis"])
					var coordinate := float(plane["coordinate"])
					if (
						absf(vertices[first][axis] - coordinate) > tolerance
						or absf(vertices[second][axis] - coordinate) > tolerance
						or absf(vertices[third][axis] - coordinate) > tolerance
					):
						continue
					var expected: Vector3 = plane["normal"]
					if (
						normals[first].dot(expected) < 0.9999
						or normals[second].dot(expected) < 0.9999
						or normals[third].dot(expected) < 0.9999
					):
						return false
					found_shell_triangles += 1
					break
	return found_hard_corner and found_shell_triangles >= 4


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


func _generated_surface_is_atomic_and_complete(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
	var generated_visuals: Dictionary = volume.get("_generated_visuals")
	var base_visuals: Dictionary = volume.get("_base_visuals")
	var expected_count := (
		volume.field.brick_counts.x
		* volume.field.brick_counts.y
		* volume.field.brick_counts.z
	)
	if generated_visuals.size() != expected_count or base_visuals.size() != expected_count:
		return false
	for visual_value: Variant in generated_visuals.values():
		var visual := visual_value as MeshInstance3D
		if visual == null or visual.mesh == null or not visual.visible:
			return false
	for visual_value: Variant in base_visuals.values():
		var visual := visual_value as MeshInstance3D
		if visual == null or visual.visible:
			return false
	return true


func _generated_mesh_results(volume: DestructibleVolume3D) -> Array:
	var results: Array = []
	var generated_visuals: Dictionary = volume.get("_generated_visuals")
	var coordinates: Array = generated_visuals.keys()
	coordinates.sort_custom(func(left: Vector3i, right: Vector3i) -> bool:
		return (
			left.z < right.z
			or (left.z == right.z and left.y < right.y)
			or (left.z == right.z and left.y == right.y and left.x < right.x)
		)
	)
	for coordinate: Vector3i in coordinates:
		var visual := generated_visuals.get(coordinate) as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		for surface_index: int in range(visual.mesh.get_surface_count()):
			var arrays := visual.mesh.surface_get_arrays(surface_index)
			results.append({
				"vertices": arrays[Mesh.ARRAY_VERTEX],
				"normals": arrays[Mesh.ARRAY_NORMAL],
				"indices": arrays[Mesh.ARRAY_INDEX],
			})
	return results


func _mesh_vertices(mesh: Mesh) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	for surface_index: int in range(mesh.get_surface_count()):
		vertices.append_array(mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX])
	return vertices


func _generated_meshes_have_no_unreferenced_halo(volume: DestructibleVolume3D) -> bool:
	if volume == null:
		return false
	var generated_visuals: Dictionary = volume.get("_generated_visuals")
	if generated_visuals.is_empty():
		return false
	for visual_value: Variant in generated_visuals.values():
		var visual := visual_value as MeshInstance3D
		if visual == null or visual.mesh == null:
			return false
		for surface_index: int in range(visual.mesh.get_surface_count()):
			var arrays := visual.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var referenced := PackedByteArray()
			referenced.resize(vertices.size())
			for vertex_index: int in indices:
				if vertex_index < 0 or vertex_index >= vertices.size():
					return false
				referenced[vertex_index] = 1
			for used: int in referenced:
				if used == 0:
					return false
	return true


func _seam_rays_hit_intact_wall(volume: DestructibleVolume3D) -> bool:
	if volume == null or volume.get_world_3d() == null:
		return false
	var generated_visuals: Dictionary = volume.get("_generated_visuals")
	var seam_probe_offset := volume.voxel_size * 0.08
	var probe_count := 0
	var directions: Array[Vector3i] = [
		Vector3i.RIGHT,
		Vector3i.UP,
	]
	for raw_coordinate: Variant in generated_visuals.keys():
		var coordinate := raw_coordinate as Vector3i
		var minimum := volume.field.brick_origin(coordinate)
		var maximum := Vector3(
			minf(minimum.x + volume.field.brick_extent, volume.field.half_extents.x),
			minf(minimum.y + volume.field.brick_extent, volume.field.half_extents.y),
			minf(minimum.z + volume.field.brick_extent, volume.field.half_extents.z)
		)
		for direction: Vector3i in directions:
			var neighbor := coordinate + direction
			if not volume.field.brick_is_valid(neighbor):
				continue
			var neighbor_generated := generated_visuals.get(neighbor) as MeshInstance3D
			if neighbor_generated == null or not neighbor_generated.visible:
				continue
			var seam_axis := 0 if direction.x != 0 else 1
			var tangent_axis := 1 if seam_axis == 0 else 0
			var seam_coordinate := (
				minimum[seam_axis]
				if direction[seam_axis] < 0
				else maximum[seam_axis]
			)
			for along_fraction: float in [0.2, 0.5, 0.8]:
				for side: float in [-1.0, 1.0]:
					var local_probe := Vector3.ZERO
					local_probe[seam_axis] = seam_coordinate + seam_probe_offset * side
					local_probe[tangent_axis] = lerpf(
						minimum[tangent_axis],
						maximum[tangent_axis],
						along_fraction
					)
					if volume.field.sample_distance(local_probe) > 0.0:
						continue
					var query := PhysicsRayQueryParameters3D.create(
						volume.to_global(local_probe + Vector3(0.0, 0.0, 1.0)),
						volume.to_global(local_probe + Vector3(0.0, 0.0, -1.0))
					)
					query.collide_with_areas = false
					if volume.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
						return false
					probe_count += 1
	return probe_count >= 4


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


func _capture_live_committed_event(event: DamageEvent, result: Dictionary) -> void:
	live_committed_event = event
	live_committed_result = result.duplicate(false)


func _replica_summary(volume: DestructibleVolume3D) -> Dictionary:
	if volume == null:
		return {}
	var state := volume.debug_state()
	return {
		"revision": volume.field.revision,
		"checksum": volume.field.checksum(),
		"generated_visuals": int(state.get("generated_visuals", 0)),
	}


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
