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

@export_subgroup("Mounted Visual Pose")
@export var equipped_position := Vector3.ZERO:
	set(value):
		equipped_position = value if value.is_finite() else Vector3.ZERO
		emit_changed()

@export var equipped_rotation_degrees := Vector3.ZERO:
	set(value):
		equipped_rotation_degrees = value if value.is_finite() else Vector3.ZERO
		emit_changed()

@export var equipped_scale := Vector3.ONE:
	set(value):
		equipped_scale = (
			Vector3(
				maxf(value.x, 0.01),
				maxf(value.y, 0.01),
				maxf(value.z, 0.01)
			)
			if value.is_finite()
			else Vector3.ONE
		)
		emit_changed()


func can_equip() -> bool:
	return equipment_slot != &""


func instantiate_equipped_visual() -> Node3D:
	var visual: Node3D
	if equipped_visual_scene != null:
		visual = equipped_visual_scene.instantiate() as Node3D
	if visual == null:
		visual = instantiate_visual()
	if visual != null:
		# Mounted pose is an offset layered over the visual scene's authored root transform. Falling
		# back to instantiate_visual() must not erase an item's ordinary mesh offset or scale.
		visual.position += equipped_position
		visual.rotation_degrees += equipped_rotation_degrees
		visual.scale *= equipped_scale
	return visual
