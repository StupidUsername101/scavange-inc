class_name DroneFlightController
extends RefCounted

const MINIMUM_GROUND_CLEARANCE := 2.8
const CRITICAL_GROUND_CLEARANCE := 0.7
const MAXIMUM_UPRIGHT_DIVISOR := 0.42
const GROUND_SAFETY_EPSILON := 0.01
const ACCELERATION_JERK_MULTIPLIER := 4.0
const MINIMUM_ACCELERATION_JERK := 4.0
const ALTITUDE_INTEGRAL_LEAK_RATE := 0.55
const ALTITUDE_INTEGRAL_LIMIT := 2.2
const ALTITUDE_INTEGRAL_GAIN := 0.62
const GROUND_ESCAPE_ACCELERATION_RATIO := 0.72
const MINIMUM_SUPPORT_GRAVITY_RATIO := 0.18
const NEAR_GROUND_TILT_RATIO := 0.22
const GROUND_UPRIGHT_OVERRIDE_DOT := 0.86
const MINIMUM_COLLECTIVE_UPRIGHTNESS := 0.08
const INVERTED_COLLECTIVE_RATIO := 0.34
const YAW_DAMPING_RATIO := 0.18
const EMERGENCY_UPRIGHT_DOT := 0.35
const GROUND_EMERGENCY_UPRIGHT_DOT := 0.72
const EMERGENCY_DAMPING_RATIO := 0.32

#######################################################
# Converts desired drone motion into stabilized body torque and per-rotor thrust while
# respecting power and actuator limits.
#######################################################

var host: RigidBody3D
var hold_position := Vector3.ZERO
var hold_initialized := false
var movement_was_active := false
var emergency_torque_world := Vector3.ZERO
var smoothed_horizontal_acceleration := Vector3.ZERO
var altitude_velocity_integral := 0.0


func _init(owner_drone: RigidBody3D) -> void:
	host = owner_drone


func reset_hold(position: Vector3) -> void:
	hold_position = position
	hold_initialized = true


func clear() -> void:
	hold_initialized = false
	movement_was_active = false
	emergency_torque_world = Vector3.ZERO
	smoothed_horizontal_acceleration = Vector3.ZERO
	altitude_velocity_integral = 0.0


func calculate_rotor_thrust_targets(
	core: DroneCoreDefinition,
	loadout: DroneLoadout,
	propeller_slots: Array[DronePropellerSlot],
	intent: Dictionary,
	ground_probe: Dictionary,
	air_environment: AirEnvironment,
	delta: float
) -> Array[float]:
	var result := _create_zero_thrust_targets(propeller_slots.size())
	emergency_torque_world = Vector3.ZERO
	if (
		core == null
		or loadout == null
		or air_environment == null
		or propeller_slots.is_empty()
	):
		return result

	if not hold_initialized:
		reset_hold(host.global_position)

	var target_state := _resolve_target_state(intent, ground_probe)
	var target_position: Vector3 = target_state["position"]
	var ground_clearance := float(target_state["ground_clearance"])
	var acceleration_state := _calculate_desired_acceleration(
		core,
		intent,
		target_position,
		ground_clearance,
		delta
	)
	var desired_horizontal_acceleration: Vector3 = (
		acceleration_state["horizontal"]
	)
	var vertical_support_acceleration := float(
		acceleration_state["vertical_support"]
	)
	var gravity := float(acceleration_state["gravity"])
	var attitude_state := _calculate_attitude_state(
		core,
		desired_horizontal_acceleration,
		vertical_support_acceleration,
		gravity,
		ground_clearance
	)
	var desired_torque_local: Vector3 = attitude_state["torque_local"]

	result = _allocate_thrust(
		float(attitude_state["collective_thrust"]),
		desired_torque_local,
		core,
		loadout,
		propeller_slots,
		air_environment
	)
	_update_emergency_torque(attitude_state, ground_clearance, core)
	return result


func _create_zero_thrust_targets(slot_count: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(slot_count)
	result.fill(0.0)
	return result


func _resolve_target_state(
	intent: Dictionary,
	ground_probe: Dictionary
) -> Dictionary:
	var movement_active := bool(intent.get("movement_active", false))
	var target_position := hold_position
	if movement_active:
		movement_was_active = true
		target_position = intent.get("movement_target", hold_position)
	elif movement_was_active:
		# A lost navigation source must hand hover a fresh hold point.
		reset_hold(host.global_position)
		movement_was_active = false
		target_position = hold_position

	var ground_clearance := INF
	if not ground_probe.is_empty():
		var ground_height := float(ground_probe.get(
			"ground_height",
			host.global_position.y - MINIMUM_GROUND_CLEARANCE
		))
		ground_clearance = maxf(host.global_position.y - ground_height, 0.0)
		target_position.y = maxf(
			target_position.y,
			ground_height + MINIMUM_GROUND_CLEARANCE
		)
	return {
		"position": target_position,
		"ground_clearance": ground_clearance,
	}


func _calculate_desired_acceleration(
	core: DroneCoreDefinition,
	intent: Dictionary,
	target_position: Vector3,
	ground_clearance: float,
	delta: float
) -> Dictionary:
	var horizontal_velocity := Vector3(
		host.linear_velocity.x,
		0.0,
		host.linear_velocity.z
	)
	var desired_horizontal_velocity := calculate_preferred_horizontal_velocity(
		core,
		intent
	)
	var horizontal_acceleration_limit := get_navigation_acceleration_limit(
		core,
		intent
	)
	var desired_horizontal_acceleration = (
		(desired_horizontal_velocity - horizontal_velocity)
		* core.ai_horizontal_velocity_gain
	).limit_length(horizontal_acceleration_limit)
	var ground_safety_scale := _get_ground_safety_scale(ground_clearance)
	desired_horizontal_acceleration *= ground_safety_scale
	desired_horizontal_acceleration = _smooth_horizontal_acceleration(
		desired_horizontal_acceleration,
		horizontal_acceleration_limit,
		intent,
		delta
	)

	var vertical_support := _calculate_vertical_support_acceleration(
		core,
		target_position.y - host.global_position.y,
		ground_clearance,
		delta
	)
	desired_horizontal_acceleration = _limit_acceleration_for_tilt(
		desired_horizontal_acceleration,
		vertical_support["acceleration"],
		core,
		ground_clearance,
		ground_safety_scale
	)
	return {
		"horizontal": desired_horizontal_acceleration,
		"vertical_support": vertical_support["acceleration"],
		"gravity": vertical_support["gravity"],
	}


func _get_ground_safety_scale(ground_clearance: float) -> float:
	var ground_safety_scale := 1.0
	if ground_clearance < MINIMUM_GROUND_CLEARANCE:
		ground_safety_scale = clampf(
			(ground_clearance - CRITICAL_GROUND_CLEARANCE)
			/ maxf(
				MINIMUM_GROUND_CLEARANCE - CRITICAL_GROUND_CLEARANCE,
				GROUND_SAFETY_EPSILON
			),
			0.0,
			1.0
		)
	return ground_safety_scale


func _smooth_horizontal_acceleration(
	desired_acceleration: Vector3,
	acceleration_limit: float,
	intent: Dictionary,
	delta: float
) -> Vector3:
	# Limit requested jerk; the body and installed hardware still determine
	# the actual acceleration envelope.
	var acceleration_jerk := maxf(
		acceleration_limit
		* ACCELERATION_JERK_MULTIPLIER
		* DroneMovementPlanner.get_jerk_scale(intent),
		MINIMUM_ACCELERATION_JERK
	)
	smoothed_horizontal_acceleration = (
		smoothed_horizontal_acceleration.move_toward(
			desired_acceleration,
			acceleration_jerk * maxf(delta, 0.0)
		)
	)
	return smoothed_horizontal_acceleration


func _calculate_vertical_support_acceleration(
	core: DroneCoreDefinition,
	vertical_position_error: float,
	ground_clearance: float,
	delta: float
) -> Dictionary:
	var desired_vertical_velocity := clampf(
		vertical_position_error * core.ai_altitude_position_gain,
		-core.ai_max_vertical_speed,
		core.ai_max_vertical_speed
	)
	var vertical_velocity_error := (
		desired_vertical_velocity - host.linear_velocity.y
	)
	# A small leaky integral rejects steady lift-model, payload, and power-bus
	# errors. It is deliberately bounded and decays quickly enough that it
	# cannot wind up into a launch after a brownout or ground contact.
	altitude_velocity_integral *= exp(
		-ALTITUDE_INTEGRAL_LEAK_RATE * maxf(delta, 0.0)
	)
	altitude_velocity_integral = clampf(
		altitude_velocity_integral + vertical_velocity_error * delta,
		-ALTITUDE_INTEGRAL_LIMIT,
		ALTITUDE_INTEGRAL_LIMIT
	)
	var desired_vertical_acceleration := clampf(
		vertical_velocity_error * core.ai_altitude_velocity_gain
		+ altitude_velocity_integral * ALTITUDE_INTEGRAL_GAIN,
		-core.ai_max_vertical_acceleration,
		core.ai_max_vertical_acceleration
	)
	if ground_clearance < CRITICAL_GROUND_CLEARANCE:
		desired_vertical_acceleration = maxf(
			desired_vertical_acceleration,
			core.ai_max_vertical_acceleration
			* GROUND_ESCAPE_ACCELERATION_RATIO
		)

	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var vertical_support_acceleration := maxf(
		gravity + desired_vertical_acceleration,
		gravity * MINIMUM_SUPPORT_GRAVITY_RATIO
	)
	return {
		"acceleration": vertical_support_acceleration,
		"gravity": gravity,
	}


func _limit_acceleration_for_tilt(
	horizontal_acceleration: Vector3,
	vertical_support_acceleration: float,
	core: DroneCoreDefinition,
	ground_clearance: float,
	ground_safety_scale: float
) -> Vector3:
	var maximum_tilt := deg_to_rad(core.ai_max_tilt_degrees)
	if ground_clearance < MINIMUM_GROUND_CLEARANCE:
		maximum_tilt *= lerpf(
			NEAR_GROUND_TILT_RATIO,
			1.0,
			ground_safety_scale
		)
	var tilt_acceleration_limit := (
		tan(maximum_tilt) * vertical_support_acceleration
	)
	return horizontal_acceleration.limit_length(
		maxf(tilt_acceleration_limit, 0.0)
	)


func _calculate_attitude_state(
	core: DroneCoreDefinition,
	desired_horizontal_acceleration: Vector3,
	vertical_support_acceleration: float,
	gravity: float,
	ground_clearance: float
) -> Dictionary:
	var desired_force_direction := Vector3(
		desired_horizontal_acceleration.x,
		vertical_support_acceleration,
		desired_horizontal_acceleration.z
	)
	var desired_up := desired_force_direction.normalized()
	var model_basis_world: Basis = host.model_orientation_basis_world()
	var current_up: Vector3 = model_basis_world.y.normalized()
	var uprightness: float = current_up.dot(Vector3.UP)
	if (
		ground_clearance < CRITICAL_GROUND_CLEARANCE
		and uprightness < GROUND_UPRIGHT_OVERRIDE_DOT
	):
		desired_up = Vector3.UP

	var collective_thrust := 0.0
	if uprightness > MINIMUM_COLLECTIVE_UPRIGHTNESS:
		collective_thrust = (
			host.mass * vertical_support_acceleration
			/ maxf(uprightness, MAXIMUM_UPRIGHT_DIVISOR)
		)
	else:
		# Keep enough rotor authority to right the frame without driving an
		# inverted drone harder into the floor.
		collective_thrust = host.mass * gravity * INVERTED_COLLECTIVE_RATIO

	var attitude_error_world := _get_rotation_error(current_up, desired_up)
	var tilt_angular_velocity := (
		host.angular_velocity
		- desired_up * host.angular_velocity.dot(desired_up)
	)
	var desired_angular_acceleration_world = (
		attitude_error_world * core.ai_attitude_response
		- tilt_angular_velocity * core.ai_angular_velocity_damping
		- desired_up
		* host.angular_velocity.dot(desired_up)
		* core.ai_angular_velocity_damping
		* YAW_DAMPING_RATIO
	)
	var desired_angular_acceleration_local = (
		host.global_basis.inverse() * desired_angular_acceleration_world
	)
	var desired_torque_local := Vector3(
		desired_angular_acceleration_local.x * host.inertia.x,
		desired_angular_acceleration_local.y * host.inertia.y,
		desired_angular_acceleration_local.z * host.inertia.z
	)
	return {
		"collective_thrust": collective_thrust,
		"torque_local": desired_torque_local,
		"attitude_error_world": attitude_error_world,
		"tilt_angular_velocity": tilt_angular_velocity,
		"uprightness": uprightness,
	}


func _update_emergency_torque(
	attitude_state: Dictionary,
	ground_clearance: float,
	core: DroneCoreDefinition
) -> void:
	var uprightness := float(attitude_state["uprightness"])
	if (
		uprightness < EMERGENCY_UPRIGHT_DOT
		or (
			ground_clearance < CRITICAL_GROUND_CLEARANCE
			and uprightness < GROUND_EMERGENCY_UPRIGHT_DOT
		)
	):
		var attitude_error_world: Vector3 = (
			attitude_state["attitude_error_world"]
		)
		var tilt_angular_velocity: Vector3 = (
			attitude_state["tilt_angular_velocity"]
		)
		emergency_torque_world = (
			attitude_error_world * core.ai_emergency_upright_torque
			- tilt_angular_velocity
			* core.ai_emergency_upright_torque
			* EMERGENCY_DAMPING_RATIO
		)


func calculate_preferred_horizontal_velocity(
	core: DroneCoreDefinition,
	intent: Dictionary
) -> Vector3:
	if core == null:
		return Vector3.ZERO
	if intent.has("horizontal_velocity_override"):
		var override: Vector3 = intent.get(
			"horizontal_velocity_override",
			Vector3.ZERO
		)
		override.y = 0.0
		return override.limit_length(get_navigation_speed_limit(core, intent))
	return calculate_unmodified_preferred_horizontal_velocity(core, intent)


func calculate_unmodified_preferred_horizontal_velocity(
	core: DroneCoreDefinition,
	intent: Dictionary
) -> Vector3:
	if core == null:
		return Vector3.ZERO
	var target_position := hold_position
	var target_velocity := Vector3.ZERO
	var stop_distance := 0.2
	if bool(intent.get("movement_active", false)):
		target_position = intent.get("movement_target", host.global_position)
		target_velocity = intent.get(
			"movement_target_velocity",
			Vector3.ZERO
		)
		stop_distance = maxf(
			float(intent.get("movement_stop_distance", 0.5)),
			0.05
		)
	elif not hold_initialized:
		target_position = host.global_position

	return DroneMovementPlanner.calculate_horizontal_velocity(
		host.global_position,
		target_position,
		target_velocity,
		stop_distance,
		get_navigation_speed_limit(core, intent),
		get_navigation_acceleration_limit(core, intent),
		core.ai_horizontal_position_gain
	)


func get_navigation_speed_limit(
	core: DroneCoreDefinition,
	intent: Dictionary
) -> float:
	if core == null:
		return 0.0
	return maxf(core.ai_max_horizontal_speed, 0.0) * (
		DroneMovementPlanner.get_speed_scale(intent)
	)


func get_navigation_acceleration_limit(
	core: DroneCoreDefinition,
	intent: Dictionary
) -> float:
	if core == null:
		return 0.0
	return maxf(core.ai_max_horizontal_acceleration, 0.0) * (
		DroneMovementPlanner.get_acceleration_scale(intent)
	)


func _allocate_thrust(
	collective_thrust: float,
	desired_torque_local: Vector3,
	core: DroneCoreDefinition,
	loadout: DroneLoadout,
	propeller_slots: Array[DronePropellerSlot],
	air_environment: AirEnvironment
) -> Array[float]:
	var result: Array[float] = []
	result.resize(propeller_slots.size())
	result.fill(0.0)
	var installed_indices: Array[int] = []
	var sum_x_squared := 0.0
	var sum_z_squared := 0.0
	var sum_yaw_squared := 0.0
	var yaw_coefficients: Dictionary[int, float] = {}

	for array_index: int in range(propeller_slots.size()):
		var slot := propeller_slots[array_index]
		var propeller := loadout.get_propeller(slot.slot_index)
		if propeller == null:
			continue
		installed_indices.append(array_index)
		sum_x_squared += slot.position.x * slot.position.x
		sum_z_squared += slot.position.z * slot.position.z
		var yaw_coefficient = (
			float(slot.spin_direction)
			* propeller.reaction_torque_per_newton
		)
		yaw_coefficients[array_index] = yaw_coefficient
		sum_yaw_squared += yaw_coefficient * yaw_coefficient

	if installed_indices.is_empty():
		return result

	var base_thrust := collective_thrust / float(installed_indices.size())
	var differential_limit := (
		base_thrust * clampf(core.ai_motor_mix_authority, 0.0, 1.0)
	)
	for array_index: int in installed_indices:
		var slot := propeller_slots[array_index]
		var correction := 0.0
		if sum_z_squared > 0.0001:
			correction += (
				desired_torque_local.x
				* -slot.position.z
				/ sum_z_squared
			)
		if sum_x_squared > 0.0001:
			correction += (
				desired_torque_local.z
				* slot.position.x
				/ sum_x_squared
			)
		if sum_yaw_squared > 0.000001:
			correction += (
				desired_torque_local.y
				* float(yaw_coefficients.get(array_index, 0.0))
				/ sum_yaw_squared
			)
		correction = clampf(
			correction,
			-differential_limit,
			differential_limit
		)
		var propeller := loadout.get_propeller(slot.slot_index)
		var maximum_thrust := air_environment.calculate_rotor_thrust(
			propeller.max_power_draw,
			propeller.get_disk_area(),
			propeller.aerodynamic_efficiency
		)
		result[array_index] = clampf(
			base_thrust + correction,
			0.0,
			maximum_thrust
		)
	return result


func _get_rotation_error(current_up: Vector3, desired_up: Vector3) -> Vector3:
	var cross := current_up.cross(desired_up)
	var cross_length := cross.length()
	var dot := clampf(current_up.dot(desired_up), -1.0, 1.0)
	if cross_length > 0.0001:
		return cross / cross_length * atan2(cross_length, dot)
	if dot < 0.0:
		return host.global_basis.x.normalized() * PI
	return Vector3.ZERO
