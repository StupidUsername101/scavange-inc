class_name VisualMaterialFactory
extends RefCounted

#######################################################
# Shared construction for simple procedural StandardMaterial3D instances. Domain-specific visual
# tuning stays with callers; this helper only removes repeated allocation/property boilerplate.
#######################################################


static func standard(
	color: Color,
	metallic: float,
	roughness: float
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


static func unshaded_emissive(
	albedo_color: Color,
	emission_color: Color,
	emission_energy: float = 1.0
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo_color
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	return material


static func binary_status_light(active: bool) -> StandardMaterial3D:
	if active:
		return unshaded_emissive(
			Color(0.12, 0.9, 0.42, 1.0),
			Color(0.04, 0.7, 0.22, 1.0)
		)
	return unshaded_emissive(
		Color(0.9, 0.56, 0.08, 1.0),
		Color(0.55, 0.24, 0.015, 1.0)
	)
