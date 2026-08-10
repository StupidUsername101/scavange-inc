@tool
class_name DroneLimbAttachmentDefinition
extends DroneAttachmentDefinition

#######################################################
# Serialized bridge from drone loadouts to the generic model-forge limb stack. ServerDrone builds
# these definitions with GenericLimbAssembly3D, so a drone can host the same articulated limbs,
# feet, tools, and grips as a creature body. The common body manifest derives every declared joint
# and end-effector channel directly from these definitions; there is no drone-specific arm contract.
#######################################################

@export_group("Generic Limbs")
@export var limb_definitions: Array[GenericLimbDefinition] = []
@export var mount_at_attachment_slot := true
@export var auto_pack_action_indices := true
@export_flags_3d_physics var limb_collision_layer := 4
@export_flags_3d_physics var limb_collision_mask := 1
@export var exclude_self_collision := true
# Creator limbs can opt into a gravity-aware neutral stance. The stored slot transform still owns
# placement; this only derives a useful bent rest pose from that mount at runtime. Legacy/gameplay
# manipulators keep their authored segment directions by leaving this disabled.
@export var mount_adaptive_neutral_pose: bool = false


func _init() -> void:
	if &"limb_host" not in capability_tags:
		capability_tags.append(&"limb_host")
	if &"manipulator" not in capability_tags:
		capability_tags.append(&"manipulator")


func ml_validation_error() -> String:
	if limb_definitions.is_empty():
		return "A limb attachment requires at least one saved GenericLimbDefinition."
	for limb_index: int in range(limb_definitions.size()):
		var limb: GenericLimbDefinition = limb_definitions[limb_index]
		if limb == null:
			return "Limb attachment entry %d is missing its saved limb definition." % limb_index
		var limb_error: String = limb.ml_validation_error()
		if not limb_error.is_empty():
			return "Limb attachment entry %d is invalid: %s" % [limb_index, limb_error]
	return ""


func required_limb_action_count() -> int:
	var mounted := mounted_limb_definitions(Vector3.ZERO)
	var result := 0
	for definition: GenericLimbDefinition in mounted:
		result = maxi(result, definition.required_action_count())
	return result


func mounted_limb_definitions(slot_mount_local: Variant) -> Array[GenericLimbDefinition]:
	var slot_transform: Transform3D = Transform3D.IDENTITY
	if slot_mount_local is Transform3D:
		slot_transform = slot_mount_local as Transform3D
	elif slot_mount_local is Vector3:
		slot_transform.origin = slot_mount_local as Vector3
	var result: Array[GenericLimbDefinition] = []
	for source: GenericLimbDefinition in limb_definitions:
		if source == null:
			continue
		var mounted: GenericLimbDefinition = MLBodyPartContract.deep_duplicate_resource(source) as GenericLimbDefinition
		if mounted == null:
			continue
		if mount_at_attachment_slot:
			mounted.mount_offset_local = (
				slot_transform.origin
				+ slot_transform.basis * mounted.mount_offset_local
			)
			mounted.mount_basis_local = (
				slot_transform.basis * mounted.mount_basis_local
			).orthonormalized()
		if mount_adaptive_neutral_pose and slot_mount_local is Transform3D:
			_apply_mount_adaptive_neutral_pose(mounted, slot_transform)
		mounted.sanitize()
		result.append(mounted)
	if auto_pack_action_indices:
		var action_cursor := 0
		for packed_definition: GenericLimbDefinition in result:
			action_cursor = packed_definition.pack_action_indices(action_cursor)
	return result


func _apply_mount_adaptive_neutral_pose(
	limb: GenericLimbDefinition,
	slot_transform: Transform3D
) -> void:
	if limb == null or limb.segments.is_empty():
		return
	# Creator attachment mounts encode their outward surface normal as local -Y. Derive a
	# horizontal radial direction from it, then fall back to mount position/orientation for top or
	# bottom mounts where the surface normal itself has no horizontal component.
	var outward: Vector3 = (slot_transform.basis * Vector3.DOWN).normalized()
	var radial: Vector3 = Vector3(outward.x, 0.0, outward.z)
	if radial.length_squared() <= 0.000001:
		radial = Vector3(slot_transform.origin.x, 0.0, slot_transform.origin.z)
	if radial.length_squared() <= 0.000001:
		var tangent: Vector3 = slot_transform.basis.z
		radial = Vector3(tangent.x, 0.0, tangent.z)
	if radial.length_squared() <= 0.000001:
		radial = Vector3.FORWARD
	radial = radial.normalized()

	var mount_inverse: Basis = limb.mount_basis_local.transposed()
	var previous_direction: Vector3 = Vector3.ZERO
	var segment_count: int = limb.segments.size()
	for segment_index: int in range(segment_count):
		var segment: LimbSegmentDefinition = limb.segments[segment_index]
		if segment == null:
			continue
		var t: float = (
			float(segment_index) / float(segment_count - 1)
			if segment_count > 1
			else 0.5
		)
		# Match the useful neutral shape of the established walker: the proximal part reaches
		# strongly outward while descending, and later parts progressively turn toward gravity.
		var horizontal_weight: float = lerpf(0.85, 0.02, t)
		var down_weight: float = sqrt(maxf(1.0 - horizontal_weight * horizontal_weight, 0.0))
		var desired_direction: Vector3 = (
			radial * horizontal_weight + Vector3.DOWN * down_weight
		).normalized()
		segment.rest_direction_local = (mount_inverse * desired_direction).normalized()

		if segment.joint != null:
			var joint_basis_core: Basis = Basis.IDENTITY
			if segment_index == 0:
				var yaw_axis: Vector3 = Vector3.UP
				var pitch_axis: Vector3 = radial.cross(yaw_axis).normalized()
				if pitch_axis.length_squared() <= 0.000001:
					pitch_axis = Vector3.RIGHT
				var locked_axis: Vector3 = pitch_axis.cross(yaw_axis).normalized()
				joint_basis_core = Basis(yaw_axis, locked_axis, pitch_axis).orthonormalized()
			else:
				var hinge_axis: Vector3 = previous_direction.cross(desired_direction).normalized()
				if hinge_axis.length_squared() <= 0.000001:
					hinge_axis = radial.cross(Vector3.DOWN).normalized()
				if hinge_axis.length_squared() <= 0.000001:
					hinge_axis = Vector3.FORWARD
				var x_axis: Vector3 = desired_direction.normalized()
				var y_axis: Vector3 = hinge_axis.cross(x_axis).normalized()
				if y_axis.length_squared() <= 0.000001:
					y_axis = Vector3.UP
				joint_basis_core = Basis(x_axis, y_axis, hinge_axis).orthonormalized()
			segment.joint.joint_basis_local = (
				mount_inverse * joint_basis_core
			).orthonormalized()
		previous_direction = desired_direction


func ml_control_descriptors() -> Array[Dictionary]:
	var mounted: Array[GenericLimbDefinition] = mounted_limb_definitions(Vector3.ZERO)
	return GenericLimbModelContract.control_descriptors(mounted)


func ml_observation_descriptors() -> Array[Dictionary]:
	var mounted: Array[GenericLimbDefinition] = mounted_limb_definitions(Vector3.ZERO)
	return GenericLimbModelContract.observation_descriptors(mounted)


func ml_encode_observation(runtime_state: Variant, host_state: Dictionary = {}) -> PackedFloat64Array:
	# Encoding depends on segment/joint/end-effector topology and physical scales, not on the mount
	# transform or dense action offsets. Do not deep-duplicate the complete limb resource tree on
	# every policy decision just to recreate an equivalent observation definition.
	return GenericLimbModelContract.encode(limb_definitions, runtime_state, host_state)


func ml_contract_dictionary() -> Dictionary:
	var result: Dictionary = super.ml_contract_dictionary()
	var limbs: Array[Dictionary] = []
	for definition: GenericLimbDefinition in mounted_limb_definitions(Vector3.ZERO):
		if definition == null:
			continue
		limbs.append({
			"limb_name": definition.limb_name,
			"mount_offset_local": [
				definition.mount_offset_local.x,
				definition.mount_offset_local.y,
				definition.mount_offset_local.z,
			],
			"segment_count": definition.segments.size(),
			"control_count": definition.ml_control_descriptors().size(),
			"observation_count": definition.ml_observation_descriptors().size(),
		})
	result["limbs"] = limbs
	result["auto_pack_action_indices"] = auto_pack_action_indices
	result["mount_adaptive_neutral_pose"] = mount_adaptive_neutral_pose
	return result
