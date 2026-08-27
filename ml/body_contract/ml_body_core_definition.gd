@tool
class_name MLBodyCoreDefinition
extends Resource

#######################################################
# Generic body-creator Core. It owns the authoritative ordered slot list and may wrap the physical
# gameplay Core resource used by an existing body family. The wrapper lets creator drafts add or
# remove slots without teaching the neural-interface builder about drones, walkers, or turrets.
#######################################################

@export var core_id: StringName = &"core"
@export var display_name: String = "Core"
@export var physical_core: Resource
@export var attachment_slots: Array[MLBodySlotDefinition] = []


func add_slot(slot: MLBodySlotDefinition) -> bool:
	if slot == null or slot_index(slot.slot_id) >= 0:
		return false
	attachment_slots.append(slot)
	return true


func remove_slot(slot_id: StringName) -> bool:
	var index: int = slot_index(slot_id)
	if index < 0:
		return false
	attachment_slots.remove_at(index)
	return true


func slot_index(slot_id: StringName) -> int:
	for index in range(attachment_slots.size()):
		var slot: MLBodySlotDefinition = attachment_slots[index]
		if slot != null and slot.slot_id == slot_id:
			return index
	return -1


func ml_part_tags() -> Array[StringName]:
	# Wrapping an existing physical Core must not change its neural contract signature. Core
	# ownership is already represented by the manifest's `core.` prefix; tags describe capability.
	if physical_core is MLBodyCoreDefinition:
		return [&"core"]
	var result: Array[StringName] = MLBodyPartContract.part_tags(physical_core)
	if result.is_empty():
		result.append(&"core")
	return result


func ml_validation_error() -> String:
	if physical_core is MLBodyCoreDefinition:
		return "A model Core cannot wrap another model Core wrapper as physical hardware."
	return ""


func ml_control_descriptors() -> Array[Dictionary]:
	if physical_core is MLBodyCoreDefinition:
		return []
	return MLBodyPartContract.control_descriptors(physical_core)


func ml_observation_descriptors() -> Array[Dictionary]:
	if physical_core is MLBodyCoreDefinition:
		return []
	return MLBodyPartContract.observation_descriptors(physical_core)


func ml_encode_observation(runtime_state: Variant, host_state: Dictionary = {}) -> PackedFloat64Array:
	if physical_core is MLBodyCoreDefinition:
		return PackedFloat64Array()
	return MLBodyPartContract.encode_observation(physical_core, runtime_state, host_state)


func ml_contract_dictionary() -> Dictionary:
	return contract_dictionary()


func contract_dictionary() -> Dictionary:
	var slots: Array[Dictionary] = []
	for slot: MLBodySlotDefinition in attachment_slots:
		if slot != null:
			slots.append(slot.contract_dictionary())
	return {
		"core_id": str(core_id),
		"display_name": display_name,
		"physical_core": (
			{}
			if physical_core is MLBodyCoreDefinition
			else MLBodyPartContract.contract_fragment(physical_core)
		),
		"slots": slots,
	}
