extends DroneAIBehavior

const MODE_ROAM := &"roam"
const MODE_ORBIT := &"orbit"
const MODE_TRAIL := &"trail"
const IDLE_ACTIVITY := 0.05
const MOVING_ACTIVITY := 0.68
const SETTLED_ACTIVITY := 0.18
const MINIMUM_STOP_DISTANCE := 0.05
const DEFAULT_ORBIT_SPEED_DEGREES := 14.0
const DEFAULT_ORBIT_DIRECTION := 1.0
const DEFAULT_RESUME_SECONDS := 1.2
const MINIMUM_RESUME_SECONDS := 0.01
const DEFAULT_STOP_DISTANCE := 0.45
const MAX_VELOCITY_SAMPLE_INTERVAL := 0.5
const DEFAULT_VELOCITY_RESPONSE := 4.0
const MINIMUM_VELOCITY_RESPONSE := 0.1
const DEFAULT_RECOVERY_BOUNDARY_MARGIN := 0.3
const MINIMUM_RECOVERY_BOUNDARY_MARGIN := 0.05
const DEFAULT_RECOVERY_HEIGHT_MARGIN := 0.55
const MINIMUM_RECOVERY_HEIGHT_MARGIN := 0.1
const DEFAULT_RECOVERY_SETTLE_SPEED := 1.15
const MINIMUM_RECOVERY_SETTLE_SPEED := 0.05
const DEFAULT_RECOVERY_SETTLE_SECONDS := 0.45
const MINIMUM_DIRECTION_LENGTH_SQUARED := 0.001
const RECOVERY_MARGIN_EXTRA := 0.12
const MINIMUM_RECOVERY_MARGIN := 0.08
const DEFAULT_RING_ARC_STEP_DEGREES := 35.0
const MINIMUM_RING_ARC_STEP_DEGREES := 1.0
const SAFE_RING_ARC_SCALE := 0.9
const CHORD_CLEARANCE_MARGIN := 0.02
const DEFAULT_REPOSITION_INTERVAL_MIN := 3.0
const DEFAULT_REPOSITION_INTERVAL_MAX := 6.0
const MINIMUM_REPOSITION_INTERVAL := 0.1
const TRAIL_MOVEMENT_SPEED_SQUARED := 0.09
const DEFAULT_STATIONARY_ORBIT_SPEED_DEGREES := 4.0
const DEFAULT_TRAIL_WEAVE_DEGREES := 24.0
const DEFAULT_TRAIL_WEAVE_SPEED := 0.7

#######################################################
# Produces stable player-following intent with orbit assignment, recovery, obstacle awareness,
# and companion spacing.
#######################################################

func evaluate(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	memory: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	if not bool(context.get("follow_target_valid", false)):
		return {"activity": IDLE_ACTIVITY}

	var player_position: Vector3 = context.get(
		"follow_target_position",
		context.get("position", Vector3.ZERO)
	)
	var drone_position: Vector3 = context.get("position", Vector3.ZERO)
	var simulation_time := float(context.get("simulation_time", 0.0))
	var inner_radius := definition.get_follow_inner_radius()
	var outer_radius := definition.get_follow_outer_radius()
	var preferred_radius := definition.get_follow_preferred_radius()
	var height_offset := definition.get_follow_height_offset()
	var stop_distance := maxf(
		float(definition.get_parameter(
			&"movement_stop_distance",
			DEFAULT_STOP_DISTANCE
		)),
		MINIMUM_STOP_DISTANCE
	)
	var follow_mode := definition.get_follow_mode()
	var raw_player_velocity: Vector3 = context.get(
		"follow_target_velocity",
		Vector3.ZERO
	)
	raw_player_velocity.y = 0.0
	var player_velocity := _filter_follow_velocity(
		definition,
		memory,
		raw_player_velocity,
		simulation_time
	)

	# Follow targets are world-space offsets around the player's position.
	# Player facing is deliberately absent: looking at a drone cannot steer it.
	var horizontal_offset := drone_position - player_position
	horizontal_offset.y = 0.0
	var offset_state := _resolve_target_offset(
		definition,
		context,
		memory,
		rng,
		drone_position,
		player_position,
		horizontal_offset,
		player_velocity,
		inner_radius,
		outer_radius,
		preferred_radius,
		height_offset,
		stop_distance,
		follow_mode,
		simulation_time
	)
	var target_offset: Vector3 = offset_state["target_offset"]
	var recovering := bool(offset_state["recovering"])
	var keep_moving := bool(offset_state["keep_moving"])

	var movement_target := (
		player_position + target_offset
		+ Vector3.UP * height_offset
	)
	var current_radius := horizontal_offset.length()
	var outside_target_area := (
		current_radius < inner_radius
		or current_radius > outer_radius
	)
	var target_reached := (
		drone_position.distance_to(movement_target) <= stop_distance
	)
	var should_move := keep_moving or outside_target_area or not target_reached
	var movement_target_velocity := _calculate_target_velocity(
		definition,
		memory,
		player_velocity,
		target_offset,
		follow_mode,
		recovering,
		simulation_time
	)
	return {
		"activity": MOVING_ACTIVITY if should_move else SETTLED_ACTIVITY,
		"movement_active": true,
		"movement_target": movement_target,
		"movement_target_velocity": movement_target_velocity,
		"movement_stop_distance": stop_distance,
	}


func _resolve_target_offset(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	memory: Dictionary,
	rng: RandomNumberGenerator,
	drone_position: Vector3,
	player_position: Vector3,
	horizontal_offset: Vector3,
	player_velocity: Vector3,
	inner_radius: float,
	outer_radius: float,
	preferred_radius: float,
	height_offset: float,
	stop_distance: float,
	follow_mode: StringName,
	simulation_time: float
) -> Dictionary:
	var recovering := _update_recovery_state(
		definition,
		memory,
		horizontal_offset,
		absf(drone_position.y - (player_position.y + height_offset)),
		player_velocity,
		context.get("velocity", Vector3.ZERO),
		inner_radius,
		outer_radius,
		simulation_time
	)
	if recovering:
		return {
			"target_offset": _get_recovery_offset(
				definition,
				memory,
				horizontal_offset,
				inner_radius,
				outer_radius,
				preferred_radius,
				stop_distance
			),
			"recovering": true,
			"keep_moving": true,
		}

	var target_offset := _get_mode_offset(
		definition,
		context,
		memory,
		rng,
		drone_position,
		player_position,
		player_velocity,
		inner_radius,
		outer_radius,
		preferred_radius,
		follow_mode,
		simulation_time
	)
	return {
		"target_offset": _constrain_offset_to_ring_path(
			definition,
			horizontal_offset,
			target_offset,
			inner_radius,
			outer_radius
		),
		"recovering": false,
		"keep_moving": follow_mode in [MODE_ORBIT, MODE_TRAIL],
	}


func _get_mode_offset(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	memory: Dictionary,
	rng: RandomNumberGenerator,
	drone_position: Vector3,
	player_position: Vector3,
	player_velocity: Vector3,
	inner_radius: float,
	outer_radius: float,
	preferred_radius: float,
	follow_mode: StringName,
	simulation_time: float
) -> Vector3:
	match follow_mode:
		MODE_ORBIT:
			return _get_orbit_offset(
				definition,
				memory,
				drone_position - player_position,
				preferred_radius,
				simulation_time,
				rng
			)
		MODE_TRAIL:
			var trail_context := context.duplicate()
			trail_context["follow_target_velocity"] = player_velocity
			return _get_trailing_offset(
				definition,
				trail_context,
				memory,
				preferred_radius,
				simulation_time,
				rng
			)
		_:
			return _get_roaming_offset(
				definition,
				memory,
				inner_radius,
				outer_radius,
				simulation_time,
				rng
			)


func _calculate_target_velocity(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	player_velocity: Vector3,
	target_offset: Vector3,
	follow_mode: StringName,
	recovering: bool,
	simulation_time: float
) -> Vector3:
	if follow_mode != MODE_ORBIT or recovering:
		return player_velocity

	var orbit_speed := deg_to_rad(float(definition.get_parameter(
		&"orbit_speed_degrees",
		DEFAULT_ORBIT_SPEED_DEGREES
	)))
	var orbit_direction := signf(float(definition.get_parameter(
		&"orbit_direction",
		DEFAULT_ORBIT_DIRECTION
	)))
	if is_zero_approx(orbit_direction):
		orbit_direction = DEFAULT_ORBIT_DIRECTION
	var resume_seconds := maxf(float(definition.get_parameter(
		&"behavior_resume_seconds",
		DEFAULT_RESUME_SECONDS
	)), MINIMUM_RESUME_SECONDS)
	var resume_blend := clampf(
		(simulation_time - float(memory.get(
			"behavior_resume_time",
			simulation_time - resume_seconds
		))) / resume_seconds,
		0.0,
		1.0
	)
	return player_velocity + Vector3(
		-target_offset.z,
		0.0,
		target_offset.x
	) * orbit_speed * orbit_direction * resume_blend


func _filter_follow_velocity(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	raw_velocity: Vector3,
	simulation_time: float
) -> Vector3:
	var previous: Vector3 = memory.get(
		"filtered_follow_velocity",
		raw_velocity
	)
	var previous_time := float(memory.get(
		"follow_velocity_sample_time",
		simulation_time
	))
	var elapsed := clampf(
		simulation_time - previous_time,
		0.0,
		MAX_VELOCITY_SAMPLE_INTERVAL
	)
	var response := maxf(float(definition.get_parameter(
		&"follow_velocity_response",
		DEFAULT_VELOCITY_RESPONSE
	)), MINIMUM_VELOCITY_RESPONSE)
	var weight := 1.0 - exp(-response * elapsed)
	var filtered := previous.lerp(raw_velocity, weight)
	memory["filtered_follow_velocity"] = filtered
	memory["follow_velocity_sample_time"] = simulation_time
	return filtered


func _update_recovery_state(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	current_offset: Vector3,
	height_error: float,
	player_velocity: Vector3,
	drone_velocity_value: Variant,
	inner_radius: float,
	outer_radius: float,
	simulation_time: float
) -> bool:
	var radius := current_offset.length()
	var boundary_margin := maxf(float(definition.get_parameter(
		&"recovery_boundary_margin",
		DEFAULT_RECOVERY_BOUNDARY_MARGIN
	)), MINIMUM_RECOVERY_BOUNDARY_MARGIN)
	var safely_inside := (
		radius >= inner_radius + boundary_margin
		and radius <= outer_radius - boundary_margin
		and height_error <= maxf(float(definition.get_parameter(
			&"recovery_height_margin",
			DEFAULT_RECOVERY_HEIGHT_MARGIN
		)), MINIMUM_RECOVERY_HEIGHT_MARGIN)
	)
	var recovering := bool(memory.get("recovering", not safely_inside))
	if not safely_inside:
		if not recovering:
			memory.erase("recovery_direction")
		recovering = true
		memory["recovery_settle_started"] = -1.0

	if recovering and safely_inside:
		var drone_velocity: Vector3 = drone_velocity_value
		drone_velocity.y = 0.0
		var relative_speed := (drone_velocity - player_velocity).length()
		var settle_speed := maxf(float(definition.get_parameter(
			&"recovery_settle_speed",
			DEFAULT_RECOVERY_SETTLE_SPEED
		)), MINIMUM_RECOVERY_SETTLE_SPEED)
		if relative_speed <= settle_speed:
			var settle_started := float(memory.get(
				"recovery_settle_started",
				-1.0
			))
			if settle_started < 0.0:
				settle_started = simulation_time
				memory["recovery_settle_started"] = settle_started
			var settle_seconds := maxf(float(definition.get_parameter(
				&"recovery_settle_seconds",
				DEFAULT_RECOVERY_SETTLE_SECONDS
			)), 0.0)
			if simulation_time - settle_started >= settle_seconds:
				recovering = false
				memory.erase("recovery_direction")
				_reanchor_behavior_after_recovery(
					definition,
					memory,
					current_offset,
					simulation_time
				)
		else:
			memory["recovery_settle_started"] = -1.0

	memory["recovering"] = recovering
	return recovering


func _get_recovery_offset(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	current_offset: Vector3,
	inner_radius: float,
	outer_radius: float,
	preferred_radius: float,
	stop_distance: float
) -> Vector3:
	var direction: Vector3 = memory.get(
		"recovery_direction",
		Vector3.ZERO
	)
	# Choose the nearest side of the ring once per recovery. Recomputing this
	# direction every chip tick made the destination walk around the player as
	# the drone approached, creating the large curved swings seen in play.
	if direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		direction = current_offset.normalized()
	if direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		var remembered: Vector3 = memory.get(
			"last_safe_direction",
			Vector3.RIGHT
		)
		direction = remembered.normalized()
	if direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		direction = Vector3.RIGHT
	direction.y = 0.0
	direction = direction.normalized()
	memory["recovery_direction"] = direction
	memory["last_safe_direction"] = direction

	var boundary_margin := maxf(float(definition.get_parameter(
		&"recovery_boundary_margin",
		DEFAULT_RECOVERY_BOUNDARY_MARGIN
	)), MINIMUM_RECOVERY_BOUNDARY_MARGIN)
	var maximum_margin := maxf(
		(outer_radius - inner_radius) * 0.5
		- MINIMUM_RECOVERY_BOUNDARY_MARGIN,
		MINIMUM_RECOVERY_BOUNDARY_MARGIN
	)
	var margin := clampf(
		boundary_margin + stop_distance + RECOVERY_MARGIN_EXTRA,
		MINIMUM_RECOVERY_MARGIN,
		maximum_margin
	)
	var radius := preferred_radius
	var current_radius := current_offset.length()
	if current_radius > outer_radius:
		radius = outer_radius - margin
	elif current_radius < inner_radius:
		radius = inner_radius + margin
	radius = clampf(radius, inner_radius + margin, outer_radius - margin)
	return direction * radius


func _reanchor_behavior_after_recovery(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	current_offset: Vector3,
	simulation_time: float
) -> void:
	var planar_offset := current_offset
	planar_offset.y = 0.0
	if (
		planar_offset.length_squared()
		<= MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		return
	var angle := atan2(planar_offset.z, planar_offset.x)
	var mode := definition.get_follow_mode()
	match mode:
		MODE_ORBIT:
			memory["orbit_start_angle"] = angle
			memory["orbit_start_time"] = simulation_time
			memory["behavior_resume_time"] = simulation_time
		MODE_TRAIL:
			memory["stationary_angle"] = angle
			memory["behavior_resume_time"] = simulation_time
		_:
			memory["target_offset"] = planar_offset
			memory["next_reposition_time"] = (
				simulation_time
				+ maxf(float(definition.get_parameter(
					&"recovery_behavior_hold_seconds",
					1.2
				)), 0.0)
			)


func _constrain_offset_to_ring_path(
	definition: DroneAIChipDefinition,
	current_offset: Vector3,
	desired_offset: Vector3,
	inner_radius: float,
	outer_radius: float
) -> Vector3:
	var current_radius := current_offset.length()
	var desired_radius := desired_offset.length()
	if (
		current_radius < inner_radius
		or current_radius > outer_radius
		or desired_radius <= MINIMUM_DIRECTION_LENGTH_SQUARED
		or inner_radius <= MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		return desired_offset

	var current_angle := atan2(current_offset.z, current_offset.x)
	var desired_angle := atan2(desired_offset.z, desired_offset.x)
	var angle_delta := wrapf(desired_angle - current_angle, -PI, PI)
	if absf(angle_delta) <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return desired_offset

	var requested_step := deg_to_rad(maxf(float(definition.get_parameter(
		&"maximum_ring_arc_step_degrees",
		DEFAULT_RING_ARC_STEP_DEGREES
	)), MINIMUM_RING_ARC_STEP_DEGREES))
	var maximum_safe_step := (
		acos(clampf(
			inner_radius / maxf(
				outer_radius,
				MINIMUM_DIRECTION_LENGTH_SQUARED
			),
			0.0,
			1.0
		))
		* SAFE_RING_ARC_SCALE
	)
	var angle_step := minf(requested_step, maximum_safe_step)
	var next_angle := desired_angle
	if absf(angle_delta) > angle_step:
		next_angle = current_angle + signf(angle_delta) * angle_step
	var applied_angle_delta := wrapf(
		next_angle - current_angle,
		-PI,
		PI
	)

	# Raising the intermediate radius keeps the straight flight chord from
	# cutting through the empty center of the follow ring.
	var chord_safe_radius := (
		inner_radius
		/ maxf(cos(absf(applied_angle_delta)), MINIMUM_RESUME_SECONDS)
		+ CHORD_CLEARANCE_MARGIN
	)
	var next_radius := clampf(
		maxf(desired_radius, chord_safe_radius),
		inner_radius,
		outer_radius
	)
	return Vector3(
		cos(next_angle) * next_radius,
		0.0,
		sin(next_angle) * next_radius
	)


func _get_roaming_offset(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	inner_radius: float,
	outer_radius: float,
	simulation_time: float,
	rng: RandomNumberGenerator
) -> Vector3:
	var next_reposition_time := float(
		memory.get("next_reposition_time", -1.0)
	)
	if not memory.has("target_offset") or simulation_time >= next_reposition_time:
		var radius := sqrt(rng.randf_range(
			inner_radius * inner_radius,
			outer_radius * outer_radius
		))
		var angle := rng.randf_range(-PI, PI)
		memory["target_offset"] = Vector3(
			cos(angle) * radius,
			0.0,
			sin(angle) * radius
		)
		var minimum_interval := maxf(float(definition.get_parameter(
			&"reposition_interval_min",
			DEFAULT_REPOSITION_INTERVAL_MIN
		)), MINIMUM_REPOSITION_INTERVAL)
		var maximum_interval := maxf(float(definition.get_parameter(
			&"reposition_interval_max",
			DEFAULT_REPOSITION_INTERVAL_MAX
		)), minimum_interval)
		memory["next_reposition_time"] = (
			simulation_time
			+ rng.randf_range(minimum_interval, maximum_interval)
		)
	var target_offset: Vector3 = memory.get(
		"target_offset",
		Vector3.ZERO
	)
	return target_offset


func _get_orbit_offset(
	definition: DroneAIChipDefinition,
	memory: Dictionary,
	current_offset: Vector3,
	preferred_radius: float,
	simulation_time: float,
	rng: RandomNumberGenerator
) -> Vector3:
	if not memory.has("orbit_start_angle"):
		var planar_offset := current_offset
		planar_offset.y = 0.0
		memory["orbit_start_angle"] = (
			atan2(planar_offset.z, planar_offset.x)
			if planar_offset.length_squared()
			> MINIMUM_DIRECTION_LENGTH_SQUARED
			else rng.randf_range(-PI, PI)
		)
		memory["orbit_start_time"] = simulation_time

	var orbit_speed := deg_to_rad(float(definition.get_parameter(
		&"orbit_speed_degrees",
		DEFAULT_ORBIT_SPEED_DEGREES
	)))
	var orbit_direction := signf(float(definition.get_parameter(
		&"orbit_direction",
		DEFAULT_ORBIT_DIRECTION
	)))
	if is_zero_approx(orbit_direction):
		orbit_direction = DEFAULT_ORBIT_DIRECTION
	var elapsed := simulation_time - float(memory.get(
		"orbit_start_time",
		simulation_time
	))
	var resume_seconds := maxf(float(definition.get_parameter(
		&"behavior_resume_seconds",
		DEFAULT_RESUME_SECONDS
	)), MINIMUM_RESUME_SECONDS)
	var ramp_elapsed := maxf(
		simulation_time - float(memory.get(
			"behavior_resume_time",
			simulation_time - resume_seconds
		)),
		0.0
	)
	# Integrate a linear angular-speed ramp so the target position and its
	# feed-forward velocity describe the same smooth orbit after recovery.
	var integrated_elapsed := (
		ramp_elapsed * ramp_elapsed / (2.0 * resume_seconds)
		if ramp_elapsed < resume_seconds
		else ramp_elapsed - resume_seconds * 0.5
	)
	if not memory.has("behavior_resume_time"):
		integrated_elapsed = elapsed
	var angle := (
		float(memory.get("orbit_start_angle", 0.0))
		+ integrated_elapsed * orbit_speed * orbit_direction
	)
	return Vector3(
		cos(angle) * preferred_radius,
		0.0,
		sin(angle) * preferred_radius
	)


func _get_trailing_offset(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	memory: Dictionary,
	preferred_radius: float,
	simulation_time: float,
	rng: RandomNumberGenerator
) -> Vector3:
	if not memory.has("trail_phase"):
		memory["trail_phase"] = rng.randf_range(-PI, PI)
		memory["stationary_angle"] = rng.randf_range(-PI, PI)

	var player_velocity: Vector3 = context.get(
		"follow_target_velocity",
		Vector3.ZERO
	)
	player_velocity.y = 0.0
	var base_angle := float(memory.get("stationary_angle", 0.0))
	if player_velocity.length_squared() > TRAIL_MOVEMENT_SPEED_SQUARED:
		var behind: Vector3 = -player_velocity.normalized()
		base_angle = atan2(behind.z, behind.x)
		memory["stationary_angle"] = base_angle
	else:
		var stationary_speed := deg_to_rad(float(definition.get_parameter(
			&"stationary_orbit_speed_degrees",
			DEFAULT_STATIONARY_ORBIT_SPEED_DEGREES
		)))
		base_angle += stationary_speed * float(definition.get_parameter(
			&"response_time",
			definition.response_time
		))
		memory["stationary_angle"] = base_angle

	var weave_amount := deg_to_rad(float(definition.get_parameter(
		&"trail_weave_degrees",
		DEFAULT_TRAIL_WEAVE_DEGREES
	)))
	var weave_speed := float(definition.get_parameter(
		&"trail_weave_speed",
		DEFAULT_TRAIL_WEAVE_SPEED
	))
	var angle := (
		base_angle
		+ sin(simulation_time * weave_speed + float(memory["trail_phase"]))
		* weave_amount
	)
	return Vector3(
		cos(angle) * preferred_radius,
		0.0,
		sin(angle) * preferred_radius
	)
