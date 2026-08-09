class_name BallisticAim
extends RefCounted

#######################################################
# Computes launch directions that intercept moving targets with finite-speed, gravity-affected
# projectiles.
#######################################################

static func calculate_intercept_point(
	origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	shooter_velocity: Vector3,
	projectile_speed: float,
	maximum_lead_seconds := 2.0
) -> Vector3:
	var speed := maxf(projectile_speed, 0.1)
	var relative_position := target_position - origin
	var relative_velocity := target_velocity - shooter_velocity
	var a := relative_velocity.length_squared() - speed * speed
	var b := 2.0 * relative_position.dot(relative_velocity)
	var c := relative_position.length_squared()
	var intercept_time := -1.0

	if absf(a) <= 0.000001:
		if absf(b) > 0.000001:
			intercept_time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			var time_a := (-b - root) / (2.0 * a)
			var time_b := (-b + root) / (2.0 * a)
			if time_a > 0.0 and time_b > 0.0:
				intercept_time = minf(time_a, time_b)
			elif time_a > 0.0:
				intercept_time = time_a
			elif time_b > 0.0:
				intercept_time = time_b

	if intercept_time <= 0.0:
		return target_position
	intercept_time = minf(intercept_time, maximum_lead_seconds)
	# The projectile inherits the shooter's velocity. Aim only for the
	# target's velocity relative to that moving launch platform.
	return target_position + relative_velocity * intercept_time


static func calculate_launch_direction(
	origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	shooter_velocity: Vector3,
	projectile_speed: float,
	gravity_scale: float,
	maximum_lead_seconds := 2.0
) -> Vector3:
	var speed := maxf(projectile_speed, 0.1)
	var relative_velocity := target_velocity - shooter_velocity
	var aim_point := calculate_intercept_point(
		origin,
		target_position,
		target_velocity,
		shooter_velocity,
		speed,
		maximum_lead_seconds
	)
	var direction := (aim_point - origin).normalized()
	var gravity := maxf(gravity_scale, 0.0) * 9.8
	if gravity <= 0.0001:
		return direction

	for _iteration: int in range(3):
		var relative_aim := aim_point - origin
		direction = _solve_low_ballistic_arc(
			relative_aim,
			speed,
			gravity
		)
		var horizontal_distance := Vector2(
			relative_aim.x,
			relative_aim.z
		).length()
		var horizontal_speed := Vector2(
			direction.x,
			direction.z
		).length() * speed
		if horizontal_speed <= 0.0001:
			break
		var travel_time := minf(
			horizontal_distance / horizontal_speed,
			maximum_lead_seconds
		)
		aim_point = (
			target_position
			+ relative_velocity * travel_time
		)
	return _solve_low_ballistic_arc(
		aim_point - origin,
		speed,
		gravity
	)


static func _solve_low_ballistic_arc(
	relative_target: Vector3,
	speed: float,
	gravity: float
) -> Vector3:
	var horizontal := Vector3(
		relative_target.x,
		0.0,
		relative_target.z
	)
	var horizontal_distance := horizontal.length()
	if horizontal_distance <= 0.0001 or gravity <= 0.0001:
		return relative_target.normalized()
	var speed_squared := speed * speed
	var discriminant := (
		speed_squared * speed_squared
		- gravity * (
			gravity * horizontal_distance * horizontal_distance
			+ 2.0 * relative_target.y * speed_squared
		)
	)
	if discriminant < 0.0:
		return relative_target.normalized()
	var angle := atan(
		(speed_squared - sqrt(discriminant))
		/ (gravity * horizontal_distance)
	)
	return (
		horizontal.normalized() * cos(angle)
		+ Vector3.UP * sin(angle)
	).normalized()
