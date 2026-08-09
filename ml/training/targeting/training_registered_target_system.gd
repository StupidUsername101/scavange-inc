class_name TrainingRegisteredTargetSystem
extends TrainingTargetSystem

#######################################################
# Generic multi-target provider for future gameplay/task systems. Cargo receivers, pickup
# items, swarm members, rescue points, or explicit escape destinations can register targets
# without changing policy inputs. The handler continuously sees every active registration.
#######################################################

const TYPE_ID: StringName = &"registered_targets"
const DISPLAY_NAME = "Task targets (runtime)"

var targets_by_id: Dictionary = {}
var stable_ids_cache: Array[String] = []
var stable_ids_dirty: bool = true


func type_id() -> StringName:
	return TYPE_ID


func display_name() -> String:
	return DISPLAY_NAME


func reset(_seed: int, _context: Dictionary = {}) -> void:
	# Registrations represent live world/task state and intentionally survive episode resets.
	pass


func upsert_target(
	stable_id: String,
	target_kind: String,
	position_world: Vector3,
	velocity_world: Vector3 = Vector3.ZERO,
	radius_m: float = 0.75,
	priority_bias: float = 0.0,
	urgency: float = 0.0,
	distance_weight: float = 1.0,
	metadata: Dictionary = {}
) -> void:
	if stable_id.is_empty() or not position_world.is_finite():
		return
	if not targets_by_id.has(stable_id):
		stable_ids_dirty = true
	var safe_velocity: Vector3 = velocity_world if velocity_world.is_finite() else Vector3.ZERO
	var safe_radius: float = maxf(RLTrainingMath.finite_float_or(radius_m, 0.75), 0.05)
	var safe_priority_bias: float = RLTrainingMath.finite_float_or(priority_bias, 0.0)
	var safe_urgency: float = RLTrainingMath.finite_float_or(urgency, 0.0)
	var safe_distance_weight: float = maxf(
		RLTrainingMath.finite_float_or(distance_weight, 1.0),
		0.0
	)
	targets_by_id[stable_id] = {
		"available": true,
		"stable_id": stable_id,
		"system_type_id": str(TYPE_ID),
		"target_kind": target_kind,
		# Runtime task registrations are not projectile targets unless a concrete task system
		# deliberately promotes them through a richer target contract in the future.
		"shootable": false,
		"position_world": position_world,
		"velocity_world": safe_velocity,
		"radius_m": safe_radius,
		"priority_bias": safe_priority_bias,
		"urgency": safe_urgency,
		"distance_weight": safe_distance_weight,
		"metadata": metadata.duplicate(false),
	}


func remove_target(stable_id: String) -> void:
	if targets_by_id.erase(stable_id):
		stable_ids_dirty = true


func clear_targets() -> void:
	if targets_by_id.is_empty():
		return
	targets_by_id.clear()
	stable_ids_cache.clear()
	stable_ids_dirty = false


func target_count() -> int:
	return targets_by_id.size()


func active_target_kinds() -> Array[String]:
	var result: Array[String] = []
	for target_value: Variant in targets_by_id.values():
		if not (target_value is Dictionary):
			continue
		var target: Dictionary = target_value
		if not bool(target.get("available", true)):
			continue
		var target_kind: String = str(target.get("target_kind", "fallback"))
		if not result.has(target_kind):
			result.append(target_kind)
	result.sort()
	return result


func append_candidates(output: Array[Dictionary], _context: Dictionary = {}) -> void:
	if not enabled or targets_by_id.is_empty():
		return
	if stable_ids_dirty:
		stable_ids_cache.clear()
		for stable_id_value: Variant in targets_by_id:
			stable_ids_cache.append(str(stable_id_value))
		stable_ids_cache.sort()
		stable_ids_dirty = false
	for stable_id: String in stable_ids_cache:
		var candidate_value: Variant = targets_by_id.get(stable_id)
		if not (candidate_value is Dictionary):
			continue
		var candidate: Dictionary = candidate_value
		if bool(candidate.get("available", true)):
			output.append(candidate)


func configuration_dictionary() -> Dictionary:
	return {
		"type_id": str(TYPE_ID),
		"enabled": enabled,
	}


func clone_configured() -> TrainingTargetSystem:
	var result: TrainingRegisteredTargetSystem = TrainingRegisteredTargetSystem.new()
	result.enabled = enabled
	# Runtime registrations are world state, not group configuration. Branches start with
	# an empty provider and receive registrations from the task systems active in the room.
	return result
