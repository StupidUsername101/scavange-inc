class_name PlayerOcularExpressionController
extends RefCounted

## Deterministic, allocation-free ocular presentation driven by replicated expression time.
## The eyes lead a gaze shift; the head only joins outside the comfortable eye-only range.

const MAX_FRAME_DELTA_SECONDS := 0.1
const EYE_ONLY_YAW := deg_to_rad(18.0)
const EYE_ONLY_PITCH := deg_to_rad(12.0)
const MAX_HEAD_YAW := deg_to_rad(32.0)
const MAX_HEAD_PITCH := deg_to_rad(18.0)
const MAX_EYE_YAW := deg_to_rad(34.0)
const MAX_EYE_PITCH := deg_to_rad(24.0)
const HEAD_RESPONSE_HZ := 4.2
const PUPIL_RESPONSE_HZ := 17.0
const LID_RESPONSE_HZ := 21.0
const BLINK_WINDOW_SECONDS := 4.8
const BLINK_MIN_OFFSET_SECONDS := 0.45
const BLINK_OFFSET_RANGE_SECONDS := 3.85
const EPSILON := 0.000001

var left_pupil_offset := Vector2.ZERO
var right_pupil_offset := Vector2.ZERO
var pupil_scale := 1.0
var left_lid_openness := 1.0
var right_lid_openness := 1.0
var left_lid_tilt := 0.0
var right_lid_tilt := 0.0
var head_rotation := Vector3.ZERO

var _identity_key := 1
var _identity_phase := Vector3.ZERO
var _head_yaw := 0.0
var _head_pitch := 0.0
var _left_pupil := Vector2.ZERO
var _right_pupil := Vector2.ZERO
var _pupil_scale_value := 1.0
var _left_openness := 1.0
var _right_openness := 1.0
var _left_tilt := 0.0
var _right_tilt := 0.0
var _initialized := false


func set_expression_identity(identity: int) -> void:
	_identity_key = absi(identity) + 1
	_identity_phase = Vector3(
		ExpressionDeterminism.ratio(_identity_key * 1103515245 + 12345) * TAU,
		ExpressionDeterminism.ratio(_identity_key * 214013 + 2531011) * TAU,
		ExpressionDeterminism.ratio(_identity_key * 1664525 + 1013904223) * TAU
	)


func update(
	delta: float,
	expression_clock: float,
	local_target: Vector3,
	attention_weight: float,
	device_focus: bool,
	fatigue_ratio: float
) -> void:
	var safe_delta := clampf(delta, 0.0, MAX_FRAME_DELTA_SECONDS)
	var safe_clock := expression_clock if is_finite(expression_clock) else 0.0
	var attention := clampf(attention_weight, 0.0, 1.0)
	var fatigue := clampf(fatigue_ratio, 0.0, 1.0)
	var target := local_target if local_target.is_finite() else Vector3(0.0, 0.0, -4.0)
	if target.length_squared() <= EPSILON:
		target = Vector3(0.0, 0.0, -4.0)
	var target_distance := target.length()
	var horizontal_distance := Vector2(target.x, target.z).length()
	var gaze_yaw := atan2(target.x, -target.z)
	var gaze_pitch := atan2(target.y, maxf(horizontal_distance, EPSILON))

	# Unfocused eyes make small, held fixations rather than tracing a sine wave continuously.
	var fixation_index := floori(safe_clock / 0.42)
	var fixation_yaw := (
		ExpressionDeterminism.ratio(
			_identity_key * 92821 + fixation_index * 68917
		) - 0.5
	) * deg_to_rad(3.4)
	var fixation_pitch := (
		ExpressionDeterminism.ratio(
			_identity_key * 31337 + fixation_index * 10163
		) - 0.5
	) * deg_to_rad(2.2)
	gaze_yaw += fixation_yaw * (1.0 - attention * 0.72)
	gaze_pitch += fixation_pitch * (1.0 - attention * 0.72)

	var desired_head_yaw := -_head_contribution(
		gaze_yaw,
		EYE_ONLY_YAW,
		MAX_HEAD_YAW,
		0.68 if device_focus else 0.56
	)
	var desired_head_pitch := _head_contribution(
		gaze_pitch,
		EYE_ONLY_PITCH,
		MAX_HEAD_PITCH,
		0.72 if device_focus else 0.52
	)
	var head_blend := _response_weight(safe_delta, HEAD_RESPONSE_HZ)
	_head_yaw = lerp_angle(_head_yaw, desired_head_yaw, head_blend)
	_head_pitch = lerp_angle(_head_pitch, desired_head_pitch, head_blend)

	# Euler Y has the opposite sign to the observer-space horizontal gaze angle.
	var residual_yaw := gaze_yaw + _head_yaw
	var residual_pitch := gaze_pitch - _head_pitch
	var pupil_target := Vector2(
		clampf(residual_yaw / MAX_EYE_YAW, -1.0, 1.0),
		clampf(residual_pitch / MAX_EYE_PITCH, -1.0, 1.0)
	)
	var vergence := clampf(
		inverse_lerp(5.0, 0.45, target_distance),
		0.0,
		1.0
	) * 0.13
	var left_pupil_target := Vector2(
		clampf(pupil_target.x + vergence, -1.0, 1.0),
		pupil_target.y
	)
	var right_pupil_target := Vector2(
		clampf(pupil_target.x - vergence, -1.0, 1.0),
		pupil_target.y
	)

	var blink_closure := _blink_closure(safe_clock)
	var slow_asymmetry := sin(
		safe_clock * TAU * 0.073 + _identity_phase.y
	)
	var attentive_squint := attention * (0.025 if device_focus else 0.012)
	var base_openness := clampf(
		0.96 - fatigue * 0.13 - attentive_squint,
		0.70,
		1.0
	)
	var left_open_target := clampf(
		base_openness - blink_closure + slow_asymmetry * 0.018,
		0.0,
		1.0
	)
	var right_open_target := clampf(
		base_openness - blink_closure - slow_asymmetry * 0.018,
		0.0,
		1.0
	)
	var expression_tilt := (
		sin(safe_clock * TAU * 0.047 + _identity_phase.z) * 0.055
		+ pupil_target.x * 0.035
	)
	var left_tilt_target := clampf(expression_tilt, -0.12, 0.12)
	var right_tilt_target := clampf(-expression_tilt, -0.12, 0.12)
	var dilation_target := clampf(
		0.94
		+ sin(safe_clock * TAU * 0.11 + _identity_phase.x) * 0.025
		+ attention * 0.055
		+ fatigue * 0.035,
		0.82,
		1.12
	)

	if not _initialized:
		_left_pupil = left_pupil_target
		_right_pupil = right_pupil_target
		_pupil_scale_value = dilation_target
		_left_openness = left_open_target
		_right_openness = right_open_target
		_left_tilt = left_tilt_target
		_right_tilt = right_tilt_target
		_initialized = true
	else:
		var pupil_blend := _response_weight(safe_delta, PUPIL_RESPONSE_HZ)
		var lid_blend := _response_weight(safe_delta, LID_RESPONSE_HZ)
		_left_pupil = _left_pupil.lerp(left_pupil_target, pupil_blend)
		_right_pupil = _right_pupil.lerp(right_pupil_target, pupil_blend)
		_pupil_scale_value = lerpf(
			_pupil_scale_value,
			dilation_target,
			pupil_blend
		)
		_left_openness = lerpf(_left_openness, left_open_target, lid_blend)
		_right_openness = lerpf(_right_openness, right_open_target, lid_blend)
		_left_tilt = lerpf(_left_tilt, left_tilt_target, lid_blend)
		_right_tilt = lerpf(_right_tilt, right_tilt_target, lid_blend)
	_sync_outputs()


func _sync_outputs() -> void:
	left_pupil_offset = _left_pupil
	right_pupil_offset = _right_pupil
	pupil_scale = _pupil_scale_value
	left_lid_openness = _left_openness
	right_lid_openness = _right_openness
	left_lid_tilt = _left_tilt
	right_lid_tilt = _right_tilt
	head_rotation = Vector3(_head_pitch, _head_yaw, 0.0)


func _blink_closure(clock: float) -> float:
	var window_index := floori(clock / BLINK_WINDOW_SECONDS)
	var closure := _blink_in_window(clock, window_index)
	# Keeping this check makes the function robust if a later art pass allows a blink to cross a window.
	closure = maxf(closure, _blink_in_window(clock, window_index - 1))
	return clampf(closure, 0.0, 1.0)


func _blink_in_window(clock: float, window_index: int) -> float:
	if window_index < 0:
		return 0.0
	var event_key := _identity_key * 104729 + window_index * 13007
	var event_time := (
		float(window_index) * BLINK_WINDOW_SECONDS
		+ BLINK_MIN_OFFSET_SECONDS
		+ ExpressionDeterminism.ratio(event_key) * BLINK_OFFSET_RANGE_SECONDS
	)
	var duration := lerpf(
		0.14,
		0.205,
		ExpressionDeterminism.ratio(event_key + 7919)
	)
	var closure := _blink_wave(clock - event_time, duration)
	if ExpressionDeterminism.ratio(event_key + 19391) > 0.84:
		closure = maxf(
			closure,
			_blink_wave(clock - event_time - duration - 0.12, duration * 0.88)
		)
	return closure


static func _blink_wave(age: float, duration: float) -> float:
	if age < 0.0 or age > duration:
		return 0.0
	var phase := clampf(age / maxf(duration, EPSILON), 0.0, 1.0)
	return pow(maxf(sin(phase * PI), 0.0), 0.42)


static func _head_contribution(
	angle: float,
	eye_only_angle: float,
	maximum: float,
	share: float
) -> float:
	var excess := maxf(absf(angle) - eye_only_angle, 0.0)
	return signf(angle) * minf(excess * share, maximum)


static func _response_weight(delta: float, response_hz: float) -> float:
	return 1.0 - exp(-maxf(delta, 0.0) * maxf(response_hz, 0.0))
