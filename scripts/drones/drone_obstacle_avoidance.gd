class_name DroneObstacleAvoidance
extends RefCounted

const PROBE_INTERVAL := 0.08
const MINIMUM_COMMAND_SPEED := 0.12
const MAXIMUM_RAY_PENETRATIONS := 6
const MINIMUM_ACCELERATION := 0.1
const MINIMUM_PHYSICAL_RADIUS := 0.1
const MINIMUM_DIRECTION_LENGTH_SQUARED := 0.001
const MINIMUM_SPEED := 0.0001
const MINIMUM_DISTANCE := 0.01
const DIRECTION_CHANGE_REFERENCE_LENGTH_SQUARED := 0.5
const DIRECTION_CHANGE_DOT_THRESHOLD := 0.88
const SAFETY_RADIUS_SCALE := 1.2
const SAFETY_MARGIN := 0.3
const SPEED_LOOKAHEAD_SECONDS := 0.55
const MIN_LOOKAHEAD_RADIUS_SCALE := 2.4
const MIN_LOOKAHEAD_MARGIN := 0.8
const MAX_LOOKAHEAD := 10.0
const CLEAR_PATH_RATIO := 0.98
const MIN_REQUIRED_CLEARANCE_SCALE := 0.72
const DANGER_THRESHOLD := 0.01
const FORWARD_SCORE_WEIGHT := 2.25
const CLEARANCE_SCORE_WEIGHT := 1.15
const CONTINUITY_SCORE_WEIGHT := 0.38
const DANGER_SCORE_WEIGHT := 4.5
const CRITICAL_CLEARANCE_RATIO := 0.38
const CRITICAL_CLEARANCE_PENALTY := 8.0
const SPEED_CLEARANCE_OFFSET_RATIO := 0.25
const MIN_SPEED_SCALE := 0.22
const PROBE_SIDE_OFFSET_RATIO := 0.72
const PROBE_HEIGHT := 0.08
const RAY_PENETRATION_ADVANCE := 0.025
const SAMPLE_ANGLES_DEGREES: Array[float] = [
	0.0,
	-22.5,
	22.5,
	-45.0,
	45.0,
	-67.5,
	67.5,
	-90.0,
	90.0,
	-135.0,
	135.0,
	180.0,
]

#######################################################
# Implements the drone obstacle avoidance subsystem and keeps its gameplay data and behavior
# in one focused script.
#######################################################

var host: RigidBody3D
var probe_time_remaining := 0.0
var cached_result: Dictionary = {}
var previous_safe_direction := Vector3.ZERO
var previous_preferred_direction := Vector3.ZERO


func _init(owner_drone: RigidBody3D) -> void:
	host = owner_drone


func clear() -> void:
	probe_time_remaining = 0.0
	cached_result = {}
	previous_safe_direction = Vector3.ZERO
	previous_preferred_direction = Vector3.ZERO


func calculate(
	preferred_velocity: Vector3,
	maximum_acceleration: float,
	physical_radius: float,
	delta: float
) -> Dictionary:
	preferred_velocity.y = 0.0
	var speed := preferred_velocity.length()
	if (
		host == null
		or not host.is_inside_tree()
		or speed < MINIMUM_COMMAND_SPEED
	):
		clear()
		return {}

	var preferred_direction := preferred_velocity / speed
	if not _should_refresh_probe(preferred_direction, delta):
		return cached_result.duplicate()

	var probe_distances := _calculate_probe_distances(
		speed,
		maximum_acceleration,
		physical_radius
	)
	var safety_distance := float(probe_distances["safety_distance"])
	var lookahead := float(probe_distances["lookahead"])
	physical_radius = float(probe_distances["physical_radius"])

	# Most movement frames only need this three-ray corridor test. The wider
	# context map is evaluated only after something actually blocks the route.
	var forward_clearance := _probe_clearance(
		preferred_direction,
		lookahead,
		physical_radius
	)
	if forward_clearance >= lookahead * CLEAR_PATH_RATIO:
		cached_result = {}
		previous_safe_direction = preferred_direction
		return {}

	var samples := _build_context_samples(
		preferred_direction,
		lookahead,
		physical_radius,
		forward_clearance
	)
	var directions: Array[Vector3] = samples["directions"]
	var clearances: Array[float] = samples["clearances"]
	var selected := select_context_velocity(
		preferred_velocity,
		directions,
		clearances,
		lookahead,
		safety_distance,
		previous_safe_direction
	)
	return _cache_selected_velocity(selected)


func _should_refresh_probe(
	preferred_direction: Vector3,
	delta: float
) -> bool:
	probe_time_remaining -= maxf(delta, 0.0)
	var direction_changed := (
		previous_preferred_direction.length_squared()
		> DIRECTION_CHANGE_REFERENCE_LENGTH_SQUARED
		and preferred_direction.dot(previous_preferred_direction)
		< DIRECTION_CHANGE_DOT_THRESHOLD
	)
	if probe_time_remaining > 0.0 and not direction_changed:
		return false

	probe_time_remaining = PROBE_INTERVAL
	previous_preferred_direction = preferred_direction
	return true


func _calculate_probe_distances(
	speed: float,
	maximum_acceleration: float,
	physical_radius: float
) -> Dictionary:
	maximum_acceleration = maxf(
		maximum_acceleration,
		MINIMUM_ACCELERATION
	)
	physical_radius = maxf(physical_radius, MINIMUM_PHYSICAL_RADIUS)
	var braking_distance := speed * speed / (2.0 * maximum_acceleration)
	var safety_distance := (
		physical_radius * SAFETY_RADIUS_SCALE
		+ braking_distance
		+ SAFETY_MARGIN
	)
	var lookahead := clampf(
		safety_distance + speed * SPEED_LOOKAHEAD_SECONDS,
		physical_radius * MIN_LOOKAHEAD_RADIUS_SCALE
		+ MIN_LOOKAHEAD_MARGIN,
		MAX_LOOKAHEAD
	)
	return {
		"physical_radius": physical_radius,
		"safety_distance": safety_distance,
		"lookahead": lookahead,
	}


func _build_context_samples(
	preferred_direction: Vector3,
	lookahead: float,
	physical_radius: float,
	forward_clearance: float
) -> Dictionary:
	var directions: Array[Vector3] = []
	var clearances: Array[float] = []
	for angle_degrees: float in SAMPLE_ANGLES_DEGREES:
		var direction := preferred_direction.rotated(
			Vector3.UP,
			deg_to_rad(angle_degrees)
		).normalized()
		directions.append(direction)
		if is_zero_approx(angle_degrees):
			clearances.append(forward_clearance)
		else:
			clearances.append(_probe_clearance(
				direction,
				lookahead,
				physical_radius
			))
	return {
		"directions": directions,
		"clearances": clearances,
	}


func _cache_selected_velocity(selected: Dictionary) -> Dictionary:
	var selected_velocity: Vector3 = selected.get("velocity", Vector3.ZERO)
	if (
		selected_velocity.length_squared()
		> MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		previous_safe_direction = selected_velocity.normalized()
	cached_result = {
		"velocity": selected_velocity,
		"blocked_sample_count": int(selected.get(
			"blocked_sample_count",
			0
		)),
		"clearance": float(selected.get("clearance", 0.0)),
	}
	return cached_result.duplicate()


static func select_context_velocity(
	preferred_velocity: Vector3,
	directions: Array[Vector3],
	clearances: Array[float],
	lookahead: float,
	safety_distance: float,
	continuity_direction: Vector3 = Vector3.ZERO
) -> Dictionary:
	preferred_velocity.y = 0.0
	var speed := preferred_velocity.length()
	if speed <= MINIMUM_SPEED or directions.is_empty():
		return {"velocity": Vector3.ZERO, "blocked_sample_count": 0}
	var preferred_direction := preferred_velocity / speed
	lookahead = maxf(lookahead, MINIMUM_DISTANCE)
	safety_distance = clampf(
		safety_distance,
		MINIMUM_DISTANCE,
		lookahead
	)
	continuity_direction.y = 0.0
	if (
		continuity_direction.length_squared()
		> MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		continuity_direction = continuity_direction.normalized()

	var best_index := -1
	var best_score := -INF
	var blocked_count := 0
	for index: int in range(mini(directions.size(), clearances.size())):
		var direction := directions[index]
		direction.y = 0.0
		if (
			direction.length_squared()
			<= MINIMUM_DIRECTION_LENGTH_SQUARED
		):
			continue
		direction = direction.normalized()
		var clearance := clampf(clearances[index], 0.0, lookahead)
		var forward_alignment := direction.dot(preferred_direction)
		var required_clearance := safety_distance * lerpf(
			MIN_REQUIRED_CLEARANCE_SCALE,
			1.0,
			maxf(forward_alignment, 0.0)
		)
		var danger := clampf(
			(required_clearance - clearance) / required_clearance,
			0.0,
			1.0
		)
		if danger > DANGER_THRESHOLD:
			blocked_count += 1
		var continuity := (
			direction.dot(continuity_direction)
			if continuity_direction.length_squared()
			> DIRECTION_CHANGE_REFERENCE_LENGTH_SQUARED
			else 0.0
		)
		# Context steering chooses one viable direction instead of averaging a
		# seek vector with an opposing avoidance vector and getting stuck at 0.
		var score := (
			forward_alignment * FORWARD_SCORE_WEIGHT
			+ clearance / lookahead * CLEARANCE_SCORE_WEIGHT
			+ continuity * CONTINUITY_SCORE_WEIGHT
			- danger * DANGER_SCORE_WEIGHT
		)
		if clearance < safety_distance * CRITICAL_CLEARANCE_RATIO:
			score -= CRITICAL_CLEARANCE_PENALTY
		if score > best_score:
			best_score = score
			best_index = index

	if best_index < 0:
		return {
			"velocity": Vector3.ZERO,
			"blocked_sample_count": blocked_count,
			"clearance": 0.0,
		}
	var best_clearance := clampf(clearances[best_index], 0.0, lookahead)
	if best_clearance < safety_distance * CRITICAL_CLEARANCE_RATIO:
		return {
			"velocity": Vector3.ZERO,
			"blocked_sample_count": blocked_count,
			"clearance": best_clearance,
		}
	var speed_scale := clampf(
		(best_clearance - safety_distance * SPEED_CLEARANCE_OFFSET_RATIO)
		/ maxf(safety_distance, MINIMUM_DISTANCE),
		MIN_SPEED_SCALE,
		1.0
	)
	return {
		"velocity": directions[best_index].normalized() * speed * speed_scale,
		"blocked_sample_count": blocked_count,
		"clearance": best_clearance,
		"selected_index": best_index,
	}


func _probe_clearance(
	direction: Vector3,
	maximum_distance: float,
	physical_radius: float
) -> float:
	direction.y = 0.0
	if direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return 0.0
	direction = direction.normalized()
	var side := Vector3.UP.cross(direction).normalized()
	var minimum_clearance := maximum_distance
	for side_factor: float in [
		-PROBE_SIDE_OFFSET_RATIO,
		0.0,
		PROBE_SIDE_OFFSET_RATIO,
	]:
		var origin := (
			host.global_position
			+ Vector3.UP * PROBE_HEIGHT
			+ side * physical_radius * side_factor
		)
		minimum_clearance = minf(
			minimum_clearance,
			_cast_ray_ignoring_drones(
				origin,
				direction,
				maximum_distance
			)
		)
	return minimum_clearance


func _cast_ray_ignoring_drones(
	origin: Vector3,
	direction: Vector3,
	maximum_distance: float
) -> float:
	var cursor := origin
	var traveled := 0.0
	var excluded: Array[RID] = [host.get_rid()]
	var space_state := host.get_world_3d().direct_space_state
	for _penetration: int in range(MAXIMUM_RAY_PENETRATIONS):
		var remaining := maximum_distance - traveled
		if remaining <= MINIMUM_DIRECTION_LENGTH_SQUARED:
			return maximum_distance
		var query := PhysicsRayQueryParameters3D.create(
			cursor,
			cursor + direction * remaining
		)
		query.exclude = excluded
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			return maximum_distance
		var hit_position: Vector3 = hit.get("position", cursor)
		traveled += cursor.distance_to(hit_position)
		var collider := hit.get("collider") as Node
		if collider is ServerDrone:
			excluded.append((collider as ServerDrone).get_rid())
			cursor = (
				hit_position
				+ direction * RAY_PENETRATION_ADVANCE
			)
			traveled += RAY_PENETRATION_ADVANCE
			continue
		return clampf(traveled, 0.0, maximum_distance)
	return clampf(traveled, 0.0, maximum_distance)
