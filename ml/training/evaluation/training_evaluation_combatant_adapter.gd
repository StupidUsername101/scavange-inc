class_name TrainingEvaluationCombatantAdapter
extends TrainingCombatantAdapter

#######################################################
# Lightweight deterministic target used only by hidden fixed-seed evaluator jobs. It gives
# turret/projectile/threat code a normal TrainingCombatantAdapter without spawning a full
# gameplay drone/limb merely to represent a benchmark target.
#######################################################

var velocity_world_value: Vector3 = Vector3.ZERO
var radius_m: float = 0.5
var alive_value: bool = true


func _init(
	owner_body: Node3D = null,
	kind: StringName = &"drone",
	new_entity_id: int = 0,
	new_group_id: int = -1,
	new_worker_id: int = -1,
	new_team_id: int = 1,
	new_radius_m: float = 0.5
) -> void:
	radius_m = maxf(new_radius_m, 0.05)
	super(owner_body, kind, new_entity_id, new_group_id, new_worker_id, new_team_id)


func update_state(position_world: Vector3, velocity_world: Vector3) -> void:
	velocity_world_value = velocity_world if velocity_world.is_finite() else Vector3.ZERO
	if is_instance_valid(body) and position_world.is_finite():
		body.global_position = position_world


func is_alive() -> bool:
	return simulation_active and alive_value and is_instance_valid(body)


func linear_velocity_world() -> Vector3:
	return velocity_world_value


func collision_radius_m() -> float:
	return radius_m


func _apply_physical_damage(_damage: float) -> void:
	# Evaluation targets record hits through the base adapter but intentionally do not die.
	pass
