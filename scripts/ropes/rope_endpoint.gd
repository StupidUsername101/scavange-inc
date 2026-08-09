class_name RopeEndpoint
extends RefCounted

#######################################################
# Implements the rope endpoint subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

var body: PhysicsBody3D
var local_anchor := Vector3.ZERO
var local_surface_normal := Vector3.UP
var surface_offset := 0.02


func _init(
	attached_body: PhysicsBody3D,
	world_anchor: Vector3,
	world_surface_normal: Vector3,
	anchor_surface_offset: float
) -> void:
	body = attached_body
	local_anchor = body.to_local(world_anchor) if body != null else world_anchor
	var safe_normal := world_surface_normal.normalized()
	if safe_normal.length_squared() < 0.000001:
		safe_normal = Vector3.UP
	local_surface_normal = (
		body.global_basis.inverse() * safe_normal
		if body != null
		else safe_normal
	).normalized()
	surface_offset = maxf(anchor_surface_offset, 0.0)


func is_valid() -> bool:
	return is_instance_valid(body) and body.is_inside_tree()


func get_surface_position() -> Vector3:
	if not is_valid():
		return local_anchor
	return body.to_global(local_anchor)


func get_world_normal() -> Vector3:
	if not is_valid():
		return local_surface_normal
	var result := (body.global_basis * local_surface_normal).normalized()
	return result if result.length_squared() > 0.000001 else Vector3.UP


func get_rope_position() -> Vector3:
	return get_surface_position() + get_world_normal() * surface_offset


func get_point_velocity() -> Vector3:
	if not is_valid():
		return Vector3.ZERO
	var rigid_body := body as RigidBody3D
	if rigid_body != null:
		var offset := get_surface_position() - rigid_body.global_position
		return (
			rigid_body.linear_velocity
			+ rigid_body.angular_velocity.cross(offset)
		)
	var character_body := body as CharacterBody3D
	if character_body != null:
		return character_body.velocity
	return Vector3.ZERO


func apply_force(force: Vector3) -> void:
	if not is_valid() or not force.is_finite():
		return
	var rigid_body := body as RigidBody3D
	if rigid_body == null or rigid_body.freeze:
		return
	rigid_body.apply_force(
		force,
		get_surface_position() - rigid_body.global_position
	)


func append_collision_exclusion(result: Array[RID]) -> void:
	if is_valid():
		result.append(body.get_rid())
