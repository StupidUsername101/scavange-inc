class_name DroneAIBehavior
extends RefCounted

#######################################################
# Evaluates drone ai behavior and contributes movement, avoidance, or combat intent without
# directly simulating the drone.
#######################################################

func evaluate(
	_definition: DroneAIChipDefinition,
	_context: Dictionary,
	_memory: Dictionary,
	_rng: RandomNumberGenerator
) -> Dictionary:
	return {}


func find_combat_target(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	rng: RandomNumberGenerator,
	center: Vector3,
	radius: float
) -> Dictionary:
	var weapon_slots: Array = context.get("weapon_slots", [])
	if weapon_slots.is_empty():
		return {}
	var weapon_range := 0.0
	for weapon_value in context.get("weapons", []):
		var weapon: Dictionary = weapon_value
		weapon_range = maxf(
			weapon_range,
			float(weapon.get("effective_range", 0.0))
		)
	if weapon_range > 0.0:
		radius = minf(radius, weapon_range)

	var own_faction := int(context.get("faction_id", 0))
	var candidates: Array = []
	var provider: Callable = context.get("combat_candidate_provider", Callable())
	if provider.is_valid():
		var provided: Variant = provider.call(center, radius)
		if provided is Array:
			candidates = provided

	var best_target := {}
	var best_distance := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		if candidate.is_empty():
			continue
		var candidate_position: Vector3 = candidate.get(
			"position",
			Vector3.ZERO
		)
		var distance := center.distance_to(candidate_position)
		if distance > radius:
			continue

		var is_friendly := int(candidate.get("faction_id", 0)) == own_faction
		if (
			is_friendly
			and rng.randf() < definition.friendly_identification_accuracy
		):
			continue
		if distance < best_distance:
			best_target = candidate
			best_distance = distance

	return best_target


func apply_aim_error(
	definition: DroneAIChipDefinition,
	origin: Vector3,
	target: Vector3,
	rng: RandomNumberGenerator
) -> Vector3:
	var distance := origin.distance_to(target)
	var error_radius := (
		tan(deg_to_rad(definition.aim_error_degrees))
		* distance
	)
	if error_radius <= 0.0001:
		return target
	var error := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	)
	if error.length_squared() > 1.0:
		error = error.normalized()
	return target + error * error_radius


func make_combat_intent(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	target: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	if target.is_empty():
		return {}
	var origin: Vector3 = context.get("position", Vector3.ZERO)
	var target_position: Vector3 = target.get("position", origin)
	return {
		"combat_active": true,
		"combat_target_id": int(target.get("target_id", -1)),
		"combat_target_kind": target.get("kind", &"unknown"),
		"combat_target_position": apply_aim_error(
			definition,
			origin,
			target_position,
			rng
		),
		"fire_requested": true,
	}
