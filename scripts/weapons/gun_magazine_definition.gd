@tool
class_name GunMagazineDefinition
extends GunPartDefinition

#######################################################
# Defines the serialized gun magazine configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Magazine")
@export_range(1, 500, 1, "or_greater") var capacity := 8
@export_range(0.1, 5.0, 0.01, "or_greater") var reload_time_multiplier := 1.0


func _init() -> void:
	part_slot = PartSlot.MAGAZINE
