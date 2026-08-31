class_name PlayerCharacterPoseController
extends RefCounted

## Allocation-free layered presentation pose. Ground contacts establish balance, the replicated
## gait clock establishes locomotion phase, and the replicated expression clock establishes slow
## idle motion. Authored action poses are additive filters and never replace procedural balance.

const WALK_CAMERA_VERTICAL := 0.036
const WALK_CAMERA_HORIZONTAL := 0.020
const RUN_CAMERA_VERTICAL := 0.032
const RUN_CAMERA_HORIZONTAL := 0.022
const CAMERA_LOCOMOTION_RESPONSE_HZ := 5.4
const ROOT_POSE_RESPONSE_HZ := 7.2
const BODY_RESPONSE_HZ := 4.8
const HEAD_RESPONSE_HZ := 5.7
const ARM_RESPONSE_HZ := 5.0
const DIRECTIONAL_BALANCE_RESPONSE_HZ := 3.7
const MAX_FRAME_DELTA_SECONDS := 0.1
const IDLE_BREATH_HZ := 0.24
const IDLE_SHIFT_HZ := 0.087
const IDLE_CORRECTION_HZ := 0.61
const TWO_LEG_BODY_SWAY := 0.020
const ONE_LEG_BODY_SWAY := 0.012
const LEGLESS_BODY_SWAY := 0.030
const WALK_ARM_SWING := 0.16
const RUN_ARM_SWING := 0.29
const LEGLESS_ARM_SWING := 0.34
const FORWARD_MOTION_LEAN := 0.060
const LATERAL_MOTION_LEAN := 0.055
const SPRINT_LATERAL_LEAN_LIFT := 0.022
const DIRECTION_CHANGE_PITCH_LAG := 0.030
const DIRECTION_CHANGE_ROLL_LAG := 0.040
const DIRECTION_CHANGE_POSITION_LAG := 0.018
const MOTION_POSITION_SHIFT := 0.010
const BODY_IMPACT_RETURN_RESPONSE_HZ := 3.6
const BODY_IMPACT_MAX_POSITION := 0.085
const BODY_IMPACT_MAX_ROTATION := 0.24
const DROP_KICK_ROOT_RECLINE := 0.76
const DROP_KICK_CAMERA_COUNTER_PITCH := -0.24
const DROP_KICK_ROOT_ROLL := -1.48
const DROP_KICK_ROOT_ROLL_VARIATION := 0.09
const DROP_KICK_ROLL_COMPLETE_PHASE := 0.56
const DROP_KICK_HEAD_ROLL_COMPENSATION := 0.16
const DROP_KICK_CAMERA_ROLL_INHERITANCE := 0.30
const DROP_KICK_CAMERA_EYE_HEIGHT := 0.56
const DROP_KICK_CAMERA_AIM_DISTANCE := 1.25
const DROP_KICK_CAMERA_FORWARD_CLEARANCE := 0.022
const DROP_KICK_CAMERA_CURVE_CENTERING_RETENTION := 0.76
const EPSILON := 0.000001
const CRITICALLY_DAMPED_VECTOR3 := preload(
	"res://scripts/characters/critically_damped_vector3.gd"
)

var body_rotation := Vector3.ZERO
var upper_body_position := Vector3.ZERO
var upper_body_rotation := Vector3.ZERO
var head_position := Vector3.ZERO
var head_rotation := Vector3.ZERO
var left_arm_rotation := Vector3.ZERO
var right_arm_rotation := Vector3.ZERO
var left_forearm_rotation := Vector3.ZERO
var right_forearm_rotation := Vector3.ZERO
var camera_position := Vector3.ZERO
var camera_rotation := Vector3.ZERO

var _body_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _upper_body_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _upper_body_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _head_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _head_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _left_arm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _right_arm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _left_forearm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _right_forearm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _camera_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _camera_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _directional_balance_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _body_impact_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _body_impact_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _identity_phase := Vector3.ZERO
var _identity_amplitude := 1.0
var _expression_identity := 0
var _initialized := false
var _pose: CharacterPoseDefinition
var _pose_weight := 0.0
var _pose_left_arm_enabled := true
var _pose_right_arm_enabled := true
var _attention_head_rotation := Vector3.ZERO
var _attention_weight := 0.0
var _kick_side := -1
var _kick_phase := 1.0
var _kick_intensity := 1.0
var _kick_style := ServerPlayer.KickStyle.SINGLE
var _kick_sequence := 0
var _kick_authority_active := false
var _dropkick_tilt_input := 0.0


func set_expression_identity(identity: int) -> void:
	# Integer hashing keeps the character-specific variation deterministic without sharing RNG state.
	var key := absi(identity) + 1
	_expression_identity = maxi(identity, 0)
	_identity_phase = Vector3(
		ExpressionDeterminism.ratio(key * 1103515245 + 12345) * TAU,
		ExpressionDeterminism.ratio(key * 214013 + 2531011) * TAU,
		ExpressionDeterminism.ratio(key * 1664525 + 1013904223) * TAU
	)
	_identity_amplitude = lerpf(
		0.88,
		1.12,
		ExpressionDeterminism.ratio(key * 22695477 + 1)
	)


func set_action_pose(
	pose: CharacterPoseDefinition,
	weight: float,
	left_arm_enabled := true,
	right_arm_enabled := true
) -> void:
	_pose = pose
	_pose_weight = clampf(weight, 0.0, 1.0)
	_pose_left_arm_enabled = left_arm_enabled
	_pose_right_arm_enabled = right_arm_enabled


func set_attention_pose(head_target_rotation: Vector3, weight: float) -> void:
	_attention_head_rotation = (
		head_target_rotation
		if head_target_rotation.is_finite()
		else Vector3.ZERO
	)
	_attention_weight = clampf(weight, 0.0, 1.0)


func set_low_priority_kick_pose(
	side: int,
	phase: float,
	intensity := 1.0,
	style := ServerPlayer.KickStyle.SINGLE,
	sequence := 0,
	authority_active := false,
	dropkick_tilt_input := 0.0
) -> void:
	# This layer intentionally sits below authored use/device/emote poses. Those actions can suppress
	# its counterbalance without the kick ever overwriting a hand or wrist interaction.
	_kick_side = side if side == 0 or side == 1 else -1
	_kick_phase = clampf(phase, 0.0, 1.0)
	_kick_intensity = clampf(intensity, 1.0, 1.72)
	_kick_style = clampi(
		style,
		ServerPlayer.KickStyle.SINGLE,
		ServerPlayer.KickStyle.DROP
	)
	_kick_sequence = maxi(sequence, 0)
	_kick_authority_active = authority_active
	_dropkick_tilt_input = clampf(dropkick_tilt_input, -1.0, 1.0)


func apply_body_impact(
	local_reaction_direction: Vector3,
	strength: float,
	contact_side: float
) -> void:
	var reaction := Vector3(
		local_reaction_direction.x,
		0.0,
		local_reaction_direction.z
	)
	if not reaction.is_finite() or reaction.length_squared() <= EPSILON:
		return
	reaction = reaction.normalized()
	# Authority supplies a normalized kinetic-load value. A sublinear presentation curve retains a
	# readable shoulder twitch at medium velocity without making full-speed impacts cartoonishly huge.
	var flinch := pow(clampf(strength, 0.0, 1.0), 0.72)
	if flinch <= EPSILON:
		return
	var side := clampf(contact_side, -1.0, 1.0)
	var position_impulse := Vector3(
		reaction.x * 0.052,
		-0.014,
		reaction.z * 0.046
	) * flinch
	var rotation_impulse := Vector3(
		reaction.z * 0.145,
		-reaction.x * 0.090 - side * 0.045,
		-reaction.x * 0.075 - side * 0.135
	) * flinch
	_body_impact_position_spring.value = (
		_body_impact_position_spring.value + position_impulse
	).limit_length(BODY_IMPACT_MAX_POSITION)
	_body_impact_rotation_spring.value = Vector3(
		clampf(
			_body_impact_rotation_spring.value.x + rotation_impulse.x,
			-BODY_IMPACT_MAX_ROTATION,
			BODY_IMPACT_MAX_ROTATION
		),
		clampf(
			_body_impact_rotation_spring.value.y + rotation_impulse.y,
			-BODY_IMPACT_MAX_ROTATION,
			BODY_IMPACT_MAX_ROTATION
		),
		clampf(
			_body_impact_rotation_spring.value.z + rotation_impulse.z,
			-BODY_IMPACT_MAX_ROTATION,
			BODY_IMPACT_MAX_ROTATION
		)
	)


func update(
	delta: float,
	expression_clock: float,
	gait_cycle: float,
	movement_weight: float,
	run_weight: float,
	endurance_spent_ratio: float,
	local_velocity: Vector3,
	grounded: bool,
	ragdoll_active: bool,
	leg_rig: PlayerProceduralLegRig,
	has_left_arm: bool,
	has_right_arm: bool,
	has_left_leg: bool,
	has_right_leg: bool,
	momentum_recovery_weight: float = 0.0
) -> void:
	var safe_delta := clampf(delta, 0.0, MAX_FRAME_DELTA_SECONDS)
	var safe_clock := expression_clock if is_finite(expression_clock) else 0.0
	var safe_cycle := gait_cycle if is_finite(gait_cycle) else 0.0
	var moving := clampf(movement_weight, 0.0, 1.0)
	var sprint := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var momentum_recovery := smoothstep(
		0.0,
		1.0,
		clampf(momentum_recovery_weight, 0.0, 1.0)
	)
	var fatigue := pow(clampf(endurance_spent_ratio, 0.0, 1.0), 1.35)
	var installed_leg_count := int(has_left_leg) + int(has_right_leg)
	if ragdoll_active:
		moving = 0.0
		_body_impact_position_spring.snap(Vector3.ZERO)
		_body_impact_rotation_spring.snap(Vector3.ZERO)
	else:
		_body_impact_position_spring.advance(
			Vector3.ZERO,
			safe_delta,
			BODY_IMPACT_RETURN_RESPONSE_HZ
		)
		_body_impact_rotation_spring.advance(
			Vector3.ZERO,
			safe_delta,
			BODY_IMPACT_RETURN_RESPONSE_HZ
		)

	var breath_phase := safe_clock * TAU * IDLE_BREATH_HZ + _identity_phase.x
	var shift_phase := safe_clock * TAU * IDLE_SHIFT_HZ + _identity_phase.y
	var correction_phase := safe_clock * TAU * IDLE_CORRECTION_HZ + _identity_phase.z
	var idle_scale := (
		(1.0 - moving * 0.58)
		* _identity_amplitude
		* (1.0 + fatigue * 0.32)
	)
	var breath := sin(breath_phase)
	var slow_shift := sin(shift_phase) * (0.72 + 0.28 * sin(shift_phase * 0.47 + 1.1))
	var correction := sin(correction_phase)

	var active_swing_side := -1
	var swing_progress := 0.5
	var balance_position := Vector3.ZERO
	var balance_rotation := Vector3.ZERO
	if leg_rig != null:
		balance_position = leg_rig.get_body_yield_offset()
		balance_rotation = leg_rig.get_body_yield_rotation()
		active_swing_side = leg_rig.get_active_swing_side()
		if active_swing_side >= 0:
			swing_progress = leg_rig.get_swing_progress(active_swing_side)

	var step_index := floori(safe_cycle)
	var gait_phase := safe_cycle - floorf(safe_cycle)
	var planted_sign := 1.0 if posmod(step_index, 2) == 0 else -1.0
	var contact_phase := gait_phase
	if active_swing_side >= 0:
		# Actual foot progress replaces the timer while a foot is in flight. The replicated gait clock
		# remains the fallback for planted/airborne/no-leg movement and late-join continuity.
		contact_phase = clampf(swing_progress, 0.0, 1.0)
		planted_sign = (
			1.0
			if active_swing_side == PlayerProceduralLegRig.Side.LEFT
			else -1.0
		)
	var stride_phase := safe_cycle * PI
	var contact_lift := sin(contact_phase * PI)
	var impact_compression := exp(-pow(minf(contact_phase, 1.0 - contact_phase) / 0.15, 2.0))
	var safe_local_velocity := (
		local_velocity if local_velocity.is_finite() else Vector3.ZERO
	)
	var forward_speed_weight := clampf(
		-safe_local_velocity.z / ServerPlayer.RUN_SPEED,
		-1.0,
		1.0
	)
	var lateral_speed_weight := clampf(
		safe_local_velocity.x / ServerPlayer.RUN_SPEED,
		-1.0,
		1.0
	)
	var directional_target := Vector3(
		lateral_speed_weight,
		0.0,
		-forward_speed_weight
	).limit_length(1.0)
	if not _initialized:
		_directional_balance_spring.snap(directional_target)
	elif ragdoll_active:
		_directional_balance_spring.snap(Vector3.ZERO)
	else:
		_directional_balance_spring.advance(
			directional_target,
			safe_delta,
			DIRECTIONAL_BALANCE_RESPONSE_HZ
		)
	var direction_change := (
		directional_target - _directional_balance_spring.value
	).limit_length(1.0)

	var gait_sway := TWO_LEG_BODY_SWAY
	if installed_leg_count == 1:
		gait_sway = ONE_LEG_BODY_SWAY
	elif installed_leg_count == 0:
		gait_sway = LEGLESS_BODY_SWAY
	var body_locomotion_position := Vector3(
		planted_sign * cos(contact_phase * PI) * gait_sway,
		(contact_lift * 0.007 - impact_compression * 0.008) * moving,
		0.0
	) * moving
	body_locomotion_position += Vector3(
		(
			lateral_speed_weight * MOTION_POSITION_SHIFT
			- direction_change.x * DIRECTION_CHANGE_POSITION_LAG
		),
		0.0,
		(
			-forward_speed_weight * MOTION_POSITION_SHIFT * 0.55
			- direction_change.z * DIRECTION_CHANGE_POSITION_LAG
		)
	)
	body_locomotion_position.y += (
		contact_lift * 0.021
		- impact_compression * 0.014
	) * momentum_recovery
	var body_locomotion_rotation := Vector3(
		(
			-forward_speed_weight * FORWARD_MOTION_LEAN
			- direction_change.z * DIRECTION_CHANGE_PITCH_LAG
		),
		sin(stride_phase) * (0.025 + sprint * 0.045) * moving,
		(
			-planted_sign * contact_lift * (0.018 + sprint * 0.025) * moving
			- lateral_speed_weight
			* (LATERAL_MOTION_LEAN + sprint * SPRINT_LATERAL_LEAN_LIFT)
			+ direction_change.x * DIRECTION_CHANGE_ROLL_LAG
		)
	)
	body_locomotion_rotation.x += (
		sin(contact_phase * TAU) * 0.026 * momentum_recovery
	)
	if not grounded:
		body_locomotion_position *= 0.35
		body_locomotion_rotation *= 0.45

	var idle_position := Vector3(
		slow_shift * 0.0024,
		breath * 0.0028 + correction * 0.00035,
		cos(shift_phase * 0.79 + 0.6) * 0.0014
	) * idle_scale
	var idle_rotation := Vector3(
		breath * 0.0045,
		correction * 0.0032,
		slow_shift * 0.0065
	) * idle_scale
	var target_upper_position := (
		balance_position
		+ body_locomotion_position
		+ idle_position
		+ Vector3(0.0, -0.0035, 0.002) * fatigue
	)
	var target_upper_rotation := balance_rotation + body_locomotion_rotation + idle_rotation
	var target_body_rotation := Vector3.ZERO

	var counter_weight := 0.62
	var target_head_position := Vector3(
		-idle_position.x * 0.30,
		breath * 0.0014,
		0.0
	)
	var target_head_rotation := Vector3(
		-idle_rotation.x * 0.45,
		-body_locomotion_rotation.y * counter_weight,
		-target_upper_rotation.z * 0.36
	)

	var arm_swing_amount := lerpf(WALK_ARM_SWING, RUN_ARM_SWING, sprint) * moving
	if installed_leg_count == 0:
		arm_swing_amount = LEGLESS_ARM_SWING * moving
	var arm_wave := sin(stride_phase - fatigue * 0.22)
	var target_left_arm_rotation := Vector3(
		arm_wave * arm_swing_amount,
		0.0,
		-slow_shift * 0.009 * idle_scale
	)
	var target_right_arm_rotation := Vector3(
		-arm_wave * arm_swing_amount,
		0.0,
		-slow_shift * 0.009 * idle_scale
	)
	var target_left_forearm_rotation := Vector3.ZERO
	var target_right_forearm_rotation := Vector3.ZERO
	if installed_leg_count == 0:
		# Arm-crawling needs a visible push/recovery cycle even though there are no foot contacts.
		target_left_arm_rotation.y = -cos(stride_phase) * arm_swing_amount * 0.24
		target_right_arm_rotation.y = cos(stride_phase) * arm_swing_amount * 0.24
		target_upper_position.z += absf(sin(stride_phase)) * 0.018 * moving

	var walk_camera := Vector3(
		planted_sign * cos(contact_phase * PI) * WALK_CAMERA_HORIZONTAL,
		-cos(contact_phase * TAU) * WALK_CAMERA_VERTICAL,
		0.0
	)
	var run_flight := sin(contact_phase * PI)
	var run_camera := Vector3(
		planted_sign * run_flight * RUN_CAMERA_HORIZONTAL,
		(
			run_flight * 0.38
			- impact_compression * 0.72
		) * RUN_CAMERA_VERTICAL,
		0.0
	)
	var target_camera_position := walk_camera.lerp(run_camera, sprint) * moving
	# Contact-derived load changes the old pure timer curve without giving uneven stairs a camera snap.
	target_camera_position.y += (
		body_locomotion_position.y * 0.32
		+ breath * 0.0012 * idle_scale
	)
	var target_camera_rotation := Vector3(
		-body_locomotion_position.y * 0.13,
		body_locomotion_rotation.y * 0.13,
		-target_upper_rotation.z * 0.16
	)

	if (
		_kick_side >= 0
		and (
			_kick_phase < 1.0
			or (
				_kick_style == ServerPlayer.KickStyle.DROP
				and _kick_authority_active
			)
		)
		and not ragdoll_active
	):
		var kick_side_sign := -1.0 if _kick_side == 0 else 1.0
		if _kick_style == ServerPlayer.KickStyle.DROP:
			var drop_weight := smoothstep(
				0.0,
				1.0,
				clampf(_kick_phase / 0.72, 0.0, 1.0)
			)
			var extension_weight := smoothstep(
				0.0,
				1.0,
				inverse_lerp(0.34, 1.0, _kick_phase)
			)
			var roll_weight := smoothstep(
				0.0,
				1.0,
				clampf(
					_kick_phase / DROP_KICK_ROLL_COMPLETE_PHASE,
					0.0,
					1.0
				)
			)
			var variation_key := (
				(_expression_identity + 1) * 4099
				+ _kick_sequence * 7919
			)
			var roll_variation := lerpf(
				-1.0,
				1.0,
				ExpressionDeterminism.ratio(
					variation_key * 214013 + 2531011
				)
			)
			var arm_variation := lerpf(
				-1.0,
				1.0,
				ExpressionDeterminism.ratio(
					variation_key * 1664525 + 1013904223
				)
			)
			var kick_load := lerpf(
				1.0,
				1.28,
				(_kick_intensity - 1.0) / 0.72
			)
			var intensity_ratio := clampf(
				(_kick_intensity - 1.0) / 0.72,
				0.0,
				1.0
			)
			# A deliberate recent yaw curve chooses the roll hemisphere. Without one, retain the old
			# clockwise fall so a straight dropkick remains stable and readable. Gesture strength only
			# trims a few degrees; it does not turn a soft mouse curve into a half-hearted kick.
			var authored_roll_direction := (
				signf(_dropkick_tilt_input)
				if absf(_dropkick_tilt_input) > EPSILON
				else 1.0
			)
			var gesture_roll_scale := lerpf(
				0.94,
				1.0,
				absf(_dropkick_tilt_input)
			) if absf(_dropkick_tilt_input) > EPSILON else 1.0
			var root_roll := (
				DROP_KICK_ROOT_ROLL
				- intensity_ratio * 0.055
				+ roll_variation * DROP_KICK_ROOT_ROLL_VARIATION
			) * authored_roll_direction * gesture_roll_scale
			var target_root_roll := root_roll * roll_weight
			# Reclining the trunk moves the COM behind the feet. The arms open asymmetrically as passive
			# rotational counterweights. Root pitch carries the pelvis, torso, arms, and legs as one body;
			# the camera receives a smaller counter-pitch so the player sees the pose without losing view
			# control to a rigid animation.
			target_body_rotation.x += DROP_KICK_ROOT_RECLINE * extension_weight
			target_body_rotation.y += (
				roll_variation * 0.018
				- authored_roll_direction
				* absf(_dropkick_tilt_input)
				* 0.055
			) * drop_weight
			target_body_rotation.z += target_root_roll
			target_upper_position.y += 0.025 * drop_weight
			target_upper_position.z += 0.075 * extension_weight * kick_load
			target_upper_rotation.x += 0.15 * extension_weight * kick_load
			target_upper_rotation.y += roll_variation * 0.045 * drop_weight
			target_upper_rotation.z += (
				roll_variation * 0.075
				- authored_roll_direction * 0.025
			) * drop_weight
			target_left_arm_rotation.x -= (
				0.28 + arm_variation * 0.055
			) * drop_weight
			target_right_arm_rotation.x -= (
				0.28 - arm_variation * 0.055
			) * drop_weight
			target_left_arm_rotation.z -= (
				0.34 - roll_variation * 0.06
			) * drop_weight
			target_right_arm_rotation.z += (
				0.34 + roll_variation * 0.06
			) * drop_weight
			target_camera_position.y += 0.018 * drop_weight
			# Remain at the anatomical eye instead of translating laterally through the rolled torso. A tiny
			# forward clearance keeps the near plane outside the locally visible chest during the fastest
			# part of the recline.
			target_camera_position.z -= (
				DROP_KICK_CAMERA_FORWARD_CLEARANCE * drop_weight
			)
			# Root roll moves the actual head to one side of the pelvis. Centre the feet/impact line by
			# turning the eyes toward it, exactly as a person does, rather than dragging the camera back to
			# the pelvis. A committed mouse curve retains some lateral framing instead of becoming a lock.
			var curve_weight := pow(absf(_dropkick_tilt_input), 1.35)
			var centering_retention := lerpf(
				1.0,
				DROP_KICK_CAMERA_CURVE_CENTERING_RETENTION,
				curve_weight
			)
			var eye_lateral_offset := (
				-sin(target_root_roll) * DROP_KICK_CAMERA_EYE_HEIGHT
			)
			target_camera_rotation.y += (
				atan2(eye_lateral_offset, DROP_KICK_CAMERA_AIM_DISTANCE)
				* centering_retention
			)
			target_camera_rotation.x += (
				DROP_KICK_CAMERA_COUNTER_PITCH * extension_weight
			)
			# The neck and eyes resist part of the body's roll. Other players see a nearly sideways body,
			# while first person still feels the maneuver without having its horizon hard-locked to -90°.
			target_head_rotation.z -= (
				root_roll * DROP_KICK_HEAD_ROLL_COMPENSATION * roll_weight
			)
			target_camera_rotation.z += (
				root_roll * DROP_KICK_CAMERA_ROLL_INHERITANCE * roll_weight
			)
		else:
			var kick_weight := sin(_kick_phase * PI)
			var strike_weight := pow(
				clampf(sin(_kick_phase * PI), 0.0, 1.0),
				0.72
			)
			# The support side accepts the load while the torso and arms counter-rotate. Camera influence is
			# deliberately smaller than body influence so first person reads the kick without a forced jerk.
			var kick_load := lerpf(1.0, 1.42, (_kick_intensity - 1.0) / 0.72)
			target_upper_position.x -= kick_side_sign * 0.042 * kick_weight * kick_load
			target_upper_position.z += 0.032 * strike_weight * kick_load
			target_upper_rotation.x -= 0.12 * strike_weight * kick_load
			target_upper_rotation.y -= kick_side_sign * 0.13 * kick_weight * kick_load
			target_upper_rotation.z -= kick_side_sign * 0.15 * kick_weight * kick_load
			target_left_arm_rotation.x += kick_side_sign * 0.16 * kick_weight * kick_load
			target_right_arm_rotation.x -= kick_side_sign * 0.16 * kick_weight * kick_load
			target_camera_position.x -= kick_side_sign * 0.009 * kick_weight * kick_load
			target_camera_rotation.z -= kick_side_sign * 0.026 * kick_weight * kick_load

	if _pose != null and _pose_weight > EPSILON:
		var action_weight := smoothstep(0.0, 1.0, _pose_weight)
		var inheritance := lerpf(1.0, _pose.procedural_inheritance, action_weight)
		target_upper_position = balance_position + (
			target_upper_position - balance_position
		) * inheritance
		target_upper_rotation = balance_rotation + (
			target_upper_rotation - balance_rotation
		) * inheritance
		target_head_position *= inheritance
		target_head_rotation *= inheritance
		target_camera_position *= inheritance
		target_camera_rotation *= inheritance
		target_upper_position += _pose.upper_body_position * _pose.upper_body_weight * action_weight
		target_upper_rotation += _pose.upper_body_rotation * _pose.upper_body_weight * action_weight
		target_head_position += _pose.head_position * _pose.head_weight * action_weight
		target_head_rotation += _pose.head_rotation * _pose.head_weight * action_weight
		target_camera_position += _pose.camera_position * _pose.camera_weight * action_weight
		target_camera_rotation += _pose.camera_rotation * _pose.camera_weight * action_weight
		if _pose_left_arm_enabled:
			target_left_arm_rotation = target_left_arm_rotation * inheritance + (
				_pose.left_arm_rotation * _pose.left_arm_weight * action_weight
			)
			target_left_forearm_rotation = (
				_pose.left_forearm_rotation
				* _pose.left_forearm_weight
				* action_weight
			)
		if _pose_right_arm_enabled:
			target_right_arm_rotation = target_right_arm_rotation * inheritance + (
				_pose.right_arm_rotation * _pose.right_arm_weight * action_weight
			)
			target_right_forearm_rotation = (
				_pose.right_forearm_rotation
				* _pose.right_forearm_weight
				* action_weight
			)

	# Attention is a presentation constraint, not an authored pose channel. Applying it after the
	# action filter lets a character continue looking at its wrist display or a nearby player.
	target_head_rotation += _attention_head_rotation * _attention_weight

	# Environmental contact remains outside authored-pose filtering: a wall can move the actual body,
	# head, camera, and wrist terminal together instead of becoming weaker whenever an emote is active.
	var impact_position := _body_impact_position_spring.value
	var impact_rotation := _body_impact_rotation_spring.value
	target_upper_position += impact_position
	target_upper_rotation += impact_rotation
	target_head_position += impact_position * 0.42
	target_head_rotation += impact_rotation * 0.56
	target_camera_position += impact_position * 0.74
	target_camera_rotation += impact_rotation * 0.78

	if not has_left_arm:
		target_left_arm_rotation = Vector3.ZERO
		target_left_forearm_rotation = Vector3.ZERO
	if not has_right_arm:
		target_right_arm_rotation = Vector3.ZERO
		target_right_forearm_rotation = Vector3.ZERO
	if ragdoll_active:
		target_body_rotation = Vector3.ZERO
		target_upper_position = Vector3.ZERO
		target_upper_rotation = Vector3.ZERO
		target_head_position = Vector3.ZERO
		target_head_rotation = Vector3.ZERO
		target_left_arm_rotation = Vector3.ZERO
		target_right_arm_rotation = Vector3.ZERO
		target_left_forearm_rotation = Vector3.ZERO
		target_right_forearm_rotation = Vector3.ZERO
		target_camera_position = Vector3.ZERO
		target_camera_rotation = Vector3.ZERO

	if not _initialized:
		_body_rotation_spring.snap(target_body_rotation)
		_upper_body_position_spring.snap(target_upper_position)
		_upper_body_rotation_spring.snap(target_upper_rotation)
		_head_position_spring.snap(target_head_position)
		_head_rotation_spring.snap(target_head_rotation)
		_left_arm_rotation_spring.snap(target_left_arm_rotation)
		_right_arm_rotation_spring.snap(target_right_arm_rotation)
		_left_forearm_rotation_spring.snap(target_left_forearm_rotation)
		_right_forearm_rotation_spring.snap(target_right_forearm_rotation)
		_camera_position_spring.snap(target_camera_position)
		_camera_rotation_spring.snap(target_camera_rotation)
		_sync_outputs()
		_initialized = true
		return
	_body_rotation_spring.advance(
		target_body_rotation, safe_delta, ROOT_POSE_RESPONSE_HZ
	)
	_upper_body_position_spring.advance(
		target_upper_position, safe_delta, BODY_RESPONSE_HZ
	)
	_upper_body_rotation_spring.advance(
		target_upper_rotation, safe_delta, BODY_RESPONSE_HZ
	)
	_head_position_spring.advance(target_head_position, safe_delta, HEAD_RESPONSE_HZ)
	_head_rotation_spring.advance(target_head_rotation, safe_delta, HEAD_RESPONSE_HZ)
	_left_arm_rotation_spring.advance(
		target_left_arm_rotation, safe_delta, ARM_RESPONSE_HZ
	)
	_right_arm_rotation_spring.advance(
		target_right_arm_rotation, safe_delta, ARM_RESPONSE_HZ
	)
	_left_forearm_rotation_spring.advance(
		target_left_forearm_rotation, safe_delta, ARM_RESPONSE_HZ
	)
	_right_forearm_rotation_spring.advance(
		target_right_forearm_rotation, safe_delta, ARM_RESPONSE_HZ
	)
	_camera_position_spring.advance(
		target_camera_position, safe_delta, CAMERA_LOCOMOTION_RESPONSE_HZ
	)
	_camera_rotation_spring.advance(
		target_camera_rotation, safe_delta, CAMERA_LOCOMOTION_RESPONSE_HZ
	)
	_sync_outputs()


func _sync_outputs() -> void:
	body_rotation = _body_rotation_spring.value
	upper_body_position = _upper_body_position_spring.value
	upper_body_rotation = _upper_body_rotation_spring.value
	head_position = _head_position_spring.value
	head_rotation = _head_rotation_spring.value
	left_arm_rotation = _left_arm_rotation_spring.value
	right_arm_rotation = _right_arm_rotation_spring.value
	left_forearm_rotation = _left_forearm_rotation_spring.value
	right_forearm_rotation = _right_forearm_rotation_spring.value
	camera_position = _camera_position_spring.value
	camera_rotation = _camera_rotation_spring.value
