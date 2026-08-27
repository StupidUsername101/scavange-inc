@tool
class_name AcousticProbe3D
extends Marker3D

## Sparse air-volume sample used by the server wavefront. More probes belong near corners,
## doorways, narrow passages and material boundaries; open areas can remain coarse.

@export var probe_id: StringName = &""
@export_range(0.25, 100.0, 0.25, "or_greater") var auto_connect_radius := 12.0
@export var auto_connect := true
## Physics-style filtering for automatic propagation and diffuse-volume links. Explicit portals
## intentionally bypass this filter, which lets a structure expose one-way radiation apertures
## without merging its interior graph into the outdoor graph.
@export_flags("World", "Interior", "Exterior") var auto_connect_layer := 1
@export_flags("World", "Interior", "Exterior") var auto_connect_mask := 0x7fffffff

@export_group("Environment response")
@export var sample_reflections := true
@export_range(2.0, 100.0, 0.5, "or_greater") var reflection_sample_distance := 28.0
@export_range(0.0, 100.0, 0.25, "or_greater") var environment_influence_radius := 0.0
@export_range(0.0, 2.0, 0.05, "or_greater") var reverb_scale := 1.0
@export_range(0.0, 1.0, 0.01) var guided_spill_strength := 0.0
@export var guided_influence_center_offset := Vector3.ZERO
@export var guided_influence_half_extents := Vector3.ZERO
@export_range(0.0, 10.0, 0.1, "or_greater") var guided_influence_boundary_fade := 0.5
@export_group("Guided aperture spill")
@export var guided_spill_origin_offset := Vector3.ZERO
@export var guided_spill_axis := Vector3.ZERO
@export var guided_spill_aperture_half_extents := Vector2.ZERO
@export var guided_spill_divergence := Vector2.ZERO
@export_range(0.1, 100.0, 0.1, "or_greater") var guided_spill_falloff_distance := 10.0
@export_group("Endpoint attachment")
@export var attachment_exclusion_center_offset := Vector3.ZERO
@export var attachment_exclusion_half_extents := Vector3.ZERO
## Optional full-strength air volume owned by this probe. A zero extent remains unbounded. The
## boundary fade extends outward and lets neighboring probe volumes overlap without a hard seam.
@export var attachment_influence_center_offset := Vector3.ZERO
@export var attachment_influence_half_extents := Vector3.ZERO
@export_range(0.0, 10.0, 0.05, "or_greater") var attachment_influence_boundary_fade := 0.0


func _enter_tree() -> void:
	add_to_group(&"acoustic_probes")


func stable_id() -> StringName:
	if not probe_id.is_empty():
		return probe_id
	return StringName(str(get_path()))


func can_auto_connect_to(other: AcousticProbe3D) -> bool:
	return (
		other != null
		and (auto_connect_mask & other.auto_connect_layer) != 0
		and (other.auto_connect_mask & auto_connect_layer) != 0
	)


func effective_environment_influence_radius() -> float:
	if environment_influence_radius > 0.0:
		return environment_influence_radius
	return maxf(auto_connect_radius * 0.85, 2.0)


func apply_authored_environment_overrides(response: Dictionary) -> Dictionary:
	if guided_spill_strength <= 0.0:
		return response
	var result := response.duplicate(false)
	result["guided_propagation"] = maxf(
		float(result.get("guided_propagation", 0.0)),
		clampf(guided_spill_strength, 0.0, 1.0)
	)
	return result


func guided_influence_world_center() -> Vector3:
	return global_transform * guided_influence_center_offset


func guided_influence_world_half_extents() -> Vector3:
	var local_extents := guided_influence_half_extents.abs()
	if local_extents.is_zero_approx():
		return Vector3.ZERO
	var world_basis := global_basis
	return (
		world_basis.x.abs() * local_extents.x
		+ world_basis.y.abs() * local_extents.y
		+ world_basis.z.abs() * local_extents.z
	)


func guided_spill_world_shape() -> Dictionary:
	var local_axis := guided_spill_axis.normalized()
	var local_aperture := guided_spill_aperture_half_extents.abs()
	if (
		local_axis.is_zero_approx()
		or local_aperture.x <= 0.0
		or local_aperture.y <= 0.0
	):
		return {}
	var world_axis_vector := global_basis * local_axis
	if world_axis_vector.is_zero_approx():
		return {}
	var world_axis := world_axis_vector.normalized()
	var world_lateral := global_basis.x
	world_lateral -= world_axis * world_lateral.dot(world_axis)
	if world_lateral.is_zero_approx():
		world_lateral = world_axis.cross(Vector3.UP)
		if world_lateral.is_zero_approx():
			world_lateral = world_axis.cross(Vector3.RIGHT)
	world_lateral = world_lateral.normalized()
	return {
		"origin": global_transform * guided_spill_origin_offset,
		"axis": world_axis,
		"lateral_axis": world_lateral,
		"aperture_half_extents": Vector2(
			local_aperture.x * global_basis.x.length(),
			local_aperture.y * global_basis.y.length()
		),
		"divergence": Vector2(
			maxf(guided_spill_divergence.x, 0.0),
			maxf(guided_spill_divergence.y, 0.0)
		),
		"falloff_distance": maxf(
			guided_spill_falloff_distance * world_axis_vector.length(),
			0.1
		),
	}


func attachment_exclusion_world_center() -> Vector3:
	return global_transform * attachment_exclusion_center_offset


func attachment_exclusion_world_half_extents() -> Vector3:
	var local_extents := attachment_exclusion_half_extents.abs()
	if local_extents.is_zero_approx():
		return Vector3.ZERO
	return (
		global_basis.x.abs() * local_extents.x
		+ global_basis.y.abs() * local_extents.y
		+ global_basis.z.abs() * local_extents.z
	)


func attachment_influence_world_center() -> Vector3:
	return global_transform * attachment_influence_center_offset


func attachment_influence_world_half_extents() -> Vector3:
	var local_extents := attachment_influence_half_extents.abs()
	if local_extents.is_zero_approx():
		return Vector3.ZERO
	return (
		global_basis.x.abs() * local_extents.x
		+ global_basis.y.abs() * local_extents.y
		+ global_basis.z.abs() * local_extents.z
	)
