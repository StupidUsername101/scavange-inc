@tool
extends EquippableItemDefinition
class_name BackpackDefinition

#######################################################
# Defines the serialized backpack configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Backpack")
@export_range(1, 9, 1) var inventory_capacity := 3:
	set(value):
		inventory_capacity = clampi(value, 1, 9)
		emit_changed()


func _init() -> void:
	equipment_slot = &"backpack"
