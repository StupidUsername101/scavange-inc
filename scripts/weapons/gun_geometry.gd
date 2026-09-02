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
	_first_person := false
) -> Node3D:
	var root := Node3D.new()
	root.name = "GunVisual"
	if build == null:
		return root
	if (
		build.receiver != null
		and build.receiver.presentation_profile == &"rifle"
	):
		_populate_rifle_visual(root, build)
		return root

	var receiver_color = (
		build.receiver.component_color
		if build.receiver != null
		else Color(0.18, 0.2, 0.22, 1.0)
	)
	var receiver_material := _create_material(receiver_color.lightened(0.07))
	var detail_material := _create_material(receiver_color.darkened(0.42))
	var grip_material := _create_material(receiver_color.darkened(0.24))
	detail_material.roughness = 0.48
	grip_material.metallic = 0.24
	grip_material.roughness = 0.72
	var receiver_size := Vector3(0.22, 0.14, 0.32)
	if build.receiver != null:
		receiver_size = build.receiver.component_size
	var slide_size := Vector3(
		receiver_size.x,
		receiver_size.y * 0.68,
		receiver_size.z * 1.18
	)
	var slide_position := Vector3(
		0.0,
		receiver_size.y * 0.3,
		-receiver_size.z * 0.08
	)
	_add_chamfered_box(
		root,
		"ReceiverFrame",
		Vector3(
			receiver_size.x * 0.94,
			receiver_size.y * 0.48,
			receiver_size.z * 0.88
		),
		Vector3(0.0, -receiver_size.y * 0.27, receiver_size.z * 0.025),
		Vector3.ZERO,
		receiver_material,
		0.018
	)
	_add_chamfered_box(
		root,
		"Slide",
		slide_size,
		slide_position,
		Vector3.ZERO,
		receiver_material,
		0.022
	)
	_add_chamfered_box(
		root,
		"Grip",
		Vector3(0.112, 0.275, 0.135),
		Vector3(0.0, -0.18, 0.075),
		Vector3(deg_to_rad(-12.0), 0.0, 0.0),
		grip_material,
		0.016
	)
	_add_item_grip_point(root, Vector3(0.0, -0.18, 0.075))
	for side: float in [-1.0, 1.0]:
		_add_box(
			root,
			"GripPanel%s" % ("L" if side < 0.0 else "R"),
			Vector3(0.008, 0.19, 0.09),
			Vector3(side * 0.059, -0.18, 0.074),
			Vector3(deg_to_rad(-12.0), 0.0, 0.0),
			detail_material
		)

	_add_torus(
		root,
		"TriggerGuard",
		0.052,
		0.073,
		Vector3(0.0, -0.09, -0.055),
		Vector3(0.0, 0.0, deg_to_rad(90.0)),
		Vector3(0.76, 1.0, 1.0),
		detail_material
	)
	_add_box(
		root,
		"Trigger",
		Vector3(0.022, 0.07, 0.018),
		Vector3(0.0, -0.08, -0.053),
		Vector3(deg_to_rad(-18.0), 0.0, 0.0),
		detail_material
	)

	var installed_barrels := build.get_barrels()
	var slide_front := slide_position.z - slide_size.z * 0.5
	# A thin opaque nose closes the procedural slide. It prevents the fully modeled barrel inside
	# the slide from reading like X-ray geometry at shelf and first-person viewing angles.
	_add_chamfered_box(
		root,
		"SlideNose",
		Vector3(slide_size.x * 0.94, slide_size.y * 0.9, 0.018),
		Vector3(0.0, slide_position.y, slide_front - 0.004),
		Vector3.ZERO,
		receiver_material,
		0.012
	)
	for barrel_index: int in range(installed_barrels.size()):
		var installed_barrel := installed_barrels[barrel_index]
		var barrel_material := _create_material(installed_barrel.component_color)
		var visible_barrel_length := clampf(
			installed_barrel.barrel_length * 0.18,
			0.028,
			0.055
		)
		var barrel_offset := get_barrel_layout_offset(
			barrel_index,
			installed_barrels.size(),
			maxf(receiver_size.x * 0.34, 0.075)
		)
		var barrel_name := "Barrel" if barrel_index == 0 else "Barrel%d" % (barrel_index + 1)
		var collar_name := (
			"MuzzleCollar"
			if barrel_index == 0
			else "MuzzleCollar%d" % (barrel_index + 1)
		)
		_add_cylinder(
			root,
			barrel_name,
			maxf(installed_barrel.component_size.x * 0.3, 0.022),
			visible_barrel_length,
			Vector3(
				barrel_offset.x,
				slide_position.y - 0.004 + barrel_offset.y,
				slide_front - visible_barrel_length * 0.5 - 0.012
			),
			barrel_material
		)
		_add_cylinder(
			root,
			collar_name,
			maxf(installed_barrel.component_size.x * 0.36, 0.027),
			0.032,
			Vector3(
				barrel_offset.x,
				slide_position.y - 0.004 + barrel_offset.y,
				slide_front - 0.008
			),
			detail_material
		)
		if barrel_index != 0:
			continue
		_add_box(
			root,
			"FrontSight",
			Vector3(0.026, 0.032, 0.038),
			Vector3(
				0.0,
				slide_position.y + slide_size.y * 0.5 + 0.016,
				slide_front + 0.035
			),
			Vector3.ZERO,
			detail_material
		)
		for side: float in [-1.0, 1.0]:
			_add_box(
				root,
				"RearSight%s" % ("L" if side < 0.0 else "R"),
				Vector3(0.024, 0.029, 0.032),
				Vector3(
					side * slide_size.x * 0.29,
					slide_position.y + slide_size.y * 0.5 + 0.014,
					slide_position.z + slide_size.z * 0.5 - 0.038
				),
				Vector3.ZERO,
				detail_material
			)

	_add_box(
		root,
		"EjectionPort",
		Vector3(slide_size.x * 0.52, 0.012, slide_size.z * 0.22),
		Vector3(
			0.025,
			slide_position.y + slide_size.y * 0.5 + 0.004,
			slide_position.z - 0.005
		),
		Vector3.ZERO,
		detail_material
	)
	for serration_index: int in range(4):
		for side: float in [-1.0, 1.0]:
			_add_box(
				root,
				"SlideSerration%d%s" % [serration_index, "L" if side < 0.0 else "R"],
				Vector3(0.007, slide_size.y * 0.63, 0.012),
				Vector3(
					side * (slide_size.x * 0.5 + 0.003),
					slide_position.y,
					slide_position.z + slide_size.z * 0.31 - float(serration_index) * 0.026
				),
				Vector3(deg_to_rad(-10.0), 0.0, 0.0),
				detail_material
			)

	if build.magazine != null:
		var magazine_material := _create_material(
			build.magazine.component_color
		)
		_add_chamfered_box(
			root,
			"Magazine",
			Vector3(0.075, 0.2, 0.085),
			Vector3(0.0, -0.2, 0.07),
			Vector3(deg_to_rad(-12.0), 0.0, 0.0),
			magazine_material,
			0.01
		)

	return root


static func _populate_rifle_visual(root: Node3D, build: GunBuild) -> void:
	var receiver := build.receiver
	var receiver_size := receiver.component_size
	var receiver_material := _create_material(receiver.component_color)
	var dark_material := _create_material(receiver.component_color.darkened(0.5))
	var furniture_material := _create_material(Color(0.075, 0.085, 0.08, 1.0))
	dark_material.roughness = 0.5
	furniture_material.metallic = 0.08
	furniture_material.roughness = 0.82

	_add_chamfered_box(
		root,
		"UpperReceiver",
		Vector3(receiver_size.x, receiver_size.y * 0.62, receiver_size.z),
		Vector3(0.0, receiver_size.y * 0.12, 0.0),
		Vector3.ZERO,
		receiver_material,
		0.018
	)
	_add_chamfered_box(
		root,
		"LowerReceiver",
		Vector3(
			receiver_size.x * 0.86,
			receiver_size.y * 0.58,
			receiver_size.z * 0.72
		),
		Vector3(0.0, -receiver_size.y * 0.23, receiver_size.z * 0.08),
		Vector3.ZERO,
		receiver_material,
		0.016
	)

	var receiver_front := -receiver_size.z * 0.5
	var installed_barrels := build.get_barrels()
	var barrel_length := 0.62
	for installed_barrel: GunBarrelDefinition in installed_barrels:
		barrel_length = maxf(
			barrel_length,
			maxf(installed_barrel.barrel_length, 0.35)
		)
	var handguard_length := clampf(barrel_length * 0.67, 0.34, 0.58)
	_add_chamfered_box(
		root,
		"Handguard",
		Vector3(
			receiver_size.x * 0.88,
			receiver_size.y * 0.88,
			handguard_length
		),
		Vector3(0.0, 0.0, receiver_front - handguard_length * 0.5),
		Vector3.ZERO,
		furniture_material,
		0.026
	)
	for slot_index: int in range(4):
		_add_box(
			root,
			"HandguardVent%d" % slot_index,
			Vector3(receiver_size.x * 0.94, 0.014, 0.045),
			Vector3(
				0.0,
				receiver_size.y * 0.47,
				receiver_front - 0.11 - float(slot_index) * 0.105
			),
			Vector3.ZERO,
			dark_material
		)

	for barrel_index: int in range(installed_barrels.size()):
		var installed_barrel := installed_barrels[barrel_index]
		var barrel_material := _create_material(installed_barrel.component_color)
		var barrel_radius := maxf(installed_barrel.component_size.x * 0.28, 0.025)
		var current_barrel_length := maxf(installed_barrel.barrel_length, 0.35)
		var barrel_offset := get_barrel_layout_offset(
			barrel_index,
			installed_barrels.size(),
			maxf(receiver_size.x * 0.34, 0.09)
		)
		var barrel_name := "Barrel" if barrel_index == 0 else "Barrel%d" % (barrel_index + 1)
		var muzzle_name := (
			"MuzzleBrake"
			if barrel_index == 0
			else "MuzzleBrake%d" % (barrel_index + 1)
		)
		_add_cylinder(
			root,
			barrel_name,
			barrel_radius,
			current_barrel_length,
			Vector3(
				barrel_offset.x,
				0.01 + barrel_offset.y,
				receiver_front - current_barrel_length * 0.5
			),
			barrel_material
		)
		var muzzle_z := receiver_front - current_barrel_length
		_add_cylinder(
			root,
			muzzle_name,
			barrel_radius * 1.42,
			0.105,
			Vector3(
				barrel_offset.x,
				0.01 + barrel_offset.y,
				muzzle_z - 0.052
			),
			dark_material
		)
		for side: float in [-1.0, 1.0]:
			_add_box(
				root,
				"MuzzlePort%d%s" % [barrel_index + 1, "L" if side < 0.0 else "R"],
				Vector3(0.012, barrel_radius * 1.4, 0.035),
				Vector3(
					barrel_offset.x + side * barrel_radius * 1.3,
					0.01 + barrel_offset.y,
					muzzle_z - 0.052
				),
				Vector3.ZERO,
				furniture_material
			)

	var stock_length := maxf(receiver_size.z * 0.95, 0.44)
	var stock_center_z := receiver_size.z * 0.5 + stock_length * 0.5
	_add_chamfered_box(
		root,
		"Stock",
		Vector3(receiver_size.x * 0.72, receiver_size.y * 0.8, stock_length),
		Vector3(0.0, -receiver_size.y * 0.04, stock_center_z),
		Vector3(deg_to_rad(-2.5), 0.0, 0.0),
		furniture_material,
		0.024
	)
	_add_chamfered_box(
		root,
		"ButtPad",
		Vector3(receiver_size.x * 0.82, receiver_size.y * 1.12, 0.075),
		Vector3(0.0, -receiver_size.y * 0.08, stock_center_z + stock_length * 0.5),
		Vector3(deg_to_rad(-2.5), 0.0, 0.0),
		dark_material,
		0.018
	)
	_add_chamfered_box(
		root,
		"PistolGrip",
		Vector3(0.105, 0.27, 0.13),
		Vector3(0.0, -0.19, receiver_size.z * 0.24),
		Vector3(deg_to_rad(-15.0), 0.0, 0.0),
		furniture_material,
		0.016
	)
	_add_item_grip_point(
		root,
		Vector3(0.0, -0.19, receiver_size.z * 0.24)
	)
	_add_torus(
		root,
		"TriggerGuard",
		0.048,
		0.069,
		Vector3(0.0, -0.11, -receiver_size.z * 0.08),
		Vector3(0.0, 0.0, deg_to_rad(90.0)),
		Vector3(0.78, 1.0, 1.0),
		dark_material
	)
	_add_box(
		root,
		"Trigger",
		Vector3(0.02, 0.065, 0.018),
		Vector3(0.0, -0.1, -receiver_size.z * 0.08),
		Vector3(deg_to_rad(-18.0), 0.0, 0.0),
		dark_material
	)

	if build.magazine != null:
		var magazine_material := _create_material(build.magazine.component_color)
		var magazine_height := maxf(build.magazine.component_size.y, 0.3)
		_add_chamfered_box(
			root,
			"MagazineUpper",
			Vector3(0.095, magazine_height * 0.58, 0.13),
			Vector3(0.0, -0.19, -receiver_size.z * 0.04),
			Vector3(deg_to_rad(-5.0), 0.0, 0.0),
			magazine_material,
			0.012
		)
		_add_chamfered_box(
			root,
			"MagazineLower",
			Vector3(0.092, magazine_height * 0.52, 0.125),
			Vector3(0.0, -0.19 - magazine_height * 0.48, -receiver_size.z * 0.005),
			Vector3(deg_to_rad(7.0), 0.0, 0.0),
			magazine_material,
			0.012
		)

	_add_box(
		root,
		"TopRail",
		Vector3(receiver_size.x * 0.66, 0.025, receiver_size.z * 0.82),
		Vector3(0.0, receiver_size.y * 0.49, 0.0),
		Vector3.ZERO,
		dark_material
	)
	for sight_spec: Dictionary in [
		{"name": "RearSight", "z": receiver_size.z * 0.31},
		{"name": "FrontSight", "z": receiver_front - handguard_length * 0.83},
	]:
		_add_box(
			root,
			str(sight_spec["name"]),
			Vector3(0.075, 0.075, 0.035),
			Vector3(0.0, receiver_size.y * 0.72, float(sight_spec["z"])),
			Vector3.ZERO,
			dark_material
		)


static func get_barrel_layout_offset(
	index: int,
	count: int,
	spacing: float
) -> Vector2:
	if count <= 1 or index < 0 or index >= count:
		return Vector2.ZERO
	var safe_spacing := maxf(spacing, 0.001)
	if count == 2:
		return Vector2(
			(-0.5 if index == 0 else 0.5) * safe_spacing,
			0.0
		)
	# Three or more barrels form an even ring. Geometry remains data-driven:
	# adding more lanes never requires a bespoke weapon silhouette.
	var angle := -PI * 0.5 + TAU * float(index) / float(count)
	var radius := safe_spacing * maxf(1.0, float(count - 1) * 0.42)
	return Vector2(cos(angle), sin(angle)) * radius


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


static func _add_item_grip_point(parent: Node3D, position: Vector3) -> void:
	var grip_point := Marker3D.new()
	grip_point.name = ItemDefinition.ITEM_GRIP_POINT_NAME
	grip_point.position = position
	parent.add_child(grip_point)


static func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.46
	material.roughness = 0.5
	# The custom chamfer mesh is also viewed very close to its silhouette. Rendering both sides
	# keeps a winding/camera-edge case from exposing overlapping internal components; depth testing
	# still makes the material fully opaque.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
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


static func _add_chamfered_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position: Vector3,
	rotation: Vector3,
	material: Material,
	chamfer: float
) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = _create_chamfered_box_mesh(size, chamfer, material)
	visual.position = position
	visual.rotation = rotation
	parent.add_child(visual)


static func _create_chamfered_box_mesh(
	size: Vector3,
	chamfer: float,
	material: Material
) -> ArrayMesh:
	var half := size * 0.5
	var edge := clampf(chamfer, 0.001, minf(half.x, half.y) * 0.8)
	var cross_section: Array[Vector2] = [
		Vector2(-half.x + edge, half.y),
		Vector2(half.x - edge, half.y),
		Vector2(half.x, half.y - edge),
		Vector2(half.x, -half.y + edge),
		Vector2(half.x - edge, -half.y),
		Vector2(-half.x + edge, -half.y),
		Vector2(-half.x, -half.y + edge),
		Vector2(-half.x, half.y - edge),
	]
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for point: Vector2 in cross_section:
		front.append(Vector3(point.x, point.y, -half.z))
		back.append(Vector3(point.x, point.y, half.z))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle_index: int in range(1, cross_section.size() - 1):
		_add_surface_triangle(surface, front[0], front[triangle_index], front[triangle_index + 1])
		_add_surface_triangle(surface, back[0], back[triangle_index + 1], back[triangle_index])
	for side_index: int in range(cross_section.size()):
		var next_index := (side_index + 1) % cross_section.size()
		_add_surface_triangle(surface, front[side_index], back[next_index], front[next_index])
		_add_surface_triangle(surface, front[side_index], back[side_index], back[next_index])
	surface.generate_normals()
	var mesh := surface.commit() as ArrayMesh
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return mesh


static func _add_surface_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


static func _add_torus(
	parent: Node3D,
	node_name: String,
	inner_radius: float,
	outer_radius: float,
	position: Vector3,
	rotation: Vector3,
	scale: Vector3,
	material: Material
) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 16
	mesh.ring_segments = 8
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	visual.scale = scale
	parent.add_child(visual)
