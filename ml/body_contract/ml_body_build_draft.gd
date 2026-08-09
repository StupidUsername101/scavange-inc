class_name MLBodyBuildDraft
extends RefCounted

#######################################################
# Mutable model-forge build. The future body-creator UI should edit this object and call
# accept_build() only when the user accepts the build. No neural-network dimensions are finalized
# before that explicit transition.
#######################################################

var core: Resource
var core_contract: Dictionary = {}
var slots: Array[Dictionary] = []
var accepted: bool = false
var last_error: String = ""


func set_core(value: Resource, contract: Dictionary = {}) -> bool:
	if accepted:
		return _fail("Accepted body builds are immutable; create a new draft before editing.")
	if value == null:
		return _fail("A model body requires a Core.")
	core = value
	core_contract = contract.duplicate(true)
	# A different Core owns a different slot topology. Never let editor code replace the Core while
	# silently carrying slot entries from the previous body. Generic Core callers should then add or
	# configure the new Core's slots explicitly.
	slots.clear()
	last_error = ""
	return true


func configure_from_core(core_definition: MLBodyCoreDefinition, body_kind: String = "generic") -> bool:
	if accepted:
		return _fail("Accepted body builds are immutable; create a new draft before editing.")
	if core_definition == null:
		return _fail("A model body requires a Core.")
	core = core_definition
	core_contract = {
		"body_kind": body_kind.strip_edges(),
		"model_core": core_definition.contract_dictionary(),
	}
	slots.clear()
	for slot: MLBodySlotDefinition in core_definition.attachment_slots:
		if slot == null or not add_slot(slot, null):
			return false
	last_error = ""
	return true


func add_slot(slot: MLBodySlotDefinition, part: Resource = null) -> bool:
	if accepted:
		return _fail("Accepted body builds are immutable; create a new draft before editing.")
	if slot == null or str(slot.slot_id).strip_edges().is_empty():
		return _fail("Body slots need a stable non-empty slot id.")
	if _slot_index(slot.slot_id) >= 0:
		return _fail("Duplicate body slot id: %s" % str(slot.slot_id))
	if part != null and not slot.accepts(part):
		return _fail("Part is incompatible with slot %s." % str(slot.slot_id))
	if core is MLBodyCoreDefinition:
		var model_core: MLBodyCoreDefinition = core as MLBodyCoreDefinition
		var core_slot_index: int = model_core.slot_index(slot.slot_id)
		if core_slot_index < 0:
			if not model_core.add_slot(slot):
				return _fail("The Core rejected slot %s." % str(slot.slot_id))
		elif model_core.attachment_slots[core_slot_index] != slot:
			return _fail("The Core already owns a different slot named %s." % str(slot.slot_id))
	slots.append({"definition": slot, "part": part})
	last_error = ""
	return true


func remove_slot(slot_id: StringName) -> bool:
	if accepted:
		return _fail("Accepted body builds are immutable; create a new draft before editing.")
	var index: int = _slot_index(slot_id)
	if index < 0:
		return _fail("Unknown body slot: %s" % str(slot_id))
	if core is MLBodyCoreDefinition:
		var model_core: MLBodyCoreDefinition = core as MLBodyCoreDefinition
		if not model_core.remove_slot(slot_id):
			return _fail("The Core could not remove slot %s." % str(slot_id))
	slots.remove_at(index)
	last_error = ""
	return true


func equip(slot_id: StringName, part: Resource) -> bool:
	if accepted:
		return _fail("Accepted body builds are immutable; create a new draft before editing.")
	var index: int = _slot_index(slot_id)
	if index < 0:
		return _fail("Unknown body slot: %s" % str(slot_id))
	var slot: MLBodySlotDefinition = slots[index].get("definition") as MLBodySlotDefinition
	if part != null and (slot == null or not slot.accepts(part)):
		return _fail("Part is incompatible with slot %s." % str(slot_id))
	slots[index]["part"] = part
	last_error = ""
	return true


func unequip(slot_id: StringName) -> bool:
	return equip(slot_id, null)


func slot_definition(slot_id: StringName) -> MLBodySlotDefinition:
	var index: int = _slot_index(slot_id)
	return slots[index].get("definition") as MLBodySlotDefinition if index >= 0 else null


func equipped_part(slot_id: StringName) -> Resource:
	var index: int = _slot_index(slot_id)
	return slots[index].get("part") as Resource if index >= 0 else null


func ui_snapshot() -> Dictionary:
	# Read-only creator data. This may preview channel counts, but it deliberately does not assign
	# global indices, freeze Resources, mutate the draft, or allocate a model.
	var slot_records: Array[Dictionary] = []
	var preview_control_count: int = MLBodyPartContract.control_descriptors(core).size()
	var preview_observation_count: int = MLBodyPartContract.observation_descriptors(core).size()
	for entry: Dictionary in slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			continue
		var part: Resource = entry.get("part") as Resource
		var controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(part)
		var observations: Array[Dictionary] = MLBodyPartContract.observation_descriptors(part)
		preview_control_count += controls.size()
		preview_observation_count += observations.size()
		var tags: Array[String] = []
		for tag: StringName in MLBodyPartContract.part_tags(part):
			tags.append(str(tag))
		slot_records.append({
			"slot_id": str(slot.slot_id),
			"display_name": slot.display_name,
			"slot_type": str(slot.slot_type),
			"accepted_part_tags": slot.contract_dictionary().get("accepted_part_tags", []),
			"mount_transform": slot.mount_transform,
			"equipped": part != null,
			"part_class": part.get_class() if part != null else "",
			"part_resource_path": MLBodyPartContract.resource_source_path(part),
			"part_tags": tags,
			"control_count": controls.size(),
			"observation_count": observations.size(),
		})
	var core_name: String = core.get_class() if core != null else ""
	if core is MLBodyCoreDefinition:
		core_name = (core as MLBodyCoreDefinition).display_name
	return {
		"body_kind": str(core_contract.get("body_kind", "generic")),
		"preset_id": str(core_contract.get("preset_id", "")),
		"accepted": accepted,
		"core_name": core_name,
		"slot_count": slots.size(),
		"preview_control_count": preview_control_count,
		"preview_observation_count": preview_observation_count,
		"slots": slot_records,
	}


func accept_build() -> MLBodyInterfaceManifest:
	last_error = ""
	if accepted:
		return _fail_manifest("This body build was already accepted.")
	if core == null:
		return _fail_manifest("A model body cannot be finalized without a Core.")
	if not _validate_final_slot_topology():
		return null
	if core is MLBodyCoreDefinition:
		if not _generic_core_slots_match_draft(core as MLBodyCoreDefinition):
			return _fail_manifest(
				"The editable Core slot list changed outside this body draft; rebuild the draft before Accept."
			)
		core_contract["model_core"] = (core as MLBodyCoreDefinition).contract_dictionary()
	var manifest = MLBodyInterfaceManifest.new()
	manifest.core_contract = core_contract.duplicate(true)
	var control_cursor: int = 0
	var observation_cursor: int = 0

	# The Core is the physical root, not a synthetic attachment slot. If a Core owns actuators or
	# topology-dependent sensors, they participate in the same accepted contract before slot parts.
	var frozen_core: Resource = MLBodyPartContract.deep_duplicate_resource(core)
	if frozen_core == null:
		return _fail_manifest("The Core could not be frozen for the accepted body.")
	var core_validation_error: String = MLBodyPartContract.validation_error(frozen_core)
	if not core_validation_error.is_empty():
		return _fail_manifest("The Core is invalid: %s" % core_validation_error)
	var core_controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(frozen_core)
	var core_observations: Array[Dictionary] = MLBodyPartContract.observation_descriptors(frozen_core)
	if not _validate_local_descriptors(core_controls, true):
		return _fail_manifest("The Core declares an invalid control channel.")
	if not _validate_local_descriptors(core_observations, false):
		return _fail_manifest("The Core declares an invalid observation channel.")
	_append_global_descriptors(manifest.control_descriptors, core_controls, "core", control_cursor)
	_append_global_descriptors(
		manifest.observation_descriptors,
		core_observations,
		"core",
		observation_cursor
	)
	manifest.core_record = {
		"part": frozen_core,
		"part_contract": MLBodyPartContract.contract_fragment(frozen_core),
		"control_offset": control_cursor,
		"control_count": core_controls.size(),
		"observation_offset": observation_cursor,
		"observation_count": core_observations.size(),
	}
	var signature_core: Dictionary = {
		"part_tags": _part_tags_as_strings(frozen_core),
		"controls": core_controls.duplicate(true),
		"observations": core_observations.duplicate(true),
	}
	control_cursor += core_controls.size()
	observation_cursor += core_observations.size()

	var signature_slots: Array[Dictionary] = []
	for slot_entry: Dictionary in slots:
		var slot: MLBodySlotDefinition = slot_entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			return _fail_manifest("Body draft contains a missing slot definition.")
		var part: Resource = slot_entry.get("part") as Resource
		if part != null and not slot.accepts(part):
			return _fail_manifest("Part is incompatible with slot %s." % str(slot.slot_id))
		var frozen_slot: MLBodySlotDefinition = (
			MLBodyPartContract.deep_duplicate_resource(slot) as MLBodySlotDefinition
		)
		if frozen_slot == null:
			return _fail_manifest("Slot %s could not be frozen for the accepted body." % str(slot.slot_id))
		var frozen_part: Resource = null
		if part != null:
			frozen_part = MLBodyPartContract.deep_duplicate_resource(part)
			if frozen_part == null:
				return _fail_manifest("Part in slot %s could not be frozen for the accepted body." % str(slot.slot_id))
		var part_validation_error: String = MLBodyPartContract.validation_error(frozen_part)
		if not part_validation_error.is_empty():
			return _fail_manifest(
				"Part in slot %s is invalid: %s" % [str(slot.slot_id), part_validation_error]
			)
		var controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(frozen_part)
		var observations: Array[Dictionary] = MLBodyPartContract.observation_descriptors(frozen_part)
		if not _validate_local_descriptors(controls, true):
			return _fail_manifest("Part in slot %s declares an invalid control channel." % str(slot.slot_id))
		if not _validate_local_descriptors(observations, false):
			return _fail_manifest("Part in slot %s declares an invalid observation channel." % str(slot.slot_id))
		var slot_prefix: String = str(slot.slot_id)
		_append_global_descriptors(manifest.control_descriptors, controls, slot_prefix, control_cursor)
		_append_global_descriptors(
			manifest.observation_descriptors,
			observations,
			slot_prefix,
			observation_cursor
		)
		var record: Dictionary = {
			"slot_id": slot_prefix,
			"slot_type": str(frozen_slot.slot_type),
			"slot_contract": frozen_slot.contract_dictionary(),
			"slot_definition": frozen_slot,
			"part": frozen_part,
			"part_contract": MLBodyPartContract.contract_fragment(frozen_part),
			"control_offset": control_cursor,
			"control_count": controls.size(),
			"observation_offset": observation_cursor,
			"observation_count": observations.size(),
		}
		manifest.slot_records.append(record)
		# The signature describes the neural interface, not physical tuning. A different part with the
		# same declared capabilities can reuse a policy; a slot/control/observation topology change cannot.
		var signature_record: Dictionary = {
			"slot_id": slot_prefix,
			"slot_type": str(frozen_slot.slot_type),
			"part_tags": _part_tags_as_strings(frozen_part),
			"controls": controls.duplicate(true),
			"observations": observations.duplicate(true),
		}
		signature_slots.append(signature_record)
		control_cursor += controls.size()
		observation_cursor += observations.size()
	var signature_payload: Dictionary = {
		"schema_version": MLBodyInterfaceManifest.SCHEMA_VERSION,
		"body_kind": str(core_contract.get("body_kind", "")),
		"core": signature_core,
		"slots": signature_slots,
		"controls": manifest.control_descriptors,
		"observations": manifest.observation_descriptors,
	}
	manifest.contract_signature = JSON.stringify(signature_payload)
	manifest.finalized = true
	accepted = true
	return manifest


func duplicate_editable() -> MLBodyBuildDraft:
	var result = MLBodyBuildDraft.new()
	if core != null:
		result.core = MLBodyPartContract.deep_duplicate_resource(core)
	result.core_contract = core_contract.duplicate(true)
	for entry: Dictionary in slots:
		var source_slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		var source_part: Resource = entry.get("part") as Resource
		var copied_slot: MLBodySlotDefinition = null
		var copied_part: Resource = null
		if source_slot != null:
			if result.core is MLBodyCoreDefinition:
				var copied_core: MLBodyCoreDefinition = result.core as MLBodyCoreDefinition
				var copied_slot_index: int = copied_core.slot_index(source_slot.slot_id)
				if copied_slot_index >= 0:
					copied_slot = copied_core.attachment_slots[copied_slot_index]
			if copied_slot == null:
				copied_slot = MLBodyPartContract.deep_duplicate_resource(source_slot) as MLBodySlotDefinition
		if source_part != null:
			copied_part = MLBodyPartContract.deep_duplicate_resource(source_part)
		result.slots.append({"definition": copied_slot, "part": copied_part})
	return result


func _append_global_descriptors(
	target: Array[Dictionary],
	local_descriptors: Array[Dictionary],
	prefix: String,
	global_offset: int
) -> void:
	for local_index in range(local_descriptors.size()):
		var descriptor: Dictionary = local_descriptors[local_index].duplicate(true)
		var fallback_name: String = "channel_%d" % local_index
		var local_name: String = str(descriptor.get("name", fallback_name))
		descriptor["name"] = "%s.%s" % [prefix, local_name]
		descriptor["slot_id"] = prefix
		descriptor["local_index"] = local_index
		descriptor["index"] = global_offset + local_index
		target.append(descriptor)


func _validate_local_descriptors(descriptors: Array[Dictionary], controls: bool) -> bool:
	var names: Dictionary = {}
	for index in range(descriptors.size()):
		var descriptor: Dictionary = descriptors[index]
		var name: String = str(descriptor.get("name", "")).strip_edges()
		if name.is_empty():
			name = "control_%d" % index if controls else "feature_%d" % index
			descriptor["name"] = name
		if names.has(name):
			return false
		names[name] = true
		var minimum_value: Variant = descriptor.get("minimum", -1.0)
		var maximum_value: Variant = descriptor.get("maximum", 1.0)
		if not (minimum_value is int or minimum_value is float):
			return false
		if not (maximum_value is int or maximum_value is float):
			return false
		var minimum: float = float(minimum_value)
		var maximum: float = float(maximum_value)
		if not is_finite(minimum) or not is_finite(maximum) or maximum <= minimum:
			return false
		descriptor["minimum"] = minimum
		descriptor["maximum"] = maximum
		if controls:
			var neutral_value: Variant = descriptor.get("neutral", 0.0)
			if not (neutral_value is int or neutral_value is float) or not is_finite(float(neutral_value)):
				return false
			descriptor["neutral"] = clampf(float(neutral_value), minimum, maximum)
	return true


func _validate_final_slot_topology() -> bool:
	var seen_ids: Dictionary = {}
	for entry: Dictionary in slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			return _fail("Body draft contains a missing slot definition.")
		var clean_id: String = str(slot.slot_id).strip_edges()
		if clean_id.is_empty():
			return _fail("Body slots need a stable non-empty slot id before Accept.")
		if seen_ids.has(clean_id):
			return _fail("Duplicate body slot id after editing: %s" % clean_id)
		seen_ids[clean_id] = true
		var mount: Transform3D = slot.mount_transform
		if (
			not mount.origin.is_finite()
			or not mount.basis.x.is_finite()
			or not mount.basis.y.is_finite()
			or not mount.basis.z.is_finite()
		):
			return _fail("Body slot %s has a non-finite mount transform." % clean_id)
		var part: Resource = entry.get("part") as Resource
		if part != null and not slot.accepts(part):
			return _fail("Part is incompatible with slot %s." % clean_id)
	return true


func _generic_core_slots_match_draft(model_core: MLBodyCoreDefinition) -> bool:
	if model_core.attachment_slots.size() != slots.size():
		return false
	for index in range(slots.size()):
		var draft_slot: MLBodySlotDefinition = slots[index].get("definition") as MLBodySlotDefinition
		var core_slot: MLBodySlotDefinition = model_core.attachment_slots[index]
		if draft_slot == null or core_slot == null or draft_slot != core_slot:
			return false
	return true


func _part_tags_as_strings(part: Resource) -> Array[String]:
	var result: Array[String] = []
	for tag: StringName in MLBodyPartContract.part_tags(part):
		result.append(str(tag))
	return result


func _slot_index(slot_id: StringName) -> int:
	for index in range(slots.size()):
		var slot: MLBodySlotDefinition = slots[index].get("definition") as MLBodySlotDefinition
		if slot != null and slot.slot_id == slot_id:
			return index
	return -1


func _fail(message: String) -> bool:
	last_error = message
	return false


func _fail_manifest(message: String) -> MLBodyInterfaceManifest:
	last_error = message
	return null
