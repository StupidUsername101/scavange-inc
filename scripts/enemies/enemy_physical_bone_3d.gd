class_name EnemyPhysicalBone3D
extends PhysicalBone3D

#######################################################
# Implements the enemy physical bone 3d subsystem and keeps its gameplay data and behavior in
# one focused script.
#######################################################

var enemy: ServerEnemy
var limb_index := -1
var segment_index := -1
var expected_bone_id := -1
var previous_drive_transform := Transform3D.IDENTITY
var has_previous_drive_transform := false


func configure(
	owner_enemy: ServerEnemy,
	new_limb_index: int,
	new_segment_index: int,
	new_expected_bone_id: int
) -> void:
	enemy = owner_enemy
	limb_index = new_limb_index
	segment_index = new_segment_index
	expected_bone_id = new_expected_bone_id


func reset_drive_history() -> void:
	previous_drive_transform = Transform3D.IDENTITY
	has_previous_drive_transform = false


func apply_damage(amount: float) -> void:
	if is_instance_valid(enemy):
		enemy.apply_damage(amount)
