class_name CharacterPoseDefinition
extends Resource

## Authored additive pose layer. Every value is relative to the character's explicit rest pose;
## zero therefore remains a valid deterministic baseline for blending, missing limbs, and late join.

@export var pose_id: StringName = &""
@export_range(0.0, 1.0, 0.01) var procedural_inheritance := 1.0
@export_range(0.0, 1.0, 0.01) var upper_body_weight := 0.0
@export var upper_body_position := Vector3.ZERO
@export var upper_body_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var head_weight := 0.0
@export var head_position := Vector3.ZERO
@export var head_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var left_arm_weight := 0.0
@export var left_arm_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var left_forearm_weight := 0.0
@export var left_forearm_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var right_arm_weight := 0.0
@export var right_arm_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var right_forearm_weight := 0.0
@export var right_forearm_rotation := Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var camera_weight := 0.0
@export var camera_position := Vector3.ZERO
@export var camera_rotation := Vector3.ZERO
