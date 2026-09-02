@tool
class_name GunItemDefinition
extends ItemDefinition

#######################################################
# Defines the serialized gun item configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Firearm")
@export var default_build: GunBuild

@export_group("Presentation")
## Complete authored presentation for this particular weapon item. Modular/fabricated guns leave
## this empty and continue to use geometry assembled from their selected parts.
@export var authored_visual_scene: PackedScene

const BUILD_SIGNATURE_KEY := "build_signature"


func make_default_instance_state() -> Dictionary:
	if default_build == null:
		return {
			"build": {},
			BUILD_SIGNATURE_KEY: GunBuild.visual_signature_from_state({}),
			"rounds": 0,
		}
	var build_state := default_build.to_state_dict()
	return {
		"build": build_state,
		BUILD_SIGNATURE_KEY: GunBuild.visual_signature_from_state(build_state),
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
	if str(result.get(BUILD_SIGNATURE_KEY, "")).is_empty():
		result[BUILD_SIGNATURE_KEY] = GunBuild.visual_signature_from_state(
			SafeVariant.dictionary_copy(result.get("build", {}), false)
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
		BUILD_SIGNATURE_KEY: str(normalized.get(BUILD_SIGNATURE_KEY, "")),
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


func is_automatic(state: Dictionary) -> bool:
	var raw_build: Dictionary = state.get("build", {})
	if raw_build.is_empty():
		return default_build != null and default_build.is_automatic()
	var receiver_path := str(raw_build.get("receiver_path", ""))
	if receiver_path.is_empty():
		return false
	var receiver := load(receiver_path) as GunReceiverDefinition
	return receiver != null and receiver.automatic


func consume_round(state: Dictionary) -> Dictionary:
	return consume_rounds(state, 1)


func consume_rounds(state: Dictionary, count: int) -> Dictionary:
	var result := normalize_instance_state(state)
	result["rounds"] = maxi(
		int(result.get("rounds", 0)) - maxi(count, 0),
		0
	)
	return result


func refill_magazine(state: Dictionary) -> Dictionary:
	var result := normalize_instance_state(state)
	result["rounds"] = get_build(result).get_magazine_capacity()
	return result


func instantiate_visual() -> Node3D:
	return instantiate_visual_from_state(make_default_instance_state())


func instantiate_visual_from_state(state: Dictionary) -> Node3D:
	var visual_root: Node3D = _create_visual_root()
	visual_root.add_child(_instantiate_gun_visual(state))
	return visual_root


func instantiate_held_visual(
	state: Dictionary,
	_first_person := false
) -> Node3D:
	# Owner and observers render the same object at the same scale. Readability comes from the
	# anatomical hand pose, not from silently enlarging a camera-only copy.
	return _instantiate_gun_visual(state)


func _instantiate_gun_visual(state: Dictionary) -> Node3D:
	if authored_visual_scene != null:
		var authored := authored_visual_scene.instantiate() as Node3D
		if authored != null:
			return authored
	return GunGeometry.create_gun_visual(get_build(state), false)


func get_held_presentation_profile(state: Dictionary) -> StringName:
	var build := get_build(state)
	if (
		build != null
		and build.receiver != null
		and build.receiver.presentation_profile == ItemDefinition.HELD_PROFILE_RIFLE
	):
		return ItemDefinition.HELD_PROFILE_RIFLE
	return ItemDefinition.HELD_PROFILE_PISTOL
