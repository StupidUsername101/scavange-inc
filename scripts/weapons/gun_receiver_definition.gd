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


func _init() -> void:
	part_slot = PartSlot.RECEIVER
