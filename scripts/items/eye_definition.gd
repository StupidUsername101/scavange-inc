@tool
extends EquippableItemDefinition
class_name EyeDefinition

#######################################################
# Defines the serialized eye configuration shared by gameplay, inspection, and replication
# systems.
#######################################################

@export_group("Sight")
@export_range(0.0, 1.0, 0.01) var visual_acuity := 0.8:
	set(value):
		visual_acuity = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0, 0.01) var contrast_sensitivity := 0.75:
	set(value):
		contrast_sensitivity = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0, 0.01) var light_sensitivity := 0.7:
	set(value):
		light_sensitivity = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0, 0.01) var optical_quality := 0.75:
	set(value):
		optical_quality = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(-0.15, 0.15, 0.001) var lens_distortion := 0.01:
	set(value):
		lens_distortion = clampf(value, -0.15, 0.15)
		emit_changed()

@export_range(0.0, 1.0, 0.01) var motion_smear := 0.2:
	set(value):
		motion_smear = clampf(value, 0.0, 1.0)
		emit_changed()

@export var vision_shader: Shader:
	set(value):
		vision_shader = value
		emit_changed()

@export_group("Future Sight Capabilities")
@export var special_sight_effects: Array[StringName] = []:
	set(value):
		special_sight_effects = value
		emit_changed()


func _init() -> void:
	equipment_slot = &"eyes"


func has_special_sight(effect_id: StringName) -> bool:
	return special_sight_effects.has(effect_id)


func get_vision_parameters() -> Dictionary:
	return {
		"visual_acuity": visual_acuity,
		"contrast_sensitivity": contrast_sensitivity,
		"light_sensitivity": light_sensitivity,
		"optical_quality": optical_quality,
		"base_distortion": lens_distortion,
		"motion_smear": motion_smear,
	}
