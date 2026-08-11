class_name DroneTrainingEditorRaycast
extends RefCounted

#######################################################
# Shared ray-query rules for training-room editor tools. The simulation room owns editor state;
# this helper only performs deterministic hit filtering so placement and selection do not drift.
#######################################################


static func authored_surface_hit(
	camera: Camera3D,
	world: World3D,
	screen_position: Vector2,
	ray_length_m: float,
	collision_mask: int,
	maximum_retries: int,
	minimum_up_normal_y: float,
	allow_authored_training_items: bool
) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _ray_query(
		camera,
		world,
		screen_position,
		ray_length_m,
		collision_mask
	)
	if query == null:
		return {}
	var exclusions: Array[RID] = []
	for _attempt_index: int in range(maxi(maximum_retries, 0)):
		query.exclude = exclusions
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Node3D = hit.get("collider") as Node3D
		if collider == null:
			return {}
		var authored_item: bool = (
			allow_authored_training_items
			and collider is TrainingItem3D
			and bool(collider.get_meta("training_authored_item", false))
		)
		var supported_surface: bool = (
			authored_item
			or bool(collider.get_meta("training_ground", false))
			or bool(collider.get_meta("training_custom_wall", false))
			or bool(collider.get_meta("training_wall", false))
		)
		var normal_value: Variant = hit.get("normal", Vector3.UP)
		var point_value: Variant = hit.get("position", Vector3.ZERO)
		if (
			supported_surface
			and normal_value is Vector3
			and point_value is Vector3
			and (normal_value as Vector3).is_finite()
			and (point_value as Vector3).is_finite()
			and (normal_value as Vector3).y >= minimum_up_normal_y
		):
			return {
				"point": point_value as Vector3,
				"normal": normal_value as Vector3,
				"collider": collider,
			}
		if not _exclude_collider(collider, exclusions):
			return {}
	return {}


static func pick_authored_training_item(
	camera: Camera3D,
	world: World3D,
	screen_position: Vector2,
	ray_length_m: float,
	collision_mask: int,
	maximum_retries: int
) -> TrainingItem3D:
	var query: PhysicsRayQueryParameters3D = _ray_query(
		camera,
		world,
		screen_position,
		ray_length_m,
		collision_mask
	)
	if query == null:
		return null
	var exclusions: Array[RID] = []
	for _attempt_index: int in range(maxi(maximum_retries, 0)):
		query.exclude = exclusions
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return null
		var item: TrainingItem3D = hit.get("collider") as TrainingItem3D
		if item == null:
			# Arena/obstacle geometry intentionally occludes item selection.
			return null
		if bool(item.get_meta("training_authored_item", false)):
			return item
		# Fallback lesson cargo is simulation content, not editor content. Look through it so it
		# cannot make an authored item behind it impossible to select.
		if not _exclude_collider(item, exclusions):
			return null
	return null


static func pick_custom_wall(
	camera: Camera3D,
	world: World3D,
	screen_position: Vector2,
	ray_length_m: float,
	collision_mask: int,
	maximum_retries: int
) -> StaticBody3D:
	var query: PhysicsRayQueryParameters3D = _ray_query(
		camera,
		world,
		screen_position,
		ray_length_m,
		collision_mask
	)
	if query == null:
		return null
	var exclusions: Array[RID] = []
	for _attempt_index: int in range(maxi(maximum_retries, 0)):
		query.exclude = exclusions
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return null
		var collider: Node3D = hit.get("collider") as Node3D
		var wall: StaticBody3D = collider as StaticBody3D
		if (
			wall != null
			and bool(wall.get_meta("training_custom_wall", false))
		):
			return wall
		# Item bodies may sit in front of an authored wall. They are handled by the item picker
		# first, so this wall-specific query may safely look through them and only them.
		if not (collider is TrainingItem3D):
			return null
		if not _exclude_collider(collider, exclusions):
			return null
	return null


static func _ray_query(
	camera: Camera3D,
	world: World3D,
	screen_position: Vector2,
	ray_length_m: float,
	collision_mask: int
) -> PhysicsRayQueryParameters3D:
	if camera == null or world == null:
		return null
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if not ray_origin.is_finite() or not ray_direction.is_finite():
		return null
	if ray_direction.length_squared() <= 0.000001:
		return null
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * maxf(ray_length_m, 0.0),
		collision_mask
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return query


static func _exclude_collider(collider: Node3D, exclusions: Array[RID]) -> bool:
	var collision_object: CollisionObject3D = collider as CollisionObject3D
	if collision_object == null:
		return false
	var collider_rid: RID = collision_object.get_rid()
	if not collider_rid.is_valid() or exclusions.has(collider_rid):
		return false
	exclusions.append(collider_rid)
	return true
