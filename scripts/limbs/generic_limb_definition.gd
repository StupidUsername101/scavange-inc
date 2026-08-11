@tool
class_name GenericLimbDefinition
extends Resource

#######################################################
# Generic modular limb definition. A limb may contain one or any larger number of segments.
#######################################################

@export var limb_name := "Limb"
@export var installed := true
@export var mount_offset_local := Vector3.ZERO
@export var mount_basis_local: Basis = Basis.IDENTITY
@export var segments: Array[LimbSegmentDefinition] = []
@export var end_effector: LimbEndEffectorDefinition


func sanitize() -> void:
	# Sanitization may clamp authored data, but it must never invent body parts. Missing segments,
	# joints, or end-effectors remain missing so the creator/accepted-body validator can reject an
	# incomplete build instead of silently growing hardcoded anatomy.
	for segment: LimbSegmentDefinition in segments:
		if segment != null:
			segment.sanitize()
	if end_effector != null:
		end_effector.sanitize()


func ml_validation_error() -> String:
	if not installed:
		return ""
	if not mount_offset_local.is_finite():
		return "Limb mount offset must be finite."
	if (
		not mount_basis_local.x.is_finite()
		or not mount_basis_local.y.is_finite()
		or not mount_basis_local.z.is_finite()
		or absf(mount_basis_local.determinant()) <= 0.000001
	):
		return "Limb mount orientation must be a finite, non-degenerate basis."
	if segments.is_empty():
		return "An installed limb requires at least one saved segment definition."
	for segment_index: int in range(segments.size()):
		var segment: LimbSegmentDefinition = segments[segment_index]
		if segment == null:
			return "Limb segment %d is missing its saved part definition." % segment_index
		if segment.joint == null:
			return "Limb segment %d is missing its saved joint definition." % segment_index
	return ""


func segment_count() -> int:
	return segments.size() if installed else 0


func required_action_count() -> int:
	var result := 0
	for segment: LimbSegmentDefinition in segments:
		if segment != null and segment.joint != null:
			result = maxi(result, segment.joint.required_action_count())
	if end_effector != null:
		result = maxi(result, end_effector.required_action_count())
	return result


func has_unique_action_mapping() -> bool:
	var seen: Dictionary[int, bool] = {}
	for segment: LimbSegmentDefinition in segments:
		if segment == null or segment.joint == null:
			continue
		for axis in range(3):
			var action_index := segment.joint.action_indices[axis]
			if action_index < 0:
				continue
			if seen.has(action_index):
				return false
			seen[action_index] = true
	if end_effector != null and end_effector.has_mapped_grip_action():
		if seen.has(end_effector.grip_action_index):
			return false
		seen[end_effector.grip_action_index] = true
	return true


func pack_action_indices(start_index: int = 0) -> int:
	# Convenience for editor/loadout-built bodies. Existing fixed ML profiles keep their explicit
	# mappings; generic assemblies can opt into deterministic dense packing without knowing how many
	# joints or terminal actuators each limb definition contains.
	var cursor := maxi(start_index, 0)
	for segment: LimbSegmentDefinition in segments:
		if segment == null or segment.joint == null:
			continue
		for axis in range(3):
			if segment.joint.axis_control_declared(axis):
				segment.joint.action_indices[axis] = cursor
				cursor += 1
			else:
				segment.joint.action_indices[axis] = -1
	if end_effector != null and end_effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED:
		end_effector.grip_action_index = cursor
		cursor += 1
	return cursor


func maximum_reach() -> float:
	var result := 0.0
	for segment: LimbSegmentDefinition in segments:
		if segment != null:
			result += maxf(segment.length, 0.0)
	if end_effector != null:
		result += end_effector.maximum_extent_from_distal_tip()
	return result


func rest_endpoint_local() -> Vector3:
	var safe_mount_basis: Basis = mount_basis_local.orthonormalized()
	var point: Vector3 = mount_offset_local
	var distal_basis: Basis = safe_mount_basis
	for segment: LimbSegmentDefinition in segments:
		if segment != null:
			var direction: Vector3 = (safe_mount_basis * segment.rest_direction_local).normalized()
			point += direction * segment.length
			distal_basis = GeometryBasis.from_y(direction)
	if end_effector != null and end_effector.is_physically_present():
		point += distal_basis * end_effector.nominal_contact_offset_parent_local()
	return point


func ml_part_tags() -> Array[StringName]:
	return [&"limb"]


func ml_control_descriptors() -> Array[Dictionary]:
	var source: Array[GenericLimbDefinition] = [self]
	return GenericLimbModelContract.control_descriptors(source)


func ml_observation_descriptors() -> Array[Dictionary]:
	var source: Array[GenericLimbDefinition] = [self]
	return GenericLimbModelContract.observation_descriptors(source)


func ml_encode_observation(runtime_state: Variant, host_state: Dictionary = {}) -> PackedFloat64Array:
	var source: Array[GenericLimbDefinition] = [self]
	return GenericLimbModelContract.encode(source, runtime_state, host_state)
