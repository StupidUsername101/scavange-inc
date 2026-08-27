@tool
class_name GunReceiverDefinition
extends GunPartDefinition

#######################################################
# Defines the serialized gun receiver configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Receiver")
@export_range(0.1, 100.0, 0.01, "or_greater") var rounds_per_second := 4.0
@export_range(0.0, 15.0, 0.01, "or_greater") var base_spread_degrees := 1.4
@export_range(0.0, 10.0, 0.01, "or_greater") var damage_multiplier := 1.0
@export_range(0.05, 20.0, 0.01, "or_greater") var reload_seconds := 1.4
@export var automatic := false
@export var presentation_profile: StringName = &"pistol"

@export_group("Report")
@export var fire_sound_id: StringName = &""
## Hearing reach at 0 dB; fire_sound_volume_db scales it by the inverse-square relation.
@export_range(0.1, 10000.0, 0.1, "or_greater") var fire_sound_max_distance := 80.0
@export_range(-60.0, 18.0, 0.1) var fire_sound_volume_db := 0.0
@export_range(0.0, 1.0, 0.01) var fire_sound_priority := 0.9
## -1 uses the standard one-shot response; receivers may opt out with 0 or author 0..1.
@export_range(-1.0, 1.0, 0.01) var fire_pressure_strength := -1.0
@export var reload_out_sound_id: StringName = &"pistol_reload_out"
@export var reload_in_sound_id: StringName = &"pistol_reload_in"


func _init() -> void:
	part_slot = PartSlot.RECEIVER
