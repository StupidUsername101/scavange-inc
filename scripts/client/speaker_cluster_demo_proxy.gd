class_name SpeakerClusterDemoProxy
extends "res://scripts/audio/speaker_array_3d.gd"

const BEACON_SCRIPT := preload("res://scripts/client/fieldlink_device_beacon.gd")
const CONE_ATTACK_SPEED := 96.0
const CONE_RELEASE_SPEED := 28.0
const MAX_CONE_RADIAL_SCALE := 0.065
const MAX_CONE_DEPTH_SCALE := 0.028
const MAX_CONE_EXCURSION := 0.014

var _unit_box: BoxMesh
var _unit_cylinder: CylinderMesh
var _materials: Dictionary[StringName, Material] = {}
var _speaker_cones: Array[MeshInstance3D] = []
var _speaker_rest_scales: Array[Vector3] = []
var _speaker_rest_positions: Array[Vector3] = []
var _speaker_levels := PackedFloat32Array()
var _emitter_ids := PackedInt32Array()


func _ready() -> void:
	super._ready()
	add_to_group(&"speaker_cluster_demo_proxy")
	_build_shared_meshes()
	_build_materials()
	if _speaker_markers.is_empty():
		push_warning("%s has no SpeakerArrayEmitter3D children" % _cluster_display_name())
	_build_speakers()
	_build_scanner_beacon()
	set_process(true)


func _build_shared_meshes() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	_unit_cylinder = CylinderMesh.new()
	_unit_cylinder.top_radius = 1.0
	_unit_cylinder.bottom_radius = 1.0
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 24


func _process(delta: float) -> void:
	var client := get_node_or_null("/root/Client")
	var renderer := (
		client.get("radio_audio_renderer") as RadioAudioRenderer
		if client != null
		else null
	)
	for speaker_index: int in range(_speaker_cones.size()):
		var target_level := 0.0
		if is_instance_valid(renderer):
			target_level = renderer.get_music_visual_level(
				_emitter_ids[speaker_index],
				_shared_program_group_id()
			)
		var response_speed := (
			CONE_ATTACK_SPEED
			if target_level > _speaker_levels[speaker_index]
			else CONE_RELEASE_SPEED
		)
		_speaker_levels[speaker_index] = lerpf(
			_speaker_levels[speaker_index],
			target_level,
			1.0 - exp(-response_speed * maxf(delta, 0.0))
		)
		_apply_speaker_level(speaker_index, _speaker_levels[speaker_index])


func _build_materials() -> void:
	_materials[&"speaker_body"] = VisualMaterialFactory.standard(Color("111719"), 0.22, 0.52)
	_materials[&"speaker_baffle"] = VisualMaterialFactory.standard(Color("252c2e"), 0.12, 0.72)
	_materials[&"speaker_trim"] = VisualMaterialFactory.standard(Color("8b7852"), 0.72, 0.28)
	_materials[&"speaker_cone"] = VisualMaterialFactory.standard(Color("030404"), 0.02, 0.86)


func _build_speakers() -> void:
	for speaker_index: int in range(_speaker_markers.size()):
		var speaker := _speaker_markers[speaker_index]
		var cabinet_size := speaker.sanitized_cabinet_size()
		var front_z := cabinet_size.z * 0.5
		var face_width := cabinet_size.x * 0.87
		var face_height := cabinet_size.y * 0.896
		var trim_height := maxf(cabinet_size.y * 0.041, 0.025)
		var trim_depth := maxf(cabinet_size.z * 0.143, 0.025)
		var cone_radius := minf(cabinet_size.x, cabinet_size.y) * 0.299
		var cone_y := -cabinet_size.y * 0.03
		_add_speaker_box(
			speaker,
			"Cabinet",
			Vector3.ZERO,
			cabinet_size,
			_materials[&"speaker_body"]
		)
		_add_speaker_box(
			speaker,
			"Baffle",
			Vector3(0.0, 0.0, front_z + cabinet_size.z * 0.036),
			Vector3(
				face_width,
				face_height,
				maxf(cabinet_size.z * 0.13, 0.025)
			),
			_materials[&"speaker_baffle"]
		)
		for trim_sign: float in [-1.0, 1.0]:
			_add_speaker_box(
				speaker,
				"BottomTrim" if trim_sign < 0.0 else "TopTrim",
				Vector3(
					0.0,
					trim_sign * cabinet_size.y * 0.418,
					front_z + cabinet_size.z * 0.143
				),
				Vector3(cabinet_size.x * 0.891, trim_height, trim_depth),
				_materials[&"speaker_trim"]
			)
		var trim := _add_speaker_disc(
			speaker,
			"SpeakerTrim",
			cone_radius * 1.164,
			maxf(cabinet_size.z * 0.167, 0.025),
			front_z + cabinet_size.z * 0.179,
			_materials[&"speaker_trim"]
		)
		trim.position.y = cone_y
		var cone := _add_speaker_disc(
			speaker,
			"SpeakerCone",
			cone_radius,
			maxf(cabinet_size.z * 0.202, 0.025),
			front_z + cabinet_size.z * 0.267,
			_materials[&"speaker_cone"]
		)
		cone.position.y = cone_y
		_speaker_cones.append(cone)
		_speaker_rest_scales.append(cone.scale)
		_speaker_rest_positions.append(cone.position)
		_speaker_levels.append(0.0)
		_emitter_ids.append(_emitter_id(speaker_index))


func _build_scanner_beacon() -> void:
	var beacon := BEACON_SCRIPT.new() as FieldlinkDeviceBeacon
	beacon.name = "%sBeacon" % _cluster_contact_id().to_pascal_case()
	beacon.position = _scanner_beacon_position()
	beacon.contact_id = _cluster_contact_id()
	beacon.display_name = _cluster_display_name()
	beacon.device_class = (
		array_definition.device_class
		if array_definition != null
		else &"PA ARRAY"
	)
	beacon.control_type = &"speaker_cluster"
	beacon.status_text = "ARRAY ONLINE"
	beacon.signal_strength = (
		array_definition.scanner_signal_strength
		if array_definition != null
		else 1.35
	)
	add_child(beacon)


func _scanner_beacon_position() -> Vector3:
	return get_fieldlink_control_local_position()


func _apply_speaker_level(speaker_index: int, level: float) -> void:
	if speaker_index < 0 or speaker_index >= _speaker_cones.size():
		return
	var cone := _speaker_cones[speaker_index]
	var safe_level := clampf(level, 0.0, 1.0)
	var rest_scale := _speaker_rest_scales[speaker_index]
	var radial_scale := 1.0 + MAX_CONE_RADIAL_SCALE * safe_level
	cone.scale = Vector3(
		rest_scale.x * radial_scale,
		rest_scale.y * (1.0 + MAX_CONE_DEPTH_SCALE * safe_level),
		rest_scale.z * radial_scale
	)
	cone.position = _speaker_rest_positions[speaker_index] + Vector3(0.0, 0.0, MAX_CONE_EXCURSION * safe_level)


func _add_speaker_box(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = _unit_box
	instance.scale = size
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_speaker_disc(
	parent: Node3D,
	node_name: String,
	radius: float,
	depth: float,
	front_z: float,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position.z = front_z
	instance.rotation.x = PI * 0.5
	instance.scale = Vector3(radius, depth, radius)
	instance.mesh = _unit_cylinder
	instance.material_override = material
	parent.add_child(instance)
	return instance
