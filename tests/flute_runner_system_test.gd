extends SceneTree

const STEP := 1.0 / 60.0
const ACOUSTIC_STIMULUS_LEDGER := preload(
	"res://scripts/enemies/acoustic_stimulus_ledger.gd"
)
const RADIO_STATE_SNAPSHOT_CODEC := preload(
	"res://scripts/audio/radio_state_snapshot_codec.gd"
)
const DESTRUCTION_MESH_AUDIT := preload(
	"res://tests/helpers/destruction_mesh_audit.gd"
)
const SERVICE_9MM: BallisticProjectileDefinition = preload(
	"res://resources/weapons/projectiles/service_9mm.tres"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authoritative_state_machine()
	_test_state_memory_lifecycle()
	_test_physical_tackle_gate()
	_test_bounded_acoustic_stimulus_memory()
	_test_acoustic_source_ownership_and_expiry()
	_test_legacy_enemy_compatibility()
	_test_definition_and_compact_wire_contract()
	_test_firearm_wound_scale_and_limb_anchors()
	_test_sdf_anatomy_survival_contract()
	_test_continuous_audio_boundary()
	_test_reversible_world_spawn()
	await _test_continuous_audio_lifecycle_and_wire_identity()
	await _test_hidden_player_requires_real_acoustic_stimulus()
	await _test_authoritative_chase_integration()
	await _test_humanoid_presentation_contract()
	await _test_animated_thigh_wound_surface_alignment()
	await _test_incremental_wound_presentation_budget()
	if failure_count == 0:
		print("Flute runner tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Flute runner tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_authoritative_state_machine() -> void:
	var definition := FluteRunnerDefinition.new()
	var controller := FluteRunnerBehaviorController.new()
	controller.reset(Vector3.ZERO)
	controller.update(
		STEP,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		7,
		Vector3(0.0, 0.0, -8.0),
		Vector3.ZERO,
		true,
		true,
		true
	)
	_expect(
		controller.state == FluteRunnerBehaviorController.State.CHASE
		and controller.target_id == 7
		and controller.desired_velocity.z < -definition.pursuit_speed,
		"a visible nearby player enters chase with a server-owned movement intent"
	)
	controller.update(
		STEP,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		7,
		Vector3(4.0, 0.0, -13.0),
		Vector3(3.0, 0.0, 0.0),
		false,
		true,
		true
	)
	_expect(
		controller.state == FluteRunnerBehaviorController.State.CURIOUS
		and controller.has_last_known_position
		and controller.last_known_position != Vector3(4.0, 0.0, -13.0),
		"hearing produces a deliberately imprecise curious target instead of wall-penetrating aim lock"
	)
	controller.update(
		STEP,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		-1,
		Vector3.ZERO,
		Vector3.ZERO,
		false,
		false,
		false
	)
	_expect(
		controller.state == FluteRunnerBehaviorController.State.SEARCH,
		"losing direct perception preserves bounded target memory and enters search"
	)


func _test_state_memory_lifecycle() -> void:
	var definition := FluteRunnerDefinition.new()
	definition.heard_memory_seconds = 0.08
	definition.search_seconds = 0.12
	var controller := FluteRunnerBehaviorController.new()
	controller.reset(Vector3.ZERO)
	controller.update(
		STEP,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		31,
		Vector3(2.0, 0.0, -5.0),
		Vector3.ZERO,
		false,
		true,
		true
	)
	controller.update(
		0.04,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		-1,
		Vector3.ZERO,
		Vector3.ZERO,
		false,
		false,
		false
	)
	var preserved_search := (
		controller.state == FluteRunnerBehaviorController.State.SEARCH
		and controller.has_last_known_position
	)
	controller.update(
		0.16,
		definition,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.ZERO,
		-1,
		Vector3.ZERO,
		Vector3.ZERO,
		false,
		false,
		false
	)
	_expect(
		preserved_search
		and controller.state == FluteRunnerBehaviorController.State.LOITER
		and not controller.has_last_known_position
		and controller.target_id == -1,
		"heard target memory survives a brief loss, then expires into ordinary loiter without a permanent wall lock"
	)


func _test_physical_tackle_gate() -> void:
	var definition := FluteRunnerDefinition.new()
	var controller := FluteRunnerBehaviorController.new()
	controller.state = FluteRunnerBehaviorController.State.CHASE
	_expect(
		not controller.can_tackle(
			definition.tackle_minimum_speed - 0.1,
			1.0,
			definition
		)
		and not controller.can_tackle(
			definition.tackle_minimum_speed + 2.0,
			definition.tackle_minimum_facing_dot - 0.1,
			definition
		)
		and controller.can_tackle(
			definition.tackle_minimum_speed + 2.0,
			definition.tackle_minimum_facing_dot + 0.1,
			definition
		),
		"tackles require chase state, relative contact speed, and forward facing"
	)
	controller.consume_tackle(definition)
	_expect(
		controller.state == FluteRunnerBehaviorController.State.FUMBLE
		and not controller.can_tackle(30.0, 1.0, definition),
		"a successful tackle enters a cooldown-backed fumble instead of radius damage spam"
	)


func _test_bounded_acoustic_stimulus_memory() -> void:
	var ledger = ACOUSTIC_STIMULUS_LEDGER.new()
	for sequence: int in range(ACOUSTIC_STIMULUS_LEDGER.CAPACITY + 9):
		ledger.record(
			sequence,
			&"footstep_soil",
			Vector3(float(sequence), 0.0, 0.0),
			24.0,
			-4.0,
			0.5,
			2,
			null
		)
	var records := ledger.readonly_records()
	var found_latest := false
	for stimulus: Variant in records:
		found_latest = found_latest or (
			stimulus.sequence == ACOUSTIC_STIMULUS_LEDGER.CAPACITY + 8
		)
	_expect(
		records.size() == ACOUSTIC_STIMULUS_LEDGER.CAPACITY and found_latest,
		"AI hearing reuses a fixed-capacity sound-event ring while retaining the newest player cue"
	)
	var server := root.get_node_or_null("Server")
	var server_ledger = server.get("acoustic_stimulus_ledger")
	server_ledger.clear()
	server.call(
		"emit_spatial_sound",
		&"footstep_soil",
		Vector3.ZERO,
		20.0,
		6.0,
		null,
		0.5
	)
	var server_records: Array = server_ledger.readonly_records()
	var expected_reach := AcousticPropagationGraph.level_scaled_hearing_distance(
		20.0,
		6.0
	)
	_expect(
		server_records.size() == 1
		and absf(server_records[0].maximum_distance - expected_reach) < 0.001,
		"enemy hearing receives the same loudness-scaled reach as player playback"
	)
	server_ledger.clear()


func _test_acoustic_source_ownership_and_expiry() -> void:
	var server := root.get_node_or_null("Server")
	var ledger = server.get("acoustic_stimulus_ledger")
	ledger.clear()
	ledger.record(
		701,
		&"footstep_soil",
		Vector3(2.0, 0.0, 0.0),
		28.0,
		-3.0,
		0.42,
		91,
		null
	)
	ledger.record(
		702,
		&"pistol_fire",
		Vector3(1.0, 0.0, 0.0),
		52.0,
		2.0,
		0.82,
		92,
		null
	)
	var only_first_player: Array[int] = [91]
	var either_player: Array[int] = [91, 92]
	var first_result: Dictionary = server.call(
		"get_recent_player_acoustic_stimulus",
		1_100_099_001,
		Vector3.ZERO,
		only_first_player,
		1.0,
		60.0
	)
	var loudest_result: Dictionary = server.call(
		"get_recent_player_acoustic_stimulus",
		1_100_099_002,
		Vector3.ZERO,
		either_player,
		1.0,
		60.0
	)
	_expect(
		int(first_result.get("player_id", -1)) == 91
		and int(loudest_result.get("player_id", -1)) == 92,
		"enemy hearing attributes a cue to an admitted candidate player and chooses the strongest valid source"
	)
	var records: Array = ledger.readonly_records()
	records[0].emitted_msec = Time.get_ticks_msec() - 5000
	var stale_result: Dictionary = server.call(
		"get_recent_player_acoustic_stimulus",
		1_100_099_003,
		Vector3.ZERO,
		only_first_player,
		0.2,
		60.0
	)
	_expect(
		stale_result.is_empty(),
		"expired sounds cannot keep an unseen player target alive"
	)
	ledger.clear()


func _test_legacy_enemy_compatibility() -> void:
	var definition := load(
		"res://resources/enemies/stationary_dummy.tres"
	) as EnemyDefinition
	var visual := definition.instantiate_visual()
	var legacy_controller := EnemyBehaviorController.new()
	var intent := legacy_controller.evaluate(
		STEP,
		definition.behavior,
		Vector3.ZERO,
		Vector3.ZERO,
		[]
	)
	_expect(
		definition != null
		and definition.presentation_type == EnemyDefinition.PresentationType.LEGACY
		and definition.flute_runner == null
		and not definition.starts_active
		and visual != null
		and not bool(intent.get("movement_active", true)),
		"the expressive-enemy extension preserves dormant legacy enemy definitions and behavior"
	)
	visual.free()


func _test_definition_and_compact_wire_contract() -> void:
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	_expect(
		definition != null
		and definition.flute_runner != null
		and definition.destructible_anatomy != null
		and definition.presentation_type == EnemyDefinition.PresentationType.HUMANOID
		and definition.starts_active
		and definition.automatically_target_players,
		"the field-test enemy is an explicit reusable humanoid definition"
	)
	var enemy := ServerEnemy.new()
	enemy.definition = definition
	root.add_child(enemy)
	enemy.current_health = definition.max_health
	var state := enemy.to_state_dict()
	var anatomy_state: Dictionary = state.get("anatomy_destruction", {})
	_expect(
		state.has("gait_cycle")
		and state.has("awareness_state")
		and state.has("flute_pose_weight")
		and enemy.destructible_anatomy != null
		and str(anatomy_state.get("profile_path", "")) == (
			definition.destructible_anatomy.resource_path
		)
		and not state.has("bones")
		and not state.has("foot_transforms"),
		"replication carries compact intent and reusable anatomy state, while never serializing humanoid bones"
	)
	var hit_result := enemy.apply_damage_event(
		_make_anatomy_damage_event(87001, Vector3(-0.42, 1.28, -0.36))
	)
	var damaged_state: Dictionary = enemy.to_state_dict().get("anatomy_destruction", {})
	var replicated_wounds: Array = damaged_state.get("wounds", [])
	var replicated_deformations: Array = damaged_state.get("deformation_events", [])
	var replicated_position := (
		(replicated_wounds.front() as Dictionary).get("local_position", Vector3.ZERO) as Vector3
		if not replicated_wounds.is_empty()
		else Vector3.ZERO
	)
	_expect(
		bool(hit_result.get("geometry_changed", false))
		and not replicated_wounds.is_empty()
		and replicated_deformations.size() == 1
		and StringName(str((replicated_deformations.front() as Dictionary).get("part", &""))) == &"left_arm"
		and absf(replicated_position.z + 0.11) < 0.002,
		"a real configured ServerEnemy routes projectile damage through its anatomy and replicates both the compact aperture and canonical SDF edit instead of a broad-collider blood marker"
	)
	enemy.queue_free()


func _test_sdf_anatomy_survival_contract() -> void:
	var profile := load(
		"res://resources/enemies/anatomies/humanoid_flesh.tres"
	) as EnemyDestructibleAnatomyDefinition
	var limb_anatomy := EnemyDestructibleAnatomy.new().configure(73, profile)
	var event_id := 1
	# Cut a narrow ballistic seam across the arm. Scattered tissue loss should not magically remove a
	# limb; a face-disconnecting path through the shared SDF should.
	for row: int in range(2):
		for column: int in range(17):
			limb_anatomy.apply_damage_event(
				_make_anatomy_damage_event(
					event_id,
					Vector3(
						-0.48 + float(column) * 0.01,
						1.205 + float(row) * 0.01,
						-0.36
					)
				),
				Transform3D.IDENTITY
			)
			event_id += 1
	var limb_state := limb_anatomy.state_dict()
	var limb_wounds: Array = limb_state.get("wounds", [])
	var severed_parts := limb_state.get("part_severed", {}) as Dictionary
	var projected_wound: Dictionary = limb_wounds.front() if not limb_wounds.is_empty() else {}
	_expect(
		not limb_anatomy.has_limb(EnemyDestructibleAnatomy.PART_LEFT_ARM)
		and bool(severed_parts.get(EnemyDestructibleAnatomy.PART_LEFT_ARM, false))
		and limb_anatomy.has_limb(EnemyDestructibleAnatomy.PART_RIGHT_ARM)
		and limb_anatomy.has_limb(EnemyDestructibleAnatomy.PART_LEFT_LEG)
		and not limb_anatomy.is_dead()
		and not limb_wounds.is_empty()
		and absf((projected_wound.get("local_position", Vector3.ZERO) as Vector3).z + 0.11) < 0.002
		and str(limb_state.get("profile_path", "")).ends_with("humanoid_flesh.tres"),
		(
			"localized profile-driven SDF loss removes one arm without killing the enemy, and broad-collider hits replicate the exact projected skin-space wound (left=%s right=%s dead=%s wounds=%d position=%s profile=%s)"
			% [
				str(limb_anatomy.has_limb(EnemyDestructibleAnatomy.PART_LEFT_ARM)),
				str(limb_anatomy.has_limb(EnemyDestructibleAnatomy.PART_RIGHT_ARM)),
				str(limb_anatomy.is_dead()),
				limb_wounds.size(),
				str(projected_wound.get("local_position", Vector3.ZERO)),
				"%s remaining=%s" % [
					str(limb_state.get("profile_path", "")),
					str((limb_state.get("part_fractions", {}) as Dictionary).get(&"left_arm")),
				],
			]
		)
	)


func _test_firearm_wound_scale_and_limb_anchors() -> void:
	var profile := load(
		"res://resources/enemies/anatomies/humanoid_flesh.tres"
	) as EnemyDestructibleAnatomyDefinition
	var left_arm := profile.get_part(EnemyDestructibleAnatomy.PART_LEFT_ARM)
	var torso := profile.get_part(EnemyDestructibleAnatomy.PART_TORSO)
	var flesh_texture := profile.damage_texture
	var service_profile := SERVICE_9MM.to_ballistic_profile()
	var response_radius := flesh_texture.response_radius(
		float(service_profile["destruction_radius"]),
		float(service_profile["destruction_energy"])
	)
	_expect(
		float(service_profile["destruction_radius"]) <= 0.0121
		and float(service_profile["penetration_depth"]) >= 0.30
		and float(service_profile["penetration_depth"]) <= 0.46
		and response_radius < 0.018
		and profile.voxel_size <= 0.01
		and left_arm.structural_anchor_mask() == SdfStructuralFragmenter.ANCHOR_POSITIVE_Y
		and torso.structural_anchor_mask() == SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y,
		"ordinary bullets author centimetre-scale flesh channels while anatomy anchors limbs at their proximal joint"
	)
	var anatomy := EnemyDestructibleAnatomy.new().configure(72, profile)
	anatomy.apply_damage_event(
		_make_anatomy_damage_event(7201, Vector3(0.18, 1.10, -0.36)),
		Transform3D.IDENTITY
	)
	anatomy.apply_damage_event(
		_make_anatomy_damage_event(7202, Vector3(0.19, 1.10, -0.36)),
		Transform3D.IDENTITY
	)
	var state := anatomy.state_dict()
	var wounds: Array = state.get("wounds", [])
	var first_radius := (
		float((wounds[0] as Dictionary).get("radius", 1.0))
		if wounds.size() > 0
		else 1.0
	)
	var second_radius := (
		float((wounds[1] as Dictionary).get("radius", 1.0))
		if wounds.size() > 1
		else 1.0
	)
	var arm_state = anatomy.parts.get(EnemyDestructibleAnatomy.PART_LEFT_ARM)
	_expect(
		wounds.size() == 2
		and first_radius < 0.018
		and second_radius < 0.018
		and arm_state != null
		and anatomy.has_limb(EnemyDestructibleAnatomy.PART_LEFT_ARM)
		and arm_state.field.structural_anchor_faces == SdfStructuralFragmenter.ANCHOR_POSITIVE_Y,
		"nearby bullets remain exact individual apertures instead of merging into one tank-sized visual hole"
	)
	var vital_anatomy := EnemyDestructibleAnatomy.new().configure(74, profile)
	var vital_event := _make_anatomy_damage_event(
		9001,
		Vector3(0.0, 1.66, -0.36)
	)
	var vital_result := vital_anatomy.apply_damage_event(
		vital_event,
		Transform3D.IDENTITY
	)
	var revision_before_duplicate := vital_anatomy.revision
	var duplicate_result := vital_anatomy.apply_damage_event(
		vital_event,
		Transform3D.IDENTITY
	)
	var flesh := load(
		"res://resources/destruction/flesh.tres"
	) as DestructionTextureDefinition
	_expect(
		bool(vital_result.get("fatal", false))
		and vital_anatomy.death_reason == &"brain_destroyed"
		and not bool(duplicate_result.get("changed", true))
		and vital_anatomy.revision == revision_before_duplicate
		and flesh.interior_color.r > flesh.deep_interior_color.r * 4.0
		and flesh.interior_color_depth > 0.0,
		"a destroyed vital core kills once, duplicate events are idempotent, and flesh explicitly grades bright shallow tissue into dark depth"
	)


func _make_anatomy_damage_event(
	event_id: int,
	position: Vector3
) -> DamageEvent:
	return DamageEvent.from_dict({
		"event_id": event_id,
		"sequence": event_id,
		"source_kind": &"anatomy_test",
		"source_id": 1,
		"world_position": position,
		"normal": Vector3.BACK,
		"direction": Vector3.BACK,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": SERVICE_9MM.destruction_radius,
		"length": SERVICE_9MM.penetration_depth,
		"penetration": SERVICE_9MM.penetration_depth,
		"energy": SERVICE_9MM.destruction_energy,
		"damage_tags": PackedStringArray(["ballistic"]),
	})


func _test_continuous_audio_boundary() -> void:
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var path := definition.flute_runner.flute_song_path
	var stream := load(path) as AudioStream
	var packet := RadioStatePacket.sanitize({
		"item_id": ServerEnemy.HUMANOID_AUDIO_SOURCE_ID_BASE + 1,
		"revision": 1,
		"song_path": path,
		"source_position": Vector3.ZERO,
		"apparent_position": Vector3.ZERO,
		"volume_db": -12.0,
		"playback_offset_seconds": 0.0,
		"stream_length_seconds": stream.get_length() if stream != null else 0.0,
	})
	_expect(
		stream != null
		and stream.get_length() > 10.0
		and not packet.is_empty()
		and int(packet["item_id"]) >= ServerEnemy.HUMANOID_AUDIO_SOURCE_ID_BASE,
		"the authored flute loop passes the same restricted continuous-audio boundary as radios"
	)
	var portable_radio := RadioItemDefinition.new()
	_expect(
		not portable_radio.discover_song_paths().has(path),
		"gameplay instrument programs cannot leak into the portable radio's selectable music list"
	)


func _test_reversible_world_spawn() -> void:
	var world_scene := load("res://scenes/server/server_world.tscn") as PackedScene
	var world := world_scene.instantiate() as Node3D
	var encounter := world.get_node_or_null("FluteRunnerFieldTest") as ServerEnemy
	_expect(
		encounter != null
		and encounter.definition != null
		and encounter.definition.flute_runner != null
		and encounter.position.distance_to(Vector3(69.0, 0.02, -20.0)) < 0.001,
		"the removable field-test spawn lives in the shared server world outside the test core"
	)
	world.free()


func _test_continuous_audio_lifecycle_and_wire_identity() -> void:
	var fixture := Node3D.new()
	fixture.name = "FluteProgramFixture"
	root.add_child(fixture)
	var enemy_scene := load(
		"res://scenes/server/server_enemy.tscn"
	) as PackedScene
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var first := enemy_scene.instantiate() as ServerEnemy
	first.definition = definition
	first.position = Vector3.ZERO
	fixture.add_child(first)
	var second := enemy_scene.instantiate() as ServerEnemy
	second.definition = definition
	second.position = Vector3(2.0, 0.0, 0.0)
	fixture.add_child(second)
	await process_frame
	var server := root.get_node_or_null("Server")
	var service := server.get("acoustic_service") as ServerAcousticService
	first._flute_playback_started_msec = Time.get_ticks_msec() - 400
	second._flute_playback_started_msec = Time.get_ticks_msec() - 700
	var first_state := first.build_flute_listener_state(
		1_100_099_101,
		Vector3(0.0, 1.58, -0.11),
		service
	)
	var second_state := second.build_flute_listener_state(
		1_100_099_101,
		Vector3(1.0, 1.58, -0.11),
		service
	)
	first._flute_playback_started_msec -= 250
	var advanced_state := first.build_flute_listener_state(
		1_100_099_101,
		Vector3(0.0, 1.58, -0.11),
		service
	)
	var source_states := {
		first.get_continuous_audio_source_id(): first_state,
		second.get_continuous_audio_source_id(): second_state,
	}
	var payload := RADIO_STATE_SNAPSHOT_CODEC.encode(source_states)
	var decoded := RADIO_STATE_SNAPSHOT_CODEC.decode(payload)
	_expect(
		first.enemy_id >= 0
		and second.enemy_id >= 0
		and first.get_continuous_audio_source_id()
		!= second.get_continuous_audio_source_id()
		and not first_state.is_empty()
		and not second_state.is_empty()
		and decoded.size() == 2,
		"multiple flute runners retain unique continuous source identities through the bounded multiplayer snapshot"
	)
	_expect(
		int(advanced_state.get("revision", -1))
		== int(first_state.get("revision", -2))
		and float(advanced_state.get("playback_offset_seconds", -1.0))
		> float(first_state.get("playback_offset_seconds", INF)),
		"ordinary listener updates advance one authoritative flute timeline without restarting its stream"
	)
	first.set_active(false)
	var inactive_state := first.build_flute_listener_state(
		1_100_099_101,
		Vector3.ZERO,
		service
	)
	first.set_active(true)
	first.apply_damage(first.current_health)
	var dead_state := first.build_flute_listener_state(
		1_100_099_101,
		Vector3.ZERO,
		service
	)
	_expect(
		inactive_state.is_empty()
		and dead_state.is_empty(),
		"inactive and dead flute runners stop publishing program input while existing client tails remain free to decay"
	)
	fixture.queue_free()
	await process_frame


func _test_hidden_player_requires_real_acoustic_stimulus() -> void:
	var fixture := Node3D.new()
	fixture.name = "FluteHearingOcclusionFixture"
	root.add_child(fixture)
	var ground := StaticBody3D.new()
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_collision)
	fixture.add_child(ground)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 1.5, -3.5)
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(4.0, 3.0, 0.5)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	fixture.add_child(wall)

	var player_scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	var player := player_scene.instantiate() as ServerPlayer
	fixture.add_child(player)
	player.setup(880024, Vector3(0.0, 1.0, -7.0))
	var server := root.get_node_or_null("Server")
	(server.get("server_players_by_player_id") as Dictionary)[player.player_id] = player
	var ledger = server.get("acoustic_stimulus_ledger")
	ledger.clear()

	var enemy_scene := load(
		"res://scenes/server/server_enemy.tscn"
	) as PackedScene
	var enemy := enemy_scene.instantiate() as ServerEnemy
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	# Call the low-rate sensing edge explicitly. Physics still owns the wall and sight ray; the AI
	# clock does not need to race the assertion on a particular headless frame.
	enemy.definition = definition
	enemy.position = Vector3.ZERO
	fixture.add_child(enemy)
	await physics_frame
	var sight_is_blocked := not enemy._has_line_of_sight_to(player)
	enemy._sense_flute_runner_target(definition.flute_runner)
	var stayed_unaware_without_sound := (
		not is_instance_valid(enemy.sensed_target)
		and not enemy.sensed_target_visible
		and not enemy.sensed_target_audible
	)
	server.call(
		"emit_spatial_sound",
		&"footstep_soil",
		player.global_position,
		34.0,
		-2.0,
		null,
		0.58,
		-1.0,
		player.player_id,
		0
	)
	enemy._sense_flute_runner_target(definition.flute_runner)
	_expect(
		sight_is_blocked
		and stayed_unaware_without_sound
		and enemy.sensed_target == player
		and not enemy.sensed_target_visible
		and enemy.sensed_target_audible,
		"an occluded player is not distance-detected, but a real emitted cue reaches enemy hearing through the shared acoustic solve"
	)
	(server.get("server_players_by_player_id") as Dictionary).erase(player.player_id)
	ledger.clear()
	fixture.queue_free()
	await process_frame


func _test_authoritative_chase_integration() -> void:
	var test_world := Node3D.new()
	test_world.name = "FluteRunnerPhysicsFixture"
	root.add_child(test_world)
	var ground := StaticBody3D.new()
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_collision)
	test_world.add_child(ground)

	var player_scene := load("res://scenes/server/server_player.tscn") as PackedScene
	var player := player_scene.instantiate() as ServerPlayer
	test_world.add_child(player)
	player.setup(880023, Vector3(0.0, 1.0, -7.0))
	var server := root.get_node_or_null("Server")
	(server.get("server_players_by_player_id") as Dictionary)[player.player_id] = player

	var enemy_scene := load("res://scenes/server/server_enemy.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as ServerEnemy
	enemy.definition = load("res://resources/enemies/flute_runner.tres") as EnemyDefinition
	enemy.position = Vector3.ZERO
	test_world.add_child(enemy)
	var saw_chase := false
	var saw_gait := false
	var saw_physical_tackle := false
	for _frame: int in range(180):
		await physics_frame
		saw_chase = saw_chase or (
			enemy.flute_runner_controller.state
			== FluteRunnerBehaviorController.State.CHASE
		)
		saw_gait = saw_gait or enemy.humanoid_gait.step_sequence > 0
		saw_physical_tackle = saw_physical_tackle or player.ragdoll_active
		if saw_chase and saw_gait and saw_physical_tackle:
			break
	_expect(
		saw_chase and saw_gait and saw_physical_tackle,
		"the authority sees, chases with a distance gait, and ragdolls only after a real tackle collision"
	)
	(server.get("server_players_by_player_id") as Dictionary).erase(player.player_id)
	test_world.queue_free()
	await process_frame


func _test_humanoid_presentation_contract() -> void:
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var presentation := EnemyHumanoidPresentation3D.new()
	presentation.configure(40023, definition.destructible_anatomy)
	root.add_child(presentation)
	await process_frame
	presentation.apply_server_state({
		"velocity": Vector3(0.0, 0.0, -8.0),
		"on_floor": true,
		"gait_cycle": 2.4,
		"gait_active": true,
		"gait_stride_distance": 2.4,
		"expression_clock": 4.0,
		"alive": true,
		"active": true,
		"target_position": Vector3(0.0, 1.0, -8.0),
		"has_target_position": true,
		"awareness_state": &"chase",
		"flute_pose_weight": 1.0,
	})
	presentation.update_presentation(STEP)
	var head_index := presentation.character_skin.skeleton.find_bone(
		&"mixamorig_Head"
	)
	var head_world := (
		presentation.character_skin.skeleton.global_transform
		* presentation.character_skin.skeleton.get_bone_global_pose(head_index)
	).origin
	var left_foot_world := presentation.leg_rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var right_foot_world := presentation.leg_rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	var flute_axis := presentation.get_flute_axis_world()
	var left_hand_world := _presentation_bone_world_position(
		presentation,
		&"mixamorig_LeftHand"
	)
	var right_hand_world := _presentation_bone_world_position(
		presentation,
		&"mixamorig_RightHand"
	)
	var left_grip_world := presentation.get_flute_grip_world_position(true)
	var right_grip_world := presentation.get_flute_grip_world_position(false)
	_expect(
		presentation.character_skin != null
		and presentation.character_skin.is_usable()
		and presentation.leg_rig != null
		and presentation.ocular_visual != null
		and presentation.flute_visual != null
		and presentation.flute_visual.visible
		and presentation.character_pose.left_forearm_rotation.length() > 0.2
		and presentation.character_pose.right_forearm_rotation.length() > 0.2
		and is_equal_approx(
			presentation.pose_root.position.y,
			EnemyHumanoidPresentation3D.PROCEDURAL_ROOT_HEIGHT
		)
		and absf(left_foot_world.y - presentation.global_position.y) < 0.04
		and absf(right_foot_world.y - presentation.global_position.y) < 0.04
		and head_world.y > presentation.global_position.y + 1.35
		and flute_axis.dot(presentation.global_basis.y) > 0.45
		and absf(flute_axis.dot(presentation.global_basis.x)) < 0.20
		and left_hand_world.distance_to(left_grip_world) < 0.035
		and right_hand_world.distance_to(right_grip_world) < 0.035
		and left_grip_world.distance_to(right_grip_world) > 0.14,
		"humanoid enemies convert their feet-origin authority into the shared full-body frame, hold the end-blown flute at two real grip points, and retain procedural feet and expression"
	)
	var initial_left_foot := left_foot_world
	var initial_right_foot := right_foot_world
	var initial_left_hand_local := presentation.pose_root.to_local(left_hand_world)
	var initial_right_hand_local := presentation.pose_root.to_local(right_hand_world)
	var saw_live_step := false
	var maximum_local_hand_motion := 0.0
	var maximum_grip_error := 0.0
	for _frame: int in range(50):
		presentation.position += Vector3(0.0, 0.0, -8.0) * STEP
		presentation.update_presentation(STEP)
		saw_live_step = saw_live_step or (
			presentation.leg_rig.get_foot_world_position(
				PlayerProceduralLegRig.Side.LEFT
			).distance_to(initial_left_foot) > 0.08
			or presentation.leg_rig.get_foot_world_position(
				PlayerProceduralLegRig.Side.RIGHT
			).distance_to(initial_right_foot) > 0.08
		)
		var moving_left_hand := _presentation_bone_world_position(
			presentation,
			&"mixamorig_LeftHand"
		)
		var moving_right_hand := _presentation_bone_world_position(
			presentation,
			&"mixamorig_RightHand"
		)
		maximum_local_hand_motion = maxf(
			maximum_local_hand_motion,
			maxf(
				presentation.pose_root.to_local(moving_left_hand).distance_to(
					initial_left_hand_local
				),
				presentation.pose_root.to_local(moving_right_hand).distance_to(
					initial_right_hand_local
				)
			)
		)
		maximum_grip_error = maxf(
			maximum_grip_error,
			maxf(
				moving_left_hand.distance_to(
					presentation.get_flute_grip_world_position(true)
				),
				moving_right_hand.distance_to(
					presentation.get_flute_grip_world_position(false)
				)
			)
		)
	_expect(
		saw_live_step
		and presentation.character_pose.upper_body_rotation.length() > 0.01
		and maximum_local_hand_motion > 0.004
		and maximum_grip_error < 0.04,
		(
			"the flute pose remains layered over the shared moving feet and full-body procedural motion while both grip-owning arms absorb chase sway (step=%s, upper=%.5f, hand=%.4f, grip=%.4f)"
			% [
				str(saw_live_step),
				presentation.character_pose.upper_body_rotation.length(),
				maximum_local_hand_motion,
				maximum_grip_error,
			]
		)
	)
	var presentation_authority := EnemyDestructibleAnatomy.new().configure(
		40023,
		definition.destructible_anatomy
	)
	var presentation_damage := _make_anatomy_damage_event(
		42,
		Vector3(0.0, 1.25, -0.36)
	)
	var presentation_damage_result := presentation_authority.apply_damage_event(
		presentation_damage,
		Transform3D.IDENTITY
	)
	var replicated_anatomy := presentation_authority.state_dict()
	var forced_presence := replicated_anatomy.get("part_presence", {}) as Dictionary
	forced_presence[EnemyDestructibleAnatomy.PART_LEFT_ARM] = false
	replicated_anatomy["part_presence"] = forced_presence
	replicated_anatomy["left_arm"] = false
	var presentation_apply_started := Time.get_ticks_usec()
	presentation.apply_server_state({"anatomy_destruction": replicated_anatomy})
	var presentation_apply_usec := Time.get_ticks_usec() - presentation_apply_started
	presentation.update_presentation(STEP)
	for _surface_frame: int in range(240):
		if not presentation.wound_presentation.has_pending_surface_rebuilds():
			break
		await process_frame
		presentation.update_presentation(STEP)
	presentation.update_presentation(STEP)
	var left_arm_index := presentation.character_skin.skeleton.find_bone(
		&"mixamorig_LeftArm"
	)
	var wound_material := (
		presentation.character_skin.skin_meshes.front().get_surface_override_material(0)
		as ShaderMaterial
	)
	var wound_entries := (
		wound_material.get_shader_parameter(&"wound_entries") as PackedVector4Array
		if wound_material != null
		else PackedVector4Array()
	)
	var wound_axes := (
		wound_material.get_shader_parameter(&"wound_axes") as PackedVector4Array
		if wound_material != null
		else PackedVector4Array()
	)
	var torso_tissue := presentation.wound_presentation.part_surface_nodes.get(
		EnemyDestructibleAnatomy.PART_TORSO
	) as Node3D
	var torso_field := presentation.wound_presentation.part_surface_fields.get(
		EnemyDestructibleAnatomy.PART_TORSO
	) as SparseSdfVolumeData
	var authority_torso_part: Object = presentation_authority.parts.get(
		EnemyDestructibleAnatomy.PART_TORSO
	) as Object
	var authority_torso_field := (
		authority_torso_part.get("field") as SparseSdfVolumeData
		if authority_torso_part != null
		else null
	)
	var tissue_meshes := presentation.wound_presentation.get_part_surface_meshes(
		EnemyDestructibleAnatomy.PART_TORSO
	)
	var tissue_results: Array[Dictionary] = []
	var tissue_color_count := 0
	var brightest_tissue_red := 0.0
	var strongest_tissue_red_dominance := 0.0
	for tissue_mesh: ArrayMesh in tissue_meshes:
		if tissue_mesh == null or tissue_mesh.get_surface_count() <= 0:
			continue
		var tissue_arrays := tissue_mesh.surface_get_arrays(0)
		var tissue_colors := tissue_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		tissue_color_count += tissue_colors.size()
		for tissue_color: Color in tissue_colors:
			brightest_tissue_red = maxf(brightest_tissue_red, tissue_color.r)
			strongest_tissue_red_dominance = maxf(
				strongest_tissue_red_dominance,
				tissue_color.r - maxf(tissue_color.g, tissue_color.b)
			)
		tissue_results.append({
			"vertices": tissue_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array,
			"normals": tissue_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array,
			"indices": tissue_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
		})
	var tissue_audit := DESTRUCTION_MESH_AUDIT.audit_results(tissue_results, torso_field)
	var surface_metrics := presentation.wound_presentation.debug_surface_metrics()
	var simulated_wound_depth := float(
		(presentation.wound_presentation._presented_wounds[0] as Dictionary).get(
			"depth",
			0.0
		)
	)
	_expect(
		presentation.wound_presentation != null
		and presentation.wound_presentation.get_visible_wound_count() == 2
		and wound_material != null
		and int(wound_material.get_shader_parameter(&"wound_count")) == 2
		and wound_entries.size() == EnemyWoundPresentation3D.MAX_WOUNDS
		and wound_axes.size() == EnemyWoundPresentation3D.MAX_WOUNDS
		and wound_entries[0].w > 0.0
		and wound_axes[0].w >= wound_entries[0].w
		and simulated_wound_depth >= SERVICE_9MM.penetration_depth * 0.95
		and wound_axes[0].w < simulated_wound_depth * 0.2
		and wound_axes[0].w <= wound_entries[0].w * 2.0
		and wound_material.shader.code.contains("void vertex()")
		and wound_material.shader.code.contains("wound_axis_distance")
		and wound_material.shader.code.contains("cull_disabled")
		and wound_material.shader.code.contains("FRONT_FACING")
		and wound_material.shader.code.contains("wound_deep_color")
		and not wound_material.shader.code.contains("wound_spheres")
		and torso_tissue != null
		and torso_tissue.visible
		and not tissue_meshes.is_empty()
		and presentation.wound_presentation.get_generated_tissue_triangle_count() > 0
		and tissue_color_count > 0
		and brightest_tissue_red > 0.5
		and strongest_tissue_red_dominance > 0.4
		and presentation.wound_presentation._tissue_material != null
		and presentation.wound_presentation._tissue_material.shader == EnemyWoundPresentation3D.TISSUE_SHADER
		and presentation.wound_presentation._tissue_material.shader.code.contains("EMISSION")
		and torso_field != null
		and bool(presentation_damage_result.get("geometry_changed", false))
		and authority_torso_field != null
		and torso_field.checksum() == authority_torso_field.checksum()
		and presentation_apply_usec < 50000
		and int(surface_metrics.get("full_replay_count", 1)) == 0
		and int(surface_metrics.get("applied_event_count", 0)) == 1
		and not presentation.wound_presentation.has_pending_surface_rebuilds()
		and int(tissue_audit.get("invalid_indices", 1)) == 0
		and int(tissue_audit.get("degenerate_triangles", 1)) == 0
		and int(tissue_audit.get("duplicate_faces", 1)) == 0
		and int(tissue_audit.get("non_manifold_edges", 1)) == 0
		and int(tissue_audit.get("wrong_winding", 1)) == 0
		and int(tissue_audit.get("component_count", 0)) == 1
		and not FileAccess.file_exists("res://shaders/enemy_wound_cavity.gdshader")
		and presentation.character_skin.skeleton.get_bone_pose_scale(left_arm_index).length() < 0.01,
		(
			"replicated anatomy accepts a hit without synchronous replay, then clips the animated shell only after worker-built red SDF tissue is ready (visible=%d count=%s entries=%d axes=%d radius=%.3f depth=%.3f triangles=%d apply=%dus replay=%d arm_scale=%.4f)"
			% [
				presentation.wound_presentation.get_visible_wound_count(),
				str(wound_material.get_shader_parameter(&"wound_count")),
				wound_entries.size(),
				wound_axes.size(),
				wound_entries[0].w if not wound_entries.is_empty() else -1.0,
				wound_axes[0].w if not wound_axes.is_empty() else -1.0,
				presentation.wound_presentation.get_generated_tissue_triangle_count(),
				presentation_apply_usec,
				int(surface_metrics.get("full_replay_count", -1)),
				presentation.character_skin.skeleton.get_bone_pose_scale(left_arm_index).length(),
			]
		)
	)
	presentation.apply_server_state({"alive": false})
	presentation.update_presentation(STEP)
	for _ragdoll_surface_frame: int in range(240):
		if (
			presentation.ragdoll_wound_presentation != null
			and not presentation.ragdoll_wound_presentation.has_pending_surface_rebuilds()
		):
			break
		await process_frame
		presentation.update_presentation(STEP)
	presentation.update_presentation(STEP)
	var ragdoll_skin := presentation.ragdoll.get_authored_skin()
	var ragdoll_left_arm_index := (
		ragdoll_skin.skeleton.find_bone(&"mixamorig_LeftArm")
		if ragdoll_skin != null and ragdoll_skin.skeleton != null
		else -1
	)
	_expect(
		presentation.ragdoll != null
		and presentation.ragdoll.is_active()
		and presentation.ragdoll.has_authored_skin()
		and presentation.ragdoll_wound_presentation != null
		and presentation.ragdoll_wound_presentation.get_visible_wound_count() == 2
		and ragdoll_left_arm_index >= 0
		and ragdoll_skin.skeleton.get_bone_pose_scale(ragdoll_left_arm_index).length() < 0.01
		and not presentation.pose_root.visible,
		"enemy death carries wounds and missing limbs into the weighted authored-body ragdoll instead of healing or becoming grey goo"
	)
	presentation.queue_free()
	await process_frame


func _test_animated_thigh_wound_surface_alignment() -> void:
	# This exercises the exact failure visible in the field report: the analytic right-leg volume is
	# straight, while the rendered thigh is bent and more than ten centimetres behind that box face.
	# A test that only counts red SDF triangles passes even when those triangles float beside intact
	# trousers, so verify the animated shell aperture and shared-SDF cavity in the same world frame.
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var presentation := EnemyHumanoidPresentation3D.new()
	presentation.configure(40117, definition.destructible_anatomy)
	root.add_child(presentation)
	await process_frame
	presentation.apply_server_state({
		"velocity": Vector3(0.0, 0.0, -7.0),
		"on_floor": true,
		"gait_cycle": 1.7,
		"gait_active": true,
		"gait_stride_distance": 2.2,
		"expression_clock": 1.0,
		"alive": true,
		"active": true,
		"flute_pose_weight": 1.0,
	})
	presentation.update_presentation(STEP)
	var authority := EnemyDestructibleAnatomy.new().configure(
		40117,
		definition.destructible_anatomy
	)
	var damage := _make_anatomy_damage_event(
		4117,
		Vector3(0.15, 0.55, -0.36)
	)
	var result := authority.apply_damage_event(damage, Transform3D.IDENTITY)
	presentation.apply_server_state({"anatomy_destruction": authority.state_dict()})
	presentation.update_presentation(STEP)
	for _surface_frame: int in range(240):
		if not presentation.wound_presentation.has_pending_surface_rebuilds():
			break
		await process_frame
		presentation.update_presentation(STEP)
	presentation.update_presentation(STEP)
	var material := (
		presentation.character_skin.skin_meshes.front().get_surface_override_material(0)
		as ShaderMaterial
	)
	var entries := (
		material.get_shader_parameter(&"wound_entries") as PackedVector4Array
		if material != null
		else PackedVector4Array()
	)
	var axes := (
		material.get_shader_parameter(&"wound_axes") as PackedVector4Array
		if material != null
		else PackedVector4Array()
	)
	var wound := (
		presentation.wound_presentation._presented_wounds[0] as Dictionary
		if not presentation.wound_presentation._presented_wounds.is_empty()
		else {}
	)
	var frame := presentation.wound_presentation._resolve_wound_world_frame(wound)
	var alignment := presentation.wound_presentation.debug_surface_alignment()
	var entry := Vector3(entries[0].x, entries[0].y, entries[0].z) if not entries.is_empty() else Vector3.INF
	var axis := Vector3(axes[0].x, axes[0].y, axes[0].z) if not axes.is_empty() else Vector3.ZERO
	var resolved_entry: Vector3 = frame.get("position", Vector3.ZERO)
	var resolved_direction: Vector3 = frame.get("direction", Vector3.ZERO)
	var radius := float(wound.get("radius", 0.0))
	var aperture_radius := entries[0].w if not entries.is_empty() else 0.0
	var simulated_depth := float(wound.get("depth", 0.0))
	var shell_aperture_depth := axes[0].w if not axes.is_empty() else INF
	_expect(
		bool(result.get("geometry_changed", false))
		and StringName(str(result.get("part_id", &""))) == EnemyDestructibleAnatomy.PART_RIGHT_LEG
		and int(alignment.get("attached_wounds", 0)) == 1
		and float(alignment.get("maximum_legacy_offset", 0.0)) > 0.08
		and float(alignment.get("maximum_chunk_anchor_error", INF)) < 0.0001
		and float(alignment.get("minimum_tissue_distance", INF)) <= aperture_radius
		and aperture_radius >= float(alignment.get("maximum_mouth_radius", INF)) + 0.002
		and aperture_radius <= radius + 0.011
		and simulated_depth >= SERVICE_9MM.penetration_depth * 0.95
		and shell_aperture_depth < simulated_depth * 0.2
		and shell_aperture_depth <= aperture_radius * 2.0
		and entry.distance_to(resolved_entry) < 0.0001
		and axis.normalized().dot(resolved_direction.normalized()) > 0.999,
		(
			"a thigh bullet attaches the animated aperture and shared-SDF cavity to the same skinned triangle instead of leaving intact trousers beside red tissue (legacy_offset=%.3f anchor_error=%.6f tissue_distance=%.4f mouth=%.4f radius=%.4f aperture=%.4f)"
			% [
				float(alignment.get("maximum_legacy_offset", -1.0)),
				float(alignment.get("maximum_chunk_anchor_error", -1.0)),
				float(alignment.get("minimum_tissue_distance", -1.0)),
				float(alignment.get("maximum_mouth_radius", -1.0)),
				radius,
				aperture_radius,
			]
		)
	)
	var initial_local_entry := presentation.to_local(resolved_entry)
	for _motion_frame: int in range(18):
		presentation.position += Vector3(0.0, 0.0, -7.0) * STEP
		presentation.update_presentation(STEP)
	var moving_material := (
		presentation.character_skin.skin_meshes.front().get_surface_override_material(0)
		as ShaderMaterial
	)
	var moving_entries := moving_material.get_shader_parameter(&"wound_entries") as PackedVector4Array
	var moving_entry := Vector3(moving_entries[0].x, moving_entries[0].y, moving_entries[0].z)
	var moving_alignment := presentation.wound_presentation.debug_surface_alignment()
	_expect(
		presentation.to_local(moving_entry).distance_to(initial_local_entry) > 0.002
		and float(moving_alignment.get("maximum_chunk_anchor_error", INF)) < 0.0001,
		"the wound remains attached to the deformed thigh through procedural gait instead of lagging behind the animated skin"
	)
	presentation.queue_free()
	await process_frame


func _test_incremental_wound_presentation_budget() -> void:
	var definition := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var presentation := EnemyHumanoidPresentation3D.new()
	presentation.configure(40024, definition.destructible_anatomy)
	root.add_child(presentation)
	await process_frame
	var authority := EnemyDestructibleAnatomy.new().configure(
		40024,
		definition.destructible_anatomy
	)
	var maximum_apply_usec := 0
	for hit_index: int in range(6):
		var damage := _make_anatomy_damage_event(
			5000 + hit_index,
			Vector3(-0.13 + float(hit_index) * 0.052, 1.08, -0.36)
		)
		authority.apply_damage_event(damage, Transform3D.IDENTITY)
		var started_usec := Time.get_ticks_usec()
		presentation.apply_server_state({"anatomy_destruction": authority.state_dict()})
		maximum_apply_usec = maxi(
			maximum_apply_usec,
			Time.get_ticks_usec() - started_usec
		)
		presentation.update_presentation(STEP)
	for _surface_frame: int in range(300):
		if not presentation.wound_presentation.has_pending_surface_rebuilds():
			break
		await process_frame
		presentation.update_presentation(STEP)
	presentation.update_presentation(STEP)
	var metrics := presentation.wound_presentation.debug_surface_metrics()
	var authority_torso = authority.parts.get(EnemyDestructibleAnatomy.PART_TORSO)
	var presentation_torso := presentation.wound_presentation.part_surface_fields.get(
		EnemyDestructibleAnatomy.PART_TORSO
	) as SparseSdfVolumeData
	_expect(
		maximum_apply_usec < 75000
		and int(metrics.get("full_replay_count", 1)) == 0
		and int(metrics.get("applied_event_count", 0)) == 6
		and int(metrics.get("rebuild_count", 0)) > 0
		and not presentation.wound_presentation.has_pending_surface_rebuilds()
		and presentation.wound_presentation.get_visible_wound_count() == 6
		and presentation.wound_presentation.get_generated_tissue_triangle_count() > 0
		and authority_torso != null
		and presentation_torso != null
		and presentation_torso.checksum() == authority_torso.field.checksum(),
		(
			"six sequential firearm hits stay incremental and worker-contoured instead of replaying full anatomy on every packet (max_apply=%dus replay=%d events=%d rebuilds=%d)"
			% [
				maximum_apply_usec,
				int(metrics.get("full_replay_count", -1)),
				int(metrics.get("applied_event_count", -1)),
				int(metrics.get("rebuild_count", -1)),
			]
		)
	)
	presentation.queue_free()
	await process_frame


func _presentation_bone_world_position(
	presentation: EnemyHumanoidPresentation3D,
	bone_name: StringName
) -> Vector3:
	var skeleton := presentation.character_skin.skeleton
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3(INF, INF, INF)
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(bone_index)
	).origin


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("Assertion failed: %s" % message)
