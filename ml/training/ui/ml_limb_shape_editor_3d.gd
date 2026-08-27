class_name MLLimbShapeEditor3D
extends SubViewportContainer

signal segment_selected(segment_index: int)
signal dimensions_change_requested(segment_index: int, length: float, radius: float)
signal joint_pose_change_requested(segment_index: int, rest_directions: Array, joint_bases: Array)

const BACKGROUND_COLOR: Color = Color("061410")
const GRID_COLOR: Color = Color(0.15, 0.42, 0.34, 0.34)
const AXIS_X_COLOR: Color = Color("ef6a68")
const AXIS_Y_COLOR: Color = Color("54e6b1")
const AXIS_Z_COLOR: Color = Color("67c7ff")
const SEGMENT_COLOR: Color = Color("397e6d")
const SEGMENT_ALTERNATE_COLOR: Color = Color("316c78")
const SELECTED_COLOR: Color = Color("ffad42")
const LENGTH_HANDLE_COLOR: Color = Color("ffad42")
const RADIUS_HANDLE_COLOR: Color = Color("67c7ff")
const JOINT_COLOR: Color = Color("c8ead9")
const EFFECTOR_COLOR: Color = Color("c57cff")
const ORBIT_SENSITIVITY: float = 0.009
const ZOOM_STEP: float = 0.12
const MIN_PITCH: float = -1.35
const MAX_PITCH: float = 1.35
const HANDLE_HIT_RADIUS_PX: float = 22.0
const SEGMENT_HIT_RADIUS_PX: float = 15.0
const JOINT_HIT_RADIUS_PX: float = 20.0
const ROTATION_RING_HIT_RADIUS_PX: float = 9.0
const ROTATION_RING_POINT_COUNT: int = 64
const ROTATION_SNAP_RADIANS: float = PI / 36.0
const MINIMUM_LENGTH_M: float = 0.05
const MAXIMUM_LENGTH_M: float = 10.0
const MINIMUM_RADIUS_M: float = 0.01
const MAXIMUM_RADIUS_M: float = 2.0

enum DragMode {
	NONE,
	LENGTH,
	RADIUS,
	ROTATE_X,
	ROTATE_Y,
	ROTATE_Z,
}

var preview_viewport: SubViewport
var scene_root: Node3D
var geometry_root: Node3D
var gizmo_root: Node3D
var camera: Camera3D
var limb: GenericLimbDefinition
var selected_segment_index: int = -1
var segment_starts: Array[Vector3] = []
var segment_ends: Array[Vector3] = []
var segment_directions: Array[Vector3] = []
var segment_visuals: Array[MeshInstance3D] = []
var joint_visuals: Array[MeshInstance3D] = []
var segment_labels: Array[Label3D] = []
var end_effector_visual: MeshInstance3D
var focus_point: Vector3 = Vector3.ZERO
var orbit_dragging: bool = false
var orbit_yaw: float = 0.72
var orbit_pitch: float = 0.28
var orbit_distance: float = 3.0
var minimum_orbit_distance: float = 0.6
var maximum_orbit_distance: float = 20.0
var drag_mode: int = DragMode.NONE
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_axis_screen: Vector2 = Vector2.RIGHT
var drag_world_per_pixel: float = 0.01
var drag_start_length: float = 0.0
var drag_start_radius: float = 0.0
var length_handle_world: Vector3 = Vector3.ZERO
var radius_handle_world: Vector3 = Vector3.ZERO
var length_gizmo_line: MeshInstance3D
var radius_gizmo_line: MeshInstance3D
var length_gizmo_handle: MeshInstance3D
var radius_gizmo_handle: MeshInstance3D
var length_gizmo_label: Label3D
var radius_gizmo_label: Label3D
var rotation_ring_visuals: Array[MeshInstance3D] = []
var rotation_gizmo_label: Label3D
var rotation_ring_radius: float = 0.1
var rotation_drag_pivot_world: Vector3 = Vector3.ZERO
var rotation_drag_axis_world: Vector3 = Vector3.RIGHT
var rotation_drag_start_vector_world: Vector3 = Vector3.UP
var rotation_drag_source_directions: Array[Vector3] = []
var rotation_drag_source_joint_bases: Array[Basis] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	stretch = true
	custom_minimum_size = Vector2(560.0, 360.0)
	tooltip_text = "Click a joint, then drag a red, green, or blue rotation ring; child parts follow. Hold Shift for 5° snapping. Drag the orange diamond for length or the blue cube for thickness. Middle-drag orbits; Ctrl+wheel zooms."
	_build_viewport()
	_rebuild_geometry(true)


func set_limb_definition(
	value: GenericLimbDefinition,
	selected_index: int = 0,
	reset_camera: bool = true
) -> void:
	limb = value
	selected_segment_index = _valid_segment_index(selected_index)
	if is_node_ready():
		_rebuild_geometry(reset_camera)


func set_selected_segment(segment_index: int) -> void:
	var next_index: int = _valid_segment_index(segment_index)
	if next_index == selected_segment_index:
		return
	selected_segment_index = next_index
	_rebuild_geometry(false)


func refresh_geometry() -> void:
	selected_segment_index = _valid_segment_index(selected_segment_index)
	if limb != null and segment_visuals.size() == limb.segments.size():
		_update_geometry_in_place()
	else:
		_rebuild_geometry(false)


func reset_view() -> void:
	orbit_yaw = 0.72
	orbit_pitch = 0.28
	_update_focus_point()
	_frame_limb()
	_update_camera()
	_rebuild_gizmo()


func _valid_segment_index(requested_index: int) -> int:
	if limb == null or limb.segments.is_empty():
		return -1
	return clampi(requested_index, 0, limb.segments.size() - 1)


func _build_viewport() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.name = "LimbShapeViewport"
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	preview_viewport.world_3d = World3D.new()
	add_child(preview_viewport)

	scene_root = Node3D.new()
	scene_root.name = "LimbEditorScene"
	preview_viewport.add_child(scene_root)

	geometry_root = Node3D.new()
	geometry_root.name = "LimbGeometry"
	scene_root.add_child(geometry_root)
	gizmo_root = Node3D.new()
	gizmo_root.name = "SelectionGizmo"
	scene_root.add_child(gizmo_root)

	camera = Camera3D.new()
	camera.name = "LimbEditorCamera"
	camera.current = true
	camera.fov = 45.0
	scene_root.add_child(camera)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_energy = 1.45
	scene_root.add_child(key_light)
	var fill_light: OmniLight3D = OmniLight3D.new()
	fill_light.position = Vector3(-2.4, 2.0, 2.2)
	fill_light.omni_range = 12.0
	fill_light.light_energy = 2.0
	scene_root.add_child(fill_light)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("527b6c")
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	scene_root.add_child(environment_node)

	_build_reference_axes()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			orbit_dragging = mouse_button.pressed
			if orbit_dragging:
				grab_focus()
			accept_event()
			return
		if (
			mouse_button.pressed
			and mouse_button.ctrl_pressed
			and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP
		):
			orbit_distance = maxf(orbit_distance * (1.0 - ZOOM_STEP), minimum_orbit_distance)
			_update_camera()
			_rebuild_gizmo()
			accept_event()
			return
		if (
			mouse_button.pressed
			and mouse_button.ctrl_pressed
			and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			orbit_distance = minf(orbit_distance * (1.0 + ZOOM_STEP), maximum_orbit_distance)
			_update_camera()
			_rebuild_gizmo()
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_begin_selection_or_drag(_to_viewport_position(mouse_button.position))
			else:
				drag_mode = DragMode.NONE
				rotation_drag_source_directions.clear()
				rotation_drag_source_joint_bases.clear()
				_rebuild_gizmo()
			accept_event()
			return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if drag_mode != DragMode.NONE:
			if drag_mode >= DragMode.ROTATE_X:
				_update_rotation_drag(
					_to_viewport_position(motion.position),
					motion.shift_pressed
				)
			else:
				_update_dimension_drag(_to_viewport_position(motion.position))
			accept_event()
			return
		if orbit_dragging:
			orbit_yaw -= motion.relative.x * ORBIT_SENSITIVITY
			orbit_pitch = clampf(
				orbit_pitch - motion.relative.y * ORBIT_SENSITIVITY,
				MIN_PITCH,
				MAX_PITCH
			)
			_update_camera()
			_rebuild_gizmo()
			accept_event()


func _begin_selection_or_drag(viewport_position: Vector2) -> void:
	if camera == null or selected_segment_index < 0:
		return
	var rotation_axis: int = _rotation_axis_at(viewport_position)
	if rotation_axis >= 0:
		_begin_rotation_drag(rotation_axis, viewport_position)
		return
	if _screen_position(length_handle_world).distance_to(viewport_position) <= HANDLE_HIT_RADIUS_PX:
		_begin_dimension_drag(DragMode.LENGTH, viewport_position)
		return
	if _screen_position(radius_handle_world).distance_to(viewport_position) <= HANDLE_HIT_RADIUS_PX:
		_begin_dimension_drag(DragMode.RADIUS, viewport_position)
		return
	var hit_index: int = _joint_at(viewport_position)
	if hit_index < 0:
		hit_index = _segment_at(viewport_position)
	if hit_index < 0:
		return
	selected_segment_index = hit_index
	_rebuild_geometry(false)
	segment_selected.emit(hit_index)


func _begin_rotation_drag(axis_index: int, viewport_position: Vector2) -> void:
	if (
		limb == null
		or selected_segment_index < 0
		or selected_segment_index >= limb.segments.size()
		or selected_segment_index >= segment_starts.size()
	):
		return
	var joint_basis_world: Basis = _selected_joint_basis_world()
	rotation_drag_pivot_world = segment_starts[selected_segment_index]
	rotation_drag_axis_world = joint_basis_world[axis_index].normalized()
	rotation_drag_start_vector_world = _ray_plane_unit_vector(
		viewport_position,
		rotation_drag_pivot_world,
		rotation_drag_axis_world
	)
	if rotation_drag_start_vector_world.length_squared() <= 0.000001:
		return
	drag_mode = DragMode.ROTATE_X + axis_index
	rotation_drag_source_directions.clear()
	rotation_drag_source_joint_bases.clear()
	for segment_index: int in range(selected_segment_index, limb.segments.size()):
		var segment: LimbSegmentDefinition = limb.segments[segment_index]
		if segment == null or segment.joint == null:
			drag_mode = DragMode.NONE
			rotation_drag_source_directions.clear()
			rotation_drag_source_joint_bases.clear()
			return
		rotation_drag_source_directions.append(segment.rest_direction_local)
		rotation_drag_source_joint_bases.append(segment.joint.joint_basis_local)
	grab_focus()


func _update_rotation_drag(viewport_position: Vector2, snap_rotation: bool) -> void:
	if limb == null or rotation_drag_source_directions.is_empty():
		drag_mode = DragMode.NONE
		return
	var current_vector: Vector3 = _ray_plane_unit_vector(
		viewport_position,
		rotation_drag_pivot_world,
		rotation_drag_axis_world
	)
	if current_vector.length_squared() <= 0.000001:
		return
	var angle: float = rotation_drag_start_vector_world.signed_angle_to(
		current_vector,
		rotation_drag_axis_world
	)
	if snap_rotation:
		angle = snappedf(angle, ROTATION_SNAP_RADIANS)
	var mount_basis: Basis = limb.mount_basis_local.orthonormalized()
	var world_delta: Basis = Basis(rotation_drag_axis_world, angle)
	var local_delta: Basis = (
		mount_basis.transposed() * world_delta * mount_basis
	).orthonormalized()
	var next_directions: Array = []
	var next_joint_bases: Array = []
	for source_direction: Vector3 in rotation_drag_source_directions:
		next_directions.append((local_delta * source_direction).normalized())
	for source_basis: Basis in rotation_drag_source_joint_bases:
		next_joint_bases.append((local_delta * source_basis).orthonormalized())
	if rotation_gizmo_label != null:
		rotation_gizmo_label.text = "ROTATE  %+.1f°%s" % [
			rad_to_deg(angle),
			"  SNAP" if snap_rotation else "",
		]
	joint_pose_change_requested.emit(
		selected_segment_index,
		next_directions,
		next_joint_bases
	)


func _begin_dimension_drag(mode: int, viewport_position: Vector2) -> void:
	if limb == null or selected_segment_index < 0 or selected_segment_index >= limb.segments.size():
		return
	var segment: LimbSegmentDefinition = limb.segments[selected_segment_index]
	if segment == null:
		return
	drag_mode = mode
	drag_start_mouse = viewport_position
	drag_start_length = segment.length
	drag_start_radius = segment.radius
	var anchor_world: Vector3
	var axis_world: Vector3
	if drag_mode == DragMode.LENGTH:
		anchor_world = segment_ends[selected_segment_index]
		axis_world = segment_directions[selected_segment_index]
	else:
		anchor_world = radius_handle_world
		axis_world = _selected_radial_direction()
	var anchor_screen: Vector2 = _screen_position(anchor_world)
	var axis_screen: Vector2 = _screen_position(anchor_world + axis_world) - anchor_screen
	if axis_screen.length_squared() <= 0.0001:
		axis_screen = Vector2.RIGHT
	drag_world_per_pixel = 1.0 / maxf(axis_screen.length(), 1.0)
	drag_axis_screen = axis_screen.normalized()
	grab_focus()


func _update_dimension_drag(viewport_position: Vector2) -> void:
	if limb == null or selected_segment_index < 0 or selected_segment_index >= limb.segments.size():
		drag_mode = DragMode.NONE
		return
	var delta_world: float = (
		(viewport_position - drag_start_mouse).dot(drag_axis_screen) * drag_world_per_pixel
	)
	var next_length: float = drag_start_length
	var next_radius: float = drag_start_radius
	if drag_mode == DragMode.LENGTH:
		next_length = clampf(drag_start_length + delta_world, MINIMUM_LENGTH_M, MAXIMUM_LENGTH_M)
		next_radius = minf(next_radius, next_length * 0.45)
	elif drag_mode == DragMode.RADIUS:
		next_radius = clampf(
			drag_start_radius + delta_world,
			MINIMUM_RADIUS_M,
			minf(MAXIMUM_RADIUS_M, next_length * 0.45)
		)
	else:
		return
	dimensions_change_requested.emit(selected_segment_index, next_length, next_radius)


func _segment_at(viewport_position: Vector2) -> int:
	var best_index: int = -1
	var best_distance: float = INF
	for segment_index: int in range(segment_starts.size()):
		var start_screen: Vector2 = _screen_position(segment_starts[segment_index])
		var end_screen: Vector2 = _screen_position(segment_ends[segment_index])
		var distance: float = _distance_to_screen_segment(viewport_position, start_screen, end_screen)
		var radius_pixels: float = 0.0
		if limb != null and segment_index < limb.segments.size():
			var segment: LimbSegmentDefinition = limb.segments[segment_index]
			if segment != null:
				var midpoint: Vector3 = segment_starts[segment_index].lerp(segment_ends[segment_index], 0.5)
				radius_pixels = (
					_screen_position(midpoint + _radial_direction(segment_directions[segment_index], midpoint) * segment.radius)
					- _screen_position(midpoint)
				).length()
		var threshold: float = maxf(SEGMENT_HIT_RADIUS_PX, radius_pixels + 7.0)
		if distance <= threshold and distance < best_distance:
			best_distance = distance
			best_index = segment_index
	return best_index


func _joint_at(viewport_position: Vector2) -> int:
	var best_index: int = -1
	var best_distance: float = INF
	for joint_index: int in range(segment_starts.size()):
		if camera.is_position_behind(segment_starts[joint_index]):
			continue
		var distance: float = _screen_position(segment_starts[joint_index]).distance_to(
			viewport_position
		)
		if distance <= JOINT_HIT_RADIUS_PX and distance < best_distance:
			best_distance = distance
			best_index = joint_index
	return best_index


func _rotation_axis_at(viewport_position: Vector2) -> int:
	if selected_segment_index < 0 or selected_segment_index >= segment_starts.size():
		return -1
	var best_axis: int = -1
	var best_distance: float = INF
	for axis_index: int in range(3):
		var points: PackedVector3Array = _rotation_ring_world_points(axis_index)
		if points.size() < 2:
			continue
		for point_index: int in range(points.size() - 1):
			if camera.is_position_behind(points[point_index]) or camera.is_position_behind(points[point_index + 1]):
				continue
			var distance: float = _distance_to_screen_segment(
				viewport_position,
				_screen_position(points[point_index]),
				_screen_position(points[point_index + 1])
			)
			if distance <= ROTATION_RING_HIT_RADIUS_PX and distance < best_distance:
				best_distance = distance
				best_axis = axis_index
	return best_axis


func _ray_plane_unit_vector(
	viewport_position: Vector2,
	pivot: Vector3,
	plane_normal: Vector3
) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var ray_origin: Vector3 = camera.project_ray_origin(viewport_position)
	var ray_direction: Vector3 = camera.project_ray_normal(viewport_position).normalized()
	var denominator: float = plane_normal.dot(ray_direction)
	if absf(denominator) <= 0.00001:
		return Vector3.ZERO
	var distance: float = plane_normal.dot(pivot - ray_origin) / denominator
	if not is_finite(distance) or distance < 0.0:
		return Vector3.ZERO
	var offset: Vector3 = ray_origin + ray_direction * distance - pivot
	return offset.normalized() if offset.length_squared() > 0.000001 else Vector3.ZERO


static func _distance_to_screen_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta: Vector2 = end - start
	var length_squared: float = delta.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var fraction: float = clampf((point - start).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(start + delta * fraction)


func _to_viewport_position(local_position: Vector2) -> Vector2:
	if preview_viewport == null:
		return local_position
	return Vector2(
		local_position.x * float(preview_viewport.size.x) / maxf(size.x, 1.0),
		local_position.y * float(preview_viewport.size.y) / maxf(size.y, 1.0)
	)


func _screen_position(world_position: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world_position)


func _rebuild_geometry(reset_camera: bool) -> void:
	if geometry_root == null:
		return
	for child: Node in geometry_root.get_children():
		child.queue_free()
	segment_visuals.clear()
	joint_visuals.clear()
	segment_labels.clear()
	end_effector_visual = null
	segment_starts.clear()
	segment_ends.clear()
	segment_directions.clear()
	if limb == null:
		focus_point = Vector3.ZERO
		_rebuild_gizmo()
		_update_camera()
		return
	var mount_basis: Basis = limb.mount_basis_local.orthonormalized()
	var point: Vector3 = Vector3.ZERO
	var distal_basis: Basis = mount_basis
	for segment_index: int in range(limb.segments.size()):
		var segment: LimbSegmentDefinition = limb.segments[segment_index]
		if segment == null:
			continue
		var direction: Vector3 = (mount_basis * segment.rest_direction_local).normalized()
		if direction.length_squared() <= 0.000001:
			direction = Vector3.DOWN
		var end: Vector3 = point + direction * maxf(segment.length, MINIMUM_LENGTH_M)
		segment_starts.append(point)
		segment_ends.append(end)
		segment_directions.append(direction)
		distal_basis = GeometryBasis.from_y(direction)
		_create_segment_visual(segment, segment_index, point, end, distal_basis)
		point = end
	_create_end_effector_visual(limb.end_effector, point, distal_basis)
	selected_segment_index = _valid_segment_index(selected_segment_index)
	_update_focus_point()
	if reset_camera:
		_frame_limb()
	_update_camera()
	_rebuild_gizmo()


func _create_segment_visual(
	segment: LimbSegmentDefinition,
	segment_index: int,
	start: Vector3,
	end: Vector3,
	basis_value: Basis
) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Part%02d" % (segment_index + 1)
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = segment.radius
	mesh.height = maxf(segment.length, segment.radius * 2.0)
	visual.mesh = mesh
	visual.transform = Transform3D(basis_value, start.lerp(end, 0.5))
	visual.material_override = _material(
		SELECTED_COLOR
		if segment_index == selected_segment_index
		else SEGMENT_COLOR if segment_index % 2 == 0 else SEGMENT_ALTERNATE_COLOR,
		0.18 if segment_index == selected_segment_index else 0.0
	)
	geometry_root.add_child(visual)
	segment_visuals.append(visual)

	var joint: MeshInstance3D = MeshInstance3D.new()
	joint.name = "Joint%02d" % (segment_index + 1)
	var joint_mesh: SphereMesh = SphereMesh.new()
	joint_mesh.radius = maxf(segment.radius * 1.06, 0.035)
	joint_mesh.height = joint_mesh.radius * 2.0
	joint.mesh = joint_mesh
	joint.position = start
	joint.material_override = _material(
		SELECTED_COLOR if segment_index == selected_segment_index else JOINT_COLOR,
		0.35 if segment_index == selected_segment_index else 0.0
	)
	geometry_root.add_child(joint)
	joint_visuals.append(joint)

	var label: Label3D = Label3D.new()
	label.text = str(segment_index + 1)
	label.font_size = 34
	label.modulate = Color.WHITE
	label.outline_size = 5
	label.position = start.lerp(end, 0.5) + Vector3.UP * maxf(segment.radius * 1.8, 0.08)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	geometry_root.add_child(label)
	segment_labels.append(label)


func _create_end_effector_visual(
	effector: LimbEndEffectorDefinition,
	distal_tip: Vector3,
	distal_basis: Basis
) -> void:
	if effector == null or not effector.enabled or not effector.is_physically_present():
		return
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "EndEffector"
	match effector.geometry_type:
		LimbEndEffectorDefinition.GeometryType.SPHERE:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = effector.sphere_radius
			sphere.height = effector.sphere_radius * 2.0
			visual.mesh = sphere
		LimbEndEffectorDefinition.GeometryType.BOX:
			var box: BoxMesh = BoxMesh.new()
			box.size = effector.box_size
			visual.mesh = box
		LimbEndEffectorDefinition.GeometryType.CAPSULE:
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = effector.capsule_radius
			capsule.height = effector.capsule_height
			visual.mesh = capsule
	if visual.mesh == null:
		return
	visual.transform = Transform3D(
		distal_basis * effector.local_basis(),
		distal_tip + distal_basis * effector.local_offset
	)
	visual.material_override = _material(EFFECTOR_COLOR, 0.12)
	geometry_root.add_child(visual)
	end_effector_visual = visual


func _update_geometry_in_place() -> void:
	if limb == null or segment_visuals.size() != limb.segments.size():
		_rebuild_geometry(false)
		return
	segment_starts.clear()
	segment_ends.clear()
	segment_directions.clear()
	var mount_basis: Basis = limb.mount_basis_local.orthonormalized()
	var point: Vector3 = Vector3.ZERO
	var distal_basis: Basis = mount_basis
	for segment_index: int in range(limb.segments.size()):
		var segment: LimbSegmentDefinition = limb.segments[segment_index]
		if segment == null:
			_rebuild_geometry(false)
			return
		var direction: Vector3 = (mount_basis * segment.rest_direction_local).normalized()
		if direction.length_squared() <= 0.000001:
			direction = Vector3.DOWN
		var end: Vector3 = point + direction * maxf(segment.length, MINIMUM_LENGTH_M)
		segment_starts.append(point)
		segment_ends.append(end)
		segment_directions.append(direction)
		distal_basis = GeometryBasis.from_y(direction)

		var visual: MeshInstance3D = segment_visuals[segment_index]
		var mesh: CapsuleMesh = visual.mesh as CapsuleMesh
		if mesh != null:
			mesh.radius = segment.radius
			mesh.height = maxf(segment.length, segment.radius * 2.0)
		visual.transform = Transform3D(distal_basis, point.lerp(end, 0.5))

		var joint: MeshInstance3D = joint_visuals[segment_index]
		var joint_mesh: SphereMesh = joint.mesh as SphereMesh
		if joint_mesh != null:
			joint_mesh.radius = maxf(segment.radius * 1.06, 0.035)
			joint_mesh.height = joint_mesh.radius * 2.0
		joint.position = point
		segment_labels[segment_index].position = (
			point.lerp(end, 0.5) + Vector3.UP * maxf(segment.radius * 1.8, 0.08)
		)
		point = end
	if end_effector_visual != null and limb.end_effector != null:
		end_effector_visual.transform = Transform3D(
			distal_basis * limb.end_effector.local_basis(),
			point + distal_basis * limb.end_effector.local_offset
		)
	_rebuild_gizmo()


func _update_focus_point() -> void:
	if segment_starts.is_empty():
		focus_point = Vector3.ZERO
		return
	var minimum: Vector3 = segment_starts[0]
	var maximum: Vector3 = segment_starts[0]
	for segment_index: int in range(segment_starts.size()):
		minimum = minimum.min(segment_starts[segment_index]).min(segment_ends[segment_index])
		maximum = maximum.max(segment_starts[segment_index]).max(segment_ends[segment_index])
	focus_point = minimum.lerp(maximum, 0.5)


func _frame_limb() -> void:
	var reach: float = limb.maximum_reach() if limb != null else 1.0
	var span: float = maxf(reach, 0.25)
	minimum_orbit_distance = maxf(span * 0.72, 0.45)
	maximum_orbit_distance = maxf(span * 9.0, 6.0)
	orbit_distance = clampf(span * 1.85, minimum_orbit_distance, maximum_orbit_distance)


func _update_camera() -> void:
	if camera == null:
		return
	var horizontal: float = cos(orbit_pitch) * orbit_distance
	camera.position = focus_point + Vector3(
		sin(orbit_yaw) * horizontal,
		sin(orbit_pitch) * orbit_distance,
		cos(orbit_yaw) * horizontal
	)
	camera.look_at(focus_point, Vector3.UP)


func _rebuild_gizmo() -> void:
	if gizmo_root == null:
		return
	if (
		limb == null
		or selected_segment_index < 0
		or selected_segment_index >= segment_starts.size()
		or selected_segment_index >= limb.segments.size()
	):
		length_handle_world = Vector3(1000000.0, 1000000.0, 1000000.0)
		radius_handle_world = length_handle_world
		gizmo_root.visible = false
		return
	var segment: LimbSegmentDefinition = limb.segments[selected_segment_index]
	if segment == null:
		gizmo_root.visible = false
		return
	_ensure_gizmo_nodes()
	gizmo_root.visible = true
	var start: Vector3 = segment_starts[selected_segment_index]
	var end: Vector3 = segment_ends[selected_segment_index]
	var direction: Vector3 = segment_directions[selected_segment_index]
	var radial: Vector3 = _radial_direction(direction, start.lerp(end, 0.5))
	var handle_size: float = clampf(orbit_distance * 0.035, 0.035, 0.18)
	length_handle_world = end + direction * handle_size * 1.15
	radius_handle_world = start.lerp(end, 0.5) + radial * (segment.radius + handle_size * 1.45)
	_update_gizmo_line(length_gizmo_line, end, length_handle_world, handle_size * 0.24)
	_update_gizmo_line(
		radius_gizmo_line,
		start.lerp(end, 0.5),
		radius_handle_world,
		handle_size * 0.24
	)
	length_gizmo_handle.position = length_handle_world
	length_gizmo_handle.scale = Vector3.ONE * handle_size
	radius_gizmo_handle.position = radius_handle_world
	radius_gizmo_handle.scale = Vector3.ONE * handle_size * 1.65
	length_gizmo_label.position = length_handle_world + Vector3.UP * handle_size * 1.7
	radius_gizmo_label.position = radius_handle_world + Vector3.UP * handle_size * 1.7
	rotation_ring_radius = maxf(segment.radius * 2.7, handle_size * 2.8)
	_rebuild_rotation_rings(start)
	rotation_gizmo_label.position = (
		start + _selected_joint_basis_world().y * rotation_ring_radius * 1.28
	)
	if drag_mode < DragMode.ROTATE_X:
		rotation_gizmo_label.text = "ROTATE JOINT"


func _ensure_gizmo_nodes() -> void:
	if length_gizmo_line != null:
		return
	length_gizmo_line = _create_gizmo_line(LENGTH_HANDLE_COLOR)
	radius_gizmo_line = _create_gizmo_line(RADIUS_HANDLE_COLOR)

	length_gizmo_handle = MeshInstance3D.new()
	var diamond_mesh: SphereMesh = SphereMesh.new()
	diamond_mesh.radius = 1.0
	diamond_mesh.height = 2.0
	diamond_mesh.radial_segments = 8
	diamond_mesh.rings = 4
	length_gizmo_handle.mesh = diamond_mesh
	length_gizmo_handle.rotation_degrees = Vector3(0.0, 0.0, 45.0)
	length_gizmo_handle.material_override = _material(LENGTH_HANDLE_COLOR, 0.55)
	length_gizmo_handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gizmo_root.add_child(length_gizmo_handle)

	radius_gizmo_handle = MeshInstance3D.new()
	var radius_mesh: BoxMesh = BoxMesh.new()
	radius_mesh.size = Vector3.ONE
	radius_gizmo_handle.mesh = radius_mesh
	radius_gizmo_handle.material_override = _material(RADIUS_HANDLE_COLOR, 0.55)
	radius_gizmo_handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gizmo_root.add_child(radius_gizmo_handle)

	length_gizmo_label = _create_gizmo_label("LENGTH", LENGTH_HANDLE_COLOR)
	radius_gizmo_label = _create_gizmo_label("THICKNESS", RADIUS_HANDLE_COLOR)
	for axis_index: int in range(3):
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo_root.add_child(ring)
		rotation_ring_visuals.append(ring)
	rotation_gizmo_label = _create_gizmo_label("ROTATE JOINT", SELECTED_COLOR)


func _rebuild_rotation_rings(_pivot: Vector3) -> void:
	var colors: Array[Color] = [AXIS_X_COLOR, AXIS_Y_COLOR, AXIS_Z_COLOR]
	for axis_index: int in range(mini(rotation_ring_visuals.size(), 3)):
		var points: PackedVector3Array = _rotation_ring_world_points(axis_index)
		var mesh: ImmediateMesh = ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded_material(colors[axis_index]))
		for point_index: int in range(points.size() - 1):
			mesh.surface_add_vertex(points[point_index])
			mesh.surface_add_vertex(points[point_index + 1])
		mesh.surface_end()
		rotation_ring_visuals[axis_index].mesh = mesh


func _rotation_ring_world_points(axis_index: int) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if selected_segment_index < 0 or selected_segment_index >= segment_starts.size():
		return result
	var basis_value: Basis = _selected_joint_basis_world()
	var tangent: Vector3
	var bitangent: Vector3
	match axis_index:
		0:
			tangent = basis_value.y
			bitangent = basis_value.z
		1:
			tangent = basis_value.z
			bitangent = basis_value.x
		_:
			tangent = basis_value.x
			bitangent = basis_value.y
	var pivot: Vector3 = segment_starts[selected_segment_index]
	result.resize(ROTATION_RING_POINT_COUNT + 1)
	for point_index: int in range(ROTATION_RING_POINT_COUNT + 1):
		var angle: float = TAU * float(point_index) / float(ROTATION_RING_POINT_COUNT)
		result[point_index] = pivot + (
			tangent * cos(angle) + bitangent * sin(angle)
		) * rotation_ring_radius
	return result


func _selected_joint_basis_world() -> Basis:
	if limb == null or selected_segment_index < 0 or selected_segment_index >= limb.segments.size():
		return Basis.IDENTITY
	var segment: LimbSegmentDefinition = limb.segments[selected_segment_index]
	if segment == null or segment.joint == null:
		return limb.mount_basis_local.orthonormalized()
	return (
		limb.mount_basis_local.orthonormalized()
		* segment.joint.joint_basis_local.orthonormalized()
	).orthonormalized()


func _create_gizmo_line(color: Color) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	visual.mesh = mesh
	visual.material_override = _material(color, 0.35)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gizmo_root.add_child(visual)
	return visual


func _update_gizmo_line(
	visual: MeshInstance3D,
	start: Vector3,
	end: Vector3,
	radius: float
) -> void:
	var direction: Vector3 = end - start
	var length: float = maxf(direction.length(), 0.000001)
	var mesh: CylinderMesh = visual.mesh as CylinderMesh
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	visual.transform = Transform3D(
		GeometryBasis.from_y(direction / length),
		start.lerp(end, 0.5)
	)


func _create_gizmo_label(text_value: String, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text_value
	label.font_size = 24
	label.modulate = color
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gizmo_root.add_child(label)
	return label


func _selected_radial_direction() -> Vector3:
	if selected_segment_index < 0 or selected_segment_index >= segment_directions.size():
		return Vector3.RIGHT
	return _radial_direction(
		segment_directions[selected_segment_index],
		segment_starts[selected_segment_index].lerp(segment_ends[selected_segment_index], 0.5)
	)


func _radial_direction(direction: Vector3, world_position: Vector3) -> Vector3:
	var view_direction: Vector3 = (
		(camera.position - world_position).normalized()
		if camera != null
		else Vector3.FORWARD
	)
	var radial: Vector3 = direction.cross(view_direction).normalized()
	if radial.length_squared() <= 0.000001:
		var helper: Vector3 = Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		radial = direction.cross(helper).normalized()
	return radial


func _build_reference_axes() -> void:
	if scene_root == null:
		return
	var axes: MeshInstance3D = MeshInstance3D.new()
	axes.name = "ReferenceAxes"
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded_material(AXIS_X_COLOR))
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.RIGHT * 0.3)
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded_material(AXIS_Y_COLOR))
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.UP * 0.3)
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded_material(AXIS_Z_COLOR))
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.BACK * 0.3)
	mesh.surface_end()
	axes.mesh = mesh
	axes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(axes)

	var grid: MeshInstance3D = MeshInstance3D.new()
	grid.name = "ReferenceGrid"
	var grid_mesh: ImmediateMesh = ImmediateMesh.new()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded_material(GRID_COLOR))
	for line_index: int in range(-5, 6):
		var coordinate: float = float(line_index) * 0.2
		grid_mesh.surface_add_vertex(Vector3(-1.0, 0.0, coordinate))
		grid_mesh.surface_add_vertex(Vector3(1.0, 0.0, coordinate))
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.0, -1.0))
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.0, 1.0))
	grid_mesh.surface_end()
	grid.mesh = grid_mesh
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(grid)


func _material(color: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.15
	material.roughness = 0.55
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_strength
	return material


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
