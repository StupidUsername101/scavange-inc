class_name GrabState
extends RefCounted

const MAX_ROTATION_INPUT_PER_EVENT := 120.0
const MAX_ACCUMULATED_ROTATION_INPUT := 240.0

#######################################################
# Stores mutable grab runtime state and serializes the fields shared between authoritative and
# presentation systems.
#######################################################

var grabber: GrabberComponent
var body: PhysicsBody3D
var local_grab_point: Vector3
var grab_distance: float
var lift_offset: float
var rotation_active := false
var rotation_input := Vector2.ZERO
var rotation_anchor_centered := false
var rotation_settle_time_remaining := 0.0


func _init(
	_grabber: GrabberComponent,
	_body: PhysicsBody3D,
	_local_grab_point: Vector3,
	_grab_distance: float,
	_lift_offset: float
) -> void:
	grabber = _grabber
	body = _body
	local_grab_point = _local_grab_point
	grab_distance = _grab_distance
	lift_offset = _lift_offset


func set_rotation_active(value: bool) -> void:
	rotation_active = value
	if not rotation_active:
		rotation_input = Vector2.ZERO
		rotation_settle_time_remaining = 0.0


func add_rotation_input(value: Vector2) -> void:
	rotation_input = (
		rotation_input
		+ value.limit_length(MAX_ROTATION_INPUT_PER_EVENT)
	).limit_length(MAX_ACCUMULATED_ROTATION_INPUT)
	if grabber != null and grabber.capability != null:
		rotation_settle_time_remaining = (
			grabber.capability.rotation_settle_duration
		)


func consume_rotation_input() -> Vector2:
	var result := rotation_input
	rotation_input = Vector2.ZERO
	return result


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
