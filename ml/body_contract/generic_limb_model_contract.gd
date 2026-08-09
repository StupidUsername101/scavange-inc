class_name GenericLimbModelContract
extends RefCounted

const LINEAR_VELOCITY_SCALE_MPS: float = 10.0
const ANGULAR_VELOCITY_SCALE_RADPS: float = 8.0
const MINIMUM_SCALE: float = 0.000001

#######################################################
# Model-facing contract for the same GenericLimbDefinition/GenericLimbAssembly3D stack used by
# four-limb workers and drone attachments. Feature/control counts are derived from authored limb
# topology; no fixed limb count or fixed segment count exists here.
#######################################################


static func control_descriptors(definitions: Array[GenericLimbDefinition]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for limb_index in range(definitions.size()):
		var limb: GenericLimbDefinition = definitions[limb_index]
		if limb == null or not limb.installed:
			continue
		var limb_controls: Array[Dictionary] = []
		var mapped_indices: Dictionary = {}
		var mapping_complete: bool = true
		for segment_index in range(limb.segments.size()):
			var segment: LimbSegmentDefinition = limb.segments[segment_index]
			if segment == null or segment.joint == null:
				continue
			for axis in range(3):
				if not segment.joint.axis_control_declared(axis):
					continue
				var mapped_index: int = segment.joint.action_indices[axis]
				if mapped_index < 0 or mapped_indices.has(mapped_index):
					mapping_complete = false
				elif mapping_complete:
					mapped_indices[mapped_index] = true
				limb_controls.append({
					"name": "limb_%d.segment_%d.joint_%s" % [limb_index, segment_index, _axis_name(axis)],
					"kind": "joint_target",
					"minimum": -1.0,
					"maximum": 1.0,
					"neutral": 0.0,
					"limb_index": limb_index,
					"segment_index": segment_index,
					"axis": axis,
					"_mapped_action_index": mapped_index,
				})
		if (
			limb.end_effector != null
			and limb.end_effector.enabled
			and limb.end_effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED
		):
			var grip_mapped_index: int = limb.end_effector.grip_action_index
			if grip_mapped_index < 0 or mapped_indices.has(grip_mapped_index):
				mapping_complete = false
			elif mapping_complete:
				mapped_indices[grip_mapped_index] = true
			limb_controls.append({
				"name": "limb_%d.grip" % limb_index,
				"kind": "grip_activation",
				"minimum": -1.0,
				"maximum": 1.0,
				"neutral": 0.0,
				"limb_index": limb_index,
				"_mapped_action_index": grip_mapped_index,
			})
		# Existing physical profiles can intentionally map axes in a non-XYZ order. Preserve that
		# local hardware contract when every declared channel already has a unique mapping. New body
		# creator parts normally have no mapping yet, so they retain deterministic topology order and
		# receive their dense global offsets only when the body draft is accepted.
		if mapping_complete and not limb_controls.is_empty():
			limb_controls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("_mapped_action_index", -1)) < int(b.get("_mapped_action_index", -1))
			)
		for descriptor: Dictionary in limb_controls:
			descriptor.erase("_mapped_action_index")
			result.append(descriptor)
	return result


static func observation_descriptors(definitions: Array[GenericLimbDefinition]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for limb_index in range(definitions.size()):
		var limb: GenericLimbDefinition = definitions[limb_index]
		if limb == null or not limb.installed:
			continue
		for segment_index in range(limb.segments.size()):
			var prefix: String = "limb_%d.segment_%d" % [limb_index, segment_index]
			_append_names(result, prefix, [
				"position_local_x", "position_local_y", "position_local_z",
				"linear_velocity_local_x", "linear_velocity_local_y", "linear_velocity_local_z",
				"angular_velocity_local_x", "angular_velocity_local_y", "angular_velocity_local_z",
				"up_local_x", "up_local_y", "up_local_z",
				"forward_local_x", "forward_local_y", "forward_local_z",
				"health", "actuator_effectiveness",
			])
			var segment: LimbSegmentDefinition = limb.segments[segment_index]
			if segment != null and segment.joint != null:
				for axis in range(3):
					if segment.joint.axis_control_declared(axis):
						_append_names(result, "%s.joint_%s" % [prefix, _axis_name(axis)], [
							"angle", "target_error", "active_torque",
						])
		if limb.end_effector != null and limb.end_effector.enabled:
			_append_names(result, "limb_%d.effector" % limb_index, [
				"activation",
				"candidate_present",
				"candidate_direction_local_x", "candidate_direction_local_y", "candidate_direction_local_z",
				"candidate_distance",
				"attached",
				"attached_direction_local_x", "attached_direction_local_y", "attached_direction_local_z",
				"load_ratio", "health",
			])
	return result


static func encode(
	definitions: Array[GenericLimbDefinition],
	assembly_state_value: Variant,
	_host_state: Dictionary = {}
) -> PackedFloat64Array:
	var assembly_state: Dictionary = assembly_state_value if assembly_state_value is Dictionary else {}
	var host_transform: Transform3D = assembly_state.get("host_transform_world", Transform3D.IDENTITY)
	var host_inverse_basis: Basis = host_transform.basis.inverse()
	var host_linear: Vector3 = assembly_state.get("host_linear_velocity_world", Vector3.ZERO)
	var host_angular: Vector3 = assembly_state.get("host_angular_velocity_world", Vector3.ZERO)
	var limb_states_value: Variant = assembly_state.get("limbs", [])
	var limb_states: Array = limb_states_value if limb_states_value is Array else []
	var result = PackedFloat64Array()
	for limb_index in range(definitions.size()):
		var limb: GenericLimbDefinition = definitions[limb_index]
		if limb == null or not limb.installed:
			continue
		var limb_state: Dictionary = _dictionary_at(limb_states, limb_index)
		var reach: float = maxf(limb.maximum_reach(), 0.1)
		var segment_states_value: Variant = limb_state.get("segments", [])
		var segment_states: Array = segment_states_value if segment_states_value is Array else []
		var joint_states_value: Variant = limb_state.get("joints", [])
		var joint_states: Array = joint_states_value if joint_states_value is Array else []
		for segment_index in range(limb.segments.size()):
			var segment_definition: LimbSegmentDefinition = limb.segments[segment_index]
			var segment_state: Dictionary = _dictionary_at(segment_states, segment_index)
			var transform: Transform3D = segment_state.get("transform_world", host_transform)
			var relative_position: Vector3 = host_inverse_basis * (transform.origin - host_transform.origin)
			_append_vector(result, relative_position / reach)
			var linear_world: Vector3 = segment_state.get("linear_velocity_world", host_linear)
			_append_vector(result, (host_inverse_basis * (linear_world - host_linear)) / LINEAR_VELOCITY_SCALE_MPS)
			var angular_world: Vector3 = segment_state.get("angular_velocity_world", host_angular)
			_append_vector(result, (host_inverse_basis * (angular_world - host_angular)) / ANGULAR_VELOCITY_SCALE_RADPS)
			_append_vector(result, host_inverse_basis * transform.basis.y.normalized())
			_append_vector(result, host_inverse_basis * transform.basis.z.normalized())
			result.append(_unit_to_signed(float(segment_state.get("health_ratio", 0.0))))
			result.append(_unit_to_signed(float(segment_state.get("actuator_effectiveness", 0.0))))
			if segment_definition == null or segment_definition.joint == null:
				continue
			var joint: LimbJointDefinition = segment_definition.joint
			var joint_state: Dictionary = _dictionary_at(joint_states, segment_index)
			var current: Vector3 = joint_state.get("current_angles", Vector3.ZERO)
			var error: Vector3 = joint_state.get("target_error_angles", Vector3.ZERO)
			var active_torque: Vector3 = joint_state.get("active_torque_joint", Vector3.ZERO)
			for axis in range(3):
				if not joint.axis_control_declared(axis):
					continue
				var angle_scale: float = maxf(
					maxf(absf(deg_to_rad(joint.lower_limit_degrees[axis])), absf(deg_to_rad(joint.upper_limit_degrees[axis]))),
					deg_to_rad(1.0)
				)
				result.append(clampf(current[axis] / angle_scale, -1.0, 1.0))
				result.append(clampf(error[axis] / angle_scale, -1.0, 1.0))
				var torque_scale: float = maxf(joint.maximum_active_torque[axis], MINIMUM_SCALE)
				result.append(clampf(active_torque[axis] / torque_scale, -1.0, 1.0))
		if limb.end_effector != null and limb.end_effector.enabled:
			_append_effector(result, limb.end_effector, limb_state.get("end_effector", {}), host_transform)
	var expected: int = observation_descriptors(definitions).size()
	return result if result.size() == expected and _all_finite(result) else PackedFloat64Array()


static func runtime_state_for_limb(
	limb: GenericLimb3D,
	host_body: RigidBody3D
) -> Dictionary:
	if not is_instance_valid(limb) or limb.definition == null:
		return {}
	var segment_states: Array[Dictionary] = []
	for segment: LimbSegment3D in limb.segments:
		if not is_instance_valid(segment):
			continue
		segment_states.append({
			"segment_index": segment.segment_index,
			"transform_world": segment.global_transform,
			"linear_velocity_world": segment.linear_velocity,
			"angular_velocity_world": segment.angular_velocity,
			"mass": segment.mass,
			"health_ratio": segment.health_ratio(),
			"actuator_effectiveness": segment.actuator_effectiveness,
		})
	var joint_states: Array[Dictionary] = []
	for record: Dictionary in limb.joint_records:
		var definition: LimbJointDefinition = record.get("definition") as LimbJointDefinition
		joint_states.append({
			"joint_index": int(record.get("joint_index", joint_states.size())),
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
	var host_transform: Transform3D = (
		host_body.global_transform if is_instance_valid(host_body) else Transform3D.IDENTITY
	)
	var host_linear: Vector3 = (
		host_body.linear_velocity if is_instance_valid(host_body) else Vector3.ZERO
	)
	var host_angular: Vector3 = (
		host_body.angular_velocity if is_instance_valid(host_body) else Vector3.ZERO
	)
	return {
		"host_instance_id": host_body.get_instance_id() if is_instance_valid(host_body) else 0,
		"host_transform_world": host_transform,
		"host_linear_velocity_world": host_linear,
		"host_angular_velocity_world": host_angular,
		"action_count": limb.definition.required_action_count(),
		"mapping_valid": limb.definition.has_unique_action_mapping(),
		"commands": PackedFloat64Array(),
		"limbs": [{
			"slot_index": limb.slot_index,
			"limb_name": limb.definition.limb_name,
			"installed": limb.definition.installed,
			"end_effector": limb.end_effector_snapshot(),
			"segment_count": limb.segments.size(),
			"segments": segment_states,
			"joints": joint_states,
		}],
	}


static func _append_effector(
	result: PackedFloat64Array,
	definition: LimbEndEffectorDefinition,
	state_value: Variant,
	host_transform: Transform3D
) -> void:
	var state: Dictionary = state_value if state_value is Dictionary else {}
	var inverse_basis: Basis = host_transform.basis.inverse()
	var position: Vector3 = state.get("position_world", host_transform.origin)
	result.append(_unit_to_signed(float(state.get("activation", 0.0))))
	var candidate_present: bool = bool(state.get("candidate_present", false))
	result.append(1.0 if candidate_present else -1.0)
	if candidate_present:
		var candidate_point: Vector3 = state.get("candidate_point_world", position)
		var candidate_offset: Vector3 = inverse_basis * (candidate_point - position)
		_append_vector(result, candidate_offset.normalized() if candidate_offset.length_squared() > MINIMUM_SCALE else Vector3.ZERO)
		result.append(_unsigned_to_signed(
			float(state.get("candidate_distance", candidate_offset.length())),
			maxf(definition.grip_detection_radius, 0.01)
		))
	else:
		_append_vector(result, Vector3.ZERO)
		result.append(0.0)
	var attached: bool = bool(state.get("attached", false))
	result.append(1.0 if attached else -1.0)
	if attached:
		var attached_point: Vector3 = state.get("attached_point_world", position)
		var attached_offset: Vector3 = inverse_basis * (attached_point - position)
		_append_vector(result, attached_offset.normalized() if attached_offset.length_squared() > MINIMUM_SCALE else Vector3.ZERO)
		result.append(clampf(float(state.get("load_ratio", 0.0)), 0.0, 2.0) - 1.0)
	else:
		_append_vector(result, Vector3.ZERO)
		result.append(0.0)
	result.append(_unit_to_signed(float(state.get("health_ratio", 0.0))))


static func _append_names(target: Array[Dictionary], prefix: String, names: Array[String]) -> void:
	for suffix: String in names:
		target.append({"name": "%s.%s" % [prefix, suffix], "minimum": -1.0, "maximum": 1.0})


static func _append_vector(target: PackedFloat64Array, value: Vector3) -> void:
	target.append(clampf(value.x, -1.0, 1.0))
	target.append(clampf(value.y, -1.0, 1.0))
	target.append(clampf(value.z, -1.0, 1.0))


static func _dictionary_at(source: Array, index: int) -> Dictionary:
	if index < 0 or index >= source.size() or not (source[index] is Dictionary):
		return {}
	return source[index]


static func _axis_name(axis: int) -> String:
	return ["x", "y", "z"][clampi(axis, 0, 2)]


static func _unit_to_signed(value: float) -> float:
	return clampf(value, 0.0, 1.0) * 2.0 - 1.0


static func _unsigned_to_signed(value: float, scale: float) -> float:
	return clampf(maxf(value, 0.0) / maxf(scale, MINIMUM_SCALE), 0.0, 1.0) * 2.0 - 1.0


static func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
