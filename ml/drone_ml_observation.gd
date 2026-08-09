class_name DroneMLObservation
extends RefCounted

const SCHEMA_VERSION = 3
const NO_GROUND_HIT_CLEARANCE_M = 12.0

#######################################################
# Captures a complete, topology-independent drone observation. Structured dictionaries are
# kept here so the future algorithm can choose its own normalization and tensor layout.
#######################################################


static func capture(drone, delta: float, step_index: int) -> Dictionary:
	var ground_probe = drone.get_ml_ground_probe()
	var observation = {
		"schema_version": SCHEMA_VERSION,
		"step_index": step_index,
		"delta_seconds": delta,
		"drone_id": drone.drone_id,
		"body": _capture_body(drone),
		"electrical": _capture_electrical(drone),
		"environment": _capture_environment(drone, ground_probe),
		"objective": _capture_objective(drone),
		"controller_memory": _capture_controller_memory(drone),
		"parts": _capture_parts(drone),
		"propellers": _capture_propellers(drone),
	}
	observation["encoded"] = DroneMLFeatureEncoder.encode(observation)
	return observation


static func capture_ppo(drone, delta: float, step_index: int) -> Dictionary:
	# PPO consumes only this compact schema. The generic diagnostic snapshot deliberately
	# remains rich, but constructing all of its static part metadata and secondary encoded
	# tensor for every decision is wasted work in the training room.
	var basis: Basis = drone.global_basis
	var inverse_basis: Basis = basis.inverse()
	var objective: Dictionary = (
		drone.ml_controller.objective
		if drone.ml_controller != null
		else {}
	)
	var obstacle_probe: Dictionary = objective.get("obstacle_probe", {})
	var core: DroneCoreDefinition = (
		drone.loadout.core if drone.loadout != null else null
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"step_index": step_index,
		"delta_seconds": delta,
		"body": {
			"position_world": drone.global_position,
			"basis_world": basis,
			"inverse_basis_world": inverse_basis,
			"linear_velocity_world": drone.linear_velocity,
			"linear_velocity_local": inverse_basis * drone.linear_velocity,
			"angular_velocity_local": inverse_basis * drone.angular_velocity,
		},
		"electrical": {
			"available_power_w": drone.current_power_output,
		},
		"environment": {
			"ground_clearance_m": float(obstacle_probe.get(
				"ground_clearance_m",
				NO_GROUND_HIT_CLEARANCE_M
			)),
		},
		"objective": objective,
		"parts": {
			"core": {
				"maximum_power_throughput_w": (
					core.max_power_throughput if core != null else 0.0
				),
			},
		},
		"propellers": capture_ppo_propeller_states(drone),
		# Schema 9 compatibility remains available for old checkpoints. New policies consume the
		# finalized body-manifest vector below instead of a hard-coded manipulator shortcut.
		"manipulator": _capture_ppo_manipulator(drone),
		"model_body_features": (
			drone.model_body_observation_features()
			if drone.has_method("model_body_observation_features")
			else PackedFloat64Array()
		),
		"model_body_signature": (
			drone.model_body_contract_signature()
			if drone.has_method("model_body_contract_signature")
			else ""
		),
	}


static func _capture_ppo_manipulator(drone) -> Dictionary:
	if drone == null or not drone.has_method("all_limb_attachment_states"):
		return {"present": false}
	var states_value: Variant = drone.all_limb_attachment_states()
	if not (states_value is Dictionary):
		return {"present": false}
	var states: Dictionary = states_value
	var slots: Array = states.keys()
	slots.sort()
	for slot_value: Variant in slots:
		var assembly_value: Variant = states.get(slot_value, {})
		if not (assembly_value is Dictionary):
			continue
		var assembly: Dictionary = assembly_value
		if int(assembly.get("action_count", 0)) <= 0:
			continue
		var limbs_value: Variant = assembly.get("limbs", [])
		if not (limbs_value is Array):
			continue
		for limb_value: Variant in limbs_value:
			if not (limb_value is Dictionary):
				continue
			var end_effector_value: Variant = (limb_value as Dictionary).get("end_effector", {})
			if not (end_effector_value is Dictionary):
				continue
			var effector: Dictionary = end_effector_value
			if not bool(effector.get("present", false)):
				continue
			return {
				"present": true,
				"grip_activation": clampf(float(effector.get("activation", 0.0)), 0.0, 1.0),
				"candidate_present": bool(effector.get("candidate_present", false)),
				"attached": bool(effector.get("attached", false)),
			}
	return {"present": false}


static func capture_ppo_propeller_states(drone) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var maximum_thrusts: Array[float] = drone.get_ml_static_thrust_limits()
	for array_index: int in range(drone.propeller_slots.size()):
		var slot = drone.propeller_slots[array_index]
		var propeller: DronePropellerDefinition = (
			drone.loadout.get_propeller(slot.slot_index)
			if drone.loadout != null
			else null
		)
		result.append({
			"slot_index": int(slot.slot_index),
			"installed": propeller != null,
			"realized_thrust_n": _array_value(
				drone.last_propeller_realized_thrust_n,
				array_index
			),
			"maximum_static_thrust_n": _array_value(
				maximum_thrusts,
				array_index
			),
		})
	return result


static func _capture_body(drone) -> Dictionary:
	return {
		"position_world": drone.global_position,
		"basis_world": drone.global_basis,
		"linear_velocity_world": drone.linear_velocity,
		"angular_velocity_world": drone.angular_velocity,
		"linear_velocity_local": drone.global_basis.inverse() * drone.linear_velocity,
		"angular_velocity_local": drone.global_basis.inverse() * drone.angular_velocity,
		"up_world": drone.global_basis.y.normalized(),
		"mass_kg": drone.mass,
		"inertia_kg_m2": drone.inertia,
		"sleeping": drone.sleeping,
		"activated": drone.activated,
		"health": drone.current_health,
	}


static func _capture_electrical(drone) -> Dictionary:
	var battery = drone.loadout.battery if drone.loadout != null else null
	return {
		"battery_energy_wh": drone.remaining_battery_energy_wh,
		"battery_charge_ratio": drone.get_battery_charge_ratio(),
		"battery_nominal_voltage_v": (
			battery.nominal_voltage_v if battery != null else 0.0
		),
		"bus_voltage_v": drone.current_bus_voltage_v,
		"available_power_w": drone.current_power_output,
		"power_spool_ratio": drone.power_spool_ratio,
		"spike_multiplier": drone.battery_spike_multiplier,
		"spike_seconds_remaining": drone.battery_spike_time_remaining,
	}


static func _capture_environment(
	drone,
	ground_probe: Dictionary
) -> Dictionary:
	var environment = drone.air_environment
	return {
		"gravity_world": drone.get_gravity(),
		"air_density_kg_m3": (
			environment.air_density if environment != null else 0.0
		),
		"wind_velocity_world": (
			environment.wind_velocity if environment != null else Vector3.ZERO
		),
		"ground_detected": not ground_probe.is_empty(),
		"ground_height_world": ground_probe.get("ground_height", 0.0),
		"ground_position_world": ground_probe.get("position", Vector3.ZERO),
		"ground_clearance_m": (
			drone.global_position.y - float(ground_probe.get("ground_height", 0.0))
			if not ground_probe.is_empty()
			else NO_GROUND_HIT_CLEARANCE_M
		),
	}


static func _capture_objective(drone) -> Dictionary:
	if drone.is_ml_control_enabled():
		return drone.ml_controller.objective.duplicate(true)
	return (
		drone.ai_controller.combined_intent.duplicate(true)
		if drone.ai_controller != null
		else {}
	)


static func _capture_controller_memory(drone) -> Dictionary:
	var controller = drone.flight_controller
	if controller == null:
		return {}
	return {
		"hold_position_world": controller.hold_position,
		"hold_initialized": controller.hold_initialized,
		"movement_was_active": controller.movement_was_active,
		"smoothed_horizontal_acceleration_world": (
			controller.smoothed_horizontal_acceleration
		),
		"altitude_velocity_integral": controller.altitude_velocity_integral,
		"emergency_torque_world": controller.emergency_torque_world,
	}


static func _capture_parts(drone) -> Dictionary:
	var loadout = drone.loadout
	if loadout == null:
		return {}
	return {
		"core": _core_stats(loadout.core),
		"battery": _battery_stats(loadout.battery),
		"attachments": _part_array(loadout.attachments),
	}


static func _capture_propellers(drone) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for array_index: int in range(drone.propeller_slots.size()):
		var slot = drone.propeller_slots[array_index]
		var propeller = (
			drone.loadout.get_propeller(slot.slot_index)
			if drone.loadout != null
			else null
		)
		var stats = _part_stats(propeller)
		stats.merge({
			"array_index": array_index,
			"slot_index": slot.slot_index,
			"installed": propeller != null,
			"position_local": slot.position,
			"lift_axis_local": slot.basis.y.normalized(),
			"spin_direction": slot.spin_direction,
			"supplied_voltage_v": drone.current_bus_voltage_v,
			"commanded_thrust_n": (
				drone.ai_motor_thrust_targets[array_index]
				if array_index < drone.ai_motor_thrust_targets.size()
				else 0.0
			),
			"requested_power_w": _array_value(
				drone.last_propeller_requested_power_w, array_index
			),
			"applied_power_w": _array_value(
				drone.last_propeller_applied_power_w, array_index
			),
			"realized_thrust_n": _array_value(
				drone.last_propeller_realized_thrust_n, array_index
			),
		})
		if propeller != null:
			stats.merge({
				"maximum_power_draw_w": propeller.max_power_draw,
				"rotor_radius_m": propeller.rotor_radius,
				"disk_area_m2": propeller.get_disk_area(),
				"aerodynamic_efficiency": propeller.aerodynamic_efficiency,
				"reaction_torque_nm_per_n": propeller.reaction_torque_per_newton,
				"axial_flow_response": propeller.axial_flow_response,
				"minimum_axial_flow_factor": propeller.minimum_axial_flow_factor,
				"maximum_axial_flow_factor": propeller.maximum_axial_flow_factor,
				"maximum_static_thrust_n": (
					drone.air_environment.calculate_rotor_thrust(
						propeller.max_power_draw,
						propeller.get_disk_area(),
						propeller.aerodynamic_efficiency
					)
					if drone.air_environment != null
					else 0.0
				),
			})
		result.append(stats)
	return result


static func _part_array(parts: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in parts:
		result.append(_part_stats(part))
	return result


static func _part_stats(part: DronePartDefinition) -> Dictionary:
	if part == null:
		return {"installed": false}
	return {
		"installed": true,
		"resource_path": part.resource_path,
		"display_name": part.display_name,
		"quality": int(part.quality),
		"mass_kg": part.get_mass(),
		"rated_voltage_v": part.rated_voltage_v,
	}


static func _core_stats(core: DroneCoreDefinition) -> Dictionary:
	var result = _part_stats(core)
	if core == null:
		return result
	result.merge({
		"maximum_power_throughput_w": core.max_power_throughput,
		"propeller_slot_count": core.propeller_slot_count,
		"body_size_m": core.body_size,
		"drag_area_m2": core.drag_area,
		"drag_coefficient": core.drag_coefficient,
		"angular_drag_coefficient": core.angular_drag_coefficient,
	})
	return result


static func _battery_stats(battery: DroneBatteryDefinition) -> Dictionary:
	var result = _part_stats(battery)
	if battery == null:
		return result
	result.merge({
		"energy_capacity_wh": battery.energy_capacity_wh,
		"nominal_voltage_v": battery.nominal_voltage_v,
		"nominal_power_output_w": battery.nominal_power_output,
		"maximum_power_output_w": battery.maximum_power_output,
		"body_size_m": battery.body_size,
		"power_output_consistency": battery.power_output_consistency,
		"surge_protection": battery.surge_protection,
	})
	return result


static func _array_value(values: Array[float], index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else 0.0
