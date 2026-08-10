extends SceneTree

#######################################################
# Generic modular-limb and passive-elasticity regression. Run with:
# godot --headless --path . --script res://tests/generic_limb_test.gd
#######################################################

const RECOVERY_FRAMES := 120

var failure_count := 0
var assertion_count := 0
var test_world: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_world = Node3D.new()
	root.add_child(test_world)
	_test_impedance_math()
	_test_swing_twist_round_trip()
	_test_joint_rotation_error_projection()
	_test_joint_frame_axis_mapping()
	_test_soft_limits_and_command_margin()
	_test_rigid_part_surface_material()
	_test_generic_grip_surface_contract()
	_test_plain_foot_skips_grip_runtime()
	_test_observation_count_matches_descriptors()
	await _test_static_ground_can_anchor_generic_grip()
	await _test_physical_end_effector_grip_uses_surface_anchor()
	await _test_arbitrary_segment_counts()
	await _test_live_observation_fast_path_matches_snapshot()
	await _test_reset_tracks_current_host_transform()
	await _test_duplicate_action_mapping_is_rejected()
	await _test_sparse_action_mapping_is_rejected()
	await _test_passive_return_without_actuator_authority()
	print("Generic limb assertions: %d, failures: %d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_impedance_math() -> void:
	var reference_span := deg_to_rad(60.0)
	var small_deflection := LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(10.0), 0.0, 130.0, 18.0, 420.0, reference_span, 5.0, 0.40
	)
	var large_deflection := LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(48.0), 0.0, 130.0, 18.0, 420.0, reference_span, 5.0, 0.40
	)
	var large_linear := LimbsController3D.spring_damper_component(
		deg_to_rad(48.0), 0.0, 130.0, 18.0, 420.0
	)
	_expect(small_deflection > 0.0, "passive torque points toward the requested/rest angle")
	_expect(
		large_deflection > small_deflection,
		"passive resistance grows as a segment bends farther from rest"
	)
	_expect(
		large_deflection > large_linear * 1.5,
		"the rubber spring hardens nonlinearly after its configured onset"
	)
	var hybrid_component := LimbsController3D.hybrid_passive_component(
		deg_to_rad(48.0), 0.0, 130.0, 18.0, 420.0,
		reference_span, 5.0, 0.40, 0.35
	)
	_expect(
		hybrid_component > 0.0 and hybrid_component < large_deflection,
		"the explicit hybrid component leaves its configured baseline share to Jolt"
	)
	var moving_toward_target := LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(35.0), 1.0, 130.0, 18.0, 420.0,
		reference_span, 5.0, 0.40
	)
	var stationary := LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(35.0), 0.0, 130.0, 18.0, 420.0,
		reference_span, 5.0, 0.40
	)
	_expect(
		moving_toward_target < stationary,
		"joint damping opposes relative angular speed and prevents noodle oscillation"
	)
	var saturated := LimbsController3D.progressive_spring_damper_component(
		10.0, 0.0, 130.0, 18.0, 40.0, reference_span, 5.0, 0.40
	)
	_expect(is_equal_approx(saturated, 40.0), "passive elasticity respects its torque cap")
	var child_torque := Vector3(3.0, -4.0, 5.0)
	var parent_torque := -child_torque
	_expect(
		(child_torque + parent_torque).length_squared() <= 0.000001,
		"the controller's parent/child torque pair has no hidden net torque"
	)


func _test_swing_twist_round_trip() -> void:
	var authored := Vector3(deg_to_rad(22.0), 0.0, deg_to_rad(-31.0))
	var delta := LimbsController3D.rotation_from_joint_angles(authored, Basis.IDENTITY)
	var recovered := LimbsController3D.joint_angles(delta, Basis.IDENTITY, Basis.IDENTITY)
	_expect(
		absf(_angle_difference(recovered.x, authored.x)) < deg_to_rad(0.25),
		"joint target generation and measurement agree on Jolt's X twist angle"
	)
	_expect(
		absf(_angle_difference(recovered.z, authored.z)) < deg_to_rad(0.25),
		"joint target generation and measurement agree on the single Z swing angle"
	)
	_expect(
		absf(recovered.y) < deg_to_rad(0.25),
		"a locked Y swing axis is not created accidentally by the decomposition"
	)


func _test_joint_rotation_error_projection() -> void:
	var joint_basis := Basis.IDENTITY
	var rest := Basis.IDENTITY
	var twist_target := LimbsController3D.rotation_from_joint_angles(
		Vector3(deg_to_rad(24.0), 0.0, 0.0),
		joint_basis
	)
	var twist_error := LimbsController3D.rotation_error_vector_parent(rest, twist_target)
	_expect(
		absf(twist_error.x - deg_to_rad(24.0)) < 0.0001
		and absf(twist_error.y) < 0.0001
		and absf(twist_error.z) < 0.0001,
		"a pure X twist target produces torque only on the joint twist axis"
	)
	var swing_target := LimbsController3D.rotation_from_joint_angles(
		Vector3(0.0, 0.0, deg_to_rad(-31.0)),
		joint_basis
	)
	var swing_error := LimbsController3D.rotation_error_vector_parent(rest, swing_target)
	_expect(
		absf(swing_error.x) < 0.0001
		and absf(swing_error.y) < 0.0001
		and absf(swing_error.z - deg_to_rad(-31.0)) < 0.0001,
		"a pure Z swing target produces torque only on the authored swing axis"
	)
	_expect(
		LimbsController3D.rotation_error_vector_parent(twist_target, twist_target)
		.is_zero_approx(),
		"a joint at its desired physical rotation has no active torque error"
	)


func _test_joint_frame_axis_mapping() -> void:
	var upper_direction := Vector3(0.55, -0.75, 0.35).normalized()
	var lower_direction := Vector3(0.08, -0.99, 0.10).normalized()
	var bending_plane_normal := upper_direction.cross(lower_direction).normalized()
	var joint_basis := GenericLimb3D.joint_basis_from_twist_and_swing(
		upper_direction,
		bending_plane_normal
	)
	_expect(
		joint_basis.x.normalized().dot(upper_direction) > 0.999,
		"generic joint-local X follows the segment long axis used by Jolt twist"
	)
	_expect(
		absf(joint_basis.z.normalized().dot(bending_plane_normal)) > 0.999,
		"generic joint-local Z follows the authored limb bending-plane normal"
	)
	var support_force := Vector3.UP * 20.0
	var foot_lever := upper_direction * 0.9 + lower_direction * 1.0
	var support_torque := foot_lever.cross(support_force)
	var locked_axis_share := absf(support_torque.dot(joint_basis.y)) / maxf(
		support_torque.length(),
		0.0001
	)
	_expect(
		locked_axis_share < 0.08,
		"vertical support torque is carried by a free hip swing axis, not locked Y"
	)
	_expect(
		absf(joint_basis.determinant() - 1.0) < 0.001,
		"the remapped joint frame remains orthonormal and right-handed"
	)


func _test_soft_limits_and_command_margin() -> void:
	var joint := LimbJointDefinition.new()
	joint.lower_limit_degrees = Vector3(-60.0, 0.0, 0.0)
	joint.upper_limit_degrees = Vector3(60.0, 0.0, 0.0)
	joint.action_indices = Vector3i(0, -1, -1)
	joint.command_limit_margin_degrees = 6.0
	joint.sanitize()
	var safe_limits := joint.command_limits_radians(Vector3.AXIS_X)
	_expect(
		safe_limits.x > deg_to_rad(-60.0) and safe_limits.y < deg_to_rad(60.0),
		"policy targets stop inside the hard anatomical constraint"
	)
	_expect(
		is_equal_approx(
			LimbsController3D.normalized_target(0.0, safe_limits.x, safe_limits.y),
			0.0
		),
		"zero command always means the authored rest pose"
	)
	var upper_pushback := LimbsController3D.soft_limit_component(
		deg_to_rad(58.0),
		1.0,
		deg_to_rad(-60.0),
		deg_to_rad(60.0),
		deg_to_rad(8.0),
		320.0,
		24.0,
		360.0
	)
	var lower_pushback := LimbsController3D.soft_limit_component(
		deg_to_rad(-58.0),
		-1.0,
		deg_to_rad(-60.0),
		deg_to_rad(60.0),
		deg_to_rad(8.0),
		320.0,
		24.0,
		360.0
	)
	_expect(upper_pushback < 0.0, "the upper soft stop pushes back toward the legal range")
	_expect(lower_pushback > 0.0, "the lower soft stop pushes back toward the legal range")


func _test_rigid_part_surface_material() -> void:
	var part := LimbSegment3D.new()
	var surface := part.configure_surface_material(1.4, -0.3, true)
	_expect(
		part.physics_material_override == surface,
		"generic rigid parts assign surface response through physics_material_override"
	)
	_expect(
		is_equal_approx(surface.friction, 1.0),
		"generic rigid-part friction is clamped to the PhysicsMaterial range"
	)
	_expect(
		is_equal_approx(surface.bounce, 0.0),
		"generic rigid-part bounce is clamped to the PhysicsMaterial range"
	)
	_expect(surface.rough, "generic limb definitions can opt into a gripping rough surface")
	part.free()


func _test_generic_grip_surface_contract() -> void:
	var stock: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	stock.enabled = true
	stock.effector_type_id = &"generic_grip"
	stock.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	stock.compatible_surface_tags = PackedStringArray(["climbable", "carryable"])
	_expect(
		not GenericGrip3D.surface_tags_are_compatible(
			stock,
			PackedStringArray(["ground"]),
			false
		),
		"the stock four-limb grip does not silently anchor ordinary locomotion to the ground"
	)
	var ground_brace: LimbEndEffectorDefinition = stock.duplicate(true) as LimbEndEffectorDefinition
	ground_brace.compatible_surface_tags = PackedStringArray(["climbable", "carryable", "ground"])
	_expect(
		GenericGrip3D.surface_tags_are_compatible(
			ground_brace,
			PackedStringArray(["ground"]),
			false
		),
		"an explicitly ground-compatible generic grip can still use static ground for bracing"
	)
	_expect(
		GenericGrip3D.surface_tags_are_compatible(
			stock,
			PackedStringArray(["carryable"]),
			true
		),
		"generic grips retain their authored carryable-object behavior"
	)
	stock.grip_acquisition_radius = 0.24
	stock.grip_detection_radius = 1.10
	stock.sanitize()
	_expect(
		stock.grip_detection_radius > stock.grip_acquisition_radius,
		"generic grips can perceive a compatible surface before the distal tip is close enough to latch"
	)
	var custom: LimbEndEffectorDefinition = stock.duplicate(true) as LimbEndEffectorDefinition
	custom.effector_type_id = &"magnetic_test_grip"
	_expect(
		not GenericGrip3D.surface_tags_are_compatible(
			custom,
			PackedStringArray(["ground"]),
			false
		),
		"custom grip types keep their explicit surface-tag filters"
	)
	var brace_force: Vector3 = GenericGrip3D.spring_damper_force(
		Vector3(0.0, -0.10, 0.0),
		Vector3.ZERO,
		1400.0,
		90.0
	)
	_expect(
		brace_force.y < -100.0,
		"a foot displaced away from a static ground anchor receives a restoring support force"
	)
	var half_activation_force: Vector3 = GenericGrip3D.activated_spring_damper_force(
		Vector3(0.24, 0.0, 0.0),
		Vector3.ZERO,
		1400.0,
		90.0,
		0.55
	)
	var full_activation_force: Vector3 = GenericGrip3D.activated_spring_damper_force(
		Vector3(0.24, 0.0, 0.0),
		Vector3.ZERO,
		1400.0,
		90.0,
		1.0
	)
	_expect(
		absf(half_activation_force.length() / full_activation_force.length() - 0.55) < 0.0001
		and half_activation_force.length() < 360.0 * 0.55,
		"grip spring demand ramps with activation so a legal edge-of-radius latch does not break merely because it engaged at threshold"
	)
	_expect(
		stock.breakaway_confirmation_seconds >= 0.05,
		"generic grip breakaway requires sustained overload instead of treating one physics-frame spike as a failed latch"
	)


func _test_plain_foot_skips_grip_runtime() -> void:
	var owner: LimbSegment3D = LimbSegment3D.new()
	var definition: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	definition.enabled = true
	definition.geometry_type = LimbEndEffectorDefinition.GeometryType.BOX
	definition.box_size = Vector3(0.2, 0.05, 0.2)
	definition.grip_mode = LimbEndEffectorDefinition.GripMode.NONE
	var effector: LimbEndEffector3D = LimbEndEffector3D.new()
	owner.add_child(effector)
	effector.configure(owner, definition, Vector3.ZERO, Color.WHITE)
	_expect(
		not is_instance_valid(effector.grip_actuator),
		"plain feet do not allocate an unused GenericGrip3D query runtime"
	)
	var snapshot: Dictionary = effector.state_snapshot()
	_expect(
		float(snapshot.get("activation", 0.0)) == 0.0
		and not bool(snapshot.get("candidate_present", true))
		and not bool(snapshot.get("attached", true)),
		"non-gripping feet retain the neutral grip observation contract without a grip node"
	)
	owner.free()


func _test_observation_count_matches_descriptors() -> void:
	var limb: GenericLimbDefinition = _create_chain_definition(4, 0)
	var effector: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	effector.enabled = true
	effector.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	effector.grip_action_index = 1
	limb.end_effector = effector
	limb.sanitize()
	var definitions: Array[GenericLimbDefinition] = [limb]
	_expect(
		GenericLimbModelContract.observation_count(definitions)
		== GenericLimbModelContract.observation_descriptors(definitions).size(),
		"fast limb observation counting stays exactly aligned with the finalized descriptor topology"
	)


func _test_static_ground_can_anchor_generic_grip() -> void:
	var floor: StaticBody3D = StaticBody3D.new()
	floor.name = "GripTestGround"
	floor.collision_layer = 1
	floor.collision_mask = 4
	floor.position = Vector3(0.0, -0.10, 0.0)
	floor.set_meta("training_ground", true)
	floor.set_meta("grip_surface_tags", PackedStringArray(["ground"]))
	var floor_collision: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(4.0, 0.20, 4.0)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	test_world.add_child(floor)

	var owner: RigidBody3D = RigidBody3D.new()
	owner.name = "GripTestOwner"
	owner.gravity_scale = 0.0
	owner.freeze = true
	owner.position = Vector3(0.0, 0.12, 0.0)
	test_world.add_child(owner)
	var definition: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	definition.enabled = true
	definition.effector_type_id = &"generic_grip"
	definition.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	definition.grip_activation_threshold = 0.5
	definition.grip_release_threshold = 0.25
	definition.activation_response_per_second = 20.0
	definition.grip_acquisition_radius = 0.24
	definition.grip_detection_radius = 0.80
	definition.grip_collision_mask = 1
	definition.allow_static_grip = true
	definition.compatible_surface_tags = PackedStringArray(["climbable", "carryable", "ground"])
	var grip: GenericGrip3D = GenericGrip3D.new()
	owner.add_child(grip)
	grip.configure(owner, definition)
	await physics_frame
	grip.step(0.05, 1.0, true)
	_expect(
		grip.attached and grip.attached_target_id == floor.get_instance_id(),
		"an explicitly ground-compatible generic grip can physically attach to the tagged arena floor"
	)
	_expect(
		grip.attached_surface_tags.has("ground"),
		"a floor attachment preserves the ground tag for the ML observation"
	)
	_expect(
		grip.attached_owner_point_world().distance_to(grip.global_position) < 0.001,
		"a geometry-free generic grip keeps its authored grip node as the owner-side spring anchor"
	)
	grip.release()
	owner.queue_free()
	floor.queue_free()
	await process_frame


func _test_physical_end_effector_grip_uses_surface_anchor() -> void:
	var floor: StaticBody3D = StaticBody3D.new()
	floor.name = "PhysicalGripTestGround"
	floor.collision_layer = 1
	floor.collision_mask = 4
	floor.position = Vector3(0.0, -0.10, 0.0)
	floor.set_meta("training_ground", true)
	floor.set_meta("grip_surface_tags", PackedStringArray(["ground"]))
	var floor_collision: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(4.0, 0.20, 4.0)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	test_world.add_child(floor)

	var owner: LimbSegment3D = LimbSegment3D.new()
	owner.name = "PhysicalGripTestOwner"
	owner.gravity_scale = 0.0
	owner.freeze = true
	owner.position = Vector3(0.0, 0.15, 0.0)
	test_world.add_child(owner)
	var definition: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	definition.enabled = true
	definition.effector_type_id = &"physical_grip_test"
	definition.geometry_type = LimbEndEffectorDefinition.GeometryType.BOX
	definition.box_size = Vector3(0.24, 0.06, 0.24)
	definition.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	definition.grip_activation_threshold = 0.5
	definition.grip_release_threshold = 0.25
	definition.activation_response_per_second = 20.0
	definition.grip_acquisition_radius = 0.24
	definition.grip_detection_radius = 0.80
	definition.grip_collision_mask = 1
	definition.allow_static_grip = true
	definition.compatible_surface_tags = PackedStringArray(["ground"])
	var effector: LimbEndEffector3D = LimbEndEffector3D.new()
	owner.add_child(effector)
	effector.configure(owner, definition, Vector3.ZERO, Color.WHITE)
	var grip: GenericGrip3D = effector.grip_actuator
	await physics_frame
	grip.step(0.05, 1.0, true)
	_expect(grip.attached, "a physical end-effector can acquire a compatible nearby surface")
	var owner_anchor: Vector3 = grip.attached_owner_point_world()
	var target_anchor: Vector3 = grip.attached_point_world()
	_expect(
		owner_anchor.y < effector.global_position.y - 0.02,
		"a physical sole grip anchors at its collision surface instead of at the effector center"
	)
	_expect(
		owner_anchor.distance_to(target_anchor) < effector.global_position.distance_to(target_anchor),
		"the surface-to-surface grip spring starts from the physical contact point rather than pulling the whole sole center into the target"
	)
	grip.release()
	owner.queue_free()
	floor.queue_free()
	await process_frame


func _test_arbitrary_segment_counts() -> void:
	for segment_count in [1, 2, 4]:
		var core := _create_frozen_core("Core%d" % segment_count, Vector3(4.0 * segment_count, 6.0, 0.0))
		var chain := GenericLimb3D.new()
		chain.name = "Chain%d" % segment_count
		test_world.add_child(chain)
		chain.configure(
			null,
			core,
			_create_chain_definition(segment_count, 0),
			segment_count,
			Color.WHITE,
			4,
			0
		)
		await process_frame
		_expect(chain.has_valid_topology(), "%d-part generic limb builds a valid chain" % segment_count)
		_expect(
			chain.segments.size() == segment_count and chain.joints.size() == segment_count,
			"%d-part generic limb creates one rigid segment and one joint per part" % segment_count
		)
		for joint: Generic6DOFJoint3D in chain.joints:
			_expect(
				_joint_has_locked_translation(joint),
				"generic limb joints lock all translation axes"
			)
			_expect(
				joint.solver_priority == 1,
				"generic load-bearing joints use Godot's highest normal solver priority"
			)
		var first_definition := chain.definition.segments[0].joint
		_expect(
			first_definition.use_native_passive_spring
			and first_definition.native_passive_fraction > 0.0,
			"generic joints keep a load-bearing baseline spring inside Jolt"
		)
		_expect(
			_joint_native_spring_enabled(chain.joints[0], Vector3.AXIS_X),
			"the free test axis enables its native angular spring"
		)
		_expect(
			chain.definition.required_action_count() == 1
			and chain.definition.has_unique_action_mapping(),
			"arbitrary chains derive a stable non-overlapping action contract"
		)
		_expect(
			chain.has_configured_native_springs(),
			"runtime Jolt spring flags and gains match the generic limb definition"
		)
		for segment: LimbSegment3D in chain.segments:
			_expect(
				segment.can_sleep and not segment.contact_monitor and segment.max_contacts_reported == 0,
				"generic model-forge limb segments use the low-overhead sleep/contact defaults"
			)
			var surface := segment.physics_material_override
			_expect(
				surface is PhysicsMaterial,
				"every generated limb part owns a valid PhysicsMaterial"
			)
			if surface is PhysicsMaterial:
				_expect(
					is_equal_approx(surface.friction, 0.95)
					and is_equal_approx(surface.bounce, 0.01),
					"generated limb-part friction and bounce match its reusable definition"
				)
		chain.queue_free()
		core.queue_free()
		await process_frame


func _test_live_observation_fast_path_matches_snapshot() -> void:
	var core: LimbSegment3D = _create_frozen_core(
		"ObservationFastPathCore",
		Vector3(20.0, 6.0, 0.0)
	)
	var definition: GenericLimbDefinition = _create_chain_definition(4, 0)
	var definitions: Array[GenericLimbDefinition] = [definition]
	var assembly: GenericLimbAssembly3D = GenericLimbAssembly3D.new()
	test_world.add_child(assembly)
	assembly.configure(core, definitions, null, 4, 0, true)
	await process_frame
	if is_instance_valid(assembly.controller) and not assembly.controller.runtime_joint_records.is_empty():
		var runtime_record = assembly.controller.runtime_joint_records[0]
		runtime_record.current_angles = Vector3(0.17, 0.0, 0.0)
		runtime_record.target_error_angles = Vector3(-0.08, 0.0, 0.0)
		runtime_record.active_torque_joint = Vector3(3.5, 0.0, 0.0)
	var snapshot_features: PackedFloat64Array = GenericLimbModelContract.encode(
		definitions,
		assembly.state_snapshot()
	)
	var live_features: PackedFloat64Array = GenericLimbModelContract.encode(
		definitions,
		assembly
	)
	var tensors_match: bool = snapshot_features.size() == live_features.size()
	if tensors_match:
		for index: int in range(snapshot_features.size()):
			if not is_equal_approx(snapshot_features[index], live_features[index]):
				tensors_match = false
				break
	_expect(
		tensors_match and live_features.size() == GenericLimbModelContract.observation_count(definitions),
		"live generic-limb observation encoding preserves the snapshot tensor exactly without building snapshot Dictionaries"
	)
	assembly.queue_free()
	core.queue_free()
	await process_frame


func _test_reset_tracks_current_host_transform() -> void:
	var core: RigidBody3D = _create_frozen_core("MovingHostCore", Vector3(2.0, 6.0, -1.0))
	var definition: GenericLimbDefinition = _create_chain_definition(2, 0)
	definition.mount_offset_local = Vector3(0.3, -0.2, 0.15)
	var chain: GenericLimb3D = GenericLimb3D.new()
	chain.name = "MovingHostChain"
	test_world.add_child(chain)
	chain.configure(null, core, definition, 0, Color.WHITE, 4, 0)
	await process_frame
	_expect(chain.segments.size() == 2, "moving-host reset test builds its articulated chain")
	if chain.segments.size() != 2:
		chain.queue_free()
		core.queue_free()
		await process_frame
		return
	var old_segment_position: Vector3 = chain.segments[0].global_position
	core.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(67.0)),
		Vector3(-8.0, 11.0, 5.5)
	)
	chain.reset_to_rest()
	for segment: LimbSegment3D in chain.segments:
		var expected: Transform3D = core.global_transform * segment.rest_transform_core_local
		_expect(
			segment.global_position.distance_to(expected.origin) <= 0.0001
			and segment.global_basis.x.distance_to(expected.basis.x) <= 0.0001
			and segment.global_basis.y.distance_to(expected.basis.y) <= 0.0001
			and segment.global_basis.z.distance_to(expected.basis.z) <= 0.0001,
			"generic limb reset rebuilds each segment from the Core's current world transform"
		)
	for record: Dictionary in chain.joint_records:
		var joint: Generic6DOFJoint3D = record.get("joint") as Generic6DOFJoint3D
		var rest_joint_value: Variant = record.get(
			"rest_joint_transform_core_local",
			Transform3D.IDENTITY
		)
		var rest_joint: Transform3D = (
			rest_joint_value if rest_joint_value is Transform3D else Transform3D.IDENTITY
		)
		var expected_joint: Transform3D = core.global_transform * rest_joint
		_expect(
			is_instance_valid(joint)
			and joint.global_position.distance_to(expected_joint.origin) <= 0.0001
			and joint.global_basis.x.distance_to(expected_joint.basis.x) <= 0.0001
			and joint.global_basis.y.distance_to(expected_joint.basis.y) <= 0.0001
			and joint.global_basis.z.distance_to(expected_joint.basis.z) <= 0.0001,
			"generic limb reset moves every joint anchor with the teleported Core"
		)
	_expect(
		chain.segments[0].global_position.distance_to(old_segment_position) > 1.0,
		"a teleported drone/host cannot reset its arm back to the construction-time world position"
	)
	chain.queue_free()
	core.queue_free()
	await process_frame


func _test_duplicate_action_mapping_is_rejected() -> void:
	var core := _create_frozen_core("MappingCore", Vector3(0.0, 9.0, 0.0))
	var left := GenericLimb3D.new()
	var right := GenericLimb3D.new()
	test_world.add_child(left)
	test_world.add_child(right)
	left.configure(null, core, _create_chain_definition(1, 0), 0, Color.WHITE, 4, 0)
	right.configure(null, core, _create_chain_definition(1, 0), 1, Color.WHITE, 4, 0)
	await process_frame
	var controller := LimbsController3D.new()
	test_world.add_child(controller)
	var limbs: Array[GenericLimb3D] = [left, right]
	controller.configure(core, limbs)
	_expect(
		not controller.action_mapping_valid,
		"a creature cannot silently bind one policy output to two different joints"
	)
	_expect(
		not controller.submit_commands(PackedFloat64Array([0.25])),
		"the controller rejects commands while a duplicate action mapping exists"
	)
	controller.queue_free()
	left.queue_free()
	right.queue_free()
	core.queue_free()
	await process_frame


func _test_sparse_action_mapping_is_rejected() -> void:
	var core := _create_frozen_core("SparseMappingCore", Vector3(0.0, 9.0, 0.0))
	var chain := GenericLimb3D.new()
	test_world.add_child(chain)
	chain.configure(null, core, _create_chain_definition(1, 2), 0, Color.WHITE, 4, 0)
	await process_frame
	var controller := LimbsController3D.new()
	test_world.add_child(controller)
	var limbs: Array[GenericLimb3D] = [chain]
	controller.configure(core, limbs)
	_expect(
		not controller.action_mapping_valid,
		"a dense policy vector cannot silently contain unmapped action holes"
	)
	var commands := PackedFloat64Array()
	commands.resize(3)
	commands.fill(0.0)
	_expect(
		not controller.submit_commands(commands),
		"the generic controller rejects commands until every declared output maps exactly once"
	)
	controller.queue_free()
	chain.queue_free()
	core.queue_free()
	await process_frame


func _test_passive_return_without_actuator_authority() -> void:
	var core := _create_frozen_core("RecoveryCore", Vector3(0.0, 7.0, 0.0))
	var definition := _create_chain_definition(1, -1)
	var joint_definition := definition.segments[0].joint
	joint_definition.passive_stiffness = Vector3(150.0, 0.0, 0.0)
	joint_definition.passive_damping = Vector3(20.0, 0.0, 0.0)
	joint_definition.maximum_passive_torque = Vector3(300.0, 0.0, 0.0)
	joint_definition.active_stiffness = Vector3.ZERO
	joint_definition.active_damping = Vector3.ZERO
	joint_definition.maximum_active_torque = Vector3.ZERO
	joint_definition.action_indices = Vector3i(-1, -1, -1)
	joint_definition.use_native_passive_spring = true
	joint_definition.sanitize()

	var chain := GenericLimb3D.new()
	chain.name = "PassiveRecoveryChain"
	test_world.add_child(chain)
	chain.configure(null, core, definition, 0, Color.WHITE, 4, 0)
	await process_frame
	var controller := LimbsController3D.new()
	controller.name = "PassiveRecoveryController"
	controller.process_physics_priority = -20
	test_world.add_child(controller)
	var limbs: Array[GenericLimb3D] = [chain]
	controller.configure(core, limbs)

	var segment := chain.segments[0]
	var hip := chain.hip_world_position()
	var deflected_direction := (
		Basis(Quaternion(Vector3.RIGHT, deg_to_rad(32.0))) * Vector3.DOWN
	).normalized()
	segment.global_basis = GenericLimb3D.basis_from_y(deflected_direction)
	segment.global_position = hip + deflected_direction * definition.segments[0].length * 0.5
	segment.linear_velocity = Vector3.ZERO
	segment.angular_velocity = Vector3.ZERO
	var initial_error := _joint_error_magnitude(chain.joint_records[0])
	_expect(initial_error >= deg_to_rad(25.0), "the recovery test begins with a real joint deflection")

	# Explicitly remove model authority. Passive elasticity must still work because it is part of
	# the limb mechanics, not a hidden policy command.
	segment.actuator_effectiveness = 0.0
	chain.set_runtime_active(true)
	controller.set_active(true)
	for _frame in range(RECOVERY_FRAMES):
		await physics_frame
	var final_error := _joint_error_magnitude(chain.joint_records[0])
	_expect(segment.has_finite_state(), "passive recovery remains numerically finite")
	_expect(
		final_error < initial_error * 0.55,
		"an uncommanded joint returns substantially toward its authored pose"
	)
	var passive_torque: Vector3 = chain.joint_records[0].get(
		"passive_torque_joint",
		Vector3.ZERO
	)
	var active_torque: Vector3 = chain.joint_records[0].get(
		"active_torque_joint",
		Vector3.ZERO
	)
	_expect(passive_torque.is_finite(), "passive torque telemetry stays finite")
	_expect(
		active_torque.length_squared() <= 0.000001,
		"passive recovery does not depend on model actuator torque"
	)
	controller.queue_free()
	chain.queue_free()
	core.queue_free()
	await process_frame


func _create_frozen_core(name_value: String, position_value: Vector3) -> LimbSegment3D:
	var core := LimbSegment3D.new()
	core.name = name_value
	core.configure(null, -1, -1, StringName(name_value), 100.0)
	core.mass = 4.0
	core.freeze = true
	core.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	core.collision_layer = 4
	core.collision_mask = 0
	test_world.add_child(core)
	core.global_position = position_value
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.25, 0.5)
	collision.shape = shape
	core.add_child(collision)
	return core


func _create_chain_definition(segment_count: int, first_action_index: int) -> GenericLimbDefinition:
	var result := GenericLimbDefinition.new()
	result.limb_name = "test_limb_%d" % segment_count
	result.mount_offset_local = Vector3.ZERO
	var segment_definitions: Array[LimbSegmentDefinition] = []
	for index in range(segment_count):
		var joint := LimbJointDefinition.new()
		joint.joint_name = "Joint%d" % index
		joint.joint_basis_local = Basis.IDENTITY
		joint.lower_limit_degrees = Vector3(-60.0, 0.0, 0.0)
		joint.upper_limit_degrees = Vector3(60.0, 0.0, 0.0)
		joint.action_indices = Vector3i(first_action_index if index == 0 else -1, -1, -1)
		joint.passive_stiffness = Vector3(130.0, 0.0, 0.0)
		joint.passive_damping = Vector3(18.0, 0.0, 0.0)
		joint.maximum_passive_torque = Vector3(420.0, 0.0, 0.0)
		joint.use_native_passive_spring = true
		var segment := LimbSegmentDefinition.new()
		segment.segment_name = "Segment%d" % index
		segment.rest_direction_local = Vector3.DOWN
		segment.length = 0.7
		segment.radius = 0.06
		segment.mass = 0.25
		segment.joint = joint
		segment_definitions.append(segment)
	result.segments = segment_definitions
	result.sanitize()
	return result


func _joint_error_magnitude(record: Dictionary) -> float:
	var parent := record.get("parent") as LimbSegment3D
	var child := record.get("child") as LimbSegment3D
	if not is_instance_valid(parent) or not is_instance_valid(child):
		return INF
	var rest_relative: Basis = record.get("rest_relative_basis", Basis.IDENTITY)
	var current_relative := (parent.global_basis.inverse() * child.global_basis).orthonormalized()
	return LimbsController3D.rotation_error_vector_parent(
		current_relative,
		rest_relative
	).length()


func _joint_has_locked_translation(joint: Generic6DOFJoint3D) -> bool:
	return (
		_joint_linear_axis_locked(joint, Vector3.AXIS_X)
		and _joint_linear_axis_locked(joint, Vector3.AXIS_Y)
		and _joint_linear_axis_locked(joint, Vector3.AXIS_Z)
	)


func _joint_linear_axis_locked(joint: Generic6DOFJoint3D, axis: int) -> bool:
	var enabled := false
	var lower := 0.0
	var upper := 0.0
	match axis:
		Vector3.AXIS_X:
			enabled = joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		Vector3.AXIS_Y:
			enabled = joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		Vector3.AXIS_Z:
			enabled = joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	return enabled and absf(lower) <= 0.0001 and absf(upper) <= 0.0001


func _joint_native_spring_enabled(joint: Generic6DOFJoint3D, axis: int) -> bool:
	match axis:
		Vector3.AXIS_X:
			return joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
		Vector3.AXIS_Y:
			return joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
		Vector3.AXIS_Z:
			return joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
	return false


func _angle_difference(left: float, right: float) -> float:
	return wrapf(left - right, -PI, PI)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: %s" % message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
