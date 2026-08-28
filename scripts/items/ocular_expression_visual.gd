class_name OcularExpressionVisual
extends Node3D

## Reusable mechanical pupil/eyelid surface for any ocular item with LeftLens and RightLens nodes.
## Geometry is derived once from each lens AABB; expression updates only mutate cached transforms.

const PUPIL_RADIUS_RATIO := 0.18
const PUPIL_TRAVEL_X_RATIO := 0.21
const PUPIL_TRAVEL_Y_RATIO := 0.16
const LID_HEIGHT_RATIO := 0.62
const LID_OPEN_CENTER_RATIO := 0.80
const LID_CLOSED_CENTER_RATIO := 0.18
const SURFACE_GAP := 0.0025
const OVERLAY_DEPTH := 0.004

class EyeSurface:
	var lens: MeshInstance3D
	var pupil: MeshInstance3D
	var upper_lid: MeshInstance3D
	var lower_lid: MeshInstance3D
	var width := 0.1
	var height := 0.1
	var front_z := -0.05

var _left := EyeSurface.new()
var _right := EyeSurface.new()
var _pupil_material: StandardMaterial3D
var _lid_material: StandardMaterial3D
var _built := false


func _ready() -> void:
	_ensure_surfaces()
	apply_ocular_expression(
		Vector2.ZERO,
		Vector2.ZERO,
		1.0,
		0.96,
		0.96,
		0.0,
		0.0
	)


func apply_ocular_expression(
	left_pupil_offset: Vector2,
	right_pupil_offset: Vector2,
	pupil_scale: float,
	left_lid_openness: float,
	right_lid_openness: float,
	left_lid_tilt: float,
	right_lid_tilt: float
) -> void:
	_ensure_surfaces()
	if not _built:
		return
	_apply_eye(
		_left,
		left_pupil_offset,
		pupil_scale,
		left_lid_openness,
		left_lid_tilt
	)
	_apply_eye(
		_right,
		right_pupil_offset,
		pupil_scale,
		right_lid_openness,
		right_lid_tilt
	)


func _ensure_surfaces() -> void:
	if _built:
		return
	_left.lens = get_node_or_null("LeftLens") as MeshInstance3D
	_right.lens = get_node_or_null("RightLens") as MeshInstance3D
	if _left.lens == null or _right.lens == null:
		return
	_pupil_material = _create_pupil_material()
	_lid_material = _create_lid_material()
	_build_eye_surface(_left, "LeftExpression")
	_build_eye_surface(_right, "RightExpression")
	_built = true


func _build_eye_surface(surface: EyeSurface, node_name: String) -> void:
	var bounds := surface.lens.get_aabb()
	surface.width = maxf(bounds.size.x, 0.02)
	surface.height = maxf(bounds.size.y, 0.02)
	surface.front_z = bounds.position.z - SURFACE_GAP

	var overlays := Node3D.new()
	overlays.name = node_name
	surface.lens.add_child(overlays)

	surface.pupil = MeshInstance3D.new()
	surface.pupil.name = "Pupil"
	surface.pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pupil_mesh := CylinderMesh.new()
	var radius := minf(surface.width, surface.height) * PUPIL_RADIUS_RATIO
	pupil_mesh.top_radius = radius
	pupil_mesh.bottom_radius = radius
	pupil_mesh.height = OVERLAY_DEPTH
	pupil_mesh.radial_segments = 16
	pupil_mesh.rings = 1
	pupil_mesh.material = _pupil_material
	surface.pupil.mesh = pupil_mesh
	surface.pupil.rotation.x = PI * 0.5
	overlays.add_child(surface.pupil)

	surface.upper_lid = _create_lid(
		"UpperLid",
		surface.width,
		surface.height
	)
	overlays.add_child(surface.upper_lid)
	surface.lower_lid = _create_lid(
		"LowerLid",
		surface.width,
		surface.height
	)
	overlays.add_child(surface.lower_lid)


func _create_lid(node_name: String, width: float, height: float) -> MeshInstance3D:
	var lid := MeshInstance3D.new()
	lid.name = node_name
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(
		width * 1.08,
		height * LID_HEIGHT_RATIO,
		OVERLAY_DEPTH
	)
	lid_mesh.material = _lid_material
	lid.mesh = lid_mesh
	return lid


func _apply_eye(
	surface: EyeSurface,
	pupil_offset: Vector2,
	pupil_scale_value: float,
	lid_openness: float,
	lid_tilt: float
) -> void:
	var safe_offset := Vector2(
		clampf(pupil_offset.x, -1.0, 1.0),
		clampf(pupil_offset.y, -1.0, 1.0)
	)
	var safe_scale := clampf(pupil_scale_value, 0.72, 1.24)
	surface.pupil.position = Vector3(
		safe_offset.x * surface.width * PUPIL_TRAVEL_X_RATIO,
		safe_offset.y * surface.height * PUPIL_TRAVEL_Y_RATIO,
		surface.front_z - SURFACE_GAP
	)
	# The cylinder's radius lies in local X/Z before its ninety-degree rotation.
	surface.pupil.scale = Vector3(safe_scale, 1.0, safe_scale)

	var openness := clampf(lid_openness, 0.0, 1.0)
	var lid_center := lerpf(
		surface.height * LID_CLOSED_CENTER_RATIO,
		surface.height * LID_OPEN_CENTER_RATIO,
		openness
	)
	var lid_z := surface.front_z - SURFACE_GAP * 2.0
	surface.upper_lid.position = Vector3(0.0, lid_center, lid_z)
	surface.lower_lid.position = Vector3(0.0, -lid_center, lid_z - 0.0005)
	surface.upper_lid.rotation.z = clampf(lid_tilt, -0.16, 0.16)
	surface.lower_lid.rotation.z = clampf(-lid_tilt * 0.24, -0.04, 0.04)


static func _create_pupil_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.004, 0.008, 0.007, 1.0)
	return material


static func _create_lid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.018, 0.025, 0.023, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.002, 0.006, 0.004, 1.0)
	return material
