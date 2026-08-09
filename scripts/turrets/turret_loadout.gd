@tool
class_name TurretLoadout
extends Resource

@export var base: TurretBaseDefinition
@export var gun: TurretGunDefinition


func ensure_contract() -> bool:
	# Runtime loadouts are no longer allowed to invent a stock body. A complete turret body
	# comes from an accepted creator build or an explicit MLBodyPresetLibrary preset.
	if base == null or gun == null:
		return false
	base.sanitize()
	gun.sanitize()
	return true


func total_mass_kg() -> float:
	if not ensure_contract():
		return 0.0
	return base.mass_kg + gun.mass_kg


func maximum_health() -> float:
	if not ensure_contract():
		return 0.0
	return base.maximum_health + gun.maximum_health


func hardware_signature() -> String:
	if not ensure_contract():
		return ""
	return "stationary_turret_v1:%s:%s" % [
		base.hardware_signature_fragment(),
		gun.hardware_signature_fragment(),
	]


func to_dictionary() -> Dictionary:
	if not ensure_contract():
		return {}
	return {
		"base": base.to_dictionary(),
		"gun": gun.to_dictionary(),
	}


static func from_dictionary(value: Dictionary) -> TurretLoadout:
	var result = TurretLoadout.new()
	var base_value: Variant = value.get("base", null)
	var gun_value: Variant = value.get("gun", null)
	if base_value is Dictionary and not (base_value as Dictionary).is_empty():
		result.base = TurretBaseDefinition.from_dictionary(base_value)
	if gun_value is Dictionary and not (gun_value as Dictionary).is_empty():
		result.gun = TurretGunDefinition.from_dictionary(gun_value)
	result.ensure_contract()
	return result
