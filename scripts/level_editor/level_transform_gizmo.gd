class_name LevelTransformGizmo
extends Node3D

## Allocation-light editor transform handles. Picking is performed in screen
## space against the same geometry the user sees, so foreshortened axes and
## rings remain usable without physics bodies or collision layers.

const MODE_HIDDEN := &"hidden"
const MODE_MOVE := &"move"
const MODE_ROTATE := &"rotate"
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS: Array[Color] = [
	Color("ef4b4b"),
	Color("62d86f"),
	Color("4c8ff2"),
]
const ARROW_START := 0.16
const ARROW_END := 1.18
const RING_RADIUS := 0.91
const RING_SEGMENTS := 72
const PICK_RADIUS_PIXELS := 13.0

var active_mode: StringName = MODE_HIDDEN
var hover_axis := -1
var move_roots: Array[Node3D] = []
var rotate_roots: Array[Node3D] = []
var move_materials: Array[StandardMaterial3D] = []
var rotate_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_build_handles()
	set_mode(MODE_HIDDEN)


func set_mode(mode: StringName) -> void:
	var mode_changed := active_mode != mode
	active_mode = mode
	visible = mode == MODE_MOVE or mode == MODE_ROTATE
	for root: Node3D in move_roots:
		root.visible = mode == MODE_MOVE
	for root: Node3D in rotate_roots:
		root.visible = mode == MODE_ROTATE
	if mode_changed:
		set_hover_axis(-1)


func set_hover_axis(axis_index: int) -> void:
	if hover_axis == axis_index:
		return
	hover_axis = axis_index
	for index: int in range(AXES.size()):
		_apply_material_state(
			move_materials[index],
			AXIS_COLORS[index],
			index == hover_axis
		)
		_apply_material_state(
			rotate_materials[index],
			AXIS_COLORS[index],
			index == hover_axis
		)


func axis_vector(axis_index: int) -> Vector3:
	return AXES[axis_index] if axis_index >= 0 and axis_index < AXES.size() else Vector3.ZERO


func pick_axis(camera: Camera3D, viewport_position: Vector2) -> int:
	if not visible or camera == null:
		return -1
	if active_mode == MODE_MOVE:
		return _pick_move_axis(camera, viewport_position)
	if active_mode == MODE_ROTATE:
		return _pick_rotation_axis(camera, viewport_position)
	return -1


func update_screen_scale(camera: Camera3D, viewport_height: float) -> void:
	if camera == null or viewport_height <= 1.0:
		return
	var distance := maxf(camera.global_position.distance_to(global_position), 0.05)
	var visible_height := 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	var world_per_pixel := visible_height / viewport_height
	var uniform_scale := clampf(world_per_pixel * 92.0, 0.08, 500.0)
	scale = Vector3.ONE * uniform_scale


func _build_handles() -> void:
	for axis_index: int in range(AXES.size()):
		var move_material := _axis_material(AXIS_COLORS[axis_index])
		move_materials.append(move_material)
		var move_root := Node3D.new()
		move_root.name = "%sMoveArrow" % _axis_name(axis_index)
		move_root.basis = _orientation_from_y(AXES[axis_index])
		add_child(move_root)
		move_roots.append(move_root)

		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.025
		shaft_mesh.bottom_radius = 0.025
		shaft_mesh.height = 0.76
		shaft_mesh.radial_segments = 10
		shaft_mesh.rings = 1
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft"
		shaft.mesh = shaft_mesh
		shaft.position.y = 0.56
		shaft.material_override = move_material
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		move_root.add_child(shaft)

		var tip_mesh := CylinderMesh.new()
		tip_mesh.top_radius = 0.0
		tip_mesh.bottom_radius = 0.095
		tip_mesh.height = 0.26
		tip_mesh.radial_segments = 14
		tip_mesh.rings = 1
		var tip := MeshInstance3D.new()
		tip.name = "ArrowHead"
		tip.mesh = tip_mesh
		tip.position.y = 1.07
		tip.material_override = move_material
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		move_root.add_child(tip)

		var rotate_material := _axis_material(AXIS_COLORS[axis_index])
		rotate_materials.append(rotate_material)
		var rotate_root := Node3D.new()
		rotate_root.name = "%sRotationRing" % _axis_name(axis_index)
		rotate_root.basis = _orientation_from_y(AXES[axis_index])
		add_child(rotate_root)
		rotate_roots.append(rotate_root)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.875
		torus.outer_radius = 0.94
		torus.rings = RING_SEGMENTS
		torus.ring_segments = 8
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = torus
		ring.material_override = rotate_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotate_root.add_child(ring)


func _pick_move_axis(camera: Camera3D, pointer: Vector2) -> int:
	var best_axis := -1
	var best_distance := PICK_RADIUS_PIXELS
	for axis_index: int in range(AXES.size()):
		var axis := AXES[axis_index]
		var start := global_position + axis * scale.x * ARROW_START
		var finish := global_position + axis * scale.x * ARROW_END
		if camera.is_position_behind(start) or camera.is_position_behind(finish):
			continue
		var distance := _point_segment_distance(
			pointer,
			camera.unproject_position(start),
			camera.unproject_position(finish)
		)
		if distance < best_distance:
			best_distance = distance
			best_axis = axis_index
	return best_axis


func _pick_rotation_axis(camera: Camera3D, pointer: Vector2) -> int:
	var best_axis := -1
	var best_distance := PICK_RADIUS_PIXELS
	for axis_index: int in range(AXES.size()):
		var axis := AXES[axis_index]
		var tangent := _ring_tangent(axis)
		var bitangent := axis.cross(tangent).normalized()
		var previous_world := global_position + tangent * scale.x * RING_RADIUS
		for segment_index: int in range(1, RING_SEGMENTS + 1):
			var angle := TAU * float(segment_index) / float(RING_SEGMENTS)
			var next_world := global_position + (
				tangent * cos(angle) + bitangent * sin(angle)
			) * scale.x * RING_RADIUS
			if (
				not camera.is_position_behind(previous_world)
				and not camera.is_position_behind(next_world)
			):
				var distance := _point_segment_distance(
					pointer,
					camera.unproject_position(previous_world),
					camera.unproject_position(next_world)
				)
				if distance < best_distance:
					best_distance = distance
					best_axis = axis_index
			previous_world = next_world
	return best_axis


static func _axis_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.94)
	material.no_depth_test = true
	return material


static func _apply_material_state(
	material: StandardMaterial3D,
	axis_color: Color,
	hovered: bool
) -> void:
	var base_color := Color(axis_color, 0.94)
	if hovered:
		base_color = base_color.lerp(Color.WHITE, 0.48)
		base_color.a = 1.0
	material.albedo_color = base_color


static func _orientation_from_y(axis: Vector3) -> Basis:
	if axis == Vector3.RIGHT:
		return Basis(Vector3.BACK, -PI * 0.5)
	if axis == Vector3.BACK:
		return Basis(Vector3.RIGHT, PI * 0.5)
	return Basis.IDENTITY


static func _ring_tangent(axis: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP


static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var amount := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * amount)


static func _axis_name(axis_index: int) -> String:
	return ["X", "Y", "Z"][axis_index]
