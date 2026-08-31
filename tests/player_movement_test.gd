extends SceneTree

const STEP := 1.0 / 60.0
const EPSILON := 0.0001
const FULL_BODY := preload(
	"res://resources/character_loadouts/full_body.tres"
)
const INDUSTRIAL_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const ACOUSTIC_HOUSE_SCENE := preload(
	"res://scenes/server/acoustic_test_house.tscn"
)

class RecordingServerPlayer:
	extends ServerPlayer

	var emitted_sound_ids: Array[StringName] = []
	var emitted_sound_positions: Array[Vector3] = []
	var emitted_sound_volume_db := PackedFloat32Array()

	func _emit_gameplay_sound(
		sound_id: StringName,
		_max_distance: float,
		_priority: float,
		_local_prediction_key := 0,
		source_position := Vector3(INF, INF, INF),
		base_volume_db := 0.0
	) -> void:
		emitted_sound_ids.append(sound_id)
		emitted_sound_positions.append(source_position)
		emitted_sound_volume_db.append(base_volume_db)

	func _resolve_foot_contact(_side: int, _contact_sequence: int) -> Dictionary:
		return {
			"position": Vector3(0.2, -0.98, 0.3),
			"collider": null,
		}

	func _landing_lacks_required_support() -> bool:
		return false


var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ground_acceleration_and_braking()
	_test_sprint_speed_curve()
	_test_run_release_momentum_recovery()
	_test_sprint_exhaustion_momentum_recovery()
	_test_airborne_momentum_and_control()
	_test_wall_collision_velocity()
	await _test_velocity_driven_environmental_impacts()
	_test_shared_gait_clock()
	_test_authoritative_jump_arc()
	_test_momentum_gated_flip_jump()
	await _test_contextual_kick_authority()
	await _test_dropkick_authority()
	await _test_impact_scaled_landing_and_hard_trip()
	await _test_authoritative_split_support_trip()
	await _test_authoritative_ragdoll_relocation()
	await _test_death_respawn_and_corpse_detach()
	await _test_ragdoll_stair_recovery()
	await _test_ragdoll_penetration_fallback()
	await _test_authoritative_step_traversal()
	await _test_authored_entrance_traversal()
	_finish()


func _test_ground_acceleration_and_braking() -> void:
	_expect(
		ServerPlayer.WALK_SPEED < ServerPlayer.RUN_SPEED * 0.55,
		"normal walking keeps a deliberate pace distinct from sprinting"
	)
	var velocity := ServerPlayer.calculate_horizontal_velocity(
		Vector3.ZERO,
		Vector3.FORWARD,
		ServerPlayer.WALK_SPEED,
		true,
		STEP
	)
	_expect(
		velocity.length() > 0.0
		and velocity.length() < ServerPlayer.WALK_SPEED,
		"ground movement accelerates instead of snapping to full speed"
	)
	for _step: int in range(30):
		velocity = ServerPlayer.calculate_horizontal_velocity(
			velocity,
			Vector3.FORWARD,
			ServerPlayer.WALK_SPEED,
			true,
			STEP
		)
	_expect(
		is_equal_approx(velocity.length(), ServerPlayer.WALK_SPEED),
		"sustained ground input reaches the authored walk speed"
	)
	var braking := ServerPlayer.calculate_horizontal_velocity(
		velocity,
		Vector3.ZERO,
		ServerPlayer.WALK_SPEED,
		true,
		STEP
	)
	_expect(
		braking.length() > 0.0 and braking.length() < velocity.length(),
		"releasing ground input brakes progressively instead of stopping instantly"
	)


func _test_sprint_speed_curve() -> void:
	var quarter_speed := ServerPlayer.sprint_speed_at_elapsed(
		ServerPlayer.SPRINT_SPEED_RAMP_SECONDS * 0.25
	)
	var halfway_speed := ServerPlayer.sprint_speed_at_elapsed(
		ServerPlayer.SPRINT_SPEED_RAMP_SECONDS * 0.5
	)
	var three_quarter_speed := ServerPlayer.sprint_speed_at_elapsed(
		ServerPlayer.SPRINT_SPEED_RAMP_SECONDS * 0.75
	)
	_expect(
		is_equal_approx(ServerPlayer.sprint_speed_at_elapsed(0.0), ServerPlayer.WALK_SPEED)
		and quarter_speed > ServerPlayer.WALK_SPEED
		and quarter_speed < halfway_speed
		and is_equal_approx(
			halfway_speed,
			(ServerPlayer.WALK_SPEED + ServerPlayer.RUN_SPEED) * 0.5
		)
		and three_quarter_speed > halfway_speed
		and three_quarter_speed < ServerPlayer.RUN_SPEED,
		"sprint speed follows a continuous nonlinear curve instead of jumping from walk to run"
	)
	_expect(
		is_equal_approx(
			ServerPlayer.sprint_speed_at_elapsed(
				ServerPlayer.SPRINT_SPEED_RAMP_SECONDS
			),
			ServerPlayer.RUN_SPEED
		)
		and is_equal_approx(
			ServerPlayer.sprint_speed_at_elapsed(100.0),
			ServerPlayer.RUN_SPEED
		),
		"the sprint curve reaches and clamps to full speed at exactly 1.5 seconds"
	)
	var grounded_elapsed := 0.0
	for _tick: int in range(45):
		grounded_elapsed = ServerPlayer.advance_sprint_speed_ramp(
			grounded_elapsed,
			true,
			true,
			STEP
		)
	var airborne_elapsed := ServerPlayer.advance_sprint_speed_ramp(
		grounded_elapsed,
		true,
		false,
		0.5
	)
	_expect(
		is_equal_approx(grounded_elapsed, 0.75)
		and is_equal_approx(airborne_elapsed, grounded_elapsed)
		and is_zero_approx(
			ServerPlayer.advance_sprint_speed_ramp(
				grounded_elapsed,
				false,
				true,
				STEP
			)
		),
		"only grounded sprint effort advances the ramp; jumping preserves earned speed and releasing sprint resets it"
	)


func _test_run_release_momentum_recovery() -> void:
	var gait := PlayerGait.new()
	gait.set_expression_identity(14)
	gait.advance(ServerPlayer.RUN_SPEED, true, true, STEP)
	gait.distance_since_step = 0.0
	var stopping_velocity := Vector3.FORWARD * ServerPlayer.RUN_SPEED
	var maximum_recovery_weight := 0.0
	var recovery_steps := 0
	var remained_active_after_stop := false
	var speed_after_quarter_second := 0.0
	var carried_distance := 0.0
	for _frame: int in range(90):
		gait.update_momentum_recovery(
			stopping_velocity.length(),
			true,
			false,
			STEP
		)
		stopping_velocity = ServerPlayer.calculate_horizontal_velocity(
			stopping_velocity,
			Vector3.ZERO,
			0.0,
			true,
			STEP,
			gait.get_momentum_recovery_weight()
		)
		carried_distance += stopping_velocity.length() * STEP
		recovery_steps += gait.advance(
			stopping_velocity.length(),
			true,
			false,
			STEP,
			true
		)
		maximum_recovery_weight = maxf(
			maximum_recovery_weight,
			gait.get_momentum_recovery_weight()
		)
		if _frame == 14:
			speed_after_quarter_second = stopping_velocity.length()
		if stopping_velocity.length() <= 0.001 and gait.active:
			remained_active_after_stop = true
	_expect(
		maximum_recovery_weight > 0.95
		and recovery_steps >= 2
		and recovery_steps <= 4
		and speed_after_quarter_second > ServerPlayer.WALK_SPEED
		and carried_distance > 3.0
		and remained_active_after_stop
		and gait.get_momentum_recovery_weight() <= 0.001
		and not gait.active,
		"releasing a full sprint physically carries forward through a bounded few-step momentum-shedding phase"
	)
	var feathered_walk_gait := PlayerGait.new()
	feathered_walk_gait.advance(ServerPlayer.RUN_SPEED, true, true, STEP)
	var feathered_walk_velocity := Vector3.FORWARD * ServerPlayer.RUN_SPEED
	for _frame: int in range(15):
		feathered_walk_gait.update_momentum_recovery(
			feathered_walk_velocity.length(),
			true,
			false,
			STEP
		)
		feathered_walk_velocity = ServerPlayer.calculate_horizontal_velocity(
			feathered_walk_velocity,
			Vector3.FORWARD,
			ServerPlayer.WALK_SPEED,
			true,
			STEP,
			feathered_walk_gait.get_momentum_recovery_weight()
		)
		feathered_walk_gait.advance(
			feathered_walk_velocity.length(),
			true,
			false,
			STEP,
			true
		)
	_expect(
		feathered_walk_velocity.length() > ServerPlayer.WALK_SPEED,
		"releasing sprint while holding forward feathers earned speed before returning to ordinary walking"
	)
	var walking_release := PlayerGait.new()
	walking_release.advance(ServerPlayer.WALK_SPEED, true, true, STEP)
	walking_release.advance(ServerPlayer.WALK_SPEED, true, false, STEP)
	_expect(
		walking_release.get_momentum_recovery_weight() <= 0.001,
		"ending an ordinary walk does not replay the full-sprint recovery gait"
	)


func _test_sprint_exhaustion_momentum_recovery() -> void:
	var player := RecordingServerPlayer.new()
	player.gait.set_expression_identity(29)
	player.gait.advance(ServerPlayer.RUN_SPEED, true, true, STEP)
	player.velocity = Vector3.FORWARD * ServerPlayer.RUN_SPEED
	player.wants_run = true
	player.sprint_speed_ramp_elapsed = ServerPlayer.SPRINT_SPEED_RAMP_SECONDS
	player.stamina = ServerPlayer.RUN_STAMINA_DRAIN_PER_SECOND * STEP * 0.5
	player.call("_update_vitals", STEP, true, true)
	var speed_on_exhaustion := player.velocity.length()
	var speed_after_quarter_second := speed_on_exhaustion
	var maximum_recovery_weight := 0.0
	for frame: int in range(16):
		player.gait.update_momentum_recovery(
			player.velocity.length(),
			true,
			player.is_actually_running,
			STEP
		)
		player.velocity = ServerPlayer.calculate_horizontal_velocity(
			player.velocity,
			Vector3.FORWARD,
			ServerPlayer.WALK_SPEED,
			true,
			STEP,
			player.gait.get_momentum_recovery_weight()
		)
		maximum_recovery_weight = maxf(
			maximum_recovery_weight,
			player.gait.get_momentum_recovery_weight()
		)
		player.call("_update_vitals", STEP, true, true)
		if frame == 14:
			speed_after_quarter_second = player.velocity.length()
	_expect(
		player.sprint_exhausted
		and not player.is_actually_running
		and is_zero_approx(player.sprint_speed_ramp_elapsed)
		and maximum_recovery_weight > 0.95
		and speed_after_quarter_second > ServerPlayer.WALK_SPEED + 1.0,
		"empty END preserves sprint momentum and enters the same visible feathering gait instead of snapping to walking speed"
	)
	player.stamina = (
		ServerPlayer.MAX_STAMINA
		* ServerPlayer.SPRINT_EXHAUSTION_RECOVERY_RATIO
	)
	player.call("_update_vitals", STEP, true, true)
	_expect(
		not player.sprint_exhausted and player.is_actually_running,
		"held sprint can resume only after END crosses the exhaustion recovery threshold"
	)
	player.free()


func _test_airborne_momentum_and_control() -> void:
	var takeoff_velocity := Vector3(13.5, 4.0, -2.75)
	var coasting := ServerPlayer.calculate_horizontal_velocity(
		takeoff_velocity,
		Vector3.ZERO,
		ServerPlayer.WALK_SPEED,
		false,
		STEP
	)
	_expect(
		coasting.is_equal_approx(Vector3(13.5, 0.0, -2.75)),
		"an airborne player preserves horizontal takeoff momentum without input"
	)

	var fast_takeoff := Vector3(18.0, 0.0, 0.0)
	var holding_forward := ServerPlayer.calculate_horizontal_velocity(
		fast_takeoff,
		Vector3.RIGHT,
		ServerPlayer.WALK_SPEED,
		false,
		STEP
	)
	_expect(
		holding_forward.is_equal_approx(fast_takeoff),
		"air control does not clamp carried momentum down to normal movement speed"
	)

	var steered := ServerPlayer.calculate_horizontal_velocity(
		Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0),
		Vector3.FORWARD,
		ServerPlayer.RUN_SPEED,
		false,
		STEP
	)
	_expect(
		steered.z < 0.0
		and steered.length() <= ServerPlayer.RUN_SPEED + EPSILON,
		"limited air steering changes heading without creating extra speed"
	)

	var opposed := ServerPlayer.calculate_horizontal_velocity(
		Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0),
		Vector3.LEFT,
		ServerPlayer.RUN_SPEED,
		false,
		STEP
	)
	_expect(
		opposed.x > 0.0 and opposed.x < ServerPlayer.RUN_SPEED,
		"opposite air input cannot reverse momentum in a single frame"
	)


func _test_wall_collision_velocity() -> void:
	var slid := ServerPlayer.horizontal_velocity_after_wall_collision(
		Vector3(-8.0, 4.0, 3.0),
		Vector3.RIGHT
	)
	_expect(
		is_zero_approx(slid.x)
		and is_equal_approx(slid.y, 4.0)
		and is_equal_approx(slid.z, 3.0),
		"wall impacts shed only the blocked momentum and preserve the tangent"
	)
	var separating := ServerPlayer.horizontal_velocity_after_wall_collision(
		Vector3(2.0, -1.0, 3.0),
		Vector3.RIGHT
	)
	_expect(
		separating.is_equal_approx(Vector3(2.0, -1.0, 3.0)),
		"a wall normal never removes velocity already moving away from it"
	)
	_expect(
		ServerPlayer.body_impact_response_strength(3.0)
		< ServerPlayer.body_impact_response_strength(7.0)
		and ServerPlayer.body_impact_response_strength(7.0)
		< ServerPlayer.body_impact_response_strength(ServerPlayer.RUN_SPEED)
		and is_equal_approx(
			ServerPlayer.body_impact_response_strength(ServerPlayer.RUN_SPEED),
			1.0
		),
		"experienced collision load grows nonlinearly from actual velocity rather than a movement mode flag"
	)
	var active_flip_threshold := (
		ServerPlayer.flip_body_impact_trip_speed_threshold(true, 0.0)
	)
	var early_recovery_threshold := (
		ServerPlayer.flip_body_impact_trip_speed_threshold(
			false,
			ServerPlayer.FLIP_POST_IMPACT_VULNERABILITY_SECONDS * 0.75
		)
	)
	var late_recovery_threshold := (
		ServerPlayer.flip_body_impact_trip_speed_threshold(
			false,
			ServerPlayer.FLIP_POST_IMPACT_VULNERABILITY_SECONDS * 0.25
		)
	)
	_expect(
		is_equal_approx(
			active_flip_threshold,
			ServerPlayer.FLIP_BODY_IMPACT_TRIP_MIN_SPEED
		)
		and early_recovery_threshold > active_flip_threshold
		and late_recovery_threshold > early_recovery_threshold
		and is_inf(
			ServerPlayer.flip_body_impact_trip_speed_threshold(false, 0.0)
		),
		"flip collision vulnerability fades continuously into ordinary impact handling after rotation"
	)


func _test_velocity_driven_environmental_impacts() -> void:
	var standing_y := ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5
	var floor := _add_static_box(
		"BodyImpactFloor",
		Vector3(14.0, 0.2, 5.0),
		Vector3(3.5, -0.1, 0.0)
	)
	var wall := _add_static_box(
		"BodyImpactWall",
		Vector3(2.5, 2.5, 0.2),
		Vector3(0.0, 1.25, 0.0)
	)
	var wall_player := _make_physics_player(
		Vector3(0.0, standing_y, 0.78)
	)
	wall_player.player_id = 101
	wall_player.on_floor = true
	wall_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	await physics_frame
	# No sprint request is involved: stored velocity alone owns the experienced load.
	wall_player.wants_run = false
	wall_player.server_physics_tick(STEP)
	var wall_state := wall_player.to_state_dict(false)
	_expect(
		wall_player.body_impact_sequence == 1
		and wall_player.body_impact_strength > 0.85
		and wall_player.body_impact_direction.z > 0.9
		and not wall_player.ragdoll_active
		and int(wall_state.get("body_impact_sequence", 0)) == 1
		and float(wall_state.get("body_impact_strength", 0.0)) > 0.85,
		"full stored velocity produces one authoritative wall flinch without consulting sprint state"
	)

	var knee_rock := _add_static_box(
		"BodyImpactKneeRock",
		Vector3(1.5, 0.58, 0.25),
		Vector3(4.0, 0.29, 0.0)
	)
	var rock_player := _make_physics_player(
		Vector3(4.0, standing_y, 0.78)
	)
	rock_player.player_id = 102
	rock_player.on_floor = true
	rock_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	await physics_frame
	rock_player.wants_run = false
	rock_player.server_physics_tick(STEP)
	var rock_state := rock_player.to_state_dict(false)
	_expect(
		rock_player.body_impact_sequence == 1
		and rock_player.ragdoll_active
		and rock_player.trip_sequence == 1
		and rock_player.trip_direction.z < -0.8
		and bool(rock_state.get("ragdoll_active", false)),
		"a velocity-loaded lower-body obstruction with clear upper space becomes a forward trip"
	)
	var slow_knee_rock := _add_static_box(
		"BodyImpactSlowKneeRock",
		Vector3(1.5, 0.58, 0.25),
		Vector3(8.0, 0.29, 0.0)
	)
	var slow_player := _make_physics_player(
		Vector3(8.0, standing_y, 0.70)
	)
	slow_player.player_id = 103
	slow_player.on_floor = true
	slow_player.velocity = Vector3(0.0, 0.0, -7.0)
	await physics_frame
	slow_player.wants_run = false
	slow_player.server_physics_tick(STEP)
	_expect(
		slow_player.body_impact_sequence == 1
		and slow_player.body_impact_strength > 0.0
		and slow_player.body_impact_strength < wall_player.body_impact_strength
		and not slow_player.ragdoll_active,
		(
			"the same knee-high geometry produces only a smaller flinch below its velocity trip load (sequence=%d, strength=%.3f, ragdoll=%s)"
			% [
				slow_player.body_impact_sequence,
				slow_player.body_impact_strength,
				str(slow_player.ragdoll_active),
			]
		)
	)

	var flip_stair := _add_static_box(
		"BodyImpactFlipStair",
		Vector3(1.5, 1.25, 0.25),
		Vector3(12.0, 0.625, 0.0)
	)
	var post_flip_stair := _add_static_box(
		"BodyImpactPostFlipStair",
		Vector3(1.5, 1.25, 0.25),
		Vector3(16.0, 0.625, 0.0)
	)
	var stable_stair := _add_static_box(
		"BodyImpactStableStair",
		Vector3(1.5, 1.25, 0.25),
		Vector3(20.0, 0.625, 0.0)
	)
	var flipping_player := _make_physics_player(
		Vector3(12.0, standing_y, 0.78)
	)
	flipping_player.player_id = 104
	flipping_player.on_floor = false
	flipping_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	flipping_player.call("_begin_flip", -1)
	var post_flip_player := _make_physics_player(
		Vector3(16.0, standing_y, 0.78)
	)
	post_flip_player.player_id = 105
	post_flip_player.on_floor = false
	post_flip_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	post_flip_player.flip_direction = -1
	post_flip_player.flip_active = false
	post_flip_player.flip_phase = 1.0
	post_flip_player.flip_impact_vulnerability_remaining = (
		ServerPlayer.FLIP_POST_IMPACT_VULNERABILITY_SECONDS * 0.75
	)
	var stable_player := _make_physics_player(
		Vector3(20.0, standing_y, 0.78)
	)
	stable_player.player_id = 106
	stable_player.on_floor = false
	stable_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	stable_player.flip_direction = -1
	stable_player.flip_active = false
	stable_player.flip_phase = 1.0
	stable_player.flip_impact_vulnerability_remaining = 0.0
	await physics_frame
	flipping_player.server_physics_tick(STEP)
	post_flip_player.server_physics_tick(STEP)
	stable_player.server_physics_tick(STEP)
	_expect(
		flipping_player.ragdoll_active
		and flipping_player.body_impact_sequence == 1
		and post_flip_player.ragdoll_active
		and post_flip_player.body_impact_sequence == 1
		and not stable_player.ragdoll_active
		and stable_player.body_impact_sequence == 1,
		"a torso-height slam during or shortly after a flip ragdolls, while the same expired collision returns to an ordinary flinch"
	)

	stable_player.free()
	post_flip_player.free()
	flipping_player.free()
	stable_stair.free()
	post_flip_stair.free()
	flip_stair.free()
	slow_player.free()
	rock_player.free()
	wall_player.free()
	slow_knee_rock.free()
	knee_rock.free()
	wall.free()
	floor.free()


func _test_shared_gait_clock() -> void:
	var gait := PlayerGait.new()
	gait.set_expression_identity(23)
	var sampled_walk_min := INF
	var sampled_walk_max := -INF
	var sampled_arc_min := INF
	var sampled_arc_max := -INF
	for sequence: int in range(24):
		var sampled_stride := PlayerGait.get_stride_distance_for_step(
			false,
			23,
			sequence
		)
		var sampled_arc := PlayerGait.get_step_arc_height(23, sequence)
		sampled_walk_min = minf(sampled_walk_min, sampled_stride)
		sampled_walk_max = maxf(sampled_walk_max, sampled_stride)
		sampled_arc_min = minf(sampled_arc_min, sampled_arc)
		sampled_arc_max = maxf(sampled_arc_max, sampled_arc)
	_expect(
		sampled_walk_min >= PlayerGait.WALK_STEP_DISTANCE_RANGE.x
		and sampled_walk_max <= PlayerGait.WALK_STEP_DISTANCE_RANGE.y
		and sampled_walk_max - sampled_walk_min > 0.20
		and sampled_arc_min >= PlayerGait.STEP_ARC_HEIGHT_RANGE.x
		and sampled_arc_max <= PlayerGait.STEP_ARC_HEIGHT_RANGE.y
		and sampled_arc_max - sampled_arc_min > 0.02
		and is_equal_approx(
			PlayerGait.get_step_lead_seconds(23, 7),
			PlayerGait.get_step_lead_seconds(23, 7)
		),
		"step distance, lift, and placement style vary inside deterministic authored ranges"
	)
	var frames_to_first_step := 0
	var first_step_count := 0
	while first_step_count == 0 and frames_to_first_step < 120:
		frames_to_first_step += 1
		first_step_count = gait.advance(
			ServerPlayer.WALK_SPEED,
			true,
			false,
			STEP
		)
	_expect(
		first_step_count == 1
		and frames_to_first_step >= 6
		and frames_to_first_step <= 11
		and gait.active
		and gait.get_phase() < 0.10,
		"movement gets half a settling stride before its first shared footfall"
	)

	var frames_to_next_step := 0
	var next_step_count := 0
	while next_step_count == 0 and frames_to_next_step < 120:
		frames_to_next_step += 1
		next_step_count = gait.advance(
			ServerPlayer.WALK_SPEED,
			true,
			false,
			STEP
		)
	_expect(
		next_step_count == 1
		and frames_to_next_step >= 13
		and frames_to_next_step <= 20,
		"walking advances through a medium deterministic step instead of a tiny fixed shuffle"
	)

	var impact_offset := PlayerGait.calculate_bob_offset(2.0, 0.04, 0.02)
	var high_offset := PlayerGait.calculate_bob_offset(2.5, 0.04, 0.02)
	var before_boundary := PlayerGait.calculate_bob_offset(
		2.9999,
		0.04,
		0.02
	)
	var after_boundary := PlayerGait.calculate_bob_offset(3.0, 0.04, 0.02)
	_expect(
		impact_offset.y < 0.0
		and high_offset.y > 0.0,
		"camera bob reaches its low point on the footstep and rises halfway to the next one"
	)
	_expect(
		before_boundary.distance_to(after_boundary) < 0.001,
		"alternating lateral sway remains continuous when the planted foot changes"
	)

	var phase_before_run := gait.get_phase()
	gait.advance(ServerPlayer.RUN_SPEED, true, true, 0.0)
	_expect(
		is_equal_approx(gait.get_phase(), phase_before_run)
		and gait.stride_distance >= PlayerGait.RUN_STEP_DISTANCE_RANGE.x
		and gait.stride_distance <= PlayerGait.RUN_STEP_DISTANCE_RANGE.y,
		"changing between walk and run preserves gait phase while changing stride length"
	)
	var sequence_before_interruption := gait.step_sequence
	gait.reset_after_full_body_interruption(sequence_before_interruption + 3)
	_expect(
		gait.step_sequence == sequence_before_interruption + 3
		and not gait.active
		and is_equal_approx(gait.get_phase(), 0.5)
		and gait.get_momentum_recovery_weight() <= 0.001,
		"full-body interruption re-arms a balanced gait without rewinding prediction sequence"
	)
	var sampled_walk_interval := (
		PlayerGait.get_stride_distance_for_motion(
			ServerPlayer.WALK_SPEED,
			false,
			23,
			gait.step_sequence
		) / ServerPlayer.WALK_SPEED
	)
	var sampled_run_interval := (
		PlayerGait.get_stride_distance_for_motion(
			ServerPlayer.RUN_SPEED,
			true,
			23,
			gait.step_sequence
		) / ServerPlayer.RUN_SPEED
	)
	_expect(
		sampled_walk_interval > 0.20
		and sampled_walk_interval < 0.34
		and sampled_run_interval > 0.16
		and sampled_run_interval < sampled_walk_interval,
		"sprint increases cadence continuously while preserving readable foot contacts"
	)
	_expect(
		is_equal_approx(
			PlayerGait.get_stride_distance_for_motion(
				10.0,
				false,
				23,
				gait.step_sequence
			),
			PlayerGait.get_stride_distance_for_motion(
				10.0,
				true,
				23,
				gait.step_sequence
			)
		),
		"actual ground speed—not the sprint button—owns step length during carried momentum"
	)
	_expect(
		PlayerGait.get_step_stance_scale_for_motion(
			ServerPlayer.RUN_SPEED,
			23,
			gait.step_sequence
		) > PlayerGait.get_step_stance_scale_for_motion(
			ServerPlayer.WALK_SPEED,
			23,
			gait.step_sequence
		)
		and PlayerGait.get_step_arc_height_for_motion(
			ServerPlayer.RUN_SPEED,
			23,
			gait.step_sequence
		) > PlayerGait.get_step_arc_height_for_motion(
			ServerPlayer.WALK_SPEED,
			23,
			gait.step_sequence
		)
		and PlayerGait.get_footstep_volume_db_for_motion(
			ServerPlayer.RUN_SPEED,
			23,
			gait.step_sequence
		) > PlayerGait.get_footstep_volume_db_for_motion(
			ServerPlayer.WALK_SPEED,
			23,
			gait.step_sequence
		),
		"speed widens and lifts the stride while giving faster foot impacts slightly more weight"
	)
	var run_impact := PlayerGait.calculate_run_bob_offset(2.0, 0.04, 0.026)
	var run_flight := PlayerGait.calculate_run_bob_offset(2.5, 0.04, 0.026)
	var run_before_boundary := PlayerGait.calculate_run_bob_offset(
		2.9999,
		0.04,
		0.026
	)
	var run_after_boundary := PlayerGait.calculate_run_bob_offset(
		3.0,
		0.04,
		0.026
	)
	_expect(
		run_impact.y < 0.0
		and run_flight.y > 0.0
		and absf(run_impact.y) < 0.03
		and run_flight.y < 0.02,
		"sprint uses restrained landing compression and flight instead of a faster walk pogo"
	)
	_expect(
		run_before_boundary.distance_to(run_after_boundary) < 0.001,
		"sprint compression and lateral transfer remain continuous at each footfall"
	)

	var server_player := RecordingServerPlayer.new()
	server_player.body_loadout = FULL_BODY
	server_player.player_id = 7
	server_player.gait.set_expression_identity(7)
	server_player.velocity = Vector3(ServerPlayer.WALK_SPEED, 0.0, 0.0)
	server_player.on_floor = true
	server_player.gait.distance_since_step = (
		server_player.gait.stride_distance
		- ServerPlayer.WALK_SPEED * STEP * 0.5
	)
	server_player.call("_update_footsteps", STEP)
	var server_cycle := server_player.gait.get_cycle()
	var server_impact := PlayerGait.calculate_bob_offset(
		server_cycle,
		0.04,
		0.02
	)
	var contact_sequence := server_player.gait.step_sequence
	var contact_key := LocalAudioPrediction.gait_step_key(contact_sequence)
	var accepted_contact := server_player.accept_presented_foot_contact(
		contact_sequence,
		PlayerProceduralLegRig.Side.RIGHT,
		contact_key
	)
	_expect(
		accepted_contact
		and server_player.emitted_sound_ids == [&"footstep_concrete"]
		and server_player.emitted_sound_positions[0].y < -0.9
		and server_player.emitted_sound_volume_db[0] < 0.0
		and server_impact.y < -0.039,
		"a validated planted foot emits from its contact point with the shared impact sequence"
	)
	server_player.free()


func _test_authoritative_jump_arc() -> void:
	var player := RecordingServerPlayer.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	player.add_child(collision)
	var grabber := GrabberComponent.new()
	grabber.name = "Grabber"
	grabber.capability = GrabCapability.new()
	player.add_child(grabber)
	player.body_loadout = FULL_BODY
	root.add_child(player)

	var carried_velocity := Vector3(12.0, 0.0, -3.5)
	player.velocity = carried_velocity
	player.on_floor = true
	player.request_jump()
	player.server_physics_tick(STEP)
	_expect(
		is_equal_approx(player.velocity.x, carried_velocity.x)
		and is_equal_approx(player.velocity.z, carried_velocity.z)
		and is_equal_approx(player.velocity.y, ServerPlayer.JUMP_VELOCITY)
		and player.jump_sequence == 1,
		"the authoritative takeoff tick carries existing horizontal momentum"
	)
	_expect(
		player.emitted_sound_ids == [&"jump_concrete"],
		"momentum-preserving takeoff still emits exactly one jump cue"
	)
	var public_state := player.to_state_dict()
	_expect(
		public_state.has("gait_cycle")
		and public_state.has("gait_stride_distance")
		and public_state.has("gait_active")
		and public_state.has("gait_momentum_recovery")
		and int(public_state.get("jump_sequence", -1)) == 1
		and int(public_state.get("flip_sequence", -1)) == 0
		and int(public_state.get("landing_sequence", -1)) == 0
		and is_zero_approx(
			float(public_state.get("landing_impact_strength", -1.0))
		)
		and is_equal_approx(float(public_state.get("stamina_ratio", -1.0)), 1.0),
		"authoritative movement snapshots replicate gait, jump/landing expression, and END ratio"
	)

	var launch_horizontal := Vector2(player.velocity.x, player.velocity.z)
	player.server_physics_tick(STEP)
	_expect(
		Vector2(player.velocity.x, player.velocity.z).is_equal_approx(
			launch_horizontal
		)
		and is_equal_approx(
			player.velocity.y,
			ServerPlayer.JUMP_VELOCITY - ServerPlayer.GRAVITY * STEP
		),
		"airborne simulation uses a stable ballistic arc without erasing momentum"
	)
	player.free()


func _test_contextual_kick_authority() -> void:
	_expect(
		ServerPlayer.select_kick_side(-1, false, false, 0) == -1
		and ServerPlayer.select_kick_side(-1, true, false, 0)
		== PlayerGait.FootSide.LEFT
		and ServerPlayer.select_kick_side(-1, false, true, 0)
		== PlayerGait.FootSide.RIGHT
		and ServerPlayer.select_kick_side(
			PlayerGait.FootSide.RIGHT,
			true,
			true,
			0
		) == PlayerGait.FootSide.RIGHT,
		"kick authority honors the live presented foot when available and never invents a missing limb"
	)
	var free_direction := Vector3.FORWARD
	var guide_direction := Vector3(0.0, 0.55, -0.84).normalized()
	var guided_direction := ServerPlayer.apply_kick_guidance(
		free_direction,
		guide_direction,
		ServerPlayer.KICK_GUIDANCE_MAX_WEIGHT
	)
	_expect(
		guided_direction.y > 0.08
		and guided_direction.dot(guide_direction) < 0.999
		and guided_direction.dot(free_direction) > 0.90,
		"situational kick spots bend a free strike toward useful height without hard-locking the foot onto the target"
	)
	var standing_impulse := ServerPlayer.kick_impulse_from_momentum(
		0.0,
		0.0,
		false
	)
	var running_impulse := ServerPlayer.kick_impulse_from_momentum(
		ServerPlayer.RUN_SPEED,
		ServerPlayer.RUN_SPEED,
		false
	)
	var flip_impulse := ServerPlayer.kick_impulse_from_momentum(
		ServerPlayer.WALK_SPEED,
		ServerPlayer.WALK_SPEED,
		true
	)
	var walking_impulse := ServerPlayer.kick_impulse_from_momentum(
		ServerPlayer.WALK_SPEED,
		ServerPlayer.WALK_SPEED,
		false
	)
	_expect(
		standing_impulse >= ServerPlayer.KICK_BASE_IMPULSE
		and running_impulse > standing_impulse * 1.8
		and flip_impulse > walking_impulse
		and running_impulse <= ServerPlayer.KICK_MAX_IMPULSE,
		"kick authority converts forward body momentum and airborne rotation into bounded physical impact"
	)
	var player := _make_physics_player(Vector3(80.0, 1.0, 0.0))
	await physics_frame
	player.look_yaw = 0.0
	player.look_pitch = 0.0
	var first_accepted := player.request_kick(PlayerGait.FootSide.RIGHT)
	var first_state := player.to_state_dict()
	var cooldown_rejected := not player.request_kick(PlayerGait.FootSide.LEFT)
	_expect(
		first_accepted
		and cooldown_rejected
		and player.kick_side == PlayerGait.FootSide.RIGHT
		and player.kick_cooldown_remaining
		== ServerPlayer.KICK_COOLDOWN_SECONDS
		and int(first_state.get("kick_sequence", 0)) == 1
		and int(first_state.get("kick_side", -1))
		== PlayerGait.FootSide.RIGHT
		and bool(first_state.get("kick_active", false)),
		"one authoritative E fallback starts the selected foot and enforces the 0.75-second cooldown"
	)
	player.kick_cooldown_remaining = 0.0
	player.flip_active = true
	player.flip_direction = -1
	player.flip_phase = 0.25
	var flip_kick_accepted := player.request_kick(PlayerGait.FootSide.LEFT)
	_expect(
		flip_kick_accepted
		and player.kick_direction.distance_to(Vector3.FORWARD) > 0.5
		and player.kick_direction.is_normalized(),
		"a kick remains valid during a flip and follows the body's current first-person rotation"
	)
	player.kick_cooldown_remaining = 0.0
	player.flip_active = false
	player.primary_action_held = true
	var weapon_action_won := not player.request_kick(PlayerGait.FootSide.RIGHT)
	player.primary_action_held = false
	player.wrist_interface_open = true
	var device_action_won := not player.request_kick(PlayerGait.FootSide.RIGHT)
	_expect(
		weapon_action_won and device_action_won,
		"kick is the lowest action layer and cannot interrupt an active weapon or technical interface"
	)
	player.wrist_interface_open = false
	player.kick_active = false
	player.kick_cooldown_remaining = 0.0
	var elevated_target := RigidBody3D.new()
	elevated_target.gravity_scale = 0.0
	var elevated_collision := CollisionShape3D.new()
	var elevated_shape := SphereShape3D.new()
	elevated_shape.radius = 0.24
	elevated_collision.shape = elevated_shape
	elevated_target.add_child(elevated_collision)
	root.add_child(elevated_target)
	elevated_target.global_position = Vector3(80.0, 1.35, -0.82)
	await physics_frame
	var guided_kick_accepted := player.request_kick(PlayerGait.FootSide.RIGHT)
	_expect(
		guided_kick_accepted
		and player.kick_guidance_weight > 0.0
		and player.kick_direction.y > 0.04
		and player.kick_direction.dot(player.kick_guidance_direction) < 0.999,
		"one small action-time query discovers a nearby kickable body and commits only a soft height correction"
	)
	elevated_target.free()
	player.free()

	var physical_player := _make_physics_player(Vector3(90.0, 1.0, 0.0))
	physical_player.look_yaw = 0.0
	physical_player.look_pitch = 0.0
	var target := RigidBody3D.new()
	target.gravity_scale = 0.0
	var target_collision := CollisionShape3D.new()
	var target_shape := SphereShape3D.new()
	target_shape.radius = 0.20
	target_collision.shape = target_shape
	target.add_child(target_collision)
	root.add_child(target)
	target.global_position = Vector3(90.0, 0.83, -0.88)
	await physics_frame
	physical_player.request_kick(PlayerGait.FootSide.RIGHT)
	physical_player.call(
		"_advance_kick_state",
		ServerPlayer.KICK_DURATION_SECONDS * 0.52
	)
	await physics_frame
	_expect(
		target.linear_velocity.z < -0.5,
		"the server resolves one physical contact at the kick strike instead of leaving it as a cosmetic leg animation"
	)
	physical_player.free()
	target.free()


func _test_dropkick_authority() -> void:
	_expect(
		ServerPlayer.running_kick_balance_failure_probability(
			ServerPlayer.WALK_SPEED,
			ServerPlayer.WALK_SPEED,
			true
		) == 0.0
		and ServerPlayer.running_kick_balance_failure_probability(
			ServerPlayer.RUN_SPEED,
			ServerPlayer.RUN_SPEED,
			true
		) > 0.25,
		"ordinary kick balance loss is impossible at walking pace and rises nonlinearly with real running momentum"
	)
	_expect(
		not ServerPlayer.should_trip_from_dropkick_landing(true, 3.1)
		and ServerPlayer.should_trip_from_dropkick_landing(true, 3.3)
		and not ServerPlayer.should_trip_from_dropkick_landing(false, 20.0),
		"dropkick recovery becomes a ragdoll only after a visible landing carries sufficient impact"
	)
	var wall_recoil := ServerPlayer.dropkick_recoil_velocity(
		Vector3(2.0, -1.0, -ServerPlayer.RUN_SPEED),
		Vector3.BACK,
		Vector3.ZERO,
		Vector3.FORWARD,
		ServerPlayer.DROP_KICK_MAX_IMPULSE
	)
	_expect(
		wall_recoil.z > ServerPlayer.DROP_KICK_MIN_REBOUND_SPEED
		and wall_recoil.x > 0.5
		and wall_recoil.x < 2.0,
		"dropkick contact reverses the closing component while retaining a bounded amount of tangential momentum"
	)
	var release_player := _make_physics_player(Vector3(110.0, 2.0, 0.0))
	await physics_frame
	release_player.on_floor = false
	release_player.air_time = 0.12
	release_player.wants_run = true
	release_player.velocity = Vector3(0.0, 3.0, -ServerPlayer.RUN_SPEED)
	release_player.set_context_action_held(true)
	var dropkick_accepted := release_player.request_kick(
		PlayerGait.FootSide.LEFT,
		-0.75
	)
	var dropkick_state := release_player.to_state_dict()
	_expect(
		dropkick_accepted
		and release_player.kick_style == ServerPlayer.KickStyle.DROP
		and int(dropkick_state.get("kick_style", -1))
		== ServerPlayer.KickStyle.DROP
		and is_equal_approx(
			float(dropkick_state.get("dropkick_tilt_input", 0.0)),
			-0.75
		)
		and release_player.kick_active,
		"held E during a sprint-speed ordinary jump starts one replicated two-foot dropkick with its committed lateral camera curve"
	)
	release_player.set_context_action_held(false)
	release_player.call("_advance_kick_state", STEP)
	_expect(
		not release_player.kick_active and not release_player.ragdoll_active,
		"releasing E before contact withdraws the dropkick without inventing an impact ragdoll"
	)
	release_player.free()

	var impact_player := _make_physics_player(Vector3(120.0, 2.0, 0.0))
	var target := RigidBody3D.new()
	target.gravity_scale = 0.0
	var target_collision := CollisionShape3D.new()
	var target_shape := SphereShape3D.new()
	target_shape.radius = 0.28
	target_collision.shape = target_shape
	target.add_child(target_collision)
	root.add_child(target)
	target.global_position = Vector3(120.0, 1.83, -0.78)
	await physics_frame
	impact_player.on_floor = false
	impact_player.gait.step_sequence = 12
	impact_player.gait.active = true
	impact_player.last_foot_contact_sequence = 13
	impact_player.air_time = 0.12
	impact_player.wants_run = true
	impact_player.velocity = Vector3(0.0, 2.5, -ServerPlayer.RUN_SPEED)
	impact_player.set_context_action_held(true)
	impact_player.request_kick(PlayerGait.FootSide.RIGHT)
	impact_player.call(
		"_advance_kick_state",
		ServerPlayer.DROP_KICK_POSE_BUILD_SECONDS * 0.78
	)
	await physics_frame
	_expect(
		impact_player.ragdoll_active
		and target.linear_velocity.z < -1.0
		and impact_player.velocity.z > 0.75,
		"an extended dropkick transfers momentum at its visible feet, pushes the kicker back, and only then enters authoritative ragdoll"
	)
	_expect(
		not impact_player.gait.active
		and impact_player.gait.step_sequence > impact_player.last_foot_contact_sequence,
		"dropkick ragdoll re-arms the shared foot-contact clock beyond every pre-impact step"
	)
	var audio_player := RecordingServerPlayer.new()
	var audio_collision := CollisionShape3D.new()
	audio_collision.name = "CollisionShape3D"
	var audio_shape := BoxShape3D.new()
	audio_shape.size = Vector3(1.0, ServerPlayer.STANDING_COLLISION_HEIGHT, 1.0)
	audio_collision.shape = audio_shape
	audio_player.add_child(audio_collision)
	var audio_grabber := GrabberComponent.new()
	audio_grabber.name = "Grabber"
	audio_grabber.capability = GrabCapability.new()
	audio_player.add_child(audio_grabber)
	audio_player.body_loadout = FULL_BODY
	root.add_child(audio_player)
	audio_player.gait.step_sequence = 30
	audio_player.gait.active = true
	audio_player.last_foot_contact_sequence = 31
	audio_player.on_floor = true
	audio_player.call("_begin_trip", Vector3.ZERO)
	audio_player.ragdoll_active = false
	if audio_player.authoritative_ragdoll_anchor != null:
		audio_player.authoritative_ragdoll_anchor.deactivate()
	audio_player.on_floor = true
	var first_stride_seconds := (
		audio_player.gait.stride_distance * 0.51 / ServerPlayer.WALK_SPEED
	)
	audio_player.gait.advance(
		ServerPlayer.WALK_SPEED,
		true,
		false,
		first_stride_seconds
	)
	var resumed_sequence := audio_player.gait.step_sequence
	var resumed := audio_player.accept_presented_foot_contact(
		resumed_sequence,
		PlayerGait.FootSide.LEFT,
		LocalAudioPrediction.gait_step_key(resumed_sequence)
	)
	_expect(
		resumed
		and audio_player.emitted_sound_ids.size() == 1
		and resumed_sequence > 31,
		"the first post-ragdoll planted foot is audible instead of waiting for an old sequence to expire"
	)
	audio_player.free()
	impact_player.free()
	target.free()


func _test_momentum_gated_flip_jump() -> void:
	_expect(
		ServerPlayer.validated_flip_direction(
			1,
			ServerPlayer.RUN_SPEED,
			false,
			true
		) == 1
		and ServerPlayer.validated_flip_direction(
			-1,
			ServerPlayer.RUN_SPEED,
			false,
			true
		) == -1
		and ServerPlayer.validated_flip_direction(
			1,
			ServerPlayer.WALK_SPEED,
			false,
			true
		) == 0
		and ServerPlayer.validated_flip_direction(
			1,
			ServerPlayer.RUN_SPEED,
			true,
			true
		) == 0
		and ServerPlayer.validated_flip_direction(
			1,
			ServerPlayer.RUN_SPEED,
			false,
			false
		) == 0,
		"signed camera-flick intent requires sprint commitment, authoritative momentum, and a closed Fieldlink"
	)
	var flip_player := _make_physics_player(Vector3(40.0, 4.0, 0.0))
	flip_player.player_id = 141
	flip_player.on_floor = true
	flip_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	flip_player.move_input = Vector2(0.0, -1.0)
	flip_player.wants_run = true
	var jump_results: Array[Dictionary] = []
	flip_player.jump_request_resolved.connect(
		func(request_id: int, accepted: bool, direction: int) -> void:
			jump_results.append({
				"request_id": request_id,
				"accepted": accepted,
				"direction": direction,
			})
	)
	flip_player.request_jump(0, 1, 71, true)
	flip_player.server_physics_tick(STEP)
	var takeoff_state := flip_player.to_state_dict(false)
	var expected_flip_horizontal_speed := (
		ServerPlayer.RUN_SPEED
		* ServerPlayer.backflip_horizontal_takeoff_multiplier(
			ServerPlayer.JUMP_VELOCITY
		)
	)
	var expected_flip_vertical_speed := (
		ServerPlayer.JUMP_VELOCITY
		* ServerPlayer.BACK_FLIP_TAKEOFF_VERTICAL_MULTIPLIER
	)
	_expect(
		flip_player.flip_sequence == 1
		and flip_player.flip_direction == 1
		and flip_player.flip_active
		and is_zero_approx(flip_player.flip_phase)
		and is_equal_approx(
			flip_player.velocity.y,
			expected_flip_vertical_speed
		)
		and is_equal_approx(
			Vector2(
				flip_player.velocity.x,
				flip_player.velocity.z
			).length(),
			expected_flip_horizontal_speed
		)
		and int(takeoff_state.get("flip_direction", 0)) == 1
		and jump_results == [{
			"request_id": 71,
			"accepted": true,
			"direction": 1,
		}],
		"a sprint-committed flick starts one replicated traversal backflip and resolves its prediction explicitly"
	)
	var normal_apex := (
		ServerPlayer.JUMP_VELOCITY * ServerPlayer.JUMP_VELOCITY
		/ (2.0 * ServerPlayer.GRAVITY)
	)
	var back_flip_apex := (
		expected_flip_vertical_speed * expected_flip_vertical_speed
		/ (2.0 * ServerPlayer.GRAVITY)
	)
	var front_flip_launch := ServerPlayer.calculate_flip_takeoff_velocity(
		Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0),
		ServerPlayer.JUMP_VELOCITY,
		-1
	)
	var front_flip_apex := (
		front_flip_launch.y * front_flip_launch.y
		/ (2.0 * ServerPlayer.GRAVITY)
	)
	var normal_range := (
		ServerPlayer.RUN_SPEED
		* 2.0 * ServerPlayer.JUMP_VELOCITY
		/ ServerPlayer.GRAVITY
	)
	var front_flip_range := _estimate_flip_equal_height_range(
		ServerPlayer.RUN_SPEED,
		-1
	)
	var back_flip_range := _estimate_flip_equal_height_range(
		ServerPlayer.RUN_SPEED,
		1
	)
	_expect(
		front_flip_range / normal_range > 1.13
		and front_flip_range / normal_range < 1.16
		and back_flip_apex / normal_apex > 1.19
		and back_flip_apex / normal_apex < 1.23
		and back_flip_range / normal_range > 0.69
		and back_flip_range / normal_range < 0.71
		and front_flip_range > back_flip_range
		and back_flip_apex > front_flip_apex,
		"frontflips gain unmistakable range while backflips exchange forward momentum for height"
	)
	var maximum_backflip_air_speed := 0.0
	for _flip_frame: int in range(44):
		flip_player.server_physics_tick(STEP)
		maximum_backflip_air_speed = maxf(
			maximum_backflip_air_speed,
			Vector2(
				flip_player.velocity.x,
				flip_player.velocity.z
			).length()
		)
	_expect(
		not flip_player.flip_active
		and is_equal_approx(flip_player.flip_phase, 1.0)
		and maximum_backflip_air_speed <= expected_flip_horizontal_speed + 0.001,
		"the authoritative backflip completes one bounded rotation without rebuilding its traded-away sprint speed"
	)
	flip_player.on_floor = true
	flip_player.velocity.y = 0.0
	flip_player.request_jump(0, 0, 74, false)
	flip_player.server_physics_tick(STEP)
	_expect(
		flip_player.jump_sequence == 2
		and flip_player.flip_sequence == 1
		and flip_player.flip_direction == 1
		and is_equal_approx(flip_player.flip_phase, 1.0)
		and jump_results.back() == {
			"request_id": 74,
			"accepted": true,
			"direction": 0,
		},
		"an ordinary jump preserves completed flip history instead of rewinding its normalized phase"
	)

	var slow_player := _make_physics_player(Vector3(44.0, 4.0, 0.0))
	slow_player.player_id = 142
	slow_player.on_floor = true
	slow_player.velocity = Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED)
	slow_player.request_jump(0, -1)
	slow_player.server_physics_tick(STEP)
	_expect(
		slow_player.jump_sequence == 1
		and slow_player.flip_sequence == 0
		and slow_player.flip_direction == 0,
		"the same camera motion remains an ordinary jump at walking or standing momentum"
	)
	var residual_player := _make_physics_player(Vector3(46.0, 4.0, 0.0))
	residual_player.player_id = 144
	residual_player.on_floor = true
	residual_player.velocity = Vector3(
		0.0,
		0.0,
		-ServerPlayer.RUN_SPEED
	)
	residual_player.wants_run = false
	residual_player.request_jump(0, 1, 72, false)
	residual_player.server_physics_tick(STEP)
	_expect(
		residual_player.jump_sequence == 1
		and residual_player.flip_sequence == 0
		and residual_player.flip_direction == 0,
		"sprint-speed residual momentum without active run commitment remains an ordinary jump"
	)
	var fieldlink_player := _make_physics_player(Vector3(48.0, 4.0, 0.0))
	fieldlink_player.player_id = 143
	fieldlink_player.on_floor = true
	fieldlink_player.velocity = Vector3(
		0.0,
		0.0,
		-ServerPlayer.RUN_SPEED
	)
	fieldlink_player.wrist_interface_open = true
	fieldlink_player.request_jump(0, 1, 73, true)
	fieldlink_player.server_physics_tick(STEP)
	_expect(
		fieldlink_player.jump_sequence == 1
		and fieldlink_player.flip_sequence == 0
		and fieldlink_player.flip_direction == 0
		and fieldlink_player.wrist_interface_open,
		"an open Fieldlink preserves ordinary jumping but authoritatively forbids flips"
	)

	var redirected := Vector3(0.0, 0.0, -ServerPlayer.RUN_SPEED)
	for _redirect_frame: int in range(40):
		redirected = ServerPlayer.calculate_flip_horizontal_velocity(
			redirected,
			Vector3.BACK,
			STEP
		)
	_expect(
		redirected.z > 0.0
		and redirected.length() < ServerPlayer.RUN_SPEED,
		"opposing flip input can carve through old velocity while the maneuver still bleeds momentum"
	)
	slow_player.free()
	residual_player.free()
	fieldlink_player.free()
	flip_player.free()


func _test_impact_scaled_landing_and_hard_trip() -> void:
	var short_drop_speed := sqrt(2.0 * ServerPlayer.GRAVITY * 1.0)
	var tall_drop_speed := sqrt(2.0 * ServerPlayer.GRAVITY * 6.0)
	var short_response := ServerPlayer.landing_response_strength(short_drop_speed)
	var tall_response := ServerPlayer.landing_response_strength(tall_drop_speed)
	_expect(
		short_response > 0.0
		and tall_response > short_response * 2.0
		and not ServerPlayer.should_trip_from_landing_impact(tall_drop_speed)
		and ServerPlayer.should_trip_from_landing_impact(
			ServerPlayer.HARD_LANDING_TRIP_SPEED
		),
		"landing load grows nonlinearly with fall height and crosses one explicit hard-impact trip threshold"
	)
	var floor_body := _add_static_box(
		"HardLandingFloor",
		Vector3(8.0, 0.2, 8.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var player := _make_physics_player(
		Vector3(
			0.0,
			ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5 + 0.01,
			0.0
		)
	)
	await physics_frame
	player.on_floor = false
	player.air_time = ServerPlayer.LANDING_MIN_AIR_TIME + STEP
	player.velocity = Vector3(
		0.0,
		-ServerPlayer.HARD_LANDING_TRIP_SPEED,
		0.0
	)
	player.server_physics_tick(STEP)
	var state := player.to_state_dict()
	_expect(
		player.ragdoll_active
		and player.landing_sequence == 1
		and player.landing_impact_strength > 0.99
		and int(state.get("landing_sequence", 0)) == 1
		and float(state.get("landing_impact_strength", 0.0)) > 0.99,
		"an authoritative over-limit floor impact replicates its load and enters ragdoll immediately"
	)
	player.free()
	floor_body.free()


func _test_authoritative_split_support_trip() -> void:
	var wide_floor := _add_static_box(
		"TripWideFloor",
		Vector3(4.0, 0.2, 4.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var player := _make_physics_player(
		Vector3(0.0, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, 0.0)
	)
	await physics_frame
	_expect(
		not bool(player.call("_landing_lacks_required_support")),
		"a biped landing on a broad surface finds independent support under both feet"
	)
	wide_floor.free()
	var single_foot_perch := _add_static_box(
		"TripSingleFootPerch",
		Vector3(0.18, 0.2, 1.2),
		Vector3(-ServerPlayer.TRIP_SUPPORT_LATERAL_OFFSET, -0.1, 0.0)
	)
	await physics_frame
	_expect(
		bool(player.call("_landing_lacks_required_support")),
		"a biped landing with empty space beneath its second foot reports lost support"
	)
	player.global_position.y = (
		ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5 + 0.01
	)
	player.on_floor = false
	player.air_time = ServerPlayer.TRIP_MIN_AIR_TIME + 0.01
	player.velocity = Vector3(1.0, -1.0, 0.0)
	player.server_physics_tick(STEP)
	var trip_state := player.to_state_dict()
	_expect(
		player.ragdoll_active
		and player.trip_sequence == 1
		and bool(trip_state.get("ragdoll_active", false))
		and int(trip_state.get("trip_sequence", 0)) == 1
		and (trip_state.get("trip_direction", Vector3.ZERO) as Vector3).length() > 0.9,
		"support loss starts and replicates one trip even below the loud-landing audio threshold"
	)
	player.call("_update_trip_state", ServerPlayer.TRIP_RECOVERY_SECONDS + STEP)
	player.on_floor = true
	player.velocity = Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED)
	player.gait.distance_since_step = (
		PlayerGait.get_stride_distance_for_motion(
			ServerPlayer.WALK_SPEED,
			false,
			player.player_id,
			player.gait.step_sequence
		) - ServerPlayer.WALK_SPEED * STEP * 0.5
	)
	player.call("_update_footsteps", STEP)
	_expect(
		player.ragdoll_active and player.trip_sequence == 2,
		"a real gait footfall also trips when its second support ray finds empty space"
	)

	var one_leg_loadout := FULL_BODY.duplicate(true) as CharacterLoadout
	one_leg_loadout.right_leg = null
	player.set_body_loadout(one_leg_loadout)
	_expect(
		not bool(player.call("_landing_lacks_required_support")),
		"a one-legged loadout never fails a check for a nonexistent second foot"
	)
	player.call("_update_trip_state", ServerPlayer.TRIP_RECOVERY_SECONDS + STEP)
	_expect(
		not player.ragdoll_active,
		"the authoritative trip state recovers after its bounded incapacitation window"
	)
	player.free()
	single_foot_perch.free()


func _test_authoritative_step_traversal() -> void:
	var floor_body := _add_static_box(
		"StepTestFloor",
		Vector3(12.0, 0.2, 5.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var curb_body := _add_static_box(
		"FiveCentimeterCurb",
		Vector3(4.0, 0.05, 1.5),
		Vector3(2.0, 0.025, -1.25)
	)
	var wall_body := _add_static_box(
		"UnclimbableWall",
		Vector3(1.0, 1.0, 1.5),
		Vector3(0.5, 0.5, 1.25)
	)
	var curb_player := _make_physics_player(
		Vector3(-1.1, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, -1.25)
	)
	var wall_player := _make_physics_player(
		Vector3(-1.1, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, 1.25)
	)
	await physics_frame
	curb_player.on_floor = true
	wall_player.on_floor = true
	for _tick: int in range(36):
		curb_player.set_input(Vector2.RIGHT, 0.0, 0.0, false)
		wall_player.set_input(Vector2.RIGHT, 0.0, 0.0, false)
		curb_player.server_physics_tick(STEP)
		wall_player.server_physics_tick(STEP)
	_expect(
		curb_player.global_position.x > 0.6
		and absf(
			curb_player.global_position.y
			- (ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5 + 0.05)
		) < 0.015,
		"grounded movement crosses a five-centimeter curb without losing forward travel"
	)
	_expect(
		wall_player.global_position.x < -0.45
		and absf(
			wall_player.global_position.y
			- ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5
		) < 0.015,
		"the same solver cannot convert a full-height wall into a climbable step"
	)
	curb_player.free()
	wall_player.free()
	floor_body.free()
	curb_body.free()
	wall_body.free()


func _test_authoritative_ragdoll_relocation() -> void:
	var floor_body := _add_static_box(
		"RagdollRelocationFloor",
		Vector3(20.0, 0.2, 20.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var player := _make_physics_player(
		Vector3(0.0, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, 0.0)
	)
	player.player_id = 9
	player.velocity = Vector3(4.0, 0.0, 0.0)
	var trip_origin := player.global_position
	player.call("_begin_trip")
	var anchor := player.authoritative_ragdoll_anchor as PlayerRagdollAnchor3D
	var authoritative_trip_direction := player.trip_direction
	await physics_frame
	var expected_fall_axis := Vector3(
		authoritative_trip_direction.z,
		0.15,
		-authoritative_trip_direction.x
	).normalized()
	_expect(
		anchor.mass > 60.0
		and anchor.linear_velocity.dot(authoritative_trip_direction)
		> Vector3(4.0, 0.0, 0.0).dot(authoritative_trip_direction) + 0.1
		and anchor.angular_velocity.dot(expected_fall_axis) > 0.02,
		"the server ragdoll carries whole-body mass and reliably applies its retained forward-fall impulse on the first valid physics tick"
	)
	for _frame: int in range(35):
		await physics_frame
		player.server_physics_tick(STEP)
	var fallen_position := player.global_position
	_expect(
		player.ragdoll_active
		and player.authoritative_ragdoll_anchor != null
		and fallen_position.distance_to(trip_origin) > 0.5,
		"the authoritative player follows its physical ragdoll instead of leaving a parked capsule"
	)
	player.call("_update_trip_state", ServerPlayer.TRIP_RECOVERY_SECONDS)
	_expect(
		not player.ragdoll_active
		and player.global_position.distance_to(trip_origin) > 0.5
		and player.global_position.distance_to(fallen_position) < 1.5,
		"ragdoll recovery stands up near the final physical body instead of snapping to the trip origin"
	)
	player.free()

	var low_ceiling := _add_static_box(
		"RagdollRecoveryLowCeiling",
		Vector3(3.0, 0.2, 3.0),
		Vector3(5.0, 1.35, 0.0)
	)
	var cramped_player := _make_physics_player(
		Vector3(5.0, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, 0.0)
	)
	await physics_frame
	cramped_player.call("_begin_trip")
	cramped_player.call("_update_trip_state", ServerPlayer.TRIP_RECOVERY_SECONDS + STEP)
	_expect(
		cramped_player.ragdoll_active,
		"recovery waits in ragdoll when no clear standing capsule fits beneath nearby geometry"
	)
	low_ceiling.free()
	for _retry_tick: int in range(8):
		cramped_player.call("_update_trip_state", STEP)
	_expect(
		not cramped_player.ragdoll_active,
		"recovery retries and stands once the authoritative volume is clear"
	)
	cramped_player.free()
	floor_body.free()


func _test_death_respawn_and_corpse_detach() -> void:
	var floor_body := _add_static_box(
		"DeathRespawnFloor",
		Vector3(12.0, 0.2, 12.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var spawn_position := Vector3(
		0.0,
		ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5,
		0.0
	)
	var player := _make_physics_player(spawn_position)
	player.player_id = 31
	player.gait.step_sequence = 19
	player.last_foot_contact_sequence = 20
	player.velocity = Vector3(3.5, 0.0, -1.0)
	var death_count := [0]
	player.died.connect(func(_dead_player: ServerPlayer) -> void:
		death_count[0] = int(death_count[0]) + 1
	)
	var applied := player.apply_damage(ServerPlayer.MAX_HEALTH * 2.0)
	var original_anchor := (
		player.authoritative_ragdoll_anchor as PlayerRagdollAnchor3D
	)
	await physics_frame
	_expect(
		is_equal_approx(applied, ServerPlayer.MAX_HEALTH)
		and is_zero_approx(player.health)
		and player.death_pending
		and player.ragdoll_active
		and int(death_count[0]) == 1
		and original_anchor.is_active(),
		"lethal damage emits once and enters the ordinary weighted ragdoll before respawn"
	)
	player.apply_damage(10.0)
	_expect(
		int(death_count[0]) == 1,
		"additional damage cannot enqueue duplicate deaths while respawn is pending"
	)
	var corpse_parent := Node3D.new()
	corpse_parent.name = "DeathRespawnCorpseParent"
	root.add_child(corpse_parent)
	var detached := player.detach_ragdoll_anchor_for_corpse(corpse_parent)
	var respawn_position := Vector3(4.0, 2.0, 3.0)
	player.respawn_at(respawn_position)
	await physics_frame
	_expect(
		detached == original_anchor
		and original_anchor.get_parent() == corpse_parent
		and original_anchor.is_active()
		and player.authoritative_ragdoll_anchor != original_anchor
		and not player.authoritative_ragdoll_anchor.is_active(),
		"death transfers the active physical body to an independent corpse and installs a fresh player anchor"
	)
	_expect(
		is_equal_approx(player.health, ServerPlayer.MAX_HEALTH)
		and not player.death_pending
		and not player.ragdoll_active
		and player.global_position.is_equal_approx(respawn_position)
		and player.velocity.is_zero_approx(),
		"respawn restores vitals and movement without deleting the detached corpse"
	)
	_expect(
		player.gait.step_sequence > 20
		and not player.gait.active
		and is_equal_approx(player.gait.get_phase(), 0.5),
		"respawn preserves the monotonic audio clock and starts new feet from balanced mid-stance"
	)
	player.free()
	corpse_parent.free()
	floor_body.free()


func _test_ragdoll_stair_recovery() -> void:
	var floor_body := _add_static_box(
		"RagdollStairFloor",
		Vector3(12.0, 0.2, 12.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var steps: Array[StaticBody3D] = []
	const STEP_DEPTH := 0.42
	const STEP_RISE := 0.18
	for step_index: int in range(7):
		var height := STEP_RISE * float(step_index + 1)
		steps.append(_add_static_box(
			"RagdollStair%02d" % step_index,
			Vector3(2.4, height, STEP_DEPTH),
			Vector3(
				0.0,
				height * 0.5,
				(float(step_index) - 3.0) * STEP_DEPTH
			)
		))
	var starting_step_index := 3
	var starting_surface_y := STEP_RISE * float(starting_step_index + 1)
	var player := _make_physics_player(Vector3(
		0.0,
		starting_surface_y + ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5,
		(float(starting_step_index) - 3.0) * STEP_DEPTH
	))
	player.player_id = 17
	await physics_frame
	player.on_floor = true
	player.velocity = Vector3(0.0, 0.0, 4.5)
	player.call("_begin_trip")
	var anchor := player.authoritative_ragdoll_anchor as PlayerRagdollAnchor3D
	var anchor_collision := anchor.get_node("Collision") as CollisionShape3D
	var recovered := false
	for _frame: int in range(240):
		await physics_frame
		player.server_physics_tick(STEP)
		if not player.ragdoll_active:
			recovered = true
			break
	_expect(
		anchor_collision.shape is CapsuleShape3D
		and anchor.continuous_cd
		and anchor.physics_material_override != null
		and anchor.physics_material_override.friction < 0.25,
		"the authoritative ragdoll uses rounded low-friction continuous collision on modular edges"
	)
	_expect(
		recovered
		and player.global_position.is_finite()
		and bool(player.call("_is_recovery_space_clear", player.global_position)),
		"a torso fallen across narrow boxed stair risers finds nearby clear standing space"
	)
	player.free()
	for step: StaticBody3D in steps:
		step.free()
	floor_body.free()


func _test_ragdoll_penetration_fallback() -> void:
	var floor_body := _add_static_box(
		"RagdollFallbackFloor",
		Vector3(12.0, 0.2, 12.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var blocker := _add_static_box(
		"RagdollFallbackBlocker",
		Vector3(2.8, 2.4, 2.8),
		Vector3(2.0, 1.2, 0.0)
	)
	var safe_position := Vector3(
		0.0,
		ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5,
		0.0
	)
	var player := _make_physics_player(safe_position)
	player.player_id = 18
	await physics_frame
	player.on_floor = true
	player.call("_begin_trip")
	var anchor := player.authoritative_ragdoll_anchor as PlayerRagdollAnchor3D
	anchor.global_position = Vector3(2.0, 0.65, 0.0)
	var recovered := bool(player.call("_recover_from_trip", true))
	_expect(
		recovered
		and not player.ragdoll_active
		and player.global_position.distance_to(safe_position) < 0.1
		and bool(player.call("_is_recovery_space_clear", player.global_position)),
		"unresolved penetration uses the nearby pre-trip standing point instead of remaining ragdolled forever"
	)
	player.free()
	blocker.free()
	floor_body.free()


func _test_authored_entrance_traversal() -> void:
	var outside_floor := _add_static_box(
		"EntranceTestOutsideFloor",
		Vector3(120.0, 0.2, 70.0),
		Vector3(0.0, -0.1, 5.0)
	)
	var complex := INDUSTRIAL_COMPLEX_SCENE.instantiate() as StaticBody3D
	root.add_child(complex)
	var house := ACOUSTIC_HOUSE_SCENE.instantiate() as StaticBody3D
	# Keep this independent entrance fixture clear of the three parallel bunker runs.
	house.position = Vector3(-25.0, 0.0, 0.0)
	root.add_child(house)

	var standing_y := ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5
	var tunnel_player := _make_physics_player(
		Vector3(11.0, standing_y, -13.4)
	)
	var wide_tunnel_player := _make_physics_player(
		Vector3(28.0, standing_y, -13.4)
	)
	var hangar_tunnel_player := _make_physics_player(
		Vector3(47.0, standing_y, -13.4)
	)
	var house_player := _make_physics_player(
		Vector3(-25.0, standing_y, 4.2)
	)
	await physics_frame
	for player: ServerPlayer in [
		tunnel_player,
		wide_tunnel_player,
		hangar_tunnel_player,
		house_player,
	]:
		player.on_floor = true
	for _tick: int in range(42):
		tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		wide_tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		hangar_tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		house_player.set_input(Vector2.UP, 0.0, 0.0, false)
		tunnel_player.server_physics_tick(STEP)
		wide_tunnel_player.server_physics_tick(STEP)
		hangar_tunnel_player.server_physics_tick(STEP)
		house_player.server_physics_tick(STEP)

	var slab_height := standing_y + 0.12
	_expect(
		tunnel_player.global_position.z > -11.5
		and wide_tunnel_player.global_position.z > -11.5
		and hangar_tunnel_player.global_position.z > -11.5
		and absf(tunnel_player.global_position.y - standing_y) < 0.02,
		"all three authored tunnel lips are walkable from the outside world"
	)
	_expect(
		house_player.global_position.z < 2.4
		and absf(house_player.global_position.y - slab_height) < 0.02,
		"the acoustic test house threshold is traversable without jumping"
	)
	tunnel_player.free()
	wide_tunnel_player.free()
	hangar_tunnel_player.free()
	house_player.free()
	house.free()
	complex.free()
	outside_floor.free()


func _make_physics_player(spawn_position: Vector3) -> ServerPlayer:
	var player := ServerPlayer.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, ServerPlayer.STANDING_COLLISION_HEIGHT, 1.0)
	collision.shape = shape
	player.add_child(collision)
	var grabber := GrabberComponent.new()
	grabber.name = "Grabber"
	grabber.position = Vector3(0.0, 0.56, -0.42)
	grabber.capability = GrabCapability.new()
	player.add_child(grabber)
	player.body_loadout = FULL_BODY
	root.add_child(player)
	player.global_position = spawn_position
	return player


func _add_static_box(
	node_name: String,
	size: Vector3,
	box_position: Vector3
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.global_position = box_position
	return body


func _estimate_flip_equal_height_range(
	horizontal_speed: float,
	flip_direction: int
) -> float:
	var launch := ServerPlayer.calculate_flip_takeoff_velocity(
		Vector3(maxf(horizontal_speed, 0.0), 0.0, 0.0),
		ServerPlayer.JUMP_VELOCITY,
		flip_direction
	)
	var flight_seconds := 2.0 * launch.y / ServerPlayer.GRAVITY
	var drag_seconds := minf(
		flight_seconds,
		ServerPlayer.FLIP_DURATION_SECONDS
	)
	var drag := ServerPlayer.FLIP_AIR_MOMENTUM_DRAG
	var decay := exp(-drag * drag_seconds)
	var range_during_flip := (
		launch.x * (1.0 - decay) / drag
		if drag > 0.00001
		else launch.x * drag_seconds
	)
	return (
		range_during_flip
		+ launch.x * decay * maxf(flight_seconds - drag_seconds, 0.0)
	)


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", label)
		return
	failure_count += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print(
		"Player movement tests: ",
		assertion_count - failure_count,
		" passed, ",
		failure_count,
		" failed"
	)
	quit(0 if failure_count == 0 else 1)
