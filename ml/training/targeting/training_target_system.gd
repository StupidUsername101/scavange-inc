class_name TrainingTargetSystem
extends RefCounted

#######################################################
# Base contract for one deterministic source of training targets. Systems publish candidate
# dictionaries; TrainingTargetHandler decides which candidate becomes the single objective
# forwarded through the existing ML observation contract.
#######################################################

var enabled: bool = true
var instance_key: String = ""


func type_id() -> StringName:
	return &"base"


func display_name() -> String:
	return "Target system"


func reset(_seed: int, _context: Dictionary = {}) -> void:
	pass


func tick(_delta: float, _context: Dictionary = {}) -> void:
	pass


func append_candidates(_output: Array[Dictionary], _context: Dictionary = {}) -> void:
	pass


func configuration_dictionary() -> Dictionary:
	return {
		"type_id": str(type_id()),
		"enabled": enabled,
	}


func load_configuration(configuration: Dictionary) -> void:
	enabled = RLTrainingMath.bool_or(configuration.get("enabled", enabled), enabled)


func clone_configured() -> TrainingTargetSystem:
	return null
