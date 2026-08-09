@tool
class_name GunBarrelDefinition
extends GunPartDefinition

#######################################################
# Defines the serialized gun barrel configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Barrel")
@export_range(0.05, 2.0, 0.01, "or_greater") var barrel_length := 0.24
@export_range(0.05, 10.0, 0.01, "or_greater") var velocity_multiplier := 1.0
@export_range(0.0, 10.0, 0.01, "or_greater") var damage_multiplier := 1.0
@export_range(0.05, 10.0, 0.01, "or_greater") var spread_multiplier := 1.0
@export_range(0.05, 10.0, 0.01, "or_greater") var range_multiplier := 1.0


func _init() -> void:
	part_slot = PartSlot.BARREL
