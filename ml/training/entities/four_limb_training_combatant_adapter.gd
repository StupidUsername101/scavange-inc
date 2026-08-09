class_name FourLimbTrainingCombatantAdapter
extends TrainingCombatantAdapter

var limb_body: FourLimbPhysicalBody3D


func _init(
	owner_body: FourLimbPhysicalBody3D = null,
	new_entity_id: int = 0,
	new_group_id: int = -1,
	new_worker_id: int = -1,
	new_team_id: int = 1
) -> void:
	limb_body = owner_body
	super(owner_body, &"four_limb", new_entity_id, new_group_id, new_worker_id, new_team_id)


func is_alive() -> bool:
	return simulation_active and is_instance_valid(limb_body) and limb_body.is_body_alive()


func world_position() -> Vector3:
	return (
		limb_body.core_transform().origin
		if is_instance_valid(limb_body)
		else Vector3.ZERO
	)


func aim_point_world() -> Vector3:
	return world_position()


func orientation_basis_world() -> Basis:
	return (
		limb_body.core_transform().basis.orthonormalized()
		if is_instance_valid(limb_body)
		else Basis.IDENTITY
	)


func linear_velocity_world() -> Vector3:
	if not is_instance_valid(limb_body) or not is_instance_valid(limb_body.physical_rig):
		return Vector3.ZERO
	var core = limb_body.physical_rig.core_bone
	return core.linear_velocity if is_instance_valid(core) else Vector3.ZERO


func collision_radius_m() -> float:
	if not is_instance_valid(limb_body) or limb_body.definition == null:
		return 0.65
	return maxf(0.45, limb_body.definition.core_size.length() * 0.45)


func _apply_physical_damage(damage: float) -> void:
	# The limb training body deliberately remains physically invulnerable so early exploratory
	# policies do not destroy their expensive articulated rig. The combat ledger still exposes
	# every hit to observations and rewards, while gameplay bodies continue using real damage.
	if is_instance_valid(limb_body) and not limb_body.training_invulnerable:
		limb_body.apply_damage(damage)
