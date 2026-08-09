@tool
class_name GunBuild
extends Resource

#######################################################
# Composes compatible gun components into validated runtime firearm statistics and persistent
# item state.
#######################################################

@export var receiver: GunReceiverDefinition
@export var barrel: GunBarrelDefinition
@export var magazine: GunMagazineDefinition
@export var ammunition: GunAmmunitionDefinition


func install_part(part: GunPartDefinition) -> bool:
	if part == null:
		return false
	match part.part_slot:
		GunPartDefinition.PartSlot.RECEIVER:
			if not part is GunReceiverDefinition:
				return false
			receiver = part as GunReceiverDefinition
		GunPartDefinition.PartSlot.BARREL:
			if not part is GunBarrelDefinition:
				return false
			barrel = part as GunBarrelDefinition
		GunPartDefinition.PartSlot.MAGAZINE:
			if not part is GunMagazineDefinition:
				return false
			magazine = part as GunMagazineDefinition
		GunPartDefinition.PartSlot.AMMUNITION:
			if not part is GunAmmunitionDefinition:
				return false
			ammunition = part as GunAmmunitionDefinition
		_:
			return false
	return true


func remove_part(slot: GunPartDefinition.PartSlot) -> GunPartDefinition:
	var removed := get_part(slot)
	match slot:
		GunPartDefinition.PartSlot.RECEIVER:
			receiver = null
		GunPartDefinition.PartSlot.BARREL:
			barrel = null
		GunPartDefinition.PartSlot.MAGAZINE:
			magazine = null
		GunPartDefinition.PartSlot.AMMUNITION:
			ammunition = null
	return removed


func get_part(slot: GunPartDefinition.PartSlot) -> GunPartDefinition:
	match slot:
		GunPartDefinition.PartSlot.RECEIVER:
			return receiver
		GunPartDefinition.PartSlot.BARREL:
			return barrel
		GunPartDefinition.PartSlot.MAGAZINE:
			return magazine
		GunPartDefinition.PartSlot.AMMUNITION:
			return ammunition
	return null


func is_complete() -> bool:
	return (
		receiver != null
		and barrel != null
		and magazine != null
		and ammunition != null
		and ammunition.projectile != null
	)


func is_compatible() -> bool:
	if not is_complete() or receiver.caliber_id == &"":
		return false
	return (
		barrel.caliber_id == receiver.caliber_id
		and magazine.caliber_id == receiver.caliber_id
		and ammunition.caliber_id == receiver.caliber_id
	)


func get_compatibility_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if receiver == null:
		errors.append("receiver missing")
	if barrel == null:
		errors.append("barrel missing")
	if magazine == null:
		errors.append("magazine missing")
	if ammunition == null:
		errors.append("ammunition missing")
	elif ammunition.projectile == null:
		errors.append("projectile definition missing")
	if receiver == null:
		return errors
	for component_value: Variant in [barrel, magazine, ammunition]:
		var component := component_value as GunPartDefinition
		if component != null and component.caliber_id != receiver.caliber_id:
			errors.append("%s caliber mismatch" % component.display_name)
	return errors


func get_ballistic_profile() -> Dictionary:
	if not is_compatible():
		return {}
	var profile := ammunition.projectile.to_ballistic_profile()
	profile["damage"] = (
		float(profile["damage"])
		* receiver.damage_multiplier
		* barrel.damage_multiplier
	)
	profile["muzzle_velocity"] = (
		float(profile["muzzle_velocity"])
		* barrel.velocity_multiplier
	)
	profile["maximum_range"] = (
		float(profile["maximum_range"])
		* barrel.range_multiplier
	)
	profile["rounds_per_second"] = maxf(
		receiver.rounds_per_second,
		0.1
	)
	profile["spread_degrees"] = maxf(
		receiver.base_spread_degrees * barrel.spread_multiplier,
		0.0
	)
	return BallisticProjectileDefinition.normalize_profile(profile)


func get_magazine_capacity() -> int:
	return maxi(magazine.capacity, 1) if magazine != null else 0


func get_reload_seconds() -> float:
	if receiver == null or magazine == null:
		return 0.0
	return maxf(
		receiver.reload_seconds * magazine.reload_time_multiplier,
		0.05
	)


func get_total_mass() -> float:
	var result := 0.0
	for component_value: Variant in [
		receiver,
		barrel,
		magazine,
		ammunition,
	]:
		var component := component_value as GunPartDefinition
		if component != null:
			result += component.mass
	return result


func to_state_dict() -> Dictionary:
	return {
		"receiver_path": _resource_path(receiver),
		"barrel_path": _resource_path(barrel),
		"magazine_path": _resource_path(magazine),
		"ammunition_path": _resource_path(ammunition),
	}


func apply_state_dict(state: Dictionary) -> void:
	var receiver_path := str(state.get("receiver_path", ""))
	var barrel_path := str(state.get("barrel_path", ""))
	var magazine_path := str(state.get("magazine_path", ""))
	var ammunition_path := str(state.get("ammunition_path", ""))
	receiver = (
		load(receiver_path) as GunReceiverDefinition
		if not receiver_path.is_empty()
		else null
	)
	barrel = (
		load(barrel_path) as GunBarrelDefinition
		if not barrel_path.is_empty()
		else null
	)
	magazine = (
		load(magazine_path) as GunMagazineDefinition
		if not magazine_path.is_empty()
		else null
	)
	ammunition = (
		load(ammunition_path) as GunAmmunitionDefinition
		if not ammunition_path.is_empty()
		else null
	)


static func _resource_path(resource: Resource) -> String:
	return resource.resource_path if resource != null else ""
