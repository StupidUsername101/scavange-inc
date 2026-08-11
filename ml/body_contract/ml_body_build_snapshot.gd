class_name MLBodyBuildSnapshot
extends RefCounted

#######################################################
# JSON-safe persistence for the future body-creator draft. The neural manifest remains a separate
# accepted/frozen contract: this snapshot stores editable physical Core/slots/parts only, so a body
# can be reopened and changed without pretending an old model automatically matches the revision.
#######################################################

const SCHEMA_VERSION: int = 1


static func encode_draft(draft: MLBodyBuildDraft) -> Dictionary:
	if draft == null or draft.core == null:
		return {}
	var core_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(draft.core)
	if core_snapshot.is_empty():
		return {}
	var slot_records: Array[Dictionary] = []
	for entry: Dictionary in draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			return {}
		var slot_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(slot)
		if slot_snapshot.is_empty():
			return {}
		var part: Resource = entry.get("part") as Resource
		var part_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(part)
		if part != null and part_snapshot.is_empty():
			return {}
		slot_records.append({
			"slot_id": str(slot.slot_id),
			"definition": slot_snapshot,
			"part": part_snapshot,
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"core": core_snapshot,
		"core_contract": draft.core_contract.duplicate(true),
		"slots": slot_records,
	}


static func decode_draft(snapshot: Dictionary) -> MLBodyBuildDraft:
	if (
		snapshot.is_empty()
		or SafeVariant.integral_int_or(snapshot.get("schema_version", -1), -1) != SCHEMA_VERSION
	):
		return null
	var core_value: Variant = snapshot.get("core", {})
	var slots_value: Variant = snapshot.get("slots", [])
	var contract_value: Variant = snapshot.get("core_contract", {})
	if not (core_value is Dictionary) or not (slots_value is Array) or not (contract_value is Dictionary):
		return null
	var decoded_core: Resource = MLBodyResourceSnapshot.decode_resource(core_value as Dictionary)
	if decoded_core == null:
		return null
	var result = MLBodyBuildDraft.new()
	var body_kind: String = str((contract_value as Dictionary).get("body_kind", "generic"))
	if decoded_core is MLBodyCoreDefinition:
		if not result.configure_from_core(decoded_core as MLBodyCoreDefinition, body_kind):
			return null
	else:
		if not result.set_core(decoded_core, contract_value as Dictionary):
			return null
	var slot_records: Array = slots_value
	if decoded_core is MLBodyCoreDefinition and slot_records.size() != result.slots.size():
		return null
	for index in range(slot_records.size()):
		var record_value: Variant = slot_records[index]
		if not (record_value is Dictionary):
			return null
		var record: Dictionary = record_value
		var slot_id_value: Variant = record.get("slot_id", "")
		if not (slot_id_value is String):
			return null
		var slot_id: StringName = StringName(slot_id_value)
		var definition_value: Variant = record.get("definition", {})
		var part_value: Variant = record.get("part", {})
		if str(slot_id).is_empty() or not (definition_value is Dictionary) or not (part_value is Dictionary):
			return null
		var decoded_slot: MLBodySlotDefinition = (
			MLBodyResourceSnapshot.decode_resource(definition_value as Dictionary) as MLBodySlotDefinition
		)
		if decoded_slot == null or decoded_slot.slot_id != slot_id:
			return null
		var target_slot: MLBodySlotDefinition = null
		if decoded_core is MLBodyCoreDefinition:
			target_slot = result.slot_definition(slot_id)
			if target_slot == null or target_slot.contract_dictionary() != decoded_slot.contract_dictionary():
				return null
		else:
			if not result.add_slot(decoded_slot):
				return null
			target_slot = decoded_slot
		var decoded_part: Resource = null
		if not (part_value as Dictionary).is_empty():
			decoded_part = MLBodyResourceSnapshot.decode_resource(part_value as Dictionary)
			if decoded_part == null:
				return null
		if decoded_part != null and (target_slot == null or not result.equip(slot_id, decoded_part)):
			return null
	# Preserve creator/preset metadata exactly, but recompute model_core at Accept so stale preview data
	# can never override the physical Core/slot snapshot that was actually restored.
	result.core_contract = (contract_value as Dictionary).duplicate(true)
	result.core_contract["body_kind"] = body_kind
	result.core_contract.erase("model_core")
	return result
