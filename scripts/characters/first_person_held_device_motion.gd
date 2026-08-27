class_name FirstPersonHeldDeviceMotion
extends RefCounted

## Reusable first-person arm/load response. Locomotion comes from the authoritative gait clock;
## small hold motion is a deterministic combination of shoulder sway and elbow correction. The
## critically damped state represents arm inertia without noise allocations or frame-rate-dependent
## lerps.

const GAIT_POSITION_INHERITANCE := 0.30
const GAIT_PITCH_PER_METER := -0.10
const GAIT_YAW_PER_METER := 0.12
const GAIT_ROLL_PER_METER := -0.18
const MOVING_HOLD_SWAY_RATIO := 0.34
const HOLD_PRIMARY_FREQUENCY_HZ := 0.68
const HOLD_SECONDARY_FREQUENCY_HZ := 0.93
const HOLD_CORRECTION_FREQUENCY_HZ := 3.2
const RESPONSE_FREQUENCY_HZ := 4.2
const FATIGUE_START_SPENT_RATIO := 0.06
const FATIGUE_FULL_SPENT_RATIO := 0.90
const FATIGUE_RESPONSE_EXPONENT := 1.25
const FATIGUE_ATTACK_SPEED := 3.6
const FATIGUE_RECOVERY_SPEED := 2.2
const FATIGUE_GAIT_POSITION_LIFT := 0.42
const WALK_SHOULDER_POSITION_AMPLITUDE := Vector3(0.0035, 0.0022, 0.0025)
const RUN_SHOULDER_POSITION_AMPLITUDE := Vector3(0.0110, 0.0050, 0.0075)
const WALK_SHOULDER_ROTATION_AMPLITUDE := Vector3(0.012, 0.010, 0.016)
const RUN_SHOULDER_ROTATION_AMPLITUDE := Vector3(0.040, 0.030, 0.050)
const FATIGUE_SHOULDER_POSITION_LIFT := 0.32
const FATIGUE_SHOULDER_ROTATION_LIFT := 0.38
const MAX_FRAME_DELTA_SECONDS := 0.1
const TIME_ROLLOVER_SECONDS := 4096.0

var position_offset := Vector3.ZERO
var rotation_offset := Vector3.ZERO
var _position_velocity := Vector3.ZERO
var _rotation_velocity := Vector3.ZERO
var _gait_bob_offset := Vector3.ZERO
var _movement_weight := 0.0
var _gait_cycle := 0.0
var _run_weight := 0.0
var fatigue_weight := 0.0
var _fatigue_target := 0.0
var _motion_time := 0.0


func set_gait_input(
	head_bob_offset: Vector3,
	movement_weight: float,
	gait_cycle: float = 0.0,
	run_weight: float = 0.0
) -> void:
	_gait_bob_offset = (
		head_bob_offset
		if head_bob_offset.is_finite()
		else Vector3.ZERO
	)
	_movement_weight = clampf(movement_weight, 0.0, 1.0)
	_gait_cycle = gait_cycle if is_finite(gait_cycle) else 0.0
	_run_weight = clampf(run_weight, 0.0, 1.0)


func set_endurance_spent_ratio(endurance_spent_ratio: float) -> void:
	_fatigue_target = fatigue_from_endurance_spent_ratio(endurance_spent_ratio)


func advance(delta: float) -> void:
	var safe_delta := clampf(delta, 0.0, MAX_FRAME_DELTA_SECONDS)
	if safe_delta <= 0.0:
		return
	_motion_time = fmod(_motion_time + safe_delta, TIME_ROLLOVER_SECONDS)
	var fatigue_speed := (
		FATIGUE_ATTACK_SPEED
		if _fatigue_target > fatigue_weight
		else FATIGUE_RECOVERY_SPEED
	)
	fatigue_weight = lerpf(
		fatigue_weight,
		_fatigue_target,
		1.0 - exp(-fatigue_speed * safe_delta)
	)
	var target_position := (
		_gait_bob_offset
		* GAIT_POSITION_INHERITANCE
		* (1.0 + FATIGUE_GAIT_POSITION_LIFT * fatigue_weight)
		+ hold_position_at_time(
			_motion_time,
			_movement_weight,
			fatigue_weight
		)
		+ shoulder_position_at_cycle(
			_gait_cycle,
			_movement_weight,
			_run_weight,
			fatigue_weight
		)
	)
	var target_rotation := Vector3(
		_gait_bob_offset.y * GAIT_PITCH_PER_METER,
		_gait_bob_offset.x * GAIT_YAW_PER_METER,
		_gait_bob_offset.x * GAIT_ROLL_PER_METER
	) + hold_rotation_at_time(
		_motion_time,
		_movement_weight,
		fatigue_weight
	) + shoulder_rotation_at_cycle(
		_gait_cycle,
		_movement_weight,
		_run_weight,
		fatigue_weight
	)
	var angular_frequency := TAU * RESPONSE_FREQUENCY_HZ
	var decay := exp(-angular_frequency * safe_delta)

	var position_error := position_offset - target_position
	var position_step := (
		_position_velocity + position_error * angular_frequency
	) * safe_delta
	position_offset = target_position + (position_error + position_step) * decay
	_position_velocity = (
		_position_velocity - position_step * angular_frequency
	) * decay

	var rotation_error := rotation_offset - target_rotation
	var rotation_step := (
		_rotation_velocity + rotation_error * angular_frequency
	) * safe_delta
	rotation_offset = target_rotation + (rotation_error + rotation_step) * decay
	_rotation_velocity = (
		_rotation_velocity - rotation_step * angular_frequency
	) * decay


static func shoulder_position_at_cycle(
	gait_cycle: float,
	movement_weight: float,
	run_weight: float,
	fatigue: float = 0.0
) -> Vector3:
	if not is_finite(gait_cycle):
		return Vector3.ZERO
	var movement := clampf(movement_weight, 0.0, 1.0)
	if is_zero_approx(movement):
		return Vector3.ZERO
	var sprint := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var fatigue_weight := clampf(fatigue, 0.0, 1.0)
	var stride_phase := gait_cycle * PI
	var step_phase := gait_cycle * TAU
	var amplitude := WALK_SHOULDER_POSITION_AMPLITUDE.lerp(
		RUN_SHOULDER_POSITION_AMPLITUDE,
		sprint
	) * (1.0 + FATIGUE_SHOULDER_POSITION_LIFT * fatigue_weight)
	# The lateral/depth ellipse is one full shoulder cycle per two footfalls. Vertical load follows
	# each impact. A small fatigue-only lag makes the heavy forearm trail the shoulder rather than
	# scaling the camera bob uniformly.
	var lagged_stride := sin(stride_phase - 0.46 * fatigue_weight)
	return Vector3(
		lagged_stride * amplitude.x,
		-cos(step_phase) * amplitude.y,
		cos(stride_phase - 0.28 - 0.38 * fatigue_weight) * amplitude.z
	) * movement


static func shoulder_rotation_at_cycle(
	gait_cycle: float,
	movement_weight: float,
	run_weight: float,
	fatigue: float = 0.0
) -> Vector3:
	if not is_finite(gait_cycle):
		return Vector3.ZERO
	var movement := clampf(movement_weight, 0.0, 1.0)
	if is_zero_approx(movement):
		return Vector3.ZERO
	var sprint := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var fatigue_weight := clampf(fatigue, 0.0, 1.0)
	var stride_phase := gait_cycle * PI
	var step_phase := gait_cycle * TAU
	var amplitude := WALK_SHOULDER_ROTATION_AMPLITUDE.lerp(
		RUN_SHOULDER_ROTATION_AMPLITUDE,
		sprint
	) * (1.0 + FATIGUE_SHOULDER_ROTATION_LIFT * fatigue_weight)
	var shoulder_wave := sin(stride_phase + 0.24 - 0.42 * fatigue_weight)
	return Vector3(
		shoulder_wave * amplitude.x,
		sin(stride_phase - 0.18 - 0.34 * fatigue_weight) * amplitude.y,
		(
			cos(stride_phase + 0.31 - 0.46 * fatigue_weight) * 0.82
			+ sin(step_phase) * 0.18
		) * amplitude.z
	) * movement


static func hold_position_at_time(
	time_seconds: float,
	movement_weight: float,
	fatigue: float = 0.0
) -> Vector3:
	var safe_time := time_seconds if is_finite(time_seconds) else 0.0
	var primary_phase := safe_time * TAU * HOLD_PRIMARY_FREQUENCY_HZ
	var secondary_phase := safe_time * TAU * HOLD_SECONDARY_FREQUENCY_HZ + 1.37
	var correction_phase := safe_time * TAU * HOLD_CORRECTION_FREQUENCY_HZ + 0.41
	var sway_scale := lerpf(
		1.0,
		MOVING_HOLD_SWAY_RATIO,
		clampf(movement_weight, 0.0, 1.0)
	)
	var stable_hold := Vector3(
		sin(primary_phase) * 0.0018 + sin(correction_phase) * 0.00028,
		sin(secondary_phase) * 0.00125 + cos(correction_phase) * 0.0002,
		cos(primary_phase * 0.71 + 0.83) * 0.00065
	) * sway_scale
	var fatigue_weight := clampf(fatigue, 0.0, 1.0)
	var breath_phase := safe_time * TAU * 0.38 + 0.76
	var shoulder_phase := safe_time * TAU * 0.57 + 2.13
	var tremor_phase := safe_time * TAU * 6.1 + 0.29
	return stable_hold + Vector3(
		sin(shoulder_phase) * 0.00145 + sin(tremor_phase) * 0.00032,
		sin(breath_phase) * 0.00235 + cos(tremor_phase * 1.11) * 0.00028,
		cos(breath_phase * 1.23) * 0.00095
	) * fatigue_weight


static func hold_rotation_at_time(
	time_seconds: float,
	movement_weight: float,
	fatigue: float = 0.0
) -> Vector3:
	var safe_time := time_seconds if is_finite(time_seconds) else 0.0
	var primary_phase := safe_time * TAU * HOLD_PRIMARY_FREQUENCY_HZ
	var secondary_phase := safe_time * TAU * HOLD_SECONDARY_FREQUENCY_HZ + 1.37
	var correction_phase := safe_time * TAU * HOLD_CORRECTION_FREQUENCY_HZ + 0.41
	var sway_scale := lerpf(
		1.0,
		MOVING_HOLD_SWAY_RATIO,
		clampf(movement_weight, 0.0, 1.0)
	)
	var stable_hold := Vector3(
		sin(secondary_phase) * 0.0031 + sin(correction_phase) * 0.00055,
		sin(primary_phase) * 0.0022,
		cos(primary_phase * 1.09 + 1.93) * 0.0042
		+ cos(correction_phase) * 0.0005
	) * sway_scale
	var fatigue_weight := clampf(fatigue, 0.0, 1.0)
	var breath_phase := safe_time * TAU * 0.38 + 0.76
	var shoulder_phase := safe_time * TAU * 0.57 + 2.13
	var tremor_phase := safe_time * TAU * 6.1 + 0.29
	return stable_hold + Vector3(
		sin(breath_phase) * 0.0085 + sin(tremor_phase) * 0.00115,
		sin(shoulder_phase) * 0.0062 + cos(tremor_phase * 0.93) * 0.0009,
		cos(breath_phase * 1.09 + 1.2) * 0.0125
		+ sin(tremor_phase * 1.17) * 0.00135
	) * fatigue_weight


static func fatigue_from_endurance_spent_ratio(
	endurance_spent_ratio: float
) -> float:
	var spent := clampf(
		endurance_spent_ratio if is_finite(endurance_spent_ratio) else 0.0,
		0.0,
		1.0
	)
	var response := smoothstep(
		FATIGUE_START_SPENT_RATIO,
		FATIGUE_FULL_SPENT_RATIO,
		spent
	)
	return pow(response, FATIGUE_RESPONSE_EXPONENT)
