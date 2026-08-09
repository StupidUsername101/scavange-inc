class_name FourLimbPhysicalBone3D
extends PhysicalBone3D

#######################################################
# Physical segment with explicit limb identity and damage/effectiveness state.
#######################################################

var owner_body: FourLimbPhysicalBody3D
var limb_slot_index = -1
var segment_index = -1
var expected_bone_id = -1
var maximum_health = 100.0
var current_health = 100.0
var actuator_effectiveness = 1.0


func configure(
	body: FourLimbPhysicalBody3D,
	slot_index: int,
	new_segment_index: int,
	new_expected_bone_id: int,
	health_value: float
) -> void:
	owner_body = body
	limb_slot_index = slot_index
	segment_index = new_segment_index
	expected_bone_id = new_expected_bone_id
	maximum_health = maxf(health_value, 0.001)
	current_health = maximum_health


func health_ratio() -> float:
	return clampf(current_health / maxf(maximum_health, 0.001), 0.0, 1.0)


func functional_ratio() -> float:
	return health_ratio() * clampf(actuator_effectiveness, 0.0, 1.0)


func apply_segment_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if is_instance_valid(owner_body) and limb_slot_index >= 0:
		owner_body.notify_limb_damage(limb_slot_index)


func has_valid_binding(require_simulating: bool = false) -> bool:
	if get_bone_id() != expected_bone_id or expected_bone_id < 0:
		return false
	return not require_simulating or is_simulating_physics()
