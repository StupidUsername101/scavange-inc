class_name GenericLimbModelContract
extends RefCounted

const LINEAR_VELOCITY_SCALE_MPS: float = 10.0
const ANGULAR_VELOCITY_SCALE_RADPS: float = 8.0
const MINIMUM_SCALE: float = 0.000001
const SEGMENT_OBSERVATION_COUNT: int = 17
const CONTROLLED_AXIS_OBSERVATION_COUNT: int = 3
const END_EFFECTOR_OBSERVATION_COUNT: int = 12

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


static func observation_count(definitions: Array[GenericLimbDefinition]) -> int:
	# Hot-path count used by runtime encoders. Building hundreds of descriptor Dictionaries every
	# control step merely to ask for .size() was a large avoidable cost on many-legged bodies.
	var result: int = 0
	for limb: GenericLimbDefinition in definitions:
		if limb == null or not limb.installed:
			continue
		for segment: LimbSegmentDefinition in limb.segments:
			result += SEGMENT_OBSERVATION_COUNT
			if segment == null or segment.joint == null:
				continue
			for axis: int in range(3):
				if segment.joint.axis_control_declared(axis):
					result += CONTROLLED_AXIS_OBSERVATION_COUNT
		if limb.end_effector != null and limb.end_effector.enabled:
			result += END_EFFECTOR_OBSERVATION_COUNT
	return result


static func encode(
	definitions: Array[GenericLimbDefinition],
	assembly_state_value: Variant,
	_host_state: Dictionary = {}
) -> PackedFloat64Array:
	if assembly_state_value is GenericLimbAssembly3D:
		return encode_runtime_assembly(
			definitions,
			assembly_state_value as GenericLimbAssembly3D
		)
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
	var expected: int = observation_count(definitions)
	return result if result.size() == expected and _all_finite(result) else PackedFloat64Array()


static func encode_runtime_assembly(
	definitions: Array[GenericLimbDefinition],
	assembly: GenericLimbAssembly3D
) -> PackedFloat64Array:
	# Training used to construct a large tree of per-segment/per-joint Dictionaries and immediately
	# unpack it again here. The finalized body contract is immutable, so the hot path can safely read
	# the matching instantiated assembly directly while preserving the exact same normalized tensor.
	if not is_instance_valid(assembly) or not is_instance_valid(assembly.host_body):
		return PackedFloat64Array()
	var host_body: RigidBody3D = assembly.host_body
	var host_transform: Transform3D = (
		host_body.call("model_transform_world") as Transform3D
		if host_body.has_method("model_transform_world")
		else host_body.global_transform
	)
	var host_inverse_basis: Basis = host_transform.basis.transposed()
	var host_linear: Vector3 = host_body.linear_velocity
	var host_angular: Vector3 = host_body.angular_velocity
	var result: PackedFloat64Array = PackedFloat64Array()
	var runtime_joint_cursor: int = 0
	for limb_index: int in range(definitions.size()):
		var limb_definition: GenericLimbDefinition = definitions[limb_index]
		if limb_definition == null or not limb_definition.installed:
			continue
		var runtime_limb: GenericLimb3D = assembly.limb_for_definition_index(limb_index)
		var reach: float = (
			runtime_limb.observation_reach
			if is_instance_valid(runtime_limb)
			else maxf(limb_definition.maximum_reach(), 0.1)
		)
		for segment_index: int in range(limb_definition.segments.size()):
			var segment_definition: LimbSegmentDefinition = limb_definition.segments[segment_index]
			var runtime_segment: LimbSegment3D = null
			if (
				is_instance_valid(runtime_limb)
				and segment_index >= 0
				and segment_index < runtime_limb.segments.size()
			):
				runtime_segment = runtime_limb.segments[segment_index]
			var transform: Transform3D = (
				runtime_segment.global_transform
				if is_instance_valid(runtime_segment)
				else host_transform
			)
			var relative_position: Vector3 = host_inverse_basis * (
				transform.origin - host_transform.origin
			)
			_append_vector(result, relative_position / reach)
			var linear_world: Vector3 = (
				runtime_segment.linear_velocity
				if is_instance_valid(runtime_segment)
				else host_linear
			)
			_append_vector(
				result,
				(host_inverse_basis * (linear_world - host_linear)) / LINEAR_VELOCITY_SCALE_MPS
			)
			var angular_world: Vector3 = (
				runtime_segment.angular_velocity
				if is_instance_valid(runtime_segment)
				else host_angular
			)
			_append_vector(
				result,
				(host_inverse_basis * (angular_world - host_angular)) / ANGULAR_VELOCITY_SCALE_RADPS
			)
			# Dynamic RigidBody3D bases are rotations; these axes are already normalized.
			_append_vector(result, host_inverse_basis * transform.basis.y)
			_append_vector(result, host_inverse_basis * transform.basis.z)
			result.append(_unit_to_signed(
				runtime_segment.health_ratio() if is_instance_valid(runtime_segment) else 0.0
			))
			result.append(_unit_to_signed(
				runtime_segment.actuator_effectiveness if is_instance_valid(runtime_segment) else 0.0
			))
			if segment_definition == null or segment_definition.joint == null:
				continue
			var joint_definition: LimbJointDefinition = segment_definition.joint
			var runtime_record = null
			if (
				is_instance_valid(assembly.controller)
				and runtime_joint_cursor >= 0
				and runtime_joint_cursor < assembly.controller.runtime_joint_records.size()
			):
				runtime_record = assembly.controller.runtime_joint_records[runtime_joint_cursor]
			runtime_joint_cursor += 1
			var current: Vector3 = (
				runtime_record.current_angles if runtime_record != null else Vector3.ZERO
			)
			var error: Vector3 = (
				runtime_record.target_error_angles if runtime_record != null else Vector3.ZERO
			)
			var active_torque: Vector3 = (
				runtime_record.active_torque_joint if runtime_record != null else Vector3.ZERO
			)
			var cached_scales_available: bool = (
				is_instance_valid(runtime_limb)
				and segment_index < runtime_limb.observation_angle_scales.size()
				and segment_index < runtime_limb.observation_torque_scales.size()
			)
			var cached_angle_scales: Vector3 = (
				runtime_limb.observation_angle_scales[segment_index]
				if cached_scales_available
				else Vector3.ONE
			)
			var cached_torque_scales: Vector3 = (
				runtime_limb.observation_torque_scales[segment_index]
				if cached_scales_available
				else Vector3.ONE
			)
			for axis: int in range(3):
				if not joint_definition.axis_control_declared(axis):
					continue
				var angle_scale: float = cached_angle_scales[axis]
				var torque_scale: float = cached_torque_scales[axis]
				if not cached_scales_available:
					angle_scale = maxf(
						maxf(
							absf(deg_to_rad(joint_definition.lower_limit_degrees[axis])),
							absf(deg_to_rad(joint_definition.upper_limit_degrees[axis]))
						),
						deg_to_rad(1.0)
					)
					torque_scale = maxf(
						joint_definition.maximum_active_torque[axis],
						MINIMUM_SCALE
					)
				result.append(clampf(current[axis] / angle_scale, -1.0, 1.0))
				result.append(clampf(error[axis] / angle_scale, -1.0, 1.0))
				result.append(clampf(active_torque[axis] / torque_scale, -1.0, 1.0))
		if limb_definition.end_effector != null and limb_definition.end_effector.enabled:
			var runtime_effector: LimbEndEffector3D = (
				runtime_limb.end_effector if is_instance_valid(runtime_limb) else null
			)
			_append_live_effector(
				result,
				limb_definition.end_effector,
				runtime_effector,
				host_transform.origin,
				host_inverse_basis
			)
	var expected: int = observation_count(definitions)
	# MLBodyPartContract/MLBodyInterfaceManifest own numeric/range validation at the common body
	# boundary. Re-scanning every articulated channel here doubled that work for each limb slot.
	return result if result.size() == expected else PackedFloat64Array()


static func runtime_state_for_limb(
	limb: GenericLimb3D,
	host_body: RigidBody3D
) -> Dictionary:
	if not is_instance_valid(limb) or limb.definition == null:
		return {}
	var limb_state: Dictionary = GenericLimbStateSnapshot.limb_state(limb)
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
		"limbs": [limb_state],
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


static func _append_live_effector(
	result: PackedFloat64Array,
	definition: LimbEndEffectorDefinition,
	effector: LimbEndEffector3D,
	host_origin: Vector3,
	host_inverse_basis: Basis
) -> void:
	var position: Vector3 = (
		effector.global_position if is_instance_valid(effector) else host_origin
	)
	var grip: GenericGrip3D = (
		effector.grip_actuator
		if is_instance_valid(effector) and is_instance_valid(effector.grip_actuator)
		else null
	)
	var activation: float = grip.activation if is_instance_valid(grip) else 0.0
	result.append(_unit_to_signed(activation))
	var candidate_present: bool = is_instance_valid(grip) and grip.candidate_present
	result.append(1.0 if candidate_present else -1.0)
	if candidate_present:
		var candidate_offset: Vector3 = host_inverse_basis * (grip.candidate_point_world - position)
		_append_vector(
			result,
			candidate_offset.normalized()
			if candidate_offset.length_squared() > MINIMUM_SCALE
			else Vector3.ZERO
		)
		result.append(_unsigned_to_signed(
			grip.candidate_distance,
			maxf(definition.grip_detection_radius, 0.01)
		))
	else:
		_append_vector(result, Vector3.ZERO)
		result.append(0.0)
	var attached: bool = is_instance_valid(grip) and grip.attached
	result.append(1.0 if attached else -1.0)
	if attached:
		var attached_offset: Vector3 = host_inverse_basis * (grip.attached_point_world() - position)
		_append_vector(
			result,
			attached_offset.normalized()
			if attached_offset.length_squared() > MINIMUM_SCALE
			else Vector3.ZERO
		)
		result.append(clampf(grip.load_ratio, 0.0, 2.0) - 1.0)
	else:
		_append_vector(result, Vector3.ZERO)
		result.append(0.0)
	result.append(_unit_to_signed(
		effector.health_ratio() if is_instance_valid(effector) else 0.0
	))


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
