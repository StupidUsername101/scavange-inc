extends SceneTree

const RIG_SCENE := preload(
	"res://scenes/proxy/player_procedural_leg_rig.tscn"
)
const PLAYER_PROXY_SCENE := preload("res://scenes/proxy/player_proxy.tscn")
const ACOUSTIC_HOUSE_PROXY_SCENE := preload(
	"res://scenes/proxy/acoustic_test_house.tscn"
)
const STEP := 1.0 / 60.0
const EPSILON := 0.025

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_flat_contact_and_allocation_cadence()
	await _test_turning_stance_clearance()
	await _test_forward_walking_knee_drive()
	await _test_airborne_pose_recovery()
	await _test_ground_relative_landing_pose()
	await _test_replicated_jump_expression()
	await _test_independent_split_height_landing()
	await _test_missing_limb_combinations()
	await _test_air_pose_and_proxy_wiring()
	await _test_detailed_contact_layer_priority()
	await _test_stair_contact_course()
	await _test_client_contact_mirror()
	if failure_count == 0:
		print(
			"Player procedural leg rig tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Player procedural leg rig tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_flat_contact_and_allocation_cadence() -> void:
	var fixture := Node3D.new()
	fixture.name = "FlatContactFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(0.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(0.0, 0.985, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	_expect(
		absf(rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT).y)
		< EPSILON
		and absf(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT).y
		) < EPSILON,
		"both installed feet plant on ordinary layer-1 world geometry"
	)
	var left_points := rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)
	_expect(
		left_points.size() == 3
		and absf(
			left_points[0].distance_to(left_points[1])
			- PlayerProceduralLegRig.UPPER_LEG_LENGTH
		) < 0.001
		and absf(
			left_points[1].distance_to(left_points[2])
			- PlayerProceduralLegRig.LOWER_LEG_LENGTH
		) < 0.001,
		"the reusable presentation solve preserves both authored segment lengths"
	)
	var probes_after_plant := rig.get_probe_cast_count()
	for _frame: int in range(180):
		rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	_expect(
		rig.get_probe_cast_count() == probes_after_plant,
		"stationary planted feet reuse their anchors without per-frame ground queries"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_turning_stance_clearance() -> void:
	var fixture := Node3D.new()
	fixture.name = "TurningStanceFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(8.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(8.0, 0.985, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	var minimum_ordered_clearance := INF
	var saw_turn_step := false
	for frame: int in range(60):
		var ratio := float(frame + 1) / 60.0
		rig.rotation.y = deg_to_rad(150.0) * ratio
		rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
		var left_local := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
		)
		var right_local := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
		)
		minimum_ordered_clearance = minf(
			minimum_ordered_clearance,
			right_local.x - left_local.x
		)
		saw_turn_step = saw_turn_step or rig.get_active_swing_side() >= 0
	_expect(
		saw_turn_step and minimum_ordered_clearance > 0.035,
		"turning in place replants early enough to preserve left/right foot order instead of crossing the legs"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_forward_walking_knee_drive() -> void:
	var fixture := Node3D.new()
	fixture.name = "ForwardKneeDriveFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 24.0),
		Vector3(20.0, -0.1, -8.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(20.0, 0.985, 0.0))
	await _settle_physics()
	var velocity := Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED)
	var gait_cycle := 0.0
	var least_forward_knee := 0.0
	var forward_knee_frames := 0
	for frame: int in range(90):
		rig.global_position += velocity * STEP
		gait_cycle += (
			ServerPlayer.WALK_SPEED
			/ PlayerGait.WALK_STEP_DISTANCE
			* STEP
		)
		rig.update_pose(STEP, velocity, true, gait_cycle, true)
		if frame < 10:
			continue
		var left_knee_local := rig.to_local(
			rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)[1]
		)
		var right_knee_local := rig.to_local(
			rig.get_leg_points(PlayerProceduralLegRig.Side.RIGHT)[1]
		)
		var forward_knee := minf(left_knee_local.z, right_knee_local.z)
		least_forward_knee = minf(least_forward_knee, forward_knee)
		if forward_knee <= -0.16:
			forward_knee_frames += 1
	_expect(
		least_forward_knee <= -0.24 and forward_knee_frames >= 60,
		"walking-speed swings keep a knee driven visibly ahead of the hips instead of dragging both knees behind the camera"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_airborne_pose_recovery() -> void:
	var fixture := Node3D.new()
	fixture.name = "AirborneRecoveryFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 12.0),
		Vector3(28.0, -0.1, -4.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(28.0, 0.985, 0.0))
	await _settle_physics()
	var velocity := Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED)
	var gait_cycle := 0.0
	for frame: int in range(16):
		rig.global_position += velocity * STEP
		gait_cycle += (
			ServerPlayer.WALK_SPEED
			/ PlayerGait.WALK_STEP_DISTANCE
			* STEP
		)
		rig.update_pose(STEP, velocity, true, gait_cycle, true)
	var left_takeoff_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var right_takeoff_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	velocity.y = ServerPlayer.JUMP_VELOCITY
	rig.global_position += velocity * STEP
	rig.update_pose(STEP, velocity, false, gait_cycle, false)
	var left_first_air_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var right_first_air_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	_expect(
		left_first_air_local.distance_to(left_takeoff_local) < 0.015
		and right_first_air_local.distance_to(right_takeoff_local) < 0.015,
		"takeoff preserves the last rendered planted/swinging pose instead of resetting both feet"
	)
	var previous_left_air := left_first_air_local
	var previous_right_air := right_first_air_local
	var previous_correction_step := 0.0
	var first_correction_step := 0.0
	var maximum_correction_step_change := 0.0
	for _frame: int in range(24):
		velocity.y -= ServerPlayer.GRAVITY * STEP
		rig.global_position += velocity * STEP
		rig.update_pose(STEP, velocity, false, gait_cycle, false)
		var current_left_air := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
		)
		var current_right_air := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
		)
		var correction_step := maxf(
			current_left_air.distance_to(previous_left_air),
			current_right_air.distance_to(previous_right_air)
		)
		if _frame == 0:
			first_correction_step = correction_step
		else:
			maximum_correction_step_change = maxf(
				maximum_correction_step_change,
				absf(correction_step - previous_correction_step)
			)
		previous_correction_step = correction_step
		previous_left_air = current_left_air
		previous_right_air = current_right_air
	_expect(
		first_correction_step < 0.012
		and maximum_correction_step_change < 0.008,
		(
			"airborne correction gains speed continuously instead of pushing either foot shortly after takeoff (first %.5f, max delta %.5f)"
			% [first_correction_step, maximum_correction_step_change]
		)
	)
	var left_apex_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var right_apex_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	var expected_height := (
		PlayerProceduralLegRig.REST_FOOT_LOCAL_HEIGHT
		+ PlayerProceduralLegRig.AIR_LANDING_TUCK_HEIGHT
	)
	_expect(
		absf(left_apex_local.x + PlayerProceduralLegRig.HIP_LATERAL_OFFSET) < 0.025
		and absf(right_apex_local.x - PlayerProceduralLegRig.HIP_LATERAL_OFFSET) < 0.025
		and absf(
			(left_apex_local.y + right_apex_local.y) * 0.5
			- expected_height
		) < 0.045,
		"by the apex both feet have smoothly recovered into a bounded moving landing-ready envelope"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_ground_relative_landing_pose() -> void:
	var fixture := Node3D.new()
	fixture.name = "GroundRelativeLandingFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(10.0, 0.2, 10.0),
		Vector3(44.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(44.0, 0.985, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.0, false)
	rig.update_pose(
		STEP,
		Vector3.UP * ServerPlayer.JUMP_VELOCITY,
		false,
		0.0,
		false
	)
	# A deliberately long airborne hold proves that landing extension is not another animation
	# timer: after several recovery durations, distant feet must remain in the tucked pose.
	rig.global_position.y = 6.0
	var previous_left_local := Vector3.ZERO
	var previous_right_local := Vector3.ZERO
	var minimum_pair_motion := INF
	var maximum_vertical_asymmetry := 0.0
	for _frame: int in range(90):
		rig.update_pose(STEP, Vector3.ZERO, false, 0.0, false)
		var left_local := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
		)
		var right_local := rig.to_local(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
		)
		if _frame >= 30:
			maximum_vertical_asymmetry = maxf(
				maximum_vertical_asymmetry,
				absf(left_local.y - right_local.y)
			)
			if _frame > 30:
				minimum_pair_motion = minf(
					minimum_pair_motion,
					left_local.distance_to(previous_left_local)
					+ right_local.distance_to(previous_right_local)
				)
		previous_left_local = left_local
		previous_right_local = right_local
	var far_left_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var tucked_height := (
		PlayerProceduralLegRig.REST_FOOT_LOCAL_HEIGHT
		+ PlayerProceduralLegRig.AIR_LANDING_TUCK_HEIGHT
	)
	_expect(
		rig.get_landing_pose_weight() < 0.001
		and absf(far_left_local.y - tucked_height) < 0.06,
		"a long high jump remains tucked regardless of elapsed time while the ground is distant"
	)
	_expect(
		minimum_pair_motion > 0.0001
		and maximum_vertical_asymmetry > 0.025,
		"airborne feet keep moving with unequal per-leg correction instead of freezing into a mirrored pose"
	)
	for frame: int in range(24):
		var descent_ratio := float(frame + 1) / 24.0
		rig.global_position.y = lerpf(3.2, 1.35, descent_ratio)
		rig.update_pose(STEP, Vector3.DOWN * 10.0, false, 0.0, false)
	var near_left_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	_expect(
		rig.get_landing_pose_weight() > 0.85
		and rig.get_landing_ground_clearance() < 0.40
		and near_left_local.y < tucked_height - 0.08,
		"ground proximity produces a normalized descending landing pose that extends the feet before contact"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_replicated_jump_expression() -> void:
	var fixture := Node3D.new()
	fixture.name = "ReplicatedJumpExpressionFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(12.0, 0.2, 8.0),
		Vector3(58.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var first := _add_rig(fixture, Vector3(56.0, 0.985, 0.0))
	var second := _add_rig(fixture, Vector3(60.0, 0.985, 0.0))
	first.set_expression_identity(77)
	second.set_expression_identity(77)
	await _settle_physics()
	first.update_pose(STEP, Vector3.ZERO, true, 0.37, false, 8)
	second.update_pose(STEP, Vector3.ZERO, true, 0.37, false, 8)
	var launch_velocity := Vector3.UP * ServerPlayer.JUMP_VELOCITY
	first.update_pose(STEP, launch_velocity, false, 0.37, false, 9)
	second.update_pose(STEP, launch_velocity, false, 0.37, false, 9)
	first.global_position.y = 6.0
	second.global_position.y = 6.0
	for _frame: int in range(36):
		first.update_pose(STEP, Vector3.ZERO, false, 0.37, false, 9)
		second.update_pose(STEP, Vector3.ZERO, false, 0.37, false, 9)
	var first_left := first.to_local(
		first.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var first_right := first.to_local(
		first.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	var second_left := second.to_local(
		second.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	var second_right := second.to_local(
		second.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	_expect(
		first_left.distance_to(second_left) < 0.0001
		and first_right.distance_to(second_right) < 0.0001,
		"player identity and replicated jump sequence produce the same expressive pose for every observer"
	)
	second.global_position.y = 0.985
	second.update_pose(STEP, Vector3.ZERO, true, 0.37, false, 9)
	second.update_pose(STEP, launch_velocity, false, 0.37, false, 10)
	second.global_position.y = 6.0
	for _frame: int in range(36):
		second.update_pose(STEP, Vector3.ZERO, false, 0.37, false, 10)
	second_left = second.to_local(
		second.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	second_right = second.to_local(
		second.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
	)
	_expect(
		first_left.distance_to(second_left)
		+ first_right.distance_to(second_right) > 0.02,
		"successive accepted jumps select visibly different nonlinear foot-placement styles"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_independent_split_height_landing() -> void:
	var fixture := Node3D.new()
	fixture.name = "SplitHeightLandingFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(5.0, 0.2, 5.0),
		Vector3(72.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	# Only the left landing footprint receives this raised contact. Its narrow X extent leaves the
	# right foot over the floor while still covering the complete toe/heel Z footprint.
	_add_static_box(
		fixture,
		Vector3(0.28, 0.16, 0.8),
		Vector3(71.8, 0.08, 0.0),
		CharacterContactLayers.FOOT_CONTACT_DETAIL
	)
	var rig := _add_rig(fixture, Vector3(72.0, 2.0, 0.0))
	rig.set_expression_identity(31)
	await _settle_physics()
	rig.update_pose(
		STEP,
		Vector3.DOWN * 4.0,
		false,
		0.25,
		false,
		5
	)
	rig.global_position.y = 1.145
	rig.update_pose(
		STEP,
		Vector3.DOWN * 4.0,
		true,
		0.25,
		false,
		5
	)
	var planted_count_at_contact := (
		int(rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT))
		+ int(rig.is_foot_planted(PlayerProceduralLegRig.Side.RIGHT))
	)
	_expect(
		planted_count_at_contact == 1
		and rig.get_active_swing_side() >= 0,
		"grounded body contact plants one foot first while the other continues its own touchdown"
	)
	for _frame: int in range(20):
		rig.update_pose(STEP, Vector3.ZERO, true, 0.25, false, 5)
	var left_height := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	).y
	var right_height := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	).y
	_expect(
		rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT)
		and rig.is_foot_planted(PlayerProceduralLegRig.Side.RIGHT)
		and absf(left_height - 0.16) < EPSILON
		and absf(right_height) < EPSILON,
		"independent probes preserve one foot on a raised rock-like contact and the other on the ground"
	)
	var yield_rotation := rig.get_body_yield_rotation()
	var yield_offset := rig.get_body_yield_offset()
	_expect(
		absf(yield_rotation.z) > deg_to_rad(3.0)
		and yield_rotation.z < 0.0
		and yield_offset.y < -0.02,
		"split-height support nonlinearly tilts and lowers the hips/upper body toward the uneven stance"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_missing_limb_combinations() -> void:
	var fixture := Node3D.new()
	fixture.name = "MissingLimbFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(12.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(12.0, 0.985, 0.0))
	await _settle_physics()
	rig.set_limb_presence(false, true)
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	_expect(
		rig.get_present_leg_count() == 1
		and not rig.left_leg_root.visible
		and rig.right_leg_root.visible
		and rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT).is_empty()
		and rig.get_leg_points(PlayerProceduralLegRig.Side.RIGHT).size() == 3,
		"a missing left leg creates no visual chain or phantom IK result"
	)
	var right_anchor := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	rig.global_position += Vector3(0.0, 0.0, -0.72)
	rig.update_pose(STEP, Vector3(0.0, 0.0, -2.0), true, 1.05, true)
	_expect(
		rig.get_active_swing_side() == PlayerProceduralLegRig.Side.RIGHT
		and rig.is_foot_swinging(PlayerProceduralLegRig.Side.RIGHT),
		"the surviving leg owns the next recovery step instead of alternating with a phantom leg"
	)
	for _frame: int in range(30):
		rig.update_pose(STEP, Vector3.ZERO, true, 1.05, false)
	_expect(
		rig.is_foot_planted(PlayerProceduralLegRig.Side.RIGHT)
		and rig.get_foot_world_position(
			PlayerProceduralLegRig.Side.RIGHT
		).distance_to(right_anchor) > 0.35,
		"one-legged presentation completes and plants its independent recovery step"
	)
	rig.set_limb_presence(false, false)
	var probes_before_legless_update := rig.get_probe_cast_count()
	rig.update_pose(STEP, Vector3(3.0, 0.0, 0.0), true, 2.0, true)
	_expect(
		rig.get_present_leg_count() == 0
		and not rig.left_leg_root.visible
		and not rig.right_leg_root.visible
		and rig.get_active_swing_side() < 0
		and rig.get_probe_cast_count() == probes_before_legless_update,
		"a legless body performs no foot queries and schedules no nonexistent support"
	)
	rig.set_limb_presence(true, false)
	rig.update_pose(STEP, Vector3.ZERO, true, 2.0, false)
	_expect(
		rig.left_leg_root.visible
		and not rig.right_leg_root.visible
		and rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT),
		"reinstalling one limb initializes only that limb without requiring a paired leg"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_detailed_contact_layer_priority() -> void:
	var fixture := Node3D.new()
	fixture.name = "DetailedContactFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(5.0, 0.24, 5.0),
		Vector3(24.0, 0.0, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var detail := DetailedFootContactSurface3D.new()
	detail.name = "DetailedTread"
	fixture.add_child(detail)
	_add_collision_box(
		detail,
		Vector3(1.4, 0.2, 1.4),
		Vector3(24.0, 0.24, 0.0)
	)
	var rig := _add_rig(fixture, Vector3(24.0, 1.325, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	_expect(
		detail.collision_layer
		== CharacterContactLayers.FOOT_CONTACT_DETAIL
		and detail.collision_mask == 0,
		"detail-only contact geometry is excluded from authoritative movement collision"
	)
	_expect(
		absf(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT).y
			- 0.34
		) < EPSILON
		and absf(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT).y
			- 0.34
		) < EPSILON,
		"foot queries prefer detailed tread geometry over the simplified movement surface"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_air_pose_and_proxy_wiring() -> void:
	var fixture := Node3D.new()
	fixture.name = "AirAndProxyFixture"
	root.add_child(fixture)
	var rig := _add_rig(fixture, Vector3(52.0, 8.0, -11.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3(4.0, 0.0, -2.0), false, 3.2, true)
	var left_air_foot := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var right_air_foot := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	_expect(
		left_air_foot.distance_to(rig.global_position) < 1.2
		and right_air_foot.distance_to(rig.global_position) < 1.2
		and rig.get_probe_cast_count() == 0,
		"a first airborne snapshot initializes a local tucked pose without querying ground or aiming at world origin"
	)

	var proxy := PLAYER_PROXY_SCENE.instantiate() as PlayerProxy
	fixture.add_child(proxy)
	proxy.process_mode = Node.PROCESS_MODE_DISABLED
	proxy.call("_apply_limb_state", {
		"left_arm": true,
		"right_arm": false,
		"left_leg": false,
		"right_leg": true,
	})
	_expect(
		not proxy.has_left_leg
		and proxy.has_right_leg
		and proxy.procedural_leg_rig.get_present_leg_count() == 1
		and not proxy.left_leg_visual.visible
		and proxy.right_leg_visual.visible,
		"replicated body-loadout state drives the procedural rig's real available-limb set"
	)
	proxy.apply_server_state({
		"player_id": 7,
		"ragdoll_active": true,
		"trip_sequence": 3,
		"trip_direction": Vector3(0.5, 0.0, -1.0),
		"vel": Vector3(2.0, 0.0, -1.0),
	})
	proxy.call("_sync_trip_presentation")
	await _settle_physics()
	_expect(
		proxy.player_ragdoll.is_active()
		and not proxy.body_visual.visible
		and proxy.player_ragdoll.get_node("left_arm").visible
		and not proxy.player_ragdoll.get_node("right_arm").visible
		and not proxy.player_ragdoll.get_node("left_upper_leg").visible
		and proxy.player_ragdoll.get_node("right_upper_leg").visible,
		"the replicated trip swaps to an articulated ragdoll containing only installed limbs"
	)
	proxy.target_ragdoll_active = false
	proxy.call("_sync_trip_presentation")
	_expect(
		not proxy.player_ragdoll.is_active() and proxy.body_visual.visible,
		"trip recovery restores the procedural character presentation cleanly"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_stair_contact_course() -> void:
	var fixture := Node3D.new()
	fixture.name = "StairContactFixture"
	root.add_child(fixture)
	# A smooth movement guide rises through the same space. Four detail-only tread tops provide the
	# actual presentation contacts, matching the production dual-geometry contract.
	var guide := _add_static_box(
		fixture,
		Vector3(1.5, 0.18, 1.5),
		Vector3(36.0, 0.06, -0.45),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	guide.rotation.x = deg_to_rad(-7.6)
	for step_index: int in range(4):
		var tread := DetailedFootContactSurface3D.new()
		tread.name = "Tread%02d" % step_index
		fixture.add_child(tread)
		var top_height := float(step_index) * 0.09
		_add_collision_box(
			tread,
			Vector3(1.25, 0.12, 0.32),
			Vector3(
				36.0,
				top_height - 0.06,
				-float(step_index) * 0.30
			)
		)
	var rig := _add_rig(fixture, Vector3(36.0, 0.985, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.0, false)
	var maximum_contact_height := 0.0
	for frame: int in range(90):
		var ratio := float(frame + 1) / 90.0
		rig.global_position = Vector3(
			36.0,
			0.985 + ratio * 0.27,
			-ratio * 0.90
		)
		rig.update_pose(
			STEP,
			Vector3(0.0, 0.0, -0.6),
			true,
			ratio * 3.0,
			true
		)
		maximum_contact_height = maxf(
			maximum_contact_height,
			maxf(
				rig.get_foot_world_position(
					PlayerProceduralLegRig.Side.LEFT
				).y,
				rig.get_foot_world_position(
					PlayerProceduralLegRig.Side.RIGHT
				).y
			)
		)
	var left_points := rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)
	var right_points := rig.get_leg_points(PlayerProceduralLegRig.Side.RIGHT)
	_expect(
		maximum_contact_height >= 0.17,
		"moving over a smooth guide still places visible feet on rising discrete stair treads"
	)
	_expect(
		_points_are_finite(left_points)
		and _points_are_finite(right_points)
		and left_points.size() == 3
		and right_points.size() == 3,
		"the stair course preserves finite continuous two-bone poses for both knees"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_client_contact_mirror() -> void:
	var fixture := Node3D.new()
	fixture.name = "ClientContactMirrorFixture"
	root.add_child(fixture)
	var house := ACOUSTIC_HOUSE_PROXY_SCENE.instantiate() as Node3D
	fixture.add_child(house)
	await _settle_physics()
	var contact_bodies: Array[StaticBody3D] = []
	_collect_contact_bodies(house, contact_bodies)
	var all_detail_only := not contact_bodies.is_empty()
	for body: StaticBody3D in contact_bodies:
		all_detail_only = (
			all_detail_only
			and body.collision_layer
			== CharacterContactLayers.FOOT_CONTACT_DETAIL
			and body.collision_mask == 0
		)
	_expect(
		all_detail_only,
		"client structures generate presentation-only contact mirrors instead of movement blockers"
	)
	var rig := _add_rig(fixture, Vector3(0.0, 0.985, 0.0))
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.0, false)
	_expect(
		absf(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT).y
			- 0.12
		)
		< EPSILON
		and absf(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT).y
			- 0.12
		) < EPSILON,
		"remote-client feet resolve against geometry rebuilt from the shared structure descriptors"
	)
	fixture.queue_free()
	await _settle_physics()


func _collect_contact_bodies(
	node: Node,
	result: Array[StaticBody3D]
) -> void:
	for child: Node in node.get_children():
		if child is StaticBody3D:
			var body := child as StaticBody3D
			if (
				body.collision_layer
				== CharacterContactLayers.FOOT_CONTACT_DETAIL
			):
				result.append(body)
		_collect_contact_bodies(child, result)


func _add_rig(parent: Node, position_value: Vector3) -> PlayerProceduralLegRig:
	var rig := RIG_SCENE.instantiate() as PlayerProceduralLegRig
	parent.add_child(rig)
	rig.global_position = position_value
	return rig


func _add_static_box(
	parent: Node,
	size: Vector3,
	position_value: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = position_value
	parent.add_child(body)
	_add_collision_box(body, size, Vector3.ZERO)
	return body


func _add_collision_box(
	body: CollisionObject3D,
	size: Vector3,
	local_position: Vector3
) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = local_position
	body.add_child(collision)


func _settle_physics() -> void:
	await physics_frame
	await physics_frame


func _points_are_finite(points: PackedVector3Array) -> bool:
	for point: Vector3 in points:
		if not is_finite(point.x) or not is_finite(point.y) or not is_finite(point.z):
			return false
	return true


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % description)
		return
	failure_count += 1
	push_error("[FAIL] %s" % description)
