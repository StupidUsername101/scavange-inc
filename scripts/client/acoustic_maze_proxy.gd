class_name AcousticMazeProxy
extends Node3D

const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")

var _unit_box: BoxMesh
var _materials: Dictionary[StringName, Material] = {}


func _ready() -> void:
	add_to_group(&"acoustic_maze_proxy")
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_build_materials()
	_build_structure()
	_build_entrance_marker()
	_build_lighting()
	_build_exit_marker()


func _build_materials() -> void:
	_materials[&"wall"] = VisualMaterialFactory.standard(
		Color("353b3d"),
		0.06,
		0.94
	)
	_materials[&"floor"] = VisualMaterialFactory.standard(
		Color("24292b"),
		0.03,
		0.97
	)
	_materials[&"roof"] = VisualMaterialFactory.standard(
		Color("171c1e"),
		0.02,
		0.9
	)
	_materials[&"hazard"] = VisualMaterialFactory.unshaded_emissive(
		Color("e49b25"),
		Color("ff741c"),
		1.8
	)
	_materials[&"exit"] = VisualMaterialFactory.unshaded_emissive(
		Color("e52f35"),
		Color("ff141c"),
		3.2
	)


func _build_structure() -> void:
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		_add_box(
			str(descriptor.get("name", &"MazeBox")),
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE),
			_materials.get(
				descriptor.get("material_id", &"wall"),
				_materials[&"wall"]
			) as Material
		)


func _build_entrance_marker() -> void:
	var entrance := LAYOUT.entrance_position()
	var front_z := entrance.z - 0.04
	_add_box(
		"EntranceHeader",
		Vector3(entrance.x, LAYOUT.WALL_HEIGHT - 0.18, front_z),
		Vector3(LAYOUT.ENTRANCE_WIDTH + 0.5, 0.12, 0.10),
		_materials[&"hazard"]
	)
	var label := Label3D.new()
	label.name = "MazeEntranceLabel"
	label.text = "ACOUSTIC MAZE  //  FOLLOW THE EXIT SIGNAL"
	label.font_size = 32
	label.modulate = Color("ffb14a")
	label.outline_size = 6
	label.position = Vector3(entrance.x, LAYOUT.WALL_HEIGHT + 0.35, front_z - 0.04)
	label.rotation_degrees.y = 180.0
	label.no_depth_test = true
	add_child(label)


func _build_lighting() -> void:
	for x: int in [1, 5, 9]:
		for y: int in [1, 5, 9]:
			var cell := LAYOUT.cell_index(Vector2i(x, y))
			var light := OmniLight3D.new()
			light.name = "MazeLight_%d_%d" % [x, y]
			light.position = LAYOUT.cell_position(cell) + Vector3(0.0, 1.25, 0.0)
			light.light_color = Color("edb96f")
			light.light_energy = 0.48
			light.omni_range = 8.2
			light.shadow_enabled = false
			add_child(light)


func _build_exit_marker() -> void:
	var exit := LAYOUT.exit_position()
	exit.y = 0.0
	_add_box(
		"ExitBeaconPedestal",
		exit + Vector3(0.0, 0.06, 0.0),
		Vector3(1.25, 0.12, 1.0),
		_materials[&"exit"]
	)
	var light := OmniLight3D.new()
	light.name = "ExitBeaconLight"
	light.position = exit + Vector3(0.0, 1.7, 0.0)
	light.light_color = Color("ff252c")
	light.light_energy = 1.5
	light.omni_range = 6.5
	light.shadow_enabled = false
	add_child(light)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _unit_box
	instance.position = position
	instance.scale = size
	instance.material_override = material
	add_child(instance)
	return instance
