@tool
extends ItemDefinition
class_name EquippableItemDefinition

#######################################################
# Defines the serialized equippable item configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Equipment")
@export var equipment_slot: StringName = &"":
	set(value):
		equipment_slot = value
		emit_changed()

@export var equipped_visual_scene: PackedScene:
	set(value):
		equipped_visual_scene = value
		emit_changed()


func can_equip() -> bool:
	return equipment_slot != &""


func instantiate_equipped_visual() -> Node3D:
	if equipped_visual_scene != null:
		var visual := equipped_visual_scene.instantiate() as Node3D
		if visual != null:
			return visual
	return instantiate_visual()
