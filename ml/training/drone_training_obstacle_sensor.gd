class_name DroneTrainingObstacleSensor
extends RefCounted

const LEGACY_NEAREST_RAY_DISTANCE_M := 4.0
const SECTOR_RAY_DISTANCE_M := 12.0
const GROUND_RAY_DISTANCE_M := 12.0
const TARGET_RAY_MARGIN_M := 0.35
const VERTICAL_ENVELOPE_RADIUS_M := 0.35
const HORIZONTAL_RAY_COUNT := 16
const SECTOR_COUNT := 8
const MINIMUM_DIRECTION_LENGTH_SQUARED := 0.000001

# Clockwise, viewed from above. Godot's local forward direction is -Z.
const SECTOR_DIRECTIONS_LOCAL: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.70710678118, 0.0, -0.70710678118),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.70710678118, 0.0, 0.70710678118),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-0.70710678118, 0.0, 0.70710678118),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(-0.70710678118, 0.0, -0.70710678118),
]
const HORIZONTAL_DIRECTIONS_WORLD: Array[Vector3] = [
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.92387953251, 0.0, 0.38268343237),
	Vector3(0.70710678118, 0.0, 0.70710678118),
	Vector3(0.38268343237, 0.0, 0.92387953251),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-0.38268343237, 0.0, 0.92387953251),
	Vector3(-0.70710678118, 0.0, 0.70710678118),
	Vector3(-0.92387953251, 0.0, 0.38268343237),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(-0.92387953251, 0.0, -0.38268343237),
	Vector3(-0.70710678118, 0.0, -0.70710678118),
	Vector3(-0.38268343237, 0.0, -0.92387953251),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.38268343237, 0.0, -0.92387953251),
	Vector3(0.70710678118, 0.0, -0.70710678118),
	Vector3(0.92387953251, 0.0, -0.38268343237),
]

#######################################################
# Wall sensing has two layers:
# - the legacy compact nearest-wall feature is kept at its original four-metre range so old
#   observation-schema checkpoints retain the same input meaning;
# - eight longer egocentric sectors plus target-path geometry give new policies enough local
#   structure to choose a route through corridors rather than reacting to one nearest point.
#
# When the training room supplies DroneTrainingWallSpatialHash, every wall query first obtains
# extent-aware broad-phase candidates and only then runs exact ray-vs-box tests. Physics-space
# ray casting remains the fallback and is still used for the separate ground-clearance ray.
#######################################################


static func sample(
	drone: ServerDrone,
	space_state: PhysicsDirectSpaceState3D,
	target_position: Vector3,
	collision_mask: int,
	wall_spatial_hash: DroneTrainingWallSpatialHash = null,
	arena_size: Vector3 = Vector3.ZERO
) -> Dictionary:
	if not is_instance_valid(drone) or space_state == null:
		return clear_probe()
	var origin := drone.global_position
	var inverse_basis := drone.global_basis.inverse()
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [drone.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# One extent-aware broad-phase lookup covers every local lidar ray. The complete ray fan
	# is then evaluated as one batch, so each candidate wall's transform and box data are read
	# once instead of once per ray. This matters much more than the broad-phase lookup itself
	# in dense mazes and at 60 Hz control.
	var horizontal_envelope_radius := maxf(
		drone.get_ai_collision_radius(),
		VERTICAL_ENVELOPE_RADIUS_M
	)
	var horizontal_inflation := Vector3(
		horizontal_envelope_radius,
		VERTICAL_ENVELOPE_RADIUS_M,
		horizontal_envelope_radius
	)
	var local_wall_candidates: Array[Dictionary] = []
	if wall_spatial_hash != null:
		local_wall_candidates = wall_spatial_hash.query_nearby(
			origin,
			SECTOR_RAY_DISTANCE_M + horizontal_envelope_radius
		)

	var ray_directions := PackedVector3Array()
	var ray_maximum_distances := PackedFloat64Array()
	for world_direction in HORIZONTAL_DIRECTIONS_WORLD:
		ray_directions.append(world_direction)
		ray_maximum_distances.append(LEGACY_NEAREST_RAY_DISTANCE_M)

	# Motion- and target-directed probes preserve the useful short-range feature even when
	# the nearest obstacle falls between two fixed fan rays.
	var velocity_ray_index := -1
	var horizontal_velocity := _horizontal_direction(drone.linear_velocity)
	if horizontal_velocity.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED:
		velocity_ray_index = ray_directions.size()
		ray_directions.append(horizontal_velocity)
		ray_maximum_distances.append(LEGACY_NEAREST_RAY_DISTANCE_M)

	var target_offset_world := target_position - origin
	var target_offset_length := target_offset_world.length()
	var target_ray_index := -1
	var horizontal_target := _horizontal_direction(target_offset_world)
	if horizontal_target.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED:
		target_ray_index = ray_directions.size()
		ray_directions.append(horizontal_target)
		ray_maximum_distances.append(LEGACY_NEAREST_RAY_DISTANCE_M)

	var sector_ray_start := ray_directions.size()
	for local_direction in SECTOR_DIRECTIONS_LOCAL:
		ray_directions.append(_yaw_aligned_world_direction(drone, local_direction))
		ray_maximum_distances.append(SECTOR_RAY_DISTANCE_M)

	var ray_distances := PackedFloat64Array()
	if wall_spatial_hash != null:
		ray_distances = wall_spatial_hash.raycast_distances_records(
			local_wall_candidates,
			origin,
			ray_directions,
			ray_maximum_distances,
			horizontal_inflation
		)
	else:
		ray_distances.resize(ray_directions.size())
		ray_distances.fill(-1.0)
		for ray_index in range(ray_directions.size()):
			ray_distances[ray_index] = _sample_wall_distance(
				space_state,
				query,
				null,
				origin,
				ray_directions[ray_index],
				ray_maximum_distances[ray_index],
				horizontal_inflation
			)

	# The presentation intentionally leaves the +Z side of the arena physically open so the
	# training room remains easy to inspect. Episode bounds, however, are rectangular on all
	# four horizontal sides. Treat those logical bounds as virtual walls in the lidar contract
	# so the policy never encounters an invisible terminal cliff that its observations cannot
	# predict. This is merged into the existing wall channels rather than adding a special
	# "border" steering input: the actor still decides how to react to obstacle geometry.
	var arena_boundary_clearance_m = INF
	if arena_size.x > 0.0 and arena_size.z > 0.0:
		arena_boundary_clearance_m = _arena_boundary_clearance_m(
			origin,
			arena_size,
			horizontal_envelope_radius
		)
		for ray_index in range(ray_directions.size()):
			var boundary_distance = _arena_boundary_ray_distance_m(
				origin,
				ray_directions[ray_index],
				arena_size,
				horizontal_envelope_radius,
				ray_maximum_distances[ray_index]
			)
			if boundary_distance < 0.0:
				continue
			if ray_distances[ray_index] < 0.0:
				ray_distances[ray_index] = boundary_distance
			else:
				ray_distances[ray_index] = minf(
					ray_distances[ray_index],
					boundary_distance
				)

	var nearest_distance := LEGACY_NEAREST_RAY_DISTANCE_M
	var nearest_world_direction := Vector3.ZERO
	var nearest_local_direction := Vector3.ZERO
	for ray_index in range(HORIZONTAL_RAY_COUNT):
		var candidate_distance := ray_distances[ray_index]
		if candidate_distance >= 0.0 and candidate_distance < nearest_distance:
			nearest_distance = candidate_distance
			nearest_world_direction = ray_directions[ray_index].normalized()
			nearest_local_direction = (
				inverse_basis * nearest_world_direction
			).normalized()
	for directed_ray_index in [velocity_ray_index, target_ray_index]:
		if directed_ray_index < 0:
			continue
		var candidate_distance := ray_distances[directed_ray_index]
		if candidate_distance >= 0.0 and candidate_distance < nearest_distance:
			nearest_distance = candidate_distance
			nearest_world_direction = ray_directions[directed_ray_index].normalized()
			nearest_local_direction = (
				inverse_basis * nearest_world_direction
			).normalized()

	var sector_clearances_m := PackedFloat64Array()
	sector_clearances_m.resize(SECTOR_COUNT)
	for sector_index in range(SECTOR_COUNT):
		var sector_distance := ray_distances[sector_ray_start + sector_index]
		sector_clearances_m[sector_index] = (
			SECTOR_RAY_DISTANCE_M
			if sector_distance < 0.0
			else sector_distance
		)

	var target_path_blocked := false
	var target_path_clearance_m := target_offset_length
	var target_wall_top_relative_height_m := 0.0
	if target_offset_length > TARGET_RAY_MARGIN_M:
		var target_direction := target_offset_world / target_offset_length
		var target_ray_distance := maxf(
			target_offset_length - TARGET_RAY_MARGIN_M,
			0.0
		)
		var target_hit := _wall_raycast(
			drone,
			space_state,
			query,
			wall_spatial_hash,
			origin,
			target_direction,
			target_ray_distance,
			false
		)
		if not target_hit.is_empty():
			target_path_blocked = true
			target_path_clearance_m = float(target_hit.get(
				"distance_m",
				target_ray_distance
			))
			target_wall_top_relative_height_m = float(target_hit.get(
				"wall_top_world_y",
				origin.y
			)) - origin.y

	# Ground/support clearance is deliberately separate from wall sensing. This physics-space
	# ray hits every solid body on the arena collision layer (floor, platforms, props and other
	# objects), not only nodes tagged as training walls. Areas are intentionally ignored. The actor
	# already has one dedicated clearance feature; allowing the floor to compete with horizontal
	# wall rays used to hide maze geometry.
	var ground_hit := _cast(
		space_state,
		query,
		origin,
		origin + Vector3.DOWN * GROUND_RAY_DISTANCE_M
	)
	var ground_clearance := (
		origin.distance_to(ground_hit.get("position", origin))
		if not ground_hit.is_empty()
		else GROUND_RAY_DISTANCE_M
	)

	var wall_contacts := _training_wall_contacts(drone)
	if not wall_contacts.is_empty():
		# Contact itself is authoritative even when the closest-point vector degenerates
		# because the drone centre is exactly on a box face/edge. Keep zero clearance
		# independent from whether a stable horizontal contact direction can be recovered.
		nearest_distance = 0.0
		var contact_world_direction := _nearest_wall_direction_world(
			wall_contacts,
			origin
		)
		if contact_world_direction.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED:
			nearest_world_direction = contact_world_direction
			nearest_local_direction = (
				inverse_basis * nearest_world_direction
			).normalized()
			_set_contact_sector_zero(
				sector_clearances_m,
				_world_direction_to_yaw_local(drone, nearest_world_direction)
			)

	var nearest_yaw_local_direction = _world_direction_to_yaw_local(
		drone,
		nearest_world_direction
	)
	return {
		# Kept for schema-3/4 compatibility. Full body-local coordinates tilt with the drone.
		"nearest_direction_local": nearest_local_direction,
		# Schema-v5 policies use heading-only coordinates. Ground clearance remains a separate
		# scalar and can never become a horizontal wall-avoidance direction.
		"nearest_direction_yaw_local": nearest_yaw_local_direction,
		"nearest_direction_world": nearest_world_direction,
		"nearest_distance_m": nearest_distance,
		"maximum_distance_m": LEGACY_NEAREST_RAY_DISTANCE_M,
		"closing_speed_mps": maxf(
			drone.linear_velocity.dot(nearest_world_direction),
			0.0
		),
		"sector_clearances_m": sector_clearances_m,
		"sector_maximum_distance_m": SECTOR_RAY_DISTANCE_M,
		"target_path_blocked": target_path_blocked,
		"target_path_clearance_m": target_path_clearance_m,
		"target_path_maximum_distance_m": maxf(target_offset_length, 0.001),
		"target_wall_top_relative_height_m": target_wall_top_relative_height_m,
		"ground_clearance_m": ground_clearance,
		"arena_boundary_clearance_m": arena_boundary_clearance_m,
		"wall_contact": not wall_contacts.is_empty(),
		"wall_contact_count": wall_contacts.size(),
	}


static func clear_probe() -> Dictionary:
	var sector_clearances_m = PackedFloat64Array()
	sector_clearances_m.resize(SECTOR_COUNT)
	sector_clearances_m.fill(SECTOR_RAY_DISTANCE_M)
	return {
		"nearest_direction_local": Vector3.ZERO,
		"nearest_direction_yaw_local": Vector3.ZERO,
		"nearest_direction_world": Vector3.ZERO,
		"nearest_distance_m": LEGACY_NEAREST_RAY_DISTANCE_M,
		"maximum_distance_m": LEGACY_NEAREST_RAY_DISTANCE_M,
		"closing_speed_mps": 0.0,
		"sector_clearances_m": sector_clearances_m,
		"sector_maximum_distance_m": SECTOR_RAY_DISTANCE_M,
		"target_path_blocked": false,
		"target_path_clearance_m": SECTOR_RAY_DISTANCE_M,
		"target_path_maximum_distance_m": SECTOR_RAY_DISTANCE_M,
		"target_wall_top_relative_height_m": 0.0,
		"ground_clearance_m": GROUND_RAY_DISTANCE_M,
		"arena_boundary_clearance_m": INF,
		"wall_contact": false,
		"wall_contact_count": 0,
	}


static func _arena_boundary_clearance_m(
	origin: Vector3,
	arena_size: Vector3,
	envelope_radius_m: float
) -> float:
	if arena_size.x <= 0.0 or arena_size.z <= 0.0:
		return INF
	var half_x = arena_size.x * 0.5
	var half_z = arena_size.z * 0.5
	var center_clearance = minf(
		half_x - absf(origin.x),
		half_z - absf(origin.z)
	)
	return maxf(center_clearance - maxf(envelope_radius_m, 0.0), 0.0)


static func _arena_boundary_ray_distance_m(
	origin: Vector3,
	world_direction: Vector3,
	arena_size: Vector3,
	envelope_radius_m: float,
	maximum_distance_m: float
) -> float:
	if (
		arena_size.x <= 0.0
		or arena_size.z <= 0.0
		or maximum_distance_m <= 0.0
		or world_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		return -1.0
	var direction: Vector3 = _horizontal_direction(world_direction)
	if direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return -1.0
	var radius = maxf(envelope_radius_m, 0.0)
	var half_x = maxf(arena_size.x * 0.5 - radius, 0.0)
	var half_z = maxf(arena_size.z * 0.5 - radius, 0.0)
	var best_distance = INF
	if absf(direction.x) > 0.000001:
		var boundary_x = half_x if direction.x > 0.0 else -half_x
		var distance_x = (boundary_x - origin.x) / direction.x
		if distance_x >= 0.0:
			best_distance = minf(best_distance, distance_x)
	if absf(direction.z) > 0.000001:
		var boundary_z = half_z if direction.z > 0.0 else -half_z
		var distance_z = (boundary_z - origin.z) / direction.z
		if distance_z >= 0.0:
			best_distance = minf(best_distance, distance_z)
	if not is_finite(best_distance) or best_distance > maximum_distance_m:
		return -1.0
	return maxf(best_distance, 0.0)


static func refresh_motion(drone: ServerDrone, cached_probe: Dictionary) -> Dictionary:
	if not is_instance_valid(drone) or cached_probe.is_empty():
		return clear_probe()
	var nearest_world_direction: Vector3 = cached_probe.get(
		"nearest_direction_world",
		Vector3.ZERO
	)
	if nearest_world_direction.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED:
		nearest_world_direction = nearest_world_direction.normalized()
	else:
		# Compatibility for probes created before the world-space direction was stored.
		var nearest_local_direction: Vector3 = cached_probe.get(
			"nearest_direction_local",
			Vector3.ZERO
		)
		nearest_world_direction = (
			(drone.global_basis * nearest_local_direction).normalized()
			if nearest_local_direction.length_squared() > 0.0
			else Vector3.ZERO
		)
	# Keep coordinate-frame features current between expensive geometry samples. The wall
	# is fixed in world space, but a turning/rolling drone changes how that same wall should
	# appear in its local observation on every control step.
	cached_probe["nearest_direction_world"] = nearest_world_direction
	cached_probe["nearest_direction_local"] = (
		(drone.global_basis.inverse() * nearest_world_direction).normalized()
		if nearest_world_direction.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED
		else Vector3.ZERO
	)
	cached_probe["nearest_direction_yaw_local"] = _world_direction_to_yaw_local(
		drone,
		nearest_world_direction
	)
	cached_probe["closing_speed_mps"] = maxf(
		drone.linear_velocity.dot(nearest_world_direction),
		0.0
	)
	return cached_probe


static func _sample_wall_distance(
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsRayQueryParameters3D,
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	origin: Vector3,
	world_direction: Vector3,
	maximum_distance_m: float,
	local_inflation: Vector3,
	prequeried_candidates: Array[Dictionary] = [],
	candidates_prequeried := false
) -> float:
	if world_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return -1.0
	var direction := world_direction.normalized()
	if wall_spatial_hash != null:
		var candidates: Array[Dictionary] = prequeried_candidates
		if not candidates_prequeried:
			var ray_end := origin + direction * maximum_distance_m
			candidates = wall_spatial_hash.query_segment(
				origin,
				ray_end,
				maxf(local_inflation.x, local_inflation.z)
			)
		return wall_spatial_hash.raycast_distance_records(
			candidates,
			origin,
			direction,
			maximum_distance_m,
			local_inflation
		)
	var hit := _cast(
		space_state,
		query,
		origin,
		origin + direction * maximum_distance_m
	)
	if hit.is_empty() or not _is_training_wall_collider(hit.get("collider")):
		return -1.0
	var hit_position: Vector3 = hit.get("position", origin)
	return maxf(
		origin.distance_to(hit_position)
		- maxf(local_inflation.x, local_inflation.z),
		0.0
	)


static func _wall_raycast(
	drone: ServerDrone,
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsRayQueryParameters3D,
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	origin: Vector3,
	world_direction: Vector3,
	maximum_distance_m: float,
	apply_drone_envelope: bool,
	prequeried_candidates: Array[Dictionary] = [],
	candidates_prequeried := false
) -> Dictionary:
	if maximum_distance_m <= 0.0:
		return {}
	var direction = world_direction.normalized()
	if wall_spatial_hash != null:
		var candidates: Array[Dictionary] = prequeried_candidates
		if not candidates_prequeried:
			var ray_end = origin + direction * maximum_distance_m
			candidates = wall_spatial_hash.query_segment(
				origin,
				ray_end,
				_envelope_radius(drone, direction) if apply_drone_envelope else 0.0
			)
		var inflation = Vector3.ZERO
		if apply_drone_envelope:
			var radius = _envelope_radius(drone, direction)
			inflation = Vector3(radius, VERTICAL_ENVELOPE_RADIUS_M, radius)
		return wall_spatial_hash.raycast_records(
			candidates,
			origin,
			direction,
			maximum_distance_m,
			inflation
		)
	var hit = _cast(
		space_state,
		query,
		origin,
		origin + direction * maximum_distance_m
	)
	if hit.is_empty() or not _is_training_wall_collider(hit.get("collider")):
		return {}
	var hit_position: Vector3 = hit.get("position", origin)
	var physical_distance = origin.distance_to(hit_position)
	var distance = physical_distance
	if apply_drone_envelope:
		distance = maxf(physical_distance - _envelope_radius(drone, direction), 0.0)
	var collider = hit.get("collider") as Node3D
	return {
		"distance_m": distance,
		"position": hit_position,
		"body": collider,
		"wall_top_world_y": _wall_top_world_y(collider, hit_position.y),
	}


static func _yaw_aligned_world_direction(
	drone: ServerDrone,
	local_direction: Vector3
) -> Vector3:
	# Sector bearings must follow heading only. Applying the full tilted body basis would skew
	# the horizontal fan whenever the drone rolls or pitches, making the same corridor produce
	# different inputs during an evasive manoeuvre.
	var forward = _horizontal_direction(-drone.global_basis.z)
	if forward.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		forward = Vector3.FORWARD
	var right = forward.cross(Vector3.UP).normalized()
	return _horizontal_direction(
		right * local_direction.x
		+ forward * -local_direction.z
	)


static func _horizontal_direction(direction: Vector3) -> Vector3:
	var horizontal = Vector3(direction.x, 0.0, direction.z)
	return (
		horizontal.normalized()
		if horizontal.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED
		else Vector3.ZERO
	)


static func _training_wall_contacts(drone: ServerDrone) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not drone.contact_monitor or drone.max_contacts_reported <= 0:
		return result
	for body in drone.get_colliding_bodies():
		var node = body as Node3D
		if (
			node != null
			and node.has_meta("training_wall")
			and bool(node.get_meta("training_wall"))
		):
			result.append(node)
	return result


static func _nearest_wall_direction_world(
	walls: Array[Node3D],
	origin: Vector3
) -> Vector3:
	var nearest_distance_squared = INF
	var nearest_offset = Vector3.ZERO
	for wall in walls:
		if not is_instance_valid(wall):
			continue
		var closest_point = _closest_point_on_wall_body(wall, origin)
		var offset = closest_point - origin
		if offset.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
			offset = wall.global_position - origin
		var distance_squared = offset.length_squared()
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_offset = offset
	if nearest_offset.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	# Wall avoidance is horizontal by contract. A top-face contact belongs to the dedicated
	# ground-clearance feature and must not turn the compact wall direction into an instruction
	# to climb or dive.
	return _horizontal_direction(nearest_offset)


static func _world_direction_to_yaw_local(
	drone: ServerDrone,
	world_direction: Vector3
) -> Vector3:
	var horizontal = _horizontal_direction(world_direction)
	if horizontal.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	var forward = _horizontal_direction(-drone.global_basis.z)
	if forward.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		forward = Vector3.FORWARD
	var right = forward.cross(Vector3.UP).normalized()
	return Vector3(
		horizontal.dot(right),
		0.0,
		-horizontal.dot(forward)
	).normalized()


static func _set_contact_sector_zero(
	sector_clearances_m: PackedFloat64Array,
	contact_direction_local: Vector3
) -> void:
	if (
		sector_clearances_m.size() != SECTOR_COUNT
		or contact_direction_local.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		return
	var horizontal_contact = Vector3(
		contact_direction_local.x,
		0.0,
		contact_direction_local.z
	).normalized()
	if horizontal_contact.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return
	var best_index = 0
	var best_dot = -INF
	for index in range(SECTOR_COUNT):
		var score = horizontal_contact.dot(SECTOR_DIRECTIONS_LOCAL[index])
		if score > best_dot:
			best_dot = score
			best_index = index
	sector_clearances_m[best_index] = 0.0


static func _closest_point_on_wall_body(body: Node3D, world_point: Vector3) -> Vector3:
	for child in body.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		var local_point := collision.global_transform.affine_inverse() * world_point
		var local_closest := local_point
		if collision.shape is BoxShape3D:
			var half_size := (collision.shape as BoxShape3D).size * 0.5
			local_closest = Vector3(
				clampf(local_point.x, -half_size.x, half_size.x),
				clampf(local_point.y, -half_size.y, half_size.y),
				clampf(local_point.z, -half_size.z, half_size.z)
			)
		elif collision.shape is SphereShape3D:
			var radius := (collision.shape as SphereShape3D).radius
			if local_point.length_squared() > radius * radius:
				local_closest = local_point.normalized() * radius
		elif collision.shape is CylinderShape3D:
			var cylinder := collision.shape as CylinderShape3D
			var radial := Vector2(local_point.x, local_point.z)
			if radial.length_squared() > cylinder.radius * cylinder.radius:
				radial = radial.normalized() * cylinder.radius
			local_closest = Vector3(
				radial.x,
				clampf(local_point.y, -cylinder.height * 0.5, cylinder.height * 0.5),
				radial.y
			)
		elif collision.shape is CapsuleShape3D:
			var capsule := collision.shape as CapsuleShape3D
			var body_half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			var segment_point := Vector3(
				0.0,
				clampf(local_point.y, -body_half, body_half),
				0.0
			)
			var from_segment := local_point - segment_point
			if from_segment.length_squared() > capsule.radius * capsule.radius:
				local_closest = segment_point + from_segment.normalized() * capsule.radius
		return collision.global_transform * local_closest
	return body.global_position


static func _wall_top_world_y(body: Node3D, fallback: float) -> float:
	if not is_instance_valid(body):
		return fallback
	for child in body.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		var kind := DroneTrainingObstacleShape.kind_from_shape(collision.shape)
		var dimensions := DroneTrainingObstacleShape.dimensions_from_shape(
			collision.shape
		)
		var world_aabb := DroneTrainingObstacleShape.world_aabb(
			kind,
			dimensions,
			collision.global_transform
		)
		return world_aabb.position.y + world_aabb.size.y
	return fallback


static func _envelope_radius(drone: ServerDrone, world_direction: Vector3) -> float:
	var vertical_weight = clampf(absf(world_direction.normalized().y), 0.0, 1.0)
	return lerpf(
		maxf(drone.get_ai_collision_radius(), VERTICAL_ENVELOPE_RADIUS_M),
		VERTICAL_ENVELOPE_RADIUS_M,
		vertical_weight
	)


static func _is_training_wall_collider(collider: Variant) -> bool:
	var node = collider as Node
	return (
		node != null
		and node.has_meta("training_wall")
		and bool(node.get_meta("training_wall"))
	)


static func _cast(
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsRayQueryParameters3D,
	from: Vector3,
	to: Vector3
) -> Dictionary:
	query.from = from
	query.to = to
	return space_state.intersect_ray(query)
