class_name DestructionFragmentProxy
extends Node3D

const INTERP_SPEED := 14.0
const GRABBED_INTERP_SPEED := 30.0
const MAX_EXTRAPOLATION_TIME := 0.25
const NETWORK_LEAD_SECONDS := 0.035
const GRABBED_NETWORK_LEAD_SECONDS := 0.055

var fragment_id := -1
var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY
var target_linear_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var time_since_last_state := 0.0
var last_motion_sequence := -1
var grabbed_by_player_id := -1
var _visual: MeshInstance3D
var _material: StandardMaterial3D
var _thermal_overlay: ThermalCutOverlay3D


func apply_spawn_packet(packet: Dictionary) -> bool:
	fragment_id = SafeVariant.integral_int_or(packet.get("fragment_id", -1), -1)
	if fragment_id < 0 or not _replace_geometry(packet):
		return false
	global_position = SafeVariant.vector3_strict_or(packet.get("pos", Vector3.ZERO), Vector3.ZERO)
	global_rotation = SafeVariant.vector3_strict_or(packet.get("rot", Vector3.ZERO), Vector3.ZERO)
	target_position = global_position
	target_rotation = Quaternion(global_basis)
	return true


func apply_geometry_packet(packet: Dictionary) -> bool:
	if SafeVariant.integral_int_or(packet.get("fragment_id", -1), -1) != fragment_id:
		return false
	return _replace_geometry(packet)


func _replace_geometry(packet: Dictionary) -> bool:
	var vertices: PackedVector3Array = packet.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = packet.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = packet.get("indices", PackedInt32Array())
	var mask: PackedColorArray = packet.get("surface_mask", PackedColorArray())
	if vertices.is_empty() or normals.size() != vertices.size() or indices.is_empty():
		return false
	var exterior: Color = packet.get("exterior_color", Color(0.34, 0.36, 0.34))
	var interior: Color = packet.get("interior_color", Color(0.20, 0.19, 0.17))
	var modulation := Color(
		interior.r / maxf(exterior.r, 0.000001),
		interior.g / maxf(exterior.g, 0.000001),
		interior.b / maxf(exterior.b, 0.000001),
		interior.a / maxf(exterior.a, 0.000001)
	)
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index: int in range(vertices.size()):
		colors[index] = Color.WHITE if index < mask.size() and mask[index].r > 0.5 else modulation
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := _visual.mesh as ArrayMesh if _visual != null else null
	if mesh == null:
		mesh = ArrayMesh.new()
	elif mesh.get_surface_count() > 0:
		mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _visual == null:
		_visual = MeshInstance3D.new()
		_visual.name = "FragmentVisual"
		add_child(_visual)
	_visual.mesh = mesh
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = false
	_material.albedo_color = exterior
	_material.roughness = clampf(float(packet.get("roughness", 0.9)), 0.0, 1.0)
	_material.metallic = clampf(float(packet.get("metallic", 0.0)), 0.0, 1.0)
	_visual.material_override = _material
	var thermal_value: Variant = packet.get("thermal_cut", null)
	if thermal_value is Dictionary:
		var thermal := thermal_value as Dictionary
		if _thermal_overlay == null:
			_thermal_overlay = ThermalCutOverlay3D.new()
			_thermal_overlay.name = "ThermalCutOverlay"
			add_child(_thermal_overlay)
		_thermal_overlay.configure(_material)
		_thermal_overlay.add_cut(
			SafeVariant.vector3_strict_or(thermal.get("position", Vector3.ZERO), Vector3.ZERO),
			SafeVariant.vector3_strict_or(thermal.get("direction", Vector3.FORWARD), Vector3.FORWARD),
			clampf(float(thermal.get("radius", 0.02)), 0.003, 2.0),
			clampf(float(thermal.get("depth", 0.05)), 0.003, 16.0),
			maxf(float(thermal.get("heat", 0.0)), 0.0)
		)
	return true


func apply_server_state(state: Dictionary) -> void:
	_apply_motion_state(state, false)


func apply_server_motion_state(state: Dictionary) -> void:
	_apply_motion_state(state, true)


func _apply_motion_state(state: Dictionary, is_high_rate: bool) -> void:
	if is_high_rate:
		var motion_sequence := SafeVariant.integral_int_or(
			state.get("fragment_motion_sequence", -1),
			-1
		)
		if not ClientProxyMotion.is_newer_motion_sequence(
			motion_sequence,
			last_motion_sequence
		):
			return
		if motion_sequence >= 0:
			last_motion_sequence = motion_sequence
	grabbed_by_player_id = SafeVariant.integral_int_or(
		state.get("grabber_player_id", grabbed_by_player_id),
		grabbed_by_player_id
	)
	var rigid_state := ClientProxyMotion.decode_rigid_state(
		state,
		global_position,
		global_rotation
	)
	target_position = rigid_state["position"]
	target_rotation = rigid_state["rotation"]
	target_linear_velocity = rigid_state["linear_velocity"]
	target_angular_velocity = rigid_state["angular_velocity"]
	time_since_last_state = 0.0


func _process(delta: float) -> void:
	if multiplayer.is_server():
		var server := get_node_or_null("/root/Server")
		var body: Node3D = (
			server.call("get_destruction_fragment", fragment_id) as Node3D
			if server != null and server.has_method("get_destruction_fragment")
			else null
		)
		if is_instance_valid(body):
			global_transform = body.global_transform
		return
	time_since_last_state += delta
	var is_grabbed := grabbed_by_player_id >= 0
	ClientProxyMotion.apply_smoothed_motion(
		self,
		delta,
		time_since_last_state + (
			GRABBED_NETWORK_LEAD_SECONDS
			if is_grabbed
			else NETWORK_LEAD_SECONDS
		),
		target_position,
		target_rotation,
		target_linear_velocity,
		target_angular_velocity,
		MAX_EXTRAPOLATION_TIME,
		GRABBED_INTERP_SPEED if is_grabbed else INTERP_SPEED
	)
