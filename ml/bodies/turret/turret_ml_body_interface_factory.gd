class_name TurretMLBodyInterfaceFactory
extends RefCounted

#######################################################
# Adapts the existing turret Base + Gun gameplay loadout into the common Core/slot manifest.
# The base is the actual Core, not a synthetic slot: yaw therefore becomes a Core channel while
# pitch/trigger belong to the gun attachment. Model channels always follow their physical owner.
#######################################################


static func create_draft(loadout: TurretLoadout) -> MLBodyBuildDraft:
	var draft = MLBodyBuildDraft.new()
	if loadout == null:
		draft.last_error = "A turret model body requires a loadout."
		return draft
	if not loadout.ensure_contract():
		draft.last_error = "A turret model body requires both a base Core and a gun attachment."
		return draft
	draft.set_core(loadout.base, {
		"body_kind": "turret",
		"body_profile_id": TurretPhysicalBody3D.BODY_PROFILE_ID,
	})
	var gun_slot = MLBodySlotDefinition.new()
	gun_slot.slot_id = &"gun"
	gun_slot.display_name = "Gun"
	gun_slot.slot_type = &"gun"
	gun_slot.accepted_part_tags.append(&"gun")
	if not draft.add_slot(gun_slot, loadout.gun):
		return draft
	return draft


static func finalize_loadout(loadout: TurretLoadout) -> MLBodyInterfaceManifest:
	var draft: MLBodyBuildDraft = create_draft(loadout)
	if not draft.last_error.is_empty():
		return null
	return draft.accept_build()


static func runtime_states(turret: TurretPhysicalBody3D) -> Dictionary:
	if not is_instance_valid(turret) or turret.loadout == null:
		return {}
	return {
		"core": {
			"yaw_angle_radians": turret.yaw_angle_radians,
			"yaw_velocity_radians_per_second": turret.yaw_velocity_radians_per_second,
		},
		"gun": {
			"pitch_angle_radians": turret.pitch_angle_radians,
			"pitch_velocity_radians_per_second": turret.pitch_velocity_radians_per_second,
			"shot_cooldown_seconds": turret.shot_cooldown_seconds,
		},
	}
