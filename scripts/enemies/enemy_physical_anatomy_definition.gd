@tool
class_name EnemyPhysicalAnatomyDefinition
extends Resource

#######################################################
# Defines the serialized enemy physical anatomy configuration shared by gameplay, inspection,
# and replication systems.
#######################################################

@export var limbs: Array[EnemyPhysicalLimbDefinition] = []

@export_group("Gait")
@export_range(0.01, 5.0, 0.01, "or_greater") var step_trigger_distance := 0.48
@export_range(0.05, 5.0, 0.01, "or_greater") var step_duration := 0.3
@export_range(0.0, 5.0, 0.01, "or_greater") var step_height := 0.42
@export_range(0.0, 5.0, 0.01, "or_greater") var velocity_look_ahead := 0.16
## Brief all-feet-planted interval between gait groups. This avoids changing
## support sets in the same physics tick and models the transfer phase used by
## alternating tetrapod gaits.
@export_range(0.0, 1.0, 0.005, "or_greater") var support_transfer_duration := 0.04
## Adds outward clearance at mid-swing so a physical leg does not sweep
## through or underneath the chassis on its way to the next foothold.
@export_range(0.0, 2.0, 0.01, "or_greater") var swing_retraction_distance := 0.12
@export_range(0.0, 10.0, 0.05, "or_greater") var probe_height := 1.25
@export_range(0.0, 20.0, 0.05, "or_greater") var probe_depth := 2.5

@export_group("Physical Drive")
@export_range(0.0, 1000.0, 0.1, "or_greater") var position_stiffness := 30.0
@export_range(0.0, 100.0, 0.05, "or_greater") var position_damping := 8.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_drive_force := 180.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var angular_stiffness := 26.0
@export_range(0.0, 100.0, 0.05, "or_greater") var angular_damping := 7.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_drive_torque := 75.0
@export_range(0.1, 100.0, 0.1, "or_greater") var maximum_target_speed := 12.0
@export_range(0.1, 200.0, 0.1, "or_greater") var maximum_target_angular_speed := 30.0
@export_range(0.0, 1.0, 0.01) var physical_influence := 1.0
## Procedurally driven limbs are already held against their authored targets by
## the linear and angular drives. Leaving full gravity enabled adds a constant
## unmodelled load and makes the chains sag beneath a moving chassis.
@export_range(0.0, 8.0, 0.01, "or_greater") var driven_gravity_scale := 0.0
## Ragdolls should return to ordinary world gravity after the active controller
## releases them.
@export_range(0.0, 8.0, 0.01, "or_greater") var ragdoll_gravity_scale := 1.0

@export_group("Physical Material")
@export_range(0.0, 1.0, 0.01) var friction := 0.82
@export_range(0.0, 1.0, 0.01) var bounce := 0.05
@export_range(0.0, 100.0, 0.05, "or_greater") var passive_linear_damp := 1.2
@export_range(0.0, 100.0, 0.05, "or_greater") var passive_angular_damp := 2.8


func get_segment_count() -> int:
	return limbs.size() * 2


func get_gait_group_count() -> int:
	var maximum_group := -1
	for limb: EnemyPhysicalLimbDefinition in limbs:
		if limb != null:
			maximum_group = maxi(maximum_group, limb.gait_group)
	return maximum_group + 1
