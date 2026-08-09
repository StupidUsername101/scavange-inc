extends DroneAIBehavior

#######################################################
# Evaluates orca collision avoidance behavior and contributes movement, avoidance, or combat
# intent without directly simulating the drone.
#######################################################

func evaluate(
	_definition: DroneAIChipDefinition,
	_context: Dictionary,
	_memory: Dictionary,
	_rng: RandomNumberGenerator
) -> Dictionary:
	# The controller applies this as a modifier after a navigation chip has
	# selected its preferred velocity. No neighbor lookup happens here: the
	# server only asks the spatial index when this powered modifier is present.
	return {
		"avoidance_active": true,
		"activity": 0.35,
	}
