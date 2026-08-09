class_name TrainingTurretThreatSensor
extends RefCounted

const TURRET_KIND: StringName = &"turret"
const TURRET_KINDS: Array[StringName] = [&"turret"]
const DEFAULT_MAXIMUM_DISTANCE_M = 80.0

#######################################################
# Shared, body-agnostic turret-threat probe. Drone and limb workers receive the same bounded
# contract, while the concrete observation encoders choose their own versioned tensor layout.
#######################################################


static func acquire(
	observer: TrainingCombatantAdapter,
	entity_spatial_hash: ServerSpatialHash3D,
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	maximum_distance_m: float = DEFAULT_MAXIMUM_DISTANCE_M
) -> Dictionary:
	var maximum_distance = maxf(maximum_distance_m, 0.1)
	if observer == null or not observer.is_alive() or entity_spatial_hash == null:
		return empty_probe(maximum_distance)
	if not entity_spatial_hash.has_kind(TURRET_KIND):
		return empty_probe(maximum_distance)
	var observer_position = observer.aim_point_world()
	var nearest_adapter: TurretTrainingCombatantAdapter = null
	var nearest_distance = INF
	for key: StringName in entity_spatial_hash.readonly_keys_for_kind(TURRET_KIND):
		var record = entity_spatial_hash.get_record(key)
		var metadata: Dictionary = record.get("metadata", {})
		var candidate = metadata.get("adapter") as TurretTrainingCombatantAdapter
		if candidate == null or not candidate.is_alive():
			continue
		if candidate.entity_id == observer.entity_id or candidate.team_id == observer.team_id:
			continue
		var distance = observer_position.distance_to(candidate.aim_point_world())
		if distance > maximum_distance:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_adapter = candidate
	if nearest_adapter == null:
		return empty_probe(maximum_distance)
	var turret = nearest_adapter.turret
	if not is_instance_valid(turret) or turret.loadout == null:
		return empty_probe(maximum_distance)
	var muzzle_position = turret.muzzle_position_world()
	var offset_world = muzzle_position - observer_position
	var distance_m = offset_world.length()
	var direction_world = offset_world / distance_m if distance_m > 0.000001 else Vector3.ZERO
	var body_basis = observer.orientation_basis_world()
	var direction_local = body_basis.inverse() * direction_world
	var line_of_sight = not _segment_blocked(
		wall_spatial_hash,
		muzzle_position,
		observer_position,
		observer.collision_radius_m() * 0.25
	)
	var turret_to_observer = observer_position - muzzle_position
	var turret_aim_alignment = -1.0
	if turret_to_observer.length_squared() > 0.000001:
		turret_aim_alignment = turret.aim_direction_world().dot(turret_to_observer.normalized())
	var projectile_speed = maxf(turret.loadout.gun.projectile_speed_mps, 0.1)
	return {
		"present": true,
		"entity_id": nearest_adapter.entity_id,
		"group_id": nearest_adapter.group_id,
		"position_world": nearest_adapter.world_position(),
		"muzzle_position_world": muzzle_position,
		"direction_world": direction_world,
		"direction_local": direction_local,
		"distance_m": distance_m,
		"maximum_distance_m": maximum_distance,
		"line_of_sight": line_of_sight,
		"aim_alignment": clampf(turret_aim_alignment, -1.0, 1.0),
		"cooldown_ready_ratio": turret.cooldown_ready_ratio(),
		"projectile_speed_mps": projectile_speed,
		"estimated_time_to_impact_s": distance_m / projectile_speed,
		"threat_level": _threat_level(
			distance_m,
			maximum_distance,
			turret_aim_alignment,
			line_of_sight,
			turret.cooldown_ready_ratio()
		),
	}


static func cache_id_for(observer: TrainingCombatantAdapter) -> StringName:
	if observer == null:
		return &""
	return StringName("%s:turret_threat" % String(observer.spatial_key()))


static func empty_probe(maximum_distance_m: float = DEFAULT_MAXIMUM_DISTANCE_M) -> Dictionary:
	return {
		"present": false,
		"entity_id": 0,
		"group_id": -1,
		"position_world": Vector3.ZERO,
		"muzzle_position_world": Vector3.ZERO,
		"direction_world": Vector3.ZERO,
		"direction_local": Vector3.ZERO,
		"distance_m": maxf(maximum_distance_m, 0.1),
		"maximum_distance_m": maxf(maximum_distance_m, 0.1),
		"line_of_sight": false,
		"aim_alignment": -1.0,
		"cooldown_ready_ratio": 0.0,
		"projectile_speed_mps": 0.0,
		"estimated_time_to_impact_s": 0.0,
		"threat_level": 0.0,
	}


static func _threat_level(
	distance_m: float,
	maximum_distance_m: float,
	aim_alignment: float,
	line_of_sight: bool,
	cooldown_ready_ratio: float
) -> float:
	if not line_of_sight:
		return 0.0
	var proximity = 1.0 - clampf(distance_m / maxf(maximum_distance_m, 0.1), 0.0, 1.0)
	var aim = smoothstep(0.80, 0.995, clampf(aim_alignment, -1.0, 1.0))
	return clampf(proximity * aim * clampf(cooldown_ready_ratio, 0.0, 1.0), 0.0, 1.0)


static func _segment_blocked(
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	origin: Vector3,
	destination: Vector3,
	padding_m: float
) -> bool:
	if wall_spatial_hash == null:
		return false
	var delta = destination - origin
	var distance = delta.length()
	if distance <= 0.000001:
		return false
	var records = wall_spatial_hash.query_segment(origin, destination, maxf(padding_m, 0.0))
	var hit_distance = wall_spatial_hash.raycast_distance_records(
		records,
		origin,
		delta / distance,
		distance,
		Vector3.ONE * maxf(padding_m, 0.0)
	)
	return hit_distance >= 0.0 and hit_distance < distance - 0.05
