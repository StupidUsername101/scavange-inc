class_name GenericLimbStateSnapshot
extends RefCounted

#######################################################
# Shared serialization of one live GenericLimb3D. Host/controller state remains owned by the
# caller because model-contract snapshots and full assembly snapshots intentionally differ there.
#######################################################


static func segment_states(limb: GenericLimb3D) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if not is_instance_valid(limb):
		return states
	for segment: LimbSegment3D in limb.segments:
		if not is_instance_valid(segment):
			continue
		states.append({
			"segment_index": segment.segment_index,
			"transform_world": segment.global_transform,
			"linear_velocity_world": segment.linear_velocity,
			"angular_velocity_world": segment.angular_velocity,
			"mass": segment.mass,
			"health_ratio": segment.health_ratio(),
			"actuator_effectiveness": segment.actuator_effectiveness,
		})
	return states


static func joint_states(limb: GenericLimb3D) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if not is_instance_valid(limb):
		return states
	for record: Dictionary in limb.joint_records:
		var definition: LimbJointDefinition = record.get("definition") as LimbJointDefinition
		states.append({
			"joint_index": int(record.get("joint_index", states.size())),
			"action_indices": (
				definition.action_indices if definition != null else Vector3i(-1, -1, -1)
			),
			"current_angles": record.get("current_angles", Vector3.ZERO),
			"target_angles": record.get("target_angles", Vector3.ZERO),
			"target_error_angles": record.get("target_error_angles", Vector3.ZERO),
			"rest_error_angles": record.get("rest_error_angles", Vector3.ZERO),
			"applied_torque_joint": record.get("applied_torque_joint", Vector3.ZERO),
			"passive_torque_joint": record.get("passive_torque_joint", Vector3.ZERO),
			"active_torque_joint": record.get("active_torque_joint", Vector3.ZERO),
			"limit_torque_joint": record.get("limit_torque_joint", Vector3.ZERO),
		})
	return states


static func limb_state(limb: GenericLimb3D) -> Dictionary:
	if not is_instance_valid(limb):
		return {}
	var definition: GenericLimbDefinition = limb.definition
	return {
		"slot_index": limb.slot_index,
		"limb_name": definition.limb_name if definition != null else "",
		"installed": definition.installed if definition != null else false,
		"end_effector": limb.end_effector_snapshot(),
		"segment_count": limb.segments.size(),
		"segments": segment_states(limb),
		"joints": joint_states(limb),
	}
