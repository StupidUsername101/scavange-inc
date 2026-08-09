@tool
class_name GrabCapability
extends Resource

#######################################################
# Implements the grab capability subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

@export_group("Reach")
@export_range(0.1, 100.0, 0.05, "or_greater") var max_distance := 4.0
@export_range(0.0, 100.0, 0.05, "or_greater") var min_distance := 0.75
@export_range(0.1, 200.0, 0.1, "or_greater") var break_distance := 6.0
@export_range(-10.0, 10.0, 0.05) var lift_offset := 0.35

@export_group("Force")
@export_range(0.0, 1000.0, 1.0, "or_greater") var spring_acceleration := 60.0
@export_range(0.0, 1000.0, 0.5, "or_greater") var damping_acceleration := 12.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var max_force := 180.0

@export_group("Carrier Impact")
@export_range(0.01, 100000.0, 0.1, "or_greater") var mobility_mass_capacity := 40.0

@export_group("Tether Movement")
@export_range(0.0, 1.0, 0.01) var tether_slowdown_start_ratio := 0.5
@export_range(0.01, 2.0, 0.01, "or_greater") var tether_lock_ratio := 1.0

@export_group("Jump Lift")
@export_range(1.0, 3.0, 0.05, "or_greater") var jump_lift_force_multiplier := 1.15
@export_range(0.0, 10.0, 0.05, "or_greater") var jump_lift_min_velocity := 0.5

@export_group("Rotation")
@export_range(0.0001, 0.05, 0.0001, "or_greater") var rotation_radians_per_pixel := 0.004
@export_range(0.0, 20.0, 0.05, "or_greater") var max_rotation_speed := 1.5
@export_range(0.0, 100.0, 0.5, "or_greater") var rotation_acceleration := 8.0
@export_range(0.0, 10000.0, 0.5, "or_greater") var max_rotation_torque := 35.0
@export_range(0.01, 10000.0, 0.1, "or_greater") var rotation_mass_capacity := 20.0
@export_range(0.0, 1.0, 0.01) var rotation_anchor_centering := 0.98

@export_group("Rotation Hold")
@export_range(1.0, 20.0, 0.1, "or_greater") var rotation_hold_spring_multiplier := 3.0
@export_range(1.0, 20.0, 0.1, "or_greater") var rotation_hold_damping_multiplier := 4.0
@export_range(0.0, 2.0, 0.01, "or_greater") var rotation_settle_duration := 0.22
@export_range(0.0, 100.0, 0.5, "or_greater") var rotation_settle_damping := 22.0


func get_clamped_min_distance() -> float:
	return clampf(min_distance, 0.0, max_distance)


func get_clamped_break_distance() -> float:
	return maxf(break_distance, 0.1)


func calculate_mobility_multiplier(
	shared_mass: float,
	is_immovable: bool
) -> float:
	if is_immovable:
		return 0.0

	return clampf(
		1.0 - shared_mass / mobility_mass_capacity,
		0.0,
		1.0
	)


func calculate_tether_restraint(force_ratio: float) -> float:
	var start_ratio := maxf(tether_slowdown_start_ratio, 0.0)
	var lock_ratio := maxf(tether_lock_ratio, start_ratio + 0.001)
	var weight := clampf(
		(force_ratio - start_ratio) / (lock_ratio - start_ratio),
		0.0,
		1.0
	)

	# Smoothly grows from free movement to a fully taut tether.
	return weight * weight * (3.0 - 2.0 * weight)
