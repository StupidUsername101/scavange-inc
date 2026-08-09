extends SceneTree

#######################################################
# Focused Jolt regression for the neutral four-limb body's real load-bearing posture. Run with:
# godot --headless --path . --script res://tests/four_limb_stability_test.gd
#######################################################

const SETTLE_FRAMES := 240
const SETTLED_MOTION_SAMPLE_FRAMES := 60
const RECOVERY_FRAMES := 180
const MINIMUM_HEIGHT_RATIO := 0.75
const MINIMUM_UPRIGHTNESS := 0.85
const MINIMUM_OUTWARD_RATIO := 0.65
const SPAWN_CLEARANCE := 0.03

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_add_floor(world)

	var definition: FourLimbBodyDefinition = MLBodyPresetLibrary.four_limb_walker_definition()
	var body := FourLimbPhysicalBody3D.new()
	body.definition = definition
	body.auto_start_simulation = false
	body.position = Vector3(0.0, definition.minimum_spawn_height(SPAWN_CLEARANCE), 0.0)
	world.add_child(body)
	for _frame in range(12):
		await physics_frame
		if (
			is_instance_valid(body.physical_rig)
			and body.physical_rig.has_valid_physical_bindings(false)
		):
			break

	_expect(
		is_instance_valid(body.physical_rig)
		and body.physical_rig.has_valid_physical_bindings(false),
		"the load-bearing test builds the complete generic rigid-body limb rig before release"
	)
	_expect(
		is_instance_valid(body.physical_rig.limbs_controller),
		"one LimbsController3D owns all four modular limb chains"
	)
	_expect(
		body.physical_rig.has_passive_rest_elasticity(),
		"every movable hip and knee axis has permanent passive stiffness, damping and torque"
	)
	_expect(
		_surface_matches_definition(body.physical_rig.core_bone, definition),
		"the chassis uses a PhysicsMaterial with the authored friction and bounce"
	)
	var correctly_materialized_segments := 0
	for chain: GenericLimb3D in body.physical_rig.generic_limbs:
		for segment: LimbSegment3D in chain.segments:
			if _surface_matches_definition(segment, definition):
				correctly_materialized_segments += 1
	_expect(
		correctly_materialized_segments == 8,
		"all eight physical limb parts use valid authored PhysicsMaterials"
	)
	_expect(
		body.submit_raw_commands(FourLimbMLAction.neutral_commands()),
		"the test holds the exact neutral twelve-axis action"
	)
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		_expect(
			body.physical_rig.set_limb_effectiveness(limb_index, 0.0),
			"the stability test disables model actuator authority for limb %d" % limb_index
		)
	_test_static_strength_budget(definition, body.physical_rig.total_mass())
	body.physical_rig.set_runtime_active(true)
	await physics_frame
	_expect(
		body.physical_rig.has_valid_physical_bindings(true),
		"the passive-only body releases all nine rigid parts into Jolt together"
	)

	for _frame in range(SETTLE_FRAMES):
		await physics_frame

	_expect(body.has_finite_physics_state(), "the neutral articulated body remains numerically finite")
	var body_state := body.physical_rig.body_snapshot()
	var preferred_clearance := float(body_state.get("preferred_ground_clearance", 0.0))
	var actual_clearance := float(body_state.get("ground_clearance", 0.0))
	_expect(
		actual_clearance >= preferred_clearance * MINIMUM_HEIGHT_RATIO,
		"after settling the chassis keeps at least 75% of its authored standing clearance"
	)
	_expect(
		float(body_state.get("uprightness", -1.0)) >= MINIMUM_UPRIGHTNESS,
		"after settling the unpiloted chassis remains upright"
	)
	_expect(
		not bool(body_state.get("core_contact", true)),
		"the chassis is carried by real leg contacts rather than resting on the floor"
	)
	var minimum_outward_ratio := _minimum_outward_ratio(body, definition)
	_expect(
		minimum_outward_ratio >= MINIMUM_OUTWARD_RATIO,
		"all four feet retain a broad spider stance instead of collapsing under the chassis"
	)
	var core_linear_motion_sum := 0.0
	var core_horizontal_motion_sum = 0.0
	var core_angular_motion_sum := 0.0
	var limb_angular_motion_sum := 0.0
	var limb_motion_samples := 0
	for _frame in range(SETTLED_MOTION_SAMPLE_FRAMES):
		await physics_frame
		var core_velocity = body.physical_rig.get_core_linear_velocity()
		core_linear_motion_sum += core_velocity.length()
		core_horizontal_motion_sum += Vector2(core_velocity.x, core_velocity.z).length()
		core_angular_motion_sum += body.physical_rig.get_core_angular_velocity().length()
		for chain: GenericLimb3D in body.physical_rig.generic_limbs:
			for segment: LimbSegment3D in chain.segments:
				limb_angular_motion_sum += segment.angular_velocity.length()
				limb_motion_samples += 1
	var average_core_linear_motion := core_linear_motion_sum / float(SETTLED_MOTION_SAMPLE_FRAMES)
	var average_core_horizontal_motion = (
		core_horizontal_motion_sum / float(SETTLED_MOTION_SAMPLE_FRAMES)
	)
	var average_core_angular_motion := core_angular_motion_sum / float(SETTLED_MOTION_SAMPLE_FRAMES)
	var average_limb_angular_motion := limb_angular_motion_sum / float(maxi(limb_motion_samples, 1))
	_expect(
		average_core_linear_motion < 0.35,
		"the passive-only chassis settles instead of continuously translating from solver jitter"
	)
	_expect(
		average_core_horizontal_motion < 0.35,
		"the passive-only chassis has no persistent horizontal wiggle without policy commands"
	)
	_expect(
		average_core_angular_motion < 1.25,
		"the passive-only chassis settles instead of continuously rotating from spring jitter"
	)
	_expect(
		average_limb_angular_motion < 2.5,
		"uncommanded elastic limbs settle instead of behaving like vibrating motors"
	)

	# A small sideways hit should bend the elastic body and then settle again without a policy gait.
	var disturbance_position := body.physical_rig.get_core_transform().origin + Vector3.UP * 0.1
	_expect(
		body.physical_rig.apply_core_impulse(Vector3(1.6, 0.0, 0.6), disturbance_position),
		"the recovery test applies a real impulse to the simulated chassis"
	)
	for _frame in range(RECOVERY_FRAMES):
		await physics_frame
	var recovered_state := body.physical_rig.body_snapshot()
	_expect(body.has_finite_physics_state(), "the disturbed body remains numerically finite")
	_expect(
		float(recovered_state.get("ground_clearance", 0.0))
		>= preferred_clearance * MINIMUM_HEIGHT_RATIO,
		"passive limb elasticity restores standing height after a disturbance"
	)
	_expect(
		float(recovered_state.get("uprightness", -1.0)) >= MINIMUM_UPRIGHTNESS,
		"passive limb elasticity restores an upright chassis after a disturbance"
	)
	_expect(
		not bool(recovered_state.get("core_contact", true)),
		"the disturbed chassis recovers without collapsing onto the floor"
	)

	print(
		"Four-limb stability assertions: %d, failures: %d, height: %.3f/%.3f, outward: %.3f, motion linear/horizontal/angular/limb: %.3f/%.3f/%.3f/%.3f"
		% [
			assertion_count,
			failure_count,
			actual_clearance,
			preferred_clearance,
			minimum_outward_ratio,
			average_core_linear_motion,
			average_core_horizontal_motion,
			average_core_angular_motion,
			average_limb_angular_motion,
		]
	)
	quit(0 if failure_count == 0 else 1)


func _add_floor(world: Node3D) -> void:
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.5, 20.0)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	floor.collision_layer = 1
	floor.collision_mask = 4
	floor.position.y = -0.25
	world.add_child(floor)


func _test_static_strength_budget(definition: FourLimbBodyDefinition, total_mass: float) -> void:
	var gravity_magnitude := float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	var per_leg_force := total_mass * gravity_magnitude / float(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	var worst_required_torque := 0.0
	var worst_locked_axis_share := 0.0
	for limb: FourLimbSlotDefinition in definition.limbs:
		var points := EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		if points.size() != 3:
			continue
		var upper_direction := (points[1] - points[0]).normalized()
		var hip_basis := FourLimbPhysicalRig3D.hip_joint_basis_for_slot(
			limb,
			upper_direction
		)
		var support_torque := (points[2] - points[0]).cross(Vector3.UP * per_leg_force)
		worst_required_torque = maxf(worst_required_torque, absf(support_torque.dot(hip_basis.z)))
		worst_locked_axis_share = maxf(
			worst_locked_axis_share,
			absf(support_torque.dot(hip_basis.y)) / maxf(support_torque.length(), 0.0001)
		)
	_expect(
		worst_locked_axis_share < 0.08,
		"the authored hip frame puts vertical support torque on free swing Z, not locked Y"
	)
	_expect(
		definition.maximum_passive_joint_torque > worst_required_torque * 4.0,
		"passive joint torque caps have large headroom over the estimated static gravity load"
	)
	var estimated_deflection := worst_required_torque / maxf(
		definition.passive_joint_stiffness,
		0.001
	)
	_expect(
		estimated_deflection < deg_to_rad(12.0),
		"the estimated static load needs less than twelve degrees of passive spring deflection"
	)
	_expect(
		definition.passive_joint_native_fraction > 0.0
		and definition.passive_joint_native_fraction < 1.0,
		"baseline passive stiffness is shared between Jolt and the bounded controller"
	)
	var edge_angle := deg_to_rad(55.0)
	var linear_edge_torque := LimbsController3D.spring_damper_component(
		edge_angle,
		0.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque
	)
	var progressive_edge_torque := LimbsController3D.progressive_spring_damper_component(
		edge_angle,
		0.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque,
		deg_to_rad(62.0),
		definition.passive_joint_progressive_ratio,
		definition.passive_joint_progressive_onset_ratio
	)
	_expect(
		progressive_edge_torque > linear_edge_torque * 1.5,
		"the passive limb hardens substantially before it can fold flat"
	)


func _minimum_outward_ratio(
	body: FourLimbPhysicalBody3D,
	definition: FourLimbBodyDefinition
) -> float:
	var result := INF
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var limb := definition.limbs[limb_index]
		var limb_state := body.physical_rig.limb_snapshot(limb_index)
		var authored_outward := limb.rest_foot_offset - limb.hip_offset
		authored_outward.y = 0.0
		var current_outward: Vector3 = (
			limb_state.get("foot_position_local", Vector3.ZERO) - limb.hip_offset
		)
		current_outward.y = 0.0
		var ratio := (
			current_outward.dot(authored_outward.normalized()) / authored_outward.length()
			if authored_outward.length_squared() > 0.000001
			else 1.0
		)
		result = minf(result, ratio)
	return result


func _surface_matches_definition(
	part: LimbSegment3D,
	definition: FourLimbBodyDefinition
) -> bool:
	if not is_instance_valid(part) or definition == null:
		return false
	var surface := part.physics_material_override
	return (
		surface is PhysicsMaterial
		and is_equal_approx(surface.friction, definition.friction)
		and is_equal_approx(surface.bounce, definition.bounce)
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: %s" % message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
