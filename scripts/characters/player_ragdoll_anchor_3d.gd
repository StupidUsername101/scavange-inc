class_name PlayerRagdollAnchor3D
extends RigidBody3D

## Server-owned physical reference for a player's articulated presentation ragdoll. The authority
## simulates one compact torso instead of every cosmetic limb, then replicates its motion through the
## ordinary player snapshot. Recovery, interaction origin, audio listener, and every client therefore
## agree on where the fallen player actually is without paying for a full networked skeleton.

const BODY_COLLISION_LAYER := 1 << 2
const TORSO_COLLISION_RADIUS := 0.30
const TORSO_COLLISION_HEIGHT := 0.82
const TORSO_OFFSET_FROM_PLAYER := Vector3(0.0, 0.15, 0.0)
# This compact server shape represents the complete articulated body, not only the visible torso.
# Match the cosmetic segment total so contacts with dynamic world objects carry believable inertia.
const TORSO_MASS := 69.8
const CONTACT_FRICTION := 0.18
const TRIP_FORWARD_DELTA_SPEED := 0.24
const TRIP_DOWNWARD_DELTA_SPEED := 0.07
const TRIP_ANGULAR_IMPULSE_PER_MASS := 0.12

var _active := false
var _activation_sequence := 0
var _collision: CollisionShape3D
var _trip_impulse_pending := false
var _pending_trip_direction := Vector3.FORWARD


func _ready() -> void:
	top_level = true
	mass = TORSO_MASS
	collision_layer = BODY_COLLISION_LAYER
	collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	linear_damp = 0.25
	angular_damp = 0.45
	can_sleep = true
	continuous_cd = true
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = CONTACT_FRICTION
	contact_material.bounce = 0.0
	physics_material_override = contact_material
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	# The authority only needs a compact physical reference, not a silhouette-perfect torso. Rounded
	# support cannot hook a box corner beneath a stair nosing or between adjacent modular colliders.
	var shape := CapsuleShape3D.new()
	shape.radius = TORSO_COLLISION_RADIUS
	shape.height = TORSO_COLLISION_HEIGHT
	_collision.shape = shape
	_collision.disabled = true
	add_child(_collision)
	freeze = true
	set_physics_process(false)


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
	# Jolt attaches a newly unfrozen body at the end of the frame. Retain the impulse until the first
	# physics tick with a valid space instead of gambling on a single deferred call.
	_pending_trip_direction = safe_direction
	_trip_impulse_pending = true
	set_physics_process(true)


func deactivate() -> void:
	_active = false
	_trip_impulse_pending = false
	set_physics_process(false)
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


func _physics_process(_delta: float) -> void:
	if not _active or not _trip_impulse_pending:
		set_physics_process(false)
		return
	_trip_impulse_pending = not _apply_trip_impulse(
		_activation_sequence,
		_pending_trip_direction
	)
	if not _trip_impulse_pending:
		set_physics_process(false)


func _apply_trip_impulse(sequence: int, safe_direction: Vector3) -> bool:
	if not _active or sequence != _activation_sequence:
		return false
	if not PhysicsServer3D.body_get_space(get_rid()).is_valid():
		return false
	apply_central_impulse(
		(
			safe_direction * TRIP_FORWARD_DELTA_SPEED
			+ Vector3.DOWN * TRIP_DOWNWARD_DELTA_SPEED
		) * mass
	)
	apply_torque_impulse(
		Vector3(safe_direction.z, 0.15, -safe_direction.x)
		* TRIP_ANGULAR_IMPULSE_PER_MASS
		* mass
	)
	return true
