extends DroneAIBehavior

#######################################################
# Evaluates area guard behavior and contributes movement, avoidance, or combat intent without
# directly simulating the drone.
#######################################################

func evaluate(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	_memory: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	if not bool(context.get("guard_enabled", false)):
		return {"activity": 0.05}

	var center: Vector3 = context.get("guard_center", Vector3.ZERO)
	var radius := maxf(float(context.get("guard_radius", 5.0)), 0.25)
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var result := {"activity": 0.55}
	if position.distance_to(center) > radius * 0.7:
		result["movement_active"] = true
		result["movement_target"] = center
		result["movement_stop_distance"] = radius * 0.45

	var target := find_combat_target(
		definition,
		context,
		rng,
		center,
		minf(radius, definition.sensor_range)
	)
	result.merge(make_combat_intent(definition, context, target, rng), true)
	return result
