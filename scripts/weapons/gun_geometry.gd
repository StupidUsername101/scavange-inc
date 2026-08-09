@tool
class_name GunGeometry
extends RefCounted

#######################################################
# Constructs reusable procedural visuals for gun instances.
#######################################################

static func create_part_visual(definition: GunPartDefinition) -> Node3D:
	var root := _create_root(definition)
	var material := _create_material(definition.component_color)
	if definition is GunBarrelDefinition:
		var barrel := definition as GunBarrelDefinition
		_add_cylinder(
			root,
			"Barrel",
			maxf(definition.component_size.x * 0.28, 0.018),
			barrel.barrel_length,
			Vector3.ZERO,
			material
		)
	elif definition is GunAmmunitionDefinition:
		_add_cylinder(
			root,
			"Cartridge",
			maxf(definition.component_size.x * 0.24, 0.012),
			maxf(definition.component_size.z, 0.06),
			Vector3.ZERO,
			material
		)
	else:
		_add_box(
			root,
			"Component",
			definition.component_size,
			Vector3.ZERO,
			Vector3.ZERO,
			material
		)
	return root


static func create_gun_visual(
	build: GunBuild,
	first_person := false
) -> Node3D:
	var root := Node3D.new()
	root.name = "GunVisual"
	if build == null:
		return root

	var receiver_color = (
		build.receiver.component_color
		if build.receiver != null
		else Color(0.18, 0.2, 0.22, 1.0)
	)
	var receiver_material := _create_material(receiver_color)
	var receiver_size := Vector3(0.22, 0.14, 0.32)
	if build.receiver != null:
		receiver_size = build.receiver.component_size
	_add_box(
		root,
		"Receiver",
		receiver_size,
		Vector3.ZERO,
		Vector3.ZERO,
		receiver_material
	)
	_add_box(
		root,
		"Grip",
		Vector3(0.11, 0.27, 0.13),
		Vector3(0.0, -0.18, 0.075),
		Vector3(deg_to_rad(-12.0), 0.0, 0.0),
		receiver_material
	)

	if build.barrel != null:
		var barrel_material := _create_material(build.barrel.component_color)
		var barrel_length := maxf(build.barrel.barrel_length, 0.05)
		_add_cylinder(
			root,
			"Barrel",
			maxf(build.barrel.component_size.x * 0.3, 0.022),
			barrel_length,
			Vector3(
				0.0,
				0.025,
				-receiver_size.z * 0.5 - barrel_length * 0.5
			),
			barrel_material
		)
		_add_box(
			root,
			"FrontSight",
			Vector3(0.025, 0.035, 0.025),
			Vector3(
				0.0,
				receiver_size.y * 0.5 + 0.018,
				-receiver_size.z * 0.5 - barrel_length + 0.025
			),
			Vector3.ZERO,
			barrel_material
		)

	if build.magazine != null:
		var magazine_material := _create_material(
			build.magazine.component_color
		)
		_add_box(
			root,
			"Magazine",
			Vector3(0.075, 0.2, 0.085),
			Vector3(0.0, -0.2, 0.07),
			Vector3(deg_to_rad(-12.0), 0.0, 0.0),
			magazine_material
		)

	root.scale = Vector3.ONE * (1.08 if first_person else 1.0)
	return root


static func _create_root(definition: ItemDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "ItemVisual"
	root.position = definition.mesh_position * definition.overall_size
	root.rotation_degrees = Vector3(
		definition.mesh_rotation_x,
		definition.mesh_rotation_y,
		definition.mesh_rotation_z
	)
	root.scale = Vector3(
		definition.mesh_size_x,
		definition.mesh_size_y,
		definition.mesh_size_z
	) * definition.overall_size
	return root


static func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.62
	material.roughness = 0.3
	return material


static func _add_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position: Vector3,
	rotation: Vector3,
	material: Material
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	parent.add_child(visual)


static func _add_cylinder(
	parent: Node3D,
	node_name: String,
	radius: float,
	length: float,
	position: Vector3,
	material: Material
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	visual.rotation.x = deg_to_rad(90.0)
	parent.add_child(visual)
