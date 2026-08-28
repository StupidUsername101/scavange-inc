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
const BODY_RESPONSE_HZ := 4.8
const HEAD_RESPONSE_HZ := 5.7
const ARM_RESPONSE_HZ := 5.0
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
const EPSILON := 0.000001
const CRITICALLY_DAMPED_VECTOR3 := preload(
	"res://scripts/characters/critically_damped_vector3.gd"
)

var upper_body_position := Vector3.ZERO
var upper_body_rotation := Vector3.ZERO
var head_position := Vector3.ZERO
var head_rotation := Vector3.ZERO
var left_arm_rotation := Vector3.ZERO
var right_arm_rotation := Vector3.ZERO
var camera_position := Vector3.ZERO
var camera_rotation := Vector3.ZERO

var _upper_body_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _upper_body_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _head_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _head_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _left_arm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _right_arm_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _camera_position_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _camera_rotation_spring := CRITICALLY_DAMPED_VECTOR3.new()
var _identity_phase := Vector3.ZERO
var _identity_amplitude := 1.0
var _initialized := false
var _pose: CharacterPoseDefinition
var _pose_weight := 0.0
var _pose_left_arm_enabled := true
var _pose_right_arm_enabled := true
var _attention_head_rotation := Vector3.ZERO
var _attention_weight := 0.0


func set_expression_identity(identity: int) -> void:
	# Integer hashing keeps the character-specific variation deterministic without sharing RNG state.
	var key := absi(identity) + 1
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
	has_right_leg: bool
) -> void:
	var safe_delta := clampf(delta, 0.0, MAX_FRAME_DELTA_SECONDS)
	var safe_clock := expression_clock if is_finite(expression_clock) else 0.0
	var safe_cycle := gait_cycle if is_finite(gait_cycle) else 0.0
	var moving := clampf(movement_weight, 0.0, 1.0)
	var sprint := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var fatigue := pow(clampf(endurance_spent_ratio, 0.0, 1.0), 1.35)
	var installed_leg_count := int(has_left_leg) + int(has_right_leg)
	if ragdoll_active:
		moving = 0.0

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
	var body_locomotion_rotation := Vector3(
		-forward_speed_weight * (0.025 + sprint * 0.035),
		sin(stride_phase) * (0.025 + sprint * 0.045) * moving,
		-planted_sign * contact_lift * (0.018 + sprint * 0.025) * moving
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
		if _pose_right_arm_enabled:
			target_right_arm_rotation = target_right_arm_rotation * inheritance + (
				_pose.right_arm_rotation * _pose.right_arm_weight * action_weight
			)

	# Attention is a presentation constraint, not an authored pose channel. Applying it after the
	# action filter lets a character continue looking at its wrist display or a nearby player.
	target_head_rotation += _attention_head_rotation * _attention_weight

	if not has_left_arm:
		target_left_arm_rotation = Vector3.ZERO
	if not has_right_arm:
		target_right_arm_rotation = Vector3.ZERO
	if ragdoll_active:
		target_upper_position = Vector3.ZERO
		target_upper_rotation = Vector3.ZERO
		target_head_position = Vector3.ZERO
		target_head_rotation = Vector3.ZERO
		target_left_arm_rotation = Vector3.ZERO
		target_right_arm_rotation = Vector3.ZERO
		target_camera_position = Vector3.ZERO
		target_camera_rotation = Vector3.ZERO

	if not _initialized:
		_upper_body_position_spring.snap(target_upper_position)
		_upper_body_rotation_spring.snap(target_upper_rotation)
		_head_position_spring.snap(target_head_position)
		_head_rotation_spring.snap(target_head_rotation)
		_left_arm_rotation_spring.snap(target_left_arm_rotation)
		_right_arm_rotation_spring.snap(target_right_arm_rotation)
		_camera_position_spring.snap(target_camera_position)
		_camera_rotation_spring.snap(target_camera_rotation)
		_sync_outputs()
		_initialized = true
		return
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
	_camera_position_spring.advance(
		target_camera_position, safe_delta, CAMERA_LOCOMOTION_RESPONSE_HZ
	)
	_camera_rotation_spring.advance(
		target_camera_rotation, safe_delta, CAMERA_LOCOMOTION_RESPONSE_HZ
	)
	_sync_outputs()


func _sync_outputs() -> void:
	upper_body_position = _upper_body_position_spring.value
	upper_body_rotation = _upper_body_rotation_spring.value
	head_position = _head_position_spring.value
	head_rotation = _head_rotation_spring.value
	left_arm_rotation = _left_arm_rotation_spring.value
	right_arm_rotation = _right_arm_rotation_spring.value
	camera_position = _camera_position_spring.value
	camera_rotation = _camera_rotation_spring.value
