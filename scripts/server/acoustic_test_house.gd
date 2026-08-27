extends StaticBody3D

const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const HOUSE_WIDTH := 6.4
const HOUSE_DEPTH := 5.9
const WALL_HEIGHT := 3.05
const WALL_THICKNESS := 0.14
const DOOR_WIDTH := 1.45
const DOOR_HEIGHT := 2.25

@export var acoustic_material: AcousticMaterial
@export var interior_panel_acoustic_material: AcousticMaterial

## Small authored room used to judge doorway diffraction, wall transmission, and short-obstacle
## response with the same authoritative colliders used by gameplay.


func _ready() -> void:
	add_to_group(&"acoustic_test_house")
	PHYSICAL_SURFACE.apply_to(self, &"concrete")
	_build_collision()


func get_acoustic_material() -> AcousticMaterial:
	return acoustic_material


func _build_collision() -> void:
	_add_box(
		"FloorCollision",
		Vector3(0.0, 0.06, 0.0),
		Vector3(HOUSE_WIDTH + 0.3, 0.12, HOUSE_DEPTH + 0.3)
	)
	_add_box(
		"RoofCollision",
		Vector3(0.0, WALL_HEIGHT + WALL_THICKNESS * 0.5, 0.0),
		Vector3(HOUSE_WIDTH + WALL_THICKNESS, WALL_THICKNESS, HOUSE_DEPTH + WALL_THICKNESS)
	)
	_add_box(
		"BackWallCollision",
		Vector3(0.0, WALL_HEIGHT * 0.5, -HOUSE_DEPTH * 0.5),
		Vector3(HOUSE_WIDTH, WALL_HEIGHT, WALL_THICKNESS)
	)
	_add_box(
		"LeftWallCollision",
		Vector3(-HOUSE_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, HOUSE_DEPTH)
	)
	_add_box(
		"RightWallCollision",
		Vector3(HOUSE_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, HOUSE_DEPTH)
	)
	var front_section_width := (HOUSE_WIDTH - DOOR_WIDTH) * 0.5
	var front_section_center := DOOR_WIDTH * 0.5 + front_section_width * 0.5
	_add_box(
		"FrontLeftCollision",
		Vector3(-front_section_center, WALL_HEIGHT * 0.5, HOUSE_DEPTH * 0.5),
		Vector3(front_section_width, WALL_HEIGHT, WALL_THICKNESS)
	)
	_add_box(
		"FrontRightCollision",
		Vector3(front_section_center, WALL_HEIGHT * 0.5, HOUSE_DEPTH * 0.5),
		Vector3(front_section_width, WALL_HEIGHT, WALL_THICKNESS)
	)
	_add_box(
		"FrontLintelCollision",
		Vector3(
			0.0,
			DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) * 0.5,
			HOUSE_DEPTH * 0.5
		),
		Vector3(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICKNESS)
	)
	# A deliberately short/narrow internal panel makes it easy to compare direct and transmitted
	# radio sound without walking all the way around the outer shell.
	var panel_body := StaticBody3D.new()
	panel_body.name = "SmallTestWallBody"
	panel_body.set_meta(
		"acoustic_material",
		interior_panel_acoustic_material
	)
	add_child(panel_body)
	_add_box(
		"SmallTestWallCollision",
		Vector3(-0.9, 0.85, 0.35),
		Vector3(1.6, 1.8, 0.10),
		panel_body
	)


func _add_box(
	node_name: String,
	local_position: Vector3,
	size: Vector3,
	collision_parent: CollisionObject3D = null
) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = local_position
	collision.shape = shape
	(collision_parent if collision_parent != null else self).add_child(collision)
