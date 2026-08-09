extends Node3D

const CATALOG := preload("res://scripts/enemies/dev_zoo_catalog.gd")
const WALL_HEIGHT := 1.35
const WALL_THICKNESS := 0.22
const ENTRANCE_WIDTH := 3.2

#######################################################
# Mirrors authoritative dev zoo state on clients and updates its local visual presentation.
#######################################################

var rail_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var active_material: StandardMaterial3D


func _ready() -> void:
	rail_material = _make_material(Color(0.17, 0.2, 0.23, 1.0), 0.68, 0.38)
	floor_material = _make_material(Color(0.09, 0.105, 0.115, 1.0), 0.15, 0.84)
	active_material = _make_material(Color(0.9, 0.24, 0.1, 1.0), 0.2, 0.42)
	active_material.emission_enabled = true
	active_material.emission = Color(0.36, 0.035, 0.012, 1.0)
	_build_zoo(CATALOG.build_layout())


func _build_zoo(layout: Dictionary) -> void:
	var total_width := float(layout.get("total_width", 10.0))
	var depth := float(layout.get("depth", 10.0))
	_add_box(
		"ZooFloor",
		Vector3(0.0, 0.025, 0.0),
		Vector3(total_width + 1.0, 0.05, depth + 1.0),
		floor_material
	)
	_add_label(
		"SCAVANGE INC.  //  DEV ZOO",
		Vector3(0.0, 2.8, depth * 0.5 + 0.2),
		52,
		Color(1.0, 0.54, 0.14, 1.0)
	)
	for raw_pen: Variant in layout.get("pens", []):
		_build_pen(raw_pen as Dictionary)


func _build_pen(pen: Dictionary) -> void:
	var slot_index := int(pen["slot_index"])
	var center: Vector3 = pen["center"]
	var size: Vector2 = pen["size"]
	_add_box(
		"Pen%dBack" % slot_index,
		center + Vector3(0.0, WALL_HEIGHT * 0.5, size.y * 0.5),
		Vector3(size.x, WALL_HEIGHT, WALL_THICKNESS),
		rail_material
	)
	_add_box(
		"Pen%dLeft" % slot_index,
		center + Vector3(-size.x * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y),
		rail_material
	)
	_add_box(
		"Pen%dRight" % slot_index,
		center + Vector3(size.x * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y),
		rail_material
	)
	var front_segment_width := (size.x - ENTRANCE_WIDTH) * 0.5
	for side: float in [-1.0, 1.0]:
		_add_box(
			"Pen%dFront%s" % [slot_index, "L" if side < 0.0 else "R"],
			center + Vector3(
				side * (ENTRANCE_WIDTH + front_segment_width) * 0.5,
				WALL_HEIGHT * 0.5,
				-size.y * 0.5
			),
			Vector3(front_segment_width, WALL_HEIGHT, WALL_THICKNESS),
			rail_material
		)
	_add_box(
		"Pen%dMarker" % slot_index,
		center + Vector3(0.0, 0.035, 0.0),
		Vector3(size.x - 0.3, 0.02, size.y - 0.3),
		active_material
	)
	_add_label(
		str(pen["display_name"]),
		center + Vector3(0.0, 2.0, size.y * 0.5 - 0.12),
		38,
		Color(0.96, 0.9, 0.72, 1.0)
	)


func _add_box(
	node_name: String,
	local_position: Vector3,
	size: Vector3,
	material: Material
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = local_position
	instance.mesh = mesh
	add_child(instance)


func _add_label(
	text: String,
	local_position: Vector3,
	font_size: int,
	color: Color
) -> void:
	var label := Label3D.new()
	label.position = local_position
	label.text = text
	label.font_size = font_size
	label.outline_size = 10
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = color
	label.outline_modulate = Color(0.005, 0.007, 0.01, 1.0)
	add_child(label)


func _make_material(
	color: Color,
	metallic: float,
	roughness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
