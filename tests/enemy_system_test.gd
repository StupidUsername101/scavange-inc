extends SceneTree

const SPIDER_PATH := "res://resources/enemies/giant_spider.tres"
const BLOCK_CREATURE_PATH := (
	"res://resources/enemies/four_legged_block_creature.tres"
)

#######################################################
# Runs headless regression coverage for enemy system behavior and reports contract or
# integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_spider_definition_contract()
	_test_quadruped_definition_contract()
	_test_two_bone_solver()
	_test_spider_knee_polarity()
	_test_physical_joint_frames()
	_test_alternating_gait_groups()
	_test_moving_limb_drive()
	_test_hunter_behavior()
	_test_dev_zoo_catalog()
	_test_procedural_visual_contract()

	if failure_count == 0:
		print("Enemy system tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Enemy system tests failed: %d/%d assertions" % [
				failure_count,
				assertion_count,
			]
		)
		quit(1)


func _test_spider_definition_contract() -> void:
	var spider := load(SPIDER_PATH) as EnemyDefinition
	_expect(spider != null, "giant spider definition loads")
	if spider == null:
		return
	_expect(spider.behavior != null and spider.behavior.can_move(), "spider has hunter behavior")
	_expect(spider.physical_anatomy != null, "spider has a physical anatomy")
	if spider.physical_anatomy == null:
		return
	_expect(spider.physical_anatomy.limbs.size() == 8, "spider has eight limbs")
	_expect(spider.physical_anatomy.get_segment_count() == 16, "spider uses sixteen physical segments")
	_expect(spider.physical_anatomy.get_gait_group_count() == 2, "spider has an alternating two-group gait")
	for limb: EnemyPhysicalLimbDefinition in spider.physical_anatomy.limbs:
		_expect(limb != null, "every spider limb resource resolves")
		if limb == null:
			continue
		var rest_distance: float = limb.hip_offset.distance_to(
			limb.rest_foot_offset
		)
		_expect(
			rest_distance < limb.get_maximum_reach(),
			"%s rest target is reachable" % limb.limb_name
		)


func _test_quadruped_definition_contract() -> void:
	var creature := load(BLOCK_CREATURE_PATH) as EnemyDefinition
	_expect(creature != null, "four-legged block creature definition loads")
	if creature == null:
		return
	_expect(
		creature.physical_visual_style
		== EnemyDefinition.PhysicalVisualStyle.BLOCK_CREATURE,
		"quadruped selects block presentation"
	)
	_expect(
		creature.behavior != null and creature.behavior.can_move(),
		"quadruped uses the shared moving enemy behavior"
	)
	_expect(creature.physical_anatomy != null, "quadruped has physical anatomy")
	if creature.physical_anatomy == null:
		return
	_expect(creature.physical_anatomy.limbs.size() == 4, "quadruped has four limbs")
	_expect(
		creature.physical_anatomy.get_segment_count() == 8,
		"quadruped uses eight physical segments"
	)
	_expect(
		creature.physical_anatomy.get_gait_group_count() == 2,
		"quadruped uses a diagonal two-group gait"
	)
	for limb: EnemyPhysicalLimbDefinition in creature.physical_anatomy.limbs:
		_expect(limb != null, "every quadruped limb resource resolves")
		if limb != null:
			_expect(
				limb.hip_offset.distance_to(limb.rest_foot_offset)
				< limb.get_maximum_reach(),
				"%s quadruped rest target is reachable" % limb.limb_name
			)

	var planner := EnemyGaitPlanner.new()
	planner.configure(creature.physical_anatomy, Transform3D.IDENTITY)
	planner.update(
		1.0 / 60.0,
		Transform3D(Basis.IDENTITY, Vector3(0.7, 0.0, 0.0)),
		Vector3(1.8, 0.0, 0.0),
		null
	)
	var stepping_count := 0
	for limb_index: int in range(creature.physical_anatomy.limbs.size()):
		if planner.is_limb_stepping(limb_index):
			stepping_count += 1
	_expect(
		stepping_count == 2,
		"shared ordered gait lifts one diagonal quadruped pair"
	)


func _test_two_bone_solver() -> void:
	var hip := Vector3(0.0, 1.0, 0.0)
	var requested_foot := Vector3(1.3, 0.0, 0.45)
	var points := EnemyGaitPlanner.solve_two_bone(
		hip,
		requested_foot,
		1.2,
		1.05,
		Vector3.UP
	)
	_expect(points.size() == 3, "two-bone solver produces hip, knee and foot")
	_expect(absf(points[0].distance_to(points[1]) - 1.2) < 0.001, "upper segment length is preserved")
	_expect(absf(points[1].distance_to(points[2]) - 1.05) < 0.001, "lower segment length is preserved")
	_expect(_is_finite_vector(points[1]), "two-bone knee remains finite")

	var unreachable := EnemyGaitPlanner.solve_two_bone(
		Vector3.ZERO,
		Vector3(100.0, 0.0, 0.0),
		1.0,
		1.0,
		Vector3.UP
	)
	_expect(unreachable[2].length() < 2.0, "unreachable foot target is clamped to limb reach")


func _test_spider_knee_polarity() -> void:
	var spider := load(SPIDER_PATH) as EnemyDefinition
	for limb: EnemyPhysicalLimbDefinition in spider.physical_anatomy.limbs:
		var side := signf(limb.hip_offset.x)
		_expect(side != 0.0, "%s has an unambiguous body side" % limb.limb_name)
		for foot_shift: Vector3 in [
			Vector3.ZERO,
			Vector3(0.22 * side, 0.0, -0.35),
			Vector3(-0.12 * side, 0.0, 0.35),
		]:
			var points := EnemyGaitPlanner.solve_two_bone(
				limb.hip_offset,
				limb.rest_foot_offset + foot_shift,
				limb.upper_length,
				limb.lower_length,
				limb.bend_hint
			)
			_expect(
				EnemyPhysicalLimbRig3D.calculate_knee_bend_alignment(
					points,
					limb.bend_hint
				) > 0.999,
				"%s knee stays in its authored outward hemisphere"
				% limb.limb_name
			)
			_expect(
				side * (points[1].x - limb.hip_offset.x) > 0.65,
				"%s knee remains visibly outside its hip" % limb.limb_name
			)

		var rest_points := EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		var upper_direction := (rest_points[1] - rest_points[0]).normalized()
		var lower_direction := (rest_points[2] - rest_points[1]).normalized()
		var rest_bend_degrees := rad_to_deg(
			acos(clampf(upper_direction.dot(lower_direction), -1.0, 1.0))
		)
		_expect(
			rest_bend_degrees
			> maxf(
				absf(limb.knee_limit_lower_degrees),
				absf(limb.knee_limit_upper_degrees)
			) + 20.0,
			"%s hinge cannot cross straight and invert" % limb.limb_name
		)


func _test_physical_joint_frames() -> void:
	for definition_path: String in [SPIDER_PATH, BLOCK_CREATURE_PATH]:
		var creature := load(definition_path) as EnemyDefinition
		for limb: EnemyPhysicalLimbDefinition in creature.physical_anatomy.limbs:
			var body_offset := EnemyPhysicalLimbRig3D.create_segment_body_offset(
				limb.upper_length
			)
			var hip_joint := EnemyPhysicalLimbRig3D.create_proximal_joint_offset(
				limb.upper_length
			)
			_expect(
				(body_offset * hip_joint).origin.length() < 0.00001,
				"%s hip joint maps the centered body back to the bone origin"
				% limb.limb_name
			)

			var points := EnemyGaitPlanner.solve_two_bone(
				limb.hip_offset,
				limb.rest_foot_offset,
				limb.upper_length,
				limb.lower_length,
				limb.bend_hint
			)
			var knee_basis := EnemyPhysicalLimbRig3D.create_knee_joint_basis(
				points
			)
			var knee_joint := EnemyPhysicalLimbRig3D.create_proximal_joint_offset(
				limb.lower_length,
				knee_basis
			)
			var lower_body := EnemyPhysicalLimbRig3D.create_segment_body_offset(
				limb.lower_length
			)
			_expect(
				(lower_body * knee_joint).origin.length() < 0.00001,
				"%s knee joint sits at the lower segment's proximal endpoint"
				% limb.limb_name
			)
			_expect(
				absf(knee_basis.determinant() - 1.0) < 0.0001,
				"%s knee hinge frame is orthonormal" % limb.limb_name
			)
			_expect(
				absf(knee_basis.z.dot(Vector3.UP)) < 0.0001,
				"%s knee hinge axis is perpendicular to the segment"
				% limb.limb_name
			)


func _test_alternating_gait_groups() -> void:
	var spider := load(SPIDER_PATH) as EnemyDefinition
	var planner := EnemyGaitPlanner.new()
	planner.configure(spider.physical_anatomy, Transform3D.IDENTITY)
	var moved_transform := Transform3D(Basis.IDENTITY, Vector3(0.8, 0.0, 0.0))
	planner.update(
		1.0 / 60.0,
		moved_transform,
		Vector3(2.0, 0.0, 0.0),
		null
	)
	var stepping_count := 0
	var stepping_group := -1
	for limb_index: int in range(spider.physical_anatomy.limbs.size()):
		if not planner.is_limb_stepping(limb_index):
			continue
		stepping_count += 1
		var group: int = spider.physical_anatomy.limbs[limb_index].gait_group
		if stepping_group < 0:
			stepping_group = group
		_expect(group == stepping_group, "only one stability group steps at once")
	_expect(stepping_count == 4, "one diagonal group lifts four feet")
	_expect(planner.get_active_gait_group() == 0, "spider starts with tetrapod group zero")

	var expected_group_by_limb := {
		"Front Left": 0,
		"Front Right": 1,
		"Mid Front Left": 1,
		"Mid Front Right": 0,
		"Mid Back Left": 0,
		"Mid Back Right": 1,
		"Back Left": 1,
		"Back Right": 0,
	}
	for limb: EnemyPhysicalLimbDefinition in spider.physical_anatomy.limbs:
		_expect(
			limb.gait_group == int(expected_group_by_limb[limb.limb_name]),
			"%s belongs to the biological alternating tetrapod set"
			% limb.limb_name
		)

	var later_transform := Transform3D(
		Basis.IDENTITY,
		Vector3(1.45, 0.0, 0.0)
	)
	planner.update(
		spider.physical_anatomy.step_duration + 0.01,
		later_transform,
		Vector3(2.0, 0.0, 0.0),
		null
	)
	_expect(planner.is_in_support_transfer(), "all eight feet plant between tetrapod phases")
	planner.update(
		spider.physical_anatomy.support_transfer_duration + 0.01,
		later_transform,
		Vector3(2.0, 0.0, 0.0),
		null
	)
	_expect(planner.get_active_gait_group() == 1, "the complementary tetrapod moves next")
	for limb_index: int in range(spider.physical_anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = spider.physical_anatomy.limbs[
			limb_index
		]
		_expect(
			planner.is_limb_stepping(limb_index) == (limb.gait_group == 1),
			"tetrapod sequence never repeats the same support group"
		)


func _test_moving_limb_drive() -> void:
	var chase_velocity := Vector3(2.8, 0.0, -0.4)
	var matched_velocity_acceleration := (
		EnemyPhysicalLimbRig3D.calculate_linear_drive_acceleration(
			Vector3.ZERO,
			chase_velocity,
			chase_velocity,
			32.0,
			8.5
		)
	)
	_expect(
		matched_velocity_acceleration.length() < 0.0001,
		"moving limb targets do not brake matching segment velocity"
	)
	var recovery_acceleration := (
		EnemyPhysicalLimbRig3D.calculate_linear_drive_acceleration(
			Vector3(0.2, 0.0, 0.0),
			chase_velocity,
			chase_velocity,
			32.0,
			8.5
		)
	)
	_expect(
		recovery_acceleration.x > 0.0,
		"moving limb targets still correct position error"
	)

	var desired_basis := Basis(Vector3.FORWARD, deg_to_rad(30.0))
	var corrective_torque := (
		EnemyPhysicalLimbRig3D.calculate_angular_drive_torque(
			Basis.IDENTITY,
			desired_basis,
			Vector3.ZERO,
			Vector3.ZERO,
			0.35,
			1.4,
			28.0,
			7.5,
			82.0
		)
	)
	_expect(
		corrective_torque.dot(Vector3.FORWARD) > 0.0,
		"angular drive torque rotates toward rather than away from its target"
	)
	var reverse_torque := (
		EnemyPhysicalLimbRig3D.calculate_angular_drive_torque(
			desired_basis,
			Basis.IDENTITY,
			Vector3.ZERO,
			Vector3.ZERO,
			0.35,
			1.4,
			28.0,
			7.5,
			82.0
		)
	)
	_expect(
		reverse_torque.dot(Vector3.FORWARD) < 0.0,
		"angular correction reverses sign when the orientation error reverses"
	)


func _test_hunter_behavior() -> void:
	var spider := load(SPIDER_PATH) as EnemyDefinition
	var controller := EnemyBehaviorController.new()
	var target_body := Node3D.new()
	var candidates: Array[Dictionary] = [{
		"target_id": 17,
		"body": target_body,
		"position": Vector3(4.0, 0.0, 0.0),
	}]
	var chase := controller.evaluate(
		1.0 / 60.0,
		spider.behavior,
		Vector3.ZERO,
		Vector3.ZERO,
		candidates
	)
	var chase_velocity: Vector3 = chase.get("desired_velocity", Vector3.ZERO)
	_expect(bool(chase.get("movement_active", false)), "hunter moves toward an activating player")
	_expect(chase_velocity.length() <= spider.behavior.maximum_speed + 0.001, "hunter respects maximum speed")
	_expect(int(chase.get("target_id", -1)) == 17, "hunter selects the supplied player")

	candidates[0]["position"] = Vector3(1.0, 0.0, 0.0)
	var attack := controller.evaluate(
		spider.behavior.attack_cooldown,
		spider.behavior,
		Vector3.ZERO,
		Vector3.ZERO,
		candidates
	)
	_expect(bool(attack.get("attack_requested", false)), "hunter attacks inside its attack range")
	target_body.free()


func _test_dev_zoo_catalog() -> void:
	var layout := DevZooCatalog.build_layout()
	var pens: Array = layout.get("pens", [])
	_expect(pens.size() >= 3, "dev zoo includes the dummy, spider and quadruped")
	var found_spider := false
	var found_block_creature := false
	for raw_pen: Variant in pens:
		var pen := raw_pen as Dictionary
		var size: Vector2 = pen.get("size", Vector2.ZERO)
		_expect(size == Vector2(20.0, 20.0), "every enemy has four times the original pen area")
		if str(pen.get("definition_path", "")) == SPIDER_PATH:
			found_spider = true
		elif str(pen.get("definition_path", "")) == BLOCK_CREATURE_PATH:
			found_block_creature = true
	_expect(found_spider, "dev zoo discovers the spider definition automatically")
	_expect(
		found_block_creature,
		"dev zoo discovers the four-legged block creature automatically"
	)


func _test_procedural_visual_contract() -> void:
	var spider := load(SPIDER_PATH) as EnemyDefinition
	var visual := spider.instantiate_visual() as EnemyPhysicalLimbVisual3D
	_expect(visual != null, "physical anatomy creates a procedural limb visual")
	if visual != null:
		_expect(visual.segment_nodes.size() == 8, "visual creates one segment set per limb")
		var segment_count := 0
		for segments: Array in visual.segment_nodes:
			segment_count += segments.size()
		_expect(segment_count == 16, "visual has sixteen independently transformed leg segments")
		visual.free()

	var creature := load(BLOCK_CREATURE_PATH) as EnemyDefinition
	var block_visual := creature.instantiate_visual() as EnemyPhysicalLimbVisual3D
	_expect(block_visual != null, "quadruped creates a procedural limb visual")
	if block_visual != null:
		_expect(
			block_visual.segment_nodes.size() == 4,
			"quadruped visual creates four leg chains"
		)
		var block_segment_count := 0
		for segments: Array in block_visual.segment_nodes:
			block_segment_count += segments.size()
			for segment: MeshInstance3D in segments:
				_expect(segment.mesh is BoxMesh, "block creature limb uses block geometry")
		_expect(block_segment_count == 8, "quadruped visual has eight physical segments")
		_expect(
			block_visual.get_node_or_null("BlockBody") != null,
			"quadruped visual has a block chassis"
		)
		block_visual.free()


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
