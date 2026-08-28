@tool
class_name DetailedFootContactSurface3D
extends StaticBody3D

## Marks detailed walkable geometry for procedural feet. By default this body is invisible to
## gameplay movement and exists only for contact queries. Enable `also_blocks_movement` only when
## the same collision really should be used by CharacterBody3D as well.

@export var also_blocks_movement := false:
	set(value):
		also_blocks_movement = value
		_apply_collision_role()


func _enter_tree() -> void:
	_apply_collision_role()


func _apply_collision_role() -> void:
	collision_layer = CharacterContactLayers.FOOT_CONTACT_DETAIL
	if also_blocks_movement:
		collision_layer |= CharacterContactLayers.MOVEMENT_SURFACE
	collision_mask = 0
