class_name EnemyPhysicalLimbVisual3D
extends Node3D

const POINT_INTERPOLATION_SPEED := 18.0

#######################################################
# Implements the enemy physical limb visual 3d subsystem and keeps its gameplay data and
# behavior in one focused script.
#######################################################

var definition: EnemyDefinition
var segment_nodes: Array[Array] = []
var joint_nodes: Array[Array] = []
var current_points: Array[PackedVector3Array] = []
var target_points: Array[PackedVector3Array] = []
var stepping_by_limb: Array[bool] = []


func configure(new_definition: EnemyDefinition) -> void:
	definition = new_definition
	name = "PhysicalLimbVisual"
	_build_chassis()
	_build_limbs()


func apply_limb_state(raw_states: Array) -> void:
	if definition == null or definition.physical_anatomy == null:
		return
	for raw_state: Variant in raw_states:
		var state := raw_state as Dictionary
		var index := int(state.get("index", -1))
		if index < 0 or index >= target_points.size():
			continue
		var raw_points: Variant = state.get("points", PackedVector3Array())
		var points := PackedVector3Array(raw_points)
		if points.size() != 3:
			continue
		target_points[index] = points
		stepping_by_limb[index] = bool(state.get("stepping", false))


func _process(delta: float) -> void:
	var weight := clampf(
		1.0 - exp(-POINT_INTERPOLATION_SPEED * delta),
		0.0,
		1.0
	)
	for limb_index: int in range(current_points.size()):
		var current := current_points[limb_index]
		var target := target_points[limb_index]
		if current.size() != 3 or target.size() != 3:
			continue
		for point_index: int in range(3):
			current[point_index] = current[point_index].lerp(
				target[point_index],
				weight
			)
		_update_limb_geometry(limb_index, current)


func _build_chassis() -> void:
	if definition == null:
		return
	if (
		definition.physical_visual_style
		== EnemyDefinition.PhysicalVisualStyle.BLOCK_CREATURE
	):
		_build_block_chassis()
		return
	_build_spider_chassis()


func _build_spider_chassis() -> void:
	var material: StandardMaterial3D = VisualMaterialFactory.standard(definition.visual_color, 0.06, 0.82)
	var abdomen := MeshInstance3D.new()
	abdomen.name = "Abdomen"
	var abdomen_mesh := SphereMesh.new()
	abdomen_mesh.radius = 0.5
	abdomen_mesh.height = 1.0
	abdomen_mesh.radial_segments = 20
	abdomen_mesh.rings = 12
	abdomen_mesh.material = material
	abdomen.mesh = abdomen_mesh
	abdomen.position = Vector3(0.0, definition.get_body_center_height(), 0.28)
	abdomen.scale = Vector3(
		definition.body_size.x,
		definition.body_size.y,
		definition.body_size.z * 0.72
	)
	add_child(abdomen)

	var thorax := MeshInstance3D.new()
	thorax.name = "Thorax"
	var thorax_mesh := SphereMesh.new()
	thorax_mesh.radius = 0.5
	thorax_mesh.height = 1.0
	thorax_mesh.radial_segments = 18
	thorax_mesh.rings = 10
	thorax_mesh.material = material
	thorax.mesh = thorax_mesh
	thorax.position = Vector3(
		0.0,
		definition.get_body_center_height() + 0.02,
		-definition.body_size.z * 0.37
	)
	thorax.scale = Vector3(
		definition.body_size.x * 0.66,
		definition.body_size.y * 0.78,
		definition.body_size.z * 0.48
	)
	add_child(thorax)

	var eye_material: StandardMaterial3D = VisualMaterialFactory.standard(Color(1.0, 0.13, 0.025, 1.0), 0.0, 0.3)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.55, 0.018, 0.002, 1.0)
	for eye_index: int in range(6):
		var column := eye_index % 3
		var row := floori(float(eye_index) / 3.0)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.075 if row == 0 else 0.055
		eye_mesh.height = eye_mesh.radius * 2.0
		eye_mesh.radial_segments = 10
		eye_mesh.rings = 6
		eye_mesh.material = eye_material
		eye.mesh = eye_mesh
		eye.position = Vector3(
			(float(column) - 1.0) * 0.19,
			definition.get_body_center_height() + 0.14 - float(row) * 0.16,
			-definition.body_size.z * 0.625
		)
		add_child(eye)


func _build_block_chassis() -> void:
	var body_material: StandardMaterial3D = VisualMaterialFactory.standard(definition.visual_color, 0.12, 0.76)
	var trim_material: StandardMaterial3D = VisualMaterialFactory.standard(
		definition.visual_color.darkened(0.2),
		0.18,
		0.68
	)
	var body := MeshInstance3D.new()
	body.name = "BlockBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = definition.body_size
	body_mesh.material = body_material
	body.mesh = body_mesh
	body.position.y = definition.get_body_center_height()
	add_child(body)

	var head := MeshInstance3D.new()
	head.name = "BlockHead"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(
		definition.body_size.x * 0.72,
		definition.body_size.y * 0.72,
		definition.body_size.z * 0.34
	)
	head_mesh.material = trim_material
	head.mesh = head_mesh
	head.position = Vector3(
		0.0,
		definition.get_body_center_height() + definition.body_size.y * 0.08,
		-definition.body_size.z * 0.58
	)
	add_child(head)

	var eye_material: StandardMaterial3D = VisualMaterialFactory.standard(Color(0.9, 0.72, 0.12, 1.0), 0.04, 0.38)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.42, 0.23, 0.015, 1.0)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "BlockEye"
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.19, 0.17, 0.055)
		eye_mesh.material = eye_material
		eye.mesh = eye_mesh
		eye.position = Vector3(
			side * definition.body_size.x * 0.2,
			head.position.y + definition.body_size.y * 0.06,
			head.position.z - definition.body_size.z * 0.18
		)
		add_child(eye)


func _build_limbs() -> void:
	if definition == null or definition.physical_anatomy == null:
		return
	var segment_material: StandardMaterial3D = VisualMaterialFactory.standard(
		definition.visual_color.lightened(0.08),
		0.04,
		0.88
	)
	var joint_material: StandardMaterial3D = VisualMaterialFactory.standard(
		definition.visual_color.darkened(0.16),
		0.03,
		0.92
	)
	for limb_index: int in range(definition.physical_anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = (
			definition.physical_anatomy.limbs[limb_index]
		)
		if limb == null:
			segment_nodes.append([])
			joint_nodes.append([])
			current_points.append(PackedVector3Array())
			target_points.append(PackedVector3Array())
			stepping_by_limb.append(false)
			continue
		var points := EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		current_points.append(points.duplicate())
		target_points.append(points.duplicate())
		stepping_by_limb.append(false)

		var limb_segments: Array[MeshInstance3D] = []
		for segment_index: int in range(2):
			var segment := MeshInstance3D.new()
			segment.name = "%sSegment%d" % [limb.limb_name, segment_index]
			if _uses_block_geometry():
				var block_mesh := BoxMesh.new()
				block_mesh.size = Vector3.ONE
				block_mesh.material = segment_material
				segment.mesh = block_mesh
			else:
				var cylinder_mesh := CylinderMesh.new()
				cylinder_mesh.top_radius = 1.0
				cylinder_mesh.bottom_radius = 1.0
				cylinder_mesh.height = 1.0
				cylinder_mesh.radial_segments = 10
				cylinder_mesh.material = segment_material
				segment.mesh = cylinder_mesh
			add_child(segment)
			limb_segments.append(segment)
		segment_nodes.append(limb_segments)

		var limb_joints: Array[MeshInstance3D] = []
		for joint_index: int in range(3):
			var joint := MeshInstance3D.new()
			joint.name = "%sJoint%d" % [limb.limb_name, joint_index]
			if _uses_block_geometry():
				var block_joint_mesh := BoxMesh.new()
				block_joint_mesh.size = Vector3.ONE * 2.0
				block_joint_mesh.material = joint_material
				joint.mesh = block_joint_mesh
			else:
				var sphere_mesh := SphereMesh.new()
				sphere_mesh.radius = 1.0
				sphere_mesh.height = 2.0
				sphere_mesh.radial_segments = 10
				sphere_mesh.rings = 6
				sphere_mesh.material = joint_material
				joint.mesh = sphere_mesh
			joint.scale = Vector3.ONE * limb.segment_radius * 1.22
			add_child(joint)
			limb_joints.append(joint)
		joint_nodes.append(limb_joints)
		_update_limb_geometry(limb_index, points)


func _update_limb_geometry(
	limb_index: int,
	points: PackedVector3Array
) -> void:
	if (
		definition == null
		or definition.physical_anatomy == null
		or limb_index < 0
		or limb_index >= definition.physical_anatomy.limbs.size()
		or points.size() != 3
	):
		return
	var limb: EnemyPhysicalLimbDefinition = (
		definition.physical_anatomy.limbs[limb_index]
	)
	if limb == null:
		return
	var segments: Array = segment_nodes[limb_index]
	var visual_radius: float = (
		limb.segment_radius * 1.8
		if _uses_block_geometry()
		else limb.segment_radius
	)
	for segment_index: int in range(2):
		_set_segment_transform(
			segments[segment_index] as MeshInstance3D,
			points[segment_index],
			points[segment_index + 1],
			visual_radius
		)
	var joints: Array = joint_nodes[limb_index]
	for joint_index: int in range(3):
		var joint := joints[joint_index] as MeshInstance3D
		joint.position = points[joint_index]
		if joint_index == 2:
			var foot_scale := 1.5 if stepping_by_limb[limb_index] else 1.28
			joint.scale = Vector3.ONE * limb.segment_radius * foot_scale


func _uses_block_geometry() -> bool:
	return (
		definition != null
		and definition.physical_visual_style
		== EnemyDefinition.PhysicalVisualStyle.BLOCK_CREATURE
	)


func _set_segment_transform(
	segment: MeshInstance3D,
	start: Vector3,
	end: Vector3,
	radius: float
) -> void:
	if segment == null:
		return
	var offset := end - start
	var length := offset.length()
	if length <= 0.0001:
		segment.visible = false
		return
	segment.visible = true
	var segment_basis := basis_from_y(offset / length)
	segment_basis.x *= radius
	segment_basis.y *= length
	segment_basis.z *= radius
	segment.transform = Transform3D(segment_basis, start.lerp(end, 0.5))


static func basis_from_y(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	if y_axis.length_squared() <= 0.000001:
		y_axis = Vector3.UP
	var reference := (
		Vector3.FORWARD
		if absf(y_axis.dot(Vector3.FORWARD)) < 0.94
		else Vector3.RIGHT
	)
	var x_axis := y_axis.cross(reference).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
