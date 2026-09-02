class_name LevelSpeakerAuthoringMarker
extends SpeakerArrayEmitter3D

const DRAFT_COLOR := Color("f1a72c")
const FINAL_COLOR := Color("4de88d")

var system_id := 0
var _cabinet: MeshInstance3D
var _front: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	if _cabinet == null:
		_build_visual()


func configure_editor_marker(finalized := false) -> void:
	if _cabinet == null:
		_build_visual()
	set_finalized(finalized)


func set_finalized(value: bool) -> void:
	if _material == null:
		_build_visual()
	_material.albedo_color = FINAL_COLOR if value else DRAFT_COLOR
	_material.emission = _material.albedo_color
	_material.emission_energy_multiplier = 0.55 if value else 0.8


func descriptor() -> Dictionary:
	return {
		"position": position,
		"rotation": rotation,
		"is_indoor": is_indoor,
		"installation_gain_db": installation_gain_db,
		"cabinet_size": sanitized_cabinet_size(),
	}


func _build_visual() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = DRAFT_COLOR
	_material.emission_enabled = true
	_material.emission = DRAFT_COLOR
	_material.emission_energy_multiplier = 0.8
	_material.no_depth_test = true
	_cabinet = MeshInstance3D.new()
	_cabinet.name = "SpeakerCabinetPreview"
	var cabinet_mesh := BoxMesh.new()
	cabinet_mesh.size = sanitized_cabinet_size()
	_cabinet.mesh = cabinet_mesh
	_cabinet.material_override = _material
	_cabinet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cabinet)
	_front = MeshInstance3D.new()
	_front.name = "SpeakerFrontPreview"
	var front_mesh := CylinderMesh.new()
	front_mesh.top_radius = minf(cabinet_size.x, cabinet_size.y) * 0.3
	front_mesh.bottom_radius = front_mesh.top_radius
	front_mesh.height = maxf(cabinet_size.z * 0.12, 0.025)
	front_mesh.radial_segments = 16
	_front.mesh = front_mesh
	_front.rotation.x = PI * 0.5
	_front.position = Vector3(0.0, 0.0, cabinet_size.z * 0.56)
	_front.material_override = _material
	_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_front)
