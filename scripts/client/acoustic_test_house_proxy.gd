extends Node3D

const FOOT_CONTACT_BUILDER := preload(
	"res://scripts/world/foot_contact_geometry_builder.gd"
)

const HOUSE_WIDTH := 6.4
const HOUSE_DEPTH := 5.9
const WALL_HEIGHT := 3.05
const WALL_THICKNESS := 0.14
const DOOR_WIDTH := 1.45
const DOOR_HEIGHT := 2.25

var wall_material: StandardMaterial3D
var trim_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var marker_material: StandardMaterial3D


func _ready() -> void:
	wall_material = VisualMaterialFactory.standard(Color("53636b"), 0.05, 0.86)
	trim_material = VisualMaterialFactory.standard(Color("202b31"), 0.35, 0.62)
	floor_material = VisualMaterialFactory.standard(Color("2b3438"), 0.12, 0.9)
	marker_material = VisualMaterialFactory.unshaded_emissive(
		Color("c16d24"),
		Color("ff9d3c"),
		2.0
	)
	_build_house()


func _build_house() -> void:
	_add_box(
		"Floor",
		Vector3(0.0, 0.06, 0.0),
		Vector3(HOUSE_WIDTH + 0.3, 0.12, HOUSE_DEPTH + 0.3),
		floor_material
	)
	_add_box(
		"Roof",
		Vector3(0.0, WALL_HEIGHT + WALL_THICKNESS * 0.5, 0.0),
		Vector3(HOUSE_WIDTH + WALL_THICKNESS, WALL_THICKNESS, HOUSE_DEPTH + WALL_THICKNESS),
		trim_material
	)
	_add_box(
		"BackWall",
		Vector3(0.0, WALL_HEIGHT * 0.5, -HOUSE_DEPTH * 0.5),
		Vector3(HOUSE_WIDTH, WALL_HEIGHT, WALL_THICKNESS),
		wall_material
	)
	_add_box(
		"LeftWall",
		Vector3(-HOUSE_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, HOUSE_DEPTH),
		wall_material
	)
	_add_box(
		"RightWall",
		Vector3(HOUSE_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, HOUSE_DEPTH),
		wall_material
	)
	var front_section_width := (HOUSE_WIDTH - DOOR_WIDTH) * 0.5
	var front_section_center := DOOR_WIDTH * 0.5 + front_section_width * 0.5
	_add_box(
		"FrontLeft",
		Vector3(-front_section_center, WALL_HEIGHT * 0.5, HOUSE_DEPTH * 0.5),
		Vector3(front_section_width, WALL_HEIGHT, WALL_THICKNESS),
		wall_material
	)
	_add_box(
		"FrontRight",
		Vector3(front_section_center, WALL_HEIGHT * 0.5, HOUSE_DEPTH * 0.5),
		Vector3(front_section_width, WALL_HEIGHT, WALL_THICKNESS),
		wall_material
	)
	_add_box(
		"FrontLintel",
		Vector3(
			0.0,
			DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) * 0.5,
			HOUSE_DEPTH * 0.5
		),
		Vector3(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICKNESS),
		trim_material
	)
	_add_box(
		"SmallTestWall",
		Vector3(-0.9, 0.85, 0.35),
		Vector3(1.6, 1.8, 0.10),
		wall_material
	)
	_add_box(
		"RadioMarker",
		Vector3(-0.9, 0.135, -0.55),
		Vector3(0.65, 0.03, 0.65),
		marker_material,
		false
	)
	_add_box(
		"ListenerMarker",
		Vector3(-0.9, 0.135, 1.15),
		Vector3(0.65, 0.03, 0.65),
		marker_material,
		false
	)
	_add_label(
		"ACOUSTIC TEST HOUSE  //  OPEN DOOR",
		Vector3(0.0, WALL_HEIGHT + 0.48, HOUSE_DEPTH * 0.5 + 0.04),
		42,
		Color("ffad42")
	)
	_add_label("RADIO", Vector3(-0.9, 0.18, -0.55), 25, Color("ffad42"))
	_add_label("LISTEN", Vector3(-0.9, 0.18, 1.15), 25, Color("ffad42"))


func _add_box(
	node_name: String,
	local_position: Vector3,
	size: Vector3,
	material: Material,
	provides_foot_contact := true
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = local_position
	instance.mesh = mesh
	add_child(instance)
	if provides_foot_contact:
		FOOT_CONTACT_BUILDER.add_box(
			self,
			"%sFootContact" % node_name,
			local_position,
			size
		)


func _add_label(
	label_text: String,
	local_position: Vector3,
	font_size: int,
	color: Color
) -> void:
	var label := Label3D.new()
	label.text = label_text
	label.position = local_position
	label.font_size = font_size
	label.pixel_size = 0.0022
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("050708")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
