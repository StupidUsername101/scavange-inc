class_name FluteRunnerBehaviorController
extends RefCounted

## Allocation-free state machine for the Flotenlaufer. Sensing and collision queries stay in the
## authoritative body; this controller turns sanitized observations into a compact movement intent.

enum State {
	LOITER,
	CURIOUS,
	PURSUE,
	CHASE,
	FUMBLE,
	SEARCH,
	STUNNED,
}

const EPSILON := 0.000001

var state := State.LOITER
var state_elapsed := 0.0
var target_id := -1
var desired_velocity := Vector3.ZERO
var desired_forward := Vector3.FORWARD
var last_known_position := Vector3.ZERO
var has_last_known_position := false
var visible_memory_remaining := 0.0
var heard_memory_remaining := 0.0
var tackle_cooldown_remaining := 0.0
var fumble_direction_sign := 1.0
var _stuck_elapsed := 0.0
var _previous_host_position := Vector3.ZERO
var _position_initialized := false


func reset(host_position: Vector3) -> void:
	state = State.LOITER
	state_elapsed = 0.0
	target_id = -1
	desired_velocity = Vector3.ZERO
	desired_forward = Vector3.FORWARD
	last_known_position = host_position
	has_last_known_position = false
	visible_memory_remaining = 0.0
	heard_memory_remaining = 0.0
	tackle_cooldown_remaining = 0.0
	_stuck_elapsed = 0.0
	_previous_host_position = host_position
	_position_initialized = true


func update(
	delta: float,
	definition: FluteRunnerDefinition,
	host_position: Vector3,
	host_forward: Vector3,
	roam_center: Vector3,
	observed_target_id: int,
	target_position: Vector3,
	target_velocity: Vector3,
	target_visible: bool,
	target_audible: bool,
	target_valid: bool
) -> void:
	var safe_delta := maxf(delta, 0.0)
	state_elapsed += safe_delta
	tackle_cooldown_remaining = maxf(
		tackle_cooldown_remaining - safe_delta,
		0.0
	)
	visible_memory_remaining = maxf(visible_memory_remaining - safe_delta, 0.0)
	heard_memory_remaining = maxf(heard_memory_remaining - safe_delta, 0.0)

	if target_valid:
		target_id = observed_target_id
		if target_visible:
			last_known_position = target_position
			has_last_known_position = true
			visible_memory_remaining = definition.visible_memory_seconds
		elif target_audible:
			# Hearing is deliberately less exact: pursue the current vicinity rather than applying
			# an aim-lock to a player hidden behind geometry.
			last_known_position = target_position - target_velocity * 0.16
			has_last_known_position = true
			heard_memory_remaining = definition.heard_memory_seconds
	else:
		target_id = -1

	_update_stuck_state(safe_delta, definition, host_position)
	if state == State.FUMBLE:
		_update_fumble(definition, host_forward)
		if state_elapsed >= definition.fumble_seconds:
			_transition(State.SEARCH if has_last_known_position else State.LOITER)
		return

	var has_fresh_memory := (
		has_last_known_position
		and (visible_memory_remaining > 0.0 or heard_memory_remaining > 0.0)
	)
	if target_visible and target_valid:
		var distance := _horizontal_distance(host_position, target_position)
		_transition_if_needed(
			State.CHASE if distance <= definition.chase_distance else State.PURSUE
		)
		_move_toward(
			target_position,
			host_position,
			definition.chase_speed if state == State.CHASE else definition.pursuit_speed,
			definition.preferred_distance
		)
		return
	if target_audible and target_valid:
		_transition_if_needed(State.CURIOUS)
		_move_toward(
			last_known_position,
			host_position,
			definition.curious_speed,
			definition.preferred_distance * 1.25
		)
		return
	if has_fresh_memory:
		_transition_if_needed(State.SEARCH)
		_move_toward(
			last_known_position,
			host_position,
			definition.pursuit_speed * 0.78,
			0.55
		)
		return
	if state == State.SEARCH and state_elapsed < definition.search_seconds:
		_update_search(definition, host_position)
		return

	has_last_known_position = false
	_transition_if_needed(State.LOITER)
	_update_loiter(definition, host_position, roam_center)


func report_steering_blocked(blocked: bool, delta: float) -> void:
	if state == State.FUMBLE:
		return
	if blocked and desired_velocity.length_squared() > 0.25:
		_stuck_elapsed += maxf(delta, 0.0)
	else:
		_stuck_elapsed = maxf(_stuck_elapsed - maxf(delta, 0.0) * 1.8, 0.0)


func can_tackle(relative_speed: float, facing_dot: float, definition: FluteRunnerDefinition) -> bool:
	return (
		definition != null
		and tackle_cooldown_remaining <= 0.0
		and relative_speed >= definition.tackle_minimum_speed
		and facing_dot >= definition.tackle_minimum_facing_dot
		and state == State.CHASE
	)


func consume_tackle(definition: FluteRunnerDefinition) -> void:
	tackle_cooldown_remaining = (
		definition.tackle_cooldown_seconds if definition != null else 1.0
	)
	_transition(State.FUMBLE)


func state_name() -> StringName:
	match state:
		State.CURIOUS:
			return &"curious"
		State.PURSUE:
			return &"pursue"
		State.CHASE:
			return &"chase"
		State.FUMBLE:
			return &"fumble"
		State.SEARCH:
			return &"search"
		State.STUNNED:
			return &"stunned"
	return &"loiter"


func _update_stuck_state(
	delta: float,
	definition: FluteRunnerDefinition,
	host_position: Vector3
) -> void:
	if not _position_initialized:
		_previous_host_position = host_position
		_position_initialized = true
		return
	var moved := _horizontal_distance(_previous_host_position, host_position)
	_previous_host_position = host_position
	if desired_velocity.length_squared() > 1.0 and moved < maxf(delta * 0.18, 0.002):
		_stuck_elapsed += delta
	else:
		_stuck_elapsed = maxf(_stuck_elapsed - delta * 1.4, 0.0)
	if _stuck_elapsed < definition.stuck_seconds or state == State.FUMBLE:
		return
	_stuck_elapsed = 0.0
	fumble_direction_sign = -fumble_direction_sign
	_transition(State.FUMBLE)


func _update_fumble(definition: FluteRunnerDefinition, host_forward: Vector3) -> void:
	var forward := Vector3(host_forward.x, 0.0, host_forward.z)
	if forward.length_squared() <= EPSILON:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * fumble_direction_sign
	desired_forward = (side - forward * 0.38).normalized()
	desired_velocity = desired_forward * definition.curious_speed * 0.82


func _update_search(
	definition: FluteRunnerDefinition,
	host_position: Vector3
) -> void:
	if not has_last_known_position:
		desired_velocity = Vector3.ZERO
		return
	var orbit_phase := state_elapsed * 1.35 + float(posmod(target_id, 7)) * 0.71
	var orbit := Vector3(cos(orbit_phase), 0.0, sin(orbit_phase)) * 1.8
	_move_toward(
		last_known_position + orbit,
		host_position,
		definition.curious_speed,
		0.35
	)


func _update_loiter(
	definition: FluteRunnerDefinition,
	host_position: Vector3,
	roam_center: Vector3
) -> void:
	var phase := state_elapsed * 0.29
	var radius := minf(definition.roam_radius * 0.22, 5.5)
	var destination := roam_center + Vector3(
		cos(phase * 0.83) * radius,
		0.0,
		sin(phase * 1.17) * radius
	)
	_move_toward(destination, host_position, definition.curious_speed * 0.48, 0.5)


func _move_toward(
	destination: Vector3,
	host_position: Vector3,
	speed: float,
	stop_distance: float
) -> void:
	var offset := destination - host_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= maxf(stop_distance, 0.0) or distance <= EPSILON:
		desired_velocity = Vector3.ZERO
		return
	desired_forward = offset / distance
	desired_velocity = desired_forward * maxf(speed, 0.0)


func _transition_if_needed(next_state: int) -> void:
	if state != next_state:
		_transition(next_state)


func _transition(next_state: int) -> void:
	state = clampi(next_state, State.LOITER, State.STUNNED)
	state_elapsed = 0.0


static func _horizontal_distance(left: Vector3, right: Vector3) -> float:
	var delta := right - left
	delta.y = 0.0
	return delta.length()
