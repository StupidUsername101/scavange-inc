class_name FourLimbTrainingObstacleSensor
extends RefCounted

const RAY_COUNT := FourLimbMLObservation.OBSTACLE_RAY_COUNT
const RAY_MAXIMUM_DISTANCE_M := FourLimbMLObservation.OBSTACLE_RAY_MAXIMUM_DISTANCE_M
const TARGET_RAY_MARGIN_M := 0.35
const MINIMUM_DIRECTION_LENGTH_SQUARED := 0.000001
const LOCAL_RAY_DIRECTIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.70710678118, 0.0, -0.70710678118),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.70710678118, 0.0, 0.70710678118),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-0.70710678118, 0.0, 0.70710678118),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(-0.70710678118, 0.0, -0.70710678118),
	Vector3(0.0, 0.54498835060, -0.83844361630),
	Vector3(0.59286916673, 0.54498835060, -0.59286916673),
	Vector3(0.83844361630, 0.54498835060, 0.0),
	Vector3(0.59286916673, 0.54498835060, 0.59286916673),
	Vector3(0.0, 0.54498835060, 0.83844361630),
	Vector3(-0.59286916673, 0.54498835060, 0.59286916673),
	Vector3(-0.83844361630, 0.54498835060, 0.0),
	Vector3(-0.59286916673, 0.54498835060, -0.59286916673),
	Vector3(0.0, -0.54498835060, -0.83844361630),
	Vector3(0.59286916673, -0.54498835060, -0.59286916673),
	Vector3(0.83844361630, -0.54498835060, 0.0),
	Vector3(0.59286916673, -0.54498835060, 0.59286916673),
	Vector3(0.0, -0.54498835060, 0.83844361630),
	Vector3(-0.59286916673, -0.54498835060, 0.59286916673),
	Vector3(-0.83844361630, -0.54498835060, 0.0),
	Vector3(-0.59286916673, -0.54498835060, -0.59286916673),
	Vector3.UP,
	Vector3.DOWN,
]

#######################################################
# Spatial-hash lidar for the articulated body. Wall geometry is sampled at the policy control
# rate, not at the 240 Hz physics rate. One horizontal ring and two pitched rings give the model
# full 3D clearance without 26 PhysicsDirectSpaceState raycasts per worker.
#######################################################


static func sample(
	body: FourLimbPhysicalBody3D,
	target_position_world: Vector3,
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	contact_snapshot: Dictionary = {},
	arena_size: Vector3 = Vector3.ZERO
) -> Dictionary:
	if (
		not is_instance_valid(body)
		or not is_instance_valid(body.physical_rig)
	):
		return clear_probe()
	var rig = body.physical_rig
	var core_transform = rig.get_core_transform()
	var origin = core_transform.origin
	var yaw_basis = _yaw_basis(core_transform.basis)
	var inverse_yaw_basis = yaw_basis.inverse()
	var ray_directions_world = _ray_directions(yaw_basis)
	var inflation = _body_inflation(body.definition)
	var ray_distances = PackedFloat64Array()
	ray_distances.resize(RAY_COUNT)
	ray_distances.fill(-1.0)
	if wall_spatial_hash != null:
		var query_radius = RAY_MAXIMUM_DISTANCE_M + maxf(inflation.x, inflation.z)
		var candidates = wall_spatial_hash.query_nearby(origin, query_radius)
		ray_distances = wall_spatial_hash.raycast_distances_records_uniform(
			candidates,
			origin,
			ray_directions_world,
			RAY_MAXIMUM_DISTANCE_M,
			inflation
		)

	var clearances = PackedFloat64Array()
	clearances.resize(RAY_COUNT)
	var nearest_distance = RAY_MAXIMUM_DISTANCE_M
	var nearest_direction_world = Vector3.ZERO
	for ray_index in range(RAY_COUNT):
		var distance = ray_distances[ray_index]
		var boundary_distance := arena_boundary_distance(
			origin,
			ray_directions_world[ray_index],
			arena_size,
			inflation
		)
		if boundary_distance >= 0.0 and (distance < 0.0 or boundary_distance < distance):
			distance = boundary_distance
		clearances[ray_index] = (
			RAY_MAXIMUM_DISTANCE_M
			if distance < 0.0
			else clampf(distance, 0.0, RAY_MAXIMUM_DISTANCE_M)
		)
		if distance >= 0.0 and distance < nearest_distance:
			nearest_distance = distance
			nearest_direction_world = ray_directions_world[ray_index]

	var contacts = (
		contact_snapshot
		if not contact_snapshot.is_empty()
		else rig.world_contact_snapshot()
	)
	var wall_contacts: Array = contacts.get("wall_contacts", [])
	if not wall_contacts.is_empty():
		nearest_distance = 0.0
		var contact_direction = _nearest_contact_direction(wall_contacts, origin)
		if contact_direction.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED:
			nearest_direction_world = contact_direction.normalized()
			var contact_ray_index = _closest_ray_index(
				ray_directions_world,
				nearest_direction_world
			)
			if contact_ray_index >= 0:
				clearances[contact_ray_index] = 0.0

	var body_velocity = rig.get_core_linear_velocity()
	var target_offset = target_position_world - origin
	var target_distance = target_offset.length()
	var target_path_blocked = false
	var target_path_clearance = target_distance
	var target_wall_top_relative_height = 0.0
	if target_distance > TARGET_RAY_MARGIN_M:
		var target_direction = target_offset / target_distance
		var maximum_target_ray = maxf(target_distance - TARGET_RAY_MARGIN_M, 0.0)
		if wall_spatial_hash != null:
			var target_candidates = wall_spatial_hash.query_segment(
				origin,
				origin + target_direction * maximum_target_ray,
				maxf(inflation.x, inflation.z)
			)
			var target_hit = wall_spatial_hash.raycast_records(
				target_candidates,
				origin,
				target_direction,
				maximum_target_ray,
				inflation
			)
			if not target_hit.is_empty():
				target_path_blocked = true
				target_path_clearance = float(target_hit.get("distance_m", maximum_target_ray))
				target_wall_top_relative_height = float(
					target_hit.get("wall_top_world_y", origin.y)
				) - origin.y
		var boundary_distance := arena_boundary_distance(
			origin,
			target_direction,
			arena_size,
			inflation
		)
		if (
			boundary_distance >= 0.0
			and boundary_distance <= maximum_target_ray
			and (not target_path_blocked or boundary_distance < target_path_clearance)
		):
			target_path_blocked = true
			target_path_clearance = boundary_distance
			# Treat an open floor edge as a non-traversable vertical boundary in the model feed.
			target_wall_top_relative_height = maxf(arena_size.y - origin.y, 0.0)

	var nearest_direction_yaw_local = (
		(inverse_yaw_basis * nearest_direction_world).normalized()
		if nearest_direction_world.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED
		else Vector3.ZERO
	)
	return {
		"nearest_direction_world": nearest_direction_world,
		"nearest_direction_yaw_local": nearest_direction_yaw_local,
		"nearest_distance_m": nearest_distance,
		"maximum_distance_m": RAY_MAXIMUM_DISTANCE_M,
		"closing_speed_mps": maxf(body_velocity.dot(nearest_direction_world), 0.0),
		"ray_clearances_m": clearances,
		"ray_maximum_distance_m": RAY_MAXIMUM_DISTANCE_M,
		"target_path_blocked": target_path_blocked,
		"target_path_clearance_m": target_path_clearance,
		"target_path_maximum_distance_m": maxf(target_distance, 0.001),
		"target_wall_top_relative_height_m": target_wall_top_relative_height,
		"wall_contact": not wall_contacts.is_empty(),
		"wall_contact_count": int(contacts.get("wall_contact_count", wall_contacts.size())),
		"maximum_contact_impulse": float(contacts.get("maximum_contact_impulse", 0.0)),
	}


static func arena_boundary_distance(
	origin: Vector3,
	direction: Vector3,
	arena_size: Vector3,
	inflation: Vector3 = Vector3.ZERO
) -> float:
	# The room deliberately has an open viewing side. For a ground body that opening is a cliff,
	# so expose the floor rectangle as a virtual lidar boundary without adding a visible wall or
	# changing drone collision geometry. Distances are measured along a normalized 3D ray.
	if (
		not origin.is_finite()
		or not direction.is_finite()
		or not arena_size.is_finite()
		or not inflation.is_finite()
		or arena_size.x <= 0.0
		or arena_size.z <= 0.0
	):
		return -1.0
	var ray_direction := direction.normalized()
	if ray_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		return -1.0
	var half_width := maxf(arena_size.x * 0.5 - maxf(inflation.x, 0.0), 0.0)
	var half_depth := maxf(arena_size.z * 0.5 - maxf(inflation.z, 0.0), 0.0)
	if absf(origin.x) >= half_width or absf(origin.z) >= half_depth:
		return 0.0
	var nearest := INF
	if absf(ray_direction.x) > 0.000001:
		var x_plane := half_width if ray_direction.x > 0.0 else -half_width
		var x_distance := (x_plane - origin.x) / ray_direction.x
		if x_distance >= 0.0:
			var x_hit_z := origin.z + ray_direction.z * x_distance
			if absf(x_hit_z) <= half_depth + 0.0001:
				nearest = minf(nearest, x_distance)
	if absf(ray_direction.z) > 0.000001:
		var z_plane := half_depth if ray_direction.z > 0.0 else -half_depth
		var z_distance := (z_plane - origin.z) / ray_direction.z
		if z_distance >= 0.0:
			var z_hit_x := origin.x + ray_direction.x * z_distance
			if absf(z_hit_x) <= half_width + 0.0001:
				nearest = minf(nearest, z_distance)
	return nearest if is_finite(nearest) else -1.0


static func clear_probe() -> Dictionary:
	return FourLimbMLObservation.empty_obstacle_probe()


static func _ray_directions(yaw_basis: Basis) -> PackedVector3Array:
	var result = PackedVector3Array()
	result.resize(RAY_COUNT)
	for ray_index in range(RAY_COUNT):
		result[ray_index] = yaw_basis * LOCAL_RAY_DIRECTIONS[ray_index]
	return result


static func _yaw_basis(body_basis: Basis) -> Basis:
	var forward = -body_basis.z
	forward.y = 0.0
	if forward.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var right = forward.cross(Vector3.UP).normalized()
	return Basis(right, Vector3.UP, -forward).orthonormalized()


static func _body_inflation(definition: FourLimbBodyDefinition) -> Vector3:
	if definition == null:
		return Vector3(0.4, 0.2, 0.5)
	var maximum_limb_radius = 0.0
	for limb: FourLimbSlotDefinition in definition.limbs:
		if limb != null and limb.installed:
			maximum_limb_radius = maxf(maximum_limb_radius, limb.segment_radius)
	return Vector3(
		definition.core_size.x * 0.5 + maximum_limb_radius,
		definition.core_size.y * 0.5,
		definition.core_size.z * 0.5 + maximum_limb_radius
	)


static func _nearest_contact_direction(
	wall_contacts: Array,
	origin: Vector3
) -> Vector3:
	var nearest_distance_squared = INF
	var result = Vector3.ZERO
	for contact_value: Variant in wall_contacts:
		if not (contact_value is Dictionary):
			continue
		var contact: Dictionary = contact_value
		var position: Vector3 = contact.get("position_world", origin)
		var offset = position - origin
		var distance_squared = offset.length_squared()
		if distance_squared < nearest_distance_squared and distance_squared > MINIMUM_DIRECTION_LENGTH_SQUARED:
			nearest_distance_squared = distance_squared
			result = offset
	return result


static func _closest_ray_index(
	ray_directions_world: PackedVector3Array,
	world_direction: Vector3
) -> int:
	var best_index = -1
	var best_dot = -INF
	for ray_index in range(ray_directions_world.size()):
		var candidate_dot = ray_directions_world[ray_index].dot(world_direction)
		if candidate_dot > best_dot:
			best_dot = candidate_dot
			best_index = ray_index
	return best_index
