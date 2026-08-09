class_name TurretTrainingProjectile3D
extends Node3D

signal resolved(projectile: TurretTrainingProjectile3D, hit: bool, target: TrainingCombatantAdapter, damage: float)

const TARGET_KINDS: Array[StringName] = [&"drone", &"four_limb", &"turret"]
const PROJECTILE_RADIUS_M = 0.045

var velocity_world = Vector3.ZERO
var remaining_distance_m = 0.0
var damage = 0.0
var shooter: TurretPhysicalBody3D
var shooter_adapter: TurretTrainingCombatantAdapter
var entity_spatial_hash: ServerSpatialHash3D
var wall_spatial_hash: DroneTrainingWallSpatialHash
var resolved_once = false
var reward_target_group_id: int = -1
var virtual_reward_target_enabled: bool = false
var virtual_reward_target_position_world: Vector3 = Vector3.ZERO
var virtual_reward_target_velocity_world: Vector3 = Vector3.ZERO
var virtual_reward_target_radius_m: float = 0.0
var reward_only_virtual_target: bool = false
var simulation_paused: bool = false


func configure(
	request: Dictionary,
	new_shooter_adapter: TurretTrainingCombatantAdapter,
	new_entity_spatial_hash: ServerSpatialHash3D,
	new_wall_spatial_hash: DroneTrainingWallSpatialHash,
	new_reward_target_group_id: int = -1,
	new_reward_target: Dictionary = {}
) -> bool:
	var direction: Vector3 = request.get("direction", Vector3.ZERO)
	var speed = float(request.get("speed_mps", 0.0))
	if direction.length_squared() <= 0.000001 or speed <= 0.0:
		return false
	global_position = request.get("origin", Vector3.ZERO)
	velocity_world = direction.normalized() * speed
	remaining_distance_m = maxf(float(request.get("maximum_range_m", 0.0)), 0.0)
	damage = maxf(float(request.get("damage", 0.0)), 0.0)
	shooter = request.get("shooter") as TurretPhysicalBody3D
	shooter_adapter = new_shooter_adapter
	entity_spatial_hash = new_entity_spatial_hash
	wall_spatial_hash = new_wall_spatial_hash
	reward_target_group_id = new_reward_target_group_id if new_reward_target_group_id >= 0 else -1
	_configure_virtual_reward_target(new_reward_target)
	_build_visual()
	return remaining_distance_m > 0.0 and damage > 0.0


func _physics_process(delta: float) -> void:
	if resolved_once or simulation_paused:
		return
	var travel = velocity_world * maxf(delta, 0.0)
	var travel_distance = minf(travel.length(), remaining_distance_m)
	if travel_distance <= 0.0:
		_resolve(false, null)
		return
	var direction: Vector3 = travel.normalized()
	var origin: Vector3 = global_position
	var destination: Vector3 = origin + direction * travel_distance
	var projectile_speed: float = maxf(velocity_world.length(), 0.000001)
	var travel_time: float = travel_distance / projectile_speed
	var wall_distance: float = _nearest_wall_distance(origin, direction, travel_distance)
	var entity_hit: Dictionary = _nearest_entity_hit(origin, direction, travel_distance)
	var entity_distance: float = float(entity_hit.get("distance_m", INF))
	var virtual_target_distance: float = _virtual_target_hit_distance(
		origin,
		direction * travel_distance,
		travel_time
	)
	var virtual_target_compare_distance: float = (
		virtual_target_distance if virtual_target_distance >= 0.0 else INF
	)
	if (
		wall_distance >= 0.0
		and wall_distance <= entity_distance
		and wall_distance <= virtual_target_compare_distance
	):
		global_position = origin + direction * wall_distance
		_resolve(false, null)
		return
	if virtual_target_distance >= 0.0 and virtual_target_distance <= entity_distance:
		global_position = origin + direction * virtual_target_distance
		_resolve_virtual_target_hit()
		return
	if not entity_hit.is_empty():
		global_position = origin + direction * entity_distance
		var target = entity_hit.get("adapter") as TrainingCombatantAdapter
		if target != null and target.receive_training_hit(
			damage,
			shooter_adapter.entity_id if shooter_adapter != null else 0,
			global_position,
			get_instance_id()
		):
			_resolve(true, target)
			return
	global_position = destination
	remaining_distance_m -= travel_distance
	if virtual_reward_target_enabled:
		virtual_reward_target_position_world += virtual_reward_target_velocity_world * travel_time
	if remaining_distance_m <= 0.000001:
		_resolve(false, null)


func _configure_virtual_reward_target(target_probe: Dictionary) -> void:
	virtual_reward_target_enabled = false
	reward_only_virtual_target = false
	virtual_reward_target_position_world = Vector3.ZERO
	virtual_reward_target_velocity_world = Vector3.ZERO
	virtual_reward_target_radius_m = 0.0
	if (
		target_probe.is_empty()
		or not bool(target_probe.get("present", false))
		or bool(target_probe.get("is_combat_target", false))
		or not bool(target_probe.get("is_shootable_target", false))
	):
		return
	var position_value: Variant = target_probe.get("position_world", null)
	var velocity_value: Variant = target_probe.get("velocity_world", Vector3.ZERO)
	if not (position_value is Vector3) or not (position_value as Vector3).is_finite():
		return
	if not (velocity_value is Vector3) or not (velocity_value as Vector3).is_finite():
		return
	virtual_reward_target_enabled = true
	reward_only_virtual_target = true
	virtual_reward_target_position_world = position_value as Vector3
	virtual_reward_target_velocity_world = velocity_value as Vector3
	virtual_reward_target_radius_m = maxf(
		RLTrainingMath.finite_float_or(target_probe.get("radius_m", 0.35), 0.35),
		0.05
	)


func _virtual_target_hit_distance(
	origin: Vector3,
	projectile_displacement: Vector3,
	travel_time: float
) -> float:
	if (
		not virtual_reward_target_enabled
		or projectile_displacement.length_squared() <= 0.000001
		or travel_time <= 0.0
	):
		return -1.0
	var relative_start: Vector3 = origin - virtual_reward_target_position_world
	var relative_motion: Vector3 = (
		projectile_displacement
		- virtual_reward_target_velocity_world * travel_time
	)
	var radius: float = virtual_reward_target_radius_m + PROJECTILE_RADIUS_M
	var c: float = relative_start.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a: float = relative_motion.length_squared()
	if a <= 0.000001:
		return -1.0
	var b: float = 2.0 * relative_start.dot(relative_motion)
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root: float = sqrt(discriminant)
	var first_fraction: float = (-b - root) / (2.0 * a)
	var second_fraction: float = (-b + root) / (2.0 * a)
	var hit_fraction: float = first_fraction
	if hit_fraction < 0.0 or hit_fraction > 1.0:
		hit_fraction = second_fraction
	if hit_fraction < 0.0 or hit_fraction > 1.0:
		return -1.0
	return projectile_displacement.length() * hit_fraction


func _resolve_virtual_target_hit() -> void:
	if resolved_once:
		return
	resolved_once = true
	if is_instance_valid(shooter):
		# The synthetic range target has no health pool, so it contributes one confirmed hit but
		# deliberately no damage-dealt bonus.
		shooter.notify_projectile_hit(0.0)
	resolved.emit(self, true, null, 0.0)
	queue_free()


func set_simulation_paused(value: bool) -> void:
	if resolved_once:
		return
	simulation_paused = value
	set_physics_process(not value)


func cancel_as_miss() -> void:
	if resolved_once:
		return
	# A real episode/evaluation horizon is part of the task. A round that has not reached its
	# target by that horizon is a miss, otherwise the policy can fire late and evade miss cost.
	resolved_once = true
	set_physics_process(false)
	if is_instance_valid(shooter):
		shooter.notify_projectile_missed()
	queue_free()


func cancel_without_reward() -> void:
	if resolved_once:
		return
	# Policy/target/configuration boundaries invalidate the old decision context rather than
	# representing a task miss. Do not leak these cancelled rounds into the replacement policy.
	resolved_once = true
	set_physics_process(false)
	queue_free()


func _nearest_wall_distance(origin: Vector3, direction: Vector3, maximum_distance: float) -> float:
	if wall_spatial_hash == null:
		return -1.0
	var records = wall_spatial_hash.query_segment(
		origin,
		origin + direction * maximum_distance,
		PROJECTILE_RADIUS_M
	)
	return wall_spatial_hash.raycast_distance_records(
		records,
		origin,
		direction,
		maximum_distance,
		Vector3.ONE * PROJECTILE_RADIUS_M
	)


func _nearest_entity_hit(origin: Vector3, direction: Vector3, maximum_distance: float) -> Dictionary:
	if entity_spatial_hash == null:
		return {}
	var midpoint = origin + direction * maximum_distance * 0.5
	var query_radius = maximum_distance * 0.5 + 2.0
	var nearest_distance = INF
	var nearest_adapter: TrainingCombatantAdapter = null
	for entity_key: StringName in entity_spatial_hash.query_keys_uncached(
		midpoint,
		query_radius,
		TARGET_KINDS
	):
		var record = entity_spatial_hash.get_record(entity_key)
		var metadata: Dictionary = record.get("metadata", {})
		var adapter = metadata.get("adapter") as TrainingCombatantAdapter
		if adapter == null or not adapter.is_alive():
			continue
		if shooter_adapter != null and adapter.entity_id == shooter_adapter.entity_id:
			continue
		if (
			shooter_adapter != null
			and adapter.team_id == shooter_adapter.team_id
			and (reward_target_group_id < 0 or adapter.group_id != reward_target_group_id)
		):
			continue
		var distance = _ray_sphere_distance(
			origin,
			direction,
			adapter.aim_point_world(),
			adapter.collision_radius_m() + PROJECTILE_RADIUS_M,
			maximum_distance
		)
		if distance >= 0.0 and distance < nearest_distance:
			nearest_distance = distance
			nearest_adapter = adapter
	return (
		{"distance_m": nearest_distance, "adapter": nearest_adapter}
		if nearest_adapter != null
		else {}
	)


static func _ray_sphere_distance(
	origin: Vector3,
	direction: Vector3,
	center: Vector3,
	radius: float,
	maximum_distance: float
) -> float:
	var offset = origin - center
	var b = offset.dot(direction)
	var c = offset.length_squared() - radius * radius
	if c > 0.0 and b > 0.0:
		return -1.0
	var discriminant = b * b - c
	if discriminant < 0.0:
		return -1.0
	var distance = -b - sqrt(discriminant)
	if distance < 0.0:
		distance = 0.0
	return distance if distance <= maximum_distance else -1.0


func _resolve(hit: bool, target: TrainingCombatantAdapter) -> void:
	if resolved_once:
		return
	resolved_once = true
	if is_instance_valid(shooter):
		var reward_eligible_hit: bool = (
			hit
			and target != null
			and not reward_only_virtual_target
			and (reward_target_group_id < 0 or target.group_id == reward_target_group_id)
		)
		if reward_eligible_hit:
			shooter.notify_projectile_hit(damage)
		else:
			# A physical hit on an unrelated worker still damages that body, but it must not be
			# credited as task success when this turret was explicitly assigned another group.
			shooter.notify_projectile_missed()
	resolved.emit(self, hit, target, damage)
	queue_free()


func _build_visual() -> void:
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = PROJECTILE_RADIUS_M
	mesh.height = PROJECTILE_RADIUS_M * 2.0
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
