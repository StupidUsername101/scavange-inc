class_name PlayerGait
extends RefCounted

## One shared distance clock for authoritative footsteps and client camera motion. A whole cycle is
## one footfall-to-footfall step: phase zero is impact, phase 0.5 is the high point, and the step
## sequence alternates the planted side.

const WALK_STEP_DISTANCE := 4.25
# At full sprint this produces about four planted steps per second. The previous 2.175 m value
# produced more than six and made both the sound and camera look mechanically fast.
const RUN_STEP_DISTANCE := 3.35
const MINIMUM_SPEED_SQUARED := 0.25
const MINIMUM_STRIDE_DISTANCE := 0.01

var distance_since_step := WALK_STEP_DISTANCE * 0.5
var stride_distance := WALK_STEP_DISTANCE
var step_sequence := 0
var active := false


func advance(
	horizontal_speed: float,
	grounded: bool,
	running: bool,
	delta: float
) -> int:
	_set_stride(get_stride_distance(running))
	var bounded_speed := maxf(horizontal_speed, 0.0)
	active = (
		grounded
		and bounded_speed * bounded_speed >= MINIMUM_SPEED_SQUARED
	)
	if not active:
		return 0

	distance_since_step += bounded_speed * maxf(delta, 0.0)
	var completed_steps := floori(
		distance_since_step / stride_distance
	)
	if completed_steps <= 0:
		return 0
	distance_since_step = fmod(distance_since_step, stride_distance)
	step_sequence += completed_steps
	return completed_steps


func get_cycle() -> float:
	return float(step_sequence) + get_phase()


func get_phase() -> float:
	return clampf(
		distance_since_step / maxf(stride_distance, MINIMUM_STRIDE_DISTANCE),
		0.0,
		1.0
	)


func _set_stride(value: float) -> void:
	var next_stride := maxf(value, MINIMUM_STRIDE_DISTANCE)
	if is_equal_approx(next_stride, stride_distance):
		return
	var phase := get_phase()
	stride_distance = next_stride
	distance_since_step = phase * stride_distance


static func get_stride_distance(running: bool) -> float:
	return RUN_STEP_DISTANCE if running else WALK_STEP_DISTANCE


static func calculate_bob_offset(
	cycle: float,
	vertical_amount: float,
	horizontal_amount: float
) -> Vector3:
	if not is_finite(cycle):
		return Vector3.ZERO
	var step_index := floori(cycle)
	var phase := cycle - floorf(cycle)
	var planted_side := 1.0 if posmod(step_index, 2) == 0 else -1.0
	return Vector3(
		planted_side * cos(phase * PI) * maxf(horizontal_amount, 0.0),
		-cos(phase * TAU) * maxf(vertical_amount, 0.0),
		0.0
	)


static func calculate_run_bob_offset(
	cycle: float,
	vertical_amount: float,
	horizontal_amount: float
) -> Vector3:
	if not is_finite(cycle):
		return Vector3.ZERO
	var step_index := floori(cycle)
	var phase := cycle - floorf(cycle)
	var planted_side := 1.0 if posmod(step_index, 2) == 0 else -1.0
	# Sprint movement is not a faster walk sine. A narrow Gaussian-like compression gives the
	# landing some weight, while the broad half-wave models the flight phase without making the
	# camera pogo through the entire authored amplitude.
	var distance_from_impact := minf(phase, 1.0 - phase)
	var compression_ratio := distance_from_impact / 0.13
	var compression := exp(-compression_ratio * compression_ratio)
	var flight := sin(phase * PI)
	return Vector3(
		planted_side * flight * maxf(horizontal_amount, 0.0),
		(
			flight * 0.38
			- compression * 0.72
		) * maxf(vertical_amount, 0.0),
		0.0
	)
