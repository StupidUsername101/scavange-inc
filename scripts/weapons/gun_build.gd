@tool
class_name GunBuild
extends Resource

#######################################################
# Composes compatible gun components into validated runtime firearm statistics and persistent
# item state.
#######################################################

@export var receiver: GunReceiverDefinition
@export var barrel: GunBarrelDefinition
## Extra barrels preserve the original single-barrel resource field while allowing
## crafted weapons to repeat the barrel lane without imposing a weapon silhouette.
@export var additional_barrels: Array[GunBarrelDefinition] = []
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


func add_barrel(next_barrel: GunBarrelDefinition) -> bool:
	if next_barrel == null:
		return false
	if barrel == null:
		barrel = next_barrel
	else:
		additional_barrels.append(next_barrel)
	return true


func set_barrels(next_barrels: Array[GunBarrelDefinition]) -> void:
	barrel = null
	additional_barrels.clear()
	for next_barrel: GunBarrelDefinition in next_barrels:
		add_barrel(next_barrel)


func get_barrels() -> Array[GunBarrelDefinition]:
	var result: Array[GunBarrelDefinition] = []
	if barrel != null:
		result.append(barrel)
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		if extra_barrel != null:
			result.append(extra_barrel)
	return result


func get_barrel_count() -> int:
	var result := 1 if barrel != null else 0
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		if extra_barrel != null:
			result += 1
	return result


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
		and get_barrel_count() > 0
		and magazine != null
		and ammunition != null
		and ammunition.projectile != null
	)


func is_compatible() -> bool:
	if not is_complete() or receiver.caliber_id == &"":
		return false
	if magazine.caliber_id != receiver.caliber_id:
		return false
	if ammunition.caliber_id != receiver.caliber_id:
		return false
	if barrel != null and barrel.caliber_id != receiver.caliber_id:
		return false
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		if extra_barrel != null and extra_barrel.caliber_id != receiver.caliber_id:
			return false
	return true


func get_compatibility_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if receiver == null:
		errors.append("receiver missing")
	if get_barrel_count() == 0:
		errors.append("barrel missing")
	if magazine == null:
		errors.append("magazine missing")
	if ammunition == null:
		errors.append("ammunition missing")
	elif ammunition.projectile == null:
		errors.append("projectile definition missing")
	if receiver == null:
		return errors
	_append_caliber_error(errors, barrel)
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		_append_caliber_error(errors, extra_barrel)
	_append_caliber_error(errors, magazine)
	_append_caliber_error(errors, ammunition)
	return errors


func _append_caliber_error(
	errors: PackedStringArray,
	component: GunPartDefinition
) -> void:
	if component != null and component.caliber_id != receiver.caliber_id:
		var message := "%s caliber mismatch" % component.display_name
		if not errors.has(message):
			errors.append(message)


func get_ballistic_profile() -> Dictionary:
	var profiles := get_ballistic_profiles()
	if profiles.is_empty():
		return {}
	var profile: Dictionary = profiles[0].duplicate(true)
	profile["barrel_count"] = profiles.size()
	return profile


func get_ballistic_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_compatible():
		return result
	if barrel != null:
		result.append(_get_ballistic_profile_for_barrel(barrel))
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		if extra_barrel != null:
			result.append(_get_ballistic_profile_for_barrel(extra_barrel))
	return result


func _get_ballistic_profile_for_barrel(
	installed_barrel: GunBarrelDefinition
) -> Dictionary:
	var profile := ammunition.projectile.to_ballistic_profile()
	profile["damage"] = (
		float(profile["damage"])
		* receiver.damage_multiplier
		* installed_barrel.damage_multiplier
	)
	profile["muzzle_velocity"] = (
		float(profile["muzzle_velocity"])
		* installed_barrel.velocity_multiplier
	)
	profile["maximum_range"] = (
		float(profile["maximum_range"])
		* installed_barrel.range_multiplier
	)
	profile["rounds_per_second"] = maxf(
		receiver.rounds_per_second,
		0.1
	)
	profile["spread_degrees"] = maxf(
		receiver.base_spread_degrees * installed_barrel.spread_multiplier,
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


func is_automatic() -> bool:
	return receiver != null and receiver.automatic


func get_reload_sound_id(insert: bool) -> StringName:
	if receiver == null:
		return &""
	return (
		receiver.reload_in_sound_id
		if insert
		else receiver.reload_out_sound_id
	)


func get_fire_sound_profile() -> Dictionary:
	if receiver == null or receiver.fire_sound_id.is_empty():
		return {}
	return {
		"sound_id": receiver.fire_sound_id,
		"max_distance": clampf(receiver.fire_sound_max_distance, 0.1, 10000.0),
		"volume_db": clampf(receiver.fire_sound_volume_db, -60.0, 18.0),
		"priority": clampf(receiver.fire_sound_priority, 0.0, 1.0),
		"pressure_strength": clampf(receiver.fire_pressure_strength, -1.0, 1.0),
	}


func get_total_mass() -> float:
	var result := 0.0
	for component_value: Variant in [
		receiver,
		magazine,
		ammunition,
	]:
		var component := component_value as GunPartDefinition
		if component != null:
			result += component.mass
	if barrel != null:
		result += barrel.mass
	for extra_barrel: GunBarrelDefinition in additional_barrels:
		if extra_barrel != null:
			result += extra_barrel.mass
	return result


func to_state_dict() -> Dictionary:
	var barrel_paths: Array[String] = []
	for installed_barrel: GunBarrelDefinition in get_barrels():
		barrel_paths.append(_resource_path(installed_barrel))
	return {
		"receiver_path": _resource_path(receiver),
		# Keep the legacy primary path for old saves and tools while the ordered
		# collection is the canonical representation for new crafted builds.
		"barrel_path": _resource_path(barrel),
		"barrel_paths": barrel_paths,
		"magazine_path": _resource_path(magazine),
		"ammunition_path": _resource_path(ammunition),
	}


func visual_signature() -> String:
	return visual_signature_from_state(to_state_dict())


static func visual_signature_from_state(state: Dictionary) -> String:
	var barrel_paths := PackedStringArray()
	var barrel_paths_value: Variant = state.get("barrel_paths", [])
	if barrel_paths_value is Array:
		for path_value: Variant in barrel_paths_value as Array:
			var path := str(path_value)
			if not path.is_empty():
				barrel_paths.append(path)
	if barrel_paths.is_empty():
		var legacy_barrel_path := str(state.get("barrel_path", ""))
		if not legacy_barrel_path.is_empty():
			barrel_paths.append(legacy_barrel_path)
	return "receiver=%s|barrels=%s|magazine=%s|ammunition=%s" % [
		str(state.get("receiver_path", "")),
		",".join(barrel_paths),
		str(state.get("magazine_path", "")),
		str(state.get("ammunition_path", "")),
	]


func apply_state_dict(state: Dictionary) -> void:
	var receiver_path := str(state.get("receiver_path", ""))
	var magazine_path := str(state.get("magazine_path", ""))
	var ammunition_path := str(state.get("ammunition_path", ""))
	receiver = (
		load(receiver_path) as GunReceiverDefinition
		if not receiver_path.is_empty()
		else null
	)
	var next_barrels: Array[GunBarrelDefinition] = []
	var barrel_paths_value: Variant = state.get("barrel_paths", [])
	if barrel_paths_value is Array:
		for path_value: Variant in barrel_paths_value as Array:
			var barrel_path := str(path_value)
			if barrel_path.is_empty():
				continue
			var loaded_barrel := load(barrel_path) as GunBarrelDefinition
			if loaded_barrel != null:
				next_barrels.append(loaded_barrel)
	if next_barrels.is_empty():
		var legacy_barrel_path := str(state.get("barrel_path", ""))
		if not legacy_barrel_path.is_empty():
			var legacy_barrel := load(
				legacy_barrel_path
			) as GunBarrelDefinition
			if legacy_barrel != null:
				next_barrels.append(legacy_barrel)
	set_barrels(next_barrels)
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
