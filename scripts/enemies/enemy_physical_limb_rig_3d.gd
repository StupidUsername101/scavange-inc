class_name EnemyPhysicalLimbRig3D
extends Skeleton3D

const PHYSICAL_LIMB_LAYER := 4
const WORLD_COLLISION_MASK := 1
const SEGMENTS_PER_LIMB := 2
const UPPER_SEGMENT_INDEX := 0
const LOWER_SEGMENT_INDEX := 1
const ROOT_BONE_NAME := "body_root"

#######################################################
# Builds and drives the physical-bone hierarchy that attaches simulated enemy limbs to the
# authoritative chassis.
#######################################################

var enemy: ServerEnemy
var anatomy: EnemyPhysicalAnatomyDefinition
var simulator: PhysicalBoneSimulator3D
var root_anchor: EnemyPhysicalBone3D
var gait_planner := EnemyGaitPlanner.new()
var segment_records: Array[Dictionary] = []
var simulated_bone_names: Array[StringName] = []
var runtime_active := false
var ragdoll_mode := false
var built := false


func configure(
	owner_enemy: ServerEnemy,
	new_anatomy: EnemyPhysicalAnatomyDefinition
) -> void:
	enemy = owner_enemy
	anatomy = new_anatomy
	if is_inside_tree():
		_build_rig()


func _ready() -> void:
	_build_rig()


func set_runtime_active(value: bool) -> void:
	runtime_active = value
	if not built or simulator == null:
		return
	if value:
		_start_simulation()
	else:
		_stop_simulation()


func set_ragdoll(value: bool) -> void:
	ragdoll_mode = value
	_set_segment_drive_mode(not value)
	if value:
		runtime_active = true
		_start_simulation()


func server_physics_tick(delta: float, body_velocity: Vector3) -> void:
	if (
		not built
		or not runtime_active
		or anatomy == null
		or not is_instance_valid(enemy)
	):
		return
	if simulator != null and not simulator.is_simulating_physics():
		_start_simulation()
	if ragdoll_mode:
		return

	var space_state := enemy.get_world_3d().direct_space_state
	var exclusions: Array[RID] = [enemy.get_rid()]
	gait_planner.update(
		delta,
		enemy.global_transform,
		body_velocity,
		space_state,
		exclusions
	)
	for limb_index: int in range(segment_records.size()):
		var points: PackedVector3Array = gait_planner.get_desired_limb_points(
			limb_index,
			enemy.global_transform
		)
		if points.size() != 3:
			continue
		var record: Dictionary = segment_records[limb_index]
		var upper := record.get("upper") as EnemyPhysicalBone3D
		var lower := record.get("lower") as EnemyPhysicalBone3D
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		if upper != null:
			_drive_segment(
				upper,
				points[0],
				points[1],
				limb.upper_length,
				limb.segment_mass,
				delta,
				body_velocity
			)
		if lower != null:
			_drive_segment(
				lower,
				points[1],
				points[2],
				limb.lower_length,
				limb.segment_mass,
				delta,
				body_velocity
			)


func get_limb_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if anatomy == null or not is_instance_valid(enemy):
		return result
	var to_local: Transform3D = enemy.global_transform.affine_inverse()
	for limb_index: int in range(anatomy.limbs.size()):
		var world_points: PackedVector3Array = _get_limb_world_points(limb_index)
		var local_points := PackedVector3Array()
		for point: Vector3 in world_points:
			local_points.append(to_local * point)
		result.append({
			"index": limb_index,
			"points": local_points,
			"stepping": gait_planner.is_limb_stepping(limb_index),
			"physical": (
				simulator != null
				and simulator.is_simulating_physics()
			),
		})
	return result


func get_physical_bone_count() -> int:
	return segment_records.size() * SEGMENTS_PER_LIMB


func get_total_physical_bone_count() -> int:
	return get_physical_bone_count() + (1 if is_instance_valid(root_anchor) else 0)


func get_maximum_drive_position_error() -> float:
	var maximum_error := 0.0
	for record: Dictionary in segment_records:
		for segment_key: String in ["upper", "lower"]:
			var physical_bone := record.get(segment_key) as EnemyPhysicalBone3D
			if (
				is_instance_valid(physical_bone)
				and physical_bone.has_previous_drive_transform
			):
				maximum_error = maxf(
					maximum_error,
					physical_bone.global_position.distance_to(
						physical_bone.previous_drive_transform.origin
					)
				)
	return maximum_error


func get_maximum_attachment_error() -> float:
	if anatomy == null or not is_instance_valid(enemy):
		return INF
	var maximum_error := 0.0
	for limb_index: int in range(segment_records.size()):
		var record: Dictionary = segment_records[limb_index]
		if record.is_empty() or limb_index >= anatomy.limbs.size():
			return INF
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		var upper := record.get("upper") as EnemyPhysicalBone3D
		var lower := record.get("lower") as EnemyPhysicalBone3D
		if limb == null or not is_instance_valid(upper) or not is_instance_valid(lower):
			return INF
		var expected_hip: Vector3 = enemy.global_transform * limb.hip_offset
		var upper_joint := get_joint_world_transform(upper).origin
		var upper_end: Vector3 = (
			upper.global_position
			+ upper.global_basis.y.normalized() * limb.upper_length * 0.5
		)
		var lower_joint := get_joint_world_transform(lower).origin
		maximum_error = maxf(
			maximum_error,
			maxf(
				upper_joint.distance_to(expected_hip),
				upper_end.distance_to(lower_joint)
			)
		)
	return maximum_error


func get_root_anchor_position_error() -> float:
	if not is_instance_valid(root_anchor) or not is_instance_valid(enemy):
		return INF
	return root_anchor.global_position.distance_to(enemy.global_position)


func get_minimum_knee_bend_alignment() -> float:
	if anatomy == null or not is_instance_valid(enemy):
		return -1.0
	var minimum_alignment := 1.0
	var found_limb := false
	for limb_index: int in range(anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		if limb == null:
			continue
		var points := _get_limb_world_points(limb_index)
		var world_bend_hint: Vector3 = enemy.global_basis * limb.bend_hint
		minimum_alignment = minf(
			minimum_alignment,
			calculate_knee_bend_alignment(points, world_bend_hint)
		)
		found_limb = true
	return minimum_alignment if found_limb else -1.0


func get_minimum_foot_outward_projection_ratio() -> float:
	if anatomy == null or not is_instance_valid(enemy):
		return -INF
	var to_local := enemy.global_transform.affine_inverse()
	var minimum_ratio := INF
	var found_limb := false
	for limb_index: int in range(anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		if limb == null:
			continue
		var points := _get_limb_world_points(limb_index)
		if points.size() != 3:
			continue
		var rest_outward = limb.rest_foot_offset - limb.hip_offset
		rest_outward.y = 0.0
		if rest_outward.length_squared() <= 0.000001:
			continue
		var foot_local: Vector3 = to_local * points[2]
		var current_outward = foot_local - limb.hip_offset
		current_outward.y = 0.0
		var ratio = (
			current_outward.dot(rest_outward.normalized())
			/ rest_outward.length()
		)
		minimum_ratio = minf(minimum_ratio, ratio)
		found_limb = true
	return minimum_ratio if found_limb else -INF


func has_valid_root_anchor(require_stationary := false) -> bool:
	if (
		not is_instance_valid(root_anchor)
		or root_anchor.expected_bone_id != 0
		or root_anchor.get_bone_id() != 0
		or root_anchor.get_parent() != simulator
		or root_anchor.joint_type != PhysicalBone3D.JOINT_TYPE_NONE
		or root_anchor.collision_layer != 0
		or root_anchor.collision_mask != 0
	):
		return false
	return not require_stationary or not root_anchor.is_simulating_physics()


func has_valid_physical_bindings(require_simulating := false) -> bool:
	if anatomy == null or simulator == null:
		return false
	if get_bone_count() != anatomy.get_segment_count() + 1:
		return false
	if simulator.get_skeleton() != self:
		return false
	if not has_valid_root_anchor(require_simulating):
		return false
	if simulated_bone_names.size() != anatomy.get_segment_count():
		return false
	var bound_bone_ids: Dictionary[int, bool] = {}
	for record: Dictionary in segment_records:
		if record.is_empty():
			return false
		var upper_bone_id := int(record.get("upper_bone_id", -1))
		var lower_bone_id := int(record.get("lower_bone_id", -1))
		if (
			upper_bone_id <= 0
			or lower_bone_id <= 0
			or get_bone_parent(upper_bone_id) != 0
			or get_bone_parent(lower_bone_id) != upper_bone_id
		):
			return false
		for segment_key: String in ["upper", "lower"]:
			var physical_bone := record.get(segment_key) as EnemyPhysicalBone3D
			if not is_instance_valid(physical_bone):
				return false
			var bone_id := physical_bone.get_bone_id()
			if bone_id != physical_bone.expected_bone_id:
				return false
			if bone_id <= 0 or bone_id >= get_bone_count():
				return false
			if bound_bone_ids.has(bone_id):
				return false
			if require_simulating and not physical_bone.is_simulating_physics():
				return false
			bound_bone_ids[bone_id] = true
	return bound_bone_ids.size() == anatomy.get_segment_count()


func _build_rig() -> void:
	if built or anatomy == null or not is_instance_valid(enemy):
		return
	built = true
	name = "PhysicalLimbRig"
	# Keep the simulator's skeleton updates on the same fixed tick as the
	# server-side physical drives. Godot defaults this property to idle mode.
	modifier_callback_mode_process = (
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	)

	var root_bone_id := add_bone(ROOT_BONE_NAME)
	set_bone_rest(root_bone_id, Transform3D.IDENTITY)
	var bone_records := _build_skeleton_bone_records(root_bone_id)
	_create_physical_bone_simulator(root_bone_id)
	_create_all_physical_segments(bone_records)
	_validate_physical_bindings()
	_configure_runtime_gait()


func _build_skeleton_bone_records(
	root_bone_id: int
) -> Array[Dictionary]:
	# Build the complete Skeleton3D before the simulator enters the tree.
	# PhysicalBoneSimulator3D sizes its binding table when it attaches to the
	# skeleton. Adding more bones afterward leaves that table stale and produces
	# `p_bone is out of bounds (bone_size = 1)` for every limb segment.
	var bone_records: Array[Dictionary] = []
	for limb_index: int in range(anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		if limb == null:
			bone_records.append({})
			continue
		var rest_points: PackedVector3Array = EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		var safe_name: String = limb.limb_name.to_snake_case()
		var upper_name := "%s_upper" % safe_name
		var lower_name := "%s_lower" % safe_name
		var upper_global_rest := _segment_transform(
			rest_points[0],
			rest_points[1],
			false
		)
		var lower_global_rest := _segment_transform(
			rest_points[1],
			rest_points[2],
			false
		)
		var upper_bone_id := add_bone(upper_name)
		set_bone_parent(upper_bone_id, root_bone_id)
		set_bone_rest(upper_bone_id, upper_global_rest)
		var lower_bone_id := add_bone(lower_name)
		set_bone_parent(lower_bone_id, upper_bone_id)
		set_bone_rest(
			lower_bone_id,
			upper_global_rest.affine_inverse() * lower_global_rest
		)
		bone_records.append({
			"upper_name": upper_name,
			"upper_bone_id": upper_bone_id,
			"lower_name": lower_name,
			"lower_bone_id": lower_bone_id,
		})
	return bone_records


func _create_physical_bone_simulator(root_bone_id: int) -> void:
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	simulator.active = true
	simulator.influence = anatomy.physical_influence
	add_child(simulator)
	root_anchor = _create_root_anchor(root_bone_id)


func _create_all_physical_segments(
	bone_records: Array[Dictionary]
) -> void:
	for limb_index: int in range(anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
		var bone_record: Dictionary = bone_records[limb_index]
		if limb == null or bone_record.is_empty():
			segment_records.append({})
			continue
		var upper := _create_physical_segment(
			str(bone_record["upper_name"]),
			int(bone_record["upper_bone_id"]),
			limb,
			limb_index,
			UPPER_SEGMENT_INDEX,
			limb.upper_length,
			PhysicalBone3D.JOINT_TYPE_CONE,
			Basis.IDENTITY
		)
		var rest_points: PackedVector3Array = EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		var knee_joint_basis := create_knee_joint_basis(rest_points)
		var lower := _create_physical_segment(
			str(bone_record["lower_name"]),
			int(bone_record["lower_bone_id"]),
			limb,
			limb_index,
			LOWER_SEGMENT_INDEX,
			limb.lower_length,
			PhysicalBone3D.JOINT_TYPE_HINGE,
			knee_joint_basis
		)
		simulated_bone_names.append(StringName(str(bone_record["upper_name"])))
		simulated_bone_names.append(StringName(str(bone_record["lower_name"])))
		segment_records.append({
			"upper": upper,
			"upper_bone_id": int(bone_record["upper_bone_id"]),
			"lower": lower,
			"lower_bone_id": int(bone_record["lower_bone_id"]),
		})


func _validate_physical_bindings() -> void:
	if not has_valid_physical_bindings(false):
		push_error(
			"Physical limb rig failed to bind all %d segments to its %d-bone skeleton"
			% [anatomy.get_segment_count(), get_bone_count()]
		)


func _configure_runtime_gait() -> void:
	if is_inside_tree():
		simulator.physical_bones_add_collision_exception(enemy.get_rid())
	var space_state := enemy.get_world_3d().direct_space_state
	gait_planner.configure(
		anatomy,
		enemy.global_transform,
		space_state,
		[enemy.get_rid()]
	)
	if runtime_active:
		call_deferred("_start_simulation")


func _create_root_anchor(root_bone_id: int) -> EnemyPhysicalBone3D:
	var anchor := EnemyPhysicalBone3D.new()
	anchor.name = "Physical Bone body_root"
	anchor.configure(enemy, -1, -1, root_bone_id)
	anchor.set("bone_name", get_bone_name(root_bone_id))
	anchor.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	anchor.body_offset = Transform3D.IDENTITY
	anchor.joint_offset = Transform3D.IDENTITY
	anchor.gravity_scale = 0.0
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.can_sleep = true
	simulator.add_child(anchor)
	return anchor


func _create_physical_segment(
	bone_name: String,
	expected_bone_id: int,
	limb: EnemyPhysicalLimbDefinition,
	limb_index: int,
	segment_index: int,
	length: float,
	joint_kind: int,
	joint_basis: Basis
) -> EnemyPhysicalBone3D:
	var physical_bone := EnemyPhysicalBone3D.new()
	physical_bone.name = "Physical Bone %s" % bone_name
	physical_bone.configure(
		enemy,
		limb_index,
		segment_index,
		expected_bone_id
	)
	# bone_name is a dynamic inspector property on PhysicalBone3D rather than a
	# regular documented script property in Godot 4.6.
	physical_bone.set("bone_name", bone_name)
	physical_bone.joint_type = joint_kind
	physical_bone.mass = limb.segment_mass
	physical_bone.friction = anatomy.friction
	physical_bone.bounce = anatomy.bounce
	physical_bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.linear_damp = anatomy.passive_linear_damp
	physical_bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.angular_damp = anatomy.passive_angular_damp
	physical_bone.gravity_scale = anatomy.driven_gravity_scale
	# A sleeping active-drive body can trail one or more fixed ticks behind a
	# CharacterBody3D chassis before an impulse wakes it. Driven limbs must stay
	# awake; ragdoll mode changes this back to a passive body.
	physical_bone.can_sleep = false
	physical_bone.collision_layer = PHYSICAL_LIMB_LAYER
	physical_bone.collision_mask = WORLD_COLLISION_MASK
	physical_bone.body_offset = create_segment_body_offset(length)
	# PhysicalBone3D's joint frame is relative to the rigid body's center,
	# while the skeleton bone starts at the proximal joint. Godot's editor
	# generator applies this same inverse body offset. Setting it explicitly is
	# important for runtime-created bones because their body offset is assigned
	# before they acquire a Skeleton3D parent.
	physical_bone.joint_offset = create_proximal_joint_offset(
		length,
		joint_basis
	)
	if joint_kind == PhysicalBone3D.JOINT_TYPE_CONE:
		# PhysicalBone3D's dynamic constraint properties use inspector degrees;
		# the engine converts them to radians internally.
		physical_bone.set(
			"joint_constraints/swing_span",
			limb.hip_swing_span_degrees
		)
		physical_bone.set(
			"joint_constraints/twist_span",
			limb.hip_twist_span_degrees
		)
	elif joint_kind == PhysicalBone3D.JOINT_TYPE_HINGE:
		physical_bone.set("joint_constraints/angular_limit_enabled", true)
		physical_bone.set(
			"joint_constraints/angular_limit_lower",
			limb.knee_limit_lower_degrees
		)
		physical_bone.set(
			"joint_constraints/angular_limit_upper",
			limb.knee_limit_upper_degrees
		)

	var capsule := CapsuleShape3D.new()
	capsule.radius = limb.segment_radius
	capsule.height = maxf(length, limb.segment_radius * 2.0)
	var collision := CollisionShape3D.new()
	collision.name = "SegmentCollision"
	collision.shape = capsule
	physical_bone.add_child(collision)
	simulator.add_child(physical_bone)
	return physical_bone


func _start_simulation() -> void:
	if simulator == null or simulator.is_simulating_physics():
		return
	_set_segment_drive_mode(not ragdoll_mode)
	_reset_drive_histories()
	# Keep body_root non-simulated so it follows the authoritative enemy chassis.
	# Every upper limb then has a real physical parent without turning the stable
	# CharacterBody3D chassis into another independently drifting rigid body.
	simulator.physical_bones_start_simulation(simulated_bone_names)
	call_deferred("_validate_started_simulation")


func _stop_simulation() -> void:
	if simulator == null:
		return
	if simulator.is_simulating_physics():
		simulator.physical_bones_stop_simulation()
	_reset_drive_histories()
	reset_bone_poses()
	if anatomy != null and is_instance_valid(enemy):
		gait_planner.reset(
			enemy.global_transform,
			enemy.get_world_3d().direct_space_state,
			[enemy.get_rid()]
		)


func _reset_drive_histories() -> void:
	for record: Dictionary in segment_records:
		for segment_key: String in ["upper", "lower"]:
			var physical_bone := record.get(segment_key) as EnemyPhysicalBone3D
			if is_instance_valid(physical_bone):
				physical_bone.reset_drive_history()


func _validate_started_simulation() -> void:
	if not runtime_active or ragdoll_mode or not is_inside_tree():
		return
	if not has_valid_physical_bindings(true):
		push_error(
			"Physical limb simulation started without all segments bound and active"
		)


func _drive_segment(
	physical_bone: EnemyPhysicalBone3D,
	start: Vector3,
	end: Vector3,
	length: float,
	mass_value: float,
	delta: float,
	chassis_velocity: Vector3
) -> void:
	if (
		not is_instance_valid(physical_bone)
		or not physical_bone.is_simulating_physics()
		or ragdoll_mode
	):
		return
	var desired: Transform3D = _segment_transform(start, end, true)
	# On the first driven frame there is no target history yet. Matching the
	# chassis velocity avoids applying a braking impulse just as locomotion
	# begins, which otherwise leaves the entire chain behind the body.
	var target_linear_velocity := chassis_velocity
	var target_angular_velocity := Vector3.ZERO
	if physical_bone.has_previous_drive_transform and delta > 0.000001:
		target_linear_velocity = (
			(desired.origin - physical_bone.previous_drive_transform.origin)
			/ delta
		).limit_length(anatomy.maximum_target_speed)
		target_angular_velocity = _get_target_angular_velocity(
			physical_bone.previous_drive_transform.basis,
			desired.basis,
			delta
		).limit_length(anatomy.maximum_target_angular_speed)
	physical_bone.previous_drive_transform = desired
	physical_bone.has_previous_drive_transform = true

	var position_error := desired.origin - physical_bone.global_position
	var acceleration := calculate_linear_drive_acceleration(
		position_error,
		target_linear_velocity,
		physical_bone.linear_velocity,
		anatomy.position_stiffness,
		anatomy.position_damping
	)
	var force: Vector3 = acceleration * mass_value
	force = force.limit_length(anatomy.maximum_drive_force)
	if force.length_squared() > 0.0000001:
		PhysicsServer3D.body_apply_central_force(physical_bone.get_rid(), force)

	var torque := calculate_angular_drive_torque(
		physical_bone.global_basis,
		desired.basis,
		target_angular_velocity,
		physical_bone.angular_velocity,
		mass_value,
		length,
		anatomy.angular_stiffness,
		anatomy.angular_damping,
		anatomy.maximum_drive_torque
	)
	if torque.length_squared() > 0.0000001:
		# PhysicalBone3D does not expose apply_torque(), but its RID is an
		# ordinary rigid physics body. Applying torque directly avoids the old
		# hand-built force couple, whose cross-product order generated exactly
		# the opposite torque and drove every limb away from its IK target.
		PhysicsServer3D.body_apply_torque(physical_bone.get_rid(), torque)


static func calculate_linear_drive_acceleration(
	position_error: Vector3,
	target_velocity: Vector3,
	current_velocity: Vector3,
	position_stiffness: float,
	velocity_damping: float
) -> Vector3:
	return (
		position_error * position_stiffness
		+ (target_velocity - current_velocity) * velocity_damping
	)


static func calculate_angular_drive_torque(
	current_basis: Basis,
	desired_basis: Basis,
	target_angular_velocity: Vector3,
	current_angular_velocity: Vector3,
	mass_value: float,
	segment_length: float,
	angular_stiffness: float,
	angular_damping: float,
	maximum_torque: float
) -> Vector3:
	var current_rotation := current_basis.get_rotation_quaternion()
	var desired_rotation := desired_basis.get_rotation_quaternion()
	var error_rotation := (
		current_rotation.inverse() * desired_rotation
	).normalized()
	var angle := error_rotation.get_angle()
	var local_axis := error_rotation.get_axis()
	if angle > PI:
		angle = TAU - angle
		local_axis = -local_axis
	if angle <= 0.0001 or local_axis.length_squared() <= 0.000001:
		return Vector3.ZERO
	var world_axis := (current_basis * local_axis).normalized()
	var angular_acceleration: Vector3 = (
		world_axis * angle * angular_stiffness
		+ (target_angular_velocity - current_angular_velocity)
		* angular_damping
	)
	var safe_mass := maxf(mass_value, 0.001)
	var safe_length := maxf(segment_length, 0.001)
	var inertia_approximation := (
		safe_mass * safe_length * safe_length / 12.0
	)
	return (
		angular_acceleration * inertia_approximation
	).limit_length(maxf(maximum_torque, 0.0))


static func calculate_knee_bend_alignment(
	points: PackedVector3Array,
	bend_hint: Vector3
) -> float:
	if points.size() != 3:
		return -1.0
	var hip_to_foot := points[2] - points[0]
	if hip_to_foot.length_squared() <= 0.000001:
		return -1.0
	var leg_axis := hip_to_foot.normalized()
	var knee_from_line := (
		points[1]
		- points[0]
		- leg_axis * (points[1] - points[0]).dot(leg_axis)
	)
	var preferred_bend := bend_hint - leg_axis * bend_hint.dot(leg_axis)
	if (
		knee_from_line.length_squared() <= 0.000001
		or preferred_bend.length_squared() <= 0.000001
	):
		return -1.0
	return knee_from_line.normalized().dot(preferred_bend.normalized())


static func _get_target_angular_velocity(
	previous_basis: Basis,
	current_basis: Basis,
	delta: float
) -> Vector3:
	if delta <= 0.000001:
		return Vector3.ZERO
	var previous_rotation := previous_basis.get_rotation_quaternion()
	var current_rotation := current_basis.get_rotation_quaternion()
	var rotation_delta := (
		previous_rotation.inverse() * current_rotation
	).normalized()
	var angle := rotation_delta.get_angle()
	var local_axis := rotation_delta.get_axis()
	if angle > PI:
		angle = TAU - angle
		local_axis = -local_axis
	if angle <= 0.0001 or local_axis.length_squared() <= 0.000001:
		return Vector3.ZERO
	return (previous_basis * local_axis).normalized() * angle / delta


func _set_segment_drive_mode(driven: bool) -> void:
	if anatomy == null:
		return
	for record: Dictionary in segment_records:
		for segment_key: String in ["upper", "lower"]:
			var physical_bone := (
				record.get(segment_key) as EnemyPhysicalBone3D
			)
			if not is_instance_valid(physical_bone):
				continue
			physical_bone.gravity_scale = (
				anatomy.driven_gravity_scale
				if driven
				else anatomy.ragdoll_gravity_scale
			)
			physical_bone.can_sleep = not driven


func _get_limb_world_points(limb_index: int) -> PackedVector3Array:
	if (
		anatomy == null
		or limb_index < 0
		or limb_index >= anatomy.limbs.size()
	):
		return PackedVector3Array()
	var desired: PackedVector3Array = gait_planner.get_desired_limb_points(
		limb_index,
		enemy.global_transform
	)
	if (
		limb_index >= segment_records.size()
		or segment_records[limb_index].is_empty()
		or simulator == null
		or not simulator.is_simulating_physics()
	):
		return desired
	var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
	var record: Dictionary = segment_records[limb_index]
	var upper := record.get("upper") as EnemyPhysicalBone3D
	var lower := record.get("lower") as EnemyPhysicalBone3D
	if not is_instance_valid(upper) or not is_instance_valid(lower):
		return desired
	var upper_axis: Vector3 = upper.global_basis.y.normalized()
	var lower_axis: Vector3 = lower.global_basis.y.normalized()
	# The chassis attachment is authoritative. Publishing that exact point also
	# prevents a solver-sized visual crack from appearing at a correctly joined
	# physical hip.
	var hip: Vector3 = enemy.global_transform * limb.hip_offset
	var upper_end: Vector3 = (
		upper.global_position + upper_axis * limb.upper_length * 0.5
	)
	var lower_start: Vector3 = (
		lower.global_position - lower_axis * limb.lower_length * 0.5
	)
	var foot: Vector3 = (
		lower.global_position + lower_axis * limb.lower_length * 0.5
	)
	var knee: Vector3 = upper_end.lerp(lower_start, 0.5)
	return PackedVector3Array([hip, knee, foot])


static func create_segment_body_offset(length: float) -> Transform3D:
	return Transform3D(
		Basis.IDENTITY,
		Vector3.UP * maxf(length, 0.0) * 0.5
	)


static func create_proximal_joint_offset(
	length: float,
	joint_basis: Basis = Basis.IDENTITY
) -> Transform3D:
	return Transform3D(
		joint_basis.orthonormalized(),
		Vector3.DOWN * maxf(length, 0.0) * 0.5
	)


static func create_knee_joint_basis(
	rest_points: PackedVector3Array
) -> Basis:
	if rest_points.size() != 3:
		return Basis.IDENTITY
	var upper_direction := (rest_points[1] - rest_points[0]).normalized()
	var lower_direction := (rest_points[2] - rest_points[1]).normalized()
	var hinge_axis := upper_direction.cross(lower_direction)
	if hinge_axis.length_squared() <= 0.000001:
		hinge_axis = lower_direction.cross(Vector3.UP)
	if hinge_axis.length_squared() <= 0.000001:
		hinge_axis = lower_direction.cross(Vector3.RIGHT)
	var lower_basis := EnemyPhysicalLimbVisual3D.basis_from_y(lower_direction)
	var local_hinge_axis := (lower_basis.inverse() * hinge_axis).normalized()
	var local_segment_axis := Vector3.UP
	var local_x := local_segment_axis.cross(local_hinge_axis)
	if local_x.length_squared() <= 0.000001:
		return Basis.IDENTITY
	local_x = local_x.normalized()
	var local_y := local_hinge_axis.cross(local_x).normalized()
	# Godot's HingeJoint3D rotates around the joint frame's local Z axis.
	return Basis(local_x, local_y, local_hinge_axis).orthonormalized()


static func get_joint_world_transform(
	physical_bone: PhysicalBone3D
) -> Transform3D:
	if physical_bone == null:
		return Transform3D.IDENTITY
	return physical_bone.global_transform * physical_bone.joint_offset


static func _segment_transform(
	start: Vector3,
	end: Vector3,
	centered: bool
) -> Transform3D:
	var offset := end - start
	var direction := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.UP
	var origin := start.lerp(end, 0.5) if centered else start
	return Transform3D(
		EnemyPhysicalLimbVisual3D.basis_from_y(direction),
		origin
	)
