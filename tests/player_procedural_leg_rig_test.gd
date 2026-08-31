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
	await _test_partial_sole_contact_preserves_ankle_center()
	await _test_short_reversal_balance_envelope()
	await _test_turning_stance_clearance()
	await _test_forward_walking_knee_drive()
	await _test_natural_multistep_gait()
	await _test_run_release_recovery_steps()
	await _test_contact_driven_footfall()
	await _test_airborne_pose_recovery()
	await _test_ground_relative_landing_pose()
	await _test_impact_scaled_landing_compression()
	await _test_replicated_jump_expression()
	await _test_independent_split_height_landing()
	await _test_missing_limb_combinations()
	await _test_contextual_kick_pose_and_foot_choice()
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


func _test_partial_sole_contact_preserves_ankle_center() -> void:
	var fixture := Node3D.new()
	fixture.name = "PartialSoleContactFixture"
	root.add_child(fixture)
	var origin := Vector3(0.0, 0.985, 12.0)
	var left_x := -PlayerProceduralLegRig.HIP_LATERAL_OFFSET
	var right_x := PlayerProceduralLegRig.HIP_LATERAL_OFFSET
	var toe_z := -PlayerProceduralLegRig.FOOT_HALF_LENGTH * 0.72
	# The left foot has support only below its toe probe. The right gets an ordinary full support so
	# the fixture still represents a valid biped stance rather than a total support failure.
	_add_static_box(
		fixture,
		Vector3(0.14, 0.10, 0.07),
		Vector3(left_x, -0.05, origin.z + toe_z),
		CharacterContactLayers.FOOT_CONTACT_DETAIL
	)
	_add_static_box(
		fixture,
		Vector3(0.14, 0.10, 0.48),
		Vector3(right_x, -0.05, origin.z),
		CharacterContactLayers.FOOT_CONTACT_DETAIL
	)
	var rig := _add_rig(fixture, origin)
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.0, false)
	var left_local := rig.to_local(
		rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
	)
	_expect(
		rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT)
		and absf(left_local.z) < 0.035,
		(
			"a toe-only contact reconstructs the ankle centre on its support plane instead of shifting the whole foot to the toe probe (z=%.4f)"
			% left_local.z
		)
	)
	fixture.queue_free()
	await _settle_physics()


func _test_short_reversal_balance_envelope() -> void:
	var fixture := Node3D.new()
	fixture.name = "ShortReversalBalanceFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(4.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(4.0, 0.985, 0.0))
	rig.set_expression_identity(27)
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	var original_left := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var original_right := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	var gait_cycle := 0.5
	var saw_reversal_step := false
	var maximum_balance_roll := 0.0
	var short_velocity := Vector3.RIGHT * 1.2
	for reversal: int in range(6):
		short_velocity.x = 1.2 if posmod(reversal, 2) == 0 else -1.2
		for _frame: int in range(4):
			rig.global_position += short_velocity * STEP
			gait_cycle += short_velocity.length() / PlayerGait.WALK_STEP_DISTANCE * STEP
			rig.update_pose(STEP, short_velocity, true, gait_cycle, true)
			saw_reversal_step = (
				saw_reversal_step or rig.get_active_swing_side() >= 0
			)
			maximum_balance_roll = maxf(
				maximum_balance_roll,
				absf(rig.get_body_yield_rotation().z)
			)
	_expect(
		not saw_reversal_step
		and original_left.distance_to(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.LEFT)
		) < 0.001
		and original_right.distance_to(
			rig.get_foot_world_position(PlayerProceduralLegRig.Side.RIGHT)
		) < 0.001
		and maximum_balance_roll > deg_to_rad(0.5),
		"brief opposing inputs remain inside the stance and become a whole-body balance wiggle instead of nervous foot replants"
	)
	var sustained_velocity := Vector3.FORWARD * ServerPlayer.WALK_SPEED
	var sustained_step_started := false
	for _frame: int in range(36):
		rig.global_position += sustained_velocity * STEP
		gait_cycle += sustained_velocity.length() / PlayerGait.WALK_STEP_DISTANCE * STEP
		rig.update_pose(STEP, sustained_velocity, true, gait_cycle, true)
		sustained_step_started = (
			sustained_step_started or rig.get_active_swing_side() >= 0
		)
	_expect(
		sustained_step_started,
		"sustained travel exits the balance envelope and still schedules an ordinary gait step"
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


func _test_contextual_kick_pose_and_foot_choice() -> void:
	var fixture := Node3D.new()
	fixture.name = "ContextualKickFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(12.0, -0.1, 8.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(12.0, 0.985, 8.0))
	rig.set_expression_identity(33)
	await _settle_physics()
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	var initial_left := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var initial_right := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	rig.update_pose(
		STEP,
		Vector3.ZERO,
		true,
		0.5,
		false,
		-1,
		0,
		0.0,
		0.0,
		1,
		PlayerProceduralLegRig.Side.LEFT,
		0.50,
		Vector3.FORWARD
	)
	var striking_left := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var left_points := rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)
	_expect(
		rig.is_kick_active()
		and rig.get_kick_side() == PlayerProceduralLegRig.Side.LEFT
		and (striking_left - initial_left).dot(Vector3.FORWARD) > 0.75
		and initial_right.distance_to(rig.get_foot_world_position(
			PlayerProceduralLegRig.Side.RIGHT
		)) < 0.015
		and absf(
			left_points[0].distance_to(left_points[1])
			- PlayerProceduralLegRig.UPPER_LEG_LENGTH
		) < 0.001,
		"the chosen live foot chambers and extends through the reusable IK chain without moving its support foot"
	)
	rig.update_pose(
		STEP,
		Vector3.ZERO,
		true,
		0.5,
		false,
		-1,
		0,
		0.0,
		0.0,
		1,
		PlayerProceduralLegRig.Side.LEFT,
		1.0,
		Vector3.FORWARD
	)
	_expect(
		not rig.is_kick_active()
		and rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT),
		"kick recovery returns the acting foot to a sampled support instead of snapping to a canned pose"
	)
	var drop_start_left := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var drop_start_right := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	rig.update_pose(
		STEP,
		Vector3(0.0, 2.0, -ServerPlayer.RUN_SPEED),
		false,
		1.5,
		true,
		0,
		0,
		0.0,
		0.0,
		2,
		PlayerProceduralLegRig.Side.RIGHT,
		0.95,
		Vector3.FORWARD,
		1.55,
		true,
		ServerPlayer.KickStyle.DROP
	)
	var drop_left := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var drop_right := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	var drop_left_travel := (drop_left - drop_start_left).dot(
		Vector3.FORWARD
	)
	var drop_right_travel := (drop_right - drop_start_right).dot(
		Vector3.FORWARD
	)
	var drop_left_knee := rig.get_leg_points(
		PlayerProceduralLegRig.Side.LEFT
	)[1]
	var drop_right_knee := rig.get_leg_points(
		PlayerProceduralLegRig.Side.RIGHT
	)[1]
	_expect(
		rig.is_kick_active()
		and drop_left_travel > 0.62
		and drop_right_travel > 0.62
		and absf(drop_left_travel - drop_right_travel) > 0.015
		and (
			absf(drop_left_knee.y - drop_right_knee.y)
			+ absf(drop_left_knee.z - drop_right_knee.z)
		) > 0.015,
		"dropkick presentation drives both feet forward while deterministic stagger and knee variation avoid a mirrored canned pose"
	)
	rig.update_pose(
		STEP,
		Vector3(0.0, 2.0, -ServerPlayer.RUN_SPEED),
		false,
		1.5,
		true,
		0,
		0,
		0.0,
		0.0,
		2,
		PlayerProceduralLegRig.Side.RIGHT,
		1.0,
		Vector3.FORWARD,
		1.55,
		false,
		ServerPlayer.KickStyle.DROP
	)
	# A flip rotates the visible body independently of world gravity. The kick must remain authored
	# in that rotating frame so its extension is equally readable at every point in the somersault.
	rig.rotation.x = deg_to_rad(128.0)
	var flip_forward := (rig.global_basis * Vector3.FORWARD).normalized()
	rig.update_pose(
		STEP,
		Vector3(0.0, 1.5, -ServerPlayer.RUN_SPEED),
		false,
		1.8,
		true,
		1,
		0,
		0.0,
		0.0,
		3,
		PlayerProceduralLegRig.Side.RIGHT,
		0.52,
		flip_forward,
		1.5,
		true,
		ServerPlayer.KickStyle.SINGLE
	)
	var flip_kick_foot_local := rig.to_local(rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	))
	var flip_kick_hip_local := rig.to_local(rig.get_hip_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	))
	var flip_support_foot_local := rig.to_local(rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	))
	var flip_support_hip_local := rig.to_local(rig.get_hip_world_position(
		PlayerProceduralLegRig.Side.LEFT
	))
	_expect(
		(flip_kick_foot_local - flip_kick_hip_local).dot(Vector3.FORWARD)
		> 0.82
		and flip_kick_foot_local.y > flip_kick_hip_local.y + 0.08
		and flip_support_foot_local.y > flip_support_hip_local.y - 0.58
		and flip_support_foot_local.z > flip_kick_foot_local.z + 0.55,
		"flip kicks keep the striking foot high and forward in the rotating body frame while the free leg counter-tucks"
	)
	rig.rotation.x = 0.0
	rig.set_limb_presence(false, true)
	_expect(
		rig.suggest_kick_side(Vector3.FORWARD, 3.0)
		== PlayerProceduralLegRig.Side.RIGHT,
		"live foot selection always falls back to the installed limb when the preferred leg is missing"
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
		least_forward_knee <= -0.30 and forward_knee_frames >= 48,
		"walking-speed swings keep a knee driven visibly ahead of the hips instead of dragging both knees behind the camera"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_natural_multistep_gait() -> void:
	var fixture := Node3D.new()
	fixture.name = "NaturalMultistepGaitFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(18.0, 0.2, 120.0),
		Vector3(34.0, -0.1, -48.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var walk_rig := _add_rig(fixture, Vector3(31.0, 0.985, 4.0))
	var run_rig := _add_rig(fixture, Vector3(37.0, 0.985, 4.0))
	walk_rig.set_expression_identity(41)
	run_rig.set_expression_identity(41)
	await _settle_physics()
	var walk_metrics := _simulate_flat_gait(
		walk_rig,
		ServerPlayer.WALK_SPEED,
		false,
		240
	)
	var run_metrics := _simulate_flat_gait(
		run_rig,
		ServerPlayer.RUN_SPEED,
		true,
		180
	)
	print(
		"[NATURAL GAIT] walk: %d contacts, %.2f/s, %.2fm | run: %d contacts, %.2f/s, %.2fm"
		% [
			int(walk_metrics["contacts"]),
			float(walk_metrics["cadence"]),
			float(walk_metrics["average_spacing"]),
			int(run_metrics["contacts"]),
			float(run_metrics["cadence"]),
			float(run_metrics["average_spacing"]),
		]
	)
	_expect(
		int(walk_metrics["contacts"]) >= 12
		and int(walk_metrics["alternation_failures"]) == 0
		and bool(walk_metrics["finite"]),
		"a four-second walk produces repeated finite left/right contacts without robotic double-stepping"
	)
	_expect(
		float(walk_metrics["cadence"]) >= 3.0
		and float(walk_metrics["cadence"]) <= 5.0
		and float(walk_metrics["average_spacing"]) >= 1.15
		and float(walk_metrics["average_spacing"]) <= 1.85,
		"walking uses medium steps and a restrained cadence instead of constant tiny shuffles"
	)
	_expect(
		float(walk_metrics["spacing_range"]) > 0.045
		and float(walk_metrics["max_planted_drift"]) < 0.001,
		"walk placement varies inside its authored range while each supporting foot remains anchored"
	)
	_expect(
		float(run_metrics["cadence"]) > float(walk_metrics["cadence"])
		and float(run_metrics["average_spacing"])
		> float(walk_metrics["average_spacing"]) * 1.35
		and float(run_metrics["average_stance"])
		> float(walk_metrics["average_stance"]) * 1.08,
		"speed continuously turns the walk into faster, longer, and wider running steps"
	)
	_expect(
		float(walk_metrics["max_visual_step"])
		< float(walk_metrics["average_spacing"]) * 0.35
		and float(walk_metrics["max_mid_swing_step_change"])
		< float(walk_metrics["average_spacing"]) * 0.18
		and float(run_metrics["max_visual_step"])
		< float(run_metrics["average_spacing"]) * 0.35
		and float(run_metrics["max_mid_swing_step_change"])
		< float(run_metrics["average_spacing"]) * 0.18
		and float(walk_metrics["max_swing_target_drift"]) < 0.001
		and float(run_metrics["max_swing_target_drift"]) < 0.001,
		"fixed touchdown targets keep multi-step ankle motion continuous without a mid-swing shove"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_run_release_recovery_steps() -> void:
	var fixture := Node3D.new()
	fixture.name = "RunReleaseRecoveryFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 24.0),
		Vector3(16.0, -0.1, -8.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(16.0, 0.985, 0.0))
	var gait := PlayerGait.new()
	gait.set_expression_identity(34)
	rig.set_expression_identity(34)
	await _settle_physics()
	gait.advance(ServerPlayer.RUN_SPEED, true, true, STEP)
	rig.update_pose(
		STEP,
		Vector3.FORWARD * ServerPlayer.RUN_SPEED,
		true,
		gait.get_cycle(),
		gait.active,
		-1,
		0,
		0.0,
		gait.get_momentum_recovery_weight()
	)
	var speed := ServerPlayer.RUN_SPEED
	var contact_count := 0
	var maximum_foot_lift := 0.0
	var recovery_survived_zero_speed := false
	for _frame: int in range(100):
		speed = maxf(speed - ServerPlayer.GROUND_DECELERATION * STEP, 0.0)
		gait.advance(speed, true, false, STEP)
		var velocity := Vector3.FORWARD * speed
		rig.global_position += velocity * STEP
		rig.update_pose(
			STEP,
			velocity,
			true,
			gait.get_cycle(),
			gait.active,
			-1,
			0,
			0.0,
			gait.get_momentum_recovery_weight()
		)
		contact_count += int(rig.has_foot_contact_event())
		maximum_foot_lift = maxf(
			maximum_foot_lift,
			maxf(
				rig.get_foot_world_position(
					PlayerProceduralLegRig.Side.LEFT
				).y,
				rig.get_foot_world_position(
					PlayerProceduralLegRig.Side.RIGHT
				).y
			)
		)
		if speed <= 0.001 and gait.active:
			recovery_survived_zero_speed = true
	_expect(
		contact_count >= 2
		and contact_count <= 4
		and maximum_foot_lift > 0.16
		and recovery_survived_zero_speed
		and rig.get_active_swing_side() < 0,
		"a released full sprint resolves into a few lifted catch steps and settles both feet even after translation stops"
	)
	fixture.queue_free()
	await _settle_physics()


func _simulate_flat_gait(
	rig: PlayerProceduralLegRig,
	speed: float,
	running: bool,
	frame_count: int
) -> Dictionary:
	var gait := PlayerGait.new()
	gait.set_expression_identity(41)
	gait.distance_since_step = 0.0
	var velocity := Vector3(0.0, 0.0, -speed)
	rig.update_pose(STEP, velocity, true, gait.get_cycle(), false)
	var previous_left := rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)[2]
	var previous_right := rig.get_leg_points(PlayerProceduralLegRig.Side.RIGHT)[2]
	var previous_left_step := 0.0
	var previous_right_step := 0.0
	var previous_left_anchor := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var previous_right_anchor := rig.get_foot_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	var last_contact_side := -1
	var last_contact_position := Vector3.ZERO
	var contacts := 0
	var alternation_failures := 0
	var spacing_sum := 0.0
	var spacing_count := 0
	var spacing_min := INF
	var spacing_max := -INF
	var stance_sum := 0.0
	var max_visual_step := 0.0
	var max_mid_swing_step_change := 0.0
	var previous_swing_side := -1
	var previous_swing_step := 0.0
	var previous_swing_target := Vector3.ZERO
	var max_swing_target_drift := 0.0
	var max_planted_drift := 0.0
	var finite := true
	for _frame: int in range(frame_count):
		gait.advance(speed, true, running, STEP)
		rig.global_position += velocity * STEP
		rig.update_pose(
			STEP,
			velocity,
			true,
			gait.get_cycle(),
			gait.active
		)
		var left_points := rig.get_leg_points(PlayerProceduralLegRig.Side.LEFT)
		var right_points := rig.get_leg_points(PlayerProceduralLegRig.Side.RIGHT)
		finite = finite and _points_are_finite(left_points) and _points_are_finite(right_points)
		var current_left := left_points[2]
		var current_right := right_points[2]
		var left_step := current_left.distance_to(previous_left)
		var right_step := current_right.distance_to(previous_right)
		var frame_visual_step := maxf(left_step, right_step)
		max_visual_step = maxf(max_visual_step, frame_visual_step)
		var active_side := rig.get_active_swing_side()
		if active_side >= 0:
			var active_step := (
				left_step
				if active_side == PlayerProceduralLegRig.Side.LEFT
				else right_step
			)
			var active_progress := rig.get_swing_progress(active_side)
			if (
				active_side == previous_swing_side
				and active_progress > 0.10
				and active_progress < 0.90
			):
				max_mid_swing_step_change = maxf(
					max_mid_swing_step_change,
					absf(active_step - previous_swing_step)
				)
				max_swing_target_drift = maxf(
					max_swing_target_drift,
					rig.get_swing_target_world_position(active_side).distance_to(
						previous_swing_target
					)
				)
			previous_swing_side = active_side
			previous_swing_step = active_step
			previous_swing_target = rig.get_swing_target_world_position(
				active_side
			)
		else:
			previous_swing_side = -1
			previous_swing_step = 0.0
			previous_swing_target = Vector3.ZERO
		var left_anchor := rig.get_foot_world_position(
			PlayerProceduralLegRig.Side.LEFT
		)
		var right_anchor := rig.get_foot_world_position(
			PlayerProceduralLegRig.Side.RIGHT
		)
		var contact_side := (
			rig.get_foot_contact_event_side()
			if rig.has_foot_contact_event()
			else -1
		)
		if (
			rig.is_foot_planted(PlayerProceduralLegRig.Side.LEFT)
			and contact_side != PlayerProceduralLegRig.Side.LEFT
		):
			max_planted_drift = maxf(
				max_planted_drift,
				left_anchor.distance_to(previous_left_anchor)
			)
		if (
			rig.is_foot_planted(PlayerProceduralLegRig.Side.RIGHT)
			and contact_side != PlayerProceduralLegRig.Side.RIGHT
		):
			max_planted_drift = maxf(
				max_planted_drift,
				right_anchor.distance_to(previous_right_anchor)
			)
		if rig.has_foot_contact_event():
			var side := rig.get_foot_contact_event_side()
			var contact_position := rig.get_foot_contact_event_position()
			if last_contact_side == side:
				alternation_failures += 1
			if contacts > 0:
				var spacing := absf(contact_position.z - last_contact_position.z)
				spacing_sum += spacing
				spacing_count += 1
				spacing_min = minf(spacing_min, spacing)
				spacing_max = maxf(spacing_max, spacing)
			stance_sum += absf(rig.to_local(contact_position).x)
			last_contact_side = side
			last_contact_position = contact_position
			contacts += 1
		previous_left = current_left
		previous_right = current_right
		previous_left_step = left_step
		previous_right_step = right_step
		previous_left_anchor = left_anchor
		previous_right_anchor = right_anchor
	var duration := float(frame_count) * STEP
	return {
		"contacts": contacts,
		"alternation_failures": alternation_failures,
		"cadence": float(contacts) / maxf(duration, STEP),
		"average_spacing": spacing_sum / maxf(float(spacing_count), 1.0),
		"spacing_range": spacing_max - spacing_min if spacing_count > 1 else 0.0,
		"average_stance": stance_sum / maxf(float(contacts), 1.0),
		"max_visual_step": max_visual_step,
		"max_mid_swing_step_change": max_mid_swing_step_change,
		"max_swing_target_drift": max_swing_target_drift,
		"max_planted_drift": max_planted_drift,
		"finite": finite,
	}


func _test_contact_driven_footfall() -> void:
	var fixture := Node3D.new()
	fixture.name = "ContactDrivenFootfallFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 12.0),
		Vector3(24.0, -0.1, -4.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(24.0, 0.985, 0.0))
	rig.set_expression_identity(19)
	await _settle_physics()
	var velocity := Vector3(0.0, 0.0, -1.2)
	var swing_start := PlayerGait.get_swing_start_phase(false, 19, 1)
	for _frame: int in range(12):
		rig.global_position += velocity * STEP
		rig.update_pose(STEP, velocity, true, swing_start - 0.01, true)
	_expect(
		not rig.has_foot_contact_event(),
		"a footstep stays silent while the selected foot is still planted or in flight"
	)
	rig.update_pose(STEP, velocity, true, swing_start + 0.01, true)
	var active_side := rig.get_active_swing_side()
	_expect(
		active_side >= 0 and rig.is_foot_swinging(active_side),
		"the ranged gait profile starts the foot before its shared impact boundary"
	)
	rig.update_pose(STEP, velocity, true, 1.0, true)
	var contact_side := rig.get_foot_contact_event_side()
	var contact_position := rig.get_foot_contact_event_position()
	_expect(
		rig.has_foot_contact_event()
		and rig.get_foot_contact_event_sequence() == 1
		and contact_side == active_side
		and rig.is_foot_planted(contact_side)
		and absf(contact_position.y) < EPSILON,
		"the audible event is raised by the sampled planted foot at the actual floor contact"
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
		) < 0.055,
		"by the apex both feet have smoothly recovered into a bounded moving landing-ready envelope"
	)
	fixture.queue_free()
	await _settle_physics()


func _test_impact_scaled_landing_compression() -> void:
	var fixture := Node3D.new()
	fixture.name = "ImpactScaledLandingCompressionFixture"
	root.add_child(fixture)
	_add_static_box(
		fixture,
		Vector3(8.0, 0.2, 8.0),
		Vector3(32.0, -0.1, 0.0),
		CharacterContactLayers.MOVEMENT_SURFACE
	)
	var rig := _add_rig(fixture, Vector3(32.0, 0.985, 0.0))
	var late_join_rig := _add_rig(fixture, Vector3(34.0, 0.985, 0.0))
	await _settle_physics()
	late_join_rig.update_pose(
		STEP,
		Vector3.ZERO,
		true,
		0.0,
		false,
		0,
		12,
		0.86
	)
	_expect(
		is_zero_approx(late_join_rig.get_landing_compression()),
		"a late observer baselines the replicated landing sequence instead of replaying stale impact"
	)
	late_join_rig.update_pose(
		STEP,
		Vector3(0.0, -8.0, 0.0),
		false,
		0.0,
		false,
		0,
		13,
		0.55
	)
	late_join_rig.update_pose(
		STEP,
		Vector3.ZERO,
		true,
		0.0,
		false,
		0,
		13,
		0.55
	)
	_expect(
		late_join_rig.get_landing_compression() > 0.0,
		"an out-of-order airborne snapshot keeps the new impact pending until grounded state arrives"
	)
	rig.update_pose(STEP, Vector3.ZERO, true, 0.0, false)
	var ordinary_peak := 0.0
	for frame: int in range(70):
		rig.update_pose(
			STEP,
			Vector3.ZERO,
			true,
			0.0,
			false,
			0,
			1,
			0.28
		)
		ordinary_peak = maxf(ordinary_peak, rig.get_landing_compression())
	var hard_peak := 0.0
	for frame: int in range(90):
		rig.update_pose(
			STEP,
			Vector3.ZERO,
			true,
			0.0,
			false,
			0,
			2,
			0.86
		)
		hard_peak = maxf(hard_peak, rig.get_landing_compression())
	_expect(
		ordinary_peak >= PlayerProceduralLegRig.LANDING_COMPRESSION_DROP_RANGE.x
		and hard_peak > ordinary_peak * 2.0
		and hard_peak <= PlayerProceduralLegRig.LANDING_COMPRESSION_DROP_RANGE.y + 0.001,
		"replicated landing impact continuously scales knee and hip compression instead of replaying one canned crouch"
	)
	_expect(
		rig.get_landing_compression() < 0.001,
		"landing compression recovers smoothly to the standing pose after absorbing the impact"
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
	var whole_body_pose := PlayerCharacterPoseController.new()
	whole_body_pose.set_expression_identity(31)
	for frame: int in range(20):
		whole_body_pose.update(
			STEP,
			float(frame) * STEP,
			0.25,
			0.0,
			0.0,
			0.0,
			Vector3.ZERO,
			true,
			false,
			rig,
			true,
			true,
			true,
			true
		)
	_expect(
		whole_body_pose.upper_body_rotation.z < deg_to_rad(-2.5)
		and whole_body_pose.upper_body_position.y < -0.015,
		"the layered full-body pose preserves real split-height balance instead of flattening it with idle or action motion"
	)
	var authored_pose := CharacterPoseDefinition.new()
	authored_pose.procedural_inheritance = 0.0
	authored_pose.upper_body_weight = 1.0
	authored_pose.upper_body_rotation = Vector3(0.1, 0.0, 0.0)
	whole_body_pose.set_action_pose(authored_pose, 1.0)
	for frame: int in range(20):
		whole_body_pose.update(
			STEP,
			0.5 + float(frame) * STEP,
			0.25,
			0.0,
			0.0,
			0.0,
			Vector3.ZERO,
			true,
			false,
			rig,
			true,
			true,
			true,
			true
		)
	_expect(
		whole_body_pose.upper_body_rotation.x > 0.08
		and whole_body_pose.upper_body_rotation.z < deg_to_rad(-2.5)
		and whole_body_pose.upper_body_position.y < -0.015,
		"an authored emote/action remains additive to physical support instead of replacing balance"
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
	# Keep the physical child active while the proxy's presentation loop is disabled for deterministic
	# direct calls below; otherwise Jolt correctly leaves its rigid bodies outside an active space.
	proxy.player_ragdoll.process_mode = Node.PROCESS_MODE_ALWAYS
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
	var field_pack := load(
		"res://resources/items/backpacks/field_pack.tres"
	) as BackpackDefinition
	proxy.apply_server_state({
		"player_id": 7,
		"inventory_revision": 1,
		"inventory": {
			"capacity": field_pack.inventory_capacity,
			"selected_slot": 0,
			"entries": [],
			"equipment": {
				PlayerInventoryRules.BACKPACK_SLOT:
					PlayerInventoryRules.to_public_entry(
						PlayerInventoryRules.make_entry(field_pack)
					),
			},
		},
	})
	var backpack_visual := proxy.equipment_visuals.get(
		PlayerInventoryRules.BACKPACK_SLOT
	) as Node3D
	proxy.gait_initialized = true
	proxy.visual_gait_cycle = 29.75
	proxy.last_predicted_gait_step_sequence = 29
	proxy.apply_server_state({
		"player_id": 7,
		"inventory_revision": 1,
		"ragdoll_active": true,
		"trip_sequence": 3,
		"trip_direction": Vector3(0.5, 0.0, -1.0),
		"vel": Vector3(2.0, 0.0, -1.0),
		"landing_sequence": 8,
		"landing_impact_strength": 0.62,
		"gait_cycle": 21.5,
		"gait_active": false,
	})
	_expect(
		proxy.target_landing_sequence == 8
		and is_equal_approx(proxy.target_landing_impact_strength, 0.62),
		"joining clients retain the authoritative landing sequence and normalized impact load"
	)
	proxy.call("_sync_trip_presentation")
	_expect(
		is_equal_approx(proxy.visual_gait_cycle, 21.5)
		and proxy.last_predicted_gait_step_sequence == 21,
		"ragdoll entry discards client-led foot contacts and re-arms prediction at authority"
	)
	await _settle_physics()
	proxy.is_local_player = true
	proxy.call("_update_trip_camera", 0.5)
	var ragdoll_head_position: Vector3 = proxy.player_ragdoll.get_head_world_position()
	_expect(
		proxy.player_ragdoll.is_active()
		and not proxy.body_visual.visible
		and proxy.player_ragdoll.get_node("left_arm").visible
		and not proxy.player_ragdoll.get_node("right_arm").visible
		and not proxy.player_ragdoll.get_node("left_upper_leg").visible
		and proxy.player_ragdoll.get_node("right_upper_leg").visible,
		"the replicated trip swaps to an articulated ragdoll containing only installed limbs"
	)
	var ragdoll_torso := proxy.player_ragdoll.get_node("torso") as RigidBody3D
	var ragdoll_head := proxy.player_ragdoll.get_node("head") as RigidBody3D
	var ragdoll_upper_leg := (
		proxy.player_ragdoll.get_node("right_upper_leg") as RigidBody3D
	)
	var ragdoll_lower_leg := (
		proxy.player_ragdoll.get_node("right_lower_leg") as RigidBody3D
	)
	var ragdoll_foot := proxy.player_ragdoll.get_node("right_foot") as RigidBody3D
	var neck_joint := (
		proxy.player_ragdoll.get_node("neck") as Generic6DOFJoint3D
	)
	var knee_joint := (
		proxy.player_ragdoll.get_node("right_knee") as Generic6DOFJoint3D
	)
	_expect(
		(ragdoll_torso.get_node("Collision") as CollisionShape3D).shape
		is CapsuleShape3D
		and (ragdoll_foot.get_node("Collision") as CollisionShape3D).shape
		is CapsuleShape3D
		and ragdoll_torso.continuous_cd
		and ragdoll_foot.continuous_cd
		and ragdoll_torso.physics_material_override != null
		and ragdoll_torso.physics_material_override.friction < 0.25,
		"cosmetic ragdoll contact uses rounded low-friction shapes that cannot hook stair nosings"
	)
	_expect(
		ragdoll_torso.mass > ragdoll_head.mass * 5.0
		and ragdoll_upper_leg.mass > ragdoll_lower_leg.mass
		and ragdoll_lower_leg.mass > ragdoll_foot.mass,
		"ragdoll segments use a human-like central mass hierarchy instead of equally weighted puppet pieces"
	)
	_expect(
		neck_joint != null
		and knee_joint != null
		and neck_joint.get_flag_x(
			Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
		)
		and knee_joint.get_flag_y(
			Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
		)
		and neck_joint.get_flag_x(
			Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING
		),
		"neck, hip, knee, and ankle connections use bounded anatomical joints with an initial active brace"
	)
	var safe_trip_direction := Vector3(0.5, 0.0, -1.0).normalized()
	var torso_forward_lead := (
		ragdoll_torso.linear_velocity - ragdoll_upper_leg.linear_velocity
	).dot(safe_trip_direction)
	var forward_fall_axis := Vector3(
		safe_trip_direction.z,
		0.15,
		-safe_trip_direction.x
	).normalized()
	var torso_forward_rotation := ragdoll_torso.angular_velocity.dot(
		forward_fall_axis
	)
	_expect(
		torso_forward_rotation > 0.05,
		(
			"a forward trip gives the weighted torso a leading fall rotation instead of collapsing every segment simultaneously (linear %.3f, angular %.3f)"
			% [torso_forward_lead, torso_forward_rotation]
		)
	)
	var ragdoll_skin: PlayerCharacterSkin = (
		proxy.player_ragdoll.get_authored_skin()
	)
	_expect(
		proxy.player_ragdoll.has_authored_skin()
		and ragdoll_skin != null
		and ragdoll_skin.visible
		and ragdoll_skin.get_variant_path()
		== proxy.character_skin.get_variant_path()
		and not proxy.player_ragdoll.get_node("torso/Visual").visible
		and not proxy.player_ragdoll.get_node("head/Visual").visible
		and not proxy.player_ragdoll.get_node("left_arm/Visual").visible,
		"ragdoll physics renders the player's exact authored skin while every gray primitive remains collision-only"
	)
	_expect(
		is_instance_valid(backpack_visual)
		and backpack_visual.get_parent() == ragdoll_skin.get_backpack_mount(),
		"an equipped backpack follows the ragdoll's physical upper spine instead of vanishing with the standing body"
	)
	_expect(
		ragdoll_skin.skeleton.get_bone_pose_scale(
			ragdoll_skin.skeleton.find_bone(&"mixamorig_LeftArm")
		).x > 0.99
		and ragdoll_skin.skeleton.get_bone_pose_scale(
			ragdoll_skin.skeleton.find_bone(&"mixamorig_RightArm")
		).x < 0.01
		and ragdoll_skin.skeleton.get_bone_pose_scale(
			ragdoll_skin.skeleton.find_bone(&"mixamorig_LeftUpLeg")
		).x < 0.01
		and ragdoll_skin.skeleton.get_bone_pose_scale(
			ragdoll_skin.skeleton.find_bone(&"mixamorig_RightUpLeg")
		).x > 0.99,
		"the authored ragdoll preserves independently missing limbs instead of restoring a complete cosmetic body"
	)
	_expect(
		proxy.camera_pivot.global_position.distance_to(ragdoll_head_position) < 0.12,
		"the local camera follows the physical ragdoll head instead of remaining on the parked proxy root"
	)
	proxy.player_ragdoll.call(
		"_physics_process",
		PlayerRagdoll3D.ACTIVE_BRACE_SECONDS
	)
	_expect(
		not neck_joint.get_flag_x(
			Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING
		)
		and not proxy.player_ragdoll.is_physics_processing(),
		"active posture decays into a passive constrained ragdoll and stops its per-tick brace work"
	)
	proxy.target_gait_cycle = 22.5
	proxy.visual_gait_cycle = 77.0
	proxy.last_predicted_gait_step_sequence = 77
	proxy.target_ragdoll_active = false
	proxy.call("_sync_trip_presentation")
	_expect(
		not proxy.player_ragdoll.is_active()
		and proxy.body_visual.visible
		and is_equal_approx(proxy.visual_gait_cycle, 22.5)
		and proxy.last_predicted_gait_step_sequence == 22
		and backpack_visual.get_parent()
		== proxy.character_skin.get_backpack_mount(),
		"trip recovery restores the character, backpack, and audible contact clock together"
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
