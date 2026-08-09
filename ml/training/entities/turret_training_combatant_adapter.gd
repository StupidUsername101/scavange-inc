class_name TurretTrainingCombatantAdapter
extends TrainingCombatantAdapter

var turret: TurretPhysicalBody3D


func _init(
	owner_turret: TurretPhysicalBody3D = null,
	new_entity_id: int = 0,
	new_group_id: int = -1,
	new_worker_id: int = -1,
	new_team_id: int = 2
) -> void:
	turret = owner_turret
	super(owner_turret, &"turret", new_entity_id, new_group_id, new_worker_id, new_team_id)


func is_alive() -> bool:
	return simulation_active and is_instance_valid(turret) and turret.is_body_alive()


func world_position() -> Vector3:
	return turret.global_position if is_instance_valid(turret) else Vector3.ZERO


func aim_point_world() -> Vector3:
	return (
		turret.muzzle_position_world()
		if is_instance_valid(turret)
		else Vector3.ZERO
	)


func orientation_basis_world() -> Basis:
	return turret.global_basis.orthonormalized() if is_instance_valid(turret) else Basis.IDENTITY


func linear_velocity_world() -> Vector3:
	return Vector3.ZERO


func collision_radius_m() -> float:
	if not is_instance_valid(turret) or turret.loadout == null:
		return 0.55
	return maxf(0.4, turret.loadout.base.footprint_size.length() * 0.45)


func _apply_physical_damage(damage: float) -> void:
	if is_instance_valid(turret):
		turret.apply_damage(damage)
