class_name ServerSpeakerClusterDemoFacility
extends Node3D

## Garage-only collision and routing-probe authoring. Keeping this out of ServerSpeakerCluster is
## what makes the speaker controller reusable by any scene that supplies emitter markers.

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const COLLISION_BUILDER := preload(
	"res://scripts/world/static_structure_collision_builder.gd"
)
const PROP_COLLISION_SHAPES := {
	&"generator": preload("res://resources/world/prop_collisions/generator_1_convex.tres"),
	&"machinery": preload("res://resources/world/prop_collisions/machinery_1_convex.tres"),
	&"metal_crate": preload("res://resources/world/prop_collisions/metal_crate_3_convex.tres"),
	&"water_barrel": preload("res://resources/world/prop_collisions/water_barrel_1_convex.tres"),
	&"wood_pallet": preload("res://resources/world/prop_collisions/wood_pallet_1_convex.tres"),
	&"control_panel": preload("res://resources/world/prop_collisions/control_panel_1_convex.tres"),
	&"fuse_box": preload("res://resources/world/prop_collisions/fuse_box_1_convex.tres"),
}
const PROP_SURFACES := {
	&"generator": &"metal",
	&"machinery": &"metal",
	&"metal_crate": &"metal",
	&"water_barrel": &"metal",
	&"wood_pallet": &"wood",
	&"control_panel": &"metal",
	&"fuse_box": &"metal",
}
const MACHINERY_ACOUSTIC_MATERIAL := preload(
	"res://resources/world/acoustic_materials/machinery_housing.tres"
)
const THIN_METAL_ACOUSTIC_MATERIAL := preload(
	"res://resources/world/acoustic_materials/thin_metal_housing.tres"
)
const WOOD_PROP_ACOUSTIC_MATERIAL := preload(
	"res://resources/world/acoustic_materials/wood_prop.tres"
)
const PROP_ACOUSTIC_MATERIALS := {
	&"generator": MACHINERY_ACOUSTIC_MATERIAL,
	&"machinery": MACHINERY_ACOUSTIC_MATERIAL,
	&"metal_crate": THIN_METAL_ACOUSTIC_MATERIAL,
	&"water_barrel": THIN_METAL_ACOUSTIC_MATERIAL,
	&"wood_pallet": WOOD_PROP_ACOUSTIC_MATERIAL,
	&"control_panel": THIN_METAL_ACOUSTIC_MATERIAL,
	&"fuse_box": THIN_METAL_ACOUSTIC_MATERIAL,
}

@export var acoustic_material: AcousticMaterial
## Reversible garage-wide A/B switch. Routing probes remain active when their sampled response is
## disabled, so this never changes reachability through the building.


func _ready() -> void:
	_build_authoritative_geometry()
	_build_acoustic_probes()


func _build_authoritative_geometry() -> void:
	var structure_descriptors := LAYOUT.structural_boxes()
	COLLISION_BUILDER.build_clustered_box_bodies(
		self,
		structure_descriptors,
		&"concrete",
		acoustic_material,
		"Garage"
	)
	COLLISION_BUILDER.build_baked_prop_bodies(
		self,
		LAYOUT.prop_descriptors(),
		PROP_COLLISION_SHAPES,
		PROP_SURFACES,
		&"concrete",
		acoustic_material,
		PROP_ACOUSTIC_MATERIALS
	)
	var report := COLLISION_BUILDER.debug_cluster_report(structure_descriptors)
	set_meta(&"structure_collision_report", report)
	# Preserve the report at the complete demo-scene boundary for diagnostics that treat it as one
	# structure, while all generated bodies remain cleanly owned by this facility component.
	if get_parent() != null:
		get_parent().set_meta(&"structure_collision_report", report)


func _build_acoustic_probes() -> void:
	for descriptor: Dictionary in LAYOUT.acoustic_probe_descriptors():
		var probe := AcousticProbe3D.new()
		probe.name = str(descriptor.get("name", &"GarageProbe"))
		probe.probe_id = descriptor.get("probe_id", &"")
		probe.position = descriptor.get("position", Vector3.ZERO)
		probe.auto_connect_radius = float(descriptor.get("auto_connect_radius", 5.0))
		# These remain propagation/routing probes. The garage's abandoned A/B room-response path
		# must not synthesize a second reflection field on top of generic propagation.
		probe.sample_reflections = false
		probe.reflection_sample_distance = 20.0
		probe.environment_influence_radius = float(
			descriptor.get("environment_influence_radius", 5.0)
		)
		probe.reverb_scale = 0.0
		add_child(probe)
