extends SceneTree

#######################################################
# Verifies the model-forge body contract independently of a physics world. A mutable Core/slot
# draft may contain arbitrary part topologies; only accept_build() freezes the neural interface.
#######################################################

var failure_count: int = 0
var assertion_count: int = 0


func _init() -> void:
	_test_generic_core_and_accept_boundary()
	_test_creator_presets_are_editable_templates()
	_test_creator_runtime_bridge()
	_test_body_factories_keep_resource_backing()
	_test_interface_signature_tracks_topology_not_tuning()
	_test_regular_articulated_drone_limb()
	_test_arbitrary_generic_limb_topology()
	_test_existing_limb_mapping_order()
	_test_turret_part_ownership()
	_test_input_vector_builder()
	_test_body_action_routing()
	if failure_count == 0:
		print("ML body interface tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("ML body interface tests failed: %d/%d assertions" % [failure_count, assertion_count])
		quit(1)


func _test_generic_core_and_accept_boundary() -> void:
	var core = MLBodyCoreDefinition.new()
	core.core_id = &"test_core"
	for index in range(3):
		var slot = MLBodySlotDefinition.new()
		slot.slot_id = StringName("slot_%d" % index)
		slot.slot_type = &"attachment"
		slot.accepted_part_tags.append(&"attachment")
		_expect(core.add_slot(slot), "Core accepts arbitrary ordered attachment slots")
	var draft = MLBodyBuildDraft.new()
	_expect(draft.configure_from_core(core, "test_body"), "body draft can be populated from a Core")
	_expect(draft.slots.size() == 3 and not draft.accepted, "draft remains editable before Accept")
	var temporary_slot = MLBodySlotDefinition.new()
	temporary_slot.slot_id = &"temporary"
	temporary_slot.slot_type = &"attachment"
	temporary_slot.accepted_part_tags.append(&"attachment")
	_expect(
		draft.add_slot(temporary_slot)
		and core.slot_index(&"temporary") >= 0
		and draft.remove_slot(&"temporary")
		and core.slot_index(&"temporary") < 0,
		"draft slot edits keep the editable Core slot list synchronized"
	)

	var incompatible = DronePropellerDefinition.new()
	_expect(
		not draft.equip(&"slot_0", incompatible),
		"typed slots reject parts that do not advertise a compatible tag"
	)
	var attachment = DroneAttachmentDefinition.new()
	_expect(draft.equip(&"slot_0", attachment), "typed slot accepts one compatible equipped part")
	var manifest: MLBodyInterfaceManifest = draft.accept_build()
	_expect(manifest != null and manifest.finalized and draft.accepted, "Accept freezes a finalized body manifest")
	_expect(
		not draft.unequip(&"slot_0"),
		"accepted draft cannot be edited in place while a model may depend on it"
	)
	var frozen_part: Resource = manifest.slot_records[0].get("part") as Resource
	_expect(
		frozen_part != attachment,
		"accepted manifest owns a frozen part copy rather than the UI draft resource"
	)
	var revision: MLBodyBuildDraft = draft.duplicate_editable()
	_expect(
		not revision.accepted and revision.unequip(&"slot_0"),
		"editing an accepted body starts an isolated draft revision"
	)
	var revision_core: MLBodyCoreDefinition = revision.core as MLBodyCoreDefinition
	var revision_slot: MLBodySlotDefinition = revision.slots[0].get("definition") as MLBodySlotDefinition
	_expect(
		revision_core != null
		and revision_core.attachment_slots[0] == revision_slot
		and revision_slot != core.attachment_slots[0],
		"editable revisions keep one isolated authoritative slot object per Core slot"
	)

	var corrupt_core = MLBodyCoreDefinition.new()
	var corrupt_slot = MLBodySlotDefinition.new()
	corrupt_slot.slot_id = &"original"
	corrupt_core.add_slot(corrupt_slot)
	var corrupt_draft = MLBodyBuildDraft.new()
	corrupt_draft.configure_from_core(corrupt_core, "test_body")
	var bypass_slot = MLBodySlotDefinition.new()
	bypass_slot.slot_id = &"bypass"
	corrupt_core.attachment_slots.append(bypass_slot)
	_expect(
		corrupt_draft.accept_build() == null,
		"Accept rejects Core slot mutations that bypass the authoritative body draft"
	)

	var malformed_core = MLBodyCoreDefinition.new()
	var malformed_slot = MLBodySlotDefinition.new()
	malformed_slot.slot_id = &"limb"
	malformed_slot.slot_type = &"limb"
	malformed_slot.accepted_part_tags.append(&"limb")
	_expect(malformed_core.add_slot(malformed_slot), "malformed-limb test Core accepts its limb slot")
	var malformed_limb = GenericLimbDefinition.new()
	malformed_limb.limb_name = "Missing saved joint"
	var malformed_segment = LimbSegmentDefinition.new()
	malformed_segment.joint = null
	malformed_limb.segments.append(malformed_segment)
	malformed_limb.sanitize()
	_expect(
		malformed_limb.end_effector == null and malformed_segment.joint == null,
		"sanitizing a creator limb never fabricates a joint or end-effector"
	)
	var malformed_draft = MLBodyBuildDraft.new()
	_expect(
		malformed_draft.configure_from_core(malformed_core, "malformed_limb_test")
		and malformed_draft.equip(&"limb", malformed_limb)
		and malformed_draft.accept_build() == null
		and malformed_draft.last_error.contains("missing its saved joint definition"),
		"Accept rejects an incomplete limb instead of inventing hardcoded body parts"
	)


func _test_creator_presets_are_editable_templates() -> void:
	var records: Array[Dictionary] = MLBodyPresetLibrary.ui_records()
	var ids: Array[String] = []
	for record: Dictionary in records:
		ids.append(str(record.get("preset_id", "")))
	_expect(
		records.size() == 4
		and ids.has(str(MLBodyPresetLibrary.DRONE_QUAD))
		and ids.has(str(MLBodyPresetLibrary.DRONE_QUAD_GRABBER))
		and ids.has(str(MLBodyPresetLibrary.FOUR_LIMB_WALKER))
		and ids.has(str(MLBodyPresetLibrary.STATIONARY_TURRET)),
		"body creator exposes the four built-in bodies as named presets"
	)

	for preset_id: StringName in [
		MLBodyPresetLibrary.DRONE_QUAD,
		MLBodyPresetLibrary.DRONE_QUAD_GRABBER,
		MLBodyPresetLibrary.FOUR_LIMB_WALKER,
		MLBodyPresetLibrary.STATIONARY_TURRET,
	]:
		var draft: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(preset_id)
		var creator_core: MLBodyCoreDefinition = draft.core as MLBodyCoreDefinition if draft != null else null
		_expect(
			draft != null
			and not draft.accepted
			and creator_core != null
			and creator_core.attachment_slots.size() == draft.slots.size(),
			"creator preset %s opens as an editable generic Core + slot draft" % str(preset_id)
		)
		if draft == null or creator_core == null:
			continue
		var original_slot_count: int = draft.slots.size()
		var preview: Dictionary = draft.ui_snapshot()
		_expect(
			int(preview.get("slot_count", -1)) == original_slot_count
			and not bool(preview.get("accepted", true))
			and (preview.get("slots", []) as Array).size() == original_slot_count,
			"creator preset %s exposes UI-ready slot data without finalizing the body" % str(preset_id)
		)
		var added_slot = MLBodySlotDefinition.new()
		added_slot.slot_id = &"ui_test_extra_slot"
		added_slot.display_name = "UI test slot"
		added_slot.slot_type = &"attachment"
		_expect(
			draft.add_slot(added_slot)
			and draft.slots.size() == original_slot_count + 1
			and creator_core.attachment_slots.size() == draft.slots.size(),
			"creator preset %s can change slot topology before Accept" % str(preset_id)
		)
		var fresh: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(preset_id)
		_expect(
			fresh != null and fresh.slots.size() == original_slot_count,
			"creator preset %s is an isolated template rather than mutable global body state" % str(preset_id)
		)
		var manifest: MLBodyInterfaceManifest = draft.accept_build()
		_expect(
			manifest != null and draft.accepted and not fresh.accepted,
			"creator preset %s finalizes neural topology only when that draft is accepted" % str(preset_id)
		)

	var invalid_edit: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(MLBodyPresetLibrary.DRONE_QUAD)
	if invalid_edit != null and invalid_edit.slots.size() >= 2:
		var first_slot: MLBodySlotDefinition = invalid_edit.slots[0].get("definition") as MLBodySlotDefinition
		var second_slot: MLBodySlotDefinition = invalid_edit.slots[1].get("definition") as MLBodySlotDefinition
		second_slot.slot_id = first_slot.slot_id
		_expect(
			invalid_edit.accept_build() == null
			and not invalid_edit.accepted
			and invalid_edit.last_error.contains("Duplicate body slot id"),
			"Accept revalidates slot ids after direct UI edits instead of freezing ambiguous routing"
		)
	var core_swap_draft = MLBodyBuildDraft.new()
	var old_core = DroneCoreDefinition.new()
	core_swap_draft.set_core(old_core, {"body_kind": "drone"})
	var stale_slot = MLBodySlotDefinition.new()
	stale_slot.slot_id = &"stale"
	core_swap_draft.add_slot(stale_slot)
	var replacement_core = DroneCoreDefinition.new()
	_expect(
		core_swap_draft.set_core(replacement_core, {"body_kind": "drone"})
		and core_swap_draft.slots.is_empty(),
		"replacing a draft Core clears stale attachment slots from the previous Core"
	)

	var walker: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(
		MLBodyPresetLibrary.FOUR_LIMB_WALKER
	)
	var walker_core: MLBodyCoreDefinition = walker.core as MLBodyCoreDefinition if walker != null else null
	_expect(
		walker_core != null
		and walker_core.physical_core is MLRigidCorePartDefinition
		and not (walker_core.physical_core is FourLimbBodyDefinition),
		"Four-Limb Walker creator preset contains generic Core physics instead of a hidden fixed-body definition"
	)
	var quad_preset_manifest: MLBodyInterfaceManifest = MLBodyPresetLibrary.preset_by_id(
		MLBodyPresetLibrary.DRONE_QUAD
	).instantiate_manifest()
	var quad_runtime_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(
		MLBodyPresetLibrary.drone_quad_loadout(false)
	)
	_expect(
		quad_preset_manifest != null
		and quad_runtime_manifest != null
		and quad_preset_manifest.contract_signature == quad_runtime_manifest.contract_signature,
		"accepting the Quad Drone creator preset matches the runtime drone body contract exactly"
	)
	var quad_revision: MLBodyBuildDraft = (
		quad_preset_manifest.editable_revision() if quad_preset_manifest != null else null
	)
	var frozen_quad_slot_count: int = (
		quad_preset_manifest.slot_records.size() if quad_preset_manifest != null else -1
	)
	var revision_slot = MLBodySlotDefinition.new()
	revision_slot.slot_id = &"revision_only_slot"
	revision_slot.slot_type = &"attachment"
	_expect(
		quad_revision != null
		and not quad_revision.accepted
		and quad_revision.add_slot(revision_slot)
		and quad_revision.slots.size() == frozen_quad_slot_count + 1
		and quad_preset_manifest.slot_records.size() == frozen_quad_slot_count
		and quad_preset_manifest.frozen_slot_copy(&"battery") != null,
		"an accepted body can open an isolated editable UI revision without mutating the running manifest"
	)
	var runtime_revision: MLBodyBuildDraft = (
		quad_runtime_manifest.editable_revision() if quad_runtime_manifest != null else null
	)
	var runtime_revision_core: MLBodyCoreDefinition = (
		runtime_revision.core as MLBodyCoreDefinition if runtime_revision != null else null
	)
	var runtime_reaccepted: MLBodyInterfaceManifest = (
		runtime_revision.accept_build() if runtime_revision != null else null
	)
	_expect(
		runtime_revision_core != null
		and runtime_reaccepted != null
		and runtime_reaccepted.contract_signature == quad_runtime_manifest.contract_signature,
		"runtime bodies reopen through the same generic Core + slots creator draft and re-Accept identically"
	)
	var quad_draft: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(MLBodyPresetLibrary.DRONE_QUAD)
	var persisted_draft_record: Dictionary = MLBodyBuildSnapshot.encode_draft(quad_draft)
	var persisted_draft_json: String = JSON.stringify(persisted_draft_record)
	var persisted_draft_value: Variant = JSON.parse_string(persisted_draft_json)
	var restored_draft: MLBodyBuildDraft = (
		MLBodyBuildSnapshot.decode_draft(persisted_draft_value as Dictionary)
		if persisted_draft_value is Dictionary
		else null
	)
	var restored_draft_manifest: MLBodyInterfaceManifest = (
		restored_draft.accept_build() if restored_draft != null else null
	)
	_expect(
		restored_draft != null
		and restored_draft_manifest != null
		and restored_draft_manifest.contract_signature == quad_preset_manifest.contract_signature,
		"creator drafts survive JSON persistence and still Accept to the same model topology"
	)
	var cyclic_core = MLBodyCoreDefinition.new()
	cyclic_core.physical_core = cyclic_core
	var cyclic_draft = MLBodyBuildDraft.new()
	cyclic_draft.configure_from_core(cyclic_core, "cycle_test")
	_expect(
		MLBodyResourceSnapshot.encode_resource(cyclic_core).is_empty()
		and MLBodyBuildSnapshot.encode_draft(cyclic_draft).is_empty(),
		"creator persistence rejects cyclic Resource graphs instead of silently dropping nested body data"
	)
	var malformed_core_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(quad_draft.core)
	var malformed_properties: Dictionary = malformed_core_snapshot.get("properties", {})
	malformed_properties["physical_core"] = {
		MLBodyResourceSnapshot.TYPE_KEY: "unknown_future_attachment_value",
		"value": "must-not-decode-as-null",
	}
	malformed_core_snapshot["properties"] = malformed_properties
	_expect(
		MLBodyResourceSnapshot.decode_resource(malformed_core_snapshot) == null,
		"creator persistence rejects unknown serialized Variant tags instead of silently nulling body data"
	)
	var quad_snapshot: Dictionary = quad_draft.ui_snapshot() if quad_draft != null else {}
	var quad_slot_types: Dictionary = {}
	for slot_record: Dictionary in quad_snapshot.get("slots", []):
		var slot_type: String = str(slot_record.get("slot_type", ""))
		quad_slot_types[slot_type] = int(quad_slot_types.get(slot_type, 0)) + 1
	_expect(
		int(quad_snapshot.get("slot_count", -1)) == 9
		and int(quad_slot_types.get("battery", 0)) == 1
		and int(quad_slot_types.get("propeller", 0)) == 4
		and int(quad_slot_types.get("ai_chip", 0)) == 2
		and int(quad_slot_types.get("attachment", 0)) == 2,
		"Quad Drone creator preview exposes every physical gameplay slot, including zero-channel battery and AI-chip slots"
	)
	var turret_preset_manifest: MLBodyInterfaceManifest = MLBodyPresetLibrary.preset_by_id(
		MLBodyPresetLibrary.STATIONARY_TURRET
	).instantiate_manifest()
	var turret_runtime_manifest: MLBodyInterfaceManifest = TurretMLBodyInterfaceFactory.finalize_loadout(
		MLBodyPresetLibrary.stationary_turret_loadout()
	)
	_expect(
		turret_preset_manifest != null
		and turret_runtime_manifest != null
		and turret_preset_manifest.contract_signature == turret_runtime_manifest.contract_signature,
		"accepting the Stationary Turret creator preset matches the runtime turret body contract exactly"
	)
	var walker_preset_manifest: MLBodyInterfaceManifest = MLBodyPresetLibrary.preset_by_id(
		MLBodyPresetLibrary.FOUR_LIMB_WALKER
	).instantiate_manifest()
	var walker_runtime_definition: FourLimbBodyDefinition = MLBodyPresetLibrary.four_limb_walker_definition()
	var walker_runtime_draft: MLBodyBuildDraft = FourLimbMLBodyInterfaceFactory.create_definition_draft(
		walker_runtime_definition
	)
	var walker_runtime_manifest: MLBodyInterfaceManifest = walker_runtime_draft.accept_build()
	_expect(
		walker_preset_manifest != null
		and walker_runtime_manifest != null
		and walker_preset_manifest.contract_signature == walker_runtime_manifest.contract_signature,
		"accepting the Four-Limb Walker creator preset matches the compatibility runtime body contract exactly"
	)

	if walker != null:
		var limb_slot_count: int = 0
		var generic_limb_count: int = 0
		for entry: Dictionary in walker.slots:
			var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
			if slot != null and slot.slot_type == &"limb":
				limb_slot_count += 1
				if entry.get("part") is GenericLimbDefinition:
					generic_limb_count += 1
		_expect(
			limb_slot_count == 4 and generic_limb_count == 4,
			"Four-Limb Walker preset expresses every leg only as an ordinary equipped GenericLimbDefinition"
		)


func _test_creator_runtime_bridge() -> void:
	for preset_id: StringName in [
		MLBodyPresetLibrary.DRONE_QUAD,
		MLBodyPresetLibrary.DRONE_QUAD_GRABBER,
		MLBodyPresetLibrary.FOUR_LIMB_WALKER,
		MLBodyPresetLibrary.STATIONARY_TURRET,
	]:
		var draft: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(preset_id)
		var accepted_draft: MLBodyBuildDraft = draft.duplicate_editable() if draft != null else null
		var creator_manifest: MLBodyInterfaceManifest = (
			accepted_draft.accept_build() if accepted_draft != null else null
		)
		var runtime_body: Resource = MLBodyCreatorRuntimeFactory.runtime_from_draft(
			preset_id,
			draft
		)
		var runtime_manifest: MLBodyInterfaceManifest = (
			MLBodyCreatorRuntimeFactory.runtime_manifest(runtime_body)
			if runtime_body != null
			else null
		)
		_expect(
			draft != null
			and creator_manifest != null
			and runtime_body != null
			and runtime_manifest != null
			and creator_manifest.contract_signature == runtime_manifest.contract_signature,
			"creator preset %s round-trips into the trainer runtime without changing its neural contract" % str(preset_id)
		)

	var drone_draft: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(
		MLBodyPresetLibrary.DRONE_QUAD
	)
	var battery_slot: MLBodySlotDefinition = null
	if drone_draft != null:
		for entry: Dictionary in drone_draft.slots:
			var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
			if slot != null and slot.slot_id == &"battery":
				battery_slot = slot
				break
	var batteries: Array[Resource] = MLBodyPartCatalog.compatible_parts(battery_slot)
	var industrial_battery_path: String = "res://resources/drones/batteries/industrial_battery.tres"
	var industrial_battery: DroneBatteryDefinition = load(industrial_battery_path) as DroneBatteryDefinition
	var catalogue_has_industrial_battery: bool = false
	for battery_part: Resource in batteries:
		if MLBodyPartContract.resource_source_path(battery_part) == industrial_battery_path:
			catalogue_has_industrial_battery = true
			break
	_expect(
		battery_slot != null
		and batteries.size() > 1
		and industrial_battery != null
		and catalogue_has_industrial_battery,
		"creator catalogue discovers multiple authored compatible battery resources instead of a hardcoded UI list"
	)
	if drone_draft != null and industrial_battery != null:
		var equipped: bool = drone_draft.equip(&"battery", industrial_battery)
		var changed_slots: Dictionary = {"battery": true}
		var customized_runtime: DroneLoadout = MLBodyCreatorRuntimeFactory.runtime_from_draft(
			MLBodyPresetLibrary.DRONE_QUAD,
			drone_draft,
			changed_slots
		) as DroneLoadout
		var accepted_custom_draft: MLBodyBuildDraft = drone_draft.duplicate_editable()
		var custom_creator_manifest: MLBodyInterfaceManifest = accepted_custom_draft.accept_build()
		var custom_runtime_manifest: MLBodyInterfaceManifest = (
			MLBodyCreatorRuntimeFactory.runtime_manifest(customized_runtime)
			if customized_runtime != null
			else null
		)
		_expect(
			equipped
			and customized_runtime != null
			and customized_runtime.battery != null
			and MLBodyPartContract.resource_source_path(customized_runtime.battery)
				== industrial_battery_path
			and custom_creator_manifest != null
			and custom_runtime_manifest != null
			and custom_creator_manifest.contract_signature == custom_runtime_manifest.contract_signature,
			"a creator part swap reaches the runtime loadout while preserving the accepted neural topology"
		)


func _test_body_factories_keep_resource_backing() -> void:
	var drone_source: DroneLoadout = load(
		MLBodyPresetLibrary.DRONE_QUAD_GRABBER_LOADOUT_PATH
	) as DroneLoadout
	var drone_draft: MLBodyBuildDraft = DroneMLBodyInterfaceFactory.create_draft(drone_source)
	var drone_attachment: DroneAttachmentDefinition = (
		drone_source.get_attachment(0) if drone_source != null else null
	)
	var drone_draft_attachment: Resource = (
		drone_draft.equipped_part(&"attachment_0") if drone_draft != null else null
	)
	_expect(
		drone_source != null
		and drone_draft != null
		and drone_draft.last_error.is_empty()
		and drone_draft.core != drone_source.core
		and drone_attachment != null
		and drone_draft_attachment != drone_attachment
		and MLBodyPartContract.resource_source_path(drone_attachment)
		== "res://resources/drones/attachments/training_belly_grabber.tres"
		and MLBodyPartContract.resource_source_path(drone_draft_attachment)
		== MLBodyPartContract.resource_source_path(drone_attachment),
		"drone body factory creates an isolated creator copy of saved articulated hardware while retaining .tres backing"
	)
	var runtime_drone_source: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var runtime_drone_draft: MLBodyBuildDraft = DroneMLBodyInterfaceFactory.create_draft(
		runtime_drone_source
	)
	_expect(
		runtime_drone_source != null
		and runtime_drone_draft != null
		and runtime_drone_draft.core != runtime_drone_source.core
		and not str(runtime_drone_draft.core_contract.get("core_resource_path", "")).is_empty()
		and not str(runtime_drone_draft.core_contract.get("battery_resource_path", "")).is_empty(),
		"runtime drone copies reopen as isolated creator drafts without losing saved Core/battery provenance"
	)

	var walker_source: FourLimbBodyDefinition = load(
		MLBodyPresetLibrary.FOUR_LIMB_WALKER_DEFINITION_PATH
	) as FourLimbBodyDefinition
	var walker_draft: MLBodyBuildDraft = FourLimbMLBodyInterfaceFactory.create_definition_draft(
		walker_source
	)
	var walker_part: Resource = (
		walker_draft.slots[0].get("part") as Resource
		if walker_draft != null and not walker_draft.slots.is_empty()
		else null
	)
	_expect(
		walker_source != null
		and walker_source.limbs.size() == 4
		and walker_source.limbs[0] != null
		and not MLBodyPartContract.resource_source_path(walker_source.limbs[0]).is_empty()
		and walker_part is GenericLimbDefinition
		and MLBodyPartContract.resource_source_path(walker_part)
		== FourLimbGenericDefinitionFactory.LIMB_TEMPLATE_PATH,
		"four-limb compatibility factory keeps the reconstructible generic-limb template as snapshot backing"
	)
	var walker_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(walker_part)
	var restored_walker_part: Resource = MLBodyResourceSnapshot.decode_resource(walker_snapshot)
	_expect(
		not walker_snapshot.is_empty()
		and restored_walker_part is GenericLimbDefinition
		and (restored_walker_part as GenericLimbDefinition).segments.size() == 2
		and (restored_walker_part as GenericLimbDefinition).end_effector != null,
		"saved four-limb creator hardware round-trips through the generic Resource snapshot"
	)
	var walker_draft_snapshot: Dictionary = MLBodyBuildSnapshot.encode_draft(walker_draft)
	var restored_walker_draft: MLBodyBuildDraft = MLBodyBuildSnapshot.decode_draft(
		walker_draft_snapshot
	)
	var walker_manifest: MLBodyInterfaceManifest = (
		walker_draft.accept_build() if walker_draft != null else null
	)
	var restored_walker_manifest: MLBodyInterfaceManifest = (
		restored_walker_draft.accept_build() if restored_walker_draft != null else null
	)
	_expect(
		not walker_draft_snapshot.is_empty()
		and restored_walker_draft != null
		and walker_manifest != null
		and restored_walker_manifest != null
		and restored_walker_manifest.contract_signature == walker_manifest.contract_signature,
		"the complete saved Four-Limb Walker creator draft round-trips and Accepts to the same neural topology"
	)
	var stale_backing_snapshot: Dictionary = walker_snapshot.duplicate(true)
	if walker_source != null and not walker_source.limbs.is_empty():
		stale_backing_snapshot["resource_path"] = MLBodyPartContract.resource_source_path(
			walker_source.limbs[0]
		)
	var restored_from_stale_backing: Resource = MLBodyResourceSnapshot.decode_resource(
		stale_backing_snapshot
	)
	var stale_reencoded: Dictionary = MLBodyResourceSnapshot.encode_resource(
		restored_from_stale_backing
	)
	_expect(
		restored_from_stale_backing is GenericLimbDefinition
		and not stale_reencoded.is_empty()
		and str(stale_reencoded.get("resource_path", "")).is_empty(),
		"snapshot restore rejects a stale backing .tres and does not preserve the bad path on the repaired Resource"
	)
	var walker_copy: FourLimbBodyDefinition = (
		MLBodyPartContract.deep_duplicate_resource(walker_source) as FourLimbBodyDefinition
	)
	_expect(
		walker_copy != null
		and walker_copy.limbs.size() == walker_source.limbs.size()
		and MLBodyPartContract.resource_source_path(walker_copy.limbs[0])
		== MLBodyPartContract.resource_source_path(walker_source.limbs[0])
		and walker_copy.limbs[0].end_effector != null
		and MLBodyPartContract.resource_source_path(walker_copy.limbs[0].end_effector)
		== MLBodyPartContract.resource_source_path(walker_source.limbs[0].end_effector),
		"deep runtime copies retain nested .tres provenance for creator reopen/edit flows"
	)
	var malformed_walker: FourLimbBodyDefinition = (
		MLBodyPartContract.deep_duplicate_resource(walker_source) as FourLimbBodyDefinition
	)
	if malformed_walker != null and not malformed_walker.limbs.is_empty() and malformed_walker.limbs[0] != null:
		malformed_walker.limbs[0].knee_limit_upper_degrees = 999.0
	var malformed_walker_draft: MLBodyBuildDraft = (
		FourLimbMLBodyInterfaceFactory.create_definition_draft(malformed_walker)
	)
	var sanitized_walker_part: GenericLimbDefinition = (
		malformed_walker_draft.slots[0].get("part") as GenericLimbDefinition
		if malformed_walker_draft != null and not malformed_walker_draft.slots.is_empty()
		else null
	)
	_expect(
		malformed_walker != null
		and not malformed_walker.limbs.is_empty()
		and malformed_walker.limbs[0] != null
		and malformed_walker.limbs[0].knee_limit_upper_degrees == 999.0
		and sanitized_walker_part != null
		and sanitized_walker_part.segments.size() == 2
		and is_equal_approx(
			sanitized_walker_part.segments[1].joint.upper_limit_degrees.z,
			120.0
		),
		"four-limb creator adaptation sanitizes a private preset copy instead of modifying the loaded source Resource"
	)


	var turret_source: TurretLoadout = load(
		MLBodyPresetLibrary.STATIONARY_TURRET_LOADOUT_PATH
	) as TurretLoadout
	var turret_draft: MLBodyBuildDraft = TurretMLBodyInterfaceFactory.create_draft(turret_source)
	var turret_gun: Resource = turret_source.gun if turret_source != null else null
	_expect(
		turret_source != null
		and turret_draft != null
		and turret_draft.last_error.is_empty()
		and turret_gun != null
		and not MLBodyPartContract.resource_source_path(turret_gun).is_empty(),
		"turret body factory adapts the saved gun .tres and does not manufacture the attachment"
	)
	var malformed_turret: TurretLoadout = (
		MLBodyPartContract.deep_duplicate_resource(turret_source) as TurretLoadout
	)
	if malformed_turret != null and malformed_turret.base != null:
		malformed_turret.base.maximum_yaw_speed_degrees_per_second = -5.0
	var malformed_turret_draft: MLBodyBuildDraft = TurretMLBodyInterfaceFactory.create_draft(
		malformed_turret
	)
	var sanitized_turret_base: TurretBaseDefinition = (
		malformed_turret_draft.core as TurretBaseDefinition
		if malformed_turret_draft != null
		else null
	)
	_expect(
		malformed_turret != null
		and malformed_turret.base != null
		and malformed_turret.base.maximum_yaw_speed_degrees_per_second == -5.0
		and sanitized_turret_base != null
		and sanitized_turret_base.maximum_yaw_speed_degrees_per_second >= 1.0,
		"turret creator adaptation sanitizes a private loadout copy instead of modifying the loaded source Resource"
	)


func _test_interface_signature_tracks_topology_not_tuning() -> void:
	var first: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var second: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(first)
	var changed_propeller: DronePropellerDefinition = second.get_propeller(0)
	changed_propeller.rotor_radius *= 1.4
	changed_propeller.max_power_draw *= 1.2
	var first_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(first)
	var second_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(second)
	_expect(
		first_manifest != null
		and second_manifest != null
		and first_manifest.contract_signature == second_manifest.contract_signature,
		"physical tuning does not invalidate a policy when the declared neural interface is unchanged"
	)
	_expect(
		first_manifest.control_count() == 4 and first_manifest.observation_count() == 8,
		"stock drone manifest derives four propeller controls and two observations per propeller"
	)
	_expect(
		DroneTrainingLoadoutConfig.install_training_belly_grabber(second),
		"articulated limb can be added through the existing gameplay attachment slot"
	)
	var articulated_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(second)
	_expect(
		articulated_manifest != null
		and articulated_manifest.contract_signature != first_manifest.contract_signature
		and articulated_manifest.control_count() == 8
		and articulated_manifest.observation_count() > first_manifest.observation_count(),
		"adding a controlled attachment changes the accepted model topology"
	)


func _test_regular_articulated_drone_limb() -> void:
	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	_expect(DroneTrainingLoadoutConfig.install_training_belly_grabber(loadout), "training articulated limb installs")
	var slots: PackedInt32Array = loadout.find_attachment_slots_with_capability(
		DroneTrainingLoadoutConfig.TRAINING_BELLY_GRABBER_CAPABILITY
	)
	_expect(slots.size() == 1, "training articulated limb occupies one normal attachment slot")
	if slots.size() != 1:
		return
	var attachment: DroneLimbAttachmentDefinition = loadout.get_attachment(slots[0]) as DroneLimbAttachmentDefinition
	_expect(
		attachment != null
		and attachment.limb_definitions.size() == 1
		and attachment.required_limb_action_count() == 4,
		"drone attachment hosts a regular GenericLimbDefinition with four authored controls"
	)
	if attachment == null or attachment.limb_definitions.is_empty():
		return
	var limb: GenericLimbDefinition = attachment.limb_definitions[0]
	var authored_shoulder_joint: LimbJointDefinition = limb.segments[0].joint
	var mounted_limbs: Array[GenericLimbDefinition] = attachment.mounted_limb_definitions(Vector3.ZERO)
	var mounted_limb: GenericLimbDefinition = mounted_limbs[0] if not mounted_limbs.is_empty() else null
	_expect(
		mounted_limb != null
		and mounted_limb != limb
		and mounted_limb.segments[0] != limb.segments[0]
		and mounted_limb.segments[0].joint != authored_shoulder_joint
		and mounted_limb.segments[0].joint.action_indices.x == 0
		and mounted_limb.segments[0].joint.action_indices.z == 1
		and authored_shoulder_joint.action_indices == Vector3i(-1, -1, -1),
		"runtime limb action packing cannot mutate nested Resources in the authored body part"
	)
	_expect(
		limb.segments.size() == 2
		and limb.segments[0].joint.axis_control_declared(0)
		and limb.segments[0].joint.axis_control_declared(2)
		and limb.segments[1].joint.axis_control_declared(2),
		"belly arm exposes shoulder X/Z and elbow Z through the standard joint definition"
	)
	_expect(
		limb.end_effector != null
		and limb.end_effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED
		and limb.end_effector.allow_static_grip
		and limb.end_effector.allow_dynamic_grip
		and limb.end_effector.compatible_surface_tags.has("climbable")
		and limb.end_effector.compatible_surface_tags.has("carryable"),
		"drone arm uses the same controlled wall/item grip contract as other generic limbs"
	)
	var manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(loadout)
	var frozen_attachment: DroneLimbAttachmentDefinition = null
	if manifest != null:
		for record: Dictionary in manifest.slot_records:
			if str(record.get("slot_id", "")) == "attachment_%d" % int(slots[0]):
				frozen_attachment = record.get("part") as DroneLimbAttachmentDefinition
				break
	_expect(
		frozen_attachment != null
		and frozen_attachment != attachment
		and frozen_attachment.limb_definitions[0] != limb
		and frozen_attachment.limb_definitions[0].segments[0] != limb.segments[0]
		and frozen_attachment.limb_definitions[0].segments[0].joint != authored_shoulder_joint,
		"accepted body manifest freezes nested limb arrays and joints, not only the top-level attachment"
	)
	var names: Array[String] = manifest.control_names() if manifest != null else []
	var prefix: String = "attachment_%d." % int(slots[0])
	_expect(
		names.has(prefix + "limb_0.segment_0.joint_x")
		and names.has(prefix + "limb_0.segment_0.joint_z")
		and names.has(prefix + "limb_0.segment_1.joint_z")
		and names.has(prefix + "limb_0.grip"),
		"accepted drone manifest exposes every regular limb actuator independently"
	)


func _test_arbitrary_generic_limb_topology() -> void:
	var source: GenericLimbDefinition = load(
		"res://resources/drones/attachments/training_belly_grabber/articulated_limb.tres"
	) as GenericLimbDefinition
	var three_segment: GenericLimbDefinition = MLBodyPartContract.deep_duplicate_resource(source) as GenericLimbDefinition
	var extra_segment: LimbSegmentDefinition = MLBodyPartContract.deep_duplicate_resource(source.segments[1]) as LimbSegmentDefinition
	three_segment.segments.append(extra_segment)
	three_segment.sanitize()
	var three_segment_source: Array[GenericLimbDefinition] = [three_segment]
	var source_array: Array[GenericLimbDefinition] = [source]
	var controls: Array[Dictionary] = GenericLimbModelContract.control_descriptors(three_segment_source)
	var observations: Array[Dictionary] = GenericLimbModelContract.observation_descriptors(three_segment_source)
	_expect(
		controls.size() == 5
		and str(controls[3].get("name", "")) == "limb_0.segment_2.joint_z"
		and str(controls[4].get("name", "")) == "limb_0.grip",
		"generic limb contract walks arbitrary segment counts instead of assuming two joints"
	)
	_expect(
		observations.size() > GenericLimbModelContract.observation_descriptors(source_array).size(),
		"additional limb segments automatically contribute their declared body observations"
	)


func _test_existing_limb_mapping_order() -> void:
	var source: GenericLimbDefinition = load(
		"res://resources/drones/attachments/training_belly_grabber/articulated_limb.tres"
	) as GenericLimbDefinition
	var limb: GenericLimbDefinition = MLBodyPartContract.deep_duplicate_resource(source) as GenericLimbDefinition
	limb.segments[0].joint.action_indices = Vector3i(1, -1, 0)
	limb.segments[1].joint.action_indices = Vector3i(-1, -1, 2)
	limb.end_effector.grip_action_index = 3
	var definitions: Array[GenericLimbDefinition] = [limb]
	var controls: Array[Dictionary] = GenericLimbModelContract.control_descriptors(definitions)
	_expect(
		controls.size() == 4
		and str(controls[0].get("name", "")) == "limb_0.segment_0.joint_z"
		and str(controls[1].get("name", "")) == "limb_0.segment_0.joint_x"
		and str(controls[2].get("name", "")) == "limb_0.segment_1.joint_z"
		and str(controls[3].get("name", "")) == "limb_0.grip",
		"generic body manifests preserve an existing limb profile's authored action order"
	)


func _test_turret_part_ownership() -> void:
	var manifest: MLBodyInterfaceManifest = TurretMLBodyInterfaceFactory.finalize_loadout(
		MLBodyPresetLibrary.stationary_turret_loadout()
	)
	_expect(
		manifest != null
		and manifest.control_names() == ["core.yaw", "gun.pitch", "gun.trigger"],
		"turret manifest assigns yaw to the Core and pitch/trigger to the equipped gun"
	)
	if manifest == null:
		return
	var routed_validation: Dictionary = MLBodyActionContract.validate({
		"body_interface_signature": manifest.contract_signature,
		"body_commands": PackedFloat64Array([0.25, -0.5, 0.75]),
	}, manifest)
	var routed: Dictionary = routed_validation.get("routed", {})
	var core_value: Variant = routed.get("core", PackedFloat64Array())
	var gun_value: Variant = routed.get("gun", PackedFloat64Array())
	var core_commands = PackedFloat64Array()
	var gun_commands = PackedFloat64Array()
	if core_value is PackedFloat64Array:
		core_commands = core_value
	if gun_value is PackedFloat64Array:
		gun_commands = gun_value
	_expect(
		bool(routed_validation.get("valid", false))
		and core_commands.size() == 1
		and is_equal_approx(core_commands[0], 0.25)
		and gun_commands.size() == 2
		and is_equal_approx(gun_commands[0], -0.5)
		and is_equal_approx(gun_commands[1], 0.75),
		"generic action routing treats Core controls and slot controls as equal manifest owners"
	)


func _test_input_vector_builder() -> void:
	var core = MLBodyCoreDefinition.new()
	var slot = MLBodySlotDefinition.new()
	slot.slot_id = &"prop"
	slot.slot_type = &"propeller"
	slot.accepted_part_tags.append(&"propeller")
	core.add_slot(slot)
	var draft = MLBodyBuildDraft.new()
	draft.configure_from_core(core, "generic_test")
	draft.equip(&"prop", DronePropellerDefinition.new())
	var manifest: MLBodyInterfaceManifest = draft.accept_build()
	var runtime_states: Dictionary = {
		"prop": {
			"installed": true,
			"realized_thrust_n": 2.0,
			"maximum_static_thrust_n": 4.0,
		}
	}
	var extra = PackedFloat64Array([0.25, -0.25])
	var vector: PackedFloat64Array = MLModelInputVectorBuilder.build(
		manifest,
		runtime_states,
		{},
		extra
	)
	_expect(
		vector.size() == extra.size() + manifest.observation_count()
		and is_equal_approx(vector[0], 0.25)
		and is_equal_approx(vector[1], -0.25),
		"model input builder appends accepted body observations after algorithm/task features"
	)
	var body_features: PackedFloat64Array = manifest.encode_body_observation(runtime_states, {})
	var preencoded_vector: PackedFloat64Array = MLModelInputVectorBuilder.combine_finalized(
		manifest, body_features, extra
	)
	_expect(
		preencoded_vector == vector,
		"all worker adapters can combine their already-captured body block through the same vector builder"
	)


func _test_body_action_routing() -> void:
	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(true)
	var manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(loadout)
	var commands = PackedFloat64Array()
	commands.resize(manifest.control_count())
	commands.fill(0.0)
	for index in range(4):
		commands[index] = 0.6
	var validation: Dictionary = MLBodyActionContract.validate({
		"body_interface_signature": manifest.contract_signature,
		"body_commands": commands,
	}, manifest)
	var routed: Dictionary = validation.get("routed", {})
	var attachment_commands: Variant = routed.get("attachment_0", PackedFloat64Array())
	_expect(
		bool(validation.get("valid", false))
		and routed.size() == 5
		and attachment_commands is PackedFloat64Array
		and attachment_commands.size() == 4,
		"generic body action router splits global outputs back into each physical slot's local controls"
	)
	var wrong_signature: Dictionary = MLBodyActionContract.validate({
		"body_interface_signature": "different-body",
		"body_commands": commands,
	}, manifest)
	_expect(
		not bool(wrong_signature.get("valid", true)),
		"actions finalized for another body topology fail closed before reaching physics"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
