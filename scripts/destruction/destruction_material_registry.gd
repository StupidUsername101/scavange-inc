class_name DestructionMaterialRegistry
extends RefCounted

const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")

static var _profiles: Dictionary[StringName, DestructionTextureDefinition] = {}


static func profile_for(surface_value: Variant) -> DestructionTextureDefinition:
	_ensure_defaults()
	var surface := PHYSICAL_SURFACE.normalize(surface_value)
	return _profiles.get(surface, _profiles[PHYSICAL_SURFACE.CONCRETE])


static func register_profile(profile: DestructionTextureDefinition) -> bool:
	if profile == null:
		return false
	profile.sanitize()
	_profiles[profile.physical_surface] = profile
	return true


static func clear_for_tests() -> void:
	_profiles.clear()


static func _ensure_defaults() -> void:
	if not _profiles.is_empty():
		return
	register_profile(_concrete())
	register_profile(_metal())
	register_profile(_wood())
	register_profile(_stone())
	register_profile(_soil())


static func _base(
	id: StringName,
	material_index: int,
	exterior: Color,
	interior: Color
) -> DestructionTextureDefinition:
	var profile := DestructionTextureDefinition.new()
	profile.texture_id = id
	profile.physical_surface = id
	profile.material_index = material_index
	profile.exterior_color = exterior
	profile.interior_color = interior
	return profile


static func _concrete() -> DestructionTextureDefinition:
	var profile := _base(
		PHYSICAL_SURFACE.CONCRETE,
		1,
		Color(0.34, 0.36, 0.34),
		Color(0.20, 0.19, 0.17)
	)
	profile.energy_resistance = 1.0
	profile.geometry_threshold = 0.65
	profile.perforation_threshold = 2.4
	profile.hardness = 0.78
	profile.fracture_toughness = 0.28
	profile.support_strength = 0.52
	profile.ductility = 0.02
	profile.entry_radius_scale = 1.25
	profile.exit_spall_radius_scale = 2.0
	profile.crack_count = 4
	profile.spatial_warp = 0.18
	profile.fragment_density_kg_m3 = 2200.0
	return profile.sanitize()


static func _metal() -> DestructionTextureDefinition:
	var profile := _base(
		PHYSICAL_SURFACE.METAL,
		2,
		Color(0.23, 0.27, 0.28),
		Color(0.12, 0.14, 0.15)
	)
	profile.energy_resistance = 1.8
	profile.geometry_threshold = 0.8
	profile.perforation_threshold = 4.2
	profile.hardness = 0.9
	profile.fracture_toughness = 0.82
	profile.support_strength = 0.92
	profile.ductility = 0.86
	profile.damage_accumulation = 0.85
	profile.entry_radius_scale = 0.62
	profile.channel_radius_scale = 0.48
	profile.exit_spall_radius_scale = 0.35
	profile.dent_depth_scale = 0.55
	profile.crack_count = 0
	profile.spatial_warp = 0.035
	profile.maximum_physical_fragments = 2
	profile.fragment_density_kg_m3 = 7850.0
	profile.metallic = 0.85
	profile.roughness = 0.42
	return profile.sanitize()


static func _wood() -> DestructionTextureDefinition:
	var profile := _base(
		PHYSICAL_SURFACE.WOOD,
		3,
		Color(0.32, 0.20, 0.10),
		Color(0.22, 0.11, 0.045)
	)
	profile.energy_resistance = 0.62
	profile.geometry_threshold = 0.45
	profile.perforation_threshold = 1.35
	profile.hardness = 0.38
	profile.fracture_toughness = 0.38
	profile.support_strength = 0.64
	profile.ductility = 0.12
	profile.entry_radius_scale = 0.85
	profile.channel_radius_scale = 0.72
	profile.crack_count = 5
	profile.crack_length_scale = 2.6
	profile.crack_width_scale = 0.07
	profile.anisotropy = 0.82
	profile.grain_axis = Vector3.UP
	profile.spatial_warp = 0.12
	profile.fragment_density_kg_m3 = 650.0
	return profile.sanitize()


static func _stone() -> DestructionTextureDefinition:
	var profile := _base(
		PHYSICAL_SURFACE.STONE,
		4,
		Color(0.30, 0.31, 0.33),
		Color(0.18, 0.18, 0.19)
	)
	profile.energy_resistance = 1.25
	profile.geometry_threshold = 0.8
	profile.perforation_threshold = 2.8
	profile.hardness = 0.84
	profile.fracture_toughness = 0.22
	profile.support_strength = 0.44
	profile.ductility = 0.0
	profile.entry_radius_scale = 1.05
	profile.exit_spall_radius_scale = 1.35
	profile.crack_count = 4
	profile.spatial_warp = 0.14
	profile.fragment_density_kg_m3 = 2650.0
	return profile.sanitize()


static func _soil() -> DestructionTextureDefinition:
	var profile := _base(
		PHYSICAL_SURFACE.SOIL,
		5,
		Color(0.20, 0.18, 0.11),
		Color(0.14, 0.12, 0.075)
	)
	profile.energy_resistance = 0.35
	profile.geometry_threshold = 0.25
	profile.perforation_threshold = 0.35
	profile.hardness = 0.08
	profile.fracture_toughness = 0.15
	profile.support_strength = 0.18
	profile.ductility = 0.62
	profile.entry_radius_scale = 1.45
	profile.channel_radius_scale = 1.1
	profile.exit_spall_radius_scale = 0.0
	profile.dent_depth_scale = 0.9
	profile.crack_count = 0
	profile.spatial_warp = 0.22
	profile.maximum_physical_fragments = 0
	profile.fragment_density_kg_m3 = 1500.0
	return profile.sanitize()
