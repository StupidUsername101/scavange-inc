class_name DroneTrainingCombatantAdapter
extends TrainingCombatantAdapter

var drone: ServerDrone


func _init(
	owner_drone: ServerDrone = null,
	new_entity_id: int = 0,
	new_group_id: int = -1,
	new_worker_id: int = -1,
	new_team_id: int = 1
) -> void:
	drone = owner_drone
	super(owner_drone, &"drone", new_entity_id, new_group_id, new_worker_id, new_team_id)


func is_alive() -> bool:
	return simulation_active and is_instance_valid(drone) and drone.current_health > 0.0


func world_position() -> Vector3:
	return drone.global_position if is_instance_valid(drone) else Vector3.ZERO


func aim_point_world() -> Vector3:
	return world_position()


func orientation_basis_world() -> Basis:
	return drone.global_basis.orthonormalized() if is_instance_valid(drone) else Basis.IDENTITY


func linear_velocity_world() -> Vector3:
	return drone.linear_velocity if is_instance_valid(drone) else Vector3.ZERO


func collision_radius_m() -> float:
	if not is_instance_valid(drone):
		return 0.5
	return maxf(0.35, sqrt(maxf(drone.mass, 0.1)) * 0.18)


func _apply_physical_damage(damage: float) -> void:
	if is_instance_valid(drone):
		drone.apply_damage(damage)
