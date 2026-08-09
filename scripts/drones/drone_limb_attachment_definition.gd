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


func mounted_limb_definitions(slot_offset_local: Vector3) -> Array[GenericLimbDefinition]:
	var result: Array[GenericLimbDefinition] = []
	for source: GenericLimbDefinition in limb_definitions:
		if source == null:
			continue
		var mounted: GenericLimbDefinition = MLBodyPartContract.deep_duplicate_resource(source) as GenericLimbDefinition
		if mounted == null:
			continue
		if mount_at_attachment_slot:
			mounted.mount_offset_local += slot_offset_local
		mounted.sanitize()
		result.append(mounted)
	if auto_pack_action_indices:
		var action_cursor := 0
		for packed_definition: GenericLimbDefinition in result:
			action_cursor = packed_definition.pack_action_indices(action_cursor)
	return result


func ml_control_descriptors() -> Array[Dictionary]:
	var mounted: Array[GenericLimbDefinition] = mounted_limb_definitions(Vector3.ZERO)
	return GenericLimbModelContract.control_descriptors(mounted)


func ml_observation_descriptors() -> Array[Dictionary]:
	var mounted: Array[GenericLimbDefinition] = mounted_limb_definitions(Vector3.ZERO)
	return GenericLimbModelContract.observation_descriptors(mounted)


func ml_encode_observation(runtime_state: Variant, host_state: Dictionary = {}) -> PackedFloat64Array:
	var mounted: Array[GenericLimbDefinition] = mounted_limb_definitions(Vector3.ZERO)
	return GenericLimbModelContract.encode(mounted, runtime_state, host_state)


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
	return result
