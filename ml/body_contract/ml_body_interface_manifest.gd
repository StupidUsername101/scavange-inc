class_name MLBodyInterfaceManifest
extends RefCounted

const SCHEMA_VERSION: int = 2

#######################################################
# Immutable-at-runtime contract produced only when a body build is accepted. It owns the exact
# ordered body observation/control topology used to size a policy. Editing a draft never mutates
# this object, which prevents a future body-creator UI from changing tensor shapes while a model is
# being trained or evaluated.
#######################################################

var core_contract: Dictionary = {}
var core_record: Dictionary = {}
var slot_records: Array[Dictionary] = []
var control_descriptors: Array[Dictionary] = []
var observation_descriptors: Array[Dictionary] = []
var contract_signature: String = ""
var finalized: bool = false


func control_count() -> int:
	return control_descriptors.size()


func observation_count() -> int:
	return observation_descriptors.size()


func control_names() -> Array[String]:
	var result: Array[String] = []
	for descriptor: Dictionary in control_descriptors:
		result.append(str(descriptor.get("name", "control_%d" % result.size())))
	return result


func observation_names() -> Array[String]:
	var result: Array[String] = []
	for descriptor: Dictionary in observation_descriptors:
		result.append(str(descriptor.get("name", "body_%d" % result.size())))
	return result


func encode_body_observation(
	runtime_states_by_slot: Dictionary,
	host_state: Dictionary = {}
) -> PackedFloat64Array:
	if not finalized:
		return PackedFloat64Array()
	var total_observation_count: int = observation_count()
	var result: PackedFloat64Array = PackedFloat64Array()
	result.resize(total_observation_count)
	var written_observation_count: int = 0
	var core_observation_count: int = int(core_record.get("observation_count", 0))
	if core_observation_count > 0:
		var core_part: Resource = core_record.get("part") as Resource
		var core_runtime_state: Variant = runtime_states_by_slot.get("core", host_state)
		var core_encoded: PackedFloat64Array = MLBodyPartContract.encode_observation(
			core_part,
			core_runtime_state,
			host_state
		)
		if core_encoded.size() != core_observation_count:
			return PackedFloat64Array()
		if not _write_validated_observations(result, core_encoded, core_record):
			return PackedFloat64Array()
		written_observation_count += core_encoded.size()
	for record: Dictionary in slot_records:
		var observation_count_for_part: int = int(record.get("observation_count", 0))
		if observation_count_for_part <= 0:
			continue
		var part: Resource = record.get("part") as Resource
		var slot_id: String = str(record.get("slot_id", ""))
		var runtime_state: Variant = runtime_states_by_slot.get(slot_id, {})
		var encoded: PackedFloat64Array = MLBodyPartContract.encode_observation(
			part,
			runtime_state,
			host_state
		)
		if encoded.size() != observation_count_for_part:
			return PackedFloat64Array()
		if not _write_validated_observations(result, encoded, record):
			return PackedFloat64Array()
		written_observation_count += encoded.size()
	return (
		result
		if written_observation_count == total_observation_count
		else PackedFloat64Array()
	)


func route_controls(commands: PackedFloat64Array) -> Dictionary:
	if not finalized or commands.size() != control_count():
		return {}
	var result: Dictionary = {}
	var core_control_count: int = int(core_record.get("control_count", 0))
	if core_control_count > 0:
		var core_offset: int = int(core_record.get("control_offset", -1))
		if core_offset < 0 or core_offset + core_control_count > commands.size():
			return {}
		var core_commands = PackedFloat64Array()
		core_commands.resize(core_control_count)
		for local_index in range(core_control_count):
			core_commands[local_index] = commands[core_offset + local_index]
		result["core"] = core_commands
	for record: Dictionary in slot_records:
		var count: int = int(record.get("control_count", 0))
		if count <= 0:
			continue
		var offset: int = int(record.get("control_offset", -1))
		if offset < 0 or offset + count > commands.size():
			return {}
		var local = PackedFloat64Array()
		local.resize(count)
		for local_index in range(count):
			local[local_index] = commands[offset + local_index]
		result[str(record.get("slot_id", ""))] = local
	return result




func editable_revision() -> MLBodyBuildDraft:
	# UI handoff after Accept: reconstruct a fully isolated draft from the frozen physical build.
	# The accepted manifest stays immutable and keeps sizing the running model while the creator edits
	# this revision. A changed revision only becomes authoritative after its own Accept.
	if not finalized:
		return null
	var frozen_core: Resource = core_record.get("part") as Resource
	if frozen_core == null:
		return null
	var copied_core: Resource = MLBodyPartContract.deep_duplicate_resource(frozen_core)
	if copied_core == null:
		return null
	# The creator always edits the same generic Core+slots representation, even when this manifest
	# came from a legacy/runtime adapter whose physical Core was stored directly. That keeps the next
	# UI independent of worker family and prevents reopening a runtime body from falling back to a
	# special-case drone/turret/walker edit path.
	var creator_core: MLBodyCoreDefinition = null
	if copied_core is MLBodyCoreDefinition:
		creator_core = copied_core as MLBodyCoreDefinition
	else:
		creator_core = MLBodyCoreDefinition.new()
		creator_core.core_id = &"core"
		creator_core.display_name = str(core_contract.get("core_display_name", "Core"))
		creator_core.physical_core = copied_core
		for record: Dictionary in slot_records:
			var frozen_slot: MLBodySlotDefinition = record.get("slot_definition") as MLBodySlotDefinition
			var copied_slot: MLBodySlotDefinition = (
				MLBodyPartContract.deep_duplicate_resource(frozen_slot) as MLBodySlotDefinition
			)
			if copied_slot == null or not creator_core.add_slot(copied_slot):
				return null
	var result = MLBodyBuildDraft.new()
	var body_kind: String = str(core_contract.get("body_kind", "generic"))
	if not result.configure_from_core(creator_core, body_kind):
		return null
	result.core_contract = core_contract.duplicate(true)
	for record: Dictionary in slot_records:
		var slot_id: StringName = StringName(str(record.get("slot_id", "")))
		var part: Resource = record.get("part") as Resource
		var copied_part: Resource = MLBodyPartContract.deep_duplicate_resource(part)
		if part != null and copied_part == null:
			return null
		if copied_part != null and not result.equip(slot_id, copied_part):
			return null
	return result


func frozen_core_copy() -> Resource:
	return MLBodyPartContract.deep_duplicate_resource(core_record.get("part") as Resource)


func frozen_slot_copy(slot_id: StringName) -> MLBodySlotDefinition:
	for record: Dictionary in slot_records:
		if StringName(str(record.get("slot_id", ""))) != slot_id:
			continue
		var copied_slot: MLBodySlotDefinition = (
			MLBodyPartContract.deep_duplicate_resource(record.get("slot_definition") as Resource)
			as MLBodySlotDefinition
		)
		return copied_slot
	return null


func frozen_part_copy(slot_id: StringName) -> Resource:
	for record: Dictionary in slot_records:
		if StringName(str(record.get("slot_id", ""))) == slot_id:
			return MLBodyPartContract.deep_duplicate_resource(record.get("part") as Resource)
	return null


func is_compatible_with(other: MLBodyInterfaceManifest) -> bool:
	return (
		other != null
		and finalized
		and other.finalized
		and contract_signature == other.contract_signature
	)


func to_dictionary() -> Dictionary:
	var serialized_core_record: Dictionary = core_record.duplicate(true)
	serialized_core_record.erase("part")
	var serialized_slots: Array[Dictionary] = []
	for source: Dictionary in slot_records:
		var record: Dictionary = source.duplicate(true)
		record.erase("part")
		record.erase("slot_definition")
		serialized_slots.append(record)
	return {
		"schema_version": SCHEMA_VERSION,
		"core": core_contract.duplicate(true),
		"core_record": serialized_core_record,
		"slots": serialized_slots,
		"controls": control_descriptors.duplicate(true),
		"observations": observation_descriptors.duplicate(true),
		"control_count": control_count(),
		"observation_count": observation_count(),
		"contract_signature": contract_signature,
	}


func _write_validated_observations(
	target: PackedFloat64Array,
	encoded: PackedFloat64Array,
	record: Dictionary
) -> bool:
	var observation_offset: int = int(record.get("observation_offset", -1))
	if observation_offset < 0 or observation_offset + encoded.size() > observation_descriptors.size():
		return false
	for local_index in range(encoded.size()):
		var descriptor: Dictionary = observation_descriptors[observation_offset + local_index]
		var minimum: float = float(descriptor.get("minimum", -1.0))
		var maximum: float = float(descriptor.get("maximum", 1.0))
		var value: float = encoded[local_index]
		if not is_finite(value) or value < minimum - 0.000001 or value > maximum + 0.000001:
			return false
		target[observation_offset + local_index] = value
	return true
