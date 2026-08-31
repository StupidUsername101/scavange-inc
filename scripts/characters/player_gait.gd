class_name PlayerGait
extends RefCounted

## Shared distance clock for authoritative movement and client presentation. Each step samples a
## deterministic profile from player identity + sequence, so cadence, placement, and impact style
## vary without sending cosmetic random state or letting observers disagree.

enum FootSide {
	LEFT,
	RIGHT,
}

const WALK_STEP_DISTANCE := 1.52
const RUN_STEP_DISTANCE := 2.70
const FOOT_STANCE_HALF_WIDTH := 0.20
const SLOW_STEP_DISTANCE_RANGE := Vector2(0.62, 0.82)
const WALK_STEP_DISTANCE_RANGE := Vector2(1.32, 1.72)
const RUN_STEP_DISTANCE_RANGE := Vector2(2.35, 3.05)
const WALK_SWING_START_PHASE_RANGE := Vector2(0.18, 0.30)
const RUN_SWING_START_PHASE_RANGE := Vector2(0.07, 0.17)
const STEP_LEAD_SECONDS_RANGE := Vector2(0.052, 0.078)
const STEP_MAX_LEAD_DISTANCE_RANGE := Vector2(0.31, 0.46)
const RUN_STEP_MAX_LEAD_DISTANCE_RANGE := Vector2(0.48, 0.68)
const STEP_FORWARD_VARIATION_RANGE := Vector2(-0.035, 0.095)
const STEP_STANCE_SCALE_RANGE := Vector2(0.88, 1.15)
const RUN_STEP_STANCE_SCALE_RANGE := Vector2(1.14, 1.42)
const STEP_LATERAL_VARIATION_RANGE := Vector2(-0.018, 0.032)
const STEP_ARC_HEIGHT_RANGE := Vector2(0.135, 0.225)
const RUN_STEP_ARC_HEIGHT_RANGE := Vector2(0.205, 0.315)
const STEP_DURATION_SCALE_RANGE := Vector2(0.90, 1.18)
const STEP_TRIGGER_DISTANCE_RANGE := Vector2(0.43, 0.56)
const FOOTSTEP_VOLUME_DB_RANGE := Vector2(-2.1, -0.35)
const RUN_FOOTSTEP_VOLUME_DB_RANGE := Vector2(-0.65, 1.15)
const MINIMUM_SPEED_SQUARED := 0.25
const MINIMUM_STRIDE_DISTANCE := 0.01
const RUN_PROFILE_SPEED_THRESHOLD := 8.0
const WALK_REFERENCE_SPEED := 5.75
const RUN_REFERENCE_SPEED := 13.5
const RUN_RELEASE_RECOVERY_MIN_SPEED := 9.0
const RUN_RELEASE_RECOVERY_FULL_SPEED := 12.6
const RUN_RELEASE_RECOVERY_DURATION_RANGE := Vector2(1.02, 1.28)
const RUN_RELEASE_RECOVERY_STRIDE_RANGE := Vector2(1.85, 2.25)
const RUN_RELEASE_RECOVERY_SYNTHETIC_SPEED := 5.0
const HASH_MODULUS := 2147483647
const HASH_ID_MODULUS := 104729

var distance_since_step := WALK_STEP_DISTANCE * 0.5
var stride_distance := WALK_STEP_DISTANCE
var step_sequence := 0
var active := false
var expression_identity := 0
var _running := false
var momentum_recovery_weight := 0.0
var _momentum_recovery_peak := 0.0
var _momentum_recovery_elapsed := 0.0
var _momentum_recovery_duration := 0.0


func set_expression_identity(identity: int) -> void:
	var phase := get_phase()
	expression_identity = maxi(identity, 0)
	stride_distance = get_stride_distance_for_motion_and_recovery(
		RUN_REFERENCE_SPEED if _running else WALK_REFERENCE_SPEED,
		_running,
		expression_identity,
		step_sequence,
		momentum_recovery_weight
	)
	distance_since_step = phase * stride_distance


func reset_after_full_body_interruption(minimum_sequence: int) -> void:
	# Sound prediction keys are derived from this sequence. Never rewind it across ragdoll, death, or
	# respawn: a client can otherwise keep rejecting perfectly valid new contacts until the new clock
	# spends several strides catching its pre-interruption high-water mark.
	step_sequence = maxi(step_sequence, maxi(minimum_sequence, 0))
	_running = false
	active = false
	momentum_recovery_weight = 0.0
	_momentum_recovery_peak = 0.0
	_momentum_recovery_elapsed = 0.0
	_momentum_recovery_duration = 0.0
	stride_distance = get_stride_distance_for_motion_and_recovery(
		WALK_REFERENCE_SPEED,
		false,
		expression_identity,
		step_sequence,
		0.0
	)
	# A recovered body starts from a balanced mid-stance and produces its first new contact after half
	# a stride. This avoids both an instant recovery slap and a full-stride silent interval.
	distance_since_step = stride_distance * 0.5


func advance(
	horizontal_speed: float,
	grounded: bool,
	running: bool,
	delta: float,
	momentum_recovery_prepared: bool = false
) -> int:
	var bounded_speed := maxf(horizontal_speed, 0.0)
	if not momentum_recovery_prepared:
		update_momentum_recovery(
			bounded_speed,
			grounded,
			running,
			delta
		)
	_set_stride(get_stride_distance_for_motion_and_recovery(
		bounded_speed,
		running,
		expression_identity,
		step_sequence,
		momentum_recovery_weight
	))
	active = (
		grounded
		and (
			bounded_speed * bounded_speed >= MINIMUM_SPEED_SQUARED
			or momentum_recovery_weight > 0.001
		)
	)
	if not active:
		return 0

	distance_since_step += get_effective_gait_speed(
		bounded_speed,
		momentum_recovery_weight
	) * maxf(delta, 0.0)
	var completed_steps := 0
	# Normal play cannot cross several human-scale strides in one physics tick, but the bounded loop
	# keeps a hitch from corrupting phase while avoiding temporary arrays or profile objects.
	while distance_since_step >= stride_distance and completed_steps < 4:
		distance_since_step -= stride_distance
		step_sequence += 1
		completed_steps += 1
		stride_distance = get_stride_distance_for_motion_and_recovery(
			bounded_speed,
			running,
			expression_identity,
			step_sequence,
			momentum_recovery_weight
		)
	return completed_steps


func update_momentum_recovery(
	horizontal_speed: float,
	grounded: bool,
	running: bool,
	delta: float
) -> void:
	var was_running := _running
	_running = running
	if running or not grounded:
		momentum_recovery_weight = 0.0
		_momentum_recovery_peak = 0.0
		_momentum_recovery_elapsed = 0.0
		_momentum_recovery_duration = 0.0
		return
	if was_running:
		var release_intensity := get_run_release_recovery_intensity(
			horizontal_speed
		)
		if release_intensity > 0.001:
			_momentum_recovery_peak = release_intensity
			_momentum_recovery_elapsed = 0.0
			_momentum_recovery_duration = (
				get_run_release_recovery_duration(expression_identity)
				* lerpf(0.62, 1.0, release_intensity)
			)
	if _momentum_recovery_duration <= 0.0:
		momentum_recovery_weight = 0.0
		return
	_momentum_recovery_elapsed += maxf(delta, 0.0)
	var progress := clampf(
		_momentum_recovery_elapsed / _momentum_recovery_duration,
		0.0,
		1.0
	)
	momentum_recovery_weight = _momentum_recovery_peak * (
		1.0 - smoothstep(0.0, 1.0, progress)
	)
	if progress >= 1.0:
		momentum_recovery_weight = 0.0
		_momentum_recovery_peak = 0.0
		_momentum_recovery_duration = 0.0


func get_momentum_recovery_weight() -> float:
	return momentum_recovery_weight


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


static func get_stride_distance_for_step(
	running: bool,
	identity: int,
	sequence: int
) -> float:
	var authored_range := (
		RUN_STEP_DISTANCE_RANGE if running else WALK_STEP_DISTANCE_RANGE
	)
	return lerpf(
		authored_range.x,
		authored_range.y,
		_profile_unit(identity, sequence, 0, 1.55)
	)


static func get_stride_distance_for_motion(
	horizontal_speed: float,
	_running: bool,
	identity: int,
	sequence: int
) -> float:
	var walk_unit := _profile_unit(identity, sequence, 0, 1.55)
	var slow_distance := lerpf(
		SLOW_STEP_DISTANCE_RANGE.x,
		SLOW_STEP_DISTANCE_RANGE.y,
		walk_unit
	)
	var walk_distance := lerpf(
		WALK_STEP_DISTANCE_RANGE.x,
		WALK_STEP_DISTANCE_RANGE.y,
		walk_unit
	)
	var bounded_speed := maxf(horizontal_speed, 0.0)
	var walk_weight := smoothstep(
		sqrt(MINIMUM_SPEED_SQUARED),
		WALK_REFERENCE_SPEED,
		bounded_speed
	)
	var result := lerpf(slow_distance, walk_distance, walk_weight)
	var run_distance := lerpf(
		RUN_STEP_DISTANCE_RANGE.x,
		RUN_STEP_DISTANCE_RANGE.y,
		_profile_unit(identity, sequence, 11, 1.45)
	)
	var run_weight := smoothstep(
		WALK_REFERENCE_SPEED,
		RUN_REFERENCE_SPEED,
		bounded_speed
	)
	return lerpf(result, run_distance, run_weight)


static func get_stride_distance_for_motion_and_recovery(
	horizontal_speed: float,
	running: bool,
	identity: int,
	sequence: int,
	recovery_weight: float
) -> float:
	var ordinary_distance := get_stride_distance_for_motion(
		horizontal_speed,
		running,
		identity,
		sequence
	)
	var recovery_distance := lerpf(
		RUN_RELEASE_RECOVERY_STRIDE_RANGE.x,
		RUN_RELEASE_RECOVERY_STRIDE_RANGE.y,
		_profile_unit(identity, sequence, 12, 1.65)
	)
	return lerpf(
		ordinary_distance,
		recovery_distance,
		smoothstep(0.0, 1.0, clampf(recovery_weight, 0.0, 1.0))
	)


static func get_run_release_recovery_intensity(horizontal_speed: float) -> float:
	return smoothstep(
		RUN_RELEASE_RECOVERY_MIN_SPEED,
		RUN_RELEASE_RECOVERY_FULL_SPEED,
		maxf(horizontal_speed, 0.0)
	)


static func get_run_release_recovery_duration(identity: int) -> float:
	return lerpf(
		RUN_RELEASE_RECOVERY_DURATION_RANGE.x,
		RUN_RELEASE_RECOVERY_DURATION_RANGE.y,
		_profile_unit(identity, 0, 13, 1.8)
	)


static func get_effective_gait_speed(
	horizontal_speed: float,
	recovery_weight: float
) -> float:
	var recovery_speed := (
		RUN_RELEASE_RECOVERY_SYNTHETIC_SPEED
		* sqrt(clampf(recovery_weight, 0.0, 1.0))
	)
	return maxf(maxf(horizontal_speed, 0.0), recovery_speed)


static func get_swing_start_phase(
	running: bool,
	identity: int,
	impact_sequence: int
) -> float:
	var authored_range := (
		RUN_SWING_START_PHASE_RANGE
		if running
		else WALK_SWING_START_PHASE_RANGE
	)
	return lerpf(
		authored_range.x,
		authored_range.y,
		_profile_unit(identity, impact_sequence, 1, 1.7)
	)


static func get_swing_start_phase_for_motion(
	horizontal_speed: float,
	identity: int,
	impact_sequence: int
) -> float:
	var run_weight := smoothstep(
		WALK_REFERENCE_SPEED,
		RUN_REFERENCE_SPEED,
		maxf(horizontal_speed, 0.0)
	)
	return lerpf(
		get_swing_start_phase(false, identity, impact_sequence),
		get_swing_start_phase(true, identity, impact_sequence),
		run_weight
	)


static func get_step_lead_seconds(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_LEAD_SECONDS_RANGE,
		identity,
		sequence,
		2,
		1.65
	)


static func get_step_forward_variation(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_FORWARD_VARIATION_RANGE,
		identity,
		sequence,
		3,
		1.8
	)


static func get_step_max_lead_distance(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_MAX_LEAD_DISTANCE_RANGE,
		identity,
		sequence,
		10,
		1.75
	)


static func get_step_max_lead_distance_for_motion(
	horizontal_speed: float,
	identity: int,
	sequence: int
) -> float:
	return lerpf(
		get_step_max_lead_distance(identity, sequence),
		_sample_range(
			RUN_STEP_MAX_LEAD_DISTANCE_RANGE,
			identity,
			sequence,
			10,
			1.75
		),
		get_run_profile_weight(horizontal_speed)
	)


static func get_step_stance_scale(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_STANCE_SCALE_RANGE,
		identity,
		sequence,
		4,
		1.9
	)


static func get_step_stance_scale_for_motion(
	horizontal_speed: float,
	identity: int,
	sequence: int
) -> float:
	return lerpf(
		get_step_stance_scale(identity, sequence),
		_sample_range(
			RUN_STEP_STANCE_SCALE_RANGE,
			identity,
			sequence,
			4,
			1.9
		),
		get_run_profile_weight(horizontal_speed)
	)


static func get_step_lateral_variation(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_LATERAL_VARIATION_RANGE,
		identity,
		sequence,
		5,
		2.0
	)


static func get_step_arc_height(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_ARC_HEIGHT_RANGE,
		identity,
		sequence,
		6,
		1.75
	)


static func get_step_arc_height_for_motion(
	horizontal_speed: float,
	identity: int,
	sequence: int
) -> float:
	return lerpf(
		get_step_arc_height(identity, sequence),
		_sample_range(
			RUN_STEP_ARC_HEIGHT_RANGE,
			identity,
			sequence,
			6,
			1.75
		),
		get_run_profile_weight(horizontal_speed)
	)


static func get_step_duration_scale(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_DURATION_SCALE_RANGE,
		identity,
		sequence,
		7,
		1.8
	)


static func get_step_trigger_distance(identity: int, sequence: int) -> float:
	return _sample_range(
		STEP_TRIGGER_DISTANCE_RANGE,
		identity,
		sequence,
		8,
		1.7
	)


static func get_footstep_volume_db(identity: int, sequence: int) -> float:
	return _sample_range(
		FOOTSTEP_VOLUME_DB_RANGE,
		identity,
		sequence,
		9,
		1.9
	)


static func get_footstep_volume_db_for_motion(
	horizontal_speed: float,
	identity: int,
	sequence: int
) -> float:
	return lerpf(
		get_footstep_volume_db(identity, sequence),
		_sample_range(
			RUN_FOOTSTEP_VOLUME_DB_RANGE,
			identity,
			sequence,
			9,
			1.9
		),
		get_run_profile_weight(horizontal_speed)
	)


static func is_running_profile(horizontal_speed: float) -> bool:
	return maxf(horizontal_speed, 0.0) >= RUN_PROFILE_SPEED_THRESHOLD


static func get_run_profile_weight(horizontal_speed: float) -> float:
	return smoothstep(
		WALK_REFERENCE_SPEED,
		RUN_REFERENCE_SPEED,
		maxf(horizontal_speed, 0.0)
	)


static func _sample_range(
	authored_range: Vector2,
	identity: int,
	sequence: int,
	channel: int,
	curve_power: float
) -> float:
	return lerpf(
		authored_range.x,
		authored_range.y,
		_profile_unit(identity, sequence, channel, curve_power)
	)


static func _profile_unit(
	identity: int,
	sequence: int,
	channel: int,
	curve_power: float
) -> float:
	var identity_component := posmod(identity, HASH_ID_MODULUS)
	var sequence_component := posmod(sequence, HASH_ID_MODULUS)
	var value := posmod(
		identity_component * 13007
		+ sequence_component * 7919
		+ posmod(channel, 97) * 104723
		+ 48611,
		HASH_MODULUS
	)
	value = posmod(value * 48271 + 1, HASH_MODULUS)
	var unit := float(value) / float(HASH_MODULUS - 1)
	# Bias ordinary steps toward the middle while keeping occasional expressive edges. A signed
	# power curve is less machine-like than a flat uniform draw and remains exactly reproducible.
	var signed := unit * 2.0 - 1.0
	var shaped := signf(signed) * pow(
		absf(signed),
		maxf(curve_power, 1.0)
	)
	return shaped * 0.5 + 0.5


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
