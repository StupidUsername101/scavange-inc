extends DroneAIBehavior

#######################################################
# Evaluates combat behavior and contributes movement, avoidance, or combat intent without
# directly simulating the drone.
#######################################################

func evaluate(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	_memory: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var target := find_combat_target(
		definition,
		context,
		rng,
		position,
		definition.sensor_range
	)
	var result := make_combat_intent(
		definition,
		context,
		target,
		rng
	)
	result["activity"] = 1.0 if not target.is_empty() else 0.2
	return result
