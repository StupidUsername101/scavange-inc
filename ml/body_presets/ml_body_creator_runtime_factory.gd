class_name MLBodyCreatorRuntimeFactory
extends RefCounted

#######################################################
# Bridges an accepted generic creator draft back into the gameplay body resource used by each
# existing trainer. This is deliberately the only body-family switch in the creator path; the UI
# itself remains generic and only knows Core + typed slots + parts.
#######################################################

static var last_error: String = ""


static func runtime_from_draft(
	preset_id: StringName,
	draft: MLBodyBuildDraft,
	changed_slot_ids: Dictionary = {}
) -> Resource:
	last_error = ""
	if draft == null or draft.core == null:
		return _fail("The creator draft has no Core.")
	var body_kind: String = str(draft.core_contract.get("body_kind", "")).strip_edges()
	match body_kind:
		"drone":
			return _drone_loadout(draft)
		"turret":
			return _turret_loadout(draft)
		"articulated_body":
			return _four_limb_definition(preset_id, draft, changed_slot_ids)
	return _fail("Body kind '%s' does not have a training runtime adapter yet." % body_kind)


static func runtime_manifest(runtime_body: Resource) -> MLBodyInterfaceManifest:
	if runtime_body is DroneLoadout:
		return DroneMLBodyInterfaceFactory.finalize_loadout(runtime_body as DroneLoadout)
	if runtime_body is TurretLoadout:
		return TurretMLBodyInterfaceFactory.finalize_loadout(runtime_body as TurretLoadout)
	if runtime_body is FourLimbBodyDefinition:
		var draft: MLBodyBuildDraft = FourLimbMLBodyInterfaceFactory.create_definition_draft(
			runtime_body as FourLimbBodyDefinition
		)
		return draft.accept_build() if draft != null and draft.last_error.is_empty() else null
	return null


static func _drone_loadout(draft: MLBodyBuildDraft) -> DroneLoadout:
	var physical_core: DroneCoreDefinition = draft.core as DroneCoreDefinition
	if physical_core == null:
		var model_core: MLBodyCoreDefinition = draft.core as MLBodyCoreDefinition
		if model_core != null:
			physical_core = model_core.physical_core as DroneCoreDefinition
	if physical_core == null:
		return _fail("The selected drone body does not contain a DroneCoreDefinition.") as DroneLoadout
	var result: DroneLoadout = DroneLoadout.new()
	result.install_core(
		MLBodyPartContract.deep_duplicate_resource(physical_core) as DroneCoreDefinition
	)
	for entry: Dictionary in draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			continue
		var part: Resource = entry.get("part") as Resource
		var slot_id: String = str(slot.slot_id)
		match str(slot.slot_type):
			"battery":
				if part != null and not (part is DroneBatteryDefinition):
					return _fail("%s requires a drone battery." % slot.display_name) as DroneLoadout
				result.install_battery(
					MLBodyPartContract.deep_duplicate_resource(part) as DroneBatteryDefinition
				)
			"propeller":
				if not (part is DronePropellerDefinition):
					return _fail("%s requires a propeller." % slot.display_name) as DroneLoadout
				var propeller_index: int = _slot_suffix_index(slot_id)
				if propeller_index < 0 or not result.set_propeller_slot_transform(
					propeller_index,
					slot.mount_transform
				):
					return _fail("Could not apply the mount transform for %s." % slot.display_name) as DroneLoadout
				if not result.install_propeller(
					propeller_index,
					MLBodyPartContract.deep_duplicate_resource(part) as DronePropellerDefinition
				):
					return _fail("Could not install %s." % slot.display_name) as DroneLoadout
			"attachment":
				var attachment_index: int = _slot_suffix_index(slot_id)
				if attachment_index < 0 or not result.set_attachment_slot_transform(
					attachment_index,
					slot.mount_transform
				):
					return _fail("Could not apply the mount transform for %s." % slot.display_name) as DroneLoadout
				if part == null:
					result.remove_attachment(attachment_index)
				elif not (part is DroneAttachmentDefinition) or not result.install_attachment(
					attachment_index,
					MLBodyPartContract.deep_duplicate_resource(part) as DroneAttachmentDefinition
				):
					return _fail("Could not install %s." % slot.display_name) as DroneLoadout
	if result.battery == null:
		return _fail("A training drone needs a battery.") as DroneLoadout
	for index: int in range(result.core.propeller_slot_count):
		if result.get_propeller(index) == null:
			return _fail("Every training drone propeller slot must be filled.") as DroneLoadout
	return result


static func _turret_loadout(draft: MLBodyBuildDraft) -> TurretLoadout:
	var physical_base: TurretBaseDefinition = draft.core as TurretBaseDefinition
	if physical_base == null:
		var model_core: MLBodyCoreDefinition = draft.core as MLBodyCoreDefinition
		if model_core != null:
			physical_base = model_core.physical_core as TurretBaseDefinition
	if physical_base == null:
		return _fail("The selected turret body does not contain a turret base Core.") as TurretLoadout
	var gun: Resource = draft.equipped_part(&"gun")
	if not (gun is TurretGunDefinition):
		return _fail("A stationary turret requires a gun part.") as TurretLoadout
	var result: TurretLoadout = TurretLoadout.new()
	result.base = MLBodyPartContract.deep_duplicate_resource(physical_base) as TurretBaseDefinition
	result.gun = MLBodyPartContract.deep_duplicate_resource(gun) as TurretGunDefinition
	if not result.ensure_contract():
		return _fail("The selected turret parts do not form a valid loadout.") as TurretLoadout
	return result


static func _four_limb_definition(
	preset_id: StringName,
	draft: MLBodyBuildDraft,
	changed_slot_ids: Dictionary
) -> FourLimbBodyDefinition:
	var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(preset_id)
	var result: FourLimbBodyDefinition = null
	if preset != null:
		result = preset.runtime_template_copy() as FourLimbBodyDefinition
	if result == null:
		return _fail("The articulated body preset has no four-limb runtime template.") as FourLimbBodyDefinition
	for entry: Dictionary in draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			continue
		var slot_id: String = str(slot.slot_id)
		if not changed_slot_ids.has(slot_id):
			continue
		var part: Resource = entry.get("part") as Resource
		if str(slot.slot_type) == "attachment":
			if part != null:
				return _fail(
					"Four-limb Core attachment slots are visible, but runtime attachment installation is not wired into this trainer yet."
				) as FourLimbBodyDefinition
			continue
		if str(slot.slot_type) != "limb":
			continue
		var limb_index: int = _slot_suffix_index(slot_id)
		if limb_index < 0 or limb_index >= result.limbs.size():
			return _fail("Unknown articulated limb slot %s." % slot_id) as FourLimbBodyDefinition
		if not (part is GenericLimbDefinition):
			return _fail("%s requires a generic limb definition." % slot.display_name) as FourLimbBodyDefinition
		if not _apply_generic_limb(result.limbs[limb_index], part as GenericLimbDefinition):
			return null
	result.ensure_contract()
	return result


static func _apply_generic_limb(
	target: FourLimbSlotDefinition,
	part: GenericLimbDefinition
) -> bool:
	if target == null or part == null or part.segments.size() != 2:
		_fail("The current four-limb runtime requires two-segment limb parts.")
		return false
	var upper: LimbSegmentDefinition = part.segments[0]
	var lower: LimbSegmentDefinition = part.segments[1]
	if upper == null or lower == null or upper.joint == null or lower.joint == null:
		_fail("The selected limb is missing one of its saved segment/joint definitions.")
		return false
	target.installed = part.installed
	target.hip_offset = part.mount_offset_local
	target.upper_length = upper.length
	target.lower_length = lower.length
	target.segment_radius = maxf((upper.radius + lower.radius) * 0.5, 0.02)
	target.segment_mass = maxf((upper.mass + lower.mass) * 0.5, 0.01)
	target.maximum_health = maxf(minf(upper.maximum_health, lower.maximum_health), 0.1)
	var upper_direction: Vector3 = upper.rest_direction_local.normalized()
	var lower_direction: Vector3 = lower.rest_direction_local.normalized()
	if upper_direction.length_squared() <= 0.000001:
		upper_direction = Vector3.DOWN
	if lower_direction.length_squared() <= 0.000001:
		lower_direction = Vector3.DOWN
	target.rest_foot_offset = (
		target.hip_offset
		+ upper_direction * target.upper_length
		+ lower_direction * target.lower_length
	)
	target.end_effector = (
		MLBodyPartContract.deep_duplicate_resource(part.end_effector) as LimbEndEffectorDefinition
		if part.end_effector != null
		else null
	)
	var hip: LimbJointDefinition = upper.joint
	var knee: LimbJointDefinition = lower.joint
	target.hip_twist_span_degrees = clampf(
		maxf(absf(hip.lower_limit_degrees.x), absf(hip.upper_limit_degrees.x)),
		1.0,
		90.0
	)
	target.hip_swing_span_degrees = clampf(absf(hip.lower_limit_degrees.z), 1.0, 90.0)
	target.hip_elevation_upper_extension_degrees = clampf(
		maxf(hip.upper_limit_degrees.z - target.hip_swing_span_degrees, 0.0),
		0.0,
		60.0
	)
	target.knee_limit_lower_degrees = clampf(knee.lower_limit_degrees.z, -20.0, -1.0)
	target.knee_limit_upper_degrees = clampf(knee.upper_limit_degrees.z, 15.0, 120.0)
	target.sanitize_joint_limits()
	return true


static func _slot_suffix_index(slot_id: String) -> int:
	var separator: int = slot_id.rfind("_")
	if separator < 0 or separator >= slot_id.length() - 1:
		return -1
	var suffix: String = slot_id.substr(separator + 1)
	return int(suffix) if suffix.is_valid_int() else -1


static func _fail(message: String) -> Resource:
	last_error = message
	return null
