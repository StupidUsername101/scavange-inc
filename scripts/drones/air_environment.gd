class_name AirEnvironment
extends Node3D

#######################################################
# Implements the air environment subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

@export_group("Atmosphere")
@export_range(0.01, 10.0, 0.001, "or_greater") var air_density := 1.225
@export_range(0.000001, 1.0, 0.000001, "or_greater") var dynamic_viscosity := 0.0000181
@export var wind_velocity := Vector3.ZERO

@export_group("Ground Effect")
@export_range(0.0, 10.0, 0.01, "or_greater") var ground_effect_strength := 0.35
@export_range(0.01, 100.0, 0.01, "or_greater") var ground_effect_falloff_distance := 1.2
@export_range(0.1, 1000.0, 0.1, "or_greater") var ground_probe_distance := 8.0
@export_flags_3d_physics var ground_collision_mask := 1


func _enter_tree() -> void:
	add_to_group("air_environment")


func calculate_rotor_thrust(
	shaft_power: float,
	disk_area: float,
	efficiency: float
) -> float:
	if shaft_power <= 0.0 or disk_area <= 0.0:
		return 0.0

	# Inverse of ideal rotor induced power:
	# P = T^(3/2) / sqrt(2 * rho * A).
	var useful_power_term := (
		shaft_power
		* clampf(efficiency, 0.01, 1.0)
		* sqrt(2.0 * air_density * disk_area)
	)
	return pow(maxf(useful_power_term, 0.0), 2.0 / 3.0)


func calculate_rotor_power(
	thrust: float,
	disk_area: float,
	efficiency: float
) -> float:
	if thrust <= 0.0 or disk_area <= 0.0:
		return 0.0

	# Inverse of calculate_rotor_thrust. Flight control asks for force; the
	# battery/rotor system then decides whether that force can be afforded.
	var denominator := (
		clampf(efficiency, 0.01, 1.0)
		* sqrt(2.0 * air_density * disk_area)
	)
	return pow(thrust, 1.5) / maxf(denominator, 0.0001)


func calculate_induced_velocity(
	thrust: float,
	disk_area: float
) -> float:
	return sqrt(
		maxf(thrust, 0.001)
		/ (2.0 * air_density * maxf(disk_area, 0.001))
	)


func calculate_ground_effect(
	space_state: PhysicsDirectSpaceState3D,
	rotor_position: Vector3,
	excluded_body: RID,
	lift_axis: Vector3 = Vector3.UP
) -> float:
	# Ground/wall proximity belongs to the rotor disc, not to world-down. Creator-authored rotors
	# can point sideways or diagonally, so probe opposite the actual thrust axis. The default keeps
	# legacy callers identical for conventional upward-facing rotors.
	var safe_lift_axis: Vector3 = lift_axis
	if not safe_lift_axis.is_finite() or safe_lift_axis.length_squared() <= 0.000001:
		safe_lift_axis = Vector3.UP
	var probe_direction: Vector3 = -safe_lift_axis.normalized()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		rotor_position,
		rotor_position + probe_direction * ground_probe_distance
	)
	query.collision_mask = ground_collision_mask
	query.exclude = [excluded_body]
	query.collide_with_areas = false

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0

	var hit_position: Vector3 = hit.get("position", rotor_position)
	var clearance: float = maxf((hit_position - rotor_position).dot(probe_direction), 0.0)
	return 1.0 + ground_effect_strength * exp(
		-clearance / maxf(ground_effect_falloff_distance, 0.01)
	)


func calculate_linear_drag(
	relative_air_velocity: Vector3,
	drag_area: float,
	drag_coefficient: float
) -> Vector3:
	var speed := relative_air_velocity.length()
	if speed <= 0.0001:
		return Vector3.ZERO

	return (
		-relative_air_velocity.normalized()
		* 0.5
		* air_density
		* maxf(drag_coefficient, 0.0)
		* maxf(drag_area, 0.0)
		* speed * speed
	)
