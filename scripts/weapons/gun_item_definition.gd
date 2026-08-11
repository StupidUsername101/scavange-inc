@tool
class_name GunItemDefinition
extends ItemDefinition

#######################################################
# Defines the serialized gun item configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Firearm")
@export var default_build: GunBuild


func make_default_instance_state() -> Dictionary:
	if default_build == null:
		return {
			"build": {},
			"rounds": 0,
		}
	return {
		"build": default_build.to_state_dict(),
		"rounds": default_build.get_magazine_capacity(),
	}


func normalize_instance_state(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	if not result.has("build"):
		result["build"] = (
			default_build.to_state_dict()
			if default_build != null
			else {}
		)
	var build := get_build(result)
	result["rounds"] = clampi(
		int(result.get("rounds", build.get_magazine_capacity())),
		0,
		build.get_magazine_capacity()
	)
	return result


func get_public_instance_state(state: Dictionary) -> Dictionary:
	var normalized := normalize_instance_state(state)
	var build := get_build(normalized)
	return {
		"build": build.to_state_dict(),
		"rounds": int(normalized.get("rounds", 0)),
		"magazine_capacity": build.get_magazine_capacity(),
		"build_valid": build.is_compatible(),
		"status_text": "%d" % int(normalized.get("rounds", 0)),
	}


func get_inventory_status_text(state: Dictionary) -> String:
	return str(get_public_instance_state(state).get("status_text", ""))


func get_instance_mass(state: Dictionary) -> float:
	var build_mass := get_build(normalize_instance_state(state)).get_total_mass()
	return maxf(build_mass if build_mass > 0.0 else mass, 0.01)


func get_build(state: Dictionary) -> GunBuild:
	var build := GunBuild.new()
	var raw_build: Dictionary = state.get("build", {})
	if raw_build.is_empty() and default_build != null:
		raw_build = default_build.to_state_dict()
	build.apply_state_dict(raw_build)
	return build


func get_ballistic_profile(state: Dictionary) -> Dictionary:
	return get_build(normalize_instance_state(state)).get_ballistic_profile()


func consume_round(state: Dictionary) -> Dictionary:
	var result := normalize_instance_state(state)
	result["rounds"] = maxi(int(result.get("rounds", 0)) - 1, 0)
	return result


func refill_magazine(state: Dictionary) -> Dictionary:
	var result := normalize_instance_state(state)
	result["rounds"] = get_build(result).get_magazine_capacity()
	return result


func instantiate_visual() -> Node3D:
	return instantiate_visual_from_state(make_default_instance_state())


func instantiate_visual_from_state(state: Dictionary) -> Node3D:
	var visual_root: Node3D = _create_visual_root()
	visual_root.add_child(
		GunGeometry.create_gun_visual(get_build(state))
	)
	return visual_root


func instantiate_held_visual(
	state: Dictionary,
	first_person := false
) -> Node3D:
	return GunGeometry.create_gun_visual(get_build(state), first_person)
