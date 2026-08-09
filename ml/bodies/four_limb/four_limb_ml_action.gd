class_name FourLimbMLAction
extends RefCounted

const SCHEMA_VERSION = 5
const CONTROL_MODE = "normalized_limb_actuator_targets_pd_bipolar_grip"
const LIMB_COUNT = 4
const JOINT_AXES_PER_LIMB = 3
# Compatibility name used by joint-only diagnostic code.
const AXES_PER_LIMB = JOINT_AXES_PER_LIMB
const ACTIONS_PER_LIMB = 4
const JOINT_ACTION_COUNT = LIMB_COUNT * JOINT_AXES_PER_LIMB
const ACTION_COUNT = LIMB_COUNT * ACTIONS_PER_LIMB
const ACTION_NAMES = [
	"hip_elevation_target",
	"hip_horizontal_sweep_target",
	"knee_bend_target",
	"grip_activation",
]
const AXIS_NAMES = ACTION_NAMES

#######################################################
# Every output belongs to one real actuator: three joint-position targets and one distal grip
# activation per limb. Positive hip elevation raises the upper segment in its radial vertical
# plane; the independent knee-bend output chooses the distal fold needed for the current pose.
# Retraction/recovery therefore remains a direct physical joint-control problem rather than a
# gait macro. There are no walk, turn, jump, pickup, climbing, or gait macro actions.
#######################################################


static func neutral_commands() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(ACTION_COUNT)
	result.fill(0.0)
	return result


static func action_offset(limb_index: int, actuator_index: int) -> int:
	return limb_index * ACTIONS_PER_LIMB + actuator_index


static func grip_action_offset(limb_index: int) -> int:
	return action_offset(limb_index, 3)


static func from_commands(commands: PackedFloat64Array) -> Dictionary:
	if commands.size() != ACTION_COUNT:
		return {}
	var targets: Array[Dictionary] = []
	for limb_index in range(LIMB_COUNT):
		for actuator_index in range(ACTIONS_PER_LIMB):
			var value := commands[action_offset(limb_index, actuator_index)]
			if not is_finite(value):
				return {}
			targets.append({
				"limb_index": limb_index,
				"actuator_index": actuator_index,
				"actuator_name": ACTION_NAMES[actuator_index],
				"target": clampf(value, -1.0, 1.0),
			})
	return {
		"schema_version": SCHEMA_VERSION,
		"body_profile_id": FourLimbBodyDefinition.BODY_PROFILE_ID,
		"control_mode": CONTROL_MODE,
		"actuator_targets": targets,
	}


static func packed_commands(action: Dictionary) -> PackedFloat64Array:
	if (
		RLTrainingMath.finite_int_or(action.get("schema_version"), -1) != SCHEMA_VERSION
		or str(action.get("body_profile_id", "")) != FourLimbBodyDefinition.BODY_PROFILE_ID
		or str(action.get("control_mode", "")) != CONTROL_MODE
	):
		return PackedFloat64Array()
	var targets_value: Variant = action.get("actuator_targets", [])
	if not (targets_value is Array):
		return PackedFloat64Array()
	var targets: Array = targets_value
	if targets.size() != ACTION_COUNT:
		return PackedFloat64Array()
	var result := neutral_commands()
	var seen: Dictionary[int, bool] = {}
	for entry_value: Variant in targets:
		if not (entry_value is Dictionary):
			return PackedFloat64Array()
		var entry: Dictionary = entry_value
		var limb_value: Variant = entry.get("limb_index")
		var actuator_value: Variant = entry.get("actuator_index")
		if typeof(limb_value) != TYPE_INT or typeof(actuator_value) != TYPE_INT:
			return PackedFloat64Array()
		var limb_index := int(limb_value)
		var actuator_index := int(actuator_value)
		if (
			limb_index < 0 or limb_index >= LIMB_COUNT
			or actuator_index < 0 or actuator_index >= ACTIONS_PER_LIMB
			or str(entry.get("actuator_name", "")) != ACTION_NAMES[actuator_index]
		):
			return PackedFloat64Array()
		var offset := action_offset(limb_index, actuator_index)
		if seen.has(offset):
			return PackedFloat64Array()
		var target_value: Variant = entry.get("target")
		if (
			(typeof(target_value) != TYPE_INT and typeof(target_value) != TYPE_FLOAT)
			or not is_finite(float(target_value))
		):
			return PackedFloat64Array()
		result[offset] = clampf(float(target_value), -1.0, 1.0)
		seen[offset] = true
	return result if seen.size() == ACTION_COUNT else PackedFloat64Array()
