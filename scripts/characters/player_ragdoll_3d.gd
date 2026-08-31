class_name PlayerRagdoll3D
extends Node3D

## Articulated local presentation for an authoritative player trip. ServerPlayer decides when the
## player has lost support and replicates a compact physical torso anchor; every peer simulates its
## installed cosmetic limbs around that shared moving reference.

const BODY_COLLISION_LAYER := 1 << 2
const WORLD_COLLISION_MASK := CharacterContactLayers.MOVEMENT_SURFACE
const TORSO_SIZE := Vector3(0.70, 0.85, 0.40)
const TORSO_COLLISION_RADIUS := 0.30
const TORSO_COLLISION_HEIGHT := 0.82
const HEAD_RADIUS := 0.28
const ARM_RADIUS := 0.11
const ARM_LENGTH := 0.82
const LEG_RADIUS := 0.125
const UPPER_LEG_LENGTH := PlayerProceduralLegRig.UPPER_LEG_LENGTH
const LOWER_LEG_LENGTH := PlayerProceduralLegRig.LOWER_LEG_LENGTH
const FOOT_SIZE := Vector3(0.27, 0.13, 0.42)
const FOOT_COLLISION_RADIUS := 0.07
const FOOT_COLLISION_HEIGHT := 0.38
const CONTACT_FRICTION := 0.18
const TORSO_MASS := 32.0
const HEAD_MASS := 4.8
const ARM_MASS := 3.6
const UPPER_LEG_MASS := 7.5
const LOWER_LEG_MASS := 4.3
const FOOT_MASS := 1.1
const BODY_LINEAR_DAMP := 0.18
const BODY_ANGULAR_DAMP := 0.92
const TRIP_TORSO_FORWARD_DELTA_SPEED := 0.44
const TRIP_TORSO_DOWN_DELTA_SPEED := 0.12
const TRIP_ANGULAR_IMPULSE_PER_MASS := 0.13
const ACTIVE_BRACE_SECONDS := 0.58
const ACTIVE_BRACE_DAMPING := 1.0
const NECK_BRACE_STIFFNESS := 22.0
const SHOULDER_BRACE_STIFFNESS := 14.0
const HIP_BRACE_STIFFNESS := 30.0
const KNEE_BRACE_STIFFNESS := 25.0
const ANKLE_BRACE_STIFFNESS := 12.0
const TORSO_OFFSET_FROM_PLAYER := Vector3(0.0, 0.15, 0.0)
const AUTHORITY_CORRECTION_SPEED := 8.0
const AUTHORITY_VELOCITY_BLEND_SPEED := 6.0
const AUTHORITY_HARD_SNAP_DISTANCE := 2.5
const AUTHORED_BONE_BODY_PAIRS := [
	[&"mixamorig_Hips", &"torso"],
	[&"mixamorig_Spine", &"torso"],
	[&"mixamorig_Spine1", &"torso"],
	[&"mixamorig_Spine2", &"torso"],
	[&"mixamorig_Head", &"head"],
	[&"mixamorig_LeftArm", &"left_arm"],
	[&"mixamorig_LeftForeArm", &"left_arm"],
	[&"mixamorig_LeftHand", &"left_arm"],
	[&"mixamorig_RightArm", &"right_arm"],
	[&"mixamorig_RightForeArm", &"right_arm"],
	[&"mixamorig_RightHand", &"right_arm"],
	[&"mixamorig_LeftUpLeg", &"left_upper_leg"],
	[&"mixamorig_LeftLeg", &"left_lower_leg"],
	[&"mixamorig_LeftFoot", &"left_foot"],
	[&"mixamorig_RightUpLeg", &"right_upper_leg"],
	[&"mixamorig_RightLeg", &"right_lower_leg"],
	[&"mixamorig_RightFoot", &"right_foot"],
]

var _bodies: Dictionary[StringName, RigidBody3D] = {}
var _joints: Dictionary[StringName, Generic6DOFJoint3D] = {}
var _joint_brace_stiffness: Dictionary[StringName, float] = {}
var _active_joint_names: Array[StringName] = []
var _shared_material: StandardMaterial3D
var _shared_physics_material: PhysicsMaterial
var _left_arm_available := true
var _right_arm_available := true
var _left_leg_available := true
var _right_leg_available := true
var _active := false
var _activation_sequence := 0
var _authored_skin: PlayerCharacterSkin
var _authored_skin_active := false
var _authored_bone_indices: Array[int] = []
var _authored_bodies: Array[RigidBody3D] = []
var _authored_bone_offsets: Array[Transform3D] = []
var _authored_root_from_torso := Transform3D.IDENTITY
var _brace_elapsed := ACTIVE_BRACE_SECONDS
var _trip_impulse_pending := false
var _pending_trip_direction := Vector3.FORWARD


func _ready() -> void:
	_build_bodies()
	visible = false
	set_process(false)
	set_physics_process(false)


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
	if _authored_skin != null:
		_authored_skin.set_limb_presence(
			_left_arm_available,
			_right_arm_available,
			_left_leg_available,
			_right_leg_available
		)
	if not _active:
		_apply_body_availability()


func is_active() -> bool:
	return _active


func has_authored_skin() -> bool:
	return (
		_authored_skin_active
		and _authored_skin != null
		and _authored_skin.is_usable()
	)


func get_authored_skin() -> PlayerCharacterSkin:
	return _authored_skin


func get_body_source_visuals() -> Dictionary:
	# Corpse handoff is rare and deliberately snapshots node references rather than sharing ownership.
	# PlayerCorpseProxy immediately copies their transforms into a separately-instantiated ragdoll.
	var result: Dictionary[StringName, Node3D] = {}
	for body_name: StringName in _bodies:
		var body := _bodies.get(body_name) as Node3D
		if body != null and _body_is_available(body_name):
			result[body_name] = body
	return result


func set_local_view(value: bool) -> void:
	if _authored_skin != null:
		_authored_skin.set_local_view(value)


func start_ragdoll(
	source_visuals: Dictionary,
	base_velocity: Vector3,
	trip_direction: Vector3,
	source_character_skin: PlayerCharacterSkin = null,
	local_view := false
) -> void:
	if not is_node_ready():
		return
	_clear_joints()
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = true
	_active = true
	set_process(true)
	set_physics_process(true)
	_activation_sequence += 1
	_brace_elapsed = 0.0
	_apply_source_transforms(source_visuals)
	_prepare_authored_skin(source_character_skin, local_view)
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
	# Unfreezing is committed at the end of the frame. Retain the impulse until a physics tick sees a
	# valid Jolt space; a single deferred call can still arrive too early and silently discard it.
	_pending_trip_direction = safe_direction
	_trip_impulse_pending = true


func stop_ragdoll() -> void:
	if not is_node_ready():
		return
	_active = false
	_trip_impulse_pending = false
	set_process(false)
	set_physics_process(false)
	_clear_joints()
	for body: RigidBody3D in _bodies.values():
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		_set_body_enabled(body, false)
	_authored_skin_active = false
	_clear_authored_bindings()
	if _authored_skin != null:
		_authored_skin.visible = false
	visible = false
	top_level = false
	transform = Transform3D.IDENTITY


func _apply_trip_impulse(sequence: int, safe_direction: Vector3) -> bool:
	if not _active or sequence != _activation_sequence:
		return false
	var torso := _bodies.get(&"torso") as RigidBody3D
	if torso == null:
		return false
	var space_rid := PhysicsServer3D.body_get_space(torso.get_rid())
	if not space_rid.is_valid():
		return false
	# The torso leads a trip instead of every segment receiving an identical puppet velocity. Express
	# the impulse as a desired torso delta-velocity so tuning remains stable with human-scale masses.
	torso.apply_central_impulse(
		(
			safe_direction * TRIP_TORSO_FORWARD_DELTA_SPEED
			+ Vector3.DOWN * TRIP_TORSO_DOWN_DELTA_SPEED
		) * torso.mass
	)
	torso.apply_torque_impulse(
		Vector3(safe_direction.z, 0.15, -safe_direction.x)
		* TRIP_ANGULAR_IMPULSE_PER_MASS
		* torso.mass
	)
	return true


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
		_sync_authored_skin_to_bodies()
		return
	var safe_velocity := target_velocity if target_velocity.is_finite() else Vector3.ZERO
	var desired_velocity := safe_velocity + error * AUTHORITY_CORRECTION_SPEED
	var weight := 1.0 - exp(-maxf(delta, 0.0) * AUTHORITY_VELOCITY_BLEND_SPEED)
	torso.linear_velocity = torso.linear_velocity.lerp(desired_velocity, weight)


func _process(_delta: float) -> void:
	if _active and _authored_skin_active:
		_sync_authored_skin_to_bodies()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _trip_impulse_pending:
		_trip_impulse_pending = not _apply_trip_impulse(
			_activation_sequence,
			_pending_trip_direction
		)
	if _brace_elapsed >= ACTIVE_BRACE_SECONDS:
		if not _trip_impulse_pending:
			set_physics_process(false)
		return
	_brace_elapsed = minf(
		_brace_elapsed + maxf(delta, 0.0),
		ACTIVE_BRACE_SECONDS
	)
	var remaining_ratio := 1.0 - _brace_elapsed / ACTIVE_BRACE_SECONDS
	_update_active_brace(smoothstep(0.0, 1.0, remaining_ratio))
	if _brace_elapsed >= ACTIVE_BRACE_SECONDS and not _trip_impulse_pending:
		set_physics_process(false)


func _build_bodies() -> void:
	_add_rounded_torso_body()
	_add_sphere_body(&"head", HEAD_RADIUS, HEAD_MASS)
	_add_capsule_body(&"left_arm", ARM_RADIUS, ARM_LENGTH, ARM_MASS)
	_add_capsule_body(&"right_arm", ARM_RADIUS, ARM_LENGTH, ARM_MASS)
	_add_capsule_body(&"left_upper_leg", LEG_RADIUS, UPPER_LEG_LENGTH, UPPER_LEG_MASS)
	_add_capsule_body(&"left_lower_leg", LEG_RADIUS, LOWER_LEG_LENGTH, LOWER_LEG_MASS)
	_add_rounded_foot_body(&"left_foot")
	_add_capsule_body(&"right_upper_leg", LEG_RADIUS, UPPER_LEG_LENGTH, UPPER_LEG_MASS)
	_add_capsule_body(&"right_lower_leg", LEG_RADIUS, LOWER_LEG_LENGTH, LOWER_LEG_MASS)
	_add_rounded_foot_body(&"right_foot")
	_apply_body_availability()


func _add_rounded_torso_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = TORSO_COLLISION_RADIUS
	shape.height = TORSO_COLLISION_HEIGHT
	var mesh := BoxMesh.new()
	mesh.size = TORSO_SIZE
	_add_body(&"torso", shape, mesh, TORSO_MASS)


func _add_rounded_foot_body(body_name: StringName) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = FOOT_COLLISION_RADIUS
	shape.height = FOOT_COLLISION_HEIGHT
	var mesh := BoxMesh.new()
	mesh.size = FOOT_SIZE
	_add_body(body_name, shape, mesh, FOOT_MASS)
	# CapsuleShape3D is Y-aligned; feet are authored lengthwise on local Z.
	var body := _bodies[body_name] as RigidBody3D
	var collision := body.get_node("Collision") as CollisionShape3D
	collision.rotation.x = PI * 0.5


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
	body.linear_damp = BODY_LINEAR_DAMP
	body.angular_damp = BODY_ANGULAR_DAMP
	body.physics_material_override = _body_physics_material()
	body.freeze = true
	body.can_sleep = true
	body.continuous_cd = true

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


func _body_physics_material() -> PhysicsMaterial:
	if _shared_physics_material == null:
		_shared_physics_material = PhysicsMaterial.new()
		_shared_physics_material.friction = CONTACT_FRICTION
		_shared_physics_material.bounce = 0.0
	return _shared_physics_material


func _apply_source_transforms(source_visuals: Dictionary) -> void:
	for body_name: StringName in _bodies:
		var body := _bodies[body_name] as RigidBody3D
		var source := source_visuals.get(body_name) as Node3D
		if source != null:
			body.global_transform = source.global_transform.orthonormalized()


func _prepare_authored_skin(
	source: PlayerCharacterSkin,
	local_view: bool
) -> void:
	_authored_skin_active = false
	_clear_authored_bindings()
	if source == null or not source.is_usable():
		if _authored_skin != null:
			_authored_skin.visible = false
		_sync_all_primitive_visuals()
		return
	if _authored_skin == null:
		_authored_skin = PlayerCharacterSkin.new()
		_authored_skin.name = &"AuthoredRagdollSkin"
		add_child(_authored_skin)
	if (
		not _authored_skin.set_player_identity(source.player_id)
		or _authored_skin.get_variant_path() != source.get_variant_path()
		or not _authored_skin.copy_runtime_pose_from(source)
	):
		_authored_skin.visible = false
		_sync_all_primitive_visuals()
		return
	_authored_skin.set_local_view(local_view)
	_authored_skin.set_limb_presence(
		_left_arm_available,
		_right_arm_available,
		_left_leg_available,
		_right_leg_available
	)
	_authored_skin.visible = true
	_authored_skin_active = true
	var torso := _bodies.get(&"torso") as RigidBody3D
	if torso != null:
		_authored_root_from_torso = (
			torso.global_transform.affine_inverse()
			* _authored_skin.global_transform
		)
	_capture_authored_bindings()
	_sync_all_primitive_visuals()
	_sync_authored_skin_to_bodies()


func _capture_authored_bindings() -> void:
	_clear_authored_bindings()
	if not has_authored_skin() or _authored_skin.skeleton == null:
		return
	var skeleton := _authored_skin.skeleton
	for pair: Array in AUTHORED_BONE_BODY_PAIRS:
		var bone_name := pair[0] as StringName
		var body_name := pair[1] as StringName
		var bone_index := skeleton.find_bone(bone_name)
		var body := _bodies.get(body_name) as RigidBody3D
		if bone_index < 0 or body == null:
			continue
		var bone_world := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(bone_index)
		)
		_authored_bone_indices.append(bone_index)
		_authored_bodies.append(body)
		_authored_bone_offsets.append(
			body.global_transform.affine_inverse() * bone_world
		)


func _clear_authored_bindings() -> void:
	_authored_bone_indices.clear()
	_authored_bodies.clear()
	_authored_bone_offsets.clear()


func _sync_authored_skin_to_bodies() -> void:
	if not has_authored_skin() or _authored_skin.skeleton == null:
		return
	var torso := _bodies.get(&"torso") as RigidBody3D
	if torso != null:
		# Keep skinned-mesh bounds close to the moving physical island. Bone poses remain world-correct
		# below, while long falls no longer leave the authored mesh root (and its culling bounds) behind.
		_authored_skin.global_transform = (
			torso.global_transform * _authored_root_from_torso
		)
	var skeleton := _authored_skin.skeleton
	var skeleton_inverse := skeleton.global_transform.affine_inverse()
	for index: int in _authored_bone_indices.size():
		var body := _authored_bodies[index]
		if body == null:
			continue
		var bone_world := body.global_transform * _authored_bone_offsets[index]
		skeleton.set_bone_global_pose(
			_authored_bone_indices[index],
			skeleton_inverse * bone_world
		)
	skeleton.force_update_all_bone_transforms()
	_authored_skin.force_equipment_attachment_update()


func _sync_all_primitive_visuals() -> void:
	for body: RigidBody3D in _bodies.values():
		_sync_primitive_visual(body)


func _sync_primitive_visual(body: RigidBody3D) -> void:
	var visual := body.get_node_or_null("Visual") as GeometryInstance3D
	if visual != null:
		visual.visible = body.visible and not _authored_skin_active


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
	_sync_primitive_visual(body)
	var collision := body.get_node("Collision") as CollisionShape3D
	collision.set_deferred("disabled", not enabled)
	if not enabled:
		body.freeze = true


func _create_active_joints() -> void:
	_active_joint_names.clear()
	_add_anatomical_joint(
		&"neck",
		&"torso",
		&"head",
		_midpoint(&"torso", &"head"),
		Vector3(-0.61, -0.79, -0.52),
		Vector3(0.61, 0.79, 0.52),
		NECK_BRACE_STIFFNESS
	)
	if _left_arm_available:
		_add_anatomical_joint(
			&"left_shoulder",
			&"torso",
			&"left_arm",
			_proximal_point(&"left_arm"),
			Vector3(-1.75, -1.22, -1.75),
			Vector3(1.75, 1.22, 1.75),
			SHOULDER_BRACE_STIFFNESS
		)
	if _right_arm_available:
		_add_anatomical_joint(
			&"right_shoulder",
			&"torso",
			&"right_arm",
			_proximal_point(&"right_arm"),
			Vector3(-1.75, -1.22, -1.75),
			Vector3(1.75, 1.22, 1.75),
			SHOULDER_BRACE_STIFFNESS
		)
	if _left_leg_available:
		_add_leg_joints(&"left")
	if _right_leg_available:
		_add_leg_joints(&"right")


func _add_leg_joints(side: StringName) -> void:
	var upper_name := StringName("%s_upper_leg" % side)
	var lower_name := StringName("%s_lower_leg" % side)
	var foot_name := StringName("%s_foot" % side)
	_add_anatomical_joint(
		StringName("%s_hip" % side),
		&"torso",
		upper_name,
		_proximal_point(upper_name),
		Vector3(-0.87, -0.79, -0.87),
		Vector3(1.75, 0.79, 0.87),
		HIP_BRACE_STIFFNESS
	)
	_add_anatomical_joint(
		StringName("%s_knee" % side),
		upper_name,
		lower_name,
		_midpoint(upper_name, lower_name),
		Vector3(-2.18, -0.17, -0.17),
		Vector3(0.14, 0.17, 0.17),
		KNEE_BRACE_STIFFNESS
	)
	_add_anatomical_joint(
		StringName("%s_ankle" % side),
		lower_name,
		foot_name,
		_midpoint(lower_name, foot_name),
		Vector3(-0.61, -0.31, -0.44),
		Vector3(0.61, 0.31, 0.44),
		ANKLE_BRACE_STIFFNESS
	)


func _add_anatomical_joint(
	joint_name: StringName,
	body_a_name: StringName,
	body_b_name: StringName,
	anchor: Vector3,
	angular_lower: Vector3,
	angular_upper: Vector3,
	brace_stiffness: float
) -> void:
	var body_a := _bodies.get(body_a_name) as RigidBody3D
	var body_b := _bodies.get(body_b_name) as RigidBody3D
	if body_a == null or body_b == null:
		return
	var joint := _joints.get(joint_name) as Generic6DOFJoint3D
	if joint == null:
		joint = Generic6DOFJoint3D.new()
		joint.name = joint_name
		add_child(joint)
		_joints[joint_name] = joint
	var torso := _bodies.get(&"torso") as RigidBody3D
	var reference_basis := (
		torso.global_basis.orthonormalized()
		if torso != null
		else Basis.IDENTITY
	)
	joint.global_transform = Transform3D(reference_basis, anchor)
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.exclude_nodes_from_collision = true
	_joint_brace_stiffness[joint_name] = maxf(brace_stiffness, 0.0)
	_active_joint_names.append(joint_name)
	_configure_joint_axis(
		joint, 0, angular_lower.x, angular_upper.x, brace_stiffness
	)
	_configure_joint_axis(
		joint, 1, angular_lower.y, angular_upper.y, brace_stiffness
	)
	_configure_joint_axis(
		joint, 2, angular_lower.z, angular_upper.z, brace_stiffness
	)


func _configure_joint_axis(
	joint: Generic6DOFJoint3D,
	axis: int,
	lower_angle: float,
	upper_angle: float,
	brace_stiffness: float
) -> void:
	match axis:
		0:
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_angle)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_angle)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, 0.0)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, brace_stiffness)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, ACTIVE_BRACE_DAMPING)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)
		1:
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_angle)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_angle)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, 0.0)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, brace_stiffness)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, ACTIVE_BRACE_DAMPING)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)
		2:
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_angle)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_angle)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, 0.0)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, brace_stiffness)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, ACTIVE_BRACE_DAMPING)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)


func _update_active_brace(weight: float) -> void:
	var safe_weight := clampf(weight, 0.0, 1.0)
	var enabled := safe_weight > 0.001
	for joint_name: StringName in _active_joint_names:
		var joint := _joints.get(joint_name) as Generic6DOFJoint3D
		if joint == null:
			continue
		var stiffness := float(
			_joint_brace_stiffness.get(joint_name, 0.0)
		) * safe_weight
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, enabled)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, enabled)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, enabled)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)


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
	_active_joint_names.clear()
	for joint: Generic6DOFJoint3D in _joints.values():
		if not is_instance_valid(joint):
			continue
		joint.node_a = NodePath()
		joint.node_b = NodePath()
