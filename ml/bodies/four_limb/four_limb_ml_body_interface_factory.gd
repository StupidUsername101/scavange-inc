class_name FourLimbMLBodyInterfaceFactory
extends RefCounted

#######################################################
# Adapts the existing four-limb gameplay definition/runtime into the same accepted body manifest
# used by drones. The legacy four-limb trainer may keep its established task encoder, but body
# topology is no longer a separate concept: each physical GenericLimbDefinition occupies a typed
# Core slot and declares its own controls/observations.
#######################################################


static func create_definition_draft(definition: FourLimbBodyDefinition) -> MLBodyBuildDraft:
	var draft = MLBodyBuildDraft.new()
	if definition == null:
		draft.last_error = "A four-limb preset requires a body definition."
		return draft
	definition.ensure_contract()
	var creator_core_part: MLRigidCorePartDefinition = _creator_core_part(definition)
	draft.set_core(creator_core_part, {
		"body_kind": "articulated_body",
		"source_runtime_profile": FourLimbBodyDefinition.BODY_PROFILE_ID,
	})
	for slot_index in range(definition.limbs.size()):
		var legacy_slot: FourLimbSlotDefinition = definition.limbs[slot_index]
		var slot = MLBodySlotDefinition.new()
		slot.slot_id = StringName("limb_%d" % slot_index)
		slot.display_name = (
			legacy_slot.slot_name
			if legacy_slot != null and not legacy_slot.slot_name.strip_edges().is_empty()
			else "Limb %d" % (slot_index + 1)
		)
		slot.slot_type = &"limb"
		slot.accepted_part_tags.append(&"limb")
		if legacy_slot != null:
			slot.mount_transform = Transform3D(Basis.IDENTITY, legacy_slot.hip_offset)
		var part: GenericLimbDefinition = FourLimbGenericDefinitionFactory.create_limb_definition(
			definition, legacy_slot, slot_index, 0
		)
		if not draft.add_slot(slot, part):
			return draft
	for slot_index in range(definition.attachment_slots.size()):
		var legacy_attachment: FourLimbAttachmentSlotDefinition = definition.attachment_slots[slot_index]
		var slot = MLBodySlotDefinition.new()
		slot.slot_id = StringName("attachment_%d" % slot_index)
		slot.display_name = (
			legacy_attachment.slot_name
			if legacy_attachment != null and not legacy_attachment.slot_name.strip_edges().is_empty()
			else "Attachment %d" % (slot_index + 1)
		)
		slot.slot_type = &"attachment"
		if legacy_attachment != null:
			slot.mount_transform = legacy_attachment.core_offset
			for tag: String in legacy_attachment.allowed_tags:
				slot.accepted_part_tags.append(StringName(tag))
		if not draft.add_slot(slot, null):
			return draft
	return draft


static func create_runtime_draft(body: FourLimbPhysicalBody3D) -> MLBodyBuildDraft:
	var draft = MLBodyBuildDraft.new()
	if not is_instance_valid(body) or body.definition == null:
		draft.last_error = "A four-limb model body requires a physical body definition."
		return draft
	body.definition.ensure_contract()
	var runtime_core_part: MLRigidCorePartDefinition = _creator_core_part(body.definition)
	draft.set_core(runtime_core_part, {
		"body_kind": "articulated_body",
		"source_runtime_profile": FourLimbBodyDefinition.BODY_PROFILE_ID,
	})
	var rig: FourLimbPhysicalRig3D = body.physical_rig
	for slot_index in range(body.definition.limbs.size()):
		var legacy_slot: FourLimbSlotDefinition = body.definition.limbs[slot_index]
		var slot = MLBodySlotDefinition.new()
		slot.slot_id = StringName("limb_%d" % slot_index)
		slot.display_name = (
			legacy_slot.slot_name
			if legacy_slot != null and not legacy_slot.slot_name.strip_edges().is_empty()
			else "Limb %d" % (slot_index + 1)
		)
		slot.slot_type = &"limb"
		slot.accepted_part_tags.append(&"limb")
		if legacy_slot != null:
			slot.mount_transform = Transform3D(Basis.IDENTITY, legacy_slot.hip_offset)
		var part: GenericLimbDefinition = _runtime_limb_definition(rig, slot_index)
		if not draft.add_slot(slot, part):
			return draft
	# Preserve the existing fixed gameplay attachment ports in the common Core manifest. Current
	# provider nodes are runtime equipment rather than serialized Resource part definitions, so an
	# empty slot contributes no dynamic channels until the future body creator equips a real part.
	for slot_index in range(body.definition.attachment_slots.size()):
		var legacy_attachment: FourLimbAttachmentSlotDefinition = body.definition.attachment_slots[slot_index]
		var slot = MLBodySlotDefinition.new()
		slot.slot_id = StringName("attachment_%d" % slot_index)
		slot.display_name = (
			legacy_attachment.slot_name
			if legacy_attachment != null and not legacy_attachment.slot_name.strip_edges().is_empty()
			else "Attachment %d" % (slot_index + 1)
		)
		slot.slot_type = &"attachment"
		if legacy_attachment != null:
			slot.mount_transform = legacy_attachment.core_offset
			for tag: String in legacy_attachment.allowed_tags:
				slot.accepted_part_tags.append(StringName(tag))
		if not draft.add_slot(slot, null):
			return draft
	return draft


static func finalize_runtime_body(body: FourLimbPhysicalBody3D) -> MLBodyInterfaceManifest:
	var draft: MLBodyBuildDraft = create_runtime_draft(body)
	if not draft.last_error.is_empty():
		return null
	return draft.accept_build()


static func runtime_states(body: FourLimbPhysicalBody3D) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(body) or not is_instance_valid(body.physical_rig):
		return result
	var rig: FourLimbPhysicalRig3D = body.physical_rig
	for slot_index in range(rig.limb_records.size()):
		var record_value: Variant = rig.limb_records[slot_index]
		if not (record_value is Dictionary):
			continue
		var chain: GenericLimb3D = (record_value as Dictionary).get("chain") as GenericLimb3D
		if not is_instance_valid(chain):
			continue
		result["limb_%d" % slot_index] = GenericLimbModelContract.runtime_state_for_limb(
			chain,
			rig.core_bone
		)
	return result


static func host_state(body: FourLimbPhysicalBody3D) -> Dictionary:
	if not is_instance_valid(body) or not is_instance_valid(body.physical_rig):
		return {}
	var rig: FourLimbPhysicalRig3D = body.physical_rig
	return {
		"transform_world": rig.get_core_transform(),
		"linear_velocity_world": rig.get_core_linear_velocity(),
		"angular_velocity_world": rig.get_core_angular_velocity(),
	}


static func _runtime_limb_definition(
	rig: FourLimbPhysicalRig3D,
	slot_index: int
) -> GenericLimbDefinition:
	if not is_instance_valid(rig) or slot_index < 0 or slot_index >= rig.limb_records.size():
		return null
	var record_value: Variant = rig.limb_records[slot_index]
	if not (record_value is Dictionary):
		return null
	var chain: GenericLimb3D = (record_value as Dictionary).get("chain") as GenericLimb3D
	return chain.definition if is_instance_valid(chain) else null


static func _creator_core_part(definition: FourLimbBodyDefinition) -> MLRigidCorePartDefinition:
	var result = MLRigidCorePartDefinition.new()
	result.display_name = "Walker Core"
	result.body_size = definition.core_size
	result.mass_kg = definition.core_mass
	result.maximum_health = definition.core_maximum_health
	result.friction = definition.friction
	result.bounce = definition.bounce
	result.linear_damp = definition.linear_damp
	result.angular_damp = definition.angular_damp
	result.sanitize()
	return result
