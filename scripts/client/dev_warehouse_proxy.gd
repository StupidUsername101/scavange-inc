extends Node3D

const CATALOG := preload("res://scripts/drones/dev_warehouse_catalog.gd")

#######################################################
# Mirrors authoritative dev warehouse state on clients and updates its local visual
# presentation.
#######################################################

var steel_material: StandardMaterial3D
var dark_material: StandardMaterial3D


func _ready() -> void:
	steel_material = _create_material(Color(0.18, 0.2, 0.22, 1.0), 0.72, 0.42)
	dark_material = _create_material(Color(0.045, 0.052, 0.06, 1.0), 0.45, 0.62)
	_build_warehouse(CATALOG.build_layout())


func _build_warehouse(layout: Dictionary) -> void:
	var total_width := float(layout.get("total_width", 1.0))
	var max_height := float(layout.get("max_height", 1.0))

	_add_box(
		"WarehouseFloor",
		Vector3(0.0, 0.09, 1.0),
		Vector3(total_width + 1.0, 0.18, 2.2),
		steel_material
	)
	_add_box(
		"WarehouseBack",
		Vector3(0.0, max_height * 0.5, -0.08),
		Vector3(total_width + 0.3, max_height, 0.12),
		dark_material
	)

	_add_world_label(
		"SCAVANGE INC.  //  DEV WAREHOUSE",
		Vector3(0.0, max_height + 0.48, 0.04),
		54,
		Color(1.0, 0.7, 0.2, 1.0)
	)

	var sections: Array = layout.get("sections", [])
	for raw_section: Variant in sections:
		var section: Dictionary = raw_section
		_build_section(section)

	var slots: Array = layout.get("slots", [])
	for raw_slot: Variant in slots:
		var slot: Dictionary = raw_slot
		_build_socket(slot)


func _build_section(section: Dictionary) -> void:
	var color: Color = section["color"]
	var material := _create_emissive_material(color.darkened(0.2), color * 0.28)
	var center_x := float(section["center_x"])
	var width := float(section["width"])
	var height := float(section["height"])

	_add_box(
		str(section["title"]) + "Header",
		Vector3(center_x, height - 0.3, 0.04),
		Vector3(width - 0.18, 0.08, 0.12),
		material
	)
	_add_world_label(
		str(section["title"]),
		Vector3(center_x, height - 0.11, 0.08),
		38,
		color
	)

	var row_count := int(section["row_count"])
	for row: int in range(row_count):
		_add_box(
			str(section["title"]) + "Shelf%d" % row,
			Vector3(
				center_x,
				CATALOG.SLOT_BASE_HEIGHT
				+ float(row) * CATALOG.VERTICAL_SPACING
				- 0.31,
				0.04
			),
			Vector3(width - 0.22, 0.055, 0.38),
			steel_material
		)


func _build_socket(slot: Dictionary) -> void:
	var position: Vector3 = slot["position"]
	var color: Color = slot["section_color"]
	var material := _create_emissive_material(
		color.darkened(0.55),
		color * 0.12
	)
	_add_box(
		"Socket%d" % int(slot["slot_index"]),
		Vector3(position.x, position.y, 0.09),
		Vector3(0.62, 0.52, 0.08),
		material
	)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: Material
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name.validate_node_name()
	instance.position = position
	instance.mesh = mesh
	add_child(instance)


func _add_world_label(
	label_text: String,
	position: Vector3,
	font_size: int,
	color: Color
) -> void:
	var label := Label3D.new()
	label.position = position
	label.text = label_text
	label.font_size = font_size
	label.outline_size = 10
	label.modulate = color
	label.outline_modulate = Color(0.005, 0.007, 0.01, 1.0)
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	add_child(label)


func _create_material(
	color: Color,
	metallic: float,
	roughness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _create_emissive_material(
	color: Color,
	emission: Color
) -> StandardMaterial3D:
	var material := _create_material(color, 0.4, 0.44)
	material.emission_enabled = true
	material.emission = emission
	return material
