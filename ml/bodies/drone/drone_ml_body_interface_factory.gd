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
	# Legacy gameplay AI chips are not part of a trainable model body. The learned policy itself
	# is the drone intelligence, so creator/training contracts expose only physical/control hardware.
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


static func training_runtime_validation_error(
	drone: ServerDrone,
	expected_manifest: MLBodyInterfaceManifest = null
) -> String:
	if not is_instance_valid(drone):
		return "Drone runtime is missing."
	var manifest: MLBodyInterfaceManifest = drone.model_body_interface()
	if manifest == null or not manifest.finalized:
		return "Drone runtime could not finalize its model-body interface."
	if expected_manifest != null and not manifest.is_compatible_with(expected_manifest):
		return "Drone runtime body no longer matches the accepted creator body contract."
	if drone.loadout == null or drone.loadout.core == null:
		return "Drone runtime has no Core/loadout."

	# Validate observations from the real instantiated worker, not only from Resource metadata. This
	# catches an attachment that advertises sensor channels but failed to build its runtime node.
	var states: Dictionary = runtime_states(drone)
	var encoded: PackedFloat64Array = manifest.encode_body_observation(states, host_state(drone))
	if encoded.size() != manifest.observation_count():
		return "Runtime body produced %d/%d finalized observation channels." % [
			encoded.size(), manifest.observation_count(),
		]

	var core_control_count: int = int(manifest.core_record.get("control_count", 0))
	if core_control_count > 0:
		if not drone.can_submit_model_core_commands(core_control_count):
			return "Runtime Core cannot consume its %d finalized model controls." % core_control_count

	for record: Dictionary in manifest.slot_records:
		var slot_id: String = str(record.get("slot_id", ""))
		var control_count: int = int(record.get("control_count", 0))
		var observation_count: int = int(record.get("observation_count", 0))
		if observation_count > 0 and not states.has(slot_id):
			return "%s declares observations but has no runtime state provider." % slot_id
		if control_count <= 0:
			continue
		if slot_id.begins_with("propeller_"):
			var suffix: String = slot_id.trim_prefix("propeller_")
			if not suffix.is_valid_int():
				return "Malformed finalized propeller slot %s." % slot_id
			var propeller_index: int = int(suffix)
			if control_count != 1 or drone.loadout.get_propeller(propeller_index) == null:
				return "%s does not resolve to one live throttle actuator." % slot_id
			continue
		if slot_id.begins_with("attachment_"):
			var attachment_suffix: String = slot_id.trim_prefix("attachment_")
			if not attachment_suffix.is_valid_int():
				return "Malformed finalized attachment slot %s." % slot_id
			var attachment_index: int = int(attachment_suffix)
			if not drone.can_submit_model_attachment_slot_commands(attachment_index, control_count):
				return "%s advertises %d controls but its instantiated attachment cannot consume them." % [
					slot_id, control_count,
				]
			var attachment: DroneAttachmentDefinition = drone.loadout.get_attachment(attachment_index)
			if attachment is DroneLimbAttachmentDefinition:
				var assembly: GenericLimbAssembly3D = drone.get_limb_attachment_assembly(attachment_index)
				if not is_instance_valid(assembly):
					return "%s has no instantiated articulated runtime assembly." % slot_id
				var declared_controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(attachment)
				var runtime_controls: Array[Dictionary] = GenericLimbModelContract.control_descriptors(assembly.limb_definitions)
				var declared_observations: Array[Dictionary] = MLBodyPartContract.observation_descriptors(attachment)
				var runtime_observations: Array[Dictionary] = GenericLimbModelContract.observation_descriptors(assembly.limb_definitions)
				if not _descriptor_topology_matches(declared_controls, runtime_controls):
					return "%s live articulated control mapping differs from the accepted attachment contract." % slot_id
				if not _descriptor_topology_matches(declared_observations, runtime_observations):
					return "%s live articulated observation mapping differs from the accepted attachment contract." % slot_id
			continue
		if not drone.has_method("can_submit_model_slot_commands") or not bool(
			drone.call("can_submit_model_slot_commands", slot_id, control_count)
		):
			return "%s advertises controls but the drone runtime has no consumer for them." % slot_id

	return ""


static func _descriptor_topology_matches(expected: Array[Dictionary], actual: Array[Dictionary]) -> bool:
	if expected.size() != actual.size():
		return false
	for index: int in range(expected.size()):
		var expected_descriptor: Dictionary = expected[index]
		var actual_descriptor: Dictionary = actual[index]
		for key: String in ["name", "kind"]:
			if str(expected_descriptor.get(key, "")) != str(actual_descriptor.get(key, "")):
				return false
		for key: String in ["minimum", "maximum", "neutral"]:
			if expected_descriptor.has(key) or actual_descriptor.has(key):
				if not is_equal_approx(
					float(expected_descriptor.get(key, 0.0)),
					float(actual_descriptor.get(key, 0.0))
				):
					return false
	return true


static func _core_contract(loadout: DroneLoadout) -> Dictionary:
	var core: DroneCoreDefinition = loadout.core
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
	}
