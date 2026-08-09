class_name GrabberComponent
extends Node3D

#######################################################
# Implements the grabber component subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

signal load_changed(
	mobility_multiplier: float,
	shared_mass: float,
	is_immovable: bool
)

@export var enabled := true
@export var capability: GrabCapability
@export var carrier_path: NodePath
@export_range(0.0, 10.0, 0.05, "or_greater") var strength_multiplier := 1.0

var current_mobility_multiplier := 1.0
var current_shared_mass := 0.0
var is_holding_immovable_body := false
var current_force_ratio := 0.0
var current_tether_away_direction := Vector3.ZERO


func make_capability_unique() -> void:
	if capability != null:
		capability = capability.duplicate(true) as GrabCapability


func set_capability(value: GrabCapability, make_unique := true) -> void:
	capability = value

	if make_unique:
		make_capability_unique()


func can_grab() -> bool:
	return enabled and capability != null and get_effective_max_force() > 0.0


func get_effective_max_force() -> float:
	if capability == null:
		return 0.0

	return capability.max_force * strength_multiplier


func get_rotation_authority() -> float:
	if capability == null or is_holding_immovable_body:
		return 0.0

	var effective_mass_capacity = (
		capability.rotation_mass_capacity * strength_multiplier
	)
	return clampf(
		1.0 - current_shared_mass / maxf(effective_mass_capacity, 0.001),
		0.0,
		1.0
	)


func get_effective_max_rotation_torque() -> float:
	if capability == null:
		return 0.0

	return (
		capability.max_rotation_torque
		* strength_multiplier
		* get_rotation_authority()
	)


func get_grab_origin() -> Vector3:
	return global_position


func get_grab_direction() -> Vector3:
	return -global_basis.z.normalized()


func get_grab_target(
	grab_distance: float,
	lift_offset: float
) -> Vector3:
	if capability == null:
		return get_grab_origin()

	return (
		get_grab_origin()
		+ get_grab_direction() * grab_distance
		+ global_basis.y.normalized() * lift_offset
	)


func get_carrier_body() -> PhysicsBody3D:
	if not carrier_path.is_empty():
		return get_node_or_null(carrier_path) as PhysicsBody3D

	var candidate := get_parent()

	while candidate != null:
		if candidate is PhysicsBody3D:
			return candidate as PhysicsBody3D

		candidate = candidate.get_parent()

	return null


func get_carrier_velocity() -> Vector3:
	var carrier := get_carrier_body()

	if carrier is CharacterBody3D:
		return (carrier as CharacterBody3D).velocity

	if carrier is RigidBody3D:
		var rigid_carrier := carrier as RigidBody3D
		var offset := global_position - rigid_carrier.global_position

		return (
			rigid_carrier.linear_velocity
			+ rigid_carrier.angular_velocity.cross(offset)
		)

	return Vector3.ZERO


func apply_reaction_force(reaction_force: Vector3) -> void:
	var carrier := get_carrier_body() as RigidBody3D
	if carrier == null or carrier.freeze:
		return

	carrier.apply_force(
		reaction_force,
		global_position - carrier.global_position
	)


func apply_reaction_torque(reaction_torque: Vector3) -> void:
	var carrier := get_carrier_body() as RigidBody3D
	if carrier == null or carrier.freeze:
		return

	carrier.apply_torque(reaction_torque)


func apply_tether_force(
	required_force: float,
	effective_max_force: float,
	grabbed_point: Vector3
) -> void:
	current_force_ratio = (
		required_force / maxf(effective_max_force, 0.001)
	)

	var away_direction := global_position - grabbed_point
	away_direction.y = 0.0
	current_tether_away_direction = away_direction.normalized()


func get_tether_restraint() -> float:
	if capability == null:
		return 0.0

	return capability.calculate_tether_restraint(current_force_ratio)


func constrain_horizontal_velocity(value: Vector3) -> Vector3:
	var direction := current_tether_away_direction
	if direction.length_squared() < 0.000001:
		return value

	var away_speed := value.dot(direction)
	if away_speed <= 0.0:
		return value

	return (
		value
		- direction * away_speed * get_tether_restraint()
	)


func apply_load(shared_mass: float, is_immovable: bool) -> void:
	current_shared_mass = maxf(shared_mass, 0.0)
	is_holding_immovable_body = is_immovable

	if capability == null:
		current_mobility_multiplier = 1.0
	else:
		current_mobility_multiplier = (
			capability.calculate_mobility_multiplier(
				current_shared_mass,
				is_holding_immovable_body
			)
		)

	load_changed.emit(
		current_mobility_multiplier,
		current_shared_mass,
		is_holding_immovable_body
	)


func clear_load() -> void:
	current_force_ratio = 0.0
	current_tether_away_direction = Vector3.ZERO
	apply_load(0.0, false)
