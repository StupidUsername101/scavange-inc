@tool
class_name GunPartDefinition
extends ItemDefinition

#######################################################
# Defines the serialized gun part configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

enum PartSlot {
	RECEIVER,
	BARREL,
	MAGAZINE,
	AMMUNITION,
}

@export_group("Gun Component")
@export var part_slot := PartSlot.RECEIVER
@export var caliber_id: StringName = &""
@export var component_color := Color(0.22, 0.24, 0.27, 1.0)
@export var component_size := Vector3(0.2, 0.12, 0.24)


func instantiate_visual() -> Node3D:
	return GunGeometry.create_part_visual(self)
