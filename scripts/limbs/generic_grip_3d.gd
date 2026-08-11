class_name GenericGrip3D
extends Node3D

#######################################################
# Host-agnostic physical point grip. It can be mounted on any RigidBody3D through a limb end
# effector or a future drone/tool attachment. The grip acquires a nearby compatible surface and
# applies bounded equal/opposite spring-damper forces. It never teleports either body and never
# relies on Jolt's unsupported PinJoint impulse clamp.
#######################################################

const MAXIMUM_QUERY_RETRIES = 8

var owner_body: RigidBody3D
var definition: LimbEndEffectorDefinition
var excluded_rids: Array[RID] = []
var requested_activation := 0.0
var activation := 0.0
var attached := false
var attached_node: Node3D
var attached_body: RigidBody3D
var attached_rid := RID()
var attached_anchor_local := Vector3.ZERO
# Material point on the owning rigid body that contacted/reached toward the target when the grip
# latched. Physical end effectors therefore spring surface-to-surface instead of pulling their
# center into the contacted collider.
var attached_owner_anchor_local: Vector3 = Vector3.ZERO
var attached_normal_local := Vector3.UP
var attached_surface_tags := PackedStringArray()
var attached_target_id := 0
var attached_target_mass := 0.0
var attachment_age := 0.0
var attachment_sequence := 0
var pickup_sequence := 0
var breakaway_count := 0
var requires_rearm := false
var breakaway_target_id := 0
var normal_load := 0.0
var shear_load := 0.0
var load_ratio := 0.0
var overload_elapsed: float = 0.0
var consumed_energy := 0.0
var candidate_present := false
var candidate_point_world := Vector3.ZERO
var candidate_owner_point_world: Vector3 = Vector3.ZERO
var candidate_normal_world := Vector3.UP
var candidate_distance := 0.0
var candidate_target_id := 0
var candidate_target_mass := 0.0
var candidate_dynamic := false
var candidate_surface_tags := PackedStringArray()
var _query_shape := SphereShape3D.new()
var _query_parameters: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _query_exclusions: Array[RID] = []
var _incompatible_static_rids: Array[RID] = []
var _candidate_refresh_remaining := 0.0


func _exit_tree() -> void:
	release()


func configure(
	new_owner_body: RigidBody3D,
	new_definition: LimbEndEffectorDefinition,
	new_excluded_rids: Array[RID] = []
) -> void:
	owner_body = new_owner_body
	definition = new_definition
	set_excluded_rids(new_excluded_rids)
	if definition != null:
		definition.sanitize()
		_query_shape.radius = definition.grip_detection_radius
	reset_state()


func set_excluded_rids(values: Array[RID]) -> void:
	excluded_rids.clear()
	for rid: RID in values:
		if rid.is_valid() and not excluded_rids.has(rid):
			excluded_rids.append(rid)
	if is_instance_valid(owner_body) and owner_body.get_rid().is_valid():
		var owner_rid := owner_body.get_rid()
		if not excluded_rids.has(owner_rid):
			excluded_rids.append(owner_rid)
	_incompatible_static_rids.clear()
	_rebuild_query_exclusions()


func invalidate_candidate_query_cache() -> void:
	# Static surfaces can be retagged by gameplay systems. Callers that do so can invalidate the
	# rejected-surface cache without rebuilding the grip or changing its attachment state.
	_incompatible_static_rids.clear()
	_rebuild_query_exclusions()
	_candidate_refresh_remaining = 0.0


func step(delta: float, command: float, operational: bool = true) -> void:
	var safe_delta := maxf(delta, 0.0)
	if definition == null or not definition.enabled or not operational:
		requested_activation = 0.0
		activation = 0.0
		release()
		_clear_candidate()
		return
	match definition.grip_mode:
		LimbEndEffectorDefinition.GripMode.PASSIVE:
			requested_activation = 1.0
		LimbEndEffectorDefinition.GripMode.CONTROLLED:
			# Use the complete normalized policy channel. Mapping [-1, +1] -> [0, 1]
			# removes the old flat negative half-space where many different PPO actions all meant
			# exactly "released". Zero remains a neutral hold request below the engage threshold.
			requested_activation = clampf((command + 1.0) * 0.5, 0.0, 1.0)
		_:
			requested_activation = 0.0
	activation = move_toward(
		activation,
		requested_activation,
		definition.activation_response_per_second * safe_delta
	)
	if requested_activation < definition.grip_release_threshold:
		requires_rearm = false
		breakaway_target_id = 0
	consumed_energy += definition.energy_cost_per_second * activation * safe_delta

	if attached:
		if activation < definition.grip_release_threshold or not _attachment_is_valid():
			release()
		else:
			_apply_attachment_force(safe_delta)
	else:
		_candidate_refresh_remaining = maxf(_candidate_refresh_remaining - safe_delta, 0.0)
		if _candidate_refresh_remaining <= 0.0:
			_update_candidate()
			_candidate_refresh_remaining = definition.candidate_refresh_seconds
		if (
			definition.grip_mode == LimbEndEffectorDefinition.GripMode.PASSIVE
			and requires_rearm
			and (not candidate_present or candidate_target_id != breakaway_target_id)
		):
			requires_rearm = false
			breakaway_target_id = 0
		if (
			not requires_rearm
			and candidate_present
			and candidate_distance <= definition.grip_acquisition_radius
			and activation >= definition.grip_activation_threshold
			and requested_activation >= definition.grip_activation_threshold
		):
			attach_candidate()


func attach_candidate() -> bool:
	if not candidate_present or definition == null or not is_instance_valid(owner_body):
		return false
	if candidate_distance > definition.grip_acquisition_radius:
		return false
	var node := instance_from_id(candidate_target_id) as Node3D
	if not is_instance_valid(node):
		return false
	attached_node = node
	attached_body = node as RigidBody3D
	_set_dynamic_collision_exception(attached_body, true)
	attached_rid = _collision_rid(node)
	attached_target_id = candidate_target_id
	attached_target_mass = candidate_target_mass
	attached_surface_tags = candidate_surface_tags.duplicate()
	attached_anchor_local = node.global_transform.affine_inverse() * candidate_point_world
	attached_owner_anchor_local = (
		owner_body.global_transform.affine_inverse() * candidate_owner_point_world
	)
	attached_normal_local = _world_normal_to_local(node, candidate_normal_world)
	if attached_normal_local.length_squared() <= 0.000001:
		attached_normal_local = Vector3.UP
	attached = true
	attachment_age = 0.0
	attachment_sequence += 1
	if attached_body != null and attached_surface_tags.has("carryable"):
		pickup_sequence += 1
	normal_load = 0.0
	shear_load = 0.0
	load_ratio = 0.0
	overload_elapsed = 0.0
	_clear_candidate()
	return true


func release() -> void:
	_set_dynamic_collision_exception(attached_body, false)
	attached = false
	attached_node = null
	attached_body = null
	attached_rid = RID()
	attached_anchor_local = Vector3.ZERO
	attached_owner_anchor_local = Vector3.ZERO
	attached_normal_local = Vector3.UP
	attached_surface_tags = PackedStringArray()
	attached_target_id = 0
	attached_target_mass = 0.0
	attachment_age = 0.0
	normal_load = 0.0
	shear_load = 0.0
	load_ratio = 0.0
	overload_elapsed = 0.0


func reset_state() -> void:
	requested_activation = (
		1.0
		if definition != null
		and definition.grip_mode == LimbEndEffectorDefinition.GripMode.PASSIVE
		else 0.0
	)
	activation = requested_activation
	release()
	_clear_candidate()
	consumed_energy = 0.0
	attachment_sequence = 0
	pickup_sequence = 0
	breakaway_count = 0
	requires_rearm = false
	breakaway_target_id = 0
	_incompatible_static_rids.clear()
	_rebuild_query_exclusions()
	_candidate_refresh_remaining = 0.0


func state_snapshot() -> Dictionary:
	return {
		"requested_activation": requested_activation,
		"activation": activation,
		"candidate_present": candidate_present,
		"candidate_point_world": candidate_point_world,
		"candidate_owner_point_world": candidate_owner_point_world,
		"candidate_normal_world": candidate_normal_world,
		"candidate_distance": candidate_distance,
		"candidate_target_id": candidate_target_id,
		"candidate_target_mass": candidate_target_mass,
		"candidate_dynamic": candidate_dynamic,
		"candidate_surface_tags": candidate_surface_tags,
		"attached": attached,
		"attached_target_id": attached_target_id,
		"attached_target_mass": attached_target_mass,
		"attached_dynamic": attached_body != null,
		"attached_point_world": attached_point_world(),
		"attached_owner_point_world": attached_owner_point_world(),
		"attached_normal_world": attached_normal_world(),
		"attached_surface_tags": attached_surface_tags,
		"attachment_age": attachment_age,
		"attachment_sequence": attachment_sequence,
		"pickup_sequence": pickup_sequence,
		"breakaway_count": breakaway_count,
		"requires_rearm": requires_rearm,
		"normal_load": normal_load,
		"shear_load": shear_load,
		"load_ratio": load_ratio,
		"overload_elapsed": overload_elapsed,
		"consumed_energy": consumed_energy,
	}


func attached_point_world() -> Vector3:
	if not attached or not is_instance_valid(attached_node):
		return global_position if is_inside_tree() else Vector3.ZERO
	return attached_node.global_transform * attached_anchor_local


func attached_owner_point_world() -> Vector3:
	if not attached or not is_instance_valid(owner_body):
		return global_position if is_inside_tree() else Vector3.ZERO
	return owner_body.global_transform * attached_owner_anchor_local


func attached_normal_world() -> Vector3:
	if not attached or not is_instance_valid(attached_node):
		return Vector3.UP
	return _local_normal_to_world(attached_node, attached_normal_local)


func _update_candidate() -> void:
	_clear_candidate()
	if (
		definition == null
		or not definition.enabled
		or definition.grip_mode == LimbEndEffectorDefinition.GripMode.NONE
		or not is_inside_tree()
	):
		return
	var world: World3D = get_world_3d()
	if world == null:
		return
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	_query_shape.radius = definition.grip_detection_radius
	_query_parameters.shape = _query_shape
	_query_parameters.transform = Transform3D(Basis.IDENTITY, global_position)
	_query_parameters.collision_mask = definition.grip_collision_mask
	_query_parameters.collide_with_bodies = true
	_query_parameters.collide_with_areas = false
	var working_exclusions: Array[RID] = _query_exclusions
	var uses_persistent_exclusions: bool = true
	for _attempt_index in range(MAXIMUM_QUERY_RETRIES):
		_query_parameters.exclude = working_exclusions
		var info: Dictionary = space_state.get_rest_info(_query_parameters)
		if info.is_empty():
			return
		var rid: RID = info.get("rid", RID())
		var target_id := int(info.get("collider_id", 0))
		var node := instance_from_id(target_id) as Node3D
		var surface_tags: PackedStringArray = (
			surface_tags_for(node) if is_instance_valid(node) else PackedStringArray()
		)
		if not is_instance_valid(node) or not _candidate_is_compatible(node, rid, surface_tags):
			if rid.is_valid() and not working_exclusions.has(rid):
				if node is StaticBody3D:
					_cache_incompatible_static_rid(rid)
					if uses_persistent_exclusions:
						working_exclusions = _query_exclusions
					elif not working_exclusions.has(rid):
						working_exclusions.append(rid)
				else:
					if uses_persistent_exclusions:
						working_exclusions = _query_exclusions.duplicate()
						uses_persistent_exclusions = false
					working_exclusions.append(rid)
				continue
			return
		var point: Vector3 = info.get("point", global_position)
		var normal: Vector3 = info.get("normal", Vector3.UP)
		if not point.is_finite() or not normal.is_finite():
			return
		if normal.length_squared() <= 0.000001:
			normal = global_position - point
		if normal.length_squared() <= 0.000001:
			normal = Vector3.UP
		candidate_present = true
		candidate_point_world = point
		candidate_owner_point_world = _owner_anchor_world_toward(point)
		candidate_normal_world = normal.normalized()
		candidate_distance = candidate_owner_point_world.distance_to(point)
		candidate_target_id = target_id
		var candidate_body := node as RigidBody3D
		candidate_dynamic = candidate_body != null
		candidate_target_mass = candidate_body.mass if candidate_body != null else 0.0
		candidate_surface_tags = surface_tags
		return


func _cache_incompatible_static_rid(rid: RID) -> void:
	if not rid.is_valid() or _incompatible_static_rids.has(rid):
		return
	_incompatible_static_rids.append(rid)
	if not _query_exclusions.has(rid):
		_query_exclusions.append(rid)


func _rebuild_query_exclusions() -> void:
	_query_exclusions.clear()
	for rid: RID in excluded_rids:
		if rid.is_valid() and not _query_exclusions.has(rid):
			_query_exclusions.append(rid)
	for rid: RID in _incompatible_static_rids:
		if rid.is_valid() and not _query_exclusions.has(rid):
			_query_exclusions.append(rid)


func _candidate_is_compatible(
	node: Node3D,
	rid: RID,
	surface_tags: PackedStringArray
) -> bool:
	if rid.is_valid() and excluded_rids.has(rid):
		return false
	if surface_grip_is_disabled(node):
		return false
	var allowed_owner_id := surface_allowed_owner_id(node)
	if allowed_owner_id > 0 and allowed_owner_id != _owner_model_instance_id():
		return false
	var rigid := node as RigidBody3D
	if rigid != null:
		if not definition.allow_dynamic_grip:
			return false
		if rigid.mass > definition.maximum_held_mass:
			return false
	elif not definition.allow_static_grip:
		return false
	return surface_tags_are_compatible(
		definition,
		surface_tags,
		rigid != null
	)


static func surface_tags_are_compatible(
	grip_definition: LimbEndEffectorDefinition,
	surface_tags: PackedStringArray,
	_is_dynamic_surface: bool
) -> bool:
	if grip_definition == null:
		return false
	if grip_definition.compatible_surface_tags.is_empty():
		return true
	for tag: String in grip_definition.compatible_surface_tags:
		if surface_tags.has(tag):
			return true

	# Surface compatibility is authored data. In particular, do not make the stock four-limb
	# generic grip silently treat the training floor as an anchor: ordinary locomotion already has
	# physical foot friction, while an active static grip is a much stronger spring-damper world
	# constraint. A creature/tool that deliberately needs ground bracing can opt in by including
	# "ground" in compatible_surface_tags. Climbable walls and carryable objects remain unchanged.
	return false


func _attachment_is_valid() -> bool:
	if not is_instance_valid(owner_body) or not is_instance_valid(attached_node):
		return false
	if attached_body != null and attached_body.mass > definition.maximum_held_mass:
		return false
	return true


func _apply_attachment_force(delta: float) -> void:
	if not _attachment_is_valid():
		release()
		return
	var anchor_world: Vector3 = attached_node.global_transform * attached_anchor_local
	var owner_anchor_world: Vector3 = attached_owner_point_world()
	var normal_world: Vector3 = _local_normal_to_world(attached_node, attached_normal_local)
	var owner_point_velocity: Vector3 = _body_point_velocity(owner_body, owner_anchor_world)
	var target_point_velocity: Vector3 = (
		_body_point_velocity(attached_body, anchor_world)
		if attached_body != null
		else Vector3.ZERO
	)
	var position_error: Vector3 = anchor_world - owner_anchor_world
	var relative_velocity: Vector3 = target_point_velocity - owner_point_velocity
	# Attachment authority must ramp coherently with activation. Previously a grip acquired at the
	# engage threshold received full spring/damper demand while its holding limits were still scaled
	# down by activation. Near the edge of the acquisition radius that could make a brand-new valid
	# latch immediately exceed breakaway and enter rearm. Scale both demand and capacity together.
	var required_force: Vector3 = activated_spring_damper_force(
		position_error,
		relative_velocity,
		definition.grip_stiffness,
		definition.grip_damping,
		activation
	)
	if not required_force.is_finite():
		release()
		return
	var required_normal_vector := normal_world * required_force.dot(normal_world)
	var required_shear_vector := required_force - required_normal_vector
	var normal_limit := definition.maximum_normal_holding_force * activation
	var shear_limit := definition.maximum_shear_holding_force * activation
	var required_normal := required_normal_vector.length()
	var required_shear := required_shear_vector.length()
	var normal_ratio := (
		required_normal / maxf(normal_limit, 0.0001)
		if normal_limit > 0.0
		else INF
	)
	var shear_ratio := (
		required_shear / maxf(shear_limit, 0.0001)
		if shear_limit > 0.0
		else INF
	)
	load_ratio = maxf(normal_ratio, shear_ratio)
	attachment_age += maxf(delta, 0.0)
	if load_ratio > definition.breakaway_load_ratio:
		overload_elapsed += maxf(delta, 0.0)
	else:
		overload_elapsed = 0.0
	if (
		load_ratio > definition.breakaway_load_ratio
		and overload_elapsed >= definition.breakaway_confirmation_seconds
	):
		breakaway_count += 1
		requires_rearm = true
		breakaway_target_id = attached_target_id
		release()
		return
	var force := (
		_limit_vector(required_normal_vector, normal_limit)
		+ _limit_vector(required_shear_vector, shear_limit)
	)
	normal_load = minf(required_normal, normal_limit)
	shear_load = minf(required_shear, shear_limit)
	if force.length_squared() <= 0.0000001:
		return
	owner_body.apply_force(force, owner_anchor_world - owner_body.global_position)
	if attached_body != null and not attached_body.freeze:
		attached_body.apply_force(-force, anchor_world - attached_body.global_position)


func _clear_candidate() -> void:
	candidate_present = false
	candidate_point_world = global_position if is_inside_tree() else Vector3.ZERO
	candidate_owner_point_world = candidate_point_world
	candidate_normal_world = Vector3.UP
	candidate_distance = (
		definition.grip_detection_radius if definition != null else 0.0
	)
	candidate_target_id = 0
	candidate_target_mass = 0.0
	candidate_dynamic = false
	candidate_surface_tags = PackedStringArray()


func _owner_anchor_world_toward(target_point_world: Vector3) -> Vector3:
	var effector: LimbEndEffector3D = get_parent() as LimbEndEffector3D
	if is_instance_valid(effector) and not effector.disabled:
		var direction_world: Vector3 = target_point_world - effector.global_position
		if direction_world.length_squared() > 0.000001:
			return effector.world_contact_point(direction_world)
	return global_position


static func _world_normal_to_local(node: Node3D, normal_world: Vector3) -> Vector3:
	if not is_instance_valid(node) or normal_world.length_squared() <= 0.000001:
		return Vector3.UP
	var result := node.global_basis.transposed() * normal_world
	return result.normalized() if result.length_squared() > 0.000001 else Vector3.UP


static func _local_normal_to_world(node: Node3D, normal_local: Vector3) -> Vector3:
	if not is_instance_valid(node) or normal_local.length_squared() <= 0.000001:
		return Vector3.UP
	var result := node.global_basis.inverse().transposed() * normal_local
	return result.normalized() if result.length_squared() > 0.000001 else Vector3.UP


static func _body_point_velocity(body: RigidBody3D, point_world: Vector3) -> Vector3:
	if not is_instance_valid(body):
		return Vector3.ZERO
	return body.linear_velocity + body.angular_velocity.cross(point_world - body.global_position)


static func spring_damper_force(
	position_error: Vector3,
	relative_velocity: Vector3,
	stiffness: float,
	damping: float
) -> Vector3:
	# Same physical spring/damper principle as the authoritative player grabber. The worker grip
	# applies this force to its owning rigid body and the exact opposite force to a movable target.
	return position_error * stiffness + relative_velocity * damping


static func activated_spring_damper_force(
	position_error: Vector3,
	relative_velocity: Vector3,
	stiffness: float,
	damping: float,
	activation_value: float
) -> Vector3:
	var authority: float = clampf(activation_value, 0.0, 1.0)
	return spring_damper_force(
		position_error,
		relative_velocity,
		maxf(stiffness, 0.0) * authority,
		maxf(damping, 0.0) * authority
	)


static func _limit_vector(value: Vector3, maximum_length: float) -> Vector3:
	if maximum_length <= 0.0 or value.length_squared() <= 0.0000001:
		return Vector3.ZERO
	return value.limit_length(maximum_length)


static func _collision_rid(node: Node3D) -> RID:
	var collision := node as CollisionObject3D
	return collision.get_rid() if collision != null else RID()


func _set_dynamic_collision_exception(target: RigidBody3D, enabled: bool) -> void:
	if not is_instance_valid(owner_body) or not is_instance_valid(target) or owner_body == target:
		return
	if enabled:
		owner_body.add_collision_exception_with(target)
		target.add_collision_exception_with(owner_body)
	else:
		owner_body.remove_collision_exception_with(target)
		target.remove_collision_exception_with(owner_body)


func _owner_model_instance_id() -> int:
	if not is_instance_valid(owner_body):
		return 0
	if owner_body is LimbSegment3D:
		var model_owner := (owner_body as LimbSegment3D).owner_body
		if is_instance_valid(model_owner):
			return model_owner.get_instance_id()
	return owner_body.get_instance_id()


static func surface_allowed_owner_id(node: Node) -> int:
	var current := node
	var depth := 0
	while is_instance_valid(current) and depth < 6:
		var value: Variant = current.get_meta("grip_allowed_owner_id", 0)
		if typeof(value) == TYPE_INT and int(value) > 0:
			return int(value)
		current = current.get_parent()
		depth += 1
	return 0


static func surface_grip_is_disabled(node: Node) -> bool:
	var current := node
	var depth := 0
	while is_instance_valid(current) and depth < 6:
		if bool(current.get_meta("grip_surface_disabled", false)):
			return true
		current = current.get_parent()
		depth += 1
	return false


static func surface_tags_have(value: Variant, expected: String) -> bool:
	if value is PackedStringArray:
		return (value as PackedStringArray).has(expected)
	if value is Array:
		for entry: Variant in value:
			if str(entry) == expected:
				return true
	return false


static func surface_tags_for(node: Node) -> PackedStringArray:
	var result := PackedStringArray()
	var current := node
	var depth := 0
	while is_instance_valid(current) and depth < 6:
		_append_tags(result, current.get_meta("grip_surface_tags", []))
		if bool(current.get_meta("training_wall", false)):
			_append_unique(result, "climbable")
		if bool(current.get_meta("training_ground", false)):
			_append_unique(result, "ground")
		if bool(current.get_meta("training_grabbable_item", false)):
			_append_unique(result, "carryable")
		current = current.get_parent()
		depth += 1
	return result


static func _append_tags(result: PackedStringArray, value: Variant) -> void:
	if value is PackedStringArray:
		for tag: String in value:
			_append_unique(result, tag)
	elif value is Array:
		for entry: Variant in value:
			_append_unique(result, str(entry))
	elif value is String or value is StringName:
		_append_unique(result, str(value))


static func _append_unique(result: PackedStringArray, value: String) -> void:
	var tag := value.strip_edges()
	if not tag.is_empty() and not result.has(tag):
		result.append(tag)
