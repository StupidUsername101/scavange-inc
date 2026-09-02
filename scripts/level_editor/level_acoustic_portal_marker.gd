class_name LevelAcousticPortalMarker
extends Node3D

const AUTHORING := preload("res://scripts/level_editor/level_acoustic_authoring.gd")
const COLOR_PORTAL := Color(0.9, 0.22, 0.95, 0.92)
const COLOR_SELECTED := Color(1.0, 0.68, 0.16, 1.0)
const PICK_RADIUS := 0.28

var portal_id := 0
var probe_a_id := 0
var probe_b_id := 0
var descriptor: Dictionary = {}
var _probe_a: LevelAcousticProbeMarker
var _probe_b: LevelAcousticProbeMarker
var _line_mesh: ImmediateMesh
var _material: StandardMaterial3D


func configure(
	value: Dictionary,
	probe_a: LevelAcousticProbeMarker,
	probe_b: LevelAcousticProbeMarker
) -> bool:
	var safe := AUTHORING.sanitize_portal(value)
	if safe.is_empty() or probe_a == null or probe_b == null:
		return false
	portal_id = int(safe["id"])
	probe_a_id = int(safe["probe_a_id"])
	probe_b_id = int(safe["probe_b_id"])
	descriptor = safe
	_probe_a = probe_a
	_probe_b = probe_b
	name = "AcousticPortal_%03d" % portal_id
	_build_visual()
	refresh()
	return true


func snapshot() -> Dictionary:
	return AUTHORING.sanitize_portal(descriptor)


func set_selected(value: bool) -> void:
	if _material != null:
		_material.albedo_color = COLOR_SELECTED if value else COLOR_PORTAL


func refresh() -> void:
	if _line_mesh == null or _probe_a == null or _probe_b == null:
		return
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_line_mesh.surface_add_vertex(to_local(_probe_a.global_position))
	_line_mesh.surface_add_vertex(to_local(_probe_b.global_position))
	_line_mesh.surface_end()


func ray_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	if _probe_a == null or _probe_b == null:
		return INF
	var segment_a := _probe_a.global_position
	var segment_b := _probe_b.global_position
	var ray_end := ray_origin + ray_direction.normalized() * 10000.0
	var closest := Geometry3D.get_closest_points_between_segments(
		ray_origin,
		ray_end,
		segment_a,
		segment_b
	)
	if closest.size() < 2:
		return INF
	var ray_point := closest[0]
	var segment_point := closest[1]
	if ray_point.distance_squared_to(segment_point) > PICK_RADIUS * PICK_RADIUS:
		return INF
	var distance := (ray_point - ray_origin).dot(ray_direction.normalized())
	return distance if distance >= 0.0 else INF


func _build_visual() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR_PORTAL
	_material.no_depth_test = true
	_line_mesh = ImmediateMesh.new()
	var visual := MeshInstance3D.new()
	visual.name = "PortalEdge"
	visual.mesh = _line_mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
