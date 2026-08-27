class_name DroneAIController
extends RefCounted

const RANDOM_SEED_BASE := 1777
const RANDOM_SEED_INSTANCE_FACTOR := 31
const RANDOM_SEED_SLOT_FACTOR := 101
const MIN_POWER_REQUEST := 0.001
const UNSET_PRIORITY := -100000
const MAX_MOVEMENT_SAMPLE_AGE := 0.75
const MIN_GUARD_RADIUS := 0.25

#######################################################
# Coordinates drone ai state and translates current inputs into gameplay decisions or actuator
# targets.
#######################################################

var host: Node3D
var chip_states: Array[Dictionary] = []
var combined_intent: Dictionary = {}
var last_power_consumption := 0.0

var waypoints: Array[Vector3] = []
var waypoint_index := 0
var waypoint_loop := true
var guard_enabled := false
var guard_center := Vector3.ZERO
var guard_radius := 5.0
var follow_player_id := -1
var simulation_time := 0.0


func _init(owner_drone: Node3D) -> void:
	host = owner_drone


func synchronize(loadout: DroneLoadout) -> void:
	var old_states := chip_states
	chip_states = []
	var slot_count = (
		loadout.core.ai_chip_slot_count
		if loadout != null and loadout.core != null
		else 0
	)
	for slot_index in range(slot_count):
		var definition := loadout.get_ai_chip(slot_index)
		if definition == null:
			chip_states.append({})
			continue
		# Finalized models bypass scripted intent arbitration and drive the existing low-level
		# DroneMLController. The authoritative ServerDrone accounts for their power separately.
		if definition.has_finalized_model_contract():
			chip_states.append({})
			continue
		var previous = (
			old_states[slot_index]
			if slot_index < old_states.size()
			else {}
		)
		if previous.get("definition") == definition:
			chip_states.append(previous)
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			RANDOM_SEED_BASE
			+ int(host.get_instance_id()) * RANDOM_SEED_INSTANCE_FACTOR
			+ slot_index * RANDOM_SEED_SLOT_FACTOR
		)
		chip_states.append({
			"definition": definition,
			"behavior": definition.create_behavior(),
			"memory": {},
			"intent": {},
			"cooldown": 0.0,
			"activity": 0.0,
			"rng": rng,
			"power_ratio": 0.0,
		})


func process(delta: float, available_power: float) -> float:
	simulation_time += delta
	var loadout := host.get("loadout") as DroneLoadout
	synchronize(loadout)
	var context: Dictionary = host.call("build_ai_context")
	context["simulation_time"] = simulation_time
	context["waypoints"] = waypoints
	context["waypoint_index"] = waypoint_index
	context["waypoint_loop"] = waypoint_loop
	context["guard_enabled"] = guard_enabled
	context["guard_center"] = guard_center
	context["guard_radius"] = guard_radius
	context["follow_player_id"] = follow_player_id
	var follow_snapshot: Dictionary = host.call(
		"get_ai_follow_target_snapshot",
		follow_player_id
	)
	context["follow_target_valid"] = not follow_snapshot.is_empty()
	context["follow_target_position"] = follow_snapshot.get(
		"position",
		Vector3.ZERO
	)
	context["follow_target_velocity"] = follow_snapshot.get(
		"velocity",
		Vector3.ZERO
	)

	var remaining_power := maxf(available_power, 0.0)
	last_power_consumption = 0.0
	for slot_index in range(chip_states.size()):
		var state = chip_states[slot_index]
		if state.is_empty():
			continue
		var definition := state.get("definition") as DroneAIChipDefinition
		var activity := float(state.get("activity", 0.0))
		var requested_power := definition.get_power_draw(activity)
		var allocated_power := minf(requested_power, remaining_power)
		remaining_power -= allocated_power
		last_power_consumption += allocated_power
		var power_ratio := (
			allocated_power / requested_power
			if requested_power > MIN_POWER_REQUEST
			else 1.0
		)
		state["power_ratio"] = power_ratio
		state["cooldown"] = float(state.get("cooldown", 0.0)) - delta
		if (
			power_ratio < definition.minimum_operating_power_ratio
			or float(state.get("cooldown", 0.0)) > 0.0
		):
			continue

		var behavior := state.get("behavior") as RefCounted
		if behavior == null or not behavior.has_method("evaluate"):
			state["intent"] = {}
			state["activity"] = 0.0
			continue
		var memory: Dictionary = state.get("memory")
		var intent: Dictionary = behavior.call(
			"evaluate",
			definition,
			context,
			memory,
			state.get("rng") as RandomNumberGenerator
		)
		intent["evaluation_time"] = simulation_time
		intent["slot_index"] = slot_index
		intent["priority"] = definition.processing_priority
		state["intent"] = intent
		state["activity"] = clampf(
			float(intent.get("activity", 0.0)),
			0.0,
			1.0
		)
		state["cooldown"] = definition.get_effective_response_time(
			power_ratio
		)

	combine_intents()
	_apply_static_obstacle_avoidance(delta)
	_apply_collision_avoidance(delta)
	return last_power_consumption


func combine_intents() -> void:
	combined_intent = {}
	var movement_priority := UNSET_PRIORITY
	var combat_priority := UNSET_PRIORITY
	var avoidance_priority := UNSET_PRIORITY
	for state in chip_states:
		if state.is_empty():
			continue
		var definition := state.get("definition") as DroneAIChipDefinition
		if (
			definition == null
			or float(state.get("power_ratio", 0.0))
			< definition.minimum_operating_power_ratio
		):
			continue
		var intent: Dictionary = state.get("intent")
		var priority := int(intent.get("priority", UNSET_PRIORITY))
		if bool(intent.get("advance_waypoint", false)):
			_advance_waypoint()
			intent.erase("advance_waypoint")
		if bool(intent.get("movement_active", false)) and priority > movement_priority:
			movement_priority = priority
			var movement_target: Vector3 = intent.get(
				"movement_target",
				Vector3.ZERO
			)
			var movement_target_velocity: Vector3 = intent.get(
				"movement_target_velocity",
				Vector3.ZERO
			)
			# Navigation chips update at their own response rate. Advance the
			# sampled target between evaluations instead of making the flight
			# loop chase a stationary point that jumps every chip tick.
			var sample_age := clampf(
				simulation_time - float(intent.get(
					"evaluation_time",
					simulation_time
				)),
				0.0,
				MAX_MOVEMENT_SAMPLE_AGE
			)
			movement_target += movement_target_velocity * sample_age
			combined_intent["movement_active"] = true
			combined_intent["movement_target"] = movement_target
			combined_intent["movement_stop_distance"] = float(
				intent.get("movement_stop_distance", 0.5)
			)
			combined_intent["movement_target_velocity"] = (
				movement_target_velocity
			)
			combined_intent["movement_speed_scale"] = (
				definition.get_navigation_speed_scale()
			)
			combined_intent["movement_acceleration_scale"] = (
				definition.get_navigation_acceleration_scale()
			)
			combined_intent["movement_jerk_scale"] = (
				definition.get_navigation_jerk_scale()
			)
		if bool(intent.get("combat_active", false)) and priority > combat_priority:
			combat_priority = priority
			for key in [
				"combat_active",
				"combat_target_id",
				"combat_target_kind",
				"combat_target_position",
				"fire_requested",
			]:
				combined_intent[key] = intent.get(key)
		if (
			bool(intent.get("avoidance_active", false))
			and priority > avoidance_priority
		):
			avoidance_priority = priority
			combined_intent["avoidance_definition"] = definition


func set_waypoint_plan(points: Array[Vector3], loop: bool) -> void:
	waypoints = points.duplicate()
	waypoint_loop = loop
	waypoint_index = 0


func set_guard_sphere(center: Vector3, radius: float) -> void:
	guard_center = center
	guard_radius = maxf(radius, MIN_GUARD_RADIUS)
	guard_enabled = true


func clear_guard_sphere() -> void:
	guard_enabled = false


func set_follow_player(player_id: int) -> void:
	follow_player_id = player_id


func clear_orders() -> void:
	waypoints.clear()
	waypoint_index = 0
	guard_enabled = false
	follow_player_id = -1


func get_active_chip_count() -> int:
	var result := 0
	for state in chip_states:
		if state.is_empty():
			continue
		var definition := state.get("definition") as DroneAIChipDefinition
		if (
			definition != null
			and float(state.get("power_ratio", 0.0))
			>= definition.minimum_operating_power_ratio
		):
			result += 1
	return result


func has_operational_behavior(behavior_id: StringName) -> bool:
	for state: Dictionary in chip_states:
		if state.is_empty():
			continue
		var definition := state.get("definition") as DroneAIChipDefinition
		if (
			definition != null
			and definition.behavior_id == behavior_id
			and float(state.get("power_ratio", 0.0))
			>= definition.minimum_operating_power_ratio
		):
			return true
	return false


func _apply_collision_avoidance(delta: float) -> void:
	var definition := combined_intent.get(
		"avoidance_definition"
	) as DroneAIChipDefinition
	if definition == null or not host.has_method("calculate_ai_avoidance"):
		combined_intent.erase("avoidance_definition")
		return
	var result: Dictionary = host.call(
		"calculate_ai_avoidance",
		definition,
		combined_intent,
		delta
	)
	for state: Dictionary in chip_states:
		if state.get("definition") == definition:
			state["activity"] = 1.0 if not result.is_empty() else 0.08
			break
	if not result.is_empty():
		combined_intent["horizontal_velocity_override"] = result.get(
			"velocity",
			Vector3.ZERO
		)
		combined_intent["avoidance_neighbor_count"] = int(result.get(
			"neighbor_count",
			0
		))
	combined_intent.erase("avoidance_definition")


func _apply_static_obstacle_avoidance(delta: float) -> void:
	if (
		not bool(combined_intent.get("movement_active", false))
		or not host.has_method("calculate_ai_static_obstacle_avoidance")
	):
		return
	var result: Dictionary = host.call(
		"calculate_ai_static_obstacle_avoidance",
		combined_intent,
		delta
	)
	if result.is_empty():
		return
	combined_intent["horizontal_velocity_override"] = result.get(
		"velocity",
		Vector3.ZERO
	)
	combined_intent["static_avoidance_active"] = true
	combined_intent["static_avoidance_blocked_samples"] = int(result.get(
		"blocked_sample_count",
		0
	))


func _advance_waypoint() -> void:
	if waypoints.is_empty():
		waypoint_index = 0
		return
	if waypoint_index + 1 < waypoints.size():
		waypoint_index += 1
	elif waypoint_loop:
		waypoint_index = 0
