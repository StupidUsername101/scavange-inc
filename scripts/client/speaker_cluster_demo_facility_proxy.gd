class_name SpeakerClusterDemoFacilityProxy
extends Node3D

## Garage-only presentation. Speaker cabinets and their animation are owned by the generic array
## proxy; this component contains only the building that happens to host the original demo array.

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const FOOT_CONTACT_BUILDER := preload(
	"res://scripts/world/foot_contact_geometry_builder.gd"
)
const PROP_SCENES := {
	&"generator": preload("res://assets/third_party/pizza_doggy/models/bunkers/generator_1.glb"),
	&"machinery": preload("res://assets/third_party/pizza_doggy/models/bunkers/machinery_1.glb"),
	&"metal_crate": preload("res://assets/third_party/pizza_doggy/models/bunkers/metal_crate_3.glb"),
	&"water_barrel": preload("res://assets/third_party/pizza_doggy/models/bunkers/water_barrel_1.glb"),
	&"wood_pallet": preload("res://assets/third_party/pizza_doggy/models/bunkers/wood_pallet_1.glb"),
	&"control_panel": preload("res://assets/third_party/pizza_doggy/models/tech/control_panel_1.glb"),
	&"fuse_box": preload("res://assets/third_party/pizza_doggy/models/tech/fuse_box_1.glb"),
}
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

var _unit_box: BoxMesh
var _materials: Dictionary[StringName, Material] = {}


func _ready() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_build_materials()
	_build_structure()
	_build_details()
	_build_props()
	FOOT_CONTACT_BUILDER.build_clustered_boxes(
		self,
		LAYOUT.structural_boxes(),
		"GarageFootContact"
	)
	FOOT_CONTACT_BUILDER.build_baked_props(
		self,
		LAYOUT.prop_descriptors(),
		PROP_COLLISION_SHAPES,
		PROP_SURFACES
	)


func _build_materials() -> void:
	_materials[&"wall"] = VisualMaterialFactory.standard(Color("394044"), 0.24, 0.8)
	_materials[&"floor"] = VisualMaterialFactory.standard(Color("272d2f"), 0.1, 0.9)
	_materials[&"roof"] = VisualMaterialFactory.standard(Color("1d2225"), 0.46, 0.62)
	_materials[&"divider"] = VisualMaterialFactory.standard(Color("535b5e"), 0.42, 0.55)
	_materials[&"speaker_trim"] = VisualMaterialFactory.standard(Color("8b7852"), 0.72, 0.28)
	_materials[&"light"] = VisualMaterialFactory.unshaded_emissive(Color("ffd18a"), Color("ff9d42"), 2.5)


func _build_structure() -> void:
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		_add_box(
			str(descriptor.get("name", &"GarageStructure")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			descriptor.get("rotation", Vector3.ZERO),
			_materials.get(descriptor.get("material_id", &"wall")) as Material
		)


func _build_details() -> void:
	var front_z := -LAYOUT.DEPTH * 0.5 - 0.16
	_add_box(
		"GarageDoorHeaderTrim",
		Vector3(LAYOUT.DOOR_CENTER_X, LAYOUT.DOOR_HEIGHT + 0.12, front_z),
		Vector3(LAYOUT.DOOR_WIDTH + 0.34, 0.18, 0.12),
		Vector3.ZERO,
		_materials[&"speaker_trim"]
	)
	for side: float in [-1.0, 1.0]:
		_add_box(
			"GarageDoorPost%s" % str(side),
			Vector3(
				LAYOUT.DOOR_CENTER_X
				+ side * (LAYOUT.DOOR_WIDTH * 0.5 + 0.09),
				LAYOUT.DOOR_HEIGHT * 0.5,
				front_z
			),
			Vector3(0.16, LAYOUT.DOOR_HEIGHT, 0.12),
			Vector3.ZERO,
			_materials[&"speaker_trim"]
		)
	for light_x: float in [-5.2, 0.1, 5.4]:
		_add_box(
			"GarageCeilingLight%s" % str(light_x),
			Vector3(light_x, LAYOUT.HEIGHT - 0.24, 0.2),
			Vector3(1.8, 0.06, 0.2),
			Vector3.ZERO,
			_materials[&"light"]
		)
		var light := OmniLight3D.new()
		light.position = Vector3(light_x, LAYOUT.HEIGHT - 0.42, 0.2)
		light.light_color = Color("ffc57a")
		light.light_energy = 0.62
		light.omni_range = 7.5
		light.shadow_enabled = false
		add_child(light)
	_add_label("GARAGE 04  //  PRESSURE ARRAY", Vector3(LAYOUT.DOOR_CENTER_X, 4.35, front_z - 0.05), 34, Color("ffb33e"))
	_add_label("FIELDLINK REMOTE", Vector3(5.7, 1.2, front_z - 0.05), 20, Color("8ee4b0"))


func _build_props() -> void:
	for descriptor: Dictionary in LAYOUT.prop_descriptors():
		var scene := PROP_SCENES.get(descriptor.get("asset_id", &"")) as PackedScene
		if scene == null:
			continue
		var instance := scene.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = str(descriptor.get("name", &"GarageProp"))
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
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _unit_box
	instance.position = position
	instance.rotation = rotation
	instance.scale = size
	instance.material_override = material
	add_child(instance)
	return instance


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
