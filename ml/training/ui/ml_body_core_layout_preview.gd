class_name MLBodyCoreLayoutPreview
extends SubViewportContainer

signal surface_clicked(mount_transform: Transform3D)
signal slot_selected(slot_index: int)
signal slot_remove_requested(slot_index: int)
signal face_selected(face_index: int)
signal orientation_direction_clicked(direction_local: Vector3)

const PART_GEOMETRY = preload("res://scripts/drones/drone_part_geometry.gd")
const BACKGROUND_COLOR: Color = Color("071713")
const CORE_FALLBACK_COLOR: Color = Color("4a6b61")
const SLOT_COLOR: Color = Color("54e6b1")
const PROPELLER_SLOT_COLOR: Color = Color("67c7ff")
const SLOT_SELECTED_COLOR: Color = Color("ffad42")
const FACE_SELECTED_COLOR: Color = Color(1.0, 0.47, 0.13, 0.55)
const FACE_HIGHLIGHT_OFFSET_M: float = 0.003
const FORWARD_COLOR: Color = Color("ffad42")
const UP_COLOR: Color = Color("54e6b1")
const PLACEMENT_OFFSET_M: float = 0.10
const MARKER_RADIUS_PX: float = 18.0
const ORBIT_SENSITIVITY: float = 0.009
const ZOOM_STEP: float = 0.12
const MIN_PITCH: float = -1.25
const MAX_PITCH: float = 1.25

const ORIENTATION_EDIT_NONE: int = 0
const ORIENTATION_EDIT_FORWARD: int = 1
const ORIENTATION_EDIT_UP: int = 2

var preview_viewport: SubViewport
var scene_root: Node3D
var core_visual_root: Node3D
var marker_root: Node3D
var face_highlight_root: Node3D
var orientation_root: Node3D
var camera: Camera3D
var core_size: Vector3 = Vector3(0.65, 0.24, 0.65)
var editable_core_mesh: DroneCoreEditableMeshDefinition
var orientation_supported: bool = false
var slot_transforms: Array[Transform3D] = []
var slot_kinds: Array[StringName] = []
var selected_slot_index: int = -1
var placement_enabled: bool = true
var face_edit_enabled: bool = false
var selected_face_index: int = -1
var orientation_edit_axis: int = ORIENTATION_EDIT_NONE
var model_forward_local: Vector3 = Vector3.FORWARD
var model_up_local: Vector3 = Vector3.UP
var orbit_dragging: bool = false
var orbit_yaw: float = 0.7
var orbit_pitch: float = 0.35
var orbit_distance: float = 2.2
var minimum_orbit_distance: float = 0.8
var maximum_orbit_distance: float = 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	stretch = true
	custom_minimum_size = Vector2(620.0, 390.0)
	_build_viewport()
	_update_camera()


func _build_viewport() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.name = "CorePreviewViewport"
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.world_3d = World3D.new()
	add_child(preview_viewport)

	scene_root = Node3D.new()
	scene_root.name = "PreviewScene"
	preview_viewport.add_child(scene_root)

	core_visual_root = Node3D.new()
	core_visual_root.name = "CoreVisual"
	scene_root.add_child(core_visual_root)
	marker_root = Node3D.new()
	marker_root.name = "SlotMarkers"
	scene_root.add_child(marker_root)
	face_highlight_root = Node3D.new()
	face_highlight_root.name = "FaceHighlight"
	scene_root.add_child(face_highlight_root)
	orientation_root = Node3D.new()
	orientation_root.name = "WorkerOrientation"
	scene_root.add_child(orientation_root)

	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.current = true
	camera.fov = 48.0
	scene_root.add_child(camera)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	key_light.light_energy = 1.4
	scene_root.add_child(key_light)
	var fill_light: OmniLight3D = OmniLight3D.new()
	fill_light.position = Vector3(-1.8, 1.6, 1.8)
	fill_light.omni_range = 8.0
	fill_light.light_energy = 1.8
	scene_root.add_child(fill_light)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("4c7165")
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	scene_root.add_child(environment_node)


func set_core_resource(core: Resource, reset_camera_distance: bool = true) -> void:
	if core_visual_root == null:
		return
	for child: Node in core_visual_root.get_children():
		child.queue_free()
	editable_core_mesh = null
	orientation_supported = core is DroneCoreDefinition
	model_forward_local = Vector3.FORWARD
	model_up_local = Vector3.UP
	if core is DroneCoreDefinition:
		var drone_core: DroneCoreDefinition = core as DroneCoreDefinition
		var model_basis: Basis = drone_core.model_orientation_basis_local()
		model_forward_local = -model_basis.z
		model_up_local = model_basis.y
		if drone_core.editable_mesh != null and drone_core.editable_mesh.has_geometry():
			editable_core_mesh = drone_core.editable_mesh
	core_size = _core_preview_size(core)
	var visual: Node3D = null
	if core is DronePartDefinition:
		visual = PART_GEOMETRY.create_visual(core as DronePartDefinition)
	if visual == null:
		visual = _fallback_core_visual(core_size)
	core_visual_root.add_child(visual)
	var extent: float = maxf(core_size.x, maxf(core_size.y, core_size.z))
	minimum_orbit_distance = maxf(extent * 1.6, 0.65)
	maximum_orbit_distance = maxf(extent * 8.0, 4.0)
	if reset_camera_distance:
		orbit_distance = clampf(extent * 3.3, minimum_orbit_distance, maximum_orbit_distance)
	else:
		orbit_distance = clampf(orbit_distance, minimum_orbit_distance, maximum_orbit_distance)
	selected_face_index = (
		selected_face_index
		if editable_core_mesh != null and selected_face_index < editable_core_mesh.face_count()
		else -1
	)
	_rebuild_face_highlight()
	_rebuild_orientation_visual()
	_update_camera()


func set_orientation_edit_axis(axis: int) -> void:
	orientation_edit_axis = clampi(axis, ORIENTATION_EDIT_NONE, ORIENTATION_EDIT_UP)


func set_model_orientation(forward_local: Vector3, up_local: Vector3) -> void:
	if forward_local.is_finite() and forward_local.length_squared() > 0.000001:
		model_forward_local = forward_local.normalized()
	if up_local.is_finite() and up_local.length_squared() > 0.000001:
		model_up_local = up_local.normalized()
	_rebuild_orientation_visual()


func set_face_edit_enabled(enabled: bool) -> void:
	face_edit_enabled = enabled
	if not face_edit_enabled:
		selected_face_index = -1
	_rebuild_face_highlight()


func set_selected_face(face_index: int) -> void:
	selected_face_index = (
		face_index
		if editable_core_mesh != null and face_index >= 0 and face_index < editable_core_mesh.face_count()
		else -1
	)
	_rebuild_face_highlight()


func set_slots(
	value: Array[Transform3D],
	kinds: Array[StringName],
	selected_index: int = -1
) -> void:
	slot_transforms = value.duplicate()
	slot_kinds = kinds.duplicate()
	while slot_kinds.size() < slot_transforms.size():
		slot_kinds.append(&"attachment")
	if slot_kinds.size() > slot_transforms.size():
		slot_kinds.resize(slot_transforms.size())
	selected_slot_index = selected_index if selected_index >= 0 and selected_index < slot_transforms.size() else -1
	_rebuild_markers()


func set_slot_transforms(value: Array[Transform3D], selected_index: int = -1) -> void:
	# Compatibility wrapper for older tests/callers. The staged creator supplies explicit kinds.
	var kinds: Array[StringName] = []
	for _slot_index: int in range(value.size()):
		kinds.append(&"attachment")
	set_slots(value, kinds, selected_index)


func set_selected_slot(index: int) -> void:
	selected_slot_index = index if index >= 0 and index < slot_transforms.size() else -1
	_rebuild_markers()


func reset_view() -> void:
	orbit_yaw = 0.7
	orbit_pitch = 0.35
	var extent: float = maxf(core_size.x, maxf(core_size.y, core_size.z))
	orbit_distance = clampf(extent * 3.3, minimum_orbit_distance, maximum_orbit_distance)
	_update_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			orbit_dragging = mouse_button.pressed
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			var viewport_position: Vector2 = _to_viewport_position(mouse_button.position)
			var marker_index: int = _marker_at(viewport_position)
			if marker_index >= 0:
				slot_remove_requested.emit(marker_index)
			accept_event()
			return
		if mouse_button.pressed and mouse_button.ctrl_pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(orbit_distance * (1.0 - ZOOM_STEP), minimum_orbit_distance)
			_update_camera()
			accept_event()
			return
		if mouse_button.pressed and mouse_button.ctrl_pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(orbit_distance * (1.0 + ZOOM_STEP), maximum_orbit_distance)
			_update_camera()
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mouse_button.position)
			accept_event()
			return
	if event is InputEventMouseMotion and orbit_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		orbit_yaw -= motion.relative.x * ORBIT_SENSITIVITY
		orbit_pitch = clampf(
			orbit_pitch - motion.relative.y * ORBIT_SENSITIVITY,
			MIN_PITCH,
			MAX_PITCH
		)
		_update_camera()
		accept_event()


func _handle_left_click(local_position: Vector2) -> void:
	var viewport_position: Vector2 = _to_viewport_position(local_position)
	if orientation_edit_axis != ORIENTATION_EDIT_NONE:
		var orientation_hit: Dictionary = _core_hit_at(viewport_position)
		if orientation_hit.is_empty():
			return
		var direction: Vector3 = orientation_hit.get("normal", Vector3.ZERO).normalized()
		if direction.length_squared() > 0.000001:
			orientation_direction_clicked.emit(direction)
		return
	if face_edit_enabled:
		var face_hit: Dictionary = _core_hit_at(viewport_position)
		if face_hit.is_empty():
			set_selected_face(-1)
			face_selected.emit(-1)
			return
		var face_index: int = int(face_hit.get("face_index", -1))
		set_selected_face(face_index)
		face_selected.emit(face_index)
		return
	var marker_index: int = _marker_at(viewport_position)
	if marker_index >= 0:
		slot_selected.emit(marker_index)
		return
	if not placement_enabled:
		return
	var mount_transform: Transform3D = _surface_mount_at(viewport_position)
	if mount_transform == Transform3D.IDENTITY:
		return
	surface_clicked.emit(mount_transform)


func _to_viewport_position(local_position: Vector2) -> Vector2:
	if preview_viewport == null:
		return local_position
	var safe_width: float = maxf(size.x, 1.0)
	var safe_height: float = maxf(size.y, 1.0)
	return Vector2(
		local_position.x * float(preview_viewport.size.x) / safe_width,
		local_position.y * float(preview_viewport.size.y) / safe_height
	)


func _marker_at(viewport_position: Vector2) -> int:
	if camera == null:
		return -1
	var best_index: int = -1
	var best_distance: float = MARKER_RADIUS_PX
	for slot_index: int in range(slot_transforms.size()):
		var world_position: Vector3 = slot_transforms[slot_index].origin
		if camera.is_position_behind(world_position):
			continue
		var screen_position: Vector2 = camera.unproject_position(world_position)
		var distance: float = screen_position.distance_to(viewport_position)
		if distance < best_distance:
			best_distance = distance
			best_index = slot_index
	return best_index


func _surface_mount_at(viewport_position: Vector2) -> Transform3D:
	var hit: Dictionary = _core_hit_at(viewport_position)
	if hit.is_empty():
		return Transform3D.IDENTITY
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.DOWN)
	var basis: Basis = _basis_with_down_axis(normal)
	return Transform3D(basis, point + normal * PLACEMENT_OFFSET_M)


func _core_hit_at(viewport_position: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(viewport_position)
	var ray_direction: Vector3 = camera.project_ray_normal(viewport_position).normalized()
	if editable_core_mesh != null and editable_core_mesh.has_geometry():
		return editable_core_mesh.ray_hit(ray_origin, ray_direction)
	var hit: Dictionary = _ray_box_hit(ray_origin, ray_direction, core_size * 0.5)
	if hit.is_empty():
		return {}
	# Fallback box faces use a stable six-face order matching DroneCoreEditableMeshDefinition.
	hit["face_index"] = _box_face_index(hit.get("normal", Vector3.ZERO))
	return hit


func _box_face_index(normal: Vector3) -> int:
	if normal.z < -0.5:
		return 0
	if normal.z > 0.5:
		return 1
	if normal.x < -0.5:
		return 2
	if normal.x > 0.5:
		return 3
	if normal.y < -0.5:
		return 4
	if normal.y > 0.5:
		return 5
	return -1


func _ray_box_hit(origin: Vector3, direction: Vector3, half_extents: Vector3) -> Dictionary:
	var t_min: float = -INF
	var t_max: float = INF
	for axis: int in range(3):
		var origin_axis: float = origin[axis]
		var direction_axis: float = direction[axis]
		var half_axis: float = maxf(half_extents[axis], 0.001)
		if absf(direction_axis) <= 0.000001:
			if origin_axis < -half_axis or origin_axis > half_axis:
				return {}
			continue
		var inverse_direction: float = 1.0 / direction_axis
		var first: float = (-half_axis - origin_axis) * inverse_direction
		var second: float = (half_axis - origin_axis) * inverse_direction
		if first > second:
			var swap: float = first
			first = second
			second = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, second)
		if t_min > t_max:
			return {}
	var distance: float = t_min if t_min >= 0.0 else t_max
	if distance < 0.0 or not is_finite(distance):
		return {}
	var point: Vector3 = origin + direction * distance
	var normal: Vector3 = _box_surface_normal(point, half_extents)
	return {"point": point, "normal": normal}


func _box_surface_normal(point: Vector3, half_extents: Vector3) -> Vector3:
	var distances: Vector3 = Vector3(
		absf(absf(point.x) - half_extents.x),
		absf(absf(point.y) - half_extents.y),
		absf(absf(point.z) - half_extents.z)
	)
	if distances.x <= distances.y and distances.x <= distances.z:
		return Vector3(signf(point.x), 0.0, 0.0)
	if distances.y <= distances.z:
		return Vector3(0.0, signf(point.y), 0.0)
	return Vector3(0.0, 0.0, signf(point.z))


func _basis_with_down_axis(surface_normal: Vector3) -> Basis:
	var normal: Vector3 = surface_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.DOWN
	var y_axis: Vector3 = -normal
	var helper: Vector3 = Vector3.FORWARD
	if absf(y_axis.dot(helper)) > 0.92:
		helper = Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _rebuild_markers() -> void:
	if marker_root == null:
		return
	for child: Node in marker_root.get_children():
		child.queue_free()
	for slot_index: int in range(slot_transforms.size()):
		var marker: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		marker.mesh = sphere
		marker.transform = slot_transforms[slot_index]
		var material: StandardMaterial3D = StandardMaterial3D.new()
		var slot_kind: StringName = (
			slot_kinds[slot_index]
			if slot_index < slot_kinds.size()
			else &"attachment"
		)
		var base_color: Color = PROPELLER_SLOT_COLOR if slot_kind == &"propeller" else SLOT_COLOR
		material.albedo_color = SLOT_SELECTED_COLOR if slot_index == selected_slot_index else base_color
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.35
		marker.material_override = material
		marker_root.add_child(marker)
		var label: Label3D = Label3D.new()
		var kind_ordinal: int = 1
		for previous_index: int in range(slot_index):
			if previous_index < slot_kinds.size() and slot_kinds[previous_index] == slot_kind:
				kind_ordinal += 1
		label.text = "%s%d" % ["P" if slot_kind == &"propeller" else "A", kind_ordinal]
		label.font_size = 42
		label.modulate = Color.WHITE
		label.position = slot_transforms[slot_index].origin + Vector3.UP * 0.09
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker_root.add_child(label)


func _rebuild_face_highlight() -> void:
	if face_highlight_root == null:
		return
	for child: Node in face_highlight_root.get_children():
		child.queue_free()
	if (
		not face_edit_enabled
		or editable_core_mesh == null
		or selected_face_index < 0
		or selected_face_index >= editable_core_mesh.face_count()
	):
		return
	var indices: PackedInt32Array = editable_core_mesh.face_indices(selected_face_index)
	if indices.size() < 3:
		return
	var normal: Vector3 = editable_core_mesh.face_normal(selected_face_index)
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var first_vertex: Vector3 = editable_core_mesh.vertices[indices[0]] + normal * FACE_HIGHLIGHT_OFFSET_M
	for corner: int in range(1, indices.size() - 1):
		surface_tool.add_vertex(first_vertex)
		surface_tool.add_vertex(editable_core_mesh.vertices[indices[corner]] + normal * FACE_HIGHLIGHT_OFFSET_M)
		surface_tool.add_vertex(editable_core_mesh.vertices[indices[corner + 1]] + normal * FACE_HIGHLIGHT_OFFSET_M)
	var highlight: MeshInstance3D = MeshInstance3D.new()
	highlight.mesh = surface_tool.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FACE_SELECTED_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	highlight.material_override = material
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face_highlight_root.add_child(highlight)


func _rebuild_orientation_visual() -> void:
	if orientation_root == null:
		return
	for child: Node in orientation_root.get_children():
		child.queue_free()
	if not orientation_supported:
		return
	var extent: float = maxf(core_size.x, maxf(core_size.y, core_size.z))
	var arrow_length: float = maxf(extent * 0.82, 0.32)
	_add_orientation_arrow(model_forward_local, arrow_length, FORWARD_COLOR, "FORWARD")
	_add_orientation_arrow(model_up_local, arrow_length, UP_COLOR, "UP")


func _add_orientation_arrow(
	direction_value: Vector3,
	length: float,
	color: Color,
	label_text: String
) -> void:
	var direction: Vector3 = direction_value.normalized()
	if direction.length_squared() <= 0.000001:
		return
	var shaft_length: float = length * 0.76
	var shaft_radius: float = maxf(length * 0.018, 0.006)
	var shaft: MeshInstance3D = MeshInstance3D.new()
	var shaft_mesh: CylinderMesh = CylinderMesh.new()
	shaft_mesh.top_radius = shaft_radius
	shaft_mesh.bottom_radius = shaft_radius
	shaft_mesh.height = shaft_length
	shaft.mesh = shaft_mesh
	shaft.transform = Transform3D(
		GeometryBasis.from_y(direction),
		direction * shaft_length * 0.5
	)
	shaft.material_override = _orientation_material(color)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orientation_root.add_child(shaft)

	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = maxf(length * 0.065, 0.022)
	head_mesh.height = length - shaft_length
	head.mesh = head_mesh
	head.transform = Transform3D(
		GeometryBasis.from_y(direction),
		direction * (shaft_length + head_mesh.height * 0.5)
	)
	head.material_override = _orientation_material(color)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orientation_root.add_child(head)

	var label: Label3D = Label3D.new()
	label.text = label_text
	label.font_size = 28
	label.modulate = color
	label.outline_size = 5
	label.position = direction * (length + maxf(length * 0.08, 0.04))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orientation_root.add_child(label)


func _orientation_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	return material


func _fallback_core_visual(size_value: Vector3) -> Node3D:
	var root: Node3D = Node3D.new()
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size_value
	mesh_instance.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = CORE_FALLBACK_COLOR
	material.metallic = 0.25
	material.roughness = 0.65
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	return root


func _core_preview_size(core: Resource) -> Vector3:
	if core is DroneCoreDefinition:
		return (core as DroneCoreDefinition).body_size
	if core is MLRigidCorePartDefinition:
		return (core as MLRigidCorePartDefinition).body_size
	if core is TurretBaseDefinition:
		return (core as TurretBaseDefinition).footprint_size
	return Vector3(0.8, 0.3, 0.8)


func _update_camera() -> void:
	if camera == null:
		return
	var horizontal: float = cos(orbit_pitch) * orbit_distance
	camera.position = Vector3(
		sin(orbit_yaw) * horizontal,
		sin(orbit_pitch) * orbit_distance,
		cos(orbit_yaw) * horizontal
	)
	camera.look_at(Vector3.ZERO, Vector3.UP)
