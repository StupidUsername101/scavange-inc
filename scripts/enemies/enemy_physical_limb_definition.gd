@tool
class_name EnemyPhysicalLimbDefinition
extends Resource

#######################################################
# Defines the serialized enemy physical limb configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Identity")
@export var limb_name := "Limb"
## Ordered locomotion phase. Limbs with the same value swing together; groups
## advance numerically and wrap, allowing tetrapod, tripod, wave, or custom
## support cycles without limb-count-specific controller code.
@export_range(0, 32, 1) var gait_group := 0

@export_group("Placement")
@export var hip_offset := Vector3.ZERO
@export var rest_foot_offset := Vector3(0.0, -1.0, 0.75)
@export var bend_hint := Vector3.UP

@export_group("Segments")
@export_range(0.05, 10.0, 0.01, "or_greater") var upper_length := 1.0
@export_range(0.05, 10.0, 0.01, "or_greater") var lower_length := 1.0
@export_range(0.01, 2.0, 0.005, "or_greater") var segment_radius := 0.09
@export_range(0.01, 1000.0, 0.01, "or_greater") var segment_mass := 0.35

@export_group("Joint Limits")
## Limits are offsets from the authored bent rest pose, not absolute anatomical
## angles. Keeping a knee's range smaller than its rest bend prevents the
## physical hinge from passing through straight and inverting to the other side.
@export_range(1.0, 120.0, 0.5) var hip_swing_span_degrees := 58.0
@export_range(1.0, 120.0, 0.5) var hip_twist_span_degrees := 34.0
@export_range(-89.0, -1.0, 0.5) var knee_limit_lower_degrees := -52.0
@export_range(1.0, 89.0, 0.5) var knee_limit_upper_degrees := 52.0


func get_maximum_reach() -> float:
	return upper_length + lower_length


func get_minimum_reach() -> float:
	return absf(upper_length - lower_length)
