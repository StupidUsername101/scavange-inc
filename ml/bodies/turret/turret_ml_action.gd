class_name TurretMLAction
extends RefCounted

const SCHEMA_VERSION = 1
const ACTION_COUNT = 3
const YAW_INDEX = 0
const PITCH_INDEX = 1
const TRIGGER_INDEX = 2


static func from_commands(commands: PackedFloat64Array) -> Dictionary:
	if commands.size() != ACTION_COUNT:
		return {}
	for command in commands:
		if not is_finite(command):
			return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"yaw_drive": clampf(commands[YAW_INDEX], -1.0, 1.0),
		"pitch_drive": clampf(commands[PITCH_INDEX], -1.0, 1.0),
		"trigger": clampf((commands[TRIGGER_INDEX] + 1.0) * 0.5, 0.0, 1.0),
	}


static func packed_commands(action: Dictionary) -> PackedFloat64Array:
	if RLTrainingMath.finite_int_or(action.get("schema_version"), -1) != SCHEMA_VERSION:
		return PackedFloat64Array()
	var yaw_drive: float = RLTrainingMath.finite_float_or(action.get("yaw_drive"), NAN)
	var pitch_drive: float = RLTrainingMath.finite_float_or(action.get("pitch_drive"), NAN)
	var trigger: float = RLTrainingMath.finite_float_or(action.get("trigger"), NAN)
	var values = PackedFloat64Array([
		yaw_drive,
		pitch_drive,
		trigger * 2.0 - 1.0,
	])
	for value in values:
		if not is_finite(value) or value < -1.000001 or value > 1.000001:
			return PackedFloat64Array()
	return values


static func neutral_commands() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, -1.0])
