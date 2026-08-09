@tool
class_name CharacterLoadout
extends Resource

#######################################################
# Implements the character loadout subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

@export_group("Arms")
@export var left_arm: LimbDefinition
@export var right_arm: LimbDefinition

@export_group("Legs")
@export var left_leg: LimbDefinition
@export var right_leg: LimbDefinition


func install_limb(limb: LimbDefinition) -> void:
	if limb == null:
		return

	match limb.slot:
		LimbDefinition.Slot.LEFT_ARM:
			left_arm = limb
		LimbDefinition.Slot.RIGHT_ARM:
			right_arm = limb
		LimbDefinition.Slot.LEFT_LEG:
			left_leg = limb
		LimbDefinition.Slot.RIGHT_LEG:
			right_leg = limb


func remove_limb(slot: LimbDefinition.Slot) -> void:
	match slot:
		LimbDefinition.Slot.LEFT_ARM:
			left_arm = null
		LimbDefinition.Slot.RIGHT_ARM:
			right_arm = null
		LimbDefinition.Slot.LEFT_LEG:
			left_leg = null
		LimbDefinition.Slot.RIGHT_LEG:
			right_leg = null


func get_grab_strength_multiplier() -> float:
	return (
		_get_grab_strength(left_arm)
		+ _get_grab_strength(right_arm)
	)


func get_movement_multiplier() -> float:
	return maxf(
		_get_movement(left_leg) + _get_movement(right_leg),
		0.0
	)


func get_jump_multiplier() -> float:
	return maxf(
		_get_jumping(left_leg) + _get_jumping(right_leg),
		0.0
	)


func has_any_arm() -> bool:
	return left_arm != null or right_arm != null


func has_any_leg() -> bool:
	return left_leg != null or right_leg != null


func to_state_dict() -> Dictionary:
	return {
		"left_arm": left_arm != null,
		"right_arm": right_arm != null,
		"left_leg": left_leg != null,
		"right_leg": right_leg != null,
	}


func _get_grab_strength(limb: LimbDefinition) -> float:
	return limb.grab_strength if limb != null else 0.0


func _get_movement(limb: LimbDefinition) -> float:
	return limb.movement if limb != null else 0.0


func _get_jumping(limb: LimbDefinition) -> float:
	return limb.jumping if limb != null else 0.0
