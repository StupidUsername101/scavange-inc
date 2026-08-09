class_name TrainingCombatantAdapter
extends RefCounted

const EMPTY_COMBAT_EVENTS = {
	"damage_taken": 0.0,
	"hit_count": 0,
	"last_attacker_entity_id": 0,
	"last_hit_position_world": Vector3.ZERO,
	"last_shot_id": 0,
}

#######################################################
# Polymorphic combat/perception boundary for training-room bodies. The shared spatial hash,
# turret targeting, projectiles, and reward code use this API instead of branching on the
# concrete drone, limb, or turret node at every call site.
#######################################################

var body: Node3D
var entity_kind: StringName = &"unknown"
var entity_id = 0
var group_id = -1
var worker_id = -1
var team_id = 0
var simulation_active: bool = true
var accumulated_damage = 0.0
var accumulated_hit_count = 0
var last_attacker_entity_id = 0
var last_hit_position_world = Vector3.ZERO
var last_shot_id = 0


func _init(
	owner_body: Node3D = null,
	kind: StringName = &"unknown",
	new_entity_id: int = 0,
	new_group_id: int = -1,
	new_worker_id: int = -1,
	new_team_id: int = 0
) -> void:
	body = owner_body
	entity_kind = kind
	entity_id = new_entity_id
	group_id = new_group_id
	worker_id = new_worker_id
	team_id = new_team_id


func spatial_key() -> StringName:
	return StringName("training:%s:%d" % [String(entity_kind), entity_id])


func set_simulation_active(value: bool) -> void:
	simulation_active = value


func is_simulation_active() -> bool:
	return simulation_active


func is_alive() -> bool:
	return simulation_active and is_instance_valid(body)


func world_position() -> Vector3:
	return body.global_position if is_instance_valid(body) else Vector3.ZERO


func aim_point_world() -> Vector3:
	return world_position()


func orientation_basis_world() -> Basis:
	return body.global_basis.orthonormalized() if is_instance_valid(body) else Basis.IDENTITY


func linear_velocity_world() -> Vector3:
	return Vector3.ZERO


func collision_radius_m() -> float:
	return 0.5


func receive_training_hit(
	damage: float,
	attacker_entity_id: int,
	hit_position_world: Vector3,
	shot_id: int
) -> bool:
	if not simulation_active or not is_alive() or not is_finite(damage) or damage <= 0.0:
		return false
	accumulated_damage += damage
	accumulated_hit_count += 1
	last_attacker_entity_id = attacker_entity_id
	last_hit_position_world = hit_position_world
	last_shot_id = shot_id
	_apply_physical_damage(damage)
	return true


func _apply_physical_damage(_damage: float) -> void:
	pass


func has_pending_combat_events() -> bool:
	return accumulated_hit_count > 0 or not is_zero_approx(accumulated_damage)


func consume_combat_events() -> Dictionary:
	if not has_pending_combat_events():
		return EMPTY_COMBAT_EVENTS
	var result = peek_combat_events()
	accumulated_damage = 0.0
	accumulated_hit_count = 0
	return result


func peek_combat_events() -> Dictionary:
	if not has_pending_combat_events():
		return EMPTY_COMBAT_EVENTS
	return {
		"damage_taken": accumulated_damage,
		"hit_count": accumulated_hit_count,
		"last_attacker_entity_id": last_attacker_entity_id,
		"last_hit_position_world": last_hit_position_world,
		"last_shot_id": last_shot_id,
	}


func metadata() -> Dictionary:
	return {
		"adapter": self,
		"entity_kind": entity_kind,
		"entity_id": entity_id,
		"group_id": group_id,
		"worker_id": worker_id,
		"team_id": team_id,
	}
