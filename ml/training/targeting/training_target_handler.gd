class_name TrainingTargetHandler
extends RefCounted

#######################################################
# Deterministically merges candidate streams into the single target already understood by
# every model. Priority classes are deliberately hardcoded for now so adding task systems
# cannot accidentally outrank survival/cargo semantics by insertion order.
#######################################################

const DEFAULT_PRIORITY_BY_KIND: Dictionary = {
	"survival_escape": 1000.0,
	"cargo_delivery": 800.0,
	"cargo_pickup": 700.0,
	"combat_objective": 500.0,
	"navigation": 100.0,
	"fallback": 0.0,
}
# TODO(target-priority-ui): expose these semantic priorities as ordered rows/sliders in the
# Target Settings UI. Keep deterministic tie-breaking and save the per-handler ordering.

var handler_key: String = ""
var systems: Array[TrainingTargetSystem] = []
var systems_by_type: Dictionary = {}
var priority_by_kind: Dictionary = DEFAULT_PRIORITY_BY_KIND.duplicate(true)
var candidate_buffer: Array[Dictionary] = []
var selected_candidate: Dictionary = {}


func add_system(system: TrainingTargetSystem) -> void:
	if system == null:
		return
	var key: String = str(system.type_id())
	if systems_by_type.has(key):
		remove_system(system.type_id())
	system.instance_key = "%s:%s" % [handler_key, key]
	systems.append(system)
	systems_by_type[key] = system


func remove_system(type_id: StringName) -> void:
	var key: String = str(type_id)
	var existing = systems_by_type.get(key) as TrainingTargetSystem
	if existing != null:
		systems.erase(existing)
	systems_by_type.erase(key)


func system(type_id: StringName) -> TrainingTargetSystem:
	return systems_by_type.get(str(type_id)) as TrainingTargetSystem


func path_system() -> TrainingPathTargetSystem:
	return system(TrainingPathTargetSystem.TYPE_ID) as TrainingPathTargetSystem


func registered_system() -> TrainingRegisteredTargetSystem:
	return system(TrainingRegisteredTargetSystem.TYPE_ID) as TrainingRegisteredTargetSystem


func set_kind_priority(target_kind: String, priority: float) -> void:
	if target_kind.is_empty() or not is_finite(priority):
		return
	priority_by_kind[target_kind] = priority


func kind_priority(target_kind: String) -> float:
	return float(priority_by_kind.get(target_kind, 0.0))


func reset(seed: int, context: Dictionary = {}) -> void:
	for index in range(systems.size()):
		var target_system: TrainingTargetSystem = systems[index]
		target_system.reset(seed + index * 104729, context)
	resolve(context)


func tick(delta: float, context: Dictionary = {}) -> Dictionary:
	for target_system: TrainingTargetSystem in systems:
		target_system.tick(delta, context)
	return resolve(context)


func resolve(context: Dictionary = {}) -> Dictionary:
	candidate_buffer.clear()
	for target_system: TrainingTargetSystem in systems:
		target_system.append_candidates(candidate_buffer, context)
	var reference_position: Vector3 = context.get("reference_position_world", Vector3.ZERO)
	if not reference_position.is_finite():
		reference_position = Vector3.ZERO
	var best: Dictionary = {}
	var best_priority: float = -INF
	var best_priority_bias: float = -INF
	var best_urgency: float = -INF
	var best_distance_score: float = -INF
	var best_stable_id: String = ""
	for candidate: Dictionary in candidate_buffer:
		if not bool(candidate.get("available", true)):
			continue
		var position_value: Variant = candidate.get("position_world", null)
		if not (position_value is Vector3):
			continue
		var position_world: Vector3 = position_value
		if not position_world.is_finite():
			continue
		var candidate_for_selection: Dictionary = candidate.duplicate(false)
		var velocity_value: Variant = candidate.get("velocity_world", Vector3.ZERO)
		candidate_for_selection["velocity_world"] = (
			velocity_value
			if velocity_value is Vector3 and (velocity_value as Vector3).is_finite()
			else Vector3.ZERO
		)
		candidate_for_selection["radius_m"] = maxf(
			RLTrainingMath.finite_float_or(candidate.get("radius_m", 0.75), 0.75),
			0.05
		)
		var target_kind: String = str(candidate.get("target_kind", "fallback"))
		var priority: float = RLTrainingMath.finite_float_or(
			priority_by_kind.get(target_kind, 0.0),
			0.0
		)
		var priority_bias: float = RLTrainingMath.finite_float_or(
			candidate.get("priority_bias", 0.0),
			0.0
		)
		var urgency: float = RLTrainingMath.finite_float_or(candidate.get("urgency", 0.0), 0.0)
		var distance_weight: float = maxf(
			RLTrainingMath.finite_float_or(candidate.get("distance_weight", 0.0), 0.0),
			0.0
		)
		var distance_score: float = -reference_position.distance_to(position_world) * distance_weight
		var stable_id: String = str(candidate.get("stable_id", ""))
		if _candidate_is_better(
			priority,
			priority_bias,
			urgency,
			distance_score,
			stable_id,
			best_priority,
			best_priority_bias,
			best_urgency,
			best_distance_score,
			best_stable_id,
			best.is_empty()
		):
			best = candidate_for_selection
			best_priority = priority
			best_priority_bias = priority_bias
			best_urgency = urgency
			best_distance_score = distance_score
			best_stable_id = stable_id
	selected_candidate = best
	return selected_candidate


func _candidate_is_better(
	priority: float,
	priority_bias: float,
	urgency: float,
	distance_score: float,
	stable_id: String,
	best_priority: float,
	best_priority_bias: float,
	best_urgency: float,
	best_distance_score: float,
	best_stable_id: String,
	no_best: bool
) -> bool:
	if no_best:
		return true
	if not is_equal_approx(priority, best_priority):
		return priority > best_priority
	# Bias can order candidates inside one semantic class, but it cannot let a cargo or
	# navigation target leapfrog a survival target. The class ordering remains authoritative.
	if not is_equal_approx(priority_bias, best_priority_bias):
		return priority_bias > best_priority_bias
	if not is_equal_approx(urgency, best_urgency):
		return urgency > best_urgency
	if not is_equal_approx(distance_score, best_distance_score):
		return distance_score > best_distance_score
	# Stable string ordering makes equal candidates deterministic regardless of dictionary or
	# scene-tree insertion order.
	return stable_id < best_stable_id


func resolved_target(fallback_position: Vector3, fallback_radius_m: float = 0.75) -> Dictionary:
	if selected_candidate.is_empty():
		var safe_fallback_position: Vector3 = (
			fallback_position if fallback_position.is_finite() else Vector3.ZERO
		)
		var safe_fallback_radius: float = maxf(
			RLTrainingMath.finite_float_or(fallback_radius_m, 0.75),
			0.05
		)
		return {
			"available": true,
			"stable_id": "%s:fallback" % handler_key,
			"system_type_id": "fallback",
			"target_kind": "fallback",
			"shootable": false,
			"position_world": safe_fallback_position,
			"velocity_world": Vector3.ZERO,
			"radius_m": safe_fallback_radius,
			"metadata": {},
		}
	return selected_candidate


func configuration_dictionary() -> Dictionary:
	var system_configs: Array[Dictionary] = []
	for target_system: TrainingTargetSystem in systems:
		system_configs.append(target_system.configuration_dictionary())
	return {
		"schema_version": 1,
		"priority_by_kind": priority_by_kind.duplicate(true),
		"systems": system_configs,
	}


func load_configuration(configuration: Dictionary) -> void:
	var priorities: Variant = configuration.get("priority_by_kind", {})
	if priorities is Dictionary:
		for key: Variant in (priorities as Dictionary).keys():
			set_kind_priority(str(key), RLTrainingMath.finite_float_or(
				(priorities as Dictionary)[key],
				kind_priority(str(key))
			))
	var system_configs: Variant = configuration.get("systems", [])
	if system_configs is Array:
		for config_value: Variant in system_configs:
			if not (config_value is Dictionary):
				continue
			var config: Dictionary = config_value as Dictionary
			var target_system = systems_by_type.get(str(config.get("type_id", ""))) as TrainingTargetSystem
			if target_system != null:
				target_system.load_configuration(config)


func clone_configured(next_handler_key: String) -> TrainingTargetHandler:
	var result: TrainingTargetHandler = TrainingTargetHandler.new()
	result.handler_key = next_handler_key
	result.priority_by_kind = priority_by_kind.duplicate(true)
	for target_system: TrainingTargetSystem in systems:
		var cloned: TrainingTargetSystem = target_system.clone_configured()
		if cloned != null:
			result.add_system(cloned)
	return result
