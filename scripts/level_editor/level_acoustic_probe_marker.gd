class_name LevelAcousticProbeMarker
extends Node3D

const AUTHORING := preload("res://scripts/level_editor/level_acoustic_authoring.gd")
const COLOR_PROBE := Color(0.15, 0.92, 1.0, 0.9)
const COLOR_SELECTED := Color(1.0, 0.68, 0.16, 1.0)
const PICK_RADIUS := 0.38

var probe_id := 0
var descriptor: Dictionary = {}
var _material: StandardMaterial3D


func configure(value: Dictionary) -> bool:
	var safe := AUTHORING.sanitize_probe(value)
	if safe.is_empty():
		return false
	probe_id = int(safe["id"])
	descriptor = safe
	name = "AcousticProbe_%03d" % probe_id
	position = safe["position"]
	_build_visual()
	return true


func snapshot() -> Dictionary:
	var result := descriptor.duplicate(false)
	result["id"] = probe_id
	result["position"] = position
	return AUTHORING.sanitize_probe(result)


func set_selected(value: bool) -> void:
	if _material != null:
		_material.albedo_color = COLOR_SELECTED if value else COLOR_PROBE


func ray_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	var direction := ray_direction.normalized()
	var to_center := global_position - ray_origin
	var along := to_center.dot(direction)
	if along < 0.0:
		return INF
	var closest := ray_origin + direction * along
	return along if closest.distance_squared_to(global_position) <= PICK_RADIUS * PICK_RADIUS else INF


func _build_visual() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 12
	sphere.rings = 6
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR_PROBE
	_material.no_depth_test = true
	sphere.material = _material
	var visual := MeshInstance3D.new()
	visual.name = "ProbeMarker"
	visual.mesh = sphere
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.28
	ring.rings = 20
	ring.ring_segments = 6
	ring.material = _material
	var ring_visual := MeshInstance3D.new()
	ring_visual.name = "ProbeInfluenceRing"
	ring_visual.mesh = ring
	ring_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_visual)

