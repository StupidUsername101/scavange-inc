class_name DroneMovementPlanner
extends RefCounted

#######################################################
# Implements the drone movement planner subsystem and keeps its gameplay data and behavior in
# one focused script.
#######################################################

static func calculate_horizontal_velocity(
	position: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	stop_distance: float,
	maximum_speed: float,
	maximum_acceleration: float,
	position_gain: float
) -> Vector3:
	var horizontal_error := target_position - position
	horizontal_error.y = 0.0
	target_velocity.y = 0.0
	maximum_speed = maxf(maximum_speed, 0.0)
	maximum_acceleration = maxf(maximum_acceleration, 0.01)
	position_gain = maxf(position_gain, 0.0)
	if maximum_speed <= 0.0:
		return Vector3.ZERO

	var error_distance := horizontal_error.length()
	var target_is_moving := target_velocity.length_squared() > 0.01
	# Stop distance is an arrival envelope for moving targets. Once the target
	# itself is stationary, tighten that envelope into a real position hold so
	# the drone cannot wander around inside a large dead zone.
	var precision_radius := minf(maxf(stop_distance, 0.02) * 0.14, 0.07)
	var arrival_radius := (
		maxf(stop_distance, 0.02)
		if target_is_moving
		else precision_radius
	)
	var remaining_distance := maxf(error_distance - arrival_radius, 0.0)
	var result := target_velocity
	if remaining_distance > 0.0 and error_distance > 0.0001:
		# A velocity command bounded by the available stopping distance prevents
		# the outer loop from asking the attitude controller to fly through its
		# destination and reverse at full bank on the other side.
		var braking_speed := sqrt(
			2.0 * maximum_acceleration * remaining_distance
		) * 0.72
		var proportional_speed := remaining_distance * position_gain
		var closing_speed := minf(proportional_speed, braking_speed)
		result += horizontal_error / error_distance * closing_speed

	return result.limit_length(maximum_speed)


static func get_speed_scale(intent: Dictionary) -> float:
	return clampf(float(intent.get("movement_speed_scale", 1.0)), 0.05, 1.0)


static func get_acceleration_scale(intent: Dictionary) -> float:
	return clampf(
		float(intent.get("movement_acceleration_scale", 1.0)),
		0.05,
		1.0
	)


static func get_jerk_scale(intent: Dictionary) -> float:
	return clampf(float(intent.get("movement_jerk_scale", 1.0)), 0.05, 1.0)
