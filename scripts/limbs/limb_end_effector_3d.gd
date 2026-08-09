class_name LimbEndEffector3D
extends CollisionShape3D

#######################################################
# Runtime terminal hardware attached directly to the distal RigidBody3D. Geometry is optional;
# the embedded GenericGrip3D remains usable at the authored tip even when no extra collision shape
# is enabled, preserving existing feet while adding a real controllable grip actuator.
#######################################################

var definition: LimbEndEffectorDefinition
var parent_segment: LimbSegment3D
var grip_actuator: GenericGrip3D
var current_health := 0.0
var static_snapshot: Dictionary = {}


func configure(
	segment: LimbSegment3D,
	new_definition: LimbEndEffectorDefinition,
	distal_tip_local: Vector3,
	visual_color: Color
) -> void:
	parent_segment = segment
	definition = new_definition
	if definition == null:
		disabled = true
		static_snapshot = empty_snapshot()
		return
	definition.sanitize()
	name = definition.effector_name.validate_node_name()
	position = distal_tip_local + definition.local_offset
	basis = definition.local_basis()
	current_health = definition.maximum_health
	static_snapshot = _build_static_snapshot()
	shape = _create_shape(definition)
	disabled = not definition.is_physically_present() or shape == null
	if not disabled:
		_create_visual(visual_color)
	grip_actuator = GenericGrip3D.new()
	grip_actuator.name = "GripActuator"
	add_child(grip_actuator)
	grip_actuator.configure(parent_segment, definition)


func set_grip_excluded_rids(values: Array[RID]) -> void:
	if is_instance_valid(grip_actuator):
		grip_actuator.set_excluded_rids(values)


func step_command(delta: float, commands: PackedFloat64Array) -> void:
	if not is_instance_valid(grip_actuator):
		return
	var command := 0.0
	if (
		definition != null
		and definition.grip_action_index >= 0
		and definition.grip_action_index < commands.size()
	):
		command = commands[definition.grip_action_index]
	var operational := current_health > 0.0
	if not operational:
		command = 0.0
	grip_actuator.step(delta, command, operational)


func reset_state() -> void:
	current_health = definition.maximum_health if definition != null else 0.0
	if is_instance_valid(grip_actuator):
		grip_actuator.reset_state()


func release_grip() -> void:
	if is_instance_valid(grip_actuator):
		grip_actuator.release()


func holds_instance_id(instance_id: int) -> bool:
	return (
		instance_id > 0
		and is_instance_valid(grip_actuator)
		and grip_actuator.attached
		and grip_actuator.attached_target_id == instance_id
	)


func world_contact_point(direction_world: Vector3 = Vector3.DOWN) -> Vector3:
	if disabled or definition == null or shape == null:
		return global_position
	var direction := direction_world.normalized()
	if direction.length_squared() <= 0.000001:
		direction = global_basis.y.normalized()
	var direction_local := (global_basis.inverse() * direction).normalized()
	return global_transform * _support_point_local(direction_local)


func _support_point_local(direction_local: Vector3) -> Vector3:
	match definition.geometry_type:
		LimbEndEffectorDefinition.GeometryType.SPHERE:
			return direction_local * definition.sphere_radius
		LimbEndEffectorDefinition.GeometryType.BOX:
			var half_size := definition.box_size * 0.5
			return Vector3(
				signf(direction_local.x) * half_size.x,
				signf(direction_local.y) * half_size.y,
				signf(direction_local.z) * half_size.z
			)
		LimbEndEffectorDefinition.GeometryType.CAPSULE:
			var cylinder_half_length := maxf(
				definition.capsule_height * 0.5 - definition.capsule_radius,
				0.0
			)
			return (
				Vector3.UP * signf(direction_local.y) * cylinder_half_length
				+ direction_local * definition.capsule_radius
			)
	return Vector3.ZERO


func health_ratio() -> float:
	if definition == null:
		return 0.0
	return clampf(current_health / maxf(definition.maximum_health, 0.1), 0.0, 1.0)


func apply_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		release_grip()


func state_snapshot() -> Dictionary:
	var result: Dictionary = static_snapshot.duplicate(false)
	if result.is_empty():
		result = empty_snapshot()
	result["physical_shape_present"] = not disabled and shape != null
	result["health_ratio"] = health_ratio()
	result["position_world"] = global_position
	if is_instance_valid(grip_actuator):
		result.merge(grip_actuator.state_snapshot(), true)
	return result


func _build_static_snapshot() -> Dictionary:
	var result: Dictionary = empty_snapshot()
	if definition == null:
		return result
	result.merge({
		"present": definition.enabled,
		"physical_shape_present": false,
		"effector_type_id": str(definition.effector_type_id),
		"geometry_type": definition.geometry_type,
		"added_mass": definition.added_mass,
		"friction": definition.friction,
		"bounce": definition.bounce,
		"rough": definition.rough,
		"absorbent": definition.absorbent,
		"normal_stiffness": definition.normal_stiffness,
		"normal_damping": definition.normal_damping,
		"maximum_compression": definition.maximum_compression,
		"grip_mode": definition.grip_mode,
		"grip_action_index": definition.grip_action_index,
		"grip_activation_threshold": definition.grip_activation_threshold,
		"activation_response_per_second": definition.activation_response_per_second,
		"grip_acquisition_radius": definition.grip_acquisition_radius,
		"grip_detection_radius": definition.grip_detection_radius,
		"candidate_refresh_seconds": definition.candidate_refresh_seconds,
		"maximum_held_mass": definition.maximum_held_mass,
		"maximum_normal_holding_force": definition.maximum_normal_holding_force,
		"maximum_shear_holding_force": definition.maximum_shear_holding_force,
		"breakaway_load_ratio": definition.breakaway_load_ratio,
		"breakaway_confirmation_seconds": definition.breakaway_confirmation_seconds,
		"energy_cost_per_second": definition.energy_cost_per_second,
		"compatible_surface_tags": definition.compatible_surface_tags.duplicate(),
	}, true)
	return result


static func empty_snapshot() -> Dictionary:
	return {
		"present": false,
		"physical_shape_present": false,
		"position_world": Vector3.ZERO,
		"effector_type_id": "",
		"geometry_type": LimbEndEffectorDefinition.GeometryType.NONE,
		"added_mass": 0.0,
		"friction": 0.0,
		"bounce": 0.0,
		"rough": false,
		"absorbent": false,
		"normal_stiffness": 0.0,
		"normal_damping": 0.0,
		"maximum_compression": 0.0,
		"grip_mode": LimbEndEffectorDefinition.GripMode.NONE,
		"grip_action_index": -1,
		"grip_activation_threshold": 0.0,
		"activation_response_per_second": 0.0,
		"grip_acquisition_radius": 0.0,
		"grip_detection_radius": 0.0,
		"candidate_refresh_seconds": 0.0,
		"maximum_held_mass": 0.0,
		"maximum_normal_holding_force": 0.0,
		"maximum_shear_holding_force": 0.0,
		"breakaway_load_ratio": 0.0,
		"breakaway_confirmation_seconds": 0.0,
		"energy_cost_per_second": 0.0,
		"requested_activation": 0.0,
		"activation": 0.0,
		"candidate_present": false,
		"candidate_point_world": Vector3.ZERO,
		"candidate_owner_point_world": Vector3.ZERO,
		"candidate_normal_world": Vector3.UP,
		"candidate_distance": 0.0,
		"candidate_target_id": 0,
		"candidate_target_mass": 0.0,
		"candidate_dynamic": false,
		"candidate_surface_tags": PackedStringArray(),
		"attached": false,
		"attached_target_id": 0,
		"attached_target_mass": 0.0,
		"attached_dynamic": false,
		"attached_point_world": Vector3.ZERO,
		"attached_owner_point_world": Vector3.ZERO,
		"attached_normal_world": Vector3.UP,
		"attached_surface_tags": PackedStringArray(),
		"attachment_age": 0.0,
		"attachment_sequence": 0,
		"pickup_sequence": 0,
		"breakaway_count": 0,
		"requires_rearm": false,
		"normal_load": 0.0,
		"shear_load": 0.0,
		"load_ratio": 0.0,
		"overload_elapsed": 0.0,
		"health_ratio": 0.0,
		"consumed_energy": 0.0,
		"compatible_surface_tags": PackedStringArray(),
	}


static func _create_shape(source: LimbEndEffectorDefinition) -> Shape3D:
	match source.geometry_type:
		LimbEndEffectorDefinition.GeometryType.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = source.sphere_radius
			return sphere
		LimbEndEffectorDefinition.GeometryType.BOX:
			var box := BoxShape3D.new()
			box.size = source.box_size
			return box
		LimbEndEffectorDefinition.GeometryType.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = source.capsule_radius
			capsule.height = source.capsule_height
			return capsule
	return null


func _create_visual(visual_color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	match definition.geometry_type:
		LimbEndEffectorDefinition.GeometryType.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = definition.sphere_radius
			sphere.height = definition.sphere_radius * 2.0
			visual.mesh = sphere
		LimbEndEffectorDefinition.GeometryType.BOX:
			var box := BoxMesh.new()
			box.size = definition.box_size
			visual.mesh = box
		LimbEndEffectorDefinition.GeometryType.CAPSULE:
			var capsule := CapsuleMesh.new()
			capsule.radius = definition.capsule_radius
			capsule.height = definition.capsule_height
			visual.mesh = capsule
	if visual.mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = visual_color.lightened(0.16)
	material.roughness = 0.78
	visual.material_override = material
	add_child(visual)
