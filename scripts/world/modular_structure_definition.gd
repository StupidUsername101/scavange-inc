class_name ModularStructureDefinition
extends Resource

## Baked, server-safe description of repeated level art. The source bounds are measured once during
## onboarding; dedicated servers can build simplified collision without loading the visual scene.

const PROFILE_ARCHED_TUNNEL := "arched_tunnel"

@export var structure_id := &"modular_structure"
@export_file("*.glb", "*.gltf", "*.tscn") var visual_scene_path := ""
@export var source_bounds := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
@export var module_scale := Vector3.ONE
@export_range(1, 512, 1, "or_greater") var module_count := 1
@export var module_name_prefix := &"StructureModule"
@export_enum("arched_tunnel") var collision_profile := PROFILE_ARCHED_TUNNEL
@export_range(0.02, 1.0, 0.01, "or_greater") var floor_thickness := 0.12
@export_range(0.02, 1.0, 0.01, "or_greater") var shell_thickness := 0.15
@export_range(0.1, 0.8, 0.01) var lower_wall_height_ratio := 0.42


func is_valid() -> bool:
	return (
		not visual_scene_path.is_empty()
		and is_supported_collision_profile(collision_profile)
		and source_bounds.position.is_finite()
		and source_bounds.size.is_finite()
		and module_scale.is_finite()
		and source_bounds.size.x > 0.0
		and source_bounds.size.y > 0.0
		and source_bounds.size.z > 0.0
		and module_scale.x > 0.0
		and module_scale.y > 0.0
		and module_scale.z > 0.0
		and module_count > 0
		and floor_thickness > 0.0
		and shell_thickness > 0.0
	)


static func is_supported_collision_profile(profile: String) -> bool:
	return profile == PROFILE_ARCHED_TUNNEL


func module_size() -> Vector3:
	return scaled_source_bounds().size


func scaled_source_bounds() -> AABB:
	return Transform3D(
		Basis.IDENTITY.scaled(module_scale),
		Vector3.ZERO
	) * source_bounds


func total_length() -> float:
	return source_bounds.size.z * float(module_count)
