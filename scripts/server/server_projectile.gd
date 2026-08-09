class_name ServerProjectile
extends Node3D

const WORLD_GRAVITY := 9.8
const MINIMUM_MOTION_LENGTH_SQUARED := 0.000001

#######################################################
# Advances an authoritative projectile, performs swept collision, and applies damage and
# impulse on impact.
#######################################################

var projectile_id := -1
var profile: Dictionary = {}
var velocity := Vector3.ZERO
var launch_direction := Vector3.FORWARD
var distance_traveled := 0.0
var excluded_rids: Array[RID] = []
var source_kind: StringName = &"unknown"
var source_id := -1
var source_slot := -1
var resolved := false


func configure(
	new_projectile_id: int,
	new_profile: Dictionary,
	origin: Vector3,
	direction: Vector3,
	inherited_velocity: Vector3,
	exclusions: Array,
	new_source_kind: StringName,
	new_source_id: int,
	new_source_slot: int
) -> void:
	projectile_id = new_projectile_id
	profile = BallisticProjectileDefinition.normalize_profile(new_profile)
	global_position = origin
	launch_direction = direction.normalized()
	velocity = (
		launch_direction * float(profile["muzzle_velocity"])
		+ inherited_velocity
	)
	excluded_rids.clear()
	for value: Variant in exclusions:
		if value is RID:
			excluded_rids.append(value)
	source_kind = new_source_kind
	source_id = new_source_id
	source_slot = new_source_slot


func server_physics_tick(delta: float) -> void:
	if resolved or not is_inside_tree():
		return

	velocity += (
		Vector3.DOWN
		* WORLD_GRAVITY
		* float(profile.get("gravity_scale", 0.0))
		* delta
	)
	var start := global_position
	var motion := velocity * delta
	var remaining_range := maxf(
		float(profile.get(
			"maximum_range",
			BallisticProjectileDefinition.MIN_MAXIMUM_RANGE
		)) - distance_traveled,
		0.0
	)
	if remaining_range <= MINIMUM_MOTION_LENGTH_SQUARED:
		_resolve()
		return
	if (
		motion.length() >= remaining_range
		and motion.length_squared() > MINIMUM_MOTION_LENGTH_SQUARED
	):
		motion = motion.normalized() * remaining_range
	var finish := start + motion
	var step_distance := start.distance_to(finish)
	var query := PhysicsRayQueryParameters3D.create(start, finish)
	query.exclude = excluded_rids
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.get("position", finish)
		_resolve_impact(hit)
		return

	global_position = finish
	distance_traveled += step_distance
	if distance_traveled >= float(profile.get(
		"maximum_range",
		BallisticProjectileDefinition.MIN_MAXIMUM_RANGE
	)):
		_resolve()


func _resolve_impact(hit: Dictionary) -> void:
	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("apply_damage"):
		collider.call("apply_damage", float(profile.get("damage", 0.0)))

	var rigid_body := collider as RigidBody3D
	if rigid_body != null:
		var direction := velocity.normalized()
		var impulse := (
			direction * float(profile.get("impact_impulse", 0.0))
		)
		var hit_position: Vector3 = hit.get(
			"position",
			rigid_body.global_position
		)
		rigid_body.apply_impulse(
			impulse,
			hit_position - rigid_body.global_position
		)
	_resolve()


func _resolve() -> void:
	if resolved:
		return
	resolved = true
	Server.despawn_projectile(projectile_id)


func to_state_dict() -> Dictionary:
	return {
		"projectile_id": projectile_id,
		"pos": global_position,
		"velocity": velocity,
		"launch_direction": launch_direction,
		"distance_traveled": distance_traveled,
		"visual_definition_path": str(
			profile.get("visual_definition_path", "")
		),
		"tracer_color": profile.get(
			"tracer_color",
			BallisticProjectileDefinition.DEFAULT_TRACER_COLOR
		),
		"tracer_length": float(profile.get(
			"tracer_length",
			BallisticProjectileDefinition.DEFAULT_TRACER_LENGTH
		)),
		"tracer_radius": float(profile.get(
			"tracer_radius",
			BallisticProjectileDefinition.DEFAULT_TRACER_RADIUS
		)),
		"source_kind": source_kind,
		"source_id": source_id,
		"source_slot": source_slot,
	}
