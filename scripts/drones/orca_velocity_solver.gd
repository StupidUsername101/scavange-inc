# SPDX-FileCopyrightText: 2008 University of North Carolina at Chapel Hill
# SPDX-License-Identifier: Apache-2.0

class_name OrcaVelocitySolver
extends RefCounted

## Two-dimensional ORCA solver for the drones' horizontal X/Z plane.
##
## This is a GDScript adaptation of the agent-agent portion of the Apache 2.0
## RVO2 reference implementation by the University of North Carolina. The
## flight controller remains responsible for acceleration and attitude limits.

const EPSILON := 0.00001
const DEFAULT_RECIPROCAL_RESPONSIBILITY := 0.5
const IMMEDIATE_RELEVANCE_DISTANCE_SQUARED := 2.25

#######################################################
# Solves reciprocal collision-avoidance constraints with the ORCA linear programming
# algorithm.
#######################################################

static func solve(
	position: Vector2,
	velocity: Vector2,
	preferred_velocity: Vector2,
	maximum_speed: float,
	radius: float,
	time_horizon: float,
	time_step: float,
	self_id: int,
	neighbors: Array[Dictionary]
) -> Dictionary:
	var lines: Array[Dictionary] = []
	var inverse_time_horizon := 1.0 / maxf(time_horizon, EPSILON)
	var inverse_time_step := 1.0 / maxf(time_step, EPSILON)
	var safe_radius := maxf(radius, 0.0)

	for neighbor: Dictionary in neighbors:
		lines.append(_build_neighbor_constraint(
			position,
			velocity,
			safe_radius,
			inverse_time_horizon,
			inverse_time_step,
			self_id,
			neighbor
		))

	var linear_result := _linear_program_2(
		lines,
		maxf(maximum_speed, 0.0),
		preferred_velocity,
		false
	)
	var result: Vector2 = linear_result.get("result", Vector2.ZERO)
	var failed_line := int(linear_result.get("failed_line", lines.size()))
	if failed_line < lines.size():
		result = _linear_program_3(
			lines,
			failed_line,
			maxf(maximum_speed, 0.0),
			result
		)
	return {
		"velocity": result,
		"constraint_count": lines.size(),
	}


static func _build_neighbor_constraint(
	position: Vector2,
	velocity: Vector2,
	radius: float,
	inverse_time_horizon: float,
	inverse_time_step: float,
	self_id: int,
	neighbor: Dictionary
) -> Dictionary:
	var other_position: Vector2 = neighbor.get("position", position)
	var other_velocity: Vector2 = neighbor.get("velocity", Vector2.ZERO)
	var other_radius := maxf(float(neighbor.get("radius", 0.0)), 0.0)
	var responsibility := clampf(
		float(neighbor.get(
			"responsibility",
			DEFAULT_RECIPROCAL_RESPONSIBILITY
		)),
		0.0,
		1.0
	)
	var relative_position := other_position - position
	var relative_velocity := velocity - other_velocity
	var distance_squared := relative_position.length_squared()
	var combined_radius := radius + other_radius
	var combined_radius_squared := combined_radius * combined_radius
	var correction_state: Dictionary
	if distance_squared > combined_radius_squared:
		correction_state = _build_separated_correction(
			relative_position,
			relative_velocity,
			distance_squared,
			combined_radius,
			combined_radius_squared,
			inverse_time_horizon,
			_fallback_axis(self_id, int(neighbor.get("entity_id", 0)))
		)
	else:
		correction_state = _build_collision_correction(
			relative_position,
			relative_velocity,
			combined_radius,
			inverse_time_step,
			_fallback_axis(self_id, int(neighbor.get("entity_id", 0)))
		)
	var line_direction: Vector2 = correction_state["direction"]
	var correction: Vector2 = correction_state["correction"]
	return {
		"point": velocity + correction * responsibility,
		"direction": _safe_normalized(line_direction, Vector2.RIGHT),
	}


static func _build_separated_correction(
	relative_position: Vector2,
	relative_velocity: Vector2,
	distance_squared: float,
	combined_radius: float,
	combined_radius_squared: float,
	inverse_time_horizon: float,
	fallback_axis: Vector2
) -> Dictionary:
	var w := relative_velocity - relative_position * inverse_time_horizon
	var w_length_squared := w.length_squared()
	var dot_product := w.dot(relative_position)
	if (
		dot_product < 0.0
		and dot_product * dot_product
		> combined_radius_squared * w_length_squared
	):
		var w_length := sqrt(maxf(w_length_squared, EPSILON))
		var unit_w := _safe_normalized(w, fallback_axis)
		return {
			"direction": Vector2(unit_w.y, -unit_w.x),
			"correction": (
				combined_radius * inverse_time_horizon - w_length
			) * unit_w,
		}

	var leg := sqrt(maxf(distance_squared - combined_radius_squared, 0.0))
	var line_direction: Vector2
	if _det(relative_position, w) > 0.0:
		line_direction = Vector2(
			relative_position.x * leg
			- relative_position.y * combined_radius,
			relative_position.x * combined_radius
			+ relative_position.y * leg
		) / maxf(distance_squared, EPSILON)
	else:
		line_direction = -Vector2(
			relative_position.x * leg
			+ relative_position.y * combined_radius,
			-relative_position.x * combined_radius
			+ relative_position.y * leg
		) / maxf(distance_squared, EPSILON)
	return {
		"direction": line_direction,
		"correction": (
			line_direction * relative_velocity.dot(line_direction)
			- relative_velocity
		),
	}


static func _build_collision_correction(
	relative_position: Vector2,
	relative_velocity: Vector2,
	combined_radius: float,
	inverse_time_step: float,
	fallback_axis: Vector2
) -> Dictionary:
	var collision_w := (
		relative_velocity - relative_position * inverse_time_step
	)
	var collision_w_length := collision_w.length()
	var collision_unit_w := _safe_normalized(collision_w, fallback_axis)
	return {
		"direction": Vector2(collision_unit_w.y, -collision_unit_w.x),
		"correction": (
			combined_radius * inverse_time_step - collision_w_length
		) * collision_unit_w,
	}


static func is_relevant_neighbor(
	position: Vector2,
	velocity: Vector2,
	preferred_velocity: Vector2,
	radius: float,
	time_horizon: float,
	neighbor: Dictionary
) -> bool:
	var other_position: Vector2 = neighbor.get("position", position)
	var other_velocity: Vector2 = neighbor.get("velocity", Vector2.ZERO)
	var combined_radius := (
		maxf(radius, 0.0)
		+ maxf(float(neighbor.get("radius", 0.0)), 0.0)
	)
	var relative_position := other_position - position
	if relative_position.length_squared() <= (
		combined_radius
		* combined_radius
		* IMMEDIATE_RELEVANCE_DISTANCE_SQUARED
	):
		return true
	return (
		_will_intersect(
			relative_position,
			velocity - other_velocity,
			combined_radius,
			time_horizon
		)
		or _will_intersect(
			relative_position,
			preferred_velocity - other_velocity,
			combined_radius,
			time_horizon
		)
	)


static func _will_intersect(
	relative_position: Vector2,
	closing_velocity: Vector2,
	combined_radius: float,
	time_horizon: float
) -> bool:
	var speed_squared := closing_velocity.length_squared()
	if speed_squared <= EPSILON:
		return false
	var closest_time := clampf(
		relative_position.dot(closing_velocity) / speed_squared,
		0.0,
		maxf(time_horizon, 0.0)
	)
	var closest_offset := (
		relative_position - closing_velocity * closest_time
	)
	return closest_offset.length_squared() <= combined_radius * combined_radius


static func _linear_program_1(
	lines: Array[Dictionary],
	line_index: int,
	radius: float,
	optimal_velocity: Vector2,
	direction_optimal: bool
) -> Dictionary:
	var line: Dictionary = lines[line_index]
	var point: Vector2 = line.get("point", Vector2.ZERO)
	var direction: Vector2 = line.get("direction", Vector2.RIGHT)
	var dot_product := point.dot(direction)
	var discriminant := (
		dot_product * dot_product + radius * radius
		- point.length_squared()
	)
	if discriminant < 0.0:
		return {"success": false, "result": Vector2.ZERO}

	var root := sqrt(discriminant)
	var left := -dot_product - root
	var right := -dot_product + root
	for previous_index: int in range(line_index):
		var previous: Dictionary = lines[previous_index]
		var previous_point: Vector2 = previous.get("point", Vector2.ZERO)
		var previous_direction: Vector2 = previous.get(
			"direction",
			Vector2.RIGHT
		)
		var denominator := _det(direction, previous_direction)
		var numerator := _det(
			previous_direction,
			point - previous_point
		)
		if absf(denominator) <= EPSILON:
			if numerator < 0.0:
				return {"success": false, "result": Vector2.ZERO}
			continue
		var parameter := numerator / denominator
		if denominator >= 0.0:
			right = minf(right, parameter)
		else:
			left = maxf(left, parameter)
		if left > right:
			return {"success": false, "result": Vector2.ZERO}

	var result := Vector2.ZERO
	if direction_optimal:
		result = point + direction * (
			right if optimal_velocity.dot(direction) > 0.0 else left
		)
	else:
		var parameter := direction.dot(optimal_velocity - point)
		result = point + direction * clampf(parameter, left, right)
	return {"success": true, "result": result}


static func _linear_program_2(
	lines: Array[Dictionary],
	radius: float,
	optimal_velocity: Vector2,
	direction_optimal: bool
) -> Dictionary:
	var result := optimal_velocity
	if direction_optimal:
		result = optimal_velocity * radius
	elif optimal_velocity.length_squared() > radius * radius:
		result = _safe_normalized(optimal_velocity, Vector2.RIGHT) * radius

	for line_index: int in range(lines.size()):
		var line: Dictionary = lines[line_index]
		var direction: Vector2 = line.get("direction", Vector2.RIGHT)
		var point: Vector2 = line.get("point", Vector2.ZERO)
		if _det(direction, point - result) <= 0.0:
			continue
		var previous_result := result
		var line_result := _linear_program_1(
			lines,
			line_index,
			radius,
			optimal_velocity,
			direction_optimal
		)
		if not bool(line_result.get("success", false)):
			return {
				"failed_line": line_index,
				"result": previous_result,
			}
		result = line_result.get("result", previous_result)
	return {"failed_line": lines.size(), "result": result}


static func _linear_program_3(
	lines: Array[Dictionary],
	begin_line: int,
	radius: float,
	initial_result: Vector2
) -> Vector2:
	var result := initial_result
	var distance := 0.0
	for line_index: int in range(begin_line, lines.size()):
		var line: Dictionary = lines[line_index]
		var line_direction: Vector2 = line.get("direction", Vector2.RIGHT)
		var line_point: Vector2 = line.get("point", Vector2.ZERO)
		if _det(line_direction, line_point - result) <= distance:
			continue

		var projected_lines: Array[Dictionary] = []
		for previous_index: int in range(line_index):
			var previous: Dictionary = lines[previous_index]
			var previous_direction: Vector2 = previous.get(
				"direction",
				Vector2.RIGHT
			)
			var previous_point: Vector2 = previous.get(
				"point",
				Vector2.ZERO
			)
			var determinant := _det(line_direction, previous_direction)
			var projected_point := Vector2.ZERO
			if absf(determinant) <= EPSILON:
				if line_direction.dot(previous_direction) > 0.0:
					continue
				projected_point = (line_point + previous_point) * 0.5
			else:
				projected_point = (
					line_point
					+ line_direction
					* (
						_det(
							previous_direction,
							line_point - previous_point
						)
						/ determinant
					)
				)
			projected_lines.append({
				"point": projected_point,
				"direction": _safe_normalized(
					previous_direction - line_direction,
					Vector2.RIGHT
				),
			})

		var previous_result := result
		var projection_result := _linear_program_2(
			projected_lines,
			radius,
			Vector2(-line_direction.y, line_direction.x),
			true
		)
		if int(projection_result.get(
			"failed_line",
			projected_lines.size()
		)) < projected_lines.size():
			result = previous_result
		else:
			result = projection_result.get("result", previous_result)
		distance = _det(line_direction, line_point - result)
	return result


static func _safe_normalized(value: Vector2, fallback: Vector2) -> Vector2:
	if value.length_squared() <= EPSILON:
		return fallback.normalized()
	return value.normalized()


static func _fallback_axis(self_id: int, other_id: int) -> Vector2:
	return Vector2.RIGHT if self_id < other_id else Vector2.LEFT


static func _det(left: Vector2, right: Vector2) -> float:
	return left.x * right.y - left.y * right.x
