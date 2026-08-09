class_name DroneMLBodyInterfaceFactory
extends RefCounted

const SLOT_LAYOUT = preload("res://scripts/drones/drone_slot_layout.gd")

#######################################################
# Adapts the existing gameplay DroneLoadout slot system into the shared model-forge body draft.
# Nothing is finalized while the loadout is being edited. Training/group creation calls
# finalize_loadout() once the body is accepted.
#######################################################


static func create_draft(loadout: DroneLoadout) -> MLBodyBuildDraft:
	var draft: MLBodyBuildDraft = MLBodyBuildDraft.new()
	if loadout == null or loadout.core == null:
		draft.last_error = "A drone model body requires a core."
		return draft
	# A creator draft is an edit buffer, never a view onto a loaded preset or live runtime loadout.
	# Deep-copy the complete hardware tree while retaining source-resource metadata for save/reopen.
	var safe_loadout: DroneLoadout = (
		MLBodyPartContract.deep_duplicate_resource(loadout) as DroneLoadout
	)
	if safe_loadout == null or safe_loadout.core == null:
		draft.last_error = "The drone hardware could not be copied into an editable body draft."
		return draft
	draft.set_core(safe_loadout.core, _core_contract(safe_loadout))
	var battery_slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
	battery_slot.slot_id = &"battery"
	battery_slot.display_name = "Battery"
	battery_slot.slot_type = &"battery"
	battery_slot.accepted_part_tags.append(&"battery")
	battery_slot.mount_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, safe_loadout.core.body_size.y * 0.5, 0.0)
	)
	if not draft.add_slot(battery_slot, safe_loadout.battery):
		return draft
	for slot_index: int in range(safe_loadout.core.propeller_slot_count):
		var slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
		slot.slot_id = StringName("propeller_%d" % slot_index)
		slot.display_name = "Propeller %d" % (slot_index + 1)
		slot.slot_type = &"propeller"
		slot.accepted_part_tags.append(&"propeller")
		if not draft.add_slot(slot, safe_loadout.get_propeller(slot_index)):
			return draft
	for slot_index: int in range(safe_loadout.core.ai_chip_slot_count):
		var slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
		slot.slot_id = StringName("ai_chip_%d" % slot_index)
		slot.display_name = "AI Chip %d" % (slot_index + 1)
		slot.slot_type = &"ai_chip"
		slot.accepted_part_tags.append(&"ai_chip")
		slot.mount_transform = Transform3D(
			Basis.IDENTITY,
			SLOT_LAYOUT.get_ai_chip_position(slot_index, safe_loadout.core.body_size)
		)
		if not draft.add_slot(slot, safe_loadout.get_ai_chip(slot_index)):
			return draft
	for slot_index: int in range(safe_loadout.core.attachment_slot_count):
		var slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
		slot.slot_id = StringName("attachment_%d" % slot_index)
		slot.display_name = "Attachment %d" % (slot_index + 1)
		slot.slot_type = &"attachment"
		slot.accepted_part_tags.append(&"attachment")
		slot.mount_transform = Transform3D(
			Basis.IDENTITY,
			SLOT_LAYOUT.get_attachment_position(slot_index, safe_loadout.core.body_size)
		)
		if not draft.add_slot(slot, safe_loadout.get_attachment(slot_index)):
			return draft
	return draft


static func finalize_loadout(loadout: DroneLoadout) -> MLBodyInterfaceManifest:
	var draft: MLBodyBuildDraft = create_draft(loadout)
	if not draft.last_error.is_empty():
		return null
	return draft.accept_build()


static func matches_runtime_contract(
	manifest: MLBodyInterfaceManifest,
	runtime_contract: Dictionary
) -> bool:
	if manifest == null or not manifest.finalized or runtime_contract.is_empty():
		return false
	return (
		int(runtime_contract.get("action_count", -1)) == manifest.control_count()
		and int(runtime_contract.get("body_feature_count", -1)) == manifest.observation_count()
		and str(runtime_contract.get("body_interface_signature", "")) == manifest.contract_signature
	)


static func matches_trainer_architecture(
	manifest: MLBodyInterfaceManifest,
	architecture: Dictionary
) -> bool:
	return matches_runtime_contract(manifest, architecture)


static func runtime_states(drone: ServerDrone) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(drone):
		return result
	var propellers: Array[Dictionary] = DroneMLObservation.capture_ppo_propeller_states(drone)
	for propeller_state: Dictionary in propellers:
		var slot_index: int = int(propeller_state.get("slot_index", -1))
		if slot_index >= 0:
			result["propeller_%d" % slot_index] = propeller_state
	var limb_states: Dictionary = (
		drone.all_limb_attachment_states()
		if drone.has_method("all_limb_attachment_states")
		else {}
	)
	if drone.loadout != null and drone.loadout.core != null:
		for slot_index in range(drone.loadout.core.attachment_slot_count):
			var attachment: DroneAttachmentDefinition = drone.loadout.get_attachment(slot_index)
			if attachment is DroneLimbAttachmentDefinition:
				result["attachment_%d" % slot_index] = limb_states.get(slot_index, {})
			elif attachment != null and drone.has_method("model_attachment_state_for_slot"):
				result["attachment_%d" % slot_index] = drone.model_attachment_state_for_slot(slot_index)
	return result


static func host_state(drone: ServerDrone) -> Dictionary:
	if not is_instance_valid(drone):
		return {}
	return {
		"transform_world": drone.global_transform,
		"linear_velocity_world": drone.linear_velocity,
		"angular_velocity_world": drone.angular_velocity,
	}


static func _core_contract(loadout: DroneLoadout) -> Dictionary:
	var core: DroneCoreDefinition = loadout.core
	var ai_paths: Array[String] = []
	var ai_slot_count: int = core.ai_chip_slot_count if core != null else 0
	for slot_index: int in range(ai_slot_count):
		ai_paths.append(MLBodyPartContract.resource_source_path(loadout.get_ai_chip(slot_index)))
	return {
		"body_kind": "drone",
		"core_resource_path": MLBodyPartContract.resource_source_path(core),
		"core_display_name": core.display_name if core != null else "",
		"core_body_size": (
			[core.body_size.x, core.body_size.y, core.body_size.z]
			if core != null
			else [0.0, 0.0, 0.0]
		),
		"propeller_slot_count": core.propeller_slot_count if core != null else 0,
		"attachment_slot_count": core.attachment_slot_count if core != null else 0,
		"battery_resource_path": MLBodyPartContract.resource_source_path(loadout.battery),
		"ai_chip_resource_paths": ai_paths,
	}
