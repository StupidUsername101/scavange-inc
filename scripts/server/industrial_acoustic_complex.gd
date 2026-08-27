extends StaticBody3D

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const COLLISION_BUILDER := preload(
	"res://scripts/world/static_structure_collision_builder.gd"
)
const PROP_COLLISION_SHAPES := {
	&"generator": preload("res://resources/world/prop_collisions/generator_1_convex.tres"),
	&"machinery": preload("res://resources/world/prop_collisions/machinery_1_convex.tres"),
	&"metal_crate": preload("res://resources/world/prop_collisions/metal_crate_3_convex.tres"),
	&"water_barrel": preload("res://resources/world/prop_collisions/water_barrel_1_convex.tres"),
	&"wood_pallet": preload("res://resources/world/prop_collisions/wood_pallet_1_convex.tres"),
	&"computer_terminal": preload("res://resources/world/prop_collisions/computer_terminal_1_convex.tres"),
	&"control_panel": preload("res://resources/world/prop_collisions/control_panel_1_convex.tres"),
	&"fuse_box": preload("res://resources/world/prop_collisions/fuse_box_1_convex.tres"),
}
const PROP_SURFACES := {
	&"generator": &"metal",
	&"machinery": &"metal",
	&"metal_crate": &"metal",
	&"water_barrel": &"metal",
	&"wood_pallet": &"wood",
	&"computer_terminal": &"metal",
	&"control_panel": &"metal",
	&"fuse_box": &"metal",
}

@export var acoustic_material: AcousticMaterial

## Authoritative collision shell for the development environment. The legacy zoo remains in the
## project, but is no longer instantiated by the active world.


func _ready() -> void:
	add_to_group(&"industrial_acoustic_complex")
	PHYSICAL_SURFACE.apply_to(self, &"concrete")
	_build_collision()
	_build_prop_collision()
	_build_building_acoustic_probe_grid()
	_build_large_bunker_acoustic_probe_grid()
	_build_valve_bunker_acoustic_probe_grid()
	_build_tunnel_acoustics()


func get_acoustic_material() -> AcousticMaterial:
	return acoustic_material


func _build_building_acoustic_probe_grid() -> void:
	for descriptor: Dictionary in LAYOUT.building_room_probe_descriptors():
		_add_probe_from_descriptor(descriptor, {
			"name": "BuildingRoomProbe",
			"auto_connect_radius": 4.7,
			"reflection_sample_distance": 18.0,
			"environment_influence_radius": 5.0,
		})


func _build_large_bunker_acoustic_probe_grid() -> void:
	_build_bunker_acoustic_probe_grid(
		LAYOUT.large_bunker_probe_descriptors(),
		"LargeBunker"
	)


func _build_valve_bunker_acoustic_probe_grid() -> void:
	_build_bunker_acoustic_probe_grid(
		LAYOUT.valve_bunker_probe_descriptors(),
		"ValveBunker"
	)


func _build_bunker_acoustic_probe_grid(
	descriptors: Array[Dictionary],
	name_prefix: String
) -> void:
	var door_inside: AcousticProbe3D
	var door_outside: AcousticProbe3D
	for descriptor: Dictionary in descriptors:
		var probe := _add_probe_from_descriptor(descriptor, {
			"name": "%sProbe" % name_prefix,
			"auto_connect_radius": 9.0,
			"reflection_sample_distance": 60.0,
			"environment_influence_radius": 6.5,
		})
		match descriptor.get("role", &"inside") as StringName:
			&"door_inside":
				door_inside = probe
			&"door_outside":
				door_outside = probe
	if door_inside == null or door_outside == null:
		return
	var portal := AcousticPortal3D.new()
	portal.name = "%sDoorOpening" % name_prefix
	portal.bidirectional = true
	add_child(portal)
	portal.probe_a_path = portal.get_path_to(door_inside)
	portal.probe_b_path = portal.get_path_to(door_outside)


func _build_tunnel_acoustics() -> void:
	var probes_by_run: Dictionary[StringName, Dictionary] = {}
	for descriptor: Dictionary in LAYOUT.tunnel_acoustic_probe_descriptors():
		var probe := _add_probe_from_descriptor(descriptor, {
			"name": "AdditionalTunnelProbe",
			"auto_connect_radius": 6.0,
			"reflection_sample_distance": 32.0,
			"environment_influence_radius": 6.0,
		})
		var run_id: StringName = descriptor.get("run_id", &"tunnel")
		var run_probes: Dictionary = probes_by_run.get(run_id, {
			"inside": [],
		})
		var role: StringName = descriptor.get("role", &"inside")
		if role == &"inside":
			(run_probes.get("inside") as Array).append(probe)
		elif role == &"south_outside" or role == &"north_outside":
			run_probes[role] = probe
		probes_by_run[run_id] = run_probes

	for run_id: StringName in probes_by_run:
		var run_probes: Dictionary = probes_by_run[run_id]
		var inside := run_probes.get("inside") as Array
		if inside.is_empty():
			continue
		_add_tunnel_opening_portal(
			"%sTunnelSouthOpening" % str(run_id).to_pascal_case(),
			run_probes.get(&"south_outside") as AcousticProbe3D,
			inside[0] as AcousticProbe3D
		)
		_add_tunnel_opening_portal(
			"%sTunnelNorthOpening" % str(run_id).to_pascal_case(),
			inside[inside.size() - 1] as AcousticProbe3D,
			run_probes.get(&"north_outside") as AcousticProbe3D
		)


func _add_probe_from_descriptor(
	descriptor: Dictionary,
	defaults: Dictionary
) -> AcousticProbe3D:
	var probe := AcousticProbe3D.new()
	probe.name = str(descriptor.get("name", defaults.get("name", "AcousticProbe")))
	probe.probe_id = StringName(str(descriptor.get("probe_id", "")))
	probe.position = descriptor.get("position", Vector3.ZERO)
	probe.auto_connect_radius = float(descriptor.get(
		"auto_connect_radius",
		defaults.get("auto_connect_radius", 12.0)
	))
	probe.sample_reflections = bool(descriptor.get("sample_reflections", true))
	probe.reflection_sample_distance = float(descriptor.get(
		"reflection_sample_distance",
		defaults.get("reflection_sample_distance", 28.0)
	))
	probe.environment_influence_radius = float(descriptor.get(
		"environment_influence_radius",
		defaults.get("environment_influence_radius", 0.0)
	))
	probe.reverb_scale = float(descriptor.get("reverb_scale", 1.0))
	probe.guided_spill_strength = float(descriptor.get("guided_spill_strength", 0.0))
	probe.guided_influence_center_offset = descriptor.get(
		"guided_influence_center_offset",
		Vector3.ZERO
	)
	probe.guided_influence_half_extents = descriptor.get(
		"guided_influence_half_extents",
		Vector3.ZERO
	)
	probe.guided_influence_boundary_fade = float(descriptor.get(
		"guided_influence_boundary_fade",
		0.5
	))
	probe.guided_spill_origin_offset = descriptor.get(
		"guided_spill_origin_offset",
		Vector3.ZERO
	)
	probe.guided_spill_axis = descriptor.get("guided_spill_axis", Vector3.ZERO)
	probe.guided_spill_aperture_half_extents = descriptor.get(
		"guided_spill_aperture_half_extents",
		Vector2.ZERO
	)
	probe.guided_spill_divergence = descriptor.get(
		"guided_spill_divergence",
		Vector2.ZERO
	)
	probe.guided_spill_falloff_distance = float(descriptor.get(
		"guided_spill_falloff_distance",
		10.0
	))
	probe.attachment_influence_center_offset = descriptor.get(
		"attachment_influence_center_offset",
		Vector3.ZERO
	)
	probe.attachment_influence_half_extents = descriptor.get(
		"attachment_influence_half_extents",
		Vector3.ZERO
	)
	probe.attachment_influence_boundary_fade = float(descriptor.get(
		"attachment_influence_boundary_fade",
		0.0
	))
	add_child(probe)
	return probe


func _add_tunnel_opening_portal(
	portal_name: String,
	probe_a: AcousticProbe3D,
	probe_b: AcousticProbe3D
) -> void:
	if probe_a == null or probe_b == null:
		return
	var portal := AcousticPortal3D.new()
	portal.name = portal_name
	portal.carries_guided_energy = true
	add_child(portal)
	portal.probe_a_path = portal.get_path_to(probe_a)
	portal.probe_b_path = portal.get_path_to(probe_b)


func _build_collision() -> void:
	var descriptors := LAYOUT.structural_boxes()
	COLLISION_BUILDER.build_clustered_box_bodies(
		self,
		descriptors,
		&"concrete",
		acoustic_material,
		"Industrial"
	)
	set_meta(
		&"structure_collision_report",
		COLLISION_BUILDER.debug_cluster_report(descriptors)
	)
	set_meta(
		&"tunnel_collision_report",
		COLLISION_BUILDER.debug_cluster_report(LAYOUT.tunnel_structural_boxes())
	)
	var run_reports: Dictionary[StringName, Dictionary] = {}
	var runs := LAYOUT.tunnel_runs()
	for run_index: int in range(runs.size()):
		var run: Dictionary = runs[run_index]
		run_reports[run.get("run_id", &"tunnel")] = (
			COLLISION_BUILDER.debug_cluster_report(
				LAYOUT.tunnel_run_structural_boxes(run_index)
			)
		)
	set_meta(&"tunnel_collision_reports", run_reports)


func _build_prop_collision() -> void:
	COLLISION_BUILDER.build_baked_prop_bodies(
		self,
		LAYOUT.prop_descriptors(),
		PROP_COLLISION_SHAPES,
		PROP_SURFACES,
		&"concrete",
		acoustic_material
	)
