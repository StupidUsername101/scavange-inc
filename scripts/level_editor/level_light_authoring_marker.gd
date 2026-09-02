class_name LevelLightAuthoringMarker
extends Node3D

const LIGHT_AUTHORING := preload(
	"res://scripts/level_editor/level_light_authoring.gd"
)
const MARKER_RADIUS := 0.22
const SELECTED_COLOR := Color("f1a72c")
const NORMAL_COLOR := Color("66dca0")

var light_id := 0
var descriptor_data: Dictionary = {}
var preview_light: Light3D
var marker_visual: MeshInstance3D
var direction_visual: MeshInstance3D
var marker_material: StandardMaterial3D


func configure(raw: Dictionary, selected := false) -> bool:
	var safe: Dictionary = LIGHT_AUTHORING.sanitize_descriptor(raw)
	if safe.is_empty():
		return false
	descriptor_data = safe
	light_id = int(safe["id"])
	position = safe["position"]
	rotation = safe["rotation"]
	_ensure_marker_visual()
	_rebuild_or_update_light()
	set_selected(selected)
	_refresh_direction_visual()
	return true


func descriptor() -> Dictionary:
	var result := descriptor_data.duplicate(true)
	result["position"] = position
	result["rotation"] = rotation
	return LIGHT_AUTHORING.sanitize_descriptor(result)


func set_selected(value: bool) -> void:
	_ensure_marker_visual()
	var color := SELECTED_COLOR if value else NORMAL_COLOR
	marker_material.albedo_color = color
	marker_material.emission = color
	marker_material.emission_energy_multiplier = 1.35 if value else 0.8


func ray_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	var direction := ray_direction.normalized()
	var offset := global_position - ray_origin
	var distance_along_ray := offset.dot(direction)
	if distance_along_ray < 0.0:
		return INF
	var closest := ray_origin + direction * distance_along_ray
	var world_radius := MARKER_RADIUS * maxf(
		global_basis.x.length(),
		maxf(global_basis.y.length(), global_basis.z.length())
	)
	return (
		distance_along_ray
		if closest.distance_squared_to(global_position) <= world_radius * world_radius
		else INF
	)


func _ensure_marker_visual() -> void:
	if marker_visual != null:
		return
	marker_material = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.emission_enabled = true
	marker_material.no_depth_test = true
	marker_visual = MeshInstance3D.new()
	marker_visual.name = "LightAuthoringHandle"
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	marker_visual.mesh = sphere
	marker_visual.material_override = marker_material
	marker_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker_visual)
	direction_visual = MeshInstance3D.new()
	direction_visual.name = "LightDirectionHandle"
	direction_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	direction_visual.material_override = marker_material
	add_child(direction_visual)


func _rebuild_or_update_light() -> void:
	if (
		preview_light != null
		and LIGHT_AUTHORING.apply_to_light(preview_light, _local_descriptor())
	):
		return
	if preview_light != null:
		remove_child(preview_light)
		preview_light.free()
	preview_light = LIGHT_AUTHORING.instantiate_light(_local_descriptor())
	if preview_light != null:
		preview_light.position = Vector3.ZERO
		preview_light.rotation = Vector3.ZERO
		preview_light.name = "PreviewLight"
		add_child(preview_light)


func _local_descriptor() -> Dictionary:
	var result := descriptor_data.duplicate(true)
	result["position"] = Vector3.ZERO
	result["rotation"] = Vector3.ZERO
	return result


func _refresh_direction_visual() -> void:
	if direction_visual == null:
		return
	var type: StringName = descriptor_data.get(
		"type",
		LIGHT_AUTHORING.TYPE_OMNI
	)
	direction_visual.visible = type != LIGHT_AUTHORING.TYPE_OMNI
	if not direction_visual.visible:
		return
	var length := minf(float(descriptor_data.get("range", 12.0)), 3.0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.07
	mesh.height = maxf(length, 0.2)
	mesh.radial_segments = 10
	direction_visual.mesh = mesh
	direction_visual.rotation.x = PI * 0.5
	direction_visual.position = Vector3(0.0, 0.0, -length * 0.5)
