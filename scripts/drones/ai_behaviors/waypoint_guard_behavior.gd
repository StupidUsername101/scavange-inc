extends DroneAIBehavior

#######################################################
# Evaluates waypoint guard behavior and contributes movement, avoidance, or combat intent
# without directly simulating the drone.
#######################################################

func evaluate(
	definition: DroneAIChipDefinition,
	context: Dictionary,
	_memory: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var waypoints: Array = context.get("waypoints", [])
	if waypoints.is_empty():
		return {"activity": 0.05}

	var waypoint_index := clampi(
		int(context.get("waypoint_index", 0)),
		0,
		waypoints.size() - 1
	)
	var waypoint: Vector3 = waypoints[waypoint_index]
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var arrival_radius := float(
		definition.get_parameter(&"arrival_radius", 0.8)
	)
	var result := {
		"movement_active": true,
		"movement_target": waypoint,
		"movement_stop_distance": arrival_radius,
		"activity": 0.75,
	}
	if position.distance_to(waypoint) <= arrival_radius:
		result["advance_waypoint"] = true

	var guard_radius := float(
		definition.get_parameter(&"guard_radius", definition.sensor_range)
	)
	var target := find_combat_target(
		definition,
		context,
		rng,
		waypoint,
		minf(guard_radius, definition.sensor_range)
	)
	result.merge(make_combat_intent(definition, context, target, rng), true)
	return result
