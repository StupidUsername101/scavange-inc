@tool
class_name GunAmmunitionDefinition
extends GunPartDefinition

#######################################################
# Defines the serialized gun ammunition configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Ammunition")
@export var projectile: BallisticProjectileDefinition


func _init() -> void:
	part_slot = PartSlot.AMMUNITION
