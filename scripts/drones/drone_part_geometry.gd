extends RefCounted

const PROPELLER_COLLISION_HEIGHT := 0.1
const FALLBACK_RADIUS := 0.15
const FALLBACK_DIAMETER := FALLBACK_RADIUS * 2.0
const WEAPON_BARREL_RADIUS := 0.025
const WEAPON_BARREL_LENGTH_SCALE := 1.35
const WEAPON_BARREL_OFFSET_SCALE := 0.55
const WEAPON_BARREL_SEGMENTS := 8
const ARM_RADIUS := 0.04
const ARM_LENGTH_SCALE := 2.2
const PROPELLER_HUB_RADIUS := 0.055
const PROPELLER_HUB_HEIGHT := 0.08
const PROPELLER_HUB_SEGMENTS := 12
const PROPELLER_BLADE_HEIGHT := 0.018
const PROPELLER_BLADE_WIDTH := 0.045

#######################################################
# Constructs reusable procedural visuals for drone part instances.
#######################################################

static func get_part_kind(definition: DronePartDefinition) -> StringName:
	if definition is DroneAIChipDefinition:
		return &"ai_chip"
	if definition is DroneAttachmentDefinition:
		return &"attachment"
	if definition is DroneBatteryDefinition:
		return &"battery"
	if definition is DroneCoreDefinition:
		return &"core"
	if definition is DronePropellerDefinition:
		return &"propeller"
	return &"unknown"


static func create_collision_shape(
	definition: DronePartDefinition
) -> Shape3D:
	if definition is DroneCameraAttachmentDefinition:
		return null
	if definition is DroneAttachmentDefinition:
		var attachment_shape := BoxShape3D.new()
		attachment_shape.size = (
			definition as DroneAttachmentDefinition
		).body_size
		return attachment_shape

	if definition is DroneAIChipDefinition:
		var chip_shape := BoxShape3D.new()
		chip_shape.size = (
			definition as DroneAIChipDefinition
		).body_size
		return chip_shape

	if definition is DroneBatteryDefinition:
		var battery_shape := BoxShape3D.new()
		battery_shape.size = (
			definition as DroneBatteryDefinition
		).body_size
		return battery_shape

	if definition is DroneCoreDefinition:
		var core: DroneCoreDefinition = definition as DroneCoreDefinition
		if core.editable_mesh != null and core.editable_mesh.has_geometry():
			var editable_shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			editable_shape.points = core.editable_mesh.vertices
			return editable_shape
		var core_shape: BoxShape3D = BoxShape3D.new()
		core_shape.size = core.body_size
		return core_shape

	if definition is DronePropellerDefinition:
		var propeller := definition as DronePropellerDefinition
		var propeller_shape := CylinderShape3D.new()
		propeller_shape.radius = propeller.rotor_radius
		propeller_shape.height = PROPELLER_COLLISION_HEIGHT
		return propeller_shape

	var fallback_shape := SphereShape3D.new()
	fallback_shape.radius = FALLBACK_RADIUS
	return fallback_shape


static func create_visual(
	definition: DronePartDefinition
) -> Node3D:
	var root := Node3D.new()
	root.name = "DronePartVisual"
	var material := create_part_material(definition)

	if definition is DroneCameraAttachmentDefinition:
		return root

	if definition is DroneAttachmentDefinition:
		_add_attachment_visual(
			root,
			definition as DroneAttachmentDefinition,
			material
		)
		return root

	if definition is DroneAIChipDefinition:
		_add_box_visual(
			root,
			(definition as DroneAIChipDefinition).body_size,
			material
		)
		return root

	if definition is DroneBatteryDefinition:
		_add_box_visual(
			root,
			(definition as DroneBatteryDefinition).body_size,
			material
		)
		return root

	if definition is DroneCoreDefinition:
		_add_core_visual(
			root,
			definition as DroneCoreDefinition,
			material
		)
		return root

	if definition is DronePropellerDefinition:
		_add_propeller_visual(
			root,
			definition as DronePropellerDefinition,
			material
		)
		return root

	var fallback_mesh := SphereMesh.new()
	fallback_mesh.radius = FALLBACK_RADIUS
	fallback_mesh.height = FALLBACK_DIAMETER
	fallback_mesh.material = VisualMaterialFactory.standard(
		Color(0.5, 0.5, 0.55, 1.0),
		0.1,
		0.65
	)
	var fallback_visual := MeshInstance3D.new()
	fallback_visual.mesh = fallback_mesh
	root.add_child(fallback_visual)
	return root


static func create_core_mesh(core: DroneCoreDefinition) -> Mesh:
	if core == null:
		return null
	if core.editable_mesh == null or not core.editable_mesh.has_geometry():
		var box: BoxMesh = BoxMesh.new()
		box.size = core.body_size
		return box
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face_index: int in range(core.editable_mesh.face_count()):
		var indices: PackedInt32Array = core.editable_mesh.face_indices(face_index)
		if indices.size() < 3:
			continue
		var first_vertex: Vector3 = core.editable_mesh.vertices[indices[0]]
		for corner: int in range(1, indices.size() - 1):
			surface_tool.add_vertex(first_vertex)
			surface_tool.add_vertex(core.editable_mesh.vertices[indices[corner]])
			surface_tool.add_vertex(core.editable_mesh.vertices[indices[corner + 1]])
	surface_tool.generate_normals()
	return surface_tool.commit()


static func _add_core_visual(
	root: Node3D,
	core: DroneCoreDefinition,
	material: StandardMaterial3D
) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = create_core_mesh(core)
	visual.material_override = material
	root.add_child(visual)


static func _add_attachment_visual(
	root: Node3D,
	attachment: DroneAttachmentDefinition,
	material: StandardMaterial3D
) -> void:
	_add_box_visual(root, attachment.body_size, material)
	if attachment is DroneWeaponDefinition:
		_add_weapon_barrel(root, attachment, material)
	elif attachment is DroneArmDefinition:
		_add_arm_extension(root, attachment, material)


static func _add_box_visual(
	root: Node3D,
	size: Vector3,
	material: StandardMaterial3D
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	root.add_child(visual)


static func _add_weapon_barrel(
	root: Node3D,
	attachment: DroneAttachmentDefinition,
	material: StandardMaterial3D
) -> void:
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = WEAPON_BARREL_RADIUS
	barrel_mesh.bottom_radius = WEAPON_BARREL_RADIUS
	barrel_mesh.height = (
		attachment.body_size.z * WEAPON_BARREL_LENGTH_SCALE
	)
	barrel_mesh.radial_segments = WEAPON_BARREL_SEGMENTS
	barrel_mesh.material = material
	var barrel := MeshInstance3D.new()
	barrel.position.z = -attachment.body_size.z * WEAPON_BARREL_OFFSET_SCALE
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.mesh = barrel_mesh
	root.add_child(barrel)


static func _add_arm_extension(
	root: Node3D,
	attachment: DroneAttachmentDefinition,
	material: StandardMaterial3D
) -> void:
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = ARM_RADIUS
	arm_mesh.height = attachment.body_size.y * ARM_LENGTH_SCALE
	arm_mesh.material = material
	var arm := MeshInstance3D.new()
	arm.position.y = -attachment.body_size.y
	arm.mesh = arm_mesh
	root.add_child(arm)


static func _add_propeller_visual(
	root: Node3D,
	propeller: DronePropellerDefinition,
	material: StandardMaterial3D
) -> void:
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = PROPELLER_HUB_RADIUS
	hub_mesh.bottom_radius = PROPELLER_HUB_RADIUS
	hub_mesh.height = PROPELLER_HUB_HEIGHT
	hub_mesh.radial_segments = PROPELLER_HUB_SEGMENTS
	hub_mesh.material = material
	var hub := MeshInstance3D.new()
	hub.mesh = hub_mesh
	root.add_child(hub)

	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(
		propeller.rotor_radius * 2.0,
		PROPELLER_BLADE_HEIGHT,
		PROPELLER_BLADE_WIDTH
	)
	blade_mesh.material = material
	var blade := MeshInstance3D.new()
	blade.mesh = blade_mesh
	root.add_child(blade)


static func create_part_material(
	definition: DronePartDefinition
) -> StandardMaterial3D:
	var metallic := 0.2
	var roughness := 0.38
	if definition is DroneCoreDefinition:
		metallic = 0.55
	elif definition is DronePropellerDefinition:
		metallic = 0.25
		roughness = 0.32
	elif definition is DroneAIChipDefinition:
		metallic = 0.08
		roughness = 0.46
	elif definition is DroneAttachmentDefinition:
		metallic = 0.42
		roughness = 0.4

	match definition.quality:
		DronePartDefinition.Quality.SCRAP:
			roughness = minf(roughness + 0.28, 1.0)
		DronePartDefinition.Quality.INDUSTRIAL:
			metallic = minf(metallic + 0.2, 1.0)
			roughness = maxf(roughness - 0.14, 0.05)

	return VisualMaterialFactory.standard(
		definition.visual_color,
		metallic,
		roughness
	)
