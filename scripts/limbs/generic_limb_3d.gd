class_name GenericLimb3D
extends Node3D

#######################################################
# Runtime chain for one GenericLimbDefinition. Rigid bodies and joints are siblings below this static
# container, never children of moving rigid bodies. Any positive number of parts is supported.
#######################################################

const MAX_CONTACTS_REPORTED := 8

var owner_body: Node
var core_body: RigidBody3D
var definition: GenericLimbDefinition
var slot_index := -1
var collision_layer_value := 4
var collision_mask_value := 1
var segments: Array[LimbSegment3D] = []
var joints: Array[Generic6DOFJoint3D] = []
var joint_records: Array[Dictionary] = []
var end_effector: LimbEndEffector3D
var color := Color.WHITE
var built := false


func configure(
	body: Node,
	core: RigidBody3D,
	new_definition: GenericLimbDefinition,
	new_slot_index: int,
	new_color: Color,
	new_collision_layer: int = 4,
	new_collision_mask: int = 1
) -> void:
	owner_body = body
	core_body = core
	definition = new_definition
	slot_index = new_slot_index
	color = new_color
	collision_layer_value = new_collision_layer
	collision_mask_value = new_collision_mask
	if definition != null:
		definition.sanitize()
	if is_inside_tree():
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if built or definition == null or not definition.installed or not is_instance_valid(core_body):
		return
	definition.sanitize()
	var validation_error: String = definition.ml_validation_error()
	if not validation_error.is_empty():
		push_error("Generic limb build rejected: %s" % validation_error)
		return
	built = true
	var start_local := definition.mount_offset_local
	var parent_body: RigidBody3D = core_body
	var parent_rest_basis := Basis.IDENTITY
	for segment_index_value in range(definition.segments.size()):
		var segment_definition: LimbSegmentDefinition = definition.segments[segment_index_value]
		if segment_definition == null:
			continue
		segment_definition.sanitize()
		var direction := segment_definition.rest_direction_local.normalized()
		var end_local := start_local + direction * segment_definition.length
		var segment_basis := basis_from_y(direction)
		var segment_transform_local := Transform3D(
			segment_basis,
			start_local.lerp(end_local, 0.5)
		)
		var segment := _create_segment(
			segment_definition,
			segment_index_value,
			segment_transform_local
		)
		var joint_definition: LimbJointDefinition = segment_definition.joint
		var joint := _create_joint(
			parent_body,
			segment,
			joint_definition,
			Transform3D(joint_definition.joint_basis_local, start_local)
		)
		var rest_relative := (parent_rest_basis.inverse() * segment_basis).orthonormalized()
		var joint_basis_parent := (
			parent_rest_basis.inverse() * joint_definition.joint_basis_local
		).orthonormalized()
		joint_records.append({
			"joint_index": segment_index_value,
			"parent": parent_body,
			"child": segment,
			"joint": joint,
			"definition": joint_definition,
			"rest_relative_basis": rest_relative,
			"joint_basis_parent": joint_basis_parent,
			"rest_start_local": start_local,
			"rest_end_local": end_local,
			"smoothed_target_angles": Vector3.ZERO,
			"current_angles": Vector3.ZERO,
			"target_angles": Vector3.ZERO,
			"passive_stretch_ratio": Vector3.ZERO,
			"passive_torque_joint": Vector3.ZERO,
			"active_torque_joint": Vector3.ZERO,
			"limit_torque_joint": Vector3.ZERO,
			"applied_torque_joint": Vector3.ZERO,
		})
		segments.append(segment)
		joints.append(joint)
		parent_body = segment
		parent_rest_basis = segment_basis
		start_local = end_local
	_build_end_effector()


func _build_end_effector() -> void:
	if segments.is_empty() or definition == null or definition.end_effector == null:
		return
	var effector_definition := definition.end_effector
	effector_definition.sanitize()
	if not effector_definition.enabled:
		return
	var distal_segment: LimbSegment3D = segments[-1]
	var distal_definition: LimbSegmentDefinition = definition.segments[-1]
	if not is_instance_valid(distal_segment) or distal_definition == null:
		return
	end_effector = LimbEndEffector3D.new()
	distal_segment.add_child(end_effector)
	end_effector.configure(
		distal_segment,
		effector_definition,
		Vector3.UP * distal_definition.length * 0.5,
		color
	)
	if effector_definition.added_mass > 0.0:
		distal_segment.mass += effector_definition.added_mass
	if effector_definition.is_physically_present():
		# The generic segment has a decorative sphere centered on its distal tip. That sphere
		# intentionally protrudes beyond the capsule and therefore visually intersects a real
		# terminal such as the stock sole even though the collision shapes are separated. A
		# physical terminal replaces that decoration at the end of the chain.
		var distal_cap: MeshInstance3D = distal_segment.get_node_or_null("JointCap") as MeshInstance3D
		if distal_cap != null:
			distal_cap.visible = false
		# PhysicsMaterial is body-wide in Godot. An enabled terminal surface therefore becomes the
		# distal body's authored contact material rather than pretending one RigidBody has two.
		distal_segment.configure_surface_material(
			effector_definition.friction,
			effector_definition.bounce,
			effector_definition.rough,
			effector_definition.absorbent
		)


func _create_segment(
	segment_definition: LimbSegmentDefinition,
	new_segment_index: int,
	rest_transform_core_local: Transform3D
) -> LimbSegment3D:
	var segment := LimbSegment3D.new()
	segment.name = "%s_%02d" % [definition.limb_name.validate_node_name(), new_segment_index]
	segment.configure(
		owner_body,
		slot_index,
		new_segment_index,
		StringName("limb_%02d_segment_%02d" % [slot_index, new_segment_index]),
		segment_definition.maximum_health
	)
	segment.mass = segment_definition.mass
	segment.configure_surface_material(
		segment_definition.friction,
		segment_definition.bounce,
		segment_definition.rough
	)
	segment.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	segment.linear_damp = 0.6
	segment.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	segment.angular_damp = 1.2
	segment.continuous_cd = segment_definition.continuous_collision_detection
	segment.can_sleep = false
	segment.freeze = true
	segment.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	segment.collision_layer = collision_layer_value
	segment.collision_mask = collision_mask_value
	segment.max_contacts_reported = MAX_CONTACTS_REPORTED
	segment.contact_monitor = true
	add_child(segment)
	# Limb definitions are authored in core-local space. Do not assume the core happens to be at
	# this container's origin: a creature editor, test scene, or spawned body may give it any world
	# transform. Store the resulting container-local pose so reset_to_rest() remains deterministic.
	var rest_transform_world := core_body.global_transform * rest_transform_core_local
	segment.global_transform = rest_transform_world
	segment.rest_transform_local = global_transform.affine_inverse() * rest_transform_world

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = segment_definition.radius
	shape.height = maxf(segment_definition.length, segment_definition.radius * 2.0)
	collision.shape = shape
	segment.add_child(collision)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := CapsuleMesh.new()
	mesh.radius = segment_definition.radius
	mesh.height = maxf(segment_definition.length, segment_definition.radius * 2.0)
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lightened(0.08 * float(new_segment_index % 2))
	material.roughness = 0.7
	visual.material_override = material
	segment.add_child(visual)

	# The local +Y end is distal because basis_from_y() points +Y from mount to tip.
	var cap := MeshInstance3D.new()
	cap.name = "JointCap"
	cap.position = Vector3.UP * segment_definition.length * 0.5
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = maxf(segment_definition.radius * 1.08, 0.055)
	cap_mesh.height = cap_mesh.radius * 2.0
	cap.mesh = cap_mesh
	cap.material_override = material
	segment.add_child(cap)
	return segment


func _create_joint(
	parent_body: RigidBody3D,
	child_body: LimbSegment3D,
	joint_definition: LimbJointDefinition,
	joint_transform_core_local: Transform3D
) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "%sJoint%02d" % [definition.limb_name.validate_node_name(), joints.size()]
	# Godot defines lower values as higher solver priority. Articulated support joints should be
	# solved before less important constraints, not near the back of the queue.
	joint.solver_priority = 1
	joint.exclude_nodes_from_collision = true
	add_child(joint)
	joint.global_transform = core_body.global_transform * joint_transform_core_local
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)
	_configure_joint_axis(joint, Vector3.AXIS_X, joint_definition)
	_configure_joint_axis(joint, Vector3.AXIS_Y, joint_definition)
	_configure_joint_axis(joint, Vector3.AXIS_Z, joint_definition)
	return joint


func _configure_joint_axis(
	joint: Generic6DOFJoint3D,
	axis: int,
	joint_definition: LimbJointDefinition
) -> void:
	var lower := deg_to_rad(joint_definition.lower_limit_degrees[axis])
	var upper := deg_to_rad(joint_definition.upper_limit_degrees[axis])
	var spring_enabled := (
		joint_definition.use_native_passive_spring
		and joint_definition.native_passive_fraction > 0.0
		and joint_definition.axis_is_free(axis)
		and joint_definition.passive_stiffness[axis] > 0.0
	)
	match axis:
		Vector3.AXIS_X:
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, spring_enabled)
			joint.set_param_x(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS,
				joint_definition.passive_stiffness.x * joint_definition.native_passive_fraction
			)
			joint.set_param_x(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING,
				joint_definition.passive_damping.x * joint_definition.native_passive_fraction
			)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)
		Vector3.AXIS_Y:
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, spring_enabled)
			joint.set_param_y(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS,
				joint_definition.passive_stiffness.y * joint_definition.native_passive_fraction
			)
			joint.set_param_y(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING,
				joint_definition.passive_damping.y * joint_definition.native_passive_fraction
			)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)
		Vector3.AXIS_Z:
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, spring_enabled)
			joint.set_param_z(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS,
				joint_definition.passive_stiffness.z * joint_definition.native_passive_fraction
			)
			joint.set_param_z(
				Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING,
				joint_definition.passive_damping.z * joint_definition.native_passive_fraction
			)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, 0.0)
	# Do not repurpose PARAM_ANGULAR_FORCE_LIMIT as a spring-torque cap. It belongs to the angular
	# constraint/limit. Explicit passive and active torques are clamped independently by the
	# LimbsController3D, while the solver's hard anatomical stop remains unrestricted.


func set_runtime_active(active: bool) -> void:
	for segment: LimbSegment3D in segments:
		if not is_instance_valid(segment):
			continue
		segment.freeze = not active
		segment.sleeping = false


func reset_to_rest() -> void:
	for segment: LimbSegment3D in segments:
		if not is_instance_valid(segment):
			continue
		segment.freeze = true
		segment.transform = segment.rest_transform_local
		segment.linear_velocity = Vector3.ZERO
		segment.angular_velocity = Vector3.ZERO
	if is_instance_valid(end_effector):
		end_effector.reset_state()
	for record: Dictionary in joint_records:
		record["smoothed_target_angles"] = Vector3.ZERO
		record["current_angles"] = Vector3.ZERO
		record["target_angles"] = Vector3.ZERO
		record["passive_stretch_ratio"] = Vector3.ZERO
		record["passive_torque_joint"] = Vector3.ZERO
		record["active_torque_joint"] = Vector3.ZERO
		record["limit_torque_joint"] = Vector3.ZERO
		record["applied_torque_joint"] = Vector3.ZERO


func foot_world_position() -> Vector3:
	if definition == null or not is_instance_valid(core_body):
		return global_position
	if segments.is_empty() or definition.segments.is_empty():
		return core_body.global_transform * definition.mount_offset_local
	var last_segment: LimbSegment3D = segments[-1]
	var last_definition: LimbSegmentDefinition = definition.segments[-1]
	if not is_instance_valid(last_segment) or last_definition == null:
		return Vector3(INF, INF, INF)
	if is_instance_valid(end_effector) and not end_effector.disabled:
		return end_effector.world_contact_point()
	return (
		last_segment.global_position
		+ last_segment.global_basis.y.normalized() * last_definition.length * 0.5
	)


func foot_world_velocity() -> Vector3:
	if segments.is_empty() or definition == null or definition.segments.is_empty():
		return Vector3.ZERO
	var last_segment: LimbSegment3D = segments[-1]
	if not is_instance_valid(last_segment):
		return Vector3.ZERO
	var foot_position := foot_world_position()
	return (
		last_segment.linear_velocity
		+ last_segment.angular_velocity.cross(foot_position - last_segment.global_position)
	)


func hip_world_position() -> Vector3:
	if definition == null or not is_instance_valid(core_body):
		return global_position
	if segments.is_empty() or definition.segments.is_empty():
		return core_body.global_transform * definition.mount_offset_local
	var first_segment: LimbSegment3D = segments[0]
	var first_definition: LimbSegmentDefinition = definition.segments[0]
	if not is_instance_valid(first_segment) or first_definition == null:
		return Vector3(INF, INF, INF)
	return (
		first_segment.global_position
		- first_segment.global_basis.y.normalized() * first_definition.length * 0.5
	)


func all_body_rids() -> Array[RID]:
	var result: Array[RID] = []
	for segment: LimbSegment3D in segments:
		if is_instance_valid(segment) and segment.get_rid().is_valid():
			result.append(segment.get_rid())
	return result


func total_mass() -> float:
	var result := 0.0
	for segment: LimbSegment3D in segments:
		if is_instance_valid(segment):
			result += segment.mass
	return result


func end_effector_snapshot() -> Dictionary:
	if is_instance_valid(end_effector):
		return end_effector.state_snapshot()
	return LimbEndEffector3D.empty_snapshot()


func has_valid_topology() -> bool:
	if definition == null or not definition.installed:
		return segments.is_empty() and joints.is_empty() and joint_records.is_empty()
	return (
		segments.size() == definition.segment_count()
		and joints.size() == segments.size()
		and joint_records.size() == segments.size()
	)


func has_configured_native_springs() -> bool:
	if joints.size() != joint_records.size():
		return false
	for index in range(joint_records.size()):
		var joint := joints[index]
		var joint_definition := joint_records[index].get("definition") as LimbJointDefinition
		if not is_instance_valid(joint) or joint_definition == null:
			return false
		for axis in range(3):
			var expected_enabled := (
				joint_definition.use_native_passive_spring
				and joint_definition.native_passive_fraction > 0.0
				and joint_definition.axis_is_free(axis)
				and joint_definition.passive_stiffness[axis] > 0.0
			)
			if _native_spring_enabled(joint, axis) != expected_enabled:
				return false
			if not expected_enabled:
				continue
			var expected_stiffness := (
				joint_definition.passive_stiffness[axis]
				* joint_definition.native_passive_fraction
			)
			var expected_damping := (
				joint_definition.passive_damping[axis]
				* joint_definition.native_passive_fraction
			)
			if (
				absf(_native_spring_stiffness(joint, axis) - expected_stiffness) > 0.001
				or absf(_native_spring_damping(joint, axis) - expected_damping) > 0.001
			):
				return false
	return true


static func _native_spring_enabled(joint: Generic6DOFJoint3D, axis: int) -> bool:
	match axis:
		Vector3.AXIS_X:
			return joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
		Vector3.AXIS_Y:
			return joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
		Vector3.AXIS_Z:
			return joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
	return false


static func _native_spring_stiffness(joint: Generic6DOFJoint3D, axis: int) -> float:
	match axis:
		Vector3.AXIS_X:
			return joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)
		Vector3.AXIS_Y:
			return joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)
		Vector3.AXIS_Z:
			return joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)
	return 0.0


static func _native_spring_damping(joint: Generic6DOFJoint3D, axis: int) -> float:
	match axis:
		Vector3.AXIS_X:
			return joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
		Vector3.AXIS_Y:
			return joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
		Vector3.AXIS_Z:
			return joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
	return 0.0


static func basis_from_y(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	if y_axis.length_squared() <= 0.000001:
		y_axis = Vector3.DOWN
	var helper := Vector3.FORWARD
	if absf(y_axis.dot(helper)) > 0.92:
		helper = Vector3.RIGHT
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


static func joint_basis_from_twist_and_swing(
	twist_axis: Vector3,
	swing_axis: Vector3
) -> Basis:
	# Jolt's SixDOF convention is X = twist and Y/Z = swing. The supplied Z axis should be the
	# normal of the limb's authored bending plane, so gravity/contact loads are resisted by a free
	# swing axis rather than being projected onto a locked axis. This is crucial for spider legs.
	var x_axis := twist_axis.normalized()
	if x_axis.length_squared() <= 0.000001:
		x_axis = Vector3.RIGHT
	var z_axis := swing_axis - x_axis * swing_axis.dot(x_axis)
	if z_axis.length_squared() <= 0.000001:
		var fallback_basis := basis_from_y(x_axis)
		z_axis = fallback_basis.x
	z_axis = z_axis.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


static func joint_basis_with_x_twist(segment_basis: Basis) -> Basis:
	# Backward-compatible helper for editor/tool callers that only know a segment orientation.
	# Creature definitions should prefer joint_basis_from_twist_and_swing() and provide the actual
	# authored bending-plane normal.
	var clean := segment_basis.orthonormalized()
	return joint_basis_from_twist_and_swing(clean.y, clean.x)
