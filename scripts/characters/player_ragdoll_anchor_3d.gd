class_name PlayerRagdollAnchor3D
extends RigidBody3D

## Server-owned physical reference for a player's articulated presentation ragdoll. The authority
## simulates one compact torso instead of every cosmetic limb, then replicates its motion through the
## ordinary player snapshot. Recovery, interaction origin, audio listener, and every client therefore
## agree on where the fallen player actually is without paying for a full networked skeleton.

const BODY_COLLISION_LAYER := 1 << 2
const TORSO_SIZE := Vector3(0.70, 0.85, 0.40)
const TORSO_OFFSET_FROM_PLAYER := Vector3(0.0, 0.15, 0.0)
const TORSO_MASS := 6.5
const TRIP_LINEAR_IMPULSE := 1.25
const TRIP_DOWNWARD_IMPULSE := 0.35
const TRIP_ANGULAR_IMPULSE := 0.65

var _active := false
var _activation_sequence := 0
var _collision: CollisionShape3D


func _ready() -> void:
	top_level = true
	mass = TORSO_MASS
	collision_layer = BODY_COLLISION_LAYER
	collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	linear_damp = 0.25
	angular_damp = 0.45
	can_sleep = true
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = TORSO_SIZE
	_collision.shape = shape
	_collision.disabled = true
	add_child(_collision)
	freeze = true


func is_active() -> bool:
	return _active


func activate(
	player_transform: Transform3D,
	base_velocity: Vector3,
	trip_direction: Vector3,
	sequence: int
) -> void:
	if not is_node_ready():
		return
	_active = true
	_activation_sequence = maxi(sequence, _activation_sequence + 1)
	var upright_basis := Basis(Vector3.UP, player_transform.basis.get_euler().y)
	global_transform = Transform3D(
		upright_basis,
		player_transform.origin + TORSO_OFFSET_FROM_PLAYER
	)
	freeze = false
	linear_velocity = base_velocity if base_velocity.is_finite() else Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_collision.set_deferred("disabled", false)

	var safe_direction := Vector3(trip_direction.x, 0.0, trip_direction.z)
	if safe_direction.length_squared() <= 0.000001:
		safe_direction = -upright_basis.z
	else:
		safe_direction = safe_direction.normalized()
	# Jolt attaches a newly unfrozen body at the end of the frame. Applying the impulse before that
	# point is silently discarded, so retain the generation and apply it once the RID owns a space.
	call_deferred("_apply_trip_impulse", _activation_sequence, safe_direction)


func deactivate() -> void:
	_active = false
	_activation_sequence += 1
	if _collision != null:
		_collision.set_deferred("disabled", true)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func get_player_reference_position() -> Vector3:
	return global_position - TORSO_OFFSET_FROM_PLAYER


func get_collision_rid() -> RID:
	return get_rid()


func _apply_trip_impulse(sequence: int, safe_direction: Vector3) -> void:
	if not _active or sequence != _activation_sequence:
		return
	if not PhysicsServer3D.body_get_space(get_rid()).is_valid():
		return
	apply_central_impulse(
		safe_direction * TRIP_LINEAR_IMPULSE
		+ Vector3.DOWN * TRIP_DOWNWARD_IMPULSE
	)
	apply_torque_impulse(
		Vector3(safe_direction.z, 0.15, -safe_direction.x)
		* TRIP_ANGULAR_IMPULSE
	)
