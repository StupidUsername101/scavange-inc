@tool
class_name DestructionTextureDefinition
extends Resource

## Authored spatial response of a material. It is called a destruction texture because it controls
## the shape and character of damage, not only the amount of health removed.

@export_group("Identity")
@export var texture_id := &"concrete"
@export var physical_surface := &"concrete"
@export_range(1, 255, 1) var material_index := 1
@export_range(1, 65535, 1) var profile_version := 1

@export_group("Resistance")
@export_range(0.01, 1000.0, 0.01, "or_greater") var energy_resistance := 1.0
@export_range(0.0, 1000.0, 0.01, "or_greater") var geometry_threshold := 1.0
@export_range(0.0, 1000.0, 0.01, "or_greater") var perforation_threshold := 3.0
@export_range(0.0, 1.0, 0.01) var hardness := 0.75
@export_range(0.0, 1.0, 0.01) var fracture_toughness := 0.45
@export_range(0.0, 1.0, 0.01) var ductility := 0.05
@export_range(0.0, 2.0, 0.01, "or_greater") var damage_accumulation := 0.4

@export_group("Damage Shape")
@export_range(0.05, 4.0, 0.01, "or_greater") var entry_radius_scale := 1.0
@export_range(0.05, 8.0, 0.01, "or_greater") var entry_depth_scale := 0.7
@export_range(0.05, 4.0, 0.01, "or_greater") var channel_radius_scale := 0.65
@export_range(0.0, 8.0, 0.01, "or_greater") var penetration_depth_scale := 1.0
@export_range(0.0, 4.0, 0.01, "or_greater") var exit_spall_radius_scale := 1.8
@export_range(0.0, 4.0, 0.01, "or_greater") var exit_spall_depth_scale := 0.8
@export_range(0.0, 2.0, 0.01, "or_greater") var dent_depth_scale := 0.35
@export_range(0.0, 1.0, 0.01) var radius_energy_exponent := 0.35
@export_range(0.0, 0.8, 0.01) var spatial_warp := 0.12
@export_range(0.1, 100.0, 0.1, "or_greater") var spatial_warp_frequency := 7.0
@export_range(0.1, 2.0, 0.05, "or_greater") var minimum_geometric_feature_voxels := 0.45

@export_group("Cracks")
@export_range(0, 12, 1) var crack_count := 3
@export_range(0.0, 8.0, 0.01, "or_greater") var crack_length_scale := 1.8
@export_range(0.0, 1.0, 0.001, "or_greater") var crack_width_scale := 0.11
@export_range(0.0, 1.0, 0.01) var crack_branching := 0.25
@export_range(0.0, 1.0, 0.01) var anisotropy := 0.0
@export var grain_axis := Vector3.UP

@export_group("Fragments and Integration")
@export_range(0, 64, 1) var maximum_physical_fragments := 6
@export_range(0.0, 10.0, 0.01, "or_greater") var minimum_fragment_volume := 0.03
@export_range(1.0, 10000.0, 1.0, "or_greater") var fragment_density_kg_m3 := 2200.0
@export_range(1.0, 600.0, 1.0, "or_greater") var fragment_lifetime_seconds := 180.0
@export_range(0.0, 4.0, 0.01, "or_greater") var acoustic_aperture_area := 0.08
@export_range(0.0, 1.0, 0.01) var support_strength := 0.65

@export_group("Presentation")
@export var exterior_color := Color(0.34, 0.36, 0.34, 1.0)
@export var interior_color := Color(0.22, 0.20, 0.18, 1.0)
@export var deep_interior_color := Color(0.22, 0.20, 0.18, 1.0)
@export_range(0.0, 4.0, 0.01, "or_greater") var interior_color_depth := 0.0
@export_range(0.0, 1.0, 0.01) var roughness := 0.9
@export_range(0.0, 1.0, 0.01) var metallic := 0.0


func sanitize() -> DestructionTextureDefinition:
	if texture_id.is_empty():
		texture_id = &"material"
	if physical_surface.is_empty():
		physical_surface = &"concrete"
	material_index = clampi(material_index, 1, 255)
	profile_version = clampi(profile_version, 1, 65535)
	energy_resistance = clampf(energy_resistance, 0.01, 1000.0)
	geometry_threshold = maxf(geometry_threshold, 0.0)
	perforation_threshold = maxf(perforation_threshold, geometry_threshold)
	hardness = clampf(hardness, 0.0, 1.0)
	fracture_toughness = clampf(fracture_toughness, 0.0, 1.0)
	ductility = clampf(ductility, 0.0, 1.0)
	damage_accumulation = maxf(damage_accumulation, 0.0)
	entry_radius_scale = maxf(entry_radius_scale, 0.05)
	entry_depth_scale = maxf(entry_depth_scale, 0.05)
	channel_radius_scale = maxf(channel_radius_scale, 0.05)
	penetration_depth_scale = maxf(penetration_depth_scale, 0.0)
	exit_spall_radius_scale = maxf(exit_spall_radius_scale, 0.0)
	exit_spall_depth_scale = maxf(exit_spall_depth_scale, 0.0)
	dent_depth_scale = maxf(dent_depth_scale, 0.0)
	radius_energy_exponent = clampf(radius_energy_exponent, 0.0, 1.0)
	spatial_warp = clampf(spatial_warp, 0.0, 0.8)
	spatial_warp_frequency = maxf(spatial_warp_frequency, 0.1)
	minimum_geometric_feature_voxels = clampf(minimum_geometric_feature_voxels, 0.1, 2.0)
	crack_count = clampi(crack_count, 0, 12)
	crack_length_scale = maxf(crack_length_scale, 0.0)
	crack_width_scale = maxf(crack_width_scale, 0.0)
	crack_branching = clampf(crack_branching, 0.0, 1.0)
	anisotropy = clampf(anisotropy, 0.0, 1.0)
	grain_axis = grain_axis.normalized() if grain_axis.length_squared() > 0.000001 else Vector3.UP
	maximum_physical_fragments = clampi(maximum_physical_fragments, 0, 64)
	minimum_fragment_volume = maxf(minimum_fragment_volume, 0.0)
	fragment_density_kg_m3 = clampf(fragment_density_kg_m3, 1.0, 10000.0)
	fragment_lifetime_seconds = clampf(fragment_lifetime_seconds, 1.0, 600.0)
	acoustic_aperture_area = maxf(acoustic_aperture_area, 0.0)
	support_strength = clampf(support_strength, 0.0, 1.0)
	interior_color_depth = maxf(interior_color_depth, 0.0)
	roughness = clampf(roughness, 0.0, 1.0)
	metallic = clampf(metallic, 0.0, 1.0)
	return self


func normalized_energy(event_energy: float) -> float:
	return maxf(event_energy, 0.0) / maxf(energy_resistance, 0.01)


func produces_geometry(event_energy: float) -> bool:
	return normalized_energy(event_energy) >= geometry_threshold


func perforates(event_energy: float) -> bool:
	return normalized_energy(event_energy) >= perforation_threshold


func response_radius(base_radius: float, event_energy: float) -> float:
	var normalized := maxf(normalized_energy(event_energy), 0.0001)
	return maxf(
		base_radius * entry_radius_scale * pow(normalized, radius_energy_exponent),
		0.001
	)


func content_signature() -> int:
	# Checkpoints must fail closed when geometry-affecting tuning changes. An ordered array avoids
	# Dictionary iteration order and quantizes floats to stable authored precision.
	return hash([
		texture_id,
		physical_surface,
		material_index,
		profile_version,
		_q(energy_resistance),
		_q(geometry_threshold),
		_q(perforation_threshold),
		_q(hardness),
		_q(fracture_toughness),
		_q(ductility),
		_q(damage_accumulation),
		_q(entry_radius_scale),
		_q(entry_depth_scale),
		_q(channel_radius_scale),
		_q(penetration_depth_scale),
		_q(exit_spall_radius_scale),
		_q(exit_spall_depth_scale),
		_q(dent_depth_scale),
		_q(radius_energy_exponent),
		_q(spatial_warp),
		_q(spatial_warp_frequency),
		_q(minimum_geometric_feature_voxels),
		crack_count,
		_q(crack_length_scale),
		_q(crack_width_scale),
		_q(crack_branching),
		_q(anisotropy),
		_q(grain_axis.x),
		_q(grain_axis.y),
		_q(grain_axis.z),
		_q(support_strength),
	]) & 0x7fffffff


static func _q(value: float) -> int:
	return roundi(value * 100000.0)
