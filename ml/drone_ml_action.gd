class_name DroneMLAction
extends RefCounted

const SCHEMA_VERSION: int = 2

const MINIMUM_NORMALIZED_COMMAND = 0.0
const MAXIMUM_NORMALIZED_COMMAND = 1.0

#######################################################
# Validates topology-independent ML actions and converts normalized per-propeller commands
# into the thrust targets consumed by the existing drone force simulation.
#######################################################


static func validate(action: Dictionary, propeller_slots: Array) -> Dictionary:
	var raw_commands_value = action.get("propeller_commands", [])
	if not (raw_commands_value is Array or raw_commands_value is PackedFloat32Array or raw_commands_value is PackedFloat64Array):
		return {
			"valid": false,
			"error": "propeller_commands must be an Array or PackedFloat32Array",
		}
	var raw_commands: Array = Array(raw_commands_value)
	if raw_commands.size() != propeller_slots.size():
		return {
			"valid": false,
			"error": "Expected %d propeller commands, received %d" % [
				propeller_slots.size(),
				raw_commands.size(),
			],
		}

	var commands: Array[float] = []
	for array_index: int in range(propeller_slots.size()):
		var raw_command = raw_commands[array_index]
		var raw_value = raw_command
		if raw_command is Dictionary:
			var expected_slot_index = int(propeller_slots[array_index].slot_index)
			var command_slot_index = RLTrainingMath.finite_int_or(raw_command.get("slot_index"), -1)
			if command_slot_index != expected_slot_index:
				return {
					"valid": false,
					"error": "Propeller command %d does not target slot %d" % [
						array_index,
						expected_slot_index,
					],
				}
			raw_value = raw_command.get("command", NAN)
		if not (raw_value is float or raw_value is int):
			return {
				"valid": false,
				"error": "Propeller command %d is not numeric" % array_index,
			}
		var normalized_command = float(raw_value)

		if not is_finite(normalized_command):
			return {
				"valid": false,
				"error": "Propeller command %d is not finite" % array_index,
			}
		commands.append(clampf(
			normalized_command,
			MINIMUM_NORMALIZED_COMMAND,
			MAXIMUM_NORMALIZED_COMMAND
		))

	return {
		"valid": true,
		"commands": commands,
	}


static func validate_body_commands(
	action: Dictionary,
	manifest: MLBodyInterfaceManifest
) -> Dictionary:
	return MLBodyActionContract.validate(action, manifest)


static func validate_limb_commands(action: Dictionary, expected_count: int) -> Dictionary:
	var safe_expected_count = maxi(expected_count, 0)
	var raw_value: Variant = action.get("limb_commands", null)
	if raw_value == null:
		var neutral = PackedFloat64Array()
		neutral.resize(safe_expected_count)
		neutral.fill(0.0)
		return {"valid": true, "commands": neutral}
	if not (raw_value is Array or raw_value is PackedFloat32Array or raw_value is PackedFloat64Array):
		return {"valid": false, "error": "limb_commands must be an Array or packed float array"}
	var raw_commands: Array = Array(raw_value)
	if raw_commands.size() != safe_expected_count:
		return {
			"valid": false,
			"error": "Expected %d limb commands, received %d" % [safe_expected_count, raw_commands.size()],
		}
	var commands = PackedFloat64Array()
	commands.resize(safe_expected_count)
	for index in range(safe_expected_count):
		var value: Variant = raw_commands[index]
		if not (value is int or value is float) or not is_finite(float(value)):
			return {"valid": false, "error": "Limb command %d is not finite numeric data" % index}
		commands[index] = clampf(float(value), -1.0, 1.0)
	return {"valid": true, "commands": commands}


static func to_thrust_targets(
	commands: Array[float],
	propeller_slots: Array,
	loadout: DroneLoadout,
	air_environment: AirEnvironment
) -> Array[float]:
	var result: Array[float] = []
	result.resize(propeller_slots.size())
	result.fill(0.0)
	if loadout == null or air_environment == null:
		return result

	for array_index: int in range(propeller_slots.size()):
		var slot = propeller_slots[array_index]
		var propeller = loadout.get_propeller(int(slot.slot_index))
		if propeller == null:
			continue
		var maximum_thrust = air_environment.calculate_rotor_thrust(
			propeller.max_power_draw,
			propeller.get_disk_area(),
			propeller.aerodynamic_efficiency
		)
		result[array_index] = commands[array_index] * maximum_thrust
	return result
