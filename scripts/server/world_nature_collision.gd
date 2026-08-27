class_name WorldNatureCollision
extends Node3D

const LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const COLLISION_SHAPES := {
	&"pine": preload("res://resources/world/nature_collisions/pine_tree_1_trunk_convex.tres"),
	&"broadleaf": preload("res://resources/world/nature_collisions/tree_8_trunk_convex.tres"),
	&"stone": preload("res://resources/world/nature_collisions/stone_2_convex.tres"),
}
const META_MAX_PARTIAL_OCCLUSION := &"acoustic_max_partial_occlusion"
# One slender outdoor object scatters a fraction of the wavefront; it is not a room boundary.
# Dense vegetation still contributes density-dependent loss through its baked scattering field.
const TREE_MAX_PARTIAL_OCCLUSION := 0.28
const ROCK_MAX_PARTIAL_OCCLUSION := 0.55


func _ready() -> void:
	var tree_body := _create_collision_body(
		"TreeCollision",
		&"wood",
		_wood_acoustic_material(),
		TREE_MAX_PARTIAL_OCCLUSION
	)
	var rock_body := _create_collision_body(
		"RockCollision",
		&"stone",
		_rock_acoustic_material(),
		ROCK_MAX_PARTIAL_OCCLUSION
	)
	for descriptor: Dictionary in LAYOUT.collision_descriptors():
		var collision_kind: StringName = descriptor.get("collision_kind", &"")
		var body := tree_body if collision_kind == &"trunk" else rock_body
		var asset_id: StringName = descriptor.get("asset_id", &"")
		var shape := COLLISION_SHAPES.get(asset_id) as ConvexPolygonShape3D
		if shape == null:
			push_warning("No baked nature collision for %s" % asset_id)
			continue
		var collision := CollisionShape3D.new()
		collision.name = str(descriptor.get("name", &"Nature")) + "Collision"
		collision.transform = LAYOUT.descriptor_transform(descriptor)
		# Resources are baked and shared by every placement: no runtime hull construction and
		# no duplicate shape allocations per rock or tree.
		collision.shape = shape
		collision.set_meta(&"nature_asset_id", asset_id)
		collision.set_meta(&"collision_source", &"baked_mesh_convex")
		body.add_child(collision)
	_build_acoustic_probe_field()


func _build_acoustic_probe_field() -> void:
	for descriptor: Dictionary in LAYOUT.acoustic_probe_descriptors():
		var probe := AcousticProbe3D.new()
		probe.name = str(descriptor.get("name", "ForestAcousticProbe"))
		probe.probe_id = StringName(str(descriptor.get("probe_id", "")))
		probe.position = descriptor.get("position", Vector3.ZERO)
		probe.auto_connect_radius = LAYOUT.ACOUSTIC_PROBE_CELL_SIZE * 1.45
		probe.reflection_sample_distance = LAYOUT.ACOUSTIC_PROBE_CELL_SIZE * 1.35
		probe.environment_influence_radius = LAYOUT.ACOUSTIC_PROBE_CELL_SIZE * 0.82
		# Trees are absorptive and open to the sky. Keep their response distinct but much shorter
		# and darker than a structural room; actual ray hits still determine the result.
		probe.reverb_scale = 1.15
		add_child(probe)


func _create_collision_body(
	node_name: String,
	physical_surface: StringName,
	acoustic_material: AcousticMaterial,
	max_partial_occlusion: float
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	PHYSICAL_SURFACE.apply_to(body, physical_surface)
	body.set_meta(&"acoustic_material", acoustic_material)
	# Trees and rocks affect direct paths without turning nearby open air into another room.
	body.set_meta(&"acoustic_boundary", false)
	body.set_meta(
		META_MAX_PARTIAL_OCCLUSION,
		clampf(max_partial_occlusion, 0.0, 1.0)
	)
	add_child(body)
	return body


func _wood_acoustic_material() -> AcousticMaterial:
	var material := AcousticMaterial.new()
	material.material_id = &"outdoor_wood"
	material.transmission_gain = Vector3(0.62, 0.28, 0.08)
	material.absorption = Vector3(0.12, 0.35, 0.66)
	material.scattering = 0.42
	material.transmission_volume_db = -3.5
	material.transmission_lowpass_hz = 3600.0
	material.reverb_send = 0.08
	return material


func _rock_acoustic_material() -> AcousticMaterial:
	var material := AcousticMaterial.new()
	material.material_id = &"outdoor_stone"
	material.transmission_gain = Vector3(0.48, 0.12, 0.025)
	material.absorption = Vector3(0.08, 0.12, 0.18)
	material.scattering = 0.34
	material.transmission_volume_db = -6.0
	material.transmission_lowpass_hz = 2200.0
	material.reverb_send = 0.12
	return material
