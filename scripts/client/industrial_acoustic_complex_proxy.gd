extends Node3D

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const MODULAR_STRUCTURE_ASSEMBLER := preload(
	"res://scripts/world/modular_structure_assembler.gd"
)
const ASSET_SCENE_LOADER := preload(
	"res://scripts/level_editor/level_asset_scene_loader.gd"
)
const FOOT_CONTACT_BUILDER := preload(
	"res://scripts/world/foot_contact_geometry_builder.gd"
)
const PROP_SCENES := {
	&"generator": preload("res://assets/third_party/pizza_doggy/models/bunkers/generator_1.glb"),
	&"machinery": preload("res://assets/third_party/pizza_doggy/models/bunkers/machinery_1.glb"),
	&"metal_crate": preload("res://assets/third_party/pizza_doggy/models/bunkers/metal_crate_3.glb"),
	&"water_barrel": preload("res://assets/third_party/pizza_doggy/models/bunkers/water_barrel_1.glb"),
	&"wood_pallet": preload("res://assets/third_party/pizza_doggy/models/bunkers/wood_pallet_1.glb"),
	&"computer_terminal": preload("res://assets/third_party/pizza_doggy/models/tech/computer_terminal_1.glb"),
	&"control_panel": preload("res://assets/third_party/pizza_doggy/models/tech/control_panel_1.glb"),
	&"fuse_box": preload("res://assets/third_party/pizza_doggy/models/tech/fuse_box_1.glb"),
}
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

var _unit_box: BoxMesh
var _materials: Dictionary[StringName, Material] = {}
var _light_material: StandardMaterial3D
var _window_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"industrial_acoustic_complex_proxy")
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_build_materials()
	_build_structure()
	_build_building_details()
	_build_tunnel_details()
	_build_large_bunker_details()
	_build_valve_bunker_details()
	_build_movement_parkour_details()
	_build_props()
	_build_foot_contact_geometry()


func _build_foot_contact_geometry() -> void:
	FOOT_CONTACT_BUILDER.build_clustered_boxes(
		self,
		LAYOUT.foot_contact_boxes(),
		"IndustrialFootContact"
	)
	FOOT_CONTACT_BUILDER.build_baked_props(
		self,
		LAYOUT.prop_descriptors(),
		PROP_COLLISION_SHAPES,
		PROP_SURFACES
	)


func _build_materials() -> void:
	_materials[&"concrete"] = VisualMaterialFactory.standard(Color("343d42"), 0.04, 0.92)
	_materials[&"valve_concrete"] = VisualMaterialFactory.standard(Color("344247"), 0.035, 0.9)
	_materials[&"floor"] = VisualMaterialFactory.standard(Color("252d31"), 0.08, 0.82)
	_materials[&"roof"] = VisualMaterialFactory.standard(Color("1b2328"), 0.26, 0.72)
	_materials[&"ramp"] = VisualMaterialFactory.standard(Color("465159"), 0.58, 0.48)
	_materials[&"parkour"] = VisualMaterialFactory.standard(Color("59636a"), 0.36, 0.7)
	_materials[&"rail"] = VisualMaterialFactory.standard(Color("171d21"), 0.72, 0.34)
	_light_material = VisualMaterialFactory.unshaded_emissive(
		Color("ffc36c"),
		Color("ff8c32"),
		2.8
	)
	_window_material = VisualMaterialFactory.standard(Color("152b34"), 0.52, 0.2)
	_window_material.emission_enabled = true
	_window_material.emission = Color("0e3542")
	_window_material.emission_energy_multiplier = 0.65


func _build_structure() -> void:
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		if not bool(descriptor.get("visual", true)):
			continue
		_add_box(
			str(descriptor.get("name", &"Structure")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			descriptor.get("rotation", Vector3.ZERO),
			_materials.get(descriptor.get("material_id", &"concrete")) as Material
		)


func _build_building_details() -> void:
	var center: Vector3 = LAYOUT.BUILDING_CENTER
	var front_z: float = center.z - LAYOUT.BUILDING_DEPTH * 0.5 - 0.13
	var door_x: float = center.x + LAYOUT.DOOR_CENTER_X
	for descriptor: Dictionary in LAYOUT.stair_tread_boxes():
		_add_box(
			str(descriptor.get("name", &"BuildingTread")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			Vector3.ZERO,
			_materials[&"ramp"]
		)
	_add_box(
		"BuildingDoorHeader",
		Vector3(door_x, LAYOUT.DOOR_HEIGHT + 0.12, front_z - 0.03),
		Vector3(LAYOUT.DOOR_WIDTH + 0.34, 0.2, 0.18),
		Vector3.ZERO,
		_materials[&"rail"]
	)
	for floor_index: int in [1, 2]:
		var y := LAYOUT.STOREY_HEIGHT * float(floor_index) + 1.25
		for window_x: float in [-4.7, -1.2, 2.2, 5.0]:
			_add_box(
				"Window%d_%s" % [floor_index, str(window_x)],
				center + Vector3(window_x, y, -LAYOUT.BUILDING_DEPTH * 0.5 - 0.135),
				Vector3(1.55, 1.45, 0.035),
				Vector3.ZERO,
				_window_material
			)
	for floor_index: int in [0, 1, 2]:
		var light_y := float(floor_index + 1) * LAYOUT.STOREY_HEIGHT - 0.22
		for light_z: float in [-2.6, 2.4]:
			_add_box(
				"BuildingLight%d_%s" % [floor_index, str(light_z)],
				center + Vector3(-1.0, light_y, light_z),
				Vector3(2.2, 0.055, 0.16),
				Vector3.ZERO,
				_light_material
			)
			_add_omni_light(
				center + Vector3(-1.0, light_y - 0.16, light_z),
				6.0,
				0.65
			)
	_add_label(
		"SUBLEVEL 19  //  ACOUSTIC ANNEX",
		Vector3(door_x, LAYOUT.DOOR_HEIGHT + 0.5, front_z - 0.08),
		36,
		Color("ffb451")
	)
	_add_label(
		"LEVELS 01—03",
		Vector3(door_x, 1.5, front_z - 0.08),
		22,
		Color("a8bbc2")
	)


func _build_tunnel_details() -> void:
	var runs := LAYOUT.tunnel_runs()
	for run_index: int in range(runs.size()):
		_build_tunnel_run(runs[run_index], run_index)


func _build_large_bunker_details() -> void:
	_build_bunker_details(
		LAYOUT.LARGE_BUNKER_CENTER,
		"LargeBunker",
		"BUNKER 40  //  INDUSTRIAL CONCRETE",
		"4-CHANNEL A/B ARRAY"
	)


func _build_valve_bunker_details() -> void:
	_build_bunker_details(
		LAYOUT.VALVE_BUNKER_CENTER,
		"ValveBunker",
		"VALVE REFERENCE  //  CONCRETE 0.05 0.07 0.08",
		"SCATTER 0.05  //  HYBRID EARLY + LATE"
	)


func _build_movement_parkour_details() -> void:
	for descriptor: Dictionary in LAYOUT.parkour_contact_detail_boxes():
		_add_box(
			str(descriptor.get("name", &"ParkourTread")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			Vector3.ZERO,
			_materials[&"ramp"]
		)
	for descriptor: Dictionary in LAYOUT.MOVEMENT_PARKOUR_LAYOUT.jump_edge_markers():
		_add_box(
			str(descriptor.get("name", &"ParkourJumpEdge")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			Vector3.ZERO,
			_light_material
		)
	var center: Vector3 = LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CENTER
	_add_label(
		"MOVEMENT LAB  //  CONTACT COURSE",
		center + Vector3(-15.6, 1.1, 0.0),
		34,
		Color("ffb451")
	)
	_add_label(
		"MOVEMENT LAB  //  EAST >>",
		center + Vector3(-28.0, 1.35, 0.0),
		28,
		Color("ffb451")
	)
	_add_label(
		"SPRINT COMMIT  //  9.0 M",
		center + Vector3(
			0.0,
			LAYOUT.MOVEMENT_PARKOUR_LAYOUT.mirror_platform_top_y() + 0.62,
			LAYOUT.MOVEMENT_PARKOUR_LAYOUT.MIRROR_Z_OFFSET
		),
		28,
		Color("ffc36c")
	)


func _build_bunker_details(
	center: Vector3,
	name_prefix: String,
	title: String,
	subtitle: String
) -> void:
	var east_x: float = center.x + LAYOUT.LARGE_BUNKER_WIDTH * 0.5 + 0.28
	var door_half_width: float = LAYOUT.LARGE_BUNKER_DOOR_WIDTH * 0.5
	for side: int in [-1, 1]:
		_add_box(
			"%sDoorPost%s" % [name_prefix, str(side)],
			Vector3(
				east_x,
				LAYOUT.LARGE_BUNKER_DOOR_HEIGHT * 0.5,
				center.z + float(side) * (door_half_width + 0.11)
			),
			Vector3(0.16, LAYOUT.LARGE_BUNKER_DOOR_HEIGHT, 0.18),
			Vector3.ZERO,
			_materials[&"rail"]
		)
	_add_box(
		"%sDoorHeaderTrim" % name_prefix,
		Vector3(east_x, LAYOUT.LARGE_BUNKER_DOOR_HEIGHT + 0.11, center.z),
		Vector3(0.16, 0.2, LAYOUT.LARGE_BUNKER_DOOR_WIDTH + 0.4),
		Vector3.ZERO,
		_materials[&"rail"]
	)
	var light_transforms: Array[Transform3D] = []
	for x_offset: float in [-15.0, -5.0, 5.0, 15.0]:
		for z_offset: float in [-10.0, 0.0, 10.0]:
			var light_position := center + Vector3(
				x_offset,
				LAYOUT.LARGE_BUNKER_HEIGHT - 0.3,
				z_offset
			)
			light_transforms.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(2.4, 0.055, 0.18)),
				light_position
			))
			_add_omni_light(light_position + Vector3.DOWN * 0.22, 11.0, 0.62)
	_add_multimesh_boxes(
		"%sCeilingLights" % name_prefix,
		light_transforms,
		_light_material
	)
	_add_label(
		title,
		Vector3(east_x + 0.05, LAYOUT.LARGE_BUNKER_DOOR_HEIGHT + 0.58, center.z),
		40,
		Color("ffb451")
	)
	_add_label(
		subtitle,
		Vector3(east_x + 0.05, 1.4, center.z),
		24,
		Color("a8bbc2")
	)


func _build_tunnel_run(run: Dictionary, run_index: int) -> void:
	var definition := run.get("definition") as ModularStructureDefinition
	if definition == null:
		return
	var module_descriptors := LAYOUT.tunnel_module_descriptors(run_index)
	var module_scene := ASSET_SCENE_LOADER.packed_scene(
		definition.visual_scene_path
	)
	MODULAR_STRUCTURE_ASSEMBLER.instantiate_visual_chain(
		self,
		module_scene,
		module_descriptors,
		run.get("container_name", &"BunkerTunnelModules")
	)
	var assembly_bounds := MODULAR_STRUCTURE_ASSEMBLER.assembly_world_bounds(
		definition,
		run.get("center", Vector3.ZERO),
		float(run.get("floor_y", 0.0))
	)
	var light_transforms: Array[Transform3D] = []
	for module_index: int in range(module_descriptors.size()):
		if module_index % 2 != 0:
			continue
		var module_bounds := MODULAR_STRUCTURE_ASSEMBLER.module_world_bounds(
			definition,
			module_descriptors[module_index]
		)
		var position := Vector3(
			module_bounds.get_center().x,
			module_bounds.end.y - 0.26,
			module_bounds.get_center().z
		)
		light_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.82, 0.035, 0.13)),
			position
		))
		_add_omni_light(position + Vector3.DOWN * 0.12, 7.0, 0.7)
	_add_multimesh_boxes(
		"%sTunnelLights" % str(run.get("run_id", &"Bunker")).to_pascal_case(),
		light_transforms,
		_light_material
	)
	_add_label(
		"BUNKER %s  //  %.1f M WIDE"
		% [str(run.get("label", "TRANSIT")), assembly_bounds.size.x],
		Vector3(
			assembly_bounds.get_center().x,
			assembly_bounds.end.y + 0.28,
			assembly_bounds.position.z - 0.18
		),
		28,
		Color("ffb451")
	)


func _build_props() -> void:
	for descriptor: Dictionary in LAYOUT.prop_descriptors():
		var asset_id: StringName = descriptor.get("asset_id", &"")
		var scene := PROP_SCENES.get(asset_id) as PackedScene
		if scene == null:
			push_warning("Unknown industrial prop asset: %s" % asset_id)
			continue
		var instance := scene.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = str(descriptor.get("name", &"IndustrialProp"))
		instance.position = descriptor.get("position", Vector3.ZERO)
		instance.rotation = descriptor.get("rotation", Vector3.ZERO)
		instance.scale = descriptor.get("scale", Vector3.ONE)
		add_child(instance)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material: Material
) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _unit_box
	instance.position = position
	instance.rotation = rotation
	instance.scale = size
	instance.material_override = material
	add_child(instance)


func _add_multimesh_boxes(
	node_name: String,
	transforms: Array[Transform3D],
	material: Material
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _unit_box
	multimesh.instance_count = transforms.size()
	for transform_index: int in range(transforms.size()):
		multimesh.set_instance_transform(transform_index, transforms[transform_index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _add_omni_light(position: Vector3, range_m: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = Color("ffae58")
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	add_child(light)


func _add_label(text: String, position: Vector3, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = font_size
	label.pixel_size = 0.0021
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("050708")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
