class_name PlayerRagdoll3D
extends Node3D

## Articulated local presentation for an authoritative player trip. ServerPlayer decides when the
## player has lost support and replicates a compact physical torso anchor; every peer simulates its
## installed cosmetic limbs around that shared moving reference.

const BODY_COLLISION_LAYER := 1 << 2
const WORLD_COLLISION_MASK := CharacterContactLayers.MOVEMENT_SURFACE
const TORSO_SIZE := Vector3(0.70, 0.85, 0.40)
const HEAD_RADIUS := 0.28
const ARM_RADIUS := 0.11
const ARM_LENGTH := 0.82
const LEG_RADIUS := 0.125
const UPPER_LEG_LENGTH := PlayerProceduralLegRig.UPPER_LEG_LENGTH
const LOWER_LEG_LENGTH := PlayerProceduralLegRig.LOWER_LEG_LENGTH
const FOOT_SIZE := Vector3(0.27, 0.13, 0.42)
const TRIP_ANGULAR_IMPULSE := 0.65
const TORSO_OFFSET_FROM_PLAYER := Vector3(0.0, 0.15, 0.0)
const AUTHORITY_CORRECTION_SPEED := 8.0
const AUTHORITY_VELOCITY_BLEND_SPEED := 6.0
const AUTHORITY_HARD_SNAP_DISTANCE := 2.5

var _bodies: Dictionary[StringName, RigidBody3D] = {}
var _joints: Dictionary[StringName, PinJoint3D] = {}
var _shared_material: StandardMaterial3D
var _left_arm_available := true
var _right_arm_available := true
var _left_leg_available := true
var _right_leg_available := true
var _active := false
var _activation_sequence := 0


func _ready() -> void:
	_build_bodies()
	visible = false


func set_limb_presence(
	left_arm: bool,
	right_arm: bool,
	left_leg: bool,
	right_leg: bool
) -> void:
	_left_arm_available = left_arm
	_right_arm_available = right_arm
	_left_leg_available = left_leg
	_right_leg_available = right_leg
	if not _active:
		_apply_body_availability()


func is_active() -> bool:
	return _active


func start_ragdoll(
	source_visuals: Dictionary,
	base_velocity: Vector3,
	trip_direction: Vector3
) -> void:
	if not is_node_ready():
		return
	_clear_joints()
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = true
	_active = true
	_activation_sequence += 1
	_apply_source_transforms(source_visuals)
	_apply_body_availability()
	_create_active_joints()

	for body: RigidBody3D in _bodies.values():
		if not _body_is_available(body.name):
			continue
		body.linear_velocity = base_velocity
		body.angular_velocity = Vector3.ZERO
		body.freeze = false
		body.sleeping = false

	var safe_direction := Vector3(
		trip_direction.x,
		0.0,
		trip_direction.z
	)
	if safe_direction.length_squared() <= 0.000001:
		safe_direction = Vector3.FORWARD
	else:
		safe_direction = safe_direction.normalized()
	# Enabling a frozen body is committed at the end of the frame. Defer the one-shot impulse until
	# Jolt has actually attached the body to a physics space; applying it synchronously is discarded.
	call_deferred(
		"_apply_trip_impulse",
		_activation_sequence,
		safe_direction
	)


func stop_ragdoll() -> void:
	if not is_node_ready():
		return
	_active = false
	_clear_joints()
	for body: RigidBody3D in _bodies.values():
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		_set_body_enabled(body, false)
	visible = false
	top_level = false
	transform = Transform3D.IDENTITY


func _apply_trip_impulse(sequence: int, safe_direction: Vector3) -> void:
	if not _active or sequence != _activation_sequence:
		return
	var torso := _bodies.get(&"torso") as RigidBody3D
	if torso == null:
		return
	var space_rid := PhysicsServer3D.body_get_space(torso.get_rid())
	if not space_rid.is_valid():
		return
	torso.apply_central_impulse(safe_direction * 1.25 + Vector3.DOWN * 0.35)
	torso.apply_torque_impulse(
		Vector3(safe_direction.z, 0.15, -safe_direction.x)
		* TRIP_ANGULAR_IMPULSE
	)


func get_torso_world_position() -> Vector3:
	var torso := _bodies.get(&"torso") as RigidBody3D
	return torso.global_position if torso != null else global_position


func get_head_world_position() -> Vector3:
	var head := _bodies.get(&"head") as RigidBody3D
	return head.global_position if head != null else get_torso_world_position()


func get_head_world_up() -> Vector3:
	var head := _bodies.get(&"head") as RigidBody3D
	return head.global_basis.y.normalized() if head != null else Vector3.UP


func synchronize_authoritative_torso(
	target_position: Vector3,
	target_velocity: Vector3,
	delta: float
) -> void:
	if not _active or not target_position.is_finite():
		return
	var torso := _bodies.get(&"torso") as RigidBody3D
	if torso == null:
		return
	var error := target_position - torso.global_position
	if error.length_squared() > AUTHORITY_HARD_SNAP_DISTANCE * AUTHORITY_HARD_SNAP_DISTANCE:
		# Move the complete articulated island together. Teleporting only the torso would stretch every
		# joint through the world and inject a large corrective impulse on the next solver step.
		for body: RigidBody3D in _bodies.values():
			if _body_is_available(body.name):
				body.global_position += error
		return
	var safe_velocity := target_velocity if target_velocity.is_finite() else Vector3.ZERO
	var desired_velocity := safe_velocity + error * AUTHORITY_CORRECTION_SPEED
	var weight := 1.0 - exp(-maxf(delta, 0.0) * AUTHORITY_VELOCITY_BLEND_SPEED)
	torso.linear_velocity = torso.linear_velocity.lerp(desired_velocity, weight)


func _build_bodies() -> void:
	_add_box_body(&"torso", TORSO_SIZE, 5.4)
	_add_sphere_body(&"head", HEAD_RADIUS, 1.1)
	_add_capsule_body(&"left_arm", ARM_RADIUS, ARM_LENGTH, 1.2)
	_add_capsule_body(&"right_arm", ARM_RADIUS, ARM_LENGTH, 1.2)
	_add_capsule_body(&"left_upper_leg", LEG_RADIUS, UPPER_LEG_LENGTH, 2.0)
	_add_capsule_body(&"left_lower_leg", LEG_RADIUS, LOWER_LEG_LENGTH, 1.6)
	_add_box_body(&"left_foot", FOOT_SIZE, 0.8)
	_add_capsule_body(&"right_upper_leg", LEG_RADIUS, UPPER_LEG_LENGTH, 2.0)
	_add_capsule_body(&"right_lower_leg", LEG_RADIUS, LOWER_LEG_LENGTH, 1.6)
	_add_box_body(&"right_foot", FOOT_SIZE, 0.8)
	_apply_body_availability()


func _add_box_body(body_name: StringName, size: Vector3, mass_value: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_body(body_name, shape, mesh, mass_value)


func _add_sphere_body(body_name: StringName, radius: float, mass_value: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	_add_body(body_name, shape, mesh, mass_value)


func _add_capsule_body(
	body_name: StringName,
	radius: float,
	height: float,
	mass_value: float
) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 6
	_add_body(body_name, shape, mesh, mass_value)


func _add_body(
	body_name: StringName,
	shape: Shape3D,
	mesh: PrimitiveMesh,
	mass_value: float
) -> void:
	var body := RigidBody3D.new()
	body.name = body_name
	body.mass = mass_value
	body.collision_layer = BODY_COLLISION_LAYER
	body.collision_mask = WORLD_COLLISION_MASK
	body.linear_damp = 0.25
	body.angular_damp = 0.45
	body.freeze = true
	body.can_sleep = true

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	collision.disabled = true
	body.add_child(collision)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	visual.material_override = _body_material()
	body.add_child(visual)
	add_child(body)
	_bodies[body_name] = body


func _body_material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.albedo_color = Color(0.21, 0.225, 0.22, 1.0)
		_shared_material.metallic = 0.16
		_shared_material.roughness = 0.72
	return _shared_material


func _apply_source_transforms(source_visuals: Dictionary) -> void:
	for body_name: StringName in _bodies:
		var body := _bodies[body_name] as RigidBody3D
		var source := source_visuals.get(body_name) as Node3D
		if source != null:
			body.global_transform = source.global_transform.orthonormalized()


func _apply_body_availability() -> void:
	for body_name: StringName in _bodies:
		_set_body_enabled(
			_bodies[body_name] as RigidBody3D,
			_active and _body_is_available(body_name)
		)


func _body_is_available(body_name: StringName) -> bool:
	match body_name:
		&"left_arm":
			return _left_arm_available
		&"right_arm":
			return _right_arm_available
		&"left_upper_leg", &"left_lower_leg", &"left_foot":
			return _left_leg_available
		&"right_upper_leg", &"right_lower_leg", &"right_foot":
			return _right_leg_available
		_:
			return true


func _set_body_enabled(body: RigidBody3D, enabled: bool) -> void:
	body.visible = enabled
	var collision := body.get_node("Collision") as CollisionShape3D
	collision.set_deferred("disabled", not enabled)
	if not enabled:
		body.freeze = true


func _create_active_joints() -> void:
	_add_pin_joint(&"neck", &"torso", &"head", _midpoint(&"torso", &"head"))
	if _left_arm_available:
		_add_pin_joint(&"left_shoulder", &"torso", &"left_arm", _proximal_point(&"left_arm"))
	if _right_arm_available:
		_add_pin_joint(&"right_shoulder", &"torso", &"right_arm", _proximal_point(&"right_arm"))
	if _left_leg_available:
		_add_leg_joints(&"left")
	if _right_leg_available:
		_add_leg_joints(&"right")


func _add_leg_joints(side: StringName) -> void:
	var upper_name := StringName("%s_upper_leg" % side)
	var lower_name := StringName("%s_lower_leg" % side)
	var foot_name := StringName("%s_foot" % side)
	_add_pin_joint(
		StringName("%s_hip" % side),
		&"torso",
		upper_name,
		_proximal_point(upper_name)
	)
	_add_pin_joint(
		StringName("%s_knee" % side),
		upper_name,
		lower_name,
		_midpoint(upper_name, lower_name)
	)
	_add_pin_joint(
		StringName("%s_ankle" % side),
		lower_name,
		foot_name,
		_midpoint(lower_name, foot_name)
	)


func _add_pin_joint(
	joint_name: StringName,
	body_a_name: StringName,
	body_b_name: StringName,
	anchor: Vector3
) -> void:
	var body_a := _bodies.get(body_a_name) as RigidBody3D
	var body_b := _bodies.get(body_b_name) as RigidBody3D
	if body_a == null or body_b == null:
		return
	var joint := _joints.get(joint_name) as PinJoint3D
	if joint == null:
		joint = PinJoint3D.new()
		joint.name = joint_name
		add_child(joint)
		_joints[joint_name] = joint
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.exclude_nodes_from_collision = true


func _proximal_point(body_name: StringName) -> Vector3:
	var body := _bodies.get(body_name) as RigidBody3D
	if body == null:
		return global_position
	if String(body_name).contains("upper_leg"):
		# Procedural leg segments author +Y from hip toward knee, so the proximal endpoint is -Y.
		return body.global_position - body.global_basis.y * UPPER_LEG_LENGTH * 0.5
	# The standing arm capsules use their authored +Y toward the shoulder.
	return body.global_position + body.global_basis.y * ARM_LENGTH * 0.5


func _midpoint(body_a_name: StringName, body_b_name: StringName) -> Vector3:
	var body_a := _bodies.get(body_a_name) as RigidBody3D
	var body_b := _bodies.get(body_b_name) as RigidBody3D
	if body_a == null or body_b == null:
		return global_position
	return body_a.global_position.lerp(body_b.global_position, 0.5)


func _clear_joints() -> void:
	for joint: PinJoint3D in _joints.values():
		if not is_instance_valid(joint):
			continue
		joint.node_a = NodePath()
		joint.node_b = NodePath()
