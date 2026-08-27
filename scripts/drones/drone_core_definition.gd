@tool
class_name DroneCoreDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone core configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Core")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_health := 100.0
@export_range(0.0, 1000000.0, 1.0, "or_greater") var max_power_throughput := 120.0
@export_range(0, 32, 1, "or_greater") var propeller_slot_count := 4
@export_range(0, 8, 1) var ai_chip_slot_count := 2
@export_range(0, 32, 1, "or_greater") var attachment_slot_count: int = 2
@export var body_size := Vector3(0.65, 0.24, 0.65)
@export var editable_mesh: DroneCoreEditableMeshDefinition

@export_group("Authored Model Frame")
# These axes describe how the worker regards the physical Core. Godot's conventional forward is
# local -Z, so the resulting model basis has forward_local as its negative Z axis. Keeping this
# frame on the serialized Core makes creator previews, training observations, and exported models
# agree even when a chassis was modeled on a different axis.
@export var model_forward_local: Vector3 = Vector3.FORWARD
@export var model_up_local: Vector3 = Vector3.UP

@export_group("AI Flight Authority")
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_horizontal_speed := 4.0
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_horizontal_acceleration := 5.5
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_vertical_speed := 4.5
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_vertical_acceleration := 7.0
@export_range(0.0, 75.0, 0.1, "or_greater") var ai_max_tilt_degrees := 26.0
@export_range(0.0, 10.0, 0.01, "or_greater") var ai_horizontal_position_gain := 0.9
@export_range(0.0, 20.0, 0.01, "or_greater") var ai_horizontal_velocity_gain := 2.25
@export_range(0.0, 10.0, 0.01, "or_greater") var ai_altitude_position_gain := 1.8
@export_range(0.0, 20.0, 0.01, "or_greater") var ai_altitude_velocity_gain := 2.8
@export_range(0.0, 100.0, 0.05, "or_greater") var ai_attitude_response := 18.0
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_angular_velocity_damping := 5.5
@export_range(0.0, 1.0, 0.01) var ai_motor_mix_authority := 0.42
@export_range(0.0, 20.0, 0.05, "or_greater") var ai_emergency_upright_torque := 1.25

# Kept as a resource compatibility alias. New flight code uses the explicit
# vertical speed/acceleration envelope above.
@export_range(0.0, 5.0, 0.01, "or_greater") var ai_altitude_authority := 0.18

@export_group("Power Response")
@export_range(0.01, 100.0, 0.05, "or_greater") var spool_up_response := 1.5
@export_range(0.01, 100.0, 0.05, "or_greater") var spool_down_response := 2.5
@export_range(0.0, 1.0, 0.001) var power_output_consistency := 0.985
@export_range(0.0, 100.0, 0.01, "or_greater") var fluctuation_rate := 0.35

@export_group("Aerodynamics")
@export_range(0.001, 1000.0, 0.001, "or_greater") var drag_area := 0.45
@export_range(0.0, 10.0, 0.01, "or_greater") var drag_coefficient := 1.05
@export_range(0.0, 1000.0, 0.01, "or_greater") var angular_drag_coefficient := 0.35


func ensure_editable_mesh() -> DroneCoreEditableMeshDefinition:
	if editable_mesh == null:
		editable_mesh = DroneCoreEditableMeshDefinition.new()
	editable_mesh.ensure_box(body_size)
	body_size = editable_mesh.bounds_size()
	return editable_mesh


func set_editable_body_size(size_value: Vector3) -> void:
	var mesh_definition: DroneCoreEditableMeshDefinition = ensure_editable_mesh()
	mesh_definition.set_bounds_size(size_value)
	body_size = mesh_definition.bounds_size()


func synchronize_body_size_from_editable_mesh() -> void:
	if editable_mesh != null and editable_mesh.has_geometry():
		body_size = editable_mesh.bounds_size()


func set_model_orientation(forward_local: Vector3, up_local: Vector3) -> bool:
	if not _valid_orientation_pair(forward_local, up_local):
		return false
	var orientation: Basis = _basis_from_orientation_pair(forward_local, up_local)
	model_forward_local = -orientation.z
	model_up_local = orientation.y
	return true


func set_model_forward(direction_local: Vector3) -> bool:
	if not direction_local.is_finite() or direction_local.length_squared() <= 0.000001:
		return false
	var forward: Vector3 = direction_local.normalized()
	var up: Vector3 = model_up_local.normalized()
	if up.length_squared() <= 0.000001 or absf(forward.dot(up)) >= 0.999:
		up = _least_aligned_cardinal(forward)
	return set_model_orientation(forward, up)


func set_model_up(direction_local: Vector3) -> bool:
	if not direction_local.is_finite() or direction_local.length_squared() <= 0.000001:
		return false
	var up: Vector3 = direction_local.normalized()
	var forward: Vector3 = model_forward_local.normalized()
	if forward.length_squared() <= 0.000001 or absf(forward.dot(up)) >= 0.999:
		forward = _least_aligned_cardinal(up)
	forward = (forward - up * forward.dot(up)).normalized()
	return set_model_orientation(forward, up)


func reset_model_orientation() -> void:
	model_forward_local = Vector3.FORWARD
	model_up_local = Vector3.UP


func model_orientation_basis_local() -> Basis:
	if _valid_orientation_pair(model_forward_local, model_up_local):
		return _basis_from_orientation_pair(model_forward_local, model_up_local)
	return Basis.IDENTITY


static func _valid_orientation_pair(forward_local: Vector3, up_local: Vector3) -> bool:
	return (
		forward_local.is_finite()
		and up_local.is_finite()
		and forward_local.length_squared() > 0.000001
		and up_local.length_squared() > 0.000001
		and absf(forward_local.normalized().dot(up_local.normalized())) < 0.999
	)


static func _basis_from_orientation_pair(forward_local: Vector3, up_local: Vector3) -> Basis:
	# Gram-Schmidt keeps the explicitly authored forward direction exact and removes only the
	# component of up that cannot belong to an orthonormal worker frame.
	var forward: Vector3 = forward_local.normalized()
	var up: Vector3 = (
		up_local - forward * up_local.dot(forward)
	).normalized()
	var right: Vector3 = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	return Basis(right, up, -forward).orthonormalized()


static func _least_aligned_cardinal(direction: Vector3) -> Vector3:
	var candidate: Vector3 = Vector3.UP
	var smallest_alignment: float = absf(direction.dot(candidate))
	for axis: Vector3 in [Vector3.RIGHT, Vector3.FORWARD]:
		var alignment: float = absf(direction.dot(axis))
		if alignment < smallest_alignment:
			smallest_alignment = alignment
			candidate = axis
	return candidate


func ml_part_tags() -> Array[StringName]:
	return [&"drone_part", &"core"]


func ml_validation_error() -> String:
	if not _valid_orientation_pair(model_forward_local, model_up_local):
		return "Core worker forward and up must be finite, non-zero, and non-parallel."
	return ""


func ml_contract_dictionary() -> Dictionary:
	var result: Dictionary = super.ml_contract_dictionary()
	var orientation: Basis = model_orientation_basis_local()
	result["model_forward_local"] = [(-orientation.z).x, (-orientation.z).y, (-orientation.z).z]
	result["model_up_local"] = [orientation.y.x, orientation.y.y, orientation.y.z]
	return result
