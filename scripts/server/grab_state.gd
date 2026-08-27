class_name GrabState
extends RefCounted

const MAX_ROTATION_INPUT_PER_TICK := 240.0
const MAX_ROTATION_INPUT_TARGET := 1000000.0

#######################################################
# Stores mutable grab runtime state and serializes the fields shared between authoritative and
# presentation systems.
#######################################################

var grabber: GrabberComponent
var body: PhysicsBody3D
var local_grab_point: Vector3
var grab_distance: float
var lift_offset: float
var side_offset: float
var rotation_active := false
var rotation_input_target := Vector2.ZERO
var rotation_input_applied := Vector2.ZERO
var rotation_session_id := 0
var target_basis_relative_to_grabber := Basis.IDENTITY
var rotation_gesture_basis_relative_to_grabber := Basis.IDENTITY
var rotation_anchor_centered := false


func _init(
	_grabber: GrabberComponent,
	_body: PhysicsBody3D,
	_local_grab_point: Vector3,
	_grab_distance: float,
	_lift_offset: float,
	_target_basis_relative_to_grabber := Basis.IDENTITY,
	_side_offset := 0.0
) -> void:
	grabber = _grabber
	body = _body
	local_grab_point = _local_grab_point
	grab_distance = _grab_distance
	lift_offset = _lift_offset
	side_offset = _side_offset
	if _target_basis_relative_to_grabber.is_finite():
		target_basis_relative_to_grabber = (
			_target_basis_relative_to_grabber.orthonormalized()
		)
	rotation_gesture_basis_relative_to_grabber = target_basis_relative_to_grabber


func set_rotation_active(value: bool, session_id := 0) -> void:
	if rotation_active == value and (not value or rotation_session_id == session_id):
		return
	rotation_active = value
	rotation_session_id = maxi(session_id, 0) if value else 0
	rotation_input_target = Vector2.ZERO
	rotation_input_applied = Vector2.ZERO
	if value:
		rotation_gesture_basis_relative_to_grabber = target_basis_relative_to_grabber


func set_rotation_input_target(value: Vector2, session_id := 0) -> void:
	if (
		not rotation_active
		or session_id != rotation_session_id
		or not value.is_finite()
	):
		return
	rotation_input_target = Vector2(
		clampf(value.x, -MAX_ROTATION_INPUT_TARGET, MAX_ROTATION_INPUT_TARGET),
		clampf(value.y, -MAX_ROTATION_INPUT_TARGET, MAX_ROTATION_INPUT_TARGET)
	)


func consume_rotation_input() -> Vector2:
	var result := (
		rotation_input_target - rotation_input_applied
	).limit_length(MAX_ROTATION_INPUT_PER_TICK)
	rotation_input_applied += result
	return result


func rotate_target(input: Vector2, radians_per_pixel: float) -> void:
	if not input.is_finite() or input.is_zero_approx():
		return
	var delta_rotation := _screen_drag_basis(input, radians_per_pixel)
	target_basis_relative_to_grabber = (
		delta_rotation * target_basis_relative_to_grabber
	).orthonormalized()
	rotation_gesture_basis_relative_to_grabber = target_basis_relative_to_grabber


func advance_rotation_target(radians_per_pixel: float) -> void:
	var input_delta := consume_rotation_input()
	if input_delta.is_zero_approx():
		return
	# Rebuild from the gesture's stable starting pose. The same absolute mouse target therefore
	# produces the same orientation even when intermediate unreliable packets are dropped.
	target_basis_relative_to_grabber = (
		_screen_drag_basis(rotation_input_applied, radians_per_pixel)
		* rotation_gesture_basis_relative_to_grabber
	).orthonormalized()


static func _screen_drag_basis(input: Vector2, radians_per_pixel: float) -> Basis:
	var scale := maxf(radians_per_pixel, 0.0)
	var yaw := Basis(Quaternion(Vector3.UP, -input.x * scale))
	var pitch := Basis(Quaternion(Vector3.RIGHT, -input.y * scale))
	return (yaw * pitch).orthonormalized()


func get_target_world_basis() -> Basis:
	if grabber == null or not is_instance_valid(grabber):
		return target_basis_relative_to_grabber
	return (
		grabber.global_basis.orthonormalized()
		* target_basis_relative_to_grabber
	).orthonormalized()


static func rotation_error_vector(current: Basis, desired: Basis) -> Vector3:
	if not current.is_finite() or not desired.is_finite():
		return Vector3.ZERO
	var error := (
		desired.orthonormalized() * current.orthonormalized().transposed()
	).get_rotation_quaternion().normalized()
	var angle := error.get_angle()
	var axis := error.get_axis()
	if angle > PI:
		angle = TAU - angle
		axis = -axis
	if angle <= 0.000001 or axis.length_squared() <= 0.000001:
		return Vector3.ZERO
	return axis.normalized() * angle


func center_rotation_anchor(
	local_center_of_mass: Vector3,
	weight: float
) -> void:
	if rotation_anchor_centered:
		return

	local_grab_point = local_grab_point.lerp(
		local_center_of_mass,
		clampf(weight, 0.0, 1.0)
	)
	rotation_anchor_centered = true
